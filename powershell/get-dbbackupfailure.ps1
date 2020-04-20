param(
    [string[]] $ComputerName
)

[object[]] $lognames = ""

foreach($Computer in $ComputerName){
    $ss = New-PSSession -ComputerName $Computer

    $lognames = Invoke-Command -Session $ss -ScriptBlock { 
                    Get-ChildItem 'C:\Program Files\VERITAS\NetBackup\logs\user_ops\mssql\logs' | Where-Object {$_.LastWriteTime -gt (Get-Date).AddDays(-1)} | Sort-Object LastWriteTime -Descending | Select-Object name,LastWriteTime 
               }

    if (($lognames.Count) -gt 0) {
        foreach($logname in $lognames) {
            $createtime = ($logname.LastWriteTime).DateTime
            $filename = $logname.Name.Replace("C:\","c$\")
            $fullpath = "\\$Computer\c$\Program Files\VERITAS\NetBackup\logs\user_ops\mssql\logs\$filename"
            get-content $fullpath  | ForEach-Object { 
                if($_ -match "INF - Policy name") {$script:policystr = $_}
                elseif ($_ -match "SQLINSTANCE") {$script:instancename = $_}
                }
            $policynames = $script:policystr.SubString( $script:policystr.length - ($script:policystr.LastIndexOf("=") - 2),$script:policystr.LastIndexOf("=") - 2 )
        
            $strresult = select-string -Path $fullpath -pattern "> operations failed." -context 0, 5
            
            $strresult | ForEach-Object { if( -NOT ($_ -match "<0> operations failed.")) {
                    Write-Output ""  
                    Write-Output "Backup for $Computer $script:instancename on $createtime"
                    Write-Output "Backup Policy: $script:policynames"
                    Write-Output "Backup result:"
                    Write-Output $strresult.Line
                    Write-Output $strresult.Context.PostContext
                    Write-Output ""
                } #if
            } #foreach %   
        
            $strresult | ForEach-Object { if( $_ -match "<0> operations failed." ) { $nofailure = $nofailure + 1 }}            
        } #foreach $logname
    
        if ($lognames.Count -eq ($nofailure)) {
            Write-Output "No Failures"
            Write-Output ""
        } 

    } #if $logname > 0
    else
    {
        write-host 'No files found'
    }
} #foreach computer
