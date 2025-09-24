/*
	Snippet is nuts and bolts for creating/moving to an isolated tempdb drive.
	After you run this, SQL Server must be restarted for it to take effect
*/
DECLARE @DriveSizeGB				 INT		   = 75 /* Set to size of drive in GB */
		,@FileCount					 INT		   = 9
		,@InstanceCount				 TINYINT	   = 1
		,@VolumeBuffer				 DECIMAL(8, 2) = .8 /* Set to amount of volume TempDB can fill. */
		,@RowID						 INT
		,@FileSize					 VARCHAR(10)
		,@InitialXPCmdshellValue	 SQL_VARIANT
		,@CreateDirectoryIfNotExists BIT		   = 1	/* Flag to have SQL create the directories if they don't exist */
		,@GreenLight				 BIT		   = 1	/* Flag for proceeding once directories are created, or halting if something is wrong */
		,@xp_cmd					 VARCHAR(255)
		,@xp_cmd_message			 VARCHAR(255)
		,@DrivePath					 VARCHAR(100)  = 'T:\' + @@SERVICENAME + '\'
		,@Debug						 BIT		   = 1;

/* Get Initial xp_cmdshell value */
SELECT @InitialXPCmdshellValue = c.value
FROM sys.configurations AS c
WHERE	c.name LIKE '%xp_cmd%';

/* Placeholder for xp_cmdshell output */
DECLARE @Output TABLE
(
    Column1 VARCHAR(MAX)
);

IF @InitialXPCmdshellValue = 0
BEGIN
    /* Enable xp_cmdshell */
    EXEC sys.sp_configure 'Show Advanced Options', 1;

    RECONFIGURE;

    EXEC sys.sp_configure 'xp_cmdshell', 1;

    RECONFIGURE;
END;

/* Sanitize path */
IF (RIGHT(@DrivePath, 1) <> '\')
BEGIN
    SET @DrivePath = @DrivePath + '\';
END;

IF OBJECT_ID('tempdb..#DataResults') IS NOT NULL
BEGIN
    DROP TABLE #DataResults;
END;

/* Check to ensure directory is valid and accessible by SQL Service */
CREATE TABLE #DataResults
(
    FileExists INT
	,
    IsDirectory INT
	,
    ParentDirExists INT
);

INSERT INTO #DataResults
EXEC master..xp_fileexist @DrivePath;

/************************/
/* Path Validation */
/************************/

/* If specified directory not exists and @CreateDirectory parameter is FALSE */
IF NOT EXISTS (
				  SELECT 1
    FROM #DataResults AS r
    WHERE		r.IsDirectory = 1
			  )
    AND @CreateDirectoryIfNotExists = 0
BEGIN
    SELECT @GreenLight =  0;

    SELECT 'Data directory not exists and @CreateDirectoryIfNotExists is FALSE' AS Message
			, @GreenLight AS GreenLight;
END;

/* If specified directory not exists and @CreateDirectory parameter is TRUE */
ELSE IF NOT EXISTS (
					   SELECT 1
    FROM #DataResults AS r
    WHERE	r.IsDirectory = 1
				   )
    AND @CreateDirectoryIfNotExists = 1
BEGIN
    SET @xp_cmd = 'mkdir ' + @DrivePath;

    INSERT INTO @Output
        (
        Column1
        )
    EXEC master..xp_cmdshell @xp_cmd;

    /* Return message from xp_cmdshell */
    SELECT TOP 1
        @xp_cmd_message = o.Column1
    FROM @Output AS o
    WHERE	o.Column1 IS NOT NULL;

    /* If an error was returned, set GreenLight to FALSE and return message*/
    IF @xp_cmd_message IS NOT NULL
	BEGIN
        SET @GreenLight = 0;

        SELECT 'Problem with path' AS Message
				, @xp_cmd_message AS ErrorMessage
				, @GreenLight AS GreenLight;
    END;
END;

/* Reduce available space if requried by company policy */
IF ISNULL(@VolumeBuffer, 0) > 0
BEGIN
    /* Allocates 80% of volume for TempDB */
    SELECT @DriveSizeGB = (@DriveSizeGB / @InstanceCount) * .8;
END;

/* Converts GB to MB */
SELECT @DriveSizeGB = @DriveSizeGB * 1000;

/* Splits size by the nine files */
SELECT @FileSize = @DriveSizeGB / @FileCount;

/* Table to house requisite SQL statements that will modify the files to the standardized name, and size */
DECLARE @Command TABLE
(
    RowID INT IDENTITY(1, 1)
	,
    Command NVARCHAR(MAX)
);

INSERT INTO @Command
    (
    Command
    )
SELECT 'ALTER DATABASE tempdb MODIFY FILE (NAME = [' + f.name + '],' + ' FILENAME = ''' + @DrivePath + f.name
		+ CASE
			  WHEN f.type = 1 THEN '.ldf'
			  ELSE '.mdf'
		  END + ''', SIZE = ' + @FileSize + ', FILEGROWTH=512);'
FROM sys.master_files AS f
WHERE	f.database_id = DB_ID(N'tempdb');

SET @RowID = @@ROWCOUNT;

/* If there are less files than indicated in @FileCount, add missing lines as ADD FILE commands */
WHILE @RowID < @FileCount
BEGIN
    INSERT INTO @Command
        (
        Command
        )
    SELECT 'ALTER DATABASE tempdb ADD FILE (NAME = [temp' + CAST(@RowID AS VARCHAR) + '],' + ' FILENAME = '''
			+ @DrivePath + 'temp' + CAST(@RowID AS VARCHAR) + '.mdf''' + ', SIZE=' + @FileSize + ', FILEGROWTH=512);';

    SET @RowID = @RowID + 1;
END;

/* Execute each line to process */
WHILE @RowID > 0
BEGIN
    DECLARE @WorkingSQL NVARCHAR(MAX);

    SELECT @WorkingSQL = Command
    FROM @Command
    WHERE	RowID = @RowID;

    PRINT @WorkingSQL;

    IF @Debug = 0
        AND @GreenLight = 1
	BEGIN
        EXEC (@WorkingSQL);
    END;

    SET @RowID = @RowID - 1;
END;

IF @InitialXPCmdshellValue = 0
BEGIN
    /* Enable xp_cmdshell */
    EXEC sys.sp_configure 'Show Advanced Options', 1;

    RECONFIGURE;

    EXEC sys.sp_configure 'xp_cmdshell', 0;

    RECONFIGURE;
END;

IF OBJECT_ID('tempdb..#DataResults') IS NOT NULL
BEGIN
    DROP TABLE #DataResults;
END;