<#
.SYNOPSIS
    Pester tests for apply-patches.ps1 AND rollback-apply-patches.ps1.
    See manifest.yaml's tests.lab_suite field, and docs/learn/modules.md
    in sab-engine.
.DESCRIPTION
    Both scripts are tested here, in one file, since the Section 4.2
    manifest schema only supports a single tests.lab_suite entry per
    module — there's no separate field for "rollback tests" specifically.

    As with stage-patches: these tests verify the scripts' own branching
    logic given WUA-shaped and wusa.exe-shaped responses. They do NOT
    prove the real WUA COM API or wusa.exe actually behave the way these
    scripts assume — that's only verified by running the real scripts
    (never casually — see the warnings in both .ps1 files) against a
    real Windows machine.
#>

BeforeAll {
    . $PSScriptRoot/apply-patches.ps1
    . $PSScriptRoot/rollback-apply-patches.ps1

    function New-FakeUpdate {
        param(
            [string[]]$KBArticleIDs,
            [bool]$IsDownloaded = $true
        )
        [PSCustomObject]@{
            KBArticleIDs = $KBArticleIDs
            IsDownloaded = $IsDownloaded
        }
    }

    function New-FakeSession {
        param(
            [array]$AvailableUpdates = @(),
            [hashtable]$ResultCodesByIndex = @{},
            [bool]$RebootRequired = $false
        )

        $searchResult = [PSCustomObject]@{ Updates = $AvailableUpdates }
        $searcher = [PSCustomObject]@{}
        Add-Member -InputObject $searcher -MemberType ScriptMethod -Name Search -Value { param($criteria) $searchResult }.GetNewClosure()

        $installResult = [PSCustomObject]@{ RebootRequired = $RebootRequired }
        Add-Member -InputObject $installResult -MemberType ScriptMethod -Name GetUpdateResult -Value {
            param($index)
            $code = if ($ResultCodesByIndex.ContainsKey($index)) { $ResultCodesByIndex[$index] } else { 2 }
            [PSCustomObject]@{ ResultCode = $code }
        }.GetNewClosure()

        $installer = [PSCustomObject]@{ Updates = $null }
        Add-Member -InputObject $installer -MemberType ScriptMethod -Name Install -Value { $installResult }.GetNewClosure()

        $session = [PSCustomObject]@{}
        Add-Member -InputObject $session -MemberType ScriptMethod -Name CreateUpdateSearcher -Value { $searcher }.GetNewClosure()
        Add-Member -InputObject $session -MemberType ScriptMethod -Name CreateUpdateInstaller -Value { $installer }.GetNewClosure()

        return $session
    }
}

Describe 'Invoke-ApplyPatches' {

    Context 'when nothing is staged' {
        BeforeEach {
            Mock New-UpdateSession { New-FakeSession -AvailableUpdates @() }
            # -NoEnumerate: an empty ArrayList returned through a
            # scriptblock's pipeline output otherwise gets auto-unrolled
            # by PowerShell to zero output items — see PD-15's notes in
            # pre-development-checklist.md for the full story.
            Mock New-UpdateCollection { Write-Output -NoEnumerate ([System.Collections.ArrayList]::new()) }
        }

        It 'reports Succeeded as true with nothing applied' {
            $result = Invoke-ApplyPatches
            $result.Succeeded | Should -BeTrue
            $result.Applied.Count | Should -Be 0
        }
    }

    Context 'when staged updates install successfully' {
        BeforeEach {
            $updates = @(
                (New-FakeUpdate -KBArticleIDs @('KB1111') -IsDownloaded $true),
                (New-FakeUpdate -KBArticleIDs @('KB2222') -IsDownloaded $true)
            )
            $fakeUpdateColl = [System.Collections.ArrayList]::new()
            Mock New-UpdateSession { New-FakeSession -AvailableUpdates $updates }
            Mock New-UpdateCollection { Write-Output -NoEnumerate $fakeUpdateColl }
        }

        It 'applies both updates' {
            $result = Invoke-ApplyPatches
            $result.Succeeded | Should -BeTrue
            $result.Applied | Should -Contain 'KB1111'
            $result.Applied | Should -Contain 'KB2222'
        }
    }

    Context 'when an update matches the filter but was never staged' {
        BeforeEach {
            $updates = @(
                (New-FakeUpdate -KBArticleIDs @('KB1111') -IsDownloaded $false)
            )
            $fakeUpdateColl = [System.Collections.ArrayList]::new()
            Mock New-UpdateSession { New-FakeSession -AvailableUpdates $updates }
            Mock New-UpdateCollection { Write-Output -NoEnumerate $fakeUpdateColl }
        }

        It 'never attempts to install it, even though it matches patch_ids' {
            # This is a real safety boundary, not just a filter — worth
            # its own test, not folded into the general filter test.
            $result = Invoke-ApplyPatches -PatchIds @('KB1111')
            $result.Applied.Count | Should -Be 0
        }
    }

    Context 'when one update fails to install and another succeeds' {
        BeforeEach {
            $updates = @(
                (New-FakeUpdate -KBArticleIDs @('KB1111') -IsDownloaded $true),
                (New-FakeUpdate -KBArticleIDs @('KB9999') -IsDownloaded $true)
            )
            $fakeUpdateColl = [System.Collections.ArrayList]::new()
            Mock New-UpdateSession { New-FakeSession -AvailableUpdates $updates -ResultCodesByIndex @{ 0 = 2; 1 = 4 } }
            Mock New-UpdateCollection { Write-Output -NoEnumerate $fakeUpdateColl }
        }

        It 'reports Succeeded as false' {
            (Invoke-ApplyPatches).Succeeded | Should -BeFalse
        }

        It 'puts the failed KB in Failed and the successful one in Applied' {
            $result = Invoke-ApplyPatches
            $result.Applied | Should -Contain 'KB1111'
            $result.Failed | Should -Contain 'KB9999'
        }
    }

    Context 'when the installer reports a reboot is required' {
        BeforeEach {
            $updates = @((New-FakeUpdate -KBArticleIDs @('KB1111') -IsDownloaded $true))
            $fakeUpdateColl = [System.Collections.ArrayList]::new()
            Mock New-UpdateSession { New-FakeSession -AvailableUpdates $updates -RebootRequired $true }
            Mock New-UpdateCollection { Write-Output -NoEnumerate $fakeUpdateColl }
        }

        It 'reports RebootRequired as true' {
            (Invoke-ApplyPatches).RebootRequired | Should -BeTrue
        }
    }
}

Describe 'Invoke-RollbackApplyPatches' {

    Context 'when uninstall succeeds cleanly' {
        BeforeEach {
            Mock Invoke-UninstallPatch { 0 }
        }

        It 'reports the KB as uninstalled' {
            $result = Invoke-RollbackApplyPatches -PatchIds @('KB1111')
            $result.Succeeded | Should -BeTrue
            $result.Uninstalled | Should -Contain 'KB1111'
        }
    }

    Context 'when uninstall succeeds but needs a reboot (exit code 3010)' {
        BeforeEach {
            Mock Invoke-UninstallPatch { 3010 }
        }

        It 'still counts as a successful uninstall' {
            $result = Invoke-RollbackApplyPatches -PatchIds @('KB1111')
            $result.Succeeded | Should -BeTrue
            $result.Uninstalled | Should -Contain 'KB1111'
        }
    }

    Context 'when uninstall genuinely fails' {
        BeforeEach {
            Mock Invoke-UninstallPatch { 1 }
        }

        It 'reports the KB as failed, not uninstalled' {
            $result = Invoke-RollbackApplyPatches -PatchIds @('KB1111')
            $result.Succeeded | Should -BeFalse
            $result.Failed | Should -Contain 'KB1111'
        }
    }

    Context 'with a mix of successful and failed uninstalls' {
        BeforeEach {
            Mock Invoke-UninstallPatch {
                param($KbId)
                if ($KbId -eq 'KB9999') { 1 } else { 0 }
            }
        }

        It 'splits results correctly across both KBs' {
            $result = Invoke-RollbackApplyPatches -PatchIds @('KB1111', 'KB9999')
            $result.Uninstalled | Should -Contain 'KB1111'
            $result.Failed | Should -Contain 'KB9999'
        }
    }
}
