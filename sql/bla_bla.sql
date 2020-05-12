CREATE EVENT SESSION [WhatisExec2mins] ON SERVER 
ADD EVENT sqlserver.sql_batch_completed(SET collect_batch_text=(1)
    ACTION(package0.last_error,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.client_pid
		,sqlserver.database_id,sqlserver.database_name,sqlserver.server_principal_name,sqlserver.session_id)
    WHERE (
	--[sqlserver].[equal_i_sql_unicode_string]([sqlserver].[server_principal_name],N'DETNSW\srvMSPBIOPG') AND 
	--[sqlserver].[equal_i_sql_unicode_string]([sqlserver].[client_hostname],N'PW0000CESDBI01') AND 
	[package0].[greater_than_uint64]([duration],(120000000))))
ADD TARGET package0.event_file(SET filename=N'WhatisExec2mins',max_file_size=(256),max_rollover_files=(24))
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS
,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=ON,STARTUP_STATE=OFF)
GO

select * from sys.databases where database_id = 6

-- list real time BLOCKS
select db_name(tl.resource_database_id) as [database]
	,tl.request_session_id as [waiter]  -- spid of waiter - join to sys.dm_exec_* DMVs as well as sys.sysprocesses 
	,wt.blocking_session_id as [blocker] -- spid of blocker
	,case tl.resource_type
		when 'DATABASE' then db_name(tl.resource_database_id)
		when 'OBJECT' then object_schema_name(tl.resource_associated_entity_id,tl.resource_database_id)+'.'+object_name(tl.resource_associated_entity_id,tl.resource_database_id) 
		else (select object_schema_name(i.object_id,tl.resource_database_id)+'.'+object_name(i.object_id,tl.resource_database_id)+COALESCE('.'+i.name,'') from sys.partitions p inner join sys.indexes i on i.object_id = p.object_id and i.index_id = p.index_id inner join sys.allocation_units au on au.container_id = case au.type % 2 when 0 then p.partition_id else p.hobt_id end where au.container_id = tl.resource_associated_entity_id) 
	end as [blockedObject]
	,CASE WHEN tl.resource_type = 'KEY' THEN 'where %%lockres%% = '''+rtrim(tl.resource_description)+'''' ELSE tl.resource_description END as waitResource	
	,wt.resource_description as lockResourceOwner
	,tl.resource_type
	,tl.request_mode			-- lock requested - Shared (S), Update (U), Exclusive (X), Intent Exclusive (IX)
	,tl.request_status --	GRANT (lock granted) | CONVERT (in process) | WAIT (waiting)
	,tl.request_reference_count as requestCount
	,tl.request_owner_type -- TRANSACTION | CURSOR | SESSION | SHARED_TRANSACTION_WORKSPACE | EXCLUSIVE_TRANSACTION_WORKSPACE
	,tl.request_owner_id as [requestTransactionID] -- the transaction_id for the associated transaction when request_owner_type is TRANSACTION
	,wt.wait_duration_ms as [waitTimeMS]	
	,wt.wait_type 	
	,waitersql.waiterInputBuffer, waitersql.waiterStmt --, waitersql.waiterText	
	,blockersql.blockerInputBuffer, blockersql.blockerStmt -- , blockersql.blockerText	
	--,tl.resource_associated_entity_id as [blkObjectid]
	--,wt.blocking_exec_context_id
from sys.dm_tran_locks as tl
inner join sys.dm_os_waiting_tasks as wt on wt.resource_address = tl.lock_owner_address
outer apply (select waiterInputBuffer=event_info, waiterStmt=substring(qt.text,r.statement_start_offset/2, 
			(case when r.statement_end_offset = -1 
			then len(convert(nvarchar(max), qt.text)) * 2 
			else r.statement_end_offset end - r.statement_start_offset)/2) --, waiterText=qt.text
		from sys.dm_exec_requests as r
		cross apply sys.dm_exec_sql_text(r.sql_handle) as qt
		OUTER APPLY sys.dm_exec_input_buffer(tl.request_session_id, r.request_id) ib -- 2014 SP2
		where r.session_id = tl.request_session_id) as waitersql
outer apply (select blockerInputBuffer=event_info, blockerStmt=substring(qt.text,r.statement_start_offset/2, 
			(case when r.statement_end_offset = -1 
			then len(convert(nvarchar(max), qt.text)) * 2 
			else r.statement_end_offset end - r.statement_start_offset)/2) --, blockerText=qt.text
		from sys.dm_exec_requests as r
		cross apply sys.dm_exec_sql_text(r.sql_handle) as qt
		OUTER APPLY sys.dm_exec_input_buffer(wt.blocking_session_id, r.request_id) ib -- 2014 SP2
		where r.session_id = wt.blocking_session_id) as blockersql


-- Buffer Pool contents by Allocation Unit
SELECT DB=db_name(BD.database_id),Obj=max(isnull(object_schema_name(P.object_id)+'.','')+object_name(P.object_id)),IndexName=max(I.name),BD.database_id,BD.allocation_unit_id
,ObjRows=MAX(P.rows), UsedPages=MAX(A.used_pages),BD.page_type--, is_in_bpool_extension 
,[Rows]=sum(BD.row_count),Pages=count(BD.page_type),freeSpaceKB=sum(free_space_in_bytes)/1024
FROM 	 sys.dm_os_buffer_descriptors BD
inner join sys.allocation_units A on  BD.allocation_unit_id = A.allocation_unit_id
inner join sys.partitions P on A.container_id = case a.type % 2 when 0 then p.partition_id else p.hobt_id end
inner join sys.indexes I on I.object_id = P.object_id and I.index_id = P.index_id
WHERE OBJECTPROPERTY(I.object_id,'IsUserTable') = 1 
	AND (BD.database_id > 4 OR BD.database_id = 2) --AND BD.database_id != 32767 -- if querying all user databases, exclude system & ResourceDB databases 
	--AND BD.database_id = db_id() AND P.object_id = object_id('dbo.ProviderNotificationTracking') -- if querying specific database and table
GROUP BY GROUPING SETS((BD.database_id,BD.allocation_unit_id,BD.page_type),(BD.database_id,BD.allocation_unit_id), (BD.database_id))

-- Number of lock requests per second that resulted in a deadlock.
SELECT sqlserver_start_time,pc.object_name,pc.counter_name,pc.instance_name,pc.cntr_value
,Days=datediff(day, sqlserver_start_time,getdate()),[per day]=pc.cntr_value/datediff(day, sqlserver_start_time,getdate()),SQLVersion=serverproperty('ProductMajorVersion')
FROM sys.dm_os_performance_counters  pc
cross apply sys.dm_os_sys_info si
WHERE cntr_type = 272696576 AND counter_name = 'Number of Deadlocks/sec' and instance_name = '_Total'
and pc.cntr_value/datediff(day, sqlserver_start_time,getdate()) > 20 

exec monitor..sp_WhoIsActive @find_block_leaders=1, @get_full_inner_text = 1, @sort_order = '[blocked_session_count] DESC'
exec monitor..sp_WhoIsActive 
@find_block_leaders=1,@sort_order='[blocked_session_count] DESC'
,@get_full_inner_text=1 
,@get_outer_command=1
--,@get_locks=1
--,@get_plans=1
--,@get_additional_info=1
--,@get_transaction_info=1

use monitor

select * from [SystemMonitoring].[Whoisactive] 
WHERE wait_info not like '%WAITFOR' and wait_info not like '%SP_SERVER_DIAGNOSTICS_SLEEP' and wait_info not like '%BACKUP%'
order by collection_time

select record_id,EventTime,SQLProcessUtilization,OtherProcessUtilization,totalUsage=cpu.SQLProcessUtilization+cpu.OtherProcessUtilization,SystemIdle
from monitor.SystemMonitoring.CPUutilization cpu
--where cpu.SQLProcessUtilization+cpu.OtherProcessUtilization > 50
order by EventTime

batch_text	exec dbo.spGetChangeNotifications


USE master;

declare @db NVARCHAR(128) = 'AG_TEMP1'
declare @cmd NVARCHAR(MAX)
SET @cmd = 'ALTER DATABASE [' + @db + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [' + @db + ']'

--print @cmd
exec sp_executesql @cmd


select * from sys.event_log
where event_category = 'connectivity' and
event_type != 'connection_successful' and 
start_time > '20200506'

