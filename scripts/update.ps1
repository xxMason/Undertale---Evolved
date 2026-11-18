# Updates this engine folder from a newer tester zip (UltimateBattleEngine-tester*.zip).
#   update.bat                      (finds the newest tester zip here or in Downloads)
#   update.bat "C:\path\UltimateBattleEngine-tester.zip"   (or drag the zip onto update.bat)
#
# Only the engine's own files change. Kept as they are: what setup made (source\,
# godot\extracted\, tools\), your settings (config\settings.json, config\godot_path.txt),
# logs, and anything you added yourself (your own bosses, profiles...). Your Undertale
# install and its saves are never touched. Every file the update replaces or removes is
# copied to backup\<old version>_<date>\ first, so an update can be undone by copying
# that folder back.
#
# The zip lists its files in MANIFEST.txt; files from the old version that the new one no
# longer has are removed (only those: a folder without a MANIFEST.txt, from before the
# updater existed, just gets the new files on top).
param([string]$Zip = '')
$ErrorActionPreference = 'Stop'
trap {
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    # (A plain exit here still prints PowerShell's error record after the message.)
    [Environment]::Exit(1)
}
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
# Never written by an update, whatever the zip holds.
$keepDirs = @('source', 'godot\extracted', 'godot\.godot', 'tools', 'logs', 'backup', 'game', 'build')
$keepFiles = @('config\settings.json', 'config\godot_path.txt')

function Version-Of([string]$text) {
    if ($text -match 'const VERSION := "([0-9]+)\.([0-9]+)\.([0-9]+)"') {
        return [version]("{0}.{1}.{2}" -f $matches[1], $matches[2], $matches[3])
    }
    return $null
}
function Is-Kept([string]$rel) {
    foreach ($d in $keepDirs) { if ($rel -eq $d -or $rel.StartsWith($d + '\')) { return $true } }
    return $keepFiles -contains $rel
}

# The zip: given, or the newest tester zip here or in Downloads.
if ($Zip -eq '') {
    $places = @($root, (Split-Path $root -Parent), (Join-Path $env:USERPROFILE 'Downloads'))
    $found = foreach ($p in $places) { if (Test-Path $p) { Get-ChildItem -Path $p -Filter 'UltimateBattleEngine-tester*.zip' -File -ErrorAction SilentlyContinue } }
    $pick = $found | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $pick) {
        throw "No UltimateBattleEngine-tester zip found here or in Downloads. Drag the new zip onto update.bat, or run: update.bat ""C:\path\to\the.zip"""
    }
    $Zip = $pick.FullName
}
if (-not (Test-Path $Zip -PathType Leaf)) { throw "No such file: $Zip" }
Write-Host "Update from: $Zip"

$za = [System.IO.Compression.ZipFile]::OpenRead($Zip)
try {
    # Entries under the zip's top folder (UltimateBattleEngine\...), as paths in this folder.
    $entries = @{}
    foreach ($e in $za.Entries) {
        # (Zips made by Windows' own tools may use \ between folders.)
        $name = $e.FullName.Replace('\', '/')
        if ($name.EndsWith('/')) { continue }
        $rel = $name -replace '^[^/]+/', '' -replace '/', '\'
        if ($rel -match '(^|\\)\.\.(\\|$)' -or [System.IO.Path]::IsPathRooted($rel)) { throw "The zip has an unsafe path: $($e.FullName)" }
        $entries[$rel] = $e
    }
    if (-not $entries.ContainsKey('godot\engine_info.gd')) { throw "This zip isn't an Ultimate Battle Engine tester build (no godot\engine_info.gd in it)." }
    foreach ($rel in $entries.Keys) {
        if ($rel -match '\.(win|exe|dll|ogg)$' -or $rel -like 'godot\extracted\*' -or $rel -like 'source\*') { throw "This zip holds game or program files ($rel); a tester build never does. Not updating." }
    }
    $r = New-Object System.IO.StreamReader($entries['godot\engine_info.gd'].Open())
    $newVer = Version-Of $r.ReadToEnd(); $r.Close()
    $curFile = Join-Path $root 'godot\engine_info.gd'
    $curVer = if (Test-Path $curFile) { Version-Of (Get-Content $curFile -Raw) } else { $null }
    if ($null -eq $newVer) { throw "Couldn't read the version in the zip." }
    Write-Host ("This folder: {0}    the zip: {1}" -f $(if ($curVer) { $curVer } else { 'unknown' }), $newVer)
    if ($curVer -and $newVer -lt $curVer) { throw "The zip ($newVer) is older than this folder ($curVer). Not updating." }

    # Files to remove: in the old file list but not in the new one.
    $oldList = Join-Path $root 'MANIFEST.txt'
    $gone = @()
    if (Test-Path $oldList) {
        foreach ($l in Get-Content $oldList) {
            $rel = $l.Trim() -replace '/', '\'
            if ($rel -ne '' -and -not $entries.ContainsKey($rel) -and -not (Is-Kept $rel) -and (Test-Path (Join-Path $root $rel) -PathType Leaf)) { $gone += $rel }
        }
    }

    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $bak = Join-Path $root ("backup\{0}_{1}" -f $(if ($curVer) { $curVer } else { 'old' }), $stamp)
    $changed = 0; $added = 0; $same = 0; $skipped = 0
    foreach ($rel in ($entries.Keys | Sort-Object)) {
        if (Is-Kept $rel) { $skipped++; continue }
        $dest = Join-Path $root $rel
        $e = $entries[$rel]
        $ms = New-Object System.IO.MemoryStream
        $s = $e.Open(); $s.CopyTo($ms); $s.Close()
        $bytes = $ms.ToArray()
        if (Test-Path $dest -PathType Leaf) {
            $old = [System.IO.File]::ReadAllBytes($dest)
            if ($old.Length -eq $bytes.Length -and [System.Linq.Enumerable]::SequenceEqual($old, $bytes)) { $same++; continue }
            $bd = Join-Path $bak $rel
            New-Item -ItemType Directory -Force (Split-Path $bd -Parent) | Out-Null
            Copy-Item $dest $bd -Force
            $changed++
        } else {
            $added++
        }
        New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
        [System.IO.File]::WriteAllBytes($dest, $bytes)
    }
    foreach ($rel in $gone) {
        $src = Join-Path $root $rel
        $bd = Join-Path $bak $rel
        New-Item -ItemType Directory -Force (Split-Path $bd -Parent) | Out-Null
        Move-Item $src $bd -Force
    }
} finally {
    $za.Dispose()
}

Write-Host ("Updated: {0} changed, {1} new, {2} removed, {3} unchanged." -f $changed, $added, $gone.Count, $same)
if ($changed + $gone.Count -gt 0) { Write-Host "The old files are in $bak" }
Write-Host "Your setup data, settings and saves were kept. play.bat re-extracts the game data by itself if this version needs it."
