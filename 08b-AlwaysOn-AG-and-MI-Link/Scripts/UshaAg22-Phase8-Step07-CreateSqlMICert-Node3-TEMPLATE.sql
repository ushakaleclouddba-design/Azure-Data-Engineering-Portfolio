-- =============================================================================
-- UshaAg22-Phase8-Step07-CreateSqlMICert-Node3.sql (TEMPLATE)
-- =============================================================================
-- Phase:    8 — Certificate generation + exchange for MI Link
-- Step:     8.7 — Create cert on Node3 representing SQL MI
-- Run on:   Node3 in SSMS, master database
-- Date:     April 29, 2026
-- =============================================================================
--
-- IMPORTANT — THIS IS A TEMPLATE
-- ------------------------------
-- The actual binary value in CREATE CERTIFICATE FROM BINARY is the
-- 4264-character hex string from SQL MI's public key. That string is
-- specific to your SQL MI instance and changes every cert rotation.
--
-- DO NOT run this template as-is. Instead:
--   1. Run Step 8.5 to get the SQL MI public key hex
--   2. Run Step 8.7a to generate the .sql file with hex embedded
--   3. Open the generated .sql file in SSMS and execute
--
-- This template is for reference / documentation only.
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
-- THE 0x... VALUE BELOW IS A PLACEHOLDER. Real value is 4264 chars.
PRINT 'Creating SqlMI_MILink_Cert from SQL MI public key...';

CREATE CERTIFICATE SqlMI_MILink_Cert
    FROM BINARY = 0x308204... ;  -- ACTUAL HEX FROM AZURE GOES HERE (~4264 chars)
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
