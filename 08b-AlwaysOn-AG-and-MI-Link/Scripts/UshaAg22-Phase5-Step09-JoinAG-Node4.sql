-- =============================================================================
-- UshaAg22-Phase5-Step09-JoinAG-Node4.sql
-- =============================================================================
-- Phase:    5 — Create UshaAg22MI + Banking Schema
-- Step:     5.9 — Join Node4 to UshaAg22MI as a secondary replica
-- Run on:   NODE4 (NOT Node3) — connect SSMS to Node4 first!
-- Date:     April 28, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Tells Node4's SQL Server instance to JOIN the UshaAg22MI availability
-- group. Until this runs, Node4 doesn't know it's a secondary replica.
--
-- WHAT JOIN DOES
-- --------------
-- 1. Establishes mirror endpoint connection from Node4 to Node3 over
--    port 5023 (TCP/AES-encrypted)
-- 2. Subscribes to the AG's transaction log stream
-- 3. Sets the local SQL instance as a participating replica
-- 4. Cluster resource gets updated to track Node4's state
--
-- WHY GRANT CREATE ANY DATABASE IS REQUIRED
-- -----------------------------------------
-- SEEDING_MODE = AUTOMATIC means Node3 will stream Loans_OnPrem directly
-- to Node4 over the AG endpoint. For SQL Server to allow Node4 to RECEIVE
-- that stream and create the database files locally, it needs CREATE ANY
-- DATABASE permission. Without this GRANT, the database appears stuck
-- "Synchronizing" forever with no error message.
-- =============================================================================

USE master;
GO

-- Sanity check: confirm we're on Node4
DECLARE @ServerName NVARCHAR(128) = CAST(@@SERVERNAME AS NVARCHAR(128));
PRINT 'Current server: ' + @ServerName;

IF @ServerName <> 'NODE4'
BEGIN
    RAISERROR('STOP - This script must run on NODE4. Current server is %s.', 16, 1, @ServerName);
    RETURN;
END
GO

-- Join Node4 to UshaAg22MI
PRINT 'Joining Node4 to UshaAg22MI...';
ALTER AVAILABILITY GROUP UshaAg22MI JOIN;
GO

-- Grant CREATE ANY DATABASE for automatic seeding
PRINT 'Granting CREATE ANY DATABASE for automatic seeding...';
ALTER AVAILABILITY GROUP UshaAg22MI GRANT CREATE ANY DATABASE;
GO

PRINT 'Step 5.9 complete - Node4 joined UshaAg22MI.';
PRINT 'Wait 5-10 seconds for join to fully complete, then verify.';

-- Verify
SELECT 
    ar.replica_server_name,
    ars.role_desc,
    ars.connected_state_desc,
    ars.synchronization_health_desc,
    ars.operational_state_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ag.name = 'UshaAg22MI';
GO
