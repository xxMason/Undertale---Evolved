# Makes Git run scripts\check.ps1 before every commit in this clone (about 2 minutes).
# A failing check stops the commit; `git commit --no-verify` skips it when you really mean to.
#
#   powershell -ExecutionPolicy Bypass -File scripts\install-hooks.ps1            # install
#   powershell -ExecutionPolicy Bypass -File scripts\install-hooks.ps1 -Remove    # remove
param([switch]$Remove)
$root = Split-Path -Parent $PSScriptRoot
$hook = Join-Path $root '.git\hooks\pre-commit'
if ($Remove) {
    if (Test-Path $hook) { Remove-Item $hook; Write-Host 'Pre-commit check removed.' } else { Write-Host 'No pre-commit hook installed.' }
    exit 0
}
if ((Test-Path $hook) -and -not ((Get-Content $hook -Raw) -match 'scripts/check.ps1')) {
    Write-Host "A different pre-commit hook already exists ($hook); leaving it alone."
    exit 1
}
$body = "#!/bin/sh`n# Installed by scripts/install-hooks.ps1: runs the quick regression check.`nexec powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/check.ps1`n"
[IO.File]::WriteAllText($hook, $body)
Write-Host "Pre-commit check installed: $hook"
