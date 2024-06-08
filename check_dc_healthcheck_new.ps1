function Get-DCHealth {
    [CmdletBinding()]

    # Parameters used in this function
    param (
        [Parameter(
            Position = 0, 
            Mandatory = $true, 
            HelpMessage = "Provide server name", 
            ValueFromPipeline = $true)
        ] 
        $Server,
 
        [Parameter(
            Position = 1, 
            Mandatory = $true, 
            HelpMessage = "Select DC health check (DCDIAG, Repadmin)", 
            ValueFromPipeline = $true)
        ]
        [ValidateSet("DCDIAG", "Repadmin")]
        [string]
        $Check
    ) 
 
    # Checking if server exist
    $AllDCErrors = @()
    Try {
        $DC = Get-ADDomainController -Identity $Server -ErrorAction Stop
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
    }

    if ($ErrorMessage) {
        Write-Host "Error: " -NoNewline -ForegroundColor Yellow
        Write-Host $ErrorMessage
        $obj = [PSCustomObject]@{
            DCname       = $Server
            ErrorMessage = $ErrorMessage
        }
        $AllDCErrors += $obj
    }
    else {
 
        # Testing connection
        If (!(Test-Connection -ComputerName $Server -BufferSize 16 -Count 1 -ea 0 -Quiet)) {
            Write-Warning   "Failed to connect to $Server"
        }
        Else {
            If ($Check -eq "DCDIAG") {
                $AllDCDiags = @()
                Write-Host "DCDIAG results for"$Server":" -ForegroundColor Yellow  -NoNewline
                             
                $Dcdiag = (Dcdiag.exe /s:$Server) -split ('[\r\n]')
                $Results = New-Object Object
                $Results | Add-Member -Type NoteProperty -Name "ServerName" -Value $Server
                $Dcdiag | % { 
             
                    Switch -RegEx ($_) { 
                        "Starting" { $TestName = ($_ -Replace ".*Starting test: ").Trim() } 
                        "passed test|failed test" { 
                            If ($_ -Match "passed test") {  
                                $TestStatus = "Passed" 
                            }  
                            Else {   
                                $TestStatus = "Failed" 
                            } 
                        } 
                    } 
             
                    If ($TestName -ne $Null -And $TestStatus -ne $Null) { 
                        $Results | Add-Member -Name $("$TestName".Trim()) -Value $TestStatus -Type NoteProperty -force
                        $TestName = $Null; $TestStatus = $Null      
                    } 
                }       
                $AllDCDiags += $Results
                $AllDCDiags # | fl | Out-String
            }
            ElseIf ($Check -eq "Repadmin") {
                $repadmin = @()
 
                Write-Host "REPADMIN results for"$Server":"  -ForegroundColor Yellow -NoNewline
                Write-Host " "
                $rep = (Invoke-Command $Server -ScriptBlock { repadmin /showrepl /repsto /csv | ConvertFrom-Csv })
 
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
        }
    }
    $AllDCErrors | ft  | Out-String
}
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
$repadmin = @()
$DCs = ([System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()).sites
foreach ($DC in $DCs.servers) {
    $dcdiag = $null
    $repadm = $null
    Write-Host "Working on... $($DC.name)"
    $dcdiag_res = Invoke-DcDiag -DomainController $DC.name
    $dcdiag_res
    $AllDCDiags += $dcdiag_res

    $repadm = Get-DCHealth -Server $DC.name -Check Repadmin
    $repadm | ft  | Out-String
    $repadmin += $repadm
}
$AllDCDiags | Export-Csv -Path $PSScriptRoot\dcdiag_output.csv -NoTypeInformation
$AllDCDiags | Format-List | Out-String
$AllDCDiags | Out-GridView

$repadmin | Export-Csv -Path $PSScriptRoot\dcdiag_output.csv -NoTypeInformation
