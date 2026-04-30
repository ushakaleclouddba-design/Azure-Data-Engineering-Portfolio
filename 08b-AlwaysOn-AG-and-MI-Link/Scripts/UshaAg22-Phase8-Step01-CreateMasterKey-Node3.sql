-- =============================================================================
-- UshaAg22-Phase8-Step01-CreateMasterKey-Node3.sql
-- =============================================================================
-- Phase:    8 — Certificate generation + exchange for MI Link
-- Step:     8.1 — Create database master key in master database
-- Run on:   Node3 in SSMS, master database
-- Date:     April 29, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Creates the database master key (DMK) in the master database. The DMK
-- is required before SQL Server can create or manage certificates and
-- asymmetric keys. Standard prerequisite for any SQL Server cert work.
--
-- ENCRYPTION HIERARCHY (foundation laid here)
-- -------------------------------------------
--   Service Master Key (SMK)        ← automatic, per SQL instance
--           ↓ encrypts
--   Database Master Key (DMK)       ← THIS STEP (encrypted by SMK + password)
--           ↓ encrypts
--   Certificate's private key       ← Step 8.2 creates this
--           ↓ used for
--   Mirroring endpoint auth         ← Step 9 uses it
--
-- WHERE IT LIVES
-- --------------
-- The DMK is stored in master database, encrypted by:
--   1. The Service Master Key (SMK) — automatic
--   2. A password — provided in the CREATE statement
--
-- The SMK encryption is what allows SQL to auto-open the DMK when the
-- service starts. The password is a backup for disaster recovery.
--
-- IMPORTANT — KEEP THE PASSWORD SAFE
-- ----------------------------------
-- If you ever need to restore the master DB on a different SQL instance,
-- you'll need this password to open the DMK manually. Store it securely
-- (Key Vault, password manager, sealed envelope in a safe).
--
-- IS THIS LIKE TDE?
-- -----------------
-- Same encryption hierarchy used by TDE, but DIFFERENT PURPOSE here.
-- TDE: cert encrypts data files at rest.
-- MI Link cert: cert authenticates server-to-server connections.
-- Both can coexist on the same instance without conflict.
-- =============================================================================

USE master;
GO

-- Check if a master key already exists
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    PRINT 'No master key exists - creating one...';
    
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'UshaMK@2026!Banking#Strong';
    
    PRINT 'Master key created.';
END
ELSE
BEGIN
    PRINT 'Master key already exists - skipping creation.';
    PRINT 'If you need to know the password, retrieve from your records.';
END
GO

-- Verify
SELECT 
    name,
    create_date,
    modify_date,
    key_length,
    algorithm_desc
FROM sys.symmetric_keys
WHERE name = '##MS_DatabaseMasterKey##';
GO
