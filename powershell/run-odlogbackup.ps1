
[String[]] $databases = "AGTest" #"monitor" #
[String]$source_host = "dw0991sqp102n1.nsw.education" #"qw0992sqs102n1.detnsw.win" #
[String]$source_inst = "DLRELTEST1" #"PV_Q2U" #
[String]$agname = "dw0000sqp102a19"
[String]$cmsserver = "pw0000sqlpe126.detnsw.win"
#[String]$Rubrik_server = "S" #"U" #

Function Get-Remotemodule {
    param (
    [String] $remotename,
    [String] $modname
    )
    $biterr=0
    Try {
        $cmsses = New-PSSession -ComputerName $remotename -ErrorAction Stop
            
        $remmod = Get-Module -ListAvailable -Name $modname -PSSession $cmsses -ErrorAction Stop
        if ($remmod) {
            Import-Module -Name $modname -PSSession $cmsses -DisableNameChecking -Force -ErrorAction SilentlyContinue
        } else {
            $biterr=1
        }
    } Catch {
        $biterr=1
    }
    if ($biterr -eq 1) {Get-PSSession | Remove-PSSession}
    Write-Output $biterr
}

$rubrikmodule = Get-Module -ListAvailable -Name rubrik
if ($rubrikmodule) { 
    Import-Module -Name rubrik
} else {
    $result1 = Get-Remotemodule -modname rubrik -remotename $cmsserver
    if ($result1 -eq 1) {
        Write-Output "Failed to import rubrik module"        
        Exit(1)
    }
}

$vaultmodule = Get-Module -ListAvailable -Name Zyborg.Vault
if ($vaultmodule) { 
    Import-Module -Name Zyborg.Vault
} else {
    $result2 = Get-Remotemodule -modname Zyborg.Vault -remotename $cmsserver
    if ($result2 -eq 1) {
        Write-Output "Failed to import Zyborg.Vault module"
        Exit(1)
    }
} 
 
try {     
    $vault = Read-VltData -path it_infraserv_database_sql/detnsw -VaultProfile detnswtoken
    
    $cred = New-Object System.Management.Automation.PSCredential ($vault["rubrik_user"],$(ConvertTo-SecureString $vault["rubrik_pass"] -AsPlainText -Force))

    #Get rubrik cert
    $ses = New-PSSession -ComputerName qw0991sqs103n1 -ErrorAction Stop # $source_host

    $cert = Invoke-Command -Session $ses -ScriptBlock {$certloc = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Rubrik Inc.\Backup Service" -Name "Trusted Certificate Path")."Trusted Certificate Path"; `
        New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certloc}
    $thumb = ($cert.Thumbprint).Substring(8,8)

    Switch ($thumb) {
    "7FB0731D" {#Write-Output "Unanderra"
                Connect-Rubrik -Server "ps0992brik1000.nsw.education" -Credential $cred -ErrorAction Stop > null}
    "4546FB71" {#Write-Output "Silverwater"
                Connect-Rubrik -Server "ps0991brik1000.nsw.education" -Credential $cred -ErrorAction Stop > null}
    default {Write-Output "Certificate is no recognised"}
    }
} catch {
    Write-Output "Failed to connect to Rubrik server"
    Exit(1)
}
Try {
    $sourcecluster = Get-RubrikHost -Hostname $source_host -ErrorAction Stop #-DetailedObject | Select-Object -Property *  # 

    $sourcedatabase = Get-RubrikDatabase -Name $databases -PrimaryClusterID $sourcecluster.primaryClusterId -AvailabilityGroupName $agname -ErrorAction Stop # $sourcedatabase | Select-Object -Property * #
    #$sourcedatabase = Get-RubrikDatabase -Name $databases -PrimaryClusterID $sourcecluster.primaryClusterId -Instance $source_inst -Hostname $source_host -ErrorAction Stop #-DetailedObject | Select-Object -Property * #
    
    if (($sourcedatabase | Measure-Object).Count -eq 1) {
        if (($($sourcedatabase.recoveryModel) -eq 'FULL') -or ($($sourcedatabase.isInAvailabilityGroup) -eq $true) ) {
            Write-Output "New-RubrikLogBackup -id $($sourcedatabase.id)"
        } else {
            Write-Output "Database $($sourcedatabase.name) recovery model is $($sourcedatabase.recoveryModel). No Tlog backup performed."
        }
    } else {
        Write-Output "Failed to retrive unique database record from rubrik"
        Exit(1)
    }
} Catch {
    Write-Output "Failed to generate t-log backup request"
    Exit(1)
}

Disconnect-Rubrik -Confirm:$false | Out-Null

Get-PSSession | Remove-PSSession

 