<#
.SYNOPSIS
    SQLPilot - AI-augmented SQL Server -> Azure migration agent.

.DESCRIPTION
    Wraps Anthropic's Claude API with tool-use to drive the four-stage
    migration flow: Assess -> Decide -> Migrate -> Day-to-day.

    This is the v0 skeleton (Friday evening). All five tools are stubs
    that return mock data, so the planning loop completes end-to-end
    without touching SQL Server or Azure. Real implementations land
    Saturday and Sunday.

.PARAMETER Source
    The on-prem SQL Server SQLPilot will assess and migrate.
    Required. Example: NODE5

.PARAMETER MaxTurns
    Safety cap on agent reasoning loop. Default 25.

.PARAMETER Model
    Claude model to use. Default is the current Sonnet (right balance
    of speed and reasoning for tool-use loops). Override with -Model
    if you want to test against Opus or Haiku.

.EXAMPLE
    .\agent.ps1 -Source NODE5

.NOTES
    Author : Kale
    Version: 0.1 (skeleton, stub tools)
    Requires: PowerShell 7+, ANTHROPIC_API_KEY env var
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $Source,

    [int]    $MaxTurns = 25,

    [string] $Model    = 'claude-sonnet-4-5'
)

# ---------------------------------------------------------------------------
# 0. Pre-flight checks.
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'

# PowerShell 7+ for Invoke-RestMethod with proper JSON handling.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "SQLPilot requires PowerShell 7 or later. Current: $($PSVersionTable.PSVersion)"
}

if (-not $env:ANTHROPIC_API_KEY) {
    throw "ANTHROPIC_API_KEY environment variable is not set. " +
          "Set it with: `$env:ANTHROPIC_API_KEY = 'sk-ant-...'"
}

# Folder for run artifacts (assessment outputs, decision log, etc.).
# Each agent run writes here. Recreated fresh on every run.
$script:ScriptRoot   = Split-Path -Parent $PSCommandPath
$script:GeneratedDir = Join-Path $ScriptRoot 'generated'
if (-not (Test-Path $GeneratedDir)) {
    New-Item -ItemType Directory -Path $GeneratedDir -Force | Out-Null
}

$script:DecisionLogPath = Join-Path $GeneratedDir 'decision_log.json'
$script:DecisionLog     = @()


# ---------------------------------------------------------------------------
# 0b. Load tool implementations.
#
# Each tool that has a real implementation lives in tools/. We dot-source
# them here so their functions are available to the dispatch layer. Tools
# that are still stubs are defined inline below.
# ---------------------------------------------------------------------------
$toolsDir = Join-Path $script:ScriptRoot 'tools'
if (Test-Path (Join-Path $toolsDir 'phase1.ps1')) {
    . (Join-Path $toolsDir 'phase1.ps1')
    Write-Host "[setup]   Loaded tools/phase1.ps1 (real implementation)" -ForegroundColor DarkGray
} else {
    Write-Host "[setup]   tools/phase1.ps1 not found - run_phase1_assessment will use stub" -ForegroundColor DarkYellow
}

if (Test-Path (Join-Path $toolsDir 'kb.ps1')) {
    . (Join-Path $toolsDir 'kb.ps1')
    Write-Host "[setup]   Loaded tools/kb.ps1 (real implementation)" -ForegroundColor DarkGray
} else {
    Write-Host "[setup]   tools/kb.ps1 not found - consult_kb will use stub" -ForegroundColor DarkYellow
}

if (Test-Path (Join-Path $toolsDir 'restore.ps1')) {
    . (Join-Path $toolsDir 'restore.ps1')
    Write-Host "[setup]   Loaded tools/restore.ps1 (real implementation)" -ForegroundColor DarkGray
} else {
    Write-Host "[setup]   tools/restore.ps1 not found - restore_database will use stub" -ForegroundColor DarkYellow
}

if (Test-Path (Join-Path $toolsDir 'terraform.ps1')) {
    . (Join-Path $toolsDir 'terraform.ps1')
    Write-Host "[setup]   Loaded tools/terraform.ps1 (real implementation)" -ForegroundColor DarkGray
} else {
    Write-Host "[setup]   tools/terraform.ps1 not found - apply_terraform will use stub" -ForegroundColor DarkYellow
}


# ---------------------------------------------------------------------------
# 1. Console helpers - make the reasoning loop visible.
#
# The point of the loop visualization isn't decoration; it's so a reviewer
# watching the demo can see plan/act/observe/decide as distinct moments
# rather than a wall of console output.
# ---------------------------------------------------------------------------
function Write-Banner {
    param ([string] $Text)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    Write-Host "  $Text"      -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
}

function Write-Stage {
    param ([int] $Number, [string] $Name)
    Write-Host ''
    Write-Host "--- Stage $Number : $Name " -NoNewline -ForegroundColor Yellow
    Write-Host ('-' * (50 - $Name.Length))   -ForegroundColor DarkYellow
}

function Write-Plan {
    param ([string] $Text)
    Write-Host '[plan]    ' -NoNewline -ForegroundColor Magenta
    Write-Host $Text         -ForegroundColor Gray
}

function Write-Tool {
    param ([string] $Name, [hashtable] $Arguments)
    $argsStr = ($Arguments.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
    Write-Host '[act]     ' -NoNewline -ForegroundColor Green
    Write-Host "$Name($argsStr)" -ForegroundColor Gray
}

function Write-Observe {
    param ([string] $Text)
    Write-Host '[observe] ' -NoNewline -ForegroundColor Blue
    Write-Host $Text         -ForegroundColor Gray
}

function Write-Decide {
    param ([string] $Text)
    Write-Host '[decide]  ' -NoNewline -ForegroundColor Yellow
    Write-Host $Text         -ForegroundColor Gray
}

function Write-Gate {
    param ([string] $Question)
    Write-Host ''
    Write-Host '[gate]    ' -NoNewline -ForegroundColor Red
    Write-Host $Question     -ForegroundColor White
}


# ---------------------------------------------------------------------------
# 2. Decision log - append-only audit trail of everything the agent does.
#
# Every tool call, every decision, every approval gate gets a row here.
# Stored as JSON so reviewers can grep / diff / replay later. This IS the
# audit story for the review board.
# ---------------------------------------------------------------------------
function Add-DecisionLogEntry {
    param (
        [string]    $Kind,          # 'plan', 'tool_call', 'tool_result', 'gate', 'final'
        [hashtable] $Payload
    )
    $entry = [pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        kind      = $Kind
        payload   = $Payload
    }
    $script:DecisionLog += $entry
    # Persist immediately so a crash doesn't lose the trail.
    $script:DecisionLog | ConvertTo-Json -Depth 8 | Set-Content -Path $script:DecisionLogPath -Encoding UTF8
}


# ---------------------------------------------------------------------------
# 3. Stub tools.
#
# Each tool returns a hashtable that the agent will receive as JSON.
# All five tools are mock implementations for the v0 skeleton - they print
# what they would do and return believable fake data. Real implementations
# come Saturday/Sunday.
#
# Contract for every tool:
#   - Input : a hashtable of arguments (what the model sent)
#   - Output: a hashtable that gets serialized to JSON for the model
#   - Side  : log the call to the decision log
# ---------------------------------------------------------------------------

function Tool-RunPhase1Assessment {
    param ([hashtable] $ToolArgs)
    Write-Tool -Name 'run_phase1_assessment' -Arguments $ToolArgs
    Add-DecisionLogEntry -Kind 'tool_call' -Payload @{ tool = 'run_phase1_assessment'; args = $ToolArgs }

    # Real implementation if tools/phase1.ps1 was loaded; otherwise fall back
    # to the mock so the loop still runs end-to-end. Detected by checking for
    # the function the tool file defines.
    $haveReal = Get-Command -Name 'Invoke-Phase1Assessment' -ErrorAction SilentlyContinue

    if ($haveReal) {
        $sourceServer = $ToolArgs.source
        if (-not $sourceServer) {
            $result = @{ status = 'error'; error = "Missing 'source' argument." }
            Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'run_phase1_assessment'; result = $result }
            return $result
        }

        try {
            # Step 1: run (or reuse) Phase 1 against the source server.
            $invoke = Invoke-Phase1Assessment -SourceServer $sourceServer

            if ($invoke.status -ne 'ok') {
                Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'run_phase1_assessment'; result = $invoke }
                return $invoke
            }

            # Step 2: parse the resulting JSON into structured findings.
            $parsed = Read-Phase1Assessment -JsonPath $invoke.json_path -Server $sourceServer

            # Persist a per-run agent-friendly snapshot into generated/.
            # Keeping this small (just what the agent surfaced) makes the
            # decision log easier to audit later.
            $jsonPath = Join-Path $GeneratedDir 'assessment.json'
            $parsed | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding UTF8

            # Build the agent-facing result. Surface the most important
            # facts at the top level so the model doesn't have to dig.
            $result = @{
                status                = 'ok'
                mock                  = $false
                source_server         = $sourceServer
                phase1_json_path      = $invoke.json_path
                phase1_excel_path     = $invoke.excel_path
                agent_snapshot_path   = $jsonPath
                reused_recent         = [bool]$invoke.reused
                sql_version           = $parsed.instance.ProductVersion
                edition               = $parsed.instance.Edition
                cu_level              = $parsed.instance.CULevel
                user_database_count   = $parsed.instance.UserDatabaseCount
                phase1_recommendation = $parsed.phase1_recommendation
                findings              = $parsed.findings
                sp_configure_flags    = $parsed.sp_configure_flags
                agent_jobs            = $parsed.agent_jobs
                linked_servers        = $parsed.linked_servers
                clr_assemblies        = $parsed.clr_assemblies
                databases             = $parsed.databases
            }
        }
        catch {
            $result = @{
                status = 'error'
                error  = $_.Exception.Message
                source_server = $sourceServer
                hint = 'Check Phase 1 wrapper path or that Phase 1 is writing JSON output.'
            }
        }

        Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'run_phase1_assessment'; result = $result }
        return $result
    }

    # ---- Fallback mock (when tools/phase1.ps1 is missing) -----------------
    $result = @{
        status                   = 'ok'
        mock                     = $true
        source_server            = $ToolArgs.source
        sql_version              = 'SQL Server 2019 CU32'
        databases_assessed       = 1
        findings = @(
            @{ id = 'F001'; severity = 'blocker'; topic = 'cross_db_query';
               detail = 'sp_GetServerHealthSnapshot references master.sys.dm_os_sys_info' },
            @{ id = 'F002'; severity = 'warning'; topic = 'disabled_login';
               detail = 'sqlpilot_app login is disabled but referenced by db user' },
            @{ id = 'F003'; severity = 'info';    topic = 'agent_job';
               detail = 'SQLPilotDemo - Nightly Audit Roll-up scheduled at 02:00' }
        )
        excel_report_path = "$GeneratedDir\assessment.xlsx"
        json_report_path  = "$GeneratedDir\assessment.json"
    }

    Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'run_phase1_assessment'; result = $result }
    return $result
}

function Tool-ConsultKB {
    param ([hashtable] $ToolArgs)
    Write-Tool -Name 'consult_kb' -Arguments $ToolArgs
    Add-DecisionLogEntry -Kind 'tool_call' -Payload @{ tool = 'consult_kb'; args = $ToolArgs }

    # Real implementation if tools/kb.ps1 was loaded; otherwise fall back to
    # the mock so the loop still runs end-to-end.
    $haveReal = Get-Command -Name 'Get-KbEntry' -ErrorAction SilentlyContinue

    if ($haveReal) {
        $topic = $ToolArgs.topic
        if (-not $topic) {
            $result = @{ status = 'error'; error = "Missing 'topic' argument." }
            Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'consult_kb'; result = $result }
            return $result
        }
        try {
            $result = Get-KbEntry -Topic $topic
        } catch {
            $result = @{
                status = 'error'
                error  = $_.Exception.Message
                topic  = $topic
                hint   = 'Check that kb.json exists at the SQLPilot project root and is valid JSON.'
            }
        }

        Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'consult_kb'; result = $result }
        return $result
    }

    # ---- Fallback mock (when tools/kb.ps1 is missing) ---------------------
    $result = @{
        status   = 'ok'
        mock     = $true
        topic    = $ToolArgs.topic
        verdict  = 'VM only'
        viable_targets = @('sql_vm')
        rationale      = 'Cross-database queries to master are not supported on Azure SQL MI or DB.'
        citation = @{
            title         = 'Managed Instance T-SQL differences'
            url           = 'https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/transact-sql-tsql-differences-sql-server'
            verified_date = '2026-03-15'
        }
    }

    Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'consult_kb'; result = $result }
    return $result
}

function Tool-VerifySku {
    param ([hashtable] $ToolArgs)
    Write-Tool -Name 'verify_sku' -Arguments $ToolArgs
    Add-DecisionLogEntry -Kind 'tool_call' -Payload @{ tool = 'verify_sku'; args = $ToolArgs }

    # MOCK: real implementation calls Azure Retail Prices API.
    $result = @{
        status        = 'ok'
        mock          = $true
        target_type   = $ToolArgs.target_type
        sku           = $ToolArgs.sku
        region        = $ToolArgs.region
        sku_exists    = $true
        monthly_cost_usd = 285.40
    }

    Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'verify_sku'; result = $result }
    return $result
}

function Tool-ApplyTerraform {
    param ([hashtable] $ToolArgs)
    Write-Tool -Name 'apply_terraform' -Arguments $ToolArgs
    Add-DecisionLogEntry -Kind 'tool_call' -Payload @{ tool = 'apply_terraform'; args = $ToolArgs }

    # Real implementation if tools/terraform.ps1 was loaded; otherwise fall
    # back to the mock so the loop still runs end-to-end.
    $haveReal = Get-Command -Name 'Invoke-RealApplyTerraform' -ErrorAction SilentlyContinue

    if ($haveReal) {
        $action = $ToolArgs.action
        if (-not $action) {
            $result = @{
                status = 'error'
                error  = "Missing 'action' argument. Must be one of: plan, apply, destroy."
                args_received = $ToolArgs
            }
            Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'apply_terraform'; result = $result }
            return $result
        }

        $action = $action.ToLower().Trim()
        if ($action -notin @('plan','apply','destroy')) {
            $result = @{
                status = 'error'
                error  = "Invalid action '$action'. Must be one of: plan, apply, destroy."
                args_received = $ToolArgs
            }
            Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'apply_terraform'; result = $result }
            return $result
        }

        try {
            $result = Invoke-RealApplyTerraform -Action $action
        } catch {
            $result = @{
                status = 'error'
                mock   = $false
                action = $action
                error  = $_.Exception.Message
                hint   = 'Check that terraform is on PATH, terraform.tfvars is populated, and the .terraform directory exists (run terraform init if not).'
            }
        }

        Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'apply_terraform'; result = $result }
        return $result
    }

    # ---- Fallback mock (when tools/terraform.ps1 is missing) -------------
    $result = @{
        status            = 'ok'
        mock              = $true
        action            = $ToolArgs.action
        target_resource   = 'sql-vm-sqlpilot-eastus2-01'
        public_ip         = '20.51.x.x (mock)'
        connection_string = 'Server=tcp:sql-vm-sqlpilot-eastus2-01,1433 (mock)'
    }

    Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'apply_terraform'; result = $result }
    return $result
}

function Tool-RestoreDatabase {
    param ([hashtable] $ToolArgs)
    Write-Tool -Name 'restore_database' -Arguments $ToolArgs
    Add-DecisionLogEntry -Kind 'tool_call' -Payload @{ tool = 'restore_database'; args = $ToolArgs }

    # Real implementation if tools/restore.ps1 was loaded; otherwise fall
    # back to the mock so the loop still runs end-to-end.
    $haveReal = Get-Command -Name 'Invoke-RealRestoreDatabase' -ErrorAction SilentlyContinue

    if ($haveReal) {
        $database = $ToolArgs.database
        $source   = $ToolArgs.source
        $target   = $ToolArgs.target

        if (-not $database -or -not $source -or -not $target) {
            $result = @{
                status = 'error'
                error  = "Missing required argument(s). Need database, source, target."
                args_received = $ToolArgs
            }
            Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'restore_database'; result = $result }
            return $result
        }

        try {
            $result = Invoke-RealRestoreDatabase -Database $database -Source $source -Target $target
        } catch {
            $result = @{
                status = 'error'
                mock   = $false
                error  = $_.Exception.Message
                database = $database
                source   = $source
                target   = $target
                hint     = 'Check that terraform has been applied (storage account + SAS exist), terraform.tfvars has admin_password, and both source and target SQL instances are reachable.'
            }
        }

        Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'restore_database'; result = $result }
        return $result
    }

    # ---- Fallback mock (when tools/restore.ps1 is missing) ----------------
    $result = @{
        status         = 'ok'
        mock           = $true
        database       = $ToolArgs.database
        source         = $ToolArgs.source
        target         = $ToolArgs.target
        rows_restored  = 1573
        elapsed_seconds = 42
    }

    Add-DecisionLogEntry -Kind 'tool_result' -Payload @{ tool = 'restore_database'; result = $result }
    return $result
}

# Tool dispatch table - maps the name the model uses to a PS function name.
# We store the function NAME (a string) rather than ${function:Tool-X} because
# PowerShell evaluates ${function:X} to the function BODY, which then prints
# itself and fails to bind parameters when invoked. Calling by name via &
# does the right thing.
$script:ToolRegistry = @{
    'run_phase1_assessment' = 'Tool-RunPhase1Assessment'
    'consult_kb'            = 'Tool-ConsultKB'
    'verify_sku'            = 'Tool-VerifySku'
    'apply_terraform'       = 'Tool-ApplyTerraform'
    'restore_database'      = 'Tool-RestoreDatabase'
}


# ---------------------------------------------------------------------------
# 4. Tool definitions for the Anthropic API.
#
# These tell Claude what tools exist, what they do, and what arguments
# they take. Names and schemas must match the dispatch table above.
# ---------------------------------------------------------------------------
$script:ToolDefinitions = @(
    @{
        name        = 'run_phase1_assessment'
        description = 'Run the Phase 1 T-SQL assessment script against the source SQL Server. Produces both an Excel report (for humans) and a JSON output (for the agent). Always call this first.'
        input_schema = @{
            type       = 'object'
            properties = @{
                source = @{ type = 'string'; description = 'Source server name, e.g. NODE5' }
            }
            required = @('source')
        }
    },
    @{
        name        = 'consult_kb'
        description = 'Look up curated Microsoft Learn guidance for a specific compatibility topic. Returns the verdict per target (sql_vm, sql_mi, sql_db), the viable_targets list, the rationale, remediation options, and a Microsoft Learn citation with title and URL. Call this for each High or Medium severity finding the assessment surfaces. Valid topic keys: xp_cmdshell, clr_strict_security, linked_server_non_sql_provider, linked_server_legacy_provider, agent_job_powershell_subsystem, ssrs_workload, ssis_workload, filestream_filetable. If a finding does not map to any of these keys, do not call consult_kb for it - just note it in the report.'
        input_schema = @{
            type       = 'object'
            properties = @{
                topic = @{
                    type        = 'string'
                    description = 'Exact KB topic key. Must be one of: xp_cmdshell, clr_strict_security, linked_server_non_sql_provider, linked_server_legacy_provider, agent_job_powershell_subsystem, ssrs_workload, ssis_workload, filestream_filetable.'
                    enum        = @(
                        'xp_cmdshell',
                        'clr_strict_security',
                        'linked_server_non_sql_provider',
                        'linked_server_legacy_provider',
                        'agent_job_powershell_subsystem',
                        'ssrs_workload',
                        'ssis_workload',
                        'filestream_filetable'
                    )
                }
            }
            required = @('topic')
        }
    },
    @{
        name        = 'verify_sku'
        description = 'Verify that a specific Azure SKU exists in the target region and return its monthly cost. Use after deciding the target type.'
        input_schema = @{
            type       = 'object'
            properties = @{
                target_type = @{ type = 'string'; description = 'sql_vm, sql_mi, or sql_db' }
                sku         = @{ type = 'string'; description = 'SKU name, e.g. Standard_D4s_v5' }
                region      = @{ type = 'string'; description = 'Azure region, e.g. eastus2' }
            }
            required = @('target_type','sku','region')
        }
    },
    @{
        name        = 'apply_terraform'
        description = 'Run a Terraform action against the SQLPilot infrastructure module. Action is one of: plan, apply, destroy. Apply requires a prior approval gate.'
        input_schema = @{
            type       = 'object'
            properties = @{
                action = @{ type = 'string'; description = 'plan, apply, or destroy' }
            }
            required = @('action')
        }
    },
    @{
        name        = 'restore_database'
        description = 'Backup a database from the source SQL Server and restore it to the target Azure resource. Uses dbatools.'
        input_schema = @{
            type       = 'object'
            properties = @{
                database = @{ type = 'string'; description = 'Database name to migrate' }
                source   = @{ type = 'string'; description = 'Source server name' }
                target   = @{ type = 'string'; description = 'Target Azure resource id or connection string' }
            }
            required = @('database','source','target')
        }
    }
)


# ---------------------------------------------------------------------------
# 5. System prompt - the agent's instructions.
#
# Kept tight: who the agent is, what stages it owns, what tools it has,
# and the discipline it follows (cite blockers, ask at gates).
# ---------------------------------------------------------------------------
$script:SystemPrompt = @"
You are SQLPilot, an AI-augmented agent that helps a DBA migrate an on-prem SQL Server to Azure.

You drive a four-stage flow:
  1. Assess  - run the Phase 1 T-SQL assessment via run_phase1_assessment
  2. Decide  - for each High or Medium severity finding, map it to a KB topic and call consult_kb. Then intersect the viable_targets across all KB results to determine the target (sql_vm, sql_mi, or sql_db). Walk findings by their actual IDs (F001, F002...).
  3. Migrate - call verify_sku, then apply_terraform (plan then apply), then restore_database
  4. Day-to-day - (skeleton run: announce day-2 ops would be installed here)

  FINDING -> KB TOPIC MAPPING (Stage 2):
    - sp_configure xp_cmdshell=1                     -> topic: xp_cmdshell
    - sp_configure clr enabled=1                     -> topic: clr_strict_security
    - CLR Assembly with UNSAFE/EXTERNAL_ACCESS       -> topic: clr_strict_security  (call once, not per assembly)
    - Linked server with non-SQL provider            -> topic: linked_server_non_sql_provider
    - Linked server with SQLNCLI / SQLNCLI11         -> topic: linked_server_legacy_provider
    - Agent job with PowerShell subsystem            -> topic: agent_job_powershell_subsystem
    - Database: ReportServer or ReportServerTempDB   -> topic: ssrs_workload
    - Database: SSISDB                               -> topic: ssis_workload
    - FILESTREAM or FileTable filegroup              -> topic: filestream_filetable
  If a finding does not match any of the above, do not call consult_kb for it - mention it in the report as "no KB match (review manually)".
  Call consult_kb at most once per topic, even if multiple findings map to the same topic.

  TARGET SELECTION (Stage 2):
  After calling consult_kb for each relevant topic, intersect the viable_targets arrays across all responses. If the intersection contains:
    - sql_vm only -> recommend sql_vm
    - sql_mi (with or without sql_vm) -> recommend sql_mi if MI compatibility is acceptable, else sql_vm
    - all three -> recommend sql_db only if the workload is single-DB; otherwise sql_mi
  State the intersection explicitly: "topics A,B,C narrow viable targets to {sql_vm}".

Discipline you must follow:

  GROUNDING (most important):
  - Numbers (database counts, sizes, durations, costs, row counts), names (database names, login names, job names, server names), versions, and findings MUST come from actual tool results in the conversation.
  - You MUST NOT invent, extrapolate, or assume any data point that wasn't returned by a tool call. If you don't have it, say "not yet retrieved" or call the tool.
  - If a tool result has the field "mock": true, you MUST explicitly label that result as "(simulated)" anywhere you cite it. Do not present mock data as if real work happened.
  - DERIVED VALUES INHERIT THE TAINT. If you do arithmetic on a mock value (sum, average, total, percentage, multiplication), the result is ALSO simulated and must be labeled. Example: a stub restore returns rows_restored=1573 per call. Calling it 18 times and reporting "28,314 rows restored" is fabrication. The honest report is "restore_database called 18 times (each returned a simulated result of 1573 rows)."
  - Never report a count you didn't see in a single tool result. If you ran 18 restores, report "18 calls to restore_database (simulated)" - not a fabricated total.
  - Never report timing you didn't measure. If a tool returned elapsed_seconds, use that exact value; otherwise say timing was not measured.

  END-OF-RUN SUMMARY:
  - At the end of the run, before [SQLPILOT_DONE], include an explicit "Tool execution status" section listing which stages called real tools vs simulated stubs.
  - Determine REAL vs SIMULATED by checking the "mock" field on each tool result (mock=true means SIMULATED).
  - Example format:
        Tool execution status:
          Stage 1 (Assess):  REAL       (run_phase1_assessment returned mock=false)
          Stage 2 (Decide):  REAL       (consult_kb returned mock=false for all topics)
          Stage 3 (Migrate): SIMULATED  (verify_sku, apply_terraform, restore_database returned mock=true)
          Stage 4 (Day-2):   NOT EXECUTED (described conceptually only)
  - This section is non-negotiable. The DBA needs to know what actually happened versus what was reasoned about.

  ERROR HANDLING:
  - If any tool returns "status": "error", STOP. Do not continue with simulated, assumed, or example data.
  - When stopping on a tool error, summarize: which tool failed, what the error was, what the hint suggested. Then end with [SQLPILOT_DONE].
  - Do NOT "continue with a representative scenario" or "demonstrate the workflow conceptually" when a tool fails.

  CITATIONS:
  - Every blocker you flag must include the Microsoft citation returned by consult_kb. Never invent guidance or URLs.

  APPROVAL GATES:
  - Before any destructive or costly action (apply_terraform with action=apply, restore_database), pause and announce that a DBA approval gate would be triggered. In this skeleton run, assume the gate is approved and proceed - but make the gate visible.

  STYLE:
  - Be concise. State the next planned action in one sentence before each tool call.
  - When the assessment surfaces N findings, walk them by their actual IDs (F001, F002...) - do not group them into "blockers and warnings" without showing which is which.

You will run against source server: $Source

When you have completed Stage 4 (or stopped on a tool error), end your response with the literal token: [SQLPILOT_DONE]
"@


# ---------------------------------------------------------------------------
# 6. The agent loop.
#
# Standard tool-use pattern:
#   - Send messages to Claude
#   - If response is text, print it and check for done token
#   - If response includes tool_use blocks, dispatch each tool and append
#     tool_result blocks to the next request
#   - Loop until done or MaxTurns hit
# ---------------------------------------------------------------------------
function Invoke-AgentLoop {
    $messages = @(
        @{
            role    = 'user'
            content = @(
                @{ type = 'text'; text = "Begin the migration assessment for source server $Source. Walk through all four stages." }
            )
        }
    )

    for ($turn = 1; $turn -le $MaxTurns; $turn++) {

        $body = @{
            model       = $Model
            max_tokens  = 4096
            system      = $SystemPrompt
            tools       = $ToolDefinitions
            messages    = $messages
        } | ConvertTo-Json -Depth 16

        $headers = @{
            'x-api-key'         = $env:ANTHROPIC_API_KEY
            'anthropic-version' = '2023-06-01'
            'content-type'      = 'application/json'
        }

        try {
            $response = Invoke-RestMethod `
                -Uri 'https://api.anthropic.com/v1/messages' `
                -Method Post `
                -Headers $headers `
                -Body $body
        } catch {
            Write-Host ''
            Write-Host '[ERROR] Anthropic API call failed:' -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message -ForegroundColor Red }
            throw
        }

        # Append the assistant's response to the conversation.
        $messages += @{
            role    = 'assistant'
            content = $response.content
        }

        # Walk every block in the response. Text blocks get printed; tool_use
        # blocks get dispatched and their results queued for the next turn.
        $toolResults = @()

        foreach ($block in $response.content) {

            switch ($block.type) {

                'text' {
                    if ($block.text.Trim()) {
                        Write-Plan $block.text.Trim()
                        Add-DecisionLogEntry -Kind 'plan' -Payload @{ text = $block.text.Trim() }
                    }
                }

                'tool_use' {
                    $toolName = $block.name
                    # Convert the input PSCustomObject to a hashtable for easier handling.
                    $toolArgs = @{}
                    if ($block.input) {
                        $block.input.PSObject.Properties | ForEach-Object {
                            $toolArgs[$_.Name] = $_.Value
                        }
                    }

                    if (-not $ToolRegistry.ContainsKey($toolName)) {
                        $errResult = @{ status = 'error'; message = "Unknown tool: $toolName" }
                        $toolResults += @{
                            type        = 'tool_result'
                            tool_use_id = $block.id
                            content     = ($errResult | ConvertTo-Json -Compress)
                            is_error    = $true
                        }
                        continue
                    }

                    # Dispatch.
                    # Pass the hashtable as a named parameter (-ToolArgs) so
                    # PowerShell binds it as a single hashtable rather than
                    # unrolling each key/value pair into positional args.
                    # (The tool functions all declare param([hashtable] $ToolArgs).)
                    $toolFnName = $ToolRegistry[$toolName]
                    $result     = & $toolFnName -ToolArgs $toolArgs
                    $resultJ    = $result | ConvertTo-Json -Depth 8 -Compress

                    Write-Observe "$toolName -> $($result.status)$(if ($result.mock) { ' (mock)' })"

                    $toolResults += @{
                        type        = 'tool_result'
                        tool_use_id = $block.id
                        content     = $resultJ
                    }
                }
            }
        }

        # If the assistant called any tools, we owe it the results in the next turn.
        if ($toolResults.Count -gt 0) {
            $messages += @{
                role    = 'user'
                content = $toolResults
            }
            continue
        }

        # No tool calls in this turn - check for the done token.
        $allText = ($response.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
        if ($allText -match '\[SQLPILOT_DONE\]') {
            Write-Decide 'Agent reports complete.'
            Add-DecisionLogEntry -Kind 'final' -Payload @{ message = 'Agent completed normally.' }
            return
        }

        # Stop_reason 'end_turn' with no done token means the agent stopped
        # without finishing. Surface this rather than silently looping.
        if ($response.stop_reason -eq 'end_turn') {
            Write-Decide 'Agent ended turn without [SQLPILOT_DONE]. Stopping.'
            Add-DecisionLogEntry -Kind 'final' -Payload @{ message = 'Agent ended without done token.' }
            return
        }
    }

    Write-Host ''
    Write-Host "[WARN] Max turns ($MaxTurns) reached without completion." -ForegroundColor Yellow
    Add-DecisionLogEntry -Kind 'final' -Payload @{ message = "Hit MaxTurns=$MaxTurns without completion." }
}


# ---------------------------------------------------------------------------
# 7. Entry point.
# ---------------------------------------------------------------------------
Write-Banner "SQLPilot v0 (skeleton, stub tools)"
Write-Host "  Source server : $Source"
Write-Host "  Model         : $Model"
Write-Host "  Max turns     : $MaxTurns"
Write-Host "  Output dir    : $GeneratedDir"
Write-Host ''
Write-Host "  Note: all 5 tools are stubs returning mock data. No SQL or Azure"
Write-Host "        calls will be made. This run validates the agent loop only."

Add-DecisionLogEntry -Kind 'plan' -Payload @{
    event  = 'agent_start'
    source = $Source
    model  = $Model
}

Invoke-AgentLoop

Write-Banner 'SQLPilot run complete'
Write-Host "  Decision log: $script:DecisionLogPath"
Write-Host "  Entries     : $($script:DecisionLog.Count)"
Write-Host ''
