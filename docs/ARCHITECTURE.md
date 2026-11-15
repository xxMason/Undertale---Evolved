# Architecture

## Layers

| Layer | Location | Notes |
|---|---|---|
| Original game logic | the user's installation, copied to `game/` | Never edited by hand, never in Git |
| Modified game logic | `patches/ube_patch.csx`, `patches/gml/` | Applied by script on every build |
| Launcher | `launcher/Program.cs` | Locating, verifying, copying, isolation gate, profiles |
| Encounter configuration | `config/encounters.json` | Turned into the in-game catalogue at build time |
| Training systems | not implemented; design below | |
| User settings | `config/settings.json`, `profiles/*.json`, `%LOCALAPPDATA%\UltimateBattleEngine\ube_config.ini` | |

## What the patch changes

Added:

- `room_ube_menu` with `obj_ube_controller` (menu, player setup, results).
- Scripts `ube_log`, `ube_catalogue` (generated), `ube_apply_player`, `ube_start_encounter`.
- `obj_ube_testdriver`, created only when the launcher requests a self-test.

Changed:

- GEN8 Name / DisplayName / FileName and Steam app id (save isolation).
- Room order: `room_ube_menu` is inserted second, so the untouched `obj_time` start-up
  code (`room_goto_next()` from `room_start`) lands on the menu instead of the intro.
- One line of original code: in `gml_Object_obj_gameover_Step_0`,
  `script_execute(scr_tempload);` becomes `global.ube_result = 2;`. Without it the game
  would try to reload `file9` after a game over.

No combat object, script, sprite or sound is modified.

## Encounter lifecycle

`global.ube_state`: 0 MENU, 1 CONFIGURING, 2 INITIALISING, 3 IN_BATTLE, 4 VICTORY,
5 DEFEAT, 6 RESULTS, 7 RETURNING_TO_MENU, 8 ERROR (reserved; nothing raises it yet).

1. MENU / CONFIGURING: `obj_ube_controller` pages. Player setup is saved to `ube_config.ini`.
2. INITIALISING (`ube_start_encounter`): stop all audio, run the original
   `SCR_GAMESTART` to reset every global, `ube_apply_player`, run the encounter's
   adapter, set `global.currentroom = room_ube_menu`.
3. IN_BATTLE: `room_goto(room_battle)`. From here only original code runs.
4. The original code returns to `global.currentroom` on victory, spare, flee or after
   the full game-over sequence. The controller is created again in RETURNING_TO_MENU,
   waits for `obj_gameover` to disappear, reads the outcome, stops audio, clears
   `global.inbattle` and `global.border`, and shows RESULTS (Retry, Fight Select, Main Menu).

Story progression is contained because every battle starts from `SCR_GAMESTART` and
nothing is ever saved to a save slot.

## Adapters

`config/encounters.json` names an adapter per encounter. Only `generic_battlegroup`
exists (set `global.battlegroup`). Encounters that need flags, special rooms or custom
return handling get their own adapter case in `ube_start_encounter.gml` plus an id in
`ube_patch.csx`. Toriel is listed as planned and disabled.

## Player configuration

`ube_apply_player` sets LV, the matching EXP threshold, max HP and starting HP using the
same formulas `obj_battlecontroller` applies at battle start, so the original code does
not overwrite the chosen values. Weapon, armour and items stay at the new-game defaults
in this milestone; `profiles/*.json` already carries the fields.

## Training system (design only)

- `global.ube_authentic` gates everything. In Authentic Mode no training object exists.
- A persistent `obj_ube_trainer`, created only in Training Mode, would implement
  modifiers from outside the combat code: infinite HP (restore `global.hp` in End Step),
  game speed (`room_speed`), instant retry (hotkey calling `ube_start_encounter`),
  hitbox overlay (Draw event over `obj_heart` and bullet parents), damage and no-hit
  tracking (compare `global.hp` between frames).
- Attack and phase selection need per-encounter knowledge and belong in adapters.
- Statistics and training presets would be extra sections in `ube_config.ini`, mirrored
  to JSON by the launcher like profiles.
