param(
[Parameter(Mandatory=$True)]
[string[]] $ComputerName,
[Parameter(Mandatory=$True)]
[string] $InstanceName

)

$servicename = 'MSSQL$' + $InstanceName

Foreach ($Computer in $ComputerName){
    $serverinstance = "$Computer\$InstanceName"
    Write-Output "Enabling AG on instance $serverinstance"
    Enable-SqlAlwaysOn -ServerInstance $serverinstance -NoServiceRestart
    Write-Output "Restarting service $servicename"
    Get-Service -ComputerName $Computer -Name $servicename | Restart-Service -Force
}
