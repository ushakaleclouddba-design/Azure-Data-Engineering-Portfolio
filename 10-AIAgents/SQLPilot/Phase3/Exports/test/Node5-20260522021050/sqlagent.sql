EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'MULTI-SERVER', @name=N'[Uncategorized (Multi-Server)]'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Data Collector'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Engine Tuning Advisor'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Full-Text'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Jobs from MSX'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Log Shipping'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-Alert Response'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-Checkup'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-Distribution'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-Distribution Cleanup'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-History Cleanup'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-LogReader'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-Merge'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-QueueReader'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-Snapshot'
GO

EXEC msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-Subscription Cleanup'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'CollectorSchedule_Every_10min', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=10, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20190924, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'3c0fcc15-a466-42fd-913a-0dc757f2bd22'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'CollectorSchedule_Every_15min', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20190924, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'b4829dad-5f2b-4e14-94b0-ccba6ba75bea'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'CollectorSchedule_Every_30min', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=30, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20190924, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'31a8acf3-8160-4287-b14f-a663f4f193c6'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'CollectorSchedule_Every_5min', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=5, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20190924, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'a800fffd-8e7e-4932-a930-97f1343cd6d8'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'CollectorSchedule_Every_60min', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=60, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20190924, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'c00977ba-5e17-49e0-92ea-772c8bc0c303'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'CollectorSchedule_Every_6h', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=6, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20190924, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'01fccd92-6f47-4926-b3ce-b24af3fa37c1'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'Every10Minutes_BankingLoad', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=10, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20260406, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'67f71302-0284-4ded-9c31-ca6e912edaf5'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'Nightly at 02:00', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20260508, 
		@active_end_date=99991231, 
		@active_start_time=20000, 
		@active_end_time=235959, 
		@schedule_uid=N'89cee176-6548-4c68-b492-9d60df348f68'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'RunAsSQLAgentServiceStartSchedule', 
		@enabled=1, 
		@freq_type=64, 
		@freq_interval=0, 
		@freq_subday_type=0, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20190924, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'c6dff703-964d-4864-b6df-14804ad71ec9'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'SSISDB Scheduler', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20001231, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=120000, 
		@schedule_uid=N'9ad26818-0beb-4f85-9904-ae1f583f49c9'
GO

EXEC msdb.dbo.sp_add_schedule @schedule_name=N'syspolicy_purge_history_schedule', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20080101, 
		@active_end_date=99991231, 
		@active_start_time=20000, 
		@active_end_time=235959, 
		@schedule_uid=N'6a99e8c6-9169-4149-88dc-6dcbecc178c8'
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Data Collector' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Data Collector'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'BankingDataLoad_Every10Min', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Loads 10 rows into each of 10 banking databases every 10 minutes. Steps 1-5 use T-SQL random data. Steps 6-10 use SSIS packages with CSV sources.', 
		@category_name=N'Data Collector', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step1_CreditCards_Insert', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
-- Insert 10 random CardHolders
DECLARE @i INT = 1;
DECLARE @FirstNames TABLE (Name NVARCHAR(50));
DECLARE @LastNames TABLE (Name NVARCHAR(50));
INSERT INTO @FirstNames VALUES (''James''),(''Mary''),(''Robert''),(''Patricia''),(''Michael''),(''Linda''),(''William''),(''Barbara''),(''David''),(''Susan'');
INSERT INTO @LastNames VALUES (''Smith''),(''Johnson''),(''Williams''),(''Brown''),(''Jones''),(''Garcia''),(''Miller''),(''Davis''),(''Wilson''),(''Taylor'');

WHILE @i <= 10
BEGIN
    DECLARE @CardHolderID INT;
    DECLARE @FName NVARCHAR(50) = (SELECT TOP 1 Name FROM @FirstNames ORDER BY NEWID());
    DECLARE @LName NVARCHAR(50) = (SELECT TOP 1 Name FROM @LastNames ORDER BY NEWID());
    DECLARE @CreditScore INT = 600 + CAST(RAND() * 250 AS INT);
    DECLARE @Income DECIMAL(18,2) = 40000 + CAST(RAND() * 160000 AS DECIMAL(18,2));

    INSERT INTO dbo.CardHolders (FirstName, LastName, Email, Phone, CreditScore, AnnualIncome)
    VALUES (@FName, @LName, 
            LOWER(@FName) + ''.'' + LOWER(@LName) + CAST(CAST(RAND()*1000 AS INT) AS NVARCHAR) + ''@email.com'',
            ''925-555-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
            @CreditScore, @Income);

    SET @CardHolderID = SCOPE_IDENTITY();

    -- Insert credit card for this holder
    DECLARE @Limit DECIMAL(18,2) = CASE 
        WHEN @CreditScore >= 750 THEN 25000 + CAST(RAND() * 25000 AS DECIMAL(18,2))
        WHEN @CreditScore >= 700 THEN 10000 + CAST(RAND() * 15000 AS DECIMAL(18,2))
        ELSE 2000 + CAST(RAND() * 8000 AS DECIMAL(18,2))
    END;
    DECLARE @Balance DECIMAL(18,2) = CAST(RAND() * @Limit * 0.7 AS DECIMAL(18,2));
    
    INSERT INTO dbo.CreditCards (CardHolderID, CardNumber, CardType, CardTier, CreditLimit, CurrentBalance, AvailableCredit, IssueDate, ExpiryDate, Status)
    VALUES (@CardHolderID,
            ''XXXX-XXXX-XXXX-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
            CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Visa'' WHEN 1 THEN ''Mastercard'' ELSE ''Amex'' END,
            CASE WHEN @CreditScore >= 750 THEN ''Platinum'' WHEN @CreditScore >= 700 THEN ''Gold'' ELSE ''Standard'' END,
            @Limit, @Balance, @Limit - @Balance,
            DATEADD(MONTH, -CAST(RAND()*24 AS INT), GETDATE()),
            DATEADD(YEAR, 3, GETDATE()), ''Active'');

    -- Insert a transaction
    INSERT INTO dbo.CardTransactions (CardID, TransactionDate, MerchantName, MerchantCategory, Amount, TransactionType, Status)
    VALUES (SCOPE_IDENTITY(), GETDATE(),
            CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Amazon'' WHEN 1 THEN ''Walmart'' WHEN 2 THEN ''Target'' WHEN 3 THEN ''Costco'' ELSE ''Shell Gas'' END,
            CASE CAST(RAND()*4 AS INT) WHEN 0 THEN ''Retail'' WHEN 1 THEN ''Grocery'' WHEN 2 THEN ''Gas'' ELSE ''Online'' END,
            CAST(RAND() * 500 AS DECIMAL(18,2)),
            ''Purchase'', ''Approved'');

    SET @i = @i + 1;
END;
PRINT ''Step 1: CreditCards_DB -- 10 rows inserted'';
', 
		@database_name=N'CreditCards_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step2_WealthMgmt_Insert', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @i INT = 1;
WHILE @i <= 10
BEGIN
    DECLARE @ClientID INT;
    DECLARE @NetWorth DECIMAL(18,2) = 500000 + CAST(RAND() * 9500000 AS DECIMAL(18,2));
    
    INSERT INTO dbo.Clients (FirstName, LastName, Email, Phone, NetWorth, RiskProfile, AdvisorID)
    VALUES (
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''John'' WHEN 1 THEN ''Sarah'' WHEN 2 THEN ''Michael'' WHEN 3 THEN ''Emily'' ELSE ''David'' END,
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Chen'' WHEN 1 THEN ''Patel'' WHEN 2 THEN ''Kim'' WHEN 3 THEN ''Singh'' ELSE ''Wang'' END,
        ''client'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR) + ''@wealth.com'',
        ''415-555-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
        @NetWorth,
        CASE WHEN @NetWorth > 5000000 THEN ''Aggressive'' WHEN @NetWorth > 2000000 THEN ''Moderate'' ELSE ''Conservative'' END,
        CAST(RAND()*5 AS INT) + 1
    );
    SET @ClientID = SCOPE_IDENTITY();

    -- Insert portfolio
    DECLARE @PortfolioID INT;
    INSERT INTO dbo.Portfolios (ClientID, PortfolioName, PortfolioType, TotalValue, OpenDate, Status)
    VALUES (@ClientID, 
            ''Portfolio-'' + CAST(@ClientID AS NVARCHAR),
            CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Retirement'' WHEN 1 THEN ''Growth'' ELSE ''Income'' END,
            @NetWorth * 0.6,
            DATEADD(MONTH, -CAST(RAND()*60 AS INT), GETDATE()),
            ''Active'');
    SET @PortfolioID = SCOPE_IDENTITY();

    -- Insert holdings
    INSERT INTO dbo.Holdings (PortfolioID, Symbol, SecurityName, SecurityType, Quantity, PurchasePrice, CurrentPrice, MarketValue)
    VALUES (@PortfolioID,
            CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''AAPL'' WHEN 1 THEN ''MSFT'' WHEN 2 THEN ''GOOGL'' WHEN 3 THEN ''AMZN'' ELSE ''BRK.B'' END,
            CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Apple Inc'' WHEN 1 THEN ''Microsoft Corp'' WHEN 2 THEN ''Alphabet Inc'' WHEN 3 THEN ''Amazon.com'' ELSE ''Berkshire Hathaway'' END,
            CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Stock'' WHEN 1 THEN ''ETF'' ELSE ''Mutual Fund'' END,
            CAST(RAND()*1000 AS DECIMAL(18,4)),
            CAST(100 + RAND()*400 AS DECIMAL(18,4)),
            CAST(100 + RAND()*400 AS DECIMAL(18,4)),
            CAST(RAND()*100000 AS DECIMAL(18,2)));

    SET @i = @i + 1;
END;
PRINT ''Step 2: WealthMgmt_DB -- 10 rows inserted'';
', 
		@database_name=N'WealthMgmt_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step3_Compliance_Insert', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @i INT = 1;
WHILE @i <= 10
BEGIN
    -- Insert Audit Log entry
    INSERT INTO dbo.AuditLog (EventType, TableName, RecordID, OldValue, NewValue, ChangedBy, IPAddress)
    VALUES (
        CASE CAST(RAND()*4 AS INT) WHEN 0 THEN ''INSERT'' WHEN 1 THEN ''UPDATE'' WHEN 2 THEN ''DELETE'' ELSE ''SELECT'' END,
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Accounts'' WHEN 1 THEN ''Transactions'' WHEN 2 THEN ''Customers'' WHEN 3 THEN ''Loans'' ELSE ''CreditCards'' END,
        CAST(RAND()*10000 AS INT),
        ''{"status":"Active","balance":'' + CAST(CAST(RAND()*50000 AS INT) AS NVARCHAR) + ''}'',
        ''{"status":"Updated","balance":'' + CAST(CAST(RAND()*50000 AS INT) AS NVARCHAR) + ''}'',
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''adfuser'' WHEN 1 THEN ''ssisadmin'' ELSE ''appuser'' END,
        ''192.168.1.'' + CAST(CAST(RAND()*254 AS INT) + 1 AS NVARCHAR)
    );

    -- Insert Compliance Alert
    INSERT INTO dbo.ComplianceAlerts (AlertType, Severity, Description, AssignedTo, Status)
    VALUES (
        CASE CAST(RAND()*4 AS INT) WHEN 0 THEN ''AML Violation'' WHEN 1 THEN ''KYC Expiry'' WHEN 2 THEN ''PCI DSS'' ELSE ''SOX Control'' END,
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''High'' WHEN 1 THEN ''Medium'' ELSE ''Low'' END,
        ''Automated compliance check triggered at '' + CONVERT(NVARCHAR, GETDATE(), 120),
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''compliance.team@bank.com'' WHEN 1 THEN ''audit@bank.com'' ELSE ''risk@bank.com'' END,
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Open'' WHEN 1 THEN ''In Progress'' ELSE ''Closed'' END
    );

    SET @i = @i + 1;
END;
PRINT ''Step 3: Compliance_DB -- 10 rows inserted'';
', 
		@database_name=N'Compliance_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step4_FraudDetection_Insert', 
		@step_id=4, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @i INT = 1;
WHILE @i <= 10
BEGIN
    DECLARE @AlertID INT;
    DECLARE @RiskScore DECIMAL(5,2) = CAST(RAND() * 100 AS DECIMAL(5,2));

    INSERT INTO dbo.FraudAlerts (AccountNumber, AlertType, RiskScore, TransactionID, Amount, MerchantName, Location, Status)
    VALUES (
        ''ACC-'' + RIGHT(''00000000'' + CAST(CAST(RAND()*99999999 AS INT) AS NVARCHAR), 8),
        CASE CAST(RAND()*4 AS INT) 
            WHEN 0 THEN ''Unusual Activity'' 
            WHEN 1 THEN ''Card Skimming'' 
            WHEN 2 THEN ''Identity Theft'' 
            ELSE ''Account Takeover'' END,
        @RiskScore,
        ''TXN-'' + CAST(CAST(RAND()*999999 AS INT) AS NVARCHAR),
        CAST(RAND() * 5000 AS DECIMAL(18,2)),
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Unknown Merchant'' WHEN 1 THEN ''Foreign ATM'' WHEN 2 THEN ''Online Purchase'' WHEN 3 THEN ''Wire Transfer'' ELSE ''Cash Advance'' END,
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Lagos, Nigeria'' WHEN 1 THEN ''Moscow, Russia'' WHEN 2 THEN ''Unknown'' WHEN 3 THEN ''San Francisco, CA'' ELSE ''New York, NY'' END,
        CASE WHEN @RiskScore > 75 THEN ''New'' WHEN @RiskScore > 50 THEN ''Under Review'' ELSE ''Dismissed'' END
    );
    SET @AlertID = SCOPE_IDENTITY();

    IF @RiskScore > 70
    BEGIN
        INSERT INTO dbo.FraudCases (AlertID, CaseOpenDate, CaseType, InvestigatorID, Priority, Status)
        VALUES (@AlertID, CAST(GETDATE() AS DATE),
                CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Card Fraud'' WHEN 1 THEN ''Identity Theft'' ELSE ''Account Fraud'' END,
                CAST(RAND()*10 AS INT) + 1,
                CASE WHEN @RiskScore > 90 THEN ''High'' WHEN @RiskScore > 80 THEN ''Medium'' ELSE ''Low'' END,
                ''Open'');
    END;

    SET @i = @i + 1;
END;
PRINT ''Step 4: FraudDetection_DB -- 10 rows inserted'';
', 
		@database_name=N'FraudDetection_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step5_HumanResources_Insert', 
		@step_id=5, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @i INT = 1;
WHILE @i <= 10
BEGIN
    DECLARE @EmployeeID INT;
    DECLARE @DeptID INT = CAST(RAND()*10 AS INT) + 1;
    DECLARE @Salary DECIMAL(18,2) = 50000 + CAST(RAND() * 150000 AS DECIMAL(18,2));

    -- Insert Employee
    INSERT INTO dbo.Employees (FirstName, LastName, Email, Phone, DepartmentID, JobTitle, EmploymentType, HireDate, Salary, Status)
    VALUES (
        CASE CAST(RAND()*6 AS INT) WHEN 0 THEN ''Alex'' WHEN 1 THEN ''Jordan'' WHEN 2 THEN ''Taylor'' WHEN 3 THEN ''Morgan'' WHEN 4 THEN ''Casey'' ELSE ''Riley'' END,
        CASE CAST(RAND()*6 AS INT) WHEN 0 THEN ''Anderson'' WHEN 1 THEN ''Martinez'' WHEN 2 THEN ''Thompson'' WHEN 3 THEN ''Garcia'' WHEN 4 THEN ''Wilson'' ELSE ''Brown'' END,
        ''emp'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR) + ''@bank.com'',
        ''925-555-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
        @DeptID,
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Senior DBA'' WHEN 1 THEN ''Data Engineer'' WHEN 2 THEN ''Business Analyst'' WHEN 3 THEN ''Software Engineer'' ELSE ''Project Manager'' END,
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Full Time'' WHEN 1 THEN ''Part Time'' ELSE ''Contract'' END,
        DATEADD(DAY, -CAST(RAND()*1825 AS INT), GETDATE()),
        @Salary, ''Active''
    );
    SET @EmployeeID = SCOPE_IDENTITY();

    -- Insert Payroll record
    INSERT INTO dbo.Payroll (EmployeeID, PayPeriodStart, PayPeriodEnd, GrossPay, FederalTax, StateTax, SocialSecurity, Medicare, NetPay, PayDate)
    VALUES (@EmployeeID,
            DATEADD(DAY, -14, CAST(GETDATE() AS DATE)),
            CAST(GETDATE() AS DATE),
            @Salary/26,
            @Salary/26 * 0.22,
            @Salary/26 * 0.093,
            @Salary/26 * 0.062,
            @Salary/26 * 0.0145,
            @Salary/26 * (1 - 0.22 - 0.093 - 0.062 - 0.0145),
            CAST(GETDATE() AS DATE));

    SET @i = @i + 1;
END;
PRINT ''Step 5: HumanResources_DB -- 10 rows inserted'';
', 
		@database_name=N'HumanResources_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step6_RetailBanking_SSIS', 
		@step_id=6, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
-- Placeholder until SSIS package is deployed
-- This will be replaced with SSIS subsystem call after deployment
-- Direct T-SQL insert from CSV simulation
INSERT INTO dbo.Customers (FirstName, LastName, Email, Phone, Address, City, State, ZipCode, DateOfBirth, CustomerSince, CustomerType)
SELECT TOP 10
    CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Alice'' WHEN 1 THEN ''Bob'' WHEN 2 THEN ''Carol'' WHEN 3 THEN ''Dan'' ELSE ''Eve'' END,
    CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Adams'' WHEN 1 THEN ''Baker'' WHEN 2 THEN ''Clark'' WHEN 3 THEN ''Dean'' ELSE ''Evans'' END,
    ''retail'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR) + ''@bank.com'',
    ''510-555-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
    CAST(CAST(RAND()*999 AS INT)+1 AS NVARCHAR) + '' Bank St'',
    CASE CAST(RAND()*4 AS INT) WHEN 0 THEN ''Oakland'' WHEN 1 THEN ''Fremont'' WHEN 2 THEN ''Hayward'' ELSE ''Berkeley'' END,
    ''CA'',
    RIGHT(''00000'' + CAST(94500 + CAST(RAND()*99 AS INT) AS NVARCHAR), 5),
    DATEADD(YEAR, -25 - CAST(RAND()*40 AS INT), GETDATE()),
    DATEADD(MONTH, -CAST(RAND()*120 AS INT), GETDATE()),
    CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Retail'' WHEN 1 THEN ''Premium'' ELSE ''Business'' END
FROM (VALUES(1),(2),(3),(4),(5),(6),(7),(8),(9),(10)) AS t(n);
PRINT ''Step 6: RetailBanking_DB -- 10 rows inserted'';
', 
		@database_name=N'RetailBanking_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step7_Mortgage_SSIS', 
		@step_id=7, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @i INT = 1;
WHILE @i <= 10
BEGIN
    DECLARE @BorrowerID INT;
    DECLARE @PropertyID INT;
    DECLARE @LoanAmt DECIMAL(18,2) = 200000 + CAST(RAND()*800000 AS DECIMAL(18,2));

    INSERT INTO dbo.Borrowers (FirstName, LastName, Email, Phone, AnnualIncome, CreditScore, EmploymentStatus)
    VALUES (
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Mark'' WHEN 1 THEN ''Laura'' WHEN 2 THEN ''Steven'' WHEN 3 THEN ''Karen'' ELSE ''Paul'' END,
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Robinson'' WHEN 1 THEN ''Mitchell'' WHEN 2 THEN ''Turner'' WHEN 3 THEN ''Phillips'' ELSE ''Campbell'' END,
        ''borrower'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR) + ''@email.com'',
        ''925-555-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
        60000 + CAST(RAND()*140000 AS DECIMAL(18,2)),
        650 + CAST(RAND()*150 AS INT),
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Employed'' WHEN 1 THEN ''Self-Employed'' ELSE ''Retired'' END
    );
    SET @BorrowerID = SCOPE_IDENTITY();

    INSERT INTO dbo.Properties (Address, City, State, ZipCode, PropertyType, AppraisedValue)
    VALUES (
        CAST(CAST(RAND()*9999 AS INT)+1 AS NVARCHAR) + '' Mortgage Lane'',
        CASE CAST(RAND()*4 AS INT) WHEN 0 THEN ''San Ramon'' WHEN 1 THEN ''Danville'' WHEN 2 THEN ''Pleasanton'' ELSE ''Dublin'' END,
        ''CA'',
        RIGHT(''00000'' + CAST(94500 + CAST(RAND()*99 AS INT) AS NVARCHAR), 5),
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Single Family'' WHEN 1 THEN ''Condo'' ELSE ''Multi-Family'' END,
        @LoanAmt / 0.8
    );
    SET @PropertyID = SCOPE_IDENTITY();

    INSERT INTO dbo.MortgageApplications (BorrowerID, PropertyID, ApplicationDate, LoanAmount, InterestRate, LoanTermYears, LoanType, Status)
    VALUES (@BorrowerID, @PropertyID, CAST(GETDATE() AS DATE),
            @LoanAmt,
            3.5 + CAST(RAND()*2 AS DECIMAL(5,3)),
            CASE CAST(RAND()*2 AS INT) WHEN 0 THEN 15 ELSE 30 END,
            CASE CAST(RAND()*4 AS INT) WHEN 0 THEN ''Fixed'' WHEN 1 THEN ''ARM'' WHEN 2 THEN ''FHA'' ELSE ''VA'' END,
            CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Pending'' WHEN 1 THEN ''Approved'' ELSE ''Under Review'' END);

    SET @i = @i + 1;
END;
PRINT ''Step 7: Mortgage_DB -- 10 rows inserted'';
', 
		@database_name=N'Mortgage_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step8_AutoLoans_SSIS', 
		@step_id=8, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @i INT = 1;
WHILE @i <= 10
BEGIN
    DECLARE @ApplicantID INT;
    DECLARE @VehicleID INT;
    DECLARE @MSRP DECIMAL(18,2) = 20000 + CAST(RAND()*60000 AS DECIMAL(18,2));
    DECLARE @Down DECIMAL(18,2) = @MSRP * 0.2;

    INSERT INTO dbo.LoanApplicants (FirstName, LastName, Email, Phone, CreditScore, AnnualIncome)
    VALUES (
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Chris'' WHEN 1 THEN ''Jessica'' WHEN 2 THEN ''Matthew'' WHEN 3 THEN ''Ashley'' ELSE ''Daniel'' END,
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Parker'' WHEN 1 THEN ''Evans'' WHEN 2 THEN ''Edwards'' WHEN 3 THEN ''Collins'' ELSE ''Stewart'' END,
        ''auto'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR) + ''@email.com'',
        ''510-555-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
        620 + CAST(RAND()*180 AS INT),
        45000 + CAST(RAND()*105000 AS DECIMAL(18,2))
    );
    SET @ApplicantID = SCOPE_IDENTITY();

    INSERT INTO dbo.Vehicles (Make, Model, Year, VIN, Color, Mileage, VehicleType, MSRP)
    VALUES (
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Toyota'' WHEN 1 THEN ''Honda'' WHEN 2 THEN ''Ford'' WHEN 3 THEN ''Chevrolet'' ELSE ''BMW'' END,
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Camry'' WHEN 1 THEN ''Civic'' WHEN 2 THEN ''F-150'' WHEN 3 THEN ''Silverado'' ELSE ''X5'' END,
        2022 + CAST(RAND()*3 AS INT),
        ''VIN'' + CAST(CAST(RAND()*9999999 AS BIGINT) AS NVARCHAR),
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''White'' WHEN 1 THEN ''Black'' WHEN 2 THEN ''Silver'' WHEN 3 THEN ''Blue'' ELSE ''Red'' END,
        CAST(RAND()*50000 AS INT),
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''New'' WHEN 1 THEN ''Used'' ELSE ''Certified'' END,
        @MSRP
    );
    SET @VehicleID = SCOPE_IDENTITY();

    INSERT INTO dbo.AutoLoanApplications (ApplicantID, VehicleID, ApplicationDate, LoanAmount, DownPayment, InterestRate, LoanTermMonths, MonthlyPayment, Status, DealerCode)
    VALUES (@ApplicantID, @VehicleID, CAST(GETDATE() AS DATE),
            @MSRP - @Down, @Down,
            4.5 + CAST(RAND()*4 AS DECIMAL(5,3)),
            CASE CAST(RAND()*3 AS INT) WHEN 0 THEN 36 WHEN 1 THEN 60 ELSE 72 END,
            (@MSRP - @Down) * 0.02,
            CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Approved'' WHEN 1 THEN ''Pending'' ELSE ''Under Review'' END,
            ''DLR00'' + CAST(CAST(RAND()*5 AS INT)+1 AS NVARCHAR));

    SET @i = @i + 1;
END;
PRINT ''Step 8: AutoLoans_DB -- 10 rows inserted'';
', 
		@database_name=N'AutoLoans_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step9_TradeFinance_SSIS', 
		@step_id=9, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=3, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @i INT = 1;
WHILE @i <= 10
BEGIN
    DECLARE @IssuerID INT;
    DECLARE @BenefID INT;

    INSERT INTO dbo.TradeClients (CompanyName, ContactName, Email, Phone, Country, ClientType)
    VALUES (
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Pacific Trade Co'' WHEN 1 THEN ''Bay Imports LLC'' WHEN 2 THEN ''Global Exports Inc'' WHEN 3 THEN ''West Coast Trading'' ELSE ''Harbor Finance Corp'' END,
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''John Lee'' WHEN 1 THEN ''Sarah Wong'' ELSE ''Mike Chen'' END,
        ''trade'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR) + ''@tradeco.com'',
        ''415-555-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
        ''USA'', ''Importer''
    );
    SET @IssuerID = SCOPE_IDENTITY();

    INSERT INTO dbo.TradeClients (CompanyName, ContactName, Email, Phone, Country, ClientType)
    VALUES (
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Shanghai Exports'' WHEN 1 THEN ''Tokyo Trading'' WHEN 2 THEN ''Seoul Manufacturing'' WHEN 3 THEN ''Mumbai Textiles'' ELSE ''Frankfurt GmbH'' END,
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Wei Zhang'' WHEN 1 THEN ''Yuki Tanaka'' ELSE ''Raj Patel'' END,
        ''export'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR) + ''@exports.com'',
        ''+86-21-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
        CASE CAST(RAND()*4 AS INT) WHEN 0 THEN ''China'' WHEN 1 THEN ''Japan'' WHEN 2 THEN ''India'' ELSE ''Germany'' END,
        ''Exporter''
    );
    SET @BenefID = SCOPE_IDENTITY();

    INSERT INTO dbo.LettersOfCredit (LCNumber, IssuingClientID, BeneficiaryID, IssueDate, ExpiryDate, LCAmount, Currency, LCType, Status)
    VALUES (
        ''LC-'' + CONVERT(NVARCHAR, GETDATE(), 112) + ''-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
        @IssuerID, @BenefID,
        CAST(GETDATE() AS DATE),
        DATEADD(MONTH, 6, CAST(GETDATE() AS DATE)),
        100000 + CAST(RAND()*900000 AS DECIMAL(18,2)),
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''USD'' WHEN 1 THEN ''EUR'' ELSE ''GBP'' END,
        CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''Sight'' WHEN 1 THEN ''Usance'' ELSE ''Standby'' END,
        ''Active''
    );

    SET @i = @i + 1;
END;
PRINT ''Step 9: TradeFinance_DB -- 10 rows inserted'';
', 
		@database_name=N'TradeFinance_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step10_Insurance_SSIS', 
		@step_id=10, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
DECLARE @i INT = 1;
WHILE @i <= 10
BEGIN
    DECLARE @HolderID INT;
    DECLARE @PolicyID INT;
    DECLARE @Premium DECIMAL(18,2) = 500 + CAST(RAND()*3500 AS DECIMAL(18,2));

    INSERT INTO dbo.PolicyHolders (FirstName, LastName, Email, Phone, DateOfBirth, Address, City, State)
    VALUES (
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Nancy'' WHEN 1 THEN ''George'' WHEN 2 THEN ''Helen'' WHEN 3 THEN ''Frank'' ELSE ''Donna'' END,
        CASE CAST(RAND()*5 AS INT) WHEN 0 THEN ''Morris'' WHEN 1 THEN ''Rogers'' WHEN 2 THEN ''Reed'' WHEN 3 THEN ''Cook'' ELSE ''Bailey'' END,
        ''ins'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR) + ''@email.com'',
        ''925-555-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
        DATEADD(YEAR, -30 - CAST(RAND()*40 AS INT), GETDATE()),
        CAST(CAST(RAND()*999 AS INT)+1 AS NVARCHAR) + '' Insurance Blvd'',
        CASE CAST(RAND()*4 AS INT) WHEN 0 THEN ''San Ramon'' WHEN 1 THEN ''Oakland'' WHEN 2 THEN ''Fremont'' ELSE ''Hayward'' END,
        ''CA''
    );
    SET @HolderID = SCOPE_IDENTITY();

    INSERT INTO dbo.InsurancePolicies (PolicyHolderID, PolicyNumber, PolicyType, CoverageAmount, PremiumAmount, StartDate, EndDate, Status, AgentID)
    VALUES (@HolderID,
            ''POL-'' + CONVERT(NVARCHAR, GETDATE(), 112) + ''-'' + RIGHT(''0000'' + CAST(CAST(RAND()*9999 AS INT) AS NVARCHAR), 4),
            CASE CAST(RAND()*4 AS INT) WHEN 0 THEN ''Life'' WHEN 1 THEN ''Auto'' WHEN 2 THEN ''Home'' ELSE ''Health'' END,
            100000 + CAST(RAND()*900000 AS DECIMAL(18,2)),
            @Premium,
            CAST(GETDATE() AS DATE),
            DATEADD(YEAR, 1, CAST(GETDATE() AS DATE)),
            ''Active'',
            CAST(RAND()*10 AS INT)+1);
    SET @PolicyID = SCOPE_IDENTITY();

    -- Insert premium payment
    INSERT INTO dbo.Premiums (PolicyID, DueDate, PaidDate, Amount, PaymentMethod, Status)
    VALUES (@PolicyID,
            DATEADD(MONTH, 1, CAST(GETDATE() AS DATE)),
            CAST(GETDATE() AS DATE),
            @Premium,
            CASE CAST(RAND()*3 AS INT) WHEN 0 THEN ''ACH'' WHEN 1 THEN ''Check'' ELSE ''Credit Card'' END,
            ''Paid'');

    SET @i = @i + 1;
END;
PRINT ''Step 10: Insurance_DB -- 10 rows inserted'';
', 
		@database_name=N'Insurance_DB', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Every10Minutes_BankingLoad', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=10, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20260406, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'67f71302-0284-4ded-9c31-ca6e912edaf5'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'SQLPilotDemo - Nightly Audit Roll-up', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Demo job for SQLPilot migration. Calls sp_GetServerHealthSnapshot and writes to Audit_Log.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Run health snapshot', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXEC dbo.sp_GetServerHealthSnapshot;
INSERT INTO dbo.Audit_Log (EventType, EventDetail)
VALUES (''JOB_RUN'', ''Nightly health snapshot completed'');', 
		@database_name=N'SQLPilotDemo', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Nightly at 02:00', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20260508, 
		@active_end_date=99991231, 
		@active_start_time=20000, 
		@active_end_time=235959, 
		@schedule_uid=N'89cee176-6548-4c68-b492-9d60df348f68'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'SSIS Server Maintenance Job', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Runs every day. The job removes operation records from the database that are outside the retention window and maintains a maximum number of versions per project.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'##MS_SSISServerCleanupJobLogin##', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'SSIS Server Operation Records Maintenance', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=3, 
		@retry_interval=3, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
	DECLARE @role int
	SET @role = (SELECT [role] FROM [sys].[dm_hadr_availability_replica_states] hars INNER JOIN [sys].[availability_databases_cluster] adc ON hars.[group_id] = adc.[group_id] WHERE hars.[is_local] = 1 AND adc.[database_name] =''SSISDB'')
	IF DB_ID(''SSISDB'') IS NOT NULL AND (@role IS NULL OR @role = 1)
		EXEC [SSISDB].[internal].[cleanup_server_retention_window]', 
		@database_name=N'msdb', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'SSIS Server Max Version Per Project Maintenance', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=3, 
		@retry_interval=3, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
	DECLARE @role int
	SET @role = (SELECT [role] FROM [sys].[dm_hadr_availability_replica_states] hars INNER JOIN [sys].[availability_databases_cluster] adc ON hars.[group_id] = adc.[group_id] WHERE hars.[is_local] = 1 AND adc.[database_name] =''SSISDB'')
	IF DB_ID(''SSISDB'') IS NOT NULL AND (@role IS NULL OR @role = 1)
		EXEC [SSISDB].[internal].[cleanup_server_project_version]', 
		@database_name=N'msdb', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'SSISDB Scheduler', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20001231, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=120000, 
		@schedule_uid=N'9ad26818-0beb-4f85-9904-ae1f583f49c9'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'syspolicy_purge_history', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Verify that automation is enabled.', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=1, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'IF (msdb.dbo.fn_syspolicy_is_automation_enabled() != 1)
        BEGIN
            RAISERROR(34022, 16, 1)
        END', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Purge history.', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXEC msdb.dbo.sp_syspolicy_purge_history', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Erase Phantom System Health Records.', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'if (''$(ESCAPE_SQUOTE(INST))'' -eq ''MSSQLSERVER'') {$a = ''\DEFAULT''} ELSE {$a = ''''};
(Get-Item SQLSERVER:\SQLPolicy\$(ESCAPE_NONE(SRVR))$a).EraseSystemHealthPhantomRecords()', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'syspolicy_purge_history_schedule', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20080101, 
		@active_end_date=99991231, 
		@active_start_time=20000, 
		@active_end_time=235959, 
		@schedule_uid=N'6a99e8c6-9169-4149-88dc-6dcbecc178c8'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO

