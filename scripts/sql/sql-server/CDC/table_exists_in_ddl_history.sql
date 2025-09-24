SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[table_exists_in_ddl_history]') AND type in (N'P', N'PC'))
BEGIN
EXEC dbo.sp_executesql @statement = N'CREATE PROCEDURE [dbo].[table_exists_in_ddl_history] AS'
END
GO

/*
    Description: This one will check if the specified table exists in ddl_history and return its schema, and table name if it does

    Test usage:
    EXEC dbo.table_exists_in_ddl_history @schema_name = 'dbo', @table_name = 'external_physician'
*/
ALTER PROCEDURE [dbo].[table_exists_in_ddl_history] (
    @schema_name sysname,
    @table_name sysname
)
AS
BEGIN
    SET NOCOUNT ON

    SELECT table_schema, table_name  FROM dbo.ddl_history WHERE table_schema = @schema_name AND table_name = @table_name
END
GO
