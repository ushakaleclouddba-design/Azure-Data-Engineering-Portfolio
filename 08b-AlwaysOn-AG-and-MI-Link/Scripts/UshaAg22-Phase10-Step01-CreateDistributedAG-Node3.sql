-- =============================================================================
-- UshaAg22-Phase10-Step01-CreateDistributedAG-Node3.sql
-- =============================================================================
-- Phase:    10 — Distributed AG creation
-- Step:     10.1 — Create the DAG on Node3 (UshaAg22MI primary side)
-- Run on:   Node3 (current primary of UshaAg22MI) in SSMS, master DB
-- Date:     April 29, 2026
-- Status:   ✅ This step succeeded
-- =============================================================================
--
-- PURPOSE
-- -------
-- Creates a Distributed Availability Group (UshaAg22DAG) that will link
-- UshaAg22MI to Azure SQL MI. The DAG sits ABOVE both AGs and orchestrates
-- log replication between them.
--
-- ARCHITECTURE
-- ------------
--                Distributed AG (UshaAg22DAG)
--          ┌────────────────┴─────────────────┐
--          ▼                                   ▼
--     UshaAg22MI                         AG_AzureSQLMI
--     (existing AG)                      (auto-created by SQL MI)
--     ┌──────────┐                       ┌────────────────┐
--     │ Node3 PR │                       │ usha-sqlmi-poc │
--     │ Node4 SC │                       │   PRIMARY      │
--     │ Node6 SC │                       │ (only replica) │
--     └──────────┘                       └────────────────┘
--
-- KEY PARAMETERS
-- --------------
-- LISTENER_URL — uses listener (UshaAg22MI-Listener) so cross-DAG comms
--   survive failovers within the on-prem AG. If Node3 fails over to Node4,
--   the DAG keeps working because the listener follows the primary.
--
-- AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT
--   Cross-cloud distance makes sync impractical. Async = some seconds lag.
--
-- FAILOVER_MODE = MANUAL
--   Never auto-failover to Azure. Cutover is a deliberate decision.
--
-- SEEDING_MODE = AUTOMATIC
--   SQL MI auto-pulls initial copy. No manual backup/restore needed.
--
-- WHY THE ;Server=[...] SUFFIX
-- ----------------------------
-- The MI side LISTENER_URL has a suffix: ;Server=[usha-sqlmi-poc]
-- This is MI-specific — tells SQL Server which managed instance is the
-- target within Microsoft's hosting environment. Without this, DAG
-- creation may fail.
-- =============================================================================

USE master;
GO

-- Drop if exists (re-run safety)
IF EXISTS (SELECT 1 FROM sys.availability_groups WHERE name = 'UshaAg22DAG')
BEGIN
    PRINT 'DAG UshaAg22DAG already exists - dropping for clean re-run';
    DROP AVAILABILITY GROUP UshaAg22DAG;
END
GO

-- Create the Distributed Availability Group
PRINT 'Creating Distributed AG UshaAg22DAG...';
PRINT 'This links UshaAg22MI (on-prem) <-> AG_AzureSQLMI (Azure)';

CREATE AVAILABILITY GROUP UshaAg22DAG
    WITH (DISTRIBUTED)
    AVAILABILITY GROUP ON
        'UshaAg22MI' WITH (
            LISTENER_URL = 'tcp://UshaAg22MI-Listener.ushadc.com:5023',
            AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
            FAILOVER_MODE = MANUAL,
            SEEDING_MODE = AUTOMATIC
        ),
        'AG_AzureSQLMI' WITH (
            LISTENER_URL = 'tcp://usha-sqlmi-poc.0f3157bbdbf7.database.windows.net:5022;Server=[usha-sqlmi-poc]',
            AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
            FAILOVER_MODE = MANUAL,
            SEEDING_MODE = AUTOMATIC
        );
GO

PRINT 'Distributed AG created on Node3.';
PRINT 'Next: Step 10.2 should join the DAG from SQL MI side.';
PRINT 'NOTE: Step 10.2 via T-SQL ALTER AVAILABILITY GROUP JOIN is NOT supported on SQL MI.';
PRINT '       Use SSMS MI Link wizard OR PowerShell New-AzSqlInstanceLink instead.';

-- Verify (note: sys.availability_groups does NOT have create_date column)
SELECT 
    name AS AGName,
    is_distributed,
    cluster_type_desc
FROM sys.availability_groups
ORDER BY name;
GO

-- Expected output: 3 AGs visible
--   UshaAg22       is_distributed=0  cluster_type=wsfc
--   UshaAg22MI     is_distributed=0  cluster_type=wsfc
--   UshaAg22DAG    is_distributed=1  cluster_type=none
