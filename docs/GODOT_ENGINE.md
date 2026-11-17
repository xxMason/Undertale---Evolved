# Godot battle engine (original battle code)

`godot/engine.tscn` (the project's main scene) runs Undertale's **own battle code** inside
Godot. Nothing about the fights is rewritten: every enemy, attack, SOUL mode, menu and
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
left out), arrows to move, Z to fight, C for Player Setup (LV 1-20, arrows or WASD; saved),
F2 smooth rendering, F3 WASD, F4 fullscreen, Esc leaves a battle or quits.

Mouse: everything in the fight select is clickable (tabs, rows, the Player Setup button,
LV arrows, the movement toggle); hovering a row selects it, the wheel scrolls, right-click
closes Player Setup. In battle, hovering FIGHT / ACT / ITEM / MERCY selects that button,
left-click is Z, right-click is X and the wheel is Up/Down, so every submenu works with
the mouse. The clicks are fed to the game's own menu code as key presses, so nothing about
the battle menus is reimplemented.

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
(inherited from parent objects), End Step, Draw (depth list), Draw GUI. Every event except
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
trace, `-RealTrace FILE` compares against a saved one. Traces are numbers only.
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

## Testing

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
