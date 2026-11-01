[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
$profileDirectory = [IO.Path]::GetFullPath(
    (Split-Path -Parent $PROFILE.CurrentUserCurrentHost)
).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
$profileParent = Split-Path -Parent $profileDirectory
$profileLeaf = Split-Path -Leaf $profileDirectory

$existingItem = if (Test-Path -LiteralPath $profileParent -PathType Container) {
    Get-ChildItem -LiteralPath $profileParent -Force |
        Where-Object Name -EQ $profileLeaf |
        Select-Object -First 1
}

if ($null -ne $existingItem) {
    if ($existingItem.LinkType -ne 'Junction') {
        if (($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "PowerShell profile path is a reparse point and cannot be replaced: $profileDirectory"
        }
        $descendants = if ($existingItem.PSIsContainer) {
            @(Get-ChildItem -LiteralPath $profileDirectory -Force -Recurse)
        }
        else {
            @()
        }
        $unsafeDescendants = @($descendants | Where-Object {
                -not $_.PSIsContainer -or
                ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            })
        if (-not $existingItem.PSIsContainer -or $unsafeDescendants.Count -ne 0) {
            throw "PowerShell profile path contains files or reparse points and cannot be replaced: $profileDirectory"
        }
        if ($PSCmdlet.ShouldProcess($profileDirectory, "Remove profile directory tree containing no files")) {
            Remove-Item -LiteralPath $profileDirectory -Recurse -Force
        }
        $existingItem = $null
    }
    if ($null -ne $existingItem) {
        $existingTarget = [IO.Path]::GetFullPath([string]$existingItem.Target).TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        if ([string]::Equals($existingTarget, $repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "PowerShell profile junction is already configured: $profileDirectory"
            return
        }

        if (Test-Path -LiteralPath $existingTarget -PathType Container) {
            throw "PowerShell profile junction points to another existing directory: $existingTarget"
        }

        if ($PSCmdlet.ShouldProcess($profileDirectory, "Remove stale junction to $existingTarget")) {
            Remove-Item -LiteralPath $profileDirectory -Force
        }
    }
}

if ($PSCmdlet.ShouldProcess($profileDirectory, "Create junction to $repositoryRoot")) {
    New-Item -ItemType Directory -Path $profileParent -Force | Out-Null
    $junction = New-Item -ItemType Junction -Path $profileDirectory -Target $repositoryRoot
    Write-Host "PowerShell profile junction created: $($junction.FullName) -> $repositoryRoot"
}
