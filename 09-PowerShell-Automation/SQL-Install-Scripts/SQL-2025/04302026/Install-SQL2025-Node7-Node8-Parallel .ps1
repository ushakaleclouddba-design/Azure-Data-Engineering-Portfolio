# ============================================================
# SQL Server 2025 Parallel Install — Node7 + Node8 (ushadc.com)
# ============================================================
#
# Run from: USHADC (or any control node in ushadc.com with admin access)
# Target nodes: Node7 (192.168.68.27), Node8 (192.168.68.28)
# Domain: ushadc.com
#
# Pattern: Push-then-install with CredSSP authentication
# Adapted from proven Srini lab pattern (Apr 22-23, 2026)
#
# Pre-requisites:
#   - ISO staged at: \\<source>\C$\SQLInstall\SQLServer2025-x64-ENU-EntDev.iso
#   - Config staged at: \\<source>\C$\SQLInstall\SQL2025-Config.ini
#   - CU2 staged at: \\<source>\C$\SQLInstall\SQLServer2025-KB5075211-x64.exe
#   - Author has Domain Admin or local admin on Node7/Node8
# ============================================================

# ------------------------------------------------------------
# STEP 0: Variables (EDIT THESE)
# ------------------------------------------------------------
$SourceNode = "USHADC"          # where ISO/config/CU live
$TargetNodes = @("Node7", "Node8")
$ISOPath    = "C:\SQLInstall\SQLServer2025-x64-ENU-EntDev.iso"
$ConfigPath = "C:\SQLInstall\SQL2025-Config.ini"
$CUPath     = "C:\SQLInstall\SQLServer2025-KB5075211-x64.exe"
$SAPassword = "REPLACE_WITH_STRONG_PASSWORD"  # 4-of-4 categories required: uppercase + lowercase + digit + special

# ------------------------------------------------------------
# STEP 1: Push files to both targets via admin share
# ------------------------------------------------------------
Write-Host "=== STEP 1: Pushing install media to targets ===" -ForegroundColor Cyan

foreach ($node in $TargetNodes) {
    Write-Host "[$node] Creating C:\SQLInstall folder..." -ForegroundColor Yellow
    Invoke-Command -ComputerName $node -ScriptBlock {
        New-Item -Path "C:\SQLInstall" -ItemType Directory -Force | Out-Null
    }

    Write-Host "[$node] Copying ISO (~1.2 GB)..." -ForegroundColor Yellow
    Copy-Item -Path $ISOPath -Destination "\\$node\C$\SQLInstall\" -Force

    Write-Host "[$node] Copying config..." -ForegroundColor Yellow
    Copy-Item -Path $ConfigPath -Destination "\\$node\C$\SQLInstall\" -Force

    Write-Host "[$node] Copying CU2..." -ForegroundColor Yellow
    Copy-Item -Path $CUPath -Destination "\\$node\C$\SQLInstall\" -Force

    Write-Host "[$node] Verifying files..." -ForegroundColor Green
    Invoke-Command -ComputerName $node -ScriptBlock {
        Get-ChildItem C:\SQLInstall | Select Name, @{N='SizeMB';E={[math]::Round($_.Length/1MB,1)}}
    }
}

# ------------------------------------------------------------
# STEP 2: Enable CredSSP on the control node (this machine)
# ------------------------------------------------------------
Write-Host "`n=== STEP 2: Enabling CredSSP client delegation ===" -ForegroundColor Cyan
Enable-WSManCredSSP -Role Client -DelegateComputer $TargetNodes -Force

# ------------------------------------------------------------
# STEP 3: Enable CredSSP on each target (must be done on the targets)
# ------------------------------------------------------------
Write-Host "`n=== STEP 3: Enabling CredSSP server role on targets ===" -ForegroundColor Cyan
foreach ($node in $TargetNodes) {
    Invoke-Command -ComputerName $node -ScriptBlock {
        Enable-WSManCredSSP -Role Server -Force
    }
    Write-Host "[$node] CredSSP server enabled" -ForegroundColor Green
}

# ------------------------------------------------------------
# STEP 4: Get domain admin credentials for CredSSP install
# ------------------------------------------------------------
Write-Host "`n=== STEP 4: Capturing credentials for parallel install ===" -ForegroundColor Cyan
$cred = Get-Credential -Message "Enter ushadc\Administrator (or Domain Admin) credentials for SQL install"

# ------------------------------------------------------------
# STEP 5: Define install script block (runs on each target)
# ------------------------------------------------------------
$installScript = {
    param($SAPassword)

    Write-Host "[$env:COMPUTERNAME] Starting SQL 2025 install at $(Get-Date)" -ForegroundColor Cyan

    # Create data/log/backup directories
    New-Item -Path "C:\data","C:\log","C:\backup" -ItemType Directory -Force | Out-Null

    # Mount ISO
    $mount = Mount-DiskImage -ImagePath "C:\SQLInstall\SQLServer2025-x64-ENU-EntDev.iso" -PassThru
    Start-Sleep -Seconds 5
    $drive = ($mount | Get-Volume).DriveLetter
    Write-Host "[$env:COMPUTERNAME] ISO mounted at ${drive}:" -ForegroundColor Yellow

    # Build sysadmin list (current domain user + Domain Admins group)
    $me = "$env:USERDOMAIN\$env:USERNAME"
    $admins = "$env:USERDOMAIN\Domain Admins"

    # Run setup
    Write-Host "[$env:COMPUTERNAME] Running setup.exe..." -ForegroundColor Yellow
    & "${drive}:\setup.exe" `
        /ConfigurationFile="C:\SQLInstall\SQL2025-Config.ini" `
        /IACCEPTSQLSERVERLICENSETERMS `
        /SAPWD="$SAPassword" `
        /SQLSYSADMINACCOUNTS="$me" "$admins"

    $setupExit = $LASTEXITCODE
    Write-Host "[$env:COMPUTERNAME] Setup exit code: $setupExit" -ForegroundColor $(if($setupExit -eq 0){'Green'}else{'Red'})

    # Dismount ISO
    Dismount-DiskImage -ImagePath "C:\SQLInstall\SQLServer2025-x64-ENU-EntDev.iso" | Out-Null

    # Apply CU2 if base install succeeded
    if ($setupExit -eq 0) {
        Write-Host "[$env:COMPUTERNAME] Applying CU2..." -ForegroundColor Yellow
        Start-Process -FilePath "C:\SQLInstall\SQLServer2025-KB5075211-x64.exe" `
            -ArgumentList "/quiet /IAcceptSQLServerLicenseTerms /Action=Patch /AllInstances" `
            -Wait -NoNewWindow

        $cuExit = $LASTEXITCODE
        Write-Host "[$env:COMPUTERNAME] CU2 exit code: $cuExit (3010 = success, reboot required)" -ForegroundColor $(if($cuExit -in 0,3010){'Green'}else{'Red'})
    } else {
        $cuExit = "skipped"
    }

    # Firewall rule
    New-NetFirewallRule -DisplayName "SQL Server 1433" -Direction Inbound -Protocol TCP `
        -LocalPort 1433 -Action Allow -ErrorAction SilentlyContinue | Out-Null

    return [PSCustomObject]@{
        Computer = $env:COMPUTERNAME
        SetupExit = $setupExit
        CUExit = $cuExit
        Time = Get-Date
    }
}

# ------------------------------------------------------------
# STEP 6: Launch parallel install
# ------------------------------------------------------------
Write-Host "`n=== STEP 6: Launching parallel install on $($TargetNodes -join ', ') ===" -ForegroundColor Cyan
Write-Host "Estimated time: 25-50 min (Setup ~25, CU2 ~15-20)" -ForegroundColor Yellow

$jobs = Invoke-Command `
    -ComputerName $TargetNodes `
    -Credential $cred `
    -Authentication Credssp `
    -ScriptBlock $installScript `
    -ArgumentList $SAPassword `
    -AsJob

Write-Host "Jobs launched. Job ID: $($jobs.Id)" -ForegroundColor Green
Write-Host "Monitor with: Get-Job $($jobs.Id) | Receive-Job -Keep" -ForegroundColor Yellow

# ------------------------------------------------------------
# STEP 7: Monitor (run periodically)
# ------------------------------------------------------------
# Get-Job | Select Id, Location, State, @{N='Duration';E={(Get-Date) - $_.PSBeginTime}}

# ------------------------------------------------------------
# STEP 8: Receive results when State=Completed
# ------------------------------------------------------------
# Get-Job | Receive-Job

# ------------------------------------------------------------
# STEP 9: Reboot targets after CU2 (CU returns 3010 = reboot needed)
# ------------------------------------------------------------
# Restart-Computer -ComputerName $TargetNodes -Force -Wait

# ------------------------------------------------------------
# STEP 10: Verify build version on both nodes
# ------------------------------------------------------------
# foreach ($node in $TargetNodes) {
#     Invoke-Command -ComputerName $node -ScriptBlock {
#         & "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\SQLCMD.EXE" `
#             -S . -E -C -Q "SELECT @@VERSION"
#     }
# }
# Expected: 17.0.4015.4 (SQL 2025 RTM CU2)

# ============================================================
# DONE — verify both nodes show 17.0.4015.4 and you're set
# ============================================================
