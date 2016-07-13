<#
.SYNOPSIS
Gets the logon history of a given machine.

.DESCRIPTION
By default, it will check the logon (both login and logout) history of the machine it's run on, but given the the computer name, it can retrieve it from a remote machine as well.
#>
# author: Rene Horn, the.rhorn@gmail.com
# requirements:
param(
    [alias("CN")]
    $ComputerName="localhost",
    [alias("Newest")]
    $Depth=0
)

$UserProperty = @{n="User";e={(New-Object System.Security.Principal.SecurityIdentifier $_.ReplacementStrings[1]).Translate([System.Security.Principal.NTAccount])}}
$TypeProperty = @{n="Action";e={if($_.EventID -eq 7001) {"Logon"} else {"Logoff"}}}
$TimeProperty = @{n="Time";e={$_.TimeGenerated}}
$MachineNameProperty = @{n="MachinenName";e={$_.MachineName}}

foreach ($computer in $ComputerName) {
    if (0 -lt $Depth) {
        Get-EventLog System -Source Microsoft-Windows-Winlogon -ComputerName $computer -Newest $Depth | select $UserProperty,$TypeProperty,$TimeProperty,$MachineNameProperty
    } else {
        Get-EventLog System -Source Microsoft-Windows-Winlogon -ComputerName $computer | select $UserProperty,$TypeProperty,$TimeProperty,$MachineNameProperty
    }
}