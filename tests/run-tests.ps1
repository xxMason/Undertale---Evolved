# Repeatable end-to-end tests. Launches the real patched game several times (a window will
# open and play by itself) and proves the original installation and saves are untouched.
# Usage: powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root 'UltimateBattleEngine.exe'
if (-not (Test-Path $exe)) { & (Join-Path $root 'scripts\build.ps1') }

function Get-Snapshot([string[]]$dirs) {
    $s = @{}
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { $s["$d|<dir>"] = 'absent'; continue }
        $s["$d|<dir>"] = 'present'
        Get-ChildItem -LiteralPath $d -Recurse -File | ForEach-Object {
            $s[$_.FullName] = '{0}:{1}:{2}' -f $_.Length, $_.LastWriteTimeUtc.Ticks, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }
    $s
}

# What must stay untouched: the launcher's verified copy of the original game (source\),
# the Steam folder the game was first found in (whatever is in it now), and the original
# save location.
$watched = @((Join-Path $root 'source'), 'C:\Program Files (x86)\Steam\steamapps\common\Undertale', (Join-Path $env:LOCALAPPDATA 'UNDERTALE'))

# Independent snapshot (hash + size + modified time), separate from the launcher's own check.
$before = Get-Snapshot $watched
$results = @()
$profile = Join-Path $root 'profiles\default.json'

foreach ($scenario in 'menu', 'keys', 'ui', 'wasd', 'gear', 'train', 'custom', 'custom_spare', 'editor', 'timeline', 'live', 'record', 'record2', 'win', 'lose', 'lose_then_win') {
    # The scenarios drive the game with simulated key presses, which the runner drops if
    # its window loses focus (for example when someone uses the PC during the run). A
    # failed scenario is retried once, and the report says so when that happens.
    $note = ''
    foreach ($attempt in 1, 2) {
        $out = & $exe --profile $profile --selftest $scenario 2>&1
        $code = $LASTEXITCODE
        if ($code -eq 0) { break }
        $note = '[first attempt failed; ' + $(if ($attempt -eq 1) { 'passed on retry' } else { 'retry failed too' }) + '] '
    }
    if ($code -ne 0) { $note = '[failed twice] ' }
    $game = ($out | Where-Object { $_ -match '^\s+game> ' } | ForEach-Object { ($_ -replace '^\s+game> ', '') }) -join ' | '
    $results += [pscustomobject]@{ Test = "selftest $scenario"; Pass = ($code -eq 0); Detail = $note + $game }
}

# Negative tests: the launcher must refuse rather than guess.
$fake = Join-Path $env:TEMP ('ube-fake-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fake | Out-Null
& $exe --undertale $fake --prepare-only --no-pause 2>&1 | Out-Null
$results += [pscustomobject]@{ Test = 'missing game files are refused (exit 2)'; Pass = ($LASTEXITCODE -eq 2); Detail = "exit $LASTEXITCODE" }
Set-Content -LiteralPath (Join-Path $fake 'data.win') -Value 'not undertale'
Set-Content -LiteralPath (Join-Path $fake 'UNDERTALE.exe') -Value 'not undertale'
& $exe --undertale $fake --prepare-only --no-pause 2>&1 | Out-Null
$results += [pscustomobject]@{ Test = 'unknown game version is refused (exit 2)'; Pass = ($LASTEXITCODE -eq 2); Detail = "exit $LASTEXITCODE" }
Remove-Item $fake -Recurse -Force

& $exe --profile $profile --prepare-only --no-pause 2>&1 | Out-Null   # leave the default setup behind

# Godot prototype: replay the recorded real-game fight through the Godot battle rules.
$godot = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
if ((Test-Path $godot) -and (Test-Path (Join-Path $root 'godot\extracted\assets.json'))) {
    foreach ($ref in 'record_reference', 'record2_reference') {
        $rep = & $godot --headless --path (Join-Path $root 'godot') --script res://replay.gd -- (Join-Path $root "tests\$ref.txt") 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^REPLAY|^  frame' }
        $results += [pscustomobject]@{ Test = "Godot battle rules match the real game ($ref)"; Pass = ($LASTEXITCODE -eq 0); Detail = ($rep -join ' | ') }
    }
} else {
    $results += [pscustomobject]@{ Test = 'Godot battle rules match the recorded real fight'; Pass = $false; Detail = 'skipped: Godot or godot\extracted missing (run scripts\prepare-godot.ps1)' }
}

# Godot engine running the original battle code (Godot prints harmless leak warnings on stderr).
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
if ((Test-Path $godot) -and (Test-Path (Join-Path $root 'godot\extracted\engine.json'))) {
    $gd = Join-Path $root 'godot'
    $rep = & $godot --headless --path $gd --script res://tools/parse_all.gd 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^PARSE' }
    $results += [pscustomobject]@{ Test = 'Godot engine parses all original code'; Pass = ($rep -match 'failed=0'); Detail = ($rep -join ' | ') }
    # Quick battles: Froggit and Dummy must be won; Papyrus (blue SOUL), Undyne (green),
    # Muffet (purple) and Mettaton EX (yellow) must reach later turns without script errors.
    $sw = & $godot --headless --path $gd -- --lv 20 --frames 1500 --sweep 0 1 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^SWEEP|SCRIPT ERROR' }
    $won = @($sw | Where-Object { $_ -match 'YOU WON' }).Count
    $results += [pscustomobject]@{ Test = 'Godot engine wins Dummy and Froggit'; Pass = ($won -eq 2 -and -not ($sw -match 'SCRIPT ERROR')); Detail = ($sw -join ' | ') }
    # Collision rounding: the probe script's results in Godot must equal the real runner's
    # (tests\coll_probe_reference.txt, logged by the real game in the trace scenario).
    $cp = & $godot --headless --path $gd -- --collprobe 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^COLL' }
    $cref = (Get-Content (Join-Path $root 'tests\coll_probe_reference.txt') -Raw).Trim()
    $results += [pscustomobject]@{ Test = 'Godot collision rounding matches the real runner (probe)'; Pass = ("$cp".Trim() -eq $cref); Detail = $(if ("$cp".Trim() -eq $cref) { '' } else { "godot: $cp" }) }
    # Frame-by-frame traces recorded from the real game (numbers only): same keys, same seed,
    # every frame's HP, invincibility, SOUL position and object checksum must agree.
    foreach ($tr in @(@{ g = 18; f = 535; file = 'trace_g18_vegetoid.txt' }, @{ g = 45; f = 330; file = 'trace_g45_maddummy.txt' }, @{ g = 92; f = 700; file = 'trace_g92_undying.txt' }, @{ g = 55; f = 600; file = 'trace_g55_moldbygg.txt' })) {
        $tf = Join-Path $root "tests\$($tr.file)"
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\trace-compare.ps1') -Group $tr.g -Seed 42 -Lv 20 -Frames $tr.f -RealTrace $tf 2>&1 | ForEach-Object { "$_" }
        $results += [pscustomobject]@{ Test = "Godot matches the real game frame by frame ($($tr.file))"; Pass = ($LASTEXITCODE -eq 0); Detail = (($out | Where-Object { $_ -match '^MATCH|^FIRST DIFF|^FRAMES' }) -join ' | ') }
    }
    # Bug reports: a fight saved at frame 250 must replay to the same state, and the same
    # recording with a different seed must be caught.
    $rd = Join-Path $env:TEMP 'ube_test_report'
    Remove-Item -Recurse -Force $rd -ErrorAction SilentlyContinue
    $rep = & $godot --headless --path $gd -- --battle 47 --lv 1 --frames 400 --reportat 250 $rd 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^REPORT|SCRIPT ERROR' }
    $pb = & $godot --headless --path $gd -- --playback (Join-Path $rd 'replay.json') 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^PLAYBACK CHECK|SCRIPT ERROR' }
    $pbOk = ($LASTEXITCODE -eq 0) -and (($pb -join ' ') -match 'MATCH')
    $results += [pscustomobject]@{ Test = 'Bug report replays to the same state (Asriel, frame 250)'; Pass = $pbOk; Detail = (@($rep) + @($pb)) -join ' | ' }
    $badJson = Join-Path $rd 'tampered.json'
    if (Test-Path (Join-Path $rd 'replay.json')) {
        ((Get-Content (Join-Path $rd 'replay.json') -Raw) -replace '"seed": \d+', '"seed": 12345') | Set-Content -Encoding ascii $badJson
    }
    $pb2 = & $godot --headless --path $gd -- --playback $badJson 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^PLAYBACK CHECK' }
    $results += [pscustomobject]@{ Test = 'A replay with the wrong seed is reported as different'; Pass = ($LASTEXITCODE -ne 0 -and (($pb2 -join ' ') -match 'DIFF')); Detail = ($pb2 -join ' | ') }
    # Mod manifests: tests\mods holds two good mods (one must load after the other), one
    # switched off and three that must be refused, each for its own reason.
    $mo = & $godot --headless --path $gd -- --mods --modsdir (Join-Path $root 'tests\mods') 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^MOD' }
    $mj = $mo -join "`n"
    $modsOk = ($mj -match 'MODS loaded=2 problems=3') -and ($mj.IndexOf('MOD tester.base_tweaks') -lt $mj.IndexOf('MOD tester.after_tweaks')) -and ($mj -match 'DISABLED tester.switched_off') -and ($mj -match 'bad_id: id') -and ($mj -match 'too_new: needs engine') -and ($mj -match 'needs nobody.not_installed')
    $results += [pscustomobject]@{ Test = 'Mod manifests: load order, switched-off mods and refusals'; Pass = $modsOk; Detail = $(if ($modsOk) { '' } else { $mo -join ' | ' }) }
    # The overworld (game mode), with a throwaway save folder: the walkthrough bot plays to
    # Snowdin, then every Ruins room is loaded on its own, with nothing missing.
    $gs = Join-Path $env:TEMP 'ube_test_saves'
    $walk = Join-Path $root 'tests\walkthrough_ruins.txt'
    $go = & $godot --headless --path $gd -- --game --unknown --seed 7 --savedir $gs --frames 34000 --bot $walk 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^GAME|^UNKNOWN|SCRIPT ERROR|^BOT (FAIL|FINISHED)|^BOT f=\d+ FAIL' }
    $gok = ("$go" -match 'BOT FINISHED') -and ("$go" -match 'in room_tundra1, \d+ instances, player [\d.]+,[\d.]+, plot 30') -and -not ("$go" -match 'UNKNOWN|SCRIPT ERROR') -and (Test-Path (Join-Path $gs 'file0'))
    $results += [pscustomobject]@{ Test = 'Game: walkthrough from the intro through the Ruins and Toriel to Snowdin, with saves'; Pass = $gok; Detail = ($go -join ' | ') }
    $st = & $godot --headless --path $gd -- --game --unknown --seed 7 --savedir $gs --room room_ruins7 --set plot=9 --frames 6000 --bot (Join-Path $root 'tests\stress_ruins.txt') 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^UNKNOWN|SCRIPT ERROR|^BOT (FAIL|FINISHED)|^BOT f=\d+ FAIL' }
    $sok = ("$st" -match 'BOT FINISHED') -and -not ("$st" -match 'UNKNOWN|SCRIPT ERROR|FAIL')
    $results += [pscustomobject]@{ Test = 'Game: encounters and talking while walking (stress)'; Pass = $sok; Detail = ($st -join ' | ') }
    $dt = & $godot --headless --path $gd -- --game --seed 7 --savedir (Join-Path $env:TEMP 'ube_debug_saves') --room room_ruins7 --set plot=9.2 --frames 400 --debugtest 60 --debugtest2 250 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^DEBUGTEST|SCRIPT ERROR' }
    $dok = ("$dt" -match 'DEBUGTEST done, 0 failed') -and ("$dt" -match 'DEBUGTEST2 done') -and -not ("$dt" -match 'DEBUGTEST FAIL|SCRIPT ERROR')
    $results += [pscustomobject]@{ Test = 'Debug menu (F5): every part used once'; Pass = $dok; Detail = ($dt -join ' | ') }
    $ruins = 'room_ruins1','room_ruins2','room_ruins3','room_ruins4','room_ruins5','room_ruins6','room_ruins7','room_ruins7A','room_ruins8','room_ruins9','room_ruins10','room_ruins11','room_ruins12','room_ruins12A','room_ruins12B','room_ruins13','room_ruins14','room_ruins15A','room_ruins15B','room_ruins15C','room_ruins15D','room_ruins15E','room_ruins16','room_ruins17','room_ruins18OLD','room_ruins19','room_torhouse1','room_torhouse2','room_torhouse3','room_basement1','room_basement2','room_basement3','room_basement4','room_basement5','room_ruinsexit'
    $bad = @()
    foreach ($r in $ruins) {
        $o = & $godot --headless --path $gd -- --game --unknown --seed 7 --savedir $gs --room $r --frames 150 --press '20:39x40,70:40x40,110:90x2' 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^GAME|^UNKNOWN|SCRIPT ERROR|^\[gml\]' -and $_ -notmatch 'missing sound 135' }
        if (-not ("$o" -match 'GAME stopped') -or "$o" -match 'UNKNOWN|SCRIPT ERROR|\[gml\]') { $bad += "${r}: $o" }
    }
    $results += [pscustomobject]@{ Test = "Game: all $($ruins.Count) Ruins rooms load and run"; Pass = ($bad.Count -eq 0); Detail = ($bad -join ' | ') }
    foreach ($b in 22, 30, 37, 38) {
        $sw = & $godot --headless --path $gd -- --lv 20 --frames 1500 --sweep $b $b 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^SWEEP|SCRIPT ERROR' }
        $turn = if (($sw -join ' ') -match 'turn=(\d+)') { [int]$matches[1] } else { 0 }
        $results += [pscustomobject]@{ Test = "Godot engine runs battle $b through several turns"; Pass = ($turn -ge 2 -and -not ($sw -match 'SCRIPT ERROR')); Detail = ($sw -join ' | ') }
    }
} else {
    $results += [pscustomobject]@{ Test = 'Godot engine runs the original battle code'; Pass = $false; Detail = 'skipped: Godot or godot\extracted\engine.json missing (run scripts\prepare-godot.ps1)' }
}
$ErrorActionPreference = $eap
$after = Get-Snapshot $watched
$changed = @()
foreach ($k in $before.Keys) { if (-not $after.ContainsKey($k)) { $changed += "removed $k" } elseif ($after[$k] -ne $before[$k]) { $changed += "modified $k" } }
foreach ($k in $after.Keys) { if (-not $before.ContainsKey($k)) { $changed += "added $k" } }
$results += [pscustomobject]@{ Test = "originals unchanged ($($before.Count) entries: verified copy, Steam folder, %LOCALAPPDATA%\UNDERTALE)"; Pass = ($changed.Count -eq 0); Detail = ($changed -join '; ') }

$tracked = & git -C $root ls-files
$bad = $tracked | Where-Object { $_ -match '\.(win|ogg|exe|dll|zip)$' -or $_ -match '^(game|tools|build|source)/' }
$results += [pscustomobject]@{ Test = 'no game assets or binaries tracked by Git'; Pass = (-not $bad); Detail = ($bad -join '; ') }

$results | ForEach-Object { '{0}  {1}{2}' -f $(if ($_.Pass) { 'PASS' } else { 'FAIL' }), $_.Test, $(if ($_.Detail) { "`n        $($_.Detail)" } else { '' }) }
$failed = @($results | Where-Object { -not $_.Pass }).Count
"`n$($results.Count - $failed)/$($results.Count) passed"
exit $failed
