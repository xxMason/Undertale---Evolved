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

- Weapon, armour and inventory selection (fixed at Stick, Bandage, empty).
- HP override above the normal maximum.
- Only Froggit is enabled. Toriel is listed and disabled.
- Training Mode, Custom Battles, Statistics and Settings are shown greyed out.
- The ERROR state exists but nothing raises it.
- The fight list does not scroll; fine for two entries, not for the full roster.
