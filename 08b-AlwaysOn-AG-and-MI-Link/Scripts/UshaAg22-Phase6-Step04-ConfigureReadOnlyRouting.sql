-- =============================================================================
-- UshaAg22-Phase6-Step04-ConfigureReadOnlyRouting.sql
-- =============================================================================
-- Phase:    6 — Listener + Validation + Failover Test
-- Step:     6.4 — Configure read-only routing for UshaAg22MI
-- Run on:   Node3 (AG primary) in SSMS
-- Date:     April 28, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Read-only routing has TWO parts that must both be configured:
--
-- PART 1: READ_ONLY_ROUTING_URL on each replica
--   Tells the cluster how to actually reach a replica when routing
--   read-intent connections to it. Must be set on EVERY replica.
--   IMPORTANT: URL must use the SQL instance port (1433), NOT the
--   listener port (1435). Listener forwards to SQL; routing connects
--   directly to SQL.
--
-- PART 2: READ_ONLY_ROUTING_LIST on each replica
--   When THIS replica is primary, route read-intent connections to
--   the listed replicas in priority order.
--
-- ROUTING POLICY FOR UshaAg22MI
-- -----------------------------
-- When NODE3 is primary  → route read-intent to NODE6 (async, readable)
-- When NODE4 is primary  → route read-intent to NODE6
-- (NODE6 is async secondary configured with ALLOW_CONNECTIONS = READ_ONLY)
--
-- HOW APPLICATIONS USE THIS
-- -------------------------
-- Connection string: Server=UshaAg22MI-Listener,1435;
--                    Database=Loans_OnPrem;
--                    Integrated Security=true;
--                    ApplicationIntent=ReadOnly;
--                    MultiSubnetFailover=true;
--
-- The ApplicationIntent=ReadOnly is the magic — without it, all
-- connections go to the primary regardless of routing list.
-- =============================================================================

USE master;
GO

-- ---------------------------------------------------------------------
-- PART 1: Set READ_ONLY_ROUTING_URL on each replica (port 1433!)
-- ---------------------------------------------------------------------
PRINT 'Setting READ_ONLY_ROUTING_URL on each replica...';

ALTER AVAILABILITY GROUP UshaAg22MI
    MODIFY REPLICA ON 'NODE3' WITH 
    (SECONDARY_ROLE (READ_ONLY_ROUTING_URL = N'TCP://Node3.ushadc.com:1433'));
GO

ALTER AVAILABILITY GROUP UshaAg22MI
    MODIFY REPLICA ON 'NODE4' WITH 
    (SECONDARY_ROLE (READ_ONLY_ROUTING_URL = N'TCP://Node4.ushadc.com:1433'));
GO

ALTER AVAILABILITY GROUP UshaAg22MI
    MODIFY REPLICA ON 'NODE6' WITH 
    (SECONDARY_ROLE (READ_ONLY_ROUTING_URL = N'TCP://Node6.ushadc.com:1433'));
GO

-- ---------------------------------------------------------------------
-- PART 2: Set READ_ONLY_ROUTING_LIST on potential primary replicas
-- ---------------------------------------------------------------------
PRINT 'Setting READ_ONLY_ROUTING_LIST on each replica...';

-- When Node3 is primary → route reads to Node6
ALTER AVAILABILITY GROUP UshaAg22MI
    MODIFY REPLICA ON 'NODE3' WITH 
    (PRIMARY_ROLE (READ_ONLY_ROUTING_LIST = ('NODE6')));
GO

-- When Node4 is primary → route reads to Node6
ALTER AVAILABILITY GROUP UshaAg22MI
    MODIFY REPLICA ON 'NODE4' WITH 
    (PRIMARY_ROLE (READ_ONLY_ROUTING_LIST = ('NODE6')));
GO

PRINT 'Step 6.4 complete.';

-- Verify routing config
SELECT 
    ar.replica_server_name,
    ar.read_only_routing_url AS ReadOnlyRoutingURL,
    rl.routing_priority,
    ar2.replica_server_name AS RoutesTo
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
LEFT JOIN sys.availability_read_only_routing_lists rl ON ar.replica_id = rl.replica_id
LEFT JOIN sys.availability_replicas ar2 ON rl.read_only_replica_id = ar2.replica_id
WHERE ag.name = 'UshaAg22MI'
ORDER BY ar.replica_server_name, rl.routing_priority;
GO
