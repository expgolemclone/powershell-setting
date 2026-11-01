BeforeAll {
    $ErrorActionPreference = 'Stop'
    $profilePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Microsoft.PowerShell_profile.ps1'
}

Describe 'PowerShell profile' {
    It 'parses without errors' {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
    }

    It 'uses native Pi, Codex and uv shims with argument and input forwarding through p and u' {
        # Stand-ins for npm-generated scripts, without starting a CLI or model.
        $shimDirectory = Join-Path $TestDrive 'agent-shims'
        New-Item -ItemType Directory -Path $shimDirectory | Out-Null
        foreach ($name in @('pi', 'codex', 'uv')) {
            Set-Content -LiteralPath (Join-Path $shimDirectory "$name.ps1") -Value @'
[pscustomobject]@{ Arguments = @($args); Incoming = @($input) }
'@
        }
        $check = @'
$ErrorActionPreference = 'Stop'
. $args[0]
. $args[0]
$env:PATH = $args[1] + [IO.Path]::PathSeparator + $env:PATH
if ((Get-Alias p).Definition -ne 'pi') { throw 'p must resolve to pi' }
if ((Get-Alias u).Definition -ne 'uv') { throw 'u must resolve directly to uv' }
foreach ($name in @('pi', 'codex', 'uv')) {
    $command = Get-Command $name
    if ($command.CommandType -ne 'ExternalScript' -or
        $command.Source -ne (Join-Path $args[1] "$name.ps1")) {
        throw "$name did not resolve to its standard shim"
    }
}
foreach ($name in @('pi', 'p', 'codex', 'uv', 'u')) {
    $result = & $name --help '--' 'two words' '"quoted"' ''
    $expected = @('--help', '--', 'two words', '"quoted"', '')
    $actualJson = ConvertTo-Json -InputObject $result.Arguments -Compress
    $expectedJson = ConvertTo-Json -InputObject $expected -Compress
    if ($actualJson -cne $expectedJson) { throw "Argument corruption for $name" }
    $piped = 'pipe input' | & $name --help
    if ($piped.Incoming.Count -ne 1 -or $piped.Incoming[0] -ne 'pipe input') {
        throw "Lost pipeline input for $name"
    }
}
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))' '$($shimDirectory.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
    }

    It 'activates mise tools and project environment changes while preserving the custom prompt' {
        $project = Join-Path $TestDrive 'mise-project'
        New-Item -ItemType Directory -Path $project | Out-Null
        Set-Content -LiteralPath (Join-Path $project 'mise.toml') -Value "[env]`nPROFILE_MISE_TEST = 'project-only'"
        $check = @'
$ErrorActionPreference = 'Stop'
. $args[0]
. $args[0]
foreach ($name in @('node', 'python', 'pi', 'uv')) {
    if ((Split-Path (Get-Command $name).Source) -ne (Split-Path (& mise.exe which $name))) { throw "Not selected by mise: $name" }
}
if ((prompt) -notmatch 'PS .+>+ $') { throw 'Custom prompt was replaced' }
& mise.exe trust (Join-Path $args[1] 'mise.toml')
if ($LASTEXITCODE) { throw 'Could not trust the test configuration' }
Push-Location -LiteralPath $args[1]
try {
    if ($env:PROFILE_MISE_TEST -ne 'project-only') { throw 'Project environment was not activated on directory change' }
    if ((prompt) -notmatch 'PS .+>+ $') { throw 'Project activation replaced the prompt' }
} finally {
    Pop-Location
    & mise.exe untrust (Join-Path $args[1] 'mise.toml')
}
if (Test-Path Env:PROFILE_MISE_TEST) { throw 'Project environment leaked after leaving the directory' }
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))' '$($project.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
    }

    It 'does not reconstruct PATH or recreate the aggregate Python launcher' {
        $source = [IO.File]::ReadAllText($profilePath)
        $source | Should -Not -Match 'envx-python|Invoke-ProjectPython|GetEnvironmentVariable|env:Path\s*='
    }

    It 'does not register the retired launcher or aliases' {
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$tokens, [ref]$parseErrors)
        $retired = $ast.FindAll({
            param($node)
            ($node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Invoke-Codex', 'Invoke-RestrictedCodex', 'Invoke-Claude', 'Invoke-RestrictedPi', 'Invoke-WindowedAgent')) -or
            ($node -is [Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Set-Alias' -and
                @($node.CommandElements | Where-Object {
                    $_ -is [Management.Automation.Language.StringConstantExpressionAst] -and
                    $_.Value -in @('co', 'codex', 'cl', 'claude', 'Invoke-Codex', 'Invoke-RestrictedCodex', 'Invoke-Claude', 'Invoke-RestrictedPi', 'Invoke-WindowedAgent')
                }).Count -gt 0)
        }, $true)
        @($retired).Count | Should -Be 0
    }

    It 'uses default text for archives and packages without changing errors or script colors' {
        $check = @'
$ErrorActionPreference = 'Stop'
$archiveExtensions = @('.zip', '.tgz', '.gz', '.tar', '.nupkg', '.cab', '.7z')
$otherExtensionColors = @{}
foreach ($extension in $PSStyle.FileInfo.Extension.Keys) {
    if ($extension -notin $archiveExtensions) {
        $otherExtensionColors[$extension] = $PSStyle.FileInfo.Extension[$extension]
    }
}
$formattingError = $PSStyle.Formatting.Error
$inputError = (Get-PSReadLineOption).ErrorColor
$executable = $PSStyle.FileInfo.Executable
. $args[0]
. $args[0]
foreach ($extension in $archiveExtensions) {
    if ($PSStyle.FileInfo.Extension.ContainsKey($extension)) {
        throw "Archive decoration remains: $extension"
    }
}
foreach ($extension in $otherExtensionColors.Keys) {
    if ($PSStyle.FileInfo.Extension[$extension] -cne $otherExtensionColors[$extension]) {
        throw "Unrelated extension color changed: $extension"
    }
}
if ($PSStyle.Formatting.Error -cne $formattingError) { throw 'Formatting error color changed' }
if ((Get-PSReadLineOption).ErrorColor -cne $inputError) { throw 'Input error color changed' }
if ($PSStyle.FileInfo.Executable -cne $executable) { throw 'Executable color changed' }
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
    }

    It 'accepts literal path <PathName> and lists directory junctions as leaves' -ForEach @(
        @{ PathName = 'tree-root' }, @{ PathName = '[tree root]' }
    ) {
        $treeRoot = Join-Path $TestDrive $PathName
        $external = Join-Path $TestDrive "$PathName-external"
        New-Item -ItemType Directory -Path (Join-Path $treeRoot '[branch]') | Out-Null
        New-Item -ItemType Directory -Path $external | Out-Null
        Set-Content -LiteralPath (Join-Path $treeRoot '[branch]/nested.txt') -Value 'nested'
        Set-Content -LiteralPath (Join-Path $external 'outside.txt') -Value 'outside'
        $links = @((Join-Path $treeRoot 'cycle'), (Join-Path $treeRoot 'external'))
        try {
            New-Item -ItemType Junction -Path $links[0] -Target $treeRoot | Out-Null
            New-Item -ItemType Junction -Path $links[1] -Target $external | Out-Null
            $check = @'
$ErrorActionPreference = 'Stop'
. $args[0]
$lines = @(tree $args[1] 6>&1 | ForEach-Object { "$_" })
if (@($lines | Where-Object { $_ -match 'cycle$' }).Count -ne 1) { throw 'Cycle was followed' }
if (@($lines | Where-Object { $_ -match 'external$' }).Count -ne 1) { throw 'External junction missing' }
if (@($lines | Where-Object { $_ -match 'outside.txt' }).Count -ne 0) { throw 'Escaped tree root' }
if (@($lines | Where-Object { $_ -match 'nested.txt$' }).Count -ne 1) { throw 'Real directory not traversed' }
if ($lines[-1].Trim() -ne '3 directories, 1 files') { throw "Wrong counts: $($lines[-1])" }
Push-Location -LiteralPath $args[1]
try {
    $default = @(tree 6>&1 | ForEach-Object { "$_" })
    if (($default -join "`n") -cne ($lines -join "`n")) { throw 'Default current directory changed' }
} finally { Pop-Location }
$shallow = @(Invoke-Tree -L 1 -d $args[1] 6>&1 | ForEach-Object { "$_" })
if ($shallow[-1].Trim() -ne '3 directories') { throw 'Directory-only depth limit changed' }
'@
            & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))' '$($treeRoot.Replace("'", "''"))'"
            $LASTEXITCODE | Should -Be 0
        } finally {
            # Pester's TestDrive cleanup must never traverse the cycle or external target.
            foreach ($link in $links) {
                if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force -ErrorAction Stop }
            }
        }
    }

    It 'loads in a fresh shell while preserving the other helpers' {
        $check = @'
. $args[0]
foreach ($name in @('co', 'codex', 'Invoke-Codex', 'Invoke-RestrictedCodex', 'cl', 'Invoke-Claude')) {
    if (Test-Path "Alias:$name") { throw "Retired alias remains: $name" }
    if (Test-Path "Function:$name") { throw "Retired function remains: $name" }
}
foreach ($name in @('u', 'la', 'tree', 'cpa')) {
    if (-not (Test-Path "Alias:$name")) { throw "Expected helper is missing: $name" }
}
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
    }
}
