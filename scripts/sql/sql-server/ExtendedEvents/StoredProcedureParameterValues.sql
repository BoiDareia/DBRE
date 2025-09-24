CREATE EVENT SESSION [StoredProcedureParameterValues] ON SERVER 
ADD EVENT sqlserver.rpc_starting(SET collect_statement=(1)
    WHERE ([sqlserver].[equal_i_sql_unicode_string]([sqlserver].[database_name],N'core') AND [sqlserver].[equal_i_sql_unicode_string]([object_name],N'shipment_get_active_shipments_by_provider_paged')))
ADD TARGET package0.event_file(SET filename=N'D:\rdsdbdata\Log\StoredProcedureParameterValues.xel',max_file_size=(100))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=ON,STARTUP_STATE=OFF)
GO