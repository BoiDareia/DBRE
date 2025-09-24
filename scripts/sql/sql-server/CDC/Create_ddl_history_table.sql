
IF NOT EXISTS (SELECT * FROM sys.tables WHERE object_id = OBJECT_ID('dbo.ddl_history'))
BEGIN 
    CREATE TABLE [dbo].[ddl_history]
    (
        [object_id] [int] NOT NULL,
        [table_schema] sysname NOT NULL,
        [table_name] sysname NOT NULL,
        [ddl_time] [datetime] NULL,
        CONSTRAINT [PK_ddl_history] PRIMARY KEY CLUSTERED ([object_id])
    ) 
END 

