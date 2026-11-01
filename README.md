# PowerShell profile

This repository is the canonical source for the current-user PowerShell 7 profile.

PowerShell loads the profile only from its standard directory. Connect that directory to this repository with the setup script.

```powershell
pwsh -NoProfile -File .\setup.ps1
```

The script creates a directory junction to this repository. Rerun it after moving the repository. It refuses to overwrite user files or a junction with another live target.

Run profile regression tests with `Invoke-Pester -Path ./tests -EnableExit` in PowerShell 7.

In Windows Terminal, PSReadLine uses `Ctrl+C` to cancel the input line and leaves `Ctrl+V` unbound. Windows Terminal handles copying and pasting with `Ctrl+Shift+C` and `Ctrl+Shift+V` through the separate `windows-terminal-config` repository.
