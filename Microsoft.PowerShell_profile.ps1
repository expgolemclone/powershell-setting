function Invoke-ClearLs {
    Clear-Host
    Get-ChildItem
}

if ($IsWindows) {
    # Keep the console code page and PowerShell encodings aligned on UTF-8.
    try {
        & "$env:SystemRoot\System32\chcp.com" 65001 > $null
    }
    catch {
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $utf8NoBom
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
}

Set-Alias -Name l -Value Invoke-ClearLs
Set-Alias -Name c -Value Clear-Host
Set-Alias -Name n -Value nvim
Set-Alias -Name p -Value pi
Set-Alias -Name u -Value uv
Set-Alias -Name sudo -Value gsudo
Set-Alias -Name m -Value mdcat

function Invoke-GlowDark {
    glow --style dark @args
}

Set-Alias -Name g -Value Invoke-GlowDark

function Invoke-ListAll {
    Get-ChildItem -Force @args
}

function Copy-ItemAutoName {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Destination
    )

    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
        throw "Path must not contain wildcard characters: $Path"
    }

    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Destination)) {
        throw "Destination must not contain wildcard characters: $Destination"
    }

    $src = Get-Item -LiteralPath $Path -ErrorAction Stop
    $dest = Get-Item -LiteralPath $Destination -ErrorAction Stop

    if ($src.PSProvider.Name -ne 'FileSystem') {
        throw "Path must be a FileSystem item: $Path"
    }

    if ($dest.PSProvider.Name -ne 'FileSystem') {
        throw "Destination must be a FileSystem item: $Destination"
    }

    if (-not $dest.PSIsContainer) {
        throw "Destination must be an existing directory: $Destination"
    }

    $name = $src.Name
    if ($src.PSIsContainer) {
        $base = $name
        $ext = ''
    }
    elseif ($name.StartsWith('.') -and $name.IndexOf('.', 1) -eq -1) {
        $base = $name
        $ext = ''
    }
    else {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $ext = [System.IO.Path]::GetExtension($name)
    }

    $target = Join-Path -Path $dest.FullName -ChildPath $name
    $i = 1

    while (Test-Path -LiteralPath $target) {
        $targetName = "{0}-{1}{2}" -f $base, $i, $ext
        $target = Join-Path -Path $dest.FullName -ChildPath $targetName
        $i++
    }

    $copyArgs = @{
        LiteralPath = $src.FullName
        Destination = $target
        ErrorAction = 'Stop'
    }

    if ($src.PSIsContainer) {
        $copyArgs.Recurse = $true
    }

    if ($PSCmdlet.ShouldProcess($src.FullName, "Copy to $target")) {
        Copy-Item @copyArgs
    }
}

Set-Alias -Name la -Value Invoke-ListAll
# Keep the built-in cp alias semantics intact for agents and scripts.
Set-Alias -Name cpa -Value Copy-ItemAutoName

function Invoke-Tree {
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',
        [int]$L = 0,
        [switch]$a,
        [switch]$d,
        [switch]$f
    )

    $targetPath = Resolve-Path -LiteralPath $Path

    # Box-drawing characters (PS 5.1 compatible)
    $tee = [char]0x251C # |-
    $elbow = [char]0x2514 # L-
    $pipe = [char]0x2502 # |
    $dash = [char]0x2500 # -
    $branch = "${dash}${dash}"

    $script:dirCount = 0
    $script:fileCount = 0

    function Show-Tree {
        param(
            [string]$Path,
            [string]$Prefix,
            [int]$Depth
        )

        if ($L -gt 0 -and $Depth -ge $L) { return }

        $getArgs = @{ LiteralPath = $Path; ErrorAction = "SilentlyContinue" }
        if ($a) { $getArgs["Force"] = $true }

        $items = Get-ChildItem @getArgs | Sort-Object { -not $_.PSIsContainer }, Name
        if ($d) { $items = $items | Where-Object { $_.PSIsContainer } }

        $count = ($items | Measure-Object).Count
        $i = 0

        foreach ($item in $items) {
            $i++
            $isLast = ($i -eq $count)
            $connector = if ($isLast) { "${elbow}${branch}" } else { "${tee}${branch}" }
            $displayName = if ($f) { $item.FullName } else { $item.Name }

            Write-Host "${Prefix}${connector} ${displayName}"

            if ($item.PSIsContainer) {
                $script:dirCount++
                $childPrefix = if ($isLast) { "${Prefix}    " } else { "${Prefix}${pipe}   " }
                # Directory links are leaves: following junctions can escape the root or cycle.
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                    Show-Tree -Path $item.FullName -Prefix $childPrefix -Depth ($Depth + 1)
                }
            }
            else {
                $script:fileCount++
            }
        }
    }

    Write-Host "."
    Show-Tree -Path $targetPath -Prefix "" -Depth 0

    $summary = "`n${script:dirCount} directories"
    if (-not $d) { $summary += ", ${script:fileCount} files" }
    Write-Host $summary
}

# Use the faster PowerShell implementation as `tree`; call `tree.exe` explicitly for the Windows native command.
Set-Alias -Name tree -Value Invoke-Tree

$readableWhite = $PSStyle.Foreground.White

$PSStyle.FileInfo.Directory = $readableWhite
$PSStyle.FileInfo.SymbolicLink = $readableWhite

# Ordinary archives and packages use the terminal's default text color, not error red.
foreach ($extension in @('.zip', '.tgz', '.gz', '.tar', '.nupkg', '.cab', '.7z')) {
    $PSStyle.FileInfo.Extension.Remove($extension)
}

if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -Colors @{
        String  = "White"
        Comment = "`e[36m"
    }

    if ($env:WT_SESSION) {
        # Windows Terminal owns Ctrl+Shift+C/V. Keep Ctrl+C for cancellation at the prompt.
        Set-PSReadLineKeyHandler -Chord Ctrl+c -Function CancelLine
        Remove-PSReadLineKeyHandler -Chord Ctrl+v
    }
}

function prompt {
    $loc = $executionContext.SessionState.Path.CurrentLocation
    $Host.UI.RawUI.WindowTitle = $loc.Path

    $out = ""
    if ($env:WT_SESSION -and $loc.Provider.Name -eq "FileSystem") {
        $out += "$([char]27)]9;9;`"$($loc.ProviderPath)`"$([char]27)\"
    }

    $out += "PS $loc$('>' * ($nestedPromptLevel + 1)) "
    return $out
}

(& mise.exe activate pwsh) | Out-String | Invoke-Expression
