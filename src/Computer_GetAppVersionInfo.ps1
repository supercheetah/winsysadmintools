<#
.SYNOPSIS
Check the version information on various installed applications.

.DESCRIPTION
It will bring up an Active Directory GUI browser to select the OU where it will retrieve the users list to find the last time they logged in.
#>
# author: Rene Horn, the.rhorn@gmail.com
# requirements:

Param(
    [parameter(Mandatory=$false)]
    [alias("OrganizationalUnit","DistinguishedName","DN","SearchBase","SB")]
    [string]$OU,
    [parameter(Mandatory=$false)]
    [alias("Group")]
    [string]$ADGroup,
    [parameter(Mandatory=$false)]
    [string]$Domain="$((Get-ADDomainController).Domain)",
    [parameter(Mandatory=$false)]
    [alias("File")]
    [string]$OutputFile="output.csv",
    [parameter(Mandatory=$false)]
    [alias("Offline")]
    [string]$OfflineFile="offline.csv"
)

$script_path = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module -Verbose "$script_path\lib\TestComputerIsOff.psm1"

$DC = (Get-ADDomainController -server $Domain).HostName
$Computers = @()
if (![string]::IsNullOrEmpty($OU)) {
    $Computers = (Get-ADComputer -filter * -SearchBase $OU -server $DC).DNSHostName
} elseif (![string]::IsNullOrEmpty($ADGroup)) {
    $Computers = (Get-ADGroupMember -Identity $ADGroup).Name
} else {
    Write-Error "Must supply either OU or AD Group."
    Exit -1
}

$colOutput = @()
$offlineComputers = @()

$applications = @{
# if there are apps that you don't need to check, just comment them out here
# add more lines for other apps not already listed
                  "Internet Explorer" = @("Program Files\Internet Explorer\iexplore.exe")
                  ;"Mozilla Firefox"   = @("Program Files (x86)\Mozilla Firefox\firefox.exe",
                                        "Program Files\Mozilla Firefox\firefox.exe")
                  ;"Chrome Frame"      = @("Program Files (x86)\Google\Chrome Frame\Application\chrome.exe")
                 }
                  
Function Get-NameValue($ContentInput, $Filter, $offset = 2, $delimeter = ':')
{
    $buffer = $ContentInput | Where { $_ -like $Filter }
    $buffer = $buffer.Substring($buffer.IndexOf($delimeter) + $offset)
    $buffer
}

Function Get-AppVersions($ComputerName, $objOutput)
{
    foreach ($app in $applications.GetEnumerator() ) {
        $versions = @()
        foreach ($location in $app.value) {
            if ( ! (Test-Path "\\$ComputerName\c$\$location") ) {
                Write-Warning "$location does not exist on $ComputerName, skipping..."
                $versions += "N/A"
                Continue
            }
            $versions += (Get-Item "\\$ComputerName\c$\$location").VersionInfo.FileVersion
        }
        $objOutput | Add-Member -Type NoteProperty -Name $app.key -Value ($versions -join ',').Trim(',')
    }
}

Function Get-JavaVersions($ComputerName, $objOutput)
{ # accommadating that there could be multiple Java versions, and that the version info isn't in java.exe
    $javaLocations = @("Program Files (x86)\Java",
                       "Program Files\Java")
    $versions = @()
    foreach($location in $javaLocations) {
        if ( ! (Test-Path "\\$ComputerName\c$\$location") ) {
            Write-Warning "$location does not exist on $ComputerName, skipping..."
            $versions += "N/A"
            Continue
        }
        $javaFiles = (Get-ChildItem -Recurse -Path "\\$ComputerName\c$\$location" -Include "java.exe").PSPath | Convert-Path
        foreach($jFile in $javaFiles) {
            $version = (Get-Item $jFile).VersionInfo.ProductVersion
            if ($null -eq $version) {
               $version = Split-Path -Leaf (Split-Path (Split-Path $jFile))
            }
            $versions += $version
        }
    }
    $objOutput | Add-Member -Type NoteProperty -Name "Java Versions" -Value ($versions -join ',').Trim(',')
}

ForEach($Computer in $Computers) {
    if( Test-ComputerIsOff($Computer) ) {
        Write-Host "Adding $Computer to offline list"
        $offlineComputers += $Computer
        continue
    }

    $objOutput = New-Object System.Object
    $objOutput | Add-Member -type NoteProperty -name Computer -value $Computer
    Get-AppVersions $Computer $objOutput
    Get-JavaVersions $Computer $objOutput

    $colOutput += $objOutput
}

$colOutput | Export-Csv -NoTypeInformation $OutputFile
$offlineComputers > $OfflineFile

$colOutput | ogv