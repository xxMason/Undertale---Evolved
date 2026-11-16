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
| Training Mode: game speed, retry key, infinite HP and hit counting in a real fight at 1 HP | `TRAIN speed=60 trainer=1`, `TRAIN retry`, `STATE VICTORY ... hp=1/20`, `TRAIN hits=7 dmg=7 lethal=7`, `TRAIN survived_lethal_hit`; screenshots show the status line and hitbox outlines |
| Authentic Mode has no trainer object | every other self-test logs `training=0`, and the trainer is only created when Training Mode is on |
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
`--sweep-unverified` then replays only the entries that did not reach an ending, this
time with the Real Knife, The Locket and Training Mode's infinite HP, and a longer time
limit, so bosses can be fought to their endings. `scripts\apply-sweep.ps1` writes the
results into `config\encounters.json`. The game did not crash or exit on any entry, and
the originals were unchanged afterwards.

| Result | Count | Meaning | In the menu |
|---|---|---|---|
| verified | 87 | Fought to its ending and returned to the results screen | enabled |
| starts | 11 | The battle starts and runs, but attacking alone never ended it within the time limit | enabled, marked `*` |

Two of the 87 end through the story guard rather than the normal return path: Asgore
(the game moves to `room_emptywhite` after the fight) and `bg58`, Undyne's second battle
object (`room_water_undyneyard`). The guard returned both to the results screen.

Still unverified (`*`): the five True Lab amalgamates (they cannot be killed, only
spared), Mettaton's second and third battles, Sans, the Asgore intro sequence, and both
Asriel entries. What happens when these really end is **not known**; the story guard
would catch a jump into a story room, but not a fight that quits or restarts the game.

Limits of the sweep:

- It proves a fight starts, runs on original code and returns cleanly after being won by
  attacking. It does not check that attacks, dialogue or ACT options behave exactly as in
  the story, and it never spares or flees.
- 18 of the 87 were verified only in the powered run (Real Knife, infinite HP).
- Display names come from the names the game itself reported, with five corrected by
  hand where the game reports a placeholder.
- Not in the catalogue: battlegroups 1, 19, 21, 69-75, 87-90 and Photoshop Flowey
  (reasons in `config/encounters.json`).

## Story safeguards

| Safeguard | Evidence |
|---|---|
| Story memory (`undertale.ini`, `file0`-`file9`, `system_information_962/963`) in the simulator's folder is deleted before every launch and every fight | launcher logged `Cleared simulator story memory: undertale.ini`; the death counter written by a lost fight was gone before the retry |
| A fight that leaves for a story room is returned to the results screen | `GUARD left battle for room_emptywhite after 8320 frames` (Asgore), `STATE STORY_EXIT` |
| None of this touches the original game | originals compared unchanged after both sweeps and every test run |

Consequences to be aware of:

- Every fight is a first encounter on a new timeline. Dialogue and behaviour that depend
  on earlier story (deaths so far, kills, who was spared, Flowey's and Sans's memory,
  genocide variants) always appear in their new-game form.
- Fights never grant lasting progress: EXP, gold, kills and items exist for that fight only.
- Not covered: code that calls `game_end()` or `game_restart()` (the Flowey and
  world-ending sequences do). None of the 87 verified fights did this; the 11 unverified
  ones are unknown. The world-destroying sequence also tries to delete `UNDERTALE.exe`
  by name; the simulator's runner has a different name and lives in its own folder.
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
- **Training Mode beyond Froggit.** Tested in one fight at 200% speed. Other speeds,
  slow-motion, retry from the game-over screen, and bosses were not tried. Fights whose
  damage does not go through `global.hp` and `obj_battlecontroller` (if any) would not be
  covered by infinite HP.
- **Hitboxes are bounding boxes** of the 69 object types that have a collision event with
  the SOUL, not pixel-precise masks, and attacks that hurt without such an event are not
  outlined.
- **HP lost** counts HP actually removed, so a hit that would have done more than your
  remaining HP is under-counted.
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
- All 98 catalogue entries are enabled, but 11 of them have unverified endings (see
  the sweep section).
- Custom Battles and Statistics are shown greyed out.
- Training Mode has infinite HP, game speed, retry key, hitboxes and hit counting. Attack
  and phase selection, checkpoints, saved statistics and training presets are not built.
- The ERROR state exists but nothing raises it.
- Scrolling of long fight lists was only seen at the top position in screenshots.
