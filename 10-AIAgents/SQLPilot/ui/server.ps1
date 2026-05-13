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
Write-Host "  Project   : $ProjectRoot"
Write-Host "  UI root   : $UiRoot"
Write-Host "  Tools dir : $ToolsDir"
Write-Host "  Terraform : $TerraformDir"
Write-Host "  Listening : http://localhost:$Port/"
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
function Get-LatestPhase1Json {
    $candidates = @(
        'C:\Users\ushakale\Documents\Temp\SQL_Migration_Assessment_Agent_AI',
        $ProjectRoot
    )
    foreach ($d in $candidates) {
        if ($d -and (Test-Path $d)) {
            $f = Get-ChildItem -Path $d -Filter 'Migration_Assessment_Report_*.json' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($f) { return $f }
        }
    }
    return $null
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
            $perServer += @{ name = $srv.Name; high = $sHigh; medium = $sMed }
        }

        Send-Json -Response $Response -Body @{
            has_data        = $true
            source_file     = $latest.Name
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
    # POST /api/assess/run  (body optional: { wrapper_path?: "C:\..\Generate_Assessment_Report.ps1" })
    # Fires the Phase 1 wrapper in a background job. Returns a job_id the UI can poll.
    if ($method -eq 'POST' -and $path -eq '/api/assess/run') {
        $argsBody = Read-JsonBody -Request $Request
        $wrapperPath = if ($argsBody -and $argsBody.wrapper_path) {
            $argsBody.wrapper_path
        } else {
            'C:\Users\ushakale\Documents\Temp\SQL_Migration_Assessment_Agent_AI\Generate_Assessment_Report.ps1'
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

        $jobId = [Guid]::NewGuid().ToString('N').Substring(0,8)
        $logFile = Join-Path $env:TEMP "sqlpilot_assess_$jobId.log"

        # Start a detached background job that runs the Phase 1 wrapper.
        # We use Start-Process so the spawned pwsh.exe is fully detached from this server's lifecycle.
        $startInfo = "Start-Process -FilePath pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$wrapperPath' -RedirectStandardOutput '$logFile' -RedirectStandardError '$logFile.err' -WindowStyle Hidden -PassThru"
        $proc = Invoke-Expression $startInfo

        # Track in script state so /api/assess/status can answer.
        if (-not $script:AssessJobs) { $script:AssessJobs = @{} }
        $script:AssessJobs[$jobId] = @{
            job_id        = $jobId
            pid           = $proc.Id
            started_at    = (Get-Date).ToString('o')
            wrapper_path  = $wrapperPath
            pre_run_mtime = $preRunMtime
            log_file      = $logFile
            status        = 'running'
        }

        Publish-UiEvent -Type 'assess_start' -Payload @{ job_id = $jobId }

        Send-Json -Response $Response -Body @{
            status     = 'started'
            job_id     = $jobId
            note       = "Phase 1 wrapper is running. Poll /api/assess/status?job_id=$jobId for progress. Expected duration: 3-5 minutes per server."
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
