USE [msdb]
GO

/****** Object:  Job [DETDBA: DeadlockCapture]    Script Date: 8/05/2020 1:27:58 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [Data Collector]    Script Date: 8/05/2020 1:27:58 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Data Collector' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Data Collector'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DETDBA: DeadlockCapture', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Usage:
select Obj=target_data.value(''(/event/data/value/deadlock/resource-list//@objectname)[1]'',''varchar(200)''),* 
from monitor.SystemHealth.Deadlock_report dl
where dl.capture_time >  dateadd(hour, -24, getdate())
--and target_data.value(''(/event/data/value/deadlock/resource-list//@objectname)[1]'',''varchar(200)'') = ''<DB.schema.object>''
order by 1,2', 
		@category_name=N'Data Collector', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [purge]    Script Date: 8/05/2020 1:27:58 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'purge', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'delete dl
from SystemHealth.Deadlock_report dl
where dl.capture_time <  dateadd(month, -1, getdate())', 
		@database_name=N'monitor', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [capture deadlocks]    Script Date: 8/05/2020 1:27:58 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'capture deadlocks', 
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
GO
CREATE SCHEMA SystemHealth;
GO

--DROP TABLE [SystemHealth].[Deadlock_report]
--GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[SystemHealth].[Deadlock_report]'') AND type in (N''U''))
BEGIN
CREATE TABLE [SystemHealth].[Deadlock_report](
	capture_time datetime not null ,
	[file_name] [nvarchar](260) NOT NULL,
	[file_offset] [bigint] NOT NULL,
	[target_data] [xml] NULL,
 CONSTRAINT [PK_Deadlockreport] PRIMARY KEY CLUSTERED 
(
	[file_name] ASC,
	[file_offset] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
END
GO
*/

SET QUOTED_IDENTIFIER ON
GO
;with deadlocks AS (
SELECT file_name, file_offset, target_data=CAST(event_data as xml),rownum = ROW_NUMBER () OVER (PARTITION BY file_name, file_offset ORDER BY file_offset)
FROM sys.fn_xe_file_target_read_file(''system_health*.xel'', null, null, null)
where object_name = ''xml_deadlock_report''
)
insert into SystemHealth.Deadlock_report (capture_time, file_name, file_offset, target_data)
select [Occurred]=DATEADD(hour,CAST(DATEDIFF(HH,GETUTCDATE(),GETDATE()) AS INT), deadlocks.target_data.value(''(/event/@timestamp)[1]'',''datetime'')),
	deadlocks.file_name, deadlocks.file_offset, deadlocks.target_data
from deadlocks
left join SystemHealth.Deadlock_report dr on dr.file_name = deadlocks.file_name and dr.file_offset = deadlocks.file_offset
where rownum = 1 and dr.file_offset is null
', 
		@database_name=N'monitor', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Every 3 hours', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=3, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20190710, 
		@active_end_date=99991231, 
		@active_start_time=100, 
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


