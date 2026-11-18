# Quick regression check, meant to run before every commit (scripts\install-hooks.ps1 makes
# Git run it automatically). Never starts the real game: every comparison uses traces the
# real game already recorded.
#
#   powershell -ExecutionPolicy Bypass -File scripts\check.ps1          # ~2 minutes
#   powershell -ExecutionPolicy Bypass -File scripts\check.ps1 -Full    # + every saved trace in logs\trace
#
# Quick: the frame-by-frame traces kept in tests\ (Vegetoid, Mad Dummy, Undyne the Undying,
# Moldbygg), the collision probe, a bug report replay, the mod manifest fixtures and a
# scripted run of the real game from its first room into the Ruins.
# Full: also every real_g*_s42_lv20_f1500.txt in logs\trace (51 battles, ~20 minutes).
# Exit code 0 when everything agrees.
param([switch]$Full)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$godot = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$gd = Join-Path $root 'godot'
$tc = Join-Path $PSScriptRoot 'trace-compare.ps1'
$fail = 0
$t0 = Get-Date

function Say($ok, $what, $detail) {
    $script:fail += [int](-not $ok)
    Write-Host ("{0}  {1}{2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $what, $(if ($detail) { "  ($detail)" } else { '' }))
}

if (-not (Test-Path $godot) -or -not (Test-Path (Join-Path $gd 'extracted\engine.json'))) {
    Write-Host 'Godot or godot\extracted is missing (run scripts\prepare-godot.ps1).'
    exit 2
}

$traces = @(
    @{ g = 18; f = 535; file = 'tests\trace_g18_vegetoid.txt' },
    @{ g = 45; f = 330; file = 'tests\trace_g45_maddummy.txt' },
    @{ g = 92; f = 700; file = 'tests\trace_g92_undying.txt' },
    @{ g = 55; f = 600; file = 'tests\trace_g55_moldbygg.txt' }
)
if ($Full) {
    foreach ($f in Get-ChildItem (Join-Path $root 'logs\trace') -Filter 'real_g*_s42_lv20_f1500.txt' -ErrorAction SilentlyContinue) {
        $g = [int]($f.Name -replace '^real_g(\d+)_.*', '$1')
        $traces += @{ g = $g; f = 1500; file = $f.FullName }
    }
}
foreach ($t in $traces) {
    $file = if ([IO.Path]::IsPathRooted($t.file)) { $t.file } else { Join-Path $root $t.file }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $tc -Group $t.g -Seed 42 -Lv 20 -Frames $t.f -RealTrace $file 2>&1 | ForEach-Object { "$_" }
    $line = ($out | Where-Object { $_ -match '^MATCH|^FIRST DIFF' } | Select-Object -First 1)
    Say ($LASTEXITCODE -eq 0) ("trace G{0} ({1})" -f $t.g, (Split-Path -Leaf $file)) $(if ($LASTEXITCODE -eq 0) { '' } else { $line })
}

$cp = & $godot --headless --path $gd -- --collprobe 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^COLL' }
$cref = (Get-Content (Join-Path $root 'tests\coll_probe_reference.txt') -Raw).Trim()
Say (("$cp" -join "`n").Trim() -eq $cref -or "$cp".Trim() -eq $cref) 'collision probe' ''

$rd = Join-Path $env:TEMP 'ube_check_report'
Remove-Item -Recurse -Force $rd -ErrorAction SilentlyContinue
& $godot --headless --path $gd -- --battle 47 --lv 1 --frames 400 --reportat 250 $rd 2>&1 | Out-Null
$pb = & $godot --headless --path $gd -- --playback (Join-Path $rd 'replay.json') 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^PLAYBACK CHECK' }
Say ($LASTEXITCODE -eq 0 -and "$pb" -match 'MATCH') 'bug report replay' $(if ("$pb" -match 'MATCH') { '' } else { "$pb" })

$mo = (& $godot --headless --path $gd -- --mods --modsdir (Join-Path $root 'tests\mods') 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^MODS ' }) -join ''
Say ($mo -match 'loaded=2 problems=3') 'mod manifests' $mo

# The overworld: the walkthrough bot (godot/game_bot.gd) plays tests\walkthrough_ruins.txt from
# the first room through the Ruins and Toriel's house to Snowdin's first room, with
# a fixed seed and a throwaway save folder, checking the story state at every section.
$gs = Join-Path $env:TEMP 'ube_check_saves'
$walk = Join-Path $root 'tests\walkthrough_ruins.txt'
$go = & $godot --headless --path $gd -- --game --unknown --seed 7 --savedir $gs --frames 34000 --bot $walk 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^GAME|^UNKNOWN|SCRIPT ERROR|^BOT (FAIL|FINISHED)|^BOT f=\d+ FAIL' }
$gok = ("$go" -match 'BOT FINISHED') -and ("$go" -match 'in room_tundra1, \d+ instances, player [\d.]+,[\d.]+, plot 30') -and -not ("$go" -match 'UNKNOWN|SCRIPT ERROR') -and (Test-Path (Join-Path $gs 'file0'))
Say $gok 'game: walkthrough from the intro through the Ruins and Toriel to Snowdin, with saves' $(if ($gok) { '' } else { "$go" })
$st = & $godot --headless --path $gd -- --game --unknown --seed 7 --savedir $gs --room room_ruins7 --set plot=9 --frames 6000 --bot (Join-Path $root 'tests\stress_ruins.txt') 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^UNKNOWN|SCRIPT ERROR|^BOT (FAIL|FINISHED)|^BOT f=\d+ FAIL' }
$sok = ("$st" -match 'BOT FINISHED') -and -not ("$st" -match 'UNKNOWN|SCRIPT ERROR|FAIL')
Say $sok 'game: encounters and talking while walking (stress)' $(if ($sok) { '' } else { "$st" })
$dt = & $godot --headless --path $gd -- --game --seed 7 --savedir (Join-Path $env:TEMP 'ube_debug_saves') --room room_ruins7 --set plot=9.2 --frames 400 --debugtest 60 --debugtest2 250 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^DEBUGTEST|SCRIPT ERROR' }
$dok = ("$dt" -match 'DEBUGTEST done, 0 failed') -and ("$dt" -match 'DEBUGTEST2 done') -and -not ("$dt" -match 'DEBUGTEST FAIL|SCRIPT ERROR')
Say $dok 'debug menu (F5): every part used once' $(if ($dok) { '' } else { "$dt" })

$secs = [int]((Get-Date) - $t0).TotalSeconds
if ($fail -eq 0) { Write-Host "All checks passed in $secs s." } else { Write-Host "$fail check(s) FAILED ($secs s)." }
exit $(if ($fail -eq 0) { 0 } else { 1 })
