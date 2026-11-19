ULTIMATE BATTLE ENGINE - tester build
=====================================

Undertale's own battle code, running in Godot. Every monster and boss fight, checked frame
by frame against the real game. We're looking for anything that plays, looks, sounds or
feels different from real Undertale: hitboxes, timing, attack patterns, menus, text,
damage, sounds, anything.

This folder contains no Undertale files. Setup builds everything from YOUR copy.


WHAT YOU NEED
- Windows
- Undertale v1.08 on Steam (the current Steam version)
- Godot 4.7 (the standard build, not .NET)
- About 1 GB of free space (a copy of Undertale and the extracted game data)


SETUP (once)
Put this UltimateBattleEngine folder somewhere of its own, e.g. Desktop or Documents.
Do NOT put it inside the Undertale folder (setup refuses to run there).

Just double-click play.bat. The first time, it runs the setup by itself (you can also run
setup.bat on its own). It will:
  1. find Undertale in your Steam libraries and check it's v1.08;
  2. copy data.win and the music into the "source" folder here (about 200 MB; your
     install and your saves are only read, never changed);
  3. download UndertaleModTool's command-line tool from its GitHub release (about 60 MB,
     checked against its known fingerprint);
  4. extract the game's code, sprites, sounds and music, and translate the code for Godot.
This takes a few minutes, once; after that play.bat starts straight away. Nothing of
the game is downloaded from anywhere: it all comes from your own copy. When an update to
the engine needs the data extracted again, play.bat does that by itself too.

If it can't find Undertale or Godot, run it from a command prompt in this folder with the
paths:
  setup.bat -Undertale "D:\SteamLibrary\steamapps\common\Undertale" -Godot "C:\Godot\Godot_v4.7-stable_win64.exe"

Starting over: clean.bat deletes everything setup made in this folder (source, extracted
data, tools), including folders nested too deep for Explorer to delete. Then run setup.bat
again.

UPDATING TO A NEW VERSION
Drag the new UltimateBattleEngine-tester zip onto update.bat (or just double-click
update.bat: it picks the newest tester zip in this folder, the folder above it, or your
Downloads). It replaces only the engine's own files. Your setup data (no need to set up
again), settings, saves, bug reports and anything you made yourself are kept, and every
file it replaces is copied to the "backup" folder first. Then play.bat as usual.

First update from a version without update.bat: unzip the new version ON TOP of your old
folder (Extract All, pick the folder that holds your old UltimateBattleEngine folder) and
choose "Replace the files in the destination". From then on, use update.bat.

IF YOU RAN AN EARLIER VERSION INSIDE THE UNDERTALE FOLDER
The old setup copied the folder into itself over and over. Your Undertale files weren't
changed, only read, but the copies need removing:
  1. Close any setup or game windows still open (or restart the PC).
  2. Unzip this version to your Desktop or Documents (NOT the Undertale folder).
  3. Open your Undertale folder (Steam: right-click Undertale > Manage > Browse local
     files), drag the old UltimateBattleEngine folder there and drop it ONTO
     remove-old-copy.bat from this new version. Answer Y. If Windows asks for
     administrator rights, say Yes: folders under Program Files need them.
  4. Optional, for peace of mind: in Steam, right-click Undertale > Properties >
     Installed Files > Verify integrity of game files.
  5. Run setup.bat in the new folder.


PLAYING
Double-click play.bat. Keep the black console window open: it shows messages, and closing
it closes the game.

The first time, it asks your name (yours, not the fallen human's). Then the title screen,
UNDERTALE: Evolved:
  Start Game     play Undertale in one of your universes
  Host Game      the same, with friends on your network (see MULTIPLAYER below)
  Join           join a friend's game
  Battle Engine  the fight select from earlier versions (single battles, Battle Creator)
  Settings       your name, controls, window, smooth motion
  Quit
Arrows choose, Z / Enter confirm, X / Esc go back.

UNIVERSES
A universe is a world of its own, like a Minecraft world: its own save, its own story
(routes, resets, everything) and its own players. Make as many as you like; whatever
happens in one never touches another. Your save from an earlier version was moved into
a universe of its own. Name one when you make it, or it's called "<your name>'s Universe".
Cheats (the F5 debug menu) can be turned on when you make a universe or later, but never
off again. Delete asks twice and puts the universe in the Recycle Bin.

In the game the controls are Undertale's (arrows, Z, X, C). Esc opens the pause menu
(Resume, Leave, Exit to desktop, Settings).
  F2   smooth motion on/off      F3   WASD on/off        F4   fullscreen


MULTIPLAYER (up to 4 players)
One of you picks Host Game and a universe; the others pick Join, where games on your
network show up by themselves: click one to pick it, double-click (or Z) to join. Or type
the host's address with "Join by IP". Everyone needs the same version, the same game data
and the same mods, or Join says what's different. The host can set a password.

The host's PC runs the game; the others send their keys and get their screen back, so
everyone needs to be on this version (run update.bat).
  - Everyone moves freely, each on their own screen, and can be in different rooms. Story
    flags are shared: a door opened for one is open for all.
  - HP, items, gold and pickups (the Faded Ribbon, the Toy Knife) are each player's own;
    LV, EXP and the kill count are shared.
  - Encounters: everyone has their own. Players close by in the same room are pulled into
    the same battle. Others see "<name> is in a battle" where that player stood; Enter
    there asks "Join Battle?" and they join at the next turn.
  - Battles with friends: each has their own SOUL (the others' are faint), attacks spread
    over the party, and you take turns in the menu. Choosing an item asks "Who?", so you
    can feed a teammate. At 0 HP you're down; after 3 turns MERCY has "Revive <name>".
    Someone who does nothing for 20 seconds on their turn is passed over. Undyne's spears
    come at each of you, with your own shield.
  - Dying alone while the others play on: you're back at the last save on full HP, and
    everyone is told. Everyone down is a game over.
  - Story scenes (Toriel, Flowey) wait for everyone: the others are asked "Teleport to
    Story Event?". A No is passed on, and the one who found it can go on without them (X).
  - Enter facing another player opens the player menu: Give item, Give gold, Heal (with
    your food), Check (their stats).
  - T opens the chat. Esc opens the pause menu (Resume, Leave, Exit to desktop, Settings;
    the host also has Players: remove someone, change the password). The game only pauses
    when everyone has it open.
  - Anyone can save at a save point; it saves the universe and everyone's character. It
    waits while someone is in a menu or a battle. A friend's character waits in the
    universe for next time.
  - Settings has "Co-op scaling" (off by default): more enemy HP for each extra player.
  - F5 (cheats) and F10 (pause) are the host's. For a bug report, press F12 on the
    host's PC: the game runs there, so that's where the useful report is.
The game uses port 7790 (and 7789 to find games). If Join can't find or reach the host,
allow the game through Windows Firewall on the host's PC (Windows usually asks the first
time; choose "Private networks"). Not on the same network? Tailscale or Radmin VPN put
you on one: everyone installs it, joins the same network, then uses Join by IP with the
address it shows for the host.

Not done yet: story scenes past the Ruins aren't set up for several players, and the pie
in Toriel's house is one for everyone.


TESTING KEYS
  F9    debug overlay: hitboxes (red = your SOUL), HP, invincibility frames, battle state.
        Hover over something to see what it is.
  F10   pause                    F11   while paused: advance one frame
  F12   BUG REPORT  <-- the important one
  F5    debug menu: items, LV, story, warps, battles, cheats, game speed, quick saves,
        an object inspector. Space pauses while it is open. Anything you change there is
        written into your bug reports, and saves made afterwards get a ".debug" note.


REPORTING A BUG
The moment you see something wrong, press F12. You can also press it on the result screen
right after a fight ends.

It saves a folder in %APPDATA%\UltimateBattleEngine\reports\ (paste that into the Explorer
address bar) with:
  replay.json      an exact recording of the whole fight so far: every key, every frame
  screenshot.png
  summary.txt      write what went wrong, and what real Undertale does instead, here

Zip the folder and send it. The replay reproduces your fight exactly, frame for frame, so
the bug can be watched happening and checked again once it's fixed. A detailed
description of how it differs from the real game is the most useful part.

Good things to try: no-hit runs, frame-tight dodges, KARMA (Sans), spare and ACT routes,
items mid-fight, the Hard Mode Ruins monsters, dying and the game-over screen, high and
low LV.

KNOWN DIFFERENCES (no need to report)
- The fight select, setup screen and testing keys aren't part of Undertale.
- Some translucent effects can be one shade off, depending on your graphics card.
- Very thin 1-pixel lines (a few strings and shadows) can be one pixel off at an end.
- The game (G) is new: the Ruins are what to test. Past the Ruins is untested.
- F12 in the game (not in a battle) saves a screenshot and your save files, not a replay.


Your files: settings, bug reports and the game's saves (the "undertale" folder) live in
%APPDATA%\UltimateBattleEngine. Delete that "undertale" folder to start the game fresh.
Undertale's own saves (%LOCALAPPDATA%\UNDERTALE) are never touched.
