<#
.SYNOPSIS
	Gets a list of SQL Server hosts in the current environment from the CMS server
	Only servers under "supported" and "can connect" will be returned

.DESCRIPTION
	Gets a list of SQL Server hosts in the current environment from the CMS server
	Only servers under "supported" and "can connect" will be returned

.PARAMETER environment   
    The name of environment, ie. crash and burn, development, production, etc
	
.PARAMETER subenvironment   
    The name of sub folder under the environment. ie. hci, virtual

.NOTES     
    Name: Get-ServersCMS
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created

    To Do:   

.EXAMPLE
	.\get-serverscms.ps1
	Returns full list of servers

.EXAMPLE
    .\get-serverscms.ps1 -environment "crash and burn" -subenvironment "virtual"
    Returns servers in crash and burn environment under virtual folder
#>
param(
[string] $environment
, [string] $subenvironment
)

if ($environment) {
    $enviro = $environment }
else {
    $enviro = "" }

if ($subenvironment) {
    $subenviro = $subenvironment }
else {
    $subenviro = "" }

$CurrentDomain = [environment]::UserDomainName
switch ($CurrentDomain)
{
	"CENTRAL" {$CMSInstance="upvewsql001.central.det.win\SQLDBA";$SQLDNS="SQL.INFRA.NSWEDUSERVICES.COM.AU"}
	"DETNSW" {$CMSInstance="pw0000sqlpe126.detnsw.win\control_point1";$SQLDNS="SQL.INFRA.NSWEDUSERVICES.COM.AU"}
	"PREDETNSW" {$CMSInstance="qw0000sqlqe015.predetnsw.win\control_point1";$SQLDNS="SQL.PREINFRA.NSWEDUSERVICES.COM.AU"}
	"UATDETNSW" {$CMSInstance="tw0000sqlte004.uatdetnsw.win\control_point1";$SQLDNS="SQL.TSTINFRA.NSWEDUSERVICES.COM.AU"}
	"DEVDETNSW" {$CMSInstance="dw0000sqlde002.devdetnsw.win\control_point1";$SQLDNS="SQL.DEVINFRA.NSWEDUSERVICES.COM.AU"}
    "UC" {$CMSInstance="pw0991sqmgmth5.uc.det.nsw.edu.au\control_point1";$SQLDNS="SQL.INFRA.NSWEDUSERVICES.COM.AU"}
    "TSTUC" {$CMSInstance="tw0000sqmgmth5.tstuc.det.nsw.edu.au\control_point1";$SQLDNS="SQL.TSTINFRA.NSWEDUSERVICES.COM.AU"}
    "DEVUC" {$CMSInstance="dw0000sqmgmth5.devuc.det.nsw.edu.au\control_point1";$SQLDNS="SQL.DEVINFRA.NSWEDUSERVICES.COM.AU"}
	default { Write-Warning "DETDBA module unable to detect CMSInstance for {0}" -f $CurrentDomain }
}

function Invoke-SqlQuery {
<#     
.SYNOPSIS     
    Executes a SQL query using System.Data.SQLClient.SQLCommand and returns a resultset.
     
.DESCRIPTION   
    Executes a SQL query using System.Data.SQLClient.SQLCommand and returns a resultset.

	Similar in function to Invoke-SqlCmd except this cmdlet is thread safe.
      
.PARAMETER ServerInstance   
    Name of server to execute query against
	
.PARAMETER Database   
    Database to execute in. Default database will be master if not specified.
        
.PARAMETER Query   
    SQL statement to be executed
       
.PARAMETER Timeout   
    Query timeout in seconds
      
.PARAMETER Username  
    Specify Username to connect using a SQL login rather than integrated authentication
       
.PARAMETER Password  
    Specify the password when using the Username parameter

.PARAMETER AsDt
	Returns DataTable instead of DataRows
                  
.NOTES     
    Name: Invoke-SqlQuery
    Author: Chris Dobson
    DateCreated: 2017-03-01     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Added to DETDBA module
	2		24/03/2017	CD		Added AsDt parameter, to return data table instead of rows

    To Do:   
    

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
      
.EXAMPLE     
    Invoke-SqlQuery -ServerInstance "myhost" -Query "SELECT 1 AS [Test]"
    Executes query against myhost in the default (master) database and retuns a single row.
     
.EXAMPLE     
    Invoke-SqlQuery -ServerInstance "myhost" -Database "msdb" -Query "SELECT COUNT(*) FROM backupset" -Username "Chris" -Password "password1"
    Executes query against myhost in msdb using a SQL login
#>    
	param (
		[string]$ServerInstance, 
		[string]$Database="master", 
		[string]$Query, 
		[int]$Timeout = 30, 
		[string]$Username, 
		[string]$Password,
		[switch]$AsDt
	) 
    if ($Username -and $Password) 
    { $ConnectionString = "Server={0};Database={1};User ID={2};Password={3};Trusted_Connection=False;Connect Timeout={4}" -f $ServerInstance,$Database,$Username,$Password,$ConnectionTimeout } 
    else 
    { $ConnectionString = "Server={0};Database={1};Integrated Security=True;Connect Timeout={2}" -f $ServerInstance,$Database,$ConnectionTimeout } 

    try {
		$Datatable = New-Object System.Data.DataTable
		$Connection = New-Object System.Data.SQLClient.SQLConnection
		$Connection.ConnectionString = $ConnectionString
		$Connection.Open()
		$Command = New-Object System.Data.SQLClient.SQLCommand
		$Command.Connection = $Connection
		$Command.CommandText = $Query
		$Command.CommandTimeout = $Timeout
		$Reader = $Command.ExecuteReader()
		$Datatable.Load($Reader)
		$Connection.Close()
    } catch {
		if ($_.Exception.InnerException.Errors[0].Message -and $_.Exception.InnerException.Errors[0].Message.StartsWith("A network-related or instance-specific error occurred"))
		{ throw("Unable to connect to instance") }
		elseif ($_.Exception.InnerException.Errors[0].Message)
		{ throw ($_.Exception.InnerException.Errors[0].Message) }
		else { throw($_) }
	}
	if ($AsDt) { return @(,$Datatable) }
    else { return @(,$Datatable.Rows) } # return as single object array to stop powershell enumerating the result set
}

	$host_query = 'WITH ServerGroups(parent_id, server_group_id, name) AS 
	(
		SELECT 
			tg.parent_id, 
			tg.server_group_id, 
			tg.name
		FROM 
			msdb.dbo.sysmanagement_shared_server_groups tg
		WHERE 
			is_system_object = 0'
    
    if ($enviro -ne "") {
        $host_query = $host_query + 'AND (tg.name = ''' + $enviro + ''')
			AND (tg.parent_id in (SELECT server_group_id from msdb.dbo.sysmanagement_shared_server_groups where name = ''can connect'' and 
									parent_id = (SELECT server_group_id from msdb.dbo.sysmanagement_shared_server_groups where name = ''supported'')))'
    }
    else {
		$host_query = $host_query + 'AND (tg.name = ''can connect'')
			AND (tg.parent_id in (SELECT server_group_id from msdb.dbo.sysmanagement_shared_server_groups where name = ''supported''))'
    }

    $host_query = $host_query + 'UNION ALL
		SELECT 
			cg.parent_id, 
			cg.server_group_id, 
			cg.name
		FROM 
			msdb.dbo.sysmanagement_shared_server_groups cg
				INNER JOIN ServerGroups pg
					ON cg.parent_id = pg.server_group_id
	)'

    if ($subenviro -ne "") {
        $host_query = $host_query + ', detailgroups(parent_id, server_group_id, name) AS 
        (
		SELECT 
			tg.parent_id, 
			tg.server_group_id, 
			tg.name
		FROM 
			msdb.dbo.sysmanagement_shared_server_groups tg
		WHERE 
			is_system_object = 0
			AND (tg.name = ''' + $subenviro + ''')
		UNION ALL
		SELECT 
			cg.parent_id, 
			cg.server_group_id, 
			cg.name
		FROM 
			msdb.dbo.sysmanagement_shared_server_groups cg
				INNER JOIN detailgroups dg
					ON cg.parent_id = dg.server_group_id
	    )'
    }

	$host_query = $host_query + 'SELECT
		DISTINCT CASE WHEN CHARINDEX(''\'',s.server_name)>0 THEN LEFT(s.server_name, CHARINDEX(''\'',s.server_name)-1) ELSE s.server_name END as [host_name]
	FROM
		msdb.dbo.sysmanagement_shared_registered_servers_internal s
	INNER JOIN ServerGroups sg 
		ON s.server_group_id = sg.server_group_id'

    if ($subenviro -ne "") {
        $host_query = $host_query + '
            INNER JOIN detailgroups dg ON sg.server_group_id = dg.server_group_id'
    }

	Invoke-SqlQuery -ServerInstance $CMSInstance -Query $host_query
