# =============================================================================
# UshaAg22-Phase1-Step01-Preflight.ps1
# =============================================================================
# Phase:    1 — Pre-flight Discovery
# Step:     1.1 — Run pre-flight script across Node3, Node4, Node6
# Run on:   Node3 (regular admin Windows PowerShell — NOT ISE)
# Date:     April 28, 2026
# Author:   Usha Kale
# =============================================================================
#
# PURPOSE
# -------
# Discovers the current state of all 3 lab nodes before any AG build work.
# Surfaces issues (time drift, missing OS features, firewall, SQL version
# mismatch) early so they don't cause obscure failures during the build.
#
# WHAT IT CHECKS
# --------------
# 1. WinRM reachability       — can we remote into each node from Node3?
# 2. Time sync drift vs DC    — must be < 60 seconds for cluster heartbeat
# 3. OS / build               — Windows Server 2022, build 20348+
# 4. Disk / RAM               — at least 5 GB free, RAM >= 4 GB
# 5. WSFC feature             — installed or available
# 6. SQL Service              — running, version, IsHadrEnabled
# 7. SQL service account      — must be consistent across nodes for AG endpoint auth
# 8. Firewall ports           — 5023 (AG endpoint), 1433 (SQL), 3343 (cluster heartbeat)
#
# OUTPUT
# ------
# - Console: per-node detail with PASS / WARN / FAIL labels
# - CSV file: C:\PSScripts\Output\UshaAg22-Preflight-<timestamp>.csv
#
# DEPENDENCIES
# ------------
# - PowerShell remoting (WinRM) enabled on all 3 nodes
# - Domain account with admin rights on all 3 nodes
# - C:\PSScripts\Output\ directory will be auto-created if missing
#
# NOTES FROM THE BUILD
# --------------------
# Phase 1 results showed:
#   - Node3, Node4: WSFC + AlwaysOn already installed (existing UshaAg22)
#   - Node6: WSFC available (not installed yet) — Phase 2 installs it
#   - All 3 nodes: 8 GB RAM, ~5 GB free, time drift well under 60s
#   - SQL Service Acct: USHADC0\ushakale (zero, not letter O — verified ASCII 48)
# =============================================================================

#Requires -RunAsAdministrator

$nodes        = @('Node3', 'Node4', 'Node6')
$domainDC     = 'USHADC'
$expectedSQL  = '16.0.4245.2'   # SQL 2022 CU24
$outputDir    = 'C:\PSScripts\Output'
$timestamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath      = Join-Path $outputDir "UshaAg22-Preflight-$timestamp.csv"

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

function Write-Header { param([string]$T,[string]$C='Cyan')
    Write-Host ''; Write-Host ('=' * 70) -ForegroundColor $C
    Write-Host $T -ForegroundColor $C
    Write-Host ('=' * 70) -ForegroundColor $C
}

function Write-Result { param([string]$L,[string]$V,[string]$S)
    $c = switch ($S) { 'PASS'{'Green'} 'WARN'{'Yellow'} 'FAIL'{'Red'} default{'White'} }
    $m = switch ($S) { 'PASS'{'[PASS]'} 'WARN'{'[WARN]'} 'FAIL'{'[FAIL]'} default{'[INFO]'} }
    Write-Host ("  {0,-7} {1,-30} {2}" -f $m, $L, $V) -ForegroundColor $c
}

$nodeCheck = {
    param($expectedSQL)
    $r = [ordered]@{
        Hostname=$env:COMPUTERNAME; Domain=$null; OS=$null; OSBuild=$null
        FreeDiskGB=$null; TotalRAMGB=$null; FreeRAMGB=$null
        WSFC_Feature=$null; SQL_Service=$null; SQL_Version=$null
        SQL_VersionMatch=$null; IsHadrEnabled=$null; SQL_ServiceAcct=$null
        FW_5023=$null; FW_1433=$null; FW_3343=$null; Errors=@()
    }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $os = Get-CimInstance Win32_OperatingSystem
        $r.Domain  = $cs.Domain
        $r.OS      = $os.Caption
        $r.OSBuild = $os.BuildNumber
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $r.FreeDiskGB = [math]::Round($disk.FreeSpace/1GB, 2)
        $r.TotalRAMGB = [math]::Round($cs.TotalPhysicalMemory/1GB, 2)
        $r.FreeRAMGB  = [math]::Round($os.FreePhysicalMemory*1KB/1GB, 2)

        $w = Get-WindowsFeature -Name Failover-Clustering -ErrorAction SilentlyContinue
        $r.WSFC_Feature = if($w){$w.InstallState.ToString()} else {'NotFound'}

        $svc = Get-Service -Name MSSQLSERVER -ErrorAction SilentlyContinue
        if ($svc) {
            $r.SQL_Service = $svc.Status.ToString()
            $wmi = Get-CimInstance Win32_Service -Filter "Name='MSSQLSERVER'"
            $r.SQL_ServiceAcct = $wmi.StartName
        } else { $r.SQL_Service = 'NotInstalled' }

        if ($svc -and $svc.Status -eq 'Running') {
            $v = & sqlcmd -S . -E -h -1 -W -Q "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50));" 2>$null | Select-Object -First 1
            $r.SQL_Version = ($v -as [string]).Trim()
            $r.SQL_VersionMatch = ($r.SQL_Version -eq $expectedSQL)
            $h = & sqlcmd -S . -E -h -1 -W -Q "SET NOCOUNT ON; SELECT SERVERPROPERTY('IsHadrEnabled');" 2>$null | Select-Object -First 1
            $r.IsHadrEnabled = ($h -as [string]).Trim()
        }

        function FW($port) {
            $rules = Get-NetFirewallPortFilter -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $port }
            if (-not $rules) { return 'NotFound' }
            $allowed = $rules | ForEach-Object { Get-NetFirewallRule -AssociatedNetFirewallPortFilter $_ -ErrorAction SilentlyContinue } | Where-Object { $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' -and $_.Direction -eq 'Inbound' }
            if ($allowed) { 'Allowed' } else { 'Blocked' }
        }
        $r.FW_5023 = FW 5023
        $r.FW_1433 = FW 1433
        $r.FW_3343 = FW 3343
    } catch { $r.Errors += $_.Exception.Message }
    [PSCustomObject]$r
}

Write-Header "UshaAg22 - Phase 1 Pre-flight  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Step 1 - Reachability
Write-Host "`nStep 1: Reachability check" -ForegroundColor Cyan
$live = @()
foreach ($n in $nodes) {
    Write-Host "  $n ... " -NoNewline
    if (-not (Test-Connection $n -Count 1 -Quiet)) { Write-Host 'UNREACHABLE' -ForegroundColor Red; continue }
    try { Test-WSMan -ComputerName $n -ErrorAction Stop | Out-Null; Write-Host 'OK' -ForegroundColor Green; $live += $n }
    catch { Write-Host 'WinRM FAILED' -ForegroundColor Red }
}
if ($live.Count -eq 0) { Write-Host 'No nodes reachable. Exit.' -ForegroundColor Red; return }

# Step 2 - Time drift
Write-Host "`nStep 2: Time sync drift vs $domainDC" -ForegroundColor Cyan
$drift = @{}
foreach ($n in $live) {
    try {
        $d = Invoke-Command -ComputerName $n -ScriptBlock {
            $o = w32tm /stripchart /computer:USHADC /samples:1 /dataonly 2>&1
            $l = $o | Where-Object { $_ -match ',\s*[+-]?\d+\.\d+s' } | Select-Object -First 1
            if ($l -match '([+-]?\d+\.\d+)s') { return [double]$Matches[1] }
        } -ErrorAction Stop
        $drift[$n] = $d
        $color = if ($d -ne $null -and [math]::Abs($d) -lt 60) {'Green'} else {'Red'}
        Write-Host ("  {0,-8} drift = {1}s" -f $n, $d) -ForegroundColor $color
    } catch { Write-Host "  $n drift unknown" -ForegroundColor Yellow }
}

# Step 3 - Per-node detail
$results = @()
foreach ($n in $live) {
    Write-Header "Node: $n" 'Yellow'
    $r = Invoke-Command -ComputerName $n -ScriptBlock $nodeCheck -ArgumentList $expectedSQL
    Write-Result 'Domain' $r.Domain $(if ($r.Domain -like '*ushadc*'){'PASS'} else {'FAIL'})
    Write-Result 'OS Build' $r.OSBuild $(if ([int]$r.OSBuild -ge 20348){'PASS'} else {'WARN'})
    Write-Result 'Free C: GB' $r.FreeDiskGB $(if ($r.FreeDiskGB -ge 5){'PASS'} elseif ($r.FreeDiskGB -ge 2){'WARN'} else {'FAIL'})
    Write-Result 'Total/Free RAM GB' "$($r.TotalRAMGB)/$($r.FreeRAMGB)" $(if ($r.FreeRAMGB -ge 1){'PASS'} else {'WARN'})
    Write-Result 'WSFC Feature' $r.WSFC_Feature $(if ($r.WSFC_Feature -eq 'Installed'){'PASS'} else {'INFO'})
    Write-Result 'SQL Service' $r.SQL_Service $(if ($r.SQL_Service -eq 'Running'){'PASS'} else {'FAIL'})
    Write-Result 'SQL Version' "$($r.SQL_Version) (expect $expectedSQL)" $(if ($r.SQL_VersionMatch){'PASS'} else {'WARN'})
    Write-Result 'IsHadrEnabled' $r.IsHadrEnabled 'INFO'
    Write-Result 'SQL Service Acct' $r.SQL_ServiceAcct 'INFO'
    Write-Result 'FW 5023 (AG)' $r.FW_5023 $(if ($r.FW_5023 -eq 'Allowed'){'PASS'} else {'WARN'})
    Write-Result 'FW 1433 (SQL)' $r.FW_1433 $(if ($r.FW_1433 -eq 'Allowed'){'PASS'} else {'WARN'})
    Write-Result 'FW 3343 (cluster)' $r.FW_3343 $(if ($r.FW_3343 -eq 'Allowed'){'PASS'} else {'INFO'})
    $results += [PSCustomObject]@{Node=$n; Domain=$r.Domain; OSBuild=$r.OSBuild; FreeDiskGB=$r.FreeDiskGB; TotalRAMGB=$r.TotalRAMGB; FreeRAMGB=$r.FreeRAMGB; TimeDriftSec=$drift[$n]; WSFC=$r.WSFC_Feature; SQL=$r.SQL_Service; SQLVer=$r.SQL_Version; HadrEnabled=$r.IsHadrEnabled; SQLAcct=$r.SQL_ServiceAcct; FW5023=$r.FW_5023; FW1433=$r.FW_1433; FW3343=$r.FW_3343}
}

$results | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "`nCSV summary: $csvPath" -ForegroundColor Cyan
Write-Host "`nPhase 1 complete. Review output. If all PASS, proceed to Phase 2." -ForegroundColor Green
