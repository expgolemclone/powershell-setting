[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$profilePath = $PROFILE.CurrentUserCurrentHost

if ($PSCmdlet.ShouldProcess($profilePath, 'Create PowerShell profile symbolic link')) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path $profilePath -Target (
        Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1'
    ) | Out-Null
}
