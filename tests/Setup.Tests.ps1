BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $setup = Join-Path $repositoryRoot 'setup.ps1'
    # Keep real fixture cleanup independent of command mocks used by safety tests.
    $getChildItem = Get-Command Get-ChildItem -CommandType Cmdlet
    $removeItem = Get-Command Remove-Item -CommandType Cmdlet
    function Invoke-TestSetup {
        param([string]$Directory, [switch]$WhatIf)
        # Shadow the profile variable only in this function, never change the real profile.
        $PROFILE = [pscustomobject]@{
            CurrentUserCurrentHost = Join-Path $Directory 'Microsoft.PowerShell_profile.ps1'
        }
        & $setup -WhatIf:$WhatIf
    }
    function Assert-ProfileJunction {
        param([string]$Directory)
        $item = Get-Item -LiteralPath $Directory -Force
        $item.LinkType | Should -Be 'Junction'
        $item.Target | Should -Be $repositoryRoot
    }
}

Describe 'Safe profile junction setup' {
    BeforeEach {
        $parent = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $directory = Join-Path $parent 'PowerShell'
    }
    AfterEach {
        # Unlink fixtures before Pester's recursive TestDrive cleanup can follow them.
        if (Test-Path -LiteralPath $parent) {
            & $getChildItem -LiteralPath $parent -Force -Recurse |
                Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } |
                ForEach-Object { & $removeItem -LiteralPath $_.FullName -Force -ErrorAction Stop }
        }
    }
    It 'creates the junction even when the profile parent is missing' {
        Invoke-TestSetup $directory
        Assert-ProfileJunction $directory
    }
    It 'creates a junction under a literal path with special characters' {
        $parent = Join-Path $TestDrive '[shell & data]'
        $directory = Join-Path $parent 'PowerShell'
        Invoke-TestSetup $directory
        Assert-ProfileJunction $directory
    }
    It 'does nothing when an existing correct junction has different casing' {
        $lowercase = Join-Path $parent 'powershell'
        New-Item -ItemType Directory -Path $parent | Out-Null
        New-Item -ItemType Junction -Path $lowercase -Target $repositoryRoot | Out-Null
        Mock New-Item { throw 'An existing correct junction must not be recreated.' }
        Invoke-TestSetup $directory
        Assert-ProfileJunction $directory
    }
    It 'refuses a stale junction without replacing it' {
        New-Item -ItemType Directory -Path $parent | Out-Null
        $target = Join-Path $parent 'previous-repository'
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType Junction -Path $directory -Target $target | Out-Null
        Remove-Item -LiteralPath $target
        { Invoke-TestSetup $directory } | Should -Throw '*already exists*'
        (Get-Item -LiteralPath $directory -Force).Target | Should -Be $target
    }
    It 'refuses another live junction and preserves its target files' {
        New-Item -ItemType Directory -Path $parent | Out-Null
        $target = Join-Path $parent 'other-repository'
        New-Item -ItemType Directory -Path $target | Out-Null
        $file = Join-Path $target 'keep.txt'
        Set-Content -LiteralPath $file -Value 'keep'
        New-Item -ItemType Junction -Path $directory -Target $target | Out-Null
        { Invoke-TestSetup $directory } | Should -Throw '*already exists*'
        (Get-Item -LiteralPath $directory).Target | Should -Be $target
        Get-Content -LiteralPath $file | Should -Be 'keep'
    }
    It 'refuses an existing empty directory tree without deleting it' {
        $nested = Join-Path $directory 'empty/nested'
        New-Item -ItemType Directory -Path $nested | Out-Null
        { Invoke-TestSetup $directory } | Should -Throw '*already exists*'
        Test-Path -LiteralPath $nested -PathType Container | Should -BeTrue
        (Get-Item -LiteralPath $directory).LinkType | Should -BeNullOrEmpty
    }
    It 'refuses an existing file without replacing it' {
        New-Item -ItemType Directory -Path $parent | Out-Null
        Set-Content -LiteralPath $directory -Value 'keep'
        { Invoke-TestSetup $directory } | Should -Throw '*already exists*'
        Get-Content -LiteralPath $directory | Should -Be 'keep'
    }
    It 'refuses a real profile tree with files' {
        New-Item -ItemType Directory -Path $directory | Out-Null
        $file = Join-Path $directory 'profile.ps1'
        Set-Content -LiteralPath $file -Value 'keep'
        { Invoke-TestSetup $directory } | Should -Throw '*already exists*'
        Get-Content -LiteralPath $file | Should -Be 'keep'
    }
    It 'refuses a tree containing a directory junction even when its target is empty' {
        New-Item -ItemType Directory -Path $directory | Out-Null
        $target = Join-Path $parent 'empty-target'
        New-Item -ItemType Directory -Path $target | Out-Null
        $link = Join-Path $directory 'link'
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        { Invoke-TestSetup $directory } | Should -Throw '*already exists*'
        (Get-Item -LiteralPath $link).LinkType | Should -Be 'Junction'
    }
    It 'refuses a non-junction root reparse point without replacing it' {
        New-Item -ItemType Directory -Path $parent | Out-Null
        Mock Get-Item {
            [pscustomobject]@{ LinkType = 'SymbolicLink' }
        } -ParameterFilter { $LiteralPath -eq $directory }
        Mock New-Item { throw 'A root reparse point must not be replaced.' }
        { Invoke-TestSetup $directory } | Should -Throw '*already exists*'
    }
    It 'does not replace a path it cannot inspect' {
        New-Item -ItemType Directory -Path $parent | Out-Null
        Mock Get-Item {
            Write-Error -Exception ([UnauthorizedAccessException]::new('Access denied'))
        } -ParameterFilter { $LiteralPath -eq $directory }
        Mock New-Item { throw 'An uninspectable path must not be replaced.' }
        { Invoke-TestSetup $directory } | Should -Throw '*Access denied*'
    }
    It 'does not create even the profile parent under WhatIf' {
        Invoke-TestSetup $directory -WhatIf
        Test-Path -LiteralPath $parent | Should -BeFalse
    }
    It 'preserves an existing empty directory tree under WhatIf' {
        $nested = Join-Path $directory 'empty/nested'
        New-Item -ItemType Directory -Path $nested | Out-Null
        { Invoke-TestSetup $directory -WhatIf } | Should -Throw '*already exists*'
        Test-Path -LiteralPath $nested -PathType Container | Should -BeTrue
        (Get-Item -LiteralPath $directory).LinkType | Should -BeNullOrEmpty
    }
}
