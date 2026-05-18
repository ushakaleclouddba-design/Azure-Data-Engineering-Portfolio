<#
.SYNOPSIS
    SQLPilot UI - local HTTP server.

.DESCRIPTION
    Hosts the SQLPilot single-page UI on http://localhost:8765 and exposes
    JSON endpoints that wrap the existing PowerShell tools.

    Endpoints:
        GET  /                       -> serves index.html
        GET  /api/health             -> liveness ping
        GET  /api/status             -> VM state + IP + deployment info
        GET  /api/assess             -> Phase 1 findings summary
        GET  /api/assess/server      -> per-server detail (?name=NODE5)
        POST /api/assess/run         -> fire Phase 1 wrapper as background job
        GET  /api/assess/status      -> poll a running Phase 1 job (?job_id=...)
        POST /api/assess/upload      -> save a user-provided Phase 1 JSON as the new latest report
        POST /api/assess/upload-raw  -> save an uploaded .rpt file to Inputs\ for later parsing (rejects other formats)
        POST /api/assess/parse-rpt   -> fire wrapper with -InputRpt on a previously-uploaded .rpt
        POST /api/assess/reveal      -> open Windows Explorer with the named report file highlighted
        POST /api/assess/open        -> open the named report file (Notepad for JSON, default app for xlsx, Explorer-reveal otherwise)
        GET  /api/decide             -> Decide cards (?server=NODE5)
        POST /api/terraform          -> { action: plan|apply|destroy }
        POST /api/restore            -> { database, source, target }
        POST /api/validate           -> { database? } - DBCC CHECKDB
        POST /api/handoff            -> { database, source } - generate handoff
        GET  /api/decision-log       -> recent decision log entries
        GET  /api/events             -> SSE live stream

    Single-file, single-user, single-tab demo. No auth, no sessions, no
    persistence beyond what the wrapped tools already do.

.NOTES
    Run:   pwsh .\ui\server.ps1
    Stop:  Ctrl+C
#>

[CmdletBinding()]
param (
    [int]    $Port         = 8765,
    [string] $UiRoot       = $null,
    [switch] $OpenBrowser
)

# ---------------------------------------------------------------------------
# Resolve paths. server.ps1 lives at <project>\ui\server.ps1.
# ---------------------------------------------------------------------------
if (-not $UiRoot) {
    $UiRoot = Split-Path -Parent $PSCommandPath
}
$ProjectRoot  = Split-Path -Parent $UiRoot
$ToolsDir     = Join-Path $ProjectRoot 'tools'
if (-not (Test-Path $ToolsDir)) { $ToolsDir = Join-Path $ProjectRoot 'Tools' }   # Windows is case-insensitive but be explicit
$TerraformDir = Join-Path $ProjectRoot 'Terraform'

# Tools' scripts use $script:ScriptRoot to find Terraform/. Set it so they work.
$script:ScriptRoot = $ProjectRoot

Write-Host ''
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host '  SQLPilot UI Server' -ForegroundColor Cyan
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host "  Project    : $ProjectRoot"
Write-Host "  UI root    : $UiRoot"
Write-Host "  Tools dir  : $ToolsDir"
Write-Host "  Terraform  : $TerraformDir"
Write-Host "  Assess dir : C:\SQLPilot\Assessment"
Write-Host "  Wrapper    : C:\SQLPilot\Assessment\Generate_Assessment_Report.ps1"
Write-Host "  Listening  : http://localhost:$Port/"
Write-Host ''

# ---------------------------------------------------------------------------
# Dot-source the tool implementations. Each tool defines Invoke-Real* and
# possibly helper functions. If any file is missing, the endpoint that
# depends on it returns a clear error - the UI is meant to run with the
# real backend.
# ---------------------------------------------------------------------------
foreach ($name in 'kb.ps1','Phase1.ps1','restore.ps1','terraform.ps1','day2.ps1','decide.ps1','handoff.ps1') {
    $p = Join-Path $ToolsDir $name
    if (Test-Path $p) {
        . $p
        Write-Host "  [+] $name" -ForegroundColor DarkGray
    } else {
        Write-Host "  [!] missing: $name" -ForegroundColor DarkYellow
    }
}
Write-Host ''


# ---------------------------------------------------------------------------
# Event channel for Server-Sent Events. Single shared in-memory list; the
# /api/events endpoint tails it. Good enough for one demo user, one tab.
# ---------------------------------------------------------------------------
$script:EventLog = New-Object System.Collections.Generic.List[string]
function Publish-UiEvent {
    param([string]$Type, [hashtable]$Payload)
    $entry = @{
        ts      = (Get-Date).ToString('o')
        type    = $Type
        payload = $Payload
    } | ConvertTo-Json -Depth 8 -Compress
    [void]$script:EventLog.Add($entry)
    if ($script:EventLog.Count -gt 1000) {
        $script:EventLog.RemoveRange(0, $script:EventLog.Count - 1000)
    }
}


# ---------------------------------------------------------------------------
# Response helpers.
# ---------------------------------------------------------------------------
function Send-Json {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [object]$Body,
        [int]$StatusCode = 200
    )
    $json = $Body | ConvertTo-Json -Depth 12
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.Headers.Add('Cache-Control','no-store')
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Read-JsonBody {
    param([System.Net.HttpListenerRequest]$Request)
    if (-not $Request.HasEntityBody) { return $null }
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    $text   = $reader.ReadToEnd()
    $reader.Close()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        $obj = $text | ConvertFrom-Json
        $ht = @{}
        foreach ($p in $obj.PSObject.Properties) { $ht[$p.Name] = $p.Value }
        return $ht
    } catch {
        return $null
    }
}

function Send-StaticFile {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$RelativePath
    )
    $clean = $RelativePath.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = 'index.html' }
    $full = Join-Path $UiRoot $clean

    if (-not (Test-Path $full -PathType Leaf)) {
        Send-Json -Response $Response -StatusCode 404 -Body @{ error = "not found: $clean" }
        return
    }
    $bytes = [System.IO.File]::ReadAllBytes($full)
    $ext = [System.IO.Path]::GetExtension($full).ToLower()
    $mime = switch ($ext) {
        '.html' { 'text/html; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.svg'  { 'image/svg+xml' }
        '.png'  { 'image/png' }
        '.ico'  { 'image/x-icon' }
        default { 'application/octet-stream' }
    }
    $Response.ContentType = $mime
    $Response.Headers.Add('Cache-Control','no-store')
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Send-EventStream {
    param([System.Net.HttpListenerResponse]$Response)
    $Response.ContentType = 'text/event-stream'
    $Response.Headers.Add('Cache-Control','no-cache')
    $Response.Headers.Add('Connection','keep-alive')
    $Response.SendChunked = $true

    $writer = New-Object System.IO.StreamWriter($Response.OutputStream, [System.Text.Encoding]::UTF8)
    $writer.AutoFlush = $true

    try {
        $writer.WriteLine("event: hello")
        $writer.WriteLine("data: connected")
        $writer.WriteLine("")
        $i = 0
        # Replay backlog
        while ($i -lt $script:EventLog.Count) {
            $writer.WriteLine("data: $($script:EventLog[$i])")
            $writer.WriteLine("")
            $i++
        }
        # Live tail
        while ($true) {
            while ($i -lt $script:EventLog.Count) {
                $writer.WriteLine("data: $($script:EventLog[$i])")
                $writer.WriteLine("")
                $i++
            }
            Start-Sleep -Milliseconds 250
        }
    } catch {
        # Client disconnected - normal
    } finally {
        try { $writer.Close() } catch {}
    }
}


# ---------------------------------------------------------------------------
# Helper: locate the latest Phase 1 JSON (same logic as decide.ps1).
# ---------------------------------------------------------------------------
# Search order, newest-wins:
#   1. <assessment dir>\reports\   ← new home of all wrapper outputs (live + upload)
#   2. <assessment dir>\           ← legacy: outputs from runs predating the reports\ refactor
#   3. <project root>              ← legacy fallback for very old runs
# We collect from every existing location and return whichever has the newest
# LastWriteTime, so a pre-existing root-level JSON doesn't shadow a fresh
# reports\ run.
function Get-LatestPhase1Json {
    $assessmentRoot = 'C:\SQLPilot\Assessment'
    $reportsRoot    = Join-Path $assessmentRoot 'Reports'

    # Per-run subfolders under Reports\ (the new layout) — recurse to find all JSON.
    # Also include legacy flat-dir JSON at the Assessment root for backward compatibility
    # with older deployments (Wed PM build wrote everything flat).
    $allMatches = @()
    if (Test-Path $reportsRoot) {
        $files = Get-ChildItem -Path $reportsRoot -Recurse -Filter 'Migration_Assessment_Report_*.json' -ErrorAction SilentlyContinue
        if ($files) { $allMatches += $files }
    }
    if (Test-Path $assessmentRoot) {
        $files = Get-ChildItem -Path $assessmentRoot -Filter 'Migration_Assessment_Report_*.json' -ErrorAction SilentlyContinue
        if ($files) { $allMatches += $files }
    }
    # Last-resort fallback: project root (rare; legacy)
    if ($ProjectRoot -and (Test-Path $ProjectRoot)) {
        $files = Get-ChildItem -Path $ProjectRoot -Filter 'Migration_Assessment_Report_*.json' -ErrorAction SilentlyContinue
        if ($files) { $allMatches += $files }
    }
    if ($allMatches.Count -eq 0) { return $null }
    return ($allMatches | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

# Find a named file (e.g. a JSON or XLSX whose bare name the UI gave us) anywhere
# under Reports\ subdirs OR flat in the Assessment root. Returns FileInfo or $null.
# Used by /api/assess/open and /api/assess/reveal so click-to-open keeps working
# regardless of whether the file is in a per-run subfolder or the legacy flat dir.
function Find-AssessmentFile {
    param([Parameter(Mandatory)] [string] $Name)
    $bare = [System.IO.Path]::GetFileName($Name)
    if ([string]::IsNullOrWhiteSpace($bare)) { return $null }
    $assessmentRoot = 'C:\SQLPilot\Assessment'
    $reportsRoot    = Join-Path $assessmentRoot 'Reports'
    $inputsRoot     = Join-Path $assessmentRoot 'Inputs'
    # Per-run subfolders under Reports\ and Inputs\.
    # NOTE: Do NOT use -Filter for exact-name lookup. -Filter delegates to
    # the Win32 FindFirstFile API, which matches against BOTH long names and
    # 8.3 short names. For our filename pattern
    # (Migration_Assessment_Report_<date>_<time>.<ext>) the .json and .xlsx
    # in the same folder can collide on a short name like MIGRAT~1, causing
    # a request for the .xlsx to return the .json (or vice versa).
    # Use -ieq on the long name only, prefer the most recent match.
    $searchRoots = @($reportsRoot, $inputsRoot) | Where-Object { Test-Path $_ }
    if ($searchRoots) {
        $hit = Get-ChildItem -Path $searchRoots -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $bare } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($hit) { return $hit }
    }
    # Legacy flat dir
    $flat = Join-Path $assessmentRoot $bare
    if (Test-Path -Path $flat -PathType Leaf) { return Get-Item -Path $flat }
    return $null
}

# Build a new per-run output folder name: {yyyy-MM-dd_HHmm}_{target}
# where target is the SQL instance, CMS group, or "uploaded". Used by /api/assess/run
# and the upload endpoints to organize outputs.
function New-RunFolderName {
    param(
        [string] $Target = 'uploaded',
        [datetime] $When = (Get-Date)
    )
    $ts = $When.ToString('yyyy-MM-dd_HHmm')
    # Sanitize target: only letters, digits, underscore, dash
    $clean = ($Target -replace '[^A-Za-z0-9_\-]', '')
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = 'unknown' }
    return "${ts}_${clean}"
}


# ---------------------------------------------------------------------------
# Route handlers.
# ---------------------------------------------------------------------------
function Invoke-Route {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response
    )

    $method = $Request.HttpMethod.ToUpper()
    $path   = $Request.Url.AbsolutePath.TrimEnd('/')
    if ($path -eq '') { $path = '/' }

    Write-Host "[$method] $path" -ForegroundColor DarkGray

    # ---- Static index ----
    if ($method -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
        Send-StaticFile -Response $Response -RelativePath 'index.html'
        return
    }

    # ---- Health ----
    if ($method -eq 'GET' -and $path -eq '/api/health') {
        Send-Json -Response $Response -Body @{ status = 'ok'; ts = (Get-Date).ToString('o') }
        return
    }

    # ---- Status ----
    if ($method -eq 'GET' -and $path -eq '/api/status') {
        $body = @{ vm_state = 'unknown'; public_ip = $null; deployment = $null }
        try {
            $stateMarker = Join-Path $TerraformDir '.terraform'
            if (Test-Path $stateMarker) {
                $tfJson = & terraform -chdir="$TerraformDir" output -json 2>$null
                if ($LASTEXITCODE -eq 0 -and $tfJson -and $tfJson -ne '{}') {
                    $tf = $tfJson | ConvertFrom-Json
                    if ($tf.public_ip_address -and $tf.public_ip_address.value) {
                        $body.vm_state = 'running'
                        $body.public_ip = $tf.public_ip_address.value
                        $body.deployment = $tf.sqlpilot_deployment.value
                    } else {
                        $body.vm_state = 'destroyed'
                    }
                } else {
                    $body.vm_state = 'destroyed'
                }
            } else {
                $body.vm_state = 'uninitialized'
            }
        } catch {
            $body.error = $_.Exception.Message
        }
        Send-Json -Response $Response -Body $body
        return
    }

    # ---- Assess: overall ----
    if ($method -eq 'GET' -and $path -eq '/api/assess') {
        $latest = Get-LatestPhase1Json
        if (-not $latest) {
            # No JSON yet — return graceful empty state so the UI can show "Run assessment" CTA.
            Send-Json -Response $Response -Body @{
                has_data = $false
                note     = "No Phase 1 assessment has been run yet."
            }
            return
        }
        $data = Get-Content $latest.FullName -Raw | ConvertFrom-Json

        $perServer = @()
        $totalHigh = 0; $totalMed = 0
        foreach ($srv in $data.servers.PSObject.Properties) {
            $sHigh = 0; $sMed = 0
            foreach ($sectionLabel in @('06_DB_Level_Findings','07_TSQL_Code_Scan','08_SKU_Features')) {
                $section = $srv.Value.$sectionLabel
                if ($section) {
                    foreach ($row in @($section)) {
                        $sev = "$($row.Severity)".ToLower()
                        if ($sev -match 'high')        { $sHigh++ }
                        elseif ($sev -match 'medium')  { $sMed++ }
                    }
                }
            }
            $totalHigh += $sHigh
            $totalMed  += $sMed

            # Database list for this server. The Phase 1 wrapper writes user DBs
            # to 05_Database_Inventory with DatabaseName + State per row. We surface
            # both so the UI can grey out non-ONLINE DBs in the picker.
            $dbs = @()
            $inv = $srv.Value.'05_Database_Inventory'
            if ($inv) {
                foreach ($row in @($inv)) {
                    $dbName  = "$($row.DatabaseName)"
                    $dbState = "$($row.State)"
                    if ($dbName) {
                        $dbs += @{ name = $dbName; state = $dbState }
                    }
                }
            }

            $perServer += @{
                name      = $srv.Name
                high      = $sHigh
                medium    = $sMed
                databases = $dbs
            }
        }

        # Look for an XLSX to surface in the "Excel Report" card. Priority:
        #   1. Matching pair: same base name as the latest JSON, swap extension.
        #      The Phase 1 wrapper produces these together in the same folder.
        #   2. Fallback: most recent *_uploaded_*.xlsx in the same folder as the JSON.
        #      (User uploaded an Excel file; we couldn't parse it, but they can still
        #      open it from the UI.)
        $xlsxName = $null
        $latestDir = $latest.DirectoryName
        $matchingXlsx = [System.IO.Path]::ChangeExtension($latest.Name, '.xlsx')
        $matchingPath = Join-Path $latestDir $matchingXlsx
        if (Test-Path -Path $matchingPath -PathType Leaf) {
            $xlsxName = $matchingXlsx
        } else {
            $uploadedXlsx = Get-ChildItem -Path $latestDir -Filter '*_uploaded_*.xlsx' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($uploadedXlsx) {
                $xlsxName = $uploadedXlsx.Name
            }
        }

        Send-Json -Response $Response -Body @{
            has_data        = $true
            source_file     = $latest.Name
            source_xlsx     = $xlsxName
            generated_at    = $data.metadata.generated_at
            file_mtime      = $latest.LastWriteTime.ToString('o')
            server_count    = $perServer.Count
            high_findings   = $totalHigh
            medium_findings = $totalMed
            per_server      = $perServer
        }
        return
    }

    # ---- Assess: run new Phase 1 ----
    # POST /api/assess/run
    # Body (all optional):
    #   { server_name?: "Node5", cms_group?: "EstateGroup", wrapper_path?: "C:\..\Generate_Assessment_Report.ps1" }
    #
    # Fires the original wrapper in a background job, passing -SqlInstanceOverride
    # and -CmsGroupOverride to redirect it at the requested server / CMS group.
    # The wrapper file is never copied or modified — overrides are parameters,
    # not file rewrites, so the .sql script next to the wrapper is reachable.
    if ($method -eq 'POST' -and $path -eq '/api/assess/run') {
        $argsBody = Read-JsonBody -Request $Request
        $wrapperPath = if ($argsBody -and $argsBody.wrapper_path) {
            $argsBody.wrapper_path
        } else {
            'C:\SQLPilot\Assessment\Generate_Assessment_Report.ps1'
        }
        if (-not (Test-Path $wrapperPath)) {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status = 'error'
                error  = "Phase 1 wrapper not found at: $wrapperPath"
            }
            return
        }

        # Capture the pre-run latest JSON timestamp so we can detect when a NEW JSON appears.
        $preRunLatest = Get-LatestPhase1Json
        $preRunMtime  = if ($preRunLatest) { $preRunLatest.LastWriteTime } else { [DateTime]::MinValue }

        $jobId   = [Guid]::NewGuid().ToString('N').Substring(0,8)
        $logFile = Join-Path $env:TEMP "sqlpilot_assess_$jobId.log"

        $serverName = $null
        $cmsGroup   = $null
        if ($argsBody) {
            if ($argsBody.server_name) { $serverName = "$($argsBody.server_name)".Trim() }
            if ($argsBody.cms_group)   { $cmsGroup   = "$($argsBody.cms_group)".Trim() }
        }

        # Determine the per-run output folder name from what we know about the run.
        # Format: {yyyy-MM-dd_HHmm}_{target}  where target is the SQL instance, the
        # CMS group name, or "uploaded" for upload paths. Always sortable, always
        # tagged with what produced it.
        $runTarget = if ($cmsGroup) { $cmsGroup }
                     elseif ($serverName) { $serverName }
                     else { 'run' }
        $runFolderName = New-RunFolderName -Target $runTarget
        $runOutputDir  = Join-Path 'C:\SQLPilot\Assessment\Reports' $runFolderName
        try {
            if (-not (Test-Path $runOutputDir)) {
                New-Item -ItemType Directory -Path $runOutputDir -Force | Out-Null
            }
        } catch {
            Write-Host "[WARN] Could not pre-create per-run dir '$runOutputDir': $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Build the argument list. The wrapper accepts -SqlInstanceOverride,
        # -CmsGroupOverride, and -OutputDir as parameters; the first two are
        # no-ops when empty, so we only pass them when we have non-empty values.
        # -OutputDir tells the wrapper where to drop its JSON+XLSX so per-run
        # folders are populated atomically (no post-run file moves needed).
        $argsList = @(
            '-NoProfile','-ExecutionPolicy','Bypass',
            '-File',$wrapperPath
        )
        if ($serverName) { $argsList += @('-SqlInstanceOverride', $serverName) }
        if ($cmsGroup)   { $argsList += @('-CmsGroupOverride',    $cmsGroup) }
        $argsList += @('-OutputDir', $runOutputDir)

        # Quote each list element, escape embedded single quotes by doubling.
        $startArgs = ($argsList | ForEach-Object {
            "'" + ($_ -replace "'", "''") + "'"
        }) -join ','
        $startInfo = "Start-Process -FilePath pwsh -ArgumentList $startArgs -RedirectStandardOutput '$logFile' -RedirectStandardError '$logFile.err' -WindowStyle Hidden -PassThru"
        $proc = Invoke-Expression $startInfo

        # Track in script state so /api/assess/status can answer.
        if (-not $script:AssessJobs) { $script:AssessJobs = @{} }
        $script:AssessJobs[$jobId] = @{
            job_id        = $jobId
            pid           = $proc.Id
            started_at    = (Get-Date).ToString('o')
            wrapper_path  = $wrapperPath
            server_name   = $serverName
            cms_group     = $cmsGroup
            pre_run_mtime = $preRunMtime
            log_file      = $logFile
            status        = 'running'
        }

        Publish-UiEvent -Type 'assess_start' -Payload @{
            job_id      = $jobId
            server_name = $serverName
            cms_group   = $cmsGroup
        }

        Send-Json -Response $Response -Body @{
            status      = 'started'
            job_id      = $jobId
            server_name = $serverName
            cms_group   = $cmsGroup
            note        = "Phase 1 wrapper is running. Poll /api/assess/status?job_id=$jobId for progress. Expected duration: 3-5 minutes per server."
            estimate_seconds = 300
        }
        return
    }

    # ---- Assess: status of a running Phase 1 job ----
    if ($method -eq 'GET' -and $path -eq '/api/assess/status') {
        $jobId = $Request.QueryString['job_id']
        if (-not $jobId -or -not $script:AssessJobs -or -not $script:AssessJobs.ContainsKey($jobId)) {
            Send-Json -Response $Response -StatusCode 404 -Body @{ error = "Unknown job_id" }
            return
        }
        $job = $script:AssessJobs[$jobId]

        # Check if the PID is still running.
        $procStillRunning = $false
        try {
            $p = Get-Process -Id $job.pid -ErrorAction SilentlyContinue
            if ($p) { $procStillRunning = $true }
        } catch {}

        # Check if a NEW JSON has appeared since the job started.
        $latestNow = Get-LatestPhase1Json
        $hasNewJson = $false
        if ($latestNow -and $latestNow.LastWriteTime -gt $job.pre_run_mtime) {
            $hasNewJson = $true
        }

        if ($hasNewJson) {
            $job.status = 'done'
        } elseif (-not $procStillRunning) {
            # Process exited without producing a new JSON — likely failed.
            $job.status = 'failed'
        }

        # Read recent log lines.
        $logTail = @()
        if (Test-Path $job.log_file) {
            $logTail = Get-Content $job.log_file -Tail 8 -ErrorAction SilentlyContinue
        }
        $errTail = @()
        if (Test-Path "$($job.log_file).err") {
            $errTail = Get-Content "$($job.log_file).err" -Tail 4 -ErrorAction SilentlyContinue
        }

        $elapsed = [int]((Get-Date) - ([DateTime]::Parse($job.started_at))).TotalSeconds

        Send-Json -Response $Response -Body @{
            job_id           = $job.job_id
            status           = $job.status
            elapsed_seconds  = $elapsed
            started_at       = $job.started_at
            process_running  = $procStillRunning
            has_new_json     = $hasNewJson
            new_json_file    = if ($hasNewJson) { $latestNow.Name } else { $null }
            log_tail         = $logTail
            error_tail       = $errTail
        }
        return
    }

    # ---- Assess: upload an existing Phase 1 JSON ----
    # POST /api/assess/upload
    # Body: { content: <parsed JSON object>, filename?: "<original filename>" }
    # Validates the body has top-level "metadata" and "servers" keys, then writes the
    # JSON to the assessment directory with a fresh timestamp so /api/assess picks it
    # up as the new latest. Returns the saved filename so the UI can confirm.
    if ($method -eq 'POST' -and $path -eq '/api/assess/upload') {
        $argsBody = Read-JsonBody -Request $Request
        if (-not $argsBody -or -not $argsBody.ContainsKey('content') -or $null -eq $argsBody.content) {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status = 'error'
                error  = "Missing 'content' (parsed JSON object) in request body"
            }
            return
        }
        $content = $argsBody.content

        # Shape validation. ConvertFrom-Json gives us a PSCustomObject — check via PSObject.Properties.
        $propNames = @()
        if ($content.PSObject -and $content.PSObject.Properties) {
            $propNames = @($content.PSObject.Properties | ForEach-Object { $_.Name })
        }
        if ($propNames -notcontains 'metadata' -or $propNames -notcontains 'servers') {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status = 'error'
                error  = "Uploaded JSON must have top-level 'metadata' and 'servers' keys. Got: $($propNames -join ', ')"
            }
            return
        }

        # Target directory — write inside a per-run subfolder under Reports\.
        # Naming: Reports\{yyyy-MM-dd_HHmm}_uploaded\Migration_Assessment_Report_<ts>.json
        # The per-run folder groups the JSON with any sibling xlsx/csv/rpt the
        # recipient might upload in the same minute. /api/assess walks Reports\*\
        # recursively, so files at this depth are picked up as the new latest.
        $assessmentRoot = 'C:\SQLPilot\Assessment'
        $reportsRoot    = Join-Path $assessmentRoot 'Reports'
        $timestamp      = Get-Date -Format 'yyyy-MM-dd_HHmm'
        $runFolderName  = "${timestamp}_uploaded"
        $targetDir      = Join-Path $reportsRoot $runFolderName
        if (-not (Test-Path $targetDir)) {
            try {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            } catch {
                Send-Json -Response $Response -StatusCode 500 -Body @{
                    status = 'error'
                    error  = "Could not create per-run dir '$targetDir': $($_.Exception.Message)"
                }
                return
            }
        }

        # Filename format matches existing Phase 1 wrapper output:
        # Migration_Assessment_Report_<yyyy-MM-dd_HHmm>.json
        $savedName = "Migration_Assessment_Report_$timestamp.json"
        $savedPath = Join-Path $targetDir $savedName

        # If a file with this exact timestamp already exists (two uploads in same minute),
        # append a short suffix so we never silently overwrite.
        if (Test-Path $savedPath) {
            $suffix = [Guid]::NewGuid().ToString('N').Substring(0,4)
            $savedName = "Migration_Assessment_Report_${timestamp}_$suffix.json"
            $savedPath = Join-Path $targetDir $savedName
        }

        try {
            $json = $content | ConvertTo-Json -Depth 32
            [System.IO.File]::WriteAllText($savedPath, $json, [System.Text.Encoding]::UTF8)
        } catch {
            Send-Json -Response $Response -StatusCode 500 -Body @{
                status = 'error'
                error  = "Failed to write '$savedPath': $($_.Exception.Message)"
            }
            return
        }

        $serverCount = 0
        try { $serverCount = @($content.servers).Count } catch {}

        Publish-UiEvent -Type 'assess_uploaded' -Payload @{
            saved_as     = $savedName
            original     = $argsBody.filename
            server_count = $serverCount
        }

        Send-Json -Response $Response -Body @{
            status         = 'ok'
            saved_as       = $savedName
            saved_path     = $savedPath
            original_name  = $argsBody.filename
            server_count   = $serverCount
            note           = "Uploaded JSON saved. /api/assess will now return this report as the latest."
        }
        return
    }

    # ---- Assess: upload a raw (non-JSON) report file (.xlsx / .csv) ----
    # POST /api/assess/upload-raw
    # Body: { filename: "<original>", content_b64: "<base64-encoded-file-bytes>" }
    # Saves the raw bytes to the assessment directory unchanged. No parsing —
    # Phase 3 will know how to turn vendor Excel/CSV reports into the agent's
    # data model. For v0.9 this is a "we received your file" placeholder so the
    # demo doesn't dead-end when a reviewer drops an Excel report on the picker.
    if ($method -eq 'POST' -and $path -eq '/api/assess/upload-raw') {
        $argsBody = Read-JsonBody -Request $Request
        if (-not $argsBody -or -not $argsBody.ContainsKey('content_b64') -or -not $argsBody.filename) {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status = 'error'
                error  = "Missing 'content_b64' or 'filename' in request body"
            }
            return
        }
        # Accept .rpt only. A client-supplied xlsx/csv/etc. can't carry the
        # 15 data sections that 01_Assessment_Script.sql produces — without
        # those, the analysis pipeline (findings, SKU recs, Cloud Migration
        # Matrix) has nothing to score. Reject early with a clear message.
        $uploadExt = [System.IO.Path]::GetExtension($argsBody.filename).ToLowerInvariant()
        if ($uploadExt -ne '.rpt') {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status = 'error'
                error  = "Only .rpt files are accepted. Got '$uploadExt'. The .rpt is the output of 01_Assessment_Script.sql run via SSMS as a multi-server query — it contains the 15 data sections SQLPilot needs to produce findings, SKU recommendations, and the Cloud Migration Matrix."
            }
            return
        }
        # Per-run subfolder under Inputs\ — raw client-supplied material.
        # Stage A artifacts (.rpt) live here. Stage B outputs (.json + .xlsx,
        # produced by parse-rpt) land in Reports\ as before.
        $assessmentRoot = 'C:\SQLPilot\Assessment'
        $inputsRoot     = Join-Path $assessmentRoot 'Inputs'
        $timestamp      = Get-Date -Format 'yyyy-MM-dd_HHmm'
        $runFolderName  = "${timestamp}_uploaded"
        $targetDir      = Join-Path $inputsRoot $runFolderName
        if (-not (Test-Path $targetDir)) {
            try {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            } catch {
                Send-Json -Response $Response -StatusCode 500 -Body @{
                    status = 'error'
                    error  = "Could not create per-run dir '$targetDir': $($_.Exception.Message)"
                }
                return
            }
        }

        $origName  = [System.IO.Path]::GetFileNameWithoutExtension($argsBody.filename)
        $ext       = [System.IO.Path]::GetExtension($argsBody.filename)
        $savedName = "${origName}_uploaded_${timestamp}${ext}"
        $savedPath = Join-Path $targetDir $savedName

        # If a file with the same name+timestamp already exists, append a suffix.
        if (Test-Path $savedPath) {
            $suffix    = [Guid]::NewGuid().ToString('N').Substring(0,4)
            $savedName = "${origName}_uploaded_${timestamp}_$suffix${ext}"
            $savedPath = Join-Path $targetDir $savedName
        }

        try {
            $bytes = [System.Convert]::FromBase64String($argsBody.content_b64)
            [System.IO.File]::WriteAllBytes($savedPath, $bytes)
        } catch {
            Send-Json -Response $Response -StatusCode 500 -Body @{
                status = 'error'
                error  = "Failed to write file: $($_.Exception.Message)"
            }
            return
        }

        Publish-UiEvent -Type 'assess_uploaded_raw' -Payload @{
            saved_as = $savedName
            original = $argsBody.filename
        }

        Send-Json -Response $Response -Body @{
            status     = 'ok'
            saved_as   = $savedName
            saved_path = $savedPath
            note       = "File saved to Inputs\. Call /api/assess/parse-rpt with this saved_as to run the Phase 1 analysis."
        }
        return
    }

    # ---- Assess: parse a previously-uploaded .rpt (or several) into the full Phase 1 deliverable ----
    # POST /api/assess/parse-rpt
    # Body:
    #   { filename:  "<saved_as>" }                 # single .rpt (back-compat)
    #   { filenames: ["<saved_as>", ...] }          # multiple .rpts — wrapper merges them
    #
    # Fires the Phase 1 wrapper with -InputRpt pointing at every supplied
    # filename. The wrapper parses each .rpt, merges into one $allData, runs
    # the full Stage 1 pipeline (cost calc, Cloud Migration Matrix, AI
    # sections), and writes a Migration_Assessment_Report_FromUpload_<ts>.xlsx
    # + .json that /api/assess will then pick up as the new latest report.
    #
    # Multi-file is the supported way to assess a CMS estate end-to-end: one
    # .rpt is produced by the SSMS multi-server query on the CMS group
    # (containing the 5 members), and a second .rpt by a single-server SSMS
    # query against the CMS host itself (which the CMS group cannot include
    # because a CMS host doesn't register itself in its own group). Together
    # they cover the full estate.
    if ($method -eq 'POST' -and $path -eq '/api/assess/parse-rpt') {
        $argsBody = Read-JsonBody -Request $Request
        if (-not $argsBody) {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status = 'error'
                error  = "Missing request body. Pass { filename } or { filenames: [...] } from /api/assess/upload-raw."
            }
            return
        }

        # Build the filename list: prefer the multi-file 'filenames' field,
        # fall back to single-file 'filename' for back-compat.
        $filenames = @()
        if ($argsBody.filenames) {
            $filenames = @($argsBody.filenames | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        } elseif ($argsBody.filename) {
            $filenames = @("$($argsBody.filename)".Trim())
        }
        if ($filenames.Count -eq 0) {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status = 'error'
                error  = "Empty 'filenames' / no 'filename'. Pass at least one saved_as value from /api/assess/upload-raw."
            }
            return
        }

        # Uploaded .rpt files live in Inputs\<yyyy-MM-dd_HHmm>_uploaded\ subfolders
        # (see /api/assess/upload-raw). Find-AssessmentFile searches both Inputs\
        # and Reports\ so legacy uploads on older deployments still resolve.
        $rptPaths = @()
        foreach ($fn in $filenames) {
            $hit = Find-AssessmentFile -Name $fn
            if (-not $hit) {
                Send-Json -Response $Response -StatusCode 404 -Body @{
                    status = 'error'
                    error  = "Uploaded file not found anywhere under C:\SQLPilot\Assessment\Inputs\ or C:\SQLPilot\Assessment\Reports\ (or legacy paths): $fn. Upload it via /api/assess/upload-raw first."
                }
                return
            }
            $rptPaths += $hit.FullName
        }

        $wrapperPath = if ($argsBody.wrapper_path) {
            $argsBody.wrapper_path
        } else {
            'C:\SQLPilot\Assessment\Generate_Assessment_Report.ps1'
        }
        if (-not (Test-Path $wrapperPath)) {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status = 'error'
                error  = "Phase 1 wrapper not found at: $wrapperPath"
            }
            return
        }

        # Locate rpt-to-datatables.ps1 — primary location is Tools\ alongside
        # the other tool scripts. Fall back to next-to-wrapper (Assessment\)
        # for back-compat with older deployments.
        $parserCandidates = @(
            (Join-Path $ToolsDir 'rpt-to-datatables.ps1'),
            (Join-Path (Split-Path $wrapperPath -Parent) 'rpt-to-datatables.ps1')
        )
        $parserPath = $null
        foreach ($pc in $parserCandidates) {
            if (Test-Path -Path $pc -PathType Leaf) { $parserPath = $pc; break }
        }
        if (-not $parserPath) {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status   = 'error'
                error    = "rpt-to-datatables.ps1 not found"
                looked_in = $parserCandidates -join ' ; '
            }
            return
        }

        # Capture the pre-run latest JSON so /api/assess/status can detect when
        # the new FromUpload JSON drops.
        $preRunLatest = Get-LatestPhase1Json
        $preRunMtime  = if ($preRunLatest) { $preRunLatest.LastWriteTime } else { [DateTime]::MinValue }

        $jobId   = [Guid]::NewGuid().ToString('N').Substring(0,8)
        $logFile = Join-Path $env:TEMP "sqlpilot_parsejob_$jobId.log"

        # Per-run output folder for the parsed result. Names it after the upload
        # time so the JSON+XLSX produced by parsing N .rpts groups under one folder.
        $runFolderName = New-RunFolderName -Target 'parsed_rpt'
        $runOutputDir  = Join-Path 'C:\SQLPilot\Assessment\Reports' $runFolderName
        try {
            if (-not (Test-Path $runOutputDir)) {
                New-Item -ItemType Directory -Path $runOutputDir -Force | Out-Null
            }
        } catch {
            Write-Host "[WARN] Could not pre-create per-run dir '$runOutputDir': $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Build the wrapper argument list. PowerShell's [string[]] parameter
        # binding accepts comma-separated values via Start-Process's ArgumentList
        # when each value is its own array element. We emit:
        #   -InputRpt 'C:\path\one.rpt' 'C:\path\two.rpt' -OutputDir '...'
        # which PS binds as a 2-element array to the wrapper's $InputRpt.
        $argsList = @(
            '-NoProfile','-ExecutionPolicy','Bypass',
            '-File',$wrapperPath,
            '-InputRpt'
        ) + $rptPaths + @('-OutputDir', $runOutputDir)

        # Quote each list element, escape embedded single quotes by doubling.
        $startArgs = ($argsList | ForEach-Object {
            "'" + ($_ -replace "'", "''") + "'"
        }) -join ','
        $startInfo = "Start-Process -FilePath pwsh -ArgumentList $startArgs -RedirectStandardOutput '$logFile' -RedirectStandardError '$logFile.err' -WindowStyle Hidden -PassThru"
        $proc = Invoke-Expression $startInfo

        if (-not $script:AssessJobs) { $script:AssessJobs = @{} }
        $script:AssessJobs[$jobId] = @{
            job_id        = $jobId
            pid           = $proc.Id
            started_at    = (Get-Date).ToString('o')
            wrapper_path  = $wrapperPath
            input_rpts    = $rptPaths
            server_name   = $null
            pre_run_mtime = $preRunMtime
            log_file      = $logFile
            status        = 'running'
            mode          = 'parse_rpt'
        }

        Publish-UiEvent -Type 'parse_rpt_start' -Payload @{
            job_id    = $jobId
            rpts      = $filenames
            rpt_count = $filenames.Count
        }

        Send-Json -Response $Response -Body @{
            status      = 'started'
            job_id      = $jobId
            input_rpts  = $filenames
            rpt_count   = $filenames.Count
            note        = "Wrapper is parsing $($filenames.Count) .rpt file(s) and building the full Phase 1 deliverable. Poll /api/assess/status?job_id=$jobId for progress. Typical runtime: 30-90 seconds."
            estimate_seconds = 60
        }
        return
    }

    # ---- Assess: reveal a generated report file in Windows Explorer ----
    # POST /api/assess/reveal
    # Body: { file: "Migration_Assessment_Report_2026-05-13_1720.json" }
    # Uses Find-AssessmentFile to locate the file anywhere under Reports\* (or legacy
    # flat Assessment\), then runs explorer.exe /select,<full-path> so the user sees
    # it highlighted in Explorer. Safe by design: only files inside the Assessment
    # tree can be opened — no path traversal allowed.
    if ($method -eq 'POST' -and $path -eq '/api/assess/reveal') {
        $argsBody = Read-JsonBody -Request $Request
        if (-not $argsBody -or -not $argsBody.file) {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status = 'error'
                error  = "Missing 'file' in request body"
            }
            return
        }
        $hit = Find-AssessmentFile -Name $argsBody.file
        if (-not $hit) {
            Send-Json -Response $Response -StatusCode 404 -Body @{
                status    = 'error'
                error     = "File not found anywhere under C:\SQLPilot\Assessment\: $($argsBody.file)"
                looked_in = 'C:\SQLPilot\Assessment\Inputs\*  +  C:\SQLPilot\Assessment\Reports\*  +  C:\SQLPilot\Assessment\ (flat)'
            }
            return
        }
        try {
            Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$($hit.FullName)`""
        } catch {
            Send-Json -Response $Response -StatusCode 500 -Body @{
                status = 'error'
                error  = "Failed to launch explorer: $($_.Exception.Message)"
            }
            return
        }
        Send-Json -Response $Response -Body @{
            status = 'ok'
            file   = $hit.Name
            path   = $hit.FullName
            note   = "Explorer opened with file highlighted."
        }
        return
    }

    # ---- Assess: open a generated report file ----
    # POST /api/assess/open
    # Body: { file: "Migration_Assessment_Report_2026-05-13_1720.json"  OR  "...xlsx" }
    # Dispatches by extension:
    #   .json  → opened in Notepad explicitly (works without a registered app)
    #   other  → opened in the default app for the extension (.xlsx → Excel,
    #            .csv → Excel, etc.). Falls back to Explorer-reveal if no
    #            default handler is registered.
    # Safe by design: only files inside the Assessment tree can be opened.
    if ($method -eq 'POST' -and $path -eq '/api/assess/open') {
        $argsBody = Read-JsonBody -Request $Request
        if (-not $argsBody -or -not $argsBody.file) {
            Send-Json -Response $Response -StatusCode 400 -Body @{
                status = 'error'
                error  = "Missing 'file' in request body"
            }
            return
        }
        $hit = Find-AssessmentFile -Name $argsBody.file
        if (-not $hit) {
            Send-Json -Response $Response -StatusCode 404 -Body @{
                status    = 'error'
                error     = "File not found: $($argsBody.file)"
                looked_in = 'C:\SQLPilot\Assessment\Inputs\*  +  C:\SQLPilot\Assessment\Reports\*  +  C:\SQLPilot\Assessment\ (flat)'
            }
            return
        }
        try {
            $ext = [System.IO.Path]::GetExtension($hit.Name).ToLower()
            $openedWith = $null
            if ($ext -eq '.json') {
                # JSON: open in Notepad explicitly. Works on machines with no
                # registered .json handler (common on fresh Server installs).
                Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$($hit.FullName)`""
                $openedWith = 'notepad.exe'
            } else {
                # Non-JSON (.xlsx, .csv, .rpt, .txt): open in the default app
                # registered for the extension (Excel, etc.). If no handler is
                # registered, Windows shows the "Open With" picker — better
                # than dumping the user in Explorer with no further hint.
                try {
                    Start-Process -FilePath "$($hit.FullName)" -ErrorAction Stop
                    $openedWith = "default app for $ext"
                } catch {
                    # Fallback: reveal in Explorer so user can still find it.
                    Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$($hit.FullName)`""
                    $openedWith = 'explorer.exe /select (no default app)'
                }
            }
        } catch {
            Send-Json -Response $Response -StatusCode 500 -Body @{
                status = 'error'
                error  = "Failed to open file: $($_.Exception.Message)"
            }
            return
        }
        Send-Json -Response $Response -Body @{
            status      = 'ok'
            file        = $hit.Name
            path        = $hit.FullName
            opened_with = $openedWith
            note        = "File opened."
        }
        return
    }

    # ---- Decide: per-server cards ----
    if ($method -eq 'GET' -and $path -eq '/api/decide') {
        $server = $Request.QueryString['server']
        if (-not $server) {
            Send-Json -Response $Response -StatusCode 400 -Body @{ error = "Missing 'server' query parameter (e.g. /api/decide?server=NODE5)" }
            return
        }
        $have = Get-Command -Name 'Invoke-RealDecideTarget' -ErrorAction SilentlyContinue
        if (-not $have) {
            Send-Json -Response $Response -StatusCode 503 -Body @{ error = "Decide tool not loaded" }
            return
        }
        try {
            $r = Invoke-RealDecideTarget -Server $server
            Send-Json -Response $Response -Body $r
        } catch {
            Send-Json -Response $Response -StatusCode 500 -Body @{ status = 'error'; error = $_.Exception.Message }
        }
        return
    }

    # ---- Terraform: plan / apply / destroy ----
    if ($method -eq 'POST' -and $path -eq '/api/terraform') {
        $args = Read-JsonBody -Request $Request
        if (-not $args -or -not $args.action) {
            Send-Json -Response $Response -StatusCode 400 -Body @{ error = "Missing 'action'" }
            return
        }
        $have = Get-Command -Name 'Invoke-RealApplyTerraform' -ErrorAction SilentlyContinue
        if (-not $have) {
            Send-Json -Response $Response -StatusCode 503 -Body @{ error = "Terraform tool not loaded" }
            return
        }
        Publish-UiEvent -Type 'terraform_start' -Payload @{ action = $args.action }
        try {
            $r = Invoke-RealApplyTerraform -Action $args.action
            Publish-UiEvent -Type 'terraform_done' -Payload @{ action = $args.action; result = $r }
            Send-Json -Response $Response -Body $r
        } catch {
            $err = @{ status = 'error'; error = $_.Exception.Message }
            Publish-UiEvent -Type 'terraform_error' -Payload $err
            Send-Json -Response $Response -StatusCode 500 -Body $err
        }
        return
    }

    # ---- Restore: BACKUP TO URL / RESTORE FROM URL ----
    if ($method -eq 'POST' -and $path -eq '/api/restore') {
        $args = Read-JsonBody -Request $Request
        if (-not $args -or -not $args.database -or -not $args.source -or -not $args.target) {
            Send-Json -Response $Response -StatusCode 400 -Body @{ error = "Missing database/source/target" }
            return
        }
        $have = Get-Command -Name 'Invoke-RealRestoreDatabase' -ErrorAction SilentlyContinue
        if (-not $have) {
            Send-Json -Response $Response -StatusCode 503 -Body @{ error = "Restore tool not loaded" }
            return
        }
        Publish-UiEvent -Type 'restore_start' -Payload @{ database = $args.database }
        try {
            $r = Invoke-RealRestoreDatabase -Database $args.database -Source $args.source -Target $args.target
            Publish-UiEvent -Type 'restore_done' -Payload @{ database = $args.database; result = $r }
            Send-Json -Response $Response -Body $r
        } catch {
            $err = @{ status = 'error'; error = $_.Exception.Message }
            Publish-UiEvent -Type 'restore_error' -Payload $err
            Send-Json -Response $Response -StatusCode 500 -Body $err
        }
        return
    }

    # ---- Validate: DBCC CHECKDB ----
    if ($method -eq 'POST' -and $path -eq '/api/validate') {
        $args = Read-JsonBody -Request $Request
        $have = Get-Command -Name 'Invoke-RealValidateDatabase' -ErrorAction SilentlyContinue
        if (-not $have) {
            Send-Json -Response $Response -StatusCode 503 -Body @{ error = "Validate tool not loaded" }
            return
        }
        Publish-UiEvent -Type 'validate_start' -Payload @{ database = ($args.database) }
        try {
            $r = if ($args -and $args.database) {
                Invoke-RealValidateDatabase -Database $args.database
            } else {
                Invoke-RealValidateDatabase
            }
            Publish-UiEvent -Type 'validate_done' -Payload @{ result = $r }
            Send-Json -Response $Response -Body $r
        } catch {
            $err = @{ status = 'error'; error = $_.Exception.Message }
            Send-Json -Response $Response -StatusCode 500 -Body $err
        }
        return
    }

    # ---- Handoff: generate the package ----
    if ($method -eq 'POST' -and $path -eq '/api/handoff') {
        $args = Read-JsonBody -Request $Request
        if (-not $args -or -not $args.database -or -not $args.source) {
            Send-Json -Response $Response -StatusCode 400 -Body @{ error = "Missing database/source" }
            return
        }
        $have = Get-Command -Name 'Invoke-RealGenerateHandoff' -ErrorAction SilentlyContinue
        if (-not $have) {
            Send-Json -Response $Response -StatusCode 503 -Body @{ error = "Handoff tool not loaded" }
            return
        }
        try {
            # If the client passes prior results, forward them; otherwise the
            # tool generates with placeholders.
            $params = @{
                Source   = $args.source
                Database = $args.database
            }
            if ($args.restore_result)  { $params['RestoreResult']  = (ConvertTo-Hashtable $args.restore_result) }
            if ($args.validate_result) { $params['ValidateResult'] = (ConvertTo-Hashtable $args.validate_result) }
            $r = Invoke-RealGenerateHandoff @params
            Send-Json -Response $Response -Body $r
        } catch {
            Send-Json -Response $Response -StatusCode 500 -Body @{ status = 'error'; error = $_.Exception.Message }
        }
        return
    }

    # ---- Decision log ----
    if ($method -eq 'GET' -and $path -eq '/api/decision-log') {
        $genDir = Join-Path $ProjectRoot 'generated'
        $latest = $null
        if (Test-Path $genDir) {
            $latest = Get-ChildItem -Path $genDir -Filter 'decision_log_*.json' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if (-not $latest) {
            Send-Json -Response $Response -Body @{ entries = @(); note = "No decision log yet. Run agent.ps1 first to produce one." }
            return
        }
        $data = Get-Content $latest.FullName -Raw | ConvertFrom-Json
        Send-Json -Response $Response -Body @{ source_file = $latest.Name; entries = $data }
        return
    }

    # ---- SSE stream (DISABLED in v0.9 demo — blocks single-threaded HttpListener) ----
    # Returning a 410 Gone immediately so the EventSource reconnect loop in the
    # browser doesn't pile up retries. Re-enable in Phase 3 with proper async
    # HttpListener (BeginGetContext) or by switching to a WebSocket library.
    if ($method -eq 'GET' -and $path -eq '/api/events') {
        Send-Json -Response $Response -StatusCode 410 -Body @{ note = 'SSE disabled in v0.9 demo' }
        return
    }

    # ---- Static fallthrough ----
    if ($method -eq 'GET') {
        Send-StaticFile -Response $Response -RelativePath $path
        return
    }

    Send-Json -Response $Response -StatusCode 404 -Body @{ error = "no route for $method $path" }
}


# Helper: convert PSCustomObject (from ConvertFrom-Json) to hashtable, since
# the handoff tool expects hashtables not PSObjects.
function ConvertTo-Hashtable {
    param ($Object)
    if ($null -eq $Object) { return $null }
    if ($Object -is [hashtable]) { return $Object }
    $ht = @{}
    foreach ($p in $Object.PSObject.Properties) {
        $val = $p.Value
        if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
            $ht[$p.Name] = @($val | ForEach-Object {
                if ($_ -is [PSCustomObject]) { ConvertTo-Hashtable $_ } else { $_ }
            })
        } elseif ($val -is [PSCustomObject]) {
            $ht[$p.Name] = ConvertTo-Hashtable $val
        } else {
            $ht[$p.Name] = $val
        }
    }
    return $ht
}


# ---------------------------------------------------------------------------
# Listener loop.
# ---------------------------------------------------------------------------
$listener = New-Object System.Net.HttpListener
$prefix   = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
try {
    $listener.Start()
} catch {
    Write-Host "Failed to bind $prefix" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Try a different port: .\server.ps1 -Port 8766" -ForegroundColor Yellow
    exit 1
}

Write-Host "Ready. Open http://localhost:$Port/ in a browser." -ForegroundColor Green
Write-Host "Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ''

if ($OpenBrowser) {
    Start-Process "http://localhost:$Port/"
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            Invoke-Route -Request $context.Request -Response $context.Response
        } catch {
            Write-Host "Request error: $($_.Exception.Message)" -ForegroundColor Red
            try {
                Send-Json -Response $context.Response -StatusCode 500 -Body @{ error = $_.Exception.Message }
            } catch {}
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
    Write-Host 'Listener stopped.' -ForegroundColor DarkGray
}
