# Screenshot comparison for many battles in one go: runs trace-compare.ps1 -Shots for each
# battle group and prints one summary line per group (identical frames, worst frame).
#
#   powershell -ExecutionPolicy Bypass -File scripts\shots-all.ps1 [-Groups 2,4,95] [-Frames 900] [-Reuse]
#
# Without -Groups it takes every group that has a saved real trace in logs\trace.
# Results also go to logs\trace\shots_summary.txt; images stay in logs\trace\shots_gN\.
param(
    [int[]]$Groups = @(),
    [int]$Frames = 900,
    [switch]$Reuse
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root 'logs\trace'
if ($Groups.Count -eq 0) {
    $Groups = Get-ChildItem $dir -Filter 'real_g*_s42_lv20_f1500.txt' |
        ForEach-Object { [int]($_.Name -replace '^real_g(\d+)_.*', '$1') } | Sort-Object -Unique
}
$lines = @()
foreach ($g in $Groups) {
    $a = @('-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'trace-compare.ps1'), '-Group', $g, '-Lv', 20, '-Frames', $Frames, '-Shots')
    if ($Reuse) { $a += '-Reuse' }
    $out = & powershell @a 2>&1 | ForEach-Object { "$_" }
    $sum = ($out | Where-Object { $_ -match '^SHOTS ' } | Select-Object -First 1) -replace ' -> .*$', ''
    $worst = $out | Where-Object { $_ -match '^SHOT f=(\d+) differing_pixels=(\d+)' } |
        ForEach-Object { [pscustomobject]@{ f = [int]$Matches[1]; n = [int]$Matches[2] } } |
        Sort-Object n -Descending | Select-Object -First 1
    $logic = $out | Where-Object { $_ -match '^(MATCH|FIRST DIFF)' } | Select-Object -First 1
    $line = "G{0} {1} worst={2}px@f{3} | {4}" -f $g, $sum, $(if ($worst) { $worst.n } else { 0 }), $(if ($worst) { $worst.f } else { '-' }), $logic
    Write-Host $line
    $lines += $line
}
$lines | Set-Content -Encoding ascii (Join-Path $dir 'shots_summary.txt')
