<#
.SYNOPSIS
    Pester tests for pre-flight-check.ps1. See manifest.yaml's
    tests.lab_suite field, and docs/learn/modules.md in sab-engine.
.DESCRIPTION
    Every external check (disk space, registry, service status) is
    mocked — these tests verify Test-PreFlightHealth's own logic, not
    the actual state of whatever machine happens to run them. Requires
    Pester v5+ (`Install-Module Pester -MinimumVersion 5.0 -Force` if
    not already installed).
#>

BeforeAll {
    . $PSScriptRoot/pre-flight-check.ps1
}

Describe 'Test-PreFlightHealth' {

    Context 'when everything is healthy' {
        BeforeEach {
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 20GB; Free = 80GB } }
            Mock Get-ItemProperty { $null }
            Mock Test-Path { $false }
            Mock Get-Service { [PSCustomObject]@{ StartType = 'Manual' } }
        }

        It 'reports Healthy as true' {
            (Test-PreFlightHealth).Healthy | Should -BeTrue
        }

        It 'reports no reasons' {
            (Test-PreFlightHealth).Reasons.Count | Should -Be 0
        }
    }

    Context 'when free disk space is below the threshold' {
        BeforeEach {
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 95GB; Free = 5GB } }
            Mock Get-ItemProperty { $null }
            Mock Test-Path { $false }
            Mock Get-Service { [PSCustomObject]@{ StartType = 'Manual' } }
        }

        It 'reports Healthy as false' {
            (Test-PreFlightHealth -MinFreeDiskPercent 10).Healthy | Should -BeFalse
        }

        It 'explains why in Reasons' {
            $result = Test-PreFlightHealth -MinFreeDiskPercent 10
            $result.Reasons | Where-Object { $_ -like '*disk*' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when a reboot is already pending' {
        BeforeEach {
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 20GB; Free = 80GB } }
            Mock Get-ItemProperty { $null }
            Mock Test-Path { $true } -ParameterFilter { $Path -like '*RebootPending*' }
            Mock Test-Path { $false } -ParameterFilter { $Path -notlike '*RebootPending*' }
            Mock Get-Service { [PSCustomObject]@{ StartType = 'Manual' } }
        }

        It 'reports Healthy as false' {
            (Test-PreFlightHealth).Healthy | Should -BeFalse
        }

        It 'explains why in Reasons' {
            $result = Test-PreFlightHealth
            $result.Reasons | Where-Object { $_ -like '*reboot*' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when the Windows Update service is disabled' {
        BeforeEach {
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 20GB; Free = 80GB } }
            Mock Get-ItemProperty { $null }
            Mock Test-Path { $false }
            Mock Get-Service { [PSCustomObject]@{ StartType = 'Disabled' } }
        }

        It 'reports Healthy as false' {
            (Test-PreFlightHealth).Healthy | Should -BeFalse
        }
    }

    Context 'when the Windows Update service cannot be found' {
        BeforeEach {
            Mock Get-PSDrive { [PSCustomObject]@{ Used = 20GB; Free = 80GB } }
            Mock Get-ItemProperty { $null }
            Mock Test-Path { $false }
            Mock Get-Service { $null }
        }

        It 'reports Healthy as false' {
            (Test-PreFlightHealth).Healthy | Should -BeFalse
        }
    }
}
