$servernames = (Get-CMSHosts).host_name
#$servernames = @('pw0991sqs105n1.detnsw.win','pw0992sqs006n1.detnsw.win','qw0992sqs102n1.detnsw.win','pw0000sqlpe097.detnsw.win','qw0000sqlqe006.detnsw.win')
foreach ($servername in $servernames) {
    $serversplit = $servername.Split(".")
    $server = $serversplit[0]
    $session = New-PSSession -ComputerName $server
    $results = Invoke-Command -Session $session -ScriptBlock {
        $SQLmodule = Get-Module -Name SQLServer -ListAvailable
        if ($null -eq $SQLmodule) {
            $SQLmodule = Get-Module -Name SQLPS -ListAvailable
        }
        if ($null -ne $SQLmodule) {
            Import-Module $SQLmodule -DisableNameChecking 
        }
        Get-ChildItem -Path "SQLSERVER:\sql\$server"
    }
    $instances = $results.servers.Keys
    if ($instances.Count -gt 1) { 
        foreach ($instance in $instances) {
            if ($instance -match "sqlplaceholder") { 
                Write-Output "$servername\$instance"
            }
        }
    }
}