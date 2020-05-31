USE [msdb]
GO

/****** Object:  Job [DETDBA: Daily Import Audit Records]    Script Date: 28/05/2020 11:19:20 AM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [SystemMonitoring]    Script Date: 28/05/2020 11:19:20 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'SystemMonitoring' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'SystemMonitoring'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DETDBA: Daily Import Audit Records', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'This job will import the server audit record from ''AUDIT'' folder.', 
		@category_name=N'SystemMonitoring', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [import records]    Script Date: 28/05/2020 11:19:21 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'import records', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'SET NOCOUNT ON

-- If required, use the script below to create schema and table in the monitor database.

USE monitor;
GO

/*
IF NOT EXISTS (SELECT name FROM sys.schemas WHERE name = ''SystemMonitoring'')
BEGIN
	EXEC sp_executesql N''CREATE SCHEMA SystemMonitoring''
END
GO

--DROP TABLE [SystemMonitoring].[ServerAudit_records]
--GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[SystemMonitoring].[ServerAudit_records]'') AND type in (N''U''))
BEGIN
	CREATE TABLE [SystemMonitoring].[ServerAudit_records](
		event_time datetime2
		,action_id varchar(4)
		,action_name sysname
		,session_id smallint
		,server_principal_id varbinary
		,target_server_principal_id int
		,object_id int
		,session_server_principal_name sysname
		,server_principal_name sysname
		,server_instance_name sysname
		,database_name sysname
		,database_principal_name sysname
		,schema_name sysname
		,object_name sysname
		,statement nvarchar(4000)
		,additional_information nvarchar(4000)
		,file_name varchar(260)
		,audit_file_offset bigint
	) ON [PRIMARY]
END

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[SystemMonitoring].[ServerAudit_records]'') AND type in (N''U''))
BEGIN
	IF NOT EXISTS (SELECT object_id FROM sys.indexes WHERE [name] = ''ix_serverauditrecords'')
		CREATE CLUSTERED INDEX ix_serverauditrecords
			ON SystemMonitoring.ServerAudit_records(event_time,action_id,server_principal_name)
END
GO
*/

--Insert the missing records in to the SystemMonitoring.ServerAudit_records table

;with actiontype AS (
select distinct action_id,name from sys.dm_audit_actions
), auditrecords AS ( 
SELECT af.event_time
	,af.action_id
	,aa.name as action_name
	,af.session_id
	,af.server_principal_id
	,af.target_server_principal_id
	,af.object_id
	,af.session_server_principal_name
	,af.server_principal_name
	,af.server_instance_name
	,af.database_name
	,af.database_principal_name
	,af.schema_name
	,af.object_name
	,af.statement
	,af.additional_information
	,af.file_name
	,af.audit_file_offset
-- select *
FROM sys.fn_get_audit_file(''E:\Audit\audit_*.sqlaudit'', DEFAULT, DEFAULT) af
join actiontype aa on aa.action_id = af.action_id
)
insert into SystemMonitoring.ServerAudit_records
select ar.event_time
	,ar.action_id
	,ar.action_name
	,ar.session_id
	,ar.server_principal_id
	,ar.target_server_principal_id
	,ar.object_id
	,ar.session_server_principal_name
	,ar.server_principal_name
	,ar.server_instance_name
	,ar.database_name
	,ar.database_principal_name
	,ar.schema_name
	,ar.object_name
	,ar.statement
	,ar.additional_information
	,ar.file_name
	,ar.audit_file_offset from auditrecords ar
left join SystemMonitoring.ServerAudit_records sr on sr.event_time = ar.event_time 
	and sr.server_principal_name = ar.server_principal_name
	and sr.action_id = ar.action_id
where sr.event_time is null and sr.action_id is null and sr.server_principal_name is null
', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'daily_import_audit_records', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=62, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20191210, 
		@active_end_date=99991231, 
		@active_start_time=73000, 
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

