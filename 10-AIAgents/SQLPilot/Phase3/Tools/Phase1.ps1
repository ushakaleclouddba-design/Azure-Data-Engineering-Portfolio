<#
.SYNOPSIS
    SQLPilot - Phase 1 integration tool (JSON edition).

.DESCRIPTION
    Two functions that drive Phase 1 of the migration assessment:

      Invoke-Phase1Assessment   - runs Generate_Assessment_Report.ps1 against
                                  a source SQL Server. Returns the path to
                                  the generated JSON report.

      Read-Phase1Assessment     - reads the JSON and extracts the findings
                                  for one server into a structured hashtable
                                  for the agent loop.

    These replace the run_phase1_assessment stub in agent.ps1.

.NOTES
    Author : Kale
    Phase 1 lives at:
        C:\SQLPilot\Assessment\Generate_Assessment_Report.ps1

    Phase 1 was modified to write a parallel .json file alongside the .xlsx
    on every run. This tool reads that .json - no Excel parsing required.
#>


# ---------------------------------------------------------------------------
# Invoke-Phase1Assessment
#
# Runs the existing Generate_Assessment_Report.ps1 against $SourceServer.
# Phase 1 writes its reports (both .xlsx and .json) into its own folder.
# We capture the most recent .json file matching the report naming pattern
# after the run.
#
# If a recent (<60 min) report for this server is already on disk, we reuse
# it instead of re-running Phase 1. Saves ~5 min during iteration. Pass
# -ForceFresh to override.
#
# Returns: hashtable with status, json_path, excel_path, server, generated_at.
# ---------------------------------------------------------------------------
function Invoke-Phase1Assessment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $SourceServer,

        [string] $Phase1Wrapper = 'C:\SQLPilot\Assessment\Generate_Assessment_Report.ps1',

        # If a Phase 1 JSON newer than this many minutes exists, reuse it.
        # Set 0 to always force a fresh run.
        [int]    $ReuseWindowMinutes = 60,

        [switch] $ForceFresh
    )

    if (-not (Test-Path $Phase1Wrapper)) {
        throw "Phase 1 wrapper not found at: $Phase1Wrapper"
    }

    # Phase 1 reports land in per-run subfolders under <phase1Dir>\Reports\
    # (e.g. Reports\2026-05-15_1501_Node5\Migration_Assessment_Report_*.json).
    # We recurse to find them. Legacy flat reports (directly in $phase1Dir)
    # are also included for back-compat.
    $phase1Dir = Split-Path -Parent $Phase1Wrapper

    # Try to reuse a recent report unless told otherwise.
    if (-not $ForceFresh -and $ReuseWindowMinutes -gt 0) {
        $cutoff = (Get-Date).AddMinutes(-$ReuseWindowMinutes)
        $recent = Get-ChildItem -Path $phase1Dir -Recurse -Filter 'Migration_Assessment_Report_*.json' -ErrorAction SilentlyContinue |
                  Where-Object { $_.LastWriteTime -gt $cutoff } |
                  Sort-Object LastWriteTime -Descending |
                  Select-Object -First 1

        # Verify the recent JSON actually contains the requested server before
        # reusing it. A report from a different node doesn't help us.
        if ($recent) {
            $candidate = Get-Content -Path $recent.FullName -Raw | ConvertFrom-Json
            $hasServer = $false
            if ($candidate.servers) {
                $hasServer = [bool]($candidate.servers.PSObject.Properties.Name |
                                    Where-Object { $_ -ieq $SourceServer })
            }
            if ($hasServer) {
                $excelGuess = [System.IO.Path]::ChangeExtension($recent.FullName, '.xlsx')
                $age        = [int]((Get-Date) - $recent.LastWriteTime).TotalMinutes
                Write-Host "[phase1]  Reusing recent report ($age min old): $($recent.Name)" -ForegroundColor DarkGray
                return @{
                    status       = 'ok'
                    json_path    = $recent.FullName
                    excel_path   = if (Test-Path $excelGuess) { $excelGuess } else { $null }
                    server       = $SourceServer
                    generated_at = $recent.LastWriteTime.ToString('o')
                    reused       = $true
                }
            }
        }
    }

    Write-Host "[phase1]  Running Phase 1 against $SourceServer..." -ForegroundColor DarkCyan

    $beforeFiles = @(Get-ChildItem -Path $phase1Dir -Recurse -Filter 'Migration_Assessment_Report_*.json' -ErrorAction SilentlyContinue)
    $beforeNames = $beforeFiles | ForEach-Object { $_.FullName }

    $start = Get-Date
    try {
        & $Phase1Wrapper -ServerInstance $SourceServer -ErrorAction Stop | Out-Host
    } catch {
        return @{
            status   = 'error'
            error    = $_.Exception.Message
            server   = $SourceServer
            phase1   = $Phase1Wrapper
            hint     = 'Confirm Phase 1 wrapper accepts -ServerInstance.'
        }
    }
    $elapsed = (Get-Date) - $start

    $afterFiles = @(Get-ChildItem -Path $phase1Dir -Recurse -Filter 'Migration_Assessment_Report_*.json' -ErrorAction SilentlyContinue)
    $newFiles   = $afterFiles | Where-Object { $beforeNames -notcontains $_.FullName }

    if ($newFiles.Count -eq 0) {
        return @{
            status = 'error'
            error  = 'Phase 1 ran but no new JSON report appeared.'
            hint   = "Check $phase1Dir for output."
        }
    }

    $json       = $newFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $excelGuess = [System.IO.Path]::ChangeExtension($json.FullName, '.xlsx')

    Write-Host "[phase1]  Done in $([int]$elapsed.TotalSeconds)s -> $($json.Name)" -ForegroundColor DarkGreen

    return @{
        status       = 'ok'
        json_path    = $json.FullName
        excel_path   = if (Test-Path $excelGuess) { $excelGuess } else { $null }
        server       = $SourceServer
        generated_at = $json.LastWriteTime.ToString('o')
        elapsed_sec  = [int]$elapsed.TotalSeconds
        reused       = $false
    }
}


# ---------------------------------------------------------------------------
# Read-Phase1Assessment
#
# Reads the Phase 1 JSON and pulls out the agent-relevant findings for one
# server. The JSON is shaped:
#   { metadata: {...}, servers: { "NODE5": { "01_Instance_Summary": [...], ... } } }
#
# We surface a flat, agent-friendly view by:
#   - Picking the rows the Decide stage cares about
#   - Filtering sp_configure to non-Info MIRelevance only (signal, not noise)
#   - Synthesizing a normalized findings[] list with stable IDs
#   - Surfacing Phase 1's own AI-driven recommendation if present
# ---------------------------------------------------------------------------
function Read-Phase1Assessment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $JsonPath,

        [Parameter(Mandatory = $true)]
        [string] $Server
    )

    if (-not (Test-Path $JsonPath)) {
        throw "Phase 1 JSON not found: $JsonPath"
    }

    Write-Host "[phase1]  Parsing $(Split-Path -Leaf $JsonPath) for server '$Server'..." -ForegroundColor DarkGray

    $report = Get-Content -Path $JsonPath -Raw | ConvertFrom-Json

    # Resolve server key case-insensitively.
    $serverKey = $report.servers.PSObject.Properties.Name |
                 Where-Object { $_ -ieq $Server } |
                 Select-Object -First 1

    if (-not $serverKey) {
        $available = ($report.servers.PSObject.Properties.Name) -join ', '
        throw "Server '$Server' not found in Phase 1 JSON. Available: $available"
    }

    $s = $report.servers.$serverKey

    # ---- Section pickers (each is an array of objects from the JSON) -----
    $instanceRows = @($s.'01_Instance_Summary')
    $instance     = if ($instanceRows.Count -gt 0) { $instanceRows[0] } else { $null }

    $allSpFlags = @($s.'02_Instance_Configuration')
    $sp_configure_flags = @($allSpFlags | Where-Object {
        $_.MIRelevance -and ($_.MIRelevance -as [string]) -notmatch '^Info'
    })

    $linked_servers = @($s.'03_Linked_Servers')
    $agent_jobs     = @($s.'04_SQL_Agent_Jobs')
    $databases      = @($s.'05_Database_Inventory')
    $clr_assemblies = @($s.'09_CLR_Assemblies')

    # ---- Synthesize a flat findings list with stable IDs ------------------
    $findings  = [System.Collections.ArrayList]::new()
    $findingId = 1
    $addFinding = {
        param ($Severity, $Source, $Object, $Finding, $MIImpact)
        $null = $findings.Add(@{
            id        = ('F{0:D3}' -f $findingId)
            severity  = $Severity
            source    = $Source
            object    = $Object
            finding   = $Finding
            mi_impact = $MIImpact
        })
        $script:findingId = $findingId + 1
    }
    # We use a script-scoped counter because PowerShell scriptblocks don't
    # share local variables with their caller's stack frame the way nested
    # functions would. Keeping it simple: reset counter, then walk.
    $script:findingId = 1
    function script:Add-Finding {
        param ($List, $Severity, $Source, $Object, $Finding, $MIImpact)
        $null = $List.Add(@{
            id        = ('F{0:D3}' -f $script:findingId)
            severity  = $Severity
            source    = $Source
            object    = $Object
            finding   = $Finding
            mi_impact = $MIImpact
        })
        $script:findingId++
    }

    # sp_configure flags
    foreach ($f in $sp_configure_flags) {
        $rel = ($f.MIRelevance -as [string])
        $sev = if ($rel -match '^High')   { 'High' }
               elseif ($rel -match '^Medium') { 'Medium' }
               else { 'Info' }
        Add-Finding -List $findings -Severity $sev -Source 'sp_configure' -Object $f.ConfigName `
                    -Finding "$($f.ConfigName) is $($f.ValueInUse)" -MIImpact $rel
    }

    # Linked servers
    foreach ($ls in $linked_servers) {
        if ($ls.MICompatibility) {
            $mic = ($ls.MICompatibility -as [string])
            $sev = if ($mic -match '^High')   { 'High' }
                   elseif ($mic -match '^WARN|^Medium') { 'Medium' }
                   else { 'Info' }
            Add-Finding -List $findings -Severity $sev -Source 'Linked Server' -Object $ls.LinkedServerName `
                        -Finding "Provider $($ls.Provider) -> $($ls.DataSource)" -MIImpact $mic
        }
    }

    # Agent jobs with risky steps
    foreach ($j in $agent_jobs) {
        if ($j.RiskySteps -and ([int]$j.RiskySteps) -gt 0) {
            Add-Finding -List $findings -Severity 'High' -Source 'SQL Agent Job' -Object $j.JobName `
                        -Finding "Risky subsystem: $($j.Subsystems). Steps: $($j.RiskySteps) risky / $($j.TotalSteps) total" `
                        -MIImpact ($j.MIRelevance -as [string])
        }
    }

    # CLR assemblies with risky permission sets
    foreach ($a in $clr_assemblies) {
        $perm = ($a.PermissionSet -as [string])
        if ($perm -match 'UNSAFE|EXTERNAL_ACCESS') {
            Add-Finding -List $findings -Severity 'High' -Source 'CLR Assembly' `
                        -Object "$($a.DatabaseName).$($a.AssemblyName) ($perm)" `
                        -Finding "User-defined CLR with $perm permission set" `
                        -MIImpact ($a.MIRelevance -as [string])
        }
    }

    # ---- Phase 1's own AI-driven recommendation (section 15) -------------
    $matrix = @($s.'15_Cloud_Migration_Matrix')
    $phase1_recommendation = @{
        target    = $null
        rationale = $null
        raw_rows  = $matrix
    }
    foreach ($row in $matrix) {
        # Each row is a PSCustomObject with arbitrary column names. We look
        # for any column whose value starts with "Recommended Target".
        $rowCols = $row.PSObject.Properties
        foreach ($c in $rowCols) {
            $v = ($c.Value -as [string])
            if ($v -and $v -match '^Recommended Target:\s*(.+)$') {
                $phase1_recommendation.target = $matches[1].Trim()
            }
        }
    }

    return @{
        status                = 'ok'
        server                = $serverKey
        source_json           = $JsonPath
        generated_at          = $report.metadata.generated_at
        instance              = $instance
        phase1_recommendation = $phase1_recommendation
        databases             = $databases
        sp_configure_flags    = $sp_configure_flags
        agent_jobs            = $agent_jobs
        linked_servers        = $linked_servers
        clr_assemblies        = $clr_assemblies
        findings              = @($findings)
    }
}
