[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/')
$profileDirectory = [IO.Path]::GetFullPath(
    (Split-Path -Parent $PROFILE.CurrentUserCurrentHost)
).TrimEnd('\', '/')

try {
    $existingItem = Get-Item -LiteralPath $profileDirectory -Force -ErrorAction Stop
}
catch [System.Management.Automation.ItemNotFoundException] {
    $existingItem = $null
}
if ($null -ne $existingItem) {
    if ($existingItem.LinkType -eq 'Junction' -and
        [IO.Path]::GetFullPath([string]$existingItem.Target).TrimEnd('\', '/') -ieq $repositoryRoot) {
        return
    }
    throw "PowerShell profile path already exists and cannot be replaced: $profileDirectory"
}

if ($PSCmdlet.ShouldProcess($profileDirectory, "Create junction to $repositoryRoot")) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $profileDirectory) -Force | Out-Null
    New-Item -ItemType Junction -Path $profileDirectory -Target $repositoryRoot | Out-Null
}
