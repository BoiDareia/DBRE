SELECT  DISTINCT p1.spid  AS [Blocking/Root Blocker SPID]
         , p1.[loginame] AS [RootBlocker_Login]
 , st.text AS [SQL Query Text]
         , p1.[CPU]
         , p1.[Physical_IO]
         , DB_NAME(p1.[dbid]) AS DBName
         , p1.[Program_name]
         , p1.[HostName]
         , p1.[Status]
         , p1.[CMD]
         , p1.[Blocked]
         , p1.[ECID] AS [ExecutionContextID]
    FROM  sys.sysprocesses p1
INNER JOIN  sys.sysprocesses p2 ON p1.spid = p2.blocked AND p1.ecid = p2.ecid 
CROSS APPLY sys.dm_exec_sql_text(p1.sql_handle) st
WHERE p1.blocked = 0 
ORDER BY p1.spid, p1.ecid
-- List Down all the blocked processes
    SELECT p2.spid AS 'Blocked SPID'
         , p2.blocked AS 'Blocking/Root Blocker SPID'
         , p2.[loginame] AS [BlockedSPID_Login]
         ,  st.text AS [SQL Query Text]
         , p2.[CPU]
         , p2.[Physical_IO]
         , DB_NAME(p2.[dbid]) AS DBName
         , p2.[Program_name]
         , p2.[HostName]
         , p2.[Status]
         , p2.[CMD]
         , p2.ECID AS [ExecutionContextID]
    FROM sys.sysprocesses p1 
INNER JOIN sys.sysprocesses p2 ON p1.spid = p2.blocked AND p1.ecid = p2.ecid
CROSS APPLY sys.dm_exec_sql_text(p1.sql_handle) st