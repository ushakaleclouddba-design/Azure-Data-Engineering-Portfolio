EXEC master.dbo.sp_addlinkedserver @server = N'NODE1', @srvproduct=N'SQL Server'
 /* For security reasons the linked server remote logins password is changed with ######## */
EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'NODE1',@useself=N'True',@locallogin=NULL,@rmtuser=NULL,@rmtpassword=NULL

EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'collation compatible', @optvalue=N'false'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'data access', @optvalue=N'true'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'dist', @optvalue=N'false'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'pub', @optvalue=N'false'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'rpc', @optvalue=N'true'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'rpc out', @optvalue=N'true'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'sub', @optvalue=N'false'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'connect timeout', @optvalue=N'0'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'collation name', @optvalue=null
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'lazy schema validation', @optvalue=N'false'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'query timeout', @optvalue=N'0'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'use remote collation', @optvalue=N'true'
EXEC master.dbo.sp_serveroption @server=N'NODE1', @optname=N'remote proc transaction promotion', @optvalue=N'true'
