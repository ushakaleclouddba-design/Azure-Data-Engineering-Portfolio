<#
.SYNOPSIS
    SQLPilot - DC->DC migration ORCHESTRATOR.

.DESCRIPTION
    Thin orchestrator for server-to-server (on-prem) migration. Resolves the
    engine, tests reachability, and calls one module per concern IN ORDER,
    assembling a single combined result. Each module is mode-aware internally
    (dbatools vs native) and independently testable; this file just sequences
    them. (Modular refactor decided 2026-05-26 - see Bible Appendix A.)

    STEP ORDER (mandatory: TDE before databases):
        verify -> TDE certs -> databases -> logins -> jobs -> linked servers
        -> configs -> SSIS -> validate

    Modules dot-sourced by server.ps1 / run_migrate_dcdc.ps1 BEFORE this file:
        migrate_tde.ps1          Invoke-MigrateTdeCertificates
        migrate_databases.ps1    Invoke-MigrateDatabases
        migrate_logins.ps1       Invoke-RealMigrateLogins        (Cloud-style; see note)
        migrate_jobs.ps1         Invoke-MigrateAgentJobs
        migrate_linkedservers.ps1 Invoke-MigrateLinkedServers
        migrate_configs.ps1      Invoke-MigrateServerConfigs
        migrate_ssis.ps1         Invoke-MigrateSsis
        migrate_validate.ps1     Invoke-MigrateValidate

    ENGINE RESOLUTION (no silent fallback):
      - Engine='dbatools' and dbatools unavailable -> ERROR (tell the user to
        install it or choose native). We do NOT silently downgrade.
      - Engine='native' -> never import/require dbatools.

    DESTINATION DOWN -> script-out path (dbatools Export-DbaInstance), unchanged
    from the original tool. Native script-out is not supported (no dbatools to
    script with); native requires a reachable destination.

    PRESERVES the proven dbatools whole-server path (Start-DbaMigration) and the
    proven dbatools database-list path (Copy-DbaDatabase) by delegating to
    migrate_databases.ps1 (which wraps Copy-DbaDatabase) and, for whole-server
    dbatools, still using Start-DbaMigration directly.

.NOTES
    Author : Kale. server.ps1's /api/migrate/dcdc calls Invoke-RealMigrateDcToDc.
#>

$script:DbatoolsChecked = $false
$script:DbatoolsOk      = $false

function Initialize-Dbatools {
    if ($script:DbatoolsChecked) { return $script:DbatoolsOk }
    $script:DbatoolsChecked = $true
    $mod = Get-Module -ListAvailable -Name dbatools | Select-Object -First 1
    if ($mod) {
        try { Import-Module dbatools -ErrorAction Stop; $script:DbatoolsOk = $true
              Write-Host "[dcdc] dbatools $($mod.Version) loaded." -ForegroundColor DarkGray
              return $true } catch {}
    }
    $script:DbatoolsOk = $false
    return $false
}

function Test-DestinationReachable {
    param([Parameter(Mandatory)] [string] $Destination)
    if ($script:DbatoolsOk) {
        try { if (Connect-DbaInstance -SqlInstance $Destination -ConnectTimeout 8 -ErrorAction Stop) { return $true } } catch { return $false }
        return $false
    }
    try { Invoke-Sqlcmd -ServerInstance $Destination -Query 'SELECT 1 AS ok' -ConnectionTimeout 8 -TrustServerCertificate -Encrypt Optional -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

# small helper: call a step module if its function exists, capture its result,
# and fold status into the overall run. Missing module => recorded, not fatal.
function Invoke-DcDcStep {
    param(
        [Parameter(Mandatory)] $Result,           # the combined result (ref by object)
        [Parameter(Mandatory)] [string] $StepName,
        [Parameter(Mandatory)] [string] $FunctionName,
        [Parameter(Mandatory)] [hashtable] $Params
    )
    $cmd = Get-Command -Name $FunctionName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $Result.steps += @{ step=$StepName; status='unavailable'; note="module function $FunctionName not loaded" }
        return
    }
    Write-Host "[dcdc] step: $StepName ($FunctionName)" -ForegroundColor Cyan
    try {
        $r = & $FunctionName @Params
        $st = if ($r -and $r.status) { "$($r.status)" } else { 'ok' }
        $Result.steps += @{ step=$StepName; status=$st; detail=$r }
        if ($st -eq 'error') { $Result.status = 'partial' }   # one step failing => partial overall
    } catch {
        $Result.steps += @{ step=$StepName; status='error'; error="$($_.Exception.Message)" }
        $Result.status = 'partial'
    }
}

# ---------------------------------------------------------------------------
# Invoke-RealMigrateDcToDc - the orchestrator.
#   -Source -Destination
#   -Scope        'whole' | 'db'
#   -Databases    string[]; required when Scope='db'
#   -Engine       'dbatools' | 'native'   (explicit; no silent fallback)
#   -SharedPath   UNC share both servers can read/write (default \\$Source\SQLPilotShare)
#   -ForceScriptOut  force the offline package path (dbatools only)
#   -ExportPath   script-out package dir
#   -IncludeJobs / -IncludeLinked / -IncludeConfigs / -IncludeSsis  toggles (default $true)
# ---------------------------------------------------------------------------
function Invoke-RealMigrateDcToDc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $Source,
        [Parameter(Mandatory)] [string]   $Destination,
        [ValidateSet('whole','db')] [string] $Scope = 'whole',
        [string[]]                         $Databases,
        [ValidateSet('dbatools','native')] [string] $Engine = 'native',
        [string]                           $SharedPath,
        [switch]                           $ForceScriptOut,
        [string]                           $ExportPath = 'C:\SQLPilot\Exports',
        [bool] $IncludeJobs=$true, [bool] $IncludeLinked=$true,
        [bool] $IncludeConfigs=$false, [bool] $IncludeSsis=$true
    )

    $started = Get-Date
    if (-not $SharedPath) { $SharedPath = "\\$Source\SQLPilotShare" }

    $result = [ordered]@{
        status='ok'; source=$Source; destination=$Destination; scope=$Scope
        engine=$Engine; databases=@($Databases); shared_path=$SharedPath
        reachable=$false; mode=$null; steps=@(); package_path=$null
        elapsed_seconds=$null; note=$null
    }

    # --- Engine resolution (no silent fallback) ---
    if ($Engine -eq 'dbatools') {
        if (-not (Initialize-Dbatools)) {
            $result.status='error'
            $result.error='dbatools engine requested but dbatools is not available on this host. Install dbatools (Install-Module dbatools -Scope CurrentUser) or choose the Native engine.'
            return $result
        }
    } else {
        # native: do not require dbatools at all
        $script:DbatoolsChecked = $true; $script:DbatoolsOk = $false
    }

    # --- Reachability ---
    if (-not $ForceScriptOut) { $result.reachable = Test-DestinationReachable -Destination $Destination }

    # --- Validate scope inputs ---
    if ($Scope -eq 'db' -and (-not $Databases -or $Databases.Count -eq 0)) {
        $result.status='error'; $result.error='Database List scope requires -Databases.'; return $result
    }

    # ===================================================================
    # SCRIPT-OUT (destination down or forced) - dbatools only.
    # ===================================================================
    if ($ForceScriptOut -or (-not $result.reachable)) {
        if ($Engine -eq 'native') {
            $result.status='error'
            $result.error="Destination not reachable and Engine=native. Native has no script-out path (needs a reachable destination). Use dbatools mode for an offline script-out package, or bring the destination online."
            return $result
        }
        $result.mode = 'script-out (dbatools Export)'
        if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
        $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
        $pkg   = Join-Path $ExportPath "dcdc_${Source}_$stamp"
        New-Item -ItemType Directory -Path $pkg -Force | Out-Null
        $result.package_path = $pkg
        try {
            if ($Scope -eq 'whole') {
                Export-DbaInstance -SqlInstance $Source -Path $pkg -NoPrefix -ErrorAction Stop 2>&1 | Out-Null
            } else {
                foreach ($db in $Databases) {
                    Export-DbaScript -InputObject (Get-DbaDatabase -SqlInstance $Source -Database $db) -Path (Join-Path $pkg "db_$db.sql") -ErrorAction SilentlyContinue 2>&1 | Out-Null
                }
            }
            $result.steps += @{ step='script-out'; status='ok'; package=$pkg }
            $result.note = "Script package written to $pkg. Apply to the destination when reachable."
        } catch { $result.status='error'; $result.error="$($_.Exception.Message)" }
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        return $result
    }

    # ===================================================================
    # LIVE migration - reachable. Resolve the database list for whole-server.
    # ===================================================================
    $result.mode = "$Engine live ($Scope)"

    # For whole-server we need the actual user-DB list to drive the modules
    # (TDE scan, validate). dbatools whole-server can still use Start-DbaMigration
    # for the bulk, but we resolve the DB list either way.
    $dbList = @($Databases)
    if ($Scope -eq 'whole') {
        try {
            $rows = Invoke-Sqlcmd -ServerInstance $Source -TrustServerCertificate -Encrypt Optional -ErrorAction Stop `
                -Query "SELECT name FROM sys.databases WHERE database_id > 4 AND state_desc='ONLINE'"
            $dbList = @($rows | ForEach-Object { "$($_.name)" })
        } catch { $dbList = @() }
    }
    $result.databases = $dbList

    # --- Special case: dbatools + whole-server = the proven Start-DbaMigration path ---
    # Preserve it: one call handles DBs+logins+jobs+linked+etc. Then we still run
    # TDE first (Start-DbaMigration is unreliable for TDE certs) and validate after.
    if ($Engine -eq 'dbatools' -and $Scope -eq 'whole') {
        # TDE certs first (so TDE DBs can come across).
        Invoke-DcDcStep -Result $result -StepName 'tde' -FunctionName 'Invoke-MigrateTdeCertificates' `
            -Params @{ Source=$Source; Destination=$Destination; Databases=$dbList; SharedPath=$SharedPath; Engine='dbatools' }
        Write-Host "[dcdc] LIVE whole-server: Start-DbaMigration $Source -> $Destination" -ForegroundColor Cyan
        try {
            $mig = Start-DbaMigration -Source $Source -Destination $Destination -Force -Exclude Backups,SystemDatabases -ErrorAction Stop 2>&1
            $result.steps += @{ step='start-dbamigration'; status='ok'; items=@($mig | ForEach-Object { @{ type="$($_.Type)"; name="$($_.Name)"; status="$($_.Status)" } }) }
        } catch { $result.status='partial'; $result.steps += @{ step='start-dbamigration'; status='error'; error="$($_.Exception.Message)" } }
        Invoke-DcDcStep -Result $result -StepName 'validate' -FunctionName 'Invoke-MigrateValidate' `
            -Params @{ Destination=$Destination; Databases=$dbList; Engine=$Engine }
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        $result.note = "dbatools whole-server via Start-DbaMigration (TDE pre-step + validate post-step layered on)."
        return $result
    }

    # ===================================================================
    # GENERAL ORDERED PIPELINE (native any-scope, or dbatools db-list).
    # Each step is mode-aware inside its module.
    # ===================================================================

    # 1. TDE (MUST precede databases).
    Invoke-DcDcStep -Result $result -StepName 'tde' -FunctionName 'Invoke-MigrateTdeCertificates' `
        -Params @{ Source=$Source; Destination=$Destination; Databases=$dbList; SharedPath=$SharedPath; Engine=$Engine }

    # 2. Databases.
    Invoke-DcDcStep -Result $result -StepName 'databases' -FunctionName 'Invoke-MigrateDatabases' `
        -Params @{ Source=$Source; Destination=$Destination; Databases=$dbList; SharedPath=$SharedPath; Engine=$Engine }

    # 3. Logins. (migrate_logins.ps1's Invoke-RealMigrateLogins targets the Cloud
    #    VM via terraform coords - NOT the DC->DC destination. For DC->DC native
    #    logins we rely on the SID-preserving path; if a DC->DC-aware login
    #    function is added later, swap the FunctionName here. For now, recorded.)
    Invoke-DcDcStep -Result $result -StepName 'logins' -FunctionName 'Invoke-MigrateLoginsDcToDc' `
        -Params @{ Source=$Source; Destination=$Destination; Databases=$dbList; Engine=$Engine }

    # 4. Agent jobs.
    if ($IncludeJobs) {
        Invoke-DcDcStep -Result $result -StepName 'jobs' -FunctionName 'Invoke-MigrateAgentJobs' `
            -Params @{ Source=$Source; Destination=$Destination; Engine=$Engine }
    }

    # 5. Linked servers.
    if ($IncludeLinked) {
        Invoke-DcDcStep -Result $result -StepName 'linked_servers' -FunctionName 'Invoke-MigrateLinkedServers' `
            -Params @{ Source=$Source; Destination=$Destination; Engine=$Engine }
    }

    # 6. Server configs (off by default - changes destination instance config).
    if ($IncludeConfigs) {
        Invoke-DcDcStep -Result $result -StepName 'configs' -FunctionName 'Invoke-MigrateServerConfigs' `
            -Params @{ Source=$Source; Destination=$Destination; Engine=$Engine }
    }

    # 7. SSIS (honest decline in native).
    if ($IncludeSsis) {
        Invoke-DcDcStep -Result $result -StepName 'ssis' -FunctionName 'Invoke-MigrateSsis' `
            -Params @{ Source=$Source; Destination=$Destination; Engine=$Engine }
    }

    # 8. Validate.
    Invoke-DcDcStep -Result $result -StepName 'validate' -FunctionName 'Invoke-MigrateValidate' `
        -Params @{ Destination=$Destination; Databases=$dbList; Engine=$Engine }

    $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
    if ($result.status -eq 'ok') { $result.note = "Completed $Engine live migration ($Scope), $($dbList.Count) database(s), modular pipeline." }
    return $result
}

# Helper retained from the original tool (used by login scoping if needed).
function Get-DbDependentLogins {
    param([Parameter(Mandatory)] [string] $Source, [string[]] $Databases)
    $names = New-Object System.Collections.Generic.HashSet[string]
    if (-not $Databases) { return @() }
    foreach ($db in $Databases) {
        $dbEsc = $db -replace ']', ']]'
        $q = "SELECT sp.name AS LoginName FROM [$dbEsc].sys.database_principals dp JOIN sys.server_principals sp ON dp.sid = sp.sid WHERE dp.type IN ('S','U','G') AND sp.sid IS NOT NULL;"
        try {
            $rows = Invoke-Sqlcmd -ServerInstance $Source -Query $q -TrustServerCertificate -Encrypt Optional -ErrorAction Stop
            foreach ($r in @($rows)) { [void]$names.Add(("$($r.LoginName)").Trim()) }
        } catch {}
    }
    return @($names)
}
