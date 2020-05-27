[cmdletbinding()]
[String] $databases = "LogBackupTestDb"
[String]$source_host = "dw0992sqmgmth1"
[String]$source_inst = "CONTROL_POINT1"
[String]$agname = "NoAG"
[String]$cmsserver = "NoMSX"
[String]$srvdomain = $env:USERDNSDOMAIN
[bool]$remote = $false

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
	throw $biterr
}

Function Get-VaultData {
    param (
	[String] $Vault_Key,
	[String] $domainname
	)

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
    $Vault_Full_Address = "https://vault.nsw.education/v1/it_infraserv_database_sql/data/$domainname"
    $Vault_SavedTokenPath = "C:\temp\token.dat"
    $Key = Get-Content "C:\temp\token.key"
    $ErrorActionPreference = 'Stop'

Get-ChildItem -Path $env:HOMEPATH

$cmsFilePath = '\\dw0992sqmgmth1\c$\Users\srvSqlAgent\.vault-profiles'
$vaultfolder = "$env:HOMEPATH\.vault-profiles"

if ((Test-Path -Path $vaultfolder) -ne $true) {
    New-Item -Path $env:HOMEPATH -Name ".vault-profiles" -ItemType Directory | Out-Null
    Get-Item $vaultfolder -Force | ForEach-Object { $_.Attributes = $_.Attributes -bor "Hidden" }
    Copy-Item -Path $cmsFilePath\token.dat,$cmsFilePath\token.key -Destination $vaultfolder -Force
}

if ((Test-Path -Path $vaultfolder\token.dat) -ne $true) {
    Copy-Item -Path $cmsFilePath\token.dat -Destination $vaultfolder -Force
}

if ((Test-Path -Path $vaultfolder\token.key) -ne $true) {
    Copy-Item -Path $cmsFilePath\token.key -Destination $vaultfolder -Force
}

    #Get Vault Token from locally encrypted dat file, otherwise it came from Param block
    if ($Vault_SavedTokenPath) {
         $token = Get-Content $Vault_SavedTokenPath | ConvertTo-SecureString -Key $Key 
        [ValidateNotNullOrEmpty()]$Vault_Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($token))
    }

    
    #Get the Value that is associated with $Vault_Key from $Vault_Full_Address
    $InvokeRestMethodParams = @{
        Uri = $Vault_Full_Address
        Headers = @{"X-Vault-Token"="$Vault_Token"}
    }

    $value = (Invoke-RestMethod @InvokeRestMethodParams).data.data | Select-Object -ExpandProperty $Vault_Key

    if ($value) {
        Write-Output $value
    } else {
        throw "Error when obtaining value from vault"
        Exit(1)
    }
}

$rubrikmodule = Get-Module -ListAvailable -Name rubrik
if ($rubrikmodule) { 
	Import-Module -Name rubrik
} else {
	throw "Failed to import rubrik module"        
	Exit(1)
}


try {  
    $rubrikuser = Get-VaultData -Vault_Key "rubrik_user" -domainname "detnsw"
    $rubrikpass = Get-VaultData -Vault_Key "rubrik_pass" -domainname "detnsw"
    
	$cred = New-Object System.Management.Automation.PSCredential ($rubrikuser,$(ConvertTo-SecureString $rubrikpass -AsPlainText -Force))

	#Get rubrik cert
	if ($remote -eq $true) {
	    $ses = New-PSSession -ComputerName $source_host -ErrorAction Stop

	    $cert = Invoke-Command -Session $ses -ScriptBlock {$certloc = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Rubrik Inc.\Backup Service" -Name "Trusted Certificate Path")."Trusted Certificate Path"; 
		    New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certloc}
    } else {
        $certloc = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Rubrik Inc.\Backup Service" -Name "Trusted Certificate Path")."Trusted Certificate Path"
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certloc
    }
	$thumb = ($cert.Thumbprint).Substring(8,8)

	Switch ($thumb) {
	"7FB0731D" {#Write-Output "Unanderra"
				Connect-Rubrik -Server "ps0992brik1000.nsw.education" -Credential $cred -ErrorAction Stop | Out-Null}
	"4546FB71" {#Write-Output "Silverwater"
				Connect-Rubrik -Server "ps0991brik1000.nsw.education" -Credential $cred -ErrorAction Stop | Out-Null}
	default {throw "Certificate is not recognised"
		Exit(1)}
	}
} catch {
	throw "Failed to connect to Rubrik server"
	Exit(1)
}

Try {
	$source_host = "$source_host.$srvdomain"

	$sourcecluster = Get-RubrikHost -Hostname $source_host -ErrorAction Stop

	$sourcedatabase = Get-RubrikDatabase -Name $databases -PrimaryClusterID $sourcecluster.primaryClusterId -Instance $source_inst -Hostname $source_host -ErrorAction Stop

	if (($sourcedatabase | Measure-Object).Count -eq 1) {
		if (($($sourcedatabase.recoveryModel) -eq "FULL") -or ($($sourcedatabase.isInAvailabilityGroup) -eq $true) ) {
			New-RubrikLogBackup -id $($sourcedatabase.id)
		} else {
			Write-Output "Database $($sourcedatabase.name) recovery model is $($sourcedatabase.recoveryModel). No Tlog backup performed."
		}
	} else {
		throw "Failed to retrive unique database record from rubrik"
		Exit(1)
	}
} Catch {
	throw "Failed to generate t-log backup request"
	Exit(1)
}

Disconnect-Rubrik -Confirm:$false | Out-Null

Get-PSSession | Remove-PSSession
