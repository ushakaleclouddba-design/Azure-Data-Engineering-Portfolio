-- =============================================================================
-- UshaAg22-Phase8-Step03-BackupCertificate-Node3.sql
-- =============================================================================
-- Phase:    8 — Certificate generation + exchange for MI Link
-- Step:     8.3 — Back up the certificate to disk
-- Run on:   Node3 in SSMS, master database
-- Date:     April 29, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Exports two files to C:\Backup\:
--   1. Node3_MILink_Cert.cer    -- PUBLIC key only (safe to share with SQL MI)
--   2. Node3_MILink_Cert.pvk    -- PRIVATE key (NEVER share, DR only)
--
-- WHAT GOES TO SQL MI
-- -------------------
-- Only the .cer file (public key). The .pvk stays on Node3 forever.
-- This is the same model as SSL/TLS certs — public key is shared,
-- private key is hidden.
--
-- WHY BACK UP THE PRIVATE KEY
-- ---------------------------
-- If Node3's master DB is ever lost or corrupted, the cert and its
-- private key are lost too. Restoring would require recreating the
-- whole MI Link relationship. Backing up the private key file lets
-- you restore the cert to the same name on a recovery node.
--
-- ENCRYPTION ON THE EXPORT
-- ------------------------
-- The .pvk file is encrypted by a password we provide. SQL Server
-- won't export it in plaintext — even on disk, the private key
-- stays protected.
-- =============================================================================

USE master;
GO

-- Backup the certificate (public key + private key)
PRINT 'Backing up Node3_MILink_Cert...';

BACKUP CERTIFICATE Node3_MILink_Cert
    TO FILE = 'C:\Backup\Node3_MILink_Cert.cer'
    WITH PRIVATE KEY (
        FILE = 'C:\Backup\Node3_MILink_Cert.pvk',
        ENCRYPTION BY PASSWORD = 'CertBackup@2026!Banking#Strong'
    );
GO

PRINT 'Backup complete.';
PRINT 'Files created:';
PRINT '  C:\Backup\Node3_MILink_Cert.cer  -- PUBLIC KEY (this goes to SQL MI)';
PRINT '  C:\Backup\Node3_MILink_Cert.pvk  -- PRIVATE KEY (keep on Node3 only!)';
GO

-- After running, verify in PowerShell:
--   Get-ChildItem C:\Backup\Node3_MILink_Cert.* | Select-Object Name, Length, LastWriteTime
-- Expected:
--   Node3_MILink_Cert.cer  ~980 bytes  (public key)
--   Node3_MILink_Cert.pvk  ~1788 bytes (private key, encrypted)
