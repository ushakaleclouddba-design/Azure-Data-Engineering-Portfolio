# =============================================================================
# UshaAg22-Phase8-Step05-GetSqlMICert-Node3.ps1
# =============================================================================
# Phase:    8 — Certificate generation + exchange for MI Link
# Step:     8.5 — Get SQL MI's mirroring endpoint certificate
# Run on:   Node3 PowerShell (still authenticated to Azure)
# Date:     April 29, 2026
# =============================================================================
#
# PURPOSE
# -------
# Retrieves SQL MI's certificate for its DATABASE_MIRRORING endpoint.
# Unlike on-prem SQL Server where we manually CREATE CERTIFICATE, Azure
# manages this cert on the SQL MI side automatically. We just ask for it.
#
# WHAT 'DATABASE_MIRRORING' MEANS HERE
# ------------------------------------
# This is the endpoint type SQL Server uses for AG and Distributed AG
# log replication. Don't be misled by 'mirroring' in the name — it's
# the same endpoint type AGs use, just historically named.
#
# AUTO-GENERATION
# ---------------
# Azure auto-generates this cert when first requested. Subsequent calls
# return the same cert. Microsoft signs the cert using their internal CA
# (Microsoft Azure RSA TLS Issuing CA 07) which is why the SQL MI cert
# is much longer (4264 chars hex) than Node3's self-signed cert (1962).
#
# CERT ROTATION
# -------------
# SQL MI cert auto-renews every ~4 months. Microsoft Learn covers
# rotation procedures. We don't worry about this for the initial setup
# but production environments need a rotation process.
# =============================================================================

# Configuration
$ResourceGroup = 'Usha_SQLMI_POC'
$SqlMIName     = 'usha-sqlmi-poc'

Write-Host ""
Write-Host "===== Retrieving SQL MI's mirroring endpoint certificate =====" -ForegroundColor Cyan
Write-Host "Resource Group : $ResourceGroup" -ForegroundColor Yellow
Write-Host "SQL MI Name    : $SqlMIName" -ForegroundColor Yellow
Write-Host ""

# Get the cert. Endpoint type for AG/DAG is DATABASE_MIRRORING
$miCert = Get-AzSqlInstanceEndpointCertificate `
    -ResourceGroupName $ResourceGroup `
    -InstanceName $SqlMIName `
    -EndpointType 'DATABASE_MIRRORING'

Write-Host "===== SQL MI Cert Details =====" -ForegroundColor Green
$miCert | Format-List

$miCertPublicKey = $miCert.PublicKey

Write-Host ""
Write-Host "===== Cert Public Key =====" -ForegroundColor Cyan
Write-Host "Length: $($miCertPublicKey.Length) chars" -ForegroundColor Green
Write-Host "Preview: $($miCertPublicKey.Substring(0, 60))..." -ForegroundColor Green

# Save the hex public key to a temp file for use in Step 8.7
$miCertPublicKey | Out-File -FilePath 'C:\Backup\SqlMI_PublicKey_Hex.txt' -Encoding ASCII
Write-Host ""
Write-Host "===== Saved to file =====" -ForegroundColor Cyan
Write-Host "C:\Backup\SqlMI_PublicKey_Hex.txt" -ForegroundColor Green
Write-Host "(We'll use this in Step 8.7 to create the cert on Node3)" -ForegroundColor Yellow
