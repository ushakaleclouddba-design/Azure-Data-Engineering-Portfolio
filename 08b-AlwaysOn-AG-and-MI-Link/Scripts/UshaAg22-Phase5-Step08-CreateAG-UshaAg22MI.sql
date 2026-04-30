-- =============================================================================
-- UshaAg22-Phase5-Step08-CreateAG-UshaAg22MI.sql
-- =============================================================================
-- Phase:    5 — Create UshaAg22MI + Banking Schema
-- Step:     5.8 — Create the UshaAg22MI availability group
-- Run on:   Node3 in SSMS (Node3 is initial primary)
-- Date:     April 28, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Creates UshaAg22MI as a SECOND availability group on the Ushaclu22
-- cluster. Existing UshaAg22 (Node3 ↔ Node4 with HRManagement_OnPrem,
-- Payroll_OnPrem) is unaffected — SQL Server permits multiple AGs on
-- the same cluster and same instance.
--
-- TOPOLOGY DECISIONS
-- ------------------
-- Node3 — initial PRIMARY
--   AVAILABILITY_MODE = SYNCHRONOUS_COMMIT
--   FAILOVER_MODE     = AUTOMATIC
--   SEEDING_MODE      = AUTOMATIC
--
-- Node4 — sync secondary
--   AVAILABILITY_MODE = SYNCHRONOUS_COMMIT
--   FAILOVER_MODE     = AUTOMATIC
--   SEEDING_MODE      = AUTOMATIC
--
-- Node6 — async secondary, read-intent destination
--   AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT
--   FAILOVER_MODE     = MANUAL
--   SEEDING_MODE      = AUTOMATIC
--   ALLOW_CONNECTIONS = READ_ONLY
--
-- AG-LEVEL OPTIONS
-- ----------------
-- AUTOMATED_BACKUP_PREFERENCE = SECONDARY  -- offload backups from primary
-- DB_FAILOVER = ON  -- database-level health detection
-- DTC_SUPPORT = NONE  -- not using distributed transactions in banking demo
--
-- ENDPOINT_URL FORMAT
-- -------------------
-- TCP://<FQDN>:<port> — using FQDN, not short name. SQL Server resolves
-- this through DNS. We use port 5023 to match the existing endpoint.
--
-- WHY THIS DOESN'T BREAK EXISTING UshaAg22
-- ----------------------------------------
-- Multiple AGs on the same cluster + same SQL instance is fully supported.
-- UshaAg22 and UshaAg22MI coexist independently sharing endpoint port 5023
-- but replicating different databases.
-- =============================================================================

USE master;
GO

PRINT 'Creating UshaAg22MI availability group...';

CREATE AVAILABILITY GROUP UshaAg22MI
WITH (
    AUTOMATED_BACKUP_PREFERENCE = SECONDARY,
    DB_FAILOVER = ON,
    DTC_SUPPORT = NONE
)
FOR DATABASE Loans_OnPrem
REPLICA ON
    -- Node3: initial primary, sync auto-failover
    'NODE3' WITH (
        ENDPOINT_URL = 'TCP://Node3.ushadc.com:5023',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = AUTOMATIC,
        BACKUP_PRIORITY = 50,
        SEEDING_MODE = AUTOMATIC,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = NO)
    ),
    -- Node4: sync secondary, auto-failover partner
    'NODE4' WITH (
        ENDPOINT_URL = 'TCP://Node4.ushadc.com:5023',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = AUTOMATIC,
        BACKUP_PRIORITY = 50,
        SEEDING_MODE = AUTOMATIC,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = NO)
    ),
    -- Node6: async secondary, read-intent destination
    'NODE6' WITH (
        ENDPOINT_URL = 'TCP://Node6.ushadc.com:5023',
        AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
        FAILOVER_MODE = MANUAL,
        BACKUP_PRIORITY = 50,
        SEEDING_MODE = AUTOMATIC,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY)
    );
GO

PRINT 'Step 5.8 complete - UshaAg22MI created.';
PRINT 'Next: run Step 5.9 ON NODE4 to JOIN the AG.';
PRINT 'Then: run Step 5.10 ON NODE6 to JOIN the AG.';

-- Verify
SELECT 
    ag.name AS AGName,
    ar.replica_server_name,
    ar.endpoint_url,
    ar.availability_mode_desc,
    ar.failover_mode_desc,
    ar.seeding_mode_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
WHERE ag.name = 'UshaAg22MI'
ORDER BY ar.replica_server_name;
GO
