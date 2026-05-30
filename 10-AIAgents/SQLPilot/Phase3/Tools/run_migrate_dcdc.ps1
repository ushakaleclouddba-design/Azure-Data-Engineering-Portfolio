<#
.SYNOPSIS
    SQLPilot - background runner for the DC->DC migration.

.DESCRIPTION
    The /api/migrate/dcdc endpoint launches THIS script as a detached
    background process (Start-Process pwsh -File ...), mirroring how
    /api/assess/run launches the Phase 1 wrapper. We do this because
    Export-DbaInstance is slow (~8 min) and the server's single-threaded
    HttpListener would drop the connection on a long inline run (the
    "connection forcibly closed" symptom seen during XE export).

    The runner:
      1. Dot-sources restore.ps1 (provides Initialize-RestoreCoords, which
         migrate_logins.ps1 reuses), then migrate_logins.ps1 and
         migrate_dcdc.ps1 from the Tools dir.
      2. Calls Invoke-RealMigrateDcToDc with the passed parameters.
      3. Writes the result hashtable as JSON to -ResultPath. The status
         endpoint (/api/migrate/dcdc/status) reads that file to know the
         job is done and to return the result.

    All console output goes to the redirected log file (set by the parent
    Start-Process), so the status endpoint can tail progress live.

.NOTES
    Author : Kale
    Pattern: mirrors the standalone wrapper that /api/assess/run executes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]   $ToolsDir,
    [Parameter(Mandatory)] [string]   $Source,
    [Parameter(Mandatory)] [string]   $Destination,
    [ValidateSet('whole','db')] [string] $Scope = 'whole',
    [string[]]                         $Databases,
    [string]                           $DatabasesB64,
    [ValidateSet('dbatools','native')] [string] $Engine = 'dbatools',
    [Parameter(Mandatory)] [string]   $ResultPath,
    [string]                          $ExportPath = 'C:\SQLPilot\Exports'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# BUG-019/020 fix (revised): Invoke-Sqlcmd (used by the NATIVE engine's logins
# and validate steps) needs the SqlServer module. PowerShell's auto-load fails
# silently in some sessions, so we import it explicitly — but ONLY for the
# native engine. SqlServer and dbatools conflict on SMO assemblies; importing
# SqlServer when the dbatools engine is selected breaks dbatools loading
# (that was BUG-026). dbatools provides its own query cmdlets, so it doesn't
# need SqlServer at all.
# ---------------------------------------------------------------------------
if ($Engine -eq 'native') {
    if (-not (Get-Module -Name SqlServer)) {
        try {
            Import-Module SqlServer -DisableNameChecking -ErrorAction Stop
            Write-Host "[runner] SqlServer module imported for native engine (v$((Get-Module SqlServer).Version))" -ForegroundColor DarkGray
        } catch {
            Write-Host "[runner] WARN: SqlServer module not available — native logins/validate may fail. Install: Install-Module SqlServer -Scope CurrentUser" -ForegroundColor DarkYellow
        }
    }
}

function Write-Result {
    param($Obj)
    try {
        $json = $Obj | ConvertTo-Json -Depth 12
        # Write atomically: temp file then move, so the status endpoint never
        # reads a half-written file.
        $tmp = "$ResultPath.tmp"
        [System.IO.File]::WriteAllText($tmp, $json)
        Move-Item -Path $tmp -Destination $ResultPath -Force
    } catch {
        # Last-ditch: write a minimal error file so the poller doesn't hang.
        [System.IO.File]::WriteAllText($ResultPath, '{"status":"error","error":"runner failed to serialize result"}')
    }
}

Write-Host "[runner] DC->DC migrate starting: $Source -> $Destination (scope=$Scope, engine=$Engine)" -ForegroundColor Cyan
Write-Host "[runner] ToolsDir=$ToolsDir  ResultPath=$ResultPath"

# --- Dot-source the tools, in dependency order. -----------------------------
# restore.ps1 first (Initialize-RestoreCoords), then migrate_logins.ps1
# (Invoke-RealMigrateLogins, used by migrate_dcdc's T-SQL fallback), then
# migrate_dcdc.ps1 (Invoke-RealMigrateDcToDc).
$loadOrder = @('restore.ps1','migrate_logins.ps1','migrate_tde.ps1','migrate_databases.ps1','migrate_jobs.ps1','migrate_linkedservers.ps1','migrate_configs.ps1','migrate_ssis.ps1','migrate_validate.ps1','migrate_dcdc.ps1')
foreach ($name in $loadOrder) {
    $p = Join-Path $ToolsDir $name
    if (-not (Test-Path $p)) {
        Write-Host "[runner] MISSING tool: $p" -ForegroundColor Red
        Write-Result @{ status='error'; error="Required tool not found: $name at $p" }
        exit 1
    }
    . $p
    Write-Host "[runner]   loaded $name" -ForegroundColor DarkGray
}

# Tools resolve Terraform/ via $script:ScriptRoot; set it to the project root
# (parent of ToolsDir) so Initialize-RestoreCoords can find terraform output.
$script:ScriptRoot = Split-Path -Parent $ToolsDir

if (-not (Get-Command -Name 'Invoke-RealMigrateDcToDc' -ErrorAction SilentlyContinue)) {
    Write-Host "[runner] Invoke-RealMigrateDcToDc not defined after dot-source." -ForegroundColor Red
    Write-Result @{ status='error'; error='Invoke-RealMigrateDcToDc not available after loading migrate_dcdc.ps1' }
    exit 1
}

# --- Decode databases from base64-JSON if present (BUG-008 fix). ------------
# pwsh -File mode can't bind repeated tokens to a [string[]] parameter — only
# the first token survives. server.ps1 encodes the list as base64-JSON and
# sends it in -DatabasesB64. Direct -Databases still works for CLI usage.
if ($DatabasesB64) {
    try {
        $dbJson    = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($DatabasesB64))
        $Databases = @($dbJson | ConvertFrom-Json)
        Write-Host "[runner] decoded $($Databases.Count) database(s) from -DatabasesB64" -ForegroundColor DarkGray
    } catch {
        Write-Host "[runner] FAILED to decode -DatabasesB64: $($_.Exception.Message)" -ForegroundColor Red
        Write-Result @{ status='error'; error="Failed to decode -DatabasesB64: $($_.Exception.Message)" }
        exit 1
    }
}

# --- Build call parameters. -------------------------------------------------
$callParams = @{
    Source      = $Source
    Destination = $Destination
    Scope       = $Scope
    Engine      = $Engine
    ExportPath  = $ExportPath
}
if ($Scope -eq 'db' -and $Databases -and $Databases.Count -gt 0) {
    $callParams['Databases'] = $Databases
}

# Engine handling:
#   dbatools -> normal call; the tool auto-selects live dbatools, and falls
#               back to script-out (Export-DbaInstance) when the destination
#               is unreachable.
#   native   -> the user's org forbids dbatools. The tool's Initialize-Dbatools
#               would otherwise attempt Install-Module dbatools when the module
#               isn't present — exactly what a locked-down org forbids. We
#               pre-set the tool's script-scoped guard flags so that check
#               short-circuits to "no dbatools" WITHOUT attempting any install,
#               forcing the tool down its T-SQL fallback path. No tool edit
#               required; these are the same flags Initialize-Dbatools reads
#               first. (If a future tool revision adds a -NoDbatools switch,
#               prefer that.)
if ($Engine -eq 'native') {
    Write-Host "[runner] Engine=native: forbidding dbatools (no Install-Module), using T-SQL path." -ForegroundColor Yellow
    Set-Variable -Name 'DbatoolsChecked' -Value $true  -Scope Script
    Set-Variable -Name 'DbatoolsOk'      -Value $false -Scope Script
}

# --- Run. -------------------------------------------------------------------
try {
    $result = Invoke-RealMigrateDcToDc @callParams
    if (-not ($result -is [hashtable]) -and -not ($result -is [System.Collections.Specialized.OrderedDictionary])) {
        # Normalize to a hashtable shell if the tool returned something odd.
        $result = @{ status='ok'; raw="$result" }
    }
    # Stamp the engine the UI asked for, so the result is self-describing.
    $result['engine_requested'] = $Engine
    Write-Result $result
    Write-Host "[runner] done. status=$($result.status)" -ForegroundColor Green
    exit 0
} catch {
    Write-Host "[runner] EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red
    Write-Result @{ status='error'; error="$($_.Exception.Message)"; engine_requested=$Engine; source=$Source; destination=$Destination }
    exit 1
}
