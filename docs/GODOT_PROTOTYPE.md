# Godot battle-core prototype

A first test of rebuilding Undertale's battle system in Godot 4.7, using assets taken
at runtime from the player's own copy of the game. The question it answers: can a
rebuild match the original exactly, and can we prove it?

## Running it

```
powershell -ExecutionPolicy Bypass -File scripts\prepare-godot.ps1
"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path godot
```

`prepare-godot.ps1` extracts 11 sprites (with their collision masks), 5 fonts, 5 sound
effects and the battle music from `source\data.win` (the launcher's verified copy) into
`godot\extracted\`. That folder is not in Git and has a `.gdignore`, so Godot loads the
files at runtime instead of importing them.

Controls: arrows (or WASD after pressing F3; the choice is remembered), Z/Enter confirm,
X/Shift back, fast-forward text or move slowly, F2 smooth rendering on/off, F4
fullscreen, Esc quits.

## What is in it

| Part | Status |
|---|---|
| Battle screen | Background, dummy, buttons, name/LV/HP bar from the game's own sprites and fonts, laid out as the battle room and `scr_binfowrite` do |
| Box | Four walls moved exactly as `obj_uborder`, `obj_dborder`, `obj_lborder`, `obj_rborder` do (top wall sideways first, widths change 30 px per frame, side walls span top to bottom); drawn between logic steps when smooth |
| Text | Writer as text type 1: `fnt_main`, 16 px per letter, 32 px lines, one letter per frame, SND_TXT2 blip, wrapping, `&` `/` `^` and colour codes; X fast-forwards |
| Menus | FIGHT and ACT target list, two-column ACT list (Check, Talk), two-by-two ITEM list, MERCY (Spare in yellow once spareable, Flee); SOUL cursor positions from the original; X goes back |
| FIGHT | Attack bar at 11-13 px per frame; damage `(weapon + AT - DEF + random 0-2)`, x2.2 within 12 px of the centre, otherwise scaled by distance (`scr_attackcalc`, `obj_targetchoice`); slash scaled and timed like `obj_slice`; enemy shake, damage number and HP bar like the monster's hurt code and `obj_dmgwriter`; MISS when the bar runs off |
| Enemy turn | Box shrinks, the demo attack runs for 6 seconds, the box grows back and the next flavour line types once the left wall arrives |
| Endings | Killing (fade-out, an approximation of the dust effect), sparing, fleeing (always works with the Bandage, as in `scr_runaway`) and game over; Z starts a new battle |
| SOUL and bullets | Same rules as `obj_heart` and `blt_parent`, frame-exact (verified below) |

The dummy's name, stats and all its text are the prototype's own, not the game's.

Not in it yet: enemy speech bubbles, the real dust and spare effects, EXP and levelling,
other SOUL modes, the game-over animation, any original enemy. The menus, attack bar and
damage were built from the original code but have not been compared frame by frame with
the real game the way the SOUL and bullets have.
## How it was checked against the real game

1. `UltimateBattleEngine.exe --selftest record` and `--selftest record2` play scripted
   fights in the real (patched) game and log every frame: keys held, the SOUL's position,
   HP, the invincibility counter, wall positions, and every bullet's position and hitbox.
   Spawns are logged at full precision.
   - `record`: a key path through all directions, diagonals, the slow key, all four
     walls and a corner, with two stationary bullets; the second is crossed exactly as
     invincibility runs out.
   - `record2`: 22 moving bullets: horizontal at 2.5 px/frame, a pixel-precise bullet
     at 3.3, aimed shots, a diagonal at 325 degrees and a double-size bullet, while the
     SOUL wanders through them.
   The logs are kept as `tests\record_reference.txt` and `tests\record2_reference.txt`
   (numbers only, no game data).
2. `godot --headless --path godot --script res://replay.gd -- <log>` feeds the same keys
   and spawns through `godot\ut_sim.gd` and compares every frame.

Result: **both recordings match on every frame**: SOUL position, HP, invincibility
counter, bullet count and every bullet's position to 6 decimal places (244 frames each,
2 hits each). `tests\run-tests.ps1` runs both comparisons.

Found by measuring rather than reading the code:

- Invincibility after a hit is **30 frames** in this copy of the game, not the 20 that
  `SCR_GAMESTART` sets.
- Positions, speeds and directions are **single-precision floats** (a speed of 3.3 is
  stored as 3.2999999523). Without copying that, positions drift by about 0.0005 px after
  170 frames.
- **Hitbox edges are rounded separately, half to even**:
  `left = round(x + margin_left * scale)`, `right = round(x + (margin_right + 1) * scale) - 1`.
  A 1-pixel-wide hitbox at a .5 position is therefore 0 or 2 pixels wide depending on the
  position. This rule matched all 1,510 logged bullet hitboxes; before it, Godot's hits
  landed up to 2 frames late.

## What this does not prove yet

- Rotated bullets (spin, or turned to face their path): the game rotates hitboxes, and
  that was not recorded.
- Scaled bullets with pixel-precise masks (only a scaled rectangle-mask bullet was
  recorded).
- The order collisions run in when the SOUL touches a wall and a bullet in the same
  frame; the prototype assumes walls first.
- How the game feels at 60 fps rendering: smooth mode only changes drawing, but nobody
  has compared it side by side with the original.
- Everything not listed under "What is in it".