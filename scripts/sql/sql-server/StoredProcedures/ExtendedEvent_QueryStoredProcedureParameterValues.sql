SELECT
n.value('(@timestamp)[1]', 'datetime2') AS [timestamp],
    n.value('(data[@name="statement"]/value)[1]', 'nvarchar(max)') AS STATEMENT
INTO #tmp
FROM (SELECT CAST(event_data AS XML) AS event_data
FROM sys.fn_xe_file_target_read_file('D:\rdsdbdata\Log\StoredProcedureParameterValues*.xel', NULL, NULL, NULL)) ed
CROSS APPLY ed.event_data.nodes('event') AS q(n)

SELECT statement,COUNT(*) FROM #tmp
WHERE statement LIKE '%patient%'
GROUP BY statement
ORDER BY 2 DESC


SELECT * FROM #tmp
WHERE statement LIKE '%patient%'
ORDER BY 1
