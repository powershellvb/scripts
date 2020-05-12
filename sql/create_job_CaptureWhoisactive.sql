USE [msdb]
GO

/****** Object:  Job [DETDBA: Capture Whoisactive]    Script Date: 8/05/2020 1:27:58 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [SystemMonitoring]    Script Date: 8/05/2020 1:27:58 PM ******/
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
/****** Object:  Step [purge activity]    Script Date: 8/05/2020 1:27:58 PM ******/
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
		@database_name=N'monitor', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [active sessions]    Script Date: 8/05/2020 1:27:58 PM ******/
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