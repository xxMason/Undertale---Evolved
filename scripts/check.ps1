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
# Stage 4: a friend joins over the network (this PC, port 7791), walks, reads the sign and
# leaves; the host checks what happened in its game.
$nh = Join-Path $env:TEMP 'ube_check_net_host.txt'
$hostp = Start-Process -FilePath $godot -ArgumentList @('--headless', '--path', "`"$gd`"", '--', '--seed', '7', '--savedir', "`"$(Join-Path $env:TEMP 'ube_check_net')`"", '--room', 'room_ruins9', '--set', 'plot=9.2', '--frames', '400', '--mphost', '7791', '--mpname', 'Kyle', '--mpcheck', 'net', '--tps', '60') -RedirectStandardOutput $nh -RedirectStandardError "$nh.err" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
$no = & $godot --headless --path $gd -- --mpjoin 127.0.0.1:7791 --mpname Greg --frames 240 --tps 60 --press '20:39x7,30:38x25,70:90x2,110:90x2,150:90x2,190:90x2' 2>&1 | ForEach-Object { "$_" }
if (-not $hostp.WaitForExit(60000)) { $hostp.Kill() }
$nho = @(Get-Content $nh -ErrorAction SilentlyContinue | Where-Object { $_ -match '^MPCHECK|SCRIPT ERROR' })
$nok = ("$nho" -match 'MPCHECK net done, 0 failed') -and -not ("$nho $no" -match 'SCRIPT ERROR')
Say $nok 'network: a friend joins, walks, reads and leaves' $(if ($nok) { '' } else { (@($nho | Where-Object { $_ -match 'FAIL|ERROR' }) + @($no | Where-Object { $_ -match 'ERROR' }) -join '; ') })

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

# Title screen, universes and co-op.
$ut = Join-Path $env:TEMP 'ube_check_universes'
Remove-Item -Recurse -Force $ut -ErrorAction SilentlyContinue
$uo = (& $godot --headless --path $gd -- --unitest --universesdir $ut 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^UNITEST|SCRIPT ERROR' }) -join "`n"
Say ($uo -match 'UNITEST done, 0 failed' -and -not ($uo -match 'SCRIPT ERROR')) 'universes' $uo
$fo = (& $godot --headless --path $gd -- --fronttest --universesdir $ut 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^FRONTTEST|SCRIPT ERROR' }) -join "`n"
Say ($fo -match 'FRONTTEST done, 0 failed' -and -not ($fo -match 'SCRIPT ERROR')) 'title screen' $fo
$so = (& $godot --headless --path $gd -- --game --seed 7 --savedir (Join-Path $env:TEMP 'ube_check_coopsave') --room room_ruins7 --set plot=9.2 --coopsavetest 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^COOPSAVE|SCRIPT ERROR' }) -join "`n"
Say ($so -match 'COOPSAVE done, all ok' -and -not ($so -match 'SCRIPT ERROR')) 'co-op saves (both characters)' $so
$sn = (& $godot --headless --path $gd -- --game --seed 7 --savedir (Join-Path $env:TEMP 'ube_check_snap') --room room_ruins7 --set plot=9.2 --snaptest 120 60 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^SNAPTEST|SCRIPT ERROR' }) -join "`n"
Say ($sn -match ': same' -and -not ($sn -match 'SCRIPT ERROR')) 'co-op state snapshot' $sn
# Two games on this PC, linked: the host walks into a battle in the Ruins and plays MERCY
# (the friend starts on 1 HP, goes down, and is revived after 3 turns). Both must end in
# exactly the same state.
$cu = Join-Path $env:TEMP 'ube_check_coop'
Remove-Item -Recurse -Force $cu -ErrorAction SilentlyContinue
$walkp = (0..40 | ForEach-Object { $a = 80 + $_ * 60; "${a}:39x25,$($a + 30):37x25,$($a + 27):90x2" }) -join ','
$walkq = (0..40 | ForEach-Object { $a = 80 + $_ * 60; "$($a + 5):38x20,$($a + 35):40x20,$($a + 28):90x2" }) -join ','
$hostlog = Join-Path $env:TEMP 'ube_check_coop_host.txt'
$hargs = @('--headless', '--path', "`"$gd`"", '--', '--coophost', '7771', '--as', 'Kyle', '--universesdir', "`"$cu\h`"", '--room', 'room_ruins9', '--set', 'plot=9.2,hp=300', '--press', $walkp, '--coopbot', '--matehp', '1', '--frames', '1600', '--tps', '200', '--cooplog')
$hp = Start-Process -FilePath $godot -ArgumentList $hargs -RedirectStandardOutput $hostlog -RedirectStandardError (Join-Path $env:TEMP 'ube_check_coop_host_err.txt') -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
$co = & $godot --headless --path $gd -- --coopjoin 127.0.0.1:7771 --as Greg --universesdir (Join-Path $cu 'c') --press $walkq --frames 1600 --tps 200 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^COOP client stopped|SCRIPT ERROR' }
$hp.WaitForExit(60000) | Out-Null
if (-not $hp.HasExited) { Stop-Process -Id $hp.Id -Force }
$ho = Get-Content $hostlog | Where-Object { $_ -match '^COOP host stopped|SCRIPT ERROR|^CBAT' }
$hs = ("$ho" -replace '.*COOP host stopped at frame \d+: \d+ frames together, (\d+) mismatches.*state (\d+).*', '$1 $2')
$cs = ("$co" -replace '.*COOP client stopped at frame \d+: \d+ frames together, (\d+) mismatches.*state (\d+).*', '$1 $2')
$revived = ("$ho" -match '"client": true') -and ("$ho" -match 'mate_hp=6.0 down=\{ "host": false, "client": false \}')   # 30% of 20 HP
# The game's own SOUL stays visible while dodging, whoever's turn it is (it once kept the
# spare SOUL's "hidden" after the turn passed).
$hidden = @($ho | Where-Object { $_ -match '^CBAT .* mn=2\.0 .*main=[-0-9.]+,[-0-9.]+ mv0' }).Count
$cok = ("$ho" -match 'COOP host stopped') -and ("$co" -match 'COOP client stopped') -and $hs -eq $cs -and $hs -match '^0 ' -and $revived -and $hidden -eq 0 -and -not ("$ho $co" -match 'SCRIPT ERROR')
Say $cok 'co-op: two games in one battle (two SOULs, down, revive), in sync' $(if ($cok) { '' } else { "host: $hs client: $cs revived: $revived hidden SOUL: $hidden" })

# Multiplayer rework (docs/MULTIPLAYER.md). Stage 1: a second world (a battle that plays to
# a game over, with its own globals) runs beside the Ruins stress bot; the game's own world
# must not notice (the same state checksums as without it).
$wa = & $godot --headless --path $gd -- --game --seed 7 --savedir (Join-Path $env:TEMP 'ube_check_wa') --room room_ruins7 --set plot=9 --frames 1500 --bot (Join-Path $root 'tests\stress_ruins.txt') --worldhash 50 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^WHASH|SCRIPT ERROR' }
$wb = & $godot --headless --path $gd -- --game --seed 7 --savedir (Join-Path $env:TEMP 'ube_check_wb') --room room_ruins7 --set plot=9 --frames 1500 --bot (Join-Path $root 'tests\stress_ruins.txt') --worldhash 50 --worldtest room_battle --worldat 20 --worldset battlegroup=4 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^WHASH|^WORLDTEST|SCRIPT ERROR' }
$wsame = (@($wa | Where-Object { $_ -match '^WHASH' }) -join ' ') -eq (@($wb | Where-Object { $_ -match '^WHASH' }) -join ' ')
$wok = $wsame -and @($wa).Count -ge 25 -and ("$wb" -match 'WORLDTEST world 1 in room_battle') -and -not ("$wa $wb" -match 'SCRIPT ERROR')
Say $wok 'worlds: a second room running alongside changes nothing in the game' $(if ($wok) { '' } else { "same checksums: $wsame, lines $(@($wa).Count)" })
# Stage 2: several players in one game. Player 2 reads a sign, eats a candy from their own
# menu, and falls through a hole, each while player 1 does something else.
$osc = ((0..7 | ForEach-Object { "$(10 + 20 * $_):37x8,$(20 + 20 * $_):39x8" }) + (0..83 | ForEach-Object { "$(230 + 8 * $_):90x2" })) -join ','
$dk = ((0..9 | ForEach-Object { "$(250 + 20 * $_):37x8,$(260 + 20 * $_):39x8" }) + (0..229 | ForEach-Object { "$(460 + 8 * $_):90x2" })) -join ','
$zz = (@('10:39x23,35:38x20') + (0..62 | ForEach-Object { "$(70 + 10 * $_):90x2" })) -join ','
$wk = (0..7 | ForEach-Object { "$(10 + 20 * $_):37x8,$(20 + 20 * $_):39x8" }) -join ','
$pz1 = (@($wk) + (0..249 | ForEach-Object { "$(230 + 8 * $_):90x2" })) -join ','
$pz2 = (0..159 | ForEach-Object { "$(234 + 8 * $_):90x2" }) -join ','
$jz2 = (@('140:67x2,200:88x2,230:13x2,245:90x2') + (0..239 | ForEach-Object { "$(270 + 8 * $_):90x2" })) -join ','
$mpruns = @(
    @('sign', @('--room', 'room_ruins9', '--set', 'plot=9.2', '--frames', '175', '--press', '40:39x15,80:37x15', '--pfeed', '2=10:39x7,20:38x25,60:90x2,100:90x2,140:90x2')),
    @('menu', @('--room', 'room_ruins9', '--set', 'plot=9.2,hp=10,item.0=1,item.1=1', '--frames', '205', '--press', '40:39x15,80:37x15', '--pfeed', '2=30:67x2,50:90x2,70:90x2,90:90x2,120:90x2,150:90x2,175:90x2')),
    @('hole', @('--room', 'room_ruins8', '--set', 'plot=9.2', '--frames', '155', '--pfeed', '2=10:39x90')),
    # Stage 5: player 2 goes into another room alone, falls through its hole, and player 1 follows.
    @('rooms', @('--room', 'room_ruins9', '--set', 'plot=11', '--frames', '305', '--pfeed', '2=10:37x50,64:37x45', '--press', '200:37x50')),
    # Stage 6: both walk back and forth, get random battles on the same frame and fight them (Z).
    @('battles', @('--room', 'room_ruins9', '--set', 'plot=11', '--frames', '955', '--press', $osc, '--pfeed', "2=$osc")),
    # Saving: refused while player 2's menu is open, then saved for both.
    @('save', @('--room', 'room_ruins7', '--set', 'plot=11', '--frames', '380', '--press', '20:40x8,40:90x2,110:90x2,125:90x2,150:90x2,190:90x2,260:90x2,275:90x2,300:90x2,330:90x2,350:90x2', '--pfeed', '2=20:67x2,170:88x2')),
    # Player 2 (1 HP) is downed alone after player 1 saved, and comes back at the save.
    @('death', @('--room', 'room_ruins7', '--set', 'plot=11,hp=1', '--frames', '2405', '--press', '20:40x8,40:90x2,110:90x2,125:90x2,150:90x2,220:90x2,240:90x2', '--pfeed', "2=$dk")),
    # Toriel's scene in room_ruins19 waits for player 2, who says Yes once free and is brought there.
    @('gather', @('--room', 'room_ruins19', '--set', 'plot=16', '--frames', '700', '--press', '80:40x100', '--pfeed', "2=$zz")),
    # Stage 8: player 2 stands by player 1's encounter and is pulled in: one battle, two SOULs, turns in order.
    @('party', @('--room', 'room_ruins9', '--set', 'plot=11', '--frames', '1600', '--press', $pz1, '--pfeed', "2=$pz2")),
    # Player 2 comes in on 1 HP and goes down; player 1 revives them from MERCY after 3 turns.
    @('revive', @('--room', 'room_ruins9', '--set', 'plot=11', '--frames', '1500', '--press', $wk, '--pfeed', '2=idle')),
    # Player 2 is in their menu (not pulled in), then joins with Enter by where player 1 stood.
    @('join', @('--room', 'room_ruins9', '--set', 'plot=11', '--frames', '2400', '--press', $pz1, '--pfeed', "2=$jz2"))
)
foreach ($r in $mpruns) {
    $mo = & $godot --headless --path $gd -- --game --seed 7 --savedir (Join-Path $env:TEMP "ube_check_mp_$($r[0])") --players 2 --mpcheck $r[0] @($r[1]) 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^MPCHECK|SCRIPT ERROR' }
    $mok = ("$mo" -match "MPCHECK $($r[0]) done, 0 failed") -and -not ("$mo" -match 'SCRIPT ERROR')
    Say $mok "players: $($r[0])" $(if ($mok) { '' } else { (@($mo | Where-Object { $_ -match 'FAIL|ERROR' }) -join '; ') })
}

if ($Full) {
    # The story walkthrough with a friend joined (the friend only takes battle turns), from the
    # intro to Napstablook (the bots can't win that one together). --coopdelay 1: the bot's
    # keys land on the frame it chose them for, as when playing alone.
    $wd = Join-Path $env:TEMP 'ube_check_coopwalk'
    Remove-Item -Recurse -Force $wd -ErrorAction SilentlyContinue
    $wlog = Join-Path $env:TEMP 'ube_check_coopwalk_host.txt'
    $wargs = @('--headless', '--path', "`"$gd`"", '--', '--coophost', '7772', '--as', 'Kyle', '--universesdir', "`"$wd\h`"", '--savedir', "`"$wd\save`"", '--frames', '14500', '--tps', '400', '--coopdelay', '1', '--bot', "`"$walk`"", '--matehp', '999', '--cooplog')
    $wp = Start-Process -FilePath $godot -ArgumentList $wargs -RedirectStandardOutput $wlog -RedirectStandardError (Join-Path $env:TEMP 'ube_check_coopwalk_err.txt') -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 3
    $wc = & $godot --headless --path $gd -- --coopjoin 127.0.0.1:7772 --as Greg --universesdir (Join-Path $wd 'c') --frames 14500 --tps 400 --coopdelay 1 --coopbot 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^COOP client stopped|SCRIPT ERROR' }
    $wp.WaitForExit(120000) | Out-Null
    if (-not $wp.HasExited) { Stop-Process -Id $wp.Id -Force }
    $wh = Get-Content $wlog | Where-Object { $_ -match '^COOP host stopped|SCRIPT ERROR|^BOT .*(FAIL|ok z_until battle)|^ROOM room_ruins12 ' }
    $whs = ("$wh" -replace '.*COOP host stopped at frame \d+: \d+ frames together, (\d+) mismatches.*state (\d+).*', '$1 $2')
    $wcs = ("$wc" -replace '.*COOP client stopped at frame \d+: \d+ frames together, (\d+) mismatches.*state (\d+).*', '$1 $2')
    $wok = ("$wh" -match 'ROOM room_ruins12 ') -and ("$wh" -match 'ok z_until battle') -and -not ("$wh" -match 'FAIL') -and $whs -eq $wcs -and $whs -match '^0 ' -and -not ("$wh $wc" -match 'SCRIPT ERROR')
    Say $wok 'co-op: the walkthrough to Napstablook with a friend joined, in sync' $(if ($wok) { '' } else { "host: $whs client: $wcs; $(@($wh | Where-Object { $_ -match 'FAIL' }) -join ' ')" })
}

$secs = [int]((Get-Date) - $t0).TotalSeconds
if ($fail -eq 0) { Write-Host "All checks passed in $secs s." } else { Write-Host "$fail check(s) FAILED ($secs s)." }
exit $(if ($fail -eq 0) { 0 } else { 1 })
