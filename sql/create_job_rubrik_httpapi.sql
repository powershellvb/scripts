CREATE OR ALTER PROC dbo.usp_createjobtlogrubrik @dbnames NVARCHAR(100) AS
BEGIN
--DECLARE @dbnames NVARCHAR(1000) = 'Monitor'
DECLARE @source_host NVARCHAR(128)
DECLARE @source_inst NVARCHAR(128)
DECLARE @proxyname NVARCHAR(128)
DECLARE @agname NVARCHAR(128)
DECLARE @jobidqry binary(16)
DECLARE @jobname NVARCHAR(128)
DECLARE @psfilename NVARCHAR(128)
DECLARE @jobcmd1 NVARCHAR(MAX)
DECLARE @jobcmd2 NVARCHAR(MAX)
DECLARE @jobstep1 sysname
DECLARE @jobstep2 sysname
DECLARE @jobstepno int
DECLARE @query1 NVARCHAR(500)
DECLARE @query2 NVARCHAR(500)
DECLARE @query3 NVARCHAR(500)
DECLARE @RegLocInst NVARCHAR(100)
DECLARE @RegLocData NVARCHAR(100)
DECLARE @RegLocMsx NVARCHAR(100)
DECLARE @MsxServer NVARCHAR(128)
DECLARE @InstFolder NVARCHAR(128)
DECLARE @DataFolder NVARCHAR(128)

--SET @source_host = 'dw0991sqp102n1.nsw.education'
SET @psfilename = 'run-odlogbackup.ps1'
SET @jobname = N'DETDBA: AdHoc Rubrik Log backup'
SET @jobstep1 = N'check ' + @psfilename + ' exists'
SET @jobstep2 = N'run ' + @psfilename + ''
SELECT @source_inst = CAST(SERVERPROPERTY('InstanceName') AS NVARCHAR(128))
SELECT @source_host = CAST(SERVERPROPERTY('MachineName') AS NVARCHAR(128))

SELECT @proxyname = DEFAULT_DOMAIN() + '\srvautojobsql'

-- get instance folder
SET @RegLocInst = 'SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
	EXEC [master].[dbo].[xp_regread]    @rootkey = N'HKEY_LOCAL_MACHINE',
									@key = @RegLocInst,
									@value_name = @source_inst,
									@value = @InstFolder OUTPUT
-- get data folder
SET @RegLocData = 'SOFTWARE\Microsoft\Microsoft SQL Server\' + @InstFolder + '\Setup'
EXEC [master].[dbo].[xp_regread]    @rootkey = N'HKEY_LOCAL_MACHINE',
									@key = @RegLocData,
									@value_name = N'SQLDataRoot',
									@value = @DataFolder OUTPUT
-- get msx server
SET @RegLocMsx = 'SOFTWARE\Microsoft\Microsoft SQL Server\' + @InstFolder + '\SQLServerAgent'
EXECUTE [master].[dbo].[xp_regread] @rootkey = N'HKEY_LOCAL_MACHINE',
									@key = @RegLocMsx,
									@value_name = N'MSXServerName',
									@value = @MsxServer OUTPUT
SET @MsxServer = COALESCE(SUBSTRING(@MsxServer,0,CHARINDEX('\',@MsxServer,0)),NULL,'NoMSX')

-- get ag listener name
SET @query3 = N'IF EXISTS (SELECT database_id from master.sys.dm_hadr_database_replica_states where database_id = DB_ID(''' + @dbnames + '''))
	SELECT @listenername = dns_name from master.sys.availability_group_listeners'
EXEC sp_executesql @query3, N'@listenername NVARCHAR(128) OUTPUT', @listenername = @agname OUTPUT
SET @agname = COALESCE(@agname,NULL,'NoAG')

SET @jobcmd1 = N'$jobpath = "' + @DataFolder + '\JOBS"
$filename = "' + @psfilename + '"
$content = ''[cmdletbinding()]
[String] $databases = "' + @dbnames + '"
[String]$source_host = "' + @source_host + '"
[String]$source_inst = "' + @source_inst + '"
[String]$agname = "' + @agname + '"
[String]$cmsserver = "' + @MsxServer + '"
[String]$srvdomain = $env:USERDNSDOMAIN
[bool]$remote = $false

Function Get-Remotemodule {
	param (
	[String] $remotename,
	[String] $modname
	)
	$biterr=0
	Try {
		$cmsses = New-PSSession -ComputerName $remotename -ErrorAction Stop
            
		$remmod = Get-Module -ListAvailable -Name $modname -PSSession $cmsses -ErrorAction Stop
		if ($remmod) {
			Import-Module -Name $modname -PSSession $cmsses -DisableNameChecking -Force -ErrorAction SilentlyContinue
		} else {
			$biterr=1
		}
	} Catch {
		$biterr=1
	}
	if ($biterr -eq 1) {Get-PSSession | Remove-PSSession}
	throw $biterr
}

Function Get-VaultData {
    param (
	[String] $Vault_Key,
	[String] $domainname
	)

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

	if ($cmsserver -eq "NoMSX") {
		$cmsFilePath = "\\$env:computername\c$\Users\srvSqlAgent\.vault-profiles"
	} else {
		$cmsFilePath = "\\$cmsserver\c$\Users\srvSqlAgent\.vault-profiles"
	}

    if ($env:USERPROFILE -match "Default") {
        $userhome = ($env:USERPROFILE).Replace("Default",$env:USERNAME)
    } else {
        $userhome = $env:USERPROFILE
    }

    $vaultfolder = "$userhome\.vault-profiles"

    if ((Test-Path -Path $vaultfolder) -ne $true) {
        New-Item -Path $userhome -Name ".vault-profiles" -ItemType Directory | Out-Null
        Get-Item $vaultfolder -Force | foreach { $_.Attributes = $_.Attributes -bor "Hidden" }
        Copy-Item -Path $cmsFilePath\token.dat,$cmsFilePath\token.key -Destination $vaultfolder -Force
    }

    if ((Test-Path -Path $vaultfolder\token.dat) -ne $true) {
        Copy-Item -Path $cmsFilePath\token.dat -Destination $vaultfolder -Force
    }

    if ((Test-Path -Path $vaultfolder\token.key) -ne $true) {
        Copy-Item -Path $cmsFilePath\token.key -Destination $vaultfolder -Force
    }

    $Vault_Full_Address = "https://vault.nsw.education/v1/it_infraserv_database_sql/data/$domainname"
    $Vault_SavedTokenPath = "$vaultfolder\token.dat"
    $Key = Get-Content "$vaultfolder\token.key"

    #Get Vault Token from locally encrypted dat file
    if ($Vault_SavedTokenPath) {
         $token = Get-Content $Vault_SavedTokenPath | ConvertTo-SecureString -Key $Key 
        [ValidateNotNullOrEmpty()]$Vault_Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($token))
    }

    #Get the Value that is associated with $Vault_Key from $Vault_Full_Address
    $InvokeRestMethodParams = @{
        Uri = $Vault_Full_Address
        Headers = @{"X-Vault-Token"="$Vault_Token"}
    }

    $value = (Invoke-RestMethod @InvokeRestMethodParams).data.data | Select-Object -ExpandProperty $Vault_Key

    if ($value) {
        Write-Output $value
    } else {
        throw "Error when obtaining value from vault"
        Exit(1)
    }
}

$rubrikmodule = Get-Module -ListAvailable -Name rubrik
if ($rubrikmodule) { 
	Import-Module -Name rubrik
} else {'

IF (@MsxServer = 'NoMSX')
BEGIN
	SET @jobcmd1 = @jobcmd1 + '
	throw "Failed to import rubrik module"        
	Exit(1)'		
END
ELSE
BEGIN
SET @jobcmd1 = @jobcmd1 + '
	$result1 = Get-Remotemodule -modname rubrik -remotename $cmsserver
	if ($result1 -eq 1) {
		throw "Failed to import rubrik module"        
		Exit(1)
	}'
END

SET @jobcmd1 = @jobcmd1 + '
}

try {     
	$rubrikuser = Get-VaultData -Vault_Key "rubrik_user" -domainname "detnsw"
    $rubrikpass = Get-VaultData -Vault_Key "rubrik_pass" -domainname "detnsw"
    
	$cred = New-Object System.Management.Automation.PSCredential ($rubrikuser,$`(ConvertTo-SecureString $rubrikpass -AsPlainText -Force))

	#Get rubrik cert
	if ($remote -eq $true) {
	    $ses = New-PSSession -ComputerName $source_host -ErrorAction Stop

	    $cert = Invoke-Command -Session $ses -ScriptBlock {$certloc = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Rubrik Inc.\Backup Service" -Name "Trusted Certificate Path")."Trusted Certificate Path"; 
		    New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certloc}
    } else {
        $certloc = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Rubrik Inc.\Backup Service" -Name "Trusted Certificate Path")."Trusted Certificate Path"
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certloc
    }
	$thumb = ($cert.Thumbprint).Substring(8,8)

	Switch ($thumb) {
	"7FB0731D" {#Write-Output "Unanderra"
				Connect-Rubrik -Server "ps0992brik1000.nsw.education" -Credential $cred -ErrorAction Stop | Out-Null}
	"4546FB71" {#Write-Output "Silverwater"
				Connect-Rubrik -Server "ps0991brik1000.nsw.education" -Credential $cred -ErrorAction Stop | Out-Null}
	default {throw "Certificate is not recognised"
		Exit(1)}
	}
} catch {
	throw "Failed to connect to Rubrik server"
	Exit(1)
}

Try {
	$source_host = "$source_host.$srvdomain"

	$sourcecluster = Get-RubrikHost -Hostname $source_host -ErrorAction Stop
'
if (@agname = 'NoAG')
Begin
SET @jobcmd1 = @jobcmd1 + '
	$sourcedatabase = Get-RubrikDatabase -Name $databases -PrimaryClusterID $sourcecluster.primaryClusterId -Instance $source_inst -Hostname $source_host -ErrorAction Stop'
END
ELSE
BEGIN
SET @jobcmd1 = @jobcmd1 + '
	$sourcedatabase = Get-RubrikDatabase -Name $databases -PrimaryClusterID $sourcecluster.primaryClusterId -AvailabilityGroupName $agname -ErrorAction Stop'  
END

SET @jobcmd1 = @jobcmd1 + '

	if (($sourcedatabase | Measure-Object).Count -eq 1) {
		if (($`($sourcedatabase.recoveryModel`) -eq "FULL") -or ($`($sourcedatabase.isInAvailabilityGroup`) -eq $true) ) {
			New-RubrikLogBackup -id $`($sourcedatabase.id`)
		} else {
			Write-Output "Database $`($sourcedatabase.name`) recovery model is $`($sourcedatabase.recoveryModel`). No Tlog backup performed."
		}
	} else {
		throw "Failed to retrive unique database record from rubrik"
		Exit(1)
	}
} Catch {
	throw "Failed to generate t-log backup request"
	Exit(1)
}

Disconnect-Rubrik -Confirm:$false | Out-Null

Get-PSSession | Remove-PSSession''

$checkfile = Test-Path -Path "$jobpath\$filename"

if ($checkfile) {
	Remove-Item "$jobpath\$filename"
}

$content -replace ''`'','''' | Out-File -FilePath "$jobpath\$filename"'

--PRINT @jobcmd1

SET @jobcmd2 = N'cd "' + @DataFolder + '\JOBS"
powershell.exe ./run-odlogbackup.ps1'

SET @query1 = N'SELECT @jobidqry1 = job_id FROM msdb.dbo.sysjobs WHERE [name] = N''' + @jobname + ''''
EXEC sp_executesql @query1, N'@jobidqry1 binary(16) OUTPUT', @jobidqry1 = @jobidqry OUTPUT

SET @query2 = N'SELECT @jobstepnoqry2=step_id from msdb.dbo.sysjobsteps WHERE job_id = 0x' + CONVERT(NVARCHAR(50), @jobidqry,2) + ' and step_name = N''' + @jobstep1 + ''''
EXEC sp_executesql @query2, N'@jobstepnoqry2 int OUTPUT', @jobstepnoqry2 = @jobstepno OUTPUT

IF (@jobidqry) IS NOT NULL
BEGIN
	EXEC msdb.dbo.sp_update_jobstep  
		@job_name = @jobname,  
		@step_id = @jobstepno,  
		@command=@jobcmd1
	END
ELSE
BEGIN
	BEGIN TRANSACTION
	DECLARE @ReturnCode INT
	SELECT @ReturnCode = 0

	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
	BEGIN
	EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

	END

	DECLARE @jobId BINARY(16)
	EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=@jobname, 
			@enabled=1, 
			@notify_level_eventlog=0, 
			@notify_level_email=0, 
			@notify_level_netsend=0, 
			@notify_level_page=0, 
			@delete_level=0, 
			@description=N'No description available.', 
			@category_name=N'Database Maintenance', 
			@owner_login_name=N'sa', @job_id = @jobId OUTPUT
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

	EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=@jobstep1, 
			@step_id=1, 
			@cmdexec_success_code=0, 
			@on_success_action=3, 
			@on_success_step_id=0, 
			@on_fail_action=2, 
			@on_fail_step_id=0, 
			@retry_attempts=0, 
			@retry_interval=0, 
			@os_run_priority=0, @subsystem=N'PowerShell', 
			@command=@jobcmd1, 
			@database_name=N'master', 
			@flags=32
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=@jobstep2, 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=@jobcmd2, 
		@flags=32, 
		@proxy_name=@proxyname
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
END

EXEC msdb.dbo.sp_start_job @jobname ;  

END
