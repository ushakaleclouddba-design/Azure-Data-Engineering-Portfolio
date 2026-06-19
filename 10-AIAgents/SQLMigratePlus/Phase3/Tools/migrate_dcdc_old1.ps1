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

    # BUG-040: PRE-FLIGHT backup-share check. The live backup/restore path writes
    # the backup to $SharedPath on the source and reads it from the destination.
    # If that UNC share is missing or not writable, the migration fails deep
    # inside Copy-DbaDatabase / BACKUP with a cryptic "OS error 67 (network name
    # cannot be found)". Catch it here with a clear, actionable message instead.
    # We test ACTUAL write access (not just Test-Path) because the share can be
    # reachable but not writable by the running account.
    try {
        $shareOk = $false
        $shareErr = $null
        $probe = Join-Path $SharedPath ("sqlpilot_preflight_{0}.tmp" -f ([Guid]::NewGuid().ToString('N').Substring(0,8)))
        try {
            Set-Content -Path $probe -Value 'sqlpilot preflight' -ErrorAction Stop
            $shareOk = Test-Path $probe
            Remove-Item $probe -Force -ErrorAction SilentlyContinue
        } catch {
            $shareErr = "$($_.Exception.Message)"
        }
        if (-not $shareOk) {
            $result.status = 'error'
            $result.halted_at = 'preflight-share'
            $result.error = "Backup share not usable: '$SharedPath'. The live backup/restore path needs a UNC share that the SOURCE can write to and the DESTINATION can read from. " +
                "Create it (e.g. on $Source: New-SmbShare -Name SQLPilotShare -Path <folder> -FullAccess <SQL service accounts>) and grant BOTH SQL Server service accounts read/write, then re-run. " +
                ($(if ($shareErr) { "Underlying error: $shareErr" } else { "(Probe write failed.)" }))
            $result.steps += @{ step='preflight-share'; status='error'; note=$result.error }
            $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
            Write-Host "[dcdc] HALT: backup share '$SharedPath' not writable. $shareErr" -ForegroundColor Red
            return $result
        }
        Write-Host "[dcdc] preflight: backup share '$SharedPath' is reachable and writable." -ForegroundColor DarkGray
    } catch {
        # If the preflight itself throws unexpectedly, fail honestly rather than
        # proceeding into a confusing downstream error.
        $result.status = 'error'
        $result.halted_at = 'preflight-share'
        $result.error = "Backup-share preflight check failed for '$SharedPath': $($_.Exception.Message)"
        $result.steps += @{ step='preflight-share'; status='error'; note=$result.error }
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        return $result
    }

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
        $migOk = $false
        try {
            # Capture warnings too: Start-DbaMigration, like Copy-DbaDatabase,
            # can report a failed transfer via the warning stream rather than a
            # terminating error (BUG-038 class). Inspect both.
            $mig = Start-DbaMigration -Source $Source -Destination $Destination -Force -Exclude Backups,SystemDatabases -ErrorAction Stop -WarningVariable migWarn 3>$null
            $items = @($mig | ForEach-Object { @{ type="$($_.Type)"; name="$($_.Name)"; status="$($_.Status)" } })
            # Consider it successful only if at least one item came back and none
            # of the database items report a failure status.
            $dbItems = @($items | Where-Object { "$($_.type)" -match 'Database' })
            $dbFailed = @($dbItems | Where-Object { "$($_.status)" -notmatch 'Success|Skipped' })
            if ($items.Count -gt 0 -and $dbFailed.Count -eq 0) {
                $result.steps += @{ step='start-dbamigration'; status='ok'; items=$items }
                $migOk = $true
            } else {
                $errMsg = if ($migWarn) { "Start-DbaMigration reported issues. First: $(@($migWarn)[0])" }
                          else { "Start-DbaMigration produced no successful database results." }
                $result.steps += @{ step='start-dbamigration'; status='error'; error=$errMsg; items=$items }
            }
        } catch {
            $result.steps += @{ step='start-dbamigration'; status='error'; error="$($_.Exception.Message)" }
        }

        # BUG-039: strict halt for the whole-server path too. If the mega-migration
        # call did not succeed, do NOT run validate (there is nothing reliably
        # migrated to check) — mark it blocked with a clear reason.
        if (-not $migOk) {
            $blockReason = "Blocked: the whole-server migration (Start-DbaMigration) did not complete successfully. Validation was not run because there is no reliably migrated database to check. See the start-dbamigration error, resolve it, then re-run."
            $result.steps += @{ step='validate'; status='blocked'; note=$blockReason }
            $result.status = 'error'
            $result.halted_at = 'start-dbamigration'
            $result.error = $blockReason
            $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
            Write-Host "[dcdc] HALT: Start-DbaMigration did not succeed — validate blocked." -ForegroundColor Red
            return $result
        }

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

    # BUG-039: STRICT dependency halt. The databases step is the foundation of
    # the migration — logins map to database users, jobs reference databases, and
    # validate runs DBCC against them. If databases did not migrate, every
    # downstream step is meaningless and would produce misleading results. So we
    # stop here and mark the remaining steps 'blocked' with an explicit reason
    # rather than running them against a destination that has no migrated DBs.
    $dbStep = @($result.steps | Where-Object { $_.step -eq 'databases' })[-1]
    if ($dbStep -and ($dbStep.status -eq 'error' -or $dbStep.status -eq 'partial')) {
        $blockReason = "Blocked: the databases step did not complete successfully ($($dbStep.status)). Downstream steps depend on the migrated databases and were not run. Resolve the database migration (see the databases step error), then re-run."
        $downstream = @('logins','jobs','linked_servers','configs','ssis','validate')
        foreach ($sname in $downstream) {
            # Respect the include flags — only list steps that would have run.
            if ($sname -eq 'jobs'           -and -not $IncludeJobs)    { continue }
            if ($sname -eq 'linked_servers' -and -not $IncludeLinked)  { continue }
            if ($sname -eq 'configs'        -and -not $IncludeConfigs) { continue }
            if ($sname -eq 'ssis'           -and -not $IncludeSsis)    { continue }
            $result.steps += @{ step=$sname; status='blocked'; note=$blockReason }
        }
        $result.status = 'error'
        $result.halted_at = 'databases'
        $result.error = $blockReason
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        Write-Host "[dcdc] HALT: databases step $($dbStep.status) — downstream steps blocked." -ForegroundColor Red
        return $result
    }

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
