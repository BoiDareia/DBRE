USE CompanyMonitor
GO

/*
QUERY TO GET TOTAL EXECUTION COUNTS PER HOUR FOR EACH RECORDED SP (TimeFrame is configurable)

NOTES:

Updated Date: 16-10-2024
Updated By: Alma Elder
Update Ticket: DB-9346

Covers the following 4 scenario's for data quality

1.We have data for every hour interval (24 records for a single day - once an hour) & the plan changes (can handle multiple plan changes)
2.We have data for every hour interval (24 records for a single day - once an hour) & the plan remains the same
3.We have partial data (less the 24 records for a 24h period) & the plan remains the same
4.We have partial data (less the 24 records for a 24h period) & the plan changes (can handle multiple plan changes)

THE AGGREGATIONS CHECK THE FOLLOWING:

1. The "leading/current"(spi) cache time is greater then the "lagging/previous"(spi2) cache time (i.e.plan change)
	a) It will report the leading value because it is the new cumulative value & represents the number of exections etc since the previous plan
2. The leading & lagging cache time are the SAME (i.e. No plan change) AND the leading & lagging values 
for execution count/total worker time/total elapsed time are the SAME.
	a) This means no change since the last capture - no new exections so it reports 0
3. The leading & lagging cache time are the SAME (i.e. No plan change) AND the leading value is higher then the lagging for 
execution count/total worker time/total elapsed time.
	a) This means no plan change BUT that there have been more executions. Lagging value is subtracted from leading value to get the differences

NULL VALUES MEAN THAT THE RESULT DIDN'T FIT ANY OF THE DEFINED AGGREGATION SCENARIO'S
(None seen during last round of testing - 16-10-2024)

SAMPLE DATA CAN BE FOUND IN FILE DB-9346-SP-EXECUTION-COUNTS-SAMPLE-TESTING-DATA IN REPO


*/

DECLARE @startDate DATETIME = '2024-10-14', @endDate DATETIME = '2024-10-15'

CREATE TABLE #delta_information_sp
(
	sp_name VARCHAR(200),
	exe_count INT,
	cpu_total_time BIGINT,
	elapsed_time_total BIGINT,
	polldate DATETIME
)


;WITH
	sp_information
	AS

	(
		SELECT [database_name] + '_' + [object_name] AS [object_name], cached_time, execution_count, total_worker_time, total_elapsed_time, [polldate], ROW_NUMBER() OVER(ORDER BY [object_name],[polldate]) AS[Row]
		FROM dbo.stored_procedure_stats
		WHERE  [database_name] = 'core'

	)
INSERT INTO #delta_information_sp
	(sp_name,exe_count,cpu_total_time,elapsed_time_total,polldate)
SELECT spi.[object_name],
	CASE
			--When "leading" cache time is greater then "lagging" cache time (new plan in cache) 
			--then report the leading execution count ( new cumulative total) 
			WHEN (spi.cached_time > spi2.cached_time) THEN spi.execution_count
			--When "leading" & "lagging" cache time match (same plan) AND counts are the SAME report 0 additional executions
			WHEN (spi.cached_time = spi2.cached_time) AND (spi.execution_count = spi2.execution_count) THEN 0
			--When "leading" & "lagging" cache time match (same plan) BUT leading count is higher Then subtract spi2 from spi 
			WHEN (spi.cached_time = spi2.cached_time) AND (spi.execution_count > spi2.execution_count) THEN spi.execution_count - spi2.execution_count
		END AS [delta_execution_count]
		, CASE
			--When "leading" cache time is greater then "lagging" cache time (new plan in cache) 
			--then report the leading total worker time ( new cumulative total) 
			WHEN (spi.cached_time > spi2.cached_time) THEN spi.total_worker_time
			--When "leading" & "lagging" total worker time match (same plan) AND counts are the SAME report 0 additional total worker time
			WHEN (spi.cached_time = spi2.cached_time) AND (spi.total_worker_time = spi2.total_worker_time) THEN 0
			--When "leading" & "lagging" total worker time match (same plan) BUT leading count is higher Then subtract spi2 from spi 
			WHEN (spi.cached_time = spi2.cached_time) AND (spi.total_worker_time > spi2.total_worker_time) THEN spi.total_worker_time - spi2.total_worker_time
		END AS [delta_total_worker_time]
		, CASE
			--When "leading" cache time is greater then "lagging" cache time (new plan in cache) 
			--then report the leading total elapsed time ( new cumulative total) 
			WHEN (spi.cached_time > spi2.cached_time) THEN spi.total_elapsed_time
			--When "leading" & "lagging" total worker time match (same plan) AND counts are the SAME report 0 additional total worker time
			WHEN (spi.cached_time = spi2.cached_time) AND (spi.total_elapsed_time = spi2.total_elapsed_time) THEN 0
			--When "leading" & "lagging" total worker time match (same plan) BUT leading count is higher Then subtract spi2 from spi 
			WHEN (spi.cached_time = spi2.cached_time) AND (spi.total_elapsed_time > spi2.total_elapsed_time) THEN spi.total_elapsed_time - spi2.total_elapsed_time
		END AS [delta_total_elapsed_time]
		, spi.[polldate]
FROM sp_information spi
	JOIN sp_information spi2 ON spi.[Row] = spi2.[Row]+1
WHERE spi.[polldate] >= @startDate AND spi.[polldate] < @endDate
ORDER BY spi.[object_name], spi.[polldate]



SELECT sp_name,
	SUM(exe_count) AS [total_execution_count_day],
	SUM(cpu_total_time) AS [total_CPU],
	SUM(elapsed_time_total) AS [total_elapsed_time],
	DATEPART(HOUR,polldate) AS [HOUR],
	DATEPART(DAY,polldate) AS [DAY]
--CONVERT(DATE,PollDate) AS PollDay
FROM #delta_information_sp
WHERE sp_name 
IN 
(
'batch_item_get_by_batch_id_paged',
'appointment_vaccination_update_mark_as_completed',
'area_get_list',
'auto_release_rule_activity_log_create',
'b2b_customer_get_filter_item_by_reseller',
'patient_get_by_mobile_number',
'patient_get_by_external_id'
)
--GROUP BY sp_name,CONVERT(DATE,PollDate)
--HAVING SUM(exe_count) > 10
--ORDER BY sp_name,PollDay 
GROUP BY sp_name,DATEPART(HOUR,polldate) ,DATEPART(DAY,polldate)
ORDER BY sp_name,DATEPART(DAY,polldate) ,DATEPART(HOUR,polldate)

DROP TABLE #delta_information_sp