function Get-DcDiag {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainController
    )
    $dcdiag_res = New-Object Object
    $dcdiag_res | Add-Member -Type NoteProperty -Name "DC" -Value $DomainController
    $result = dcdiag /s:$DomainController
    $result_all = $result | select-string -pattern '\. (.*) \b(passed|failed)\b test (.*)' 
    $result_all | foreach {
        $dcdiag_res | Add-Member -Type NoteProperty -Name $($_.Matches.Groups[3].Value) -Value $($_.Matches.Groups[2].Value) -force
    }
    $dcdiag_res
}
function Get-Repadmin {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainController
    )
    $repadmin = @()
 
    $rep = (Invoke-Command $DomainController -ScriptBlock { repadmin /showrepl /repsto /csv | ConvertFrom-Csv })
 
    $rep | ForEach-Object {
     
        # Define current loop to variable
        $r = $_
 
        # Adding properties to object
        $REPObject = New-Object PSCustomObject
        $REPObject | Add-Member -Type NoteProperty -Name "Destination DCA" -Value $r.'destination dsa'
        $REPObject | Add-Member -Type NoteProperty -Name "Source DSA" -Value $r.'source dsa'
        $REPObject | Add-Member -Type NoteProperty -Name "Source DSA Site" -Value $r."Source DSA Site"
        $REPObject | Add-Member -Type NoteProperty -Name "Last Success Time" -Value $r.'last success time'
        $REPObject | Add-Member -Type NoteProperty -Name "Last Failure Status" -Value $r.'Last Failure Status'
        $REPObject | Add-Member -Type NoteProperty -Name "Last Failure Time" -Value $r.'last failure time'
        $REPObject | Add-Member -Type NoteProperty -Name "Number of failures" -Value $r.'number of failures'
 
        # Adding object to array
        $repadmin += $REPObject
 
    }
    $repadmin #| ft  | Out-String
}
function Check-DcExist {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainController
    )

    # Checking if DomainController exist
    $DCErrors = @()
    Try {
        $DC = Get-ADDomainController -Identity $DomainController -ErrorAction Stop
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
    }

    if ($ErrorMessage) {
        Write-Host "Error: " -NoNewline -ForegroundColor Yellow
        Write-Host $ErrorMessage
        $obj = [PSCustomObject]@{
            DCname       = $DomainController
            ErrorMessage = $ErrorMessage
        }
        $DCErrors += $obj
    }
    else {
 
        # Testing connection
        If (Test-Connection -ComputerName $DomainController -BufferSize 16 -Count 1 -ea 0 -Quiet) {
            $status = $true
        }
        Else {
            $status = $false
        }
    }
    $DCErrors,$status
}
function Invoke-DcHealthcheck {
    $AllDCDiags = @()
    $repadmin = @()
    $AllDcErrors = @()
    $DCs = ([System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()).sites
    foreach ($DC in $DCs.servers) {
        Write-Host "Working on... $($DC.name)" -ForegroundColor Yellow
        $DCErrors,$status = Check-DcExist -DomainController $DC.Name
        if ($DCErrors) {
            $AllDcErrors += $DCErrors
        }
        if ($status) {
            $dcdiag_res = Get-DcDiag -DomainController $DC.Name
            $dcdiag_res
            $AllDCDiags += $dcdiag_res
            $repadmin_res = Get-Repadmin -DomainController $DC.Name
            $repadmin_res | ft -AutoSize
            $repadmin += $repadmin_res
        }
    }
    $LogFileName = "_output-$(Get-Date -UFormat "%Y-%m-%d_%H-%m-%S").csv"
    $AllDCDiags | Export-Csv -Path $PSScriptRoot\dcdiag_$LogFileName -NoTypeInformation
    $AllDCDiags | Out-GridView

    $repadmin | Export-Csv -Path $PSScriptRoot\repadmin_$LogFileName -NoTypeInformation
    $repadmin | Out-GridView
    if ($AllDcErrors) {
        $AllDcErrors | Export-Csv -Path $PSScriptRoot\AllDcErrors_$LogFileName -NoTypeInformation
        $AllDcErrors | ft -AutoSize
        $AllDcErrors | Out-GridView
    }
}
Invoke-DcHealthcheck