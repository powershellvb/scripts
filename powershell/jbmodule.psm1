### get-pwdinvault ###
function get-pwdinvault {
<#
.SYNOPSIS
    Get the password from HashiCorp Vault

.PARAMETER domain
    Domain name, ie. tstuc, detnsw, etc

.PARAMETER fieldname
    Secret field name, ie. sa_pass, sqlserver_pass, etc

.EXAMPLE
    PS> get-pwdinvault -domain detnsw -fieldname sa_pass

    This will get SA password for DETNSW domain
#>
param (
    [String]$domain
    , [String]$fieldname
)

switch($domain){
    "tstuc" { $domain = "testuc" }
}
#vault login -method=ldap username=jboediman
$pass = vault kv get -field="$fieldname" "it_infraserv_database_sql/$domain"
Write-Output $pass
}

### Get-CMSControlPoint ###
function Get-CMSControlPoint {
<#
.SYNOPSIS
	Gets the CMS server instance for the current environment

.DESCRIPTION
	Gets the CMS server instance for the current environment

.NOTES  

.PARAMETER InstanceFQDN
    Fully Qualified Domain Name of any SQL Instance

.EXAMPLE
    PS> Get-CMSControlPoint -InstanceFQDN 'servername.detnsw.win\instancename'
#>	
Param(
  [Parameter(Mandatory = $True,
  ValueFromPipeline=$True,
  ValueFromPipelineByPropertyName=$True,
  HelpMessage="SQL Instance FQDN")] 
  [string] $InstanceFQDN 
)
$index1 = $InstanceFQDN.IndexOf("\",0)
$serverfqdn = $InstanceFQDN.substring(0,$index1)
$serversplit = $serverfqdn.Split(".")

if ($serversplit.Count -gt 2) {
    switch ($serversplit[1]) {
        "CENTRAL" { $CMSInstance = "upvewsql001.central.det.win\SQLDBA" }
        "DETNSW" { $CMSInstance = "pw0000sqlpe126.detnsw.win\control_point1" }
        "PREDETNSW" { $CMSInstance = "qw0000sqlqe015.predetnsw.win\control_point1" }
        "UATDETNSW" { $CMSInstance = "tw0000sqlte004.uatdetnsw.win\control_point1" }
        "DEVDETNSW" { $CMSInstance = "dw0000sqlde002.devdetnsw.win\control_point1" }
        "UC" { $CMSInstance = "pw0991sqmgmth5.uc.det.nsw.edu.au\control_point1" }
        "TSTUC" { $CMSInstance = "tw0000sqmgmth5.tstuc.det.nsw.edu.au\control_point1" }
        "DEVUC" { $CMSInstance = "dw0000sqmgmth5.devuc.det.nsw.edu.au\control_point1" }
        default { throw "Unable to detect CMSInstance for $($serversplit[1])" }
    }
    Write-Output $CMSInstance
} else {
    throw "Server domain undetected. Please enter the correct Instance FQDN"
}
}

### get-sqladhocjob ###
function get-sqladhocjob {    
param (
    [String]$instancename
    , [String]$sapwd
    , [String]$jobname
)

$jobname = $jobname -replace '[^a-zA-Z0-9 -,.]'
$query = "select
@@SERVERNAME as server_name
,sysjobs.job_id
,sysjobs.name job_name
,sysjobs.enabled job_enabled
,sysschedules.name schedule_name
,sysschedules.schedule_id
,sysschedules.active_start_date
,sysschedules.active_start_time
,sysschedules.enabled as 'schedule_enabled'
,sysschedules.date_modified
from msdb.dbo.sysjobs
inner join msdb.dbo.sysjobschedules on sysjobs.job_id = sysjobschedules.job_id
inner join msdb.dbo.sysschedules on sysjobschedules.schedule_id = sysschedules.schedule_id
where sysjobs.name = '$jobname' and sysschedules.freq_type = 1"

$jobsched = Invoke-Sqlcmd -ServerInstance $instancename -Username sa -Password $sapwd -Query $query

$properties = @{        
                servername = $jobsched.server_name
                jobid = $jobsched.job_id
                jobname = $jobsched.job_name
                jobenabled = $jobsched.job_enabled
                schedulename = $jobsched.schedule_name
                scheduleid = $jobsched.schedule_id
                schedulestartdate = $jobsched.active_start_date
                schedulestarttime = $jobsched.active_start_time
                schedulesenabled = $jobsched.schedule_enabled
                schedulesmodified = $jobsched.date_modified      
            } 

$jobdetails = New-Object -TypeName PSObject -Property $properties
Write-Output $jobdetails
}

function Remove-CMSEntry {    
<#
.SYNOPSIS
Remove the specified SQL server instance from its CMS

.DESCRIPTION
Remove the specified SQL server instance from its CMS Control point

.PARAMETER FQDNInstance
Specifies the target instance name.

.PARAMETER cms
Specifies the Control_Point instance.

.PARAMETER saAccount
Specifies the SQL sa account.

.PARAMETER saPassword
Specifies the SQL sa account password.

.EXAMPLE
PS> Remove-CMSEntry -FQDNInstance "$Env:Computername.$env:userdnsdomain\AGRELTEST072019A" -cms "dw0000sqlde002.devdetnsw.win\control_point1" -saaccount "sa" -sapassword $SASecurePwd

#>   
[CmdletBinding()]
param (
    [Parameter(Mandatory=$True,
    ValueFromPipeline=$True,
    ValueFromPipelineByPropertyName=$True,
    HelpMessage="SQL Instance being decommissioned")]
    [String]$FQDNInstance,
    [Parameter(Mandatory=$False,
    HelpMessage="CMS Control_Point instance")]
    [string]$cms,
    [Parameter(Mandatory=$False,
    HelpMessage="SA account name")]
    [string]$saAccount,
    [Parameter(Mandatory=$False,
    HelpMessage="SA account password")]
    [string]$saPassword
)

$sql = "DECLARE @decom_group_id INT, @target_server_id INT, @server_name VARCHAR(200), @err_msg NVARCHAR(1000)
        SET @server_name = '$FQDNInstance'

        SELECT @decom_group_id=MIN(tg.server_group_id) 
        FROM msdb.dbo.sysmanagement_shared_server_groups tg 
        WHERE tg.name='Decommissioned' 

        IF @decom_group_id IS NULL 
        BEGIN
            RAISERROR ('Failed to locate Decommissioned folder',16,1)
            RETURN
        END

        SELECT @target_server_id = wh.server_id 
        FROM msdb.dbo.sysmanagement_shared_registered_servers wh
        WHERE wh.name=@server_name

        IF @target_server_id IS NULL
        BEGIN
            RAISERROR ('Failed to locate target SQL server instance',16,1)
            RETURN
        END
        BEGIN TRY
            EXEC msdb.dbo.sp_sysmanagement_move_shared_registered_server @server_id=@target_server_id, @new_parent_id=@decom_group_id
        END TRY
        BEGIN CATCH
            SET @err_msg = ERROR_MESSAGE()
            IF @err_msg LIKE '%Violation of UNIQUE KEY constraint%'
                RAISERROR ('Target SQL server instance already exists in Decommission folder',16,1)
            ELSE
            BEGIN
                RAISERROR(@err_msg,16,1)
            END
        END CATCH
        "
                
$properties = @{
    FQDNInst = $FQDNInstance
    CMS = $cms
    ErrStatus = 0
    MsgLevel = "INFO"
    Message = ""
}
    
try
{      
    #Invoke-SqlCmd -ServerInstance $CMS -Database "msdb" -Query $sql -ErrorAction Stop
    $sqlconn = New-Object System.Data.SqlClient.SqlConnection
    $sqlconn.ConnectionString = "Server=$cms; Database=master; Connect Timeout=10; User ID=$saAccount; Password=$saPassword;"
    #$sqlcred = New-Object System.Data.SqlClient.SqlCredential($saAccount, $saPassword);
    #$sqlconn.Credential = $sqlcred
    $sqlcmd = New-Object System.Data.SqlClient.SqlCommand
    $sqlcmd.Connection = $sqlconn
    $sqlcmd.CommandType = [System.Data.CommandType]::Text
    $sqlcmd.CommandText = $sql
    $sqlconn.Open()
    $sqlcmd.ExecuteNonQuery()

    $properties.Message = "Server $FQDNInstance moved to Decommissioned folder in CMS $cms"
}
catch [System.Data.SqlClient.SqlException]
{
    $properties.Message = "Failed to decommission $FQDNInstance in CMS, please complete manually..." + $Error
    $properties.MsgLevel = "ERROR"
    $properties.ErrStatus = 1
    $Error.Clear()
} finally {    
    $sqlconn.Close()
    $obj = New-Object -TypeName psobject -Property $properties
    Write-Output $obj
}
}

function Get-DriveSpace {
<#
.SYNOPSIS
	Get the disk drive size for specified server

.DESCRIPTION
	Get the disk size for specified server. Can be filtered by drive name

.NOTES     
	
.PARAMETER  ComputerName     
    The computer name. If not specified, it will check the localhost.

.EXAMPLE
    Get-DriveSpace -ComputerName pw0000sqlpe002

    Get space information for all drives

.EXAMPLE
    Get-DriveSpace -ComputerName pw0000sqlpe126 -Drive D

    Get disk space information for D drive

#>
[CmdletBinding()]
Param(
[Parameter (ValueFromPipeline=$true,
    ValueFromPipelineByPropertyName=$true)] [string] $ComputerName, 
[string] $Drive 
)

if(!$ComputerName){$ComputerName = 'localhost'}
$results = Get-CimInstance Win32_LogicalDisk -ComputerName $ComputerName 

if ($Drive) {
    Write-Output $results | Where-Object {$_.DeviceID -match $Drive} | Format-Table DeviceId, `
    @{Name="SizeGB";Expression={[int]($_.Size/1024/1024/1024)}}, `
    @{Name="FreeSpaceGB";Expression={[int]($_.FreeSpace/1024/1024/1024)}}, `
    @{Name="PercFree";Expression={[int]($_.FreeSpace/$_.Size * 100)}}, `
    @{Name="ReportDate";Expression={(Get-Date -Format "yyyyMMdd-HHMMss")}} 
} else {
    Write-Output $results | Format-Table DeviceId, `
    @{Name="SizeGB";Expression={[int]($_.Size/1024/1024/1024)}}, `
    @{Name="FreeSpaceGB";Expression={[int]($_.FreeSpace/1024/1024/1024)}}, `
    @{Name="PercFree";Expression={[int]($_.FreeSpace/$_.Size * 100)}}, `
    @{Name="ReportDate";Expression={(Get-Date -Format "yyyyMMdd-HHMMss")}} 
}

}