-- =============================================================================
-- UshaAg22-Phase9-Step01-AlterEndpointDualAuth-Node3.sql
-- =============================================================================
-- Phase:    9 — Cert-based mirroring endpoint
-- Step:     9.1 — Modify existing endpoint to support dual authentication
-- Run on:   Node3 in SSMS, master database
-- Date:     April 29, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Adds CERTIFICATE authentication to the existing HADR_Endpoint on port 5023,
-- alongside its existing Windows authentication. After this, the same endpoint
-- accepts BOTH:
--   - Windows auth from Node4/Node6 (existing UshaAg22MI internal AG)
--   - Certificate auth from SQL MI (new MI Link traffic)
--
-- WHY ALTER INSTEAD OF CREATE A SECOND ENDPOINT
-- ----------------------------------------------
-- SQL Server allows ONLY ONE database mirroring endpoint per instance,
-- regardless of port or auth method. Attempting to CREATE ENDPOINT with
-- AUTHENTICATION = CERTIFICATE on port 5022 fails with:
--   Msg 7862: An endpoint of the requested type already exists.
--             Only one endpoint of this type is supported.
--
-- The Microsoft-recommended pattern is dual auth on the existing endpoint.
--
-- KEYWORD COMBINATION
-- -------------------
-- AUTHENTICATION = WINDOWS NEGOTIATE CERTIFICATE <cert_name>
-- This single line tells SQL Server to accept either Windows OR certificate
-- authentication, choosing whichever the connecting party presents.
--
-- DOES THIS BREAK EXISTING UshaAg22MI?
-- ------------------------------------
-- No. ALTER ENDPOINT just ADDS the cert auth capability. The Windows auth
-- behavior is preserved unchanged. Existing AG replication (Node3 ↔ Node4
-- ↔ Node6) continues working without interruption.
-- =============================================================================

USE master;
GO

-- View current endpoint state
PRINT '=== BEFORE: Current HADR_Endpoint configuration ===';
SELECT 
    e.name AS EndpointName,
    te.port,
    dme.role_desc,
    dme.is_encryption_enabled,
    dme.encryption_algorithm_desc,
    CASE 
        WHEN dme.certificate_id > 0 THEN 'Cert: ' + cert.name
        ELSE 'Windows only'
    END AS CurrentAuth
FROM sys.tcp_endpoints te
JOIN sys.endpoints e ON te.endpoint_id = e.endpoint_id
JOIN sys.database_mirroring_endpoints dme ON e.endpoint_id = dme.endpoint_id
LEFT JOIN sys.certificates cert ON dme.certificate_id = cert.certificate_id
WHERE e.type_desc = 'DATABASE_MIRRORING';
GO

-- Modify to support BOTH authentication methods
PRINT '=== Modifying HADR_Endpoint to support BOTH auth methods ===';
ALTER ENDPOINT HADR_Endpoint
    FOR DATABASE_MIRRORING (
        ROLE = ALL,
        AUTHENTICATION = WINDOWS NEGOTIATE CERTIFICATE Node3_MILink_Cert,
        ENCRYPTION = REQUIRED ALGORITHM AES
    );
GO

-- Verify the change
PRINT '=== AFTER: Updated HADR_Endpoint configuration ===';
SELECT 
    e.name AS EndpointName,
    te.port,
    dme.role_desc,
    dme.is_encryption_enabled,
    dme.encryption_algorithm_desc,
    CASE 
        WHEN dme.certificate_id > 0 THEN 'Windows + Cert: ' + cert.name
        ELSE 'Windows only'
    END AS NewAuth
FROM sys.tcp_endpoints te
JOIN sys.endpoints e ON te.endpoint_id = e.endpoint_id
JOIN sys.database_mirroring_endpoints dme ON e.endpoint_id = dme.endpoint_id
LEFT JOIN sys.certificates cert ON dme.certificate_id = cert.certificate_id
WHERE e.type_desc = 'DATABASE_MIRRORING';
GO

-- Expected result: NewAuth = 'Windows + Cert: Node3_MILink_Cert' on port 5023
