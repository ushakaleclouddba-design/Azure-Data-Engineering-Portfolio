<#
.SYNOPSIS
    SQLPilot - Decide stage tool.

.DESCRIPTION
    Provides Invoke-RealDecideTarget: takes a server name, walks that
    server's findings from the latest Phase 1 JSON, maps each finding to a
    KB topic via the kb.json phase1_match patterns, then aggregates verdicts
    across three Azure targets (VM / MI / SQL DB).

    Output shape is what the Decide screen renders directly: three cards,
    each with viability summary (✓/!/✗), a list of contributing findings,
    and the citation list from each KB entry.

    Verdict aggregation rules (target by target):
      - If ANY contributing finding marks the target as 'blocker' → BLOCKED
      - Else if ANY finding marks 'warning_remediable' → CONDITIONAL
      - Else → READY (no contributing blockers found)

    The "recommended target" is the highest-tier target that's READY or
    CONDITIONAL (prefer SQL DB → MI → VM → none). For SQLPilotDemo on
    Node5, the typical result is "Azure VM" because UNSAFE CLR / xp_cmdshell
    / linked-server findings block MI and SQL DB.

.NOTES
    Author : Kale
    Pattern: mirrors tools/kb.ps1 - script-scoped cache, returns hashtable.
             Loaded by agent.ps1 and ui/server.ps1 alongside the other tools.
#>

# ---------------------------------------------------------------------------
# Lazy-loaded KB cache. Re-uses Get-KbEntry if kb.ps1 is already loaded;
# otherwise loads kb.json ourselves.
# ---------------------------------------------------------------------------
$script:DecideKb = $null
$script:DecidePhase1 = $null

function Initialize-DecideKb {
    [CmdletBinding()]
    param ()
    if ($script:DecideKb) { return }

    $kbPath = $null
    if ($script:ScriptRoot) {
        $candidate = Join-Path $script:ScriptRoot 'kb.json'
        if (Test-Path $candidate) { $kbPath = $candidate }
    }
    if (-not $kbPath) {
        # Fallback - kb.json in cwd or parent
        foreach ($d in @((Get-Location).Path, (Split-Path (Get-Location).Path -Parent))) {
            if ($d -and (Test-Path (Join-Path $d 'kb.json'))) {
                $kbPath = Join-Path $d 'kb.json'
                break
            }
        }
    }
    if (-not $kbPath) {
        throw "Could not locate kb.json. Decide tool needs the knowledge base."
    }
    $script:DecideKb = Get-Content $kbPath -Raw | ConvertFrom-Json
}


function Initialize-DecidePhase1 {
    [CmdletBinding()]
    param ([string] $JsonPath)


    if (-not $JsonPath) {
        # Find the latest Migration_Assessment_Report_*.json. The Phase 1
        # wrapper writes into per-run subfolders under Assessment\Reports\
        # (e.g. Reports\2026-05-15_1501_Node5\) — we recurse to find them.
        # Falls back to the legacy flat Assessment\ dir for back-compat with
        # older output files left over from before the folder restructure.
        $assessmentRoot = 'C:\SQLPilot\Assessment'
        $reportsRoot    = Join-Path $assessmentRoot 'Reports'
        $allMatches = @()
        if (Test-Path $reportsRoot) {
            $files = Get-ChildItem -Path $reportsRoot -Recurse -Filter 'Migration_Assessment_Report_*.json' -ErrorAction SilentlyContinue
            if ($files) { $allMatches += $files }
        }
        if (Test-Path $assessmentRoot) {
            $files = Get-ChildItem -Path $assessmentRoot -Filter 'Migration_Assessment_Report_*.json' -ErrorAction SilentlyContinue
            if ($files) { $allMatches += $files }
        }
        if ($script:ScriptRoot -and (Test-Path $script:ScriptRoot)) {
            $files = Get-ChildItem -Path $script:ScriptRoot -Filter 'Migration_Assessment_Report_*.json' -ErrorAction SilentlyContinue
            if ($files) { $allMatches += $files }
        }
        if ($allMatches.Count -gt 0) {
            $latest = $allMatches | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $JsonPath = $latest.FullName
        }
    }
    if (-not $JsonPath -or -not (Test-Path $JsonPath)) {
        throw "Could not locate a Phase 1 JSON file. Run Generate_Assessment_Report.ps1 first."
    }
    $script:DecidePhase1 = Get-Content $JsonPath -Raw | ConvertFrom-Json
}


# ---------------------------------------------------------------------------
# Pattern matcher: given a Phase 1 finding row, does it match one of a KB
# topic's phase1_match patterns?
#
# kb.json phase1_match strings are human-readable signals like:
#   "sp_configure: xp_cmdshell"
#   "CLR Assembly: PERMISSION_SET in (UNSAFE, EXTERNAL_ACCESS)"
#   "Database with FileStream/FileTable filegroup"
#
# We match them with pattern-specific logic per category. The match is
# heuristic - exact-string would be too brittle, and full regex would
# require kb.json to carry regex.
# ---------------------------------------------------------------------------
function Test-FindingMatch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] $Row,
        [Parameter(Mandatory)] [string] $Section,
        [Parameter(Mandatory)] [string] $Pattern
    )

    $rowText = ($Row.PSObject.Properties | ForEach-Object { "$($_.Value)" }) -join ' '
    $patternLower = $Pattern.ToLower()
    $rowLower = $rowText.ToLower()

    # sp_configure patterns: "sp_configure: <option>"
    if ($patternLower -like 'sp_configure:*') {
        $opt = ($Pattern -split ':')[1].Trim()
        if ($Section -eq '02_Instance_Configuration' -and
            "$($Row.ConfigName)" -eq $opt -and
            "$($Row.ValueInUse)" -eq '1') {
            return $true
        }
        return $false
    }

    # CLR Assembly UNSAFE/EXTERNAL_ACCESS
    if ($patternLower -match 'clr assembly.*permission_set.*unsafe.*external_access') {
        if ($Section -eq '09_CLR_Assemblies') {
            $perm = "$($Row.PermissionSet)"
            if ($perm -match 'UNSAFE' -or $perm -match 'EXTERNAL') { return $true }
        }
        return $false
    }

    # Linked server with non-SQL provider
    if ($patternLower -match 'linked server with non-sql provider') {
        if ($Section -eq '03_Linked_Servers') {
            $provider = "$($Row.Provider)"
            if ($provider -and $provider -notmatch 'SQLNCLI' -and $provider -notmatch 'MSOLEDBSQL') {
                return $true
            }
        }
        return $false
    }

    # Linked server with SQLNCLI / SQLNCLI11 (legacy)
    if ($patternLower -match 'linked server.*sqlncli') {
        if ($Section -eq '03_Linked_Servers') {
            $provider = "$($Row.Provider)"
            if ($provider -match 'SQLNCLI') { return $true }
        }
        return $false
    }

    # SQL Agent Job with PowerShell subsystem step
    if ($patternLower -match 'agent job.*powershell.*subsystem') {
        if ($Section -eq '04_SQL_Agent_Jobs') {
            $subsystems = "$($Row.Subsystems)"
            if ($subsystems -match 'PowerShell') { return $true }
        }
        return $false
    }

    # Database name patterns: "Database: SSISDB present" / "Database: ReportServer present"
    if ($patternLower -match 'database:\s*(\S+)\s*present') {
        $dbName = $Matches[1]
        if ($Section -eq '05_Database_Inventory') {
            if ("$($Row.DatabaseName)" -eq $dbName) { return $true }
        }
        return $false
    }

    # FileStream / FileTable filegroup
    if ($patternLower -match 'filestream.*filetable.*filegroup') {
        if ($Section -eq '10_Database_Files') {
            $type = "$($Row.FileType)"
            if ($type -match 'FILESTREAM' -or $type -match 'FILETABLE') { return $true }
        }
        # Or via DB-level findings calling it out
        if ($Section -eq '06_DB_Level_Findings') {
            $finding = "$($Row.Finding)".ToLower()
            if ($finding -match 'filestream' -or $finding -match 'filetable') { return $true }
        }
        return $false
    }

    # Generic fallback: substring match on row text vs pattern keywords
    return $false
}


# ---------------------------------------------------------------------------
# Aggregate verdicts: given a list of contributing KB topics, compute the
# net verdict per target.
# ---------------------------------------------------------------------------
function Resolve-TargetVerdict {
    [CmdletBinding()]
    param (
        [AllowEmptyCollection()] [array] $ContributingTopics = @(),
        [Parameter(Mandatory)] [string] $TargetKey   # sql_vm | sql_mi | sql_db
    )

    $blockers = @()
    $warnings = @()

    foreach ($topic in $ContributingTopics) {
        $verdict = $topic.verdicts.$TargetKey
        if ($verdict -eq 'blocker') {
            $blockers += $topic
        } elseif ($verdict -eq 'warning_remediable') {
            $warnings += $topic
        }
    }

    if ($blockers.Count -gt 0) {
        return @{
            label    = 'Blocked'
            severity = 'blocker'
            blockers = @($blockers | ForEach-Object { @{ topic = $_.topic_id; rationale_short = $_.short } })
            warnings = @($warnings | ForEach-Object { @{ topic = $_.topic_id; rationale_short = $_.short } })
        }
    }
    if ($warnings.Count -gt 0) {
        return @{
            label    = 'Conditional'
            severity = 'warning'
            blockers = @()
            warnings = @($warnings | ForEach-Object { @{ topic = $_.topic_id; rationale_short = $_.short } })
        }
    }
    return @{
        label    = 'Ready'
        severity = 'supported'
        blockers = @()
        warnings = @()
    }
}


# ---------------------------------------------------------------------------
# Invoke-RealDecideTarget
#
# Public entry point. Returns the full Decide payload for one server.
# ---------------------------------------------------------------------------
function Invoke-RealDecideTarget {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $Server,
        [string] $Phase1JsonPath
    )

    $started = Get-Date

    Initialize-DecideKb
    Initialize-DecidePhase1 -JsonPath $Phase1JsonPath

    $serverData = $script:DecidePhase1.servers.$Server
    if (-not $serverData) {
        throw "Server '$Server' not found in Phase 1 JSON. Available: $($script:DecidePhase1.servers.PSObject.Properties.Name -join ', ')"
    }

    # Walk each KB topic; for each, scan the relevant sections for matches.
    # Build "contributingTopics" with topic_id + first-matching row excerpt.
    $contributingTopics = @()

    foreach ($topicProp in $script:DecideKb.topics.PSObject.Properties) {
        $topicId = $topicProp.Name
        $topic   = $topicProp.Value

        $matchesForThisTopic = @()
        foreach ($pattern in @($topic.phase1_match)) {
            # Scan every section's rows. Most patterns are scoped to one
            # section but we don't hardcode which.
            foreach ($sectionProp in $serverData.PSObject.Properties) {
                $sectionLabel = $sectionProp.Name
                $rows = $sectionProp.Value
                if (-not $rows) { continue }
                foreach ($row in @($rows)) {
                    if (Test-FindingMatch -Row $row -Section $sectionLabel -Pattern $pattern) {
                        $matchesForThisTopic += @{
                            section = $sectionLabel
                            pattern = $pattern
                            row_excerpt = ($row.PSObject.Properties | Select-Object -First 4 | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '
                        }
                    }
                }
            }
        }

        if ($matchesForThisTopic.Count -gt 0) {
            # Use the topic's rationale first sentence as a short label
            $short = "$($topic.rationale)" -split '\.\s' | Select-Object -First 1
            if ($short.Length -gt 100) { $short = $short.Substring(0, 97) + '...' }

            $contributingTopics += @{
                topic_id    = $topicId
                ms_rule     = $topic.ms_rule_name
                category    = $topic.ms_rule_category
                short       = $short
                verdicts    = $topic.verdicts
                matches     = $matchesForThisTopic
                match_count = $matchesForThisTopic.Count
                citations   = @($topic.citations)
            }
        }
    }

    # Compute per-target verdicts.
    $targets = @(
        @{ key='sql_vm'; display='Azure VM (IaaS)';      tier=1 }
        @{ key='sql_mi'; display='Azure SQL MI';         tier=2 }
        @{ key='sql_db'; display='Azure SQL Database';   tier=3 }
    )

    $cards = @()
    foreach ($t in $targets) {
        $verdict = Resolve-TargetVerdict -ContributingTopics $contributingTopics -TargetKey $t.key
        $cards += @{
            target_key = $t.key
            display    = $t.display
            tier       = $t.tier
            label      = $verdict.label
            severity   = $verdict.severity
            blocker_count = $verdict.blockers.Count
            warning_count = $verdict.warnings.Count
            blockers   = $verdict.blockers
            warnings   = $verdict.warnings
        }
    }

    # On-prem DC->DC target. Unlike the Azure targets, this is a SQL Server ->
    # SQL Server move, so Azure-platform blockers (MI feature gaps, DB
    # limitations) don't apply. The only real compatibility constraint is engine
    # version: you cannot restore/attach a database from a NEWER SQL major
    # version onto an OLDER one. The destination isn't chosen until the Migrate
    # step, so here we surface that as an informational note rather than a hard
    # verdict. tier=0 keeps it out of the Azure recommendation ranking below.
    $cards += @{
        target_key    = 'onprem_dcdc'
        display       = 'On-prem DC -> DC'
        tier          = 0
        label         = 'Ready'
        severity      = 'info'
        blocker_count = 0
        warning_count = 0
        blockers      = @()
        warnings      = @(@{
            severity = 'info'
            text     = 'Server-to-server on-prem migration. Final compatibility depends on the destination chosen at the Migrate step (a database cannot be restored onto an older SQL Server major version than its source).'
        })
    }

    # Recommended = highest-tier target that's Ready, else highest-tier
    # Conditional, else Azure VM as fallback.
    $ready = $cards | Where-Object { $_.label -eq 'Ready' } | Sort-Object -Property tier -Descending | Select-Object -First 1
    $cond  = $cards | Where-Object { $_.label -eq 'Conditional' } | Sort-Object -Property tier -Descending | Select-Object -First 1
    $recommended = if ($ready) { $ready } elseif ($cond) { $cond } else { $cards[0] }
    # Microsoft decision-tree nuance: when ALL targets are viable (clean
    # server), an existing-instance migration should default to SQL MI
    # ("best for most migrations to the cloud"), NOT SQL Database. SQL
    # Database is only correct for a single clean cloud-born database.
    # (When blockers exist, the tier logic already picks correctly, e.g. VM.)
    if ($recommended.label -eq 'Ready' -and $recommended.target_key -eq 'sql_db') {
        $userDbCount = @($serverData.'05_Database_Inventory').Count
        $miReady = $cards | Where-Object { $_.target_key -eq 'sql_mi' -and $_.label -eq 'Ready' } | Select-Object -First 1
        if ($userDbCount -ne 1 -and $miReady) {
            $recommended = $miReady
        }
    }

    return @{
        status            = 'ok'
        mock              = $false
        server            = $Server
        contributing_topics = $contributingTopics
        cards             = $cards
        recommended_target = @{
            key     = $recommended.target_key
            display = $recommended.display
            label   = $recommended.label
        }
        elapsed_seconds   = [int]((Get-Date) - $started).TotalSeconds
    }
}
