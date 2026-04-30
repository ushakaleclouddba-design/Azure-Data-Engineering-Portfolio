-- =============================================================================
-- UshaAg22-Phase5-Step04-SeedData-Loans_OnPrem.sql
-- =============================================================================
-- Phase:    5 — Create UshaAg22MI + Banking Schema
-- Step:     5.4 — Insert seed data into Customers, Loans, Transactions
-- Run on:   Node3 in SSMS, connected to Loans_OnPrem
-- Date:     April 28, 2026
-- =============================================================================
--
-- IMPORTANT: Verify SSMS database dropdown shows "Loans_OnPrem" before F5.
--            Or check by running:  SELECT DB_NAME();
--            Expected output:      Loans_OnPrem
-- =============================================================================
--
-- PURPOSE
-- -------
-- Populates Loans_OnPrem with realistic banking data:
--   - 1,000 Customers
--   - 2,000 Loans (each customer has ~2 loans on average)
--   - 5,000 Transactions (each loan has ~2.5 transactions on average)
--
-- DATA GENERATION TECHNIQUE
-- -------------------------
-- Cross joins sys.all_objects with itself (typically returns ~50K combinations
-- on a fresh SQL instance) then TOP N to limit rows. ROW_NUMBER() OVER
-- (ORDER BY (SELECT NULL)) generates sequential numbers without sorting cost.
-- Random distributions use ABS(CHECKSUM(NEWID())) % N for fast pseudo-random
-- integers without RAND()'s repeating-seed problem.
--
-- WHY CASE INSTEAD OF CHOOSE
-- --------------------------
-- Original implementation used CHOOSE() but hit "Cannot insert NULL" errors
-- because the SQL optimizer can re-evaluate NEWID() within a single row,
-- producing different values for the index calculation vs. when CHOOSE
-- actually executes. CASE WHEN doesn't have this problem because each
-- branch is a discrete literal.
--
-- IDEMPOTENCY
-- -----------
-- Tables are TRUNCATED before insert so re-running gives consistent
-- results. DBCC CHECKIDENT resets IDENTITY values back to 1.
-- =============================================================================

USE Loans_OnPrem;
GO

PRINT 'Current database: ' + DB_NAME();
GO

-- Truncate in FK-aware order (children first)
PRINT 'Clearing tables...';
DELETE FROM dbo.Transactions;
DELETE FROM dbo.Loans;
DELETE FROM dbo.Customers;
DBCC CHECKIDENT ('dbo.Customers',    RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dbo.Loans',        RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dbo.Transactions', RESEED, 0) WITH NO_INFOMSGS;
GO

-- ---------------------------------------------------------------------
-- 1,000 Customers
-- ---------------------------------------------------------------------
PRINT 'Inserting 1,000 Customers...';
INSERT INTO dbo.Customers (FirstName, LastName, Email, Phone)
SELECT TOP 1000
    'First' + CAST(rn AS NVARCHAR(10)),
    'Last'  + CAST(rn AS NVARCHAR(10)),
    'cust' + CAST(rn AS NVARCHAR(10)) + '@bank.example.com',
    '925-555-' + RIGHT('0000' + CAST(rn AS NVARCHAR(4)), 4)
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
) src;
GO

-- ---------------------------------------------------------------------
-- 2,000 Loans — using CASE instead of CHOOSE to avoid NULL bug
-- ---------------------------------------------------------------------
PRINT 'Inserting 2,000 Loans...';
INSERT INTO dbo.Loans (CustomerID, Principal, InterestRate, TermMonths, OriginationDate, Status)
SELECT TOP 2000
    ABS(CHECKSUM(NEWID())) % 1000 + 1                                              AS CustomerID,
    50000 + (ABS(CHECKSUM(NEWID())) % 250000)                                      AS Principal,
    3.5 + (ABS(CHECKSUM(NEWID())) % 50) / 10.0                                     AS InterestRate,
    CASE ABS(CHECKSUM(NEWID())) % 4
        WHEN 0 THEN 60
        WHEN 1 THEN 120
        WHEN 2 THEN 180
        ELSE 360
    END                                                                            AS TermMonths,
    DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 1825), CAST(SYSUTCDATETIME() AS DATE)) AS OriginationDate,
    CASE ABS(CHECKSUM(NEWID())) % 3
        WHEN 0 THEN 'Active'
        WHEN 1 THEN 'Paid'
        ELSE 'Default'
    END                                                                            AS Status
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
) src;
GO

-- ---------------------------------------------------------------------
-- 5,000 Transactions
-- ---------------------------------------------------------------------
PRINT 'Inserting 5,000 Transactions...';
INSERT INTO dbo.Transactions (LoanID, TransactionDate, Amount, TransactionType)
SELECT TOP 5000
    ABS(CHECKSUM(NEWID())) % 2000 + 1                                AS LoanID,
    DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 365), SYSUTCDATETIME())  AS TransactionDate,
    100 + (ABS(CHECKSUM(NEWID())) % 5000)                            AS Amount,
    CASE ABS(CHECKSUM(NEWID())) % 3
        WHEN 0 THEN 'Payment'
        WHEN 1 THEN 'Interest'
        ELSE 'Fee'
    END                                                              AS TransactionType
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
) src;
GO

PRINT 'Step 5.4 complete.';

-- Verify
SELECT 'Customers'    AS Tbl, COUNT(*) AS RowCnt FROM dbo.Customers
UNION ALL SELECT 'Loans',        COUNT(*) FROM dbo.Loans
UNION ALL SELECT 'Transactions', COUNT(*) FROM dbo.Transactions;
GO
