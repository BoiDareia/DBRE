USE [msdb]
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE [name] = 'splunk' AND type = 'S')
CREATE USER [splunk] FOR LOGIN [splunk] WITH DEFAULT_SCHEMA=[dbo]
GO

GRANT SELECT ON rds_fn_get_audit_file TO splunk
GO
