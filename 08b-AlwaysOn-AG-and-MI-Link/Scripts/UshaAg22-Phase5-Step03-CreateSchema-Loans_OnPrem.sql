-- =============================================================================
-- UshaAg22-Phase5-Step03-CreateSchema-Loans_OnPrem.sql
-- =============================================================================
-- Phase:    5 — Create UshaAg22MI + Banking Schema
-- Step:     5.3 — Create banking schema (Customers, Loans, Transactions)
-- Run on:   Node3 in SSMS, connected to Loans_OnPrem database
-- Date:     April 28, 2026
-- =============================================================================
--
-- IMPORTANT: VERIFY DATABASE CONTEXT BEFORE F5
--
--   The first line of this script is "USE Loans_OnPrem; GO" but SSMS may
--   not pick it up if your query window is connected to "master" by default.
--   Always check the database dropdown at the top of SSMS — it should say
--   "Loans_OnPrem" before you press F5.
--
--   Or run this first to confirm:
--     SELECT DB_NAME();
--   Expected: Loans_OnPrem
--
--   Running against master will create these tables in master, polluting
--   the system database. There's a cleanup script for that scenario, but
--   it's better to avoid the issue entirely by checking context first.
-- =============================================================================
--
-- PURPOSE
-- -------
-- Creates a realistic banking schema in Loans_OnPrem to serve as the
-- migration payload for Day 2's MI Link POC. The schema mirrors what a
-- regional bank loan-origination system would actually look like, with
-- the three core entities and proper foreign key relationships.
--
-- TABLE STRUCTURE
-- ---------------
-- Customers (parent table)
--   CustomerID, FirstName, LastName, Email, Phone, CreatedDate
--
-- Loans (depends on Customers)
--   LoanID, CustomerID FK, Principal, InterestRate, TermMonths,
--   OriginationDate, Status
--
-- Transactions (depends on Loans)
--   TransactionID BIGINT (because transactions accumulate fast)
--   LoanID FK, TransactionDate, Amount, TransactionType
--
-- DESIGN CHOICES
-- --------------
-- 1. Foreign keys enforced — referential integrity must survive failover
-- 2. DECIMAL(18,2) for money — prevents float rounding errors
-- 3. NVARCHAR for text — international-ready (Unicode)
-- 4. DATETIME2 over DATETIME — higher precision (100ns vs 3.33ms)
-- 5. SYSUTCDATETIME() default — UTC, critical for Azure migration
-- 6. No row counts inserted here — Step 5.4 inserts seed data separately
--
-- IDEMPOTENCY
-- -----------
-- Tables are dropped if they exist (in FK-aware order: Transactions,
-- Loans, Customers — children before parents).
--
-- DAY 2 RELEVANCE
-- ---------------
-- This exact schema gets replicated to Azure SQL MI via MI Link. All
-- datatypes used here are MI-compatible by design (no FILESTREAM, no
-- SQL CLR types, no FileTable, etc).
-- =============================================================================

USE Loans_OnPrem;
GO

-- Sanity check
PRINT 'Current database: ' + DB_NAME();
IF DB_NAME() <> 'Loans_OnPrem'
BEGIN
    RAISERROR('STOP - Not in Loans_OnPrem database. Switch context and re-run.', 16, 1);
    RETURN;
END
GO

PRINT 'Creating banking schema in Loans_OnPrem...';

-- Drop existing tables in FK-aware order (children first)
IF OBJECT_ID('dbo.Transactions') IS NOT NULL DROP TABLE dbo.Transactions;
IF OBJECT_ID('dbo.Loans')        IS NOT NULL DROP TABLE dbo.Loans;
IF OBJECT_ID('dbo.Customers')    IS NOT NULL DROP TABLE dbo.Customers;
GO

-- Customers — parent table
CREATE TABLE dbo.Customers (
    CustomerID  INT IDENTITY(1,1) NOT NULL,
    FirstName   NVARCHAR(50)      NOT NULL,
    LastName    NVARCHAR(50)      NOT NULL,
    Email       NVARCHAR(100)     NULL,
    Phone       NVARCHAR(20)      NULL,
    CreatedDate DATETIME2(3)      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Customers PRIMARY KEY CLUSTERED (CustomerID)
);
GO

-- Loans — depends on Customers
CREATE TABLE dbo.Loans (
    LoanID          INT IDENTITY(1,1) NOT NULL,
    CustomerID      INT               NOT NULL,
    Principal       DECIMAL(18,2)     NOT NULL,
    InterestRate    DECIMAL(5,2)      NOT NULL,
    TermMonths      INT               NOT NULL,
    OriginationDate DATE              NOT NULL,
    Status          NVARCHAR(20)      NOT NULL DEFAULT 'Active',
    CONSTRAINT PK_Loans PRIMARY KEY CLUSTERED (LoanID),
    CONSTRAINT FK_Loans_Customers FOREIGN KEY (CustomerID)
        REFERENCES dbo.Customers(CustomerID)
);
GO

-- Transactions — depends on Loans
CREATE TABLE dbo.Transactions (
    TransactionID   BIGINT IDENTITY(1,1) NOT NULL,
    LoanID          INT                  NOT NULL,
    TransactionDate DATETIME2(3)         NOT NULL DEFAULT SYSUTCDATETIME(),
    Amount          DECIMAL(18,2)        NOT NULL,
    TransactionType NVARCHAR(20)         NOT NULL,
    CONSTRAINT PK_Transactions PRIMARY KEY CLUSTERED (TransactionID),
    CONSTRAINT FK_Transactions_Loans FOREIGN KEY (LoanID)
        REFERENCES dbo.Loans(LoanID)
);
GO

PRINT 'Step 5.3 complete - banking schema created.';

-- Verify
SELECT 
    t.name AS TableName,
    p.rows AS RowCnt,
    SUM(a.total_pages) * 8 AS SizeKB
FROM sys.tables t
JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE t.name IN ('Customers', 'Loans', 'Transactions')
GROUP BY t.name, p.rows
ORDER BY t.name;
GO
