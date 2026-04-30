# =============================================================================
# UshaAg22-Phase8-Step07a-GenerateImportSql-Node3.ps1
# =============================================================================
# Phase:    8 — Certificate generation + exchange for MI Link
# Step:     8.7a — Generate the T-SQL script that imports SQL MI's cert
# Run on:   Node3 PowerShell
# Date:     April 29, 2026
# =============================================================================
#
# PURPOSE
# -------
# The SQL MI public key is 4264 hex characters — too long to type into
# SSMS by hand. This script reads the saved hex from Step 8.5 and
# generates a complete .sql file that can be opened in SSMS and executed.
#
# WHY A TWO-STAGE APPROACH
# ------------------------
# Stage A (this script):  PowerShell generates the SQL with the hex embedded
# Stage B (the .sql file): Open in SSMS, execute against Node3 master DB
#
# Trying to do it as a single Invoke-Sqlcmd from PowerShell often fails
# because the hex string contains characters that get interpreted as
# PowerShell variables. The two-stage approach sidesteps that entirely.
# =============================================================================

$miPublicKey = (Get-Content 'C:\Backup\SqlMI_PublicKey_Hex.txt' -Raw).Trim()

$sql = @"
-- =============================================================================
-- UshaAg22-Phase8-Step07-CreateSqlMICert-Node3.sql
-- =============================================================================
-- Phase:    8 — Certificate generation + exchange for MI Link
-- Step:     8.7 — Create cert on Node3 representing SQL MI
-- Run on:   Node3 in SSMS, master database
-- =============================================================================
--
-- PURPOSE
-- -------
-- Creates a certificate on Node3 that represents SQL MI's identity.
-- After this, Node3 trusts any connection signed by this cert as
-- coming from SQL MI.
--
-- HOW THIS DIFFERS FROM Node3's OWN CERT (Step 8.2)
-- -------------------------------------------------
-- Step 8.2 created Node3's own cert with private key (Node3 SIGNS).
-- Step 8.7 creates a cert with PUBLIC key only — Node3 VERIFIES.
-- We never have SQL MI's private key — Microsoft keeps it.
-- =============================================================================

USE master;
GO

-- Drop if exists (re-run safety)
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'SqlMI_MILink_Cert')
BEGIN
    PRINT 'Cert SqlMI_MILink_Cert already exists - dropping for clean re-run';
    DROP CERTIFICATE SqlMI_MILink_Cert;
END
GO

-- Create the cert from SQL MI's public key
PRINT 'Creating SqlMI_MILink_Cert from SQL MI public key...';

CREATE CERTIFICATE SqlMI_MILink_Cert
    FROM BINARY = $miPublicKey;
GO

PRINT 'Certificate created successfully.';

-- Verify
SELECT 
    name AS CertName,
    subject,
    start_date,
    expiry_date,
    issuer_name,
    pvt_key_encryption_type_desc AS PrivateKeyEncryption
FROM sys.certificates
WHERE name = 'SqlMI_MILink_Cert';
GO

-- Show all certs on Node3
SELECT 
    name AS CertName,
    LEFT(subject, 60) AS Subject,
    expiry_date,
    pvt_key_encryption_type_desc AS HasPrivateKey
FROM sys.certificates
WHERE name LIKE '%MILink%' OR name LIKE '%SqlMI%' OR name LIKE '%Node%'
ORDER BY name;
GO
"@

$sql | Out-File -FilePath 'C:\Backup\Phase8-Step07-CreateSqlMICert.sql' -Encoding UTF8

Write-Host ""
Write-Host "===== SQL Script Generated =====" -ForegroundColor Green
Write-Host "File: C:\Backup\Phase8-Step07-CreateSqlMICert.sql" -ForegroundColor Yellow
Write-Host "Size: $((Get-Item 'C:\Backup\Phase8-Step07-CreateSqlMICert.sql').Length) bytes" -ForegroundColor Yellow
Write-Host ""
Write-Host "NEXT: Open this file in SSMS connected to Node3, master database" -ForegroundColor Cyan
Write-Host "Then F5 to execute" -ForegroundColor Cyan
