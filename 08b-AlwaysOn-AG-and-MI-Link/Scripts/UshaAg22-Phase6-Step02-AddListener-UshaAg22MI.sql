-- =============================================================================
-- UshaAg22-Phase6-Step02-AddListener-UshaAg22MI.sql
-- =============================================================================
-- Phase:    6 — Listener + Validation + Failover Test
-- Step:     6.2 — Create UshaAg22MI-Listener (192.168.68.34:1435)
-- Run on:   Node3 (current AG primary) in SSMS
-- Date:     April 28, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Creates the AG listener — a virtual network name that applications
-- use to connect to UshaAg22MI without knowing which physical node is
-- currently the primary. The listener IP "follows" the primary on
-- failover, so connection strings stay constant.
--
-- CHOSEN IP AND PORT
-- ------------------
-- IP   : 192.168.68.34  (free, verified by lab IP scan)
-- Port : 1435           (avoid collision with SQL on 1433 and existing
--                       UshaAg22-Listener on 1434)
-- Mask : 255.255.255.0  (cluster subnet 192.168.68.0/24)
--
-- WHAT GETS CREATED
-- -----------------
-- 1. Virtual Computer Object (VCO) in AD: UshaAg22MI-Listener
--    The cluster CNO (Ushaclu22$) creates this on your behalf.
-- 2. DNS A record: UshaAg22MI-Listener.ushadc.com → 192.168.68.34
-- 3. New Cluster Resource (Network Name + IP + Port) in the
--    UshaAg22MI cluster role
-- 4. Listener entry in SQL Server's metadata
--
-- WHY THIS RUNS ON THE PRIMARY (NODE3)
-- ------------------------------------
-- ALTER AVAILABILITY GROUP commands always go to the primary. The
-- primary then propagates the listener config to all replicas via the
-- AG mechanism.
-- =============================================================================

USE master;
GO

-- Sanity check
DECLARE @ServerName NVARCHAR(128) = CAST(@@SERVERNAME AS NVARCHAR(128));
PRINT 'Current server: ' + @ServerName;

IF @ServerName <> 'NODE3'
BEGIN
    RAISERROR('STOP - This script must run on Node3 (the AG primary).', 16, 1);
    RETURN;
END
GO

-- Add the listener
PRINT 'Adding UshaAg22MI-Listener (192.168.68.34:1435)...';

ALTER AVAILABILITY GROUP UshaAg22MI
ADD LISTENER 'UshaAg22MI-Listener' (
    WITH IP ((N'192.168.68.34', N'255.255.255.0')),
    PORT = 1435
);
GO

PRINT 'Step 6.2 complete - listener created.';

-- Verify
SELECT 
    ag.name AS AGName,
    agl.dns_name AS ListenerName,
    aglip.ip_address,
    aglip.ip_subnet_mask,
    agl.port
FROM sys.availability_groups ag
JOIN sys.availability_group_listeners agl ON ag.group_id = agl.group_id
JOIN sys.availability_group_listener_ip_addresses aglip ON agl.listener_id = aglip.listener_id
WHERE ag.name = 'UshaAg22MI';
GO
