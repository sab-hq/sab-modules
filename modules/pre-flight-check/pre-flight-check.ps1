<#
.SYNOPSIS
    pre-flight-check — SAB module. Checks whether a Windows Server is
    healthy enough to safely patch right now.
.DESCRIPTION
    See manifest.yaml in this folder for the module contract (inputs,
    outputs, rollback, tests), and docs/learn/modules.md in sab-engine
    for the plain-language version of what a module is.

    Read-only — makes no changes to the system. See
    rollback-pre-flight-check.ps1 for why it still has a (no-op)
    rollback script anyway, rather than omitting one.
#>
param(
    [double]$MinFreeDiskPercent = 10
)

function Test-PreFlightHealth {
    param(
        [double]$MinFreeDiskPercent = 10
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    # Check 1: free disk space on the system drive — insufficient space
    # could cause a patch installation to fail partway through.
    $systemDriveLetter = $env:SystemDrive.TrimEnd(':')
    $disk = Get-PSDrive -Name $systemDriveLetter -ErrorAction SilentlyContinue
    if ($null -eq $disk) {
        $reasons.Add("Could not determine free space on system drive '$systemDriveLetter'.")
    }
    else {
        $totalBytes = $disk.Used + $disk.Free
        $freePercent = if ($totalBytes -gt 0) { ($disk.Free / $totalBytes) * 100 } else { 0 }
        if ($freePercent -lt $MinFreeDiskPercent) {
            $reasons.Add("Free disk space on ${systemDriveLetter}: is $([math]::Round($freePercent, 1))%, below the required $MinFreeDiskPercent%.")
        }
    }

    # Check 2: a reboot isn't already pending from a previous action —
    # patching on top of an outstanding reboot can compound issues.
    $rebootPending = $false

    $pendingFileRename = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    if ($null -ne $pendingFileRename) { $rebootPending = $true }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $rebootPending = $true
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $rebootPending = $true
    }

    if ($rebootPending) {
        $reasons.Add('A reboot is already pending from a previous action — patching now could compound issues.')
    }

    # Check 3: the Windows Update service is available to actually apply patches later.
    $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if ($null -eq $wuService) {
        $reasons.Add('Could not find the Windows Update service (wuauserv).')
    }
    elseif ($wuService.StartType -eq 'Disabled') {
        $reasons.Add('The Windows Update service (wuauserv) is disabled.')
    }

    [PSCustomObject]@{
        Healthy = ($reasons.Count -eq 0)
        Reasons = $reasons.ToArray()
    }
}

# Only auto-run when executed directly, not when dot-sourced — this is
# what lets pre-flight-check.tests.ps1 dot-source this file and call
# Test-PreFlightHealth directly with mocks in place, without also
# triggering a real, unmocked run against whatever machine runs the tests.
if ($MyInvocation.InvocationName -ne '.') {
    Test-PreFlightHealth -MinFreeDiskPercent $MinFreeDiskPercent
}
