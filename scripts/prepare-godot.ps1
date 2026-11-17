# Extracts the assets the Godot prototype needs from the verified copy of the original
# game (source\, made by the launcher) into godot\extracted\. Nothing extracted is
# committed; godot\extracted\ is in .gitignore and has a .gdignore so Godot does not
# import it (the prototype loads the files at runtime).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$data = Join-Path $root 'source\data.win'
if (-not (Test-Path $data)) { throw "No verified copy of the game in source\. Run UltimateBattleEngine.exe once first." }
$cli = Join-Path $root 'tools\utmt-cli\UndertaleModCli.exe'
$out = Join-Path $root 'godot\extracted'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null
Set-Content -Path (Join-Path $out '.gdignore') -Value '' -Encoding ascii
$env:UBE_GODOT_OUT = $out
$log = & $cli load $data -s (Join-Path $root 'scripts\extract_for_godot.csx') 2>&1 | Out-String
if ($log -notmatch 'UBE-GODOT-EXTRACT ok') { Write-Host $log; throw 'Extraction failed' }
New-Item -ItemType Directory -Force (Join-Path $out 'music') | Out-Null
Copy-Item (Join-Path $root 'source\mus_battle1.ogg') (Join-Path $out 'music\mus_battle1.ogg')
Write-Host "Extracted to $out"
