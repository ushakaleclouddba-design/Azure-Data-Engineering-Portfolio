-- =============================================================================
-- UshaAg22-Phase4-Step04-CreateEndpoint-Node6.sql
-- =============================================================================
-- Phase:    4 — Enable AlwaysOn + Endpoint on Node6
-- Step:     4.4 — Create HADR_Endpoint on Node6 (port 5023)
-- Run on:   Node6 in SSMS (or sqlcmd -S Node6)
-- Date:     April 28, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Creates the HADR (High Availability Disaster Recovery) endpoint on
-- Node6. This is the TCP listener inside SQL Server that AG replicas
-- use to send/receive transaction log blocks between each other.
--
-- WHY PORT 5023 (not the textbook 5022)
-- --------------------------------------
-- Node3 and Node4 already have HADR_Endpoint on port 5023 from the
-- existing UshaAg22 build. Node6 must match for the new UshaAg22MI
-- to use a consistent endpoint across all 3 replicas.
--
-- ENCRYPTION
-- ----------
-- AES encryption is REQUIRED. Microsoft requires this for production
-- HADR endpoints because log blocks contain user data including PII.
-- Without encryption, log replication is sent over the network in
-- plain text — never acceptable in a banking context.
--
-- AUTHENTICATION
-- --------------
-- WINDOWS NEGOTIATE means the endpoint authenticates using the SQL
-- Server service accounts via Kerberos. Since Node3/4/6 all run SQL
-- under USHADC0\ushakale (verified Phase 1), they trust each other
-- automatically without certificates. Cert-based auth is what MI
-- Link adds in Day 2 — that's a SEPARATE endpoint for the DAG to
-- Azure SQL MI, on a different port.
--
-- ENDPOINT OWNERSHIP
-- ------------------
-- Whoever runs CREATE ENDPOINT becomes the OWNER of that endpoint and
-- has implicit full permissions on it. Since this script is run as
-- USHADC0\ushakale (the SQL service account), no separate GRANT
-- CONNECT is needed for that account — they own the endpoint.
-- =============================================================================

USE master;
GO

-- Drop endpoint if it already exists (re-run safety)
IF EXISTS (SELECT 1 FROM sys.tcp_endpoints WHERE name = 'HADR_Endpoint')
BEGIN
    PRINT 'HADR_Endpoint already exists — dropping and recreating';
    DROP ENDPOINT HADR_Endpoint;
END
GO

-- Create the endpoint
CREATE ENDPOINT HADR_Endpoint
    STATE = STARTED
    AS TCP (
        LISTENER_PORT = 5023,
        LISTENER_IP = ALL
    )
    FOR DATA_MIRRORING (
        ROLE = ALL,
        AUTHENTICATION = WINDOWS NEGOTIATE,
        ENCRYPTION = REQUIRED ALGORITHM AES
    );
GO

-- Verify
PRINT 'HADR_Endpoint configuration:';
SELECT 
    name,
    type_desc,
    state_desc,
    port,
    is_dynamic_port
FROM sys.tcp_endpoints
WHERE type_desc = 'DATABASE_MIRRORING';
GO

-- Verify owner
PRINT 'Endpoint owner:';
SELECT 
    e.name AS EndpointName,
    sp.name AS Owner,
    e.state_desc,
    e.protocol_desc
FROM sys.endpoints e
JOIN sys.server_principals sp ON e.principal_id = sp.principal_id
WHERE e.type_desc = 'DATABASE_MIRRORING';
GO

PRINT 'Step 4.4 complete.';
GO
