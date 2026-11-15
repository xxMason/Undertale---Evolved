# Builds UltimateBattleEngine.exe (the launcher) with the C# compiler that ships with Windows.
# The patched game working copy is built by the launcher itself on first run (or --rebuild).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw '.NET Framework 4 C# compiler (csc.exe) not found.' }
$out = Join-Path $root 'UltimateBattleEngine.exe'
& $csc /nologo /target:exe /platform:anycpu /optimize+ "/out:$out" /r:System.Web.Extensions.dll (Join-Path $root 'launcher\Program.cs')
if ($LASTEXITCODE -ne 0) { throw "csc failed with exit code $LASTEXITCODE" }
Write-Host "Built $out"
