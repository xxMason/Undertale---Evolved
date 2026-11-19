# Co-op battles: both players are in the same battle, each with their own SOUL.
#
# The game has one SOUL (obj_heart) and one set of player stats in globals. The player whose
# menu turn it is stays "the game's" player (the leader, see coop_partner.gd); the other
# player's SOUL is a second obj_heart. Whenever an event runs on that SOUL, or on something
# touching it (a bullet's collision event), the VM swaps that player's keys and stats in
# (gml_vm.gd: scoped / scope_enter / scope_exit), so Undertale's own movement and damage code
# runs for them unchanged.
#
# Turns alternate between the players. A player at 0 HP is down: their SOUL goes away and,
# if it was the leader, the other player takes over. After 3 turns down, MERCY gets
# "Revive <name>" (the whole turn; back at 30% HP). Down players get up on 1 HP when the
# battle ends. Both down is the game's own game over.
#
# Runs the same on both PCs from the frame's keys (lockstep), so it's all deterministic.
extends RefCounted

const GmlKeys = preload("res://gml/gml_keys.gd")
const REVIVE_TURNS := 3
const REVIVE_PART := 0.3
# Per-player battle state besides CoopPartner.OWN: invincibility frames and the game's
# control state (control_update), which obj_time works out from the leader's keys.
const REVIVE_SAFE := 90.0      # frames of invulnerability after a Revive
const CTL := ["invc", "control_state", "control_pressed", "control_new_state"]
const TIME := ["up", "down", "left", "right"]

var eng
var vm
var partner                  # coop_partner.gd
var active := false
var heart = null             # the other player's SOUL (Inst)
var pkeys                    # the other player's keys, as the game reads them
var pctl := {}               # the other player's CTL / TIME values
var down := {"host": false, "client": false}
var down_turns := {"host": 0, "client": 0}
var start_leader := "host"
var last_turn := -1.0
var revive_sel := false      # the MERCY cursor is on "Revive"
var who := -1                # ITEM "Who?" choice: -1 closed, 0 yourself, 1 your teammate
var heal_mate := false       # the item now being used heals the teammate
var _hp0 := 0.0
var _saved := {}
var leader_hp = null         # while drawing on the other player's PC: the leader's real HP
var _shots := {}
var _sel_frames := 0


func setup(p) -> void:
	partner = p
	eng = p.eng
	vm = p.vm
	pkeys = GmlKeys.new()
	_reset_ctl()


func _reset_ctl() -> void:
	pctl = {"invc": 0.0, "control_state": [[0.0, 0.0, 0.0]], "control_pressed": [[0.0, 0.0, 0.0]], "control_new_state": [[0.0, 0.0, 0.0]],
		"up": 0.0, "down": 0.0, "left": 0.0, "right": 0.0}


func to_dict() -> Dictionary:
	return {"active": active, "heart": heart.id if heart != null and not heart.dead else -1, "pctl": pctl.duplicate(true),
		"down": down.duplicate(), "down_turns": down_turns.duplicate(), "start": start_leader, "turn": last_turn,
		"rsel": revive_sel, "who": who, "feed": heal_mate, "hp0": _hp0, "keys": [pkeys.now.duplicate(), pkeys.prev.duplicate(), pkeys.cleared.duplicate(), pkeys.sim.duplicate()]}


func from_dict(d: Dictionary) -> void:
	active = d.get("active", false)
	var hid := int(d.get("heart", -1))
	heart = vm.by_id.get(hid) if hid >= 0 else null
	pctl = (d.get("pctl", pctl) as Dictionary).duplicate(true)
	down = (d.get("down", down) as Dictionary).duplicate()
	down_turns = (d.get("down_turns", down_turns) as Dictionary).duplicate()
	start_leader = d.get("start", "host")
	last_turn = d.get("turn", -1.0)
	revive_sel = d.get("rsel", false)
	who = d.get("who", -1)
	heal_mate = d.get("feed", false)
	_hp0 = d.get("hp0", 0.0)
	var k: Array = d.get("keys", [{}, {}, {}, {}])
	pkeys.now = (k[0] as Dictionary).duplicate()
	pkeys.prev = (k[1] as Dictionary).duplicate()
	pkeys.cleared = (k[2] as Dictionary).duplicate()
	pkeys.sim = (k[3] as Dictionary).duplicate()
	_hook()


func other() -> String:
	return partner.leader_other()


func _g(n: String, d = 0.0):
	return vm.globals.get(n, d)


func _obj(n: String) -> float:
	return float(vm.obj_index.get(n, -1))


func _first(n: String):
	var keep = vm.scoped
	vm.scoped = null
	var r = vm.first_of(_obj(n), {"self": null, "other": null})
	vm.scoped = keep
	return r


func _main_heart():
	for i in vm.resolve(_obj("obj_heart"), {"self": null, "other": null}):
		if i != heart and int(i.obj) == int(_obj("obj_heart")):
			return i
	return null


# ------------------------------------------------------------------ the VM's scope

func _hook() -> void:
	var on: bool = active and heart != null and not heart.dead
	vm.scoped = heart if on else null
	vm.aim_split = on and float(_g("mnfight")) == 2.0
	if vm.aim_skip.is_empty():
		for n in ["obj_battlecontroller", "obj_heart", "obj_lborder", "obj_rborder", "obj_uborder", "obj_dborder",
				"OBJ_WRITER", "OBJ_INSTAWRITER", "obj_time", "obj_shaker"]:
			if vm.obj_index.has(n):
				vm.aim_skip[int(vm.obj_index[n])] = true
	vm.scope_enter = _enter
	vm.scope_exit = _exit
	vm.inst_keys = {heart.id: pkeys} if on else {}


func _enter() -> void:
	var g: Dictionary = vm.globals
	_saved = {}
	for k in partner.OWN + partner.OWN_ARRAYS:
		_saved[k] = g.get(k, 0.0)
		if partner.profile.has(k):
			g[k] = partner.profile[k]
	for k in CTL:
		_saved[k] = g.get(k, 0.0)
		g[k] = pctl[k]
	var t = _first("obj_time")
	if t != null:
		for k in TIME:
			_saved["t_" + k] = t.v.get(k, 0.0)
			t.v[k] = pctl[k]
	_saved["_keys"] = eng.bi.keys
	eng.bi.keys = pkeys


func _exit() -> void:
	var g: Dictionary = vm.globals
	for k in partner.OWN + partner.OWN_ARRAYS:
		if partner.profile.has(k):
			partner.profile[k] = g.get(k, 0.0)
		g[k] = _saved[k]
	for k in CTL:
		pctl[k] = g.get(k, 0.0)
		g[k] = _saved[k]
	var t = _first("obj_time")
	if t != null:
		for k in TIME:
			pctl[k] = t.v.get(k, 0.0)
			t.v[k] = _saved["t_" + k]
	eng.bi.keys = _saved["_keys"]


# ------------------------------------------------------------------ every frame

# Before the game's step. host_keys / client_keys: this frame's keys of each PC.
func before_step(host_keys: Array, client_keys: Array) -> void:
	# Flowey's first fight is a scripted scene with no menu and no turns: the leader's
	# SOUL alone, the friend watches.
	if not eng.in_battle_room() or vm.room_names[vm.room] == "room_floweybattle":
		if active:
			_end()
		return
	if not active:
		_begin()
	# A new menu turn (the game counts global.turn): it's the other player's go, unless down.
	var turn := float(_g("turn"))
	if turn != last_turn and float(_g("myfight")) == 0.0 and float(_g("mnfight")) == 0.0:
		last_turn = turn
		revive_sel = false
		for p in down:
			if down[p]:
				down_turns[p] += 1
		if not down[other()]:
			_swap_roles()
	var pk: Array = client_keys if partner.leader == "host" else host_keys
	_revive_keys(host_keys if partner.leader == "host" else client_keys)
	_who_keys(host_keys if partner.leader == "host" else client_keys)
	# Outside the dodging part the other SOUL gets no keys: its Step is obj_heart's, which in
	# the menu works the menu, so a friend pressing Z on the other's turn would pick options too.
	pkeys.poll(pk if float(_g("mnfight")) == 2.0 else [])
	_control_update()
	# The other player's SOUL: made from the game's own one (copied, not created, so
	# obj_heart's Create, which resets the battle menu, doesn't run again).
	var mh = _main_heart()
	if (heart == null or heart.dead) and not down[other()] and mh != null:
		heart = vm.instance_create(float(mh.v["x"]), float(mh.v["y"]), int(mh.obj), false)
		for k in mh.v:
			var val = mh.v[k]
			heart.v[k] = val.duplicate(true) if val is Array or val is Dictionary else val
		heart.alarm = mh.alarm.duplicate()
	if heart != null and heart.dead:
		heart = null
	if heart != null:
		# Shown with the game's own SOUL once the enemy's part starts (the box); hidden in the
		# menu, where the game's SOUL is the cursor.
		var seen := 0.0
		if float(_g("mnfight")) != 0.0 and mh != null:
			seen = float(mh.v.get("visible", 1.0))
		heart.v["visible"] = seen
	_hook()


# After the game's step: who went down.
func after_step() -> void:
	if not active:
		return
	if eng.coop.test_log and eng.frames % 50 == 0:
		var mh = _main_heart()
		print("CBAT f=%d leader=%s hp=%s mate_hp=%s down=%s turns=%s turn=%s my=%s mn=%s bm=%s main=%s mate=%s" % [eng.frames, partner.leader,
			_g("hp"), partner.profile.get("hp"), down, down_turns, _g("turn"), _g("myfight"), _g("mnfight"), _g("bmenuno"),
			("%s,%s mv%s" % [mh.v["x"], mh.v["y"], mh.v["visible"]]) if mh != null else "-", ("%s,%s v%s" % [heart.v["x"], heart.v["y"], heart.v["visible"]]) if heart != null else "-"])
	var o := other()
	if heal_mate:
		# The game used the item on "its" player, who had the teammate's HP for this frame.
		heal_mate = false
		var mate_hp := float(_g("hp"))
		if eng.coop.test_log:
			print("CBAT fed teammate %d HP" % int(mate_hp - float(partner.profile.get("hp", 0.0))))
		partner.profile["hp"] = mate_hp
		vm.globals["hp"] = _hp0
	if not down[o] and float(partner.profile.get("hp", 1.0)) <= 0.0:
		_go_down(o)
	if not down[partner.leader] and float(_g("hp")) <= 0.0 and not down[o]:
		# The game's player is down but the other one isn't: they take over the fight.
		var p: String = partner.leader
		_swap_roles()
		_go_down(p)
	_hook()


func _go_down(p: String) -> void:
	down[p] = true
	down_turns[p] = 0
	if p == other() and heart != null:
		vm.instance_destroy(heart)
		heart = null
	eng._toast("%s is down!" % eng.coop_name(p), 3000)


func _begin() -> void:
	active = true
	start_leader = partner.leader
	last_turn = float(_g("turn"))
	down = {"host": false, "client": false}
	down_turns = {"host": 0, "client": 0}
	revive_sel = false
	heart = null
	_reset_ctl()
	pkeys.now = {}
	pkeys.prev = {}
	pkeys.cleared = {}
	pkeys.sim = {}


func _snd(n: String) -> void:
	if vm.consts.has(n):
		eng.bi.play_sound(int(vm.consts[n]), false)


# The partner went away (left, or the game ended): the host carries on alone.
func drop() -> void:
	if active and partner.leader != "host":
		_swap_roles(false)
	if heart != null and not heart.dead:
		vm.instance_destroy(heart)
	heart = null
	active = false
	_hook()


func _end() -> void:
	active = false
	heart = null
	_hook()
	# Back to how it was in the overworld, then the downed get up on 1 HP (not after a
	# game over: that loads the save).
	if partner.leader != start_leader:
		_swap_roles(false)
	var over: bool = vm.room >= 0 and String(vm.room_names[vm.room]).begins_with("room_gameover")
	if over:
		# The game loads the save; until co-op saves hold the friend's HP, they come back full.
		partner.profile["hp"] = float(_g("maxhp", 20.0))
	else:
		if float(_g("hp")) <= 0.0:
			vm.globals["hp"] = 1.0
		if float(partner.profile.get("hp", 1.0)) <= 0.0:
			partner.profile["hp"] = 1.0
	down = {"host": false, "client": false}


# The other player becomes the game's player: stats, battle state, keys, and which SOUL is
# whose. with_hearts = false after the battle (no SOULs left).
func _swap_roles(with_hearts := true) -> void:
	partner._swap_profiles()
	var g: Dictionary = vm.globals
	for k in CTL:
		var mine = g.get(k, 0.0)
		g[k] = pctl[k]
		pctl[k] = mine
	var t = _first("obj_time")
	if t != null:
		for k in TIME:
			var mine = t.v.get(k, 0.0)
			t.v[k] = pctl[k]
			pctl[k] = mine
	var mk = eng.keys
	for f in ["now", "prev", "cleared", "sim"]:
		var a = mk.get(f)
		mk.set(f, pkeys.get(f))
		pkeys.set(f, a)
	partner.leader = other()
	partner.swaps += 1
	if with_hearts:
		var mh = _main_heart()
		if heart != null and mh != null:
			# The spare SOUL becomes the game's own: it shows as the game had its own (in the
			# menu it's the cursor), not hidden as the spare one was there.
			var shown = mh.v.get("visible", 1.0)
			heart.v["visible"] = shown
			heart = mh
		elif heart == null and mh != null:
			# The new leader had no SOUL (was down): theirs is the game's now, the old
			# leader's goes away below if they're down.
			heart = null
	_hook()


# The other player's control_update (as obj_time does it for the leader).
func _control_update() -> void:
	var ns := [1.0 if pkeys.held(90) or pkeys.held(13) else 0.0, 1.0 if pkeys.held(88) or pkeys.held(16) else 0.0,
		1.0 if pkeys.held(67) or pkeys.held(17) else 0.0]
	var st: Array = (pctl["control_state"] as Array)[0]
	var pr: Array = (pctl["control_pressed"] as Array)[0]
	for i in 3:
		pr[i] = 1.0 if float(st[i]) == 0.0 and ns[i] == 1.0 else 0.0
		st[i] = ns[i]
	(pctl["control_new_state"] as Array)[0] = ns.duplicate()
	for pair in [["up", 38], ["down", 40], ["left", 37], ["right", 39]]:
		pctl[pair[0]] = 1.0 if pkeys.held(pair[1]) else 0.0


# ------------------------------------------------------------------ Revive (in MERCY)

func revive_shown() -> bool:
	return active and down[other()] and float(_g("myfight")) == 0.0 and float(_g("mnfight")) == 0.0 \
		and float(_g("bmenuno")) == 4.0


func revive_ready() -> bool:
	return down_turns[other()] >= REVIVE_TURNS


func _mercy_rows() -> int:
	return 1 if float(_g("mercy")) >= 1.0 else 2


# The leader's keys before the game sees them: Down/Up move onto and off "Revive", and Z
# on it revives instead of reaching the game.
func _revive_keys(lk: Array) -> void:
	if not revive_shown():
		revive_sel = false
		return
	var mk = eng.keys
	var pressed := func(c: int) -> bool: return lk.has(c) and not mk.now.has(c)
	var coord := float(_bm(4))
	if not revive_sel:
		if pressed.call(40) and coord >= float(_mercy_rows() - 1):
			revive_sel = true
			lk.erase(40)
			_snd("snd_squeak")
		elif pressed.call(38) and coord == 0.0:
			revive_sel = true
			lk.erase(38)
			_snd("snd_squeak")
		return
	for c in [37, 38, 39, 40]:
		if pressed.call(c) and (c == 38 or c == 40):
			revive_sel = false
			_set_bm(4, float(_mercy_rows() - 1) if c == 38 else 0.0)
			_snd("snd_squeak")
		lk.erase(c)
	if pressed.call(90) or pressed.call(13):
		lk.erase(90)
		lk.erase(13)
		if revive_ready():
			_revive()
	# The game's SOUL cursor goes on the Revive row (after the game's step places it).


func _bm(i: int) -> float:
	var a = _g("bmenucoord", [[0.0]])
	if a is Array and not a.is_empty() and a[0] is Array and (a[0] as Array).size() > i:
		return float(a[0][i])
	return 0.0


func _set_bm(i: int, v: float) -> void:
	var a = _g("bmenucoord", [[0.0]])
	if a is Array and not a.is_empty() and a[0] is Array and (a[0] as Array).size() > i:
		a[0][i] = v


func _revive() -> void:
	var o := other()
	down[o] = false
	down_turns[o] = 0
	revive_sel = false
	var mx := float(_g("maxhp", 20.0))
	partner.profile["hp"] = maxf(1.0, ceilf(mx * REVIVE_PART))
	# Back up in time for the enemy's attack: a moment safe from it, as after a hit (and the
	# SOUL flashes meanwhile), so they live to take their own turn.
	pctl["invc"] = REVIVE_SAFE
	var who: String = eng.coop_name(o).replace("\"", "'")
	vm.run_source("""with (OBJ_WRITER) halt = 3;
with (OBJ_INSTAWRITER) halt = 3;
global.typer = 1;
global.msc = 0;
global.msg[0] = "* You helped %s back up!&* %s recovered %d HP!/%%";
instance_create(global.idealborder[0], global.idealborder[2], OBJ_WRITER);
global.myfight = 4;
obj_heart.x = -200;
snd_play(snd_heal_c);
control_clear(0);""" % [who, who, int(partner.profile["hp"])])


# ------------------------------------------------------------------ ITEM: "Who?"

func _who_possible() -> bool:
	var bm := float(_g("bmenuno"))
	return active and not down[other()] and float(_g("myfight")) == 0.0 and float(_g("mnfight")) == 0.0 		and bm >= 3.0 and bm < 4.0


# Z on an item asks who it's for (when the teammate is up); Z again uses it on them.
func _who_keys(lk: Array) -> void:
	if not _who_possible():
		who = -1
		return
	var mk = eng.keys
	var pressed := func(c: int) -> bool: return lk.has(c) and not mk.now.has(c)
	var z: bool = pressed.call(90) or pressed.call(13)
	if who < 0:
		var t = _first("obj_time")
		var side := t != null and (float(t.v.get("left", 0.0)) != 0.0 or float(t.v.get("right", 0.0)) != 0.0)
		if z and not side:
			who = 0
			lk.erase(90)
			lk.erase(13)
			_snd("snd_select")
		return
	for c in [37, 38, 39, 40]:
		if pressed.call(c):
			who = 1 - who
			_snd("snd_squeak")
		lk.erase(c)
	if pressed.call(88) or pressed.call(16):
		who = -1
		lk.erase(88)
		lk.erase(16)
		return
	if z:
		# This Z reaches the game, which uses the item as usual.
		heal_mate = who == 1
		_hp0 = float(_g("hp"))
		if heal_mate:
			# The game heals its own player: for this frame that's the teammate's HP.
			vm.globals["hp"] = partner.profile.get("hp", 0.0)
		if eng.coop.test_log:
			print("CBAT item for %s at f=%d (hp %s, mate %s)" % ["teammate" if heal_mate else "self", eng.frames, _g("hp"), partner.profile.get("hp")])
		who = -1
	else:
		lk.erase(90)
		lk.erase(13)


# ------------------------------------------------------------------ drawing (this PC only)

# Row y of the battle menu, as the game works it out.
func _row_y(r: int) -> float:
	return float(vm.call_script("scr_battlemenu_cursor_y", [float(r)], {"self": null, "other": null, "locals": {}, "args": []}))


func after_draw_step() -> void:
	# The cursor: the game put its SOUL on the MERCY row it knows; Revive is one more.
	if revive_shown() and revive_sel:
		var mh = _main_heart()
		if mh != null:
			mh.v["y"] = _row_y(_mercy_rows())


# Draws the co-op parts of the battle for the player on this PC (me = "host"/"client").
func draw(me: String) -> void:
	if not active:
		return
	var bi = eng.bi
	var keep: Array = [bi.draw_font, bi.halign, bi.valign, bi.draw_color, bi.draw_alpha]
	var mate := "client" if me == "host" else "host"
	var ib = _g("idealborder", [[0.0, 0.0, 0.0, 0.0]])
	var b: Array = ib[0] if ib is Array and not ib.is_empty() and ib[0] is Array else [32.0, 602.0, 250.0, 385.0]
	# Teammate's HP, small, top-left.
	var hp := float(partner.profile.get("hp", 0.0))
	if partner.leader == mate:
		hp = float(leader_hp) if leader_hp != null else float(_g("hp"))
	var mx := float(_g("maxhp", 20.0))
	var line := "%s  HP %d/%d" % [eng.coop_name(mate), int(hp), int(mx)]
	var col := 16777215
	if down[mate]:
		var left: int = REVIVE_TURNS - int(down_turns[mate])
		line = "%s  DOWN" % eng.coop_name(mate) + (("  revive in %d" % left) if left > 0 else "  can be revived")
		col = 4210943   # red (BGR)
	_text(10.0, 8.0, line, col, "fnt_small", 2.0)
	# Whose turn it is, on the other player's screen.
	if float(_g("myfight")) == 0.0 and float(_g("mnfight")) == 0.0 and partner.leader != me:
		_text(10.0, 30.0, "%s's turn" % eng.coop_name(partner.leader), 65535, "fnt_small", 2.0)
	# The teammate's SOUL gets their name.
	if float(_g("mnfight")) != 0.0:
		var hs = heart if partner.leader == me else _main_heart()
		if hs != null and not hs.dead and float(hs.v.get("visible", 1.0)) >= 0.5:
			var nm: String = eng.coop_name(mate)
			bi.draw_font = int(vm.consts.get("fnt_small", -1.0))
			var w: float = bi.text_width(nm)
			_text(float(hs.v["x"]) + 8.0 - w / 2.0, float(hs.v["y"]) - 12.0, nm, 16777215, "fnt_small", 1.0)
	# ITEM: Who?
	if who >= 0 and _who_possible():
		var bx := float(b[1]) - 200.0
		var by := float(b[2]) + 12.0
		var me_name: String = eng.coop_name(partner.leader)
		var mate_name: String = eng.coop_name(other())
		bi._rect(bx - 6.0, by - 6.0, bx + 180.0, by + 82.0, false, Color.BLACK)
		bi._rect(bx - 6.0, by - 6.0, bx + 180.0, by + 82.0, true, Color.WHITE)
		_text(bx, by, "Who?", 16777215, "fnt_main", 1.0)
		_text(bx + 10.0, by + 26.0, ("> " if who == 0 else "  ") + me_name, 65535 if who == 0 else 16777215, "fnt_main", 1.0)
		_text(bx + 10.0, by + 52.0, ("> " if who == 1 else "  ") + mate_name, 65535 if who == 1 else 16777215, "fnt_main", 1.0)
	# MERCY: the Revive row.
	if revive_shown():
		var nm2: String = eng.coop_name(other())
		var t: String = "*  Revive  " + nm2
		var c2 := 16777215 if revive_ready() else 8421504
		if not revive_ready():
			t += " (%d)" % (REVIVE_TURNS - int(down_turns[other()]))
		_text(float(b[0]) + 68.0, _row_y(_mercy_rows()) - 6.0, t, c2, "fnt_main", 1.0)
	bi.draw_font = keep[0]
	bi.halign = keep[1]
	bi.valign = keep[2]
	bi.draw_color = keep[3]
	bi.draw_alpha = keep[4]
	# Testing (--cooplog): a picture of each of these the first time it shows.
	if eng.coop.test_log:
		_sel_frames = _sel_frames + 1 if revive_sel else 0
		for k in [["revive", revive_shown() and _sel_frames == 4], ["who", who >= 0], ["mateturn", partner.leader != me and float(_g("bmenuno")) == 0.0 and float(_g("mnfight")) == 0.0]]:
			if k[1] and not _shots.has(k[0]):
				_shots[k[0]] = true
				eng.bot_shot(k[0])


func _text(x: float, y: float, s: String, col: int, font: String, sc: float) -> void:
	var bi = eng.bi
	bi.draw_font = int(vm.consts.get(font, vm.consts.get("fnt_small", -1.0)))
	bi.halign = 0
	bi.valign = 0
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		bi._draw_text(x + o.x, y + o.y, s, sc, sc, 0.0, 0, 1.0)
	bi._draw_text(x, y, s, sc, sc, 0.0, col, 1.0)
