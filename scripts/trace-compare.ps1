# Frame-by-frame comparison of one fight between the real game (the simulator's patched
# copy, scenario "trace") and the Godot engine.
#
#   powershell -ExecutionPolicy Bypass -File scripts\trace-compare.ps1 -Group 4 -Seed 42 -Lv 1 -Frames 600
#
# Both sides seed GameMaker's random generator the same way, the Godot side replays the
# exact keys the real game saw, and both log HP, karma, invincibility, the SOUL's position,
# battle state and a checksum of every battle object's position after each frame's Draw.
# -Reuse skips running the real game when its trace for these settings already exists;
# -RealTrace <file> compares against a saved real-game trace instead (tests\trace_*.txt).
# -Shots also saves a screenshot every 50 frames in both (the Godot side runs in a window)
# and compares them pixel by pixel (scripts\shot-compare.ps1, logs\trace\shots_g<N>\).
# Traces are kept in logs\trace\ (numbers only, no game data); screenshots stay local.
param(
    [Parameter(Mandatory = $true)][int]$Group,
    [int]$Seed = 42,
    [int]$Lv = 1,
    [int]$Frames = 900,
    [string]$Watch = '',
    [switch]$Reuse,
    [string]$RealTrace = '',
    [int]$Show = 3,
    [switch]$Shots
)
$ErrorActionPreference = 'Stop'
if ($Shots) { $Watch = '@shots' }
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root 'logs\trace'
New-Item -ItemType Directory -Force $dir | Out-Null
$spec = "${Group}:${Seed}:${Lv}:${Frames}" + $(if ($Watch) { ":$Watch" } else { "" })
$tag = "g${Group}_s${Seed}_lv${Lv}_f${Frames}" + $(if ($Watch) { "_" + ($Watch -replace '\*', 'all') } else { "" })
$real = if ($RealTrace) { (Resolve-Path $RealTrace).Path } else { Join-Path $dir "real_$tag.txt" }
$mine = Join-Path $dir "godot_$tag.txt"

if (-not $RealTrace -and -not ($Reuse -and (Test-Path $real))) {
    # Items 1, 1, 11 (Monster Candy x2, Butterscotch Pie) match the Godot engine's set-up.
    $prof = Join-Path $dir 'trace_profile.json'
    '{ "schema": 1, "name": "trace", "love": ' + $Lv + ', "startingHp": 0, "weapon": 3, "armor": 4, "items": [1, 1, 11, 0, 0, 0, 0, 0], "authentic": true }' | Set-Content -Encoding ascii $prof
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'UltimateBattleEngine') -Filter 'ube_trace_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force
    $exe = Join-Path $root 'UltimateBattleEngine.exe'
    $out = & $exe --profile $prof --trace $spec --no-pause 2>&1 | ForEach-Object { "$_" }
    $out | Where-Object { $_ -match 'game> (TRACE|STATE)|SELFTEST' } | ForEach-Object { Write-Host $_ }
    $src = Join-Path $env:LOCALAPPDATA 'UltimateBattleEngine\ube_trace.txt'
    if (-not (Test-Path $src)) { throw "The real game wrote no trace ($src)." }
    Copy-Item $src $real -Force
    if ($Shots) {
        $sd = Join-Path $dir "shots_g$Group"
        if (Test-Path $sd) { Remove-Item -Recurse -Force $sd }
        New-Item -ItemType Directory -Force $sd | Out-Null
        Get-ChildItem (Join-Path $env:LOCALAPPDATA 'UltimateBattleEngine') -Filter 'ube_trace_*.png' | ForEach-Object { Copy-Item $_.FullName (Join-Path $sd ($_.Name -replace '^ube_trace_', 'real_')) }
    }
}

$godot = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$sd = Join-Path $dir "shots_g$Group"
$gargs = @('--path', (Join-Path $root 'godot'), '--', '--gmtrace', $spec, '--replay', $real, '--out', $mine)
if ($Shots) { Get-ChildItem $sd -Filter 'godot_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force; $gargs += @('--shotsdir', $sd) } else { $gargs = @('--headless') + $gargs }
& $godot @gargs 2>&1 |
    ForEach-Object { "$_" } | Where-Object { $_ -match '^TRACE|SCRIPT ERROR' } | ForEach-Object { Write-Host $_ }
$ErrorActionPreference = $eap

$a = @(Get-Content $real); $b = @(Get-Content $mine)
$sNames = 'lv', 'maxhp', 'hp', 'at', 'df', 'wstrength', 'adef', 'weapon', 'armor', 'inv', 'battlegroup'
$tNames = 'f', 'keys', 'hp', 'km', 'invc', 'heart_x', 'heart_y', 'mnfight', 'myfight', 'turn', 'bmenuno', 'n', 'sum_x', 'sum_y', 'gameover'
$sa = ($a | Where-Object { $_ -like 'S *' } | Select-Object -First 1); $sb = ($b | Where-Object { $_ -like 'S *' } | Select-Object -First 1)
if ($sa -ne $sb) {
    $x = $sa.Substring(2).Split(';'); $y = $sb.Substring(2).Split(';')
    for ($i = 0; $i -lt $sNames.Count; $i++) { if ($x[$i] -ne $y[$i]) { Write-Host ("START differs: {0} real={1} godot={2}" -f $sNames[$i], $x[$i], $y[$i]) } }
}
$ta = @($a | Where-Object { $_ -like 'T *' }); $tb = @($b | Where-Object { $_ -like 'T *' })
$n = [Math]::Min($ta.Count, $tb.Count)
$first = @{}
$firstAny = -1
for ($i = 0; $i -lt $n; $i++) {
    $x = $ta[$i].Substring(2).Split(';'); $y = $tb[$i].Substring(2).Split(';')
    for ($k = 1; $k -lt $tNames.Count; $k++) {
        if ($first.ContainsKey($tNames[$k])) { continue }
        $dx = 0.0; $dy = 0.0
        $same = if ([double]::TryParse($x[$k], [ref]$dx) -and [double]::TryParse($y[$k], [ref]$dy)) { [Math]::Abs($dx - $dy) -lt 0.01 } else { $x[$k] -eq $y[$k] }
        if (-not $same) {
            $first[$tNames[$k]] = $i
            if ($firstAny -lt 0) { $firstAny = $i }
        }
    }
}
Write-Host ("FRAMES real={0} godot={1}" -f $ta.Count, $tb.Count)
if ($Shots) { & (Join-Path $PSScriptRoot 'shot-compare.ps1') -Dir $sd }
if ($Watch) {
    $wa = @{}; foreach ($l in ($a | Where-Object { $_ -like 'W *' })) { $p = $l.Substring(2).Split(';', 2); $wa[[int]$p[0]] = $p[1] }
    $wb = @{}; foreach ($l in ($b | Where-Object { $_ -like 'W *' })) { $p = $l.Substring(2).Split(';', 2); $wb[[int]$p[0]] = $p[1] }
    $shown = 0
    foreach ($f in (@($wa.Keys) + @($wb.Keys) | Sort-Object -Unique)) {
        if ($Watch -eq '*') {
            # Every object: compare as sorted sets (instance order differs between runners).
            $ea = @("$($wa[$f])".Split('|') | Where-Object { $_ } | Sort-Object); $eb = @("$($wb[$f])".Split('|') | Where-Object { $_ } | Sort-Object)
            $d = Compare-Object $ea $eb
            if ($d -and $shown -lt 8) { Write-Host "  WATCH f=$f"; $d | ForEach-Object { Write-Host ("    {0} {1}" -f $(if ($_.SideIndicator -eq '<=') { 'R' } else { 'G' }), $_.InputObject) }; $shown++ }
        }
        elseif ($wa[$f] -ne $wb[$f] -and $shown -lt 12) { Write-Host ("  WATCH f={0}`n    R {1}`n    G {2}" -f $f, $wa[$f], $wb[$f]); $shown++ }
    }
    if ($shown -eq 0) { Write-Host "WATCH $Watch identical on every frame" }
}
if ($firstAny -lt 0) {
    Write-Host "MATCH: every logged value agrees on all $n frames."
    exit 0
}
foreach ($k in ($first.Keys | Sort-Object { $first[$_] })) { Write-Host ("FIRST DIFF {0,-9} at frame {1}" -f $k, ($first[$k] + 1)) }
Write-Host "Frames around the first difference (real / godot):"
for ($i = [Math]::Max(0, $firstAny - 2); $i -le [Math]::Min($n - 1, $firstAny + $Show); $i++) {
    Write-Host ("  R " + $ta[$i]); Write-Host ("  G " + $tb[$i])
}
exit 1
