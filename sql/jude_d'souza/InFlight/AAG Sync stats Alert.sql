USE [monitor]
GO

/****** Object:  Table [SystemMonitoring].[AAGSyncStats]    Script Date: 3/03/2020 4:33:27 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

--drop table monitor.SystemMonitoring.whoisactive
CREATE TABLE monitor.SystemMonitoring.Whoisactive ( [dd hh:mm:ss.mss] varchar(16) NULL,[session_id] smallint NOT NULL,[blocking_session_id] smallint NULL,[database_name] nvarchar(128) NULL,[sql_text] xml NULL,[sql_command] xml NULL,[wait_info] nvarchar(4000) NULL,[tran_log_writes] nvarchar(4000) NULL,[reads] varchar(30) NULL,[writes] varchar(30) NULL,[status] varchar(30) NOT NULL,[open_tran_count] varchar(30) NULL,[tran_start_time] datetime NULL,[start_time] datetime NOT NULL,[login_time] datetime NULL,[login_name] nvarchar(128) NOT NULL,[host_name] nvarchar(128) NULL,[program_name] nvarchar(128) NULL,[collection_time] datetime NOT NULL)
--DECLARE @sch VARCHAR(MAX)


CREATE TABLE [SystemMonitoring].[AAGSyncStats](
	[ag_name] [sysname] NULL,
	[database_name] [sysname] NULL,
	[replica_server] [nvarchar](256) NULL,
	[is_local] [bit] NULL,
	[role_desc] [nvarchar](60) NULL,
	[log_reuse_wait_desc] [nvarchar](60) NULL,
	[syncstate] [nvarchar](60) NULL,
	[is_commit_participant] [bit] NULL,
	[synchealth] [nvarchar](60) NULL,
	[is_suspended] [nvarchar](60) NULL,
	[log_send_queue_size] [bigint] NULL,
	[log_send_rate] [bigint] NULL,
	[redo_queue_size] [bigint] NULL,
	[redo_rate] [bigint] NULL,
	[last_hardened_lsn] [numeric](25, 0) NULL,
	[last_hardened_time] [datetime] NULL,
	[secs_behind_primary] [int] NULL,
	[last_sent_lsn] [numeric](25, 0) NULL,
	[last_sent_time] [datetime] NULL,
	[last_received_lsn] [numeric](25, 0) NULL,
	[last_received_time] [datetime] NULL,
	[last_redone_lsn] [numeric](25, 0) NULL,
	[last_redone_time] [datetime] NULL,
	[last_commit_lsn] [numeric](25, 0) NULL,
	[last_commit_time] [datetime] NULL,
	[end_of_log_lsn] [numeric](25, 0) NULL,
	[recovery_lsn] [numeric](25, 0) NULL,
	[truncation_lsn] [numeric](25, 0) NULL,
	[ETA] [datetime] NULL,
	[captureTime] [datetime] NOT NULL
) ON [PRIMARY]
GO



/****** Object:  Table [SystemMonitoring].[AAGSyncStatsThresholds]    Script Date: 3/03/2020 4:33:50 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- DROP TABLE [SystemMonitoring].[AAGSyncStatsThresholds]

CREATE TABLE [SystemMonitoring].[AAGSyncStatsThresholds](
	[th_send_lag_sync] [real] NOT NULL,
	[th_send_lag_async] [real] NOT NULL,
	[th_redo_lag] [real] NOT NULL
) ON [PRIMARY]
GO

-- TRUNCATE TABLE SystemMonitoring.AAGSyncStatsThresholds
insert into SystemMonitoring.AAGSyncStatsThresholds
VALUES (.001, 1, 1)
--(128, 16384, 16384)


--select * from monitor.SystemMonitoring.AAGSyncStatsThresholds
--select * from monitor.[SystemMonitoring].[AAGSyncStats]



USE [msdb]
GO

/****** Object:  Job [DETDBA: Capture AAG Sync Stats]    Script Date: 9/03/2020 4:17:39 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [SystemMonitoring]    Script Date: 9/03/2020 4:17:39 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'SystemMonitoring' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'SystemMonitoring'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DETDBA: Capture AAG Sync Stats', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Capture Availability Group synchronisation stats into monitor.SystemMonitoring.AAGSyncStats and alert if over threshold.

select SendLag=cast(log_send_queue_size/(log_send_rate*1.) as numeric(20,3)),RedoLag=cast(redo_queue_size / (redo_rate * 1.) as numeric(20,3)),* 
from SystemMonitoring.AAGSyncStats drs
cross join SystemMonitoring.AAGSyncStatsThresholds th
where is_local = 0 
order by drs.captureTime, database_name, replica_server', 
		@category_name=N'SystemMonitoring', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [purge history]    Script Date: 9/03/2020 4:17:40 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'purge history', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'delete AAGSyncStats
--select * 
from monitor.SystemMonitoring.AAGSyncStats AAGSyncStats
where captureTime < dateadd(week, -1,  cast(getdate() as date));
', 
		@database_name=N'monitor', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Capture stats]    Script Date: 9/03/2020 4:17:40 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Capture stats', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'/*
USE monitor;
-- DROP TABLE [SystemMonitoring].[AAGSyncStatsThresholds]

CREATE TABLE [SystemMonitoring].[AAGSyncStatsThresholds](
	[th_send_lag_sync] [real] NOT NULL,
	[th_send_lag_async] [real] NOT NULL,
	[th_redo_lag] [real] NOT NULL
) ON [PRIMARY]
GO

-- TRUNCATE TABLE SystemMonitoring.AAGSyncStatsThresholds
insert into SystemMonitoring.AAGSyncStatsThresholds
VALUES (.001, 1, 1)
--(128, 16384, 16384)

select * from SystemMonitoring.AAGSyncStatsThresholds

select SendLag=cast(log_send_queue_size/(log_send_rate*1.) as numeric(20,3)),RedoLag=cast(redo_queue_size / (redo_rate * 1.) as numeric(20,3)),* 
from SystemMonitoring.AAGSyncStats drs
cross join SystemMonitoring.AAGSyncStatsThresholds th
where drs.is_local = 0 
and (
		drs.redo_queue_size/(drs.redo_rate*1.) > th.th_redo_lag 
	OR (drs.is_commit_participant = 0 and drs.log_send_queue_size/(drs.log_send_rate*1.) > th.th_send_lag_async)
	OR (drs.is_commit_participant = 1 and drs.log_send_queue_size/(drs.log_send_rate*1.) > th.th_send_lag_sync))
order by drs.captureTime, database_name, replica_server

*/


DECLARE  @TmpTableVar TABLE(
	[ag_name] [sysname] NULL,
	[database_name] [sysname] NULL,
	[replica_server] [nvarchar](256) NULL,
	[is_local] [bit] NULL,
	[is_commit_participant] [bit] NULL,
	[role_desc] [nvarchar](60) NULL,
	[syncstate] [nvarchar](60) NULL,
	[synchealth] [nvarchar](60) NULL,
	[is_suspended] [nvarchar](60) NULL,
	[log_send_queue_size] [bigint] NULL,
	[log_send_rate] [bigint] NULL,
	[redo_queue_size] [bigint] NULL,
	[redo_rate] [bigint] NULL,
	[ETA] [datetime] NULL
--	,captureTime datetime
) 

INSERT into monitor.SystemMonitoring.AAGSyncStats
OUTPUT 
	INSERTED.ag_name,
	INSERTED.database_name,
	INSERTED.replica_server,
	INSERTED.is_local,
	INSERTED.is_commit_participant,
	INSERTED.role_desc,
	INSERTED.syncstate,
	INSERTED.synchealth,
	INSERTED.is_suspended,
	INSERTED.log_send_queue_size,
	INSERTED.log_send_rate,
	INSERTED.redo_queue_size,
	INSERTED.redo_rate,
	INSERTED.ETA
--	,INSERTED.captureTime
INTO @TmpTableVar
SELECT 
	ag_name=ag.name, 
	adc.database_name, 
	replica_server=ar.replica_server_name,
	drs.is_local, 
	ars.role_desc,
	db.log_reuse_wait_desc,
	syncstate=drs.synchronization_state_desc, 
	drs.is_commit_participant, -- 1 = Transaction commit is synchronized with respect to this database. always 0, for a database on an asynchronous-commit availability replica.
	synchealth=drs.synchronization_health_desc, 
	is_suspended=IIF(drs.is_suspended=1, drs.suspend_reason_desc, ''NO''),
	drs.log_send_queue_size, -- Amount of log records of the primary database that has not been sent to the secondary databases, in kilobytes (KB).
	drs.log_send_rate, 
	drs.redo_queue_size, -- Amount of log records in the log files of the secondary replica that has not yet been redone (replayed), in kilobytes (KB).
	drs.redo_rate,
	drs.last_hardened_lsn, -- any LSN < the value of last_hardened_lsn is on disk    on a secondary database.   
	drs.last_hardened_time, secs_behind_primary=datediff(ss,drs.last_hardened_time,getdate()),
	drs.last_sent_lsn, --Log block ID that indicates the point up to which all log blocks have been sent by the primary. This is the ID of the next log block that will be sent, rather than the ID of the most recently sent log block.
	drs.last_sent_time, 
	drs.last_received_lsn, --Log block ID identifying the point up to which all log blocks have been received by the secondary replica that hosts this secondary database.
	drs.last_received_time, 
	drs.last_redone_lsn, --Actual LSN of the last log record that was redone on the secondary database. last_redone_lsn is always less than last_hardened_lsn.
	drs.last_redone_time, 
	drs.last_commit_lsn, --For the primary db, this is last commit record processed. Rows for secondary dbs show the LSN that the secondary replica has sent to the primary replica. On the secondary replica, this is the last commit record that was redone.
	drs.last_commit_time,
	drs.end_of_log_lsn, --log-block ID corresponding to the last log record in the log cache on the primary and secondary databases.  On the primary replica, the secondary rows reflect the end of log LSN from the latest progress messages that the secondary replicas have sent to the primary replica.
	drs.recovery_lsn, --On the primary replica, the end of the transaction log before the primary database writes any new log records after recovery or failover. For a given secondary database, if this value is less than the current hardened LSN (last_hardened_lsn), recovery_lsn is the value to which this secondary database would need to resynchronize (that is, to revert to and reinitialize to). If this value is greater than or equal to the current hardened LSN, resynchronization would be unnecessary and would not occur.
	drs.truncation_lsn, -- On the primary replica, for the primary database, reflects the minimum log truncation LSN across all the corresponding secondary databases. If local log truncation is blocked (eg. a backup operation), this LSN might be higher than the local truncation LSN. For a given secondary database, reflects the truncation point of that database.
	ETA=case when redo_rate = 0 then null else dateadd(MILLISECOND,redo_queue_size / (redo_rate * 1.)*1000,getdate()) end,
	captureTime = getdate()
--into monitor.SystemMonitoring.AAGSyncStats
FROM sys.dm_hadr_database_replica_states AS drs
LEFT JOIN sys.dm_hadr_availability_replica_states ars ON drs.group_id = ars.group_id AND drs.replica_id = ars.replica_id
LEFT JOIN sys.availability_databases_cluster AS adc ON drs.group_id = adc.group_id AND drs.group_database_id = adc.group_database_id
LEFT JOIN sys.databases db on db.name = adc.database_name and drs.is_local = 1
LEFT JOIN sys.availability_groups AS ag ON ag.group_id = drs.group_id
LEFT JOIN sys.availability_replicas AS ar ON drs.group_id = ar.group_id AND drs.replica_id = ar.replica_id
inner join (
	select ars.group_id from sys.dm_hadr_availability_replica_states ars where (ars.is_local & ars.role) = 1 -- Capture if Local is Primary
) as Pri (group_id) on Pri.group_id = drs.group_id
--order by drs.is_local desc

DECLARE @xml NVARCHAR(MAX) = NULL;
SELECT @xml = CAST(( 
select 
	@@Servername AS ''td'','''',
	tmp.ag_name AS ''td'','''',
	tmp.database_name AS ''td'','''',
	tmp.replica_server AS ''td'','''',
	tmp.syncstate AS ''td'','''',
	tmp.synchealth AS ''td'','''',
	tmp.is_suspended AS ''td'','''',
	convert(varchar(24), cast(tmp.log_send_queue_size/(tmp.log_send_rate*1.) as numeric(20,3))) AS ''td'','''',
	convert(varchar(24), cast(tmp.redo_queue_size/(tmp.redo_rate*1.) as numeric(20,3))) AS ''td'','''',
	convert(VARCHAR(24), tmp.ETA, 121) AS ''td'',''''
from  @TmpTableVar tmp
cross join SystemMonitoring.AAGSyncStatsThresholds th
where tmp.is_local = 0 
and (	tmp.redo_queue_size/(tmp.redo_rate*1.) > th.th_redo_lag 
	OR (tmp.is_commit_participant = 0 and tmp.log_send_queue_size/(tmp.log_send_rate*1.) > th.th_send_lag_async)
	OR (tmp.is_commit_participant = 1 and tmp.log_send_queue_size/(tmp.log_send_rate*1.) > th.th_send_lag_sync))
FOR XML PATH(''tr''), ELEMENTS ) AS NVARCHAR(MAX))

if not @xml is null
begin
	if exists (select * from msdb.dbo.sysjobs where name = N''DETDBA: Capture Whoisactive'')
		EXEC msdb.dbo.sp_start_job N''DETDBA: Capture Whoisactive'' -- capture activity

	-- Send the alert
	DECLARE @body NVARCHAR(MAX)

	SET @body =''<html><body>
	<H1 align="center" style="color:red">AAG SYNCHRONIZATION Alert</H1>
	<table border="1" bordercolor="lime" width="100%">
	<tr bgcolor="cornsilk" style="color:darkred">
	<th> primary </th>
	<th> AAG </th>
	<th> database </th>
	<th> replica </th>
	<th> syncState </th>
	<th> syncHealth </th>
	<th> suspended? </th>
	<th> sendLag </th>
	<th> redoLag(KB) </th>
	<th> ETA </th>
	</tr>''
	 
	SET @body = @body + @xml +''</table></body></html>''
	EXEC msdb.dbo.sp_send_dbmail
	@profile_name = ''DBASupport'',
	@body = @body,
	@body_format =''HTML'',
	@recipients = ''ITInfraServDatabaseSQL@det.nsw.edu.au'',
	@subject = ''AAG SYNCHRONIZATION Alert'' ;
end
', 
		@database_name=N'monitor', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Daily', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=10, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20200303, 
		@active_end_date=99991231, 
		@active_start_time=1000, 
		@active_end_time=235959, 
		@schedule_uid=N'8082b190-7119-46ad-907d-60f401666e67'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO




USE [msdb]
GO

/****** Object:  Job [DETDBA: Capture Whoisactive]    Script Date: 4/03/2020 2:41:07 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [SystemMonitoring]    Script Date: 4/03/2020 2:41:07 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'SystemMonitoring' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'SystemMonitoring'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DETDBA: Capture Whoisactive', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'select * from [SystemMonitoring].[Whoisactive] 
WHERE wait_info not like ''%WAITFOR'' and wait_info not like ''%SP_SERVER_DIAGNOSTICS_SLEEP'' and wait_info not like ''%BACKUP%''
order by collection_time', 
		@category_name=N'SystemMonitoring', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [purge activity]    Script Date: 4/03/2020 2:41:07 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'purge activity', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'delete Whoisactive
--select * 
from monitor.SystemMonitoring.Whoisactive Whoisactive
where collection_time < dateadd(day, -7,  cast(getdate() as date));
', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [active sessions]    Script Date: 4/03/2020 2:41:07 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'active sessions', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'--drop table monitor.SystemMonitoring.whoisactive
--CREATE TABLE monitor.SystemMonitoring.Whoisactive ( [dd hh:mm:ss.mss] varchar(16) NULL,[session_id] smallint NOT NULL,[blocking_session_id] smallint NULL,[database_name] nvarchar(128) NULL,[sql_text] xml NULL,[sql_command] xml NULL,[wait_info] nvarchar(4000) NULL,[tran_log_writes] nvarchar(4000) NULL,[reads] varchar(30) NULL,[writes] varchar(30) NULL,[status] varchar(30) NOT NULL,[open_tran_count] varchar(30) NULL,[tran_start_time] datetime NULL,[start_time] datetime NOT NULL,[login_time] datetime NULL,[login_name] nvarchar(128) NOT NULL,[host_name] nvarchar(128) NULL,[program_name] nvarchar(128) NULL,[collection_time] datetime NOT NULL)
--DECLARE @sch VARCHAR(MAX)
exec monitor..sp_whoisactive @get_outer_command=1,@get_transaction_info=1, @output_column_list=''[dd hh:mm:ss.mss][session_id][blocking_session_id][database_name][sql_text][sql_command][wait_info][tran_log_writes][reads][writes][status][open_tran_count][tran_start_time][start_time][login_time][login_name][host_name][program_name][collection_time]''
,@destination_table = ''monitor.SystemMonitoring.Whoisactive''
--,@return_schema = 1, @schema = @sch OUTPUT ; select @sch;', 
		@database_name=N'monitor', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO



