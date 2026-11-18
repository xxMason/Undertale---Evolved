# Builds the tester zip: every file Git tracks or would track (nothing .gitignore leaves out,
# so no Undertale data, tools or logs), under an UltimateBattleEngine\ folder, with
# MANIFEST.txt listing them for the updater (scripts\update.ps1).
#   powershell -ExecutionPolicy Bypass -File scripts\make-tester-zip.ps1
# Writes UltimateBattleEngine-tester-<version>.zip in the project folder.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
try {
    $files = @(git ls-files --cached --others --exclude-standard | Where-Object { $_ -ne '' -and (Test-Path $_ -PathType Leaf) } | Sort-Object)
    if ($LASTEXITCODE -ne 0 -or $files.Count -eq 0) { throw 'git ls-files failed' }
    $bad = $files | Where-Object { $_ -match '\.(win|exe|dll|ogg|zip)$' -or $_ -match '^(source|game|tools|logs|backup)/' -or $_ -like 'godot/extracted/*' }
    if ($bad) { throw "These must not go into a tester zip: $($bad -join ', ')" }
    $info = Get-Content 'godot\engine_info.gd' -Raw
    if ($info -notmatch 'const VERSION := "([0-9.]+)"') { throw 'No VERSION in godot\engine_info.gd' }
    $ver = $matches[1]
    $out = Join-Path $root "UltimateBattleEngine-tester-$ver.zip"
    if (Test-Path $out) { Remove-Item $out }
    $zs = [System.IO.File]::Open($out, 'CreateNew')
    $z = New-Object System.IO.Compression.ZipArchive($zs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $files) {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, (Join-Path $root $f), "UltimateBattleEngine/$f", 'Optimal') | Out-Null
        }
        $m = $z.CreateEntry('UltimateBattleEngine/MANIFEST.txt')
        $w = New-Object System.IO.StreamWriter($m.Open())
        $w.Write((($files + 'MANIFEST.txt') -join "`r`n") + "`r`n")
        $w.Close()
    } finally {
        $z.Dispose()
        $zs.Dispose()
    }
    Write-Host ("Built {0}: version {1}, {2} files, {3:N0} KB" -f $out, $ver, ($files.Count + 1), ((Get-Item $out).Length / 1KB))
} finally {
    Pop-Location
}
