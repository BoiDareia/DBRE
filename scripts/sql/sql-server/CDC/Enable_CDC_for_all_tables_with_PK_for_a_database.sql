SET NOCOUNT ON
GO

DECLARE @db_name sysname = DB_NAME()

IF NOT EXISTS (SELECT * FROM sys.databases WHERE database_id = DB_ID() AND is_cdc_enabled = 1)
BEGIN
    EXEC msdb.dbo.rds_cdc_enable_db @db_name
    RAISERROR (N'Enabled CDC on %s database', 0, 1,@db_name) WITH NOWAIT 
END
GO

DECLARE @db_name sysname = DB_NAME()
DECLARE @source_schema sysname = ''
DECLARE @source_name sysname =''
DECLARE @source_objectid INT 
DECLARE @filegroup_name sysname = N'CDC'
DECLARE @cmd NVARCHAR(MAX)

IF NOT EXISTS (SELECT * FROM sys.data_spaces WHERE [name] = @filegroup_name) 
BEGIN 
    SET @cmd = 'ALTER DATABASE [' + @db_name + '] ADD FILEGROUP [' + @filegroup_name + ']'
    RAISERROR (@cmd, 0, 1,@db_name) WITH NOWAIT 
    EXEC sp_executesql @cmd
END 

IF NOT EXISTS (SELECT * FROM sys.database_files df INNER JOIN sys.data_spaces ds ON ds.data_space_id = df.data_space_id WHERE ds.[name] = @filegroup_name) 
BEGIN 
    SET @cmd = 'ALTER DATABASE [' + @db_name + '] ADD FILE ( NAME = N''' + @db_name + '_' + @filegroup_name + ''', FILENAME = N''D:\rdsdbdata\DATA\' + @db_name + '_' + @filegroup_name + '.ndf'', SIZE = 1048576KB , FILEGROWTH = 262144KB ) TO FILEGROUP [' + @filegroup_name + ']'
    RAISERROR (@cmd, 0, 1,@db_name) WITH NOWAIT 
    EXEC sp_executesql @cmd
END

WHILE 1=1
BEGIN
    SELECT TOP(1) @source_schema = sc.name
    FROM sys.tables tab
    INNER JOIN sys.schemas sc ON sc.schema_id = tab.schema_id
    WHERE sc.name > @source_schema
    AND tab.[schema_id] NOT IN( SCHEMA_ID('cdc'),ISNULL(SCHEMA_ID('app_event'),0)) -- Exclude cdc and app_event schemas
    ORDER BY sc.name ASC 

    IF @@ROWCOUNT = 0 BREAK;

    SET @source_name = ''

    WHILE 1=1
    BEGIN 
        SELECT TOP(1) @source_name = tab.[name], @source_objectid = tab.[object_id]
        FROM sys.tables tab
        INNER JOIN sys.indexes pk 
            ON tab.[object_id] = pk.[object_id] and pk.is_primary_key = 1
        WHERE tab.name > @source_name
        AND tab.schema_id = SCHEMA_ID(@source_schema) 
            AND tab.[name] NOT IN ('__RefactorLog','session_token', 'AmazonEmployees', 'ddl_history','last_synchronisation', 'sysdiagrams', 'b2w_csv_file_staging','eligibility_csv_file_staging','UserMfaProviders','TotpUsageLog')
            AND tab.[name] NOT LIKE '%backup%'
            AND tab.[name] NOT LIKE '%tmp%'
            AND tab.[name] NOT LIKE '%temp'
            AND tab.[name] NOT LIKE '%temporary%'
            AND tab.[name] NOT LIKE '%flyway%'
			AND tab.[name] NOT LIKE '%integration_event%'
        ORDER BY schema_name(tab.schema_id) ASC, tab.[name] ASC 

        IF @@ROWCOUNT = 0 BREAK;

        -- if the table is not already published for CDC, enable CDC for it.
        IF NOT EXISTS(SELECT 1 FROM sys.tables WHERE object_id = @source_objectid AND is_tracked_by_cdc = 1)
        BEGIN 
            EXEC sys.sp_cdc_enable_table
                @source_schema = @source_schema,
                @source_name = @source_name,
                @role_name = NULL,
                @filegroup_name = @filegroup_name,
                @supports_net_changes = 1

            RAISERROR (N'CDC enabled for [%s].[%s] table.', 0, 1,@source_schema,@source_name) WITH NOWAIT 
        END
    END
END
GO

EXEC sys.sp_cdc_add_job @job_type = N'capture';
GO

EXEC sys.sp_cdc_add_job @job_type = N'cleanup';
GO

-- Set the retention period for changes to be available on the source
EXEC sys.sp_cdc_change_job @job_type = 'capture', @MaxTrans=500, @pollinginterval = 5
GO
EXEC sp_cdc_change_job @job_type= 'cleanup', @retention = 7200
GO

-- If you are using Amazon RDS with Multi-AZ, make sure that also you set secondary following to have the right values in case of failover.
EXEC rdsadmin.dbo.rds_set_configuration 'cdc_capture_pollinginterval' , 5
GO
EXEC rdsadmin.dbo.rds_set_configuration 'cdc_capture_maxtrans', 500
GO
EXEC rdsadmin.dbo.rds_set_configuration 'cdc_cleanup_retention', 7200
GO

EXEC sys.sp_cdc_stop_job 'capture'
GO
-- and start CDC job
EXEC sys.sp_cdc_start_job 'capture'
GO

/*
    --> Verify that the CDC tables are there
    SELECT TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME 
    FROM INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_SCHEMA = 'cdc'
    AND (TABLE_NAME LIKE 'dbo%' OR TABLE_NAME LIKE 'eRx%')
    ORDER BY TABLE_NAME ASC 
    GO

    SELECT TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME 
    FROM INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_SCHEMA = 'cdc'
    AND TABLE_NAME NOT LIKE 'dbo%'
    AND TABLE_NAME NOT LIKE 'eRx%'
    ORDER BY TABLE_NAME ASC 
    GO
*/
 
 /*
 SELECT * FROM sys.dm_cdc_log_scan_sessions 
 SELECT * FROM  sys.dm_cdc_errors
 SELECT latency FROM sys.dm_cdc_log_scan_sessions WHERE session_id = 0
 SELECT * from sys.dm_cdc_log_scan_sessions where empty_scan_count <> 0

 EXEC sys.sp_cdc_help_jobs 
 EXEC rdsadmin.dbo.rds_show_configuration 'cdc_capture_maxtrans' 
 EXEC rdsadmin.dbo.rds_show_configuration 'cdc_capture_maxscans' 
 EXEC rdsadmin.dbo.rds_show_configuration 'cdc_capture_pollinginterval'  
 EXEC rdsadmin.dbo.rds_show_configuration 'cdc_cleanup_retention'
 SELECT * FROM sys.dm_cdc_log_scan_sessions 
 */
