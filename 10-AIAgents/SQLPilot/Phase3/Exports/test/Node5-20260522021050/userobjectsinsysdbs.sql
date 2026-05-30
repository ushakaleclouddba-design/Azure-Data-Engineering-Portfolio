SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON



    CREATE PROCEDURE [dbo].[sp_ssis_startup]
    AS
    SET NOCOUNT ON
        /* Currently, the IS Store name is 'SSISDB' */
        IF DB_ID('SSISDB') IS NULL
            RETURN
        
        IF NOT EXISTS(SELECT name FROM [SSISDB].sys.procedures WHERE name=N'startup')
            RETURN
         
        /*Invoke the procedure in SSISDB  */
        /* Use dynamic sql to handle AlwaysOn non-readable mode*/
        DECLARE @script nvarchar(500)
        SET @script = N'EXEC [SSISDB].[catalog].[startup]'
        EXECUTE sp_executesql @script


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON


CREATE   FUNCTION smart_admin.fn_get_current_xevent_settings()
	RETURNS  @t TABLE(
		event_name	NVARCHAR(128),
		is_configurable	NVARCHAR(128),
		is_enabled	NVARCHAR(128)
		)
AS
BEGIN
	INSERT INTO @t
	SELECT event_name, is_configurable, is_enabled
	FROM managed_backup.fn_get_current_xevent_settings()

	RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON


CREATE   FUNCTION smart_admin.fn_get_parameter(@parameter_name NVARCHAR(128))
       RETURNS @t table
       (
              parameter_name       NVARCHAR(128),
              parameter_value      NVARCHAR(MAX)
       )
AS
BEGIN
       INSERT INTO @t
       SELECT parameter_name, parameter_value 
       FROM managed_backup.fn_get_parameter (@parameter_name)

       RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

-- Returns the V1 instance configuration parameters
--
CREATE   FUNCTION smart_admin.fn_backup_instance_config () 
	RETURNS @t TABLE
		(
			is_managed_backup_enabled	BIT,
			credential_name				SYSNAME NULL,
			retention_days				INT,
			storage_url					NVARCHAR(1024) NULL,
			encryption_algorithm		SYSNAME NULL,
			encryptor_type				NVARCHAR(32) NULL,
			encryptor_name				SYSNAME NULL
		)
AS
BEGIN
	IF  (HAS_PERMS_BY_NAME(null, null, 'ALTER ANY CREDENTIAL') = 1 AND 
            IS_ROLEMEMBER('db_backupoperator') = 1  AND
	    HAS_PERMS_BY_NAME(null, null, 'VIEW ANY DEFINITION') = 1)
	BEGIN		   
	    INSERT INTO @t
	    SELECT
	    CONVERT(BIT, task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";
		(/PD:AutoBackupGlobalData/PD:defaultAutoBackupSetting)[1]', 'nvarchar(32)')),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
	    	(/PD:AutoBackupGlobalData/PD:defaultCredentialName)[1]', 'nvarchar(128)'), ''),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";
		(/PD:AutoBackupGlobalData/PD:defaultRetentionPeriod)[1]', 'int'), 0),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalData/PD:defaultURL)[1]', 'nvarchar(1024)'), ''),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalData/PD:defaultEncryptionAlgorithm)[1]', 'nvarchar(128)'), ''),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalData/PD:defaultEncryptorType)[1]', 'nvarchar(32)'), ''),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalData/PD:defaultEncryptorName)[1]', 'nvarchar(128)'), '')
		FROM autoadmin_task_agent_metadata
		WHERE autoadmin_id = 0

		IF NOT EXISTS(SELECT TOP 1 1 FROM @t)
		BEGIN
			INSERT INTO @t VALUES (NULL, NULL, NULL, NULL, NULL, NULL, NULL)
		END
	END
	RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE   FUNCTION smart_admin.fn_available_backups
                 ( @database_name NVARCHAR(512))
	RETURNS  @t TABLE(
		backup_path				NVARCHAR(260) COLLATE Latin1_General_CI_AS_KS_WS,
		backup_type				NVARCHAR(6),
		expiration_date			DATETIME,
		database_guid			UNIQUEIDENTIFIER,	
		first_lsn				NUMERIC(25, 0), 
		last_lsn				NUMERIC(25, 0), 
		backup_start_date		DATETIME,
		backup_finish_date		DATETIME,
		machine_name			NVARCHAR(128) NULL,
		last_recovery_fork_id	UNIQUEIDENTIFIER, --last_recovery_fork_id in backupset
		first_recovery_fork_id	UNIQUEIDENTIFIER NULL,
		fork_point_lsn			NUMERIC(25, 0) NULL,
		availability_group_guid UNIQUEIDENTIFIER NULL -- this is for Hadron
		Unique Clustered (database_guid, backup_start_date, first_lsn, backup_type)
	)
AS
BEGIN

	INSERT INTO @t 
	SELECT backup_path, backup_type, expiration_date, database_guid, first_lsn, last_lsn, backup_start_date, backup_finish_date, 
		machine_name, last_recovery_fork_id, first_recovery_fork_id, fork_point_lsn, availability_group_guid
	FROM managed_backup.fn_available_backups (@database_name)

	RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON


CREATE   FUNCTION managed_backup.fn_available_backups
                 ( @database_name NVARCHAR(512))
	RETURNS  @t TABLE(
		backup_path				NVARCHAR(260) COLLATE Latin1_General_CI_AS_KS_WS,
		backup_type				NVARCHAR(6),
		expiration_date			DATETIME,
		database_guid			UNIQUEIDENTIFIER,	
		first_lsn				NUMERIC(25, 0), 
		last_lsn				NUMERIC(25, 0), 
		backup_start_date		DATETIME,
		backup_finish_date		DATETIME,
		machine_name			NVARCHAR(128) NULL,
		last_recovery_fork_id	UNIQUEIDENTIFIER, --last_recovery_fork_id in backupset
		first_recovery_fork_id	UNIQUEIDENTIFIER NULL,
		fork_point_lsn			NUMERIC(25, 0) NULL,
		availability_group_guid UNIQUEIDENTIFIER NULL -- this is for Hadron
		Unique Clustered (database_guid, backup_start_date, first_lsn, backup_type, backup_path)
	)
AS
BEGIN
	-- helper to decide whether lsn is continuous
	DECLARE @logsWithRowNumber TABLE
	       (
		log_backup_id			INT,			
		backup_path				NVARCHAR(260) COLLATE Latin1_General_CI_AS_KS_WS,
		backup_type				NVARCHAR(6),
		expiration_date			DATETIME,
		database_guid			UNIQUEIDENTIFIER,	
		first_lsn				NUMERIC(25, 0), 
		last_lsn				NUMERIC(25, 0), 
		backup_start_date		DATETIME,
		backup_finish_date		DATETIME,
		machine_name			NVARCHAR(128) NULL,
		last_recovery_fork_id	UNIQUEIDENTIFIER, --last_recovery_fork_id in backupset
		first_recovery_fork_id	UNIQUEIDENTIFIER NULL,
		fork_point_lsn			NUMERIC(25, 0) NULL,
		availability_group_guid UNIQUEIDENTIFIER NULL, -- this is for Hadron
		adjusted_db_guid        UNIQUEIDENTIFIER NULL-- this is for Hadron
	)

	--existing backup files
	INSERT INTO @t SELECT 
	    	'https://' + backup_path AS backup_path, 
		CASE WHEN backup_type = 1 THEN 'DB' ELSE 'Log' END AS backup_type,
		expiration_date,
		database_guid,
		first_lsn,
		last_lsn,
		backup_start_date,
		backup_finish_date,
		machine_name,
		first_recovery_fork_id,
		last_recovery_fork_id,
		fork_point_lsn,
		availability_group_guid
	FROM smart_backup_files
	WHERE database_name = @database_name
		AND (status = 'A' OR status = 'U') 

	-- populate the helper table
	INSERT INTO @logsWithRowNumber
	SELECT 
		row_number() OVER (PARTITION BY adjusted_db_guid ORDER BY first_lsn) AS log_backup_id,
		* 
	FROM 
	(SELECT
		*,
		CASE WHEN availability_group_guid = '00000000-0000-0000-0000-000000000000' THEN database_guid 
			WHEN availability_group_guid is NULL THEN database_guid
			ELSE availability_group_guid END as adjusted_db_guid
	FROM @t) temp
	WHERE backup_type = 'Log' 

	-- insert gap rows
	INSERT into @t
	SELECT 'Broken_Chain_' + CONVERT(NVARCHAR(64), t1.last_lsn) + '_to_' + CONVERT(NVARCHAR(64), t2.first_lsn) AS backup_path, 
	'Log', 
	CONVERT(DateTime, '9999-12-31 23:59:59.000') AS expiration_date, 
	t1.database_guid AS database_guid, 
	t1.last_lsn, 
	t2.first_lsn, 
	t1.backup_finish_date, 
	t2.backup_start_date, 
	t1.machine_name, 
	NULL, 
	NULL, 
	NULL, 
	t1.availability_group_guid
	FROM @logsWithRowNumber t1 
		JOIN @logsWithRowNumber t2 ON t1.log_backup_id = t2.log_backup_id - 1 
			AND t1.adjusted_db_guid = t2.adjusted_db_guid
	WHERE t1.last_lsn != t2.first_lsn AND t1.first_lsn != t2.first_lsn

	RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON


--Look at a period of time, report aggregated number of several type of errors
--When @begin_time and @end_time are not specified, by default look at events in last 30 minutes
--
CREATE   FUNCTION smart_admin.fn_get_health_status (
	@begin_time DATETIME = NULL,
	@end_time DATETIME = NULL
) 
RETURNS @t TABLE(
	number_of_storage_connectivity_errors int,
	number_of_sql_errors int,
	number_of_invalid_credential_errors int,
	number_of_other_errors int,
	number_of_corrupted_or_deleted_backups int,
	number_of_backup_loops int,
	number_of_retention_loops int
	)
AS 
BEGIN 

	INSERT INTO @t 
	SELECT 
		number_of_storage_connectivity_errors
		,number_of_sql_errors
		,number_of_invalid_credential_errors
		,number_of_other_errors
		,number_of_corrupted_or_deleted_backups
		,number_of_backup_loops
		,number_of_retention_loops
	FROM managed_backup.fn_get_health_status (@begin_time, @end_time)
	RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

-- Returns Smart Backup configuration details for a given database,
-- when @db_name is NULL or an empty string, info about all databases is returned.
--
CREATE   FUNCTION smart_admin.fn_backup_db_config (@db_name SYSNAME) 
	RETURNS @t TABLE
		(
			db_name						SYSNAME,
			db_guid						UNIQUEIDENTIFIER,
			is_availability_database	BIT,
			is_dropped					BIT,
			is_managed_backup_enabled	BIT,
			credential_name				SYSNAME NULL,
			retention_days				INT,
			storage_url					NVARCHAR(1024),
			encryption_algorithm		SYSNAME NULL,
			encryptor_type				NVARCHAR(32) NULL,
			encryptor_name				SYSNAME NULL
		)
AS
BEGIN
	IF  (HAS_PERMS_BY_NAME(null, null, 'ALTER ANY CREDENTIAL') = 1 AND 
            IS_ROLEMEMBER('db_backupoperator') = 1  AND
	    HAS_PERMS_BY_NAME(null, null, 'VIEW ANY DEFINITION') = 1)
	BEGIN	
	   
		SET @db_name = ISNULL(@db_name, '')

		INSERT INTO @t
		SELECT  
		aamd.db_name, 
		aamd.db_guid,
		CASE 
			WHEN aamd.group_db_guid IS NULL
			THEN CONVERT(BIT, 'false')
			ELSE CONVERT(BIT, 'true')
		END,
		CASE 
			WHEN aamd.drop_date IS NULL 
			THEN CONVERT(BIT, 'false')
			ELSE CONVERT(BIT, 'true')
		END,
		CONVERT(BIT, aatm.task_agent_data.value('(/DBBackupRecord/autoBackupSetting)[1]', 'nvarchar(32)')),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecord/credentialName)[1]', 'nvarchar(128)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecord/retentionPeriod)[1]', 'int'), 0),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecord/URL)[1]', 'nvarchar(128)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecord/encryptionAlgorithm)[1]', 'nvarchar(128)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecord/encryptorType)[1]', 'nvarchar(32)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecord/encryptorName)[1]', 'nvarchar(128)'), '')
		FROM autoadmin_managed_databases aamd 
		RIGHT OUTER JOIN autoadmin_task_agent_metadata aatm
		ON aamd.autoadmin_id = aatm.autoadmin_id
		WHERE 
		(
			QUOTENAME(@db_name) = QUOTENAME('') OR
			QUOTENAME(@db_name) = QUOTENAME(aamd.db_name)
		) AND
		(
			aatm.task_agent_data.exist('/DBBackupRecord') = 1
		)
		AND aamd.autoadmin_id <> 0
	END
	RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

-- Returns the V2 instance configuration parameters
--
CREATE   FUNCTION managed_backup.fn_backup_instance_config () 
	RETURNS @t TABLE
		(
			is_managed_backup_enabled	BIT,
			container_url				NVARCHAR(1024),
			retention_days				INT,
			encryption_algorithm		SYSNAME NULL,
			encryptor_type				NVARCHAR(32) NULL,
			encryptor_name				SYSNAME NULL,
			local_cache_path			NVARCHAR(1024),
			scheduling_option			SYSNAME NULL,
			full_backup_freq_type		SYSNAME NULL,
			days_of_week				NVARCHAR(256),
			backup_begin_time			NVARCHAR(32),
			backup_duration				NVARCHAR(32),
			log_backup_freq				NVARCHAR(32)
		)
AS
BEGIN
	IF  (HAS_PERMS_BY_NAME(null, null, 'ALTER ANY CREDENTIAL') = 1 AND 
            IS_ROLEMEMBER('db_backupoperator') = 1  AND
	    HAS_PERMS_BY_NAME(null, null, 'VIEW ANY DEFINITION') = 1)
	BEGIN		   
	    INSERT INTO @t
	    SELECT
	    CONVERT(BIT, task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";
		(/PD:AutoBackupGlobalDataV2/PD:defaultAutoBackupSetting)[1]', 'nvarchar(32)')),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
	    (/PD:AutoBackupGlobalDataV2/PD:defaultContainerUrl)[1]', 'nvarchar(1024)'), ''),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";
		(/PD:AutoBackupGlobalDataV2/PD:defaultRetentionPeriod)[1]', 'int'), 0),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalDataV2/PD:defaultEncryptionAlgorithm)[1]', 'nvarchar(128)'), ''),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalDataV2/PD:defaultEncryptorType)[1]', 'nvarchar(32)'), ''),
	    NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalDataV2/PD:defaultEncryptorName)[1]', 'nvarchar(128)'), ''),
		NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
	    (/PD:AutoBackupGlobalDataV2/PD:defaultLocalCachePath)[1]', 'nvarchar(1024)'), ''),
		NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalDataV2/PD:defaultSchedulingOption)[1]', 'nvarchar(128)'), ''),
		NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalDataV2/PD:defaultFullBackupFreqType)[1]', 'nvarchar(128)'), ''),
		NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalDataV2/PD:defaultDaysOfWeek)[1]', 'nvarchar(256)'), ''),
		NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalDataV2/PD:defaultBackupBeginTime)[1]', 'nvarchar(32)'), ''),
		NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalDataV2/PD:defaultBackupDuration)[1]', 'nvarchar(32)'), ''),
		NULLIF(task_agent_data.value('declare namespace PD="http://schemas.datacontract.org/2004/07/Microsoft.SqlServer.SmartAdmin.SmartBackupAgent";  
		(/PD:AutoBackupGlobalDataV2/PD:defaultLogBackupFreq)[1]', 'nvarchar(32)'), '')
		FROM autoadmin_task_agent_metadata
		WHERE autoadmin_id = 0 

		IF NOT EXISTS(SELECT TOP 1 1 FROM @t)
		BEGIN
			INSERT INTO @t VALUES (NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL)
		END
	END
	RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

-- Returns Smart Backup configuration details for a given database,
-- when @db_name is NULL or an empty string, info about all databases is returned.
--
CREATE   FUNCTION managed_backup.fn_backup_db_config (@db_name SYSNAME) 
	RETURNS @t TABLE
		(
			db_name						SYSNAME,
			db_guid						UNIQUEIDENTIFIER,
			is_availability_database	BIT,
			is_dropped					BIT,
			is_managed_backup_enabled	BIT,
			container_url				NVARCHAR(1024),
			retention_days				INT,
			encryption_algorithm		SYSNAME NULL,
			encryptor_type				NVARCHAR(32) NULL,
			encryptor_name				SYSNAME NULL,
			local_cache_path			NVARCHAR(1024),
			scheduling_option			SYSNAME NULL,
			full_backup_freq_type		SYSNAME NULL,
			days_of_week				NVARCHAR(256),
			backup_begin_time			NVARCHAR(32),
			backup_duration				NVARCHAR(32),
			log_backup_freq				NVARCHAR(32)
		)
AS
BEGIN
	IF  (HAS_PERMS_BY_NAME(null, null, 'ALTER ANY CREDENTIAL') = 1 AND 
            IS_ROLEMEMBER('db_backupoperator') = 1  AND
	    HAS_PERMS_BY_NAME(null, null, 'VIEW ANY DEFINITION') = 1)
	BEGIN	
		SET @db_name = ISNULL(@db_name, '')

		INSERT INTO @t
		SELECT  
		aamd.db_name, 
		aamd.db_guid,
		CASE 
			WHEN aamd.group_db_guid IS NULL
			THEN CONVERT(BIT, 'false')
			ELSE CONVERT(BIT, 'true')
		END,
		CASE 
			WHEN aamd.drop_date IS NULL 
			THEN CONVERT(BIT, 'false')
			ELSE CONVERT(BIT, 'true')
		END,
		CONVERT(BIT, aatm.task_agent_data.value('(/DBBackupRecordV2/autoBackupSetting)[1]', 'nvarchar(32)')),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/containerURL)[1]', 'nvarchar(1024)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/retentionPeriod)[1]', 'int'), 0),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/encryptionAlgorithm)[1]', 'nvarchar(128)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/encryptorType)[1]', 'nvarchar(32)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/encryptorName)[1]', 'nvarchar(128)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/localCachePath)[1]', 'nvarchar(1024)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/schedulingOption)[1]', 'nvarchar(128)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/fullBackupFreqType)[1]', 'nvarchar(128)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/daysOfWeek)[1]', 'nvarchar(256)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/backupBeginTime)[1]', 'nvarchar(32)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/backupDuration)[1]', 'nvarchar(32)'), ''),
		NULLIF(aatm.task_agent_data.value('(/DBBackupRecordV2/logBackupFreq)[1]', 'nvarchar(32)'), '')
		FROM autoadmin_managed_databases aamd 
		RIGHT OUTER JOIN autoadmin_task_agent_metadata aatm
		ON aamd.autoadmin_id = aatm.autoadmin_id
		WHERE 
		(
			QUOTENAME(@db_name) = QUOTENAME('') OR
			QUOTENAME(@db_name) = QUOTENAME(aamd.db_name)
		) AND
		(
			aatm.task_agent_data.exist('/DBBackupRecordV2') = 1
		)
		AND aamd.autoadmin_id <> 0
		
	END
	RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE   FUNCTION [dbo].[fn_sysutility_ucp_get_policy_violations](@policy_name SYSNAME, @target_query_expression NVARCHAR(max))
RETURNS @data TABLE 
( health_state_id BIGINT ) 
AS
BEGIN

   INSERT INTO @data
    SELECT hs.detail_id
    FROM msdb.dbo.sysutility_ucp_policy_violations hs
    INNER JOIN msdb.dbo.syspolicy_policies p ON hs.policy_id = p.policy_id
    WHERE (hs.target_query_expression_with_id LIKE +'%'+@target_query_expression+'%' ESCAPE '\'
    OR hs.target_query_expression LIKE +'%'+@target_query_expression+'%')
    AND hs.result = 0
    AND p.name = @policy_name
    
   RETURN 
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON


--Look at a period of time, report aggregated number of several type of errors
--When @begin_time and @end_time are not specified, by default look at events in last 30 minutes
--
CREATE   FUNCTION managed_backup.fn_get_health_status (
	@begin_time DATETIME = NULL,
	@end_time DATETIME = NULL
) 
RETURNS @t TABLE(
	number_of_storage_connectivity_errors int,
	number_of_sql_errors int,
	number_of_invalid_credential_errors int,
	number_of_other_errors int,
	number_of_corrupted_or_deleted_backups int,
	number_of_backup_loops int,
	number_of_retention_loops int
	)
AS 
BEGIN 
	DECLARE @logpath NVARCHAR(MAX);
	SELECT TOP 1 @logpath = [path] FROM sys.dm_os_server_diagnostics_log_configurations
	SET @logpath = @logpath + '\ManagedBackupEvents_Backup*.xel';
	DECLARE @adminAndAnalyticXevents TABLE
	(
	event_name NVARCHAR(512),
	event_type int,
	error_code int,
	timestamp DATETIME
	)

	if (@end_time IS NULL)
	BEGIN	
		SELECT @end_time = GETUTCDATE()
	END
	
	if (@begin_time IS NULL)
	BEGIN
		SELECT @begin_time = DATEADD(minute, -30, @end_time)
	END

	--Find most recent analytic events
	INSERT INTO @adminAndAnalyticXevents
	SELECT event_name, event_type, error_code, timestamp
	FROM
	(
		SELECT CAST(event_data AS XML).value('(event/@name)[1]','NVARCHAR(512)') AS event_name, 
			CASE WHEN CAST(event_data AS XML).value('(event/@name)[1]','NVARCHAR(512)') LIKE 'SSMBackup2WA%'		
				THEN
					CAST(event_data AS XML).value('(event/data[@name="error_code"]/value[text()])[1]', 'NVARCHAR(512)') 
				ELSE 
					CAST(event_data AS XML).value('(event/data[@name="event_type"]/value[text()])[1]', 'NVARCHAR(512)')  
				END AS event_type,
			CAST(event_data AS XML).value('(event/data[@name="error_code"]/value[text()])[1]', 'NVARCHAR(512)') 
				AS error_code,
			CAST(event_data AS XML).value('(event/@timestamp)[1]', 'NVARCHAR(512)') AS timestamp
		FROM sys.fn_xe_file_target_read_file(@logpath, NULL, NULL, NULL)
	) t 
	WHERE  (event_name LIKE '%Admin%' OR event_name LIKE '%Analytic%') 
 	AND timestamp >= @begin_time AND timestamp <= @end_time

	DECLARE @numberOfStorageErrors int
	DECLARE @numberOfSqlErrorsFromMainLoop int
	DECLARE @numberOfSqlErrorsFromRetention int	
	DECLARE @numberOfCorruptedOrDeletedBackups int
	DECLARE @numberOfCredentialErrorsFromMainLoop int
	DECLARE @numberOfCredentialErrorsFromRetention int
	DECLARE @numberOfTotalErrors int
	DECLARE @numberOfBackupLoops int
	DECLARE @numberOfRetentionLoops int

	SELECT @numberOfStorageErrors = COUNT(*)
	FROM @adminAndAnalyticXevents
	WHERE event_name = 'FileRetentionAdminXevent' AND event_type = 1 --xstoreError
	AND timestamp >= @begin_time AND timestamp <= @end_time

	-- 10107 = Smart Backup internal error. 
	-- 3288 = SQL Error due to invalid credential, we report them in a separate category.
	--
	SELECT @numberOfSqlErrorsFromMainLoop = COUNT(*)
	FROM @adminAndAnalyticXevents
	WHERE event_name = 'SSMBackup2WAAdminXevent' and error_code != 10107 and error_code != 3288  
	AND timestamp >= @begin_time AND timestamp <= @end_time

	SELECT @numberOfSqlErrorsFromRetention= COUNT(*)
	FROM @adminAndAnalyticXevents
	WHERE event_name = 'FileRetentionAdminXevent' AND event_type = 0 --sqlError
	AND timestamp >= @begin_time AND timestamp <= @end_time

	SELECT @numberOfCredentialErrorsFromRetention = COUNT(*)
	FROM @adminAndAnalyticXevents
	WHERE event_name = 'FileRetentionAdminXevent' AND event_type = 2 --InvalidCredential
	AND timestamp >= @begin_time AND timestamp <= @end_time

	SELECT @numberOfCredentialErrorsFromMainLoop = COUNT(*)
	FROM @adminAndAnalyticXevents
	WHERE event_name = 'SSMBackup2WAAdminXevent' and error_code = 3288 --InvalidCredential SQL Error code
	AND timestamp >= @begin_time AND timestamp <= @end_time

	SELECT @numberOfCorruptedOrDeletedBackups = COUNT(*)
	FROM @adminAndAnalyticXevents
	WHERE event_name = 'FileRetentionAdminXevent' AND event_type = 5 --CORRUPTEDORDELETED FILE
    	AND timestamp >= @begin_time AND timestamp <= @end_time

	SELECT @numberOfTotalErrors = COUNT(*)
	FROM @adminAndAnalyticXevents
	WHERE event_name LIKE '%Admin%'	
        AND timestamp >= @begin_time AND timestamp <= @end_time

	SELECT @numberOfRetentionLoops = COUNT(*)
	FROM @adminAndAnalyticXevents
	WHERE event_name = 'FileRetentionAnalyticXevent'
	AND timestamp >= @begin_time AND timestamp <= @end_time

	SELECT @numberOfBackupLoops = COUNT(*)
	FROM @adminAndAnalyticXevents
	WHERE event_name = 'SSMBackup2WAAnalyticXevent'
	AND timestamp >= @begin_time AND timestamp <= @end_time

	INSERT INTO @t Values(@numberOfStorageErrors, 
		@numberOfSqlErrorsFromMainLoop + @numberOfSqlErrorsFromRetention,
		@numberOfCredentialErrorsFromMainLoop + @numberOfCredentialErrorsFromRetention,
		@numberOfTotalErrors - (@numberOfStorageErrors + @numberOfSqlErrorsFromMainLoop + @numberOfSqlErrorsFromRetention + @numberOfCredentialErrorsFromMainLoop + @numberOfCredentialErrorsFromRetention + @numberOfCorruptedOrDeletedBackups),
		@numberOfCorruptedOrDeletedBackups,
		@numberOfBackupLoops,
		@numberOfRetentionLoops 
	)
	RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON


CREATE   FUNCTION managed_backup.fn_get_current_xevent_settings()
	RETURNS  @t TABLE(
		event_name	NVARCHAR(128),
		is_configurable	NVARCHAR(128),
		is_enabled	NVARCHAR(128)
		)
AS
BEGIN
DECLARE @XEventNames TABLE
	(
	event_name NVARCHAR(128),
	configurable NVARCHAR(128)
	)

	INSERT INTO @t VALUES ('SSMBackup2WAAdminXevent', 'false', 'true')
	INSERT INTO @t VALUES ('SSMBackup2WAOperationalXevent', 'false', 'true')
	INSERT INTO @t VALUES ('SSMBackup2WAAnalyticXevent', 'false', 'true')
	INSERT INTO @t VALUES ('FileRetentionAdminXevent', 'false', 'true')
	INSERT INTO @t VALUES ('FileRetentionAnalyticXevent', 'false', 'true')
	INSERT INTO @XEventNames VALUES ('SSMBackup2WADebugXevent', 'true')
	INSERT INTO @XEventNames VALUES ('FileRetentionOperationalXevent', 'true')
	INSERT INTO @XEventNames VALUES ('FileRetentionDebugXevent', 'true')
	INSERT INTO @XEventNames VALUES ('StorageOperationDebugXevent', 'true')
	
	INSERT INTO @t
	SELECT event_name, configurable,
	CASE  WHEN value IS NULL THEN 'false' ELSE value END AS IsEnabled
	FROM
	(
		SELECT *
		FROM @XEventNames t1 LEFT JOIN
	     autoadmin_system_flags t2 ON t1.event_name = t2.name
	) t
	RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE   FUNCTION managed_backup.fn_get_parameter(@parameter_name NVARCHAR(128))
       RETURNS @t table
       (
              parameter_name       NVARCHAR(128),
              parameter_value      NVARCHAR(MAX)
       )
AS
BEGIN
       SET @parameter_name = ISNULL(@parameter_name, '')

       INSERT INTO @t
       SELECT name, value 
       FROM autoadmin_system_flags
       WHERE 
       (
              QUOTENAME(@parameter_name) = QUOTENAME(N'') OR
              QUOTENAME(@parameter_name) = QUOTENAME(name)
       )

       RETURN
END


SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON


CREATE   VIEW [dbo].[sysdtslog90]
AS
	SELECT [id]
		  ,[event]
		  ,[computer]
		  ,[operator]
		  ,[source]
		  ,[sourceid]
		  ,[executionid]
		  ,[starttime]
		  ,[endtime]
		  ,[datacode]
		  ,[databytes]
		  ,[message]
	  FROM [msdb].[dbo].[sysssislog]



