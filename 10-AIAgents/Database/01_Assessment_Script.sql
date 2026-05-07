/* ============================================================================
   SQL SERVER CLOUD MIGRATION FIT ASSESSMENT — FULL REPORT
   ----------------------------------------------------------------------------
   Author:    Usha Kale
   Mode:      READ-ONLY. Safe for production.
   Designed:  Single file. Runs in SSMS, including via CMS multi-server query.
   ----------------------------------------------------------------------------
   What this script produces (15 result sets, in order):

     RS  Section                        Purpose
     --  -----------------------------  -----------------------------------------
      1  Instance Summary               Edition, version, CU, auth mode, HADR
      2  Instance Configuration         xp_cmdshell, OLE Automation, CLR, etc.
      3  Linked Servers                 With provider + MI compatibility flag
      4  SQL Agent Jobs                 Subsystem analysis (CmdExec/PoSh/SSIS)
      5  Database Inventory             Format version, compat, size, TDE
      6  Database-Level Findings        FileStream, In-Memory, Temporal, CDC...
      7  T-SQL Code Scan                Risky patterns inside stored procedures
      8  Per-DB SKU Features            sys.dm_db_persisted_sku_features
      9  CLR Assemblies                 UNSAFE / EXTERNAL_ACCESS detection
     10  Database Files                 Physical layout + FileStream/FileTable
     11  Availability Groups            AG / DAG full topology
     12  Database Mirroring             Legacy DBM partners
     13  Log Shipping                   Primary + secondary configs
     14  Replication                    Publishers / Publications
     15  Cloud Migration Matrix         Yes/No per target with reasoning
                                          - Azure VM / Managed Instance / SQL DB
                                          - AWS EC2 / RDS for SQL Server
                                          - GCP Compute / Cloud SQL for SQL Server
                                        Plus MI-Link-specific format verdict.

   ----------------------------------------------------------------------------
   How to run via CMS:
     1. Right-click your CMS server group → New Query
     2. Tools → Options → Query Results → SQL Server → Multiserver Results
        ✓ Add server name to results, ✓ Merge results
     3. Paste this whole script and press F5
     4. Each result set arrives merged across all registered servers, with
        a "Server Name" column prepended automatically by SSMS.
============================================================================ */

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

----------------------------------------------------------------------------
-- Setup: shared findings table used across multiple sections
----------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Findings') IS NOT NULL DROP TABLE #Findings;
IF OBJECT_ID('tempdb..#SkuFeatures') IS NOT NULL DROP TABLE #SkuFeatures;
IF OBJECT_ID('tempdb..#CLR') IS NOT NULL DROP TABLE #CLR;
IF OBJECT_ID('tempdb..#CodeScan') IS NOT NULL DROP TABLE #CodeScan;
IF OBJECT_ID('tempdb..#Matrix') IS NOT NULL DROP TABLE #Matrix;

CREATE TABLE #Findings (
    FindingID    INT IDENTITY(1,1),
    ScopeType    VARCHAR(30),
    ScopeName    SYSNAME NULL,
    Category     VARCHAR(100),
    Severity     VARCHAR(10),
    Finding      VARCHAR(4000)
);

CREATE TABLE #SkuFeatures (
    DatabaseName SYSNAME,
    FeatureName  SYSNAME,
    Severity     VARCHAR(10),
    Note         VARCHAR(400)
);

CREATE TABLE #CLR (
    DatabaseName  SYSNAME,
    AssemblyName  SYSNAME,
    PermissionSet VARCHAR(50),
    IsUserDefined BIT,
    Verdict       VARCHAR(80)
);

CREATE TABLE #CodeScan (
    DatabaseName SYSNAME,
    SchemaName   SYSNAME NULL,
    ObjectName   SYSNAME NULL,
    ObjectType   VARCHAR(20),
    RiskPattern  VARCHAR(50),
    Severity     VARCHAR(10)
);

CREATE TABLE #Matrix (
    TargetPlatform VARCHAR(60),
    Fit            VARCHAR(10),
    Reason         VARCHAR(4000)
);

DECLARE
    @ProductVersion       VARCHAR(50)  = CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50)),
    @ProductMajorVersion  INT          = TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT),
    @Edition              VARCHAR(200) = CAST(SERVERPROPERTY('Edition') AS VARCHAR(200)),
    @ProductLevel         VARCHAR(50)  = CAST(SERVERPROPERTY('ProductLevel') AS VARCHAR(50));

----------------------------------------------------------------------------
-- RS 1: Instance Summary
----------------------------------------------------------------------------
SELECT
    '01_Instance_Summary'                                              AS Section,
    @@SERVERNAME                                                       AS ServerName,
    CAST(SERVERPROPERTY('MachineName')                  AS sysname)    AS MachineName,
    CAST(SERVERPROPERTY('InstanceName')                 AS sysname)    AS InstanceName,
    @Edition                                                           AS Edition,
    @ProductVersion                                                    AS ProductVersion,
    @ProductLevel                                                      AS ProductLevel,
    CAST(SERVERPROPERTY('ProductUpdateLevel')           AS sysname)    AS CULevel,
    CAST(SERVERPROPERTY('Collation')                    AS sysname)    AS ServerCollation,
    CASE SERVERPROPERTY('IsClustered')        WHEN 1 THEN 'Yes' ELSE 'No' END AS IsClustered,
    CASE SERVERPROPERTY('IsHadrEnabled')      WHEN 1 THEN 'Yes' ELSE 'No' END AS HadrEnabled,
    CASE SERVERPROPERTY('IsIntegratedSecurityOnly')
         WHEN 1 THEN 'Windows-only' ELSE 'Mixed Mode' END              AS AuthMode,
    (SELECT COUNT(*) FROM sys.databases WHERE database_id > 4)         AS UserDatabaseCount,
    (SELECT COUNT(*) FROM sys.servers   WHERE is_linked = 1)           AS LinkedServerCount,
    (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE enabled = 1)          AS EnabledAgentJobs,
    SYSDATETIME()                                                      AS AssessedAt;

----------------------------------------------------------------------------
-- Build #Findings (instance-level)
----------------------------------------------------------------------------
IF @ProductMajorVersion < 11
INSERT INTO #Findings VALUES
('Instance', @@SERVERNAME, 'Version', 'High',
 'SQL Server version is older than 2012. Most managed cloud targets will not accept it directly.');

IF @Edition LIKE '%Express%'
INSERT INTO #Findings VALUES
('Instance', @@SERVERNAME, 'Edition', 'Medium',
 'Source is SQL Server Express. Verify size limits and Agent dependencies before any managed migration.');

INSERT INTO #Findings
SELECT 'Instance', @@SERVERNAME, 'Server Configuration', 'High',
       'xp_cmdshell is ENABLED. Generally requires redesign for managed/hosted SQL platforms.'
FROM sys.configurations WHERE name = 'xp_cmdshell' AND value_in_use = 1;

INSERT INTO #Findings
SELECT 'Instance', @@SERVERNAME, 'Server Configuration', 'High',
       'Ole Automation Procedures are ENABLED. Restricted/unsupported on most managed SQL platforms.'
FROM sys.configurations WHERE name = 'Ole Automation Procedures' AND value_in_use = 1;

INSERT INTO #Findings
SELECT 'Instance', @@SERVERNAME, 'Server Configuration', 'Medium',
       'Ad Hoc Distributed Queries ENABLED. Audit OPENROWSET / OPENDATASOURCE usage.'
FROM sys.configurations WHERE name = 'Ad Hoc Distributed Queries' AND value_in_use = 1;

INSERT INTO #Findings
SELECT 'Instance', @@SERVERNAME, 'Server Configuration', 'Medium',
       'CLR ENABLED at server level. Validate assemblies and PERMISSION_SET levels.'
FROM sys.configurations WHERE name = 'clr enabled' AND value_in_use = 1;

INSERT INTO #Findings
SELECT 'Instance', name, 'Linked Servers', 'High',
       'Linked server: ' + name + '. Cross-server queries often need redesign on managed platforms.'
FROM sys.servers WHERE is_linked = 1;

----------------------------------------------------------------------------
-- RS 2: Instance Configuration (key sp_configure values relevant to MI/cloud)
----------------------------------------------------------------------------
SELECT
    '02_Instance_Configuration' AS Section,
    name                        AS ConfigName,
    value_in_use                AS ValueInUse,
    description                 AS Description,
    CASE
        WHEN name = 'xp_cmdshell'                AND value_in_use = 1 THEN 'High — usually unsupported on managed SQL'
        WHEN name = 'Ole Automation Procedures'  AND value_in_use = 1 THEN 'High — usually unsupported on managed SQL'
        WHEN name = 'Ad Hoc Distributed Queries' AND value_in_use = 1 THEN 'Medium — review OPENROWSET usage'
        WHEN name = 'clr enabled'                AND value_in_use = 1 THEN 'Medium — review CLR assemblies'
        WHEN name = 'remote access'              AND value_in_use = 1 THEN 'Info — RPC; review for managed targets'
        ELSE 'Info'
    END AS MIRelevance
FROM sys.configurations
WHERE name IN (
    'xp_cmdshell','Ole Automation Procedures','Ad Hoc Distributed Queries','clr enabled',
    'remote access','backup compression default','optimize for ad hoc workloads',
    'cost threshold for parallelism','max degree of parallelism','max server memory (MB)'
)
ORDER BY name;

----------------------------------------------------------------------------
-- RS 3: Linked Servers
----------------------------------------------------------------------------
SELECT
    '03_Linked_Servers' AS Section,
    s.name              AS LinkedServerName,
    s.product           AS Product,
    s.provider          AS Provider,
    s.data_source       AS DataSource,
    s.is_remote_login_enabled AS RemoteLoginEnabled,
    s.is_rpc_out_enabled      AS RpcOutEnabled,
    s.is_data_access_enabled  AS DataAccessEnabled,
    CASE
        WHEN s.provider IN ('SQLNCLI','SQLNCLI11') THEN 'WARN — legacy provider; MI requires MSOLEDBSQL'
        WHEN s.provider = 'MSOLEDBSQL'             THEN 'OK — supported on MI'
        WHEN s.provider = 'SQLOLEDB'               THEN 'WARN — deprecated provider'
        ELSE                                            'CHECK — verify provider supported on target'
    END                 AS MICompatibility
FROM sys.servers s
WHERE s.server_id > 0;

----------------------------------------------------------------------------
-- RS 4: SQL Agent Jobs (with subsystem risk analysis)
----------------------------------------------------------------------------
;WITH JobSteps AS (
    SELECT
        j.job_id,
        j.name              AS JobName,
        j.enabled           AS JobEnabled,
        STRING_AGG(s.subsystem, ', ') AS Subsystems,
        SUM(CASE WHEN s.subsystem IN ('CmdExec','PowerShell','SSIS') THEN 1 ELSE 0 END) AS RiskySteps,
        COUNT(*)            AS TotalSteps
    FROM msdb.dbo.sysjobs j
    LEFT JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
    GROUP BY j.job_id, j.name, j.enabled
)
SELECT
    '04_SQL_Agent_Jobs' AS Section,
    JobName,
    CASE JobEnabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END AS Status,
    TotalSteps,
    RiskySteps,
    Subsystems,
    CASE
        WHEN RiskySteps > 0 THEN 'High — uses CmdExec/PowerShell/SSIS, redesign for managed SQL'
        WHEN TotalSteps  > 0 THEN 'Info — review job dependencies on file paths, proxies, etc.'
        ELSE 'Info — empty job'
    END AS MIRelevance
FROM JobSteps
ORDER BY RiskySteps DESC, JobName;

INSERT INTO #Findings
SELECT 'Instance', JobName, 'SQL Agent', 'High',
       'Job uses CmdExec / PowerShell / SSIS subsystem (' + Subsystems + '). Requires redesign for managed SQL.'
FROM (
    SELECT j.name AS JobName, STRING_AGG(s.subsystem, ', ') AS Subsystems
    FROM msdb.dbo.sysjobs j
    JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
    WHERE s.subsystem IN ('CmdExec','PowerShell','SSIS')
    GROUP BY j.name
) X;

----------------------------------------------------------------------------
-- RS 5: Database Inventory
----------------------------------------------------------------------------
SELECT
    '05_Database_Inventory'                                            AS Section,
    d.database_id                                                      AS DatabaseId,
    d.name                                                             AS DatabaseName,
    d.state_desc                                                       AS State,
    d.recovery_model_desc                                              AS RecoveryModel,
    d.compatibility_level                                              AS CompatLevel,
    CAST(DATABASEPROPERTYEX(d.name, 'Version') AS INT)                 AS DBFormat,
    CASE
        WHEN CAST(DATABASEPROPERTYEX(d.name, 'Version') AS INT) <= 904 THEN 'SQL 2019 or earlier'
        WHEN CAST(DATABASEPROPERTYEX(d.name, 'Version') AS INT) =  957 THEN 'SQL 2022 RTM'
        WHEN CAST(DATABASEPROPERTYEX(d.name, 'Version') AS INT) =  974 THEN 'SQL 2022 (later CU)'
        WHEN CAST(DATABASEPROPERTYEX(d.name, 'Version') AS INT) =  998 THEN 'SQL 2025 / MI AlwaysUpToDate'
        ELSE 'unknown format'
    END                                                                AS FormatNotes,
    SUSER_SNAME(d.owner_sid)                                           AS OwnerLogin,
    d.create_date                                                      AS CreatedAt,
    d.is_read_only                                                     AS IsReadOnly,
    d.is_encrypted                                                     AS IsTDEEncrypted,
    d.is_published                                                     AS IsPublished,
    d.is_subscribed                                                    AS IsSubscribed,
    d.is_cdc_enabled                                                   AS IsCDCEnabled,
    (SELECT CAST(SUM(CAST(mf.size AS BIGINT)) * 8 / 1024 AS INT)
       FROM sys.master_files mf WHERE mf.database_id = d.database_id)  AS SizeMB
FROM sys.databases d
WHERE d.database_id > 4
ORDER BY d.name;

----------------------------------------------------------------------------
-- Loop: per-database checks (findings, SKU features, CLR, code scan)
----------------------------------------------------------------------------
DECLARE @db sysname, @sql NVARCHAR(MAX);
DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT d.name
    FROM sys.databases d
    LEFT JOIN sys.dm_hadr_database_replica_states drs
           ON drs.database_id = d.database_id
          AND drs.is_local = 1
    WHERE d.database_id > 4
      AND d.state_desc = 'ONLINE'
      AND d.is_read_only = 0
      -- Skip databases this replica cannot query (AG secondary without read access)
      AND (drs.database_id IS NULL                                  -- not in any AG → fine
           OR drs.is_primary_replica = 1                            -- primary replica → fine
           OR (drs.is_primary_replica = 0
               AND EXISTS (
                   SELECT 1
                   FROM sys.availability_replicas ar
                   WHERE ar.replica_id = drs.replica_id
                     AND ar.secondary_role_allow_connections_desc IN ('READ_ONLY','ALL')
               ))                                                   -- readable secondary → fine
          );
OPEN db_cur;
FETCH NEXT FROM db_cur INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- 5a. Per-DB feature findings
    SET @sql = N'
        USE ' + QUOTENAME(@db) + N';

        IF EXISTS (SELECT 1 FROM sys.database_files WHERE type_desc = ''FILESTREAM'')
            INSERT INTO #Findings VALUES
            (''Database'', @d, ''FILESTREAM'', ''High'',
             ''FILESTREAM filegroup found. Not supported on Azure SQL MI / SQL DB / RDS / Cloud SQL.'');

        IF EXISTS (SELECT 1 FROM sys.tables WHERE is_filetable = 1)
            INSERT INTO #Findings VALUES
            (''Database'', @d, ''FileTable'', ''High'',
             ''FileTable found. Not supported on managed SQL targets.'');

        IF EXISTS (SELECT 1 FROM sys.tables WHERE is_memory_optimized = 1)
            INSERT INTO #Findings VALUES
            (''Database'', @d, ''In-Memory OLTP'', ''High'',
             ''Memory-optimized tables found. Validate target tier (MI Business Critical only).'');

        IF EXISTS (SELECT 1 FROM sys.tables WHERE temporal_type <> 0)
            INSERT INTO #Findings VALUES
            (''Database'', @d, ''Temporal Tables'', ''Medium'',
             ''System-versioned temporal tables found. Validate target compatibility level.'');

        IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @d AND is_cdc_enabled = 1)
            INSERT INTO #Findings VALUES
            (''Database'', @d, ''CDC'', ''Medium'',
             ''Change Data Capture enabled. Supported on MI; review cleanup job after migration.'');

        IF EXISTS (SELECT 1 FROM sys.change_tracking_databases WHERE database_id = DB_ID())
            INSERT INTO #Findings VALUES
            (''Database'', @d, ''Change Tracking'', ''Medium'',
             ''Change Tracking enabled. Validate target migration approach.'');

        IF EXISTS (SELECT 1 FROM sys.service_queues WHERE is_ms_shipped = 0)
            INSERT INTO #Findings VALUES
            (''Database'', @d, ''Service Broker'', ''Medium'',
             ''Service Broker user objects present. Cross-instance broker not supported on MI.'');

        IF EXISTS (SELECT 1 FROM sys.assemblies WHERE is_user_defined = 1)
            INSERT INTO #Findings VALUES
            (''Database'', @d, ''CLR Assemblies'', ''High'',
             ''User-defined CLR assemblies present. Review PERMISSION_SET (UNSAFE/EXTERNAL_ACCESS) for MI.'');

        IF EXISTS (
            SELECT 1 FROM sys.database_principals
            WHERE type_desc IN (''WINDOWS_USER'', ''WINDOWS_GROUP'')
        )
            INSERT INTO #Findings VALUES
            (''Database'', @d, ''Security'', ''Medium'',
             ''Windows users/groups present. Map to AAD/Entra ID on Azure targets; SQL logins for RDS/Cloud SQL.'');
    ';
    BEGIN TRY
        EXEC sp_executesql @sql, N'@d sysname', @d = @db;
    END TRY BEGIN CATCH END CATCH

    -- 5b. SKU features per DB
    SET @sql = N'
        USE ' + QUOTENAME(@db) + N';
        INSERT INTO #SkuFeatures (DatabaseName, FeatureName, Severity, Note)
        SELECT @d, feature_name,
               CASE feature_name
                   WHEN ''FileStreamEnabled''                THEN ''High''
                   WHEN ''FileTableEnabled''                 THEN ''High''
                   WHEN ''PolybaseEnabled''                  THEN ''High''
                   WHEN ''MultipleFSContainers''             THEN ''High''
                   WHEN ''DBMirroring''                      THEN ''Medium''
                   WHEN ''TransactionalReplicationEnabled''  THEN ''Medium''
                   WHEN ''ChangeCapture''                    THEN ''Medium''
                   ELSE                                            ''Info''
               END,
               CASE feature_name
                   WHEN ''FileStreamEnabled''                THEN ''Not supported on Azure SQL MI / SQL DB''
                   WHEN ''FileTableEnabled''                 THEN ''Not supported on Azure SQL MI / SQL DB''
                   WHEN ''PolybaseEnabled''                  THEN ''Not supported on Azure SQL MI''
                   WHEN ''MultipleFSContainers''             THEN ''Multi-container FILESTREAM blocked on MI''
                   WHEN ''DBMirroring''                      THEN ''Deprecated; replace with AG before MI''
                   WHEN ''TransactionalReplicationEnabled''  THEN ''Reconfigure replication on MI side''
                   WHEN ''ChangeCapture''                    THEN ''CDC supported on MI; review cleanup job''
                   ELSE                                            ''Feature present; review case by case''
               END
        FROM sys.dm_db_persisted_sku_features;
    ';
    BEGIN TRY
        EXEC sp_executesql @sql, N'@d sysname', @d = @db;
    END TRY BEGIN CATCH END CATCH

    -- 5c. CLR assemblies per DB
    SET @sql = N'
        USE ' + QUOTENAME(@db) + N';
        INSERT INTO #CLR (DatabaseName, AssemblyName, PermissionSet, IsUserDefined, Verdict)
        SELECT @d, name, permission_set_desc, is_user_defined,
               CASE permission_set_desc
                   WHEN ''SAFE_ACCESS''     THEN ''OK — SAFE assembly''
                   WHEN ''EXTERNAL_ACCESS'' THEN ''WARN — EXTERNAL_ACCESS needs explicit MI configuration''
                   WHEN ''UNSAFE_ACCESS''   THEN ''HIGH — UNSAFE CLR; review carefully for MI''
                   ELSE                          ''CHECK''
               END
        FROM sys.assemblies WHERE is_user_defined = 1;
    ';
    BEGIN TRY
        EXEC sp_executesql @sql, N'@d sysname', @d = @db;
    END TRY BEGIN CATCH END CATCH

    -- 5d. T-SQL code scan inside stored procedures / functions / triggers
    SET @sql = N'
        USE ' + QUOTENAME(@db) + N';
        INSERT INTO #CodeScan (DatabaseName, SchemaName, ObjectName, ObjectType, RiskPattern, Severity)
        SELECT @d,
               OBJECT_SCHEMA_NAME(m.object_id),
               OBJECT_NAME(m.object_id),
               o.type_desc,
               pattern,
               sev
        FROM sys.sql_modules m
        JOIN sys.objects o ON o.object_id = m.object_id
        CROSS APPLY (VALUES
            (''xp_cmdshell'',          ''High''),
            (''OPENROWSET'',           ''High''),
            (''OPENDATASOURCE'',       ''High''),
            (''sp_OACreate'',          ''High''),
            (''sp_OAMethod'',          ''High''),
            (''CREATE ASSEMBLY'',      ''High''),
            (''BULK INSERT'',          ''Medium''),
            (''sp_addlinkedserver'',   ''Medium''),
            (''sp_send_dbmail'',       ''Medium'')
        ) X(pattern, sev)
        WHERE m.definition LIKE ''%'' + pattern + ''%'';
    ';
    BEGIN TRY
        EXEC sp_executesql @sql, N'@d sysname', @d = @db;
    END TRY BEGIN CATCH END CATCH

    FETCH NEXT FROM db_cur INTO @db;
END
CLOSE db_cur; DEALLOCATE db_cur;

----------------------------------------------------------------------------
-- HADR-related findings
----------------------------------------------------------------------------
IF SERVERPROPERTY('IsHadrEnabled') = 1
    INSERT INTO #Findings VALUES
    ('Instance', @@SERVERNAME, 'Always On', 'Medium',
     'Always On enabled. VM/IaaS targets best fit; managed targets may need redesign or AG-aware migration.');

IF EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_primary_databases)
    INSERT INTO #Findings VALUES
    ('Instance', @@SERVERNAME, 'Log Shipping', 'Medium',
     'Log shipping configured. Must be redesigned for managed SQL targets.');

IF EXISTS (SELECT 1 FROM sys.database_mirroring WHERE mirroring_state IS NOT NULL)
    INSERT INTO #Findings VALUES
    ('Instance', @@SERVERNAME, 'Database Mirroring', 'Medium',
     'Database mirroring is configured. Deprecated; replace with AG before any MI Link migration.');

----------------------------------------------------------------------------
-- RS 6: Database-Level Findings (consolidated from #Findings)
----------------------------------------------------------------------------
SELECT
    '06_DB_Level_Findings' AS Section,
    ScopeName              AS DatabaseName,
    Category,
    Severity,
    Finding
FROM #Findings
WHERE ScopeType = 'Database'
ORDER BY
    CASE Severity WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END,
    ScopeName, Category;

----------------------------------------------------------------------------
-- RS 7: T-SQL Code Scan
----------------------------------------------------------------------------
SELECT
    '07_TSQL_Code_Scan' AS Section,
    DatabaseName,
    SchemaName,
    ObjectName,
    ObjectType,
    RiskPattern,
    Severity
FROM #CodeScan
ORDER BY
    CASE Severity WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END,
    DatabaseName, ObjectName, RiskPattern;

----------------------------------------------------------------------------
-- RS 8: Per-DB SKU Features (sys.dm_db_persisted_sku_features)
----------------------------------------------------------------------------
SELECT
    '08_SKU_Features' AS Section,
    DatabaseName,
    FeatureName,
    Severity,
    Note
FROM #SkuFeatures
ORDER BY
    CASE Severity WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END,
    DatabaseName, FeatureName;

----------------------------------------------------------------------------
-- RS 9: CLR Assemblies
----------------------------------------------------------------------------
SELECT
    '09_CLR_Assemblies' AS Section,
    DatabaseName,
    AssemblyName,
    PermissionSet,
    IsUserDefined,
    Verdict
FROM #CLR
ORDER BY
    CASE WHEN Verdict LIKE 'HIGH%' THEN 1
         WHEN Verdict LIKE 'WARN%' THEN 2
         ELSE 3 END,
    DatabaseName, AssemblyName;

----------------------------------------------------------------------------
-- RS 10: Database Files
----------------------------------------------------------------------------
SELECT
    '10_Database_Files'                                                AS Section,
    DB_NAME(mf.database_id)                                            AS DatabaseName,
    mf.name                                                            AS LogicalName,
    mf.type_desc                                                       AS FileType,
    mf.physical_name                                                   AS PhysicalPath,
    CAST(mf.size AS BIGINT) * 8 / 1024                                 AS SizeMB,
    CASE
        WHEN mf.type_desc IN ('FILESTREAM','FILETABLE') THEN 'High — not supported on managed SQL'
        WHEN mf.type_desc IN ('LOG','ROWS')             THEN 'OK'
        ELSE                                                  'CHECK'
    END                                                                AS MIVerdict
FROM sys.master_files mf
WHERE mf.database_id > 4
ORDER BY DB_NAME(mf.database_id), mf.type_desc, mf.name;

----------------------------------------------------------------------------
-- RS 11: Availability Groups (full topology — replicas + sync state)
----------------------------------------------------------------------------
SELECT
    '11_Availability_Groups' AS Section,
    ag.name                  AS AGName,
    ag.is_distributed        AS IsDistributedAG,
    ar.replica_server_name   AS ReplicaServer,
    ar.availability_mode_desc AS AvailabilityMode,
    ar.failover_mode_desc    AS FailoverMode,
    rs.role_desc             AS Role,
    rs.synchronization_health_desc AS SyncHealth,
    rs.connected_state_desc  AS ConnectedState,
    rs.operational_state_desc AS OperationalState
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar             ON ar.group_id  = ag.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states rs ON rs.replica_id = ar.replica_id
ORDER BY ag.name, ar.replica_server_name;

----------------------------------------------------------------------------
-- RS 12: Database Mirroring (legacy)
----------------------------------------------------------------------------
SELECT
    '12_Database_Mirroring'                AS Section,
    d.name                                 AS DatabaseName,
    dm.mirroring_state_desc                AS State,
    dm.mirroring_role_desc                 AS Role,
    dm.mirroring_safety_level_desc         AS SafetyLevel,
    dm.mirroring_partner_name              AS PartnerName,
    dm.mirroring_witness_name              AS WitnessName
FROM sys.database_mirroring dm
JOIN sys.databases d ON d.database_id = dm.database_id
WHERE dm.mirroring_state IS NOT NULL;

----------------------------------------------------------------------------
-- RS 13: Log Shipping
----------------------------------------------------------------------------
SELECT
    '13_LogShipping_Primary' AS Section,
    primary_database         AS PrimaryDatabase,
    primary_id               AS PrimaryId,
    backup_directory         AS BackupDirectory,
    backup_share             AS BackupShare
FROM msdb.dbo.log_shipping_primary_databases;

SELECT
    '13_LogShipping_Secondary' AS Section,
    secondary_database         AS SecondaryDatabase,
    secondary_id               AS SecondaryId,
    restore_delay              AS RestoreDelayMin,
    restore_mode               AS RestoreMode,
    disconnect_users           AS DisconnectUsers
FROM msdb.dbo.log_shipping_secondary_databases;

----------------------------------------------------------------------------
-- RS 14: Replication
----------------------------------------------------------------------------
IF OBJECT_ID('msdb.dbo.MSdistpublishers') IS NOT NULL
    EXEC ('
        SELECT ''14_Replication_Publishers'' AS Section,
               name        AS PublisherDB,
               publisher_id AS PublisherId
        FROM msdb.dbo.MSdistpublishers;
    ');
ELSE
    SELECT '14_Replication_Publishers' AS Section,
           CAST(NULL AS sysname) AS PublisherDB, CAST(NULL AS INT) AS PublisherId
    WHERE 1 = 0;

IF DB_ID('distribution') IS NOT NULL
    EXEC ('
        SELECT ''14_Replication_Publications'' AS Section,
               publisher_db     AS PublisherDB,
               publication      AS PublicationName,
               publication_type AS PublicationType
        FROM distribution.dbo.MSpublications;
    ');
ELSE
    SELECT '14_Replication_Publications' AS Section,
           CAST(NULL AS sysname) AS PublisherDB,
           CAST(NULL AS sysname) AS PublicationName,
           CAST(NULL AS INT)     AS PublicationType
    WHERE 1 = 0;

----------------------------------------------------------------------------
-- Build Cloud Migration Matrix from accumulated findings
----------------------------------------------------------------------------
DECLARE
    @HighCount         INT = (SELECT COUNT(*) FROM #Findings WHERE Severity = 'High'),
    @MediumCount       INT = (SELECT COUNT(*) FROM #Findings WHERE Severity = 'Medium'),
    @LinkedServerCount INT = (SELECT COUNT(*) FROM #Findings WHERE Category = 'Linked Servers'),
    @AgentRiskCount    INT = (SELECT COUNT(*) FROM #Findings WHERE Category = 'SQL Agent'),
    @CLRCount          INT = (SELECT COUNT(*) FROM #CLR),
    @CLRUnsafeCount    INT = (SELECT COUNT(*) FROM #CLR WHERE PermissionSet IN ('UNSAFE_ACCESS','EXTERNAL_ACCESS')),
    @FileStreamCount   INT = (SELECT COUNT(*) FROM #Findings WHERE Category IN ('FILESTREAM','FileTable')),
    @InMemoryCount     INT = (SELECT COUNT(*) FROM #Findings WHERE Category = 'In-Memory OLTP'),
    @XpCount           INT = (SELECT COUNT(*) FROM #Findings WHERE Finding LIKE '%xp_cmdshell%'),
    @CodeRiskCount     INT = (SELECT COUNT(*) FROM #CodeScan WHERE Severity = 'High'),
    @ReplicationCount  INT = (SELECT COUNT(*) FROM sys.databases
                                WHERE is_published = 1 OR is_subscribed = 1
                                   OR is_merge_published = 1 OR is_distributor = 1),
    @AGEnabled         BIT = CAST(SERVERPROPERTY('IsHadrEnabled') AS BIT),
    @MaxDBFormat       INT = (SELECT MAX(CAST(DATABASEPROPERTYEX(name, 'Version') AS INT))
                                FROM sys.databases WHERE database_id > 4);

-- Azure VM (IaaS) — almost always Yes
INSERT INTO #Matrix VALUES
('Azure VM (SQL on IaaS)', 'Yes',
 'Best compatibility option. Carries over almost all on-prem features. Validate OS, edition, licensing, HA/DR, storage, and version support.');

-- AWS EC2 (IaaS) — almost always Yes
INSERT INTO #Matrix VALUES
('AWS EC2 (SQL on IaaS)', 'Yes',
 'Best AWS compatibility option. Validate licensing model (BYOL vs LI), EBS/FSx storage, AD domain dependency, and HA/DR strategy.');

-- GCP Compute Engine (IaaS) — almost always Yes
INSERT INTO #Matrix VALUES
('GCP Compute Engine (SQL on IaaS)', 'Yes',
 'Best GCP compatibility option. Validate licensing, persistent-disk storage, AD/IAM dependencies, and HA/DR strategy.');

-- Azure SQL Managed Instance — full nuanced verdict including format check
INSERT INTO #Matrix VALUES
('Azure SQL Managed Instance', 
 CASE WHEN @FileStreamCount > 0 OR @InMemoryCount > 0
       OR @CLRUnsafeCount > 0 OR @LinkedServerCount > 5
       OR @AgentRiskCount > 0
      THEN 'No' ELSE 'Yes' END,
 'Format version analysis: max DB format = ' + ISNULL(CAST(@MaxDBFormat AS VARCHAR(10)), 'n/a')
 + CASE @MaxDBFormat
       WHEN 998 THEN ' (998 = MI Link viable when target MI is AlwaysUpToDate / 998).'
       WHEN 974 THEN ' (974 = SQL 2022 later CU; MI Link blocked, use DMS or backup/restore).'
       WHEN 957 THEN ' (957 = SQL 2022 RTM; MI Link blocked, use DMS or backup/restore).'
       WHEN 904 THEN ' (904 = SQL 2019; MI Link blocked, use DMS or backup/restore).'
       ELSE ' (unknown format — review).'
   END
 + ' Blockers found: '
 + 'FileStream/FileTable=' + CAST(@FileStreamCount AS VARCHAR(10))
 + ', In-Memory OLTP=' + CAST(@InMemoryCount AS VARCHAR(10))
 + ', UNSAFE/EXTERNAL CLR=' + CAST(@CLRUnsafeCount AS VARCHAR(10))
 + ', Risky Agent jobs=' + CAST(@AgentRiskCount AS VARCHAR(10))
 + ', Linked Servers=' + CAST(@LinkedServerCount AS VARCHAR(10))
 + '.');

-- Azure SQL Database — strict, instance-features kill it fast
INSERT INTO #Matrix VALUES
('Azure SQL Database',
 CASE WHEN @HighCount > 0 OR @LinkedServerCount > 0 OR @AgentRiskCount > 0
       OR @XpCount > 0 OR @ReplicationCount > 0 OR @InMemoryCount > 0
      THEN 'No' ELSE 'Yes' END,
 'Single-DB target. Anything instance-level (Agent jobs, linked servers, cross-DB queries, CLR, FileStream) blocks this. Ideal for clean app-level workloads only.');

-- AWS RDS for SQL Server
INSERT INTO #Matrix VALUES
('AWS RDS for SQL Server',
 CASE WHEN @FileStreamCount > 0 OR @CLRUnsafeCount > 0 OR @AgentRiskCount > 0
       OR @XpCount > 0 OR @ReplicationCount > 0 OR @InMemoryCount > 0
      THEN 'No' ELSE 'Yes' END,
 'RDS restricts OS access, has option-group feature gates, no SQL Agent CmdExec/PowerShell/SSIS subsystems, no xp_cmdshell, and limited linked-server support. Validate edition + version availability.');

-- GCP Cloud SQL for SQL Server
INSERT INTO #Matrix VALUES
('GCP Cloud SQL for SQL Server',
 CASE WHEN @FileStreamCount > 0 OR @CLRCount > 0 OR @AgentRiskCount > 0
       OR @XpCount > 0 OR @LinkedServerCount > 0 OR @ReplicationCount > 0
       OR @InMemoryCount > 0
      THEN 'No' ELSE 'Yes' END,
 'Most restrictive managed SQL Server option. No SQL Agent until recently, limited linked-server support, no FileStream, and tight feature gates. Validate Cloud SQL Server version availability.');

----------------------------------------------------------------------------
-- RS 15: Cloud Migration Matrix
----------------------------------------------------------------------------
SELECT
    '15_Cloud_Migration_Matrix' AS Section,
    TargetPlatform,
    Fit,
    Reason
FROM #Matrix
ORDER BY
    CASE
        WHEN TargetPlatform LIKE 'Azure VM%'  THEN 1
        WHEN TargetPlatform LIKE 'AWS EC2%'   THEN 2
        WHEN TargetPlatform LIKE 'GCP Compute%' THEN 3
        WHEN TargetPlatform LIKE 'Azure SQL Managed%' THEN 4
        WHEN TargetPlatform LIKE 'Azure SQL Database%' THEN 5
        WHEN TargetPlatform LIKE 'AWS RDS%'   THEN 6
        WHEN TargetPlatform LIKE 'GCP Cloud SQL%' THEN 7
        ELSE 8
    END;

----------------------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#Findings')    IS NOT NULL DROP TABLE #Findings;
IF OBJECT_ID('tempdb..#SkuFeatures') IS NOT NULL DROP TABLE #SkuFeatures;
IF OBJECT_ID('tempdb..#CLR')         IS NOT NULL DROP TABLE #CLR;
IF OBJECT_ID('tempdb..#CodeScan')    IS NOT NULL DROP TABLE #CodeScan;
IF OBJECT_ID('tempdb..#Matrix')      IS NOT NULL DROP TABLE #Matrix;

PRINT '=== Migration assessment complete on ' + @@SERVERNAME + ' at '
      + CONVERT(VARCHAR(30), SYSDATETIME(), 121) + ' ===';
