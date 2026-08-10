<#
.SYNOPSIS
    stage-patches — SAB module. Downloads available Windows updates to
    the local cache without installing them.
.DESCRIPTION
    See manifest.yaml for the module contract. Uses the native Windows
    Update Agent (WUA) COM API (Microsoft.Update.Session) rather than an
    external module like PSWindowsUpdate, so this has zero extra
    dependencies beyond what every Windows Server already has.

    "Staging" means download-only — apply-patches (a separate, later
    module) is what actually installs what gets staged here. Separating
    the two means a slow or flaky download doesn't happen in the same
    step as the actual, more disruptive install.

    IMPORTANT: running this file directly triggers a REAL Windows Update
    search/download against whatever machine runs it — unlike
    pre-flight-check, this is not a safe, side-effect-free operation to
    run casually. Pester tests (stage-patches.tests.ps1) mock the WUA
    boundary entirely and are safe to run anywhere; running this script
    directly is not.
#>
param(
    [string[]]$PatchIds = @()
)

# The two COM-interop boundaries in this script, isolated into their own
# functions specifically so Pester tests can mock these two points
# rather than needing to fake COM object creation deep inside the real
# logic. See stage-patches.tests.ps1.
function New-UpdateSession {
    New-Object -ComObject 'Microsoft.Update.Session'
}

function New-UpdateCollection {
    New-Object -ComObject 'Microsoft.Update.UpdateColl'
}

function Invoke-StagePatches {
    param(
        [string[]]$PatchIds = @()
    )

    $session = New-UpdateSession
    $searcher = $session.CreateUpdateSearcher()
    $searchResult = $searcher.Search('IsInstalled=0 and IsHidden=0')

    $toStage = @()
    foreach ($update in $searchResult.Updates) {
        $kbIds = @($update.KBArticleIDs)
        $matchesFilter = $PatchIds.Count -eq 0 -or ($kbIds | Where-Object { $PatchIds -contains $_ })
        if ($matchesFilter) {
            $update.AcceptEula()
            $toStage += $update
        }
    }

    $staged = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()

    if ($toStage.Count -gt 0) {
        $updateColl = New-UpdateCollection
        foreach ($update in $toStage) {
            $updateColl.Add($update) | Out-Null
        }

        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updateColl
        $downloader.Download() | Out-Null

        foreach ($update in $toStage) {
            $label = ($update.KBArticleIDs -join ',')
            if ($update.IsDownloaded) {
                $staged.Add($label)
            }
            else {
                $failed.Add($label)
            }
        }
    }

    [PSCustomObject]@{
        Staged    = $staged.ToArray()
        Failed    = $failed.ToArray()
        Succeeded = ($failed.Count -eq 0)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-StagePatches -PatchIds $PatchIds
}
