-- =============================================================================
-- UshaAg22-Phase5-Step02-CreateDatabase-Loans_OnPrem.sql
-- =============================================================================
-- Phase:    5 — Create UshaAg22MI + Banking Schema
-- Step:     5.2 — Create Loans_OnPrem on Node3
-- Run on:   Node3 in SSMS
-- Date:     April 28, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Creates the seed database for the new UshaAg22MI availability group.
-- Holds banking schema (Customers, Loans, Transactions) and becomes
-- the migration payload for Day 2's MI Link POC.
--
-- NAMING CONVENTION
-- -----------------
-- Loans_OnPrem matches the existing UshaAg22 database naming pattern:
--   - HRManagement_OnPrem  (existing)
--   - Payroll_OnPrem       (existing)
--   - Loans_OnPrem         (NEW - this script)
-- The "_OnPrem" suffix signals these are the on-premises versions.
-- When migrated to Azure SQL MI in Day 2, the cloud-side equivalent
-- becomes "Loans" (no suffix) inside the Managed Instance.
--
-- REQUIREMENTS BAKED IN
-- ---------------------
-- 1. RECOVERY MODEL = FULL  (required for AG)
-- 2. PRIMARY DATA FILE on C:\data
-- 3. LOG FILE on C:\log
-- 4. SIZED 50 MB / 10 MB initial, 64 MB autogrowth
-- 5. COMPATIBILITY LEVEL 160 (SQL 2022 native — set automatically)
-- 6. RE-RUN SAFETY: Drops the database first if it exists
--
-- WHY NOT TDE
-- -----------
-- TDE intentionally NOT enabled here. TDE adds complexity to AG seeding
-- and MI Link setup. Separate POC (Appendix S - TDE Migration) covers
-- TDE for AGs.
-- =============================================================================

USE master;
GO

-- Drop database if exists (re-run safety)
IF DB_ID('Loans_OnPrem') IS NOT NULL
BEGIN
    PRINT 'Loans_OnPrem already exists - dropping for clean re-run';
    ALTER DATABASE Loans_OnPrem SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Loans_OnPrem;
END
GO

-- Create the database
PRINT 'Creating Loans_OnPrem...';

CREATE DATABASE Loans_OnPrem
ON PRIMARY
    (NAME = 'Loans_OnPrem_Data',
     FILENAME = 'C:\data\Loans_OnPrem.mdf',
     SIZE = 50MB,
     FILEGROWTH = 64MB)
LOG ON
    (NAME = 'Loans_OnPrem_Log',
     FILENAME = 'C:\log\Loans_OnPrem.ldf',
     SIZE = 10MB,
     FILEGROWTH = 64MB);
GO

-- Set FULL recovery model — REQUIRED for AG
ALTER DATABASE Loans_OnPrem SET RECOVERY FULL;
GO

PRINT 'Step 5.2 complete.';

-- Verify
SELECT 
    name AS DatabaseName,
    recovery_model_desc AS RecoveryModel,
    compatibility_level AS CompatLevel,
    state_desc AS State,
    create_date AS CreateDate
FROM sys.databases
WHERE name = 'Loans_OnPrem';
GO

SELECT 
    DB_NAME(database_id) AS DatabaseName,
    name AS LogicalName,
    physical_name AS PhysicalPath,
    size * 8 / 1024 AS SizeMB,
    type_desc AS FileType
FROM sys.master_files
WHERE database_id = DB_ID('Loans_OnPrem');
GO
