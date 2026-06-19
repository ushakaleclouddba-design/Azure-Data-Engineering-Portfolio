<#
.SYNOPSIS
    SQLPilot - Real migrate_logins tool (SID-preserving).

.DESCRIPTION
    Migrates SQL Server logins from a SOURCE instance to a TARGET, preserving
    SIDs so that database users restored on the target re-map to their logins
    automatically (no orphaned users).

    Two engines, auto-selected:
      1. If dbatools is available  -> Copy-DbaLogin (handles SID + password
         hash + default DB + roles natively, the gold standard).
      2. Otherwise                  -> classic sp_help_revlogin-style T-SQL:
         read sys.sql_logins on the source (name, sid, password_hash,
         default_database, is_disabled), then on the target
         CREATE LOGIN [name] WITH PASSWORD = 0x... HASHED, SID = 0x...,
         DEFAULT_DATABASE = ... . Windows logins are scripted with
         FROM WINDOWS. Existing logins are skipped (idempotent).

    Scope:
      - When -Databases is supplied, only logins that are USERS in those
        databases (mapped by SID) are migrated -> the dependency-aware,
        single-database case.
      - When -Databases is empty/null, ALL non-system logins are migrated
        -> the whole-server case.

    System logins (sa, ##MS*, NT SERVICE\, NT AUTHORITY\) are always skipped.

    Returns a hashtable shaped like restore.ps1:
      status, mock, source, target, engine, scope, migrated[], skipped[],
      failed[], migrated_count, skipped_count, failed_count, elapsed_seconds.

.NOTES
    Author : Kale
    Pattern: mirrors tools/restore.ps1. server.ps1 dot-sources this file at
             startup; /api/migrate/logins calls Invoke-RealMigrateLogins.
             Reuses Initialize-RestoreCoords from restore.ps1 for target
             coordinates (same terraform output), so restore.ps1 must load
             first (server.ps1 loads it earlier in the dot-source list).
#>

# ---------------------------------------------------------------------------
# Helper - resolve target coordinates. Reuse restore.ps1's loader/cache if
# present (same terraform output); otherwise we can't proceed.
# ---------------------------------------------------------------------------
function Get-MigrateTargetCoords {
    if ($script:RestoreCoords) { return $script:RestoreCoords }
    $init = Get-Command -Name 'Initialize-RestoreCoords' -ErrorAction SilentlyContinue
    if ($init) {
        Initialize-RestoreCoords
        return $script:RestoreCoords
    }
    throw "Target coordinates unavailable (restore.ps1 not loaded). Cannot resolve target VM."
}

# ---------------------------------------------------------------------------
# Helper - build common Invoke-Sqlcmd args, and a target credential set.
# ---------------------------------------------------------------------------
function Get-MigrateInvokeArgs {
    param([Parameter(Mandatory)] $Coords)
    $common = @{
        TrustServerCertificate = $true
        Encrypt                = 'Optional'
        QueryTimeout           = 600
        ConnectionTimeout      = 30
        ErrorAction            = 'Stop'
    }
    $securePw   = ConvertTo-SecureString $Coords.AdminPassword -AsPlainText -Force
    $targetCred = New-Object System.Management.Automation.PSCredential($Coords.AdminUser, $securePw)
    $target = $common.Clone()
    $target['Credential'] = $targetCred
    return @{ Common = $common; Target = $target }
}

# ---------------------------------------------------------------------------
# Helper - bytes to 0x-prefixed hex string for SID / password_hash literals.
# ---------------------------------------------------------------------------
function ConvertTo-SqlHex {
    param([byte[]] $Bytes)
    if (-not $Bytes -or $Bytes.Length -eq 0) { return $null }
    return '0x' + (($Bytes | ForEach-Object { $_.ToString('X2') }) -join '')
}

# ---------------------------------------------------------------------------
# Invoke-RealMigrateLogins
#   -Source    source SQL instance (Windows auth)
#   -Target    optional; defaults to terraform target VM
#   -Databases optional array; if set, only logins mapped as users in those
#              DBs are migrated. If empty, all non-system logins.
# ---------------------------------------------------------------------------
function Invoke-RealMigrateLogins {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]   $Source,
        [string]                          $Target,
        [string[]]                        $Databases
    )

    $started = Get-Date
    $coords  = Get-MigrateTargetCoords
    $effectiveTarget = $coords.PublicIp
    $ia = Get-MigrateInvokeArgs -Coords $coords
    $sourceArgs = $ia.Common
    $targetArgs = $ia.Target

    $migrated = @(); $skipped = @(); $failed = @()

    # System / built-in logins we never migrate.
    $systemPrefixes = @('##','NT SERVICE\','NT AUTHORITY\','BUILTIN\')
    $systemNames    = @('sa')

    # -----------------------------------------------------------------
    # 1. Decide which logins are in scope.
    # -----------------------------------------------------------------
    $scopeDesc = 'all logins'
    $loginNameFilter = $null

    if ($Databases -and $Databases.Count -gt 0) {
        $scopeDesc = "logins for $($Databases.Count) database(s)"
        # Collect distinct login names that are users (by SID) in the chosen DBs.
        $names = New-Object System.Collections.Generic.HashSet[string]
        foreach ($db in $Databases) {
            $dbEsc = $db -replace ']', ']]'
            $q = @"
SELECT sp.name AS LoginName
FROM [$dbEsc].sys.database_principals dp
JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE dp.type IN ('S','U','G') AND sp.sid IS NOT NULL;
"@
            $a = $sourceArgs.Clone(); $a['ServerInstance'] = $Source; $a['Query'] = $q; $a['OutputAs'] = 'DataTables'
            try {
                $rows = Invoke-Sqlcmd @a
                $rs = if ($rows -is [System.Data.DataTable]) { @($rows) } elseif ($null -ne $rows) { @($rows.Rows) } else { @() }
                foreach ($r in $rs) { [void]$names.Add(("$($r.LoginName)").Trim()) }
            } catch {
                Write-Host "[logins] warn: could not read users for [$db]: $($_.Exception.Message)" -ForegroundColor DarkYellow
            }
        }
        $loginNameFilter = @($names)
        if ($loginNameFilter.Count -eq 0) {
            return @{
                status='ok'; mock=$false; source=$Source; target=$effectiveTarget
                engine='none'; scope=$scopeDesc
                migrated=@(); skipped=@(); failed=@()
                migrated_count=0; skipped_count=0; failed_count=0
                note='No database users mapped to server logins were found for the selected database(s).'
                elapsed_seconds=[int]((Get-Date)-$started).TotalSeconds
            }
        }
    }

    # -----------------------------------------------------------------
    # 2. Engine A - dbatools Copy-DbaLogin if available.
    # -----------------------------------------------------------------
    $haveDbatools = Get-Command -Name 'Copy-DbaLogin' -ErrorAction SilentlyContinue
    if ($haveDbatools) {
        Write-Host "[logins] Using dbatools Copy-DbaLogin." -ForegroundColor DarkGray
        $securePw = ConvertTo-SecureString $coords.AdminPassword -AsPlainText -Force
        $targetCred = New-Object System.Management.Automation.PSCredential($coords.AdminUser, $securePw)
        try {
            $cp = @{
                Source            = $Source
                Destination       = $effectiveTarget
                DestinationSqlCredential = $targetCred
                Force             = $false
                ErrorAction       = 'Stop'
            }
            if ($loginNameFilter) { $cp['Login'] = $loginNameFilter }
            $res = Copy-DbaLogin @cp
            foreach ($row in @($res)) {
                $name = "$($row.Name)"
                $st   = "$($row.Status)"
                if ($st -match 'Success') { $migrated += $name }
                elseif ($st -match 'Skip') { $skipped += @{ name=$name; reason="$($row.Notes)" } }
                else { $failed += @{ name=$name; reason="$($row.Notes)" } }
            }
            return @{
                status='ok'; mock=$false; source=$Source; target=$effectiveTarget
                engine='dbatools Copy-DbaLogin'; scope=$scopeDesc
                migrated=$migrated; skipped=$skipped; failed=$failed
                migrated_count=$migrated.Count; skipped_count=$skipped.Count; failed_count=$failed.Count
                elapsed_seconds=[int]((Get-Date)-$started).TotalSeconds
            }
        } catch {
            Write-Host "[logins] dbatools path failed ($($_.Exception.Message)); falling back to T-SQL." -ForegroundColor DarkYellow
        }
    }

    # -----------------------------------------------------------------
    # 3. Engine B - classic SID-preserving T-SQL.
    # -----------------------------------------------------------------
    Write-Host "[logins] Using T-SQL SID-preserving script." -ForegroundColor DarkGray

    # 3a. Read source logins.
    $srcQ = @"
SELECT sp.name AS LoginName, sp.sid AS Sid, sp.type AS LoginType,
       sp.is_disabled AS IsDisabled, sp.default_database_name AS DefaultDb,
       sl.password_hash AS PwdHash
FROM sys.server_principals sp
LEFT JOIN sys.sql_logins sl ON sp.sid = sl.sid
WHERE sp.type IN ('S','U','G')
ORDER BY sp.name;
"@
    $a = $sourceArgs.Clone(); $a['ServerInstance'] = $Source; $a['Query'] = $srcQ; $a['OutputAs'] = 'DataTables'
    $srcRows = Invoke-Sqlcmd @a
    $srcList = if ($srcRows -is [System.Data.DataTable]) { @($srcRows) } elseif ($null -ne $srcRows) { @($srcRows.Rows) } else { @() }

    # 3b. Read existing target logins so we skip duplicates.
    $tgtQ = "SELECT name FROM sys.server_principals WHERE type IN ('S','U','G');"
    $ta = $targetArgs.Clone(); $ta['ServerInstance'] = $effectiveTarget; $ta['Query'] = $tgtQ; $ta['OutputAs'] = 'DataTables'
    $tgtRows = Invoke-Sqlcmd @ta
    $tgtList = if ($tgtRows -is [System.Data.DataTable]) { @($tgtRows) } elseif ($null -ne $tgtRows) { @($tgtRows.Rows) } else { @() }
    $existing = New-Object System.Collections.Generic.HashSet[string]
    foreach ($r in $tgtList) { [void]$existing.Add(("$($r.name)").Trim().ToLowerInvariant()) }

    foreach ($r in $srcList) {
        $name = ("$($r.LoginName)").Trim()
        if (-not $name) { continue }

        # Skip system logins.
        $isSystem = $false
        foreach ($p in $systemPrefixes) { if ($name.StartsWith($p)) { $isSystem = $true; break } }
        if ($systemNames -contains $name) { $isSystem = $true }
        if ($isSystem) { continue }

        # Scope filter (single-DB case).
        if ($loginNameFilter -and ($loginNameFilter -notcontains $name)) { continue }

        # Already on target?
        if ($existing.Contains($name.ToLowerInvariant())) {
            $skipped += @{ name=$name; reason='already exists on target' }
            continue
        }

        try {
            $type      = ("$($r.LoginType)").Trim()
            $defaultDb = ("$($r.DefaultDb)").Trim(); if (-not $defaultDb) { $defaultDb = 'master' }
            $disabled  = [bool]$r.IsDisabled
            $nameEsc   = $name -replace ']', ']]'
            $dbEsc     = $defaultDb -replace ']', ']]'

            if ($type -eq 'S') {
                # SQL login: preserve password hash + SID.
                $sidBytes = $null; $pwdBytes = $null
                if ($r.Sid -is [byte[]]) { $sidBytes = $r.Sid } elseif ($r.Sid) { $sidBytes = [byte[]]$r.Sid }
                if ($r.PwdHash -is [byte[]]) { $pwdBytes = $r.PwdHash } elseif ($r.PwdHash) { $pwdBytes = [byte[]]$r.PwdHash }
                $sidHex = ConvertTo-SqlHex $sidBytes
                $pwdHex = ConvertTo-SqlHex $pwdBytes
                if (-not $pwdHex) { $skipped += @{ name=$name; reason='no password hash readable (need sysadmin on source)' }; continue }
                $sql = "CREATE LOGIN [$nameEsc] WITH PASSWORD = $pwdHex HASHED" + ($(if ($sidHex) { ", SID = $sidHex" } else { '' })) + ", DEFAULT_DATABASE = [$dbEsc], CHECK_POLICY = OFF;"
                if ($disabled) { $sql += " ALTER LOGIN [$nameEsc] DISABLE;" }
            } else {
                # Windows login (user 'U' or group 'G').
                $sql = "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$($name -replace "'","''")') CREATE LOGIN [$nameEsc] FROM WINDOWS WITH DEFAULT_DATABASE = [$dbEsc];"
                if ($disabled) { $sql += " ALTER LOGIN [$nameEsc] DISABLE;" }
            }

            $ea = $targetArgs.Clone(); $ea['ServerInstance'] = $effectiveTarget; $ea['Query'] = $sql
            Invoke-Sqlcmd @ea | Out-Null
            $migrated += $name
        } catch {
            $failed += @{ name=$name; reason="$($_.Exception.Message)" }
        }
    }

    return @{
        status='ok'; mock=$false; source=$Source; target=$effectiveTarget
        engine='T-SQL SID-preserving'; scope=$scopeDesc
        migrated=$migrated; skipped=$skipped; failed=$failed
        migrated_count=$migrated.Count; skipped_count=$skipped.Count; failed_count=$failed.Count
        method_rationale='SID-preserving login migration so restored database users re-map without orphaning (Microsoft: Transfer Logins and Passwords between instances).'
        elapsed_seconds=[int]((Get-Date)-$started).TotalSeconds
    }
}

# ===========================================================================
# DC->DC variant - Invoke-MigrateLoginsDcToDc
#   Same SID-preserving logic as Invoke-RealMigrateLogins, but connects to the
#   DESTINATION BY NAME (Windows auth) instead of the Cloud VM via terraform
#   coords. This is the function the DC->DC orchestrator calls at step 3.
#   Reuses ConvertTo-SqlHex (defined above).
#
#   -Source / -Destination  SQL instances (Windows auth, by name)
#   -Databases   optional; if set, only logins that are users (by SID) in those
#                DBs are migrated (dependency-aware). Empty => all non-system.
#   -Engine      'dbatools' | 'native'
#   -Overwrite   $false (default) => skip existing logins on destination
#   Returns the same result shape as the other DC->DC modules.
# ===========================================================================
function Invoke-MigrateLoginsDcToDc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $Source,
        [Parameter(Mandatory)] [string]   $Destination,
        [string[]]                        $Databases,
        [ValidateSet('dbatools','native')] [string] $Engine = 'native',
        [bool] $Overwrite = $false
    )

    $started = Get-Date
    $common  = @{ TrustServerCertificate=$true; Encrypt='Optional'; QueryTimeout=600; ConnectionTimeout=30; ErrorAction='Stop' }
    $result  = [ordered]@{
        status='ok'; engine=$Engine; source=$Source; destination=$Destination
        scope=$(if($Databases -and $Databases.Count){"logins for $($Databases.Count) database(s)"}else{'all logins'})
        migrated=@(); skipped=@(); failed=@(); elapsed_seconds=$null; note=$null
    }

    $systemPrefixes = @('##','NT SERVICE\','NT AUTHORITY\','BUILTIN\')
    $systemNames    = @('sa')

    # BUG-027 fix: in dbatools mode the SqlServer module can't load (SMO assembly
    # conflict with dbatools), so Invoke-Sqlcmd is unavailable. Route every query
    # through this helper: Invoke-DbaQuery for dbatools, Invoke-Sqlcmd for native.
    $runQuery = {
        param($ServerInstance, $Query)
        if ($Engine -eq 'dbatools') {
            Invoke-DbaQuery -SqlInstance $ServerInstance -Query $Query -EnableException
        } else {
            Invoke-Sqlcmd @common -ServerInstance $ServerInstance -Query $Query
        }
    }

    # ----- scope: which logins? (dependency-aware for db-list) -----
    $loginNameFilter = $null
    if ($Databases -and $Databases.Count -gt 0) {
        $names = New-Object System.Collections.Generic.HashSet[string]
        foreach ($db in $Databases) {
            $dbEsc = $db -replace ']', ']]'
            $q = "SELECT sp.name AS LoginName FROM [$dbEsc].sys.database_principals dp JOIN sys.server_principals sp ON dp.sid = sp.sid WHERE dp.type IN ('S','U','G') AND sp.sid IS NOT NULL;"
            try {
                $rows = & $runQuery $Source $q
                foreach ($r in @($rows)) { [void]$names.Add(("$($r.LoginName)").Trim()) }
            } catch { Write-Host "[logins-dcdc] warn: users for [$db]: $($_.Exception.Message)" -ForegroundColor DarkYellow }
        }
        $loginNameFilter = @($names)
        if (-not $loginNameFilter.Count) {
            $result.note = 'No database users mapped to server logins for the selected database(s).'
            $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
            return $result
        }
    }

    # ----- dbatools engine -----
    if ($Engine -eq 'dbatools') {
        try {
            $cp = @{ Source=$Source; Destination=$Destination; ErrorAction='Stop' }
            if ($Overwrite) { $cp['Force'] = $true }
            if ($loginNameFilter) { $cp['Login'] = $loginNameFilter }
            $res = Copy-DbaLogin @cp 2>&1
            foreach ($row in @($res)) {
                $n = "$($row.Name)"; $st = "$($row.Status)"
                if ($st -match 'Success') { $result.migrated += $n }
                elseif ($st -match 'Skip') { $result.skipped += @{ name=$n; reason="$($row.Notes)" } }
                else { $result.failed += @{ name=$n; reason="$($row.Notes)" } }
            }
        } catch { $result.status='error'; $result.error="$($_.Exception.Message)" }
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        return $result
    }

    # ----- native: SID-preserving T-SQL (reuses ConvertTo-SqlHex) -----
    $srcQ = @"
SELECT sp.name AS LoginName, sp.sid AS Sid, sp.type AS LoginType,
       sp.is_disabled AS IsDisabled, sp.default_database_name AS DefaultDb,
       sl.password_hash AS PwdHash
FROM sys.server_principals sp
LEFT JOIN sys.sql_logins sl ON sp.sid = sl.sid
WHERE sp.type IN ('S','U','G')
ORDER BY sp.name;
"@
    try { $srcList = @(Invoke-Sqlcmd @common -ServerInstance $Source -Query $srcQ -OutputAs DataTables) }
    catch { $result.status='error'; $result.error="Could not read source logins: $($_.Exception.Message)"; return $result }
    if ($srcList.Count -eq 1 -and $srcList[0] -is [System.Data.DataTable]) { $srcList = @($srcList[0].Rows) }

    # existing logins on destination
    $existing = New-Object System.Collections.Generic.HashSet[string]
    try {
        $tgt = @(Invoke-Sqlcmd @common -ServerInstance $Destination -Query "SELECT name FROM sys.server_principals WHERE type IN ('S','U','G');")
        foreach ($r in $tgt) { [void]$existing.Add(("$($r.name)").Trim().ToLowerInvariant()) }
    } catch { $result.status='error'; $result.error="Could not read destination logins: $($_.Exception.Message)"; return $result }

    foreach ($r in $srcList) {
        $name = ("$($r.LoginName)").Trim()
        if (-not $name) { continue }
        $isSystem = $false
        foreach ($p in $systemPrefixes) { if ($name.StartsWith($p)) { $isSystem = $true; break } }
        if ($systemNames -contains $name) { $isSystem = $true }
        if ($isSystem) { continue }
        if ($loginNameFilter -and ($loginNameFilter -notcontains $name)) { continue }

        if ($existing.Contains($name.ToLowerInvariant())) {
            if (-not $Overwrite) { $result.skipped += @{ name=$name; reason='already exists on destination' }; continue }
            try { Invoke-Sqlcmd @common -ServerInstance $Destination -Query "DROP LOGIN [$($name -replace ']',']]')];" } catch {}
        }

        try {
            $type      = ("$($r.LoginType)").Trim()
            $defaultDb = ("$($r.DefaultDb)").Trim(); if (-not $defaultDb) { $defaultDb = 'master' }
            $disabled  = [bool]$r.IsDisabled
            $nameEsc   = $name -replace ']', ']]'
            $dbEsc     = $defaultDb -replace ']', ']]'

            if ($type -eq 'S') {
                $sidBytes = if ($r.Sid -is [byte[]]) { $r.Sid } elseif ($r.Sid) { [byte[]]$r.Sid } else { $null }
                $pwdBytes = if ($r.PwdHash -is [byte[]]) { $r.PwdHash } elseif ($r.PwdHash) { [byte[]]$r.PwdHash } else { $null }
                $sidHex = ConvertTo-SqlHex $sidBytes
                $pwdHex = ConvertTo-SqlHex $pwdBytes
                if (-not $pwdHex) { $result.skipped += @{ name=$name; reason='no password hash readable (need sysadmin on source)' }; continue }
                $sql = "CREATE LOGIN [$nameEsc] WITH PASSWORD = $pwdHex HASHED" + ($(if ($sidHex) { ", SID = $sidHex" } else { '' })) + ", DEFAULT_DATABASE = [$dbEsc], CHECK_POLICY = OFF;"
                if ($disabled) { $sql += " ALTER LOGIN [$nameEsc] DISABLE;" }
            } else {
                $sql = "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$($name -replace "'","''")') CREATE LOGIN [$nameEsc] FROM WINDOWS WITH DEFAULT_DATABASE = [$dbEsc];"
                if ($disabled) { $sql += " ALTER LOGIN [$nameEsc] DISABLE;" }
            }
            Invoke-Sqlcmd @common -ServerInstance $Destination -Query $sql | Out-Null
            $result.migrated += $name
        } catch {
            $result.failed += @{ name=$name; reason="$($_.Exception.Message)" }
        }
    }

    if ($result.failed.Count -and $result.migrated.Count) { $result.status='partial' }
    elseif ($result.failed.Count -and -not $result.migrated.Count) { $result.status='error' }
    $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
    $result.note = "native SID-preserving T-SQL · $($result.migrated.Count) login(s) migrated to $Destination (orphaned-user-safe)."
    return $result
}
