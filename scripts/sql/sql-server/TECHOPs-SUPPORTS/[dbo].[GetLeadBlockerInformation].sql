USE CompanyMonitor
GO

CREATE PROCEDURE [dbo].[GetLeadBlockerInformation](
	@num_hours SMALLINT = 1
)
AS
BEGIN

	DECLARE @startdate DATETIME,
			@enddate DATETIME

	SET @enddate = GETUTCDATE()

	SET @startdate = DATEADD(HOUR,-@num_hours,@enddate)

	SELECT [session_id], login_name, [database_name], blocked_session_count, REPLACE(REPLACE(REPLACE(REPLACE(SUBSTRING(CONVERT(NVARCHAR(MAX),sql_text),0,300),',',' '), CHAR(9), ''), CHAR(10), ''), CHAR(13), '') AS [Partial_Query], collection_time
	FROM dbo.WhoWasActive WITH(NOLOCK)
	WHERE collection_time >= @startdate AND collection_time <= @enddate
		AND blocking_session_id IS NULL
		AND blocked_session_count > 0

END