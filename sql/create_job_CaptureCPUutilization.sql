USE [msdb]
GO

/****** Object:  Job [DETDBA: Capture CPUutilization]    Script Date: 8/05/2020 1:27:57 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [SystemMonitoring]    Script Date: 8/05/2020 1:27:57 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'SystemMonitoring' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'SystemMonitoring'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DETDBA: Capture CPUutilization', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'USAGE:
select record_id,EventTime,SQLProcessUtilization,OtherProcessUtilization,totalUsage=cpu.SQLProcessUtilization+cpu.OtherProcessUtilization,SystemIdle
from monitor.SystemMonitoring.CPUutilization cpu
where cpu.SQLProcessUtilization+cpu.OtherProcessUtilization > 95
order by EventTime
', 
		@category_name=N'SystemMonitoring', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [purge activity]    Script Date: 8/05/2020 1:27:57 PM ******/
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
		@command=N'delete CPUutilization
--select * 
from monitor.SystemMonitoring.CPUutilization CPUutilization
where EventTime < dateadd(day, -30,  cast(getdate() as date));
', 
		@database_name=N'monitor', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [capture cpu usage]    Script Date: 8/05/2020 1:27:57 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'capture cpu usage', 
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

--create schema SystemMonitoring;

--drop table monitor.SystemMonitoring.CPUutilization
CREATE TABLE [SystemMonitoring].[CPUutilization](
	[record_id] [int] NOT NULL,
	[EventTime] [datetime] NOT NULL,
	[SQLProcessUtilization] [int] NOT NULL,
	[SystemIdle] [int] NOT NULL,
	[OtherProcessUtilization] [int] NOT NULL
) ON [PRIMARY]
GO


CREATE UNIQUE CLUSTERED INDEX CI_CPUutilization ON [SystemMonitoring].[CPUutilization] (EventTime)
*/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

DECLARE @ms_ticks_now BIGINT
SELECT @ms_ticks_now = ms_ticks FROM sys.dm_os_sys_info;

INSERT INTO [monitor].[SystemMonitoring].[CPUutilization]
SELECT cpu.record_id
	,cpu.EventTime
	,cpu.SQLProcessUtilization
	,cpu.SystemIdle
	,100 - cpu.SystemIdle - cpu.SQLProcessUtilization AS OtherProcessUtilization
--into monitor.SystemMonitoring.CPUutilization
FROM (
	SELECT record.value(''(./Record/@id)[1]'', ''int'') AS record_id
		,dateadd(ms, - 1 * (@ms_ticks_now - [timestamp]), GetDate()) AS EventTime
		,record.value(''(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]'', ''int'') AS SystemIdle
		,record.value(''(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]'', ''int'') AS SQLProcessUtilization
		,TIMESTAMP
	FROM (
		SELECT TIMESTAMP
			,convert(XML, record) AS record
		FROM sys.dm_os_ring_buffers
		WHERE ring_buffer_type = N''RING_BUFFER_SCHEDULER_MONITOR''
			AND record LIKE ''%<SystemHealth>%''
		) AS x
) AS cpu -- 256 rows
left join SystemMonitoring.CPUutilization hist on hist.EventTime = cpu.EventTime where hist.EventTime IS NULL
ORDER BY cpu.EventTime 
go
', 
		@database_name=N'monitor', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Every 4 hours', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=4, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20200326, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO
