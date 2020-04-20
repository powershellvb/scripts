#function Fix-StartupParams {
<# 
.SYNOPSIS
	To enable the SQL trace flag via registry

.DESCRIPTION
	To enable the SQL trace flag via registry. The changes will not take affect until the SQL instance is restarted. 

.NOTES     
    Name: Fix-StartupParams
    Author: Januar Boediman
    DateCreated: 2019-10-23     
    
	Build	Date		Author	Comments
	-----------------------------------------------------------------------------------------------
	1		2019-10-23	JB		Created

    To Do:   

.PARAMETER ComputerName
	The name of the server. Can be fed via pipeline.

.PARAMETER TraceFlag
    Trace flags (eg 'T2371')

.PARAMETER InstanceName
    The instance name (eg 'SQLPlaceholder1')

.LINK     
    https://itdwiki.det.nsw.edu.au/display/Database/Powershell

.EXAMPLE
    PS> .\fix-StartupParams.ps1 -ComputerName 'dw0991sqlp0001.devdetnsw.win' -TraceFlag '-T7412','-T3226' -InstanceName 'MV_HCI_TEST5','MV_HCI_TEST1' -Verbose

    Fix traceflag -T7412 and -T3226 on server dw0991sqlp0001.devdetnsw.win, instance name MV_HCI_TEST5 and MV_HCI_TEST1, with verbose flag turn on

.EXAMPLE
    PS> 'dw0991sqlp0001.devdetnsw.win' | .\fix-StartupParams.ps1 -PrintOnly

    This will print out any commands and results from ALL instances on DW0991SQLP0001 server to the screen

.EXAMPLE
    PS> (Get-CMSHosts -child "hci" -parent "crash and burn" -Filter "[host_name] not like '%pocn%'and [host_name] not in ('dw0991sqlp0001.devdetnsw.win')").host_name |
.\fix-StartupParams.ps1

    Specified instances from Get-CMSInstance function and pass it through pipeline 
#>

[CmdletBinding()]
Param (
[Parameter (ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
[String[]] $ComputerName
, [String[]] $TraceFlag
, [String[]] $InstanceName
, [Switch] $PrintOnly
#$ComputerName = (Get-CMSHosts2 -child "hci" -parent "crash and burn" -Filter "[host_name] like '%102n%'").host_name
)
BEGIN
{
    If ($PSBoundParameters.ContainsKey('traceflag')) {
        $properties = @{traceflags = $TraceFlag}
    } else {
        $properties = @{traceflags = @('-T2371','-T1204','-T4199','-T3226','-T7412')}
    }

    If ($PSBoundParameters.ContainsKey('verbose')) {
        $properties += @{vpref = "Continue"}
    } else {
        $properties += @{vpref = "SilentlyContinue"}
    }

    If ($PSBoundParameters.ContainsKey('InstanceName')) {
        $properties += @{instancename = $InstanceName}
    } else {
        $properties += @{instancename = "All"}
    }

    If ($PSBoundParameters.ContainsKey('PrintOnly')) {
        $properties += @{print = "y"}
    } else {
        $properties += @{print = "n"}
    }

    $tflagobj = New-Object -TypeName PSObject -Property $properties
}

PROCESS
{
    Invoke-Parallel -InputObject $ComputerName -Parameter $tflagobj -Throttle 5 -Quiet -ScriptBlock {
        [CmdletBinding()]
        $Computer = $_
        $traces = $parameter.traceflags
        $verbosePref = $parameter.vpref
        $InstNames = $parameter.instancename
        $view = $parameter.print

        #Write-Output " "
        Write-Warning "############## Processing $Computer ##############"
    
        $session = New-PSSession -ComputerName $Computer
        Invoke-Command -Session $session -ScriptBlock {
            param (
                [string] $viewonly
                ,[string] $verbpref
                ,[string []] $instancenames
                ,[string []] $tflags
         
            )
            Function Add-SqlServerStartupParameter {
                [CmdletBinding()]
                Param (
                ## The parameter you wish to add
                [Parameter(Mandatory = $true)]
                $StartupParameter,
                [Parameter(Mandatory = $true)]
                [string]$instance_to_set
                , [string]$view
                )

                $hklmRootNode = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server"
                $regKey = "$hklmRootNode\$instance_to_set\MSSQLServer\Parameters"
                $props = Get-ItemProperty $regKey
                $params = $props.psobject.properties | ?{$_.Name -like 'SQLArg*'} | select Name, Value
                $hasFlag = $false
                
                foreach ($param in $params) {
                    if($param.Value -eq $StartupParameter) {
                        $hasFlag = $true
                        break;
                    }
                }
                if (-not $hasFlag) {
                    $VerbosePreference=$verbpref; 
                    Write-Verbose "Adding $StartupParameter"
                    $newRegProp = "SQLArg"+($params.Count)
                    $VerbosePreference=$verbpref; 
                    Write-Verbose "Set-ItemProperty -Path $regKey -Name $newRegProp -Value $StartupParameter"
                    if ($view -eq "n") {
                        Set-ItemProperty -Path $regKey -Name $newRegProp -Value $StartupParameter
                    }
                } else {
                    $VerbosePreference=$verbpref; 
                    Write-Verbose "$StartupParameter already set"
                }
            }
            
            if ($viewonly -eq "y") {
                $verbpref = "Continue"
            }

            $hklmRootNode = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server"
            $props = Get-ItemProperty "$hklmRootNode\Instance Names\SQL"
            
            if ($instancenames -eq "All") {
                $instances = $props.psobject.properties | Where-Object {$_.Value -like 'MSSQL*'} | Select-Object Value
                
            } else {
                foreach ($instname in $instancenames) {
                    $checkedinsts = $props.psobject.properties | Where-Object {$_.Value -like "MSSQL*$instname"} | Select-Object Value
                    if ($checkedinsts) {
                        $instances += $checkedinsts
                    } else {
                        Write-Warning "### THERE IS NO INSTANCE NAME '$instname' ON $ENV:COMPUTERNAME ###"
                    }
                }
            } 
                
            foreach ($instance in $instances) {
                $VerbosePreference=$verbpref; 
                Write-Verbose "`nRun script to set startup trace flags for instance $($instance.value)"    
                foreach ($flag in $tflags ) {
	               add-sqlserverstartupparameter -StartupParameter $flag -instance_to_set $instance.value -view $viewonly
                }
            }
            
        } -ArgumentList (,$view,$verbosePref,$InstNames,$traces)
    }
}

END {}

#}