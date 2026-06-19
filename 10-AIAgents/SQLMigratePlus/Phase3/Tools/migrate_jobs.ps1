<#
.SYNOPSIS
    SQLPilot - SQL Agent job migration module (native msdb scripting + dbatools).

.DESCRIPTION
    Migrates SQL Agent jobs from SOURCE to DESTINATION, in either engine.

      dbatools : Copy-DbaAgentJob (handles steps, schedules, owners natively).
      native   : read the job graph from msdb on the SOURCE and regenerate it on
                 the DESTINATION via sp_add_job -> sp_add_jobstep (one per step,
                 in order, preserving on_success/on_fail flow) -> sp_add_jobschedule
                 -> sp_add_jobserver. Pure T-SQL, no dbatools.

    Scope: ALL jobs (both db-list and whole-server). SQL Agent jobs are not owned
    by a database, so "jobs for these databases" is only a heuristic; we migrate
    all jobs, matching dbatools' default behavior. (db-list callers get the same
    full set of jobs.)

    Conflict handling: a job of the same name on the destination is SKIPPED with
    a warning by default (-Overwrite $true drops+recreates).

    DOCUMENTED LIMITATIONS (honest framing):
      - Job OWNER is mapped by login name; that login must already exist on the
        destination (migrate logins first). If absent, the job is created owned
        by the connecting principal and flagged.
      - Steps that use PROXIES / CREDENTIALS or subsystems like SSIS/CmdExec/
        PowerShell require the proxy + credential to exist on the destination.
        Native mode recreates the step definition but cannot create the proxy's
        underlying credential secret - flagged as a post-migration manual step.
      - Native focuses on the common job shape (TSQL / CmdExec steps, standard
        schedules). Exotic constructs (alerts, notifications to operators,
        complex schedule recurrences) are best-effort.

.NOTES
    Author : Kale
    Pattern: mirrors migrate_tde.ps1 / migrate_databases.ps1 (DC->DC style:
             connect to destination by name, Windows auth). server.ps1
             dot-sources this; the orchestrator calls Invoke-MigrateAgentJobs.
#>

# ---------------------------------------------------------------------------
# Invoke-MigrateAgentJobs
#   -Source / -Destination  SQL instances
#   -Engine                 'dbatools' | 'native'
#   -Overwrite              $false (default) => skip existing jobs;
#                           $true => drop + recreate
#   Returns: @{ status; engine; source; destination; migrated[]; skipped[];
#               failed[]; warnings[]; elapsed_seconds; note }
# ---------------------------------------------------------------------------
function Invoke-MigrateAgentJobs {
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
        try {
            $cpArgs = @{ Source=$Source; Destination=$Destination; ErrorAction='Stop' }
            if ($Overwrite) { $cpArgs['Force'] = $true }
            $cj = Copy-DbaAgentJob @cpArgs 2>&1
            foreach ($j in @($cj)) {
                $e = @{ name="$($j.Name)"; status="$($j.Status)"; notes="$($j.Notes)" }
                if ("$($j.Status)" -match 'Success') { $result.migrated += $e }
                elseif ("$($j.Status)" -match 'Skip') { $result.skipped += $e }
                else { $result.failed += $e }
            }
        } catch { $result.status='error'; $result.error="$($_.Exception.Message)" }
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        return $result
    }

    # =====================================================================
    # native engine - script jobs from msdb, regenerate on destination
    # =====================================================================

    # 1. Enumerate user jobs on the source (exclude nothing by default;
    #    callers can extend). Pull the fields we need to recreate.
    $jobsQ = @"
SELECT j.job_id, j.name, j.enabled, j.description,
       SUSER_SNAME(j.owner_sid) AS owner_name,
       ISNULL(c.name, 'Database Maintenance') AS category
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
ORDER BY j.name;
"@
    try { $jobs = @(Invoke-Sqlcmd @common -ServerInstance $Source -Query $jobsQ) }
    catch { $result.status='error'; $result.error="Could not read jobs from source msdb: $($_.Exception.Message)"; return $result }

    if (-not $jobs.Count) {
        $result.note = 'No Agent jobs found on source.'
        $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
        return $result
    }

    foreach ($job in $jobs) {
        $jobName = "$($job.name)"
        $nmeEsc  = $jobName -replace "'","''"
        try {
            # 1a. Existing-job conflict check on destination.
            $existsQ = "SELECT COUNT(*) AS n FROM msdb.dbo.sysjobs WHERE name = N'$nmeEsc'"
            $ex = Invoke-Sqlcmd @common -ServerInstance $Destination -Query $existsQ
            if ([int]$ex.n -gt 0) {
                if (-not $Overwrite) { $result.skipped += @{ name=$jobName; reason='exists on destination' }; continue }
                Invoke-Sqlcmd @common -ServerInstance $Destination -Query "EXEC msdb.dbo.sp_delete_job @job_name = N'$nmeEsc';"
            }

            # 1b. Owner: verify it exists on destination, else fall back + warn.
            $ownerName = "$($job.owner_name)"
            $ownerEsc  = $ownerName -replace "'","''"
            $ownerOk = $false
            if ($ownerName) {
                $oq = Invoke-Sqlcmd @common -ServerInstance $Destination -Query "SELECT COUNT(*) AS n FROM sys.server_principals WHERE name = N'$ownerEsc'"
                $ownerOk = ([int]$oq.n -gt 0)
            }
            if (-not $ownerOk -and $ownerName) {
                $result.warnings += @{ job=$jobName; warning="Owner login '$ownerName' not found on destination; job created under connecting principal. Migrate logins first." }
            }

            # 2. Read the steps (ordered) from source.
            $stepsQ = @"
SELECT step_id, step_name, subsystem, command, database_name,
       on_success_action, on_success_step_id, on_fail_action, on_fail_step_id,
       ISNULL(proxy_id,0) AS proxy_id
FROM msdb.dbo.sysjobsteps
WHERE job_id = '$($job.job_id)'
ORDER BY step_id;
"@
            $steps = @(Invoke-Sqlcmd @common -ServerInstance $Source -Query $stepsQ)

            # 3. Read schedules attached to this job.
            $schQ = @"
SELECT s.name AS sched_name, s.enabled, s.freq_type, s.freq_interval,
       s.freq_subday_type, s.freq_subday_interval, s.freq_relative_interval,
       s.freq_recurrence_factor, s.active_start_date, s.active_end_date,
       s.active_start_time, s.active_end_time
FROM msdb.dbo.sysjobschedules js
JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
WHERE js.job_id = '$($job.job_id)';
"@
            $scheds = @(Invoke-Sqlcmd @common -ServerInstance $Source -Query $schQ)

            # 4. Build the recreate script on the destination.
            $en   = if ([int]$job.enabled -eq 1) { 1 } else { 0 }
            $desc = ("$($job.description)") -replace "'","''"
            $cat  = ("$($job.category)") -replace "'","''"
            $ownerClause = if ($ownerOk) { ", @owner_login_name = N'$ownerEsc'" } else { '' }

            $sb = New-Object System.Text.StringBuilder
            [void]$sb.AppendLine("USE msdb;")
            [void]$sb.AppendLine("EXEC dbo.sp_add_job @job_name = N'$nmeEsc', @enabled = $en, @description = N'$desc'$ownerClause;")

            foreach ($st in $steps) {
                $sname = ("$($st.step_name)") -replace "'","''"
                $subsys= ("$($st.subsystem)") -replace "'","''"
                $cmd   = ("$($st.command)") -replace "'","''"
                $dbn   = ("$($st.database_name)") -replace "'","''"
                $osa   = [int]$st.on_success_action; $oss = [int]$st.on_success_step_id
                $ofa   = [int]$st.on_fail_action;    $ofs = [int]$st.on_fail_step_id
                $dbClause = if ($subsys -eq 'TSQL' -and $dbn) { ", @database_name = N'$dbn'" } else { '' }
                if ([int]$st.proxy_id -gt 0) {
                    $result.warnings += @{ job=$jobName; warning="Step '$($st.step_name)' uses a proxy (proxy_id $($st.proxy_id)); the proxy + its credential must exist on the destination." }
                }
                [void]$sb.AppendLine("EXEC dbo.sp_add_jobstep @job_name = N'$nmeEsc', @step_id = $([int]$st.step_id), @step_name = N'$sname', @subsystem = N'$subsys', @command = N'$cmd'$dbClause, @on_success_action = $osa, @on_success_step_id = $oss, @on_fail_action = $ofa, @on_fail_step_id = $ofs;")
            }

            foreach ($sc in $scheds) {
                $scn = ("$($sc.sched_name)") -replace "'","''"
                [void]$sb.AppendLine("EXEC dbo.sp_add_jobschedule @job_name = N'$nmeEsc', @name = N'$scn', @enabled = $([int]$sc.enabled), @freq_type = $([int]$sc.freq_type), @freq_interval = $([int]$sc.freq_interval), @freq_subday_type = $([int]$sc.freq_subday_type), @freq_subday_interval = $([int]$sc.freq_subday_interval), @freq_relative_interval = $([int]$sc.freq_relative_interval), @freq_recurrence_factor = $([int]$sc.freq_recurrence_factor), @active_start_date = $([int]$sc.active_start_date), @active_end_date = $([int]$sc.active_end_date), @active_start_time = $([int]$sc.active_start_time), @active_end_time = $([int]$sc.active_end_time);")
            }

            # Associate with the local Agent so it runs on the destination.
            [void]$sb.AppendLine("EXEC dbo.sp_add_jobserver @job_name = N'$nmeEsc', @server_name = N'(LOCAL)';")

            # BUG-015 fix: -DisableVariables prevents Invoke-Sqlcmd from
            # parsing $(...) tokens like Ola Hallengren's $(ESCAPE_SQUOTE(...))
            # as SQLCMD variables. Those tokens are meant for SQL Agent's
            # CmdExec subsystem, not for the sqlcmd parser.
            Invoke-Sqlcmd @common -ServerInstance $Destination -Query $sb.ToString() -DisableVariables
            $result.migrated += @{ name=$jobName; steps=$steps.Count; schedules=$scheds.Count; owner_mapped=$ownerOk }
        }
        catch {
            $result.failed += @{ name=$jobName; error="$($_.Exception.Message)" }
        }
    }

    if ($result.failed.Count -and $result.migrated.Count) { $result.status='partial' }
    elseif ($result.failed.Count -and -not $result.migrated.Count) { $result.status='error' }
    $result.elapsed_seconds = [int]((Get-Date)-$started).TotalSeconds
    $result.note = "native msdb scripting · $($result.migrated.Count) job(s) migrated. Proxy/credential-based steps need the proxy on the destination (see warnings)."
    return $result
}
