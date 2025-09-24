/*                         
--------------------------------------------------------------------------------------
 Post-Deployment Script: 
 Refresh CDC for any tables with DDL changes, and enable CDC for new tables
 Specific post script for identityprovider database (not to confuse with identityprovider_user database) 
--------------------------------------------------------------------------------------
*/
SET NOCOUNT ON
GO

DECLARE @source_schema sysname = ''
DECLARE @source_name sysname =''
DECLARE @source_objectid INT 
DECLARE @cdc_table_name sysname =''
DECLARE @cdc_table_name_with_schema sysname =''
DECLARE @strSQL NVARCHAR(MAX)

/*
--------------------------------------------------------------------------------------
(A) Disable CDC for any tables CDC is enabled and had DDL changes 
--------------------------------------------------------------------------------------
*/
-- if the database is enabled for cdc
IF EXISTS (SELECT * FROM sys.databases WHERE database_id = DB_ID() AND is_cdc_enabled = 1)
BEGIN
    WHILE 1=1 -- loop the schemas
    BEGIN
        SELECT TOP(1) @source_schema = sc.name
        FROM sys.tables tab
        INNER JOIN sys.schemas sc ON sc.schema_id = tab.schema_id
        WHERE sc.name > @source_schema
        AND tab.[schema_id] NOT IN( SCHEMA_ID('cdc'),ISNULL(SCHEMA_ID('app_event'),0)) -- Exclude cdc and app_event schemas
        ORDER BY sc.name ASC 

        IF @@ROWCOUNT = 0 BREAK;

        SET @source_name = ''

        WHILE 1=1 -- loop the tables for a specific schema
        BEGIN 
            SELECT TOP(1) @source_name = tab.[name], @source_objectid = tab.[object_id]
            FROM sys.tables tab
            INNER JOIN sys.indexes pk 
                ON tab.object_id = pk.object_id and pk.is_primary_key = 1
            WHERE tab.name > @source_name
            AND tab.schema_id = SCHEMA_ID(@source_schema) 
            --AND tab.[name] NOT IN ('__RefactorLog','session_token', 'AmazonEmployees', 'ddl_history','last_synchronisation', 'sysdiagrams','b2w_csv_file_staging','eligibility_csv_file_staging','UserMfaProviders','TotpUsageLog')
            --AND tab.[name] NOT LIKE '%backup%'
            --AND tab.[name] NOT LIKE '%tmp%'
            --AND tab.[name] NOT LIKE '%temp'
            --AND tab.[name] NOT LIKE '%temporary%'
            --AND tab.[name] NOT LIKE '%flyway%'
			and tab.[name] IN ('SamlTenantMappings') 
            ORDER BY schema_name(tab.schema_id) ASC, tab.[name] ASC 

            IF @@ROWCOUNT = 0 BREAK;

            SET @cdc_table_name_with_schema = '[cdc].[' + @source_schema + '_' + @source_name + '_CT]'
            SET @cdc_table_name = @source_schema + '_' + @source_name 

            -- check if the table at hand has CDC enabled
            IF EXISTS(SELECT 1 FROM sys.tables WHERE object_id = @source_objectid AND is_tracked_by_cdc = 1)
            BEGIN 
                -- if the source table had any DDL changes recorded, 
                -- (a) isert a record int dbo.ddl_history (needed trigger initial load for snaplogic pipeline)
                -- (b) truncate the cdc table and
                -- (c) disable CDC for it
                IF EXISTS (SELECT * FROM cdc.ddl_history WHERE source_object_id = @source_objectid)
                BEGIN
                    MERGE dbo.ddl_history AS TARGET
                    USING (
                        SELECT TOP(1) source_object_id, ddl_time 
                        FROM cdc.ddl_history 
                        WHERE source_object_id = @source_objectid
                        ORDER BY ddl_time DESC
                    ) AS SOURCE
                    ON (TARGET.[object_id] = SOURCE.[source_object_id])
                    WHEN MATCHED THEN UPDATE SET TARGET.ddl_time = SOURCE.ddl_time
                    WHEN NOT MATCHED BY TARGET 
                    THEN 
                    INSERT ([object_id], [table_schema], [table_name], [ddl_time]) 
                    VALUES (SOURCE.source_object_id, @source_schema, @source_name, SOURCE.ddl_time); 

                    SET @strSQL = N'TRUNCATE TABLE ' + @cdc_table_name_with_schema -- truncate the CDC table to speed up the sp_cdc_disable_table
                    EXEC sp_executesql @strSQL

                    EXEC sys.sp_cdc_disable_table @source_schema = @source_schema, @source_name = @source_name, @capture_instance = @cdc_table_name

                    RAISERROR (N'CDC now disabled for [%s].[%s] table.', 0, 1, @source_schema, @source_name) WITH NOWAIT 
                END
            END

        END -- end loop tables
    END -- end loop schemas
END

/*
--------------------------------------------------------------------------------------
(B) Enable CDC for new tables and tables that had CDC disabled due to DDL changes 
--------------------------------------------------------------------------------------
*/
-- reset variables
SET @source_schema = ''
SET @source_name = ''
SET @source_objectid = 0

DECLARE @filegroup_name sysname = N'PRIMARY'
IF EXISTS (SELECT * FROM sys.filegroups WHERE name = 'CDC') 
    SET @filegroup_name = N'CDC';

-- if the database is enabled for cdc
IF EXISTS (SELECT * FROM sys.databases WHERE database_id = DB_ID() AND is_cdc_enabled = 1)
BEGIN
    WHILE 1=1 -- loop the schemas
    BEGIN
        SELECT TOP(1) @source_schema = sc.name
        FROM sys.tables tab
        INNER JOIN sys.schemas sc ON sc.schema_id = tab.schema_id
        WHERE sc.name > @source_schema
        AND tab.[schema_id] NOT IN( SCHEMA_ID('cdc'),ISNULL(SCHEMA_ID('app_event'),0))
        ORDER BY sc.name ASC 

        IF @@ROWCOUNT = 0 BREAK;

        SET @source_name = ''

        WHILE 1=1 -- loop the tables for a specific schema
        BEGIN 
            SELECT TOP(1) @source_name = tab.[name], @source_objectid = tab.[object_id]
            FROM sys.tables tab
            INNER JOIN sys.indexes pk 
                ON tab.object_id = pk.object_id and pk.is_primary_key = 1
            WHERE tab.name > @source_name
            AND tab.schema_id = SCHEMA_ID(@source_schema) 
            --AND tab.[name] NOT IN ('__RefactorLog','session_token', 'AmazonEmployees', 'ddl_history','last_synchronisation', 'sysdiagrams','b2w_csv_file_staging','eligibility_csv_file_staging','UserMfaProviders','TotpUsageLog')
            --AND tab.[name] NOT LIKE '%backup%'
            --AND tab.[name] NOT LIKE '%tmp%'
            --AND tab.[name] NOT LIKE '%temp'
            --AND tab.[name] NOT LIKE '%temporary%'
            --AND tab.[name] NOT LIKE '%flyway%'
			and tab.[name] IN ('SamlTenantMappings') 
            ORDER BY schema_name(tab.schema_id) ASC, tab.[name] ASC 

            IF @@ROWCOUNT = 0 BREAK;

            -- if the table is not already published for CDC, enable CDC for it.
            IF NOT EXISTS(SELECT 1 FROM sys.tables WHERE object_id = @source_objectid AND is_tracked_by_cdc = 1)
            BEGIN 
					
				--merge into ddl_history to make sure table rebuilds trigger a full load
				MERGE dbo.ddl_history AS TARGET
				USING (
					SELECT SCHEMA_NAME([schema_id]) AS table_schema, [name] AS table_name
					FROM sys.tables
					WHERE SCHEMA_NAME([schema_id]) = @source_schema AND [name]=@source_name
				) AS SOURCE
				ON (TARGET.[table_schema] = SOURCE.[table_schema] AND TARGET.[table_name] = SOURCE.[table_name])
				WHEN NOT MATCHED BY TARGET 
				THEN 
				INSERT ([object_id], [table_schema], [table_name], [ddl_time]) 
				VALUES (@source_objectid, @source_schema, @source_name, GETUTCDATE());
				
				EXEC sys.sp_cdc_enable_table
                    @source_schema = @source_schema,
                    @source_name = @source_name,
                    @role_name = NULL,
                    @filegroup_name = @filegroup_name,
                    @supports_net_changes = 1

                RAISERROR (N'CDC enabled for [%s].[%s] table.', 0, 1,@source_schema,@source_name) WITH NOWAIT 
            END
        END -- end loop tables
    END -- end loop schemas

END
GO
