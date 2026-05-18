<#
.SYNOPSIS
    Parses an SSMS Results-to-Text (.rpt) export of the Phase 1 assessment
    SQL into the same in-memory data shape that Invoke-Sqlcmd -OutputAs
    DataTables produces.

.DESCRIPTION
    The Phase 1 assessment script (01_Assessment_Script.sql) emits 17 result
    sets. Two ways those result sets reach a consumer:

      1. Live via Invoke-Sqlcmd inside Generate_Assessment_Report.ps1, which
         hands back DataTables in memory.

      2. The client runs the same SQL in SSMS GUI ("Results to Text",
         multi-server merge), saves the output as a .rpt file, and sends it
         back. That .rpt file is the textual rendering of the same 17 result
         sets — same columns, same rows, just formatted as fixed-width text
         with the SSMS-injected "Server Name" prefix column.

    This parser handles path (2). It reads the .rpt and returns a hashtable
    in the exact shape Generate_Assessment_Report.ps1's $allData uses, so
    the wrapper's downstream pipeline (cost calc, AI sections, Cloud Migration
    Matrix, Excel build, JSON export) runs unchanged.

    The returned shape:
        $allData[$ServerName] = @{
            '01_Instance_Summary'        = [System.Data.DataTable]
            '02_Instance_Configuration'  = [System.Data.DataTable]
            ...
            '15_Cloud_Migration_Matrix'  = [System.Data.DataTable]
        }

    Empty result sets are represented as empty DataTables with the correct
    column schema, matching what Invoke-Sqlcmd would have returned for an
    empty section.

.PARAMETER InputPath
    Path to the .rpt file.

.OUTPUTS
    Hashtable indexed by ServerName, matching $allData from
    Generate_Assessment_Report.ps1.

.NOTES
    Author: Claude (for SQLPilot Phase 2)
    Algorithm validated against the canonical Phase 1 JSON output —
    parses produce identical row counts per server per section.
#>

[CmdletBinding()]
param(
    # When this script is dot-sourced (e.g. from Generate_Assessment_Report.ps1),
    # this parameter is not used and no prompt should fire. Hence it is NOT
    # marked Mandatory. The standalone-run code at the bottom of the file
    # validates presence and emits a friendly error if it is missing.
    [string] $InputPath = ''
)


# Mapping: tuple of expected data-column-headers → JSON section key.
# Used to identify result sets, especially empty ones where no data row
# reveals the Section value.
#
# Headers must match what 01_Assessment_Script.sql actually emits. If the
# wrapper version changes column names, update this map.
$script:SectionByHeaders = @(
    @{ Hdrs = @('ServerName','MachineName','InstanceName','Edition','ProductVersion',
                'ProductLevel','CULevel','ServerCollation','IsClustered','HadrEnabled',
                'AuthMode','UserDatabaseCount','LinkedServerCount','EnabledAgentJobs',
                'AssessedAt');                                                          Key = '01_Instance_Summary' },
    @{ Hdrs = @('ConfigName','ValueInUse','Description','MIRelevance');                 Key = '02_Instance_Configuration' },
    @{ Hdrs = @('LinkedServerName','Product','Provider','DataSource','RemoteLoginEnabled',
                'RpcOutEnabled','DataAccessEnabled','MICompatibility');                 Key = '03_Linked_Servers' },
    @{ Hdrs = @('JobName','Status','TotalSteps','RiskySteps','Subsystems','MIRelevance');Key = '04_SQL_Agent_Jobs' },
    @{ Hdrs = @('DatabaseId','DatabaseName','State','RecoveryModel','CompatLevel',
                'DBFormat','FormatNotes','OwnerLogin','CreatedAt','IsReadOnly',
                'IsTDEEncrypted','IsPublished','IsSubscribed','IsCDCEnabled','SizeMB'); Key = '05_Database_Inventory' },
    @{ Hdrs = @('DatabaseName','Category','Severity','Finding');                        Key = '06_DB_Level_Findings' },
    @{ Hdrs = @('DatabaseName','SchemaName','ObjectName','ObjectType','RiskPattern',
                'Severity');                                                            Key = '07_TSQL_Code_Scan' },
    @{ Hdrs = @('DatabaseName','FeatureName','Severity','Note');                        Key = '08_SKU_Features' },
    @{ Hdrs = @('DatabaseName','AssemblyName','PermissionSet','IsUserDefined','Verdict');Key = '09_CLR_Assemblies' },
    @{ Hdrs = @('DatabaseName','LogicalName','FileType','PhysicalPath','SizeMB',
                'MIVerdict');                                                           Key = '10_Database_Files' },
    @{ Hdrs = @('AGName','IsDistributedAG','ReplicaServer','AvailabilityMode',
                'FailoverMode','Role','SyncHealth','ConnectedState','OperationalState');Key = '11_Availability_Groups' },
    @{ Hdrs = @('DatabaseName','State','Role','SafetyLevel','PartnerName','WitnessName');Key = '12_Database_Mirroring' },
    @{ Hdrs = @('PrimaryDatabase','PrimaryId','BackupDirectory','BackupShare');         Key = '13_Log_Shipping_Primary' },
    @{ Hdrs = @('SecondaryDatabase','SecondaryId','RestoreDelayMin','RestoreMode',
                'DisconnectUsers');                                                     Key = '13_Log_Shipping_Secondary' },
    @{ Hdrs = @('PublisherDB','PublisherId');                                           Key = '14_Replication_Subscribers' },
    @{ Hdrs = @('PublisherDB','PublicationName','PublicationType');                     Key = '14_Replication_Publishers' },
    @{ Hdrs = @('TargetPlatform','Fit','Reason');                                       Key = '15_Cloud_Migration_Matrix' }
)

$script:SectionOrder = @(
    '01_Instance_Summary','02_Instance_Configuration','03_Linked_Servers',
    '04_SQL_Agent_Jobs','05_Database_Inventory','06_DB_Level_Findings',
    '07_TSQL_Code_Scan','08_SKU_Features','09_CLR_Assemblies',
    '10_Database_Files','11_Availability_Groups','12_Database_Mirroring',
    '13_Log_Shipping_Primary','13_Log_Shipping_Secondary',
    '14_Replication_Subscribers','14_Replication_Publishers',
    '15_Cloud_Migration_Matrix'
)

$script:ValidSections = @{}
foreach ($s in $script:SectionOrder) { $script:ValidSections[$s] = $true }


function Test-IsDashesLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    $s = $Line.Trim()
    foreach ($c in $s.ToCharArray()) {
        if ($c -ne '-' -and $c -ne ' ') { return $false }
    }
    # Must contain a meaningful number of dashes
    return ($s -replace '[^-]', '').Length -gt 40
}

function Get-ColumnSpansFromDashes {
    param([string]$DashesLine)
    $spans = New-Object 'System.Collections.Generic.List[object]'
    $i = 0
    $n = $DashesLine.Length
    while ($i -lt $n) {
        if ($DashesLine[$i] -eq '-') {
            $start = $i
            while ($i -lt $n -and $DashesLine[$i] -eq '-') { $i++ }
            $spans.Add(@{ Start = $start; End = $i }) | Out-Null
        } else {
            $i++
        }
    }
    return $spans
}

function Get-RowSlice {
    param([string]$Line, [object]$Spans)
    $result = @()
    foreach ($span in $Spans) {
        $start = $span.Start
        $end   = $span.End
        if ($start -ge $Line.Length) {
            $result += ''
        } elseif ($end -le $Line.Length) {
            $result += $Line.Substring($start, $end - $start).Trim()
        } else {
            $result += $Line.Substring($start).Trim()
        }
    }
    return ,$result
}

function Get-SectionForHeaders {
    param([object[]]$DataHeaders)
    foreach ($mapping in $script:SectionByHeaders) {
        $hdrs = $mapping.Hdrs
        if ($DataHeaders.Count -lt $hdrs.Count) { continue }
        $match = $true
        for ($i = 0; $i -lt $hdrs.Count; $i++) {
            if ($DataHeaders[$i] -ne $hdrs[$i]) { $match = $false; break }
        }
        if ($match) { return $mapping.Key }
    }
    return $null
}

function New-EmptyDataTable {
    param([string[]]$ColumnNames)
    $dt = New-Object System.Data.DataTable
    foreach ($col in $ColumnNames) {
        if ($col) { [void]$dt.Columns.Add($col, [string]) }
    }
    return $dt
}


function Convert-RptToAllData {
    <#
    .SYNOPSIS
        Parses an SSMS .rpt file and returns $allData hashtable matching what
        Generate_Assessment_Report.ps1's live-SQL path produces.
    .OUTPUTS
        Hashtable: [string $ServerName] -> [hashtable] of section -> DataTable
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string] $RptPath
    )

    if (-not (Test-Path -LiteralPath $RptPath)) {
        throw "RPT file not found: $RptPath"
    }

    # Resolve to a full filesystem path. PowerShell's "current location" and
    # .NET's process working directory are separate concepts — relative paths
    # like '.\test.rpt' work in PowerShell but break .NET I/O calls. Convert
    # to a full path so [System.IO.File] always finds the file.
    $RptPath = (Resolve-Path -LiteralPath $RptPath).ProviderPath

    # Read the file, stripping the UTF-8 BOM if present.
    $raw = [System.IO.File]::ReadAllText($RptPath, [System.Text.Encoding]::UTF8)
    if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) {
        $raw = $raw.Substring(1)
    }
    $lines = $raw -split "`r`n|`r|`n"

    # Find dashes-line indices — each one marks a result-set boundary.
    $blockIndices = New-Object 'System.Collections.Generic.List[int]'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (Test-IsDashesLine -Line $lines[$i]) {
            $blockIndices.Add($i) | Out-Null
        }
    }

    # Build per-block (header, dashes, data_start, data_end)
    $blocks = New-Object 'System.Collections.Generic.List[object]'
    for ($k = 0; $k -lt $blockIndices.Count; $k++) {
        $dashesIdx = $blockIndices[$k]
        $headerIdx = $dashesIdx - 1
        $dataStart = $dashesIdx + 1
        if ($k + 1 -lt $blockIndices.Count) {
            $dataEnd = $blockIndices[$k + 1] - 1
            while ($dataEnd -gt $dataStart -and [string]::IsNullOrWhiteSpace($lines[$dataEnd - 1])) {
                $dataEnd--
            }
        } else {
            $dataEnd = $lines.Count
            while ($dataEnd -gt $dataStart -and [string]::IsNullOrWhiteSpace($lines[$dataEnd - 1])) {
                $dataEnd--
            }
        }
        $blocks.Add(@{
            HeaderIdx = $headerIdx
            DashesIdx = $dashesIdx
            DataStart = $dataStart
            DataEnd   = $dataEnd
        }) | Out-Null
    }

    # Output structure — server name -> hashtable of section -> rows-list (we'll
    # convert rows-list to DataTable at the end).
    $serversRaw = [ordered]@{}

    # When the .rpt is single-server format (no 'Server Name' prefix column),
    # only sections whose own data columns contain 'ServerName' (i.e. section
    # 01_Instance_Summary) reveal which server this file belongs to. We latch
    # onto that the moment we see it and reuse it for every other section in
    # the file — otherwise sections like 02_Instance_Configuration (which have
    # no ServerName column) would orphan into an 'UNKNOWN' bucket.
    $singleServerName = $null

    foreach ($block in $blocks) {
        $headerLine = $lines[$block.HeaderIdx]
        $dashesLine = $lines[$block.DashesIdx]
        $spans      = Get-ColumnSpansFromDashes -DashesLine $dashesLine
        if ($spans.Count -eq 0) { continue }

        $headerCols = Get-RowSlice -Line $headerLine -Spans $spans
        $isMulti    = ($headerCols[0] -eq 'Server Name')
        $firstDataCol = if ($isMulti) { 2 } else { 1 }

        # Data column headers (skip the SSMS-prefix and Section columns)
        $dataHeaders = @()
        for ($i = $firstDataCol; $i -lt $headerCols.Count; $i++) {
            $h = $headerCols[$i].Trim()
            if ($h) { $dataHeaders += $h }
        }

        $sectionKey = Get-SectionForHeaders -DataHeaders $dataHeaders
        if (-not $sectionKey) {
            Write-Warning ("Unable to identify section at line {0}; data headers were: {1}" -f
                ($block.HeaderIdx + 1), ($dataHeaders -join ','))
            continue
        }

        for ($r = $block.DataStart; $r -lt $block.DataEnd; $r++) {
            $line = $lines[$r]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $row = Get-RowSlice -Line $line -Spans $spans
            if ($row.Count -eq 0) { continue }

            # Stop reading rows for this block if we hit something that's not
            # a valid data row — typically the SSMS trailing completion banner.
            if ($isMulti) {
                if ($row.Count -lt 2) { break }
                $sectionInRow = $row[1].Trim()
                if (-not $script:ValidSections.ContainsKey($sectionInRow)) { break }
            } else {
                if ($row.Count -lt 1) { break }
                $sectionInRow = $row[0].Trim()
                if (-not $script:ValidSections.ContainsKey($sectionInRow)) { break }
            }

            # Build the row as an ordered hashtable.
            $rowObj = [ordered]@{ Section = $sectionKey }
            for ($i = 0; $i -lt $dataHeaders.Count; $i++) {
                $cellIdx = $firstDataCol + $i
                if ($cellIdx -lt $row.Count) {
                    $val = $row[$cellIdx]
                    if ($val -eq 'NULL' -or $val -eq '') { $val = $null }
                    $rowObj[$dataHeaders[$i]] = $val
                } else {
                    $rowObj[$dataHeaders[$i]] = $null
                }
            }

            # Determine canonical server name. Priority:
            #   1. The row's own ServerName column (section 01_Instance_Summary
            #      is the authoritative source).
            #   2. In multi-server mode, the SSMS 'Server Name' prefix column.
            #   3. In single-server mode, the latched server name we captured
            #      from a previous section in this same file.
            $preferred = $null
            if ($rowObj.Contains('ServerName') -and $rowObj['ServerName']) {
                $preferred = "$($rowObj['ServerName'])"
                # Latch single-server name once we know it.
                if (-not $isMulti -and -not $singleServerName) {
                    $singleServerName = $preferred
                }
            } elseif ($isMulti -and $row[0]) {
                $preferred = "$($row[0])"
            } elseif (-not $isMulti -and $singleServerName) {
                $preferred = $singleServerName
            }
            if (-not $preferred) { $preferred = 'UNKNOWN' }

            if (-not $serversRaw.Contains($preferred)) {
                $entry = [ordered]@{}
                foreach ($s in $script:SectionOrder) { $entry[$s] = @() }
                # Also remember the data-column-headers for each section we see,
                # so we can build an empty DataTable with the right schema later.
                $entry['__headers__'] = @{}
                $serversRaw[$preferred] = $entry
            }
            $serversRaw[$preferred][$sectionKey] += ,$rowObj
            $serversRaw[$preferred]['__headers__'][$sectionKey] = $dataHeaders
        }

        # Even for empty result sets, remember the headers so we can build an
        # empty DataTable with the right schema for sections that produced no
        # rows for any server.
        if ($serversRaw.Count -eq 0) {
            # File has only empty sections so far; nothing to record yet.
        }
    }

    # Defensive cleanup: if single-server mode ran but section 01 appeared
    # AFTER some other section (so we didn't have $singleServerName yet when
    # those earlier rows came through), those rows landed in 'UNKNOWN'. Fold
    # them into the real server name now that we know it.
    if ($singleServerName -and $serversRaw.Contains('UNKNOWN')) {
        if (-not $serversRaw.Contains($singleServerName)) {
            # Real server entry doesn't exist yet — just rename UNKNOWN.
            $serversRaw[$singleServerName] = $serversRaw['UNKNOWN']
        } else {
            # Both exist — merge UNKNOWN's rows into the real server.
            $u = $serversRaw['UNKNOWN']
            $real = $serversRaw[$singleServerName]
            foreach ($s in $script:SectionOrder) {
                if ($u.Contains($s)) {
                    foreach ($row in $u[$s]) {
                        $real[$s] += ,$row
                    }
                }
            }
            foreach ($k in $u['__headers__'].Keys) {
                $real['__headers__'][$k] = $u['__headers__'][$k]
            }
        }
        $serversRaw.Remove('UNKNOWN')
    }

    # Merge case-variant server names (e.g. 'Node1' from Server Name column vs
    # 'NODE1' from the data's ServerName column). Prefer the variant that has
    # data in section 01_Instance_Summary (the authoritative source).
    $byUpper = @{}
    foreach ($name in $serversRaw.Keys) {
        $u = $name.ToUpperInvariant()
        if (-not $byUpper.ContainsKey($u)) { $byUpper[$u] = @() }
        $byUpper[$u] += $name
    }

    # Merge case-variant server names AND normalize to a single canonical
    # casing across all servers. The .rpt's data has inconsistent casing
    # (some hosts set up as 'NODE1', others as 'Node3') — we uppercase every
    # canonical key here so downstream artifacts (xlsx tab names, JSON keys,
    # UI tables) all show the same shape.
    $serversMerged = [ordered]@{}
    foreach ($u in $byUpper.Keys) {
        $variants    = $byUpper[$u]
        $canonical   = $u    # always uppercase, regardless of original casing
        $merged      = [ordered]@{}
        foreach ($s in $script:SectionOrder) { $merged[$s] = @() }
        $merged['__headers__'] = @{}
        foreach ($v in $variants) {
            foreach ($s in $script:SectionOrder) {
                foreach ($row in $serversRaw[$v][$s]) {
                    # Also rewrite the ServerName field inside row data so
                    # downstream readers (e.g. Decide stage display) see the
                    # canonical name even when they pull it from inside the row.
                    if ($row -is [hashtable] -and $row.Contains('ServerName') -and $row['ServerName']) {
                        $row['ServerName'] = $canonical
                    }
                    $merged[$s] += ,$row
                }
            }
            foreach ($k in $serversRaw[$v]['__headers__'].Keys) {
                $merged['__headers__'][$k] = $serversRaw[$v]['__headers__'][$k]
            }
        }
        $serversMerged[$canonical] = $merged
    }

    # Build the final $allData: per-server hashtable of DataTables.
    # For sections that had no rows, we still need a DataTable (with proper
    # column schema) so the downstream wrapper code (which iterates dt.Rows)
    # doesn't blow up.
    #
    # Schema source order:
    #   1. Any header set we recorded for this section (from a server that had rows)
    #   2. The canonical SectionByHeaders entry's expected headers
    $allData = @{}

    # Collect all known headers per section across all servers
    $globalHeaders = @{}
    foreach ($sname in $serversMerged.Keys) {
        $sdata = $serversMerged[$sname]
        foreach ($k in $sdata['__headers__'].Keys) {
            if (-not $globalHeaders.ContainsKey($k)) {
                $globalHeaders[$k] = $sdata['__headers__'][$k]
            }
        }
    }

    foreach ($sname in $serversMerged.Keys) {
        $sdata = $serversMerged[$sname]
        $serverOut = @{}
        foreach ($sectionKey in $script:SectionOrder) {
            # Determine column schema for this section
            $hdrs = $null
            if ($globalHeaders.ContainsKey($sectionKey)) {
                $hdrs = $globalHeaders[$sectionKey]
            } else {
                # Fall back to canonical schema
                foreach ($mapping in $script:SectionByHeaders) {
                    if ($mapping.Key -eq $sectionKey) {
                        $hdrs = $mapping.Hdrs
                        break
                    }
                }
            }
            if (-not $hdrs) { $hdrs = @() }

            # Build DataTable with all expected columns (plus 'Section' since
            # the wrapper's JSON converter expects every row to carry Section).
            $dt = New-Object System.Data.DataTable
            [void]$dt.Columns.Add('Section', [string])
            foreach ($col in $hdrs) {
                if (-not $dt.Columns.Contains($col)) {
                    [void]$dt.Columns.Add($col, [string])
                }
            }
            # Add rows
            $rows = $sdata[$sectionKey]
            foreach ($rowObj in $rows) {
                $newRow = $dt.NewRow()
                $newRow['Section'] = $sectionKey
                foreach ($col in $hdrs) {
                    if ($rowObj.Contains($col)) {
                        $val = $rowObj[$col]
                        if ($null -eq $val) {
                            $newRow[$col] = [System.DBNull]::Value
                        } else {
                            $newRow[$col] = "$val"
                        }
                    }
                }
                $dt.Rows.Add($newRow)
            }
            $serverOut[$sectionKey] = $dt
        }
        $allData[$sname] = $serverOut
    }

    return $allData
}


# -----------------------------------------------------------------------------
# Script entry point — when run directly (not dot-sourced), parse the file
# and dump a quick summary to stdout. Useful for testing.
# -----------------------------------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $InputPath) {
        Write-Host '[ERROR] -InputPath is required when running this script directly.' -ForegroundColor Red
        Write-Host 'Example: .\rpt-to-datatables.ps1 -InputPath ''.\test.rpt''' -ForegroundColor Yellow
        exit 1
    }
    $allData = Convert-RptToAllData -RptPath $InputPath
    Write-Host ''
    Write-Host '======================================================' -ForegroundColor Cyan
    Write-Host '  rpt-to-datatables' -ForegroundColor Cyan
    Write-Host '======================================================' -ForegroundColor Cyan
    Write-Host "  Input  : $InputPath"
    Write-Host "  Servers: $($allData.Count)"
    Write-Host ''
    foreach ($sname in ($allData.Keys | Sort-Object)) {
        $hi = 0; $md = 0
        foreach ($k in @('06_DB_Level_Findings','07_TSQL_Code_Scan','08_SKU_Features')) {
            $dt = $allData[$sname][$k]
            if ($dt) {
                foreach ($r in $dt.Rows) {
                    $sev = "$($r['Severity'])".ToLower()
                    if ($sev -match 'high')        { $hi++ }
                    elseif ($sev -match 'medium')  { $md++ }
                }
            }
        }
        $dbCount = $allData[$sname]['05_Database_Inventory'].Rows.Count
        Write-Host ("  {0,-10} {1,3} dbs · {2} high · {3} medium" -f $sname, $dbCount, $hi, $md)
    }
    Write-Host ''
}
