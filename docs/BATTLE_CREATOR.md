# Battle Creator, stage 1: custom boss files

A custom boss is one text file. The game reads it when the fight starts, so you can edit
the file, pick the boss again from **CUSTOM BATTLES**, and see the change. There is no
in-game editor yet (that is stage 2).

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

## How it works

- The boss is a real monster to the game: it inherits from the game's `obj_monsterparent`
  and its bullets from `blt_parent`, so targeting, the attack bar, damage numbers,
  collision, invincibility frames, death and sparing are all the original code.
- It works with Player Setup and Training Mode, including hitbox outlines.
- No original script is edited. The boss uses monster type and battlegroup 777, which the
  build checks are unused.

## Limits in stage 1

- One boss per fight, one phase, four attack patterns.
- Attacks cannot change the SOUL's colour or movement rules.
- The hurt animation is a shake; there is no separate hurt or talking sprite.
- A boss PNG is loaded again each fight and not unloaded, so memory grows slightly with
  every custom fight in one session.
- A typo in a key name is ignored and the default is used; a sprite or music name the
  game does not have falls back to the default.
- Custom music files are not supported yet, only the game's own tracks.
