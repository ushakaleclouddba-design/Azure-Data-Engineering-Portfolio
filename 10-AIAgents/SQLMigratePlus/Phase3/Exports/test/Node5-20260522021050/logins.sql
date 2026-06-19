
USE master

GO
IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = 'adfuser') CREATE LOGIN [adfuser] WITH PASSWORD = 0x02005C35B8E00D33D37210DE48533C8F5680B0E6CBE871D76D3C69B260D9EDDB5DF7C76804785A6EFC57DAF8AA80998C1197D5C122B298733AD118010698336C26CD30721883 HASHED, SID = 0x7C6A3E6F2E16FC469D7BEBD8917A51C0, DEFAULT_DATABASE = [master], CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_LANGUAGE = [us_english]
GO

USE master

GO
Grant CONNECT SQL TO [adfuser]  AS [sa]
GO

USE [AcquiredBanks_OnPrem_POC]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'adfuser')
CREATE USER [adfuser] FOR LOGIN [adfuser] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_datareader] ADD MEMBER [adfuser]
GO
Grant CONNECT TO [adfuser]  AS [dbo]
GO

USE [CoreBank_OnPrem_POC]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'adfuser')
CREATE USER [adfuser] FOR LOGIN [adfuser] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_datareader] ADD MEMBER [adfuser]
GO
Grant CONNECT TO [adfuser]  AS [dbo]
GO

USE [LoanProcessing_Staging]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'adfuser')
CREATE USER [adfuser] FOR LOGIN [adfuser] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_datareader] ADD MEMBER [adfuser]
GO
Grant CONNECT TO [adfuser]  AS [dbo]
GO

USE master

GO
IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = 'SqlPilot') CREATE LOGIN [SqlPilot] WITH PASSWORD = 0x02005D0CB1E88E24CF9EAB03ACB990FAE771F8F1D4DB8C1168B05916FDA083A014160C3C413BF292DCCC4D1A4077884617406D066E16C952D63309E7425BA674082C8E508068 HASHED, SID = 0x617E4BF68576B144B20906CE177CD8FF, DEFAULT_DATABASE = [master], CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF, DEFAULT_LANGUAGE = [us_english]
GO
ALTER SERVER ROLE [sysadmin] ADD MEMBER [SqlPilot]
GO

USE master

GO
Grant CONNECT SQL TO [SqlPilot]  AS [sa]
GO

USE master

GO
IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = 'sqlpilot_app') CREATE LOGIN [sqlpilot_app] WITH PASSWORD = 0x02008D32516E411E987F03267A3CC0CEB996A7EF39D29FFE27367322BA55B66F742A15344C9915F3A1D114140F6BED7BACDA82BF7CFE46FE9042261C963E062B5E3411205D3E HASHED, SID = 0xAA42AAB15E2E2B4AA7C6B1F43C9AD9A9, DEFAULT_DATABASE = [master], CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF, DEFAULT_LANGUAGE = [us_english]
GO
ALTER LOGIN [sqlpilot_app] DISABLE
GO

USE master

GO
Grant CONNECT SQL TO [sqlpilot_app]  AS [sa]
GO

USE [SQLPilotDemo]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'sqlpilot_app')
CREATE USER [sqlpilot_app] FOR LOGIN [sqlpilot_app] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_datareader] ADD MEMBER [sqlpilot_app]
GO
Grant CONNECT TO [sqlpilot_app]  AS [dbo]
GO

USE master

GO
IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = 'ssisadmin') CREATE LOGIN [ssisadmin] WITH PASSWORD = 0x020038530827A938449D0F8A442C80BCDFF0ACFC50AE368255050162D4EBF5C01BD7C4D4CE3AD888D0BA686EBA9C207493CA88A647B31D1EA21F7DD308BF966A57D1A6B1640E HASHED, SID = 0x5917B9E2E05324498E2D40E609189A07, DEFAULT_DATABASE = [master], CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_LANGUAGE = [us_english]
GO

USE master

GO
Grant CONNECT SQL TO [ssisadmin]  AS [sa]
GO
Grant VIEW ANY DATABASE TO [ssisadmin]  AS [sa]
GO
Grant VIEW SERVER STATE TO [ssisadmin]  AS [sa]
GO

USE master

GO
IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = 'USHADC0\ushakale') CREATE LOGIN [USHADC0\ushakale] FROM WINDOWS WITH DEFAULT_DATABASE = [master], DEFAULT_LANGUAGE = [us_english]
GO
ALTER SERVER ROLE [sysadmin] ADD MEMBER [USHADC0\ushakale]
GO

USE master

GO
Grant CONNECT SQL TO [USHADC0\ushakale]  AS [sa]
GO

USE [AcquiredBanks_OnPrem_POC]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [AutoLoans_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [BankingDW_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [Compliance_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [CoreBank_OnPrem_POC]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [CreditCards_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [FraudDetection_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [HumanResources_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [Insurance_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [LoanProcessing_Staging]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [master]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'USHADC0\ushakale')
CREATE USER [USHADC0\ushakale] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[USHADC0\ushakale]
GO
ALTER ROLE [RSExecRole] ADD MEMBER [USHADC0\ushakale]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [Mortgage_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [msdb]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'USHADC0\ushakale')
CREATE USER [USHADC0\ushakale] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[USHADC0\ushakale]
GO
ALTER ROLE [RSExecRole] ADD MEMBER [USHADC0\ushakale]
GO
ALTER ROLE [SQLAgentOperatorRole] ADD MEMBER [USHADC0\ushakale]
GO
ALTER ROLE [SQLAgentReaderRole] ADD MEMBER [USHADC0\ushakale]
GO
ALTER ROLE [SQLAgentUserRole] ADD MEMBER [USHADC0\ushakale]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [ReportServer]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [ReportServerTempDB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [RetailBanking_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [SQLPilotDemo]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [TradeFinance_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO

USE [WealthMgmt_DB]

GO
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = N'dbo')
CREATE USER [dbo] FOR LOGIN [USHADC0\ushakale] WITH DEFAULT_SCHEMA=[dbo]
GO
ALTER ROLE [db_owner] ADD MEMBER [dbo]
GO
Grant CONNECT TO [USHADC0\ushakale]  AS [dbo]
GO
