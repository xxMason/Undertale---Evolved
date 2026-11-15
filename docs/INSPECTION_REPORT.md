# Technical inspection report

Inspected on 2026-11-15. Everything below was read from the installed game with
`scripts/inspect.csx` (read-only) unless marked otherwise.

## Installation

| Item | Value |
|---|---|
| Path | `C:\Program Files (x86)\Steam\steamapps\common\Undertale` |
| Version | Undertale **v1.08** (exe file version 1.0.8.0), Steam, Windows |
| Runtime | GameMaker: Studio 1.4 runner (IDE build 1.0.0.1539), 32-bit, **bytecode 16** |
| `data.win` SHA-256 | `B718F8223A5BB31979FFEED10BE6140C857B882FC0D0462B89D6287AE38C81C7` (62,921,978 bytes) |
| `UNDERTALE.exe` SHA-256 | `C8C4191026BF5587A6FAD120855B8B82FFB4FA0C3EAF10515BE472AD84248E58` (4,136,960 bytes) |
| Layout | exe, `data.win`, `options.ini`, `D3DX9_43.dll`, `steam_api.dll`, `splash.png`, 210 external `.ogg` files, all in one folder |
| Data file | 1709 objects, 336 rooms, 238 scripts, 6272 code entries, 2583 sprites, 443 sounds, 20 fonts |
| GEN8 | Name / DisplayName / FileName = `UNDERTALE`, Steam app id field = -391540 |

All 6272 code entries decompiled with UndertaleModTool 0.9.2.0 without a failure.

## The supplied decompile does not match the installed game

`C:\Users\Mason\Downloads\mason undertale dump` is a GMX project from an **older build**
(v1.00/1.001 era). Differences that matter:

- Battlegroup numbers differ: Froggit is group 135 in the dump but **4** in v1.08.
- Object and room indices differ (e.g. `room_battle` is 306 in v1.08).
- v1.08 routes all file access through `ossafe_*` wrappers and has Japanese-language,
  joypad and border code that the dump lacks.

The dump was used only for orientation. Every name and number used by the patch comes
from the installed `data.win`.

## Start-up flow (v1.08)

1. `room_start` (room 0) holds the persistent `obj_time` and `obj_screen`.
2. `obj_time` Game Start runs `SCR_GAMESTART` (initialises all globals).
3. `obj_time` Begin Step, first frame: reads `config.ini` and `undertale.ini`, then
   normally ends with `room_goto_next()` into `room_introstory`.

## Battle flow (v1.08)

- Overworld code sets `global.battlegroup` and creates `obj_battler`, which stores
  `global.currentroom = room`, makes the room persistent and does `room_goto(room_battle)`.
- `room_battle` contains `obj_battlecontroller`, `obj_heart`, the four buttons and borders.
- `obj_battlecontroller` Create calls `scr_battlegroup`, a `switch` on
  `global.battlegroup` that creates the monsters and music. It then **recomputes**
  `maxhp`, `at` and `df` from `global.lv` (LV 20 gives 99 HP, AT 30, DF 30) and clamps
  HP to `maxhp + 15`.
- Froggit alone is battlegroup **4** (`obj_froggit`, object 214, music `battle1`).
  Toriel is battlegroup 22 (`obj_torielboss`).
- Victory, spare and flee all end with `room_goto(global.currentroom)`
  (`obj_battlecontroller` User Event 0, `obj_heart` Step).
- Defeat: `scr_gameoverb` goes to `room_gameover`; the persistent `obj_gameover` plays
  the original sequence (`obj_heartdefeated`), increments `Gameover` in `undertale.ini`,
  returns to `global.currentroom` and then calls `scr_tempload`, which reloads `file9`.
  It issues `room_goto` twice on the way back.

## Save files

- GMS 1.4 keeps saves in `%LOCALAPPDATA%\<GEN8 name>`, so the original uses
  `%LOCALAPPDATA%\UNDERTALE` (`file0`, `file8`, `file9`, `undertale.ini`, `config.ini`,
  `system_information_962/963`).
- **On this machine `%LOCALAPPDATA%\UNDERTALE` did not exist** at inspection time, and
  there is no Steam Cloud folder for app 391540. There were no existing saves to
  protect, but the path is still monitored: it must stay absent.
- The game code also uses Steam Cloud calls (`steam_file_write_file`,
  `steam_file_delete`, `steam_file_exists`) when `steam_initialised()` is true.
- No game code reads environment variables or uses absolute paths.

## Strategy chosen for a separate build

- Copy the installation to `game/` without `steam_api.dll`, rename the runner.
- Patch a copy of `data.win` with a script; never open the original for writing.
- Rename GEN8 Name/DisplayName/FileName to `UltimateBattleEngine`, which moves the save
  directory to `%LOCALAPPDATA%\UltimateBattleEngine`. Verified at runtime (see test report).

## Limitations and concerns

- Only this exact v1.08 build is accepted (`config/compat.json`). Other versions are
  refused before anything is copied.
- Simulated key presses are ignored by the runner for the first few seconds after
  start-up. This only affects the automated test driver, which probes for it.
- UndertaleModTool recompiles any original code entry it edits. The patch edits exactly
  one (`gml_Object_obj_gameover_Step_0`, 13 lines); all combat code keeps its original
  bytecode.
- The working copy runs without Steam, so the Steam overlay and Cloud are unavailable in
  the simulator by design.
