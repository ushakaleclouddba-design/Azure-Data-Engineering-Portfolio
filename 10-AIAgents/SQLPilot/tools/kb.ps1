<#
.SYNOPSIS
    SQLPilot - Knowledge Base tool (real implementation).

.DESCRIPTION
    Loads kb.json (curated Microsoft Learn citations) at first use, then
    answers consult_kb requests with verified verdicts and citations.

    This replaces the stubbed consult_kb in agent.ps1.

.NOTES
    Author : Kale
    Source : kb.json lives at the SQLPilot project root.
             Citations in kb.json are verified against Microsoft's official
             "Assessment rules for SQL Server to Azure SQL Managed Instance
             migration" page, plus T-SQL Differences and the MI overview docs.
#>

# ---------------------------------------------------------------------------
# Load kb.json into a script-scoped cache. Doing this once means consult_kb
# is fast even when the agent calls it many times in one run.
# ---------------------------------------------------------------------------
$script:KbCache    = $null
$script:KbCachePath = $null

function Initialize-Kb {
    [CmdletBinding()]
    param (
        [string] $KbPath
    )

    # If KbPath wasn't supplied, default to <SQLPilot root>\kb.json. We assume
    # this script was dot-sourced from agent.ps1 and that $script:ScriptRoot
    # has been set there. If not, fall back to the dot-source caller's location.
    if (-not $KbPath) {
        if ($script:ScriptRoot -and (Test-Path (Join-Path $script:ScriptRoot 'kb.json'))) {
            $KbPath = Join-Path $script:ScriptRoot 'kb.json'
        } else {
            # Last resort: look two levels up from this file (tools\kb.ps1 -> SQLPilot\)
            $here    = Split-Path -Parent $PSCommandPath
            $candidate = Join-Path (Split-Path -Parent $here) 'kb.json'
            if (Test-Path $candidate) { $KbPath = $candidate }
        }
    }

    if (-not $KbPath -or -not (Test-Path $KbPath)) {
        throw "kb.json not found. Looked at: $KbPath. Place kb.json at the SQLPilot project root."
    }

    Write-Host "[kb]      Loading $(Split-Path -Leaf $KbPath)..." -ForegroundColor DarkGray
    $script:KbCache     = Get-Content -Path $KbPath -Raw | ConvertFrom-Json
    $script:KbCachePath = $KbPath

    $topicCount = ($script:KbCache.topics | Get-Member -MemberType NoteProperty).Count
    Write-Host "[kb]      Loaded $topicCount topics, verified $($script:KbCache._meta.verified_date)" -ForegroundColor DarkGray
}


# ---------------------------------------------------------------------------
# Get-KbEntry
#
# Looks up a topic by exact key match (case-insensitive). Returns a
# hashtable shaped for the agent: status, topic, verdicts (per target),
# viable_targets, rationale, remediation, citation (with title, url,
# category, verified_date).
#
# If the topic isn't found, returns status=not_found with the list of
# available topic keys so the agent (and the model) can correct itself.
# ---------------------------------------------------------------------------
function Get-KbEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Topic
    )

    if (-not $script:KbCache) {
        Initialize-Kb
    }

    # Match topic keys case-insensitively. JSON keys are lowercase by
    # convention here, but be lenient.
    $allTopics = $script:KbCache.topics.PSObject.Properties
    $match = $allTopics | Where-Object { $_.Name -ieq $Topic } | Select-Object -First 1

    if (-not $match) {
        return @{
            status            = 'not_found'
            mock              = $false
            requested_topic   = $Topic
            available_topics  = @($allTopics.Name)
            hint              = "No KB entry for '$Topic'. Use one of available_topics or extend kb.json."
        }
    }

    $entry = $match.Value

    return @{
        status              = 'ok'
        mock                = $false
        topic               = $match.Name
        ms_rule_name        = $entry.ms_rule_name
        ms_rule_category    = $entry.ms_rule_category
        verdicts            = $entry.verdicts
        viable_targets      = $entry.viable_targets
        rationale           = $entry.rationale
        remediation_options = $entry.remediation_options
        citation            = $entry.citation
        additional_references = $entry.additional_references
        kb_verified_date    = $script:KbCache._meta.verified_date
        kb_source_file      = (Split-Path -Leaf $script:KbCachePath)
    }
}
