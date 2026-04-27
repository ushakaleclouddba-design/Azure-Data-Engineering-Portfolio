# ============================================================
# SQL Server 2025 Enterprise Developer - LOCAL INSTALL
# Run ON the target node (Node5 or Node6)
# ============================================================
# This script runs ON the node being installed.
# Pulls install files from SRINI-NODE4 admin share.
#
# How to use:
#   1. RDP to SRINI-NODE5 (or SRINI-NODE6)
#   2. Open admin PowerShell
#   3. Run this script (or copy-paste sections)
#   4. Wait ~50 min total (install + CU + reboot)
#
# Prerequisites on SRINI-NODE4:
#   \\SRINI-NODE4\C$\SQLInstall\SQLServer2025-x64-ENU-EntDev.iso
#   \\SRINI-NODE4\C$\SQLInstall\SQL2025-Config.ini
#   \\SRINI-NODE4\C$\SQLInstall\SQLServer2025-KB5075211-x64.exe
# ============================================================


# ============================================================
# STEP 1: Create local install folder
# ============================================================
New-Item -Path "C:\SQLInstall" -ItemType Directory -Force


# ============================================================
# STEP 2: Copy SQL 2025 ISO from Node4 (~1.18 GB)
# ============================================================
Copy-Item "\\SRINI-NODE4\C$\SQLInstall\SQLServer2025-x64-ENU-EntDev.iso" "C:\SQLInstall\" -Force


# ============================================================
# STEP 3: Copy unattended install config file
# ============================================================
Copy-Item "\\SRINI-NODE4\C$\SQLInstall\SQL2025-Config.ini" "C:\SQLInstall\" -Force


# ============================================================
# STEP 4: Copy CU2 patch file (~394 MB)
# ============================================================
Copy-Item "\\SRINI-NODE4\C$\SQLInstall\SQLServer2025-KB5075211-x64.exe" "C:\SQLInstall\" -Force


# ============================================================
# STEP 5: Verify all files copied
# ============================================================
Get-ChildItem "C:\SQLInstall" | Select-Object Name, @{N='SizeMB';E={[math]::Round($_.Length/1MB,0)}}


# ============================================================
# STEP 6: Create data, log, and backup folders
# ============================================================
New-Item -Path C:\data, C:\log, C:\backup -ItemType Directory -Force


# ============================================================
# STEP 7: Mount the SQL Server 2025 ISO as virtual DVD
# ============================================================
$mount = Mount-DiskImage -ImagePath "C:\SQLInstall\SQLServer2025-x64-ENU-EntDev.iso" -PassThru
Start-Sleep -Seconds 3
$drive = ($mount | Get-Volume).DriveLetter
Write-Host "ISO mounted at: $drive`:" -ForegroundColor Green


# ============================================================
# STEP 8: Run SQL Server 2025 install (silent, ~25 min)
# ============================================================
& "${drive}:\setup.exe" `
    /ConfigurationFile="C:\SQLInstall\SQL2025-Config.ini" `
    /IACCEPTSQLSERVERLICENSETERMS `
    /SAPWD="Str0ng#Srini2026!POC" `
    /SQLSYSADMINACCOUNTS="$env:USERDOMAIN\$env:USERNAME" "$env:USERDOMAIN\Domain Admins"


# ============================================================
# STEP 9: Check exit code (0 = success)
# ============================================================
Write-Host "Setup exit code: $LASTEXITCODE" -ForegroundColor Yellow


# ============================================================
# STEP 10: Unmount the ISO
# ============================================================
Dismount-DiskImage -ImagePath "C:\SQLInstall\SQLServer2025-x64-ENU-EntDev.iso"


# ============================================================
# STEP 11: Apply CU2 patch (silent, ~15-20 min)
# Note: Exit 3010 = success but reboot needed (normal)
# ============================================================
Start-Process "C:\SQLInstall\SQLServer2025-KB5075211-x64.exe" `
    -ArgumentList "/quiet /IAcceptSQLServerLicenseTerms /Action=Patch /AllInstances" `
    -Wait -NoNewWindow

Write-Host "CU2 exit: $LASTEXITCODE (0=success, 3010=success-reboot-needed)" -ForegroundColor Yellow


# ============================================================
# STEP 12: Open Windows Firewall for SQL port 1433
# ============================================================
New-NetFirewallRule -DisplayName "SQL Server 1433" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 1433 `
    -Action Allow


# ============================================================
# STEP 13: Reboot to finalize CU2
# (CU2 requires reboot - exit 3010 means restart needed)
# ============================================================
Write-Host "Rebooting in 10 seconds..." -ForegroundColor Cyan
Start-Sleep 10
Restart-Computer -Force


# === AFTER REBOOT - run these manually ===

# ============================================================
# STEP 14: Verify after reboot
# (RDP back in and run these commands)
# ============================================================
# Get-Service MSSQLSERVER
# 
# & "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\SQLCMD.EXE" `
#     -S . -E -C `
#     -Q "SELECT @@VERSION"
#
# Expected: Microsoft SQL Server 2025 (RTM-CU2) - 17.0.4015.4 (X64)


# ============================================================
# DONE! SQL Server 2025 CU2 installed on this node
# ============================================================
