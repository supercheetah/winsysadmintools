<#
.SYNOPSIS
Check the last logon times of users in an OU.

.DESCRIPTION
It will bring up an Active Directory GUI browser to select the OU where it will retrieve the users list to find the last time they logged in.
#>
# author: Rene Horn, the.rhorn@gmail.com
# requirements:

$script_path = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module ActiveDirectory
Import-Module -Verbose "$script_path\lib\BrowseAD.psm1"

$OU = Browse-AD

$users = Get-ADUser -Filter * -SearchBase $OU -Properties lastLogon

[datetime]$epoch = "1970-01-01T00:00:00Z"

$last_logons_accum = @()

$i = 1
foreach ($user in $users) {
    Write-Progress -Activity "Querying user..." -Status $user.Name -PercentComplete (($i++/$users.Count)*100)
    if ($user.lastLogon -ne $null) {
        $last_logon_time = [datetime]::FromFileTime($user.lastLogon)
    } else {
        $last_logon_time = $epoch
    }
    $last_logons_accum += [pscustomobject]@{UserName=$user.SamAccountName; Name=$user.Name; LastLogonDate=$last_logon_time}
}

$last_logons_accum | ogv