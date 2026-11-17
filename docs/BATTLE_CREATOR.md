# Battle Creator

A custom boss is one text file that the game reads when the fight starts. You can build
one two ways: in the game, from **CUSTOM BATTLES**, or by editing the file by hand.

## In the game

**CUSTOM BATTLES** lists your bosses. `Z` fights the selected one, `C` edits it, and
**+ NEW BOSS** makes one.

### Boss editor (keyboard)

List pages for the boss's name, stats, picture, music, box size, dialogue, ACTs and
attacks. Left/Right changes a value, `Z` opens a page or starts typing in a text field,
`Enter` finishes typing, `X` goes back. **TEST FIGHT** plays the whole boss and returns
to the editor. Leaving the first page saves.

Attacks come in two kinds:

- **+ NEW ATTACK (LIVE BUILD)** opens the live-build screen below.
- **+ NEW SIMPLE ATTACK** is one of four ready-made patterns (rain, aimed, ring, wall)
  with a few numbers. Its **TEST LIVE** drops you into the box with the attack looping
  while the number keys change it.

### Live build (mouse)

A larger screen (1280x960; the window grows while it is open) with:

- **Stage**: the battle screen with your boss and the box. Each placed object shows a
  numbered diamond where it starts and a line for its direction.
- **+ ADD**: the game's bullet sprites. Click one, then click in the stage to place it
  at the current time. Click the same one again to stop placing.
- **OBJECTS**: everything placed, as a list.
- **EDIT**: the selected object's START time, X, Y, ANGLE, AIM AT YOU, SPEED, REPEAT,
  EVERY, DAMAGE, SIZE, SPIN and FACE ITS PATH, plus COPY and DELETE.
- **Timeline**: one row per object with a tick for each time it fires. Click or drag to
  move the playhead; click a row to select that object.
- **Top bar**: switch between this boss's live-build attacks, add one, and set BOX WIDTH,
  BOX HEIGHT and HOW LONG.
- **HITBOXES / PAUSE / SLOW**, **FROM START**, **UNDO / REDO** (40 steps).
- **TEST IT** plays the attack in a real fight, looping, where you cannot die;
  `Backspace` returns. **DONE** saves and goes back to the boss editor.

In the stage, drag a diamond to move an object and drag the square handle of the
selected object to turn it. Arrow keys nudge the selected object (Shift for 10 pixels),
`Delete` removes it, `Space` plays or pauses.

The preview draws where bullets will be from the same numbers the fight uses: straight
flight from the start point, removed when they leave the box through a wall they are
moving towards. It keeps the SOUL in the middle, so AIM AT YOU aims there; in a real
fight it aims at wherever you are.

## Where the files live

- Your bosses: `%LOCALAPPDATA%\UltimateBattleEngine\custom\` (one `.ini` per boss, plus
  any `.png` it uses).
- The example, `bosses\sentinel.ini` in the project, is copied there when the launcher
  starts. Your own edits in the `custom` folder are kept unless the project copy is newer.
- The launcher lists every `.ini` in that folder in the CUSTOM BATTLES menu.

To make a new boss, copy `sentinel.ini` to a new name in the `custom` folder, change it,
and restart Ultimate Battle Engine.

## File format

Values go in quotes. In any text, `&` starts a new line.

### `[Boss]`

| Key | Meaning | Default |
|---|---|---|
| `Name` | Name shown in the fight and the menu | Custom Boss |
| `HP`, `ATK`, `DEF` | Stats. ATK is the default bullet damage | 100, 5, 0 |
| `EXP`, `Gold` | Rewards for winning by fighting | 0, 0 |
| `SpriteFile` | A PNG next to the boss file | none |
| `Sprite` | Used when there is no PNG: the name of one of the game's own sprites | `spr_dummybattle` |
| `Scale` | Size multiplier for the sprite (0.25 to 8) | 1 |
| `Music` | One of the game's tracks, without `mus_` or `.ogg` (for example `battle1`, `boss1`, `dummybattle`) | `battle1` |
| `MusicVolume`, `MusicPitch` | 0 to 1, and 0.25 to 3 | 0.6, 1 |
| `Intro` | Text when the fight starts | `* <Name> appears.` |
| `Check` | Text for the Check ACT | name and stats |
| `Flavor1` to `Flavor6` | Lines shown in the box at the start of your turn (picked at random) | a generic line |
| `Speech1` to `Speech6` | Speech-bubble lines before each attack (picked at random). Leave out for a silent boss | none |
| `Box` | Size of the bullet box: one of the game's presets 0 to 7 (3 is the usual small box, 0 the wide one) | 3 |
| `AttackOrder` | 0 = random attack each turn, 1 = in order | 0 |
| `SpareAfterActs` | Mercy points needed before the boss can be spared. 0 = cannot be spared this way | 0 |
| `SpareWhenWeak` | 1 = can also be spared at low HP, like ordinary monsters | 0 |

### `[Act1]` to `[Act5]`

Check is always present. Each section adds one more ACT.

| Key | Meaning |
|---|---|
| `Name` | Up to 12 characters |
| `Response` | Text shown when you use it |
| `Mercy` | Mercy points it gives (counted towards `SpareAfterActs`) |

### `[Attack1]` to `[Attack8]`

| Key | Meaning | Default |
|---|---|---|
| `Pattern` | `rain`, `aimed`, `ring` or `wall` (below) | required |
| `Count` | Bullets per wave (for `wall`: size of the gap, in bullets) | 1 |
| `Speed` | Bullet speed, 0.5 to 12 | 3 |
| `Interval` | Frames between waves (30 frames = 1 second) | 20 |
| `Duration` | Length of the attack in frames | 150 |
| `Damage` | Damage per hit | the boss's ATK |
| `Bullet` | One of the game's bullet sprites, for example `spr_bulletmd`, `spr_bulletsm`, `spr_firebullet` | `spr_bulletmd` |

Patterns:

- **rain**: bullets fall from above the box.
- **aimed**: bullets start outside the box and fly at where your SOUL is.
- **ring**: a circle of bullets closes in on the middle of the box.
- **wall**: a wall crosses the box with a gap to slip through; walls alternate sides.

### Timeline attacks

An attack with `Pattern="timeline"` is what the live-build screen saves:

| Key | Meaning |
|---|---|
| `Duration` | Length in frames (30 = 1 second) |
| `BoxW`, `BoxH` | Box size in pixels (0 = use the boss's `Box` preset) |
| `Objects` | Number of objects |
| `O1` to `O40` | One object each, as 13 comma-separated values |

Object values, in order: sprite name, start frame, x, y (pixels from the centre of the
box), angle (0 = right, 90 = up), speed, aim at the SOUL (0/1), repeat count, frames
between repeats, damage, size, spin (degrees per frame), face its direction (0/1).

Example: `O1="spr_bulletmd,0,-90,-40,0,3,0,4,15,3,1,0,0"` fires four bullets to the
right from the upper left of the box, half a second apart.
## How it works

- The boss is a real monster to the game: it inherits from the game's `obj_monsterparent`
  and its bullets from `blt_parent`, so targeting, the attack bar, damage numbers,
  collision, invincibility frames, death and sparing are all the original code.
- It works with Player Setup and Training Mode, including hitbox outlines.
- No original script is edited. The boss uses monster type and battlegroup 777, which the
  build checks are unused.

## Limits

- One boss per fight and one phase.
- Live-build objects fly in straight lines. The palette is the game's 72 bullet sprites;
  bones, blasters and other scripted attack objects are not available yet.
- The boss editor pages are keyboard-driven lists, not the sidebar-and-tabs layout.
- Comment lines (starting with ;) in a boss file must not contain double quotes, and
  should be followed by a blank line; otherwise the game skips the section after them.
- Attacks cannot change the SOUL's colour or movement rules.
- The hurt animation is a shake; there is no separate hurt or talking sprite.
- A boss PNG is loaded again each fight and not unloaded, so memory grows slightly with
  every custom fight in one session.
- A typo in a key name is ignored and the default is used; a sprite or music name the
  game does not have falls back to the default.
- Custom music files are not supported yet, only the game's own tracks.
