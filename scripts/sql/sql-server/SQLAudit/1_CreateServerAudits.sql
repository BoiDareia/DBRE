USE [master]
GO

CREATE SERVER AUDIT [SQLAudit]
TO FILE 
(	 FILEPATH = N'D:\rdsdbdata\SQLAudit'
	,MAXSIZE = 50 MB
	,RESERVE_DISK_SPACE = ON
)
WITH
(	 QUEUE_DELAY = 1000
	,ON_FAILURE = CONTINUE
	,AUDIT_GUID = '2E636682-9C5E-44E2-9354-BDB6D66C6ED7' -- set the GUID, because we need to create the server audit on the failover server as well
)
WHERE (
    [server_principal_name] <>  'service_user_1' AND
	[server_principal_name] <>  'service_user_2' AND
	[server_principal_name] <> 'NT SERVICE\SQLSERVERAGENT' AND
	[server_principal_name] NOT LIKE  'WORKGROUP\EC2%'
)
GO

ALTER SERVER AUDIT [SQLAudit]
WITH (STATE = ON)
GO

CREATE SERVER AUDIT [LoginAudit]
TO FILE 
(	 FILEPATH = N'D:\rdsdbdata\SQLAudit'
	,MAXSIZE = 50 MB
	,RESERVE_DISK_SPACE = ON
)
WITH
(	QUEUE_DELAY = 1000
	,ON_FAILURE = CONTINUE
	,AUDIT_GUID = '22EFBD50-A969-4EC9-A1D5-5A310992159F' -- set the GUID, because we need to create the server audit on the failover server as well
)
WHERE (
	[server_principal_name] <>  'service_user_1' AND
	[server_principal_name] <>  'service_user_2' AND
	[server_principal_name] NOT LIKE '##MS_Policy%' AND 
    [server_principal_name] NOT LIKE 'NT SERVICE%' AND
    [server_principal_name] <>  'NT AUTHORITY\SYSTEM' AND
	[server_principal_name] NOT LIKE  'WORKGROUP\EC2%'
)
GO

ALTER SERVER AUDIT [LoginAudit]
WITH (STATE = ON)
GO

