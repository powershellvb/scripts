
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelinebyPropertyName=$true)]
        $ComputerName,
        [boolean] $nonzero = $false
    )

    begin {
    }

    process {
        foreach ($Computer in $ComputerName) {
            $Computer
            if ($nonzero -eq $true) {
                $things = Get-WmiObject -ComputerName $Computer -Class "win32_shadowstorage" -Property * |
                    Select-Object -Property PSComputerName, @{n='UsedSpace'; e={[math]::Round([double]$_.UsedSpace/1gb,1)}}, DiffVolume | Where-Object UsedSpace -gt 0
            }
            else {
                $things = Get-WmiObject -ComputerName $Computer -Class "win32_shadowstorage" -Property * |
                    Select-Object -Property PSComputerName, @{n='UsedSpace'; e={[math]::Round([double]$_.UsedSpace/1gb,1)}}, DiffVolume
            }

            $cimss = New-CimSession -ComputerName $Computer

            foreach ( $thing in $things) {
                $diffvol = $thing.DiffVolume
                $diffvolclean = $diffvol.replace("\\","\")
                $diffvolfinal = $diffvolclean.Substring($diffvolclean.IndexOf("\\"),($diffvolclean.Length - $diffvolclean.IndexOf("\\")) - 1)

                $drive = Get-Partition -CimSession $cimss | Select-Object DiskNumber, DriveLetter, @{n='VolumeID';e={
                  $_.AccessPaths | Where-Object { $_ -like '\\?\volume*' }
                }
                } | Where-Object { $_.VolumeID -like $diffvolfinal }
                $diskobjectproperties = @{
                    ComputerName = $thing.PSComputerName
                    DrvLetter = $drive.DriveLetter
                    SpaceUsed_GB = $thing.UsedSpace
                }
                New-Object psobject -Property $diskobjectproperties
            }
            Write-Output ""
        }
    }

    end {
    }
