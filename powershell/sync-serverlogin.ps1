<# 
.SYNOPSIS
	Synchronise the Server Principals and its server roles between the primary and secondary instances

.DESCRIPTION
    This script will only run if it identifies the instance as a primary replica of an Availability Group. 
    It checks the servers principals on primary replica, compare them with the one on secondaries and will deploy and server principals that exists on primary but not on secondary to the secondary replicas. 
    Requires the location of sync-serverlogin_sprocs.sql file to be specified.

.NOTES     
    Name: Sync-Serverlogin
    Author: Januar Boediman
    DateCreated: 2019-11-18     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		2019-11-18	JB		Created

    To Do:   

.PARAMETER InstancenNames
	The name of the SQL instance.

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.EXAMPLE
    PS> .\Sync-Serverlogin.ps1 -InstanceNames (Get-CMSInstances -Filter "instance like '%101%'").instance -Verbose

    Synchronise the server principals of the SQL instances specified by 'Get-CMSInstances' function. Turn on the 'Verbose' messages

.EXAMPLE
    PS> 'dw0991sqp102n1\cirreltest23' | .\Sync-Serverlogin.ps1

    Specifying a single primary instance via pipeline

.EXAMPLE
    PS> (Get-CMSInstances -Filter "instance like 'dw%'").instance | .\Sync-Serverlogin.ps1 -Verbose *> c:\dbascripts\syncServerlogins_verbose.txt

    Synchronise the server principals and capture the verbose messages to a file 
#>

[CmdletBinding()]
param (
[Parameter (ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
[string[]] $InstanceNames
)
BEGIN {
    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
    try {
        $sprevlogin = Get-Content .\sync-serverlogin_sprocs.sql -Raw -ErrorAction Stop
    } catch {
        Write-Error "Cannot find 'sync-serverlogin_sprocs.sql' file in the specified location." -ErrorAction Stop
        exit
    }

    If ($PSBoundParameters.ContainsKey('verbose')) {
        $properties += @{vpref = "Continue"}
    } else {
        $properties += @{vpref = "SilentlyContinue"}
    }

    $properties += @{sprevlogin = $sprevlogin}

    $invokepara_obj = New-Object -TypeName PSObject -Property $properties
}

PROCESS {
Invoke-Parallel -InputObject $InstanceNames -Parameter $invokepara_obj -Throttle 5 -Quiet -ScriptBlock {
    #[CmdletBinding()]
    $InstanceName = $_
    $VerbosePref = $parameter.vpref
    $sprevlogins = $parameter.sprevlogin
    #$VerbosePreference=$VerbosePref;

    Function Get-Loginandrole {
        Param(
            [string]$Instance #= "dw0991sqp003n1\aos_ag_test"
        )
    
        try {
        $serverInstance = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $Instance
        Foreach ($Role in $serverInstance.Roles){
            $Role.EnumServerRoleMembers() | Where-Object { `
                    ($_ -ne 'sa') `
                    -and ($_ -notlike '*srvSQLServer') `
                    -and ($_ -notlike '*srvSQLAgent') `
                    -and ($_ -notlike '*ad_databases_admin*') `
                    -and ($_ -notlike '*NT*\*') `
                    -and ($_ -notlike '##*') } | ForEach-Object {
                    $properties = @{LoginName = $_
                                    RoleName = $Role.Name} 
                $loginroleobj = New-Object -TypeName PSObject -Property $properties
                Write-Output $loginroleobj
                }
        $serverInstance.ConnectionContext.Disconnect()
        }
        } Catch {}
    }

    #Extract logins and create sql script to create login and assign roles
    function Create-Loginandrole{
        param (
            [String]$serverinstance,
            [String]$loginname,
            [String]$rolename
        )
    
        $sqlscript = "exec tempdb.dbo.sp_help_revlogin @login_name='$loginname'"
        $ps = [PowerShell]::Create()
        $ps.AddCommand( "Invoke-Sqlcmd" ).AddParameter( "serverinstance", $serverinstance ).AddParameter( "Query", $sqlscript ).AddParameter( "Verbose" ) | Out-Null
        $ps.Invoke()
        $createloginsql = "if not exists (select 1 from sys.server_principals where name = '$loginname') `r`nbegin`r`n"
        $createloginsql += $ps.Streams.Verbose | ForEach-Object { $_.Message }
        $createloginsql += "`r`nend`r`n `r`nAlter Server Role $rolename add member [$loginname] `r`nGO`r`n"

        Write-Output $createloginsql
    }

    function sync-sysdbuser {
        param (
            [String]$primaryinstance,
            [String]$secondaryinstance,
            [String[]]$sysdbs = @("msdb","master")
        )
    
        foreach ($sysdb in $sysdbs) {
            [object[]]$sysdbresult = @()
            $VerbosePreference=$VerbosePref;
                Write-Verbose "`tPrimary - CHECK - user permission on $sysdb - $primaryinstance" 4>&1
            $VerbosePreference="SilentlyContinue";
            $sysdbqry ="use $sysdb
             -- Database role mappings
            select [LoginName]=suser_sname(usr.sid),[RoleName]=rol.name --,DBUsr=usr.name
            from sys.database_role_members rm 
            inner join sys.database_principals rol  ON rol.principal_id = rm.role_principal_id and rol.Type = 'R'
            left join sys.database_principals usr on usr.principal_id = rm.member_principal_id and usr.Type != 'R'
            WHERE  suser_sname(usr.sid) not in ('sa') --,'netbackup')
            and suser_sname(usr.sid) not like 'NT%\%'
            and suser_sname(usr.sid) not like '##%'
            and suser_sname(usr.sid) not like '%ad_databases_admin%'
            and suser_sname(usr.sid) not like '%srvSQL%'
            "
            try {
                $sysdbresult = Invoke-Sqlcmd -ServerInstance $primaryinstance -Query $sysdbqry -ErrorAction Stop
            }
            catch {
                $sysdbresult = @()
                Write-Error "`tPrimary - CHECK - FAILED SYS DB" 2>&1
            }

            if (@($sysdbresult).Count -gt 0) {
                $sysdbresult | ForEach-Object {
                $login = $_.loginname
                $role = $_.rolename
                $VerbosePreference=$VerbosePref;
                    Write-Verbose "`tSecondary - SYNC - user permission on $sysdb - $primaryinstance" 4>&1
                $VerbosePreference="SilentlyContinue";
                $loginroleqry = "use $sysdb
                if not exists (select name from sys.database_principals where name = '$login')
                create user [$login] for login [$login]
                Alter role $role add member [$login]"

                try {
                    Invoke-Sqlcmd -ServerInstance $secondaryinstance -Query $loginroleqry -ErrorAction Stop
                }
                catch {
                    Write-Error "`tSecondary - ERROR - adding user $login to $sysdb - $secondarysrv"
                }
                }
            } else { }
        }
    }

    try { 
        $ServerInstance = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $InstanceName

        try {
            $Index1 = ($InstanceName | Select-String "\." ).Matches.Index 
            $Index2 = (($InstanceName[-1..-($InstanceName.length)] -join ”") | Select-String "\\" ).Matches.Index
            $HostOnly = $InstanceName.Substring(0,$Index1[0])
            $InstanceOnly = $InstanceName.Substring($InstanceName.Length - $Index2[0],$Index2[0])
            $InstanceNoDomain = "$HostOnly\$InstanceOnly"
        }
        catch {
            $InstanceNoDomain = $InstanceName
        }

        if ($serverInstance.AvailabilityGroups.Name) {
            $primaryserver = $serverInstance.AvailabilityGroups.PrimaryReplicaServerName
            if ($instancenodomain -eq $primaryserver) {
                $secondaryservers = $serverInstance.AvailabilityGroups.AvailabilityReplicas | Where-Object { $_.name -ne $primaryserver }
                #get login from primary
                $VerbosePreference=$VerbosePref;
                    Write-Verbose "$instancenodomain - Executing" 4>&1
                $VerbosePreference="SilentlyContinue";
                $priloginrole = Get-Loginandrole -instance $primaryserver
                if (@($priloginrole).count -gt 0) {
                    try {
                        Invoke-Sqlcmd -ServerInstance $primaryserver -Query $sprevlogins -ErrorAction Stop
                    }
                    catch {
                        Write-Error "$instancenodomain - ERROR - Deploy SP_RevLogin - $secondaryservername"  -ErrorAction Stop
                    }
                    foreach ($secondaryserver in $secondaryservers) {
                        $secondaryservername = $secondaryserver.name
                        #Write-Verbose "`nGet the configurations of instance $secondaryservername" 4>&1
                        $VerbosePreference=$VerbosePref;
                            Write-Verbose "`tSecondary - CHECK - Logins and Roles - $secondaryserver" 4>&1
                        $VerbosePreference="SilentlyContinue";
                        $secloginrole = Get-Loginandrole -instance $secondaryservername
                        if (@($secloginrole).count -gt 0) {
                            $compare = Compare-Object -ReferenceObject $priloginrole -DifferenceObject $secloginrole -Property LoginName,rolename | Where-Object {$_.sideindicator -eq "<="}
                        } else {
                            $properties = @{LoginName = ""
                                            RoleName = ""} 
                            $secloginrole = New-Object -TypeName PSObject -Property $properties
                            $compare = Compare-Object -ReferenceObject $priloginrole -DifferenceObject $secloginrole -Property LoginName,rolename | Where-Object {$_.sideindicator -eq "<="}
                        }
                        if (@($compare).count -gt 0) {
                            $createloginsql = Create-Loginandrole -serverinstance $primaryserver -loginname $_.LoginName -rolename $_.rolename
                            try {
                                Invoke-Sqlcmd -ServerInstance $secondaryservername -Query $createloginsql -ErrorAction Stop
                            }
                            catch {
                                Write-Error "`tSecondary - ERROR - Create Login Role - $secondaryservername" 2>&1
                            }
                        }
                        sync-sysdbuser -primaryinstance $primaryserver -secondaryinstance $secondaryservername
                    } #secondary servers
                } #primary login exists
            } #primary server
            try {
                $dropsprevlogin = "USE tempdb
                    GO

                    IF OBJECT_ID ('sp_hexadecimal') IS NOT NULL
                      DROP PROCEDURE sp_hexadecimal
                    GO

                    IF OBJECT_ID ('sp_help_revlogin') IS NOT NULL
                      DROP PROCEDURE sp_help_revlogin
                    GO"
                Invoke-Sqlcmd -ServerInstance $primaryserver -Query $dropsprevlogin -ErrorAction Stop
            }
            catch {
                Write-Error "$primaryserver - ERROR - Drop SP_RevLogin" 2>&1
            }
        } #availability group
        $serverInstance.ConnectionContext.Disconnect()
    } catch {
        Write-Error "$InstanceName - ERROR - Failed to connect"
    }
}
$VerbosePreference="SilentlyContinue";
}

END {}
