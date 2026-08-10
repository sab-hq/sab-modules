<#
.SYNOPSIS
    Pester tests for stage-patches.ps1. See manifest.yaml's
    tests.lab_suite field, and docs/learn/modules.md in sab-engine.
.DESCRIPTION
    The Windows Update Agent (WUA) COM API is entirely mocked here, at
    the two boundary functions the script deliberately isolates it
    behind (New-UpdateSession, New-UpdateCollection) — these tests never
    touch real Windows Update, and are safe to run on any machine.

    Worth being explicit about what this does and doesn't prove: these
    tests verify Invoke-StagePatches' own branching logic (filtering,
    staged/failed classification) given a WUA-shaped response — they do
    NOT prove the real WUA COM API actually behaves the way this script
    assumes. That's only verified by running the real script (not the
    tests) against a real Windows machine with pending updates — ideally
    the lab VM (PD-11), not a casual local run, since running the real
    script triggers a genuine Windows Update search/download.
#>

BeforeAll {
    . $PSScriptRoot/stage-patches.ps1

    # Defined inside BeforeAll, not at the top of the file, specifically
    # because Pester v6 doesn't reliably carry plain top-level script
    # functions into It/BeforeEach scope the way some other test
    # frameworks do — BeforeAll is the officially-supported mechanism for
    # making things available throughout a Describe block's Run phase.
    function New-FakeUpdate {
        param(
            [string[]]$KBArticleIDs,
            [bool]$WillFailDownload = $false
        )

        $update = [PSCustomObject]@{
            KBArticleIDs      = $KBArticleIDs
            IsDownloaded      = $false
            _WillFailDownload = $WillFailDownload
        }
        Add-Member -InputObject $update -MemberType ScriptMethod -Name AcceptEula -Value { }
        return $update
    }

    function New-FakeSession {
        param(
            [array]$AvailableUpdates = @()
        )

        $searchResult = [PSCustomObject]@{ Updates = $AvailableUpdates }
        $searcher = [PSCustomObject]@{}
        Add-Member -InputObject $searcher -MemberType ScriptMethod -Name Search -Value { param($criteria) $searchResult }.GetNewClosure()

        $downloader = [PSCustomObject]@{ Updates = $null }
        Add-Member -InputObject $downloader -MemberType ScriptMethod -Name Download -Value {
            foreach ($u in $this.Updates) {
                $u.IsDownloaded = -not $u._WillFailDownload
            }
        }

        $session = [PSCustomObject]@{}
        Add-Member -InputObject $session -MemberType ScriptMethod -Name CreateUpdateSearcher -Value { $searcher }.GetNewClosure()
        Add-Member -InputObject $session -MemberType ScriptMethod -Name CreateUpdateDownloader -Value { $downloader }.GetNewClosure()

        return $session
    }
}

Describe 'Invoke-StagePatches' {

    Context 'when no updates are available' {
        BeforeEach {
            Mock New-UpdateSession { New-FakeSession -AvailableUpdates @() }
            # -NoEnumerate matters here: an empty ArrayList returned
            # through a scriptblock's pipeline output otherwise gets
            # auto-unrolled by PowerShell (it implements IEnumerable),
            # producing zero output items — so $updateColl = New-UpdateCollection
            # would silently end up $null instead of an empty collection.
            Mock New-UpdateCollection { Write-Output -NoEnumerate ([System.Collections.ArrayList]::new()) }
        }

        It 'reports Succeeded as true with nothing staged' {
            $result = Invoke-StagePatches
            $result.Succeeded | Should -BeTrue
            $result.Staged.Count | Should -Be 0
            $result.Failed.Count | Should -Be 0
        }
    }

    Context 'when updates are available and all download successfully' {
        BeforeEach {
            $updates = @(
                (New-FakeUpdate -KBArticleIDs @('KB1111')),
                (New-FakeUpdate -KBArticleIDs @('KB2222'))
            )
            $fakeUpdateColl = [System.Collections.ArrayList]::new()
            Mock New-UpdateSession { New-FakeSession -AvailableUpdates $updates }
            Mock New-UpdateCollection { Write-Output -NoEnumerate $fakeUpdateColl }
        }

        It 'stages both updates' {
            $result = Invoke-StagePatches
            $result.Succeeded | Should -BeTrue
            $result.Staged | Should -Contain 'KB1111'
            $result.Staged | Should -Contain 'KB2222'
        }
    }

    Context 'when a PatchIds filter is given' {
        BeforeEach {
            $updates = @(
                (New-FakeUpdate -KBArticleIDs @('KB1111')),
                (New-FakeUpdate -KBArticleIDs @('KB2222'))
            )
            $fakeUpdateColl = [System.Collections.ArrayList]::new()
            Mock New-UpdateSession { New-FakeSession -AvailableUpdates $updates }
            Mock New-UpdateCollection { Write-Output -NoEnumerate $fakeUpdateColl }
        }

        It 'only stages the requested KB, ignoring the rest' {
            $result = Invoke-StagePatches -PatchIds @('KB1111')
            $result.Staged | Should -Contain 'KB1111'
            $result.Staged | Should -Not -Contain 'KB2222'
        }
    }

    Context 'when one update fails to download and another succeeds' {
        BeforeEach {
            $updates = @(
                (New-FakeUpdate -KBArticleIDs @('KB1111') -WillFailDownload $false),
                (New-FakeUpdate -KBArticleIDs @('KB9999') -WillFailDownload $true)
            )
            $fakeUpdateColl = [System.Collections.ArrayList]::new()
            Mock New-UpdateSession { New-FakeSession -AvailableUpdates $updates }
            Mock New-UpdateCollection { Write-Output -NoEnumerate $fakeUpdateColl }
        }

        It 'reports Succeeded as false' {
            (Invoke-StagePatches).Succeeded | Should -BeFalse
        }

        It 'puts the failed KB in Failed and the successful one in Staged' {
            $result = Invoke-StagePatches
            $result.Staged | Should -Contain 'KB1111'
            $result.Failed | Should -Contain 'KB9999'
        }
    }
}
