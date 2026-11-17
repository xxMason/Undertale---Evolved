# Undertale: Ultimate Battle Engine

A battle simulator that runs the **original** Undertale combat code from your own copy of
the game, behind a custom fight-select menu. It works on a private copy of the game and
keeps its saves in a separate folder.

Current state: 98 encounters in the catalogue, 87 verified to their endings by automated
sweeps and 11 more that start and run with unverified endings (marked `*` in the menu).
Player Setup covers LOVE, HP, weapon, armour and inventory; Training Mode adds infinite HP,
game speed, a retry key and hitbox outlines. Custom Battles has a boss editor and a mouse-driven
live-build screen for attacks (`docs/BATTLE_CREATOR.md`). See `docs/TEST_REPORT.md`.

## Requirements

- Windows, and Undertale **v1.08** from Steam (other versions are refused).
- UndertaleModTool CLI 0.9.2.0 in `tools/utmt-cli/` (see `docs/TOOLCHAIN.md`).

## Build and run

```
powershell -ExecutionPolicy Bypass -File scripts\build.ps1
.\UltimateBattleEngine.exe
```

The first run copies the game to `game/` and patches it (about a minute). If Undertale is
not in a Steam library, pass `--undertale "<folder>"` once.

Controls are Undertale's: arrows, Z or Enter to confirm, X or Shift to go back, F4 for
fullscreen, hold Esc to quit.

Other options: `--profile <json>`, `--export-profile <json>`, `--rebuild`,
`--prepare-only`, `--selftest menu|ui|win|lose|lose_then_win`.

## If your Undertale folder is modded

The first time it runs, the launcher copies the original game files it has verified into
`source/` and builds from that copy afterwards. Mods or updates applied to the Steam
folder later do not affect the simulator. If the Steam folder is already modded when you
first set up, point the launcher at an untouched copy once:

```
.\UltimateBattleEngine.exe --undertale "<folder with the original UNDERTALE.exe and data.win>"
```
## What it will not touch

- The original installation is only read. The launcher hashes it before and after each
  session and reports any difference.
- Saves go to `%LOCALAPPDATA%\UltimateBattleEngine`, not `%LOCALAPPDATA%\UNDERTALE`.
- Steam integration is left out of the copy, so Steam Cloud is never contacted.
- If any isolation check fails, the game is not started.

## Layout

| Folder | Contents |
|---|---|
| `launcher/` | Launcher source |
| `patches/` | Patch script and GML added to the game |
| `config/` | Supported versions, encounter catalogue |
| `profiles/` | Player presets (JSON) |
| `scripts/` | Build and inspection scripts |
| `tests/` | End-to-end tests |
| `docs/` | Inspection report, toolchain, architecture, test report |
| `bosses/` | Example custom boss for the Battle Creator |
| `source/`, `game/`, `tools/`, `build/`, `logs/` | Verified original files, working copy, tools and logs; not in Git |

No Undertale assets or binaries are stored in this repository.
