CREATE EVENT SESSION [WhatisExecuting] ON SERVER 
ADD EVENT sqlserver.rpc_completed(SET collect_statement=(1)
    ACTION(package0.last_error,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.database_name,sqlserver.plan_handle,sqlserver.server_principal_name,sqlserver.session_id)
    WHERE ([package0].[greater_than_equal_uint64]([sqlserver].[database_id],(6)) AND [package0].[less_than_equal_uint64]([sqlserver].[database_id],(9)) AND [package0].[greater_than_uint64]([duration],(20000000)))),
ADD EVENT sqlserver.sql_batch_completed(SET collect_batch_text=(1)
    ACTION(package0.last_error,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.database_name,sqlserver.plan_handle,sqlserver.server_principal_name,sqlserver.session_id)
    WHERE ([package0].[greater_than_equal_uint64]([sqlserver].[database_id],(6)) AND [package0].[less_than_equal_uint64]([sqlserver].[database_id],(9)) AND [package0].[greater_than_uint64]([duration],(20000000)))),
ADD EVENT sqlserver.rpc_starting(SET collect_statement=(1)
    ACTION(package0.last_error,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.database_name,sqlserver.plan_handle,sqlserver.server_principal_name,sqlserver.session_id)
    WHERE ([package0].[greater_than_equal_uint64]([sqlserver].[database_id],(6)) AND [package0].[less_than_equal_uint64]([sqlserver].[database_id],(9)))),
ADD EVENT sqlserver.sql_batch_starting(SET collect_batch_text=(1)
    ACTION(package0.last_error,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.database_name,sqlserver.plan_handle,sqlserver.server_principal_name,sqlserver.session_id)
    WHERE ([package0].[greater_than_equal_uint64]([sqlserver].[database_id],(6)) AND [package0].[less_than_equal_uint64]([sqlserver].[database_id],(9))))
ADD TARGET package0.event_file(SET filename=N'WhatisExecuting',max_file_size=(256),max_rollover_files=(24))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=ON,STARTUP_STATE=OFF)
GO

