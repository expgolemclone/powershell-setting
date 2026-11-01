BeforeAll {
    $ErrorActionPreference = 'Stop'
    $profilePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.ps1'
}

Describe 'PowerShell profile' {
    It 'parses without errors' {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
    }

    It 'uses native Neovim, Pi, Codex and uv shims with argument and input forwarding through n, p and u' {
        $shimDirectory = Join-Path $TestDrive 'agent-shims'
        New-Item -ItemType Directory -Path $shimDirectory | Out-Null
        foreach ($name in @('nvim', 'pi', 'codex', 'uv')) {
            Set-Content -LiteralPath (Join-Path $shimDirectory "$name.ps1") -Value @'
[pscustomobject]@{ Arguments = @($args); Incoming = @($input) }
'@
        }
        $check = @'
$ErrorActionPreference = 'Stop'
. $args[0]
. $args[0]
$env:PATH = $args[1] + [IO.Path]::PathSeparator + $env:PATH
if ((Get-Alias n).Definition -ne 'nvim') { throw 'n must resolve to nvim' }
if ((Get-Alias p).Definition -ne 'pi') { throw 'p must resolve to pi' }
if ((Get-Alias u).Definition -ne 'uv') { throw 'u must resolve directly to uv' }
foreach ($name in @('nvim', 'pi', 'codex', 'uv')) {
    $command = Get-Command $name
    if ($command.CommandType -ne 'ExternalScript' -or
        $command.Source -ne (Join-Path $args[1] "$name.ps1")) {
        throw "$name did not resolve to its standard shim"
    }
}
foreach ($name in @('nvim', 'n', 'pi', 'p', 'codex', 'uv', 'u')) {
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

    It 'activates mise tools and project environment changes without changing the default prompt' {
        $project = Join-Path $TestDrive 'mise-project'
        New-Item -ItemType Directory -Path $project | Out-Null
        Set-Content -LiteralPath (Join-Path $project 'mise.toml') -Value "[env]`nPROFILE_MISE_TEST = 'project-only'"
        $check = @'
$ErrorActionPreference = 'Stop'
$originalPrompt = prompt
. $args[0]
. $args[0]
foreach ($name in @('node', 'python', 'pi', 'uv')) {
    if ((Split-Path (Get-Command $name).Source) -ne (Split-Path (& mise.exe which $name))) { throw "Not selected by mise: $name" }
}
if ((prompt) -cne $originalPrompt) { throw 'Default prompt was changed' }
& mise.exe trust (Join-Path $args[1] 'mise.toml')
if ($LASTEXITCODE) { throw 'Could not trust the test configuration' }
Push-Location -LiteralPath $args[1]
try {
    if ($env:PROFILE_MISE_TEST -ne 'project-only') { throw 'Project environment was not activated on directory change' }
    if ((prompt) -notmatch 'PS .+>+ $') { throw 'Project activation changed the prompt' }
} finally {
    Pop-Location
    & mise.exe untrust (Join-Path $args[1] 'mise.toml')
}
if (Test-Path Env:PROFILE_MISE_TEST) { throw 'Project environment leaked after leaving the directory' }
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))' '$($project.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
    }

    It 'uses UTF-8 for console input, output and native pipelines on Windows' {
        $check = @'
$ErrorActionPreference = 'Stop'
. $args[0]
if ($IsWindows) {
    foreach ($encoding in @([Console]::InputEncoding, [Console]::OutputEncoding, $OutputEncoding)) {
        if ($encoding.CodePage -ne 65001 -or $encoding.GetPreamble().Length -ne 0) {
            throw 'Expected UTF-8 without a byte-order mark'
        }
    }
}
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
    }

    It 'does not shadow native tree or sudo commands' {
        $check = @'
$ErrorActionPreference = 'Stop'
. $args[0]
foreach ($name in @('tree', 'sudo')) {
    if ((Test-Path "Alias:$name") -or (Test-Path "Function:$name")) {
        throw "$name is shadowed by the profile"
    }
}
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
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
}
