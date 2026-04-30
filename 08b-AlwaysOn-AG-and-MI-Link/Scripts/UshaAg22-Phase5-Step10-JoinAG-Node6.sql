-- =============================================================================
-- UshaAg22-Phase5-Step10-JoinAG-Node6.sql
-- =============================================================================
-- Phase:    5 — Create UshaAg22MI + Banking Schema
-- Step:     5.10 — Join Node6 to UshaAg22MI as async secondary replica
-- Run on:   NODE6 — connect SSMS to Node6 first!
-- Date:     April 28, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Tells Node6's SQL Server instance to JOIN the UshaAg22MI availability
-- group as the async secondary.
--
-- IMPORTANT — POSSIBLE PRE-STEP REQUIRED
-- ---------------------------------------
-- If this script errors with "remote WSFC cluster context" (Msg 19417),
-- it means Node6's SQL Server has stale cluster context — SQL was
-- running BEFORE Node6 joined the cluster, and SQL caches the cluster
-- info at startup. Verify with this query:
--
--   SELECT cluster_name, quorum_type_desc FROM sys.dm_hadr_cluster;
--
-- If cluster_name is empty, restart SQL Server service on Node6 first:
--
--   Restart-Service -ComputerName Node6 -Name MSSQLSERVER -Force
--
-- After restart, sys.dm_hadr_cluster will show Ushaclu22 + 
-- NodeAndFileShareMajority. Then this JOIN script will work.
-- =============================================================================

USE master;
GO

-- Sanity check
DECLARE @ServerName NVARCHAR(128) = CAST(@@SERVERNAME AS NVARCHAR(128));
PRINT 'Current server: ' + @ServerName;

IF @ServerName <> 'NODE6'
BEGIN
    RAISERROR('STOP - This script must run on NODE6. Current server is %s.', 16, 1, @ServerName);
    RETURN;
END
GO

-- Verify Node6's SQL has fresh cluster context (no empty cluster_name)
PRINT 'Verifying SQL cluster context...';
SELECT 
    cluster_name,
    quorum_type_desc,
    quorum_state_desc
FROM sys.dm_hadr_cluster;
GO

-- Join
PRINT 'Joining Node6 to UshaAg22MI...';
ALTER AVAILABILITY GROUP UshaAg22MI JOIN;
GO

PRINT 'Granting CREATE ANY DATABASE for automatic seeding...';
ALTER AVAILABILITY GROUP UshaAg22MI GRANT CREATE ANY DATABASE;
GO

PRINT 'Step 5.10 complete - Node6 joined UshaAg22MI.';
PRINT 'Wait 5-10 seconds, then verify all 3 replicas HEALTHY.';

-- Verify
SELECT 
    ar.replica_server_name,
    ars.role_desc,
    ars.connected_state_desc,
    ars.synchronization_health_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ag.name = 'UshaAg22MI';
GO
