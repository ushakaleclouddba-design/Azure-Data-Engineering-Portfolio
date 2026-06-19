<#
.SYNOPSIS
    SQLPilot - Database migration module (BACKUP/RESTORE + dbatools).

.DESCRIPTION
    Migrates user databases (data included) from a SOURCE instance to a
    DESTINATION, in either engine. One module, both modes, standalone-testable.

      native   : BACKUP DATABASE -> share -> RESTORE ... WITH MOVE (+REPLACE,
                 COMPRESSION, RECOVERY). Logical file names and destination
                 paths are discovered dynamically (never hardcoded):
                   - RESTORE FILELISTONLY for logical names (e.g. *_Data/*_Log)
                   - SERVERPROPERTY InstanceDefaultDataPath/LogPath on the dest
                     to build the MOVE clauses.
      dbatools : Copy-DbaDatabase -BackupRestore -SharedPath (the proven path).

    TDE NOTE: a TDE-encrypted database can only be restored if its certificate
    already exists on the destination. The orchestrator must call the TDE
    module (migrate_tde.ps1) BEFORE this one. This module does not handle certs.

    CUTOVER / DOWNTIME (documented honestly):
      This is a FULL-BACKUP migration. With -Recovery $true (default) the DB is
      restored RECOVERY and comes online immediately, so the cutover/downtime
      window = the full backup + copy + restore duration. Fine for small DBs and
      maintenance windows; for large always-on production DBs the minimal-
      downtime approach is full NORECOVERY + a differential/log chain + a final
      tail-log restore at cutover (seconds of downtime regardless of size) -
      that is a documented ROADMAP enhancement, not implemented here. The
      -Recovery switch (set $false to restore NORECOVERY) leaves the door open
      to add the log-chain cutover later without restructuring.

.NOTES
    Author : Kale
    Pattern: mirrors tools/migrate_logins.ps1 / migrate_tde.ps1. server.ps1
             dot-sources this; the orchestrator calls Invoke-MigrateDatabases.
#>

# ---------------------------------------------------------------------------
# Invoke-MigrateDatabases
#   -Source / -Destination   SQL instances
#   -Databases               databases to migrate (required; the orchestrator
#                            passes the selected list, or all user DBs for whole)
#   -SharedPath              UNC share both servers can read/write (backup transit)
#   -Engine                  'dbatools' | 'native'
#   -Overwrite               if a DB exists on the dest: $true => WITH REPLACE /
#                            dbatools -Force; $false (default) => skip with warning
#   -Recovery                $true (default) => RESTORE WITH RECOVERY (online now);
#                            $false => WITH NORECOVERY (leave restoring - future
#                            log-chain cutover)
#   -Compression             $true (default) => BACKUP WITH COMPRESSION, falls
#                            back gracefully if the edition rejects it
#   Returns: @{ status; engine; source; destination; migrated[]; skipped[];
#               failed[]; elapsed_seconds; note }
# ---------------------------------------------------------------------------
function Invoke-MigrateDatabases {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $Source,
        [Parameter(Mandatory)] [string]   $Destination,
        [Parameter(Mandatory)] [string[]] $Databases,
        [Parameter(Mandatory)] [string]   $SharedPath,
        [ValidateSet('dbatools','native')] [string] $Engine = 'native',
        [bool] $Overwrite   = $true,
        [bool] $Recovery    = $true,
        [bool] $Compression = $true
    )

    $started = Get-Date
    $result = [ordered]@{
        status='ok'; engine=$Engine; source=$Source; destination=$Destination
        migrated=@(); skipped=@(); failed=@(); elapsed_seconds=$null; note=$null
    }
    if (-not $Databases -or $Databases.Count -eq 0) {
        $result.status='error'; $result.error='No databases specified.'; return $result
    }

    $common = @{ TrustServerCertificate=$true; Encrypt='Optional'; QueryTimeout=0; ErrorAction='Stop' }

    # =====================================================================
    # dbatools engine - the proven Copy-DbaDatabase path.
    # =====================================================================
    if ($Engine -eq 'dbatools') {
        try {
            $copyArgs = @{
                Source       = $Source
                Destination  = $Destination
                Database     = $Databases
                BackupRestore= $true
                SharedPath   = $SharedPath
                ErrorAction  = 'Stop'
            }
            if ($Overwrite) { $copyArgs['Force'] = $true }
            # Capture warnings explicitly. Copy-DbaDatabase often reports a failed
            # backup/restore as a WARNING (non-terminating) rather than throwing,
            # so -ErrorAction Stop alone does NOT guarantee the catch fires. We
            # must inspect the returned objects AND the warning stream. (BUG-038)
            $cdb = Copy-DbaDatabase @copyArgs -WarningVariable copyWarn 3>$null
            foreach ($d in @($cdb)) {
                $entry = @{ name="$($d.Name)"; status="$($d.Status)"; notes="$($d.Notes)" }
                if ("$($d.Status)" -match 'Success') { $result.migrated += $entry } else { $result.failed += $entry }
            }
            # BUG-038 honesty checks — do NOT leave status='ok' on a silent failure:
            #  - if dbatools emitted warnings but produced no Success objects, the
            #    copy did not actually happen (e.g. backup share unreachable, OS
            #    error 67). Surface those warnings as failures.
            if ($copyWarn -and $result.migrated.Count -eq 0) {
                foreach ($w in @($copyWarn)) {
                    $result.failed += @{ name='(unknown)'; error="$($w)" }
                }
            }
            #  - final status: nothing migrated -> error; some failed -> partial.
            if ($result.migrated.Count -eq 0) {
                $result.status = 'error'
                if (-not $result.error) {
                    $result.error = if ($copyWarn) { "Copy-DbaDatabase migrated 0 databases. First issue: $(@($copyWarn)[0])" }
                                    else { "Copy-DbaDatabase migrated 0 databases (no objects returned, no warnings captured)." }
                }
            } elseif ($result.failed.Count -gt 0) {
                $result.status = 'partial'
            }
        } catch {
            $result.status='error'; $result.error="$($_.Exception.Message)"
        }
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        return $result
    }

    # =====================================================================
    # native engine - BACKUP / RESTORE in pure T-SQL.
    # =====================================================================
    # Discover destination default data/log paths once.
    try {
        $paths = Invoke-Sqlcmd @common -ServerInstance $Destination -Query `
            "SELECT CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260)) AS DataPath,
                    CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS NVARCHAR(260)) AS LogPath"
        $dataPath = "$($paths.DataPath)"; $logPath = "$($paths.LogPath)"
        if ([string]::IsNullOrWhiteSpace($dataPath)) { throw "Destination default data path is empty." }
    } catch {
        $result.status='error'; $result.error="Could not resolve destination file paths: $($_.Exception.Message)"; return $result
    }

    foreach ($db in $Databases) {
        $dbEsc  = $db -replace "'","''"
        $dbBr   = $db -replace ']',']]'
        $safe   = ($db -replace '[^A-Za-z0-9_]','_')
        $bak    = Join-Path $SharedPath "mig_$safe.bak"

        try {
            # 0. If DB exists on dest and not overwriting -> skip.
            $exists = Invoke-Sqlcmd @common -ServerInstance $Destination -Query "SELECT DB_ID('$dbEsc') AS id"
            if ($exists.id -ne [DBNull]::Value -and "$($exists.id)" -ne '' -and -not $Overwrite) {
                $result.skipped += @{ name=$db; reason='exists on destination (Overwrite=$false)' }
                continue
            }

            # 1. BACKUP on source (compression with graceful fallback).
            $comp = if ($Compression) { ', COMPRESSION' } else { '' }
            $bkpSql = "BACKUP DATABASE [$dbBr] TO DISK = N'$bak' WITH INIT, FORMAT$comp"
            try {
                Invoke-Sqlcmd @common -ServerInstance $Source -Query $bkpSql
            } catch {
                # edition may not support compression -> retry without it
                if ($Compression -and "$($_.Exception.Message)" -match 'compress') {
                    Invoke-Sqlcmd @common -ServerInstance $Source -Query "BACKUP DATABASE [$dbBr] TO DISK = N'$bak' WITH INIT, FORMAT"
                } else { throw }
            }

            # 2. FILELISTONLY -> logical names (never hardcode).
            $files = Invoke-Sqlcmd @common -ServerInstance $Destination -Query "RESTORE FILELISTONLY FROM DISK = N'$bak'"
            $moves = @()
            foreach ($f in @($files)) {
                $logical = "$($f.LogicalName)"
                $logicalEsc = $logical -replace "'","''"
                $ext = if ("$($f.Type)" -eq 'L') { '.ldf' } else { '.mdf' }
                $base = ($logical -replace '[^A-Za-z0-9_]','_')
                $target = if ("$($f.Type)" -eq 'L') { (Join-Path $logPath ($base+'.ldf')) } else { (Join-Path $dataPath ($base+$ext)) }
                $moves += "MOVE N'$logicalEsc' TO N'$target'"
            }
            if (-not $moves.Count) { throw "FILELISTONLY returned no files for $db." }

            # 3. RESTORE on dest with dynamic MOVE.
            $rec     = if ($Recovery) { 'RECOVERY' } else { 'NORECOVERY' }
            $replace = if ($Overwrite) { ', REPLACE' } else { '' }
            $restoreSql = "RESTORE DATABASE [$dbBr] FROM DISK = N'$bak' WITH " + ($moves -join ', ') + ", $rec$replace"
            Invoke-Sqlcmd @common -ServerInstance $Destination -Query $restoreSql

            $result.migrated += @{ name=$db; status='Success'; recovery=$rec }
        }
        catch {
            $result.status = if ($result.status -eq 'ok') { 'partial' } else { $result.status }
            $result.failed += @{ name=$db; error="$($_.Exception.Message)" }
        }
        finally {
            # 4. Cleanup the backup file from the share.
            try { if (Test-Path $bak) { Remove-Item $bak -Force -ErrorAction SilentlyContinue } } catch {}
        }
    }

    if ($result.failed.Count -and $result.migrated.Count) { $result.status = 'partial' }
    elseif ($result.failed.Count -and -not $result.migrated.Count) { $result.status = 'error' }
    $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
    $result.note = "native BACKUP/RESTORE · downtime = migration duration (full-backup cutover). Minimal-downtime log-chain cutover is roadmap."
    return $result
}
