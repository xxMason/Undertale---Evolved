# Mods (format 1, draft)

Status: the engine finds mods, checks them and decides their load order, but mods can't
change anything yet. What they will be able to replace (rooms, events, text, battles,
sprites) comes with the Ruins port. The manifest format is fixed now so that mods written
later don't have to be redone.

## Rules that won't change

- **Mods need the player's own copy of Undertale.** The engine reads the game's code and
  assets from that copy at set-up time. A mod contains only its own work and its changes
  on top of the game, never Undertale's files.
- **Mods never touch Undertale's saves.** The engine keeps its own data folder
  (`%APPDATA%\UltimateBattleEngine` on Windows) for settings, bug reports, mods and,
  later, saves. Undertale's `%LOCALAPPDATA%\UNDERTALE` is never written. Each save will
  record which mods made it.
- **The base game stays 1:1.** With no mods installed, the game runs the original code and
  is checked frame by frame against the real game. Display extras (window size, scaling,
  smooth motion) only change how frames are drawn, never the game logic.

## Where mods go

`%APPDATA%\UltimateBattleEngine\mods\<folder>\mod.json`, one folder per mod. The folder
name doesn't matter; the `id` does.

## mod.json

```json
{
  "format": 1,
  "id": "author.mod_name",
  "name": "Readable Name",
  "version": "1.0.0",
  "engine": ">=0.3.0 <1.0.0",
  "description": "What it does.",
  "authors": ["you"],
  "requires": ["other.mod"],
  "load_after": ["optional.mod"],
  "conflicts": ["incompatible.mod"],
  "enabled": true
}
```

| Field | Required | Meaning |
|---|---|---|
| `format` | yes | Manifest format. This engine reads format 1. |
| `id` | yes | Unique, lower case: `author.mod_name` (letters, digits, `_`, at least one dot). |
| `name` | yes | Shown to players. |
| `version` | yes | `major.minor.patch` (`1`, `1.2` are read as `1.0.0`, `1.2.0`). |
| `engine` | no | Engine versions the mod works with, space-separated conditions that must all hold: `>=0.3.0`, `<1.0.0`, `=0.3.0`, `^0.3` (same major version, or same minor while the major is 0). |
| `requires` | no | Mods that must be present. They load first. |
| `load_after` | no | Mods that, if present, load first. |
| `conflicts` | no | Mods this one can't run with. |
| `enabled` | no | `false` keeps the mod installed but off. |

## Load order

Mods that `requires` or `load_after` name load first. Ties are broken alphabetically by
`id`, so the order never depends on folder names or the file system.

A mod is left out entirely, never half-loaded, when:
- its manifest is invalid;
- it needs a different engine version;
- something it requires is missing or was itself left out;
- it conflicts with a loaded mod;
- it shares an `id` with another mod;
- its load order loops back to itself.

The fight select shows "Mods: N" (and how many have problems). To list the order and
every problem:

```
godot --headless --path godot -- --mods [--modsdir DIR]
```

`tests/mods/` holds fixtures for each case; `tests/run-tests.ps1` and `scripts/check.ps1`
check them.

## Versions

`godot/engine_info.gd` holds the engine version and every file format number: settings,
replays, mod manifests and (later) saves. Readers accept older formats by upgrading them
one version at a time (`godot/engine_save.gd`). They refuse newer ones without
overwriting them, so a file from a newer engine is never damaged by an older one.
