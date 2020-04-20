<# 
.SYNOPSIS
	Synchronise the Server config settings between the primary and secondary servers

.DESCRIPTION
	This script will only run if it identifies the instance as a primary replica of an Availability Group. It will then compare the configuration settings ('cost threshold for parallelism','max degree of parallelism','min server memory (MB)','max server memory (MB)','optimize for ad hoc workloads') and will apply the difference on to the secondary replicas.

.NOTES     
    Name: Sync-Serverconfig
    Author: Januar Boediman
    DateCreated: 2019-11-07     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		2019-11-07	JB		Created

    To Do:   

.PARAMETER InstancenNames
	The name of the SQL instance.

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.EXAMPLE
    PS> .\sync-Serverconfig.ps1 -InstanceNames (Get-CMSInstances -Filter "instance like '%101%'").instance -Verbose

    Synchronise the config of the SQL instances specified by 'Get-CMSInstances' function. Turn on the 'Verbose' messages

.EXAMPLE
    PS> 'dw0991sqp102n1\cirreltest23' | .\sync-Serverconfig.ps1

    Specifying a single primary instance via pipeline

.EXAMPLE
    PS> (Get-CMSInstances -Filter "instance like 'dw%'").instance | .\sync-Serverconfig.ps1 -Verbose *> c:\dbascripts\syncconfiguration_verbose.txt

    Synchronise the configuration and capture the verbose messages to a file 
#>

[CmdletBinding()]
param (
[Parameter (ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
[string[]] $InstanceNames
)
BEGIN {
    #$opt = (Get-Host).PrivateData
    #$opt.WarningBackgroundColor = "white"
    #$opt.WarningForegroundColor = "red"
    #$opt.ErrorBackgroundColor = "red"
    #$opt.ErrorForegroundColor = "white"

    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
    
    If ($PSBoundParameters.ContainsKey('verbose')) {
        $properties += @{vpref = "Continue"}
    } else {
        $properties += @{vpref = "SilentlyContinue"}
    }

    $invokepara_obj = New-Object -TypeName PSObject -Property $properties
}

PROCESS{
Invoke-Parallel -InputObject $InstanceNames -Parameter $invokepara_obj -Throttle 5 -Quiet -ScriptBlock {
    [CmdletBinding()]
    $instancename = $_
    $verbosePref = $parameter.vpref
    $VerbosePreference=$verbosePref;

    Function Compare-ObjectProperties {
        Param(
            [PSObject]$ReferenceObject,
            [PSObject]$DifferenceObject 
        )
        $objprops = $ReferenceObject | Get-Member -MemberType Property,NoteProperty | ForEach-Object Name
        $objprops += $DifferenceObject | Get-Member -MemberType Property,NoteProperty | ForEach-Object Name
        $objprops = $objprops | Sort-Object | Select-Object -Unique
        $diffs = @()
        foreach ($objprop in $objprops) {
            $diff = Compare-Object $ReferenceObject $DifferenceObject -Property $objprop
            if ($diff) {            
                $diffprops = @{
                    PropertyName=$objprop
                    RefValue=($diff | Where-Object {$_.SideIndicator -eq '<='} | ForEach-Object $($objprop))
                    DiffValue=($diff | Where-Object {$_.SideIndicator -eq '=>'} | ForEach-Object $($objprop))
                }
                $diffs += New-Object PSObject -Property $diffprops
            }        
        }
        if ($diffs) {Write-Output ($diffs | Select-Object PropertyName,RefValue,DiffValue)}     
    }
  
    Function Get-Config {
        Param(
            [String]$instance
        )
    
        $serverInstancecfg = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $instance

        #Write-Verbose "`t secondary: $instance - check - config" 4>&1

        $setting = New-Object -TypeName PSObject
            $setting | Add-Member -name 'MaxServerMemory' -MemberType Noteproperty $serverInstancecfg.Configuration.MaxServerMemory.ConfigValue
            $setting | Add-Member -name 'MinServerMemory' -MemberType Noteproperty -Value $serverInstancecfg.Configuration.MinServerMemory.ConfigValue
            $setting | Add-Member -name 'MaxDegreeOfParallelism' -MemberType Noteproperty -Value $serverInstancecfg.Configuration.MaxDegreeOfParallelism.ConfigValue
            $setting | Add-Member -name 'CostThresholdForParallelism' -MemberType Noteproperty -Value $serverInstancecfg.Configuration.CostThresholdForParallelism.ConfigValue
            $setting | Add-Member -name 'OptimizeAdhocWorkloads' -MemberType Noteproperty -Value $serverInstancecfg.Configuration.OptimizeAdhocWorkloads.ConfigValue

        $serverInstancecfg.ConnectionContext.Disconnect()

        Write-Output $setting
    }

    Function Update-Config {
        Param(
            [string]$Instance
            ,[string]$PropertyName
            ,[string]$value

        )
    
        try {
        $serverInstance1 = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $instance -ErrorAction stop

        Write-Verbose "`t secondary: $instance - setting - $PropertyName  with value: $value" 4>&1
        $serverInstance1.Configuration.$PropertyName.ConfigValue = $value
        $serverInstance1.Configuration.Alter()

        $serverInstance1.ConnectionContext.Disconnect()
        }
        catch {
            Write-error "secondary: $instance - ERROR - Altering the config value"
            #Write-Warning "`nsecondary: $instance - ERROR - Altering the config value" 3>&1
        }
    }

    [object[]]$results
  
    $serverInstance = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $instancename
    try {
        $index1 = ($instancename | Select-String "\." ).Matches.Index 
        $index2 = (($instancename[-1..-($instancename.length)] -join ”") | Select-String "\\" ).Matches.Index
        $hostonly = $instancename.Substring(0,$index1[0])
        $instaonly = $instancename.Substring($instancename.Length - $index2[0],$index2[0])
        $instancenodomain = "$hostonly\$instaonly"
    }
    catch {
        $instancenodomain = $instancename
    }

    try {
    if ($serverInstance.AvailabilityGroups.Name) {
        $primaryserver = $serverInstance.AvailabilityGroups.PrimaryReplicaServerName
        if ($instancenodomain -eq $primaryserver) {
            $secondaryservers = $serverInstance.AvailabilityGroups.AvailabilityReplicas | Where-Object { $_.name -ne $primaryserver }
            $prisetting = Get-Config -instance $primaryserver

            foreach ($secondaryserver in $secondaryservers) {
                $secondaryservername = $secondaryserver.name
                Write-Verbose "$primaryserver - secondary: $secondaryservername" 4>&1
                $secsetting = Get-Config -instance $secondaryservername
                $results = Compare-ObjectProperties $prisetting $secsetting
                if (@($results).count -gt 0) {
                    $results | ForEach-Object {
                        $PropertyName = $_.PropertyName
                        $Refvalue = $_.RefValue
                        Update-Config -instance $secondaryservername -PropertyName $PropertyName -value $Refvalue
                    }
                }
            }
            $serverInstance.ConnectionContext.Disconnect()
        }
    }
    }
    catch {
        Write-Error "$instancenodomain - ERROR - Processing instance"
        #Write-Warning "`n$instancenodomain - ERROR - Processing instance" 3>&1
    }
} #invoke-parallel
    $VerbosePreference="SilentlyContinue";
} #process

END {
    #$opt = (Get-Host).PrivateData
    #$opt.ErrorForegroundColor = "Red"
    #$opt.ErrorBackgroundColor = "Black"
    #$opt.WarningForegroundColor = "Yellow"
    #$opt.WarningBackgroundColor = "Black"
}
