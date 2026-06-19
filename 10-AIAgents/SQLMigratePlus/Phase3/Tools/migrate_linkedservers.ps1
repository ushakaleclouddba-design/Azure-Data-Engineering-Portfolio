<#
.SYNOPSIS
    SQLPilot - Linked server migration module (native sp_addlinkedserver + dbatools).

.DESCRIPTION
    Migrates linked server definitions from SOURCE to DESTINATION, either engine.

      dbatools : Copy-DbaLinkedServer.
      native   : read sys.servers (is_linked = 1) + sys.linked_logins on the
                 source, recreate via sp_addlinkedserver (+ sp_addlinkedsrvlogin
                 for the login mappings). Pure T-SQL, no dbatools.

    Scope: all linked servers, EXCLUDING the loopback entry (server_id = 0, the
    instance's own name). Skip-existing by default.

    DOCUMENTED LIMITATION (honest framing - and this is a SQL Server limit, not
    a SQLPilot one): SQL Server does NOT expose the stored REMOTE PASSWORD for a
    linked-server login (it's encrypted and unreadable even to sysadmin). So we
    recreate the linked-server DEFINITION and the login-MAPPING structure, but
    the remote password must be RE-ENTERED on the destination afterward. The
    result flags every linked server that has a credential mapping needing a
    manual password. (dbatools has the same limitation.)

.NOTES
    Author : Kale
    Pattern: mirrors migrate_tde.ps1 / migrate_databases.ps1 / migrate_jobs.ps1.
             server.ps1 dot-sources this; the orchestrator calls
             Invoke-MigrateLinkedServers.
#>

# ---------------------------------------------------------------------------
# Invoke-MigrateLinkedServers
#   -Source / -Destination  SQL instances
#   -Engine                 'dbatools' | 'native'
#   -Overwrite              $false (default) => skip existing; $true => drop+recreate
#   Returns: @{ status; engine; source; destination; migrated[]; skipped[];
#               failed[]; warnings[]; elapsed_seconds; note }
# ---------------------------------------------------------------------------
function Invoke-MigrateLinkedServers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination,
        [ValidateSet('dbatools','native')] [string] $Engine = 'native',
        [bool] $Overwrite = $false
    )

    $started = Get-Date
    $common  = @{ TrustServerCertificate=$true; Encrypt='Optional'; QueryTimeout=0; ErrorAction='Stop' }
    $result  = [ordered]@{
        status='ok'; engine=$Engine; source=$Source; destination=$Destination
        migrated=@(); skipped=@(); failed=@(); warnings=@(); elapsed_seconds=$null; note=$null
    }

    # =====================================================================
    # dbatools engine
    # =====================================================================
    if ($Engine -eq 'dbatools') {
        # BUG-021/023 fix: previously `2>&1` was used to capture warnings into
        # the same stream as objects, which masked silent failures (e.g. a
        # network warning that returned no objects). Now we use a dedicated
        # WarningVariable, and if no objects came back AND warnings fired,
        # we promote to status=error so the UI shows the truth.
        $warns = $null
        try {
            $cpArgs = @{
                Source         = $Source
                Destination    = $Destination
                ErrorAction    = 'Stop'
                WarningAction  = 'SilentlyContinue'
                WarningVariable = 'warns'
            }
            if ($Overwrite) { $cpArgs['Force'] = $true }
            $cls = Copy-DbaLinkedServer @cpArgs
            foreach ($l in @($cls)) {
                $e = @{ name="$($l.Name)"; status="$($l.Status)"; notes="$($l.Notes)" }
                if ("$($l.Status)" -match 'Success') { $result.migrated += $e }
                elseif ("$($l.Status)" -match 'Skip') { $result.skipped += $e }
                else { $result.failed += $e }
            }
            # Silent-failure promotion: warnings fired AND nothing came back -> real failure.
            if (-not @($cls).Count -and $warns) {
                $result.status = 'error'
                $result.error  = 'Copy-DbaLinkedServer emitted warnings with no result: ' + (($warns | ForEach-Object { "$_" }) -join ' | ')
            }
            if ($warns) {
                foreach ($w in $warns) { $result.warnings += @{ warning = "$w" } }
            }
            $result.warnings += @{ warning='Linked-server remote passwords are not migrated by dbatools either (SQL limitation); re-enter them on the destination.' }
        } catch {
            $result.status='error'
            $result.error="$($_.Exception.Message)"
        }
        if ($result.failed.Count -and $result.status -eq 'ok') { $result.status='partial' }
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        return $result
    }

    # =====================================================================
    # native engine - sys.servers -> sp_addlinkedserver
    # =====================================================================

    # 1. Read linked servers from source (exclude the loopback, server_id 0).
    $lsQ = @"
SELECT s.server_id, s.name, s.product, s.provider, s.data_source,
       s.location, s.provider_string, s.catalog,
       s.is_data_access_enabled, s.is_rpc_out_enabled
FROM sys.servers s
WHERE s.is_linked = 1
ORDER BY s.name;
"@
    try { $links = @(Invoke-Sqlcmd @common -ServerInstance $Source -Query $lsQ) }
    catch { $result.status='error'; $result.error="Could not read linked servers from source: $($_.Exception.Message)"; return $result }

    if (-not $links.Count) {
        $result.note = 'No linked servers on source.'
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        return $result
    }

    foreach ($ls in $links) {
        $lname   = "$($ls.name)"
        $nmeEsc  = $lname -replace "'","''"
        try {
            # 1a. Exists on destination?
            $ex = Invoke-Sqlcmd @common -ServerInstance $Destination -Query "SELECT COUNT(*) AS n FROM sys.servers WHERE is_linked = 1 AND name = N'$nmeEsc'"
            if ([int]$ex.n -gt 0) {
                if (-not $Overwrite) { $result.skipped += @{ name=$lname; reason='exists on destination' }; continue }
                Invoke-Sqlcmd @common -ServerInstance $Destination -Query "EXEC master.dbo.sp_dropserver @server = N'$nmeEsc', @droplogins = 'droplogins';"
            }

            # 2. Build sp_addlinkedserver from the source definition.
            $prod = ("$($ls.product)")        -replace "'","''"
            $prov = ("$($ls.provider)")       -replace "'","''"
            $dsrc = ("$($ls.data_source)")    -replace "'","''"
            $loc  = ("$($ls.location)")       -replace "'","''"
            $pstr = ("$($ls.provider_string)")-replace "'","''"
            $cat  = ("$($ls.catalog)")        -replace "'","''"

            # A SQL Server linked server has product = 'SQL Server' and needs NO
            # provider/datasrc beyond @server. A blank/null product is invalid;
            # treat blank product as a generic OLEDB linked server (needs provider).
            $params = @("@server = N'$nmeEsc'")
            if ([string]::IsNullOrWhiteSpace($prod) -and [string]::IsNullOrWhiteSpace($dsrc) -and [string]::IsNullOrWhiteSpace($prov)) {
                # nothing but a name -> assume SQL Server product
                $params += "@srvproduct = N'SQL Server'"
            }
            elseif ([string]::IsNullOrWhiteSpace($prod)) {
                # generic OLEDB: product must be a non-empty string ('' is allowed
                # ONLY together with @provider + @datasrc), provider+datasrc required
                $params += "@srvproduct = N''"
                if ($prov) { $params += "@provider = N'$prov'" }
                if ($dsrc) { $params += "@datasrc = N'$dsrc'" }
                if ($pstr) { $params += "@provstr = N'$pstr'" }
                if ($cat)  { $params += "@catalog = N'$cat'" }
                if ($loc)  { $params += "@location = N'$loc'" }
            }
            else {
                $params += "@srvproduct = N'$prod'"
                if ($prov) { $params += "@provider = N'$prov'" }
                if ($dsrc) { $params += "@datasrc = N'$dsrc'" }
                if ($loc)  { $params += "@location = N'$loc'" }
                if ($pstr) { $params += "@provstr = N'$pstr'" }
                if ($cat)  { $params += "@catalog = N'$cat'" }
            }
            $addSql = "EXEC master.dbo.sp_addlinkedserver " + ($params -join ', ') + ";"

            # 3. Data-access / RPC options to match the source.
            $optSql = @"
EXEC master.dbo.sp_serveroption @server = N'$nmeEsc', @optname = 'data access', @optvalue = '$( if([int]$ls.is_data_access_enabled -eq 1){'true'}else{'false'} )';
EXEC master.dbo.sp_serveroption @server = N'$nmeEsc', @optname = 'rpc out',     @optvalue = '$( if([int]$ls.is_rpc_out_enabled -eq 1){'true'}else{'false'} )';
"@

            Invoke-Sqlcmd @common -ServerInstance $Destination -Query ($addSql + "`n" + $optSql)

            # 4. Recreate login mappings (definition only - passwords cannot migrate).
            $llQ = @"
SELECT ll.uses_self_credential, ll.remote_name,
       SUSER_SNAME(ll.local_principal_id) AS local_login
FROM sys.linked_logins ll
WHERE ll.server_id = $([int]$ls.server_id);
"@
            $mappings = @(Invoke-Sqlcmd @common -ServerInstance $Source -Query $llQ)
            $needsPwd = $false
            foreach ($m in $mappings) {
                $local  = ("$($m.local_login)") -replace "'","''"
                $remote = ("$($m.remote_name)") -replace "'","''"
                if ([int]$m.uses_self_credential -eq 1) {
                    # self-mapping (use the connecting login's own credentials)
                    $lp = if ($local) { "N'$local'" } else { 'NULL' }
                    Invoke-Sqlcmd @common -ServerInstance $Destination -Query "EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$nmeEsc', @useself = 'true', @locallogin = $lp;"
                }
                elseif ($remote) {
                    # remote-credential mapping: recreate the mapping WITHOUT the
                    # password (SQL won't expose it) - flag for manual re-entry.
                    $lp = if ($local) { "N'$local'" } else { 'NULL' }
                    Invoke-Sqlcmd @common -ServerInstance $Destination -Query "EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$nmeEsc', @useself = 'false', @locallogin = $lp, @rmtuser = N'$remote', @rmtpassword = N'__SET_ON_DESTINATION__';"
                    $needsPwd = $true
                }
            }
            if ($needsPwd) {
                $result.warnings += @{ linked_server=$lname; warning="Remote-credential login mapping recreated WITHOUT password (SQL cannot export it). Re-set the password on the destination: sp_addlinkedsrvlogin ... @rmtpassword=N'<real>'." }
            }

            $result.migrated += @{ name=$lname; product=$prod; data_source=$dsrc; login_mappings=$mappings.Count; password_reentry_needed=$needsPwd }
        }
        catch {
            $result.failed += @{ name=$lname; error="$($_.Exception.Message)" }
        }
    }

    if ($result.failed.Count -and $result.migrated.Count) { $result.status='partial' }
    elseif ($result.failed.Count -and -not $result.migrated.Count) { $result.status='error' }
    $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
    $result.note = "native sp_addlinkedserver · $($result.migrated.Count) linked server(s). Remote passwords are NOT migratable (SQL limitation) - re-enter on destination where flagged."
    return $result
}
