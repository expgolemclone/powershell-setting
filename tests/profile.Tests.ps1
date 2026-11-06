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

    It 'clears the screen before listing and forwards listing arguments through l' {
        $directory = Join-Path $TestDrive 'list-files'
        New-Item -ItemType Directory -Path $directory | Out-Null
        Set-Content -LiteralPath (Join-Path $directory 'one.txt') -Value ''
        Set-Content -LiteralPath (Join-Path $directory 'two.log') -Value ''
        $check = @'
$ErrorActionPreference = 'Stop'
. $args[0]
if ((Get-Command l).CommandType -ne 'Function') { throw 'l must be a function' }
$events = [System.Collections.Generic.List[string]]::new()
function Clear-Host { $events.Add('clear') }
function Get-ChildItem {
    $events.Add('list')
    Microsoft.PowerShell.Management\Get-ChildItem @args
}
Push-Location -LiteralPath $args[1]
try {
    $events.Clear()
    $all = @(l)
    if (($events -join ',') -ne 'clear,list') { throw 'l must clear before listing' }
    if ((@($all.Name | Sort-Object) -join ',') -ne 'one.txt,two.log') {
        throw 'l must list the current directory'
    }
    $events.Clear()
    $filtered = @(l -LiteralPath $args[1] -Filter '*.txt' -Name)
    if (($events -join ',') -ne 'clear,list') { throw 'l must clear before listing with arguments' }
    if ($filtered.Count -ne 1 -or $filtered[0] -ne 'one.txt') {
        throw 'l must forward directory listing arguments'
    }
} finally {
    Pop-Location
}
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))' '$($directory.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
    }

    It 'forwards arguments and input through the command shortcuts' {
        $shimDirectory = Join-Path $TestDrive 'agent-shims'
        New-Item -ItemType Directory -Path $shimDirectory | Out-Null
        foreach ($name in @('nvim', 'pi', 'codex', 'uv')) {
            Set-Content -LiteralPath (Join-Path $shimDirectory "$name.ps1") -Value @'
[pscustomobject]@{ Arguments = @($args); Incoming = @($input); ExpectingInput = $MyInvocation.ExpectingInput }
'@
        }
        $check = @'
$ErrorActionPreference = 'Stop'
. $args[0]
. $args[0]
$env:PATH = $args[1] + [IO.Path]::PathSeparator + $env:PATH
if ((Get-Alias n).Definition -ne 'nvim') { throw 'n must resolve to nvim' }
if ((Get-Alias p).Definition -ne 'pi') { throw 'p must resolve to pi' }
if ((Get-Command u).CommandType -ne 'Function') { throw 'u must be a function' }
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
    if ($name -eq 'u') { $expected = @('run', 'python') + $expected }
    $actualJson = ConvertTo-Json -InputObject $result.Arguments -Compress
    $expectedJson = ConvertTo-Json -InputObject $expected -Compress
    if ($actualJson -cne $expectedJson) { throw "Argument corruption for $name" }
    $piped = 'pipe input' | & $name --help
    if ($piped.Incoming.Count -ne 1 -or $piped.Incoming[0] -ne 'pipe input') {
        throw "Lost pipeline input for $name"
    }
}
$direct = u
if (($direct.Arguments -join ',') -ne 'run,python') { throw 'u must run Python by default' }
if ($direct.ExpectingInput) { throw 'u must not redirect input when invoked without a pipeline' }
$piped = 'first', 'second' | u -
if (($piped.Arguments -join ',') -ne 'run,python,-' -or
    ($piped.Incoming -join ',') -ne 'first,second') {
    throw 'u must pass all pipeline input to a single Python invocation'
}
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))' '$($shimDirectory.Replace("'", "''"))'"
        $LASTEXITCODE | Should -Be 0
    }

    It 'runs Python in the uv project with arguments, standard input and exit codes' {
        $cacheDirectory = Join-Path $TestDrive 'uv-cache'
        $project = Join-Path $TestDrive 'uv-project'
        New-Item -ItemType Directory -Path $project | Out-Null
        Set-Content -LiteralPath (Join-Path $project 'pyproject.toml') -Value @'
[project]
name = "powershell-u-test"
version = "0.0.0"
requires-python = ">=3.10"
'@
        $check = @'
$ErrorActionPreference = 'Stop'
$env:UV_NO_PROJECT = '0'
$env:UV_NO_SYNC = '0'
$env:UV_PYTHON_DOWNLOADS = 'never'
$env:UV_OFFLINE = '1'
$env:UV_CACHE_DIR = $args[1]
. $args[0]
Push-Location -LiteralPath $args[2]
try {
    $prefix = u -c 'import sys; print(sys.prefix)'
    if ($LASTEXITCODE -ne 0 -or $prefix -ne (Join-Path $args[2] '.venv')) {
        throw 'u must use the uv project environment'
    }
    $result = u -c 'import sys; print("|".join(sys.argv[1:]))' 'two words' '"quoted"' ''
    if ($LASTEXITCODE -ne 0 -or $result -cne 'two words|"quoted"|') {
        throw 'u must pass Python arguments unchanged'
    }
    $result = 'first line', 'second line' | u -c 'import sys; print("|".join(sys.stdin.read().splitlines()))'
    if ($LASTEXITCODE -ne 0 -or $result -cne 'first line|second line') {
        throw 'u must pass standard input to Python'
    }
    u -c 'import sys; sys.exit(23)'
    if ($LASTEXITCODE -ne 23) { throw 'u must preserve the Python exit code' }
} finally {
    Pop-Location
}
'@
        & pwsh -NoProfile -Command "& { $check } '$($profilePath.Replace("'", "''"))' '$($cacheDirectory.Replace("'", "''"))' '$($project.Replace("'", "''"))'"
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
