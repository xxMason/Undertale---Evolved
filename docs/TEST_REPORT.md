# Test report: milestone 1

Run on 2026-11-15 with `tests\run-tests.ps1` against Undertale v1.08 (Steam).
Result: **9 of 9 automated checks passed.**

Latest full run, 2026-11-17: **28 of 28 checks passed**, including the new Godot engine
checks (all 6272 original code files parse; Dummy and Froggit won; Papyrus, Undyne,
Muffet and Mettaton EX run several turns with their SOUL modes and no script errors).

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
| Custom boss from a file fights as a real monster and can be killed | `CUSTOM boss=Sentinel hp=150 atk=5 def=0 acts=2 attacks=4`, `CUSTOM bullets_seen=1 max=15`, `STATE VICTORY kills=1 ... gold=40`; screenshots show its own sprite, intro text and bullets |
| Custom boss can be talked down and spared through the real ACT and MERCY menus | `CUSTOM act=Talk points=1/2`, `points=2/2`, `CUSTOM spared`, `STATE VICTORY kills=0`; screenshots of the target list and ACT menu |
| Boss editor: new boss, HP 100 to 130, attack pattern and count changed, saved | `EDITOR save ... hp=130 a1=aimed count=4`; driven with simulated keys |
| Simple-attack lab: the attack loops, a number key retunes it live, Backspace returns and the change is kept | `LAB1 count=4 pat=aimed mnfight=2`, `LAB2 count=5 bullets=1`, `EDITOR save ... count=5` |
| Timeline attack plays in a real fight with its own box size | `TL box=240x100 border=9777`, `CUSTOM bullets_seen=1 max=8`, `STATE VICTORY kills=1` |
| Live-build screen: pick a bullet, place it, pick another, place it, change its angle, TEST IT, return, DONE | `LIVE add n=1`, `LIVE add n=2`, `LIVE store objects=2`, `LIVE lab objects=2 bullets=1`, `EXIT test=live`; clicks are fed to the screen's own pointer, not the real mouse |
| The editor's 1280x960 screen opens and the window returns to 640x480 | `BIGWIN window=1280x960 surface=1280x960`, `BIGWIN back window=640x480` (run separately, not part of the suite) |
| The launcher builds from its own verified copy when the Steam folder is modded | `Using the verified copy of the original game: ...\source` |
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

## Godot engine sweep (original battle code in Godot, 48 battles)

Run on 2026-11-17: `godot --headless --path godot -- --lv 20 --frames 3000 --sweep 0 47`
(see `GODOT_ENGINE.md`). Scripted input: confirm through text, FIGHT every turn, weave
left and right, jump and confirm during attacks, confirm on the game-over screen.

**No script errors and no missing GameMaker functions in any of the 48 battles.**

| Result | Battles |
|---|---|
| Won (35) | Dummy, Froggit, Whimsun, Moldsmal, Migosp, Vegetoid, Loox, Napstablook, Parsnik, Moldessa, Migospel, Snowdrake, Chilldrake, Ice Cap, Gyftrot, Jerry, Doggo, Lesser Dog, Dogamy & Dogaressa, Greater Dog, Aaron, Woshua, Moldbygg, Temmie, Shyren, Glad Dummy, Tsunderplane, Vulkin, Pyrope, Mettaton NEO, Madjick, Knight Knight, Final Froggit, Whimsalot, Astigmatism |
| Player died, original game over played and the battle ended (3) | Undyne the Undying (turn 6; see the argument bug below, now turn 1), Sans (turn 1), Asgore (turn 7) |
| Still going at 3000 frames, turns advancing (10) | Toriel (turn 11), Glyde (10), Papyrus (7), Mad Dummy (7), Undyne (10), Royal Guards (10), So Sorry (8), Muffet (8), Mettaton EX (7, in the game over), Asriel (8) |

The ten unfinished fights are ones the scripted input cannot end within 100 seconds:
fights that need ACT or MERCY, bosses that cannot be killed by FIGHT alone (Mad Dummy,
Asriel), and long boss fights. None of them is stuck: every one is several turns in.

SOUL modes checked on screen during attacks (screenshots): blue gravity and jumping
(Papyrus, Sans: `obj_heart.movement = 2`, landing and jump arcs traced frame by frame),
green shield (Undyne), purple strings (Muffet), yellow shooting (Mettaton EX).

Fixed during this sweep: GameMaker's Outside Room event was missing (55 objects use it to
remove bullets; Asriel's stars piled up into the hundreds); equal-depth objects drew in an
unstable order; curved paths were straight; `distance_to_point` and `sprite_delete` were
missing. Asriel's fight went from about 39 ms to 10 ms per game frame.

### Translated code vs interpreter (2026-11-17)

The game's code now runs as translated GDScript (see "Speed" in `GODOT_ENGINE.md`). Both
ways were swept with the same seeded random numbers
(`--lv 20 --frames 1500 --sweep 0 47`, once with `--interp`): **all 48 battles gave
identical results** (31 won, 2 ended in the original game over, 15 still going at the
1500-frame cap), with no script errors. The translated sweep took 137 s against 253 s
interpreted, headless.

The comparison found a real bug in the interpreter: a script that assigns to its own
arguments (`scr_sr` does `argument3 = 1`) stored the value on the instance, where the next
script that instance ran read it as its argument. In Undyne the Undying this made every
spear that got past the shield do 1 damage instead of 14. Fixed in both paths; earlier
results for that fight (which survived to turn 6) were wrong.

Windowed, LV 20, 900 frames, worst game frame (budget 33 ms): Asgore 16.6 ms, Sans
13.4 ms, Undyne 11.0 ms, Asriel 8.6 ms; drawing under 1 ms. No frame over 20 ms.

Mouse control (menus and battle buttons) is implemented but has only been checked by
running the code, not by clicking through it by hand.

### Frame-by-frame comparison with the real game (2026-11-17)

`scripts\trace-compare.ps1` (see "Matching the real game" in `GODOT_ENGINE.md`) ran 43
battles in the real game and in Godot with the same seed and the same keys, LV 20, up to
1500 frames, comparing every frame: HP, karma, invincibility, the SOUL's position, battle
state, object count and the sum of every battle object's position.

**All 43 battles agree on every value of every frame**: Dummy, Froggit, Whimsun,
Moldsmal, Loox, Vegetoid, Napstablook, Toriel, Doggo, Lesser Dog, Dogamy & Dogaressa,
Greater Dog, Papyrus, Gyftrot, Snowdrake, Ice Cap, Jerry, Aaron, Temmie, Woshua, Shyren,
Mad Dummy, Undyne, Royal Guards, Tsunderplane, Vulkin, Pyrope, Muffet, Madjick, Knight
Knight, Final Froggit, Astigmatism, Whimsalot, Mettaton EX, Glad Dummy, Mettaton NEO, Sans
(through the game over), Asgore, Parsnik, Glyde, So Sorry, Undyne the Undying (through the
game-over heart shards) and Asriel. Not compared yet: Migosp, Moldessa, Migospel,
Chilldrake, Moldbygg.

The last two drifts were the runner's direction/speed conversion, measured with
`ube_motion_probe`: single-precision pi and cos/sin, and hspeed, vspeed and speed snapped
to a whole number within 0.0001 (a heart shard thrown at 270.2455 degrees falls at exactly
7, not 6.99994). The Undying test in `run-tests.ps1` now covers all 700 recorded frames.

Screenshots (`trace-compare.ps1 -Shots`, every 50 frames, pixel by pixel):
- Sans: the Gaster Blaster beams went from 1,284 differing pixels to 1, after measuring
  how the runner fills `draw_line_width` (`ube_draw_probe`).
- Undyne: the background grid sat one row off at fractional heights (outlined rectangles
  land on ceil()), and translucent drawing was one shade off (alpha is a byte,
  floor(alpha * 255)); 6 of 20 frames are now identical, down from 0, and the rest differ
  only by one unit (of 255) on blends that aren't whole numbers. That last unit depends on
  the graphics card (this one rounds some blends down), so it is left alone.
- Asgore and Papyrus: one-unit channel differences on faded or tinted sprites and text,
  same cause. Papyrus: 15 of 20 frames identical.
- Plain 1-pixel `draw_line` is still not exact (the runner leaves out one end pixel by a
  rule not pinned down); a few thin strings and shadows use it.

Smooth rendering (F2) now blends sizes, scales and angles as well as positions, so the
battle box no longer comes apart while it resizes (seen on Undyne at half-way frames).

Monster deaths: the dust (hundreds of one-pixel instances) made frames take 25-60 ms;
caching the object-order list and each collision target's instances brought the worst
frame of the Dummy's death under 20 ms (a frame has 33 ms), with all traces unchanged.

What the comparisons found and fixed (each measured in the real game first, the
collision rules with `ube_coll_probe`, whose 49 results now all agree):
- Collision boxes are anchored on the mask's first column/row and sized by rounding
  from there (a 1.5 px mask covers 1 or 2 pixels depending on where it starts).
- Two rectangle masks only compare boxes, even when rotated (Madjick's cross zaps meeting
  the box border); a rectangle against a precise mask is tested pixel by pixel.
- The mask lookup multiplies by the single-precision reciprocal of the scale (Knight
  Knight's growing sun bullets hit or missed the SOUL a frame early or late).
- Reading `object.var` takes the oldest instance (Aaron's sweat drops fell at the wrong
  speed).
- Instances created during Draw at a lower depth are drawn the same frame (Sans's Gaster
  Blasters started moving a frame late).
- After `room_goto` the old room's remaining events are skipped and the new room runs that
  frame (game over: one extra invincibility frame, and the game-over timers a frame late).
- At room start every placed instance exists before any Create event runs (Sans's box
  borders showed for a moment); the view position drives screen shake; `merge_colour`
  rounds each channel (the HP bar's red).
- Earlier in the same work: single-precision positions, speeds, scales, angles and alpha;
  GameMaker's comparison epsilon; alarm rounding; right-to-left argument order; animation
  timing.

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
- **Custom bosses beyond the example.** Only `sentinel.ini` was run. Across the two test
  fights its attacks were chosen in order, but which of the four patterns actually ran was
  not recorded, so `ring` and `wall` in particular are unconfirmed. Losing to a custom
  boss, the Insult ACT, the Check text, fleeing, other box sizes, game sprites as the boss
  image and a boss with no speech lines were not exercised.
- **Test flakiness.** In the last full run (18 of 18 passed) three scenarios failed their
  first attempt and passed on the automatic retry: `wasd`, `editor` and `live`. Earlier
  failures of this kind were traced to the game window losing focus while the PC was in
  use; that was not confirmed for these three.
- **The Battle Creator with real input.** Nobody has used the boss editor or the
  live-build screen by hand. Typing text, dragging objects, turning them with the handle,
  scrubbing the timeline, undo and redo, copy and delete, switching attacks, hitboxes,
  pause and slow, the OBJECTS list and box-size steppers were not exercised by any test.
- **How closely the live-build preview matches a real fight** was not measured; it uses
  the same numbers but draws bullets itself.
- **The Steam Undertale folder is now a modded install** (Undertale Together, installed
  on 2026-11-16 at 19:00, not by this project). The suite checks it did not change during
  a run, but it is no longer the original game; the simulator builds from `source\`.
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
- Statistics is shown greyed out.
- Custom Battles plays bosses defined in files (`docs/BATTLE_CREATOR.md`). There is no
  in-game editor, phases, or custom music yet.
- Training Mode has infinite HP, game speed, retry key, hitboxes and hit counting. Attack
  and phase selection, checkpoints, saved statistics and training presets are not built.
- The ERROR state exists but nothing raises it.
- Scrolling of long fight lists was only seen at the top position in screenshots.
