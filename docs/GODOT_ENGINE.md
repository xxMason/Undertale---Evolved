# Godot engine (original game code)

`godot/engine.tscn` (the project's main scene) runs Undertale's **own battle code** inside
Godot, and now the game itself from its first room (see "The game (overworld)"). Nothing about the fights is rewritten: every enemy, attack, SOUL mode, menu and
text box is the game's decompiled GameMaker code, interpreted at runtime, using the
sprites, sounds, fonts and music from the player's own copy. None of that is in Git.

The older hand-built prototype (`battle.tscn`, `ut_sim.gd`) is still in the project; see
`GODOT_PROTOTYPE.md`. Its frame-exact SOUL measurements are what this engine's motion
and collision rules were checked against.

## Running it

```
powershell -ExecutionPolicy Bypass -File scripts\prepare-godot.ps1
"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path godot
```

`prepare-godot.ps1` reads `source\data.win` (the launcher's verified copy, never the
Steam install) with UndertaleModTool and writes `godot\extracted\`: all 6272 code entries
decompiled (0 failures), the object table (parents, events, depths, masks), the battle and
game-over rooms, every sprite frame with its collision mask, backgrounds, fonts, sounds,
paths and the music. About 190 MB; ignored by Git and by Godot's importer.

Fight select: area tabs (RUINS ... BARRIER) with MONSTERS / BOSSES tabs (empty tabs are
left out), arrows to move, Z to fight, C for Setup, F2 smooth rendering, F3 WASD,
F4 fullscreen, Esc leaves a battle or quits.

Setup (all saved):
- LV 1-20
- movement: arrows or WASD
- smooth motion: frames drawn at the screen's own rate, blended between the game's 30
  per second; the game logic always runs at 30
- window size: 1x to 4x of 640x480
- scaling: pixel-perfect whole multiples, or fill the window keeping 4:3
- fullscreen

The window can also be resized freely.

Testing keys, anywhere in a battle:
- F9: debug overlay. Every collision box (red: the SOUL, yellow: objects with collision
  events, green: the rest), the frame, logic time, instance count, room, seed, HP,
  invincibility, KARMA and battle state. Hover over something to see each instance under
  the mouse: object, id, position, depth, sprite, frame and running alarms.
- F10: pause. F11 then advances one game frame at a time.
- F12: bug report. See "Bug reports and replays" below.
- F5: the debug menu (see below).

### Debug menu (F5)

`godot/debug_menu.gd`, in the game and in battles. While it is open the game keeps running
but gets no keys; Space pauses and resumes, PageUp/PageDown change tab, Esc or F5 closes,
and `<>` moves the panel to the other side. Mouse and keyboard both work.

| Tab | What it does |
|---|---|
| Player | name, LV (sets EXP, max HP, AT and DF to match, as the game's level-up does), HP, max HP, AT, DF, EXP, gold, kills |
| Items | the 8 item slots, weapon and armour (equipped with the game's `scr_weaponeq` / `scr_armoreq`), 4 phone slots |
| Story | `plot`, any `global.flag[N]`, and values to keep on screen (`plot, flag.202, obj_toroverworld3.x`) |
| Warp | story points the walkthrough plays from (room and plot set to match); any room by name; click to move the player |
| Battle | start any battle group where you stand (as an encounter); no damage (`global.invc`); keep HP full; monsters to 1 HP; make spareable (`mercymod`) |
| World | game speed x0.25 to x8; walk through walls (the game's own `global.phasing`, walls not solid); no random encounters / encounter now, with the step counter; monsters left per area for genocide (`flag[202..205]` against 20, 16, 18, 40); auto-advance text; FUN (`flag[5]`); reseed the random generator |
| Saves | the game's own save (`scr_save`); 3 quick save slots of the exact moment (every instance, globals, room, kept rooms, random generator; not the music); undo everything since the menu opened; open the save folder |
| Inspect | click an object in the game (or pick one from the list): its variables, alarms, box and the last events it ran, live; set any variable |

Cheats (no damage, keep HP, walls, encounters, auto text, speed) are off at every start.
Everything changed is listed in the Story tab and in F12 reports; saves written after a
change get `<save>.debug` next to them (file0.debug...) listing what was changed, so the
save itself stays in Undertale's format.

Tests: `--debugtest F` uses each part once at game frame F and prints `DEBUGTEST ok/FAIL`
lines; `--debugtest2 F` checks the battle cheats; `--debugkeys F` (windowed) sends real
F5, Space, Esc, arrow and mouse events; `--debugopen F [TAB]` opens it for screenshots.

Data folder: `%APPDATA%\UltimateBattleEngine` (settings, `reports\`, `mods\`). It is
separate from Undertale's own save folder, which the engine never writes. Settings from
builds that used the old "UBE Battle Prototype" folder are picked up once.

Mouse: everything in the fight select is clickable (tabs, rows, the Player Setup button,
LV arrows, the movement toggle); hovering a row selects it, the wheel scrolls, right-click
closes Player Setup. In battle, hovering FIGHT / ACT / ITEM / MERCY selects that button,
left-click is Z, right-click is X and the wheel is Up/Down, so every submenu works with
the mouse. The clicks are fed to the game's own menu code as key presses, so nothing about
the battle menus is reimplemented.

## The game (overworld)

G on the fight select (or `--game`) starts **Undertale itself** from its first room:
intro story, title menu, naming, Flowey, Toriel, the Ruins. As with battles, nothing is
rewritten. Rooms, tiles, backgrounds, views and objects come from `data.win`, and every
cutscene, puzzle and NPC is the game's own code.

What the engine adds for this (in `gml_vm.gd` / `gml_builtins.gd`):
- **Rooms.** `vm.load_room` follows GameMaker 1.4's order:
  1. Room End;
  2. keep or drop the old room's instances;
  3. place every instance, then run each one's Create and creation code;
  4. Game Start (first room only), the room's creation code, then Room Start.
  A room with `room_persistent` set (Undertale sets it before most battles) is kept as it
  was, alarms included, and comes back without Create events.
- **Views.** Undertale's 320x240 view is drawn at 2x into the 640x480 window. A view
  follows its object with GameMaker's border and speed rules and stays inside the room.
  With smooth motion on, the camera is smoothed between game frames like everything else.
- **Backgrounds and tiles.** The background colour and the back layers come first. Tiles
  are drawn between the instances by depth, and the front layers last. Layers scroll by
  their speeds. `tile_layer_shift/hide/show/delete`, `tile_add` and `tile_delete` work.
- **Save files.** `ini_*` and `file_text_*` work for real in game mode, inside
  `%APPDATA%\UltimateBattleEngine\undertale\`. Only the file name the game asks for is
  used (any folder part is dropped), so nothing is written anywhere else. Undertale's own
  saves in `%LOCALAPPDATA%\UNDERTALE` are never read or written. Battles started from the
  fight select still see no save files at all, so their traces don't change.
  Deleting that folder starts the game from scratch; Flowey remembers otherwise, as in the
  real game.

Testing options:
- `--room NAME`: boot, then go straight to a room.
- `--press "F:K[xN],..."`: key K held from frame F for N frames.
- `--gameshot "F,F" DIR`: screenshots.
- `--seed N`: fixed random seed; the clock then runs on game frames, so a run repeats
  exactly.
- `--savedir DIR`: a separate save folder, emptied first.
- `--unknown`: print missing functions.
- `--dumpinst`: list objects when stopping.
- `--frames N`: stop after N frames.
- `--bot FILE`: play a walkthrough script with `godot/game_bot.gd` (`--botexit` stops
  when it ends). The commands are listed at the top of that file:
  - waits on story conditions (`plot>=5`, `room=`, `exists=`, `notext`, `OBJ.VAR=N`...);
  - `path X Y` walks around walls, planning through the room's solid objects (precise
    masks such as Toriel's stairs are tested by their pixels) and around holes, unless
    the target is in one;
  - `use OBJ` walks up to an object from whichever side it can reach, faces it and talks
    until the text is gone, and fails if nothing was said;
  - `push OBJ DIR COND`, `roam DIRS COND` (walk with keys held, e.g. into an encounter),
    `canmove DIR`, `choose 0|1` (answer for choice boxes), `talk`, `face`, `expect`,
    `shot`, `where`, `near`, `show`;
  - `battle fight|spare|flee|act:N|acts:N`. `act:N` uses the sparing ACT of monsters it
    knows (Loox: Don't Pick On, Vegetoid: Dinner, then it eats the green carrots).
  `tests/walkthrough_ruins.txt` plays from the first room through the Ruins, Toriel's
  house and fight, to Snowdin's first room, and checks the story state in each room; a
  broken cutscene or puzzle stops it there. `tests/stress_ruins.txt` starts random
  encounters while walking (and mashing Z) and reads a save point mid-walk, checking that
  the player can still move after each.
- `--watch`: every 10 frames, print where Toriel and the player are, with sprite,
  direction and path position.

Headless game runs go as fast as possible (the whole Ruins walkthrough, about 31800
frames, takes about a minute and a half).

F9 shows collision boxes and plot/interact/entrance in the overworld too. F10/F11 pause
and step. F12 saves a screenshot, the room and position, and a copy of the save files.
Overworld replays aren't done yet.

Not done yet:
- the overworld isn't compared frame by frame with the real game (the battles are);
- 30 fps only;
- `game_restart` returns to the fight select;
- areas beyond the Ruins are untested.

## The roster

One battle per monster and every real boss (48). Monsters that only appear in groups are
fought alone using the group's own placement and music. Story-only encounters (Flowey,
the Undyne date, Monster Kid, Mettaton's quiz/cooking/news shows, the Asgore intro, the
Lost Souls) and the True Lab Amalgamates are left out.

| Area | Monsters | Bosses |
|---|---|---|
| Ruins | Dummy, Froggit, Whimsun, Moldsmal, Migosp, Vegetoid, Loox; Hard Mode: Parsnik, Moldessa, Migospel | Napstablook, Toriel |
| Snowdin | Snowdrake, Chilldrake, Ice Cap, Gyftrot, Jerry, Glyde, Doggo, Lesser Dog, Dogamy & Dogaressa, Greater Dog | Papyrus |
| Waterfall | Aaron, Woshua, Moldbygg, Temmie, Shyren | Mad Dummy, Glad Dummy, Undyne, Undyne the Undying |
| Hotland | Tsunderplane, Vulkin, Pyrope | Royal Guards, So Sorry, Muffet, Mettaton EX, Mettaton NEO |
| Core | Madjick, Knight Knight, Final Froggit, Whimsalot, Astigmatism | |
| Judgement Hall | | Sans |
| Barrier | | Asgore, Asriel Dreemurr |

## How it works

| Part | File | What it does |
|---|---|---|
| Extraction | `scripts/extract_engine.csx` | Decompiles all code and exports assets and tables to `godot/extracted/` |
| Compiler | `godot/gml/gml_compiler.gd` | Lexer and parser for the decompiled GML (all 6272 files parse; `tools/parse_all.gd` checks) |
| Runtime | `godot/gml/gml_vm.gd` | Instances, variables, events with parent inheritance, `with`, alarms, paths (including GameMaker's curved-path subdivision), precise collision masks, and the GameMaker frame order |
| Translator | `godot/gml/gml_transpiler.gd` | Turns each parsed code entry into a GDScript class that Godot compiles, so the game's code runs as native GDScript instead of being walked node by node (the interpreter remains as the fallback and for `--interp`) |
| Built-ins | `godot/gml/gml_builtins.gd` | About 300 GameMaker functions: drawing, text, audio, input, maths, strings, instances, ds_map/ds_list, actions |
| Input | `godot/gml/gml_keys.gd` | GameMaker key codes, WASD option, scripted keys for tests |
| Drawing | `godot/gml/gml_recorder.gd` | Draw events run once per game frame (some contain game logic) and are replayed every rendered frame. With smooth rendering on, an instance that drew the same calls on both game frames has every position, rectangle, scale and angle blended between them (so the battle box's sides and corners stay joined while it resizes); otherwise its drawing is shifted back towards its previous position |
| Host | `godot/engine.gd` | Fight select, Player Setup, starting a battle the way the game does, ending it when the game leaves the battle room |

Frame order follows GameMaker 1.4, as measured against the real game (see "Matching the
real game" below): `xprevious`/`yprevious` saved, Begin Step, animation (image_index and
Animation End), alarms (alarm 0 for everyone, then alarm 1, ...), keyboard / key press /
key release, Step, motion (friction, gravity, path, speed), Outside Room, collisions
(inherited from parent objects, each instance's targets in ascending object order), End
Step, Draw (depth list), Draw GUI. Every event except
Draw runs object by object in object order, each object's instances in creation order.

Runner details that change outcomes, all measured:

- Positions, speeds, `image_index`/`image_speed`, image scales, angle and alpha are
  single precision (the real game's alpha reads 0.220000148 where doubles give 0.22).
- Every number comparison uses GameMaker's epsilon, 0.00001: Undyne's darkener goes when
  its alpha reaches 0.000000014, because that counts as `<= 0`.
- Alarms store whole numbers, rounded half to even (`20 + random(20)` = 20.28 fires on
  step 20).
- Function arguments are evaluated last to first (`instance_create(x + random(a),
  y + random(b), ...)` draws `b`'s number first).
- Collision boxes: the edge of the mask's first column (row) is rounded, half to even, and
  the other edge is round(that + scaled size), so a 1.5 px mask covers 1 or 2 pixels
  depending on where it starts; mirrored masks start from their other side.
- Collision masks: the mask sits on the position rounded to a whole pixel, a world pixel's
  corner is mapped into it, and the scale division and rotation are in single precision
  (8 / 1.6 is exactly 5). Two rectangle masks only compare bounding boxes, even when
  rotated; a rectangle against a precise mask is tested pixel by pixel (rotated: the
  rotated rectangle). `collision_point` on an unrotated rectangle mask is its box.
- Reading `object.var` takes the oldest instance (Aaron's `blt_muscbul.vspeed -= 0.02`
  gives every bullet the first bullet's speed).
- Draw walks the live depth list: an instance created during a Draw event at a lower depth
  is drawn, and runs its Draw, in the same frame (Sans's Gaster Blasters).
- After `room_goto` no further events run in the old room that frame; the new room is
  loaded and its events run in the same frame (game over: the SOUL's invincibility stops
  counting at once, and the game-over heart's alarms start counting that frame).
- Direction/speed and hspeed/vspeed convert with a single-precision pi and single-precision
  cos/sin, and hspeed, vspeed and speed snap to a whole number when within 0.0001 of it
  (direction 270.2455 at speed 7 gives vspeed exactly 7). Gravity adds to hspeed/vspeed
  without snapping, with the angle in radians rounded to single precision, so straight-down
  gravity nudges hspeed by about 2e-9 a step (heart shards on the game-over screen).
- At room start every placed instance exists before any Create event or creation code runs.
- The view position (`view_xview`/`view_yview`) offsets drawing: screen shake.
- `merge_colour` rounds each channel.
- Collision events run in ascending target-object order: a Moldbygg bullet touching the
  SOUL and the top border on the same frame hits the SOUL before the border removes it.
- The random number generator is GameMaker's WELL512a with its seeding and scaling.

Drawing details, measured with `patches/gml/scripts/ube_draw_probe.gml` (logged as `DRAW ...`
by the trace scenario) and screenshot comparisons:

- Alpha reaches the GPU as a byte, floor(alpha * 255): 0.333 draws white at 84 on black.
- `draw_line_width` quads are filled as if each pixel were sampled at its top-left corner
  minus half a pixel; Godot draws them one pixel right and down (Sans's beams match).
- Outlined `draw_rectangle` lands on ceil() of each coordinate (16.33 -> row 17); filled
  rectangles already match.
- Not exact: plain 1-pixel `draw_line` (the runner skips one end pixel by a rule not yet
  pinned down; used by a few thin strings and shadows), and blends that are not whole
  numbers, which can be one unit (of 255) off depending on the graphics card.

## Matching the real game

`scripts/trace-compare.ps1 -Group N` runs one fight in the real game (the simulator's
patched copy, scenario "trace": seeded random numbers, scripted keys) and the same fight in
Godot with the exact keys the real game saw, then compares every frame: HP, karma,
invincibility, the SOUL's position, battle state, object count and a checksum of every
battle object's position. `-Watch NAME` (or `*`) also compares one object's positions and
frames (with hspeed, vspeed and direction to 9 decimals), `-Reuse` reuses the last real
trace, `-RealTrace FILE` compares against a saved one. Traces are numbers only. Any
battle group number works, not just the roster's (a group with no roster entry runs as
"Group N" with the game's own setup for it).
`scripts/shots-all.ps1 [-Groups 2,4] [-Frames 900] [-Reuse]` runs `-Shots` for every group
that has a saved real trace and writes one line per group (identical frames, worst frame)
to `logs/trace/shots_summary.txt`.
`-Shots` saves a screenshot every 50 frames in both (the Godot side runs in a window) and
compares them pixel by pixel with `scripts/shot-compare.ps1`; images and red-marked
`diff_F.png` files stay in `logs/trace/shots_gN/` (git-ignored). Godot's own
`--shotsdir DIR --shotevery N --shotblend F` saves every Nth frame drawn F of the way from
the previous game frame, to inspect smooth rendering.
`ube_motion_probe.gml` logs the runner's direction/speed conversions (`MOTION ...`).
`godot -- --collprobe` runs `patches/gml/scripts/ube_coll_probe.gml`, which the real game
also runs and logs (`COLL ...`): collision boxes and hits at fractional positions, scales and
angles. Godot debugging flags for traces: `--dumpat F`, `--watch NAME`, `--colllog`,
`--alarmlog`, `--hits`.

A battle starts like the real game: `obj_time` (its original input code runs), the game's
start-up scripts, the player's LV, HP, AT/DF and equipment, `global.battlegroup`, then the
real `room_battle` with its instances and creation code. The battle is over when the game
goes back to the room it came from.

## Speed

The decompiled code is translated to GDScript once, at prepare time
(`tools/transpile_all.gd --write`, run by `prepare-godot.ps1`), into
`godot/extracted/gd/`. Each file carries a stamp of the translator version and the
built-in table; a stale file is ignored and translated again on the fly, so the engine
never runs out-of-date code. If you change the translator or the built-ins, rerun
`prepare-godot.ps1` (or just `transpile_all.gd --write`) to refresh the files.

Godot still has to compile those scripts. While the fight select is open the engine
compiles them in the background (the menu shows "Preparing battles... N%"), battle
machinery first. When a battle starts, every script it can reach (its objects' events,
the objects they create and the scripts they call, recorded in `_refs.json`) is compiled
before the first frame, so nothing compiles mid-attack.

Measured at LV 20, 900 frames, on screen: Asriel's logic went from 8.9 s to 2.8 s in
total; worst frames are now Asgore 16.6 ms, Sans 13.4 ms, Undyne 11.0 ms, Asriel 8.6 ms
(a frame at 30 fps has 33 ms), where compile hitches of around 100 ms used to happen.
`--spikes` prints any frame over 20 ms; `--prof` (with `--sweep`) adds time per frame phase
(`#begin_step`, `#alarms`, `#step`, `#motion`, `#collisions`, ...).

Monster deaths create hundreds of one-pixel dust instances at once. The object-order list
every event pass uses is now cached until an instance is created, removed or changes
object, and sorted natively, and each collision target's instances are cached too (the
SOUL used to be searched for through the whole list once per bullet). The Dummy's death
went from 25-60 ms frames to under 20 ms, and Knight Knight's collision time over a fight
from 1.7 s to 0.45 s. Smooth rendering decides how to blend each instance once per game
frame, not on every rendered frame.

Later passes: event passes skip objects with no handler for the event, the depth list
inserts by binary search, unscaled sprites draw directly, and the translator handles
`x++;` statements (the text writer used to fall back to the interpreter: 7 ms a frame,
now 0.5 ms). Dust frames are now about 9-15 ms. To look for hitches on screen:
`--battle 0 --hitchlog` prints every displayed frame over 25 ms (`HITCH frame dt logic
draw inst ops`), and `--prof --spikes` prints the top phases of any game frame over 8 ms.

## Title screen, universes and co-op

- `front_menu.gd`: the name prompt, the UNDERTALE: Evolved title screen, the universe list (create, rename, cheats, delete), Settings and Join.
- `universes.gd`: each universe is a folder in `%APPDATA%\UltimateBattleEngine\universes\<id>` with `universe.json` (name, cheats, players) and `save\` (the game's file0 / file8 / undertale.ini, plus `coop_friends.json`).
- `coop_net.gd`: LAN co-op in lockstep. Both PCs run the whole game from the same keys: each frame's keys from both players go to both (3 frames of input delay; `--coopdelay N` on both PCs changes it, tests use 1 so a bot's keys land on the frame it chose them for), a state checksum every 30 frames, and the host resends its full state (`coop_state.gd`, about 8 KB compressed) if they ever differ. Games are found by a UDP beacon on port 7778; play is on 7777. Sound timing in co-op runs on game frames (`det_audio`) so both PCs agree.
- `coop_partner.gd`: the second player in the overworld. The game has one player, the leader; the other walks the same room and takes the lead (positions and their own HP, items, gold, weapon and armor swap) when they press Z, open their menu (C) or use a door. Each PC's picture follows its own player, except while `global.interact` is set (text, menus, cutscenes): the game places text boxes by its own view, so then both PCs draw that view, and the other player's menu is labelled with their name. A save point (obj_savepoint healing the leader) heals both. A friend who leaves and comes back in the same session gets their character back as it was (`_left_friends`, cleared by a load). On a game over either player's keys count.
- `coop_battle.gd`: the second SOUL. It's a second obj_heart; events on it (or on a bullet touching it) run with that player's keys and stats swapped in (`scoped` / `scope_enter` / `scope_exit` in `gml_vm.gd`), so Undertale's own movement and damage code runs for both. Turns alternate. Outside the dodging part the second SOUL gets no keys (obj_heart's Step works the battle menu, so a waiting friend's Z would pick options too), and when the turn passes the SOUL that becomes the game's own takes over its visibility (it's the menu cursor). Flowey's first fight (room_floweybattle) is the leader's alone. Down, Revive (MERCY, after 3 turns, 30%, then 90 frames safe from attacks) and "Who?" for items are done around the game's own menu by holding back keys.
- Saves: `file0` / `file8` always hold the host's own things (patched after the game writes them); `coop_friends.json` holds each friend's, written at the same moment and read back on load.
- `sans_speech.gd`: what a friend gets on their first F5 in a universe without cheats (their screen only).
- Tests: `--unitest`, `--fronttest`, `--coopsavetest`, `--snaptest F N`, and two games linked with `--coophost PORT` / `--coopjoin IP:PORT` (`--coopbot`, `--matehp`, `--cooplog`); all are in `scripts\check.ps1` (with `-Full`, also the story walkthrough with a friend joined, as far as Napstablook).
- Aimed attacks: while dodging, code that reads "the SOUL" gets one of the two by the reading instance's id (`aim_split`), except the battle's own bookkeeping objects (`aim_skip`).
- Commands with the keys (`coop_net.gd` `send_cmd`): a friend's own-character cheats (`coop_cheats.gd`, cheats-on universes only) and their own backup copy of their character (`me.json` beside the world copy; used only when the universe has no record of them and `_implausible` finds nothing wrong). Both PCs apply them on the same frame.

## Bug reports and replays

Every fight played on screen is recorded: the battle, the player's LV, the random seed
and the keys held on every game frame (mouse clicks are recorded as the keys they press).
While recording, the game's clock (`current_time`, `get_timer`) counts game frames
instead of real time. The fight is then fully deterministic and replays exactly.

F12 (in battle, or on the result screen afterwards) saves
`%APPDATA%\UltimateBattleEngine\reports\<date-time>\` with three files:
- `replay.json`: the recording, plus a fingerprint of the state at that moment (frame,
  HP, turn, object count, position sums, room);
- `screenshot.png`;
- `summary.txt`: what was going on, with room to describe the bug.

```
godot --path godot -- --playback "...\replay.json"
```

plays it back on screen. Esc leaves; when the recording runs out you take over the
controls. With `--headless` (or `--fast`) it runs as fast as possible, checks the
fingerprint at the report's frame, prints `PLAYBACK CHECK ... MATCH` or `DIFF` and exits
0 or 1. Any reported bug can be kept as a test this way. `--reportat F DIR` saves a
report at frame F, for tests. The format is in `godot/fight_replay.gd`.

## Testing

`scripts/check.ps1` is the quick regression check (about 45 s, never starts the real
game). It runs:
- the four frame-by-frame traces kept in `tests/`;
- the collision probe;
- a bug-report replay;
- the mod manifest fixtures;
- the Ruins walkthrough (`tests/walkthrough_ruins.txt`), from the first room to Snowdin's
  first room, checked to end in `room_tundra1` with plot 30 and a written `file0`;
- the overworld stress script (`tests/stress_ruins.txt`).
- the debug menu's self-test (`--debugtest`, `--debugtest2`).

`run-tests.ps1` also loads all 35 Ruins rooms one by one and fails on any missing
function or script warning.

`-Full` adds every saved real-game trace in `logs/trace` (51 battles, about 20 minutes).
`scripts/install-hooks.ps1` makes Git run the quick check before every commit
(`-Remove` takes it out again).

```
godot --headless --path godot -- --lv 20 --sweep 0 47
```

plays every battle back to back with scripted input (confirm through text, FIGHT every
turn, dodge left/right, jump and confirm during attacks, confirm on the game-over screen)
and prints the result, turns, HP, time, missing functions and unset variables.
`--frames N` sets the cap, `--dump` lists live objects of unfinished battles, `--prof`
prints where time went, `--heart` traces the SOUL, `--interp` runs the interpreter
instead of the translated code, `--warm` compiles everything up front. Sweeps seed the
random number generator per battle, so the interpreter and the translated code can be
compared run for run. `--battle N --shots DIR` plays one
battle on screen and saves screenshots during attacks.

See `TEST_REPORT.md` for the latest results.

## Tester builds and updates

`scripts\make-tester-zip.ps1` builds `UltimateBattleEngine-tester-<version>.zip` from
every file Git tracks or would track (so nothing `.gitignore` leaves out: no Undertale
data, tools or logs), under an `UltimateBattleEngine\` folder, with `MANIFEST.txt`
listing the files. It refuses to pack game or program files. Bump `VERSION` in
`godot/engine_info.gd` for each build sent out.

Testers update with `update.bat` (`scripts\update.ps1`): drag the zip onto it, or run
it bare to use the newest tester zip in the folder, its parent or Downloads. It checks
the zip is a tester build, refuses an older version, writes only the engine's own files
(never `source`, `godot\extracted`, `tools`, `logs`, `config\settings.json` or
`config\godot_path.txt`), copies every file it replaces to `backup\<old version>_<date>\`,
and removes files the old `MANIFEST.txt` listed that the new build no longer has.
`play.bat` re-runs setup by itself when the extracted data is missing or older than the
engine expects (`extract_version` in `engine.json`).
