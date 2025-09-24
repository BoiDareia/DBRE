USE [CompanyMonitor] -- Specify the database in which the objects will be created.
GO
/*
	This one will create 2 SQL agent jobs:
	The 1st one will refrsh SQLAudit table with the latest SQL Audit events from file, every 30 min
	The 2nd one will prune SQLAudit table from all records older than a week.
*/
SET NOCOUNT ON

DECLARE @CreateJobs nvarchar(max)          = 'Y'
-- Specify whether jobs should be created.
DECLARE @LogToTable nvarchar(max)          = 'Y'
-- Log commands to a table.

DECLARE @ErrorMessage nvarchar(max)

IF IS_SRVROLEMEMBER('sysadmin') = 0 AND NOT (DB_ID('rdsadmin') IS NOT NULL AND SUSER_SNAME(0x01) = 'rdsa')
BEGIN
  SET @ErrorMessage = 'You need to be a member of the SysAdmin server role to install the SQL Server Maintenance Solution.'
  RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
END

IF OBJECT_ID('tempdb..#Config') IS NOT NULL DROP TABLE #Config

CREATE TABLE #Config
(
  [Name] nvarchar(max),
  [Value] nvarchar(max)
)

INSERT INTO #Config
  ([Name], [Value])
VALUES('CreateJobs', @CreateJobs)
INSERT INTO #Config
  ([Name], [Value])
VALUES('LogToTable', @LogToTable)
INSERT INTO #Config
  ([Name], [Value])
VALUES('DatabaseName', DB_NAME(DB_ID()))
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF (SELECT [Value]
  FROM #Config
  WHERE Name = 'CreateJobs') = 'Y' AND SERVERPROPERTY('EngineEdition') NOT IN(4, 5) AND (IS_SRVROLEMEMBER('sysadmin') = 1 OR (DB_ID('rdsadmin') IS NOT NULL AND SUSER_SNAME(0x01) = 'rdsa')) AND (SELECT [compatibility_level]
  FROM sys.databases
  WHERE database_id = DB_ID()) >= 90
BEGIN
  DECLARE @LogToTable nvarchar(max)
  DECLARE @DatabaseName nvarchar(max)

  DECLARE @HostPlatform nvarchar(max)
  DECLARE @DirectorySeparator nvarchar(max)
  DECLARE @LogDirectory nvarchar(max)

  DECLARE @TokenServer nvarchar(max)
  DECLARE @TokenJobID nvarchar(max)
  DECLARE @TokenJobName nvarchar(max)
  DECLARE @TokenStepID nvarchar(max)
  DECLARE @TokenStepName nvarchar(max)
  DECLARE @TokenDate nvarchar(max)
  DECLARE @TokenTime nvarchar(max)
  DECLARE @TokenLogDirectory nvarchar(max)

  DECLARE @JobDescription nvarchar(max)
  DECLARE @JobCategory nvarchar(max)
  DECLARE @JobOwner nvarchar(max)

  DECLARE @Jobs TABLE (JobID int IDENTITY,
    [Name] nvarchar(max),
    CommandTSQL nvarchar(max),
    CommandCmdExec nvarchar(max),
    DatabaseName varchar(max),
    OutputFileNamePart01 nvarchar(max),
    OutputFileNamePart02 nvarchar(max),
    Selected bit DEFAULT 0,
    Completed bit DEFAULT 0)

  DECLARE @CurrentJobID int
  DECLARE @jobId BINARY(16)
  DECLARE @CurrentJobName nvarchar(max)
  DECLARE @CurrentCommandTSQL nvarchar(max)
  DECLARE @CurrentCommandCmdExec nvarchar(max)
  DECLARE @CurrentDatabaseName nvarchar(max)
  DECLARE @CurrentOutputFileNamePart01 nvarchar(max)
  DECLARE @CurrentOutputFileNamePart02 nvarchar(max)
  DECLARE @CurrentJobStepCommand nvarchar(max)
  DECLARE @CurrentJobStepSubSystem nvarchar(max)
  DECLARE @CurrentJobStepDatabaseName nvarchar(max)
  DECLARE @CurrentOutputFileName nvarchar(max)

  DECLARE @Version numeric(18,10) = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)), LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))),'.','') AS numeric(18,10))

  DECLARE @AmazonRDS bit = CASE WHEN DB_ID('rdsadmin') IS NOT NULL AND SUSER_SNAME(0x01) = 'rdsa' THEN 1 ELSE 0 END

  IF @Version >= 14
    BEGIN
    SELECT @HostPlatform = host_platform
    FROM sys.dm_os_host_info
  END
    ELSE
    BEGIN
    SET @HostPlatform = 'Windows'
  END

  SELECT @DirectorySeparator = CASE
    WHEN @HostPlatform = 'Windows' THEN '\'
    WHEN @HostPlatform = 'Linux' THEN '/'
    END

  SET @TokenServer = '$' + '(ESCAPE_SQUOTE(SRVR))'
  SET @TokenJobID = '$' + '(ESCAPE_SQUOTE(JOBID))'
  SET @TokenStepID = '$' + '(ESCAPE_SQUOTE(STEPID))'
  SET @TokenDate = '$' + '(ESCAPE_SQUOTE(DATE))'
  SET @TokenTime = '$' + '(ESCAPE_SQUOTE(TIME))'

  IF @Version >= 13
    BEGIN
    SET @TokenJobName = '$' + '(ESCAPE_SQUOTE(JOBNAME))'
    SET @TokenStepName = '$' + '(ESCAPE_SQUOTE(STEPNAME))'
  END

  IF @Version >= 12 AND @HostPlatform = 'Windows'
    BEGIN
    SET @TokenLogDirectory = '$' + '(ESCAPE_SQUOTE(SQLLOGDIR))'
  END

  SELECT @LogToTable = Value
  FROM #Config
  WHERE [Name] = 'LogToTable'

  SELECT @DatabaseName = Value
  FROM #Config
  WHERE [Name] = 'DatabaseName'

  IF @Version >= 11
    BEGIN
    SELECT @LogDirectory = [path]
    FROM sys.dm_os_server_diagnostics_log_configurations
  END
    ELSE
    BEGIN
    SELECT @LogDirectory = LEFT(CAST(SERVERPROPERTY('ErrorLogFileName') AS nvarchar(max)),LEN(CAST(SERVERPROPERTY('ErrorLogFileName') AS nvarchar(max))) - CHARINDEX('\',REVERSE(CAST(SERVERPROPERTY('ErrorLogFileName') AS nvarchar(max)))))
  END

  IF @LogDirectory IS NOT NULL AND RIGHT(@LogDirectory,1) = @DirectorySeparator
    BEGIN
    SET @LogDirectory = LEFT(@LogDirectory, LEN(@LogDirectory) - 1)
  END

  SET @JobDescription = 'Insert into SQLAuditLog table new SQL Audit events from file'
  SET @JobCategory = '[Uncategorized (Local)]'

  IF @AmazonRDS = 0
    BEGIN
    SET @JobOwner = SUSER_SNAME(0x01)
  END

  -- Integrity Checks
  INSERT INTO @Jobs
    ([Name], CommandTSQL, DatabaseName, OutputFileNamePart01)
  SELECT 'Get new SQL Audit events into SQLAuditLog',
    'EXEC [dbo].[sql_auditlog_process]',
    @DatabaseName,
    'GetNewSQLAuditEvents'

  -- TableSizeGrowth pruning
  INSERT INTO @Jobs
    ([Name], CommandTSQL, DatabaseName, OutputFileNamePart01)
  SELECT 'SQLAuditLog Pruning',
    'DELETE FROM [dbo].[SQLAuditLog] ' + CHAR(13) + CHAR(10) + 'WHERE [event_local_time] < DATEADD(dd,-7,GETDATE())',
    @DatabaseName,
    'TableSizeGrowthPruning'

  UPDATE @Jobs
    SET Selected = 1
    WHERE [Name] IN('Get new SQL Audit events into SQLAuditLog','SQLAuditLog Pruning')

  WHILE EXISTS (SELECT *
  FROM @Jobs
  WHERE Completed = 0 AND Selected = 1)
  BEGIN
    SELECT @CurrentJobID = JobID,
      @CurrentJobName = [Name],
      @CurrentCommandTSQL = CommandTSQL,
      @CurrentCommandCmdExec = CommandCmdExec,
      @CurrentDatabaseName = DatabaseName,
      @CurrentOutputFileNamePart01 = OutputFileNamePart01,
      @CurrentOutputFileNamePart02 = OutputFileNamePart02
    FROM @Jobs
    WHERE Completed = 0
      AND Selected = 1
    ORDER BY JobID ASC

    IF @CurrentCommandTSQL IS NOT NULL AND @AmazonRDS = 1
    BEGIN
      SET @CurrentJobStepSubSystem = 'TSQL'
      SET @CurrentJobStepCommand = @CurrentCommandTSQL
      SET @CurrentJobStepDatabaseName = @CurrentDatabaseName
    END

    IF @CurrentJobStepSubSystem IS NOT NULL AND @CurrentJobStepCommand IS NOT NULL AND NOT EXISTS (SELECT *
      FROM msdb.dbo.sysjobs
      WHERE [name] = @CurrentJobName)
    BEGIN
      PRINT 'Creating database maintenance job: "' + @CurrentJobName + '"'

      SET @jobId = NULL

      EXECUTE msdb.dbo.sp_add_job @job_name = @CurrentJobName, @description = @JobDescription, @category_name = @JobCategory, @owner_login_name = @JobOwner, @job_id = @jobId OUTPUT

      EXECUTE	msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Record Job start', 
				@step_id=1, 
				@cmdexec_success_code=0, 
				@on_success_action=3, 
				@on_success_step_id=0, 
				@on_fail_action=3, 
				@on_fail_step_id=0, 
				@retry_attempts=0, 
				@retry_interval=0, 
				@os_run_priority=0, 
				@subsystem=N'TSQL', 
				@command=N'DECLARE @LogTime datetime2 = GETDATE()
DECLARE @Jobname NVARCHAR(128)
SELECT @Jobname = [name] from msdb.dbo.sysjobs WHERE job_id = $(ESCAPE_SQUOTE(JOBID))

INSERT INTO dbo.JobLog ([JobName], [LogTime], [Action])
VALUES(@Jobname, @LogTime, ''Job is Starting'')', 
				@database_name= @CurrentJobStepDatabaseName, 
				@flags=0

      EXECUTE msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name = @CurrentJobName, 
			@step_id=2, 
			@cmdexec_success_code=0, 
			@on_success_action=4, 
			@on_success_step_id=3, 
			@on_fail_action=4, 
			@on_fail_step_id=4, 
			@retry_attempts=0, 
			@retry_interval=0, 
			@os_run_priority=0, 
			@subsystem = @CurrentJobStepSubSystem, 
			@command = @CurrentJobStepCommand, 
			@output_file_name = @CurrentOutputFileName, 
			@database_name = @CurrentJobStepDatabaseName,
			@flags=0

      EXECUTE	msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Record Job Finished with Success', 
				@step_id=3, 
				@cmdexec_success_code=0, 
				@on_success_action=1, 
				@on_success_step_id=0, 
				@on_fail_action=1, 
				@on_fail_step_id=0, 
				@retry_attempts=0, 
				@retry_interval=0, 
				@os_run_priority=0, 
				@subsystem=N'TSQL', 
				@command=N'DECLARE @LogTime datetime2 = GETDATE()
DECLARE @Jobname NVARCHAR(128)
SELECT @Jobname = [name] from msdb.dbo.sysjobs WHERE job_id = $(ESCAPE_SQUOTE(JOBID))

INSERT INTO dbo.JobLog ([JobName], [LogTime], [Action])
VALUES(@Jobname, @LogTime, ''Job completed successfully'')', 
				@database_name= @CurrentJobStepDatabaseName, 
				@flags=0

      EXECUTE	msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Record Job finished with Failure', 
				@step_id=4, 
				@cmdexec_success_code=0, 
				@on_success_action=2, 
				@on_success_step_id=0, 
				@on_fail_action=2, 
				@on_fail_step_id=0, 
				@retry_attempts=0, 
				@retry_interval=0, 
				@os_run_priority=0, 
				@subsystem=N'TSQL', 
				@command=N'DECLARE @LogTime datetime2 = GETDATE()
DECLARE @Jobname NVARCHAR(128)
SELECT @Jobname = [name] from msdb.dbo.sysjobs WHERE job_id = $(ESCAPE_SQUOTE(JOBID))

INSERT INTO dbo.JobLog ([JobName], [LogTime], [Action])
VALUES(@Jobname, @LogTime, ''Job failed. Check CommandLog for details '')', 
				@database_name= @CurrentJobStepDatabaseName, 
				@flags=0

      EXECUTE msdb.dbo.sp_add_jobserver @job_id = @jobId
    END

    UPDATE Jobs
    SET Completed = 1
    FROM @Jobs Jobs
    WHERE JobID = @CurrentJobID

    SET @CurrentJobID = NULL
    SET @CurrentJobName = NULL
    SET @CurrentCommandTSQL = NULL
    SET @CurrentCommandCmdExec = NULL
    SET @CurrentDatabaseName = NULL
    SET @CurrentOutputFileNamePart01 = NULL
    SET @CurrentOutputFileNamePart02 = NULL
    SET @CurrentJobStepCommand = NULL
    SET @CurrentJobStepSubSystem = NULL
    SET @CurrentJobStepDatabaseName = NULL
    SET @CurrentOutputFileName = NULL

  END

END
GO

/*
-- select * from msdb.dbo.sysjobs

-- TEST: Start a job and then check the logs
DECLARE @rc int
EXEC @rc = msdb.dbo.sp_start_job N'Get new SQL Audit events into SQLAuditLog';  
SELECT @rc

SELECT * FROM dbo.JobLog order by 1 desc
GO

-- TEST: View running Jobs
exec msdb.dbo.sp_help_job @execution_status=1
GO

-- TEST: delete a job
DECLARE @job_id uniqueidentifier
SELECT @job_id = job_id from msdb.dbo.sysjobs where [name] = N'Get new SQL Audit events into SQLAuditLog'
EXEC msdb.dbo.sp_delete_job @job_id = @job_id
GO

*/


