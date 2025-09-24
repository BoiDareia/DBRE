USE CompanyMonitor
GO

-- get aggregared results for a period of time
DECLARE @minDate DATETIME, @maxDate DATETIME, @daysPeriod INT = 1
SELECT @minDate = '2024-06-24 15:00:00'
SELECT @maxDate = '2024-06-24 19:00:00'

SELECT TOP 10
    CONVERT(NVARCHAR(MAX),w.sql_text) AS sql_text, w.database_name,
    COUNT(1) AS number_of_calls,
    SUM(CONVERT(FLOAT,REPLACE(w.CPU,',',''))) AS CPU_total,
    SUM(CONVERT(FLOAT,REPLACE(w.tempdb_allocations,',',''))) AS tempdb_allocations_total,
    SUM(CONVERT(FLOAT,REPLACE(w.reads,',',''))) AS reads_total,
    SUM(CONVERT(FLOAT,REPLACE(w.writes,',',''))) AS writes_total,
    SUM(CONVERT(FLOAT,REPLACE(w.physical_reads,',',''))) AS physical_reads_total,
    SUM(CONVERT(FLOAT,REPLACE(w.used_memory,',',''))) AS used_memory_total--,
--	DATEPART(DAY,w.collection_time) AS [DAY],
--	DATEPART(HOUR,w.collection_time) AS [HOUR]
FROM dbo.WhoWasActive w (NOLOCK)
WHERE w.[database_name] <> 'master' -- exclude queries on system views
    AND w.login_name not in ('dbadmin', 'dbroot') -- exclude DBA tasks
    --AND [database_name] = 'frontend'
    --AND w.[program_name] <> 'RdsAdminService' -- exclude RDS admin tasks
    --AND 
    AND w.collection_time BETWEEN @minDate AND @maxDate
--AND CONVERT(NVARCHAR(MAX),w.sql_text) LIKE '%order_view%'
GROUP BY CONVERT(NVARCHAR(MAX),w.sql_text), w.database_name
--GROUP BY DATEPART(DAY,w.collection_time), DATEPART(HOUR,w.collection_time),CONVERT(NVARCHAR(MAX),w.sql_text), w.database_name
ORDER BY CPU_total DESC--DATEPART(DAY,w.collection_time),DATEPART(HOUR,w.collection_time) asc
GO


