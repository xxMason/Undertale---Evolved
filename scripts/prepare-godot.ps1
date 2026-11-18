# Extracts the assets the Godot engine needs from the player's own copy of Undertale into
# godot\extracted\. Nothing extracted is committed; godot\extracted\ is in .gitignore and
# has a .gdignore so Godot does not import it (the engine loads the files at runtime).
#
#   powershell -ExecutionPolicy Bypass -File scripts\prepare-godot.ps1 [-Undertale DIR] [-Godot EXE]
#
# Undertale: source\ if it already holds a supported data.win (the launcher's verified copy, or
# an earlier run); otherwise -Undertale, or the Steam libraries are searched. The install is
# only read: data.win is checked against config\compat.json, then data.win and the music
# (*.ogg in the game's top folder, nothing else, no subfolders) are copied into source\.
# This project folder must not be inside the Undertale folder (or the other way round).
# UndertaleModTool CLI: tools\utmt-cli\; downloaded from its GitHub release (checked by
# SHA-256) if missing. Godot: -Godot, config\godot_path.txt, %GODOT%, or the Steam copy.
param(
    [string]$Undertale = '',
    [string]$Godot = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'source'
$data = Join-Path $src 'data.win'

function Find-Undertale {
    $libs = @()
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $p = (Get-ItemProperty $k -ErrorAction Stop)
            foreach ($v in $p.SteamPath, $p.InstallPath) { if ($v) { $libs += ($v -replace '/', '\') } }
        } catch {}
    }
    $libs += 'C:\Program Files (x86)\Steam'
    foreach ($s in @($libs)) {
        $vdf = Join-Path $s 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') }
        }
    }
    foreach ($l in ($libs | Select-Object -Unique)) {
        $d = Join-Path $l 'steamapps\common\Undertale'
        if (Test-Path (Join-Path $d 'data.win')) { return $d }
    }
    return ''
}

function Full($p) { return [IO.Path]::GetFullPath($p).TrimEnd('\') + '\' }
function Inside($a, $b) { return (Full $a).StartsWith((Full $b), [StringComparison]::OrdinalIgnoreCase) }

$supported = @((Get-Content (Join-Path $root 'config\compat.json') -Raw | ConvertFrom-Json).supported | ForEach-Object { $_.files.'data.win' })
function Is-Supported($file) {
    if (-not (Test-Path $file -PathType Leaf)) { return $false }
    return $supported -contains (Get-FileHash $file -Algorithm SHA256).Hash
}

# A project placed inside the game folder would copy itself into source\ again and again.
if (Test-Path (Join-Path $root 'data.win')) {
    throw "This folder holds a data.win: the engine has been put inside the Undertale folder. Move the whole UltimateBattleEngine folder somewhere else (for example your Desktop or Documents), then run setup again."
}

if (-not (Is-Supported $data)) {
    if ($Undertale -eq '') { $Undertale = Find-Undertale }
    if ($Undertale -eq '' -or -not (Test-Path (Join-Path $Undertale 'data.win'))) {
        throw "Couldn't find Undertale. Run again with -Undertale ""<folder that contains data.win>""."
    }
    if ((Inside $root $Undertale) -or (Inside $Undertale $root)) {
        throw "The engine folder ($root) is inside the Undertale folder ($Undertale), or the other way round. Move the UltimateBattleEngine folder somewhere else (for example your Desktop or Documents), then run setup again."
    }
    if (-not (Is-Supported (Join-Path $Undertale 'data.win'))) {
        $have = (Get-FileHash (Join-Path $Undertale 'data.win') -Algorithm SHA256).Hash
        throw "This Undertale's data.win ($have) is not a supported version (the engine is verified against Undertale v1.08 on Steam, Windows)."
    }
    Write-Host "Copying data.win and the music from $Undertale into source\ (the install itself is only read) ..."
    New-Item -ItemType Directory -Force $src | Out-Null
    Copy-Item -LiteralPath (Join-Path $Undertale 'data.win') -Destination $data -Force
    Get-ChildItem -LiteralPath $Undertale -Filter '*.ogg' -File | Copy-Item -Destination $src -Force
    if (-not (Is-Supported $data)) { throw "The copy of data.win in source\ doesn't match; run setup again." }
} elseif (-not (Get-ChildItem -LiteralPath $src -Filter '*.ogg' -File | Select-Object -First 1)) {
    # data.win is there but the music isn't (an interrupted copy): fetch just the music.
    if ($Undertale -eq '') { $Undertale = Find-Undertale }
    if ($Undertale -ne '' -and -not ((Inside $root $Undertale) -or (Inside $Undertale $root))) {
        Get-ChildItem -LiteralPath $Undertale -Filter '*.ogg' -File | Copy-Item -Destination $src -Force
    }
}

$cli = Join-Path $root 'tools\utmt-cli\UndertaleModCli.exe'
if (-not (Test-Path $cli)) {
    $url = 'https://github.com/UnderminersTeam/UndertaleModTool/releases/download/0.9.2.0/UTMT_CLI_v0.9.2.0-Windows.zip'
    $sha = 'E7573E45D107BE34F81F955C6E4AFC3C7C8F2628E5A6F307A871E3825B3DFB40'
    $zip = Join-Path $root 'tools\UTMT_CLI_v0.9.2.0-Windows.zip'
    New-Item -ItemType Directory -Force (Join-Path $root 'tools') | Out-Null
    if (-not (Test-Path $zip)) {
        Write-Host "Downloading UndertaleModTool CLI 0.9.2.0 from GitHub ..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing } catch {
            throw "Download failed. Get $url by hand, extract it so tools\utmt-cli\UndertaleModCli.exe exists, and run this again."
        }
    }
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $sha) {
        Remove-Item $zip
        throw "The UndertaleModTool download doesn't match its known SHA-256; deleted it. Try again, or extract the official 0.9.2.0 CLI zip to tools\utmt-cli\ by hand."
    }
    Expand-Archive $zip (Join-Path $root 'tools\utmt-cli') -Force
    if (-not (Test-Path $cli)) {
        $found = Get-ChildItem (Join-Path $root 'tools\utmt-cli') -Recurse -Filter 'UndertaleModCli.exe' | Select-Object -First 1
        if ($found) { Get-ChildItem $found.DirectoryName | Move-Item -Destination (Join-Path $root 'tools\utmt-cli') -Force }
    }
    if (-not (Test-Path $cli)) { throw "Couldn't find UndertaleModCli.exe after extracting $zip." }
}

# Godot: remembered in config\godot_path.txt for play.bat and the scripts.
$gpath = Join-Path $root 'config\godot_path.txt'
if ($Godot -eq '' -and (Test-Path $gpath)) { $Godot = (Get-Content $gpath -Raw).Trim() }
if ($Godot -eq '' -and $env:GODOT) { $Godot = $env:GODOT }
if ($Godot -eq '') { $Godot = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' }
if (Test-Path $Godot) { Set-Content -Path $gpath -Value $Godot -Encoding ascii }
$out = Join-Path $root 'godot\extracted'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null
Set-Content -Path (Join-Path $out '.gdignore') -Value '' -Encoding ascii
$env:UBE_GODOT_OUT = $out
# Native tools may write warnings to stderr; success is judged by their "ok" lines below.
$ErrorActionPreference = 'Continue'
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
$godot = $Godot
# Godot prints harmless warnings on stderr at exit; PowerShell 5.1 would turn those into
# errors under 'Stop', so native output is read with 'Continue' and judged by its content.
$ErrorActionPreference = 'Continue'
if (Test-Path $godot) {
    $tl = & $godot --headless --path (Join-Path $root 'godot') --script res://tools/transpile_all.gd -- --write 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^TRANSPILE|^WROTE' }
    Write-Host ($tl -join "`n")
} else {
    Write-Host 'Godot not found: the engine will translate the game code while it runs (slower first battles).'
}
Write-Host "Extracted to $out"
