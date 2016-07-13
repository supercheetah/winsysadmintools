<#
.SYNOPSIS
Gets the time and date of the last the a machine was rebooted.

.DESCRIPTION
By default, it will check the last reboot time of the machine it's run on, but given the name of another computer, it will reach out to it remotely to get that information.
#>
# author: Rene Horn, the.rhorn@gmail.com
# requirements:

param (
    [parameter(Mandatory=$false)]
    [alias("cn")]
    [string]$ComputerName="."
)

$get_last_boot_time = {
    # shamelessly stolen from here: http://blogs.technet.com/b/heyscriptingguy/archive/2013/03/27/powertip-get-the-last-boot-time-with-powershell.aspx
    if (3 -le $PSVersionTable.PSVersion.Major) {
        Get-CimInstance -ClassName win32_operatingsystem | select csname, lastbootuptime
    } else {
        Get-WmiObject win32_operatingsystem | select csname, @{LABEL='LastBootUpTime';EXPRESSION={$_.ConverttoDateTime($_.lastbootuptime)}}
    }
}

Invoke-Command -ComputerName $ComputerName -ScriptBlock $get_last_boot_time