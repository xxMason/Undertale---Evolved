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
