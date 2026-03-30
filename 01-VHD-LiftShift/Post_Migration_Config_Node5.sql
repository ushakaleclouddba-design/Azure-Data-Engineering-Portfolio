/*
================================================================================
  POST MIGRATION CONFIGURATION SCRIPT — NODE5 AZURE VM
================================================================================
  Server    : NODE5 (<VM_NAME>)
  VM Size   : Standard_B2as_v2 (2 vCPUs, 8 GB RAM)
  Location  : North Central US
  SQL Ver   : SQL Server 2019 (<SQL_VERSION>)
  Databases : CoreBank_OnPrem_POC, AcquiredBanks_OnPrem_POC
              ReportServer, ReportServerTempDB
  Date      : March 2026
  Purpose   : Post-migration hardening, configuration, and validation
================================================================================
  INSTRUCTIONS: Run each section one at a time. Review output before proceeding.
  Run as sysadmin (sa or <DOMAIN>\<USERNAME>).
================================================================================
*/

--------------------------------------------------------------------------------
-- SECTION 1: SERVER CONFIGURATION
-- Standard_B2as_v2 = 2 vCPUs, 8 GB RAM
-- Max memory: leave ~2 GB for OS = set max to 6144 MB
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 1: SERVER CONFIGURATION';
PRINT '======================================================';

EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 6144;
RECONFIGURE WITH OVERRIDE;
EXEC sp_configure 'min server memory (MB)', 512;
RECONFIGURE WITH OVERRIDE;
EXEC sp_configure 'optimize for ad hoc workloads', 1;
RECONFIGURE WITH OVERRIDE;
EXEC sp_configure 'xp_cmdshell', 0;
RECONFIGURE WITH OVERRIDE;
EXEC sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE WITH OVERRIDE;
EXEC sp_configure 'max degree of parallelism', 2;
RECONFIGURE WITH OVERRIDE;
PRINT 'Section 1 Complete: Server configuration applied.';
GO

--------------------------------------------------------------------------------
-- SECTION 2: TEMPDB CONFIGURATION
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 2: TEMPDB CONFIGURATION CHECK';
PRINT '======================================================';

SELECT name, physical_name, size * 8 / 1024 AS SizeMB,
       max_size, growth, is_percent_growth
FROM sys.master_files
WHERE database_id = DB_ID('tempdb');
GO

SELECT COUNT(*) AS TempDB_DataFiles
FROM sys.master_files
WHERE database_id = DB_ID('tempdb')
AND type_desc = 'ROWS';
GO
PRINT 'Section 2 Complete: Review TempDB output above.';
GO

--------------------------------------------------------------------------------
-- SECTION 3: DATABASE INTEGRITY CHECK
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 3: DATABASE INTEGRITY CHECK (DBCC CHECKDB)';
PRINT '======================================================';

DBCC CHECKDB ('CoreBank_OnPrem_POC') WITH NO_INFOMSGS, ALL_ERRORMSGS;
GO
DBCC CHECKDB ('AcquiredBanks_OnPrem_POC') WITH NO_INFOMSGS, ALL_ERRORMSGS;
GO
DBCC CHECKDB ('ReportServer') WITH NO_INFOMSGS, ALL_ERRORMSGS;
GO
PRINT 'Section 3 Complete: No output = no errors found.';
GO

--------------------------------------------------------------------------------
-- SECTION 4: UPDATE STATISTICS
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 4: UPDATE STATISTICS';
PRINT '======================================================';

USE [CoreBank_OnPrem_POC]; EXEC sp_updatestats; GO
USE [AcquiredBanks_OnPrem_POC]; EXEC sp_updatestats; GO
USE [ReportServer]; EXEC sp_updatestats; GO
PRINT 'Section 4 Complete.';
GO

--------------------------------------------------------------------------------
-- SECTION 5: INDEX MAINTENANCE
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 5: INDEX FRAGMENTATION CHECK';
PRINT '======================================================';

USE [CoreBank_OnPrem_POC];
SELECT OBJECT_NAME(ips.object_id) AS TableName, i.name AS IndexName,
       ips.index_type_desc,
       ROUND(ips.avg_fragmentation_in_percent, 2) AS FragmentationPct,
       ips.page_count,
       CASE WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
            WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
            ELSE 'OK' END AS Recommendation
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.page_count > 100
ORDER BY ips.avg_fragmentation_in_percent DESC;
GO

USE [CoreBank_OnPrem_POC];
EXEC sp_MSforeachtable 'ALTER INDEX ALL ON ? REBUILD WITH (ONLINE = OFF)';
GO
USE [AcquiredBanks_OnPrem_POC];
EXEC sp_MSforeachtable 'ALTER INDEX ALL ON ? REBUILD WITH (ONLINE = OFF)';
GO
PRINT 'Section 5 Complete.';
GO

--------------------------------------------------------------------------------
-- SECTION 6: COMPATIBILITY LEVEL
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 6: COMPATIBILITY LEVEL';
PRINT '======================================================';

SELECT name, compatibility_level,
    CASE compatibility_level
        WHEN 160 THEN 'SQL Server 2022'
        WHEN 150 THEN 'SQL Server 2019'
        WHEN 140 THEN 'SQL Server 2017'
        WHEN 130 THEN 'SQL Server 2016'
        WHEN 120 THEN 'SQL Server 2014'
        ELSE 'Older'
    END AS CompatVersion
FROM sys.databases
WHERE name NOT IN ('master','model','msdb','tempdb')
ORDER BY name;
GO

ALTER DATABASE [CoreBank_OnPrem_POC] SET COMPATIBILITY_LEVEL = 150;
ALTER DATABASE [AcquiredBanks_OnPrem_POC] SET COMPATIBILITY_LEVEL = 150;
PRINT 'Section 6 Complete: Compatibility levels set to 150 (SQL 2019).';
GO

--------------------------------------------------------------------------------
-- SECTION 7: QUERY STORE
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 7: QUERY STORE';
PRINT '======================================================';

ALTER DATABASE [CoreBank_OnPrem_POC]
SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    MAX_STORAGE_SIZE_MB = 100,
    QUERY_CAPTURE_MODE = AUTO
);
GO
ALTER DATABASE [AcquiredBanks_OnPrem_POC]
SET QUERY_STORE = ON (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    MAX_STORAGE_SIZE_MB = 100,
    QUERY_CAPTURE_MODE = AUTO
);
GO

SELECT name, is_query_store_on, query_store_actual_state_desc
FROM sys.databases
WHERE name IN ('CoreBank_OnPrem_POC', 'AcquiredBanks_OnPrem_POC');
GO
PRINT 'Section 7 Complete.';
GO

--------------------------------------------------------------------------------
-- SECTION 8: RECOVERY MODEL
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 8: RECOVERY MODEL';
PRINT '======================================================';

SELECT name, recovery_model_desc
FROM sys.databases
WHERE name NOT IN ('master','model','msdb','tempdb')
ORDER BY name;
GO

ALTER DATABASE [CoreBank_OnPrem_POC] SET RECOVERY SIMPLE;
ALTER DATABASE [AcquiredBanks_OnPrem_POC] SET RECOVERY SIMPLE;
PRINT 'POC databases set to SIMPLE recovery model.';
PRINT 'NOTE: Change to FULL recovery model for production workloads.';
GO

--------------------------------------------------------------------------------
-- SECTION 9: LOGIN AND USER VALIDATION
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 9: LOGIN AND USER VALIDATION';
PRINT '======================================================';

SELECT name AS LoginName, type_desc AS LoginType,
       is_disabled, create_date, modify_date
FROM sys.server_principals
WHERE type IN ('S','U','G')
AND name NOT LIKE '##%'
ORDER BY type_desc, name;
GO

USE [CoreBank_OnPrem_POC]; EXEC sp_change_users_login 'Report'; GO
USE [AcquiredBanks_OnPrem_POC]; EXEC sp_change_users_login 'Report'; GO
PRINT 'Section 9 Complete: Review orphaned user output above.';
GO

--------------------------------------------------------------------------------
-- SECTION 10: SQL SERVER AGENT JOBS
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 10: SQL SERVER AGENT JOBS';
PRINT '======================================================';

USE msdb;
SELECT j.name AS JobName, j.enabled AS IsEnabled, j.description,
       c.name AS CategoryName,
       CASE j.enabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END AS Status,
       js.last_run_date, js.last_run_time,
       CASE js.last_run_outcome
           WHEN 0 THEN 'Failed' WHEN 1 THEN 'Succeeded'
           WHEN 3 THEN 'Cancelled' WHEN 5 THEN 'Unknown'
           ELSE 'Never Run' END AS LastRunOutcome
FROM sysjobs j
LEFT JOIN syscategories c ON j.category_id = c.category_id
LEFT JOIN sysjobservers js ON j.job_id = js.job_id
ORDER BY j.name;
GO
PRINT 'Section 10 Complete.';
GO

--------------------------------------------------------------------------------
-- SECTION 11: AZURE VM CHECKS
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 11: AZURE VM CHECKS';
PRINT '======================================================';

EXEC xp_readerrorlog 0, 1, 'Instant file initialization';
GO

SELECT DB_NAME(database_id) AS DatabaseName, type_desc AS FileType,
       physical_name AS FilePath, size * 8 / 1024 AS SizeMB,
       max_size, growth
FROM sys.master_files
WHERE database_id NOT IN (1,2,3,4)
ORDER BY database_id, type_desc;
GO
PRINT 'Section 11 Complete.';
GO

--------------------------------------------------------------------------------
-- SECTION 12: FINAL VALIDATION SUMMARY
--------------------------------------------------------------------------------
PRINT '======================================================';
PRINT 'SECTION 12: FINAL VALIDATION SUMMARY';
PRINT '======================================================';

SELECT name AS DatabaseName, state_desc AS Status,
       recovery_model_desc AS RecoveryModel,
       compatibility_level AS CompatLevel,
       is_query_store_on AS QueryStoreOn,
       log_reuse_wait_desc AS LogReuseWait,
       page_verify_option_desc AS PageVerify
FROM sys.databases
WHERE name NOT IN ('master','model','msdb','tempdb')
ORDER BY name;
GO

SELECT name, value_in_use AS CurrentValue, description
FROM sys.configurations
WHERE name IN (
    'max server memory (MB)', 'min server memory (MB)',
    'max degree of parallelism', 'cost threshold for parallelism',
    'optimize for ad hoc workloads', 'xp_cmdshell'
)
ORDER BY name;
GO

PRINT '======================================================';
PRINT 'POST MIGRATION CONFIGURATION COMPLETE — NODE5';
PRINT '<VM_NAME> | North Central US';
PRINT 'SQL Server 2019 (<SQL_VERSION>)';
PRINT '======================================================';
GO
