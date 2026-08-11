<#
.SYNOPSIS
    validate — SAB module. Confirms specific patches actually installed
    and the server is still healthy afterward.
.DESCRIPTION
    See manifest.yaml for the module contract. This is the fourth and
    final step in the patching workflow (see docs/learn/workflows.md) —
    it closes the loop pre-flight-check opened: pre-flight-check
    confirms the server is healthy enough to start; validate confirms
    it's still healthy afterward, and that the specific patches
    apply-patches was supposed to install actually landed.

    Read-only, like pre-flight-check — makes no changes to the system,
    which is why its rollback (rollback-validate.ps1) is a deliberate
    no-op, same reasoning as pre-flight-check's.

    Deliberately does NOT treat a pending reboot as an unhealthy signal
    the way pre-flight-check does — right after apply-patches, a
    pending reboot is normal and expected, not a problem to flag.
#>
param(
    [string[]]$PatchIds = @(),
    [double]$MinFreeDiskPercent = 10
)

function New-UpdateSession {
    New-Object -ComObject 'Microsoft.Update.Session'
}

function Invoke-Validate {
    param(
        [string[]]$PatchIds = @(),
        [double]$MinFreeDiskPercent = 10
    )

    # Confirm each requested patch actually shows as installed now.
    $confirmed = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()

    if ($PatchIds.Count -gt 0) {
        $session = New-UpdateSession
        $searcher = $session.CreateUpdateSearcher()
        $searchResult = $searcher.Search('IsInstalled=1')

        $installedKbIds = @()
        foreach ($update in $searchResult.Updates) {
            $installedKbIds += @($update.KBArticleIDs)
        }

        foreach ($kbId in $PatchIds) {
            if ($installedKbIds -contains $kbId) {
                $confirmed.Add($kbId)
            }
            else {
                $missing.Add($kbId)
            }
        }
    }

    # General post-patch health re-check — same spirit as
    # pre-flight-check, minus the pending-reboot check (see the note in
    # the synopsis above for why that's deliberately excluded here).
    $reasons = [System.Collections.Generic.List[string]]::new()

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

    $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if ($null -eq $wuService) {
        $reasons.Add('Could not find the Windows Update service (wuauserv).')
    }
    elseif ($wuService.StartType -eq 'Disabled') {
        $reasons.Add('The Windows Update service (wuauserv) is disabled.')
    }

    $healthy = ($reasons.Count -eq 0)

    [PSCustomObject]@{
        Confirmed = $confirmed.ToArray()
        Missing   = $missing.ToArray()
        Healthy   = $healthy
        Reasons   = $reasons.ToArray()
        Succeeded = ($healthy -and $missing.Count -eq 0)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Validate -PatchIds $PatchIds -MinFreeDiskPercent $MinFreeDiskPercent
}
