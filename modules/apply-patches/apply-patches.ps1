<#
.SYNOPSIS
    apply-patches — SAB module. Installs updates that were already
    staged (downloaded) by stage-patches.
.DESCRIPTION
    See manifest.yaml for the module contract. This is the highest-risk
    module in the patching workflow — the only one that actually changes
    a server's running behavior. It never triggers its own download;
    only updates already marked IsDownloaded=true are ever installed,
    even if a caller's patch_ids filter matches something that isn't
    staged yet. Staging and applying are kept as separate steps
    deliberately (see docs/learn/modules.md and stage-patches.ps1) so a
    slow/flaky download never happens in the same step as the actual,
    disruptive install.

    IMPORTANT: running this file directly triggers a REAL install of
    Windows updates on whatever machine runs it. Pester tests
    (apply-patches.tests.ps1) mock the WUA boundary entirely and are
    safe to run anywhere; running this script directly is not.
#>
param(
    [string[]]$PatchIds = @()
)

# Same COM-interop boundary pattern as stage-patches.ps1 — isolated so
# Pester can mock these points instead of faking COM object creation
# deep inside the real logic.
function New-UpdateSession {
    New-Object -ComObject 'Microsoft.Update.Session'
}

function New-UpdateCollection {
    New-Object -ComObject 'Microsoft.Update.UpdateColl'
}

function Invoke-ApplyPatches {
    param(
        [string[]]$PatchIds = @()
    )

    $session = New-UpdateSession
    $searcher = $session.CreateUpdateSearcher()
    $searchResult = $searcher.Search('IsInstalled=0 and IsHidden=0')

    $toApply = @()
    foreach ($update in $searchResult.Updates) {
        $kbIds = @($update.KBArticleIDs)
        $matchesFilter = $PatchIds.Count -eq 0 -or ($kbIds | Where-Object { $PatchIds -contains $_ })
        # Never install anything that wasn't already staged — this is a
        # real safety boundary, not just a filter.
        if ($matchesFilter -and $update.IsDownloaded) {
            $toApply += $update
        }
    }

    $applied = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $rebootRequired = $false

    if ($toApply.Count -gt 0) {
        $updateColl = New-UpdateCollection
        foreach ($update in $toApply) {
            $updateColl.Add($update) | Out-Null
        }

        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updateColl
        $installResult = $installer.Install()

        for ($i = 0; $i -lt $toApply.Count; $i++) {
            $label = ($toApply[$i].KBArticleIDs -join ',')
            $resultCode = $installResult.GetUpdateResult($i).ResultCode

            # WUA OperationResultCode: 2 = orcSucceeded, 3 = orcSucceededWithErrors.
            # Both count as applied; anything else (failed/aborted/etc.) doesn't.
            if ($resultCode -eq 2 -or $resultCode -eq 3) {
                $applied.Add($label)
            }
            else {
                $failed.Add($label)
            }
        }

        if ($installResult.RebootRequired) {
            $rebootRequired = $true
        }
    }

    [PSCustomObject]@{
        Applied        = $applied.ToArray()
        Failed         = $failed.ToArray()
        RebootRequired = $rebootRequired
        Succeeded      = ($failed.Count -eq 0)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ApplyPatches -PatchIds $PatchIds
}
