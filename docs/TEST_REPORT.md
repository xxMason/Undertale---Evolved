# Test report: milestone 1

Run on 2026-11-15 with `tests\run-tests.ps1` against Undertale v1.08 (Steam).
Result: **9 of 9 automated checks passed.**

## How the tests work

The launcher's `--selftest <scenario>` starts the real patched game. A test driver inside
the game presses keys through GameMaker's simulated-key functions, so the battle runs on
unmodified original code. The game writes a log to its save directory, and the launcher
checks the log for the expected sequence. Around every launch the launcher hashes the
whole original installation and the original save location; the test script does the
same independently (hash, size and modified time) around the whole run.

## Verified by automated test

| Check | Evidence from the run |
|---|---|
| Game boots into the custom menu, Steam not initialised | `BOOT ... steam=0`, screenshot |
| Menu navigation with keys: Player Setup, LOVE 1 to 5, HP 36 to 33, Fight Select, Froggit | `CONFIG lv=5 hp=33`, `STATE IN_BATTLE id=froggit battlegroup=4 lv=5 hp=33/36` |
| Fight Select tabs with keys: Monsters to Bosses and back, RUINS to SNOWDIN and back, down to the list | `TABS area=0 cat=1 focus=1 rows=1`, `TABS area=1 cat=0 focus=0 rows=0`, three screenshots |
| Settings: W does nothing in arrow mode; after switching MOVEMENT to WASD, S moves the menu cursor | `WASDCHK off sel=0`, `SETTINGS movement=1`, `WASDCHK on sel=0` |
| WASD reaches the battle's movement input | `WASDCHK battle timeup=1` (`obj_time.up`, which `obj_heart` reads) |
| Simulated arrow keys reach `keyboard_check_direct` | `KEYS check=1 direct=1 timeup=1` |
| Weapon, armour and inventory reach the original battle (Real Knife, The Locket, items in slots 2 and 3) | `GEAR weapon=52 wstr=99 armor=53 adef=99 item0=11 item1=1 item2=0`: stats set by the game's own equip scripts, inventory packed from slot 0 |
| A configured item works through the real ITEM menu | `GEAR used hp=20/20 item0=1`: Butterscotch Pie healed 5 to 20 HP and left the inventory |
| LOVE and starting HP reach the original battle | battle screenshot shows `LV 1`, `HP 01 / 20`; LV 20 run shows 99/99 |
| Winning returns to the results screen | `STATE VICTORY kills=1 xp=3 gold=2 hp=29/36` (EXP and gold from original code) |
| Losing plays the original game over and returns | `STATE DEFEAT hp=0` |
| Retry after a defeat starts a clean battle | `DEFEAT`, `RETRY`, `IN_BATTLE lv=20 hp=99/99`, `VICTORY` |
| Results to Main Menu to Exit | `EXIT`, process exit code 0 |
| Saves go to `%LOCALAPPDATA%\UltimateBattleEngine` | log, config, screenshots and the game's own `undertale.ini` (game-over counter) appear there |
| Original installation unchanged | 221 files identical by SHA-256, size and timestamp |
| Original save location unchanged | `%LOCALAPPDATA%\UNDERTALE` absent before and after |
| Missing or unknown game files are refused | exit code 2, nothing copied |
| No game assets or binaries tracked by Git | `git ls-files` check |

## Encounter sweep (all 98 catalogue entries)

`UltimateBattleEngine.exe --sweep` starts every catalogue entry at LV 20, speeds the game
up, presses confirm repeatedly (which attacks every turn) and records what happens.
`scripts\apply-sweep.ps1` writes the result into `config\encounters.json`. The game did
not crash or exit on any entry, and the originals were unchanged afterwards.

| Result | Count | Meaning | In the menu |
|---|---|---|---|
| verified | 69 | Fought to a victory and returned to the results screen | enabled |
| starts | 28 | The battle starts and runs, but ended in a defeat or was still going at the time limit, so its ending is unknown | enabled, marked `*` |
| needs-adapter | 1 | Left the battle for a story room (`bg58`, Undyne's second battle object) | disabled |

The 28 "starts" entries are mostly bosses that cannot be beaten by attacking alone or in
the time limit: Toriel, Papyrus, Mad Dummy, Monster Kid, Undyne, Undyne the Undying,
Muffet, So Sorry, the three Mettaton battles, Mettaton EX, Sans, both Asgore entries,
both Asriel entries, RG 01 and RG 02, the five True Lab amalgamates, Glyde, and four
ordinary groups where the idle player died. For these, what happens when the fight
really ends (cutscenes, room changes, a game-over that expects a save) is **not known**.

Limits of the sweep:

- It proves a fight starts, runs on original code and, for "verified", returns cleanly
  after a kill. It does not check that attacks, dialogue or ACT options behave exactly
  as in the story, and it never spares or flees.
- Every fight starts from a new-game state. Fights that change with story flags or kill
  counts (for example genocide variants) run in whatever form that state gives.
- Display names come from the names the game itself reported, with five corrected by
  hand where the game reports a placeholder.
- Not in the catalogue: battlegroups 1, 19, 21, 69-75, 87-90 and Photoshop Flowey
  (reasons in `config/encounters.json`).

## Verified by inspection only

- The isolation gate's refusal paths (overlapping folders, Steam files present, wrong
  GEN8 name) are implemented but were not triggered in a test.
- Results text for a battle that ends without a kill.

## Not tested

- **Playing by hand.** Nobody has yet played the build with a real keyboard. In
  particular, the runner ignored simulated keys for the first few seconds after start;
  whether real key presses are affected in that window is unknown.
- **Spare and flee endings.** They use the same return path as victory in the original
  code, but no test exercised them.
- **Menu music.** The menu loops `mus_house1` ("Home", the track `obj_housemusic` plays
  in Toriel's house) and stops it when a battle starts. The code runs without error, but
  nobody has listened to it.
- **Equipment and items beyond the tested set.** Only Real Knife, The Locket,
  Butterscotch Pie and Monster Candy were exercised. Weapon and armour choices in the
  menu were not driven by a test, and equipping gear from the inventory mid-battle was
  not tried.
- **WASD with a real keyboard.** The tests press W/A/S/D through simulated keys. The
  helper may add up to one frame of input delay in WASD mode; this was not measured.
- **Mouse support** in the menus, including clicking tabs.
- **Areas with a single tab** (JUDGEMENT HALL, BARRIER) were not opened in a test; the
  Bosses-only layout is implemented but unseen.
- **Fullscreen (F4) and window scaling.**
- **Original saves that actually exist.** This machine had no Undertale save folder, so
  the "unchanged" result proves nothing was created there, not that existing files
  survive. The mechanism (different save folder, Steam removed) does not depend on
  whether saves exist, and the launcher compares them on every run.
- **Launching the original game afterwards.** Its files are byte-identical, but it was
  not started as part of this run.
- Profile export (`--export-profile`).

## Incomplete in milestone 1

- HP override above the normal maximum.
- 97 of 98 catalogue entries are enabled, but 28 of them have unverified endings (see
  the sweep section).
- Training Mode, Custom Battles, Statistics and Settings are shown greyed out.
- The ERROR state exists but nothing raises it.
- Scrolling of long fight lists was only seen at the top position in screenshots.
