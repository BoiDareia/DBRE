SET NOCOUNT ON
GO

/*
	Run this, after both SQLAuditLog jobs are created.
	It will check if the jobs already have schedules, and if not it will assign one for each.
*/

BEGIN TRY
  ----------------------------------------------------------------------------------------------------
  --// Create a temp table to hold the results of sp_help_jobschedule                              //--
  ----------------------------------------------------------------------------------------------------
	IF OBJECT_ID('tempdb.dbo.#JobsInSchedule') IS NOT NULL DROP TABLE dbo.#JobsInSchedule 
	CREATE TABLE dbo.#JobsInSchedule 
	(
		 schedule_id	int	
		,schedule_name sysname	
		,[enabled]	int	
		,freq_type	int
		,freq_interval	int	
		,freq_subday_type	int	
		,freq_subday_interval	int	
		,freq_relative_interval	int	
		,freq_recurrence_factor	int	
		,active_start_date	int	
		,active_end_date	int	
		,active_start_time	int	
		,active_end_time	int	
		,date_created	datetime	
		,schedule_description nvarchar(4000)	
		,next_run_date	int	
		,next_run_time	int	
		,schedule_uid	uniqueidentifier
		,job_count	int	
	)

  ----------------------------------------------------------------------------------------------------
  --// Create the job schedules																	//--
  ----------------------------------------------------------------------------------------------------
	DECLARE @schedule_id int
	DECLARE @job_id uniqueidentifier
	DECLARE @name sysname
	DECLARE @active_start_time INT
    
    --Get new SQL Audit events into SQLAuditLog
	SELECT @job_id = job_id from msdb.dbo.sysjobs where [name] = N'Get new SQL Audit events into SQLAuditLog'
	INSERT INTO dbo.#JobsInSchedule  EXEC msdb.dbo.sp_help_jobschedule @job_id = @job_id

    SELECT @name=N'MTWTFSS x Run ever 30 min on min 15'

	IF (@job_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.#JobsInSchedule))
	BEGIN
        EXEC msdb.dbo.sp_add_jobschedule 
                @job_id = @job_id, 
                @name= @name, 
		        @enabled=1, 
		        @freq_type=4, 
		        @freq_interval=1, 
		        @freq_subday_type=4, 
		        @freq_subday_interval=30, 
		        @freq_relative_interval=0, 
		        @freq_recurrence_factor=1, 
		        @active_start_date=20200525, 
		        @active_end_date=99991231, 
		        @active_start_time=1500, 
		        @active_end_time=235959, 
                @schedule_id = @schedule_id OUTPUT

		-- Finally if all good check if the jobs have been added to schedules
		exec msdb.dbo.sp_help_jobs_in_schedule   @schedule_id =  @schedule_id
	END
	ELSE
	BEGIN
		SELECT * FROM dbo.#JobsInSchedule
	END

	--SQLAuditLog Pruning
	SELECT @job_id = job_id from msdb.dbo.sysjobs where [name] = N'SQLAuditLog Pruning'
	TRUNCATE TABLE dbo.#JobsInSchedule 
	INSERT INTO dbo.#JobsInSchedule  EXEC msdb.dbo.sp_help_jobschedule @job_id = @job_id

	IF (@job_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.#JobsInSchedule))
	BEGIN
		EXEC msdb.dbo.sp_add_jobschedule @job_id, 
				@name=N'MTWTFSS @ 00:00', 
		        @enabled=1, 
		        @freq_type=16, 
		        @freq_interval=1, 
		        @freq_subday_type=1, 
		        @freq_subday_interval=0, 
		        @freq_relative_interval=0, 
		        @freq_recurrence_factor=1, 
		        @active_start_date=20200525, 
		        @active_end_date=99991231,
				@active_start_time=0, 
				@active_end_time=235959, 
                @schedule_id = @schedule_id OUTPUT

		-- Finally if all good check if the jobs have been added to schedules
		exec msdb.dbo.sp_help_jobs_in_schedule   @schedule_id =  @schedule_id
	END
	ELSE
	BEGIN
		SELECT * FROM dbo.#JobsInSchedule
	END
END TRY
BEGIN CATCH
	THROW;
END CATCH
GO
--exec msdb.dbo.sp_detach_schedule  @job_name = N'IndexOptimize - USER_DATABASES', @schedule_id =12
--exec msdb.dbo.sp_detach_schedule  @job_name = N'DatabaseIntegrityCheck - USER_DATABASES', @schedule_id =17
--exec msdb.dbo.sp_detach_schedule  @job_name = N'CommandLog Cleanup', @schedule_id =14
--exec msdb.dbo.sp_delete_schedule @schedule_id = 17
--exec msdb.dbo.sp_delete_schedule @schedule_id = 11
--exec msdb.dbo.sp_delete_schedule @schedule_id = 12
--exec msdb.[dbo].[sp_help_schedule]