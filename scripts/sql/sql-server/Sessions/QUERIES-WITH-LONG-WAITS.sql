
--QUERIES WITH WAITS LONGER THAN 500ms

SELECT r.session_id, r.wait_type, r.wait_time AS wait_time_ms
FROM sys.dm_exec_requests r 
   JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id 
WHERE wait_time > 500
AND is_user_process = 1