# ============================================================
# SQL Server 2022 Standalone Install - SRINI-NODE7
# ============================================================
# Pulls install files from srinidcmaster, installs SQL Server 2022,
# applies CU24, opens firewall, verifies version.
#
# Prerequisites:
#   - Node7 joined to srinidc.com
#   - Files exist on \\srinidcmaster\C$\SQLInstall\:
#       - SQLServer2022-x64-ENU-Dev.iso
#       - SQL2022-Config.ini
#       - SQLServer2022-KB5080999-x64.exe
#   - Run on Node7 in admin PowerShell
#
# Total time: ~45 min
# ============================================================


# ============================================================
# STEP 1: Create local install folder
# ============================================================
New-Item -Path "C:\SQLInstall" -ItemType Directory -Force


# ============================================================
# STEP 2: Copy SQL 2022 ISO from srinidcmaster (~1.1 GB)
# ============================================================
Copy-Item "\\srinidcmaster\C$\SQLInstall\SQLServer2022-x64-ENU-Dev.iso" "C:\SQLInstall\" -Force


# ============================================================
# STEP 3: Copy unattended install config file
# ============================================================
Copy-Item "\\srinidcmaster\C$\SQLInstall\SQL2022-Config.ini" "C:\SQLInstall\" -Force


# ============================================================
# STEP 4: Copy CU24 patch file (~487 MB)
# ============================================================
Copy-Item "\\srinidcmaster\C$\SQLInstall\SQLServer2022-KB5080999-x64.exe" "C:\SQLInstall\" -Force


# ============================================================
# STEP 5: Verify all files copied
# ============================================================
Get-ChildItem "C:\SQLInstall" | Select-Object Name, @{N='SizeMB';E={[math]::Round($_.Length/1MB,0)}}


# ============================================================
# STEP 6: Create data, log, and backup folders
# ============================================================
New-Item -Path C:\data, C:\log, C:\backup -ItemType Directory -Force


# ============================================================
# STEP 7: Mount the SQL Server ISO as a virtual DVD drive
# ============================================================
$mount = Mount-DiskImage -ImagePath "C:\SQLInstall\SQLServer2022-x64-ENU-Dev.iso" -PassThru
Start-Sleep -Seconds 3
$drive = ($mount | Get-Volume).DriveLetter
Write-Host "ISO mounted at: $drive`:" -ForegroundColor Green


# ============================================================
# STEP 8: Run SQL Server install (silent, ~25 min)
# ============================================================
& "${drive}:\setup.exe" `
    /ConfigurationFile="C:\SQLInstall\SQL2022-Config.ini" `
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
Dismount-DiskImage -ImagePath "C:\SQLInstall\SQLServer2022-x64-ENU-Dev.iso"


# ============================================================
# STEP 11: Apply CU24 patch (silent, ~15 min)
# ============================================================
Start-Process "C:\SQLInstall\SQLServer2022-KB5080999-x64.exe" `
    -ArgumentList "/quiet /IAcceptSQLServerLicenseTerms /Action=Patch /AllInstances" `
    -Wait -NoNewWindow

Write-Host "CU24 exit code: $LASTEXITCODE" -ForegroundColor Yellow


# ============================================================
# STEP 12: Restart SQL Server service to apply patch
# ============================================================
Restart-Service MSSQLSERVER -Force


# ============================================================
# STEP 13: Open Windows Firewall for SQL port 1433
# ============================================================
New-NetFirewallRule -DisplayName "SQL Server 1433" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 1433 `
    -Action Allow


# ============================================================
# STEP 14: Verify SQL Server is running and check version
# ============================================================
Get-Service MSSQLSERVER

& "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe" `
    -S . -E `
    -Q "SELECT @@VERSION"

# Expected: Microsoft SQL Server 2022 (RTM-CU24) - 16.0.4245.2 (X64)


# ============================================================
# DONE! SQL Server 2022 CU24 installed on SRINI-NODE7
# ============================================================
