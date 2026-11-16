# Applies logs\sweep-results.txt (from UltimateBattleEngine.exe --sweep) to
# config\encounters.json: real monster names, status and enabled.
#   verified      fought to a victory and returned to the menu
#   starts        battle starts and runs; ended in defeat or was still going at the time limit
#   needs-adapter left the battle for a story room, crashed, or ended the game
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$jsonPath = Join-Path $root 'config\encounters.json'
$doc = Get-Content $jsonPath -Raw | ConvertFrom-Json
$lines = Get-Content (Join-Path $root 'logs\sweep-results.txt')

$res = @{}
$cur = -1
foreach ($l in $lines) {
    if ($l -match '^SWEEP start i=(\d+) ') { $cur = [int]$Matches[1]; $res[$cur] = @{ outcome = 'none'; names = '' }; continue }
    if ($cur -lt 0) { continue }
    if ($l -match '^SWEEP names i=\d+ \|(.*)$') { $res[$cur].names = $Matches[1] }
    elseif ($l -match '^SWEEP timeout') { $res[$cur].outcome = 'timeout' }
    elseif ($l -match '^SWEEP escaped i=\d+ room=(\S+)') { $res[$cur].outcome = "escaped to $($Matches[1])" }
    elseif ($l -match '^SWEEP crash i=\d+ (\w+)') { $res[$cur].outcome = "game $($Matches[1])" }
    elseif ($l -match '^STATE VICTORY') { if ($res[$cur].outcome -eq 'none') { $res[$cur].outcome = 'victory' } }
    elseif ($l -match '^STATE DEFEAT') { if ($res[$cur].outcome -eq 'none') { $res[$cur].outcome = 'defeat' } }
}

$summary = @()
for ($i = 0; $i -lt $doc.encounters.Count; $i++) {
    $e = $doc.encounters[$i]
    if (-not $res.ContainsKey($i)) { $e.status = 'untested'; $e.enabled = $false; $summary += "$i`t$($e.id)`tuntested"; continue }
    $r = $res[$i]
    switch -Regex ($r.outcome) {
        '^victory$' { $e.status = 'verified'; $e.enabled = $true }
        '^(defeat|timeout)$' { $e.status = 'starts'; $e.enabled = $true }
        default { $e.status = 'needs-adapter'; $e.enabled = $false }
    }
    $e | Add-Member -NotePropertyName sweepOutcome -NotePropertyValue $r.outcome -Force
    # Real names as the game reported them, e.g. "Froggit;Whimsun;" -> "Froggit, Whimsun".
    $names = @($r.names.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($names.Count -gt 0) {
        $label = (($names | Group-Object | ForEach-Object { if ($_.Count -gt 1) { "$($_.Name) x$($_.Count)" } else { $_.Name } }) -join ', ')
        if ($e.displayName -match '(\s\([^)]*\))$') { $label += $Matches[1] }
        $e.displayName = $label
    }
    $summary += "$i`t$($e.id)`t$($e.displayName)`t$($r.outcome)`t$($e.status)"
}
[IO.File]::WriteAllText($jsonPath, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
$summary
"`n" + (($doc.encounters | Group-Object status | ForEach-Object { "$($_.Name): $($_.Count)" }) -join '   ')
