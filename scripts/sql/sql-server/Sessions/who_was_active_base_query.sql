USE CompanyMonitor
GO


SELECT -- *
	[dd hh:mm:ss.mss],
	session_id,
	CONVERT(NVARCHAR(MAX),sql_text),
	login_name,
	wait_info,
	CPU,
	tempdb_current,
	tempdb_allocations,
	blocking_session_id,
	blocked_session_count,
	reads,
	writes,
	physical_reads,
	--	query_plan,
	used_memory,
	[status],
	open_tran_count,
	percent_complete,
	[host_name],
	[database_name],
	[program_name],
	start_time,
	login_time,
	request_id,
	collection_time,
	isolation_level
FROM dbo.whowasactive WITH(NOLOCK)
WHERE [collection_time] >= '2024-06-28' AND [collection_time] < '2024-06-29'
	--AND [database_name] = 'core'
	--AND [login_name] != 'rdsa'
	--AND blocking_session_id IS NOT NULL 
	AND blocking_session_id IS  NULL
	AND blocked_session_count > 0
	AND [login_name] NOT IN ('sa','NT AUTHORITY\SYSTEM','dbadmin','rdsa')
--AND [status] = 'sleeping'
--and [open_tran_count] > 0
--AND CONVERT(NVARCHAR(MAX),sql_text) LIKE '%registration_update%'
--AND wait_info IS NULL
--AND [dd hh:mm:ss.mss] LIKE '%:10.%'
--AND [host_name] LIKE 'shop%'
--AND session_id = 109
--AND blocking_session_id IN (2)
--AND login_name = 'sa'
--AND login_name = 'frontend_user'
--AND wait_info LIKE '%LATCH_EX%'
--AND wait_info LIKE '%CX%'
--AND CONVERT(NVARCHAR(MAX),sql_text) LIKE '%registration_activity_log%'



--SELECT COUNT(client_platform_information_id)
--FROM [frontend].[dbo].[client_platform_information]


-- TEST: View running Jobs
--exec msdb.dbo.sp_help_job @execution_status=1

----SELECT MIN([collection_time])
----FROM dbo.whowasactive WITH(NOLOCK)