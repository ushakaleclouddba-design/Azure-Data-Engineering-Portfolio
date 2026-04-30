# =============================================================================
# UshaAg22-Phase8-Step04-UploadCertToSqlMI-Node3.ps1
# =============================================================================
# Phase:    8 — Certificate generation + exchange for MI Link
# Step:     8.4 — Upload Node3's public certificate to SQL MI
# Run on:   Node3 PowerShell (regular admin window)
# Date:     April 29, 2026
# =============================================================================
#
# PURPOSE
# -------
# Sends Node3's public certificate (.cer file from Step 8.3) to Azure
# SQL MI via the New-AzSqlInstanceServerTrustCertificate cmdlet. After
# this, SQL MI will trust connections signed by Node3_MILink_Cert.
#
# CRITICAL — TWO GOTCHAS DISCOVERED DURING BUILD
# ----------------------------------------------
# GOTCHA #1: Browser auth fails in remote/admin sessions with error
#   "A window handle must be configured. See https://aka.ms/msal-net-wam"
# Fix: use -UseDeviceAuthentication flag
#
# GOTCHA #2: -PublicKey parameter expects HEX format (^0x[0-9a-fA-F]+$),
# NOT base64. Microsoft docs are misleading on this.
# Wrong:   $cert | base64
# Right:   '0x' + [System.BitConverter]::ToString($bytes).Replace('-', '')
#
# Both gotchas are baked into this script.
# =============================================================================

# ---------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------
$CertFilePath        = 'C:\Backup\Node3_MILink_Cert.cer'
$ResourceGroup       = 'Usha_SQLMI_POC'
$SqlMIName           = 'usha-sqlmi-poc'
$CertNameInAzure     = 'Node3_MILink_Cert'
$SubscriptionId      = '26f7a991-84b3-47b7-966b-f19cbb0379bf'

# ---------------------------------------------------------------------
# Step 1: Connect to Azure using DEVICE CODE (avoids browser-handle issue)
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "===== Step 1: Authenticating to Azure (device code) =====" -ForegroundColor Cyan
Write-Host "You will see a code. Open https://microsoft.com/devicelogin in any browser," -ForegroundColor Yellow
Write-Host "enter the code, and sign in. Then return here." -ForegroundColor Yellow
Write-Host ""

Connect-AzAccount -UseDeviceAuthentication -SubscriptionId $SubscriptionId

Get-AzContext | Select-Object Name, Subscription, Tenant, Account | Format-List

# ---------------------------------------------------------------------
# Step 2: Read cert and convert to HEX (not base64!)
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "===== Step 2: Reading certificate file (hex format) =====" -ForegroundColor Cyan

if (-not (Test-Path $CertFilePath)) {
    Write-Host "ERROR: Certificate file not found at $CertFilePath" -ForegroundColor Red
    return
}

$CertBytes = [System.IO.File]::ReadAllBytes($CertFilePath)
$CertHex = '0x' + [System.BitConverter]::ToString($CertBytes).Replace('-', '')

Write-Host "  Cert file: $CertFilePath" -ForegroundColor Green
Write-Host "  File size: $($CertBytes.Length) bytes" -ForegroundColor Green
Write-Host "  Hex length: $($CertHex.Length) chars (includes 0x prefix)" -ForegroundColor Green

# ---------------------------------------------------------------------
# Step 3: Upload to SQL MI
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "===== Step 3: Uploading cert to SQL MI =====" -ForegroundColor Cyan

$result = New-AzSqlInstanceServerTrustCertificate `
    -ResourceGroupName $ResourceGroup `
    -InstanceName $SqlMIName `
    -Name $CertNameInAzure `
    -PublicKey $CertHex

Write-Host ""
Write-Host "===== Result =====" -ForegroundColor Green
$result | Format-List

# Expected output: Result object with ResourceId, Type, CertificateName, Thumbprint, PublicKey
