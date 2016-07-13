<#
.SYNOPSIS
This script gets MAC address tables from Cisco routers/switches running IOS using the SSH protocol.

.DESCRIPTION
The script uses the Plink (command line version of PuTTY, http://www.chiark.greenend.org.uk/~sgtatham/putty/download.html)
 to get the output of the command "show mac address-table" and put into a object array (i.e. table) that is outputted to
Out-GridView, and can optionally be saved to a CSV file.
#>
# author: Rene Horn, the.rhorn@gmail.com
# requirements:
#   at least PowerShell v3+
#   plink

param(
    [parameter(Mandatory=$false)]
    [alias("CN","Computer","Name","Switch","SwitchName")]
    [string[]]$ComputerName,
    [parameter(Mandatory=$false)]
    [alias("File","Path","List","SwitchListFile")]
    [string]$ComputerListFile,
    [parameter(Mandatory=$false)]
    [string]$SaveFile,
    [parameter(Mandatory=$false)]
    [switch]$NoGUI
)

[bool]$NoGUI = $NoGUI.IsPresent

if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Error "PowerShell 3.0 or higher is required!"
    Exit -1
}

function Get-PlinkPath()
{
    if(!($plink_exe = Get-Command plink.exe -ErrorAction SilentlyContinue)) {
        Write-Error "Can't find plink.exe!  Please install before using this."
        Exit -1
    } else {
        return $plink_exe.Path
    }
}

function Construct-ObjectFromHeader([string]$computer,[string[]]$headers,[string[]]$split_line)
{
    [pscustomobject]$tbl_object = New-Object psobject -Property @{"hostname"=$computer}
    for($i=0; $i -lt $headers.Count; $i++) {
        $tbl_object | Add-Member -MemberType NoteProperty -Name $headers[$i] -Value $split_line[$i]
    }
    return $tbl_object
}

function Parse-Output([string]$computer, [string[]]$output_raw, [string[]]$cmds)
{
    $output_iter = 0
    for (; $output_iter -lt $output_raw.Count; $output_iter++) {
        if ($output_raw[$output_iter] -match "^\S+>.*") {
            break
        }
    }

    if (($output_iter+5) -ge $output_raw.Count) {
        Write-Error "No output from $computer, skipping..."
        return $null
    }

    $output_iter+=3 # skip the line for "term len 0" and the first command line output

    $cmds_results_hash = @{}
    foreach($cmd in $cmds) {
        # we don't care about the first two lines of the output...
        # this regex split allows us to capture headers like "Mac Address"
        # TODO: a more complex table parser would be needed for other tables, e.g. for "show interface status"
        $line_split_re = "\s{2}\s*"
        $headers = [regex]::Split($output_raw[$output_iter++].Trim(), $line_split_re)
        $output_tbl = @()
        do {
            $output_tbl += Construct-ObjectFromHeader $computer $headers ([regex]::Split($output_raw[$output_iter].Trim(), $line_split_re))
        } while (($output_raw[++$output_iter] -notmatch "^\S+>.*") -and ($output_iter -lt $output_raw.Count))
        $cmds_results_hash[$cmd] = $output_tbl
        $output_iter+=1 # skip blank line after command
        if ($output_iter -ge $output_raw.Count) {
            Write-Error "Truncated output!"
            break
        }
    }
    return $cmds_results_hash
}

function Ask-ForHostKeyAccept([string]$host_key_err_msg)
{
    $split_string = $host_key_err_msg.Trim().Split("`n")
    $caption = "Accept host key?"
    $message = (@"
{0}
If you trust this host, click Yes to add the key to
PuTTY's cache and carry on connecting.
If you want to carry on connecting just once, without
adding the key to the cache, click No.
If you do not trust this host, click Cancel to abandon the
connection.
Store key in cache?
"@ -f [string]::Join("`n", $split_string[0..($split_string.Count - 2)]))

    $response = [System.Windows.Forms.MessageBox]::Show($message, $caption, "YesNoCancel", "Warning", "Button1", 0)
    if ($response -eq "Yes") {
        return 'y'
    } elseif ($response -eq "No") {
        return 'n'
    } else {
        return "`n"
    }
}

function New-PlinkSession([string]$computer, [string[]]$cisco_ios_cmds, [pscredential]$credentials, [string]$host_key_err_msg = $null)
{
    # returns: System.Diagnostics.Process for plink, StreamReader for its stdin, stdout, and async read variables for stdout and stderr, respectively
    # if this returns null, that means the host key was rejected
    $plink_exe = Get-PlinkPath

    # The process start info needs to be set up separately.
    # Creating a new System.Diagnostics.Process object, and setting up its StartInfo, and then starting it doesn't seem to work.
    # Also, calling plink directly here does not work properly, nor does using Start-Process.  The output always gets truncated if there's too much.
    # The reason seems to be that .NET has a buffer limit (http://www.codeducky.org/process-handling-net/) for stdin, stdout, and stderr, so they
    # need to be written to/read from asynchronously so that those streams will have some other buffer to use that don't have those limitations.
    $plink_proc_info = New-Object System.Diagnostics.ProcessStartInfo
    $plink_proc_info.FileName = $plink_exe
    $plink_proc_info.UseShellExecute = $false
    $plink_proc_info.RedirectStandardError = $true
    $plink_proc_info.RedirectStandardInput = $true
    $plink_proc_info.RedirectStandardOutput = $true
    $plink_proc_info.CreateNoWindow = $true
    # putting the arguments here to minimize the amount of time the password shows up in clear text in memory
    $plink_proc_info.Arguments = ('-v','-2','-pw {0} {1}@{2}' -f $credentials.GetNetworkCredential().Password, $credentials.GetNetworkCredential().UserName, $computer)
    $plink_proc = $null
    $host_key_accepted = $null
    if (([string]::IsNullOrEmpty($host_key_err_msg))) {
        $plink_proc_info.Arguments = '-batch ' + $plink_proc_info.Arguments
    } else {
        $host_key_accepted = (Ask-ForHostKeyAccept $host_key_err_msg)
        if ($host_key_accepted -eq "`n") {
            Write-Warning "Host key not accepted, skipping $computer..."
            return $null
        }
    }

    $plink_proc = [System.Diagnostics.Process]::Start($plink_proc_info)
    $plink_proc_info.Arguments = "" # for security reasons, blanking this out so there aren't so many copies of the password in clear text floating around in memory

    if (!([string]::IsNullOrEmpty($host_key_err_msg))) {
        $plink_proc.StandardInput.WriteLine("$host_key_accepted")
        # plink seems to need need a break after prompting for the host key
        # seems to randomly fail at just a one or two seconds pause, three seems safe
        Start-Sleep 3
    }
    
    return $plink_proc, [System.IO.StreamWriter]($plink_proc.StandardInput), $plink_proc.StandardOutput.ReadToEndAsync(), $plink_proc.StandardInput, $plink_proc.StandardError.ReadToEndAsync()
}

function Test-HostKeyIsCached([string]$plink_stderr_result)
{
    $err_split = $plink_stderr_result.Trim().Split("`n")
    return ($err_split[($err_split.Count - 1)].Trim() -notmatch "Connection abandoned.")
}

function Invoke-CiscoIOSCmds([string]$computer, [string[]]$cisco_ios_cmds, [pscredential]$credentials)
{
    $host_key_results_err = $null
    do {
        # PowerShell seems to lock stdin and stdout until the process exits, so we can't do anything with them until it exits.
        $plink_proc, $plink_stdin, $plink_stdout, $plink_stderr = New-PlinkSession $computer $cisco_ios_cmds $credentials $host_key_results_err
        if ($plink_proc -eq $null) {
            return $null
        }

        # We don't want to use WriteLine() here because it writes \n\r to the stream, which gets interpreted as two EOLs by Cisco IOS
        $plink_stdin.Write("terminal length 0`n")
        # Cisco IOS gets a little weird if it doesn't get a break between commands, so we sleep for a bit.
        Start-Sleep 1
        foreach ($cmd in $cisco_ios_cmds) {
            $plink_stdin.Write("$cmd`n")
            Start-Sleep 1
        }

        $plink_stdin.Write("exit`n")
        $plink_proc.WaitForExit()
        $cmds_response = $plink_stdout.Result
    
        if ($plink_proc.ExitCode -ne 0) {
            $plink_err_file = "$pwd\$computer.error.log"
            $plink_stderr.Result | Out-File $plink_err_file
            Write-Error "Connection to $computer failed, check $plink_err_file."
            return $null
        } elseif (!(Test-HostKeyIsCached $plink_stderr.Result)) {
            $host_key_results_err = $plink_stderr.Result
        } else {
            $host_key_results_err = $null
        }
    } while ($host_key_results_err -ne $null)
    $cmds_output = Parse-Output $computer $cmds_response.Split("`n") $cisco_ios_cmds
    return $cmds_output
}

function Get-AddressTables([string[]]$computer_list) {
    begin {
        $credentials = (Get-Credential)
        if ($credentials -eq $null) {
            Write-Error "Logon cancelled, abandon all hope..."
            Exit -15
        }
        $cisco_ios_cmd = "sh mac address-table | e -|CPU|Mac Address Table|Total"
    }
    process {
        $address_table = @()
        $i = 1
        foreach ($computer in $computer_list) {
            Write-Progress -Activity "Getting MAC address table..." -Status $computer -PercentComplete ($i++/$computer_list.Count*100.00)
            $buffer = Invoke-CiscoIOSCmds $computer.Trim() $cisco_ios_cmd $credentials
            if ($buffer -ne $null) {
                $address_table += $buffer[$cisco_ios_cmd]
            }
        }
        return $address_table
    }
    end {}
}

function Open-ComputerListFile()
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

    $open_file_dlg = New-Object System.Windows.Forms.OpenFileDialog
    $open_file_dlg.Filter = "All files (*.*)| *.*"
    $open_file_dlg.ShowDialog() | Out-Null
    $open_file_dlg.FileName
}

function Save-ReportFile()
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

    $save_file_dlg = New-Object System.Windows.Forms.SaveFileDialog
    $save_file_dlg.Filter = "CSV file (*.csv) | *.csv"
    $save_file_dlg.OverwritePrompt = $true
    $save_file_dlg.ShowDialog() | Out-Null
    $save_file_dlg.FileName
}

function Show-GUI()
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

    # creating it here so we can get the default height of a single line text box for reference
    $computer_list_textbox = New-Object System.Windows.Forms.TextBox
    $textbox_height = $computer_list_textbox.Height

    $main_dlg_box = New-Object System.Windows.Forms.Form -Property @{
        ClientSize = New-Object System.Drawing.Size(600,($textbox_height*16))
        MaximizeBox = $false
        MinimizeBox = $false
        FormBorderStyle = 'FixedSingle'
        Text = "Get MAC address tables"
    }

    # widget size and location variables
    $ctrl_width_col = $main_dlg_box.ClientSize.Width/15
    $ctrl_height_row = $textbox_height
    $max_ctrl_width = $main_dlg_box.ClientSize.Width - $ctrl_width_col*2
    $max_ctrl_height = $main_dlg_box.ClientSize.Height - $ctrl_height_row*2
    $right_edge_x = $max_ctrl_width
    $left_edge_x = $ctrl_width_col
    $bottom_edge_y = $max_ctrl_height
    $top_edge_y = $ctrl_height_row

    $computer_list_label = New-Object System.Windows.Forms.Label -Property @{
        Size = New-Object System.Drawing.Size($max_ctrl_width, $textbox_height)
        Text = "Enter Cisco switch/router hostnames/IP addresses (comma separated or each on their own line):"
        Location = New-Object System.Drawing.Point($left_edge_x, $top_edge_y)
    }
    $main_dlg_box.Controls.Add($computer_list_label)

    $computer_list_textbox.Multiline = $true
    $computer_list_textbox.Height = $textbox_height*6
    $computer_list_textbox.Width = $max_ctrl_width
    $computer_list_textbox.Location = New-Object System.Drawing.Point($left_edge_x, ($top_edge_y + $ctrl_height_row))
    $main_dlg_box.Controls.Add($computer_list_textbox)

    $open_listfile_button = New-Object System.Windows.Forms.Button -Property @{
        Size = New-Object System.Drawing.Size(($ctrl_width_col*4), $textbox_height)
        Location = New-Object System.Drawing.Point($left_edge_x, ($computer_list_textbox.Height + $computer_list_textbox.Location.Y + $ctrl_height_row))
        Text = "&Open file with hostnames"
    }
    $open_listfile_button.Add_Click({$main_dlg_box.Enabled=$false; $open_listfile_textbox.Text=Open-ComputerListFile; $main_dlg_box.Enabled=$true})
    $main_dlg_box.Controls.Add($open_listfile_button)

    $open_listfile_textbox = New-Object System.Windows.Forms.TextBox -Property @{
        Size = New-Object System.Drawing.Size(($max_ctrl_width - $open_listfile_button.Width - $ctrl_width_col*2), $textbox_height)
        ReadOnly = $true
        BackColor = $main_dlg_box.BackColor
        TabStop = $false
    }
    $open_listfile_textbox.Location = New-Object System.Drawing.Point(($right_edge_x - $open_listfile_textbox.Width), $open_listfile_button.Location.Y)
    $main_dlg_box.Controls.Add($open_listfile_textbox)

    $save_file_button = New-Object System.Windows.Forms.Button -Property @{
        Size = New-Object System.Drawing.Size($open_listfile_button.Width, $textbox_height)
        Location = New-Object System.Drawing.Point($left_edge_x, ($open_listfile_button.Height + $open_listfile_button.Location.Y + $ctrl_height_row))
        Text = "&Save report to..."
    }
    $save_file_button.Add_Click({$main_dlg_box.Enabled=$false; $save_file_textbox.Text=Save-ReportFile; $main_dlg_box.Enabled=$true})
    $main_dlg_box.Controls.Add($save_file_button)

    $save_file_textbox = New-Object System.Windows.Forms.TextBox -Property @{
        Size = New-Object System.Drawing.Size(($max_ctrl_width - $save_file_button.Width - $ctrl_width_col*2), $textbox_height)
        ReadOnly = $true
        BackColor = $main_dlg_box.BackColor
        TabStop = $false
    }
    $save_file_textbox.Location = New-Object System.Drawing.Point(($right_edge_x - $save_file_textbox.Width), $save_file_button.Location.Y)
    $main_dlg_box.Controls.Add($save_file_textbox)

    $ok_button = New-Object System.Windows.Forms.Button -Property @{
        Size = New-Object System.Drawing.Size(($ctrl_width_col*2), $textbox_height)
        DialogResult = "OK"
        Text = "O&k"
    }
    $ok_button.Location = New-Object System.Drawing.Point(($right_edge_x - $ok_button.Width), ($bottom_edge_y - $ok_button.Height))
    $main_dlg_box.Controls.Add($ok_button)

    $cancel_button = New-Object System.Windows.Forms.Button -Property @{
        Size = New-Object System.Drawing.Size(($ctrl_width_col*2), $textbox_height)
        DialogResult = "Cancel"
        Text = "&Cancel"
    }
    $cancel_button.Location = New-Object System.Drawing.Point($left_edge_x, $ok_button.Location.Y)
    $main_dlg_box.Controls.Add($cancel_button)

    if($main_dlg_box.ShowDialog() -eq "Cancel") {
        return $null
    } else {
        return ([regex]::Split($computer_list_textbox.Text.Trim(), ",|`n")), $open_listfile_textbox.Text, $save_file_textbox.Text
    }
}

$computer_list = $null
while([string]::IsNullOrEmpty($computer_list)) {
    if (![string]::IsNullOrEmpty($ComputerName)) {
        $computer_list = @($ComputerName)
    } elseif (![string]::IsNullOrEmpty($ComputerListFile)) {
        $computer_list = (Get-Content -Path $ComputerListFile)
    } elseif($NoGUI) {
        $buffer = Read-Host "Please specify a switch/rouer hostname(s) (comma separated) or file containing the hostnames"
        if (Test-Path $buffer -ErrorAction SilentlyContinue) {
            $ComputerListFile = $buffer
        } elseif ($buffer -match "(\w+,?)+") { # if it's not a valid file path, assume we were given a hostname(s)
            $ComputerName = $buffer.Split(",")
        } else {
            Write-Error "I don't understand!"
        }
    } else {
        $buffer = Show-GUI
        if ($buffer -ne $null) {
            $ComputerName, $ComputerListFile, $SaveFile = $buffer
        } else {
            Exit 0
        }
    }
}
$address_tables = Get-AddressTables $computer_list

if (![string]::IsNullOrEmpty($SaveFile)) {
    $address_tables | Export-Csv -Path $SaveFile -NoTypeInformation
}

$address_tables | ogv -Wait -Title "MAC address tables"
