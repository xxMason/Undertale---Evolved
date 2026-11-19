# Multiplayer rework: architecture and rules

Agreed with the project owner on 2026-11-19. This replaces the 0.4.x co-op design (one real
player plus a "partner" drawn beside them, lockstep netcode, leader swapping). The goal is an
Undertale that is multiplayer by nature, for up to 4 players, built on Undertale's own code but
reworked wherever its one-player assumptions get in the way, and shaped so a drag-and-drop
editor and mods can use every part of it.

## What stays the same, and what changes

Kept from Undertale, loaded from the player's own install and never shipped:

- Sprites, sounds, music, tiles, fonts and rooms as the starting content.
- Attack patterns and enemy behaviour (bullets, boss fights). Attacks learn to target "a SOUL"
  rather than "the SOUL", nothing more.
- 30 fps game timing, the GameMaker random generator, Undertale's text codes (`\E`, `^1`, `/`...).
- Complex cutscenes stay as their original code, made player-aware, until someone rebuilds them
  as data.
- How the game *feels*: sprites, timing, boss fights. Solo play with no mods is still checked
  against the real game (scripts/check.ps1), because that is the best bug detector we have.

Not bound to the original: logic. Multiplayer, new items, menus, saving rules and so on are
free to differ from Undertale.

## The one rule: there is no "the player"

Every system works for *a* player. Every event says which player caused it ("on interact
(player)", "on enter trigger (player)"), and every system asks which player it is acting for.
A game with one player is simply a player list with one entry, not a separate mode. Mods built
on the engine's API are multiplayer-safe because they cannot express a one-player assumption.

## Three kinds of state

| Kind | Examples | Where it lives | Sent over the network |
|---|---|---|---|
| World | rooms and their objects, story flags (`plot`, most of `flag`), kill count and route, LV and EXP | the host | no (only its picture) |
| Player | position, HP, items, gold, weapon and armour, busy state (`interact`), open text box, menu, step counter, per-player pickups | the host, one copy per player | no (only its picture) |
| Screen | camera, what is drawn, HUD, chat window, prompts | each PC | never |

### Player overlays

Undertale keeps player state in globals (`global.interact`, `global.hp`, `global.item`,
`global.msg`...). The engine keeps a table of which globals are per-player (data, editable,
mods can add to it). When code runs on behalf of a player, that player's copies are swapped in;
the 0.4 co-op battle code already does a small version of this for the second SOUL
(`gml_vm.gd` scope_enter / scope_exit).

### Ownership

Every instance can have an owner (a player). Rules:

1. A player's own character (`obj_mainchara`, their SOUL) is owned by them.
2. An instance created by code running for player P is owned by P. So an NPC's text box and
   writer, created after P talked to it, belong to P.
3. An object a player touches or interacts with runs that event for that player, and becomes
   theirs until its scene ends (the 0.4 code did this by swapping the real character around).
4. World objects (doors, platforms, a cutscene before it starts) have no owner.

Code running for P sees P's overlays, and `obj_mainchara` / `obj_heart` mean P's own instance.
Code with no owner sees the world view: `obj_mainchara` means the nearest player where that
makes sense (a trigger), and a player counts as busy only in a Gather or Room scene.

## Network: the host runs the game

Lockstep (every PC runs the whole game and they swap key presses) is replaced:

- Only the host runs the game, every room that has a player in it.
- Each other PC sends its key presses and receives the *picture* of its own screen: draw
  commands (sprite, frame, position, colour, text) and sound events. Tiles and other room
  furniture are sent once per room. Each PC still loads the sprites and sounds from its own
  Undertale install, so nothing from Undertale goes over the network.
- Your own movement is predicted on your PC and shows at once, corrected by the host if it
  differs, so walking never waits on the network. The same goes for your SOUL in battle: your
  PC moves it and reports where it is, and the host decides hits from that (co-op between
  friends, so trusting your own SOUL is fine).
- One slow PC no longer holds everyone back, and a mismatch can no longer split the games apart,
  because there is only one real game.
- Private sessions only: join by address with a password. Everyone needs the same mods (the
  host checks its mod list against yours; later it may send engine-format mods, never files
  holding Undertale's own assets).
- Friends can join and leave at any time; their character waits in the universe. If the host
  leaves, the session ends for everyone after a save.
- Host controls: kick, change the password, the existing cheat rules.
- Internet play (port forwarding, Tailscale or Radmin work already; a relay server later) waits
  until LAN play is right.

Tester builds become exported apps, which run the game code much faster than the Godot editor.

## Rooms

Players can be in different rooms. Each room with at least one player in it is a running
*world* on the host; a room with nobody in it is not running (as in GameMaker, an ordinary room
starts fresh when someone enters). Story flags and other world globals are shared by all of
them, so opening a door in the Ruins opens it for everyone. Movement is fully free.

## Encounters and battles

- Every player has their own step counter, as in Undertale, and gets their own encounters.
- Players in the same room and close by are pulled into the battle. Anyone further away or in
  another room is not. A player in a menu or a text box is skipped; for a boss, the others are
  told "<name> is busy".
- A player not in the battle sees "<name> is in a battle" above that player. Pressing Enter near
  them asks "Join Battle?" (Yes / No); a Yes joins at the start of the next turn. Several battles
  can run at once.
- All of this is a setting mods can change: the pull-in range, joining mid-battle, solo-only
  fights.
- Up to 4 SOULs, turns in order, revive under MERCY (from 0.4). Other players' SOULs are drawn at
  25% opacity so your own stands out; SOUL colours keep their Undertale meaning.
- Attacks that would be trivial with several players get per-player versions. Example: Undyne's
  green-SOUL spears come at each player separately, so the party cannot all block one direction.
- Optional "Co-op Difficulty Scaling" (more enemy HP per player). Off by default.
- A player downed in a battle they are in alone respawns at the universe's last save point on
  full HP with their items as they were, and everyone else is told they died. No other penalty.
  In a shared battle the existing revive rules apply. Game over only when every player is down.
- EXP and LV are shared (the kill count is shared too).

## Story scenes

Each scene has a setting (chosen by us for Undertale's scenes, by modders for theirs):

| Setting | Used for | Behaviour |
|---|---|---|
| Gather | major scenes and bosses (Toriel, Papyrus, Undyne...) | The trigger waits ("waiting for 1 more player"). Players elsewhere get "Teleport to Story Event?" (Yes / No). Yes brings them there; No is reported to whoever triggered it. A busy player (menu, battle, text) gets the prompt when they are free. The scene plays for the whole party. |
| Room | smaller scenes | Only players in that room take part; others get a short note. |
| Personal | signs, simple NPC talks, shops | Only the player who triggered it sees it; everyone else keeps playing. |

- Choices (spare or fight, and so on) are made by whoever is in the choice box. Friends coordinate
  in person; sessions are private.
- Characters who follow you (Toriel in the Ruins) follow whoever started the scene. This needs a
  trial in the Ruins.

## Items, menus and saves

- Each player has their own menu, drawn by the engine in Undertale's style, with their own items,
  gold and stats. Several can be open at once, and the world keeps running. Using an item still
  runs Undertale's original item code for that player.
- Item pickups in the world are per player: everyone gets their own copy. Limited things that are
  meant to be shared stay shared.
- Press Enter facing another player for the player menu:
  - **Give item**: hand them one of your items.
  - **Give gold**.
  - **Heal**: use one of your food items on them.
  - **Check**: their LV, HP, AT, DF, weapon and armour, like Undertale's STAT page.
- Saving: anyone can save at a save point, and it saves the whole universe for everyone, with a
  text box telling everyone who saved. Saving is refused while any player is in a menu or a
  battle. Each player's position is saved; on load everyone returns together at that save point.

## Chat

T opens a chat window in Undertale's style. Each player's lines are marked with a SOUL in their
colour: host red, then blue, green and yellow for players 2 to 4.

## Look and feel

Every new window, prompt and notification uses Undertale's style: its fonts, black boxes with
white borders, the SOUL as the cursor, Undertale's sounds for moving and confirming. "Join
Battle?" and "Teleport to Story Event?" look like Undertale's own yes/no choices.

## Stages

Each stage ends with every existing check passing (solo still matches the real game) plus its
own tests. Every stage is measured for frame time (worst frame, not just the average), hitches
and skipped frames, and checked by screenshots of every player's screen.

1. **Worlds.** Split the GML machine's per-room state (instances, room, views, tiles,
   backgrounds, audio routing) into a World object, with code and shared globals kept once.
   One world behaves exactly as today.
2. **Players and ownership.** A player list (1-4), several `obj_mainchara` in one world, the
   per-player overlay table, ownership through creation and interaction. Leader swapping is
   removed. Tested locally with several bot-driven players in one process, no network.
3. **Screens.** Each world's drawing becomes a list of draw commands; each player's screen is
   built from their camera plus their own private content; on-screen things are pinned to the
   screen. Other players' SOULs at 25%. Sound routed to the players who should hear it.
4. **Network.** Host runs the game, clients send keys and draw what they receive, own movement
   and SOUL predicted. Replaces lockstep. Join with password, version and mod check, join and
   leave at any time. Lag measured on LAN.
5. **Many rooms.** One world per occupied room, players moving between worlds through doors,
   shared globals.
6. **Rules.** Encounters per player and pulling in, Join Battle, solo death and respawn, Gather /
   Room / Personal scenes with the teleport prompt and its queue, saving rules, per-player
   pickups.
7. **Engine menus.** Per-player menu with Give, the player menu (Enter on a player), chat on T,
   notifications. All in Undertale's style.
8. **Battles.** Up to 4 SOULs, per-player attack versions (Undyne's spears), Co-op Difficulty
   Scaling, the Toriel follower trial.
9. **The Ruins with 1-4 players**, start to finish, then the rest of the game area by area. The
   editor's building blocks (doors, signs, NPCs, save points, triggers, shops) grow out of the
   objects these stages have to understand anyway.

## Progress

### Stage 1: worlds (done 2026-11-19)

`godot/gml/gml_world.gd`. The GML machine keeps the active world's state in its own fields
(so the hot paths are unchanged), and `World.use()` switches between worlds by swapping
those fields: instances, ids, room and its size, views, tiles, backgrounds, drawing state,
random generator, keys, sounds playing. Each world numbers its instances, sounds and tiles
from its own base (world k from 100001 + k x 10^9), so a player can later move between worlds
without id clashes. Globals, parked persistent rooms and open files are shared; a test world
can take private copies (`World.private_copy`).

Test: `--worldtest ROOM [--worldat F] [--worldset k=v,...]` runs ROOM as a second world beside
the game, stepped and drawn every frame (tapping Z, so a battle there plays on), and
`--worldhash N` prints the game world's checksum every N frames. The checksums must equal a run
without the second world. Checked over 8000 frames of the Ruins walkthrough with a battle that
plays to a game over, an overworld room, and the first room; scripts/check.ps1 runs a short one.

### Stage 2: players and ownership (done 2026-11-19)

`godot/mp_players.gd`, hooks in `gml_vm.gd` (owners_on, ctx_owner, owner_switch, claimed,
private_objs, multi_objs). What works:

- Up to 4 players, each a real `obj_mainchara` with their own keys. The room's own one is
  player 1's; the others are created beside it in their own context.
- `PER_PLAYER` globals swapped per event: input (`control_*` and obj_time's arrow fields),
  facing, interact, phasing, entrance, encounter, currentroom, menu state, HP and stats, gold,
  items, phone, and the text box globals (`msg`, `msc`, `typer`, `choice`...). Each player's
  camera (view 0) is kept the same way.
- Instances created in a player's context are theirs. An object becomes a player's while they
  are busy with it: talking to it (`scr_interact`), or any world object whose event makes them
  busy (a hole they fall into, a trigger). It is released once its talk is over, the player is
  free and its alarms are done.
- Text boxes and faces are private: in a player's context only their own (and the world's)
  exist; the world sees its own and player 1's, as in the one-player game.
- The overworld menu (`obj_overworldcontroller`) runs once per player with their own copy of
  its variables, so every player can have their own menu open at once, with their own items.
- With one player nothing is swapped and the game is the original.

Tests: `--players N --pfeed "2=SPEC;3=SPEC"` (SPEC: `follow`, `idle`, or presses like `--press`),
`--mplog N` (each player's state and the worst and average frame time), `--mpcheck NAME`
(mp_tests.gd: `sign`, `menu`, `hole`, run by scripts/check.ps1), `--hitchlog` (frames over
40 ms, with the test bot's own time shown separately).

Measured (headless, Ruins walkthrough): average frame 2-3 ms solo, 3-4.5 ms with 4 players
following player 1; same rooms reached on the same frames as solo. The large spikes seen in
test runs (0.8 s) are the test bot's path finding, not the game; the game's own worst is about
65 ms when a battle starts (first run of its code), with 1 or 4 players.

Known gaps, by the stage that closes them:

- A door used by any player takes everyone to the next room; battles take everyone out of the
  overworld (stages 5, 6, 8).
- World objects see player 1 as "the player": random encounters count player 1's steps, story
  triggers watch player 1 (stage 6).
- Saving and loading still store one player (stage 6).

### Stage 3: screens (done 2026-11-19)

- Each player's screen is drawn from their own camera. The recorder marks every instance's
  drawing with whose it is (`@owner [id, player, anchor]`); a player's screen leaves out other
  players' text boxes, faces and menus (`gml_recorder.gd` replay with `who`).
- Drawing placed against the view (faders, the menu, text boxes: any object whose Draw reads
  `view_xview`/`view_yview`) is moved to each player's own view, so a room fade covers every
  screen however far apart the cameras are.
- The room's background colour covers the whole room when several players play.
- Sounds played for one player (short sounds in their context: their text's voice, their menu)
  are theirs; music and longer sounds are everyone's. Other players' sounds are silent on the
  host (a muted bus) and sent to their PC.
- Tests: `--viewas K` shows player K's screen; the `sign` check counts what each screen draws
  (the text box only on player 2's, the same everywhere once it closes).

Left for later areas: the parallax background objects (`obj_backgrounder_*`: Snowdin town and
its bridges, Waterfall's dock, the Core, the last corridor) still follow one camera. None are
in the Ruins.

### Stage 4: network (done 2026-11-19)

`godot/mp_net.gd`. The host runs the game; a friend's PC sends its keys and draws what it gets.

- Frames: the recorder's commands for that player's screen, packed (types and floats, textures
  as numbers: sprite and frame, background, font), about 13 KB a frame before compression and
  1 to 1.5 KB after (ENet's zstd): 30 to 45 KB/s per friend.
- Keys: every frame's keys, sent with the last three; the host queues them so a quick tap is
  never lost, and merges identical waiting frames when more than two wait, so a backlog never
  delays later keys. When the friend's keys are late the host carries on with what they held
  and skips those frames when they arrive, so a held key lasts as long as it was held.
- Your own walking is predicted: keys the host hasn't used yet move your character and camera at
  once (3 pixels a frame); a direction the host shows blocked (a wall) isn't predicted until
  it's let go. Measured on one PC: the host uses a friend's keys 2 frames after they're
  pressed; at a wall the picture moves back by 3 pixels once.
- Joining and leaving at any time: a friend who comes back under the same name gets their slot,
  stats and items back. Version, mods and password are checked on joining. "Greg joined." /
  "Greg left." notices on every screen.
- Code compiles in the background while playing, so the first text box no longer stops the game
  for 150 ms (it did in solo too).
- Tests: `--mphost PORT [--mppw P]`, `--mpjoin IP:PORT [--mpname N] [--mppw P]`, `--netlog`
  (prediction per frame), `--mplog N` (bytes per frame, round trip, key queue). The check suite
  runs a friend joining, walking, reading a sign and leaving (`--mpcheck net`).
- **Host Game / Join on the title screen** use this network (the 0.4 co-op is left only for
  its old tests). Hosting asks for an optional password. The host announces its game on the
  local network every second (UDP 7789: host, universe, LV, room, players, password needed),
  and the Join page lists those games ("2 of 4 players", "Password needed", "Full", "Another
  version"). Join by IP address is there for other networks; it always asks for a password
  (empty if none). A wrong password gets "Wrong password." and the Join page back.
- **Keys the host ignores from friends:** Esc and F1 to F12, so a friend can't end the game
  or change the host's window. `mp_net.gd kick(i)` and `set_password(pw)` are ready for the
  host's menu (stage 7).

### Pause menu (2026-11-19)

`godot/pause_menu.gd`. Esc no longer reaches the game (Undertale's held Esc quits): it opens
a menu with Resume, Leave (back to the title screen), Exit to desktop and Settings (movement
keys, smooth motion, window size, scaling, fullscreen). Leave and Exit ask first when that
costs something: the host is told "Everyone's game ends with yours." with friends in, and
anyone not on a friend's PC is told progress since the last save is lost. A friend leaving is
not asked: their things stay in the host's game.

Alone, the game stops while the menu is open. In co-op every PC has its own menu and tells
the host when it opens or closes (`"pause"` message); the game only stops when every player
has it open, and the menu says "The game goes on for the others." until then. A paused player
gives the game no keys. Tests: `--pausetest` (with `--game`, a window) and `--mpcheck pause`
with a friend's `--mppause A:B`.

Note for measuring: Windows slows down windowless test runs after about 15 seconds (every phase
2.5x slower). Measure frame times with a window.

### Stage 5: many rooms (done 2026-11-19)

`godot/mp_rooms.gd`. Every room with a player in it is a running world; each has a lead (the
player whose camera and values the room's own objects follow) and members.

- A door used by one player while others stay sends only that player: their character and the
  door's fade leave the room, the door is ready again for the others, and they join the world
  already running the room they go to, or a new one (with copies of the persistent things
  everyone shares, like the overworld controller, and its own random numbers and sound).
- When everyone in a world leaves together, the world changes room as in the one-player game,
  or joins the world already running that room. A world nobody is in ends (a persistent room is
  parked as usual).
- Every global is per player except a shared list (story flags, save bookkeeping, settings).
  The host's PC plays the sounds of its own player's world; the others go to their players.
- Found and fixed on the way: a new world's character was made twice (the room made one for the
  player and binding made a second), so the hole in room_ruins8 kept catching the spare one and
  the player fell forever.
- Measured: 2 players in different rooms average 3.2 ms a frame on the host (headless, 5 ms
  worst after warm-up); the frame where one player changes room took 8 ms.
- Tests: `--mpcheck rooms` (player 2 goes into room_ruins8 alone and falls through its hole,
  player 1 follows into player 2's world), `--roomlog`, `--recdump F` (the host's draw list).
- Not yet: the parallax backgrounds of later areas (`obj_backgrounder_*`) follow one camera.

### Stage 6: rules (in progress 2026-11-19)

- **Encounters per player.** Each room's encounter object runs once per player with their own
  step count, so everyone gets their own random battles, even in the same room on the same
  frame. A battle room is never shared by walking in: each battle is its own world.
- **A player's code doesn't see another player's things** (their battle starting, their fade,
  the sign they are reading): each acts as if alone. A room's own objects are nobody's.
- **Back from a battle** in a room that kept running for the others, a player is where they were.
- **Solo death.** A player downed alone while others play on sees Undertale's game over screen,
  then comes back in the room of the last save, where loading puts the player, on full HP with
  their items as they were. Everyone else is told "Greg died." The story isn't loaded back.
  Game over is only for a player alone in the game (or, with shared battles, everyone down).
- **Saving.** Anyone can save; file0 keeps the host's own things whoever saved, players.json
  beside it everyone's (by name, so a friend who joins again later gets theirs back), and
  everyone is told who saved. The save menu doesn't open while another player is in a menu or
  a battle ("Can't save now: Greg is in a menu."). An LV gained by anyone gives everyone that
  LV's HP, AT and DF.
- **Gather scenes** (`godot/mp_scenes.gd`): Toriel's and Flowey's triggers. Walking into one
  while others are in other rooms holds the trigger and shows "Waiting for 1 more player...
  (X: go on)"; the others get "Teleport to Story Event?" (Yes / No, `godot/mp_ui.gd`), once they
  are free if they are busy. Yes brings them beside the player who found it; No is reported to
  that player. Then the scene plays, and what that player reads shows on every screen in the
  room (with its sounds). Not yet: scenes that start as a room loads (Toriel at the training
  dummy, in her house) only play for whoever is in the room; players brought to a scene stand
  on the spot of the one who found it.
- Tests: `--mpcheck battles / save / death / gather`.

### Stage 7: player menu, chat, host controls (done 2026-11-19)

- **Player menu** (`godot/mp_pmenu.gd`). Enter facing another player (within 34 pixels in
  front of you, walking about freely) opens it, drawn like Undertale's overworld menu with
  their name on top. The host runs it like the other prompts, so a friend's opens on the
  host and reaches their PC with each frame.
  - **Give item**: your items listed; the item leaves your inventory with Undertale's
    `scr_itemshift` and goes into their first free slot ("Greg can't carry any more." when
    they have 8).
  - **Give gold**: an amount, LEFT/RIGHT by 1 and UP/DOWN by 10.
  - **Heal**: your food (items whose `scr_itemuseb` case calls `scr_recoitem`; the others
    are greyed out). The item's own use code runs as the player being healed, so it heals
    what it heals in the game (with their weapon: a Burnt Pan adds 4).
  - **Check**: their STAT page in Undertale's own words (`stat_menu_*` text).
  - Both players are told what happened. Notices move below the menu while it's open.
- **Chat** (`godot/chat.gd`). T opens it in a game with friends. Each PC types on its own
  keyboard and gives the game no keys meanwhile; a friend's line goes to the host, which
  sends it to everyone (`"chat"`). Lines show bottom left with a SOUL in the player's colour
  for 8 seconds, and the last 6 while the chat is open. 60 characters a line.
- **Host controls**: the host's pause menu has Players: each friend (Remove asks first; a
  removed name can't come back this session, even with the password) and the password
  friends join with (empty: none).
- Tests: `--mpcheck pmenu` (local), `--mpchat TEXT` on host and friend, `--mpcheck kick`.

### Stage 8: battles (in progress 2026-11-19)

`godot/mp_battles.gd`.

- **Pulling in.** A player's encounter takes the players in the same room within 160 pixels
  who are free (no menu, text box or prompt) into the same battle. A battle with everyone in
  the world becomes that world; otherwise the battle is a new world with them in it.
- **One battle, several players.** While a battle has more than one player, its state (menu,
  turn, enemies, text) is everyone's; only HP, stats, items, gold, invincibility and input stay
  each player's (`mp_players.gd PERSONAL`). Every player has their own `obj_heart`, copied from
  the room's (its Create would reset the menu), moved by their own keys. A bullet's collision
  runs in the context of the SOUL it touches, so Undertale's own damage code takes that
  player's HP. Bullets aiming at `obj_heart` each pick one SOUL by their id, so attacks spread
  over the party; the battle's own bookkeeping means the SOUL of the player whose turn it is.
- **Screens.** Your SOUL as Undertale draws it; the others' at 25% with their name over them
  (`gml_recorder.gd` fade, also over the network). The HP bar shows the player whose turn it is,
  by name. The others' HP is listed top-right, with "Greg's turn" on the screens of those
  waiting.
- **Turns in order.** Each new menu turn the next player up becomes the world's lead: the menu
  and the text answer to their keys. The world steps with its lead's keys (`engine.gd`).
- **Down and Revive.** A player at 0 HP is down: their SOUL goes and everyone is told. If it was
  their turn, the next player takes it. After 3 turns down, MERCY gets "Revive Greg" (the
  turn; back at 30% HP, a moment of invincibility). The downed get up on 1 HP after the battle.
  Everyone down is Undertale's game over (with others playing elsewhere: everyone in it comes
  back at the save, as for a solo death).
- **Join Battle.** Players who weren't pulled in see "Kyle is in a battle" where Kyle stood;
  Enter there asks "Join Battle?" (Yes / No), and a Yes joins at the start of the next turn.
  After the battle a player who joined from elsewhere goes back to where they joined from.
- **Rewards.** EXP is shared; the gold the battle gives goes to each player in it.
- **Co-op Difficulty Scaling** (setting `multiplayer/difficulty_scaling`, off by default;
  `--mpscale` in tests): enemy HP +50% for each player past the first, raised again as players
  join.
- A persistent room everyone had left gets a character again where it places its player.
- Not yet: Undyne's per-player spears (Waterfall); ITEM on a teammate ("Who?" from 0.4); a turn
  timer for a player who doesn't act; a toggle for scaling in the menus.
- Tests: `--mpcheck party / revive / join`.
