if ($IsWindows) {
    # Keep the console code page and PowerShell encodings aligned on UTF-8.
    & "$env:SystemRoot\System32\chcp.com" 65001 > $null

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $utf8NoBom
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
}

Set-Alias -Name c -Value Clear-Host
Set-Alias -Name n -Value nvim
Set-Alias -Name p -Value pi
Set-Alias -Name u -Value uv
Set-Alias -Name g -Value glow

$readableWhite = $PSStyle.Foreground.White

$PSStyle.FileInfo.Directory = $readableWhite
$PSStyle.FileInfo.SymbolicLink = $readableWhite

# Ordinary archives and packages use the terminal's default text color, not error red.
foreach ($extension in @('.zip', '.tgz', '.gz', '.tar', '.nupkg', '.cab', '.7z')) {
    $PSStyle.FileInfo.Extension.Remove($extension)
}

Set-PSReadLineOption -Colors @{
    String  = "White"
    Comment = "`e[36m"
}

if ($env:WT_SESSION) {
    # Windows Terminal owns Ctrl+Shift+C/V. Keep Ctrl+C for cancellation at the prompt.
    Set-PSReadLineKeyHandler -Chord Ctrl+c -Function CancelLine
    Remove-PSReadLineKeyHandler -Chord Ctrl+v
}

(& mise.exe activate pwsh) | Out-String | Invoke-Expression
