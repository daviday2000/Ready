function Invoke-DcDiag {
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


$AllDCDiags = @()
$DCs = ([System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()).sites
foreach ($DC in $DCs.servers) {
    Write-Host "Working on... $($DC.name)"
    $dcdiag_res = Invoke-DcDiag -DomainController $DC.name
    $AllDCDiags += $dcdiag_res
}

$AllDCDiags | Export-Csv -Path $PSScriptRoot\dcdiag_output.csv -NoTypeInformation
$AllDCDiags | fl | Out-String
$AllDCDiags | Out-GridView