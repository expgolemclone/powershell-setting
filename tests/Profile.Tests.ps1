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

    It 'keeps UTF-8 and Windows Terminal key bindings' {
        $check = @'
$ErrorActionPreference = 'Stop'
$env:WT_SESSION = 'test'
. $args[0]
if ([Console]::InputEncoding.WebName -ne 'utf-8' -or
    [Console]::OutputEncoding.WebName -ne 'utf-8' -or
    $OutputEncoding.WebName -ne 'utf-8') { throw 'Console encoding is not UTF-8' }
if ((Get-PSReadLineKeyHandler -Chord Ctrl+c).Function -ne 'CancelLine') { throw 'Ctrl+C does not cancel' }
if (Get-PSReadLineKeyHandler -Chord Ctrl+v) { throw 'Ctrl+V is still bound' }
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
    }

    It 'uses native Pi, Codex, uv and Glow commands with direct aliases' {
        # Stand-ins for npm-generated scripts, without starting a CLI or model.
        $shimDirectory = Join-Path $TestDrive 'agent-shims'
        New-Item -ItemType Directory -Path $shimDirectory | Out-Null
        foreach ($name in @('pi', 'codex', 'uv', 'glow')) {
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
if ((Get-Alias g).Definition -ne 'glow') { throw 'g must resolve directly to glow' }
foreach ($name in @('pi', 'codex', 'uv', 'glow')) {
    $command = Get-Command $name
    if ($command.CommandType -ne 'ExternalScript' -or
        $command.Source -ne (Join-Path $args[1] "$name.ps1")) {
        throw "$name did not resolve to its standard shim"
    }
}
foreach ($name in @('pi', 'p', 'codex', 'uv', 'u', 'glow', 'g')) {
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

    It 'activates mise tools and project environments with the standard prompt' {
        $project = Join-Path $TestDrive 'mise-project'
        New-Item -ItemType Directory -Path $project | Out-Null
        Set-Content -LiteralPath (Join-Path $project 'mise.toml') -Value "[env]`nPROFILE_MISE_TEST = 'project-only'"
        $check = @'
$ErrorActionPreference = 'Stop'
$standardPrompt = prompt
. $args[0]
. $args[0]
if ((prompt) -cne $standardPrompt) { throw 'The standard prompt was replaced' }
foreach ($name in @('node', 'python', 'pi', 'uv')) {
    if ((Split-Path (Get-Command $name).Source) -ne (Split-Path (& mise.exe which $name))) { throw "Not selected by mise: $name" }
}
& mise.exe trust (Join-Path $args[1] 'mise.toml')
if ($LASTEXITCODE) { throw 'Could not trust the test configuration' }
Push-Location -LiteralPath $args[1]
try {
    if ($env:PROFILE_MISE_TEST -ne 'project-only') { throw 'Project environment was not activated on directory change' }
    if ((prompt) -notmatch 'PS .+>+ $') { throw 'Project activation changed the prompt format' }
} finally {
    Pop-Location
    & mise.exe untrust (Join-Path $args[1] 'mise.toml')
}
if (Test-Path Env:PROFILE_MISE_TEST) { throw 'Project environment leaked after leaving the directory' }
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))' '$($project.Replace("'", "''"))'"
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

    It 'uses native filesystem commands without custom wrappers or overrides' {
        $fixture = Join-Path $TestDrive 'native-commands'
        New-Item -ItemType Directory -Path $fixture | Out-Null
        $check = @'
$ErrorActionPreference = 'Stop'
. $args[0]
foreach ($name in @('l', 'la', 'cpa', 'tree', 'sudo', 'm')) {
    if (Test-Path "Alias:$name") { throw "Unexpected alias: $name" }
}
foreach ($name in @('Invoke-ClearLs', 'Invoke-GlowDark', 'Invoke-ListAll', 'Copy-ItemAutoName', 'Invoke-Tree')) {
    if (Test-Path "Function:$name") { throw "Unexpected wrapper: $name" }
}
if ((Get-Alias cp).Definition -ne 'Copy-Item') { throw 'cp must use the built-in Copy-Item' }
if ((Get-Command tree).CommandType -ne 'Application') { throw 'tree must use the Windows command' }
Set-Content -LiteralPath (Join-Path $args[1] 'source.txt') -Value 'content'
cp -LiteralPath (Join-Path $args[1] 'source.txt') -Destination (Join-Path $args[1] 'copy.txt')
if ((Get-Content -LiteralPath (Join-Path $args[1] 'copy.txt')) -cne 'content') { throw 'Native copy failed' }
$listing = @(tree $args[1] /F)
if (-not ($listing -match 'copy.txt')) { throw 'Native tree did not list the copy' }
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))' '$($fixture.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
    }
}
