<# 
.SYNOPSIS
Gets the CDP information from a computer.

.DESCRIPTION
Attempts to get the CDP information from a computer.  It automatically downloads tcpdump.exe if it's not already on a computer.

.PARAMETER DeviceNumber
Alias: dn

The device number available in tcpdump to listen on.  If not specified, it will list the available devices from tcpdump.

.PARAMETER ComputerName
Alias: cn

Specifies the computer to run on.  If not specified, will run on the local computer.

.EXAMPLE
    Get-CDPInfo.ps1 -ComputerName remotecomputername
    Please select a device number:
    1.\Device\PssdkLoopback (PSSDK Loopback Ethernet Emulation Adapter)
    2.\Device\NdisWanBh (WAN Miniport (Network Monitor))
    3.\Device\{F03D74ED-4868-4396-8F40-7CBC6E794F24} (DW1530 Wireless-N WLAN Half-Mini Card)
    4.\Device\{33BD9CF9-E3BB-40C6-82C0-50BBA92CEF57} (Intel(R) 82579LM Gigabit Network Connection)
    NotSpecified: (:String) [], RemoteException
        + CategoryInfo          : NotSpecified: (:String) [], RemoteException
        + FullyQualifiedErrorId : NativeCommandError
        + PSComputerName        : app01admtest2
 
    *******************************************************************
    **                                                               **
    **         Tcpdump v4.5.1 (Nov 20, 2013) for Windows             **
    **    Win98/ME/NT4/2000/XP/2003/Vista/2008/Win7/Win8/Win2012     **
    **                                                               **
    **      built with Microolap Packet Sniffer SDK v6.1 and         **
    **   Microolap WinPCap to Packet Sniffer SDK migration module.   **
    **                                                               **
    **                  (c) Microolap Technologies,                  **
    **                  Khalturin A.P. & Naumov D.A.                 **
    **                   http://www.microolap.com                    **
    **                                                               **
    **                         Trial license.                        **
    **                                                               **
    *******************************************************************

First, query the remote machine for what devices are available to it, and then rerun the command with one of the device numbers specified above (we'll user #4):

    C:\PS>Get-CDPInfo.ps1 4 -ComputerName app01admtest2
    16:50:34.414268 CDPv2, ttl: 180s, checksum: 692 (unverified), length 455
	    Device-ID (0x01), length: 23 bytes: 'APPAS5.dc.convergys.com'
	    Version String (0x05), length: 247 bytes: 
	      Cisco IOS Software, C3750 Software (C3750-IPSERVICESK9-M), Version 12.2(55)SE9, RELEASE SOFTWARE (fc1)
	      Technical Support: http://www.cisco.com/techsupport
	      Copyright (c) 1986-2014 by Cisco Systems, Inc.
	      Compiled Mon 03-Mar-14 22:45 by prod_rel_team
	    Platform (0x06), length: 18 bytes: 'cisco WS-C3750-48P'
	    Address (0x02), length: 13 bytes: IPv4 (1) 10.129.1.49
	    Port-ID (0x03), length: 18 bytes: 'FastEthernet4/0/33'
	    Capability (0x04), length: 4 bytes: (0x00000028): L2 Switch, IGMP snooping
	    Protocol-Hello option (0x08), length: 32 bytes: 
	    VTP Management Domain (0x09), length: 8 bytes: 'Appleton'
	    Native VLAN ID (0x0a), length: 2 bytes: 4
	    Duplex (0x0b), length: 1 byte: full
	    ATA-186 VoIP VLAN request (0x0e), length: 3 bytes: app 1, vlan 11
	    AVVID trust bitmap (0x12), length: 1 byte: 0x01
	    Management Addresses (0x16), length: 13 bytes: IPv4 (1) 10.129.1.49
	    unknown field type (0x1a), length: 12 bytes: 
	      0x0000:  0000 0001 0000 0000 ffff ffff

.NOTES
Author: Rene Horn, the.rhorn@gmail.com
Version: 0.3
Known issue:
    - Does no parsing of CDP information.  Just outputs it as it gets it from tcpdump.
    - Does not check if the device number specified is valid for tcpdump (although tcpdump should just error out anyway).

#>

param(
    [parameter(Mandatory=$false)]
    [alias("dn")]
    [int]$DeviceNumber,
    [parameter(Mandatory=$false)]
    [alias("cn")]
    [string]$ComputerName="."
)

$run_tcpdump = {

    param($DeviceNumber)

    function Unzip-File($file, $destination, $filter)
    {
        $shell = New-Object -ComObject Shell.Application
        $zip = $shell.NameSpace($file)
        foreach($item in $zip.items()) {
            if ($item.Path -imatch $filter) {
                $shell.NameSpace($destination).CopyHere($item)
            }
        }
    }

    function Get-TCPDump
    {
        $tcpdump_zip = "$env:SystemRoot\temp\tcpdump.zip"
        $tcpdump_url = "https://www.microolap.com/downloads/tcpdump/tcpdump_trial_license.zip"
        if (3 -le $PSVersionTable.PSVersion.Major) {
            Invoke-WebRequest -Uri $tcpdump_url -OutFile $tcpdump_zip
        } else {
            $downloader = New-Object System.Net.WebClient
            $downloader.DownloadFile($tcpdump_url, $tcpdump_zip)
        }
        Unzip-File $tcpdump_zip "$env:systemroot\system32" "tcpdump.exe"
        Remove-Item $tcpdump_zip
    }

    try {
        $tcpdump_exe = (Get-Command tcpdump -ErrorAction Stop).Path
    } catch {
        Get-TCPDump
    }

    if ($DeviceNumber -eq 0) {
        Write-Output "Please select a device number:"
        & tcpdump.exe -D | where {$_ -match '^[1-9]+\.\\Device\\{[^}]+}'} 
        Exit -2
    }
    $tcpdump_args = @("-i","$DeviceNumber","-nn","-v","-s","1500","-c","1",'"(ether[12:2]==0x88cc or ether[20:2]==0x2000)"')
    $tcpdump_stdout = "$env:SystemRoot\temp\tcpdump_stdout.txt"
    $tcpdump_stderr = "$env:SystemRoot\temp\tcpdump_stderr.txt"
    $tcpdump_proc = Start-Process -NoNewWindow -FilePath $tcpdump_exe -ArgumentList $tcpdump_args -PassThru -RedirectStandardOutput $tcpdump_stdout -RedirectStandardError $tcpdump_stderr
    for ($i = 60; $i -ge 1; $i--) {
        if ($tcpdump_proc.HasExited) {
            break
        }
        Write-Progress -Activity "Watching the packets..." -Status "Waiting for CDP packet" -SecondsRemaining $i
        Start-Sleep -Seconds 1
    }

    if ($tcpdump_proc.HasExited) {
        Get-Content $tcpdump_stdout
    } else {
        $tcpdump_proc.Kill()
        Write-Error "CDP packets not detected!"
    }
    Remove-Item $tcpdump_stdout
    Get-Content $tcpdump_stderr | Write-Warning
    Remove-Item $tcpdump_stderr
}

Invoke-Command -ComputerName $ComputerName -ScriptBlock $run_tcpdump -ArgumentList $DeviceNumber
