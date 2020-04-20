
<# 
.SYNOPSIS
	To compare and report any difference in SQL login between primary and secondary instances

.DESCRIPTION
	To compare and report any difference in SQL login between primary and secondary instances

.NOTES     
    Name: Get-LoginDiff
    Author: Januar Boediman
    DateCreated: 2019-10-24     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		2019-10-24	JB		Created

    To Do:   

.PARAMETER PrimaryInstance
	The name of the primary instance.

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.EXAMPLE
    .\get-logindiff.ps1 -PrimaryInstance 'dw0991sqp003n1\AdobeConnect1' | Select-Object primaryserver, secondaryserver, loginname, rolename | Format-Table -GroupBy secondaryserver

    Specifying a single primary instance, select the specified object properties and display in table format, grouped by secondaryserver

.EXAMPLE
    'dw0991sqp003n1\AdobeConnect1' | .\get-logindiff.ps1

    Specifying a single primary instance via pipeline

.EXAMPLE
    (Get-CMSInstances -Filter "[host_name] not like '%pocn%'and [host_name] not in ('dw0991sqlp0001.devdetnsw.win')").instance | .\get-logindiff.ps1 | Select-Object primaryserver, secondaryserver, loginname, rolename | Format-Table -GroupBy secondaryserver

    Specified instances from Get-CMSInstances function and pass it through pipeline 
#>

[CmdletBinding()]
Param (
[Parameter (ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
[String[]] $PrimaryInstance
#$ComputerName = (Get-CMSHosts2 -child "hci" -parent "crash and burn" -Filter "[host_name] like '%102n%'").host_name
)
BEGIN {
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null

#$cmsinstances = Get-CMSInstances #-Filter "instance like 'dw09%sqp003%'"
#$instances = $cmsinstances.instance
}
PROCESS {
Function get-loginandrole {
    Param(
        [string]$Instance #= "dw0991sqp003n1\aos_ag_test"
    )
    
    $sqlquery = "SELECT login.name AS Login, role.name AS RoleName
    FROM sys.server_principals AS login 
    left join sys.server_role_members rm ON rm.member_principal_id = login.principal_id
    left JOIN sys.server_principals AS role ON  role.principal_id = rm.role_principal_id and role.type = 'R' --and role.is_fixed_role = 0  
    LEFT JOIN sys.server_permissions sp on sp.grantee_principal_id = ISNULL(login.principal_id, role.principal_id)
    WHERE login.type_desc in ('WINDOWS_GROUP','SQL_LOGIN','WINDOWS_LOGIN')
    and login.name <> 'sa'
    and login.name not like 'NT%\%'
    and login.name not like '##%'
    and login.name not like '%ad_databases_admin%'
    and login.name not like '%srvSQLServer%'
    and login.name not like '%srvSQLAgent%'" 
    try {
    $results = Invoke-Sqlcmd -ServerInstance $Instance -Query $sqlquery -ErrorAction Stop
    Write-Output $results
    } Catch {}
}

foreach ($instancename in $PrimaryInstance) {
    
    try {
        $index1 = ($instancename | Select-String "\." ).Matches.Index 
        $index2 = (($instancename[-1..-($instancename.length)] -join ”") | Select-String "\\" ).Matches.Index
        $hostonly = $instancename.Substring(0,$index1[0])
        $instaonly = $instancename.Substring($instancename.Length - $index2[0],$index2[0])
        $instancenodmn = "$hostonly\$instaonly"
    }
    catch {
        $instancenodmn = $instancename
    }

    try {
    $serverInstance = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $instancename -ErrorAction Stop
    Write-Verbose "`nChecking if instance is in AG if not exit"
    if ($serverInstance.AvailabilityGroups.Name) {
        
        $primaryserver = $serverInstance.AvailabilityGroups.PrimaryReplicaServerName 
        #Write-Output "`nprimary server is $primaryserver"
        #Write-Verbose "`nChecking if instance is primary server if not exit"
        if ($instancenodmn -eq $primaryserver) {
            #Write-Warning "executing on $instancenodmn"
            $secondaryservers = $serverInstance.AvailabilityGroups.AvailabilityReplicas | Where-Object { $_.name -ne $primaryserver }
            #Write-Output "secondary replicas: $secondaryservers"
            $priloginrole = get-loginandrole -instance $primaryserver
            #Write-Output "Primary login $priloginrole"
            foreach ($secondaryserver in $secondaryservers) {
                $secondaryservername = $secondaryserver.name
                #Write-Verbose "`nGet the configurations of instance $secondaryservername"
                $secloginrole = get-loginandrole -instance $secondaryservername
                $compare = Compare-Object -ReferenceObject $priloginrole -DifferenceObject $secloginrole -Property Login,rolename | Where-Object {$_.sideindicator -eq "<="}
                if (@($compare).count -gt 0) {
                #Write-Output "`nDiff on Secondary Replica: $secondaryservername"
                    $compare | ForEach-Object {
                        $props = @{PrimaryServer = $instancenodmn
                        SecondaryServer = $secondaryservername
                        LoginName = $_.Login
                        RoleName = $_.rolename}
                    $compareresult = New-Object -TypeName PSObject -Property $props
                    Write-Output $compareresult
                    }          
                }
                #else {
                #    Write-Output "No Difference"
                #}
            }
            $serverInstance.ConnectionContext.Disconnect()
        }
        #else {
        #    Write-Output "$serverInstance is not primary - not processing"
        #}
    }
    else {
        Write-Verbose "`n$serverInstance has no AG"
    }
    } Catch {}


}
}
END {}