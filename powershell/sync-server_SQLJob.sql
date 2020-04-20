/***********************************************************************************
This script will create a SQL Job with a Single step to execute the powershell script.
If required to execute the script against more than 1 environments, execute the script and add the step manually.
************************************************************************************/

DECLARE @jobsql NVARCHAR(MAX)
, @jobname NVARCHAR(128)
, @jobdescription NVARCHAR(1000)
, @psscriptname VARCHAR(100)
, @foldername VARCHAR(100)
, @starttime VARCHAR(6)
, @CMSenvironment VARCHAR(25)
, @envshort VARCHAR(5)

/*************** UPDATE THIS SECTION ONLY *********************/
-- SET @CMSenvironment to ('Development', 'Production', 'PreProd', 'Priv', 'Test', 'UC', 'DevUC', 'TestUC')
SET @CMSenvironment = 'PreProd'	
-- SET @psscriptname to ('sync-serverlogin', 'sync-serverconfig')
SET @psscriptname = 'sync-serverconfig'
-- SET @foldername to location of the scripts
SET @foldername = 'C:\PSSCRIPT'
/**************************************************************/
SELECT @jobname =
	CASE @psscriptname
	WHEN 'sync-serverlogin' THEN 'SYNC_Server_Principals'
	WHEN 'sync-serverconfig' THEN 'SYNC_Server_Configurations'
	END
, @jobdescription = 
	CASE @psscriptname
	WHEN 'sync-serverlogin' THEN 'Synchronised server principals and its roles between Primary and Secondary replicas. Only check SQL instance that has AG turned on'
	WHEN 'sync-serverconfig' THEN 'Synchronised server configurations between servers in AG.
Configurations: 
''''cost threshold for parallelism''''
''''max degree of parallelism''''
''''min server memory (MB)''''
''''max server memory (MB)''''
''''optimize for ad hoc workloads'''''
	END
, @starttime = 
	CASE @psscriptname
	WHEN 'sync-serverlogin' THEN '73000'
	WHEN 'sync-serverconfig' THEN '63000'
	END
SELECT @envshort =
	CASE @CMSenvironment
	WHEN 'Development' THEN  'dev'
	WHEN 'Production' THEN  'prod'
	WHEN 'PreProd' THEN  'pre'
	WHEN 'Priv' THEN  'priv'
	WHEN 'Test' THEN  'tst'
	WHEN 'UC' THEN  'uc'
	WHEN 'DevUC' THEN  'devuc'
	WHEN 'TestUC' THEN  'tstuc'
	END
	

SET @jobsql = N'USE [msdb]
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N''[Uncategorized (Local)]'' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N''JOB'', @type=N''LOCAL'', @name=N''[Uncategorized (Local)]''
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N''' + RTRIM(@jobname) + ''', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N''' + @jobdescription+ ''', 
		@category_name=N''[Uncategorized (Local)]'', 
		@owner_login_name=N''sa'', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step bla ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N''' + RTRIM(@psscriptname) + '_' + RTRIM(@CMSenvironment) + ''', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N''PowerShell'', 
		@command=N''set-location "' + RTRIM(@foldername) + '"
(Get-CMSInstances -parent "can connect" -child "' + RTRIM(@CMSenvironment) + '").instance | .\' + RTRIM(@psscriptname) + '.ps1 -Verbose *> ' + RTRIM(@foldername) + '\' + RTRIM(@psscriptname) + '_' + RTRIM(@envshort) + '_verbose.txt'', 
		@database_name=N''master'', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N''' + RTRIM(@psscriptname) + ' Weekdays @' + RTRIM(@starttime) + ''', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=62, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20191118, 
		@active_end_date=99991231, 
		@active_start_time=' + RTRIM(@starttime) + ', 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N''(local)''
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
'
--PRINT @jobsql
EXEC sp_executesql @jobsql