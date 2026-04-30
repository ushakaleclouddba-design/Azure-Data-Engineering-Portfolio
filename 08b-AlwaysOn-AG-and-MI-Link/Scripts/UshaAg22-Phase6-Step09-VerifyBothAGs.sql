-- =============================================================================
-- UshaAg22-Phase6-Step09-VerifyBothAGs.sql
-- =============================================================================
-- Phase:    6 — Listener + Validation + Failover Test
-- Step:     6.9 — Verify existing UshaAg22 still healthy after all operations
-- Run on:   Node3 in SSMS
-- Date:     April 28, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Final verification that the brownfield extension didn't disturb the
-- existing UshaAg22 (HRManagement_OnPrem + Payroll_OnPrem). Shows both
-- AGs side-by-side with full health status — the visual proof that the
-- entire build was non-destructive.
--
-- WHAT WE'RE LOOKING FOR
-- ----------------------
-- Result set 1 (replicas):
--   - UshaAg22:    Node3 + Node4, both HEALTHY, both CONNECTED
--   - UshaAg22MI:  Node3 + Node4 + Node6, all HEALTHY, all CONNECTED
--
-- Result set 2 (databases):
--   - HRManagement_OnPrem:  SYNCHRONIZED on both replicas
--   - Payroll_OnPrem:       SYNCHRONIZED on both replicas
--   - Loans_OnPrem:         SYNCHRONIZED on Node3+Node4 (sync replicas)
--                           SYNCHRONIZING on Node6 (async replica - normal)
--
-- ASYNC REPLICAS SHOW SYNCHRONIZING NOT SYNCHRONIZED
-- --------------------------------------------------
-- Node6's Loans_OnPrem will perpetually show "SYNCHRONIZING" rather than
-- "SYNCHRONIZED" — this is correct behavior for ASYNCHRONOUS_COMMIT replicas.
-- They're always catching up with primary, never strictly in lock-step.
-- HEALTHY here just means the connection is working and lag is acceptable.
-- =============================================================================

-- Check both AGs side by side
SELECT 
    ag.name AS AGName,
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_health_desc,
    ars.connected_state_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
ORDER BY ag.name, ar.replica_server_name;

-- Check all AG databases
SELECT 
    DB_NAME(drs.database_id) AS DatabaseName,
    ag.name AS AGName,
    ar.replica_server_name,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.is_primary_replica
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
JOIN sys.availability_groups ag ON ar.group_id = ag.group_id
ORDER BY ag.name, drs.is_primary_replica DESC, ar.replica_server_name;
GO
