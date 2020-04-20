
#Connect to Rubrik brik
$cred = Get-Credential -Message 'Use PROD SA account'

Connect-Rubrik -Server ps0991brik1000.nsw.education -Credential $cred #-Username sajboediman

#locate database ID - the database that you want to restore

$sourcehost = "PW0991SQP008N1.DETNSW.WIN"
$sourceinstance = ""
$sourceagname = "pw0000sqp008a1\"
$sourcedbname = "dba_rubrik"

$sourceclusterid = Get-RubrikHost -Hostname $sourcehost | Select-Object primaryclusterid

$sourcedbdetails = Get-RubrikDatabase -ServerInstance $sourceagname -PrimaryClusterID $sourceclusterid.primaryClusterId -Name $sourcedbname -DetailedObject #| select id #| select name, primaryclusterid, isinavailabilitygroup, copyonly, slaassignment


#Get the list of snapshots (backups)
Get-RubrikDatabase -ServerInstance $sourceagname -PrimaryClusterID $sourceclusterid.primaryClusterId -Name $sourcedbname | Get-RubrikSnapshot |Where-Object {$_.Date -GT '2019-08-20'}

#Get the latest recovery point
get-date $sourcedbdetails.latestRecoveryPoint
#or
Get-RubrikDatabase -ServerInstance $sourceagname -PrimaryClusterID $sourceclusterid.primaryClusterId -Name $sourcedbname | Get-RubrikSnapshot -Latest

#Mount database to get the details
New-RubrikDatabaseMount -id $sourcedbdetails.id -targetInstanceId $sourcedbdetails.instanceId -mountedDatabaseName 'BAR-LM' -recoveryDateTime (Get-date $sourcedbdetails.latestRecoveryPoint)

#$targetfiles = @()
#
#$targetfiles += @{logicalName='synergy_mrds';exportPath='D:\MSSQL\MSSQL14.MV_HCI_TEST1\MSSQL\DATA\'}
#$targetfiles += @{logicalName='synergy_mrds_log';exportPath='L:\MSSQL\MSSQL14.MV_HCI_TEST1\MSSQL\Log\'}


#Export-RubrikDatabase -id $sourcedbdetails.id -targetInstanceId MssqlInstance:::11a6078e-f470-43f1-a7a9-84b270eea2b1 -finishRecovery -RecoveryDateTime 2019-08-26T23:39:02.000Z -targetDatabaseName ag_test_uat -targetFilePaths $targetfiles

#Export-RubrikDatabase -id $db.id -recoveryDateTime (Get-Date (Get-RubrikDatabase $db).latestRecoveryPoint) -targetInstanceId $db2.instanceId -targetDatabaseName 'BAR_EXP' -targetFilePaths $targetfiles -maxDataStreams 1

Disconnect-Rubrik -Confirm:$false

