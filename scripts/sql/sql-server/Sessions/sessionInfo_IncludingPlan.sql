-- Listing 2.20: A better sp_who2.
SELECT  des.session_id
		,des.status
        ,des.login_name
        ,des.[HOST_NAME]
        ,der.blocking_session_id AS blocked_by_session_id
        ,DB_NAME(der.database_id) AS database_name
        ,der.command
        ,des.cpu_time
        ,des.reads
		,der.logical_reads
        ,des.writes
		,der.writes AS RequestWrite
        ,dec.last_write
		,der.row_count
		,der.granted_query_memory
	--	,der.dop
    --    ,des.[program_name]
        ,der.wait_type
        ,der.wait_time AS wait_time_MilliSec
        ,der.last_wait_type
        ,der.wait_resource
        ,CASE des.transaction_isolation_level
          WHEN 0 THEN 'Unspecified'
          WHEN 1 THEN 'ReadUncommitted'
          WHEN 2 THEN 'ReadCommitted'
          WHEN 3 THEN 'Repeatable'
          WHEN 4 THEN 'Serializable'
          WHEN 5 THEN 'Snapshot'
        END AS transaction_isolation_level
		,COALESCE(QUOTENAME(OBJECT_SCHEMA_NAME(dest.[objectid], der.database_id)) + '.' + QUOTENAME(OBJECT_NAME(dest.[objectid], der.database_id)), '<ad hoc>') AS OBJECT_NAME
        ,SUBSTRING(dest.text, der.statement_start_offset / 2,
                  ( CASE WHEN der.statement_end_offset = -1
                         THEN DATALENGTH(dest.text)
                         ELSE der.statement_end_offset
                    END - der.statement_start_offset ) / 2)
                                          AS [executing statement]
	--	,deqp.query_plan		
		,dec.Local_net_address
        ,dec.local_tcp_port	
		,des.[HOST_NAME]
        ,dec.[client_net_address]
		,dec.client_tcp_port
        --,ot.os_thread_id
		,dec.net_transport
		,dec.protocol_type
		,dec.auth_scheme
	    ,dec.net_transport
FROM    sys.dm_exec_sessions des
LEFT JOIN 
		sys.dm_exec_requests der
		ON	des.session_id = der.session_id
--LEFT JOIN
--		sys.dm_os_tasks AS t		
--		ON	t.session_id = der.session_id
--LEFT JOIN
--		sys.dm_os_threads AS ot
--		ON	t.worker_address = ot.worker_address
LEFT JOIN 
		sys.dm_exec_connections dec
		ON	des.session_id = dec.session_id
OUTER APPLY	
		sys.dm_exec_sql_text(der.sql_handle) dest
OUTER APPLY	
		sys.dm_exec_query_plan(der.plan_handle) deqp
WHERE   des.session_id <> @@SPID
AND		des.status NOT IN ('dormant','sleeping')
--AND der.blocking_session_id > 0
--AND login_name = 'core_user'
--AND COALESCE(QUOTENAME(OBJECT_SCHEMA_NAME(dest.[objectid], der.database_id)) + '.' + QUOTENAME(OBJECT_NAME(dest.[objectid], der.database_id)), '<ad hoc>') = '[dbo].[order_shipment_get_by_reseller_with_outbound_labels_to_print_paginated]'
--AND		DB_NAME(der.database_id) IS NOT NULL

ORDER BY
		--des.session_id
		des.cpu_time

		
	

		
/*
CROSS APPLY	
		sys.dm_exec_sql_text(der.sql_handle) dest
CROSS APPLY	
		sys.dm_exec_query_plan(der.plan_handle) deqp	
--*/



