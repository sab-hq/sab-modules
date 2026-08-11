<#
.SYNOPSIS
    Pester tests for validate.ps1. See manifest.yaml's tests.lab_suite
    field, and docs/learn/modules.md in sab-engine.
.DESCRIPTION
    Combines the two mocking patterns already established: WUA search
    mocking (from stage-patches.tests.ps1) for confirming installed
    patches, and health-check cmdlet mocking (from
    pre-flight-check.tests.ps1) for the post-patch health re-check.
    Every external dependency is mocked — these tests are safe to run
    anywhere and never touch real Windows Update or real system state.
#>

BeforeAll {
    . $PSScriptRoot/validate.ps1

    function New-FakeInstalledUpdate {
        param([string[]]$KBArticleIDs)
        [PSCustomObject]@{ KBArticleIDs = $KBArticleIDs }
    }

    function New-FakeSession {
        param([array]$InstalledUpdates = @())

        $searchResult = [PSCustomObject]@{ Updates = $InstalledUpdates }
        $searcher = [PSCustomObject]@{}
        Add-Member -InputObject $searcher -MemberType ScriptMethod -Name Search -Value { param($criteria) $searchResult }.GetNewClosure()

        $session = [PSCustomObject]@{}
        Add-Member -InputObject $session -MemberType ScriptMethod -Name CreateUpdateSearcher -Value { $searcher }.GetNewClosure()

        return $session
    }
}

Describe 'Invoke-Validate' {

    Context 'when no patch_ids are given and the system is healthy' {
        BeforeEach {
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 20GB; Free = 80GB } }
            Mock Get-Service { [PSCustomObject]@{ StartType = 'Manual' } }
        }

        It 'reports Succeeded as true with nothing to confirm' {
            $result = Invoke-Validate
            $result.Succeeded | Should -BeTrue
            $result.Confirmed.Count | Should -Be 0
            $result.Missing.Count | Should -Be 0
        }
    }

    Context 'when the requested patches are all confirmed installed' {
        BeforeEach {
            $installed = @(
                (New-FakeInstalledUpdate -KBArticleIDs @('KB1111')),
                (New-FakeInstalledUpdate -KBArticleIDs @('KB2222'))
            )
            Mock New-UpdateSession { New-FakeSession -InstalledUpdates $installed }
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 20GB; Free = 80GB } }
            Mock Get-Service { [PSCustomObject]@{ StartType = 'Manual' } }
        }

        It 'confirms both and reports Succeeded as true' {
            $result = Invoke-Validate -PatchIds @('KB1111', 'KB2222')
            $result.Succeeded | Should -BeTrue
            $result.Confirmed | Should -Contain 'KB1111'
            $result.Confirmed | Should -Contain 'KB2222'
            $result.Missing.Count | Should -Be 0
        }
    }

    Context 'when a requested patch is not actually installed' {
        BeforeEach {
            $installed = @((New-FakeInstalledUpdate -KBArticleIDs @('KB1111')))
            Mock New-UpdateSession { New-FakeSession -InstalledUpdates $installed }
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 20GB; Free = 80GB } }
            Mock Get-Service { [PSCustomObject]@{ StartType = 'Manual' } }
        }

        It 'puts it in Missing and reports Succeeded as false' {
            $result = Invoke-Validate -PatchIds @('KB1111', 'KB9999')
            $result.Confirmed | Should -Contain 'KB1111'
            $result.Missing | Should -Contain 'KB9999'
            $result.Succeeded | Should -BeFalse
        }
    }

    Context 'when free disk space is below the threshold' {
        BeforeEach {
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 95GB; Free = 5GB } }
            Mock Get-Service { [PSCustomObject]@{ StartType = 'Manual' } }
        }

        It 'reports Healthy and Succeeded as false' {
            $result = Invoke-Validate -MinFreeDiskPercent 10
            $result.Healthy | Should -BeFalse
            $result.Succeeded | Should -BeFalse
        }
    }

    Context 'when the Windows Update service is disabled' {
        BeforeEach {
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 20GB; Free = 80GB } }
            Mock Get-Service { [PSCustomObject]@{ StartType = 'Disabled' } }
        }

        It 'reports Healthy as false' {
            (Invoke-Validate).Healthy | Should -BeFalse
        }
    }

    Context 'when patches are confirmed but the system is unhealthy' {
        BeforeEach {
            $installed = @((New-FakeInstalledUpdate -KBArticleIDs @('KB1111')))
            Mock New-UpdateSession { New-FakeSession -InstalledUpdates $installed }
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 95GB; Free = 5GB } }
            Mock Get-Service { [PSCustomObject]@{ StartType = 'Manual' } }
        }

        It 'still reports Succeeded as false — both conditions matter' {
            $result = Invoke-Validate -PatchIds @('KB1111') -MinFreeDiskPercent 10
            $result.Confirmed | Should -Contain 'KB1111'
            $result.Healthy | Should -BeFalse
            $result.Succeeded | Should -BeFalse
        }
    }
}
