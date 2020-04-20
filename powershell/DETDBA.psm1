<#
 Purpose: DETDBA PowerShell module - exports common cmdlets with environment specific usage

 Usage: Module will auto load when installed to C:\Program Files\WindowsPowerShell\Modules\DETDBA
 Where: See https://itdwiki.det.nsw.edu.au/display/Database/Powershell
 Example: Run "dbahelp" in a new powershell window for module usage

 Dependencies:	SqlPs SQL 2012+ (or sqlservercmdletsnapin100 for 2008R2)
				ActiveDirectory module (DNS cmdlets)
				DNS management (DNS cmdlets)
				failoverclusters module (AG Failover cmdlets)


 Build	Date		Author	Comments
 ----------------------------------------------------------------------------------------------------------------
 1		01/03/2017	CD		Created. See individual functions for update comments
 2      12/10/2017  PB      self update routine added

#>

########################################################################################
# PRIVATE FUNCTIONS
# (private functions do not follow the "verb-noun" naming convention and are not exported)
#

function IsAdmin {
	$AdminCheck = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
	If (-NOT $AdminCheck) { Write-Warning "Administrator check failed" }
	return $AdminCheck
}
function Get-SQLDNS {
	<#
.SYNOPSIS
	Gets the DNS server for current environment

.DESCRIPTION
	Gets the CMS server instance for the current environment

.NOTES     
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	2       10/02/2020  NK      updated to support parameter for different domains

.PARAMETER  Domain     
   Default is current domain, can optionally specifiy another DET Domain


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>	
	Param(
  [Parameter(Mandatory = $false )] [string] $Domain 
	)

	if ($Domain -eq [String]::Empty) { $Domain = [environment]::UserDomainName }
	switch -regex ($Domain) {
		"CENTRAL|UC|DETNSW|PRIV" { $SQLDNS = "SQL.INFRA.NSWEDUSERVICES.COM.AU" }
		"PREDETNSW|PREUC" { $SQLDNS = "SQL.PREINFRA.NSWEDUSERVICES.COM.AU" }
		"UATDETNSW|TSTUC" { $SQLDNS = "SQL.TSTINFRA.NSWEDUSERVICES.COM.AU" }
		"DEVDETNSW|DEVUC" { $SQLDNS = "SQL.DEVINFRA.NSWEDUSERVICES.COM.AU" }
		default { Write-Warning "DETDBA module unable to detect SQLDNS for $Domain" }
	}

	return $SQLDNS
}
function Get-CMSControlPoint {
	<#
.SYNOPSIS
	Gets the CMS server instance for the current environment

.DESCRIPTION
	Gets the CMS server instance for the current environment

.NOTES     
    Name: Get-CMSControlPoint
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created
	2       10/02/2020  NK      updated to support parameter for different domains

    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>	
	Param(
  [Parameter(Mandatory = $false )] [string] $Domain 
	)
	if ($Domain -eq [String]::Empty) { $Domain = [environment]::UserDomainName }
	#[String] $CMSInstance
	switch ($Domain) {
		"CENTRAL" { $CMSInstance = "upvewsql001.central.det.win\SQLDBA" }
		"DETNSW" { $CMSInstance = "pw0000sqlpe126.detnsw.win\control_point1" }
		"PREDETNSW" { $CMSInstance = "qw0000sqlqe015.predetnsw.win\control_point1" }
		"UATDETNSW" { $CMSInstance = "tw0000sqlte004.uatdetnsw.win\control_point1" }
		"DEVDETNSW" { $CMSInstance = "dw0000sqlde002.devdetnsw.win\control_point1" }
		"UC" { $CMSInstance = "pw0991sqmgmth5.uc.det.nsw.edu.au\control_point1" }
		"TSTUC" { $CMSInstance = "tw0000sqmgmth5.tstuc.det.nsw.edu.au\control_point1" }
		"DEVUC" { $CMSInstance = "dw0000sqmgmth5.devuc.det.nsw.edu.au\control_point1" }
		default { Write-Warning "DETDBA module unable to detect CMSInstance for $Domain" }
	}

	return $CMSInstance
}
function ImportModuleTS { 
	<# 
.SYNOPSIS
	Imports a module with thread safety

.DESCRIPTION
	Imports a module with thread safety

	Calls Import-Module through a mutex to ensure multiple threads dont load a corrput module

.NOTES     
    Name: ImportModuleTS
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		2017-04-06	CD		Created

    To Do:   

.PARAMETER Name
	Module name to load  

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	[CmdletBinding()]  
	param(
		[Parameter(Mandatory = $true)]
		[string]$Name,
		[switch]$DisableNameChecking
	)
	# Yet another PS cmdlet that's not thread safe so protected by a mutex.
	$Mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList $false, "Global\ModuleLoad_$Name"
	[void]$Mutex.WaitOne()
	### Mutex Protected ###
	Import-Module $Name -DisableNameChecking:$DisableNameChecking -Verbose:$false -ErrorAction Stop
	### /Mutex Protected ###
	[void]$Mutex.ReleaseMutex()
}

function GetSqlType {  
	param([string]$TypeName)  
	switch ($TypeName) {  
		'Boolean' { [Data.SqlDbType]::Bit }  
		'Byte[]' { [Data.SqlDbType]::VarBinary }  
		'Byte' { [Data.SQLDbType]::VarBinary }  
		'Datetime' { [Data.SQLDbType]::DateTime }  
		'Decimal' { [Data.SqlDbType]::Decimal }  
		'Double' { [Data.SqlDbType]::Float }  
		'Guid' { [Data.SqlDbType]::UniqueIdentifier }  
		'Int16' { [Data.SQLDbType]::SmallInt }  
		'Int32' { [Data.SQLDbType]::Int }  
		'Int64' { [Data.SqlDbType]::BigInt }  
		'UInt16' { [Data.SQLDbType]::SmallInt }  
		'UInt32' { [Data.SQLDbType]::Int }  
		'UInt64' { [Data.SqlDbType]::BigInt }  
		'Single' { [Data.SqlDbType]::Decimal } 
		default { [Data.SqlDbType]::VarChar }  
	}  
      
} #GetSqlType 

#
# /PRIVATE FUNCTIONS
########################################################################################

########################################################################################
# MODULE ENVIRONMENT CONFIG
#

$RemedyServer = "servicemanagement.det.nsw.edu.au"

# Detect and load SQL cmdlets, SqlPs for 2012+, sqlservercmdletsnapin100 for 2008R2
if (!(Get-Module SqlPs) -and !(get-pssnapin sqlservercmdletsnapin100 -ErrorAction SilentlyContinue)) {
	if (Get-Module SqlPs -ListAvailable) {
		ImportModuleTS SqlPs -DisableNameChecking #SQL 2012+		
	}
	elseif (!(get-pssnapin sqlservercmdletsnapin100 -ErrorAction SilentlyContinue)) {
		add-pssnapin sqlservercmdletsnapin100 -ErrorAction SilentlyContinue
	}
}

# Define environment specific variables
$CurrentDomain = [environment]::UserDomainName
$SQLDNS = Get-SQLDNS -Domain $CurrentDomain
$CMSInstance = Get-CMSControlPoint -Domain $CurrentDomain
#
# PB - delibreately commented out for now until working in a dev environment
#

# self update when logged in as an sa type user (assumes we are on a server)
# NB: user workstations are updated via the UpdateHosts scheduled task and depend on the detdba symlink

# try ip address

$remote_location = "\\hppewmgt004.citrix.mgmt.det\eXpress\SOURCES\Applications\Microsoft\SQL\DET DBA Scripts\Powershell";
$detdba_library = "\detdba\detdba.psm1";

# $(Get-Item Env:\PSModulePath).value.split(';') |
# loop through the path to find where the detdba library file lives
#     foreach {
#         if( Test-Path "$_$detdba_library" ) {
#             $username = $(Get-Item Env:\USERNAME).value;
# if logged in with an sa type username (assume we are on a server)
#             if( $username.substring(0, 2) -eq 'sa' ) {
#                 $username = $username.substring(2, $username.length - 2);
<# I could not get this to work
                    # get stored (encrypted) credentials and only ask if these don't match the AD
                    New-ImpersonatedUser (Get-SavedCredential -Domain "central" -DefaultUsername "central\$username")
                    # if the files are different . . .
                    if( Compare-Object -ReferenceObject $(get-item $remote_location$detdba_library).LastWriteTime -DifferenceObject $(get-item $_$detdba_library).LastWriteTime ) {
                        Copy-Item -Path $remote_location$detdba_library -Destination $_$detdba_library
                    }
                    # go back to being the previous user
                    Remove-ImpersonateUser;
                #>
#                 $remote_credential = Get-SavedCredential -Domain "central.det.win" -DefaultUsername "central\$username";
#                 Remove-PSDrive -Name x -ErrorAction SilentlyContinue > $null
#                 New-PSDrive –Name "x" –PSProvider FileSystem –Root $remote_location -Credential $remote_credential -ErrorAction Stop > $null
# if the files are different . . .
#                 if( Compare-Object -ReferenceObject $(get-item $remote_location$detdba_library).LastWriteTime -DifferenceObject $(get-item $_$detdba_library).LastWriteTime ) {
#                     Copy-Item -Path "x:$detdba_library" -Destination $_$detdba_library
#                 }
#                 Remove-PSDrive -Name x -ErrorAction SilentlyContinue > $null
#             }
#         }
#     }

    
#
# /MODULE ENVIRONMENT CONFIG
########################################################################################

########################################################################################
# PUBLIC FUNCTIONS
#

function Get-DETModuleHelp {
	<#
.SYNOPSIS
	Lists all DETDBA cmdlets

.DESCRIPTION
	Lists all DETDBA cmdlets

.NOTES     
    Name: Get-DETModuleHelp
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created
	2		08/05/2017	CD		Corrected filter for private functions

    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	Get-Help -Category Function | ? { $_.ModuleName -eq "DETDBA" -and $_.Name -like "*-*" } | select Name, Synopsis | Sort-Object -Property Name
	Write-Host "`nTo view detailed help for a cmdlet type: `"Get-Help <cmdlet name>`"`n"
}
Set-Alias -Name dbahelp -Value Get-DETModuleHelp -Description "Lists all DETDBA cmdlets"

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
		[string]$Database = "master", 
		[string]$Query, 
		[int]$Timeout = 30, 
		[string]$Username, 
		[string]$Password,
		[switch]$AsDt
	) 
	if ($Username -and $Password) 
 { $ConnectionString = "Server={0};Database={1};User ID={2};Password={3};Trusted_Connection=False;Connect Timeout={4}" -f $ServerInstance, $Database, $Username, $Password, $ConnectionTimeout } 
	else 
 { $ConnectionString = "Server={0};Database={1};Integrated Security=True;Connect Timeout={2}" -f $ServerInstance, $Database, $ConnectionTimeout } 

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
	}
 catch {
		if ($_.Exception.InnerException.Errors[0].Message -and $_.Exception.InnerException.Errors[0].Message.StartsWith("A network-related or instance-specific error occurred"))
		{ throw("Unable to connect to instance") }
		elseif ($_.Exception.InnerException.Errors[0].Message)
		{ throw ($_.Exception.InnerException.Errors[0].Message) }
		else { throw($_) }
	}
	if ($AsDt) { return @(, $Datatable) }
	else { return @(, $Datatable.Rows) } # return as single object array to stop powershell enumerating the result set
}

#Parameters

function Get-CMSInstances (
	[string]$child,
	[string]$parent
) {

	<#
.SYNOPSIS
	Gets a list of instances in the current environment from the CMS server where we can specify the child and parent of the CMS tree.
	If no child and parent folder specified, instances under "supported" and "can connect" will be returned

.DESCRIPTION
	Gets a list of instances in the current environment from the CMS server where we can specify the child and parent of the CMS tree.
	If no child and parent folder specified, instances under "supported" and "can connect" will be returned

.PARAMETER child
    Name of the child folder

.PARAMETER parent
    Name of the parent folder

.NOTES     
    Name: Get-CMSInstances
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created
	2		12/05/2017	CD		Added host_name to output list
    3       18/10/2019  JB      Added parameter to specify the child and parent folder
	4       29/11/2019  JB      Remove -Filter parameter
	5       09/12/2019  NK      Sanitize $child,$parent input. Update CMS query to return cms hierarchy

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.EXAMPLE
	Get-CMSInstances
	Returns full list of instances

.EXAMPLE
	Get-CMSInstances | Where-Object {$_.instance -like "pw*"}
	Returns list of instances with the instance name beginning with pw

.EXAMPLE
    Get-CMSInstances -child hci -parent "development"
    Returns list of instances under development/hci folder

.EXAMPLE
	(Get-CMSInstances | Where-Object {$_.instance -like "pw*"}).instance
	Returns the instance name ONLY where name is beginning with pw

.EXAMPLE
    (Get-CMSInstances | Where-Object {$_.instance -like "dw*"}).host_name | Sort-Object -Unique
    Returns unique list of host names which name is beginning with 'dw'

#>
	if (!$PSBoundParameters.ContainsKey('child')) {
		$child = "can connect"
	}
	else { 
		#escape ' and strip out characters which could be used for sql injection
		$child = $child.Replace("'", "''") -replace '[^a-zA-Z0-9 -,.]'
	}
	if (!$PSBoundParameters.ContainsKey('parent')) {
		$parent = "supported"
	}
	else { 
		#escape ' and strip out characters which could be used for sql-injection
		$parent = $parent.Replace("'", "''") -replace '[^a-zA-Z0-9 -,.]'
	}
	$InstanceQuery = "
DECLARE @child nvarchar(100) = '$child';
DECLARE @parent nvarchar(100) = '$parent';
WITH ServerGroups(parent_id, server_group_id, [name],[level],[cms_path]) AS 
	(
		SELECT 
			tg.parent_id, 
			tg.server_group_id, 
			tg.name
			,level=0
			,cms_path=cast('+' as varchar(1000))
		FROM 
			msdb.dbo.sysmanagement_shared_server_groups tg
		WHERE 
			is_system_object = 0
			AND (tg.name = @child)
			AND (tg.parent_id in (SELECT server_group_id from msdb.dbo.sysmanagement_shared_server_groups where name = @parent))
		UNION ALL
		SELECT 
			 cg.parent_id
			,cg.server_group_id
			,cg.name
			,level+1
			,cms_path=LTRIM(CAST((cms_path +' / '+pg.name) as varchar(1000)))
		FROM 
			msdb.dbo.sysmanagement_shared_server_groups cg
				INNER JOIN ServerGroups pg
					ON cg.parent_id = pg.server_group_id
	)
	
	, Servers AS
	(
	SELECT
		isnull(s.name,'') as instance,
		CASE WHEN CHARINDEX('\',s.server_name)>0 THEN LEFT(s.server_name, CHARINDEX('\',s.server_name)-1) ELSE s.server_name END as [host_name],
		cast(cast(s.description as xml).query('data(/instance/name[1])') as varchar(300)) as name,
		cast(cast(s.description as xml).query('data(/instance/application_name[1])') as varchar(300)) as application_name,
		cast(cast(s.description as xml).query('data(/instance/owner[1])') as varchar(300)) as owner,
		cast(cast(s.description as xml).query('data(/instance/owner_email_address[1])') as varchar(300)) as owner_email_address,
		cast(cast(s.description as xml).query('data(/instance/outage_cycle[1])') as varchar(300)) as outage_cycle,
		cast(cast(s.description as xml).query('data(/instance/approver_email_address[1])') as varchar(300)) as instance_approver_email_address,
		cast(cast(s.description as xml).query('data(/outage/OutageDescription[1])') as varchar(300)) as OutageDescription,
		cast(cast(s.description as xml).query('data(/outage/outage_specific_cycle[1])') as varchar(300)) as outage_specific_cycle,
		cast(cast(s.description as xml).query('data(/outage/outage_date[1])') as varchar(300)) as outage_date,
		cast(cast(s.description as xml).query('data(/outage/approver_email_address[1])') as varchar(300)) as outage_approver_email_address,
		cast(cast(s.description as xml).query('data(/outage/approver_email_address[1]/response[1])') as varchar(300)) as response
		,cms_path
	FROM
		msdb.dbo.sysmanagement_shared_registered_servers_internal s
	INNER JOIN ServerGroups sg 
		ON s.server_group_id = sg.server_group_id
	)
	SELECT * FROM Servers as i
"
	$resultinstance = Invoke-SqlQuery -ServerInstance $CMSInstance -Query $InstanceQuery

	Write-Output $resultinstance
}

function Get-CMSHosts(
	[string]$child,
	[string]$parent
) {
	<#
.SYNOPSIS
	Gets a list of hosts in the current environment from the CMS server where we can specify the child and parent of the CMS tree.
	If no child and parent folder specified, hosts under "supported" and "can connect" will be returned.

.DESCRIPTION
	Gets a list of hosts in the current environment from the CMS server where we can specify the child and parent of the CMS tree.
	If no child and parent folder specified, hosts under "supported" and "can connect" will be returned.
	
.PARAMETER child
    Name of the child folder

.PARAMETER parent
    Name of the parent folder

.NOTES     
    Name: Get-CMSHosts
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build    Date        Author  Comments
	-----------------------------------------------------------------------------------------------
	1        20/03/2017  CD      Created
    2        18/10/2019  JB      Added Child and Parent folder, also ability to filter result
	3        27/11/2019  JB      Remove -Filter parameter. Update Example
	4        09/12/2019  NK      Sanitize $child,$parent input. 

    To Do:   

.LINK     
	https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.EXAMPLE
	Get-CMSHosts
	Returns full list of instances

.EXAMPLE
	Get-CMSHosts
	Returns full list of hosts

.EXAMPLE
    Get-CMSHosts -child hci -parent "crash and burn"
    Returns list of instances under crash and burn/hci

.EXAMPLE
    Get-CMSHosts -child hci -parent "crash and burn" | Where-Object {$_.host_name -like "*0992*n2*"}
    Returns list of instances under crash and burn/hci folder and the host name is like *0992*n2*

#>
	if (!$PSBoundParameters.ContainsKey('child')) {
		$child = "can connect"
	}
	else { 
		#strip out characters which could be used for sql-injection
		$child = $child.Replace("'", "''") -replace '[^a-zA-Z0-9 -,.]'
	}
	if (!$PSBoundParameters.ContainsKey('parent')) {
		$parent = "supported"
	}
	else { 
		#strip out characters which could be used for sql-injection
		$parent = $parent.Replace("'", "''") -replace '[^a-zA-Z0-9 -,.]'
	}

	$host_query = "WITH ServerGroups(parent_id, server_group_id, name) AS 
	(
		SELECT 
			tg.parent_id, 
			tg.server_group_id, 
			tg.name
		FROM 
			msdb.dbo.sysmanagement_shared_server_groups tg
		WHERE 
			is_system_object = 0
			AND (tg.name = '$child')
			AND (tg.parent_id in (SELECT server_group_id from msdb.dbo.sysmanagement_shared_server_groups where name = '$parent'))
		UNION ALL
		SELECT 
			cg.parent_id, 
			cg.server_group_id, 
			cg.name
		FROM 
			msdb.dbo.sysmanagement_shared_server_groups cg
				INNER JOIN ServerGroups pg
					ON cg.parent_id = pg.server_group_id
	), Servers as (
	SELECT
		DISTINCT CASE WHEN CHARINDEX('\',s.server_name)>0 THEN LEFT(s.server_name, CHARINDEX('\',s.server_name)-1) ELSE s.server_name END as [host_name]
	FROM
		msdb.dbo.sysmanagement_shared_registered_servers_internal s
	INNER JOIN ServerGroups sg 
		ON s.server_group_id = sg.server_group_id
    )
    SELECT * FROM Servers"
    
	$resulthosts = Invoke-SqlQuery -ServerInstance $CMSInstance -Query $host_query
    
	Write-Output $resulthosts
}

function Test-Port {   
	<#     
.SYNOPSIS     
    Tests port on computer.   
     
.DESCRIPTION   
    Tests port on computer.  
      
.PARAMETER computer   
    Name of server to test the port connection on. 
       
.PARAMETER port   
    Port to test  
        
.PARAMETER tcp   
    Use tcp port  
       
.PARAMETER udp   
    Use udp port   
      
.PARAMETER UDPTimeOut  
    Sets a timeout for UDP port query. (In milliseconds, Default is 1000)   
       
.PARAMETER TCPTimeOut  
    Sets a timeout for TCP port query. (In milliseconds, Default is 1000) 
                  
.NOTES     
    Name: Test-Port.ps1   
    Author: Boe Prox   
    DateCreated: 18Aug2010    
    List of Ports: http://www.iana.org/assignments/port-numbers   
       
    To Do:   
        Add capability to run background jobs for each host to shorten the time to scan.          
.LINK     
    https://boeprox.wordpress.org  
      
.EXAMPLE     
    Test-Port -computer 'server' -port 80   
    Checks port 80 on server 'server' to see if it is listening   
     
.EXAMPLE     
    'server' | Test-Port -port 80   
    Checks port 80 on server 'server' to see if it is listening  
       
.EXAMPLE     
    Test-Port -computer @("server1","server2") -port 80   
    Checks port 80 on server1 and server2 to see if it is listening   
     
.EXAMPLE 
    Test-Port -comp dc1 -port 17 -udp -UDPtimeout 10000 
     
    Server   : dc1 
    Port     : 17 
    TypePort : UDP 
    Open     : True 
    Notes    : "My spelling is Wobbly.  It's good spelling but it Wobbles, and the letters 
            get in the wrong places." A. A. Milne (1882-1958) 
     
    Description 
    ----------- 
    Queries port 17 (qotd) on the UDP port and returns whether port is open or not 
        
.EXAMPLE     
    @("server1","server2") | Test-Port -port 80   
    Checks port 80 on server1 and server2 to see if it is listening   
       
.EXAMPLE     
    (Get-Content hosts.txt) | Test-Port -port 80   
    Checks port 80 on servers in host file to see if it is listening  
      
.EXAMPLE     
    Test-Port -computer (Get-Content hosts.txt) -port 80   
    Checks port 80 on servers in host file to see if it is listening  
         
.EXAMPLE     
    Test-Port -computer (Get-Content hosts.txt) -port @(1..59)   
    Checks a range of ports from 1-59 on all servers in the hosts.txt file       
             
#>    
	[cmdletbinding(   
		DefaultParameterSetName = '',   
		ConfirmImpact = 'low'   
	)]   
	Param(   
		[Parameter(   
			Mandatory = $True,   
			Position = 0,   
			ParameterSetName = '',   
			ValueFromPipeline = $True)]   
		[array]$computer,   
		[Parameter(   
			Position = 1,   
			Mandatory = $True,   
			ParameterSetName = '')]   
		[array]$port,   
		[Parameter(   
			Mandatory = $False,   
			ParameterSetName = '')]   
		[int]$TCPtimeout = 1000,   
		[Parameter(   
			Mandatory = $False,   
			ParameterSetName = '')]   
		[int]$UDPtimeout = 1000,              
		[Parameter(   
			Mandatory = $False,   
			ParameterSetName = '')]   
		[switch]$TCP,   
		[Parameter(   
			Mandatory = $False,   
			ParameterSetName = '')]   
		[switch]$UDP                                     
	)   
	Begin {   
		If (!$tcp -AND !$udp) { $tcp = $True }   
		#Typically you never do this, but in this case I felt it was for the benefit of the function   
		#as any errors will be noted in the output of the report           
		$ErrorActionPreference = "SilentlyContinue"   
		$report = @()   
	}   
	Process {      
		ForEach ($c in $computer) {   
			ForEach ($p in $port) {   
				If ($tcp) {     
					#Create temporary holder    
					$temp = "" | Select Server, Port, TypePort, Open, Notes   
					#Create object for connecting to port on computer   
					$tcpobject = new-Object system.Net.Sockets.TcpClient   
					#Connect to remote machine's port                 
					$connect = $tcpobject.BeginConnect($c, $p, $null, $null)   
					#Configure a timeout before quitting   
					$wait = $connect.AsyncWaitHandle.WaitOne($TCPtimeout, $false)   
					#If timeout   
					If (!$wait) {   
						#Close connection   
						$tcpobject.Close()   
						Write-Verbose "Connection Timeout"   
						#Build report   
						$temp.Server = $c   
						$temp.Port = $p   
						$temp.TypePort = "TCP"   
						$temp.Open = "False"   
						$temp.Notes = "Connection to Port Timed Out"   
					}
					Else {   
						$error.Clear()   
						$tcpobject.EndConnect($connect) | out-Null   
						#If error   
						If ($error[0]) {   
							#Begin making error more readable in report   
							[string]$string = ($error[0].exception).message   
							$message = (($string.split(":")[1]).replace('"', "")).TrimStart()   
							$failed = $true   
						}   
						#Close connection       
						$tcpobject.Close()   
						#If unable to query port to due failure   
						If ($failed) {   
							#Build report   
							$temp.Server = $c   
							$temp.Port = $p   
							$temp.TypePort = "TCP"   
							$temp.Open = "False"   
							$temp.Notes = "$message"   
						}
						Else {   
							#Build report   
							$temp.Server = $c   
							$temp.Port = $p   
							$temp.TypePort = "TCP"   
							$temp.Open = "True"     
							$temp.Notes = ""   
						}   
					}      
					#Reset failed value   
					$failed = $Null       
					#Merge temp array with report               
					$report += $temp   
				}       
				If ($udp) {   
					#Create temporary holder    
					$temp = "" | Select Server, Port, TypePort, Open, Notes                                      
					#Create object for connecting to port on computer   
					$udpobject = new-Object system.Net.Sockets.Udpclient 
					#Set a timeout on receiving message  
					$udpobject.client.ReceiveTimeout = $UDPTimeout  
					#Connect to remote machine's port                 
					Write-Verbose "Making UDP connection to remote server"  
					$udpobject.Connect("$c", $p)  
					#Sends a message to the host to which you have connected.  
					Write-Verbose "Sending message to remote host"  
					$a = new-object system.text.asciiencoding  
					$byte = $a.GetBytes("$(Get-Date)")  
					[void]$udpobject.Send($byte, $byte.length)  
					#IPEndPoint object will allow us to read datagrams sent from any source.   
					Write-Verbose "Creating remote endpoint"  
					$remoteendpoint = New-Object system.net.ipendpoint([system.net.ipaddress]::Any, 0)  
					Try {  
						#Blocks until a message returns on this socket from a remote host.  
						Write-Verbose "Waiting for message return"  
						$receivebytes = $udpobject.Receive([ref]$remoteendpoint)  
						[string]$returndata = $a.GetString($receivebytes) 
						If ($returndata) { 
							Write-Verbose "Connection Successful"   
							#Build report   
							$temp.Server = $c   
							$temp.Port = $p   
							$temp.TypePort = "UDP"   
							$temp.Open = "True"   
							$temp.Notes = $returndata    
							$udpobject.close()    
						}                        
					}
					Catch {  
						If ($_.ToString() -match "\bRespond after a period of time\b") {  
							#Close connection   
							$udpobject.Close()   
							#Make sure that the host is online and not a false positive that it is open  
							If (Test-Connection -comp $c -count 1 -quiet) {  
								Write-Verbose "Connection Open"   
								#Build report   
								$temp.Server = $c   
								$temp.Port = $p   
								$temp.TypePort = "UDP"   
								$temp.Open = "True"   
								$temp.Notes = ""  
							}
							Else {  
								<#  
                                It is possible that the host is not online or that the host is online,   
                                but ICMP is blocked by a firewall and this port is actually open.  
                                #>  
								Write-Verbose "Host maybe unavailable"   
								#Build report   
								$temp.Server = $c   
								$temp.Port = $p   
								$temp.TypePort = "UDP"   
								$temp.Open = "False"   
								$temp.Notes = "Unable to verify if port is open or if host is unavailable."                                  
							}                          
						}
						ElseIf ($_.ToString() -match "forcibly closed by the remote host" ) {  
							#Close connection   
							$udpobject.Close()   
							Write-Verbose "Connection Timeout"   
							#Build report   
							$temp.Server = $c   
							$temp.Port = $p   
							$temp.TypePort = "UDP"   
							$temp.Open = "False"   
							$temp.Notes = "Connection to Port Timed Out"                          
						}
						Else {       
							
							$udpobject.close()  
						}  
					}      
					#Merge temp array with report               
					$report += $temp   
				}                                   
			}   
		}                   
	}   
	End {   
		#Generate Report   
		$report  
	} 
}

function Write-DataTable { 
	<# 
.SYNOPSIS 
	Writes data to a SQL Server table

.DESCRIPTION 
	Writes data to a SQL Server table. 
	
	The target can only be a SQL Server table, however the data source is not limited to SQL Server; any can be used as long as the data can be loaded to a DataTable instance or read with a IDataReader instance. 

.INPUTS 
	None 
    You cannot pipe objects to Write-DataTable 

.OUTPUTS 
	None 
    Produces no output 

.EXAMPLE 
	$dt = Invoke-SqlQuery -ServerInstance "Z003\R2" -Database pubs "select *  from authors" 
	Write-DataTable -ServerInstance "Z003\R2" -Database pubscopy -TableName authors -Data $dt 
	This example loads a variable dt of type DataTable from query and write the datatable to another database 

.NOTES 
	Write-DataTable uses the SqlBulkCopy class see links for additional information on this class. 
	Version History 
	v1.0   - Chad Miller - Initial release 
	v1.1   - Chad Miller - Fixed error message 
.LINK 
	http://msdn.microsoft.com/en-us/library/30c3y597%28v=VS.90%29.aspx 
#> 
	[CmdletBinding()] 
	param( 
		[Parameter(Position = 0, Mandatory = $true)] [string]$ServerInstance, 
		[Parameter(Position = 1, Mandatory = $true)] [string]$Database, 
		[Parameter(Position = 2, Mandatory = $true)] [string]$TableName, 
		[Parameter(Position = 3, Mandatory = $true)] $Data, 
		[Parameter(Position = 4, Mandatory = $false)] [string]$Username, 
		[Parameter(Position = 5, Mandatory = $false)] [string]$Password, 
		[Parameter(Position = 6, Mandatory = $false)] [Int32]$BatchSize = 50000, 
		[Parameter(Position = 7, Mandatory = $false)] [Int32]$QueryTimeout = 0, 
		[Parameter(Position = 8, Mandatory = $false)] [Int32]$ConnectionTimeout = 15 
	) 
     
	$conn = new-object System.Data.SqlClient.SQLConnection 
 
	if ($Username -and $Password) 
 { $ConnectionString = "Server={0};Database={1};User ID={2};Password={3};Trusted_Connection=False;Connect Timeout={4}" -f $ServerInstance, $Database, $Username, $Password, $ConnectionTimeout } 
	else 
 { $ConnectionString = "Server={0};Database={1};Integrated Security=True;Connect Timeout={2}" -f $ServerInstance, $Database, $ConnectionTimeout } 
 
	$conn.ConnectionString = $ConnectionString 
 
	try { 
		$conn.Open() 
		$bulkCopy = new-object ("Data.SqlClient.SqlBulkCopy") $connectionString 
		$bulkCopy.DestinationTableName = $tableName 
		$bulkCopy.BatchSize = $BatchSize 
		$bulkCopy.BulkCopyTimeout = $QueryTimeOut 
		$bulkCopy.WriteToServer($Data) 
		$conn.Close() 
	} 
	catch { 
		$ex = $_.Exception 
		Write-Error "$ex.Message" 
		continue 
	} 
 
} #Write-DataTable

function Add-SqlTable {  
	<#  
.SYNOPSIS  
Creates a SQL Server table from a DataTable  
.DESCRIPTION  
Creates a SQL Server table from a DataTable using SMO.  
.EXAMPLE  
$dt = Invoke-Sqlcmd2 -ServerInstance "Z003\R2" -Database pubs "select *  from authors"; Add-SqlTable -ServerInstance "Z003\R2" -Database pubscopy -TableName authors -DataTable $dt  
This example loads a variable dt of type DataTable from a query and creates an empty SQL Server table  
.EXAMPLE  
$dt = Get-Alias | Out-DataTable; Add-SqlTable -ServerInstance "Z003\R2" -Database pubscopy -TableName alias -DataTable $dt  
This example creates a DataTable from the properties of Get-Alias and creates an empty SQL Server table.  
.NOTES  
Add-SqlTable uses SQL Server Management Objects (SMO). SMO is installed with SQL Server Management Studio and is available  
as a separate download: http://www.microsoft.com/downloads/details.aspx?displaylang=en&FamilyID=ceb4346f-657f-4d28-83f5-aae0c5c83d52  
Version History  
v1.0   - Chad Miller - Initial Release  
v1.1   - Chad Miller - Updated documentation 
v1.2   - Chad Miller - Add loading Microsoft.SqlServer.ConnectionInfo 
v1.3   - Chad Miller - Added error handling 
v1.4   - Chad Miller - Add VarCharMax and VarBinaryMax handling 
v1.5   - Chad Miller - Added AsScript switch to output script instead of creating table 
v1.6   - Chad Miller - Updated GetSqlType types 
#>  
    
	param(  
		[Parameter(Position = 0, Mandatory = $true)] [string]$ServerInstance,  
		[Parameter(Position = 1, Mandatory = $true)] [string]$Database,  
		[Parameter(Position = 2, Mandatory = $true)] [String]$TableName,  
		[Parameter(Position = 3, Mandatory = $true)] $DataTable,  
		[Parameter(Position = 4, Mandatory = $false)] [string]$Username,  
		[Parameter(Position = 5, Mandatory = $false)] [string]$Password,  
		[Parameter(Position = 6, Mandatory = $false)] [switch]$AsScript 
	)  
	try { add-type -AssemblyName "Microsoft.SqlServer.ConnectionInfo, Version=10.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -EA Stop }
	catch { add-type -AssemblyName "Microsoft.SqlServer.ConnectionInfo" }
	try { add-type -AssemblyName "Microsoft.SqlServer.Smo, Version=10.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -EA Stop }
	catch { add-type -AssemblyName "Microsoft.SqlServer.Smo" }
 try { 
		if ($Username -and $Password)  
		{ $con = new-object ("Microsoft.SqlServer.Management.Common.ServerConnection") $ServerInstance, $Username, $Password }  
		else  
		{ $con = new-object ("Microsoft.SqlServer.Management.Common.ServerConnection") $ServerInstance }  
    
		# Handle if data row collection passed instaed of data table object
		if ($DataTable.GetType().Name -eq "DataRowCollection") { $DataTable = $DataTable[0].Table }

		$con.Connect()  
  
		$server = new-object ("Microsoft.SqlServer.Management.Smo.Server") $con  
		$db = $server.Databases[$Database]  
		$table = new-object ("Microsoft.SqlServer.Management.Smo.Table") $db, $TableName  
  
		foreach ($column in $DataTable.Columns) {  
			$sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]"$(GetSqlType $column.DataType.Name)"  
			if ($sqlDbType -eq 'VarBinary' -or $sqlDbType -eq 'VarChar') {  
				$MaxLength = $column.MaxLength
				if ($MaxLength -gt 0)  
				{ $dataType = new-object ("Microsoft.SqlServer.Management.Smo.DataType") $sqlDbType, $MaxLength } 
				else {
					$sqlDbType = [Microsoft.SqlServer.Management.Smo.SqlDataType]"$(GetSqlType $column.DataType.Name)Max" 
					$dataType = new-object ("Microsoft.SqlServer.Management.Smo.DataType") $sqlDbType 
				} 
			}  
			else  
			{ $dataType = new-object ("Microsoft.SqlServer.Management.Smo.DataType") $sqlDbType }  
			$col = new-object ("Microsoft.SqlServer.Management.Smo.Column") $table, $column.ColumnName, $dataType  
			$col.Nullable = $column.AllowDBNull  
			$table.Columns.Add($col)  
		}  
  
		if ($AsScript) { 
			$table.Script() 
		} 
		else { 
			$table.Create() 
		} 
	} 
	catch { 
		$message = $_.Exception.GetBaseException().Message 
		Write-Error $message 
	} 
   
} #Add-SqlTable


function Invoke-Parallel {
	<#
    .SYNOPSIS
        Function to control parallel processing using runspaces

    .DESCRIPTION
        Function to control parallel processing using runspaces

            Note that each runspace will not have access to variables and commands loaded in your session or in other runspaces by default.  
            This behaviour can be changed with parameters.

    .PARAMETER ScriptFile
        File to run against all input objects.  Must include parameter to take in the input object, or use $args.  Optionally, include parameter to take in parameter.  Example: C:\script.ps1

    .PARAMETER ScriptBlock
        Scriptblock to run against all computers.

        You may use $Using:<Variable> language in PowerShell 3 and later.
        
            The parameter block is added for you, allowing behaviour similar to foreach-object:
                Refer to the input object as $_.
                Refer to the parameter parameter as $parameter

    .PARAMETER InputObject
        Run script against these specified objects.

    .PARAMETER Parameter
        This object is passed to every script block.  You can use it to pass information to the script block; for example, the path to a logging folder
        
            Reference this object as $parameter if using the scriptblock parameterset.

    .PARAMETER ImportVariables
        If specified, get user session variables and add them to the initial session state

    .PARAMETER ImportModules
        If specified, get loaded modules and pssnapins, add them to the initial session state

    .PARAMETER Throttle
        Maximum number of threads to run at a single time.

    .PARAMETER SleepTimer
        Milliseconds to sleep after checking for completed runspaces and in a few other spots.  I would not recommend dropping below 200 or increasing above 500

    .PARAMETER RunspaceTimeout
        Maximum time in seconds a single thread can run.  If execution of your code takes longer than this, it is disposed.  Default: 0 (seconds)

        WARNING:  Using this parameter requires that maxQueue be set to throttle (it will be by default) for accurate timing.  Details here:
        http://gallery.technet.microsoft.com/Run-Parallel-Parallel-377fd430

    .PARAMETER NoCloseOnTimeout
		Do not dispose of timed out tasks or attempt to close the runspace if threads have timed out. This will prevent the script from hanging in certain situations where threads become non-responsive, at the expense of leaking memory within the PowerShell host.

    .PARAMETER MaxQueue
        Maximum number of powershell instances to add to runspace pool.  If this is higher than $throttle, $timeout will be inaccurate
        
        If this is equal or less than throttle, there will be a performance impact

        The default value is $throttle times 3, if $runspaceTimeout is not specified
        The default value is $throttle, if $runspaceTimeout is specified

    .PARAMETER LogFile
        Path to a file where we can log results, including run time for each thread, whether it completes, completes with errors, or times out.

	.PARAMETER Quiet
		Disable progress bar.

    .EXAMPLE
        Each example uses Test-ForPacs.ps1 which includes the following code:
            param($computer)

            if(test-connection $computer -count 1 -quiet -BufferSize 16){
                $object = [pscustomobject] @{
                    Computer=$computer;
                    Available=1;
                    Kodak=$(
                        if((test-path "\\$computer\c$\users\public\desktop\Kodak Direct View Pacs.url") -or (test-path "\\$computer\c$\documents and settings\all users

        \desktop\Kodak Direct View Pacs.url") ){"1"}else{"0"}
                    )
                }
            }
            else{
                $object = [pscustomobject] @{
                    Computer=$computer;
                    Available=0;
                    Kodak="NA"
                }
            }

            $object

    .EXAMPLE
        Invoke-Parallel -scriptfile C:\public\Test-ForPacs.ps1 -inputobject $(get-content C:\pcs.txt) -runspaceTimeout 10 -throttle 10

            Pulls list of PCs from C:\pcs.txt,
            Runs Test-ForPacs against each
            If any query takes longer than 10 seconds, it is disposed
            Only run 10 threads at a time

    .EXAMPLE
        Invoke-Parallel -scriptfile C:\public\Test-ForPacs.ps1 -inputobject c-is-ts-91, c-is-ts-95

            Runs against c-is-ts-91, c-is-ts-95 (-computername)
            Runs Test-ForPacs against each

    .EXAMPLE
        $stuff = [pscustomobject] @{
            ContentFile = "windows\system32\drivers\etc\hosts"
            Logfile = "C:\temp\log.txt"
        }
    
        $computers | Invoke-Parallel -parameter $stuff {
            $contentFile = join-path "\\$_\c$" $parameter.contentfile
            Get-Content $contentFile |
                set-content $parameter.logfile
        }

        This example uses the parameter argument.  This parameter is a single object.  To pass multiple items into the script block, we create a custom object (using a PowerShell v3 language) with properties we want to pass in.

        Inside the script block, $parameter is used to reference this parameter object.  This example sets a content file, gets content from that file, and sets it to a predefined log file.

    .EXAMPLE
        $test = 5
        1..2 | Invoke-Parallel -ImportVariables {$_ * $test}

        Add variables from the current session to the session state.  Without -ImportVariables $Test would not be accessible

    .EXAMPLE
        $test = 5
        1..2 | Invoke-Parallel -ImportVariables {$_ * $Using:test}

        Reference a variable from the current session with the $Using:<Variable> syntax.  Requires PowerShell 3 or later.

    .FUNCTIONALITY
        PowerShell Language

    .NOTES

		Name: Invoke-Parallel
		Author: External
		DateCreated: 2017-03-20  
    
		Build	Date		Author	Comments
		-----------------------------------------------------------------------------------------------
		1		20/03/2017	CD		Added to DETDBA module
		2		04/04/2017	CD		Fixed bug where timed out jobs would hang. Job is now stopped with BeginStop and runspacepool closed with BeginClose 
									when NoCloseOnTimeout param specified.
									
    To Do:   


	Original Notes:
        Credit to Boe Prox for the base runspace code and $Using implementation
            http://learn-powershell.net/2012/05/10/speedy-network-information-query-using-powershell/
            http://gallery.technet.microsoft.com/scriptcenter/Speedy-Network-Information-5b1406fb#content
            https://github.com/proxb/PoshRSJob/
        Credit to T Bryce Yehl for the Quiet and NoCloseOnTimeout implementations
        Credit to Sergei Vorobev for the many ideas and contributions that have improved functionality, reliability, and ease of use


    .LINK
        https://github.com/RamblingCookieMonster/Invoke-Parallel
    #>
	[cmdletbinding(DefaultParameterSetName = 'ScriptBlock')]
	Param (   
		[Parameter(Mandatory = $false, position = 0, ParameterSetName = 'ScriptBlock')]
		[System.Management.Automation.ScriptBlock]$ScriptBlock,

		[Parameter(Mandatory = $false, ParameterSetName = 'ScriptFile')]
		[ValidateScript( { test-path $_ -pathtype leaf })]
		$ScriptFile,

		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias('CN', '__Server', 'IPAddress', 'Server', 'ComputerName')]    
		[PSObject]$InputObject,

		[PSObject]$Parameter,

		[switch]$ImportVariables,

		[switch]$ImportModules,

		[int]$Throttle = 20,

		[int]$SleepTimer = 200,

		[int]$RunspaceTimeout = 0,

		[switch]$NoCloseOnTimeout = $false,

		[int]$MaxQueue,

		[validatescript( { Test-Path (Split-Path $_ -parent) })]
		[string]$LogFile,

		[switch] $Quiet = $false
	)
    
	Begin {
                
		#No max queue specified?  Estimate one.
		#We use the script scope to resolve an odd PowerShell 2 issue where MaxQueue isn't seen later in the function
		if ( -not $PSBoundParameters.ContainsKey('MaxQueue') ) {
			if ($RunspaceTimeout -ne 0) { $script:MaxQueue = $Throttle }
			else { $script:MaxQueue = $Throttle * 3 }
		}
		else {
			$script:MaxQueue = $MaxQueue
		}

		Write-Verbose "Throttle: '$throttle' SleepTimer '$sleepTimer' runSpaceTimeout '$runspaceTimeout' maxQueue '$maxQueue' logFile '$logFile'"

		#If they want to import variables or modules, create a clean runspace, get loaded items, use those to exclude items
		if ($ImportVariables -or $ImportModules) {
			$StandardUserEnv = [powershell]::Create().addscript( {

					#Get modules and snapins in this clean runspace
					$Modules = Get-Module | Select -ExpandProperty Name
					$Snapins = Get-PSSnapin | Select -ExpandProperty Name

					#Get variables in this clean runspace
					#Called last to get vars like $? into session
					$Variables = Get-Variable | Select -ExpandProperty Name
                
					#Return a hashtable where we can access each.
					@{
						Variables = $Variables
						Modules   = $Modules
						Snapins   = $Snapins
					}
				}).invoke()[0]
            
			if ($ImportVariables) {
				#Exclude common parameters, bound parameters, and automatic variables
				Function _temp { [cmdletbinding()] param() }
				$VariablesToExclude = @( (Get-Command _temp | Select -ExpandProperty parameters).Keys + $PSBoundParameters.Keys + $StandardUserEnv.Variables )
				Write-Verbose "Excluding variables $( ($VariablesToExclude | sort ) -join ", ")"

				# we don't use 'Get-Variable -Exclude', because it uses regexps. 
				# One of the veriables that we pass is '$?'. 
				# There could be other variables with such problems.
				# Scope 2 required if we move to a real module
				$UserVariables = @( Get-Variable | Where { -not ($VariablesToExclude -contains $_.Name) } ) 
				Write-Verbose "Found variables to import: $( ($UserVariables | Select -expandproperty Name | Sort ) -join ", " | Out-String).`n"

			}

			if ($ImportModules) {
				$UserModules = @( Get-Module | Where { $StandardUserEnv.Modules -notcontains $_.Name -and (Test-Path $_.Path -ErrorAction SilentlyContinue) } | Select -ExpandProperty Path )
				$UserSnapins = @( Get-PSSnapin | Select -ExpandProperty Name | Where { $StandardUserEnv.Snapins -notcontains $_ } ) 
			}
		}

		#region functions
            
		Function Get-RunspaceData {
			[cmdletbinding()]
			param( [switch]$Wait )

			#loop through runspaces
			#if $wait is specified, keep looping until all complete
			Do {

				#set more to false for tracking completion
				$more = $false

				#Progress bar if we have inputobject count (bound parameter)
				if (-not $Quiet) {
					Write-Progress  -Activity "Running Query" -Status "Starting threads"`
						-CurrentOperation "$startedCount threads defined - $totalCount input objects - $script:completedCount input objects processed"`
						-PercentComplete $( Try { $script:completedCount / $totalCount * 100 } Catch { 0 } )
				}

				#run through each runspace.           
				Foreach ($runspace in $runspaces) {
                    
					#get the duration - inaccurate
					$currentdate = Get-Date
					$runtime = $currentdate - $runspace.startTime
					$runMin = [math]::Round( $runtime.totalminutes , 2 )

					#set up log object
					$log = "" | select Date, Action, Runtime, Status, Details
					$log.Action = "Removing:'$($runspace.object)'"
					$log.Date = $currentdate
					$log.Runtime = "$runMin minutes"

					#If runspace completed, end invoke, dispose, recycle, counter++
					If ($runspace.Runspace.isCompleted) {
                            
						$script:completedCount++
                        
						#check if there were errors
						if ($runspace.powershell.Streams.Error.Count -gt 0) {
                                
							#set the logging info and move the file to completed
							$log.status = "CompletedWithErrors"
							Write-Verbose ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1]
							foreach ($ErrorRecord in $runspace.powershell.Streams.Error) {
								Write-Error -ErrorRecord $ErrorRecord
							}
						}
						else {
                                
							#add logging details and cleanup
							$log.status = "Completed"
							Write-Verbose ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1]
						}

						#everything is logged, clean up the runspace
						$runspace.powershell.EndInvoke($runspace.Runspace)
						$runspace.powershell.dispose()
						$runspace.Runspace = $null
						$runspace.powershell = $null

					}

					#If runtime exceeds max, dispose the runspace
					ElseIf ( $runspaceTimeout -ne 0 -and $runtime.totalseconds -gt $runspaceTimeout) {
                            
						$script:completedCount++
						$script:timedOutTasks = $true
                            
						#add logging details and cleanup
						$log.status = "TimedOut"
						Write-Verbose ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1]
						Write-Error "Runspace timed out at $($runtime.totalseconds) seconds for the object:`n$($runspace.object | out-string)"

						#Depending on how it hangs, we could still get stuck here as dispose calls a synchronous method on the powershell instance
						if ($noCloseOnTimeout) { [void]$runspace.powershell.BeginStop($null, $null) }
						else { $runspace.powershell.dispose() }
						$runspace.Runspace = $null
						$runspace.powershell = $null
						$completedCount++

					}
                   
					#If runspace isn't null set more to true  
					ElseIf ($runspace.Runspace -ne $null ) {
						$log = $null
						$more = $true
					}

					#log the results if a log file was indicated
					if ($logFile -and $log) {
						($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1] | out-file $LogFile -append
					}
				}

				#Clean out unused runspace jobs
				$temphash = $runspaces.clone()
				$temphash | Where { $_.runspace -eq $Null } | ForEach {
					$Runspaces.remove($_)
				}

				#sleep for a bit if we will loop again
				if ($PSBoundParameters['Wait']) { Start-Sleep -milliseconds $SleepTimer }

				#Loop again only if -wait parameter and there are more runspaces to process
			} while ($more -and $PSBoundParameters['Wait'])
                
			#End of runspace function
		}

		#endregion functions
        
		#region Init

		if ($PSCmdlet.ParameterSetName -eq 'ScriptFile') {
			$ScriptBlock = [scriptblock]::Create( $(Get-Content $ScriptFile | out-string) )
		}
		elseif ($PSCmdlet.ParameterSetName -eq 'ScriptBlock') {
			#Start building parameter names for the param block
			[string[]]$ParamsToAdd = '$_'
			if ( $PSBoundParameters.ContainsKey('Parameter') ) {
				$ParamsToAdd += '$Parameter'
			}

			$UsingVariableData = $Null
                

			# This code enables $Using support through the AST.
			# This is entirely from  Boe Prox, and his https://github.com/proxb/PoshRSJob module; all credit to Boe!
                
			if ($PSVersionTable.PSVersion.Major -gt 2) {
				#Extract using references
				$UsingVariables = $ScriptBlock.ast.FindAll( { $args[0] -is [System.Management.Automation.Language.UsingExpressionAst] }, $True)    

				If ($UsingVariables) {
					$List = New-Object 'System.Collections.Generic.List`1[System.Management.Automation.Language.VariableExpressionAst]'
					ForEach ($Ast in $UsingVariables) {
						[void]$list.Add($Ast.SubExpression)
					}

					$UsingVar = $UsingVariables | Group SubExpression | ForEach { $_.Group | Select -First 1 }
        
					#Extract the name, value, and create replacements for each
					$UsingVariableData = ForEach ($Var in $UsingVar) {
						Try {
							$Value = Get-Variable -Name $Var.SubExpression.VariablePath.UserPath -ErrorAction Stop
							[pscustomobject]@{
								Name       = $Var.SubExpression.Extent.Text
								Value      = $Value.Value
								NewName    = ('$__using_{0}' -f $Var.SubExpression.VariablePath.UserPath)
								NewVarName = ('__using_{0}' -f $Var.SubExpression.VariablePath.UserPath)
							}
						}
						Catch {
							Write-Error "$($Var.SubExpression.Extent.Text) is not a valid Using: variable!"
						}
					}
					$ParamsToAdd += $UsingVariableData | Select -ExpandProperty NewName -Unique

					$NewParams = $UsingVariableData.NewName -join ', '
					$Tuple = [Tuple]::Create($list, $NewParams)
					$bindingFlags = [Reflection.BindingFlags]"Default,NonPublic,Instance"
					$GetWithInputHandlingForInvokeCommandImpl = ($ScriptBlock.ast.gettype().GetMethod('GetWithInputHandlingForInvokeCommandImpl', $bindingFlags))
        
					$StringScriptBlock = $GetWithInputHandlingForInvokeCommandImpl.Invoke($ScriptBlock.ast, @($Tuple))

					$ScriptBlock = [scriptblock]::Create($StringScriptBlock)

					Write-Verbose $StringScriptBlock
				}
			}
                
			$ScriptBlock = $ExecutionContext.InvokeCommand.NewScriptBlock("param($($ParamsToAdd -Join ", "))`r`n" + $Scriptblock.ToString())
		}
		else {
			Throw "Must provide ScriptBlock or ScriptFile"; Break
		}

		Write-Debug "`$ScriptBlock: $($ScriptBlock | Out-String)"
		Write-Verbose "Creating runspace pool and session states"

		#If specified, add variables and modules/snapins to session state
		$sessionstate = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
		if ($ImportVariables) {
			if ($UserVariables.count -gt 0) {
				foreach ($Variable in $UserVariables) {
					$sessionstate.Variables.Add( (New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $Variable.Name, $Variable.Value, $null) )
					Write-Verbose "Adding $($Variable.Name) $($Variable.Value)"
				}
			}
		}
		if ($ImportModules) {
			if ($UserModules.count -gt 0) {
				foreach ($ModulePath in $UserModules) {
					$sessionstate.ImportPSModule($ModulePath)
				}
			}
			if ($UserSnapins.count -gt 0) {
				foreach ($PSSnapin in $UserSnapins) {
					[void]$sessionstate.ImportPSSnapIn($PSSnapin, [ref]$null)
				}
			}
		}

		#Create runspace pool
		$runspacepool = [runspacefactory]::CreateRunspacePool(1, $Throttle, $sessionstate, $Host)
		$runspacepool.Open()

		Write-Verbose "Creating empty collection to hold runspace jobs"
		$Script:runspaces = New-Object System.Collections.ArrayList        
        
		#If inputObject is bound get a total count and set bound to true
		$bound = $PSBoundParameters.keys -contains "InputObject"
		if (-not $bound) {
			[System.Collections.ArrayList]$allObjects = @()
		}

		#Set up log file if specified
		if ( $LogFile ) {
			New-Item -ItemType file -path $logFile -force | Out-Null
			("" | Select Date, Action, Runtime, Status, Details | ConvertTo-Csv -NoTypeInformation -Delimiter ";")[0] | Out-File $LogFile
		}

		#write initial log entry
		$log = "" | Select Date, Action, Runtime, Status, Details
		$log.Date = Get-Date
		$log.Action = "Batch processing started"
		$log.Runtime = $null
		$log.Status = "Started"
		$log.Details = $null
		if ($logFile) {
			($log | convertto-csv -Delimiter ";" -NoTypeInformation)[1] | Out-File $LogFile -Append
		}

		$script:timedOutTasks = $false

		#endregion INIT
	}

	Process {

		#add piped objects to all objects or set all objects to bound input object parameter
		if ($bound) {
			$allObjects = $InputObject
		}
		Else {
			[void]$allObjects.add( $InputObject )
		}
	}

	End {
        
		#Use Try/Finally to catch Ctrl+C and clean up.
		Try {
			#counts for progress
			$totalCount = $allObjects.count
			$script:completedCount = 0
			$startedCount = 0

			foreach ($object in $allObjects) {
        
				#region add scripts to runspace pool
                    
				#Create the powershell instance, set verbose if needed, supply the scriptblock and parameters
				$powershell = [powershell]::Create()
                    
				if ($VerbosePreference -eq 'Continue') {
					[void]$PowerShell.AddScript( { $VerbosePreference = 'Continue' })
				}

				[void]$PowerShell.AddScript($ScriptBlock).AddArgument($object)

				if ($parameter) {
					[void]$PowerShell.AddArgument($parameter)
				}

				# $Using support from Boe Prox
				if ($UsingVariableData) {
					Foreach ($UsingVariable in $UsingVariableData) {
						Write-Verbose "Adding $($UsingVariable.Name) with value: $($UsingVariable.Value)"
						[void]$PowerShell.AddArgument($UsingVariable.Value)
					}
				}

				#Add the runspace into the powershell instance
				$powershell.RunspacePool = $runspacepool
    
				#Create a temporary collection for each runspace
				$temp = "" | Select-Object PowerShell, StartTime, object, Runspace
				$temp.PowerShell = $powershell
				$temp.StartTime = Get-Date
				$temp.object = $object
    
				#Save the handle output when calling BeginInvoke() that will be used later to end the runspace
				$temp.Runspace = $powershell.BeginInvoke()
				$startedCount++

				#Add the temp tracking info to $runspaces collection
				Write-Verbose ( "Adding {0} to collection at {1}" -f $temp.object, $temp.starttime.tostring() )
				$runspaces.Add($temp) | Out-Null
            
				#loop through existing runspaces one time
				Get-RunspaceData

				#If we have more running than max queue (used to control timeout accuracy)
				#Script scope resolves odd PowerShell 2 issue
				$firstRun = $true
				while ($runspaces.count -ge $Script:MaxQueue) {

					#give verbose output
					if ($firstRun) {
						Write-Verbose "$($runspaces.count) items running - exceeded $Script:MaxQueue limit."
					}
					$firstRun = $false
                    
					#run get-runspace data and sleep for a short while
					Get-RunspaceData
					Start-Sleep -Milliseconds $sleepTimer
                    
				}

				#endregion add scripts to runspace pool
			}
                     
			Write-Verbose ( "Finish processing the remaining runspace jobs: {0}" -f ( @($runspaces | Where { $_.Runspace -ne $Null }).Count) )
			Get-RunspaceData -wait

			if (-not $quiet) {
				Write-Progress -Activity "Running Query" -Status "Starting threads" -Completed
			}
		}
		Finally {
			#Close the runspace pool, unless we specified no close on timeout and something timed out
			if ( ($script:timedOutTasks -eq $false) -or ( ($script:timedOutTasks -eq $true) -and ($noCloseOnTimeout -eq $false) ) ) {
				Write-Verbose "Closing the runspace pool"
				$runspacepool.close()
			}
			else { # close the runspace asynchronously... better than nothing!
				Write-Verbose "Closing the runspace pool (async)"
				[void]$runspacepool.BeginClose($null, $null)
			}

			#collect garbage
			[gc]::Collect()
		}       
	}
}

function Add-DataColumn (
	[Parameter(Mandatory = $true)]
	[System.Data.DataTable]$dt,
	[Parameter(Mandatory = $true)]
	[string]$column,
	[Parameter(Mandatory = $true)]
	$type,
	[Parameter(Mandatory = $true)]
	[int]$length,
	$value) {
	<#
.SYNOPSIS
	Adds a column to a result set as the first column

.DESCRIPTION
	Adds a column to a result set as the first column

.NOTES     
    Name: Add-DataColumn
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created
	2		24/03/2017	CD		Modified to work with DataTable instead of DataRows

    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER dt
	Expects a DataTable as per the output of Invoke-SqlQuery -AsDt

.PARAMETER column
	Name of the column to add

.PARAMETER type
	Type of the column to add

.PARAMETER length
	Length of the column if variable (ie string)

.PARAMETER value
	Value to assign to the new column for all rows in the result set

.EXAMPLE
	Add-DataColumn -rs $rs -column "instance_name" -type string -length 300 -value $server
	Adds a column named instance_name to the result set of type string and length 300. The value of $server will be populated in the result set.

#>
	$col = $dt.Columns.Add($column, $type)
	if ($length -gt 0) { $col.MaxLength = $length }
	$col.SetOrdinal(0)
	if ($value) { foreach ($row in $dt) { $row.$column = $value } }
}

function Get-LockoutEvents (
	[string]$UserName = [environment]::UserName,
	[int]$Minutes = 30
) {
	<#
.SYNOPSIS
	Query all SQL server event logs where user authentication has failed

.DESCRIPTION
	Query all SQL server event logs where user authentication has failed

.NOTES     
    Name: Get-LockoutEvents
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created

    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER Username
	User name to search for lockout events, default is the current user.
	User name without domain is required, eg "sacdobson8"

.PARAMETER Minutes
	Number of minutes to search the event logs for, default is 30 minutes.
	Warning: searching beyond 30 minutes can be very slow

.EXAMPLE
	Get-LockoutEvents
	Get lockout events for the current user that occurred in the last 30 minutes

	Server    : pw0000sqlpe001.detnsw.win
	EventTime : 20/03/2017 1:12:22 PM
	Message   : An account failed to log on.

				Logon Type:            3

				Account For Which Logon Failed:
				Security ID:        S-1-0-0
				Account Name:        sacdobson8
				Account Domain:        detnsw

.EXAMPLE
	Get-LockoutEvents -UserName "sadgeorgette" -Minutes 90
	Get lockout events for the user sadgeorgette that occurred in the last 90 minutes

	Server    : pw0000sqlpe001.detnsw.win
	EventTime : 20/03/2017 1:12:22 PM
	Message   : An account failed to log on.

				Logon Type:            3

				Account For Which Logon Failed:
				Security ID:        S-1-0-0
				Account Name:        sadgeorgette
				Account Domain:        detnsw
#>

	$servers = Get-CMSHosts
	$serverarr = @() + $servers | % { $_.host_name }
	$servercount = $servers.Count
	write-host "Checking $username on $servercount servers for failed authentication attempts"
	$paramobj = [pscustomobject] @{username = $username; minutes = $minutes }
	invoke-parallel -InputObject $serverarr -Parameter $paramobj -ScriptBlock { 
		$server = $_
		try {
			Get-EventLog -ComputerName $server -LogName Security -ErrorAction SilentlyContinue | % { $_; if ($_.TimeGenerated.CompareTo((get-date).AddMinutes(-$parameter.minutes)) -lt 1) { Break; } } | Where-Object { $_.EntryType -eq "FailureAudit" -and $_.Message.Contains($parameter.username) } | % { new-object psobject -property @{EventTime = $_.TimeGenerated; Server = $server; Message = $_.Message } } | Format-List #Select {$_.TimeGenerated}, {$server}, {$_.Message} | Format-List
		}
		catch {
			Write-Warning "$server - $_"
		}
	}
}

function Get-RemoteSessions(
	[string]$UserName = [environment]::UserName
) {
	<#
.SYNOPSIS
	Gets list of RDP sessions open on any servers in the current environment 

.DESCRIPTION
	Gets list of RDP sessions open on any servers in the current environment

.NOTES     
    Name: Get-RemoteSessions
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created

    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	$servers = Get-CMSHosts
	$servercount = $servers.Count
	write-host "Checking $username on $servercount servers"

	$paramobj = [pscustomobject] @{username = $username; errorcount = 0 }
	invoke-parallel -InputObject $servers -Parameter $paramobj -Quiet -ScriptBlock { 
		$server = $_
		try { gwmi win32_process -ComputerName $server.host_name -Filter "Name = 'explorer.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.GetOwner().User -eq $parameter.username } | % { New-Object psobject -Property @{Server = $server.host_name.PadRight(35); LogonTime = ([datetime]::ParseExact($_.CreationDate.Split(".")[0], 'yyyyMMddHHmmss', $null)) } } } catch { $parameter.errorcount = + 1 }
	}
	if ($paramobj.errorcount) { write-warning "Server errors:", $paramobj.errorcount }
}


function Test-FirewallPorts(
	[string]$SingleServer,
	[switch]$CMS
) {
	<#
.SYNOPSIS
	Tests pre-defined set of ports to verify firewall rules are correctly setup

.DESCRIPTION
	Tests pre-defined set of ports to verify firewall rules are correctly setup

	Uses Test-Port to test the following ports:
		1434            UDP		- SQL Server Browser service
		135             TCP		- Remote Procedure Call
		49152 to 65535  TCP		- SQL Server named instance
		1433            TCP		- SQL Server default instance
		445             TCP		- Server Message Block
		5985            TCP		- Powershell Remoting

.NOTES     
    Name: Test-FirewallPorts
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created

    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER SingleServer
	Server host name to run port tests against

.PARAMETER CMS
	Test all hosts returned by the CMS

.EXAMPLE
	Test-FirewallPorts -SingleServer "upvewsql001.central.det.win"

	Testing port 1434 UDP...Closed
	Testing port 135 TCP...Open
	Getting list of SQL instances...found 1 instances
	Testing instance SQLDBA...Open on 49379
	Testing port 445 TCP...Open
	Testing port 5985 TCP...Closed

.EXAMPLE
	Test-FirewallPorts -CMS

	Checking firewall rules on 6 servers
	Starting tests on hpplswrp002.central.det.win
	Testing port 1434 UDP...Closed
	Testing port 135 TCP...Open
	Getting list of SQL instances...No named instances found
	Testing port 1433 TCP...Open
	Testing port 445 TCP...Open
	Testing port 5985 TCP...Closed
	...
#>
	function Test-ServerFW([string]$server) {
		# Test port 1434 UDP
		Write-Host "Testing port 1434 UDP..." -NoNewline
		$result = Test-Port -computer $server -port 1434 -UDP
		if ($result.Open -eq "True") { Write-Host "Open" -ForegroundColor Green }
		else { Write-Host "Closed" -ForegroundColor Red }

		# Test port 135 TCP
		Write-Host "Testing port 135 TCP..." -NoNewline
		$result = Test-Port -computer $server -port 135
		if ($result.Open -eq "True") { Write-Host "Open" -ForegroundColor Green }
		else { Write-Host "Closed" -ForegroundColor Red }

		# Test port 49152 to 65535 (get list of SQL instances)
		if ($result.Open -eq "True") {
			Write-Host "Getting list of SQL instances..." -NoNewline
			try { 
				#$portlist = Get-SQLInstancesPort $server 
				#Write-Host "found $($portlist.Length) instances"
				$instances = @() + (Get-Service MSSQL$* -ComputerName $server | % { $_.Name.Substring(6, $_.Name.Length - 6) })
			}
			catch { 
				Write-Host "$_" -ForegroundColor Red 
			}
			if ($instances) {
				Write-Host "found $($instances.Length) instances"
				foreach ($instance in $instances) {
					Write-Host "Testing instance $instance..." -NoNewline -ForegroundColor Gray
					#$result = Test-Port -computer $server -port $instance.port -TCP
					try { 
						if ($instance -eq "MSSQLSERVER") { $svrconn = $server } else { $svrconn = "$server\$instance" }
						$result = Invoke-Sqlcmd -ServerInstance $svrconn -Query "select top 1 value_data AS Port from sys.dm_server_registry WHERE value_name = 'TcpPort'" -ErrorAction Stop
						Write-Host "Open on", $result.Port -ForegroundColor Green
					}
					catch {
						Write-Host "Closed" -ForegroundColor Red
					}
				}
			}
			else { Write-Host "No named instances found" }
			if (Get-Service MSSQLSERVER -ComputerName $server -ErrorAction SilentlyContinue) {
				# Test port 1433 TCP
				Write-Host "Testing port 1433 TCP..." -NoNewline
				$result = Test-Port -computer $server -port 1433
				if ($result.Open -eq "True") { Write-Host "Open" -ForegroundColor Green }
				else { Write-Host "Closed" -ForegroundColor Red }
			}
		}
		else {
			Write-Host "Unable to get list of instance ports" -ForegroundColor Yellow
			# Test port 1433 TCP
			Write-Host "Testing port 1433 TCP..." -NoNewline
			$result = Test-Port -computer $server -port 1433
			if ($result.Open -eq "True") { Write-Host "Open" -ForegroundColor Green }
			else { Write-Host "Closed" -ForegroundColor Red }
		}

		# Test port 445 TCP
		Write-Host "Testing port 445 TCP..." -NoNewline
		$result = Test-Port -computer $server -port 445
		if ($result.Open -eq "True") { Write-Host "Open" -ForegroundColor Green }
		else { Write-Host "Closed" -ForegroundColor Red }

		# Test port 5985 TCP
		Write-Host "Testing port 5985 TCP..." -NoNewline
		$result = Test-Port -computer $server -port 5985
		if ($result.Open -eq "True") { Write-Host "Open" -ForegroundColor Green }
		else { Write-Host "Closed" -ForegroundColor Red }
	}
	if ($CMS) {
		$servers = Get-CMSHosts
		$servercount = $servers.Count
		write-host "Checking firewall rules on $servercount servers"
		foreach ($server in $servers) {
			Write-Host "Starting tests on", $server.host_name -ForegroundColor Cyan
			Test-ServerFW $server.host_name
		}
	}
	elseif ($SingleServer) {
		Write-Host "Starting tests on $SingleServer" -ForegroundColor Cyan
		Test-ServerFW $SingleServer
	}
 else {
		Write-Host "Usage: Test-FirewallPorts -SingleServer <hostname> (test single host)`n       Test-FirewallPorts -CMS (test all servers from CMS server)"
	}
}


function Invoke-ForEachInstance	{
	<#
.SYNOPSIS
	Loop through CMS instances, execute the supplied query and output to table in monitor db.

.DESCRIPTION
	Loop through CMS instances, execute the supplied query and output to table in monitor db or PS object.
	Query will be run in parallel against all servers. If result set is indeterminate based on execution against the CMS,
	the table will not be created until valid results are received. The table creation is now done in powershell and the instance_name
	column is dynamically inserted into result set.

.NOTES     
    Name: Invoke-ForEachInstance
    Author: Chris Dobson
    DateCreated: 2017-02-17     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		17/02/2017	CD		Created
	2		06/03/2017	CD		Added multithreading. Statement cost is estimated and parallelcost param determines whether query is run in parallel. Also added querytimeout param.
	3		07/03/2017	CD		Added output_server, output_username, output_password to allow a query results to be stored on a server other than the CMS itself
	4		08/03/2017	CD		Added posh mode - powershell dynamically creates the table, delaying creation if required.
	5		08/03/2017	CD		If query1 is a valid file, get the file contents
	6		20/03/2017	CD		Rewrote for_each_instance.ps1 into Invoke-ForEachInstance command. Removed singled threaded option and always execute in posh mode.
								OutputTable is optional, results output as object if not specifid.
	7		24/03/2017	CD		Object output merged to single DataTable
	8		08/05/2017	CD		Dont print errors when ErrorAction = SilentlyContinue
	9		18/05/2018	CD		Added support for pipeline input of $servers
	10		19/05/2017	CD		Bug fix, where sometimes DETDBA module isnt loaded by threads when run on a workstation
								Added Count property to the returned DataTable (rather than having to use $dt.Rows.Count)
	11		02/06/2017	CD		Bug fix, some rows missing when using outputtable - was setting the table created flag before it was created... oops.

    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER Query
	Can be a sql statement, or a file containing sql

.PARAMETER OutputTable
	table to populate in cms instance in monitor database

.PARAMETER Filter
	Filter clause to apply to CMS instance list
	Available filters:
		instance
		host_name
		application_name
		owner
		owner_email_address
		outage_cycle
		instance_approver_email_address
		OutageDescription
		outage_specific_cycle
		outage_date
		outage_approver_email_address
		response

.PARAMETER QueryTimeout
	Query time out in seconds, default is 30

.PARAMETER OutputServer
	Output results to server other than the CMS

.PARAMETER OutputUsername
	Output server username

.PARAMETER OutputPassword
	Output server password

.EXAMPLE
	Invoke-ForEachInstance -Query "SELECT GETDATE() AS TimeNow"

.EXAMPLE
	Invoke-ForEachInstance -Query "SELECT GETDATE() AS TimeNow" -OutputTable "query1"

.EXAMPLE
	Invoke-ForEachInstance -Query .\query1.sql -OutputTable "query1"

.EXAMPLE
	Invoke-ForEachInstance -Query .\query1.sql -OutputTable "query1" -OutputServer "host1\instance1" -OutputUserName "user1" -OutputPassword "password1"

#>
	[CmdletBinding()]  
	param (
		[Parameter(Mandatory = $true)]
		[string]$Query,
		[string]$OutputTable,
		[string]$Filter,
		[int]$QueryTimeout = 30,
		[Parameter(ValueFromPipeline = $True)][PSObject]$Servers = (Get-CMSInstances -Filter $Filter).instance,
		[string]$OutputServer,
		[string]$OutputUsername,
		[string]$OutputPassword
	)
	if ($DebugPreference -eq "Inquire") { $DebugPreference = "Continue" }
	$starttime = Get-Date
	Write-Verbose ("Start: {0}" -f (Get-Date $starttime -Format "HH:mm:ss"))

	# Test if $Query is a file and load
	$OFSdefault = $OFS
	$OFS = "`n" # Ensure new lines are maintained when converting the get-content string array to a text block
	if (!($Query.Contains("`n")) -and !($Query.Contains("`r"))) {
		if (Test-Path $Query -PathType Leaf) {
			$Query = [string](gc $Query)
		}
		elseif (Test-Path ".\$Query" -PathType Leaf) {
			$Query = [string](gc ".\$Query")
		}
	}
	$OFS = $OFSdefault

	# Handle pipeline input - store $input to our $Servers variable rather than use the "Process {}" method
	# Pipeline input might be from another Invoke-ForEachInstance or Get-CMSInstances or as a string array - we need to handle these 3 scenarios
	if ($input) {
		# .instance is from Get-CMSInstances, .instance_name is from Invoke-ForEachInstance otherwise assume string array
		$Servers = [string[]]($input | % { if ($_.instance) { $_.instance } elseif ($_.instance_name) { $_.instance_name } else { $_ } })
	}

	if (!$OutputServer) { $OutputServer = $CMSInstance }

	if ($OutputTable) {
		Write-Debug "Drop table if exists"
		$drop_query = "set nocount on; if object_id('$OutputTable', 'u') is not null drop table $OutputTable;"
		Write-Debug $drop_query
		Invoke-SqlQuery -ServerInstance $OutputServer -Database "monitor" -Query "set nocount on; if object_id('$OutputTable', 'u') is not null drop table $OutputTable;" -Username $output_username -Password $output_password

		Write-Debug "Create table dynamically using resultset"
		$rs = Invoke-SqlQuery -ServerInstance $CMSInstance -Database "master" -Query $Query -AsDt
		Write-Debug $rs
		if ($rs.Count) {
			Write-Debug "Add instance_name to data table"
			Add-DataColumn -dt $rs -column "instance_name" -type string -length 300

			Write-Debug "Create table"
			try {
				Add-SqlTable -ServerInstance $OutputServer -Database "monitor" -Tablename $OutputTable -DataTable $rs -Username $OutputUsername -Password $OutputPassword
				$istablecreated = $true
			}
			catch {
				throw($_)
				return
			}
		}
		else {
			Write-Warning "Delayed table creation, table will not be created if no rows returned"
		}
	}

	Write-Verbose ("Servers: {0}" -f $servers.Count)

	$paramobj = [pscustomobject] @{cms_instance = $CMSInstance; Query = $Query; OutputTable = $OutputTable; QueryTimeout = $QueryTimeout; OutputServer = $OutputServer; OutputUsername = $OutputUsername; OutputPassword = $OutputPassword; IsTablecreated = $IsTablecreated }

	$result = invoke-parallel -InputObject $servers -runspaceTimeout ($querytimeout * 2) -Parameter $paramobj -Verbose:$false -ScriptBlock { 
		$server = $_
		$rs = $null
		# Bug fix - sometimes the DETDBA module doesnt load when running on a workstation
		if (!(Get-Module DETDBA)) { Start-Sleep -m 1000; Import-Module DETDBA }

		try { $rs = Invoke-SqlQuery -ServerInstance $server -Database "master" -Query $parameter.Query -Timeout $parameter.QueryTimeout -AsDt }
		catch { return (New-Object psobject -property @{error = $true; msg = "Error $server, $_`n"; rs = $null }) }

		if ($rs.Rows.Count) {
			Add-DataColumn -dt $rs -column "instance_name" -type string -length 300 -value $server
			if ($parameter.OutputTable) {
				if (!$parameter.IsTablecreated) { # fast check
					# Sync threads with a mutex since we dont want multiple threads creating a table
					$Mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList $false, "Global\CreateTableMutex"
					$Mutex.WaitOne() | Out-Null
					### Mutex Protected ###
					if (!$parameter.IsTablecreated) {
						$dtclone = [System.Data.DataTable]$rs.Clone() # clone the data table because Add-SqlTable spits the dummy otherwise
						Add-SqlTable -ServerInstance $parameter.OutputServer -Database "monitor" -Tablename $parameter.OutputTable -DataTable $dtclone -Username $parameter.OutputUsername -Password $parameter.OutputPassword
						$parameter.istablecreated = $true 
					}
					### /Mutex Protected ###
					$Mutex.ReleaseMutex() | Out-Null
				}
				Write-DataTable -ServerInstance $parameter.OutputServer -Database "monitor" -TableName $parameter.OutputTable -Data $rs -Username $parameter.OutputUsername -Password $parameter.OutputPassword
			}
			else {
				# output object
			}
		}
		return (New-Object psobject -property @{error = $false; msg = ""; rs = $rs })
	}
	$rowcount = ($result.rs.Rows.Count | Measure-Object -Sum).Sum
	if (!$OutputTable) {
		# Merge multiple data tables into single and return
		$dt = New-Object System.Data.DataTable
		$result | ? { $_.rs } | ? { $_.rs.GetType().Name -eq "DataTable" } | % { $dt.Merge($_.rs) }
		# Add Count property at the dt level
		@(, $dt) | Add-Member -Name Count -Value $dt.Rows.Count -MemberType NoteProperty
		# To stop powershell unravelling the DataTable into an array of rows we give it a pretend array @(,$realobject)
		@(, $dt)
	}
	if ($ErrorActionPreference -ne "SilentlyContinue") {
		foreach ($r in $result) { if ($r.error) { Write-Host $r.msg -ForegroundColor Red; $errorflag += 1 } }
	}
	if ($errorflag) { Write-Error "$errorflag error(s) occured" }
	
	$endtime = Get-Date
	Write-Verbose ("End: {0}" -f (Get-Date $endtime -Format "HH:mm:ss"))
	Write-Verbose ("Duration: {0}" -f (($endtime - $starttime).TotalSeconds))
	Write-Verbose ("Rowcount: {0}" -f $rowcount)
}


function Invoke-ForEachInstanceMulti {
	<#
.SYNOPSIS
	Loop through CMS instances, execute the supplied query and output to table in monitor db.

.DESCRIPTION
	Get .sql scripts in supplied path and execute against all CMS instances, output to table/ps object.
	Query will be run in parallel against all servers. If result set is indeterminate based on execution against the CMS,
	the table will not be created until valid results are received. The table creation is now done in powershell and the instance_name
	column is dynamically inserted into result set.

.NOTES     
    Name: Invoke-ForEachInstance
    Author: Chris Dobson
    DateCreated: 2017-02-17     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created


    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER Path
	Directory containing .sql files

.PARAMETER OutputTable
	table to populate in cms instance in monitor database

.PARAMETER Filter
	Filter clause to apply to CMS instance list
	Available filters:
		instance
		application_name
		owner
		owner_email_address
		outage_cycle
		instance_approver_email_address
		OutageDescription
		outage_specific_cycle
		outage_date
		outage_approver_email_address
		response

.PARAMETER QueryTimeout
	Query time out in seconds, default is 30

.PARAMETER OutputServer
	Output results to server other than the CMS

.PARAMETER OutputUsername
	Output server username

.PARAMETER OutputPassword
	Output server password

.EXAMPLE
	Invoke-ForEachInstanceMulti -Path "c:\sqlscripts\"

.EXAMPLE
	Invoke-ForEachInstanceMulti -Path "sqlscripts\" -OutputTable "query"

.EXAMPLE
	Invoke-ForEachInstanceMulti -Path "sqlscripts\" -OutputTable "query" -OutputServer "host1\instance1" -OutputUserName "user1" -OutputPassword "password1"

#>
	[CmdletBinding()]  
	param (
		[Parameter(Mandatory = $true)]
		[ValidateScript( { Test-Path $_ -PathType 'Container' })] 
		[string]$Path,
		[Parameter(Mandatory = $true)]
		[string]$OutputTable,
		[string]$Filter,
		[int]$QueryTimeout = 30,
		[string]$OutputServer,
		[string]$OutputUsername,
		[string]$OutputPassword
	)

	$multiquery = @()
	$sqlfiles = Get-ChildItem $Path -Filter *.sql
	foreach ($sqlfile in $sqlfiles) {
		if ($Path.Contains(":\")) { $Query = $sqlfile.FullName }
		else { $Query = $sqlfile.FullName | Resolve-Path -Relative }
		$multi_output_table = "$($OutputTable)_$($sqlfile.BaseName)"
		Write-Host "Starting Invoke-ForEachInstance on $Query" -ForegroundColor Cyan
		Write-Host "Output table:", $multi_output_table -ForegroundColor Cyan
		Invoke-ForEachInstance -Query $query -OutputTable $multi_output_table -Filter $Filter -querytimeout $querytimeout -OutputServer $OutputServer -OutputUsername $OutputUsername -OutputPassword $OutputPassword
	}
}

function New-SSMSGroupRegistration {
	<#
.SYNOPSIS
	Create local server group registration & bulk fill with servers. Server list must be pasted into the powershell window.

.DESCRIPTION
	Create local server group registration & bulk fill with servers. Server list must be pasted into the powershell window.

.NOTES     
    Name: New-SSMSGroupRegistration 
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created
	2		21/03/2017	CD		Remove blank inputs from server list

    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER GroupName
	Name of the group registration to create

.EXAMPLE
	New-SSMSGroupRegistration "group1"

	Paste server list:
	server1
	server2

	Adding 2 servers to group1...
	Done
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$GroupName
	)

	$SSMS = "SQLSERVER:\SqlRegistration\Database Engine Server Group\"
	$Parent = "$SSMS\$GroupName\"
	$Instances = @()

	Write-Host "Paste server list:"
	while ($in = Read-Host) {
		$Instances += $in
	}

	# Pete-proof the input, remove whitespace
	$Instances = $Instances | ? { $_ -replace '\s', '' }

	if ($Instances) {
		Write-Host "Adding", $Instances.Count, "servers to $GroupName..."
	} 
	else { return }

	if (!(Test-Path $Parent)) {
		New-Item -Path $SSMS -Name $GroupName -ItemType "directory" 
	}
	else {
		Remove-Item -Path "$Parent\*"
	}

	foreach ($instance in $Instances) {
		# escape the \ character with the HTML equivalent %5C with adding named instances
		if (!$instance.Contains("\")) {
			if ($instance.ToLower().Contains($env:userdnsdomain.ToLower()) -or !$instance.Contains(".")) {
				$multiinstancecheck = Get-CMSInstances -Filter "instance like '$instance\%'"
			}
			else {
				Write-Warning "It appears as $instance is in a different domain - cannot expand host instances"
			}
			if ($multiinstancecheck.Count) {
				foreach ($mic in $multiinstancecheck) {
					New-Item -Path $Parent -Name $mic.instance.Replace('\', '%5C') -ItemType "registration" -Value ("Server=$($mic.instance) ; integrated security=true");
				}
			}
			else {
				New-Item -Path $Parent -Name $instance.Replace('\', '%5C') -ItemType "registration" -Value ("Server=$instance ; integrated security=true");
			}
		}
		else {
			New-Item -Path $Parent -Name $instance.Replace('\', '%5C') -ItemType "registration" -Value ("Server=$instance ; integrated security=true");
		}
	}
	Write-Host "Done"
}

function Show-SQLServiceHealth {
	<#
.SYNOPSIS
	Check if sql services are running on all instances in CMS.

.DESCRIPTION
	Check if sql services are running on all instances in CMS.

.NOTES     
    Name: Show-SQLServiceHealth
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		10/02/2017	CD		Created

    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER NotRunning
	Only display services that are not running to reduce output

.EXAMPLE
	Show-SQLServiceHealth
	Shows service status of all servers for the current environment

.EXAMPLE
	Show-SQLServiceHealth -NotRunning
	Shows services that are currently stopped

#>
	[CmdletBinding()]
	Param (
		# list services not running only
		[switch]$NotRunning
	)
	$servers = Get-CMSHosts
	$servercount = $servers.Count
	write-host "Server count $servercount"
	foreach ($server in $servers) {
		$i += 1 # used for calculating progress %
		$sqlservices = Get-WmiObject -Class Win32_Service -Filter "Name LIKE 'MSSQL`$%' OR Name LIKE 'SQLAG%' OR Name='MSSQLSERVER' OR Name='SQLSERVERAGENT' OR Name='SQLBrowser'" -ComputerName $server.host_name
	
		# filter services to only those not running if flags set
		if ($NotRunning -or $StartServices) {
			$sqlservices = $sqlservices | Where-Object { $_.state -ne "Running" }
			$pc = [math]::Round(($i / $servercount) * 100, 0)
			Write-Progress -Activity "Working..." -PercentComplete $pc -CurrentOperation "$pc% complete" -Status "Please wait."
		}
	
		if ($sqlservices) { 
			Write-Host $server.host_name -ForegroundColor Cyan
			foreach ($svc in $sqlservices) {
				<# disabled for now 
				# Only attempt to start services in Automatic mode
				if ($StartServices -and $svc.StartMode -eq "Auto")
				{
					Write-Host ("").PadRight(10), $svc.Name.PadRight(30), "($($svc.StartMode.Substring(0,1)))" -NoNewline
					Write-Host "Starting... " -ForegroundColor Yellow -NoNewline
					try
					{
						Set-Service $svc.Name -ComputerName $server.host_name -Status "Running" -ErrorAction Stop
						Write-Host "Running" -ForegroundColor Green
					}
					catch
					{
						Write-Host "Failed.`n$_" -ForegroundColor Red
					}
				} 
				#>
				
				# print state
				
				Write-Host ("").PadRight(10), $svc.Name.PadRight(30), "($($svc.StartMode.Substring(0,1)))" -NoNewline
				if ($svc.state -ne "Running") {
					Write-Host $svc.state -ForegroundColor Red
				}
				else {
					Write-Host $svc.state -ForegroundColor Green
				}
				
			}
			Write-Host ""
		}
	}
}

function Invoke-SafeAGFailover {
	<#
.SYNOPSIS
	Failover an AG whether in synchronous or asynchronous mode

.DESCRIPTION
	Failover an AG whether in synchronous or asynchronous mode
	Use -Verbose to get detailed step information
	Supports updating a DataTable with status information

.NOTES     
    Name: Invoke-SafeAGFailover
    Author: Chris Dobson
    DateCreated: 2017-03-24     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		24/03/2017	CD		Created
	2		31/03/2017	CD		Added log reuse wait check before starting failover
	3		05/04/2017	CD		Changed import module failoverclusters to use ImportModuleTS.
								Some of the tests will not fail the script if failover steps have begun.
								Added step number and info - in the case of mid failover failure the user will get info on what the last successful step was
	4		02/05/2017	CD		Silenced warnings due to bug in SqlPS communicating with different versions. The methods still work but were producing many warnings.
	5		01/06/2017	CD		A few minor bug fixes following first production mass failover test.

    To Do:   
	Parallelism bugs remain due to SMO calls to Get-ChildItem, Test-SqlAvailabilityReplica.
	For 100% thread safe commands Invoke-SqlQuery can replace the 'Detect and check AG environment' section and all of the Test-SqlAvailabilityReplica calls.


.PARAMETER PrimaryInstance
	Specify the primary instance of the AG to fail over

.PARAMETER UpdateDT
	Specify the DataTable where status updates can be written
	The DataTable must have an instance column with a row containing the $PrimaryInstance
	It must also have a Status column

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>

	[CmdletBinding()]
	Param (
		# Primary instance name, FQDN
		[Parameter(Mandatory = $true)]
		[ValidateScript( { $_.ToLower().Contains($env:userdnsdomain.ToLower()) })]
		[string]$PrimaryInstance,
		[System.Data.DataTable]$UpdateDT
	)
	try {
		ImportModuleTS failoverclusters
	} 
	catch { 
		# failovercluster module must be installed to set node weight
		Write-Host "Failed to load failoverclusters module. From an Administrator powershell prompt run:" -ForegroundColor Red
		Write-Host "Install-WindowsFeature -Name RSAT-Clustering-PowerShell -IncludeManagementTools" -BackgroundColor Black
		return
	}
	Function Out-Message {
		param($Message, [switch]$NoVerbose)
		if ($UpdateDT) { 
			# Sync threads with a mutex since a DataTable is not threadsafe
			$Mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList $false, "Global\UpdateDTMutex"
			$Mutex.WaitOne() | Out-Null

			### Mutex Protected ###
			$UpdateDT | ? { $_.instance -eq $PrimaryInstance } | % { $_.Status = $Message } 
			### /Mutex Protected ###

			$Mutex.ReleaseMutex() | Out-Null
		}
		if (!$NoVerbose) { Write-Verbose $message }
	}
	Function Write-Status {
		param($message, $ForegroundColor = "White")
		$Mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList $false, "Global\WriteHostMsg"
		$Mutex.WaitOne() | Out-Null

		### Mutex Protected ###
		Write-Host (Get-Date -Format "HH:mm:ss.fff:"), $message -ForegroundColor $ForegroundColor
		### /Mutex Protected ###

		$Mutex.ReleaseMutex() | Out-Null
	}
	try {
		$ErrorActionPreference = "Stop"
		$WarningPreference = "SilentlyContinue"
		# Detect and check AG environment
		$pi = "SQLSERVER:\Sql\$PrimaryInstance"
		$pi_non_fqdn = $PrimaryInstance -Replace ".$env:userdnsdomain", ''
		if (!(Test-Path $pi)) { throw("Invalid sql instance $PrimaryInstance") }
		$ag = Get-ChildItem "$pi\AvailabilityGroups" -ErrorAction Continue
		if (!$ag) { throw("AG not found on $PrimaryInstance") }
		if ($ag.PrimaryReplicaServerName -ne $pi_non_fqdn) { throw("$PrimaryInstance is not the Primary") }
		$replicas = Get-ChildItem "$pi\AvailabilityGroups\$($ag.Name)\AvailabilityReplicas"
		while (!(Test-SqlAvailabilityReplica -InputObject $replicas -Verbose:$false -Debug:$false -ErrorAction Continue)) { Wait-Event -Timeout 1 } # refresh replica info
		$pr = $replicas | ? { $_.Role -eq "Primary" }
		$sr = $replicas | ? { $_.Role -eq "Secondary" }
		if ($pr.RollupSynchronizationState -ne "Synchronized") { throw("Primary not in Synchronized state: $($pr.RollupSynchronizationState)") }
		if ($sr.RollupSynchronizationState -ne "Synchronized" -and $sr.RollupSynchronizationState -ne "Synchronizing") { throw("Secondary not in Synchronized state: $($sr.RollupSynchronizationState)") }
		if ($pr.Name.Contains("\")) { $phost = "{0}.{1}" -f $pr.Name.Split("\")[0], $env:userdnsdomain } else { $phost = "{0}.{1}" -f $pr.Name, $env:userdnsdomain }
		if ($sr.Name.Contains("\")) { $shost = "{0}.{1}" -f $sr.Name.Split("\")[0], $env:userdnsdomain } else { $shost = "{0}.{1}" -f $sr.Name, $env:userdnsdomain }
		if ($sr.Name.Contains("\")) { $si = "SQLSERVER:\Sql\{0}\{1}" -f $shost, $sr.Name.Split("\")[1] } else { $si = $shost }
		if ($sr.Name.Contains("\")) { $SecondaryInstance = "{0}\{1}" -f $shost, $sr.Name.Split("\")[1] } else { $SecondaryInstance = $shost }
		$OriginalAMode = $pr.AvailabilityMode
		
		Out-Message "Starting failover from $PrimaryInstance to $SecondaryInstance"
		Write-Status "Starting failover from $PrimaryInstance to $SecondaryInstance"
		Write-Verbose "Primary: $pr"
		Write-Verbose "Secondary: $sr"
		Write-Verbose "AvailabilityMode: $OriginalAMode"

		Out-Message "Starting AlwaysOn_health XE"
		$xesql = "IF NOT EXISTS(select * from sys.dm_xe_sessions WHERE name='AlwaysOn_health')
				ALTER EVENT SESSION [AlwaysOn_health]
					ON SERVER
					STATE=START"
		Invoke-SqlQuery -ServerInstance $PrimaryInstance -Query $xesql | Out-Null
		$DangerZone = $true #set a flag that changes have been applied to the AG
		
		# Set to Synchronous Commit for safe failover
		if ($pr.AvailabilityMode -ne "SynchronousCommit") {
			Out-Message "Setting $pr.Name to SynchronousCommit"
			Set-SqlAvailabilityReplica -InputObject $pr -AvailabilityMode "SynchronousCommit" | Out-Null
		}
		if ($sr.AvailabilityMode -ne "SynchronousCommit") {
			Out-Message "Setting $sr.Name to SynchronousCommit"
			Set-SqlAvailabilityReplica -InputObject $sr -AvailabilityMode "SynchronousCommit" | Out-Null
		}
		$LastStepMsg = "(1/5) Set to Synchronous Commit for safe failover"
		
		# Ensure synchronization before failover
		Out-Message "Waiting for synchronization..."
		while (Get-ChildItem "$pi\AvailabilityGroups\$($ag.Name)\AvailabilityReplicas" | ? { $_.RollupSynchronizationState -ne "Synchronized" }) {
			Wait-Event -Timeout 1; 
			Test-SqlAvailabilityReplica -InputObject $replicas -Verbose:$false -Debug:$false -ErrorAction Continue | Out-Null 
		}
		
		# Check log reuse waits before failover
		$lrwquery = "select d.name, d.log_reuse_wait_desc from sys.databases d where d.replica_id is not null and d.log_reuse_wait_desc not in ('nothing', 'log_backup')"
		While (($lrw = Invoke-SqlQuery -ServerInstance $PrimaryInstance -Query $lrwquery).Count) {
			$lrwmsg = "Waiting for log reuse waits... "
			$lrw | % { $lrwmsg += "($($_.name): $($_.log_reuse_wait_desc)) " }
			Out-Message $lrwmsg
			Wait-Event -Timeout 1
		}

		Out-Message "Setting node weight to 1 for $shost"
		(Get-ClusterNode -Cluster $shost -Name $shost).NodeWeight = 1
		$LastStepMsg = "(2/5) Set node weight pre failover"
		
		Out-Message "Failing over to $sr"
		Switch-SqlAvailabilityGroup -Path "$si\AvailabilityGroups\$($ag.Name)"
		$LastStepMsg = "(3/5) Failover"

		# switch command objects to new primary
		$replicas = Get-ChildItem "$si\AvailabilityGroups\$($ag.Name)\AvailabilityReplicas"
		$pr = $replicas | ? { $_.Role -eq "Primary" }
		$sr = $replicas | ? { $_.Role -eq "Secondary" }
		
		Out-Message "Waiting for post failover synchronization..."
		Test-SqlAvailabilityReplica -InputObject $replicas -Verbose:$false -Debug:$false -ErrorAction Continue | Out-Null
		while (Get-ChildItem "$si\AvailabilityGroups\$($ag.Name)\AvailabilityReplicas" | ? { $_.RollupSynchronizationState -ne "Synchronized" }) {
			try {
				# Display top 1 database not in healthy state, query secondary first
				$Sync_query = "select top 1 d.name as database_name, rs.synchronization_state_desc, ISNULL((SELECT CAST(AVG(percent_complete) as numeric(6,1)) FROM sys.dm_exec_requests where percent_complete>0 and last_wait_type='HADR_DB_COMMAND'),-1) percent_complete
					from sys.dm_hadr_database_replica_states rs with (nolock) join sys.databases d on rs.database_id=d.database_id 
					WHERE rs.synchronization_health_desc!='healthy' AND rs.synchronization_state_desc!='SYNCHRONIZING'" 
				$rs_state2 = Invoke-SqlQuery -ServerInstance $PrimaryInstance -Query "$Sync_query AND rs.synchronization_state_desc!='NOT SYNCHRONIZING'" -Timeout 300
				if ($rs_state2.Count) {
					$pc_complete = $null
					if ($rs_state2.percent_complete -ge 0) { $pc_complete = "($($rs_state2.percent_complete)%)" }
					Out-Message "Waiting for post failover synchronization... $($rs_state2.database_name): $($rs_state2.synchronization_state_desc) $pc_complete" -NoVerbose 
				}
				else {
					$rs_state1 = Invoke-SqlQuery -ServerInstance $SecondaryInstance -Query $Sync_query -Timeout 300
					if ($rs_state1.Count) { Out-Message "Waiting for post failover synchronization... $($rs_state1.database_name): $($rs_state1.synchronization_state_desc)" -NoVerbose }
				}
			}
			catch { Write-Host $_ -ForegroundColor Red }
			Wait-Event -Timeout 1
			Test-SqlAvailabilityReplica -InputObject $replicas -Verbose:$false -Debug:$false -ErrorAction Continue | Out-Null
		}

		# Reset availability mode to original state
		if ($OriginalAMode -ne "SynchronousCommit") {
			Out-Message "Set $sr to $OriginalAMode"
			Set-SqlAvailabilityReplica -InputObject $sr -AvailabilityMode $OriginalAMode | Out-Null
			Out-Message "Set $pr to $OriginalAMode"
			Set-SqlAvailabilityReplica -InputObject $pr -AvailabilityMode $OriginalAMode | Out-Null
			$LastStepMsg = "(4/5) Set to Asynchronous Commit post failover"
		}

		# Reverse node weight
		Out-Message "Setting node weight to 0 for $phost"
		(Get-ClusterNode -Cluster $phost -Name $phost).NodeWeight = 0
		$LastStepMsg = "(5/5) Set node weight post failover"
		$DangerZone = $false

		Out-Message "Complete"
		Write-Status "Successful failover to $SecondaryInstance" -ForegroundColor Green
	}
	catch {
		if ($DangerZone) {
			$WarningPreference = "Continue"
			Write-Warning "$PrimaryInstance failover partially complete - manual remediation required. Last step to run was $LastStepMsg"
		}
		
		Out-Message "ERROR $_"
		throw($_)
	}

}

Function Show-InstanceMsgForm {
	<#
.SYNOPSIS
	Creates a dynamically updatable data form to display status messages for multiple instances

.DESCRIPTION
	Creates a dynamically updatable data form to display status messages for multiple instances

	The form uses a DataGridView object syncronised with a DataTable to allow multiple process to update the DT on screen.

	The function returns the DataTable, Job, and PSScript objects which must be disposed once complete.

.NOTES     
    Name: Show-InstanceMsgForm
    Author: Chris Dobson
    DateCreated: 2017-03-24     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		24/03/2017	CD		Created

    To Do:   

.PARAMETER Title
	Title for the form window

.EXAMPLE
	$Status = Show-InstanceMsgForm "Query Status"
	$Status.dt.Rows.Add("Server1","Starting Status msg")
	...
	$result = $Status.ps.EndInvoke($Status.job)

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	param(
		[string]$Title,
		[switch]$AddExMenu
	)
	$dt = New-Object System.Data.DataTable
	$dt.ExtendedProperties | Add-Member EventStart (Get-Date)
	$dt.Columns.Add("Instance", [string]) | Out-Null
	$dt.Columns.Add("Status", [string]) | Out-Null
	$newPowerShell = [PowerShell]::Create().AddScript( {
			param($dt, $Title, $AddExMenu)
			Add-Type -AssemblyName System.Windows.Forms
			Import-Module DETDBA
			Import-Module SQLPS
			$ExEventWindows = @() # keep track of event windows here
			function Event_MenuClick {
				$e = $_
				$instance = $dt.Rows[$this.CurrentMouseOverRow].instance
				<#if ($script:ExEventWindow) {[System.Windows.Forms.MessageBox]::Show("Only 1 at a time!" , "My Dialog Box")}
			else 
			{
				$script:ExEventWindow = Show-ExtendedEvents $instance "AlwaysOn_health" $dt.ExtendedProperties.EventStart
				$script:ExEventWindow.winform.Add_Closed({Form_Closed})
			}#>
				#$script:ExEventWindows += Show-ExtendedEvents $instance "AlwaysOn_health" $dt.ExtendedProperties.EventStart
				$process = "powershell.exe"
				$p_args = "Show-ExtendedEvents $instance AlwaysOn_health {0}" -f (Get-Date $dt.ExtendedProperties.EventStart -Format "yyyy-MM-ddTHH:mm:ss")
				Start-Process $process $p_args -NoNewWindow
			}
			function Event_MouseClick {
				$e = $_
				if ($e.Button -eq "Right") {
					$m = New-Object System.Windows.Forms.ContextMenu
			
					$currentMouseOverRow = $dataGridView.HitTest($e.X, $e.Y).RowIndex;
					if ($currentMouseOverRow -ge 0) {
						$mi = New-Object System.Windows.Forms.MenuItem "Get ExtendedEvents"
						$mi | Add-Member currentMouseOverRow $currentMouseOverRow
						$mi.Add_Click( { Event_MenuClick })
						$m.MenuItems.Add($mi);
					}
					$m.Show($dataGridView, (New-Object System.Drawing.Point($e.X, $e.Y)));
				}
			}
			function Form_Closed {
				$e = $_
				$script:ExEventWindow.Dispose()
				$script:ExEventWindow = $null
			}
			$form = New-Object System.Windows.Forms.Form
			$form.Text = $Title
			$Icon = [system.drawing.icon]::ExtractAssociatedIcon($PSHOME + "\powershell.exe")
			$Form.Icon = $Icon
			$form.Size = New-Object System.Drawing.Size(1024, 768)
			$form.AutoScroll = $true;
			$dataGridView = New-Object System.Windows.Forms.DataGridView
			$dataGridView.Anchor
			$dataGridView.AutoSize = $true
			$dataGridView.Dock = "Fill"
			$dataGridView.AllowUserToAddRows = $false
			$dataGridView.AllowUserToDeleteRows = $false
			$dataGridView.ReadOnly = $true
			$form.Controls.Add($dataGridView) 
			$bs = New-Object System.Windows.Forms.BindingSource
			$bs.DataSource = $dt
			$dataGridView.DataSource = $bs
			$dataGridView.Columns[0].Width = 300
			$dataGridView.Columns[1].Width = $form.Size.Width - 360
			if ($AddExMenu) { $dataGridView.Add_MouseClick( { Event_MouseClick }) }
			$form.ShowDialog()
			foreach ($w in $ExEventWindows) { 
				$w.Dispose() # clean up any extended event windows
			}
		})
	$Runspace = [runspacefactory]::CreateRunspace()
	$newPowerShell.Runspace = $Runspace
	$Runspace.Open()
	$newPowerShell.AddArgument($dt) | Out-Null
	$newPowerShell.AddArgument($Title) | Out-Null
	$newPowerShell.AddArgument($AddExMenu) | Out-Null
	$job = $newPowerShell.BeginInvoke()
	$returnobj = New-Object psobject -Property @{dt = $dt; job = $job; ps = $newPowerShell }
	$returnobj | Add-Member -MemberType ScriptMethod Dispose -Value {
		while (!$this.job.IsCompleted) { Wait-Event -Timeout 1; if (!$formmsg) { $formmsg = $true; Write-Host "Waiting for status window" -ForegroundColor Yellow; } }
		$this.ps.EndInvoke($this.job)
	}
	return ($returnobj)
}


Function Show-ExtendedEvents {
	<#
.SYNOPSIS
	Shows extended events for a given server in popup window

.DESCRIPTION
	Shows extended events for a given server in popup window

	The extended events are polled and loaded every 10 seconds (there may be a small freeze of the window pane during this load)

.NOTES     
    Name: Show-ExtendedEvents
    Author: Chris Dobson
    DateCreated: 2017-03-29     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		29/03/2017	CD		Created
	2		05/04/2017	CD		Backround thread updates were causing the window to freeze, implemented alternative BackgroundWorker thread processing.

    To Do:   
	Only really tested/supports AlwaysOn_health, other extended event types could fail

.PARAMETER Instance
	Instance to retrieve the events

.PARAMETER ExName
	Extended event name to retrieve

.PARAMETER StartTime
	By default, Start time will be 00:00 on the current day

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	param(
		[Parameter(Mandatory = $true)]
		[string]$Instance,
		[Parameter(Mandatory = $true)]
		[string]$ExName,
		$StartTime
	)
	Add-Type -AssemblyName System.Windows.Forms
	if ($ExName -ne "AlwaysOn_health") { write-warning "Only AlwaysOn_health is supported"; }
	if ($StartTime) { $st = Get-Date $StartTime -Format "yyyy-MM-ddTHH:mm:ss" } else { $st = Get-Date -Format "yyyy-MM-dd" }
	$XeQuery = "DECLARE @xelfile VARCHAR(300)
				;WITH EventInfo AS (
				select CAST(st.target_data as XML) target_data FROM sys.dm_xe_session_targets st
				INNER JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
				where s.name='$ExName'
				)
				select @xelfile=c.value('@name','varchar(max)')  FROM EventInfo
				CROSS APPLY target_data.nodes ('//EventFileTarget/File') AS X(c)
				
				;WITH Data AS (
					select cast(event_data as xml) AS TargetData, object_name from sys.fn_xe_file_target_read_file (@xelfile, null, null, null)  
				)
				SELECT DISTINCT
					convert(datetime,switchoffset(convert(datetimeoffset,c.value('@timestamp', 'datetime')),datename(TzOffset,sysdatetimeoffset()))) as timestamp
					,'ERROR '+c.value('(data[@name=''error_number'']/value)[1]', 'varchar(max)')+': '+c.value('(data[@name=''message'']/value)[1]', 'varchar(max)') as [message]
				FROM Data d 
					CROSS APPLY TargetData.nodes ('//event') AS X(c)
				WHERE object_name='error_reported' AND convert(datetime,switchoffset(convert(datetimeoffset,c.value('@timestamp', 'datetime')),datename(TzOffset,sysdatetimeoffset()))) >'$st'
				UNION
				SELECT DISTINCT
					convert(datetime,switchoffset(convert(datetimeoffset,c.value('@timestamp', 'datetime')),datename(TzOffset,sysdatetimeoffset()))) as timestamp
					,c.value('(data[@name=''statement'']/value)[1]', 'varchar(max)') as [message]
				FROM Data d 
					CROSS APPLY TargetData.nodes ('//event') AS X(c)
				WHERE object_name='alwayson_ddl_executed' AND convert(datetime,switchoffset(convert(datetimeoffset,c.value('@timestamp', 'datetime')),datename(TzOffset,sysdatetimeoffset()))) >'$st'
				UNION
				SELECT DISTINCT
					convert(datetime,switchoffset(convert(datetimeoffset,c.value('@timestamp', 'datetime')),datename(TzOffset,sysdatetimeoffset()))) as timestamp
					,'STATE CHANGE FROM '+ c.value('(data[@name=''previous_state'']/text)[1]', 'varchar(max)') + ' TO ' + c.value('(data[@name=''current_state'']/text)[1]', 'varchar(max)') as [message]
				FROM Data d 
					CROSS APPLY TargetData.nodes ('//event') AS X(c)
				WHERE object_name='availability_replica_state_change' AND convert(datetime,switchoffset(convert(datetimeoffset,c.value('@timestamp', 'datetime')),datename(TzOffset,sysdatetimeoffset()))) >'$st'
				ORDER BY timestamp"
	
	$dt = Invoke-SqlQuery -ServerInstance $Instance -Query $XeQuery -AsDt
	$dt.PrimaryKey = $dt.Columns[0], $dt.Columns[1]
	$dataGridView = New-Object System.Windows.Forms.DataGridView
	$form = New-Object System.Windows.Forms.Form
	$Title = "$ExName : $Instance"
	Add-Type -AssemblyName System.Windows.Forms
	Import-Module DETDBA
	Import-Module SQLPS
	$form.Text = $Title
	$Icon = [system.drawing.icon]::ExtractAssociatedIcon($PSHOME + "\powershell.exe")
	$Form.Icon = $Icon
	$form.Size = New-Object System.Drawing.Size(800, 500)
	$form.AutoScroll = $true;
	$dataGridView.AutoSize = $true
	$dataGridView.Dock = "Fill"
	$dataGridView.AllowUserToAddRows = $false
	$dataGridView.AllowUserToDeleteRows = $false
	$dataGridView.ReadOnly = $true
	[void]$form.Controls.Add($dataGridView) 
	$bs = New-Object System.Windows.Forms.BindingSource
	$bs.DataSource = $dt
	$dataGridView.DataSource = $bs
	$dataGridView.Columns[0].Width = 110
	$dataGridView.Columns[0].DefaultCellStyle.Format = "yyyy-MM-dd HH:mm:ss";
	$dataGridView.Columns[1].Width = $form.Size.Width - 190
	Wait-Event -Timeout 0.5
	if ($dataGridView.RowCount -ge 5) { $dataGridView.FirstDisplayedScrollingRowIndex = $dataGridView.RowCount - 1 }
	
	$bw = New-Object System.ComponentModel.BackgroundWorker
	$timer = New-Object System.Windows.Forms.Timer
	$timer.Interval = 10000
	$timer.add_Tick( { $bw.RunWorkerAsync() })

	$bw | Add-Member Instance $Instance
	$bw | Add-Member XeQuery $XeQuery
	$bw | Add-Member Dt $dt
	$bw | Add-Member DtResult $null
	$bw | Add-Member dataGridView $dataGridView
	$bw | Add-Member Timer $timer
	
	Register-ObjectEvent -InputObject $bw -EventName DoWork -Action {
		param($sender, $e)
		Write-Verbose "Getting Data"
		$sender.Timer.Enabled = $false
		$sender.DtResult = Invoke-SqlQuery -ServerInstance $sender.Instance -Query $sender.XeQuery -AsDt
	} | Out-Null
	
	$bw.Add_RunWorkerCompleted( {
			param($sender, $e)
			Write-Verbose "Data work completed"
			if ($sender.DtResult) {
				if ($sender.DtResult.Rows.Count -gt $sender.Dt.Rows.Count) {
					$sender.Dt.Merge($sender.DtResult)
					if ($sender.dataGridView.RowCount -ge 5) { $sender.dataGridView.FirstDisplayedScrollingRowIndex = $sender.dataGridView.RowCount - 1 }
				}
				$sender.DtResult = $null
			}
			$sender.Timer.Enabled = $true
		})
	
	[void]$timer.Start()
	[void]$form.ShowDialog()
}

function Wait-Confirm {
	<#
.SYNOPSIS
	Simple Yes/No native powershell confirmation

.DESCRIPTION
	Simple Yes/No native powershell confirmation
	
	Returns $true for yes, $false for no

.NOTES     
    Name: Wait-Confirm
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		20/03/2017	CD		Created

    To Do:   

.PARAMETER message
	Confirmation message prompt to user

.EXAMPLE
	$result = Wait-Confirm "Would you like to continue?"

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	param($message)
	$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes"
	$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No"
	$options = [System.Management.Automation.Host.ChoiceDescription[]]($no, $yes)
	[bool]$host.ui.PromptForChoice($null, $message, $options, 0) 
}

function Invoke-SafeForEachAGFailover {
	<#
.SYNOPSIS
	Failover multiple AGs, status output displayed in separate window

.DESCRIPTION
	Failover multiple AGs, status output displayed in separate window

	Server list is taken as a pasted input

.NOTES     
    Name: Invoke-SafeForEachAGFailover
    Author: Chris Dobson
    DateCreated: 2017-03-24   
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		24/03/2017	CD		Created
	2		06/03/2017	CD		Added test for transaction log usage, added log threshold parameter. Added filter to remove all whitespace from host input.
	3		13/04/2017	CD		Added module checks for failoverclusters and SqlPs
	4		30/05/2017	CD		Changed $Instances to be a string array not an object list for compatibility with Invoke-ForEachInstance

    To Do:   

.PARAMETER Force
	Forces the AG failover to continue

.EXAMPLE
	Invoke-SafeForEachAGFailover
	Paste list of primary AG instances:
	ucvdbsql001.devdetnsw.win\ag_2012_tst1

	Received 1 instances
	Validating AG instances...OK
	*******************************************
	*************** AG failover ***************
	Ready to commence failver for 1 AGs
	*******************************************
	Are you sure you want to continue?
	[N] No  [Y] Yes  [?] Help (default is "N"):n

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	param([switch]$Force, [int]$LogThreshold = 100)

	if (!(Get-Module failoverclusters -ListAvailable)) { Write-Host "Missing failoverclusters module" -ForegroundColor Red ; return; }
	if (!(Get-Module SqlPs -ListAvailable)) { Write-Host "Missing SqlPs module (SQL 2012+)" -ForegroundColor Red ; return; }

	$Instances = @()

	Write-Host "Paste list of primary AG instances:"
	while ($in = Read-Host) {
		$Instances += $in -replace '\s', '' # strip whitespace from string
	}

	$Instances = $Instances | ? { $_.ToLower() -replace '\s', '' } # Remove blanks 
	$Instances = $Instances | Select-Object -Unique # Remove duplicates
	$icount = $Instances.Count

	$Instances | ? { !$_.ToLower().Contains($env:userdnsdomain.ToLower()) } | % { Write-Host "$_ must be FQDN" -ForegroundColor Red; $fqdn_exit = $true; }
	if ($fqdn_exit) { return }

	Write-Host "Received $icount instances"
	if ($icount -eq 0) { return }

	Write-Host "Validating AG instances..." -NoNewline

	try {
		# Test for Primary AG, AG is in Healthy state and open transactions are not consuming more than $LogThreshold Mb of log space
		$primary_query = "IF NOT EXISTS (select 1 from sys.dm_hadr_availability_replica_states where is_local=1 and role_desc='PRIMARY') RAISERROR('Not a Primary AG',16,1)
			IF EXISTS (select 1 from sys.dm_hadr_availability_replica_states WHERE synchronization_health!=2) RAISERROR('Synchronization state is not healthy',16,1)
			DECLARE @database_transaction_log_mb_used INT
			select @database_transaction_log_mb_used=SUM(tdt.database_transaction_log_bytes_used/1024/1024)
			from sys.dm_tran_session_transactions as tst
			inner join sys.dm_tran_active_transactions as tat on tst.transaction_id = tat.transaction_id
			inner join sys.dm_tran_database_transactions as tdt on tst.transaction_id = tdt.transaction_id AND tdt.database_id>1
			inner join sys.databases d on d.database_id=tdt.database_id
			where d.replica_id IS NOT NULL
			IF @database_transaction_log_mb_used>$LogThreshold RAISERROR('Log use by open transactions exceeded threshold: %dMb',16,1,@database_transaction_log_mb_used)"
		$results = Invoke-ForEachInstance -Query $primary_query -Servers $Instances -ErrorAction Stop
		Write-Host "OK" -ForegroundColor Green
	}
	catch {
		Write-Host "Server validation failed: $_" -ForegroundColor Red
		return
	}

	Write-Host "*******************************************" -ForegroundColor Yellow -BackgroundColor Black
	Write-Host "*************** AG failover ***************" -ForegroundColor Yellow -BackgroundColor Black
	Write-Host "    Ready to commence failver for $icount AGs" -ForegroundColor Yellow -BackgroundColor Black
	Write-Host "*******************************************" -ForegroundColor Yellow -BackgroundColor Black
	if (!(Wait-Confirm "Are you sure you want to continue?")) { return }

	if (!$Force) {
		Write-Host "AG failover disabled unless you use the Force" -ForegroundColor Yellow
		return
	}

	$Status = Show-InstanceMsgForm "AG Failover Status" -AddExMenu
	$Instances | % { $Status.dt.Rows.Add($_, "Queued") | Out-Null }
	$paramobj = [pscustomobject] @{dtdisplay = $Status.dt }

	Invoke-Parallel -InputObject $Instances -runspaceTimeout 3600 -Throttle 50 -Parameter $paramobj -Verbose:$false -ScriptBlock { 
		$server = $_
		try {
			Invoke-SafeAGFailover -PrimaryInstance $server -UpdateDT $parameter.dtdisplay
		} 
		catch {
			Write-Host (Get-Date -Format "HH:mm:ss.fff:"), "Failover FAILED for $server`n$_" -ForegroundColor Red
		}
	}
	$result = $Status.Dispose() # Very important to dispose the PS threads, otherwise memory will leak
}

function New-RemedyIncident {
	<#
.SYNOPSIS
	Creates Remedy incident using web services

.DESCRIPTION
	Creates Remedy incident using web services

	https://servicemanagement.det.nsw.edu.au/arsys/WSDL/public/servicemanagementars-as/HPD_IncidentInterface_Create_WS

	Credentials to access web services in KeyPass -> Application -> Remedy
	Credentials will be stored in the user's profile if connection is successful

.NOTES     
    Name: New-RemedyIncident
    Author: Chris Dobson
    DateCreated: 2017-03-20     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		10/04/2017	CD		Created
	2		19/04/2017	CD		Now using Get-SavedCredential to retrieve credentials

    To Do:   
	Add target Group types
	Add support for work info
	Add support for attachments

.PARAMETER Summary
	Appears in Summary on the Help Desk form

.PARAMETER Notes
	Appears in the Notes on the Help Desk form

.PARAMETER AssignedGroup
	The group the incident will be assigned to

.PARAMETER ImpactType
	The impact of the incident

.PARAMETER Urgency
	The urgency of the incident

.PARAMETER UpdateCredential
	Specify UpdateCredential if the remedy credentials have been saved and need to be updated

.EXAMPLE
	New-RemedyIncident -Summary "Perfmon Query" -Notes "Collect perfmon stats on host ucvdbsql001"

	This will create a new incident and assign default values:
		AssignedGroup="SQL"
		ImpactType="3ModerateLimited"
		Urgency="3Medium"

.EXAMPLE
	New-RemedyIncident -Summary "Increase E:" -Notes "Increase E: to 500Gb on host ucvdbsql001" -AssignedGroup WaCT -ImpactType 4MinorLocalized -Urgency 2High

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	param
	(
		[Parameter(Mandatory = $true)] [string]$Summary,
		[Parameter(Mandatory = $true)] [string]$Notes,
		[ValidateSet("SQL", "WaCT", "Network", "Backup", "VMWare")] [string]$AssignedGroup = "SQL",
		[ValidateSet("1ExtensiveWidespread", "2SignificantLarge", "3ModerateLimited", "4MinorLocalized")] [string]$ImpactType = "3ModerateLimited",
		[ValidateSet("1Critical", "2High", "3Medium", "4Low")] [string]$Urgency = "3Medium",
		[switch]$UpdateCredential
	)
	function New-ObjectFromProxy {
		param($proxy, $proxyAttributeName, $typeName)
		# Locate the assembly for $proxy
		$attribute = $proxy | gm | where { $_.Name -eq $proxyAttributeName }
		$str = "`$assembly = [" + $attribute.TypeName + "].assembly"
		invoke-expression $str
		# Instantiate an AuthenticationHeaderValue object
		$type = $assembly.getTypes() | where { $_.Name -eq $typeName }
		return $assembly.CreateInstance($type)
	}
	if ($Verbose) { $VerbosePreference = "Continue" }

	try {
		# Get saved remedy credentails from file, or prompt user
		$RemedyCred = Get-SavedCredential "remedy" -UpdateCredential:$UpdateCredential -DefaultUsername "svcsqlremedyuser"
		$UserName = $RemedyCred.UserName
		$Password = $RemedyCred.GetPlainPassword()
		if (!$UserName -or !$Password) { throw("Failed to get Remedy credentials") }
	}
 catch {
		throw("Failed to get Remedy credentials")
		return
	}

	switch ($AssignedGroup) {
		"SQL" { $Assigned_Group = "Enterprise Database SQL"; $PC_Tier_1 = "Applications"; $PC_Tier_2 = "Desktop Application"; $PC_Tier_3 = "n/a"; $Product_Name = "MS SQL Server" }
		"WaCT" { $Assigned_Group = "WaCT Enterprise Windows Support"; $PC_Tier_1 = "Operating System/Platform"; $PC_Tier_2 = "Operating Systems"; $PC_Tier_3 = "n/a"; $Product_Name = "Windows" }
		"Network" { $Assigned_Group = "Network Support"; $PC_Tier_1 = "Networking"; $PC_Tier_2 = "Security Components"; $PC_Tier_3 = "n/a"; $Product_Name = "Firewall" }
		"Backup" { $Assigned_Group = "SaC - Backup"; $PC_Tier_1 = "Applications"; $PC_Tier_2 = "Online Application"; $PC_Tier_3 = "n/a"; $Product_Name = "Symantic Netbackup" }
		"VMWare" { $Assigned_Group = "SaC - Virtualisation"; $PC_Tier_1 = "Operating System/Platform"; $PC_Tier_2 = "Operating Systems"; $PC_Tier_3 = "n/a"; $Product_Name = "VMware" }
	}
	try {
		$RemedyURI = "https://$RemedyServer/arsys/WSDL/public/servicemanagementars-as"
		$svcuri = [System.Uri] "$RemedyURI/HPD_IncidentInterface_Create_WS"
		Write-Verbose "Connecting web service proxy $svcuri"
		$proxy = New-WebServiceProxy -Uri $svcuri
		$proxy.Url = $proxy.Url.Replace("http://", "https://")
		$authHeader = New-ObjectFromProxy -proxy $proxy -proxyAttributeName "AuthenticationInfoValue" -typeName "AuthenticationInfo"
		$authHeader.userName = $UserName
		$authHeader.password = $Password
		$proxy.AuthenticationInfoValue = $authHeader
		Write-Verbose "Calling web service HelpDesk_Submit_Service"
		$result = $proxy.HelpDesk_Submit_Service(
			$Assigned_Group, # Assigned_Group
			$null, # Assigned_Group_Shift_Name
			"ICT Service Management", # Assigned_Support_Company
			"ITD-IS", # Assigned_Support_Organization
			$null, # Assignee
			"Move | Add | Change", # Categorization_Tier_1
			$null, # Categorization_Tier_2
			$null, # Categorization_Tier_3
			$null, # CI_Name
			$null, # Closure_Manufacturer
			$null, # Closure_Product_Category_Tier1
			$null, # Closure_Product_Category_Tier2
			$null, # Closure_Product_Category_Tier3
			$null, # Closure_Product_Model_Version
			$null, # Closure_Product_Name
			"Corporate", # Department
			"sql", # First_Name
			"Item$ImpactType", # Impact (Item1ExtensiveWidespread,Item2SignificantLarge,Item3ModerateLimited,Item4MinorLocalized)
			"service", # Last_Name
			$null, # Lookup_Keyword
			"ICT Service Management", # Manufacturer
			$PC_Tier_1, # Product_Categorization_Tier_1
			$PC_Tier_2, # Product_Categorization_Tier_2
			$PC_Tier_3, # Product_Categorization_Tier_3
			$null, # Product_Model_Version
			$Product_Name, # Product_Name
			"DirectInput", # Reported_Source (DirectInput,Email,ExternalEscalation,Fax,SelfService,SystemsManagement,Phone,VoiceMail,WalkIn,Web,Other,BMCImpactManagerEvent)
			$null, # Resolution
			$null, # Resolution_Category_Tier_1
			$null, # Resolution_Category_Tier_2
			$null, # Resolution_Category_Tier_3
			"UserServiceRequest", # Service (UserServiceRestoration, UserServiceRequest, InfrastructureRestoration, InfrastructureEvent)
			"New", # Status (New,Assigned,InProgress,Pending,Resolved,Closed,Cancelled)
			"CREATE", # Action
			"Yes", # Create_Request
			$null, # bool Create_RequestSpecified
			$Summary, # Summary
			$notes, # Notes
			"Item$Urgency", # Urgency (Item1Critical,Item2High,Item3Medium,Item4Low)
			$null, # Work_Info_Summary
			$null, # Work_Info_Notes
			"General", # Work_Info_Type (CustomerInbound,CustomerCommunication,CustomerFollowup,CustomerStatusUpdate,CustomerOutbound,ClosureFollowUp,DetailClarification,GeneralInformation,ResolutionCommunications,SatisfactionSurvey,StatusUpdate,General,IncidentTaskAction,ProblemScript,WorkingLog,EmailSystem,PagingSystem,BMCImpactManagerUpdate,Chat)
			$null, # bool Work_Info_TypeSpecified
			(Get-Date), # datetime Work_Info_Date
			$null, # bool Work_Info_DateSpecified
			"Other", # Work_Info_Source (Email,Fax,Phone,VoiceMail,WalkIn,Pager,SystemAssignment,Web,Other,BMCImpactManagerEvent)
			$null, # bool Work_Info_SourceSpecified
			"Yes", # Work_Info_Locked
			"Internal", # Work_Info_View_Access (Internal,Public)
			$null, # Middle_Initial
			"Request", # Status_Reason (InfrastructureChangeCreated,LocalSiteActionRequired,PurchaseOrderApproval,RegistrationApproval,SupplierDelivery,SupportContactHold,ThirdPartyVendorActionReqd,ClientActionRequired,InfrastructureChange,Request,FutureEnhancement,PendingOriginalIncident,ClientHold,MonitoringIncident,CustomerFollowUpRequired,TemporaryCorrectiveAction,NoFurtherActionRequired,ResolvedbyOriginalIncident,AutomatedResolutionReported,NolongeraCausalCI)
			$null, # bool Status_ReasonSpecified
			$null, # Direct_Contact_First_Name
			$null, # Direct_Contact_Middle_Initial
			$null, # Direct_Contact_Last_Name
			$null, # TemplateID
			$null, # ServiceCI
			$null, # ServiceCI_ReconID
			$null, # HPD_CI
			$null, # HPD_CI_ReconID
			$null, # HPD_CI_FormName
			$null, # WorkInfoAttachment1Name
			$null, # byte[] WorkInfoAttachment1Data
			$null, # int WorkInfoAttachment1OrigSize
			$null, # bool WorkInfoAttachment1OrigSizeSpecified
			"sql_remsvc", # Login_ID
			"ICT Service Management", # Customer_Company
			$null 							# Corporate_ID
		)
		Write-Host "New incident created $result"
	}
 catch {
		Write-Host "Error creating incident" -ForegroundColor Red
		Throw($_)
	}
}

function Get-RemedyIncidents {
	<#
.SYNOPSIS
	Gets a list of Remedy incidents

.DESCRIPTION
	Gets a list of Remedy incidents using web services

	https://servicemanagement.det.nsw.edu.au/arsys/WSDL/public/servicemanagementars-as/HPD_IncidentInterface_WS

	Due to the returned XML not matching the XSD this has been implemented using a direct webrequest rather than using a web proxy.

	Credentials to access web services in KeyPass -> Application -> Remedy
	Credentials will be stored in the user's profile if connection is successful

.NOTES     
    Name: Get-RemedyIncidents
    Author: Chris Dobson
    DateCreated: 2017-04-12     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		12/04/2017	CD		Created
	2		13/04/2017	CD		Added default user to Get-Credential
	3		19/04/2017	CD		Added AdvancedQuery parameter to search any incident
								Now using Get-SavedCredential to retrieve credentials
	4		04/05/2017	CD		Allow multiple status' and set default to return all open tickets
								Added FormatTable parameter to return results as a table

    To Do:   

.PARAMETER FullName
	We can only search on first and last name so full name must include both. Default will be the service account name "SQL Service"

.PARAMETER Status
	Status of the incident as defined by Remedy

.PARAMETER AssignedGroup
	A short version of the Remedy field and restricted to SQL, WaCT and Network

.PARAMETER CreateDateBefore
	Only incidents before a certain date

.PARAMETER CreateDateAfter
	Only incidents after a certain date

.PARAMETER MaxLimit
	Maximum number of results to return

.PARAMETER UpdateCredential
	Prompt for and update saved credentials

.PARAMETER AdvancedQuery
	Allows for custom criteria search using any remedy field

	eg 'First Name' = "sql" AND 'Last Name' = "service" AND 'Assigned Group' = "Enterprise Database SQL"

.EXAMPLE
	Get-RemedyIncidents

	Gets incidents for the service account user, 10 results returned. User will be prompted for credentails if not stored.

.EXAMPLE
	Get-RemedyIncidents -AssignedGroup WaCT -CreateDateBefore ((Get-Date).AddDays(-3)) -MaxLimit 100

	Get incidents older than 3 days assigned to WaCT. Increase limit to 100 records returned

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>

	[CmdletBinding()] 
	param
	(
		[ValidateScript( { $_.Split(" ")[1] })]
		[string]$FullName = "SQL Service",
		[ValidateSet("New", "Assigned", "In Progress", "Pending", "Resolved", "Closed", "Cancelled")]
		[string[]]$Status = ("Assigned", "In Progress", "Pending", "Resolved"),
		[ValidateSet("SQL", "WaCT", "Network", "Backup", "VMWare")]
		[string]$AssignedGroup,
		[datetime]$CreateDateBefore,
		[datetime]$CreateDateAfter,
		[ValidateScript( { $_ -gt 0 -and $_ -le 1000 })]
		[int]$MaxLimit = 10,
		[switch]$UpdateCredential,
		[string]$AdvancedQuery,
		[switch]$FormatTable
	)
	if ($Verbose) { $VerbosePreference = "Continue" }

	try {
		# Get saved remedy credentails from file, or prompt user
		$RemedyCred = Get-SavedCredential "remedy" -UpdateCredential:$UpdateCredential -DefaultUsername "svcsqlremedyuser"
		$UserName = $RemedyCred.UserName
		$Password = $RemedyCred.GetPlainPassword()
		if (!$UserName -or !$Password) { throw("Failed to get Remedy credentials") }
	}
 catch {
		throw("Failed to get Remedy credentials")
		return
	}

	if ($AdvancedQuery) {
		$criteria = $AdvancedQuery.Replace(">", "&gt;").Replace("<", "&lt;")
	}
	else {
		# Construct criteria query
		$FirstName = $FullName.Split(" ")[0].ToLower()
		$LastName = $FullName.Split(" ")[1].ToLower()
		$criteria = "'First Name' = ""$FirstName"" AND 'Last Name' = ""$LastName"""
		if ($Status) {
			$criteria += (" AND ('Status' = ""{0}""" -f $Status[0])
			for ($i = 1; $i -lt $Status.Count; $i++) {
				$criteria += (" OR 'Status' = ""{0}""" -f $Status[$i])
			}
			$criteria += ")"
		} 

		if ($AssignedGroup) {
			switch ($AssignedGroup) {
				"SQL" { $criteria += " AND 'Assigned Group' = ""Enterprise Database SQL""" }
				"WaCT" { $criteria += " AND 'Assigned Group' = ""WaCT Enterprise Windows Support""" }
				"Network" { $criteria += " AND 'Assigned Group' = ""Network Support""" }
				"Backup" { $criteria += " AND 'Assigned Group' = ""SaC - Backup""" }
				"VMWare" { $criteria += " AND 'Assigned Group' = ""SaC - Virtualisation""" }
			}
		}
		if ($CreateDateBefore) {
			$criteria += " AND 'Submit Date' &lt;= ""{0}""" -f (Get-Date $CreateDateBefore -Format "dd/MM/yyyy HH:mm:ss")
		}
		if ($CreateDateAfter) {
			$criteria += " AND 'Submit Date' &gt;= ""{0}""" -f (Get-Date $CreateDateAfter -Format "dd/MM/yyyy HH:mm:ss")
		}
	}
	Write-Verbose "Search criteria: $criteria"
	$soapBody = "<soapenv:Envelope xmlns:soapenv=""http://schemas.xmlsoap.org/soap/envelope/"" xmlns:urn=""urn:HPD_IncidentInterface_WS"">
   <soapenv:Header>
      <urn:AuthenticationInfo>
         <urn:userName>$UserName</urn:userName>
         <urn:password>$Password</urn:password>
      </urn:AuthenticationInfo>
   </soapenv:Header>
   <soapenv:Body>
      <urn:HelpDesk_QueryList_Service>
         <urn:Qualification>$criteria</urn:Qualification>
         <urn:startRecord>0</urn:startRecord>
         <urn:maxLimit>$MaxLimit</urn:maxLimit>
      </urn:HelpDesk_QueryList_Service>
   </soapenv:Body>
</soapenv:Envelope>"
	Write-Verbose ($soapBody -replace "<urn:password>$Password</urn:password>", ("<urn:password>" + ("".PadRight($Password.Length, "*")) + "</urn:password>"))
	$soapBody = [xml]$soapBody
	try {
		Write-Verbose "Making direct web service call instead of through the proxy due to invalid XML returned!"
		$svcuri = "https://$RemedyServer/arsys/services/ARService?server=servicemanagementars-as&webService=HPD_IncidentInterface_WS"
		
		# Have to use a custom WebRequest object with headers in specific order otherwise we errors
		$soapWebRequest = [System.Net.WebRequest]::Create($svcuri)
		$soapWebRequest.Headers.Add("Accept-Encoding", "gzip,deflate")
		$soapWebRequest.ContentType = "text/xml;charset=`"utf-8`""
		$soapWebRequest.Headers.Add("SOAPAction", """urn:HPD_IncidentInterface_WS/HelpDesk_QueryList_Service""")
		$soapWebRequest.Accept = "text/xml"
		$soapWebRequest.Method = "POST"
		
		Write-Verbose "Connecting web service $svcuri"
		$requestStream = $soapWebRequest.GetRequestStream()
		$soapBody.Save($requestStream)
		$requestStream.Close()
		
		Write-Verbose "Getting response"
		$response = $soapWebRequest.GetResponse() 
		$ErrorActionPreference = "Stop"
		$responseStream = $response.GetResponseStream() 
		$soapReader = [System.IO.StreamReader]($responseStream)  
		$ReturnXml = [Xml] $soapReader.ReadToEnd() 
		$responseStream.Close()

		if ($FormatTable) {
			$ReturnXml.Envelope.Body.HelpDesk_QueryList_ServiceResponse.getListValues | Select-Object Incident_Number, Submit_Date, Status, Assignee, Summary | Format-Table -AutoSize
		}
		else { return $ReturnXml.Envelope.Body.HelpDesk_QueryList_ServiceResponse.getListValues }
	}
 catch {
		if ($_.Exception.InnerException.Response) {
			$result = $_.Exception.InnerException.Response.GetResponseStream()
			$reader = New-Object System.IO.StreamReader($result)
			$reader.BaseStream.Position = 0
			$reader.DiscardBufferedData()
			$responseBody = [xml]$reader.ReadToEnd();
			$FaultString = $responseBody.Envelope.Body.Fault.faultstring
			if ($FaultString.Contains("ERROR (302): Entry does not exist in database;")) { Write-Host "No results" }
			else { throw($FaultString) }
		}
		else { throw($_) }
	}
}

function Get-SavedCredential {
	<#
.SYNOPSIS
	Gets a credentail from encrypted user profile file

.DESCRIPTION
	Gets a credential from encrypted user profile file

	If credential file is not found, user is prompted for credentials.

	Note: Credential domain does not have to represent an AD domain, hence credentials are not validated.

.NOTES     
    Name: Get-SavedCredential
    Author: Chris Dobson
    DateCreated: 2017-04-13     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		13/04/2017	CD		Created
	2		16/05/2019	CD		Fixed bug where if user aborted credentials prompt, empty credentials were saved
	3		19/05/2017	CD		Added validation option for credentials

    To Do:   

.PARAMETER Domain
	Domain name identifier for this credential (although it doesnt actually have to be an AD domain)

.PARAMETER UpdateCredential
	Prompt for and update saved credentials

.PARAMETER DefaultMessage
	Message appearing in prompt

.PARAMETER DefaultUsername
	Fill the username with a default

.EXAMPLE
	Get-SavedCredential central

	Gets credential saved under the central domain

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	param(
		[Parameter(Mandatory = $true)] [string]$Domain,
		[switch]$UpdateCredential,
		[string]$DefaultMessage,
		[string]$DefaultUsername,
		[ValidateSet("SQL", "Domain")][string]$Validate
	)
	$DomainCredFile = "~\$Domain.cred"
	if ((get-item "~\").FullName -eq "C:\WINDOWS\system32") { $DomainCredFile = "C:\Users\$([environment]::UserName)\$Domain.cred" } # fix for service account
	if (!$DefaultMessage) { $DefaultMessage = "$Domain Credentials Required" }

	try {
		if (!(Test-Path $DomainCredFile) -or $UpdateCredential) {
			Write-Verbose "Getting credentials"
			$incred = Get-Credential -Message $DefaultMessage -UserName $DefaultUsername
			if (!$incred) { throw("Call to Get-Credential failed"); }

			# validate if requested
			if ($Validate -eq "Domain") {
				Add-Type -AssemblyName System.DirectoryServices.AccountManagement
				$DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('domain')
				try { $validation = $DS.ValidateCredentials($incred.UserName, $incred.GetNetworkCredential().Password) }
				catch { throw("Login failed for $($incred.UserName)") }
				if (!$validation) { throw("Login failed for $($incred.UserName)") }
			}
			if ($Validate -eq "SQL") {
				Invoke-SqlQuery -ServerInstance $CMSInstance -Query "select 1" -Username $incred.UserName -Password $incred.GetNetworkCredential().Password | Out-Null
			}

			# save credentials 
			if (Test-Path $DomainCredFile) { Remove-Item $DomainCredFile -Force }
			$incred.UserName + ";" + ($incred.Password | ConvertFrom-SecureString) | Out-File $DomainCredFile -Force
			Get-Item $DomainCredFile | % { $_.Attributes = "hidden" }
			Write-Verbose "$Domain credential stored securely in user profile"
		}
		else {
			Write-Verbose "Found stored $Domain credentials $DomainCredFile"
		}
		$CredFile = Get-Content $DomainCredFile
		$UserName = $CredFile.Split(";")[0]
		if (!$UserName) { if (Test-Path $DomainCredFile) { Remove-Item $DomainCredFile -Force }; throw("Username missing"); }
		$secpasswd = ConvertTo-SecureString $CredFile.Split(";")[1]
		$cred = New-Object System.Management.Automation.PSCredential ($UserName, $secpasswd)
		$cred | Add-Member -MemberType ScriptMethod GetPlainPassword { [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.Password)) }
		if ($Validate -and !$incred) {
			# validate if requested
			if ($Validate -eq "Domain") {
				Add-Type -AssemblyName System.DirectoryServices.AccountManagement
				$DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('domain')
				try { $validation = $DS.ValidateCredentials($cred.UserName, $cred.GetPlainPassword()) }
				catch { throw("Login failed for $($cred.UserName)") }
				if (!$validation) { throw("Login failed for $($cred.UserName)") }
			}
			if ($Validate -eq "SQL") {
				Invoke-SqlQuery -ServerInstance $CMSInstance -Query "select 1" -Username $cred.UserName -Password $cred.GetPlainPassword() | Out-Null
			}
		}

		return $cred
	}
 catch {
		Throw("Failed to get $Domain credentials`n$_"); 
		return
	}
}

function Test-CMSHosts {
	<#
.SYNOPSIS
	Tests CMS servers if they are online, require reboot and if the instance is up

.DESCRIPTION
	Tests CMS servers if they are online, require reboot and if the instance is up

	Only exceptions are displayed by default with a summary of all servers

.NOTES     
    Name: Test-CMSHosts
    Author: Chris Dobson
    DateCreated: 2017-04-18     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		18/04/2017	CD		Created
	2		21/04/2017	CD		Added 2 extra registry keys to check for reboot pending

    To Do:   

.PARAMETER Detailed
	Shows detailed host information, not just exceptions

.PARAMETER ClearHost
	Clears the powershell window before displaying results

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	param([switch]$Detailed, [switch]$ClearHost)
	$servers = Get-CMSHosts
	$serverarr = @() + $servers | % { $_.host_name }
	$servercount = $servers.Count
	Write-Host "Querying $servercount hosts..."
	$Starttime = Get-Date

	$results = invoke-parallel -InputObject $serverarr -Throttle 50 -Quiet -ScriptBlock { 
		$server = $_
		$serverob = new-object psobject -Property @{Server = $server; Instances = @() }
		try {
			$i = 0
			while (!($alive = Test-Connection -ComputerName $server -Count 1 -Quiet) -and $i -lt 5) { $i++; Wait-Event -Timeout 0.5 }
			if ($alive) {
				$serverob | Add-Member Online $true
				try { $Instances = Get-WmiObject win32_service -ComputerName $Server -Filter "Name LIKE 'MSSQL%'" | ? { ($_.Name -like 'MSSQL$*') -or ($_.Name -eq 'MSSQLSERVER') } | Sort-Object -Property Name } catch { throw("WMI unavailable, $_") }
				foreach ($Instance in $Instances) {
					$InstanceName = $Instance.Name.Replace("MSSQL$", "")
					if ($InstanceName -eq "MSSQLSERVER") {
						$connectToInstance = $Server
					}
					else {
						$connectToInstance = "$Server\$InstanceName"
					}
					if ($Instance.State -eq "Running") {
						try {
							$queryresult = Invoke-SqlQuery -ServerInstance $connectToInstance -Query "SELECT CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(100)) AS [Build]"
							$serverob.Instances += New-Object psobject -Property @{Instance = $InstanceName; Build = $queryresult.Build; State = $Instance.State }
						} 
						catch { $serverob.Instances += New-Object psobject -Property @{Instance = $InstanceName; State = $Instance.State; Error = $_ } }
					}
					else {
						$serverob.Instances += New-Object psobject -Property @{Instance = $InstanceName; State = $Instance.State }
					}
				}
				try {
					$RebootRequired = Test-RebootRequired $server
					$serverob | Add-Member RebootRequired $RebootRequired
				}
				catch { }
			}
			else {
				$serverob | Add-Member Online $false
			}
		}
		catch {
			$serverob | Add-Member Error $_
		}
		return $serverob
	} | Sort-Object -Property Server
	$TotalServers = $servers.Count
	$OfflineServers = $TotalServers - ($results.Online | Measure-Object -Sum).Sum
	$RebootRequired = ($results.RebootRequired | Measure-Object -Sum).Sum
	$TotalInstances = $results.Instances.Count
	$OfflineInstances = ($results.Instances | ? { !$_.Build } | Measure-Object).Count
	$Duration = ((Get-Date) - $Starttime).TotalSeconds

	if ($ClearHost) { Clear-Host }

	Write-Host ("Total Servers:".PadRight(23) + "$TotalServers".PadRight(5)) -BackgroundColor Black
	Write-Host ("Offline Servers:".PadRight(23) + "$OfflineServers".PadRight(5)) -BackgroundColor Black
	Write-Host ("Reboots Required:".PadRight(23) + "$RebootRequired".PadRight(5)) -BackgroundColor Black
	Write-Host ("Total Instances:".PadRight(23) + "$TotalInstances".PadRight(5)) -BackgroundColor Black
	Write-Host ("Offline Instances:".PadRight(23) + "$OfflineInstances".PadRight(5)) -BackgroundColor Black
	Write-Host ("Duration (sec):".PadRight(23) + ("{0:N1}" -f $Duration).PadRight(5)) -BackgroundColor Black

	foreach ($serverob in $results) {
		if ($serverob.RebootRequired) {
			Write-Host ("`n" + $serverob.Server) -ForegroundColor Cyan -NoNewline
			Write-Host " (Reboot Required)" -ForegroundColor Yellow
		}
		elseif (!$serverob.Online) {
			Write-Host ("`n" + $serverob.Server) -ForegroundColor Cyan -NoNewline
			Write-Host " (Offline)" -ForegroundColor Red
		}
		elseif ($Detailed -or ($serverob.Instances | ? { !$_.Build })) {
			Write-Host ("`n" + $serverob.Server) -ForegroundColor Cyan 
		}
		
		foreach ($Instance in $serverob.Instances) {
			if ($Instance.Build) { if ($Detailed) { Write-Host ("".PadRight(5) + ($Instance.Instance).PadRight(25) + "(" + ($Instance.Build) + ")") -ForegroundColor Green } }
			elseif ($Instance.State -eq "Running") { Write-Host ("".PadRight(5) + ($Instance.Instance).PadRight(25) + "Running") -ForegroundColor Yellow }
			else { Write-Host ("".PadRight(5) + ($Instance.Instance).PadRight(25) + ($Instance.State)) -ForegroundColor Red }
		}
	}
}

function Test-RebootRequired {
	<#
.SYNOPSIS
	Tests whether server reboot required

.DESCRIPTION
	Tests whether server reboot required

.NOTES     
    Name: Test-RebootRequired
    Author: Chris Dobson
    DateCreated: 2017-04-27     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		27/04/2017	CD		Created

    To Do:   


.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	param([Parameter(Mandatory = $true)][string]$Server)
	$Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $Server)
	$RegKey = $Reg.OpenSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate\\Auto Update")
	$rr1 = $RegKey.GetValue("RebootRequired")
	$RegKey = $Reg.OpenSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Component Based Servicing")
	$rr2 = $RegKey.GetValue("RebootRequired")
	$RegKey = $Reg.OpenSubKey("SYSTEM\\CurrentControlSet\\Control\\Session Manager")
	$rr3 = $RegKey.GetValue("PendingFileRenameOperations")
	if ($Reg.OpenSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Component Based Servicing\\RebootPending")) { $rr4 = $true }
	if ($Reg.OpenSubKey("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate\\Auto Update\\RebootRequired")) { $rr5 = $true }
	return ($rr1 -or $rr2 -or $rr3 -or $rr4 -or $rr5)
}

function Invoke-ForEachHost {
	<#
.SYNOPSIS
	Execute a scriptblock locally against all CMS hosts in parallel

.DESCRIPTION
	Execute a scriptblock locally against all CMS hosts in parallel

.NOTES     
    Name: Invoke-ForEachHost
    Author: Chris Dobson
    DateCreated: 2017-05-05     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		05/05/2017	CD		Created
	2		12/05/2017	CD		Added pipeline input for host list

    To Do:   

.EXAMPLE
	Invoke-ForEachHost -ScriptBlock {[environment]::OSVersion.Version}

	Gets the OS version from each host

.EXAMPLE
	Invoke-ForEachHost { get-WmiObject win32_logicaldisk | ?{$_.Size} | ? {(($_.FreeSpace/$_.Size)*100) -lt 20} | %{ New-Object PSObject -Property @{freepct=(($_.FreeSpace/$_.Size)*100);device=($_.DeviceID);size=($_.Size/1024/1024)}}}

	Queries hosts with disk space < 20%

	Note it is important to return multiple results from the pipeline as an object with  New-Object PSObject -Property @{value1="value";value2="value2"}
	This way the results will display with the computer name.

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	param(
		[ScriptBlock]$ScriptBlock,
		$Params,
		[Parameter(Mandatory = $false, ValueFromPipeline = $true)]
		[PSObject]$Hosts = (Get-CMSHosts).host_name
	)
	if (!(IsAdmin)) { return }
	$P_Params = New-Object PSObject -Property @{ScriptBlock = $ScriptBlock; Params = $Params }
	if ($input) {
		$Hosts = $input
	}
	if ($Hosts.host_name) {
		$Hosts = $Hosts.host_name
	}
	$Hosts | Invoke-Parallel -Throttle 50 -Parameter $P_Params -ScriptBlock {
		$server = $_
		Invoke-Command -ComputerName $server -ScriptBlock $parameter.ScriptBlock -ArgumentList $parameter.Params
	}
}

function New-ImpersonatedUser {
	<#
.SYNOPSIS
	Impersonates another user on a local machine or Active Directory.

.DESCRIPTION
	New-ImpersonateUser uses the LogonUser method from the advapi32.dll to get a token that can then be used to call the WindowsIdentity.Impersonate method in order to impersonate another user without logging off from the current session.  You can pass it either a PSCredential or each field separately. Once impersonation is done, it is highly recommended that Remove-ImpersonateUser (a function added to the global scope at runtime) be called to revert back to the original user. 

.NOTES
	Name: New-ImpersonatedUser
    Author: Chris Dobson
    DateCreated: 2017-05-05     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		05/05/2017	CD		Created from https://gallery.technet.microsoft.com/scriptcenter/Impersonate-a-User-9bfeff82

    To Do:   
	

	ORIGINAL NOTES:
	It is recommended that you read some of the documentation on MSDN or Technet regarding impersonation and its potential complications, limitations, and implications.
	Author:  Chris Carter
	Version: 1.0

.PARAMETER Credential
	The PS Credential to be used, eg. from Get-Credential

.PARAMETER Username
	The username of the user to impersonate.

.PARAMETER Domain
	The domain of the user to impersonate.  If the user is local, use the name of the local computer stored in $env:COMPUTERNAME

.PARAMETER Password
	The password of the user to impersonate.  This is in cleartext which is why sending a PSCredential is recommended.

.PARAMETER Quiet
	Using the Quiet parameter will force New-ImpersonateUser to have no outputs.

.INPUTS
	None.  You cannot pipe objects to New-ImpersonateUser

.OUTPUTS
System.String
	By default New-ImpersonateUser will output strings confirming Impersonation and a reminder to revert back.

None
	The Quiet parameter will force New-ImpersonateUser to have no outputs.

.EXAMPLE
	PS C:\> New-ImpersonateUser -Credential (Get-Credential)

	This command will impersonate the user supplied to the Get-Credential cmdlet.
.EXAMPLE
	PS C:\> New-ImpersonateUser -Username "user" -Domain "domain" -Password "password"

	This command will impersonate the user "domain\user" with the password "password."
.EXAMPLE
	PS C:\> New-ImpersonateUser -Credential (Get-Credential) -Quiet

	This command will impersonate the user supplied to the Get-Credential cmdlet, but it will not produce any outputs.

.LINK
	http://msdn.microsoft.com/en-us/library/chf6fbt4(v=vs.110).aspx (Impersonate Method)
	http://msdn.microsoft.com/en-us/library/windows/desktop/aa378184(v=vs.85).aspx (LogonUser function)  
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

#>
	[CmdletBinding(DefaultParameterSetName = "Credential")]
	Param(
		[Parameter(ParameterSetName = "Credential", Mandatory = $true, Position = 0)][PSCredential]$Credential
	)

	#Import the LogonUser Function from advapi32.dll and the CloseHandle Function from kernel32.dll
	Add-Type -Namespace Import -Name Win32 -MemberDefinition @'
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool LogonUser(string user, string domain, string password, int logonType, int logonProvider, out IntPtr token);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);
'@

	#Set Global variable to hold the Impersonation after it is created so it may be ended after script run
	$Global:ImpersonatedUser = @{ }
	#Initialize handle variable so that it exists to be referenced in the LogonUser method
	$tokenHandle = 0

	#Pass the PSCredentials to the variables to be sent to the LogonUser method
	$Username = $Credential.GetNetworkCredential().Username
	$Password = $Credential.GetNetworkCredential().Password
	$Domain = $Credential.GetNetworkCredential().Domain

	#Call LogonUser and store its success.  [ref]$tokenHandle is used to store the token "out IntPtr token" from LogonUser.
	$returnValue = [Import.Win32]::LogonUser($Username, $Domain, $Password, 2, 0, [ref]$tokenHandle)

	#If it fails, throw the verbose with the error code
	if (!$returnValue) {
		$errCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error();
		Write-Host "Impersonate-User failed a call to LogonUser with error code: $errCode"
		throw [System.ComponentModel.Win32Exception]$errCode
	}
	#Successful token stored in $tokenHandle
	else {
		#Call the Impersonate method with the returned token. An ImpersonationContext is returned and stored in the
		#Global variable so that it may be used after script run.
		$Global:ImpersonatedUser.ImpersonationContext = [System.Security.Principal.WindowsIdentity]::Impersonate($tokenHandle)
    
		#Close the handle to the token. Voided to mask the Boolean return value.
		[void][Import.Win32]::CloseHandle($tokenHandle)

		#Write the current user to ensure Impersonation worked and to remind user to revert back when finished.
		Write-Verbose ("You are now impersonating user $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)")
	}
}

Function Remove-ImpersonateUser {
	<#
.SYNOPSIS
	Used to revert back to the orginal user after New-ImpersonateUser is called. You can only call this function once; it is deleted after it runs.

.INPUTS
	None.  You cannot pipe objects to Remove-ImpersonateUser

.OUTPUTS
	None.  Remove-ImpersonateUser does not generate any output.

.NOTES
	Name: New-ImpersonatedUser
    Author: Chris Dobson
    DateCreated: 2017-05-05     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		05/05/2017	CD		Created from https://gallery.technet.microsoft.com/scriptcenter/Impersonate-a-User-9bfeff82

    To Do:   

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

#>
	[CmdletBinding()]
	param([switch]$Quiet)
	#Calling the Undo method reverts back to the original user.
	$ImpersonatedUser.ImpersonationContext.Undo()

	#Clean up the Global variable and the function itself.
	Remove-Variable ImpersonatedUser -Scope Global

	Write-Verbose "Impersonation reverted"
}

function Get-DnsCNames {
	<#
.SYNOPSIS
	Get list of defined CNames for the SQL infrastructure domain zone

.DESCRIPTION
	Get list of defined CNames for the SQL infrastructure domain zone

	A service account is required to query the DNS server which will prompt for and save credentials upon first run
	(credential file is saved in the users home directory as domain.cred - delete this file to update credentials)

	CENTRAL / DETNSW		- SQL.INFRA.NSWEDUSERVICES.COM.AU
	PREDETNSW				- SQL.PREINFRA.NSWEDUSERVICES.COM.AU
	UATDETNSW				- SQL.TSTINFRA.NSWEDUSERVICES.COM.AU
	DEVDETNSW				- SQL.DEVINFRA.NSWEDUSERVICES.COM.AU

.NOTES
	Name: Get-DnsCNames
    Author: Chris Dobson
    DateCreated: 2017-05-08     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		08/05/2017	CD		Created 
	2		23/05/2017	CD		Modified list output to fully qualified CName and hostname

    To Do:   

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

#>
	[CmdletBinding()] param()

	if (!(IsAdmin)) { return }
	if (!(Get-Module ActiveDirectory -ListAvailable)) { throw("ActiveDirectory module not installed"); return; }
	if (!(Get-Command "Get-DnsServerResourceRecord" -ErrorAction SilentlyContinue)) {
		try {
			Install-WindowsFeature RSAT-DNS-Server
		}
		catch {
			throw($_)
			return
		}
	}
	# Install-WindowsFeature RSAT-DNS-Server
	$DC = (Get-ADDomainController -Discover -NextClosestSite).HostName
	if (!$SQLDNS) { Write-Host "Missing SQL DNS variable" -ForegroundColor Red; return }
	New-ImpersonatedUser (Get-SavedCredential -Domain $SQLDNS -DefaultUsername "$CurrentDomain\srvSQLDNSadmin")
	Get-DnsServerResourceRecord -ComputerName $DC -ZoneName $SQLDNS -RRType CName | % { New-Object PSObject -Property @{CName = (($_.HostName + "." + $SQLDNS).ToLower()); HostName = $_.RecordData.HostNameAlias } }
	Remove-ImpersonateUser
}

function Add-DnsCName {
	<#
.SYNOPSIS
	Add a CName to the SQL infrastructure domain zone

.DESCRIPTION
	Add a CName to the SQL infrastructure domain zone

	A service account is required to query the DNS server which will prompt for and save credentials upon first run
	(credential file is saved in the users home directory as domain.cred - delete this file to update credentials)

	Application EventLog is written username and added CName

	CENTRAL / DETNSW		- SQL.INFRA.NSWEDUSERVICES.COM.AU
	PREDETNSW				- SQL.PREINFRA.NSWEDUSERVICES.COM.AU
	UATDETNSW				- SQL.TSTINFRA.NSWEDUSERVICES.COM.AU
	DEVDETNSW				- SQL.DEVINFRA.NSWEDUSERVICES.COM.AU

.NOTES
	Name: Add-DnsCName
    Author: Chris Dobson
    DateCreated: 2017-05-08     

    Build   Date        Author	Comments
    -----------------------------------------------------------------------------------------------
    1       08/05/2017  CD      Created 
    2       08/05/2017  CD      Added logging to event log
    3       09/10/2019  JB      Checked if DNS exists and Added 'force' parameter to over-write

    To Do:   

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER Name
	CName alias to create

.PARAMETER HostName
    Host name for the alias to direct to
    
.PARAMETER Force
    Allow the script to overwrite the existing entry

.EXAMPLE
	Add-DnsCName -Name "CONTROLPOINT" -HostName "DW0000SQLDE002.DEVDETNSW.WIN"

	Creates an alias CONTROLPOINT.SQL.DEVINFRA.NSWEDUSERVICES.COM.AU

.EXAMPLE
	Add-DnsCName -Name "CONTROLPOINT" -HostName "DW0000SQLDE002.DEVDETNSW.WIN" -Force

	Creates an alias CONTROLPOINT.SQL.DEVINFRA.NSWEDUSERVICES.COM.AU even if it already exists
#>

	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)][string]$Name,
		[Parameter(Mandatory = $true)][string]$HostName,
		[switch]$Force
	)

	if (!(IsAdmin)) { return }
	if (!(Get-Module ActiveDirectory -ListAvailable)) { throw("ActiveDirectory module not installed") }
	if (!(Get-Command "Get-DnsServerResourceRecord" -ErrorAction SilentlyContinue)) {
		try {
			Install-WindowsFeature RSAT-DNS-Server
		}
		catch {
			throw($_)
			return
		}
	}
	if (!$SQLDNS) { Write-Warning "Missing SQL DNS variable"; return }
	if (!($FQDN = (Resolve-DnsName $HostName -QuickTimeout -NoHostsFile -ErrorAction SilentlyContinue | Select-Object -First 1).Name)) { throw("Failed to resolve $HostName") }
	$dnsname = "$Name.$SQLDNS"
	try {
		$checkdns = Resolve-DnsName $dnsname -QuickTimeout -NoHostsFile -ErrorAction stop | Where-Object { $_.name -like "$Name*" }
	}
 catch {
		$checkdns = ""
	}
	if ((($checkdns -ne "") -and ($Force)) -or ($checkdns -eq "")) {
		Write-Output "`nCreating $dnsname`n"
		try {
			$DC = (Get-ADDomainController -Discover -NextClosestSite).HostName
			Write-Verbose "AD controller: $DC"
			Write-Verbose "ZoneName: $SQLDNS"
			New-ImpersonatedUser (Get-SavedCredential -Domain $SQLDNS -DefaultUsername "$CurrentDomain\srvSQLDNSadmin")
			$SvcAccount = [environment]::UserName
			Write-Verbose "Adding $Name.$SQLDNS"
			Add-DnsServerResourceRecordCName -Name $Name -HostNameAlias $FQDN -ComputerName $DC -ZoneName $SQLDNS -ErrorAction Stop
			Remove-ImpersonateUser
			Write-AppEventLog -EntryType Information -Id 1000 -Message "Executed by: $([environment]::UserName)`nExecution impersonation account: $SvcAccount`n`nAdded CName $Name.$SQLDNS"
			Write-Output "`n$dnsname created"
		}
		catch {
			Write-Output "`n"
			Write-Warning "Add-DnsCName failed"
			throw($_)
		}
	}
 elseif (($checkdns -ne "") -and (!$Force)) {
		Write-Warning "DNS exists. Please use -Force switch to over-write"
	}
}

function Remove-DnsCName {
	<#
.SYNOPSIS
	Remove a CName from the SQL infrastructure domain zone

.DESCRIPTION
	Remove a CName from the SQL infrastructure domain zone

	A service account is required to query the DNS server which will prompt for and save credentials upon first run
	(credential file is saved in the users home directory as domain.cred - delete this file to update credentials)

	Application EventLog is written username and deleted CName

	CENTRAL / DETNSW		- SQL.INFRA.NSWEDUSERVICES.COM.AU
	PREDETNSW				- SQL.PREINFRA.NSWEDUSERVICES.COM.AU
	UATDETNSW				- SQL.TSTINFRA.NSWEDUSERVICES.COM.AU
	DEVDETNSW				- SQL.DEVINFRA.NSWEDUSERVICES.COM.AU

.NOTES
	Name: Remove-DnsCName
    Author: Chris Dobson
    DateCreated: 2017-05-08     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		08/05/2017	CD		Created 
	2		08/05/2017	CD		Added logging to event log

    To Do:   

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER Name
	CName alias to remove

.PARAMETER Force
	User will not be prompted before removing the CName

.EXAMPLE
	Remove-DnsCName -Name "CONTROLPOINT"

	Removes the alias CONTROLPOINT.SQL.DEVINFRA.NSWEDUSERVICES.COM.AU
#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)][string]$Name,
		[switch]$Force
	)
	if (!(IsAdmin)) { return }
	if (!(Get-Module ActiveDirectory -ListAvailable)) { throw("ActiveDirectory module not installed"); return; }
	if (!(Get-Command "Get-DnsServerResourceRecord" -ErrorAction SilentlyContinue)) {
		try {
			Write-Host "Installing DNS components"
			Install-WindowsFeature RSAT-DNS-Server
		}
		catch {
			throw($_)
			return
		}
	}
	if (!$SQLDNS) { Write-Host "Missing SQL DNS variable" -ForegroundColor Red; return }
	$DC = (Get-ADDomainController -Discover -NextClosestSite).HostName
	if ($Name.ToLower().Contains($SQLDNS.ToLower())) {
		$FQDN = $Name
		$Name = $Name.Split(".")[0]
	}
 else {
		$FQDN = "$Name.$SQLDNS"
	}
	Write-Verbose "Name: $Name"
	Write-Verbose "FQDN: $FQDN"
	if (!(Resolve-DnsName $FQDN -QuickTimeout -NoHostsFile -ErrorAction SilentlyContinue | Select-Object -First 1)) { throw("Failed to resolve $FQDN"); return; }
	try {
		New-ImpersonatedUser (Get-SavedCredential -Domain $SQLDNS -DefaultUsername "$CurrentDomain\srvSQLDNSadmin")
		$SvcAccount = [environment]::UserName
		Write-Verbose "Removing $FQDN"
		Remove-DnsServerResourceRecord -Name $Name -ZoneName $SQLDNS -ComputerName $DC -RRType CName -Force:$Force
		Remove-ImpersonateUser
		Write-AppEventLog -EntryType Information -Id 1001 -Message "Executed by: $([environment]::UserName)`nExecution impersonation account: $SvcAccount`n`nRemoved CName $FQDN"
	}
 catch {
		Write-Host "Remove-DnsCName failed" -ForegroundColor Red
		throw($_)
	}
}

function Write-AppEventLog {
	<#
.SYNOPSIS
	Writes a message to the Application event log

.DESCRIPTION
	Writes a message to the Application event log with the source of DETDBA

.NOTES
	Name: Write-AppEventLog
    Author: Chris Dobson
    DateCreated: 2017-05-08     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		08/05/2017	CD		Created 

    To Do:   

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER EntryType
	Can be Error, Information or Warning

.PARAMETER Message
	Details to be logged

.PARAMETER Id
	Specifies a unique identifier - between 1 and 65535

.EXAMPLE
	Write-AppEventLog -EntryType Information -Id 100 -Message "UserName started create script"

#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)][ValidateSet("Error", "Information", "Warning")][string]$EntryType,
		[Parameter(Mandatory = $true)][string]$Message,
		[Parameter(Mandatory = $true)][int]$Id
	)
	if (!([system.diagnostics.eventlog]::SourceExists("DETDBA"))) { [system.diagnostics.EventLog]::CreateEventSource("DETDBA", "Application") }
	Write-EventLog -LogName Application -Source "DETDBA" -EventId $Id -EntryType $EntryType -Message $Message
}


function Get-Shortcut {
	<#
.SYNOPSIS
	Outputs the definition of a symbolic link

.DESCRIPTION
	Outputs the definition of a symbolic link

.NOTES
	Name: Get-Shortcut
    Author: Pete Baekdal
    DateCreated: 2017-10-11     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		11/10/2017	PB		Created
    2       12/10/2017  PB      dos based solution replaced with native powershell solution

    To Do:

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.PARAMETER symbolic_link
	Link to be deciphered

.EXAMPLE
	Get-Shortcut "detdba"

#>
	param(
		[Parameter(Mandatory = $true)][string]$symbolic_link
	)
	<# original dos based solution
    cmd /c dir /a:l | ? { $_ -match "$symbolic_link \[.*\]$" } | % `
    {
        $_.Split([char[]] @( '[', ']' ), [StringSplitOptions]::RemoveEmptyEntries)[1]
    }
    #>
	Get-Item $symbolic_link | Select-Object -ExpandProperty Target
}

function Get-LowSpaceVolumes {
	<# 
.SYNOPSIS
	Generates a simple chart showing free space

.DESCRIPTION
	Pipeline enabled so can check n servers in the same domain and then RDP to the selected server

.NOTES     
    Name: Get-LowSpaceVolumes
    Author: Pete Baekdal
    DateCreated: 2018-10-04     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		2018-10-04	PB		Initial version
	2		2018-10-09	PB		sped up 10X through parallel processing

    To Do:   
    - if possible change the colour of the bars (red, amber, green)

.PARAMETER Name
	ComputerName to check

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell
#>
	[CmdLetBinding()]
	Param(
		[Parameter(Mandatory = $false, Position = 1, ValueFromPipeline = $true)]
		[String]$computer = $env:ComputerName
	)

	begin {
		$computers = @()
	}

	process {
		$computers += $computer
	}

	end {
		$result_list = $computers | Invoke-Parallel -Throttle 50 -ScriptBlock {
			[string]$bar = [char]9612
			#for use in splatting the parameters into Get-WmiObject
			$wmi = @{
				Filter      = "DriveType='3' AND (Not Name LIKE  '\\\\?\\%')"
				Class       = "Win32_Volume"
				ErrorAction = "Stop"
				Property    = "Name", "Label", "Capacity", "FreeSpace", "__SERVER"
			}
			$list = New-Object System.Collections.ArrayList

			Get-WmiObject @wmi -ComputerName $_ |
			ForEach {
				$decimal = $_.freespace / $_.capacity
				$graph = "$($bar)" * ($decimal * 100) + (" " * (165 - ($decimal * 100))) # 165 is to deliberately pad the end of the bar with spaces so it doesn't get truncated
				$hash = [ordered]@{
					<#watch out: if we didn't include the __server in the splatting property for Get-WmiObject to output
			then we wouldn't get PSComputerName - it is an alias of __server
			#>
					Computername = $_.PSComputerName
					Name         = $_.Name
					FreeSpace    = "$graph"       
					Percent      = $decimal * 100
					FreeSpaceGB  = ([math]::Round(($_.Freespace / 1GB), 2))
					CapacityGB   = ([math]::Round(($_.Capacity / 1GB), 2))
				}
				$list.Add([pscustomobject]$hash) | out-null
			}
			$list
		}

		$result_list |
		Sort-Object -Property Percent |
		Out-GridView -Title 'Drive Space - click a server and the OK button to RDP to it (when run on a workstation)' -PassThru |
		foreach {
			<#somehow just within the scope of this function, $CurrentDomain is being reset to the env:UserDomainName but luckily $CMSInstance isn't so we get the domain out of it and use it #>
			#Start-Process mstsc "/v:$($_.computername).$($CurrentDomain).win"

			$CMSInstance_domain = $CMSInstance.split('.')[1]
			$mstsc_parameters = "/v:$($_.computername).$($CMSInstance_domain)."
			switch ($CMSInstance_domain) {
				"central"	{ $mstsc_parameters += "det.win" }
				default { $mstsc_parameters += "win" }
			}
			Start-Process mstsc $mstsc_parameters
		}


	}
}
function Get-InstanceStatus {
	<# 
	.SYNOPSIS
		Get the current status of an instance
	
	.DESCRIPTION
		Get the current status of an instance. 
	
	.NOTES     
		Name: Get-InstanceStatus
		Author: Januar Boediman
		DateCreated: 2019-10-21     
		
		Build	Date		Author	Comments
		-----------------------------------------------------------------------------------------------
		1		2019-10-21	JB		Created
	
		To Do:   
	
	.PARAMETER InstanceName
		Name of the Instance. It can use pipeline 
	
	.PARAMETER fromCMS
		Run the script with the input from get-cmsinstance
	
	.LINK     
		https://itdwiki.det.nsw.edu.au/display/Database/Powershell
	
	.EXAMPLE
		@('dw0991sqp103n1.devdetnsw.win\whss1','dw0991sqp103n1.devdetnsw.win\whss1') | Get-InstanceStatus
		
		Get status of the instances fed through pipeline
	
	.EXAMPLE
		Get-InstanceStatus -InstanceName @('dw0991sqp103n1.devdetnsw.win\whss1','dw0991sqp103n1.devdetnsw.win\whss1')
		Get-InstanceStatus -InstanceName 'dw0991sqp103n1.devdetnsw.win\whss1','dw0991sqp103n1.devdetnsw.win\whss1'
	
		Get the status of the specified instances
	
	.EXAMPLE
		Get-InstanceStatus -fromCMS
	
		This will display the status of the isntances listed by get-cmsinstances function
	
	.EXAMPLE
		(Get-CMSInstances -child hci -parent development).instance | Get-InstanceStatus
	
		Specified instances from Get-CMSInstance function and pass it through pipeline 
	#>
	
	[CmdletBinding()]
	Param (
		[Parameter (ValueFromPipeline = $true,
			ValueFromPipelineByPropertyName = $true)]
		[string[]] $InstanceName,
		[switch] $fromCMS
	)
	
	BEGIN {
		if ($fromCMS) {
			$Instances = Get-CMSInstances
			$InstanceName = @() + $Instances.instance
		}
	}
	
	PROCESS {
		#$results = 
		invoke-parallel -InputObject $InstanceName -Throttle 4 -Quiet -ScriptBlock {
			$Instance = $_
			$index1 = ($Instance | Select-String "\." ).Matches.Index
			$host_name = $Instance.Substring(0, $index1[0])
			try {
				$query_result = invoke-sqlcmd2 -ServerInstance $Instance -Query "select '1' as [column1]"
				$Properties = @{host_name = $host_name; 
					instance                 = $Instance; 
					online                   = $true
    }
			}
			catch {
				$Properties = @{host_name = $host_name; 
					instance                 = $Instance; 
					online                   = $false
    }
			}
			finally {
				$instance_object = New-Object -TypeName psobject -Property $Properties
				Write-Output $instance_object
			}
		} 
	}
}