-- =============================================================================
-- UshaAg22-Phase6-Step05-PlannedFailover-ToNode4.sql
-- =============================================================================
-- Phase:    6 — Listener + Validation + Failover Test
-- Step:     6.5 — Planned failover Node3 → Node4
-- Run on:   NODE4 (failover TARGET — not Node3!)
-- Date:     April 28, 2026
-- =============================================================================
--
-- WHY THIS RUNS ON NODE4
-- ----------------------
-- Failover commands run on the replica that will BECOME the new primary,
-- not on the current primary. Logic: the new primary needs to assert
-- itself; running this on Node3 (current primary) would be the equivalent
-- of asking "should I demote myself?" — SQL doesn't work that way.
--
-- WHAT FAILOVER DOES
-- ------------------
-- 1. Node4 sends a "ready to be primary" message to the cluster
-- 2. Cluster verifies all sync secondaries are caught up (zero data loss)
-- 3. Node3 transitions Loans_OnPrem from PRIMARY to SECONDARY role
-- 4. Node4 transitions Loans_OnPrem from SECONDARY to PRIMARY role
-- 5. Cluster moves the listener IP (192.168.68.34) to Node4
-- 6. Apps using UshaAg22MI-Listener experience a brief reconnect (~5s)
--
-- SAFETY: SYNC + AUTOMATIC FAILOVER MODE
-- --------------------------------------
-- Node3 and Node4 are SYNCHRONOUS_COMMIT with FAILOVER_MODE = AUTOMATIC.
-- Sync mode guarantees zero data loss because Node4 acks every transaction
-- before the primary commits.
--
-- WHAT NODE6 DOES DURING FAILOVER
-- -------------------------------
-- Node6 is async / manual failover. It's not involved in the failover
-- decision. It will reconnect to the new primary (Node4) afterwards
-- and continue pulling logs asynchronously.
--
-- EXISTING UshaAg22 IS UNAFFECTED
-- -------------------------------
-- This failover targets ONLY UshaAg22MI. The other AG (UshaAg22 with
-- HRManagement_OnPrem + Payroll_OnPrem) doesn't move.
-- =============================================================================

USE master;
GO

-- Sanity check: confirm we're on Node4
DECLARE @ServerName NVARCHAR(128) = CAST(@@SERVERNAME AS NVARCHAR(128));
PRINT 'Current server: ' + @ServerName;

IF @ServerName <> 'NODE4'
BEGIN
    RAISERROR('STOP - This script must run on Node4 (the failover TARGET).', 16, 1);
    RETURN;
END
GO

-- Show roles BEFORE failover
PRINT '=== Roles BEFORE failover ===';
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

-- Trigger planned failover
PRINT '=== Triggering failover... ===';
ALTER AVAILABILITY GROUP UshaAg22MI FAILOVER;
GO

PRINT '=== Failover complete. Wait 5 seconds, then verify roles. ===';
WAITFOR DELAY '00:00:05';
GO

-- Show roles AFTER failover
PRINT '=== Roles AFTER failover ===';
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
