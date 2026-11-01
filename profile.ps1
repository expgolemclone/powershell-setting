if ($IsWindows) {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $utf8NoBom
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
}

function l {
    Clear-Host
    Get-ChildItem @args
}

Set-Alias -Name c -Value Clear-Host
Set-Alias -Name n -Value nvim
Set-Alias -Name p -Value pi
Set-Alias -Name u -Value uv

$readableWhite = $PSStyle.Foreground.White

$PSStyle.FileInfo.Directory = $readableWhite
$PSStyle.FileInfo.SymbolicLink = $readableWhite

foreach ($extension in @('.zip', '.tgz', '.gz', '.tar', '.nupkg', '.cab', '.7z')) {
    $PSStyle.FileInfo.Extension.Remove($extension)
}

if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -Colors @{
        String  = "White"
        Comment = "`e[36m"
    }

    if ($env:WT_SESSION) {
        Set-PSReadLineKeyHandler -Chord Ctrl+c -Function CancelLine
        Remove-PSReadLineKeyHandler -Chord Ctrl+v
    }
}

(& mise.exe activate pwsh) | Out-String | Invoke-Expression
