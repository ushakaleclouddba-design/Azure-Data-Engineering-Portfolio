-- =============================================================================
-- UshaAg22-Phase6-Step08-Failback-ToNode3.sql
-- =============================================================================
-- Phase:    6 — Listener + Validation + Failover Test
-- Step:     6.8 — Failback Node4 → Node3 (restore Node3 as primary)
-- Run on:   NODE3 (failback target)
-- Date:     April 28, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Restores Node3 as the AG primary after the test failover in Step 6.5.
-- Same FAILOVER command pattern as Step 6.5 but in the reverse direction.
-- Run on the target (Node3 in this case).
--
-- WHY FAIL BACK
-- -------------
-- Two reasons:
-- 1. Returns the cluster to its baseline state (Node3 = primary).
-- 2. Demonstrates that failover is reversible — important for the
--    portfolio story. Day 2's MI Link uses Distributed AGs which also
--    support bidirectional failover, so the on-prem AG works the same way.
--
-- IMPORTANT — secondaries may briefly show NOT_HEALTHY immediately
-- after failback. This is transient: the secondary needs 5-30 seconds
-- to reconnect and resume sync with the new primary. Wait, then
-- re-verify. All replicas should return to HEALTHY.
-- =============================================================================

USE master;
GO

-- Verify we're on Node3
DECLARE @ServerName NVARCHAR(128) = CAST(@@SERVERNAME AS NVARCHAR(128));
PRINT 'Current server: ' + @ServerName;

IF @ServerName <> 'NODE3'
BEGIN
    RAISERROR('STOP - This script must run on Node3 (the failback target).', 16, 1);
    RETURN;
END
GO

-- Show roles BEFORE failback
PRINT '=== Roles BEFORE failback ===';
SELECT 
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_health_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ag.name = 'UshaAg22MI'
ORDER BY ar.replica_server_name;
GO

-- Trigger failback
PRINT '=== Triggering failback to Node3... ===';
ALTER AVAILABILITY GROUP UshaAg22MI FAILOVER;
GO

WAITFOR DELAY '00:00:05';
GO

PRINT '=== Roles AFTER failback ===';
SELECT 
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_health_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ag.name = 'UshaAg22MI'
ORDER BY ar.replica_server_name;
GO

-- If any replica shows NOT_HEALTHY, wait 30s and re-run this query:
PRINT '';
PRINT 'If secondaries show NOT_HEALTHY, wait 30 seconds and re-verify.';
PRINT 'Transient state during reconnect is normal.';
GO
