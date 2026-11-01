BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $setup = Join-Path $repositoryRoot 'setup.ps1'
    $sourceProfile = Join-Path $repositoryRoot 'profile.ps1'
    $newItem = Get-Command New-Item -CommandType Cmdlet

    function Invoke-TestSetup {
        param([string]$Directory, [switch]$WhatIf)
        $PROFILE = [pscustomobject]@{
            CurrentUserAllHosts = Join-Path $Directory 'profile.ps1'
        }
        & $setup -WhatIf:$WhatIf
    }
}

Describe 'Profile file setup' {
    BeforeEach {
        $directory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $profilePath = Join-Path $directory 'profile.ps1'
    }

    AfterEach {
        if (Test-Path -LiteralPath $profilePath) {
            $item = Get-Item -LiteralPath $profilePath -Force
            if ($item.LinkType -eq 'SymbolicLink') {
                Remove-Item -LiteralPath $profilePath -Force
            }
        }
    }

    Context 'when requesting a link' {
        BeforeEach {
            Mock New-Item {
                & $newItem -ItemType $ItemType -Path $Path -Force:$Force
            }
            Mock New-Item {} -ParameterFilter { $ItemType -eq 'SymbolicLink' }
        }

        It 'creates the profile directory and links to the repository file' {
            Invoke-TestSetup $directory
            Test-Path -LiteralPath $directory -PathType Container | Should -BeTrue
            Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
                $ItemType -eq 'SymbolicLink' -and $Path -eq $profilePath -and $Target -eq $sourceProfile
            }
        }

        It 'preserves modules in an existing profile directory' {
            $moduleDirectory = Join-Path $directory 'Modules/example'
            New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
            $module = Join-Path $moduleDirectory 'example.psm1'
            Set-Content -LiteralPath $module -Value 'keep'
            Invoke-TestSetup $directory
            Get-Content -LiteralPath $module | Should -Be 'keep'
            Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
                $ItemType -eq 'SymbolicLink' -and $Path -eq $profilePath -and $Target -eq $sourceProfile
            }
        }
    }

    It 'refuses to overwrite an existing profile' {
        New-Item -ItemType Directory -Path $directory | Out-Null
        Set-Content -LiteralPath $profilePath -Value 'keep'
        { Invoke-TestSetup $directory } | Should -Throw
        Get-Content -LiteralPath $profilePath | Should -Be 'keep'
    }

    It 'preserves an existing profile and directory junction' {
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $target | Out-Null
        $existingProfile = Join-Path $target 'profile.ps1'
        Set-Content -LiteralPath $existingProfile -Value 'keep'
        New-Item -ItemType Junction -Path $directory -Target $target | Out-Null
        try {
            { Invoke-TestSetup $directory } | Should -Throw
            (Get-Item -LiteralPath $directory -Force).LinkType | Should -Be 'Junction'
            Get-Content -LiteralPath $existingProfile | Should -Be 'keep'
        }
        finally {
            Remove-Item -LiteralPath $directory -Force
        }
    }

    It 'does not create the profile directory under WhatIf' {
        Invoke-TestSetup $directory -WhatIf
        Test-Path -LiteralPath $directory | Should -BeFalse
    }

    It 'creates the profile file link when the operating system permits it' {
        try {
            Invoke-TestSetup $directory
        }
        catch [System.UnauthorizedAccessException] {
            if ($_.FullyQualifiedErrorId -notlike 'NewItemSymbolicLinkElevationRequired*') { throw }
            Set-ItResult -Skipped -Because 'Windows requires administrator privileges or Developer Mode for file symbolic links'
            return
        }
        $item = Get-Item -LiteralPath $profilePath -Force
        $item.LinkType | Should -Be 'SymbolicLink'
        $item.Target | Should -Be $sourceProfile
    }
}
