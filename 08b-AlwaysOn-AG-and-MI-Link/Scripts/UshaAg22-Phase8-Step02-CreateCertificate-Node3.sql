-- =============================================================================
-- UshaAg22-Phase8-Step02-CreateCertificate-Node3.sql
-- =============================================================================
-- Phase:    8 — Certificate generation + exchange for MI Link
-- Step:     8.2 — Create cert on Node3 for mirroring endpoint authentication
-- Run on:   Node3 in SSMS, master database
-- Date:     April 29, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Creates a certificate that Node3 will present to SQL MI when they
-- establish the mirroring endpoint connection. SQL MI will verify
-- Node3's identity using the public part of this cert.
--
-- KEY FACTS
-- ---------
-- - Certificate's PRIVATE KEY stays on Node3 (we never share it)
-- - Certificate's PUBLIC KEY gets uploaded to SQL MI in Step 8.4
-- - Cert is encrypted by the database master key (created in Step 8.1)
-- - Cert is valid for 10 years (best practice for endpoint certs)
--
-- NAMING CONVENTION
-- -----------------
-- Cert name follows MI Link convention: <ServerName>_MILink_Cert
-- This makes it obvious which server the cert belongs to in case of
-- multi-instance setups.
--
-- ANALOGY
-- -------
-- Think of this cert as Node3 printing a passport for itself:
--   - Photo and signature  = public key (anyone can see)
--   - Holographic seal     = private key (only Node3 can produce)
--   - Expiration date      = 10 years out
--   - Whole passport       = locked in a safe (encrypted by master key)
--
-- Subsequent steps:
--   8.3: Photocopy public-facing parts of passport (export public key)
--   8.4: Send photocopy to SQL MI's immigration office (upload to Azure)
--   8.5-8.7: Get SQL MI's passport in return
-- =============================================================================

USE master;
GO

-- Drop if exists (re-run safety)
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'Node3_MILink_Cert')
BEGIN
    PRINT 'Certificate Node3_MILink_Cert already exists - dropping for clean re-run';
    DROP CERTIFICATE Node3_MILink_Cert;
END
GO

-- Create the certificate
PRINT 'Creating certificate Node3_MILink_Cert...';

CREATE CERTIFICATE Node3_MILink_Cert
    WITH SUBJECT = 'Node3 MI Link Certificate',
         EXPIRY_DATE = '2036-04-29';
GO

PRINT 'Certificate created successfully.';

-- Verify
SELECT 
    name AS CertName,
    subject,
    start_date,
    expiry_date,
    pvt_key_encryption_type_desc AS PrivateKeyEncryption,
    issuer_name
FROM sys.certificates
WHERE name = 'Node3_MILink_Cert';
GO
