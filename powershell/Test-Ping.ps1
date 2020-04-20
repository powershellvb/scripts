
param(
[string] $ComputerName
, [string] $FileLocation
, [int] $WaitinSec
)

#check if $ComputerName and $FileLocation parameters populated
if($ComputerName -eq "" -and $FileLocation -eq ""){
    Write-Host ""
    Write-Host "*************** Test-Ping Usage *************************************************"
    Write-host 'Please populate "$ComputerName" or "$FileLocation" parameter' -ForegroundColor Yellow #-ErrorAction Stop
    Write-Host "example:"
    Write-Host "Test-Ping.ps1 -Computername pw1234sqp111n1 or"
    Write-Host "Test-Ping.ps1 -Filelocation servers.txt -waitinsec 5" -NoNewline
	Write-Host "    By default -waitinsec is set to 3 seconds" -ForegroundColor DarkGray
    Write-Host "*********************************************************************************"
    Write-Host ""

    return
} #if both parameters empty
elseif($ComputerName -ne "" -and $FileLocation -ne "") {
    Write-Host ""
    Write-Host "*************** Test-Ping Usage ***************************************************"
    Write-host 'Only polulate either "$ComputerName" or "$FileLocation" parameter. Do not use both.' -ForegroundColor Yellow
    Write-Host "example:"
    Write-Host "Test-Ping.ps1 -Computername pw1234sqp111n1 or"
    Write-Host "Test-Ping.ps1 -Filelocation servers.txt -waitinsec 5" -NoNewline
	Write-Host "    By default -waitinsec is set to 3 seconds" -ForegroundColor DarkGray
    Write-Host "***********************************************************************************"
    Write-Host ""

    return
} #if both parameters populated

#set the value of $servers
if($ComputerName -ne "") {
    $servers = $ComputerName
}
elseif($FileLocation -ne ""){
    if(Test-Path $FileLocation){
        $servers = Get-Content ".\$FileLocation"
    } #if file exists
    else {
        Write-Error "File specified cannot be found. Please check." -ErrorAction Stop
    } #if not exists
}

#set $reps to 1 if not specified
if(!($WaitinSec)){
    $WaitinSec = 3
}

$totalservers = $servers.Count

#do the ping until $reps value drop to less than 1
DO{
    Get-Date -Format G
    $serverdown = 0
    $serverup = 0
    $servercount = 0
    foreach ($server in $servers){
        if(!(Test-Connection -ComputerName $server -BufferSize 16 -Count 1 -ea 0 -quiet)){
            Write-Output "Server $server is not available"
            $serverdown = $serverdown + 1
        } #if
        Else {
            $serverup = $serverup + 1
        } #elseif
    } #foreach

    $servercount = $totalservers - $serverup

    if ($servercount -gt 0){
        Write-Output ""
        Write-Output "Total server in the list = $totalservers"
        Write-Output "Total server down = $servercount"
        Start-Sleep -s $WaitinSec
        Write-Output ""
    }
    else {
        Write-Output ""
        Write-Output "Total server in the list = $totalservers"
        Write-Output "Total server down = $servercount"
        Write-Output ""
    }

} until ($servercount -lt 1)

if($servercount -lt 1){
    Write-Output ""
    $g = $host.ui.RawUI.ForegroundColor
    $host.ui.RawUI.ForegroundColor = “Green”
    Write-Output "All servers are available"
    $host.ui.RawUI.ForegroundColor = $g
    Write-Output ""
}
else{
    Write-Output ""
    $r = $host.ui.RawUI.ForegroundColor
    $host.ui.RawUI.ForegroundColor = “Red”
    Write-Output "Some servers are still down. Please check."
    $host.ui.RawUI.ForegroundColor = $r
    Write-Output ""
}

