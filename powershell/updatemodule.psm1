function update-mymodules {
<#
.SYNOPSIS
    update a module to the latest. Assuming module name is used as folder name and file name

.DESCRIPTION
    updating a module to the latest in the local computer. Remote update, coming.

.NOTES     
    
.PARAMETER Name
    name of the module 

.EXAMPLE
    update-mymodules jbmodule 
    
#>
[CmdletBinding()]
Param(
[Parameter (ValueFromPipeline=$true,
    ValueFromPipelineByPropertyName=$true,
    Position=0, Mandatory)] [string] $Name 
)

$sourcepath = "\\ps0992ntxfs001.DETNSW.WIN\Citrix_User_Data\HomeFolder\sajboediman\Documents\repos_vs\scripts\powershell\$Name.psm1"
$modpath = $env:PSModulePath
$psmodpaths = $modpath.Split(";") | Where-Object {$_ -match "\\modules"}
foreach($psmodpath in $psmodpaths) {
$destinationpath = "$psmodpath\$Name\$Name.psm1"
$modexist = Test-Path -Path $destinationpath
    if ($modexist -eq $true) {
        #write-output "Copy-Item -Path $sourcepath -Destination $destinationpath -Force -Confirm $false"
        Copy-Item -Path $sourcepath -Destination $destinationpath -Force
        Start-Sleep -Seconds 3
        Import-Module -Name $Name -Force
        Write-Output "`nModule $Name has been successfully updated`n"
    }
}
}