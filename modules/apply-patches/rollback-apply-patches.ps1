<#
.SYNOPSIS
    rollback-apply-patches — uninstalls specific KB patches that were applied.
.DESCRIPTION
    Unlike pre-flight-check and stage-patches, apply-patches genuinely
    changes the server's running state — this rollback is real, not a
    deliberate no-op, per Section 2's non-negotiable rollback
    requirement (design doc, and docs/learn/modules.md).

    Uses wusa.exe (the built-in Windows Update Standalone Installer) to
    uninstall specific KBs — the WUA COM API itself doesn't expose a
    straightforward "uninstall by KB ID" method the way it does for
    search/download/install.

    IMPORTANT: running this file directly triggers a REAL uninstall of
    Windows updates on whatever machine runs it, same caution as
    apply-patches.ps1 itself.
#>
param(
    [string[]]$PatchIds = @()
)

# Isolated into its own function specifically so Pester can mock the
# actual wusa.exe invocation, rather than faking Start-Process deep
# inside the real logic.
function Invoke-UninstallPatch {
    param(
        [string]$KbId
    )
    $kbNumber = $KbId -replace '^KB', ''
    $process = Start-Process -FilePath 'wusa.exe' -ArgumentList "/uninstall /kb:$kbNumber /quiet /norestart" -Wait -PassThru -NoNewWindow
    return $process.ExitCode
}

function Invoke-RollbackApplyPatches {
    param(
        [string[]]$PatchIds = @()
    )

    $uninstalled = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()

    foreach ($kbId in $PatchIds) {
        $exitCode = Invoke-UninstallPatch -KbId $kbId

        # wusa.exe exit codes: 0 = success, 3010 = success but a reboot
        # is required to finish — both count as a successful uninstall.
        if ($exitCode -eq 0 -or $exitCode -eq 3010) {
            $uninstalled.Add($kbId)
        }
        else {
            $failed.Add($kbId)
        }
    }

    [PSCustomObject]@{
        Uninstalled = $uninstalled.ToArray()
        Failed      = $failed.ToArray()
        Succeeded   = ($failed.Count -eq 0)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-RollbackApplyPatches -PatchIds $PatchIds
}
