
DECLARE @sqlCMD NVARCHAR(MAX), @db_name NVARCHAR(100)

IF EXISTS (SELECT * FROM tempdb.sys.tables WHERE object_id = OBJECT_ID('tempdb.dbo.#db_list'))
BEGIN
    DROP TABLE dbo.[#db_list]
END

CREATE TABLE #db_list(
	[name] NVARCHAR(100),
	[status] BIT DEFAULT(0)
)

INSERT INTO #db_list([name])
SELECT [name]
FROM sys.databases WITH(NOLOCK)
WHERE [name] NOT IN ('master','tempdb','model','msdb','rdsadmin')

WHILE EXISTS(SELECT TOP 1 [name] FROM #db_list WHERE [status] = 0)
BEGIN

	 SELECT TOP 1 @db_name =[name] FROM #db_list WHERE [status] = 0

	 SET @sqlCMD = 'USE ['+@db_name+'] 
	 SELECT '''+@db_name+''' as [database],
			t.[name] AS [Table_Name],
			mc.[name],
			[masking_function]
		FROM sys.masked_columns mc
		JOIN sys.tables t ON mc.object_id = t.object_id'

	PRINT @sqlCMD

	EXEC sp_executesql @sqlCMD

	 UPDATE #db_list SET [status] = 1 WHERE [name] = @db_name

END