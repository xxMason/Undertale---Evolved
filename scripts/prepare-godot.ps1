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
# Full engine extraction: all code, objects, sprites, backgrounds, fonts and sounds.
$log2 = & $cli load $data -s (Join-Path $root 'scripts\extract_engine.csx') 2>&1 | Out-String
if ($log2 -notmatch 'UBE-ENGINE-EXTRACT ok') { Write-Host $log2; throw 'Engine extraction failed' }
Write-Host ($log2 -split "
" | Where-Object { $_ -match 'UBE-ENGINE-EXTRACT' })
New-Item -ItemType Directory -Force (Join-Path $out 'music') | Out-Null
Get-ChildItem (Join-Path $root 'source') -Filter '*.ogg' | ForEach-Object { Copy-Item $_.FullName (Join-Path $out ('music\' + $_.Name)) }
# Translate all the game's code to GDScript once, so the engine only has to compile it.
$godot = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
if (Test-Path $godot) {
    $tl = & $godot --headless --path (Join-Path $root 'godot') --script res://tools/transpile_all.gd -- --write 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^TRANSPILE|^WROTE' }
    Write-Host ($tl -join "`n")
} else {
    Write-Host 'Godot not found: the engine will translate the game code while it runs (slower first battles).'
}
Write-Host "Extracted to $out"
