 <#
.SYNOPSIS
    SQL Server Cloud Migration Assessment - All-in-One Agent
    Connects to SQL Server, runs the assessment, and produces a formatted
    Excel report in a single execution. No external Python or converter needed.

.DESCRIPTION
    This script is the complete client-side workflow:
        1. Connects to your SQL Server (single instance or CMS hub)
        2. Runs the read-only migration assessment script
        3. Captures all 15 result sets as structured data
        4. Builds a formatted .xlsx report with Summary, Critical Findings,
           and per-server tabs
        5. Saves the .xlsx file next to this script

    The script is READ-ONLY against your SQL Server. It runs SELECT statements
    against system views (sys.* and msdb.*). It does not modify any data,
    schema, or configuration.

.NOTES
    REQUIREMENTS:
      - PowerShell 5.1 or later (built into Windows 10+ / Windows Server 2016+)
      - SqlServer PowerShell module  (auto-installed if missing)
      - ImportExcel PowerShell module (auto-installed if missing)
      - Read access to system views on the target SQL Server

    Both modules install to the current user's profile - no admin rights needed.

    HOW TO RUN:
      1. Edit the SQL_SERVER variable at the top of this script.
      2. Right-click this file -> "Run with PowerShell".

    If you get "running scripts is disabled on this system", run this once
    in an elevated PowerShell window:
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

#>

# =============================================================================
# ARCHITECTURE OVERVIEW
# =============================================================================
#
# Execution flow (top to bottom):
#
#   1. CONFIG          - User edits $SqlInstance and $CmsGroup at the top.
#                        Everything below is configuration-free.
#
#   2. SCRIPT DIR      - Resolve where this .ps1 lives (handles dot-sourcing,
#                        ISE, and pasted-into-PowerShell edge cases).
#
#   3. SANITY CHECKS   - Verify 01_Assessment_Script.sql is alongside this file.
#                        Fail fast with a clear message if it's missing.
#
#   4. MODULES         - Auto-install SqlServer + ImportExcel modules to the
#                        current user's profile. No admin rights needed.
#
#   5. SERVER LIST     - If $CmsGroup is empty -> single-server mode.
#                        Otherwise -> query CMS host's msdb for registered
#                        servers and build the fan-out list.
#
#   6. ASSESSMENT      - For each target server, run 01_Assessment_Script.sql
#                        and capture all 17 result sets as DataTables.
#                        Per-server failures are logged and skipped (don't
#                        halt the whole run).
#
#   7. EXCEL BUILD     - Build the workbook tab by tab using ImportExcel +
#                        EPPlus. Most tabs are written cell-by-cell rather
#                        than via Export-Excel because layout requirements
#                        (banners, merged cells, color coding) outgrew what
#                        Export-Excel can do cleanly.
#
#                        Tabs created (in build order):
#                          - Summary           (per-server roll-up)
#                          - Critical Findings (estate-wide sortable)
#                          - Executive Summary (narrative + scoreboard)
#                          - Remediation Plan  (issue + recommendation)
#                          - <Per-server>      (one tab per assessed server)
#
#   8. REORDER         - Move tabs to their final left-to-right order:
#                        Executive Summary | Summary | Critical Findings |
#                        Remediation Plan | <per-server>
#
#   9. SAVE & FINISH   - Close the package, print path to the .xlsx, and
#                        wait for Enter so the window doesn't close on errors.
#
# Why PowerShell instead of Python:
#   - Invoke-Sqlcmd returns DataTables natively (column types preserved)
#   - Target audience is DBAs - PowerShell is already on every SQL Server box
#   - No external dependencies beyond two modules that auto-install
#
# Why ImportExcel + direct EPPlus instead of openpyxl:
#   - Single Windows binary, no Python install
#   - EPPlus handles complex formatting (merged cells, conditional fills,
#     row heights) more reliably than openpyxl over the wire
#
# Read-only safety:
#   - Every SQL is SELECT against sys.* and msdb.* system views
#   - No DDL, no DML, no sp_configure changes
#   - Worst case: 2-10 seconds of DMV CPU on each target server
#
# =============================================================================


# =============================================================================
# >>>>>  EDIT THIS LINE BEFORE RUNNING  <<<<<
# =============================================================================
#
# Set this to the SQL Server you want to assess.
#
#  - For a SINGLE-SERVER assessment: set this to the instance you want assessed.
#       $SqlInstance = 'MyServer'
#       $CmsGroup = ''           <-- leave empty
#
#  - For a CMS MULTI-SERVER assessment: set this to your CMS HOST (the server
#    where the Central Management Server is registered) and put the CMS group
#    name in $CmsGroup. The agent will fan out to every server in the group
#    AND assess the CMS host itself (CMS does not register its own host).
#       $SqlInstance = 'MyCmsHost'
#       $CmsGroup    = 'MyEstateGroup'
#
# The CMS host can be anywhere reachable - on this machine, another server,
# or your laptop. The agent does not assume it lives on any specific box.
#
  $SqlInstance = 'Node5'
$CmsGroup    = 'ushadc_estate'  


# Output Excel filename. Defaults to a date-stamped name next to this script.
$OutputXlsx = "Migration_Assessment_Report_$(Get-Date -Format 'yyyy-MM-dd_HHmm').xlsx"

# Optional: SQL login instead of Windows auth. Leave $SqlUser empty for Windows auth.
$SqlUser     = ''
$SqlPassword = ''

# Backward compatibility - if someone is using the old variable name $SqlServer
# from a previous version of this script, fall through to it.
if ($SqlInstance -eq 'CHANGE_ME' -and (Get-Variable -Name SqlServer -ErrorAction SilentlyContinue)) {
    if ($SqlServer -and $SqlServer -ne 'CHANGE_ME') {
        $SqlInstance = $SqlServer
    }
}

# =============================================================================
# Internals - do not edit below unless you know what you are doing.
# =============================================================================

$ErrorActionPreference = 'Stop'

# Resolve the script's directory robustly. $MyInvocation.MyCommand.Path is null
# when the script is dot-sourced, pasted into a PowerShell session, or run from
# the ISE. Fall back to PSCommandPath, then PSScriptRoot, then the current
# working directory.
$scriptDir = $null
if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
} elseif ($PSCommandPath) {
    $scriptDir = Split-Path -Parent $PSCommandPath
} elseif ($PSScriptRoot) {
    $scriptDir = $PSScriptRoot
} else {
    $scriptDir = (Get-Location).Path
    Write-Host "Note: running from current directory ($scriptDir) - script path could not be auto-detected." -ForegroundColor Yellow
}
Set-Location $scriptDir

Clear-Host
Write-Host ''
Write-Host '===============================================================================' -ForegroundColor Cyan
Write-Host '  SQL Server Cloud Migration Assessment - All-in-One Agent' -ForegroundColor Cyan
Write-Host '===============================================================================' -ForegroundColor Cyan
Write-Host ''

# -----------------------------------------------------------------------------
# Sanity checks
# -----------------------------------------------------------------------------
# Fail fast and clearly. The script assumes 01_Assessment_Script.sql is in the
# same folder. If it's missing, no point doing anything else - the whole agent
# is built around running that SQL.
#
# Common failure: someone copied just the .ps1 file to a new machine and left
# the .sql behind. The error message tells them what to do.

if ($SqlInstance -eq 'CHANGE_ME') {
    Write-Host '[ERROR] You have not edited the server name yet.' -ForegroundColor Red
    Write-Host ''
    Write-Host '        Open this file in Notepad, find the line:'
    Write-Host ''
    Write-Host "            `$SqlInstance = 'CHANGE_ME'"
    Write-Host ''
    Write-Host '        Replace CHANGE_ME with your SQL Server instance name.'
    Write-Host '        Examples:'
    Write-Host "            `$SqlInstance = 'YourServerName'"
    Write-Host "            `$SqlInstance = 'YourServer\InstanceName'"
    Write-Host "            `$SqlInstance = 'YourServer.YourDomain.com,1433'"
    Write-Host ''
    Write-Host '        For a CMS multi-server run, also set:'
    Write-Host "            `$CmsGroup    = 'YourEstateGroupName'"
    Write-Host ''
    Read-Host 'Press Enter to exit'
    exit 1
}

if (-not (Test-Path '01_Assessment_Script.sql')) {
    Write-Host '[ERROR] 01_Assessment_Script.sql is missing from this folder.' -ForegroundColor Red
    Write-Host '        Make sure you unzipped the entire package.'
    Read-Host 'Press Enter to exit'
    exit 1
}

# -----------------------------------------------------------------------------
# Module installation - SqlServer and ImportExcel
# -----------------------------------------------------------------------------
# Two modules are required:
#
#   SqlServer   - provides Invoke-Sqlcmd. We use this rather than the older
#                 sqlps module because it returns DataTables (typed columns)
#                 and supports modern auth options like -TrustServerCertificate.
#
#   ImportExcel - provides Export-Excel and exposes the underlying EPPlus
#                 ExcelPackage object. We use ImportExcel for initial sheet
#                 creation but switch to direct EPPlus calls when we need
#                 cell-level control (merged banners, row heights, fills).
#
# Both install to the CurrentUser scope - no admin rights, no PSGallery trust
# prompts after the first run. If your environment blocks PSGallery, the user
# needs to ask their admin to install both modules with -Scope AllUsers.

function Ensure-Module {
    param([string]$Name)
    if (Get-Module -ListAvailable -Name $Name) {
        return
    }
    Write-Host "Installing $Name module to your user profile (one-time setup)..." -ForegroundColor Yellow
    try {
        # Trust PSGallery so we don't get prompted
        if ((Get-PSRepository -Name 'PSGallery').InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Host "  $Name installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Could not install $Name." -ForegroundColor Red
        Write-Host "        $_"
        Write-Host ''
        Write-Host '        If your environment blocks PowerShell Gallery, ask your admin'
        Write-Host '        to install these modules ahead of time:'
        Write-Host '            Install-Module SqlServer -Scope AllUsers'
        Write-Host '            Install-Module ImportExcel -Scope AllUsers'
        Read-Host 'Press Enter to exit'
        exit 1
    }
}

Ensure-Module -Name 'SqlServer'
Ensure-Module -Name 'ImportExcel'

Import-Module SqlServer -ErrorAction Stop
Import-Module ImportExcel -ErrorAction Stop

Write-Host "Server:       $SqlInstance"
if ($CmsGroup) {
    Write-Host "CMS Group:    $CmsGroup"
    Write-Host "Mode:         Multi-server fan-out via CMS"
} else {
    Write-Host "Mode:         Single-server assessment"
}
Write-Host "Output:       $OutputXlsx"
Write-Host ''

# -----------------------------------------------------------------------------
# Build the auth argument
# -----------------------------------------------------------------------------
# Default is Windows auth (most common). If the user supplied $SqlUser and
# $SqlPassword at the top of the script, switch to SQL auth instead.
#
# We pass -TrustServerCertificate because most lab/on-prem SQL Servers use
# self-signed certs. Newer SqlServer module versions REQUIRE encryption by
# default, and refuse self-signed certs unless this flag is set. Without it,
# you get "The certificate chain was issued by an authority that is not
# trusted" and the connection fails.

$invokeArgs = @{
    QueryTimeout           = 600
    ConnectionTimeout      = 30
    OutputAs               = 'DataTables'   # Returns each result set as a DataTable
    TrustServerCertificate = $true          # Required for lab / self-signed cert environments
    Encrypt                = 'Optional'     # Don't fail if encryption isn't available
    Verbose                = $false
    ErrorAction            = 'Stop'
}

if ($SqlUser) {
    $secure = ConvertTo-SecureString $SqlPassword -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($SqlUser, $secure)
    $invokeArgs['Credential'] = $cred
}

# -----------------------------------------------------------------------------
# Resolve the list of servers to assess
# -----------------------------------------------------------------------------
# Two modes:
#
#   Single-server: $CmsGroup is empty. Just assess $SqlInstance.
#
#   CMS fan-out: $CmsGroup is set. Connect to $SqlInstance (the CMS HOST) and
#   query its msdb.dbo.sysmanagement_shared_registered_servers table to get
#   the list of all servers registered under that group. We then assess each
#   server in the list PLUS the CMS host itself, because CMS does not register
#   its own host (a quirk of the CMS design - the host is implicit).
#
# CMS is just a registry that lives in msdb on a designated SQL Server. It is
# NOT global across the estate; it lives on one box. We read it directly via
# T-SQL rather than going through SSMS or SMO - that keeps the agent
# dependency-free and lets it run from anywhere that can reach the CMS host.
#  - If $CmsGroup is empty: just assess $SqlInstance (single-server mode).
#  - If $CmsGroup is set: $SqlInstance is the CMS host. Query its msdb to find
#    every server in the named group, then add $SqlInstance itself (CMS does
#    not register its own host).
#
# We query CMS via T-SQL on msdb rather than the SQLSERVER:\SQLRegistration PSDrive
# because the PSDrive approach reads the LOCAL machine's SSMS registrations,
# not the actual CMS catalog on the remote server. The msdb path works whether
# the CMS lives on this box or anywhere else.

function Get-CmsRegisteredServers {
    param(
        [Parameter(Mandatory)] [string] $CmsHostInstance,
        [Parameter(Mandatory)] [string] $GroupName,
        [hashtable] $InvokeArgs
    )

    # Walk the group hierarchy in case the named group is nested.
    # Top-level groups have parent_id = NULL.
    $sql = @"
;WITH GroupTree AS (
    SELECT server_group_id, name, parent_id
    FROM msdb.dbo.sysmanagement_shared_server_groups_internal
    WHERE name = '$($GroupName -replace "'", "''")'
    UNION ALL
    SELECT g.server_group_id, g.name, g.parent_id
    FROM msdb.dbo.sysmanagement_shared_server_groups_internal g
    INNER JOIN GroupTree t ON g.parent_id = t.server_group_id
)
SELECT DISTINCT s.server_name AS ServerName
FROM msdb.dbo.sysmanagement_shared_registered_servers_internal s
INNER JOIN GroupTree g ON g.server_group_id = s.server_group_id
ORDER BY s.server_name;
"@

    $args = $InvokeArgs.Clone()
    $args['ServerInstance'] = $CmsHostInstance
    $args['Query']          = $sql
    $args.Remove('InputFile') | Out-Null

    $rows = Invoke-Sqlcmd @args
    if ($rows -is [System.Data.DataTable]) {
        $serverNames = @($rows | ForEach-Object { $_.ServerName })
    } else {
        $serverNames = @($rows | ForEach-Object { $_.ServerName })
    }
    return $serverNames
}

$serversToAssess = @()
if ($CmsGroup) {
    Write-Host "Discovering registered servers in CMS group '$CmsGroup' on '$SqlInstance'..."
    try {
        $cmsServers = Get-CmsRegisteredServers -CmsHostInstance $SqlInstance -GroupName $CmsGroup -InvokeArgs $invokeArgs
        $serversToAssess = @($cmsServers)
        # Add the CMS host itself - it cannot register itself in its own CMS
        if ($serversToAssess -notcontains $SqlInstance) {
            $serversToAssess += $SqlInstance
        }
        Write-Host "  Found $($serversToAssess.Count) servers (including the CMS host)." -ForegroundColor Green
        Write-Host "  Servers: $($serversToAssess -join ', ')" -ForegroundColor Green
    } catch {
        Write-Host "  Could not enumerate CMS group. Error: $_" -ForegroundColor Yellow
        Write-Host "  Falling back to assessing $SqlInstance only." -ForegroundColor Yellow
        $serversToAssess = @($SqlInstance)
    }
} else {
    $serversToAssess = @($SqlInstance)
}

# -----------------------------------------------------------------------------
# Run the assessment against each server, capturing all 17 result sets
# -----------------------------------------------------------------------------
# Loop through the resolved server list and assess each one. The pattern:
#
#   1. Build connection args (server name + auth + trust cert)
#   2. Invoke-Sqlcmd with the SQL file as -InputFile
#   3. Capture the array of DataTables in $tables
#   4. Map each DataTable to its section label using $SectionLabels (positional)
#   5. Stash the result in $allData[$server]
#
# Critical resilience pattern: each server is wrapped in try/catch. If Node7
# fails (e.g. SSPI hiccup, network blip, dead service), we log the error,
# move on to Node8, and the Excel still gets built with whatever succeeded.
# This is the difference between a fragile script and a production-grade one.
#
# The -OutputAs DataTables flag is what gives us typed columns. Without it,
# Invoke-Sqlcmd returns PSObjects and we'd have to parse strings - which
# breaks on null values, ints with thousand-separators, and dates in the
# wrong locale.

# Map of section index (0..14) to label - matches what the SQL script emits
$SectionLabels = @(
    '01_Instance_Summary',
    '02_Instance_Configuration',
    '03_Linked_Servers',
    '04_SQL_Agent_Jobs',
    '05_Database_Inventory',
    '06_DB_Level_Findings',
    '07_TSQL_Code_Scan',
    '08_SKU_Features',
    '09_CLR_Assemblies',
    '10_Database_Files',
    '11_Availability_Groups',
    '12_Database_Mirroring',
    '13_Log_Shipping_Primary',
    '13_Log_Shipping_Secondary',
    '14_Replication_Subscribers',
    '14_Replication_Publishers',
    '15_Cloud_Migration_Matrix'
)

$SectionTitles = @{
    '01_Instance_Summary'          = '1. Instance Summary'
    '02_Instance_Configuration'    = '2. Instance Configuration (sp_configure)'
    '03_Linked_Servers'            = '3. Linked Servers'
    '04_SQL_Agent_Jobs'            = '4. SQL Agent Jobs'
    '05_Database_Inventory'        = '5. Database Inventory'
    '06_DB_Level_Findings'         = '6. DB-Level Findings'
    '07_TSQL_Code_Scan'            = '7. T-SQL Code Scan'
    '08_SKU_Features'              = '8. Per-DB SKU Features'
    '09_CLR_Assemblies'            = '9. CLR Assemblies'
    '10_Database_Files'            = '10. Database Files'
    '11_Availability_Groups'       = '11. Availability Groups'
    '12_Database_Mirroring'        = '12. Database Mirroring'
    '13_Log_Shipping_Primary'      = '13a. Log Shipping (Primary)'
    '13_Log_Shipping_Secondary'    = '13b. Log Shipping (Secondary)'
    '14_Replication_Subscribers'   = '14a. Replication Subscribers'
    '14_Replication_Publishers'    = '14b. Replication Publishers'
    '15_Cloud_Migration_Matrix'    = '15. Cloud Migration Matrix'
}

# -----------------------------------------------------------------------------
# JSON export helper - added for SQLPilot (Phase 2) integration
# -----------------------------------------------------------------------------
# At the end of the run, in addition to the .xlsx, we write a parallel .json
# file with identical structure. The JSON is the machine-readable contract
# the SQLPilot agent consumes - same section labels, same column names, same
# row contents, just shaped for ConvertTo-Json instead of EPPlus cells.
#
# Why a separate function:
#   - DataTables don't serialize cleanly via ConvertTo-Json (System.Data
#     internal types confuse the serializer). We coerce each row to an
#     ordered hashtable first, which serializes predictably.
#   - Keeps the JSON structure logic in one place rather than scattered
#     through the Excel-build section.
#
# Output shape:
#   {
#     "metadata": { generated_at, source_xlsx, servers_assessed, ... },
#     "servers": {
#       "<ServerName>": {
#         "<section_label>": [ { col1: val, col2: val }, ... ],
#         ...
#       }
#     }
#   }
function Convert-AllDataToJsonStructure {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable] $AllData,

        [string] $SourceXlsxPath = ''
    )

    $servers = [ordered]@{}

    # Sort server names for stable output (same ordering across runs).
    foreach ($serverName in ($AllData.Keys | Sort-Object)) {
        $serverSections = $AllData[$serverName]
        $serverOut      = [ordered]@{}

        # Iterate sections in the canonical SectionLabels order so the JSON
        # has predictable key order rather than hashtable-iteration order.
        foreach ($sectionLabel in $SectionLabels) {
            if (-not $serverSections.ContainsKey($sectionLabel)) {
                $serverOut[$sectionLabel] = @()
                continue
            }

            $dt = $serverSections[$sectionLabel]
            if ($null -eq $dt -or $dt.Rows.Count -eq 0) {
                $serverOut[$sectionLabel] = @()
                continue
            }

            # Convert each DataRow to an ordered hashtable. We use [ordered]
            # so column order in the JSON matches column order in the SQL
            # results (which is what readers will expect).
            $rowList = @()
            foreach ($row in $dt.Rows) {
                $rowHash = [ordered]@{}
                foreach ($col in $dt.Columns) {
                    $val = $row[$col]
                    # Convert DBNull to $null so JSON gets a real null,
                    # not the string "System.DBNull".
                    if ($val -is [System.DBNull]) { $val = $null }
                    $rowHash[$col.ColumnName] = $val
                }
                $rowList += $rowHash
            }
            $serverOut[$sectionLabel] = $rowList
        }

        $servers[$serverName] = $serverOut
    }

    return [ordered]@{
        metadata = [ordered]@{
            generated_at     = (Get-Date).ToString('o')
            phase1_version   = '1.0'
            servers_assessed = $AllData.Count
            source_xlsx      = $SourceXlsxPath
            section_labels   = $SectionLabels
        }
        servers = $servers
    }
}

# Collect: $allData[$serverName] = @{ '01_Instance_Summary' = DataTable; ... }
$allData = @{}

foreach ($server in $serversToAssess) {
    Write-Host "Assessing $server..." -NoNewline
    $tStart = Get-Date

    try {
        $invokeArgs['ServerInstance'] = $server
        $invokeArgs['InputFile']      = '01_Assessment_Script.sql'

        $resultSets = Invoke-Sqlcmd @invokeArgs

        # When OutputAs=DataTables, the cmdlet returns either:
        #  - A single DataTable (if 1 result set)
        #  - A DataTableCollection or array of DataTables (if multiple)
        # Normalize to an array.
        if ($null -eq $resultSets) {
            $tables = @()
        } elseif ($resultSets -is [System.Data.DataTable]) {
            $tables = @($resultSets)
        } else {
            $tables = @($resultSets)
        }

        # Map result sets to section labels by index (the script emits them in order)
        $serverSections = @{}
        for ($i = 0; $i -lt $SectionLabels.Count -and $i -lt $tables.Count; $i++) {
            $label = $SectionLabels[$i]
            $serverSections[$label] = $tables[$i]
        }

        # If the server name in the data differs from the connection name, prefer
        # the data's own ServerName from section 01
        $resolvedName = $server
        $sec01 = $serverSections['01_Instance_Summary']
        if ($sec01 -and $sec01.Rows.Count -gt 0 -and $sec01.Columns.Contains('ServerName')) {
            $resolvedName = [string]$sec01.Rows[0]['ServerName']
        }

        $allData[$resolvedName] = $serverSections

        $elapsed = ((Get-Date) - $tStart).TotalSeconds
        Write-Host (" done ({0:N1}s, {1} sections)" -f $elapsed, $tables.Count) -ForegroundColor Green

    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Error: $_"
        Write-Host '  (continuing with next server)'
    }
}

if ($allData.Count -eq 0) {
    Write-Host ''
    Write-Host '[ERROR] No servers assessed successfully. Cannot build report.' -ForegroundColor Red
    Read-Host 'Press Enter to exit'
    exit 1
}

# -----------------------------------------------------------------------------
# Build the Excel report
# -----------------------------------------------------------------------------
# At this point $allData is a hashtable of { server -> { section -> DataTable } }.
# All SQL is done. Everything below is pure Excel construction.
#
# We use the ImportExcel module, but most sheets are written via direct EPPlus
# calls rather than Export-Excel. Reason: Export-Excel is great for "dump a
# DataTable into a sheet with a header row" but breaks down when you need:
#   - Banner rows merged across N columns
#   - Different column counts in different sections of the same sheet
#   - Cell-level color coding driven by data values
#   - Custom row heights for visual padding
#
# By holding onto the underlying $pkg (ExcelPackage) handle and writing cells
# directly, we get full control without fighting the library.
#
# Sheet build order does NOT match final tab order - we reorder at the end.
# Build order is just whatever's most convenient given data dependencies
# (e.g. Critical Findings has to be built before Executive Summary because
# the score calculation depends on the findings list).

Write-Host ''
Write-Host 'Building Excel report...'

# Remove any existing file first
if (Test-Path $OutputXlsx) {
    Remove-Item $OutputXlsx -Force
}

# Color palette (matches the look from the previous Excel report)
$NavyHex   = '#1F3864'
$LightHex  = '#D9E2F3'
$RedFill   = '#FCE4E4'
$AmberFill = '#FFF2CC'
$RedText   = '#C00000'
$AmberText = '#ED7D31'
$GreenText = '#2E7D32'
$GreyHex   = '#808080'

# We use Export-Excel to write each table, then Set-ExcelRange / conditional
# formatting via the package's ConditionalText feature.

$pkg = $null  # ExcelPackage handle, kept open across multiple sheet writes

# --- Helper: classify severity text into a fill color
function Get-SeverityFill {
    param([string]$Text)
    if (-not $Text) { return $null }
    $t = $Text.ToLower()
    if ($t -match 'high')               { return $RedFill }
    if ($t -match 'medium' -or $t -match 'warn') { return $AmberFill }
    return $null
}

# --- Helper: classify severity text into a text color
function Get-SeverityTextColor {
    param([string]$Text)
    if (-not $Text) { return $null }
    $t = $Text.ToLower()
    if ($t -match 'high' -or $t -match 'unsafe' -or $t -eq 'no') { return $RedText }
    if ($t -match 'medium' -or $t -match 'warn')                 { return $AmberText }
    if ($t -match 'info' -or $t -eq 'yes' -or $t -match 'ok')    { return '#2E75B6' }
    return $null
}

# Severity column index (1-based) per section.
# Data columns now start at column A (no leading Section column on data/header
# rows - banner rows still use column A but get merged across the full width).
# So Severity column index = its position within the DataTable (1-based).
$SeverityColumnByLabel = @{
    '02_Instance_Configuration' = 4   # A=ConfigName, B=ValueInUse, C=Description, D=MIRelevance
    '03_Linked_Servers'         = 8   # 8 cols ending in MICompatibility
    '04_SQL_Agent_Jobs'         = 6
    '06_DB_Level_Findings'      = 3   # A=DatabaseName, B=Category, C=Severity, D=Finding
    '07_TSQL_Code_Scan'         = 6
    '08_SKU_Features'           = 3
    '09_CLR_Assemblies'         = 5
    '10_Database_Files'         = 6
    '15_Cloud_Migration_Matrix' = 2   # A=TargetPlatform, B=Fit, C=Notes
}

# -----------------------------------------------------------------------------
# Write Summary sheet - built manually cell-by-cell for full control over layout
# -----------------------------------------------------------------------------
# The Summary sheet is the technical roll-up: one row per server with the
# vital stats (Edition, Version, CU, Auth, HADR, DBs, Linked Servers, Jobs,
# MI Verdict), plus Estate Totals at the bottom.
#
# Earlier versions tried to use Export-Excel here and got tangled in merged
# cells overwriting data. Now we create a placeholder sheet and write every
# cell explicitly. More verbose, but predictable - what you see in the code
# is what shows up in the file.
#
# Layout:
#   Row 1     - title banner (merged, navy)
#   Rows 3-5  - run metadata (date, server count, etc.)
#   Row 7     - "Per-Server Roll-up" sub-banner
#   Row 8     - column headers
#   Rows 9+   - one row per server, MI Verdict color-coded red/green
#   Then a blank row, "Estate Totals" sub-banner, and 10 metric rows.

# First compute estate totals (we'll write these into the sheet at the end)
$totalDbs = 0
$totalJobs = 0
$totalHigh = 0
$totalMed = 0
$tdeDbs = 0
$clrAsm = 0
$xpCmd = 0
$linkedLegacy = 0
$dagDisconnected = 0
$seenAgs = New-Object System.Collections.Generic.HashSet[string]

foreach ($server in $allData.Keys) {
    $sec01 = $allData[$server]['01_Instance_Summary']
    if ($sec01 -and $sec01.Rows.Count -gt 0) {
        $row = $sec01.Rows[0]
        if ($sec01.Columns.Contains('UserDatabaseCount')) {
            $val = $row['UserDatabaseCount']
            if ($val -ne $null -and $val -ne [DBNull]::Value) { $totalDbs += [int]$val }
        }
        if ($sec01.Columns.Contains('EnabledAgentJobs')) {
            $val = $row['EnabledAgentJobs']
            if ($val -ne $null -and $val -ne [DBNull]::Value) { $totalJobs += [int]$val }
        }
    }
    foreach ($secLabel in @('06_DB_Level_Findings','07_TSQL_Code_Scan','08_SKU_Features')) {
        $sec = $allData[$server][$secLabel]
        if ($sec) {
            foreach ($r in $sec.Rows) {
                if ($sec.Columns.Contains('Severity')) {
                    $sv = "$($r['Severity'])".ToLower()
                    if ($sv -match 'high')   { $totalHigh++ }
                    elseif ($sv -match 'medium') { $totalMed++ }
                }
            }
        }
    }
    $secJobs = $allData[$server]['04_SQL_Agent_Jobs']
    if ($secJobs -and $secJobs.Columns.Contains('MIRelevance')) {
        foreach ($r in $secJobs.Rows) {
            if ("$($r['MIRelevance'])".ToLower() -match 'high') { $totalHigh++ }
        }
    }
    $secClr = $allData[$server]['09_CLR_Assemblies']
    if ($secClr) {
        $clrAsm += $secClr.Rows.Count
        if ($secClr.Columns.Contains('Verdict')) {
            foreach ($r in $secClr.Rows) {
                if ("$($r['Verdict'])".ToLower() -match 'high') { $totalHigh++ }
            }
        }
    }
    $secLs = $allData[$server]['03_Linked_Servers']
    if ($secLs -and $secLs.Columns.Contains('MICompatibility')) {
        foreach ($r in $secLs.Rows) {
            if ("$($r['MICompatibility'])" -match 'WARN') { $linkedLegacy++ }
        }
    }
    $secCfg = $allData[$server]['02_Instance_Configuration']
    if ($secCfg) {
        foreach ($r in $secCfg.Rows) {
            if ("$($r['ConfigName'])" -eq 'xp_cmdshell' -and "$($r['ValueInUse'])" -eq '1') {
                $xpCmd++
            }
        }
    }
    $secAg = $allData[$server]['11_Availability_Groups']
    if ($secAg) {
        foreach ($r in $secAg.Rows) {
            if ($secAg.Columns.Contains('AGName')) {
                $agName = "$($r['AGName'])"
                if ($agName) { $null = $seenAgs.Add($agName) }
            }
            if ($secAg.Columns.Contains('ConnectedState')) {
                if ("$($r['ConnectedState'])" -eq 'DISCONNECTED') { $dagDisconnected++ }
            }
        }
    }
    $secDb = $allData[$server]['05_Database_Inventory']
    if ($secDb -and $secDb.Columns.Contains('IsTDEEncrypted')) {
        foreach ($r in $secDb.Rows) {
            $tde = "$($r['IsTDEEncrypted'])"
            if ($tde -eq '1' -or $tde -eq 'True') { $tdeDbs++ }
        }
    }
}

# Build per-server roll-up rows
$summaryRows = @()
foreach ($server in ($allData.Keys | Sort-Object)) {
    $sec01 = $allData[$server]['01_Instance_Summary']
    if (-not $sec01 -or $sec01.Rows.Count -eq 0) { continue }
    $r = $sec01.Rows[0]

    $miVerdict = 'No'
    $sec15 = $allData[$server]['15_Cloud_Migration_Matrix']
    if ($sec15) {
        foreach ($mr in $sec15.Rows) {
            $platform = "$($mr['TargetPlatform'])"
            if ($platform -like 'Azure SQL Managed Instance*') {
                $miVerdict = "$($mr['Fit'])"
                break
            }
        }
    }

    $summaryRows += [PSCustomObject]@{
        Server     = "$($r['ServerName'])"
        Edition    = "$($r['Edition'])"
        Version    = "$($r['ProductVersion'])"
        CU         = "$($r['CULevel'])"
        AuthMode   = "$($r['AuthMode'])"
        HADR       = "$($r['HadrEnabled'])"
        UserDBs    = "$($r['UserDatabaseCount'])"
        LinkedSrv  = "$($r['LinkedServerCount'])"
        AgentJobs  = "$($r['EnabledAgentJobs'])"
        MIVerdict  = $miVerdict
    }
}

# Create the Summary worksheet by writing a single placeholder row to it
# (this is the cleanest way to get an ExcelPackage handle pointing at it)
$pkg = @([PSCustomObject]@{ A = '' }) | Export-Excel -Path $OutputXlsx -WorksheetName 'Summary' -PassThru -NoHeader

$ws = $pkg.Workbook.Worksheets['Summary']
# Clear the placeholder cell
$ws.Cells['A1'].Value = ''

# --- Row 1: title banner ---
$ws.Cells['A1'].Value = 'SQL Server -> Cloud Migration Assessment'
$ws.Cells['A1:J1'].Merge = $true
$ws.Cells['A1'].Style.Font.Bold = $true
$ws.Cells['A1'].Style.Font.Size = 16
$ws.Cells['A1'].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$ws.Cells['A1'].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$ws.Cells['A1'].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$ws.Cells['A1'].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
$ws.Cells['A1'].Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Left
$ws.Row(1).Height = 28

# --- Rows 3-5: run metadata ---
$ws.Cells['A3'].Value = 'Assessment run'
$ws.Cells['B3'].Value = (Get-Date -Format 'yyyy-MM-dd HH:mm')
$ws.Cells['A4'].Value = 'Servers assessed'
$ws.Cells['B4'].Value = $allData.Count
$ws.Cells['A5'].Value = 'Method'
$ws.Cells['B5'].Value = 'PowerShell agent (SqlServer + ImportExcel modules)'

@('A3','A4','A5') | ForEach-Object {
    $ws.Cells[$_].Style.Font.Bold = $true
}

# --- Row 7: Per-Server Roll-up banner ---
$ws.Cells['A7'].Value = 'Per-Server Roll-up'
$ws.Cells['A7:J7'].Merge = $true
$ws.Cells['A7'].Style.Font.Bold = $true
$ws.Cells['A7'].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$ws.Cells['A7'].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$ws.Cells['A7'].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$ws.Row(7).Height = 22

# --- Row 8: column headers ---
$rollupHeaders = @('Server','Edition','Version','CU','Auth Mode','HADR','User DBs','Linked Srv','Agent Jobs','MI Verdict')
for ($c = 0; $c -lt $rollupHeaders.Count; $c++) {
    $cell = $ws.Cells[8, ($c + 1)]
    $cell.Value = $rollupHeaders[$c]
    $cell.Style.Font.Bold = $true
    $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($LightHex))
    $cell.Style.Border.Bottom.Style = [OfficeOpenXml.Style.ExcelBorderStyle]::Thin
}

# --- Rows 9+: per-server rollup data ---
$rollupStartRow = 9
$rollupRow = $rollupStartRow
foreach ($srvData in $summaryRows) {
    $vals = @($srvData.Server, $srvData.Edition, $srvData.Version, $srvData.CU,
              $srvData.AuthMode, $srvData.HADR, $srvData.UserDBs, $srvData.LinkedSrv,
              $srvData.AgentJobs, $srvData.MIVerdict)
    for ($c = 0; $c -lt $vals.Count; $c++) {
        $cell = $ws.Cells[$rollupRow, ($c + 1)]
        $cell.Value = $vals[$c]
    }
    # Color-code the MI Verdict column (col J, index 10)
    $verdictCell = $ws.Cells[$rollupRow, 10]
    $vTrimmed = "$($srvData.MIVerdict)".ToLower().Trim()
    if ($vTrimmed -eq 'no') {
        $verdictCell.Style.Font.Bold = $true
        $verdictCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($RedText))
    } elseif ($vTrimmed -eq 'yes') {
        $verdictCell.Style.Font.Bold = $true
        $verdictCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($GreenText))
    }
    $rollupRow++
}

# --- Estate Totals banner ---
$totalsRow = $rollupRow + 1
$ws.Cells["A$totalsRow"].Value = 'Estate Totals'
$ws.Cells["A${totalsRow}:J${totalsRow}"].Merge = $true
$ws.Cells["A$totalsRow"].Style.Font.Bold = $true
$ws.Cells["A$totalsRow"].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$ws.Cells["A$totalsRow"].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$ws.Cells["A$totalsRow"].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$ws.Row($totalsRow).Height = 22

$stats = @(
    @{ Label = 'Total user databases across estate';       Value = $totalDbs;          Alert = $false }
    @{ Label = 'Total enabled SQL Agent jobs';             Value = $totalJobs;         Alert = $false }
    @{ Label = 'High-severity findings';                   Value = $totalHigh;         Alert = ($totalHigh -gt 0) }
    @{ Label = 'Medium-severity findings';                 Value = $totalMed;          Alert = $false }
    @{ Label = 'TDE-encrypted databases';                  Value = $tdeDbs;            Alert = $false }
    @{ Label = 'CLR assemblies (user-defined)';            Value = $clrAsm;            Alert = $false }
    @{ Label = 'Servers with xp_cmdshell enabled';         Value = $xpCmd;             Alert = ($xpCmd -gt 0) }
    @{ Label = 'Linked servers using legacy SQLNCLI';      Value = $linkedLegacy;      Alert = ($linkedLegacy -gt 0) }
    @{ Label = 'Distinct Availability Groups';             Value = $seenAgs.Count;     Alert = $false }
    @{ Label = 'AG/DAG replicas in DISCONNECTED state';    Value = $dagDisconnected;   Alert = ($dagDisconnected -gt 0) }
)

$statRow = $totalsRow + 1
foreach ($s in $stats) {
    $cellA = $ws.Cells["A$statRow"]
    $cellA.Value = $s.Label
    $cellA.Style.Font.Bold = $true
    $cellB = $ws.Cells["B$statRow"]
    $cellB.Value = $s.Value
    if ($s.Alert) {
        $cellB.Style.Font.Bold = $true
        $cellB.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($RedText))
    }
    $statRow++
}

# --- Footer note ---
$noteRow = $statRow + 1
$ws.Cells["A$noteRow"].Value = 'Note: All on-prem databases ship at format 904 (SQL 2019) or 957 (SQL 2022 RTM). Azure SQL MI Free-tier targets are at format 998 (AlwaysUpToDate). Format mismatch blocks MI Link; migration must use DMS or backup/restore.'
$ws.Cells["A${noteRow}:J${noteRow}"].Merge = $true
$ws.Cells["A$noteRow"].Style.Font.Italic = $true
$ws.Cells["A$noteRow"].Style.Font.Size = 9
$ws.Cells["A$noteRow"].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#595959'))
$ws.Cells["A$noteRow"].Style.WrapText = $true
$ws.Row($noteRow).Height = 30

# --- Column widths ---
$ws.Column(1).Width = 50
for ($c = 2; $c -le 10; $c++) { $ws.Column($c).AutoFit() }

# --- Freeze title row ---
$ws.View.FreezePanes(2, 1)

# -----------------------------------------------------------------------------
# Critical Findings sheet
# -----------------------------------------------------------------------------
# Walks every server's data and extracts findings worth surfacing to the
# estate-wide view. The finding categories pulled here are:
#
#   - Section 4  : Agent jobs flagged as High (CmdExec/PowerShell/SSIS subsystems)
#   - Section 6  : DB-level findings (Windows users, FileStream, Temporal, etc.)
#   - Section 7  : T-SQL code scan hits
#   - Section 8  : Per-DB SKU features (FileTable, In-Memory OLTP, etc.)
#   - Section 9  : CLR assemblies with UNSAFE/EXTERNAL_ACCESS
#   - Section 3  : Linked servers using legacy SQLNCLI provider
#   - Section 2  : xp_cmdshell enabled
#   - Section 11 : Disconnected AGs
#   - Section 5  : TDE-encrypted databases (Medium - cert migration needed)
#
# Each finding becomes a PSCustomObject with: Server, Severity, Source,
# Object, Finding, MI Impact. After the loop we sort by severity (High first)
# then server name, and write to a sheet with autofilter and color coding.
#
# This is also the data source for the MI Readiness Score and the
# Remediation Plan tab below.

$findings = @()
foreach ($server in ($allData.Keys | Sort-Object)) {
    $sd = $allData[$server]

    # Section 4 — high-severity Agent jobs
    $sec = $sd['04_SQL_Agent_Jobs']
    if ($sec) {
        foreach ($row in $sec.Rows) {
            $rel = "$($row['MIRelevance'])".ToLower()
            if ($rel -match 'high') {
                $findings += [PSCustomObject]@{
                    Server   = $server
                    Severity = 'High'
                    Source   = 'SQL Agent Job'
                    Object   = "$($row['JobName'])"
                    Finding  = "Risky subsystem: $($row['Subsystems']). Steps: $($row['RiskySteps']) risky / $($row['TotalSteps']) total"
                    'MI Impact' = 'Redesign for managed SQL - no CmdExec/PowerShell/SSIS in MI'
                }
            }
        }
    }

    # Section 6 — DB-level findings
    $sec = $sd['06_DB_Level_Findings']
    if ($sec) {
        foreach ($row in $sec.Rows) {
            $sv = "$($row['Severity'])".ToLower()
            if ($sv -in @('high','medium')) {
                $findings += [PSCustomObject]@{
                    Server   = $server
                    Severity = "$($row['Severity'])"
                    Source   = "$($row['Category'])"
                    Object   = "$($row['DatabaseName'])"
                    Finding  = "$($row['Finding'])"
                    'MI Impact' = 'Review for managed-target compatibility'
                }
            }
        }
    }

    # Section 7 — code scan
    $sec = $sd['07_TSQL_Code_Scan']
    if ($sec) {
        foreach ($row in $sec.Rows) {
            $sv = "$($row['Severity'])".ToLower()
            if ($sv -in @('high','medium')) {
                $findings += [PSCustomObject]@{
                    Server   = $server
                    Severity = "$($row['Severity'])"
                    Source   = 'T-SQL Code'
                    Object   = "$($row['DatabaseName']).$($row['SchemaName']).$($row['ObjectName']) ($($row['ObjectType']))"
                    Finding  = "$($row['RiskPattern'])"
                    'MI Impact' = 'Refactor before MI migration'
                }
            }
        }
    }

    # Section 8 — SKU features
    $sec = $sd['08_SKU_Features']
    if ($sec) {
        foreach ($row in $sec.Rows) {
            $sv = "$($row['Severity'])".ToLower()
            if ($sv -in @('high','medium')) {
                $findings += [PSCustomObject]@{
                    Server   = $server
                    Severity = "$($row['Severity'])"
                    Source   = "$($row['FeatureName'])"
                    Object   = "$($row['DatabaseName'])"
                    Finding  = "$($row['Note'])"
                    'MI Impact' = 'Verify availability on managed target'
                }
            }
        }
    }

    # Section 9 — CLR
    $sec = $sd['09_CLR_Assemblies']
    if ($sec) {
        foreach ($row in $sec.Rows) {
            $v = "$($row['Verdict'])".ToLower()
            if ($v -match 'high' -or $v -match 'unsafe') {
                $findings += [PSCustomObject]@{
                    Server   = $server
                    Severity = 'High'
                    Source   = 'CLR Assembly'
                    Object   = "$($row['DatabaseName']).$($row['AssemblyName']) ($($row['PermissionSet']))"
                    Finding  = "User-defined CLR with $($row['PermissionSet']) permission set"
                    'MI Impact' = 'UNSAFE/EXTERNAL_ACCESS CLR not supported on MI'
                }
            }
        }
    }

    # Section 3 — Linked servers (legacy provider)
    $sec = $sd['03_Linked_Servers']
    if ($sec) {
        foreach ($row in $sec.Rows) {
            $mi = "$($row['MICompatibility'])"
            if ($mi -match 'WARN') {
                $findings += [PSCustomObject]@{
                    Server   = $server
                    Severity = 'Medium'
                    Source   = 'Linked Server'
                    Object   = "$($row['LinkedServerName'])"
                    Finding  = "Legacy provider: $($row['Provider'])"
                    'MI Impact' = 'MI requires MSOLEDBSQL provider'
                }
            }
        }
    }

    # Section 2 — xp_cmdshell enabled
    $sec = $sd['02_Instance_Configuration']
    if ($sec) {
        foreach ($row in $sec.Rows) {
            if ("$($row['ConfigName'])" -eq 'xp_cmdshell' -and "$($row['ValueInUse'])" -eq '1') {
                $findings += [PSCustomObject]@{
                    Server   = $server
                    Severity = 'High'
                    Source   = 'sp_configure'
                    Object   = 'xp_cmdshell'
                    Finding  = 'xp_cmdshell is enabled (value=1)'
                    'MI Impact' = 'xp_cmdshell not supported on managed SQL'
                }
            }
        }
    }

    # Section 11 — DISCONNECTED AG/DAG
    $sec = $sd['11_Availability_Groups']
    if ($sec) {
        foreach ($row in $sec.Rows) {
            if ("$($row['ConnectedState'])" -eq 'DISCONNECTED') {
                $findings += [PSCustomObject]@{
                    Server   = $server
                    Severity = 'High'
                    Source   = 'Availability Group'
                    Object   = "$($row['AGName']) -> $($row['ReplicaServer'])"
                    Finding  = "Replica state: $($row['SyncHealth']) / $($row['ConnectedState'])"
                    'MI Impact' = 'DAG must be HEALTHY before MI Link or cutover'
                }
            }
        }
    }

    # Section 5 — TDE-encrypted databases (Medium)
    $sec = $sd['05_Database_Inventory']
    if ($sec -and $sec.Columns.Contains('IsTDEEncrypted')) {
        foreach ($row in $sec.Rows) {
            $tde = "$($row['IsTDEEncrypted'])"
            if ($tde -eq '1' -or $tde -eq 'True') {
                $findings += [PSCustomObject]@{
                    Server   = $server
                    Severity = 'Medium'
                    Source   = 'TDE Database'
                    Object   = "$($row['DatabaseName'])"
                    Finding  = 'Database is TDE-encrypted'
                    'MI Impact' = 'Migrate certificate to MI before restore'
                }
            }
        }
    }
}

# Sort: High first, then Medium, then by server
$severityRank = @{ 'High' = 0; 'Medium' = 1 }
$findingsSorted = $findings | Sort-Object @{ Expression = { $severityRank[$_.Severity] }}, @{ Expression = { $_.Server }}

if ($findingsSorted.Count -eq 0) {
    # Empty placeholder
    $findingsSorted = @([PSCustomObject]@{
        Server      = ''
        Severity    = 'No findings'
        Source      = ''
        Object      = ''
        Finding     = ''
        'MI Impact' = ''
    })
}

$pkg = $findingsSorted | Export-Excel -ExcelPackage $pkg -WorksheetName 'Critical Findings' -AutoSize -BoldTopRow -PassThru

$cf = $pkg.Workbook.Worksheets['Critical Findings']
$cfLastCol = $cf.Dimension.End.Column

# Insert two rows at the top: row 1 = title banner, row 2 = gap.
# This pushes existing column headers from row 1 down to row 3, and data
# rows down accordingly.
$cf.InsertRow(1, 2)

# Row 1 - title banner (navy fill, white bold text, merged across all columns)
$cf.Cells[1, 1].Value = 'Critical Findings - Estate-Wide (sortable)'
$cf.Cells[1, 1, 1, $cfLastCol].Merge = $true
$cf.Cells[1, 1].Style.Font.Bold = $true
$cf.Cells[1, 1].Style.Font.Size = 12
$cf.Cells[1, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$cf.Cells[1, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$cf.Cells[1, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$cf.Cells[1, 1].Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Left

# Row 2 - gap (left blank intentionally for visual separation)

# Apply autofilter on the header row (now at row 3) and freeze panes below it
$cf.Cells[3, 1, 3, $cfLastCol].AutoFilter = $true
$cf.View.FreezePanes(4, 1)

# Color-code DATA rows (now starting at row 4) by severity (column 2 = Severity)
$lastRow = $cf.Dimension.End.Row
for ($r = 4; $r -le $lastRow; $r++) {
    $sev = "$($cf.Cells[$r, 2].Value)"
    $fillHex = Get-SeverityFill -Text $sev
    $textHex = Get-SeverityTextColor -Text $sev
    if ($fillHex) {
        $rng = $cf.Cells[$r, 1, $r, 6]
        $rng.Style.Fill.PatternType = 'Solid'
        $rng.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($fillHex))
    }
    if ($textHex) {
        $cf.Cells[$r, 2].Style.Font.Bold = $true
        $cf.Cells[$r, 2].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($textHex))
    }
}

# -----------------------------------------------------------------------------
# Compute MI Readiness Score per server
# -----------------------------------------------------------------------------
# Scoring model: start at 100, subtract per-finding penalties.
#   - High severity findings:   -15 each
#   - Medium severity findings:  -5 each
# Then map to a label:
#   - >= 85 : Ready
#   - 60-84 : Conditional
#   - <  60 : Blocked
# Per-server findings are derived from the same $findings list used for the
# Critical Findings tab.

$ScoreByServer = @{}
$LabelByServer = @{}
$TopIssueByServer = @{}

foreach ($server in ($allData.Keys | Sort-Object)) {
    $score = 100
    $serverFindings = @($findings | Where-Object { $_.Server -eq $server })
    foreach ($f in $serverFindings) {
        if ("$($f.Severity)" -eq 'High')   { $score -= 15 }
        elseif ("$($f.Severity)" -eq 'Medium') { $score -= 5 }
    }
    if ($score -lt 0) { $score = 0 }

    $label = if ($score -ge 85) { 'Ready' } elseif ($score -ge 60) { 'Conditional' } else { 'Blocked' }
    $ScoreByServer[$server] = $score
    $LabelByServer[$server] = $label

    # Top issue = first High finding if any, else first Medium, else "(none)"
    $topHigh = $serverFindings | Where-Object { $_.Severity -eq 'High' } | Select-Object -First 1
    $topMed  = $serverFindings | Where-Object { $_.Severity -eq 'Medium' } | Select-Object -First 1
    if ($topHigh) {
        $TopIssueByServer[$server] = "$($topHigh.Source): $($topHigh.Object)"
    } elseif ($topMed) {
        $TopIssueByServer[$server] = "$($topMed.Source): $($topMed.Object)"
    } else {
        $TopIssueByServer[$server] = '(none)'
    }
}

# Estate-wide tallies
$serverCount  = $allData.Count
$readyCount   = @($LabelByServer.Values | Where-Object { $_ -eq 'Ready' }).Count
$condCount    = @($LabelByServer.Values | Where-Object { $_ -eq 'Conditional' }).Count
$blockedCount = @($LabelByServer.Values | Where-Object { $_ -eq 'Blocked' }).Count
$highCount    = @($findings | Where-Object { $_.Severity -eq 'High' }).Count
$medCount     = @($findings | Where-Object { $_.Severity -eq 'Medium' }).Count

# Top 3 blockers (most-frequent finding sources across the estate)
$blockerCounts = @{}
foreach ($f in $findings) {
    $key = "$($f.Source)"
    if ($f.Severity -eq 'High') {
        if ($blockerCounts.ContainsKey($key)) { $blockerCounts[$key]++ }
        else { $blockerCounts[$key] = 1 }
    }
}
$top3Blockers = @($blockerCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 3)


# =============================================================================
# AI-DRIVEN COST-AWARE RECOMMENDATION ENGINE
# =============================================================================
# This is the "AI Agent" layer. For each assessed server, it:
#
#   1. Calculates the 1-year cost for each migration target:
#      - DC-to-DC (stay on-prem at a different datacenter, reference rates)
#      - DC-to-Azure VM (PAYG: SQL license baked in)
#      - DC-to-Azure VM (BYOL: bring your own SQL license via AHB)
#      - DC-to-Azure SQL MI (AI-sized SKU)
#
#   2. Calls an LLM (provider-abstracted) to:
#      - Recommend the right MI SKU based on workload characteristics
#      - Write a per-server cost-vs-benefit narrative
#      - Synthesize an estate-wide migration strategy (one extra call)
#
# Provider abstraction (Path C design):
#   Set $LlmProvider = 'Claude' (default) or 'AzureOpenAi' to switch.
#   The abstraction handles auth, request shape, and response parsing per
#   provider. Calling code is provider-agnostic.
#
# Cost data sources:
#   - Cloud (Azure VM, MI): live Azure Retail Prices API (no auth required)
#   - On-prem (DC-DC):       industry-standard reference rates (2026 snapshot)
# =============================================================================

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------

# LLM provider choice. Today: 'Claude' (built and tested).
# To switch to Azure OpenAI later: set this to 'AzureOpenAi' and ensure the
# AZURE_OPENAI_* environment variables are set. No other code changes needed.
$LlmProvider = 'Claude'

# Anthropic Claude API config
$ClaudeApiKey = $env:ANTHROPIC_API_KEY
$ClaudeApiUrl = 'https://api.anthropic.com/v1/messages'
$ClaudeModel  = 'claude-sonnet-4-5'   # fast + smart enough; Opus is 5x more $
$ClaudeApiVer = '2023-06-01'

# Azure OpenAI config (used only if $LlmProvider -eq 'AzureOpenAi')
$AzOpenAiEndpoint   = $env:AZURE_OPENAI_ENDPOINT
$AzOpenAiKey        = $env:AZURE_OPENAI_KEY
$AzOpenAiDeployment = $env:AZURE_OPENAI_DEPLOYMENT
$AzOpenAiApiVersion = '2024-08-01-preview'

# Azure pricing API (public, no auth)
$AzureRetailApi = 'https://prices.azure.com/api/retail/prices'

# Pricing region for Azure cost lookups - matches typical lab/POC usage.
# Production: parameterize this to match the customer's target region.
$PricingRegion = 'westus2'

# 2026 industry-standard reference rates for on-prem TCO.
# Sources: Microsoft list pricing, Gartner DC TCO benchmarks, vendor surveys.
# Refresh quarterly; surfaced to users with "estimate" labeling.
$ReferenceRates = @{
    HardwareRefreshUSD     = 12000   # $12K per server, amortized over 5 years
    HardwareLifeYears      = 5
    ColocationPerYear      = 3600    # rack space, power, cooling
    OperationalLaborYearly = 4000    # allocated DBA labor per server
    StoragePerGBMonth      = 0.30    # SAN allocation
    SqlStdLicensePer2Cores = 3586    # Microsoft list price 2-core pack
    SqlEntLicensePer2Cores = 14256   # Microsoft list price 2-core pack
}

# Diagnostic banner so user knows the AI agent is active
Write-Host ''
Write-Host '===============================================================================' -ForegroundColor Cyan
Write-Host '  AI Cost-Aware Recommendation Engine' -ForegroundColor Cyan
Write-Host '===============================================================================' -ForegroundColor Cyan
Write-Host "  LLM Provider: $LlmProvider" -ForegroundColor Cyan
Write-Host "  Pricing Region: $PricingRegion (Azure Retail Prices API, live)" -ForegroundColor Cyan

# Validate provider config; if invalid, set a flag so we degrade gracefully
$LlmReady = $false
if ($LlmProvider -eq 'Claude') {
    if ($ClaudeApiKey) {
        $LlmReady = $true
        Write-Host "  Claude API: ready" -ForegroundColor Green
    } else {
        Write-Host "  Claude API: ANTHROPIC_API_KEY env var not set - AI narratives will be skipped" -ForegroundColor Yellow
    }
} elseif ($LlmProvider -eq 'AzureOpenAi') {
    if ($AzOpenAiEndpoint -and $AzOpenAiKey -and $AzOpenAiDeployment) {
        $LlmReady = $true
        Write-Host "  Azure OpenAI: ready" -ForegroundColor Green
    } else {
        Write-Host "  Azure OpenAI: missing AZURE_OPENAI_ENDPOINT/KEY/DEPLOYMENT - AI narratives will be skipped" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Unknown LLM provider '$LlmProvider' - AI narratives will be skipped" -ForegroundColor Yellow
}
Write-Host ''


# -----------------------------------------------------------------------------
# LLM PROVIDER ABSTRACTION
# -----------------------------------------------------------------------------
# Calling code uses Invoke-LlmCompletion - it doesn't know which provider is
# behind it. To swap providers, change $LlmProvider above (and ensure the
# corresponding env vars are set). Internal functions handle the provider-
# specific request/response shapes.

function Invoke-ClaudeApi {
    param(
        [string]$SystemPrompt,
        [string]$UserPrompt,
        [int]$MaxTokens = 1024
    )
    $body = @{
        model       = $ClaudeModel
        max_tokens  = $MaxTokens
        system      = $SystemPrompt
        messages    = @(
            @{ role = 'user'; content = $UserPrompt }
        )
    } | ConvertTo-Json -Depth 10 -Compress

    $headers = @{
        'x-api-key'         = $ClaudeApiKey
        'anthropic-version' = $ClaudeApiVer
        'content-type'      = 'application/json; charset=utf-8'
    }

    try {
        # Force UTF-8 for the request body so non-ASCII characters in prompts
        # round-trip correctly. Also use Invoke-WebRequest + manual decode of
        # response bytes as UTF-8 - Invoke-RestMethod's default encoding
        # heuristic mangles em-dashes and other UTF-8 multi-byte chars.
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $rawResponse = Invoke-WebRequest -Uri $ClaudeApiUrl -Method Post -Headers $headers -Body $bodyBytes -TimeoutSec 60 -UseBasicParsing
        $rawText = [System.Text.Encoding]::UTF8.GetString($rawResponse.RawContentStream.ToArray())
        $response = $rawText | ConvertFrom-Json
        # Claude returns: { content: [ { type: 'text', text: '...' } ] }
        if ($response.content -and $response.content.Count -gt 0) {
            return $response.content[0].text
        }
        return $null
    } catch {
        Write-Host "  Claude API call failed: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

function Invoke-AzureOpenAi {
    param(
        [string]$SystemPrompt,
        [string]$UserPrompt,
        [int]$MaxTokens = 1024
    )
    # Azure OpenAI endpoint format:
    #   <endpoint>/openai/deployments/<deployment>/chat/completions?api-version=...
    $url = "$AzOpenAiEndpoint/openai/deployments/$AzOpenAiDeployment/chat/completions?api-version=$AzOpenAiApiVersion"

    $body = @{
        max_tokens = $MaxTokens
        messages   = @(
            @{ role = 'system'; content = $SystemPrompt },
            @{ role = 'user';   content = $UserPrompt }
        )
    } | ConvertTo-Json -Depth 10 -Compress

    $headers = @{
        'api-key'      = $AzOpenAiKey
        'content-type' = 'application/json; charset=utf-8'
    }

    try {
        # Same UTF-8 handling as the Claude provider for em-dashes etc.
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $rawResponse = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $bodyBytes -TimeoutSec 60 -UseBasicParsing
        $rawText = [System.Text.Encoding]::UTF8.GetString($rawResponse.RawContentStream.ToArray())
        $response = $rawText | ConvertFrom-Json
        # Azure OpenAI returns: { choices: [ { message: { content: '...' } } ] }
        if ($response.choices -and $response.choices.Count -gt 0) {
            return $response.choices[0].message.content
        }
        return $null
    } catch {
        Write-Host "  Azure OpenAI call failed: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

function Invoke-LlmCompletion {
    param(
        [string]$SystemPrompt,
        [string]$UserPrompt,
        [int]$MaxTokens = 1024
    )
    if (-not $LlmReady) { return $null }
    switch ($LlmProvider) {
        'Claude'      { return Invoke-ClaudeApi      -SystemPrompt $SystemPrompt -UserPrompt $UserPrompt -MaxTokens $MaxTokens }
        'AzureOpenAi' { return Invoke-AzureOpenAi    -SystemPrompt $SystemPrompt -UserPrompt $UserPrompt -MaxTokens $MaxTokens }
        default       { return $null }
    }
}


# -----------------------------------------------------------------------------
# AZURE PRICING - live lookups via Retail Prices API
# -----------------------------------------------------------------------------
# Cache pricing within a single agent run to avoid repeated calls for the
# same SKU. Cleared at start of each run (script scope).
$script:AzPriceCache = @{}
# Timestamp recorded at the FIRST successful pricing API call.
# Surfaced on the Methodology & Sources tab so reviewers can see exactly
# when the live pricing data was retrieved.
$script:PricingFetchedAt = $null

function Get-AzureVmHourlyPrice {
    param(
        [string]$Region = $PricingRegion,
        [string]$VmSku  = 'Standard_D4s_v5'
    )
    # Returns the BASE Windows VM hourly price (no SQL license).
    # SQL license cost is computed separately in Get-SqlLicenseHourlyAddOn so
    # we can apply the right per-core rate based on edition.
    $cacheKey = "VM|$Region|$VmSku"
    if ($script:AzPriceCache.ContainsKey($cacheKey)) {
        return $script:AzPriceCache[$cacheKey]
    }

    # Calculator-validated fallback rates (West US 2, 2026 reference).
    # Source: Azure Pricing Calculator at azure.microsoft.com/pricing/calculator
    # Cross-validated against actual VM Windows-only pricing.
    # D8s v5: $548.96/month / 730 hrs = $0.752/hr
    # NOTE: 'break' keyword prevents switch from matching multiple regex patterns
    #       (e.g. 'D8s_v5' would otherwise match both 'D8s_v5' AND 'D8s').
    $fallbackHourly = switch -Regex ($VmSku) {
        'D2s_v5'  { 0.188; break }
        'D4s_v5'  { 0.376; break }
        'D8s_v5'  { 0.752; break }
        'D16s_v5' { 1.504; break }
        'D2s'     { 0.188; break }
        'D4s'     { 0.376; break }
        'D8s'     { 0.752; break }
        'D16s'    { 1.504; break }
        default   { 0.376 }
    }

    try {
        $filter = "serviceName eq 'Virtual Machines' and armRegionName eq '$Region' and armSkuName eq '$VmSku' and priceType eq 'Consumption'"
        $url = "$AzureRetailApi" + '?$filter=' + [System.Uri]::EscapeDataString($filter)
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30

        # Filter to Windows OS, exclude spot/low-priority/Linux
        $candidates = $response.Items | Where-Object {
            $_.productName -match 'Windows' -and
            $_.skuName -notmatch 'Low Priority' -and
            $_.skuName -notmatch 'Spot' -and
            $_.productName -notmatch 'Linux'
        }

        $vmPrice = ($candidates | Select-Object -First 1).retailPrice

        # Sanity check: reject suspiciously low values (likely matched Linux
        # or got the no-license-included rate when we wanted Windows-included).
        # Windows-included pricing should always be higher than the fallback's 60%.
        $minExpected = $fallbackHourly * 0.6
        $maxExpected = $fallbackHourly * 1.5
        if (-not $vmPrice -or $vmPrice -lt $minExpected -or $vmPrice -gt $maxExpected) {
            $vmPrice = $fallbackHourly
        }

        $script:AzPriceCache[$cacheKey] = $vmPrice
        if (-not $script:PricingFetchedAt) { $script:PricingFetchedAt = Get-Date }
        return $vmPrice
    } catch {
        $script:AzPriceCache[$cacheKey] = $fallbackHourly
        return $fallbackHourly
    }
}

function Get-SqlLicenseHourlyAddOn {
    param(
        [string]$Edition = 'Standard',   # Standard / Enterprise / Web / Developer
        [int]$CoreCount = 4
    )
    # PAYG SQL Server license add-on pricing (Microsoft Marketplace, 2026 reference).
    # Source: Azure Marketplace SQL Server VM PAYG image pricing.
    # Per core per hour rates (approximate, list pricing):
    #   Developer:  $0.00      (free)
    #   Web:        $0.020     (~$175/yr per core)
    #   Standard:   $0.115     (~$1,008/yr per core)
    #   Enterprise: $0.460     (~$4,030/yr per core)
    # Note: Azure normally meters on a per-core-hour basis.
    $perCorePerHour = switch ($Edition) {
        'Developer'  { 0.00 }
        'Web'        { 0.020 }
        'Standard'   { 0.115 }
        'Enterprise' { 0.460 }
        default      { 0.115 }   # treat unknown editions as Standard
    }
    return $perCorePerHour * $CoreCount
}

function Get-AzureMiHourlyPrice {
    param(
        [string]$Region = $PricingRegion,
        [string]$Tier   = 'GeneralPurpose',   # GeneralPurpose or BusinessCritical
        [int]$VCore     = 8
    )
    # Returns hourly price for the WHOLE MI instance at the requested vCore tier.
    #
    # IMPORTANT BUG FIX: Azure exposes MI pricing as FIXED VCORE TIERS, not
    # per-vCore. Each tier (4, 8, 16, 24, 32, 40, 64, 80 vCore) has its own
    # meter with the price for the entire instance. Earlier versions of this
    # function multiplied a single meter's price by the requested vCore count,
    # which produced wildly inflated numbers (e.g., $341,358/yr for 8 vCore).
    # The correct approach is to match the meter whose skuName equals the
    # exact vCore tier (e.g. "8 vCore") and use that price directly.
    $cacheKey = "MI|$Region|$Tier|$VCore"
    if ($script:AzPriceCache.ContainsKey($cacheKey)) {
        return $script:AzPriceCache[$cacheKey]
    }

    # Round requested vCore UP to the nearest available MI Gen5 tier.
    $availableTiers = @(4, 8, 16, 24, 32, 40, 64, 80)
    $effectiveVCore = ($availableTiers | Where-Object { $_ -ge $VCore } | Select-Object -First 1)
    if (-not $effectiveVCore) { $effectiveVCore = 80 }   # cap

    # Per-instance fallback rates (West US 2, 2026 reference).
    # Calculator-validated: 8 vCore GP = $888.95/month / 730 hrs = $1.218/hour.
    # Other tiers extrapolated linearly from this anchor.
    # Used if the live API filter misses or returns a suspect value.
    $fallbackHourly = if ($Tier -eq 'BusinessCritical') {
        # BC is roughly 2.7x GP for the same vCore count
        switch ($effectiveVCore) {
            4  { 1.64 }
            8  { 3.29 }
            16 { 6.58 }
            24 { 9.87 }
            32 { 13.16 }
            40 { 16.45 }
            64 { 26.32 }
            80 { 32.90 }
            default { 3.29 }
        }
    } else {
        switch ($effectiveVCore) {
            4  { 0.609 }
            8  { 1.218 }   # calculator-validated
            16 { 2.436 }
            24 { 3.654 }
            32 { 4.872 }
            40 { 6.090 }
            64 { 9.741 }   # diagnostic showed exactly this
            80 { 12.180 }
            default { 1.218 }
        }
    }

    try {
        $filter = "serviceName eq 'SQL Managed Instance' and armRegionName eq '$Region' and priceType eq 'Consumption'"
        $url = "$AzureRetailApi" + '?$filter=' + [System.Uri]::EscapeDataString($filter)
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30

        $tierKeyword = if ($Tier -eq 'BusinessCritical') { 'Business Critical' } else { 'General Purpose' }
        $vcoreSku    = "$effectiveVCore vCore"   # e.g. "8 vCore" - exact match

        # Match the COMPUTE meter for the tier + exact vCore SKU.
        $matches = $response.Items | Where-Object {
            $_.productName -match $tierKeyword -and
            $_.productName -match 'Compute'    -and
            $_.skuName     -eq $vcoreSku       -and
            $_.unitOfMeasure -match 'Hour'
        }

        # Prefer Gen5 if multiple
        $gen5 = $matches | Where-Object { $_.productName -match 'Gen5' }
        $chosen = if ($gen5) { $gen5 | Select-Object -First 1 } else { $matches | Select-Object -First 1 }

        $hourlyPrice = if ($chosen) { [double]$chosen.retailPrice } else { $fallbackHourly }

        # Sanity check: ensure the price is in a believable band for this tier+vCore.
        # Reject obviously wrong values (too low: matched a side meter; too high:
        # something else broke).
        $minExpected = $fallbackHourly * 0.5
        $maxExpected = $fallbackHourly * 2.0
        if ($hourlyPrice -lt $minExpected -or $hourlyPrice -gt $maxExpected) {
            $hourlyPrice = $fallbackHourly
        }

        $script:AzPriceCache[$cacheKey] = $hourlyPrice
        if (-not $script:PricingFetchedAt) { $script:PricingFetchedAt = Get-Date }
        return $hourlyPrice
    } catch {
        $script:AzPriceCache[$cacheKey] = $fallbackHourly
        return $fallbackHourly
    }
}


# -----------------------------------------------------------------------------
# SERVER PROFILE EXTRACTION
# -----------------------------------------------------------------------------
# Pulls workload characteristics from the assessment data we already collected.
# These are inputs to cost calculations and AI MI sizing recommendation.

function Get-ServerProfile {
    param(
        [string]$Server,
        [hashtable]$ServerData
    )
    $profileObj = [PSCustomObject]@{
        Server       = $Server
        VCpuEstimate = 4         # default for cost sizing
        RamGBEstimate = 16
        DbCount      = 0
        TotalDbGB    = 0
        Edition      = 'Standard'
        FindingsHigh = 0
        FindingsMed  = 0
        HasAg        = $false
        HasSsis      = $false
        HasUnsafeClr = $false
    }

    # Section 1: Instance Summary => Edition
    if ($ServerData['01_Instance_Summary'] -and $ServerData['01_Instance_Summary'].Rows.Count -gt 0) {
        $row = $ServerData['01_Instance_Summary'].Rows[0]
        try {
            $editionText = "$($row['Edition'])"
            # Order matters here. SQL 2025 has "Enterprise Developer Edition"
            # which contains BOTH "Enterprise" and "Developer" in the string.
            # It is licensed as Developer (free), not Enterprise. Check
            # "Developer" first so "Enterprise Developer" gets classified
            # correctly as free Developer Edition with Enterprise features.
            if ($editionText -match 'Developer') { $profileObj.Edition = 'Developer' }
            elseif ($editionText -match 'Enterprise') { $profileObj.Edition = 'Enterprise' }
            elseif ($editionText -match 'Standard') { $profileObj.Edition = 'Standard' }
            elseif ($editionText -match 'Web') { $profileObj.Edition = 'Web' }
        } catch {}
    }

    # Section 5: Database Inventory => count
    if ($ServerData['05_Database_Inventory']) {
        $profileObj.DbCount = $ServerData['05_Database_Inventory'].Rows.Count
        # SSISDB indicates SSIS catalog deployed
        foreach ($row in $ServerData['05_Database_Inventory'].Rows) {
            try {
                if ("$($row['DatabaseName'])" -eq 'SSISDB') { $profileObj.HasSsis = $true }
            } catch {}
        }
    }

    # Section 10: Database Files => total size
    if ($ServerData['10_Database_Files']) {
        $totalMB = 0
        foreach ($row in $ServerData['10_Database_Files'].Rows) {
            try { $totalMB += [int64]"$($row['SizeMB'])" } catch {}
        }
        $profileObj.TotalDbGB = [math]::Round($totalMB / 1024.0, 1)
    }

    # Section 9: CLR Assemblies => unsafe CLR present?
    if ($ServerData['09_CLR_Assemblies']) {
        foreach ($row in $ServerData['09_CLR_Assemblies'].Rows) {
            try {
                $perm = "$($row['PermissionSet'])"
                if ($perm -match 'UNSAFE' -or $perm -match 'EXTERNAL') { $profileObj.HasUnsafeClr = $true }
            } catch {}
        }
    }

    # Section 11: AGs present?
    if ($ServerData['11_Availability_Groups'] -and $ServerData['11_Availability_Groups'].Rows.Count -gt 0) {
        $profileObj.HasAg = $true
    }

    # Findings counts
    $sFindings = @($findings | Where-Object { $_.Server -eq $Server })
    $profileObj.FindingsHigh = @($sFindings | Where-Object { $_.Severity -eq 'High' }).Count
    $profileObj.FindingsMed  = @($sFindings | Where-Object { $_.Severity -eq 'Medium' }).Count

    # Heuristic for vCore sizing based on DB count and total size
    # (Real production would query the SQL Server for actual core count)
    if ($profileObj.TotalDbGB -gt 500 -or $profileObj.DbCount -gt 20) {
        $profileObj.VCpuEstimate = 8
        $profileObj.RamGBEstimate = 32
    } elseif ($profileObj.TotalDbGB -gt 100 -or $profileObj.DbCount -gt 10) {
        $profileObj.VCpuEstimate = 4
        $profileObj.RamGBEstimate = 16
    } else {
        $profileObj.VCpuEstimate = 4
        $profileObj.RamGBEstimate = 16
    }

    return $profileObj
}


# -----------------------------------------------------------------------------
# COST CALCULATIONS
# -----------------------------------------------------------------------------

function Calculate-DcToDcCost {
    param([PSCustomObject]$Profile)
    # Annual on-prem TCO components per server.
    # Uses reference rates - clearly an estimate; intent is order-of-magnitude.
    $hardware = $ReferenceRates.HardwareRefreshUSD / $ReferenceRates.HardwareLifeYears
    $colo     = $ReferenceRates.ColocationPerYear
    $labor    = $ReferenceRates.OperationalLaborYearly
    $storage  = $Profile.TotalDbGB * $ReferenceRates.StoragePerGBMonth * 12

    # SQL license: rough estimate based on edition and core count
    $coresFor2Pack = [math]::Ceiling($Profile.VCpuEstimate / 2.0)
    $license = if ($Profile.Edition -eq 'Enterprise') {
        $ReferenceRates.SqlEntLicensePer2Cores * $coresFor2Pack / $ReferenceRates.HardwareLifeYears
    } elseif ($Profile.Edition -eq 'Developer') {
        0   # Developer is free
    } else {
        $ReferenceRates.SqlStdLicensePer2Cores * $coresFor2Pack / $ReferenceRates.HardwareLifeYears
    }

    return [PSCustomObject]@{
        Total     = [math]::Round($hardware + $colo + $labor + $storage + $license, 0)
        Hardware  = [math]::Round($hardware, 0)
        Colo      = [math]::Round($colo, 0)
        Labor     = [math]::Round($labor, 0)
        Storage   = [math]::Round($storage, 0)
        License   = [math]::Round($license, 0)
        Notes     = 'Industry reference rates; refresh quarterly.'
    }
}

function Calculate-AzureVmCost {
    param(
        [PSCustomObject]$Profile,
        [switch]$BringYourOwnLicense
    )
    # Map vCPU estimate to a representative VM SKU (cores match)
    $vmSku = if ($Profile.VCpuEstimate -ge 16) { 'Standard_D16s_v5' }
             elseif ($Profile.VCpuEstimate -ge 8) { 'Standard_D8s_v5' }
             elseif ($Profile.VCpuEstimate -ge 4) { 'Standard_D4s_v5' }
             else { 'Standard_D2s_v5' }

    # Extract core count from SKU name (D2=2 cores, D4=4 cores, etc.)
    $coreCount = if ($vmSku -match 'D(\d+)s') { [int]$Matches[1] } else { 4 }

    # Base VM hourly rate (always same regardless of BYOL/PAYG)
    $baseHourly = [double](Get-AzureVmHourlyPrice -Region $PricingRegion -VmSku $vmSku)

    # SQL license add-on (PAYG only - BYOL applies Azure Hybrid Benefit so no add-on)
    $licenseHourly = if ($BringYourOwnLicense) {
        [double]0
    } else {
        [double](Get-SqlLicenseHourlyAddOn -Edition $Profile.Edition -CoreCount $coreCount)
    }

    $hourlyTotal = [double]($baseHourly + $licenseHourly)
    $compute = [double]($hourlyTotal * 24 * 365)

    # Storage (managed disk, premium SSD): rough $0.135/GB-month for P-series
    $storage = [double]([double]$Profile.TotalDbGB * 0.135 * 12)

    # Egress allowance: small, ~$50/month for typical migrations
    $egress = [double]600

    return [PSCustomObject]@{
        Total      = [math]::Round([double]($compute + $storage + $egress), 0)
        Compute    = [math]::Round([double]$compute, 0)
        Storage    = [math]::Round([double]$storage, 0)
        Egress     = [math]::Round([double]$egress, 0)
        VmSku      = $vmSku
        CoreCount  = $coreCount
        HourlyBase = [math]::Round([double]$baseHourly, 4)
        HourlySql  = [math]::Round([double]$licenseHourly, 4)
        HourlyAll  = [math]::Round([double]$hourlyTotal, 4)
        Notes      = if ($BringYourOwnLicense) { "BYOL: assumes Azure Hybrid Benefit applied to existing $($Profile.Edition) license. No SQL add-on cost." } else { "PAYG: SQL $($Profile.Edition) license metered at per-core rate." }
    }
}

function Calculate-AzureMiCost {
    param(
        [PSCustomObject]$Profile,
        [string]$Tier = 'GeneralPurpose',
        [int]$VCore = 8
    )
    $hourlyPrice = Get-AzureMiHourlyPrice -Region $PricingRegion -Tier $Tier -VCore $VCore
    $compute = [double]$hourlyPrice * 24 * 365

    # MI storage: priced from byte 1 (not "extra beyond included"). Calculator-
    # validated: 256 GB at 8 vCore GP = $25.76/month = $0.1006/GB/month.
    # Minimum allocation = max(database size, 32GB per vCore).
    # Source: Azure Pricing Calculator cross-validation.
    $minStorageGB = [double]($VCore * 32)
    $dbSizeWithHeadroom = [double]([math]::Ceiling([double]$Profile.TotalDbGB * 1.5))
    $allocatedGB = [double][math]::Max($minStorageGB, $dbSizeWithHeadroom)
    $storageRate = [double]0.1006
    $storage = [double]($allocatedGB * $storageRate * 12)

    # Backup: 100% of DB size included free; long-term retention extra (skipped here)
    $backup = [double]0

    return [PSCustomObject]@{
        Total       = [math]::Round([double]($compute + $storage + $backup), 0)
        Compute     = [math]::Round([double]$compute, 0)
        Storage     = [math]::Round([double]$storage, 0)
        Backup      = $backup
        Tier        = $Tier
        VCore       = $VCore
        HourlyRate  = [math]::Round([double]$hourlyPrice, 4)
        StorageGB   = [int]$allocatedGB
        Notes       = "MI $Tier $VCore vCore. Storage allocated $([int]$allocatedGB) GB at `$$storageRate/GB-month."
    }
}


# -----------------------------------------------------------------------------
# AI REASONING - per-server recommendation
# -----------------------------------------------------------------------------

function Get-AiMiSizing {
    param([PSCustomObject]$Profile)
    # Default sizing if AI fails
    $defaultTier = 'GeneralPurpose'
    $defaultVCore = 8

    if (-not $LlmReady) {
        return [PSCustomObject]@{ Tier = $defaultTier; VCore = $defaultVCore; Reason = 'AI not available; using default sizing.' }
    }

    $sysPrompt = @'
You are a senior Azure SQL Managed Instance sizing expert. Given workload
characteristics for a single SQL Server, recommend the right MI tier and
vCore count.

Your response must be ONLY valid JSON in this exact shape (no other text):
{"tier": "GeneralPurpose" or "BusinessCritical", "vcore": <integer 8-80>, "reason": "<one sentence>"}

Sizing guidance:
- GeneralPurpose: standard workloads, dev/test, departmental databases
- BusinessCritical: high IOPS, low-latency, mission-critical, AGs/HA workloads
- vCore MINIMUM is 8 - below that, recommend Azure SQL Database, not MI
- vCore: 8 for small/medium workloads, 16 for moderate, 24-32 for large, 40+ for very large
- Round up if HA is required (BusinessCritical) or DB count > 20
- IMPORTANT: 4 vCore MI exists in the catalog but is sub-minimal for production. Always use 8 vCore as the floor.
'@

    $userPrompt = @"
Server: $($Profile.Server)
Edition: $($Profile.Edition)
Estimated vCPU on-prem: $($Profile.VCpuEstimate)
Estimated RAM (GB) on-prem: $($Profile.RamGBEstimate)
Database count: $($Profile.DbCount)
Total DB size (GB): $($Profile.TotalDbGB)
HA / Availability Groups: $($Profile.HasAg)
SSIS catalog present: $($Profile.HasSsis)
UNSAFE CLR present: $($Profile.HasUnsafeClr)
High-severity findings: $($Profile.FindingsHigh)
Medium-severity findings: $($Profile.FindingsMed)

Recommend the MI tier and vCore.
"@

    $reply = Invoke-LlmCompletion -SystemPrompt $sysPrompt -UserPrompt $userPrompt -MaxTokens 256
    if (-not $reply) {
        return [PSCustomObject]@{ Tier = $defaultTier; VCore = $defaultVCore; Reason = 'AI call failed; using default sizing.' }
    }

    # Parse JSON from reply (LLM might wrap it; be tolerant)
    try {
        $jsonMatch = [regex]::Match($reply, '\{[^}]*\}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($jsonMatch.Success) {
            $parsed = $jsonMatch.Value | ConvertFrom-Json
            $tier  = if ($parsed.tier -match 'Business') { 'BusinessCritical' } else { 'GeneralPurpose' }
            $vcore = [int]$parsed.vcore
            # Enforce minimum 8 vCore - below that, customers should use
            # Azure SQL Database, not Managed Instance. 4 vCore MI exists in
            # the catalog but is sub-minimal for any real production workload.
            if ($vcore -lt 8) { $vcore = 8 }
            if ($vcore -gt 80) { $vcore = 80 }
            return [PSCustomObject]@{ Tier = $tier; VCore = $vcore; Reason = "$($parsed.reason)" }
        }
    } catch {}

    return [PSCustomObject]@{ Tier = $defaultTier; VCore = $defaultVCore; Reason = 'AI response unparseable; using default sizing.' }
}

function Get-AiServerRecommendation {
    param(
        [PSCustomObject]$Profile,
        [PSCustomObject]$DcCost,
        [PSCustomObject]$AzVmPaygCost,
        [PSCustomObject]$AzVmByolCost,
        [PSCustomObject]$AzMiCost
    )
    $defaultRec = [PSCustomObject]@{
        RecommendedTarget = 'Azure VM (BYOL)'
        Narrative         = 'AI not available - default to Azure VM with Bring Your Own License as the most cost-effective lift-and-shift target. Review individual findings on the per-server tab for blockers.'
    }

    if (-not $LlmReady) { return $defaultRec }

    $sysPrompt = @'
You are a senior Azure migration architect advising a customer on the right
target for a single SQL Server. You will be given workload characteristics,
a list of significant findings, and the 1-year cost for each migration target.

Your response must be ONLY valid JSON in this exact shape (no other text):
{"target": "<one of: DC-DC, Azure VM (PAYG), Azure VM (BYOL), Azure SQL MI>", "narrative": "<3-5 sentences explaining the recommendation, citing specific findings and cost trade-offs>"}

Decision principles:
- UNSAFE CLR or SSIS catalog: MI is blocked, prefer Azure VM
- Significant HA/AG complexity: Azure VM preserves it; MI requires re-architecture
- Low blocker count + clean workload: MI is preferred for ops savings even if slightly more expensive
- Cost ties broken in favor of less operational burden (MI > VM > DC)
- DC-DC is rarely the best choice unless cost gap is dramatic
- TIE-BREAKING for Azure VM: when PAYG and BYOL costs are EQUAL or within 5%, ALWAYS recommend "Azure VM (BYOL)" - it is the more enterprise-typical choice via Azure Hybrid Benefit, even if there is no immediate cost difference (e.g., Developer Edition where SQL license is free either way). The narrative should note that PAYG and BYOL are equivalent for this edition but BYOL is recommended as the standard enterprise pattern.
'@

    $userPrompt = @"
Server: $($Profile.Server)
Edition: $($Profile.Edition)
DB count: $($Profile.DbCount), Total size: $($Profile.TotalDbGB) GB
HA/AG: $($Profile.HasAg), SSIS: $($Profile.HasSsis), UNSAFE CLR: $($Profile.HasUnsafeClr)
Findings: $($Profile.FindingsHigh) High, $($Profile.FindingsMed) Medium

1-Year Costs:
- DC-to-DC (stay on-prem):      `$$($DcCost.Total)
- DC-to-Azure VM (PAYG):        `$$($AzVmPaygCost.Total)
- DC-to-Azure VM (BYOL/AHB):    `$$($AzVmByolCost.Total)
- DC-to-Azure SQL MI:           `$$($AzMiCost.Total) ($($AzMiCost.Tier), $($AzMiCost.VCore) vCore)

Recommend the right target and explain why. Reference specific findings and cost numbers.
"@

    $reply = Invoke-LlmCompletion -SystemPrompt $sysPrompt -UserPrompt $userPrompt -MaxTokens 600
    if (-not $reply) { return $defaultRec }

    try {
        $jsonMatch = [regex]::Match($reply, '\{.*\}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($jsonMatch.Success) {
            $parsed = $jsonMatch.Value | ConvertFrom-Json
            return [PSCustomObject]@{
                RecommendedTarget = "$($parsed.target)"
                Narrative         = "$($parsed.narrative)"
            }
        }
    } catch {}

    return $defaultRec
}

function Get-AiEstateSynthesis {
    param([array]$AllRecommendations)
    if (-not $LlmReady) {
        return 'AI synthesis not available. Review individual server recommendations and the cost summary table below for migration priorities.'
    }

    $sysPrompt = @'
You are a senior cloud migration architect summarizing an estate-wide
SQL Server migration strategy for executive leadership. You will be given
per-server recommendations and 1-year costs.

Your response should be 2-3 paragraphs of plain prose (no markdown, no bullets):
- Paragraph 1: Estate at a glance - count by recommendation, total estimated cost savings if any
- Paragraph 2: Phasing recommendation - which servers go first, why, and timeline
- Paragraph 3: Key risks and the most common blocker pattern across the estate

Be specific. Reference actual server names and cost numbers. Do not pad.
'@

    $serverSummary = ($AllRecommendations | ForEach-Object {
        "$($_.Server): recommended $($_.Recommendation), DC=`$$($_.DcCost), AzVM-PAYG=`$$($_.AzVmPaygCost), AzVM-BYOL=`$$($_.AzVmByolCost), AzMI=`$$($_.AzMiCost)"
    }) -join "`n"

    $userPrompt = "Estate of $($AllRecommendations.Count) servers.`n`n$serverSummary`n`nWrite the executive synthesis."

    $reply = Invoke-LlmCompletion -SystemPrompt $sysPrompt -UserPrompt $userPrompt -MaxTokens 800
    if (-not $reply) {
        return 'AI synthesis call failed. Review the per-server scoreboard and cost table below for migration priorities.'
    }
    return $reply.Trim()
}


# -----------------------------------------------------------------------------
# RUN THE AI ENGINE PER SERVER
# -----------------------------------------------------------------------------
Write-Host '  Computing AI-driven cost analysis per server...' -ForegroundColor Cyan

# Per-server data structures populated below
$ServerProfiles      = @{}
$DcCosts             = @{}
$AzVmPaygCosts       = @{}
$AzVmByolCosts       = @{}
$AzMiCosts           = @{}
$MiSizings           = @{}
$ServerRecommendations = @{}

foreach ($server in ($allData.Keys | Sort-Object)) {
    Write-Host "    $server..." -NoNewline
    $sd = $allData[$server]

    # Profile + DC cost (cheap, no API)
    $prof = Get-ServerProfile -Server $server -ServerData $sd
    $ServerProfiles[$server] = $prof
    $DcCosts[$server] = Calculate-DcToDcCost -Profile $prof

    # AI MI sizing FIRST so VM and MI compare at the same vCore count.
    # This is what an architect would do: pick the right size, then compare
    # platform options at that size. Otherwise VM/MI cost numbers are
    # apples-to-oranges (e.g. 4 vCore VM vs 8 vCore MI).
    $sizing = Get-AiMiSizing -Profile $prof
    $MiSizings[$server] = $sizing

    # Sync the profile's vCPU estimate up to match the MI-recommended size
    # so VM cost is comparable. Only sync up, never down (don't undersize).
    if ($sizing.VCore -gt $prof.VCpuEstimate) {
        $prof.VCpuEstimate = $sizing.VCore
        $prof.RamGBEstimate = $sizing.VCore * 4   # rough 4GB per vCore for D-series
    }

    # Azure VM costs (live API, but cached after first SKU lookup)
    $AzVmPaygCosts[$server] = Calculate-AzureVmCost -Profile $prof
    $AzVmByolCosts[$server] = Calculate-AzureVmCost -Profile $prof -BringYourOwnLicense

    # MI cost (uses sizing already determined above)
    $AzMiCosts[$server] = Calculate-AzureMiCost -Profile $prof -Tier $sizing.Tier -VCore $sizing.VCore

    # AI recommendation (1 LLM call per server)
    $rec = Get-AiServerRecommendation -Profile $prof `
        -DcCost $DcCosts[$server] `
        -AzVmPaygCost $AzVmPaygCosts[$server] `
        -AzVmByolCost $AzVmByolCosts[$server] `
        -AzMiCost $AzMiCosts[$server]
    $ServerRecommendations[$server] = $rec

    Write-Host " done ($($rec.RecommendedTarget))" -ForegroundColor Green
}

# Estate-wide synthesis (1 LLM call total)
Write-Host '  Computing estate-wide AI synthesis...' -NoNewline -ForegroundColor Cyan
$estateRecArray = foreach ($server in ($allData.Keys | Sort-Object)) {
    [PSCustomObject]@{
        Server         = $server
        Recommendation = $ServerRecommendations[$server].RecommendedTarget
        DcCost         = $DcCosts[$server].Total
        AzVmPaygCost   = $AzVmPaygCosts[$server].Total
        AzVmByolCost   = $AzVmByolCosts[$server].Total
        AzMiCost       = $AzMiCosts[$server].Total
    }
}
$EstateSynthesis = Get-AiEstateSynthesis -AllRecommendations $estateRecArray
Write-Host ' done' -ForegroundColor Green
Write-Host ''


# -----------------------------------------------------------------------------
# Executive Summary sheet
# -----------------------------------------------------------------------------
# The CIO-facing tab. Designed for someone with 60 seconds, not 60 minutes.
#
# Layout:
#   Row 1     - title banner (navy, 14pt)
#   Row 3     - narrative paragraph (auto-generated from the tallies)
#   Row 5     - "Estate at a Glance" sub-banner
#   Rows 6-7  - 6 headline tiles (label + big number, color-coded)
#   Row 9     - "Top 3 Blockers" sub-banner
#   Rows 10+  - the most-frequent High-severity finding sources estate-wide
#   Then     - "Per-Server Scoreboard" with Server | Score | Label |
#              High | Medium | Top Issue (color-coded by label)
#
# The narrative paragraph is templated, not free-form. We pick the right
# closing phrase based on whether Blocked > Ready (mostly blocked),
# Ready > Blocked (mostly ready), or they tie (mixed).

$es = $pkg.Workbook.Worksheets.Add('Executive Summary')

# --- Row 1: title banner ---
$es.Cells[1, 1].Value = 'Executive Summary - SQL Server to Cloud Migration'
$es.Cells[1, 1, 1, 6].Merge = $true
$es.Cells[1, 1].Style.Font.Bold = $true
$es.Cells[1, 1].Style.Font.Size = 14
$es.Cells[1, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$es.Cells[1, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$es.Cells[1, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$es.Cells[1, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
$es.Row(1).Height = 28

# --- Row 3: narrative paragraph ---
$mostCommonVerdict = if ($blockedCount -gt $readyCount) { 'most servers are blocked from Azure SQL MI' }
                    elseif ($readyCount -gt $blockedCount) { 'most servers are MI-ready' }
                    else { 'the estate is mixed' }

$narrative = "$serverCount servers were assessed. $highCount High-severity and $medCount Medium-severity findings identified across the estate. " +
             "MI readiness: $readyCount Ready, $condCount Conditional, $blockedCount Blocked - $mostCommonVerdict. " +
             "Recommended approach: address blockers (see Remediation Plan) for Conditional servers; consider Azure VM (SQL on IaaS) for Blocked servers as a lift-and-shift fallback."

$es.Cells[3, 1].Value = $narrative
$es.Cells[3, 1, 3, 6].Merge = $true
$es.Cells[3, 1].Style.WrapText = $true
$es.Cells[3, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
$es.Cells[3, 1].Style.Font.Size = 11
$es.Row(3).Height = 60

# --- Row 5: headline tile banner ---
$es.Cells[5, 1].Value = 'Estate at a Glance'
$es.Cells[5, 1, 5, 6].Merge = $true
$es.Cells[5, 1].Style.Font.Bold = $true
$es.Cells[5, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$es.Cells[5, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$es.Cells[5, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$es.Cells[5, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
$es.Row(5).Height = 22

# --- Rows 6-7: tile labels and values (6 tiles across) ---
$tiles = @(
    @{ Label = 'Servers Assessed'; Value = "$serverCount"; Color = '#2E75B6' },
    @{ Label = 'High Findings'; Value = "$highCount"; Color = $RedText },
    @{ Label = 'Medium Findings'; Value = "$medCount"; Color = $AmberText },
    @{ Label = 'MI Ready'; Value = "$readyCount"; Color = $GreenText },
    @{ Label = 'Conditional'; Value = "$condCount"; Color = $AmberText },
    @{ Label = 'Blocked'; Value = "$blockedCount"; Color = $RedText }
)

for ($i = 0; $i -lt $tiles.Count; $i++) {
    [int]$col = $i + 1
    $labelCell = $es.Cells.Item(6, $col)
    $labelCell.Value = $tiles[$i].Label
    $labelCell.Style.Font.Bold = $true
    $labelCell.Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center
    $labelCell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $labelCell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($LightHex))

    $valCell = $es.Cells.Item(7, $col)
    $valCell.Value = $tiles[$i].Value
    $valCell.Style.Font.Bold = $true
    $valCell.Style.Font.Size = 18
    $valCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($tiles[$i].Color))
    $valCell.Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center
}
$es.Row(6).Height = 18
$es.Row(7).Height = 32

# --- Row 9: Top 3 Blockers banner ---
$es.Cells[9, 1].Value = 'Top 3 Blockers (most frequent High findings)'
$es.Cells[9, 1, 9, 6].Merge = $true
$es.Cells[9, 1].Style.Font.Bold = $true
$es.Cells[9, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$es.Cells[9, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$es.Cells[9, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$es.Cells[9, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
$es.Row(9).Height = 22

# Rows 10+: top blockers list
$rowIdx = 10
if ($top3Blockers.Count -eq 0) {
    $es.Cells[$rowIdx, 1].Value = '(no High-severity blockers found)'
    $es.Cells[$rowIdx, 1, $rowIdx, 6].Merge = $true
    $es.Cells[$rowIdx, 1].Style.Font.Italic = $true
    $rowIdx++
} else {
    foreach ($b in $top3Blockers) {
        $es.Cells[$rowIdx, 1].Value = "$($b.Key)"
        $es.Cells[$rowIdx, 1, $rowIdx, 5].Merge = $true
        $es.Cells.Item($rowIdx, 6).Value = "$($b.Value) servers"
        $es.Cells.Item($rowIdx, 6).Style.Font.Bold = $true
        $es.Cells.Item($rowIdx, 6).Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($RedText))
        $rowIdx++
    }
}

# --- Per-Server Scoreboard banner ---
$rowIdx++   # gap
$scoreBannerRow = $rowIdx
$es.Cells[$scoreBannerRow, 1].Value = 'Per-Server Scoreboard'
$es.Cells[$scoreBannerRow, 1, $scoreBannerRow, 6].Merge = $true
$es.Cells[$scoreBannerRow, 1].Style.Font.Bold = $true
$es.Cells[$scoreBannerRow, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$es.Cells[$scoreBannerRow, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$es.Cells[$scoreBannerRow, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$es.Cells[$scoreBannerRow, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
$es.Row($scoreBannerRow).Height = 22
$rowIdx++

# Scoreboard headers
$scoreHeaders = @('Server', 'Score', 'Label', 'High', 'Medium', 'Top Issue')
for ($i = 0; $i -lt $scoreHeaders.Count; $i++) {
    [int]$col = $i + 1
    $hcell = $es.Cells.Item($rowIdx, $col)
    $hcell.Value = $scoreHeaders[$i]
    $hcell.Style.Font.Bold = $true
    $hcell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $hcell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($LightHex))
}
$rowIdx++

# Scoreboard data rows
foreach ($server in ($allData.Keys | Sort-Object)) {
    $sFindings = @($findings | Where-Object { $_.Server -eq $server })
    $sHigh = @($sFindings | Where-Object { $_.Severity -eq 'High' }).Count
    $sMed  = @($sFindings | Where-Object { $_.Severity -eq 'Medium' }).Count

    $es.Cells.Item($rowIdx, 1).Value = $server
    $es.Cells.Item($rowIdx, 2).Value = "$($ScoreByServer[$server])"
    $es.Cells.Item($rowIdx, 3).Value = "$($LabelByServer[$server])"
    $es.Cells.Item($rowIdx, 4).Value = "$sHigh"
    $es.Cells.Item($rowIdx, 5).Value = "$sMed"
    $es.Cells.Item($rowIdx, 6).Value = "$($TopIssueByServer[$server])"

    # Color the Label cell based on label
    $lbl = $LabelByServer[$server]
    $lblCell = $es.Cells.Item($rowIdx, 3)
    $lblCell.Style.Font.Bold = $true
    if ($lbl -eq 'Ready') {
        $lblCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($GreenText))
    } elseif ($lbl -eq 'Conditional') {
        $lblCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($AmberText))
    } else {
        $lblCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($RedText))
    }

    # Score color: same scheme
    $scCell = $es.Cells.Item($rowIdx, 2)
    $scCell.Style.Font.Bold = $true
    if ($lbl -eq 'Ready') {
        $scCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($GreenText))
    } elseif ($lbl -eq 'Conditional') {
        $scCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($AmberText))
    } else {
        $scCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($RedText))
    }

    $rowIdx++
}

# -----------------------------------------------------------------------------
# CLOUD MIGRATION MATRIX (cloud-grouped tick/cross by server)
# -----------------------------------------------------------------------------
# Visual scoreboard of which cloud targets each assessed server can land in.
# Rows are grouped by cloud (Azure / AWS / GCP); columns are servers.
#
# Per-cell rule:
#   - IaaS targets (Azure VM, AWS EC2, GCP Compute Engine):
#       ALWAYS tick. Lift-and-shift to a VM preserves on-prem feature set,
#       so IaaS is viable for every server regardless of findings.
#
#   - Managed / PaaS targets (Azure SQL MI, Azure SQL DB, AWS RDS, GCP
#     Cloud SQL): tick if MI Label is 'Ready', cross otherwise. Conditional
#     and Blocked both render as cross because both have remediation work
#     before the PaaS target is viable. Azure SQL MI's readiness is used as
#     the proxy for AWS RDS / GCP Cloud SQL because the same instance-level
#     blockers (UNSAFE CLR, FileStream/FileTable, cross-DB queries, Linked
#     Servers, etc.) gate all three managed offerings.
#
# Layout (dynamic in server count N):
#   row sec     - "Cloud Migration Matrix" title (merged A:lastCol)
#   row sec+1   - subtitle "{N} servers assessed. ..." (merged A:lastCol)
#   row hdr     - column headers: Cloud | Target | <server1>..<serverN>
#   row +1      - Azure cloud header band (#0078D4)
#   rows...     - Azure VM, Azure SQL MI, Azure SQL DB
#   row         - AWS cloud header band (#FF9900)
#   rows...     - AWS EC2, AWS RDS for SQL Server
#   row         - GCP cloud header band (#4285F4)
#   rows...     - GCP Compute Engine, GCP Cloud SQL for SQL Server
#   row         - blank
#   row         - "Legend:" + tick swatch + description
#   row         - cross swatch + description
#   row         - blank
#   row         - "Notes:" anchor + 3 explanatory note rows

# Sorted server list - used as columns. Same sort order as the scoreboard above.
$matrixServers = @($allData.Keys | Sort-Object)
$matrixServerCount = $matrixServers.Count

# Last column index: 2 fixed cols (Cloud, Target) + N server cols.
[int]$matrixLastCol = 2 + $matrixServerCount

# Brand colour palette (kept local to this block so the rest of the script is untouched).
$AzureBrandHex = '#0078D4'
$AwsBrandHex   = '#FF9900'
$GcpBrandHex   = '#4285F4'
$TickFillHex   = '#C6EFCE'   # light green
$TickTextHex   = '#27500A'   # dark green
$CrossFillHex  = '#FFC7CE'   # light red/pink
$CrossTextHex  = '#791F1F'   # dark red
$MatrixTitleTextHex    = '#1F3864'   # navy text (no fill) for the section title
$MatrixSubtitleTextHex = '#595959'

$rowIdx++   # gap row before the matrix section

# --- Section title row ---
$matrixTitleRow = $rowIdx
$es.Cells[$matrixTitleRow, 1].Value = 'Cloud Migration Matrix - Estate Fit'
$es.Cells[$matrixTitleRow, 1, $matrixTitleRow, $matrixLastCol].Merge = $true
$es.Cells[$matrixTitleRow, 1].Style.Font.Bold = $true
$es.Cells[$matrixTitleRow, 1].Style.Font.Size = 14
$es.Cells[$matrixTitleRow, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($MatrixTitleTextHex))
$es.Row($matrixTitleRow).Height = 22
$rowIdx++

# --- Subtitle row ---
$es.Cells[$rowIdx, 1].Value = "$matrixServerCount servers assessed. Tick = migration viable. Cross = blocked by current findings."
$es.Cells[$rowIdx, 1, $rowIdx, $matrixLastCol].Merge = $true
$es.Cells[$rowIdx, 1].Style.Font.Size = 10
$es.Cells[$rowIdx, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($MatrixSubtitleTextHex))
$rowIdx++

$rowIdx++   # gap before header band

# --- Column-header band (navy) ---
$matrixHdrRow = $rowIdx
$es.Cells[$matrixHdrRow, 1].Value = 'Cloud'
$es.Cells[$matrixHdrRow, 2].Value = 'Target deployment'
for ($i = 0; $i -lt $matrixServerCount; $i++) {
    [int]$col = 3 + $i
    $es.Cells.Item($matrixHdrRow, $col).Value = $matrixServers[$i]
}
for ($c = 1; $c -le $matrixLastCol; $c++) {
    [int]$cInt = $c
    $hcell = $es.Cells.Item($matrixHdrRow, $cInt)
    $hcell.Style.Font.Bold = $true
    $hcell.Style.Font.Size = 11
    $hcell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
    $hcell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $hcell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
    $hcell.Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center
}
$es.Row($matrixHdrRow).Height = 22
$rowIdx++

# Helper scriptblock: emit one cloud's block (header band + target rows).
# Uses $script:rowIdx so it can advance the outer counter. Reads other
# captured vars ($es, $matrixServers, $matrixServerCount, $matrixLastCol,
# $LabelByServer, $NavyHex, tick/cross palette) from the enclosing scope.
$EmitCloudBlock = {
    param(
        [string]$CloudName,
        [string]$CloudHex,
        [System.Collections.IList]$Targets   # each: @{ Name='...'; IsIaaS=$true/$false }
    )

    # Cloud header band - cloud name in col A, brand fill across full row
    $bandRow = $script:rowIdx
    $es.Cells[$bandRow, 1].Value = $CloudName
    for ($c = 1; $c -le $matrixLastCol; $c++) {
        [int]$cInt = $c
        $bcell = $es.Cells.Item($bandRow, $cInt)
        $bcell.Style.Font.Bold = $true
        $bcell.Style.Font.Size = 11
        $bcell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
        $bcell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
        $bcell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($CloudHex))
    }
    $es.Row($bandRow).Height = 20
    $script:rowIdx++

    # Target rows
    foreach ($t in $Targets) {
        $tRow = $script:rowIdx
        $es.Cells[$tRow, 2].Value = $t.Name
        $es.Cells[$tRow, 2].Style.Font.Size = 10

        for ($i = 0; $i -lt $matrixServerCount; $i++) {
            [int]$col = 3 + $i
            $server = $matrixServers[$i]

            # Decide tick vs cross.
            $isViable = $false
            if ($t.IsIaaS) {
                $isViable = $true
            } else {
                $isViable = ($LabelByServer[$server] -eq 'Ready')
            }

            $cell = $es.Cells.Item($tRow, $col)
            # PatternType MUST be set before BackgroundColor.SetColor or EPPlus
            # throws "Can't set color when patterntype is not set."
            $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            if ($isViable) {
                $cell.Value = [string][char]0x2713   # tick
                $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($TickFillHex))
                $cell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($TickTextHex))
            } else {
                $cell.Value = [string][char]0x2717   # cross
                $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($CrossFillHex))
                $cell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($CrossTextHex))
            }
            $cell.Style.Font.Bold = $true
            $cell.Style.Font.Size = 14
            $cell.Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center
            $cell.Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
        }
        $es.Row($tRow).Height = 20
        $script:rowIdx++
    }
}

# --- Azure block ---
& $EmitCloudBlock 'Azure' $AzureBrandHex @(
    @{ Name = 'Azure VM (IaaS)';            IsIaaS = $true  },
    @{ Name = 'Azure SQL Managed Instance'; IsIaaS = $false },
    @{ Name = 'Azure SQL Database';         IsIaaS = $false }
)

# --- AWS block ---
& $EmitCloudBlock 'AWS' $AwsBrandHex @(
    @{ Name = 'AWS EC2 (IaaS)';           IsIaaS = $true  },
    @{ Name = 'AWS RDS for SQL Server';   IsIaaS = $false }
)

# --- GCP block ---
& $EmitCloudBlock 'GCP' $GcpBrandHex @(
    @{ Name = 'GCP Compute Engine (IaaS)';     IsIaaS = $true  },
    @{ Name = 'GCP Cloud SQL for SQL Server';  IsIaaS = $false }
)

$rowIdx++   # gap before legend

# --- Legend ---
$legendStart = $rowIdx
$es.Cells[$legendStart, 1].Value = 'Legend:'
$es.Cells[$legendStart, 1].Style.Font.Bold = $true

$tickLegend = $es.Cells.Item($legendStart, 2)
$tickLegend.Value = [string][char]0x2713
$tickLegend.Style.Font.Bold = $true
$tickLegend.Style.Font.Size = 14
$tickLegend.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($TickTextHex))
$tickLegend.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$tickLegend.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($TickFillHex))
$tickLegend.Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center

$es.Cells[$legendStart, 3].Value = 'Migration viable'
$rowIdx++

$crossLegend = $es.Cells.Item($rowIdx, 2)
$crossLegend.Value = [string][char]0x2717
$crossLegend.Style.Font.Bold = $true
$crossLegend.Style.Font.Size = 14
$crossLegend.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($CrossTextHex))
$crossLegend.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$crossLegend.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($CrossFillHex))
$crossLegend.Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center

$es.Cells[$rowIdx, 3].Value = 'Blocked by current findings'
$rowIdx++

$rowIdx++   # gap before notes

# --- Notes ---
$es.Cells[$rowIdx, 1].Value = 'Notes:'
$es.Cells[$rowIdx, 1].Style.Font.Bold = $true
$rowIdx++

$matrixNotes = @(
    'Per-server blocker detail in each server tab (Section 6: DB-Level Findings, Section 9: CLR Assemblies).',
    'Common blockers across estate: UNSAFE CLR assemblies, FileStream/FileTable, instance-level features.',
    'IaaS targets (VM/EC2/Compute Engine) preserve on-prem feature set. Managed/PaaS targets require remediation.'
)
foreach ($note in $matrixNotes) {
    $es.Cells[$rowIdx, 2].Value = $note
    $es.Cells[$rowIdx, 2, $rowIdx, $matrixLastCol].Merge = $true
    $es.Cells[$rowIdx, 2].Style.Font.Size = 9
    $es.Cells[$rowIdx, 2].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($MatrixSubtitleTextHex))
    $es.Cells[$rowIdx, 2].Style.WrapText = $true
    $rowIdx++
}

$rowIdx++   # gap before next section


# -----------------------------------------------------------------------------
# AI ESTATE SYNTHESIS (auto-generated narrative) -- existing block continues
# -----------------------------------------------------------------------------
$rowIdx++   # gap
$synthBannerRow = $rowIdx
$es.Cells[$synthBannerRow, 1].Value = 'AI Estate Migration Strategy (auto-generated)'
$es.Cells[$synthBannerRow, 1, $synthBannerRow, 6].Merge = $true
$es.Cells[$synthBannerRow, 1].Style.Font.Bold = $true
$es.Cells[$synthBannerRow, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$es.Cells[$synthBannerRow, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$es.Cells[$synthBannerRow, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$es.Cells[$synthBannerRow, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
$es.Row($synthBannerRow).Height = 22
$rowIdx++

$es.Cells[$rowIdx, 1].Value = $EstateSynthesis
$es.Cells[$rowIdx, 1, $rowIdx, 6].Merge = $true
$es.Cells[$rowIdx, 1].Style.WrapText = $true
$es.Cells[$rowIdx, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
$es.Cells[$rowIdx, 1].Style.Font.Size = 11
# Estimate height for 6-column merged region - a narrative paragraph of ~600
# chars fits in roughly 4-6 wrapped lines at this width.
$charsPerLine = 130
$synthLines = [math]::Max(4, [math]::Ceiling($EstateSynthesis.Length / $charsPerLine))
$es.Row($rowIdx).Height = [math]::Min(220, $synthLines * 16)
$rowIdx++

# -----------------------------------------------------------------------------
# COST SUMMARY TABLE (1-year costs per server per target)
# -----------------------------------------------------------------------------
$rowIdx++   # gap
$costBannerRow = $rowIdx
$es.Cells[$costBannerRow, 1].Value = '1-Year Cost Summary by Migration Target (USD)'
$es.Cells[$costBannerRow, 1, $costBannerRow, 6].Merge = $true
$es.Cells[$costBannerRow, 1].Style.Font.Bold = $true
$es.Cells[$costBannerRow, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$es.Cells[$costBannerRow, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$es.Cells[$costBannerRow, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$es.Cells[$costBannerRow, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
$es.Row($costBannerRow).Height = 22
$rowIdx++

# Cost table headers
$costHeaders = @('Server', 'DC-to-DC', 'AzVM PAYG', 'AzVM BYOL', 'Azure SQL MI', 'AI Recommendation')
for ($i = 0; $i -lt $costHeaders.Count; $i++) {
    [int]$col = $i + 1
    $hcell = $es.Cells.Item($rowIdx, $col)
    $hcell.Value = $costHeaders[$i]
    $hcell.Style.Font.Bold = $true
    $hcell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $hcell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($LightHex))
}
$rowIdx++

# Cost table data rows
foreach ($server in ($allData.Keys | Sort-Object)) {
    $rec      = $ServerRecommendations[$server]
    $dcTotal  = $DcCosts[$server].Total
    $vmPayg   = $AzVmPaygCosts[$server].Total
    $vmByol   = $AzVmByolCosts[$server].Total
    $miTotal  = $AzMiCosts[$server].Total

    $es.Cells.Item($rowIdx, 1).Value = $server
    $es.Cells.Item($rowIdx, 2).Value = "`$$('{0:N0}' -f $dcTotal)"
    $es.Cells.Item($rowIdx, 3).Value = "`$$('{0:N0}' -f $vmPayg)"
    $es.Cells.Item($rowIdx, 4).Value = "`$$('{0:N0}' -f $vmByol)"
    $es.Cells.Item($rowIdx, 5).Value = "`$$('{0:N0}' -f $miTotal)"
    $es.Cells.Item($rowIdx, 6).Value = $rec.RecommendedTarget
    $es.Cells.Item($rowIdx, 6).Style.Font.Bold = $true

    # Highlight the recommended cost cell in green
    $recTarget = $rec.RecommendedTarget
    $highlightCol = $null
    if     ($recTarget -match 'DC')          { $highlightCol = 2 }
    elseif ($recTarget -match 'PAYG')        { $highlightCol = 3 }
    elseif ($recTarget -match 'BYOL')        { $highlightCol = 4 }
    elseif ($recTarget -match 'MI')          { $highlightCol = 5 }
    elseif ($recTarget -match 'VM')          { $highlightCol = 4 }   # default to BYOL if VM unspecified
    if ($highlightCol) {
        $hcell = $es.Cells.Item($rowIdx, $highlightCol)
        $hcell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
        $hcell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml('#E2F0D9'))
        $hcell.Style.Font.Bold = $true
        $hcell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($GreenText))
    }
    $rowIdx++
}

# Footer note about pricing source
$rowIdx++
$priceTimestamp = if ($script:PricingFetchedAt) { $script:PricingFetchedAt.ToString('yyyy-MM-dd HH:mm zzz') } else { 'fallback rates' }
$es.Cells[$rowIdx, 1].Value = "Pricing fetched $priceTimestamp from Azure Retail Prices API (live, $PricingRegion). On-prem: industry reference rates, refresh quarterly. AI: $LlmProvider. See 'Methodology & Sources' tab for full details and caveats."
$es.Cells[$rowIdx, 1, $rowIdx, 6].Merge = $true
$es.Cells[$rowIdx, 1].Style.Font.Italic = $true
$es.Cells[$rowIdx, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#595959'))
$rowIdx++

# Column widths
$es.Column(1).Width = 22   # Server / labels
$es.Column(2).Width = 14
$es.Column(3).Width = 16
$es.Column(4).Width = 14
$es.Column(5).Width = 16
$es.Column(6).Width = 60   # AI rec / top issue
$es.View.FreezePanes(2, 1)

# -----------------------------------------------------------------------------
# Remediation Plan sheet
# -----------------------------------------------------------------------------
# For every finding, produce an actionable recommendation. This is what
# transforms the report from "audit" to "engagement deliverable".
#
# Get-Recommendation pattern-matches on the finding source string and returns
# the right boilerplate advice. Examples:
#
#   "xp_cmdshell"      -> "Disable via sp_configure; refactor any callers..."
#   "CLR Assembly"     -> "Replace UNSAFE/EXTERNAL_ACCESS with SAFE..."
#   "SQL Agent Job"    -> "Replace CmdExec/PowerShell/SSIS subsystems with..."
#   "Linked Server"    -> "Update provider to MSOLEDBSQL..."
#
# If no specific pattern matches, fall through to the existing 'MI Impact'
# string already attached to the finding.
#
# The output is sorted (High first, then Medium, then by server) and rendered
# with autofilter so users can sort/filter the action list any way they want.
# A focused list of issue + recommendation per finding (no effort/phase).

# Map each finding source to a recommendation. Falls back to the existing
# 'MI Impact' text on the finding if no specific recommendation is mapped.
function Get-Recommendation {
    param([string]$Source, [string]$Finding, [string]$MIImpact)
    $s = $Source.ToLower()
    if ($s -match 'xp_cmdshell')         { return 'Disable xp_cmdshell via sp_configure; refactor any callers to use Agent jobs or Azure Automation.' }
    if ($s -match 'clr')                 { return 'Identify the assembly owner; replace UNSAFE/EXTERNAL_ACCESS with SAFE if possible, or migrate logic out of the database (e.g. Azure Function).' }
    if ($s -match 'agent job')           { return 'Redesign job: replace CmdExec/PowerShell/SSIS subsystems with TSQL or move orchestration to Azure Data Factory / Azure Automation.' }
    if ($s -match 'linked server')       { return 'Update provider to MSOLEDBSQL; for non-SQL targets, evaluate Azure Data Factory linked services or Elastic Query.' }
    if ($s -match 'tde')                 { return 'Export the TDE certificate and private key; restore on the MI target before database restore.' }
    if ($s -match 'availability group')  { return 'Investigate replica health (SyncHealth, ConnectedState); resolve before MI Link / cutover.' }
    if ($s -match 't-sql')               { return 'Refactor flagged code patterns; test under MI compatibility level before migration.' }
    if ($s -match 'security')            { return 'Migrate Windows logins to Microsoft Entra ID (Azure AD) for MI; for RDS/Cloud SQL targets, convert to SQL Authentication.' }
    if ($MIImpact)                       { return $MIImpact }
    return 'Review for managed-target compatibility.'
}

$rpRows = @()
foreach ($f in $findingsSorted) {
    if ("$($f.Severity)" -eq 'No findings') { continue }
    $rec = Get-Recommendation -Source "$($f.Source)" -Finding "$($f.Finding)" -MIImpact "$($f.'MI Impact')"
    $rpRows += [PSCustomObject]@{
        Server         = "$($f.Server)"
        Severity       = "$($f.Severity)"
        Source         = "$($f.Source)"
        Object         = "$($f.Object)"
        Issue          = "$($f.Finding)"
        Recommendation = $rec
    }
}

$rp = $pkg.Workbook.Worksheets.Add('Remediation Plan')

# Row 1 - title banner
$rp.Cells[1, 1].Value = 'Remediation Plan - Issues and Recommended Actions'
$rp.Cells[1, 1, 1, 6].Merge = $true
$rp.Cells[1, 1].Style.Font.Bold = $true
$rp.Cells[1, 1].Style.Font.Size = 12
$rp.Cells[1, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$rp.Cells[1, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$rp.Cells[1, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$rp.Cells[1, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
$rp.Row(1).Height = 22
# Row 2 - gap (left blank)

# Row 3 - column headers
$rpHeaders = @('Server', 'Severity', 'Source', 'Object', 'Issue', 'Recommendation')
for ($i = 0; $i -lt $rpHeaders.Count; $i++) {
    [int]$col = $i + 1
    $hcell = $rp.Cells.Item(3, $col)
    $hcell.Value = $rpHeaders[$i]
    $hcell.Style.Font.Bold = $true
    $hcell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $hcell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($LightHex))
}

# Row 4+ - data
$rIdx = 4
foreach ($row in $rpRows) {
    $rp.Cells.Item($rIdx, 1).Value = $row.Server
    $rp.Cells.Item($rIdx, 2).Value = $row.Severity
    $rp.Cells.Item($rIdx, 3).Value = $row.Source
    $rp.Cells.Item($rIdx, 4).Value = $row.Object
    $rp.Cells.Item($rIdx, 5).Value = $row.Issue
    $rp.Cells.Item($rIdx, 6).Value = $row.Recommendation
    $rp.Cells.Item($rIdx, 6).Style.WrapText = $true

    # Severity color
    $sevCell = $rp.Cells.Item($rIdx, 2)
    if ("$($row.Severity)" -eq 'High') {
        for ($c = 1; $c -le 6; $c++) {
            $rp.Cells.Item($rIdx, $c).Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $rp.Cells.Item($rIdx, $c).Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FCE4E4'))
        }
        $sevCell.Style.Font.Bold = $true
        $sevCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($RedText))
    } elseif ("$($row.Severity)" -eq 'Medium') {
        for ($c = 1; $c -le 6; $c++) {
            $rp.Cells.Item($rIdx, $c).Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $rp.Cells.Item($rIdx, $c).Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFF2CC'))
        }
        $sevCell.Style.Font.Bold = $true
        $sevCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($AmberText))
    }
    $rIdx++
}

if ($rpRows.Count -eq 0) {
    $rp.Cells[4, 1].Value = '(no findings - estate is clean)'
    $rp.Cells[4, 1, 4, 6].Merge = $true
    $rp.Cells[4, 1].Style.Font.Italic = $true
}

# Column widths and filter
$rp.Column(1).Width = 12  # Server
$rp.Column(2).Width = 10  # Severity
$rp.Column(3).Width = 22  # Source
$rp.Column(4).Width = 35  # Object
$rp.Column(5).Width = 50  # Issue
$rp.Column(6).Width = 70  # Recommendation
$rp.Cells[3, 1, 3, 6].AutoFilter = $true
$rp.View.FreezePanes(4, 1)

# -----------------------------------------------------------------------------
# Per-server tabs
# -----------------------------------------------------------------------------
# One tab per server with all 17 sections. Each section gets:
#   - A navy banner with the section title (or grey banner if section is empty)
#   - A header row with the actual DataTable column names
#   - One row per data record
#   - A blank gap row before the next section
#
# Layout decisions worth knowing:
#
#   * Banner rows are 22pt tall (vs ~15pt default) for visual padding.
#   * Banner text starts at column A and merges across maxCols (computed in
#     a first pass over all sections - lets us merge consistently).
#   * Headers and data rows START AT COLUMN A. There is no leading "Section"
#     column. The SQL emits a Section tag column on most result sets (useful
#     for CMS multi-server queries), but we strip it here because the title
#     is already in the banner above.
#   * Severity-bearing rows get a row fill: pink for High, amber for Medium,
#     red text for High severity, amber for Medium. Cloud Migration Matrix
#     uses the same scheme: green Yes, red No.
#
# This sheet is built via direct EPPlus calls. Earlier attempts using
# Export-Excel kept introducing a phantom "Section" column header that
# couldn't be cleanly removed without dropping the whole pipeline.

foreach ($server in ($allData.Keys | Sort-Object)) {
    $sheetName = $server
    if ($sheetName.Length -gt 31) { $sheetName = $sheetName.Substring(0, 31) }

    $sd = $allData[$server]

    # First pass: figure out the widest section so we know how far to merge banners.
    $maxCols = 1
    foreach ($label in $SectionLabels) {
        $sec = $sd[$label]
        if ($sec -and $sec.Columns.Count -gt $maxCols) { $maxCols = $sec.Columns.Count }
    }
    if ($maxCols -lt 1) { $maxCols = 1 }

    # Add the worksheet directly (no Export-Excel round-trip - we write cells ourselves).
    $serverWs = $pkg.Workbook.Worksheets.Add($sheetName)

    $TallRowHeight  = 22   # banner rows - taller for visual padding
    $NormalRowHeight = 15  # default Excel row height-ish

    $r = 1

    # ---- Top banner: "Server: <name>  -  MI Migration Assessment" ----
    $serverWs.Cells[$r, 1].Value = "Server: $server  -  MI Migration Assessment"
    $serverWs.Cells[$r, 1, $r, $maxCols].Merge = $true
    $serverWs.Cells[$r, 1].Style.Font.Bold = $true
    $serverWs.Cells[$r, 1].Style.Font.Size = 12
    $serverWs.Cells[$r, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
    $serverWs.Cells[$r, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $serverWs.Cells[$r, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
    $serverWs.Cells[$r, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
    $serverWs.Row($r).Height = $TallRowHeight
    $r++

    # ---- Gap row between top banner and first section banner ----
    $serverWs.Row($r).Height = $NormalRowHeight
    $r++

    # ---- AI MIGRATION RECOMMENDATION section ----
    # Pulls the AI engine's outputs for this server and renders 4 cost cards,
    # the recommended target, and the AI-generated narrative. This block is
    # what makes each per-server tab actionable for the DBA owning the server.
    $aiRec    = $ServerRecommendations[$server]
    $dcCost   = $DcCosts[$server]
    $vmPayg   = $AzVmPaygCosts[$server]
    $vmByol   = $AzVmByolCosts[$server]
    $miCost   = $AzMiCosts[$server]
    $miSize   = $MiSizings[$server]

    # Section banner
    $serverWs.Cells[$r, 1].Value = 'Migration Recommendation (AI-Driven)'
    $serverWs.Cells[$r, 1, $r, $maxCols].Merge = $true
    $serverWs.Cells[$r, 1].Style.Font.Bold = $true
    $serverWs.Cells[$r, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
    $serverWs.Cells[$r, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $serverWs.Cells[$r, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
    $serverWs.Cells[$r, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
    $serverWs.Row($r).Height = $TallRowHeight
    $r++

    # Recommended target highlighted
    $serverWs.Cells[$r, 1].Value = "Recommended Target: $($aiRec.RecommendedTarget)"
    $serverWs.Cells[$r, 1, $r, $maxCols].Merge = $true
    $serverWs.Cells[$r, 1].Style.Font.Bold = $true
    $serverWs.Cells[$r, 1].Style.Font.Size = 12
    $serverWs.Cells[$r, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $serverWs.Cells[$r, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml('#E2F0D9'))
    $serverWs.Cells[$r, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($GreenText))
    $serverWs.Row($r).Height = 22
    $r++

    # AI narrative paragraph
    $serverWs.Cells[$r, 1].Value = $aiRec.Narrative
    $serverWs.Cells[$r, 1, $r, $maxCols].Merge = $true
    $serverWs.Cells[$r, 1].Style.WrapText = $true
    $serverWs.Cells[$r, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
    $serverWs.Cells[$r, 1].Style.Font.Size = 10
    # Estimate row height based on narrative length and number of merged columns.
    # Wider merged area means each visual line fits more characters, so fewer
    # lines needed. Roughly 12 chars per column-width-unit at font size 10.
    $charsPerLine = [math]::Max(80, $maxCols * 18)
    $narrLines = [math]::Max(2, [math]::Ceiling($aiRec.Narrative.Length / $charsPerLine))
    $serverWs.Row($r).Height = [math]::Min(80, $narrLines * 14)
    $r++

    # Gap
    $serverWs.Row($r).Height = $NormalRowHeight
    $r++

    # Cost cards row - header row first
    $costHeaders = @('1-Year Cost', 'DC-to-DC', 'Azure VM (PAYG)', 'Azure VM (BYOL)', "Azure SQL MI ($($miSize.Tier), $($miSize.VCore) vCore)")
    for ($i = 0; $i -lt $costHeaders.Count; $i++) {
        [int]$col = $i + 1
        $cell = $serverWs.Cells.Item($r, $col)
        $cell.Value = $costHeaders[$i]
        $cell.Style.Font.Bold = $true
        $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
        $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($LightHex))
        $cell.Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center
    }
    $r++

    # Cost cards row - values
    [int]$c1 = 1; [int]$c2 = 2; [int]$c3 = 3; [int]$c4 = 4; [int]$c5 = 5
    $serverWs.Cells.Item($r, $c1).Value = 'USD/year'
    $serverWs.Cells.Item($r, $c1).Style.Font.Bold = $true
    $serverWs.Cells.Item($r, $c2).Value = "`$$('{0:N0}' -f $dcCost.Total)"
    $serverWs.Cells.Item($r, $c3).Value = "`$$('{0:N0}' -f $vmPayg.Total)"
    $serverWs.Cells.Item($r, $c4).Value = "`$$('{0:N0}' -f $vmByol.Total)"
    $serverWs.Cells.Item($r, $c5).Value = "`$$('{0:N0}' -f $miCost.Total)"
    for ($i = 2; $i -le 5; $i++) {
        [int]$colInt = $i
        $serverWs.Cells.Item($r, $colInt).Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center
        $serverWs.Cells.Item($r, $colInt).Style.Font.Size = 12
        $serverWs.Cells.Item($r, $colInt).Style.Font.Bold = $true
    }

    # Highlight the recommended cost card in green
    $recTgt = $aiRec.RecommendedTarget
    $highlightCol = $null
    if     ($recTgt -match 'DC')   { $highlightCol = 2 }
    elseif ($recTgt -match 'PAYG') { $highlightCol = 3 }
    elseif ($recTgt -match 'BYOL') { $highlightCol = 4 }
    elseif ($recTgt -match 'MI')   { $highlightCol = 5 }
    elseif ($recTgt -match 'VM')   { $highlightCol = 4 }
    if ($highlightCol) {
        [int]$hcInt = $highlightCol
        $hcell = $serverWs.Cells.Item($r, $hcInt)
        $hcell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
        $hcell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml('#E2F0D9'))
        $hcell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($GreenText))
    }
    $serverWs.Row($r).Height = 22
    $r++

    # MI sizing rationale
    $serverWs.Cells[$r, 1].Value = "MI sizing rationale: $($miSize.Reason)"
    $serverWs.Cells[$r, 1, $r, $maxCols].Merge = $true
    $serverWs.Cells[$r, 1].Style.Font.Italic = $true
    $serverWs.Cells[$r, 1].Style.Font.Size = 9
    $serverWs.Cells[$r, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#595959'))
    $r++

    # Gap row before standard sections begin
    $serverWs.Row($r).Height = $NormalRowHeight
    $r++

    # ---- Section loop: write each section's banner + header + data + gap ----
    foreach ($label in $SectionLabels) {
        $sec = $sd[$label]
        $title = $SectionTitles[$label]

        if (-not $sec -or $sec.Rows.Count -eq 0) {
            # Empty section banner: grey fill, "(none)" suffix
            $serverWs.Cells[$r, 1].Value = "$title  -  (none)"
            $serverWs.Cells[$r, 1, $r, $maxCols].Merge = $true
            $serverWs.Cells[$r, 1].Style.Font.Bold = $true
            $serverWs.Cells[$r, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
            $serverWs.Cells[$r, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $serverWs.Cells[$r, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($GreyHex))
            $serverWs.Cells[$r, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
            $serverWs.Row($r).Height = $TallRowHeight
            $r++
            # Gap row after empty banner
            $serverWs.Row($r).Height = $NormalRowHeight
            $r++
            continue
        }

        # ---- Section banner: navy fill, taller row ----
        $serverWs.Cells[$r, 1].Value = $title
        $serverWs.Cells[$r, 1, $r, $maxCols].Merge = $true
        $serverWs.Cells[$r, 1].Style.Font.Bold = $true
        $serverWs.Cells[$r, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
        $serverWs.Cells[$r, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
        $serverWs.Cells[$r, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
        $serverWs.Cells[$r, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
        $serverWs.Row($r).Height = $TallRowHeight
        $r++

        # ---- Header row: actual DataTable column names, starting at column A ----
        # The SQL emits a leading 'Section' tag column on most result sets (useful
        # for CMS multi-server queries). For per-server tabs the section title is
        # already in the banner row above, so we drop the 'Section' column here.
        $colNames = @()
        foreach ($c in $sec.Columns) { $colNames += $c.ColumnName }
        if ($colNames.Count -gt 0 -and $colNames[0] -eq 'Section') {
            $colNames = $colNames[1..($colNames.Count - 1)]
        }
        for ($i = 0; $i -lt $colNames.Count; $i++) {
            # GOTCHA: EPPlus's Cells indexer is overloaded - Cells[row, col]
            # returns a single cell, but Cells[fromR, fromC, toR, toC] returns
            # a range. PowerShell's overload resolution sometimes can't pick
            # the right one when the column index is an expression. Two-step
            # workaround:
            #   1. Cast to [int] explicitly so PS knows the type.
            #   2. Use .Item(...) instead of [...] for unambiguous binding.
            # Without these, you get "The property 'Value' cannot be found
            # on this object" because Cells returned an ExcelRangeBase view
            # that doesn't expose a settable .Value.
            [int]$colIdx = $i + 1
            $cell = $serverWs.Cells.Item($r, $colIdx)
            $cell.Value = $colNames[$i]
            $cell.Style.Font.Bold = $true
            $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($LightHex))
        }
        $headerRow = $r
        $r++

        # ---- Data rows: actual values, starting at column A ----
        # Severity column index is recorded against the 'Section'-stripped layout,
        # so it's already aligned with $colNames.
        $sevCol = $SeverityColumnByLabel[$label]   # 1-based; null if section has no severity
        foreach ($row in $sec.Rows) {
            for ($i = 0; $i -lt $colNames.Count; $i++) {
                $val = $row[$colNames[$i]]
                if ($val -is [DBNull]) { $val = '' }
                [int]$colIdx = $i + 1
                $serverWs.Cells.Item($r, $colIdx).Value = "$val"
            }

            # Severity-based row coloring
            if ($sevCol) {
                [int]$sevColInt = $sevCol
                $sevCell = $serverWs.Cells.Item($r, $sevColInt)
                $sev = "$($sevCell.Value)"
                $rowFill = $null
                $sevTextColor = $null

                $sl = $sev.ToLower()
                if ($sl -match 'high' -or $sl -match 'unsafe') {
                    $rowFill = '#FCE4E4'
                    $sevTextColor = $RedText
                } elseif ($sl -match 'medium' -or $sl -match 'warn') {
                    $rowFill = '#FFF2CC'
                    $sevTextColor = $AmberText
                } elseif ($sl -eq 'no') {
                    $rowFill = '#FCE4E4'
                    $sevTextColor = $RedText
                } elseif ($sl -eq 'yes') {
                    $rowFill = '#E2F0D9'
                    $sevTextColor = $GreenText
                } elseif ($sl -match 'info' -or $sl -match 'ok') {
                    $sevTextColor = '#2E75B6'
                }

                if ($rowFill) {
                    for ($c = 1; $c -le $colNames.Count; $c++) {
                        [int]$cInt = $c
                        $cell = $serverWs.Cells.Item($r, $cInt)
                        $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
                        $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($rowFill))
                    }
                }
                if ($sevTextColor) {
                    $sevCell.Style.Font.Bold = $true
                    $sevCell.Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml($sevTextColor))
                }
            }
            $r++
        }

        # ---- Gap row after section data ----
        $serverWs.Row($r).Height = $NormalRowHeight
        $r++
    }

    # Auto-size all data columns. Skip merged banner rows by only sizing based on
    # cells in the data region.
    for ($c = 1; $c -le $maxCols; $c++) {
        $serverWs.Column($c).AutoFit()
    }

    # Freeze the top banner so it stays visible while scrolling
    $serverWs.View.FreezePanes(2, 1)
}


# =============================================================================
# METHODOLOGY & SOURCES tab
# =============================================================================
# A dedicated transparency tab. Architects reviewing this report can see
# exactly where every cost number came from, what assumptions were made,
# and which AI model produced the recommendations. This is what separates
# a "tool that calculates costs" from "a tool an architect would trust to
# make decisions with."

$method = $pkg.Workbook.Worksheets.Add('Methodology & Sources')

# Track current row as we build down
$mr = 1

# ---- Title banner ----
$method.Cells[$mr, 1].Value = 'Methodology & Sources'
$method.Cells[$mr, 1, $mr, 4].Merge = $true
$method.Cells[$mr, 1].Style.Font.Bold = $true
$method.Cells[$mr, 1].Style.Font.Size = 14
$method.Cells[$mr, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$method.Cells[$mr, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$method.Cells[$mr, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$method.Cells[$mr, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Center
$method.Row($mr).Height = 28
$mr += 2   # banner + gap

# ---- Section 1: Run metadata ----
$method.Cells[$mr, 1].Value = 'Report Run Metadata'
$method.Cells[$mr, 1, $mr, 4].Merge = $true
$method.Cells[$mr, 1].Style.Font.Bold = $true
$method.Cells[$mr, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$method.Cells[$mr, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$method.Cells[$mr, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$method.Row($mr).Height = 22
$mr++

$runMeta = @(
    ,@('Run Timestamp',          (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
    ,@('Servers Assessed',       "$($allData.Keys.Count)")
    ,@('Pricing Region',         $PricingRegion)
    ,@('Output File',            (Split-Path $OutputXlsx -Leaf))
    ,@('Agent Script Version',   '2026.05 - AI Cost-Aware Recommendation Engine')
)
foreach ($pair in $runMeta) {
    $method.Cells[$mr, 1].Value = $pair[0]
    $method.Cells[$mr, 1].Style.Font.Bold = $true
    $method.Cells[$mr, 2].Value = $pair[1]
    $method.Cells[$mr, 2, $mr, 4].Merge = $true
    $mr++
}
$mr++

# ---- Section 2: AI Agent Configuration ----
$method.Cells[$mr, 1].Value = 'AI Agent Configuration'
$method.Cells[$mr, 1, $mr, 4].Merge = $true
$method.Cells[$mr, 1].Style.Font.Bold = $true
$method.Cells[$mr, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$method.Cells[$mr, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$method.Cells[$mr, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$method.Row($mr).Height = 22
$mr++

# Estimate AI calls and approximate cost
$aiCallsPerServer = 2   # MI sizing + recommendation
$aiEstateCalls    = 1   # estate-wide synthesis
$totalAiCalls     = ($allData.Keys.Count * $aiCallsPerServer) + $aiEstateCalls
$estimatedAiCost  = [math]::Round($totalAiCalls * 0.04, 2)   # rough avg per Claude Sonnet call

$llmDescription = if ($LlmReady) {
    if ($LlmProvider -eq 'Claude') {
        "Anthropic Claude API ($ClaudeModel)"
    } elseif ($LlmProvider -eq 'AzureOpenAi') {
        "Azure OpenAI ($AzOpenAiDeployment)"
    } else { "Unknown" }
} else { "AI not configured - default recommendations used" }

# Resolve provider endpoint to a variable - PowerShell cannot inline `if` expressions
# inside array literals.
$providerEndpoint = if ($LlmProvider -eq 'Claude') {
    $ClaudeApiUrl
} elseif ($LlmProvider -eq 'AzureOpenAi') {
    $AzOpenAiEndpoint
} else {
    'N/A'
}

$aiMeta = @(
    ,@('LLM Provider',           $llmDescription)
    ,@('Provider Endpoint',      $providerEndpoint)
    ,@('AI Calls This Run',      "~$totalAiCalls (per-server: $aiCallsPerServer x $($allData.Keys.Count) servers + $aiEstateCalls estate-wide)")
    ,@('Estimated AI Cost',      "~`$$estimatedAiCost USD (paid by report runner's account)")
    ,@('AI Used For',            'MI SKU sizing recommendation, per-server target recommendation + narrative, estate-wide migration strategy synthesis')
    ,@('AI NOT Used For',        'Cost calculations (deterministic from Azure pricing data), assessment SQL queries (read-only T-SQL), severity scoring (rule-based)')
)
foreach ($pair in $aiMeta) {
    $method.Cells[$mr, 1].Value = $pair[0]
    $method.Cells[$mr, 1].Style.Font.Bold = $true
    $method.Cells[$mr, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
    $method.Cells[$mr, 2].Value = $pair[1]
    $method.Cells[$mr, 2, $mr, 4].Merge = $true
    $method.Cells[$mr, 2].Style.WrapText = $true
    $method.Cells[$mr, 2].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
    $method.Row($mr).Height = 30
    $mr++
}
$mr++

# ---- Section 3: Cloud Pricing Sources ----
$method.Cells[$mr, 1].Value = 'Cloud Pricing Sources (Azure VM, Azure SQL MI)'
$method.Cells[$mr, 1, $mr, 4].Merge = $true
$method.Cells[$mr, 1].Style.Font.Bold = $true
$method.Cells[$mr, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$method.Cells[$mr, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$method.Cells[$mr, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$method.Row($mr).Height = 22
$mr++

$cloudMeta = @(
    ,@('Source',                 'Azure Retail Prices API')
    ,@('Endpoint',               $AzureRetailApi)
    ,@('Authentication',         'None required (public API)')
    ,@('Pricing Type',           'Pay-as-you-go (Consumption) list price - no negotiated discounts, no Reserved Instance, no Enterprise Agreement')
    ,@('Region',                 $PricingRegion)
    ,@('Pricing Fetched At',     $(if ($script:PricingFetchedAt) { $script:PricingFetchedAt.ToString('yyyy-MM-dd HH:mm:ss zzz') } else { 'Live API not reached - fallback rates used' }))
    ,@('Validation',             'Cross-validated against Azure Pricing Calculator at azure.microsoft.com/pricing/calculator')
    ,@('VM SKU sizing',          'Synced to AI-recommended MI vCore count for apples-to-apples comparison')
    ,@('Storage rate (VM)',      'Premium SSD: ~$0.135/GB-month')
    ,@('Storage rate (MI)',      '$0.1006/GB-month (calculator-validated)')
    ,@('Egress allowance',       '~$50/month per server (typical migration)')
    ,@('Caching',                'Per-run only - prices fetched fresh each report')
)
foreach ($pair in $cloudMeta) {
    $method.Cells[$mr, 1].Value = $pair[0]
    $method.Cells[$mr, 1].Style.Font.Bold = $true
    $method.Cells[$mr, 2].Value = $pair[1]
    $method.Cells[$mr, 2, $mr, 4].Merge = $true
    $method.Cells[$mr, 2].Style.WrapText = $true
    $method.Row($mr).Height = 18
    $mr++
}
$mr++

# ---- Section 4: SQL License (PAYG) Rates ----
$method.Cells[$mr, 1].Value = 'SQL Server License (PAYG add-on) - per core per hour'
$method.Cells[$mr, 1, $mr, 4].Merge = $true
$method.Cells[$mr, 1].Style.Font.Bold = $true
$method.Cells[$mr, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$method.Cells[$mr, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$method.Cells[$mr, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$method.Row($mr).Height = 22
$mr++

# Header row for license rate table
$method.Cells[$mr, 1].Value = 'Edition'
$method.Cells[$mr, 2].Value = 'Per Core/Hour'
$method.Cells[$mr, 3].Value = 'Per Core/Year'
$method.Cells[$mr, 4].Value = 'Notes'
for ($c = 1; $c -le 4; $c++) {
    [int]$cInt = $c
    $cell = $method.Cells.Item($mr, $cInt)
    $cell.Style.Font.Bold = $true
    $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($LightHex))
}
$mr++

$licenseRates = @(
    ,@('Developer',  '$0.000',  '$0',     'Free (non-production use). SQL 2025 also markets as "Enterprise Developer Edition" - same free licensing.')
    ,@('Web',        '$0.020',  '~$175',  'Hosted web environments only')
    ,@('Standard',   '$0.115',  '~$1,008','Per Microsoft list pricing')
    ,@('Enterprise', '$0.460',  '~$4,030','Per Microsoft list pricing')
)
foreach ($row in $licenseRates) {
    $method.Cells[$mr, 1].Value = $row[0]
    $method.Cells[$mr, 1].Style.Font.Bold = $true
    $method.Cells[$mr, 2].Value = $row[1]
    $method.Cells[$mr, 3].Value = $row[2]
    $method.Cells[$mr, 4].Value = $row[3]
    $method.Cells[$mr, 4].Style.WrapText = $true
    $method.Row($mr).Height = 22
    $mr++
}
$mr++

# ---- Section 5: On-Prem (DC-to-DC) Reference Rates ----
$method.Cells[$mr, 1].Value = 'On-Prem (DC-to-DC) Reference Rates - per server per year'
$method.Cells[$mr, 1, $mr, 4].Merge = $true
$method.Cells[$mr, 1].Style.Font.Bold = $true
$method.Cells[$mr, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$method.Cells[$mr, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$method.Cells[$mr, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$method.Row($mr).Height = 22
$mr++

# Header row for DC components table
$method.Cells[$mr, 1].Value = 'Component'
$method.Cells[$mr, 2].Value = 'Rate'
$method.Cells[$mr, 3].Value = 'Notes'
for ($c = 1; $c -le 3; $c++) {
    [int]$cInt = $c
    $cell = $method.Cells.Item($mr, $cInt)
    $cell.Style.Font.Bold = $true
    $cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($LightHex))
}
$mr++

$dcRates = @(
    ,@('Hardware refresh', "`$$($ReferenceRates.HardwareRefreshUSD)/$($ReferenceRates.HardwareLifeYears)yr",
      "Server hardware amortized over $($ReferenceRates.HardwareLifeYears)-year life. Industry estimate.")
    ,@('Colocation + power', "`$$($ReferenceRates.ColocationPerYear)/yr",
      'Rack space, power, cooling. Typical mid-market data center rates.')
    ,@('Operational labor', "`$$($ReferenceRates.OperationalLaborYearly)/yr",
      'Allocated DBA labor per server (patching, backups, monitoring). Varies wildly in real orgs.')
    ,@('Storage (SAN)', "`$$($ReferenceRates.StoragePerGBMonth)/GB-month",
      'SAN allocation per database GB.')
    ,@('SQL Standard license', "`$$($ReferenceRates.SqlStdLicensePer2Cores)/2-core pack",
      'Microsoft list price. Edition detected from server, applied to active core count.')
    ,@('SQL Enterprise license', "`$$($ReferenceRates.SqlEntLicensePer2Cores)/2-core pack",
      'Microsoft list price.')
)
foreach ($row in $dcRates) {
    $method.Cells[$mr, 1].Value = $row[0]
    $method.Cells[$mr, 1].Style.Font.Bold = $true
    $method.Cells[$mr, 2].Value = $row[1]
    $method.Cells[$mr, 3].Value = $row[2]
    $method.Cells[$mr, 3, $mr, 4].Merge = $true
    $method.Cells[$mr, 3].Style.WrapText = $true
    $method.Row($mr).Height = 22
    $mr++
}
$mr++

# ---- Section 6: Caveats & Limitations ----
$method.Cells[$mr, 1].Value = 'Caveats & Limitations'
$method.Cells[$mr, 1, $mr, 4].Merge = $true
$method.Cells[$mr, 1].Style.Font.Bold = $true
$method.Cells[$mr, 1].Style.Font.Color.SetColor([System.Drawing.ColorTranslator]::FromHtml('#FFFFFF'))
$method.Cells[$mr, 1].Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
$method.Cells[$mr, 1].Style.Fill.BackgroundColor.SetColor([System.Drawing.ColorTranslator]::FromHtml($NavyHex))
$method.Row($mr).Height = 22
$mr++

$caveats = @(
    'Costs are estimates based on Azure list (PAYG) pricing - actual customer cost may be lower with Reserved Instances, Azure Hybrid Benefit on existing licenses, Enterprise Agreement discounts, or Dev/Test pricing.',
    'On-prem reference rates are industry estimates - actual customer cost varies significantly based on hardware vendor, datacenter contract, and existing operational scale.',
    'AI-generated recommendations are reasoning over assessment data and cost numbers - they are not legal/contractual advice. Final migration target choice should be validated with the customer''s architecture review process.',
    'AI narratives are non-deterministic - re-running may produce different wording for the same recommendation. Recommendations themselves should be consistent if inputs are unchanged.',
    'Migration project costs (data transfer, licensing transition, application changes, testing) are NOT included in these estimates - this is steady-state operational cost only.',
    'For production decisions, prices should be re-validated within 90 days as Azure pricing changes monthly.'
)
foreach ($caveat in $caveats) {
    $method.Cells[$mr, 1].Value = "* $caveat"
    $method.Cells[$mr, 1, $mr, 4].Merge = $true
    $method.Cells[$mr, 1].Style.WrapText = $true
    $method.Cells[$mr, 1].Style.VerticalAlignment = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
    $method.Cells[$mr, 1].Style.Font.Italic = $true
    $caveatLines = [math]::Ceiling($caveat.Length / 110)
    $method.Row($mr).Height = [math]::Max(20, $caveatLines * 16)
    $mr++
}

# Column widths for the methodology tab
$method.Column(1).Width = 25
$method.Column(2).Width = 22
$method.Column(3).Width = 25
$method.Column(4).Width = 60


# -----------------------------------------------------------------------------
# Reorder tabs: Executive Summary | Summary | Critical Findings | Remediation Plan | <per-server>
# -----------------------------------------------------------------------------
# We built the sheets in a different order than they should appear. Reorder
# now using EPPlus's MoveToStart - which moves a sheet to position 0.
#
# Calling MoveToStart in REVERSE of the desired order leaves the workbook
# in the right sequence: each move pushes the previous one to position 1,
# then 2, etc. So the LAST call wins for "leftmost".
#
# Per-server tabs aren't moved - they stay in their build order (alphabetical
# by server name) at the right end of the workbook.
# Methodology & Sources goes near the right end, just before per-server tabs.
$pkg.Workbook.Worksheets.MoveToStart('Methodology & Sources')
$pkg.Workbook.Worksheets.MoveToStart('Remediation Plan')
$pkg.Workbook.Worksheets.MoveToStart('Critical Findings')
$pkg.Workbook.Worksheets.MoveToStart('Summary')
$pkg.Workbook.Worksheets.MoveToStart('Executive Summary')

# -----------------------------------------------------------------------------
# Save and finish
# -----------------------------------------------------------------------------
# Close-ExcelPackage writes the .xlsx to disk and releases the file handle.
# After that we print the path in yellow (so it's easy to spot in the
# scrollback), the server count, and a "next step" pointer.
#
# The final Read-Host blocks the window from closing - if the script ran via
# right-click "Run with PowerShell", PowerShell auto-closes the window when
# the script exits, which would hide any error messages. Read-Host keeps the
# window open until the user presses Enter.

# -----------------------------------------------------------------------------
# JSON export (added for SQLPilot Phase 2 consumption)
# -----------------------------------------------------------------------------
# Write a parallel .json file with the same data the Excel contains, so the
# SQLPilot agent can read structured findings without parsing Excel cells.
# Same filename as the Excel, just .json instead of .xlsx.
#
# Wrapped in try/catch so a JSON serialization failure (rare, but possible
# on edge-case row data) doesn't block the Excel save below. The Excel is
# the primary deliverable; the JSON is supplementary.
$OutputJson = [System.IO.Path]::ChangeExtension($OutputXlsx, '.json')
$jsonOk     = $false
try {
    $jsonStructure = Convert-AllDataToJsonStructure -AllData $allData -SourceXlsxPath $OutputXlsx

    # ConvertTo-Json with -Depth high enough to traverse server -> section -> row -> column.
    # Servers (1) -> sections (2) -> rows (3) -> column hashtable (4) -> values (5).
    # We use 8 to leave headroom for any nested values future sections might emit.
    $jsonStructure | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputJson -Encoding UTF8
    $jsonOk = $true
} catch {
    Write-Host ''
    Write-Host '[WARN] JSON export failed; Excel will still be written.' -ForegroundColor Yellow
    Write-Host "       Error: $($_.Exception.Message)" -ForegroundColor Yellow
}

Close-ExcelPackage $pkg

Write-Host ''
Write-Host '===============================================================================' -ForegroundColor Green
Write-Host '  DONE' -ForegroundColor Green
Write-Host '===============================================================================' -ForegroundColor Green
Write-Host ''
Write-Host '  Excel report:'
Write-Host "    $(Resolve-Path $OutputXlsx)" -ForegroundColor Yellow
if ($jsonOk) {
    Write-Host ''
    Write-Host '  JSON report (for SQLPilot agent):'
    Write-Host "    $(Resolve-Path $OutputJson)" -ForegroundColor Yellow
}
Write-Host ''
Write-Host "  Servers assessed: $($allData.Count)"
Write-Host ''
Write-Host '  NEXT STEP:'
Write-Host '    Open the .xlsx file. Review the Summary and Critical Findings tabs.'
Write-Host '    Email the .xlsx to the consultant if they need a copy.'
Write-Host ''
Read-Host 'Press Enter to close'
 
