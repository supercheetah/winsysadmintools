Function Test-ComputerIsOff
{
# This was written because:
# 1. A number of computers that I work with are stuck on just PowerShell 2.0 for the time being.
# 2. Test-Connection doesn't have enough time resolution (only down to the second).
    param(
        [Parameter(Mandatory = $true)]
        $ComputerName
    )

    # Write-Host "Pinging $ComputerName"

    & C:\WINDOWS\system32\PING.EXE -n 1 -w 1000 $ComputerName | Out-Null
    return $LASTEXITCODE -ne 0
}
