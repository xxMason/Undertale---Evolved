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
  Host Game      the same, with a friend on your network (see CO-OP below)
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

In the game the controls are Undertale's (arrows, Z, X, C). Hold Esc to go back to the
title screen.
  F2   smooth motion on/off      F3   WASD on/off        F4   fullscreen


CO-OP (two players on the same network)
One of you picks Host Game and a universe; the other picks Join, where games on your
network show up by themselves (like Minecraft's LAN worlds): click one to pick it,
double-click (or Z) to join. Or type the host's address with "Join by IP". Both need the same version, the same
game data and the same mods, or Join says what's different.
  - You both walk around as the human, with your names above your heads. Each screen
    follows its own player, except while text, a menu or a cutscene is up: then both
    screens show the same view. Whoever talks to someone, checks something, opens their
    menu (C) or goes through a door first takes the lead for that.
  - HP, items and gold are each player's own; LV and EXP are shared. C opens your own
    menu with your own items; your friend's screen shows it too, marked "<name>'s menu". A friend joining for
    the first time starts at the host's LV with half the host's gold (the host keeps theirs).
  - Battles: both of you are in them, each with your own SOUL, and both of you dodge every
    attack, and attacks aim at either of you. You take turns choosing in the menu. Your HP is at the bottom as usual; your
    teammate's is in the top-left corner.
  - Items: choosing one asks "Who?", so you can feed your teammate.
  - At 0 HP you're down for the rest of the fight. After 3 turns, MERCY has
    "Revive <name>": it takes the turn and brings them back on 30% HP, safe from attacks
    for a moment. Anyone still down when the battle ends gets up on 1 HP. Both down is a
    game over; either of you can go on from there.
  - A save point heals you both. Saving saves the world and both characters together, so loading or resetting puts you
    both back to that save. The universe stays the host's; a friend's character is kept in
    it for next time. Several friends can play in one universe, two at a time.
  - Only the host can pause (F10) or change game speed. Cheats follow the universe: with
    them on, the host has the whole F5 menu and a friend's F5 changes their own HP, gold
    and items only.
  - Each friend's PC also keeps its own copy of their character. If the host's universe
    has none (say it was lost), that copy is used, as long as it looks possible.
  - If your friend leaves, the host carries on alone. If they come back before the host
    quits or loads, they're as they were when they left.
The game uses port 7777 (and 7778 to find games). If Join can't find or reach the host,
allow the game through Windows Firewall on the host's PC (Windows usually asks the first
time; choose "Private networks"). Not on the same network? Tailscale or Radmin VPN put
you on one: both install it, join the same network, then use Join by IP with the
address it shows for the host.


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
