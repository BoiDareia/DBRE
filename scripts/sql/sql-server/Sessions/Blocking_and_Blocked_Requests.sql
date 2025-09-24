USE MASTER
GO
-- Search or the Head Blocker (Head Blocker column = 1)
SELECT
   [Session ID]    = s.session_id,
   [Blocker]    = ISNULL(CONVERT (varchar, w.blocking_session_id), 0),
   [Login]         = s.login_name,  
   [Database]      = ISNULL(db_name(p.dbid), N''),
   [Open Transactions] = ISNULL(r.open_transaction_count,0),
   s.status,
   --[Wait Type]    = ISNULL(w.wait_type, N''),
   [Head Blocker]  =
        CASE
            -- session has an active request, is blocked, but is blocking others or session is idle but has an open tran and is blocking others
            WHEN r2.session_id IS NOT NULL AND (r.blocking_session_id = 0 OR r.session_id IS NULL) THEN '1'
            -- session is either not blocking someone, or is blocking someone but is blocked by another party
            ELSE ''
        END,
   [Command]       = ISNULL(r.command, N''),
   [Wait Time (ms)] = ISNULL(w.wait_duration_ms, 0),
   --[Wait Resource] = ISNULL(w.resource_description, N''),
   [Host Name]     = ISNULL(s.host_name, N''),  
   [Application]   = ISNULL(s.program_name, N''),
   --[Total CPU (ms)] = s.cpu_time,
   --[Total Physical I/O (MB)]   = (s.reads + s.writes) * 8 / 1024,
   --[Memory Use (KB)]  = s.memory_usage * 8192 / 1024,
   [Login Time]    = s.login_time,
   [Last Request Start Time] = s.last_request_start_time

FROM sys.dm_exec_sessions s LEFT OUTER JOIN sys.dm_exec_connections c ON (s.session_id = c.session_id)
LEFT OUTER JOIN sys.dm_exec_requests r ON (s.session_id = r.session_id)
LEFT OUTER JOIN sys.dm_os_tasks t ON (r.session_id = t.session_id AND r.request_id = t.request_id)
LEFT OUTER JOIN
(
    -- In some cases (e.g. parallel queries, also waiting for a worker), one thread can be flagged as
    -- waiting for several different threads.  This will cause that thread to show up in multiple rows
    -- in our grid, which we don't want.  Use ROW_NUMBER to select the longest wait for each thread,
    -- and use it as representative of the other wait relationships this thread is involved in.
    SELECT *, ROW_NUMBER() OVER (PARTITION BY waiting_task_address ORDER BY wait_duration_ms DESC) AS row_num
    FROM sys.dm_os_waiting_tasks
) w ON (t.task_address = w.waiting_task_address) AND w.row_num = 1
LEFT OUTER JOIN sys.dm_exec_requests r2 ON (s.session_id = r2.blocking_session_id)
LEFT OUTER JOIN sys.sysprocesses p ON (s.session_id = p.spid)
WHERE s.session_id >50
AND (r2.session_id IS NOT NULL AND (r.blocking_session_id = 0 OR r.session_id IS NULL))
OR blocked >0
ORDER BY s.session_id;


-- Show Blocker and Blocked Sessions
select 
t1.request_session_id as [session sid]  -- spid of waiter
,t2.blocking_session_id as [blocker] -- spid of blocker
,t1.resource_type as [lock type]
,db_name(resource_database_id) as [database]
,t1.resource_associated_entity_id as [blocked object]
,t1.request_mode as [lock req]          -- lock requested
,t2.wait_duration_ms as [wait time] 
,(select text from sys.dm_exec_requests as r  --- get sql for waiter
cross apply sys.dm_exec_sql_text(r.sql_handle) 
where r.session_id = t1.request_session_id) as blocked_batch
,(select substring(qt.text,r.statement_start_offset/2, 
(case when r.statement_end_offset = -1 
then len(convert(nvarchar(max), qt.text)) * 2 
else r.statement_end_offset end - r.statement_start_offset)/2) 
from sys.dm_exec_requests as r
cross apply sys.dm_exec_sql_text(r.sql_handle) as qt
where r.session_id = t1.request_session_id) as blocked_stmt    --- this is the statement executing right now
,(select text from sys.sysprocesses as p        --- get sql for blocker
cross apply sys.dm_exec_sql_text(p.sql_handle) 
where p.spid = t2.blocking_session_id) as blocker_stmt
from
sys.dm_tran_locks as t1, 
sys.dm_os_waiting_tasks as t2
where
t1.lock_owner_address = t2.resource_address
ORDER BY [session sid]
GO