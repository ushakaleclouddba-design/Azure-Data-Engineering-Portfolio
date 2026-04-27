# SQL 2022 Install - Reads from LOCAL C:\SQLInstall
# With explicit UPDATEENABLED=False override

$iso    = "C:\SQLInstall\SQLServer2022-x64-ENU-Dev.iso"
$config = "C:\SQLInstall\SQL2022-Config.ini"
$sa     = "Str0ng#Srini2026!POC"
$me     = "$env:USERDOMAIN\$env:USERNAME"

Write-Host "[$env:COMPUTERNAME] Starting install..." -ForegroundColor Cyan

if (-not (Test-Path $iso))    { throw "ISO not found at $iso" }
if (-not (Test-Path $config)) { throw "Config not found at $config" }

New-Item -Path C:\data, C:\log, C:\backup -ItemType Directory -Force | Out-Null

Write-Host "[$env:COMPUTERNAME] Mounting ISO..." -ForegroundColor Yellow
$mount = Mount-DiskImage -ImagePath $iso -PassThru
Start-Sleep -Seconds 3
$drive = ($mount | Get-Volume).DriveLetter
Write-Host "[$env:COMPUTERNAME] ISO at ${drive}:" -ForegroundColor Green

Write-Host "[$env:COMPUTERNAME] Running setup (20-30 min)..." -ForegroundColor Yellow
# Key: /UPDATEENABLED=False overrides whatever's in the config file
# Also skip update-related rules
& "${drive}:\setup.exe" `
    /ConfigurationFile="$config" `
    /IACCEPTSQLSERVERLICENSETERMS `
    /SAPWD="$sa" `
    /SQLSYSADMINACCOUNTS="$me" "srini\Domain Admins" `
    /UPDATEENABLED=False `
    /USEMICROSOFTUPDATE=False `
    /SKIPRULES=RebootRequiredCheck

Write-Host "[$env:COMPUTERNAME] Setup exit code: $LASTEXITCODE" -ForegroundColor Yellow

Dismount-DiskImage -ImagePath $iso

Remove-NetFirewallRule -DisplayName "SQL Server 1433" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "SQL Browser 1434" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "SQL Server 1433" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow | Out-Null
New-NetFirewallRule -DisplayName "SQL Browser 1434" -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow | Out-Null

$sql = Get-Service MSSQLSERVER -ErrorAction SilentlyContinue
if ($sql) {
    Write-Host "[$env:COMPUTERNAME] SUCCESS - SQL service: $($sql.Status)" -ForegroundColor Green
} else {
    Write-Host "[$env:COMPUTERNAME] FAILED - no SQL service" -ForegroundColor Red
}
