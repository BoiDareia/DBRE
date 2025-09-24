IF EXISTS (SELECT * FROM tempdb.sys.tables WHERE object_id = OBJECT_ID('tempdb.dbo.#deadlock'))
BEGIN
    DROP TABLE dbo.[#deadlock]
END


CREATE TABLE #deadlock  (
        DeadlockID INT IDENTITY PRIMARY KEY CLUSTERED,
        deadlock XML
        );


;WITH cte3 AS
		(
		SELECT    event_data = CONVERT(XML, t2.event_data)
		FROM    sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL) t2
		WHERE    t2.object_name = 'xml_deadlock_report'
		)
		INSERT INTO #deadlock(deadlock)
		SELECT  Deadlock = Deadlock.Report.query('.')
		FROM    cte3    
				CROSS APPLY cte3.event_data.nodes('//event/data/value/deadlock') Deadlock(Report)

		SELECT deadlock
		FROM #deadlock
		WHERE deadlock.value('(deadlock/process-list/process/@lasttranstarted)[1]','DATETIME') >= '2024-10-24'
--		AND deadlock.value('(deadlock/process-list/process/@lasttranstarted)[1]','DATETIME') < '2024-10-05'
--		AND deadlock.value('(deadlock/process-list/process/@currentdbname)[1]','VARCHAR(50)') IN ('orderflowparticipant')