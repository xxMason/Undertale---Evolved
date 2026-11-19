# The players of a game (docs/MULTIPLAYER.md, stage 2): up to 4, each with their own
# character (a real obj_mainchara), keys, and their own copy of the globals Undertale
# keeps for "the player" (input, HP, items, gold, text, menu, camera...).
#
# The GML machine runs every event of a player's instance in that player's context
# (gml_vm.gd owners_on / owner_switch): this file swaps that player's values into the
# globals for the event and back out afterwards. The world's own objects run in the
# primary player's context, so with one player nothing is ever swapped and the game is
# exactly the original.
extends RefCounted

const Keys = preload("res://gml/gml_keys.gd")

const MAX := 4
# Every global is each player's own (their input, HP, items, gold, text, menus, battle...)
# except these, which are the world's: story progress (plot, flags, kills, shared EXP and LV),
# the save file's bookkeeping, and the game's settings. Data, not code: mods can add their own.
const SHARED := {
	"plot": true, "flag": true, "fplot": true, "kills": true, "xp": true, "lv": true,
	"charname": true, "filechoice": true, "lastsavedkills": true, "lastsavedlv": true,
	"lastsavedtime": true, "hardmode": true, "osflavor": true,
	"language": true, "locale": true, "debug": true, "awfultest": true, "starton9": true,
	"analog_sense": true, "analog_sense_sense": true, "default_analog_sense": true,
	"default_analog_sense_sense": true, "button0": true, "button1": true, "button2": true,
	"default_button0": true, "default_button1": true, "default_button2": true,
	"default_joy_dir": true, "joy_dir": true, "joypad_dir": true, "to_joyconfig": true,
	"disable_os_pause": true, "current_ini": true, "savedata": true, "savedata_async_id": true,
	"savedata_async_load": true, "savedata_buffer": true, "savedata_debuginfo": true,
	"savedata_error": true, "screen_border_activate_on_game_over": true,
	"screen_border_active": true, "screen_border_alpha": true,
	"screen_border_dynamic_fade_id": true, "screen_border_dynamic_fade_level": true,
	"screen_border_id": true, "screen_border_state": true, "kanatype_lookup_2ch": true,
	"kanatype_lookup_3ch": true, "kanatype_lookup_4ch": true, "text_data_en": true,
	"text_data_ja": true, "trophy_init_complete": true, "steam_int": true,
	"window_scale": true, "window_xofs": true, "window_yofs": true,
}
# Text boxes and faces: each player sees only their own (and the world's).
const PRIVATE_ROOTS := ["obj_dialoguer", "obj_base_writer", "obj_choicer", "obj_face"]
# Objects that run once per player with their own variables: the overworld menu.
const MULTI_OBJECTS := ["obj_overworldcontroller"]
# obj_time's own variables that hold each player's arrow keys.
const TIME_FIELDS := ["left", "right", "up", "down"]
# SOUL colours for players 1-4 (chat, name tags): red, blue, green, yellow.
const COLOURS := [Color(1, 0, 0), Color(0, 0.6, 1), Color(0, 0.85, 0.2), Color(1, 0.9, 0)]


class Player:
	var index := 0
	var name := ""
	var keys                     # gml_keys.gd: what this player holds this frame
	var feed := Callable()       # returns this frame's held key codes (bots, network)
	var overlay := {}            # their own globals while someone else's are loaded (and their view, keys)
	var inst = null              # their obj_mainchara in the current room
	var view := Vector2.ZERO     # their camera (view 0's position) this logic frame
	var prev_view := Vector2.ZERO
	var active := true           # false: left the game; their slot (and stats) wait for them
	var back = null              # [room, x, y]: where they were before a battle; [room, "save"]: by its save point (mp_rooms.gd)
	var respawn := false         # downed alone: comes back at the last save after the game over screen


var eng
var vm
var list: Array = []
var primary := 0          # whose values the world's objects see
var loaded := 0           # whose values are in the globals right now
var obj_main := -1
var obj_time := -1
var _time_inst = null


func setup(e, names: Array) -> void:
	eng = e
	vm = e.vm
	obj_main = int(vm.obj_index.get("obj_mainchara", -1))
	obj_time = int(vm.obj_index.get("obj_time", -1))
	list.clear()
	for k in mini(names.size(), MAX):
		var p := Player.new()
		p.index = k
		p.name = String(names[k])
		p.keys = e.keys if k == 0 else Keys.new()
		list.append(p)
	primary = 0
	loaded = 0
	vm.player_insts = []
	for p in list:
		vm.player_insts.append({})
	vm.owner_switch = switch_to
	vm.ctx_owner = -1
	vm.primary_owner = primary
	vm.multi_players = range(list.size())
	vm.private_objs = _family(PRIVATE_ROOTS, "obj_face_")
	vm.multi_objs = _family(MULTI_OBJECTS, "")
	# Random encounters: each room's encounter object counts each player's own steps
	# (global.encounter) and starts their own battle.
	for o in vm.obj_names.size():
		var nm: String = vm.obj_names[o]
		if (nm.begins_with("obj_encount_") or nm.begins_with("obj_encounter_") or nm.begins_with("obj_encounterer_")):
			vm.multi_objs[o] = true
	vm.anchored_objs = _anchored()
	vm.owners_on = list.size() > 1


# Objects whose Draw (their own or inherited) places things relative to the view.
func _anchored() -> Dictionary:
	var out := {}
	var seen := {}
	for o in vm.obj_names.size():
		var found: Array = vm.find_event(o, vm.EV_DRAW, 0)
		if found.is_empty():
			continue
		var code: String = found[0]
		if not seen.has(code):
			var path: String = vm.base.path_join("code/" + code + ".gml")
			var src := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
			seen[code] = src.contains("view_xview") or src.contains("view_yview")
		if seen[code]:
			out[o] = true
	return out


# Object indices of the named objects and all their children (and of every object whose
# name starts with `prefix`, if one is given).
func _family(roots: Array, prefix: String) -> Dictionary:
	var out := {}
	var ids: Array = []
	for r in roots:
		if vm.obj_index.has(r):
			ids.append(int(vm.obj_index[r]))
	for o in vm.obj_names.size():
		var nm: String = vm.obj_names[o]
		if prefix != "" and nm.begins_with(prefix):
			out[o] = true
			continue
		for r in ids:
			if vm.is_child_of(o, r):
				out[o] = true
	return out


func count() -> int:
	return list.size()


# With players in several rooms (mp_rooms.gd): the players in the world the machine has
# loaded now. Empty: everyone.
var members: Array = []


func here(i: int) -> bool:
	return members.is_empty() or members.has(i)


# Before the machine changes world: the lead's values are loaded and everyone's saved, so the
# world keeps its own camera and keys and nobody takes this world's camera along.
func park() -> void:
	switch_to(-1)
	_save(loaded)


# After: the new world's lead is loaded (their values, camera and keys).
func unpark() -> void:
	_load(primary)
	loaded = primary
	vm.ctx_owner = -1


func active_count() -> int:
	var n := 0
	for p in list:
		if p.active:
			n += 1
	return n


# A friend joins mid-game (stage 4). Someone who left and comes back under the same name
# gets their own slot, stats and items back; anyone new starts as a copy of the primary
# player. Returns their index, or -1 when the game is full.
func add_player(pname: String) -> int:
	var slot = null
	for p in list:
		if not p.active and p.name == pname:
			slot = p
			break
	if slot == null:
		for p in list:
			if not p.active and slot == null:
				slot = p
		if slot != null:
			slot.overlay = {}
	if slot == null:
		if list.size() >= MAX:
			return -1
		slot = Player.new()
		slot.index = list.size()
		slot.keys = Keys.new()
		list.append(slot)
		vm.player_insts.append({})
	if slot.overlay.is_empty():
		_save(loaded)
		slot.overlay = list[primary].overlay.duplicate(true) if loaded != primary else _snapshot()
		# Their own text and menu start closed.
		slot.overlay["interact"] = 0.0
		slot.overlay["menuno"] = -1.0
	slot.name = pname
	slot.active = true
	slot.feed = Callable()
	_refresh()
	if eng.get("mprooms") != null:
		eng.mprooms.joined(slot.index)
	if eng.get("mpsaves") != null:
		eng.mpsaves.joined(slot.index)
	bind()
	return slot.index


# A friend leaves: their character goes, their text boxes close, whatever they were busy
# with is nobody's again. Their slot keeps their stats for when they come back.
func remove_player(i: int) -> void:
	if i < 0 or i >= list.size() or i == primary or not list[i].active:
		return
	var p: Player = list[i]
	var rooms = eng.get("mprooms")
	var back = rooms.cur if rooms != null else null
	if rooms != null and rooms.room_of(i) != null:
		rooms.switch(rooms.room_of(i))
	if loaded == i:
		switch_to(primary)
	p.active = false
	p.feed = Callable()
	for inst in vm.instances:
		if inst.dead or inst.owner != i:
			continue
		if inst.obj == obj_main or vm.private_objs.has(inst.obj):
			inst.dead = true
		else:
			inst.owner = -1
	vm.inst_version += 1
	vm.player_insts[i] = {}
	p.inst = null
	_refresh()
	if rooms != null:
		rooms.left(i)
		if rooms.rooms.has(back):
			rooms.switch(back)


func _snapshot() -> Dictionary:
	var out := {}
	for k in vm.globals:
		if not SHARED.has(k):
			out[k] = vm.globals[k].duplicate(true) if vm.globals[k] is Array else vm.globals[k]
	return out


func _refresh() -> void:
	var on: Array = []
	for p in list:
		if p.active and here(p.index):
			on.append(p.index)
	vm.multi_players = on
	vm.owners_on = list.size() > 1


# Everyone else starts as a copy of the primary player (same HP, items, text state...).
func copy_primary_to_others() -> void:
	_save(loaded)
	var src: Dictionary = list[loaded].overlay
	for p in list:
		if p.index != loaded:
			p.overlay = src.duplicate(true)


# ---------------------------------------------------------------- context switching

func switch_to(o: int) -> void:
	vm.ctx_owner = o
	var want := primary if o < 0 else o
	if want == loaded:
		return
	_save(loaded)
	_load(want)
	loaded = want


func _time():
	if _time_inst == null or _time_inst.dead:
		_time_inst = vm.first_of(float(obj_time), {"self": null, "other": null}) if obj_time >= 0 else null
	return _time_inst


func _save(i: int) -> void:
	var p: Player = list[i]
	var g: Dictionary = vm.globals
	for k in g:
		if not SHARED.has(k):
			p.overlay[k] = g[k]
	var t = _time()
	if t != null:
		for f in TIME_FIELDS:
			p.overlay["time." + f] = t.v.get(f, 0.0)
	p.overlay["view"] = Vector2(float(eng.bi.view_xview[0]), float(eng.bi.view_yview[0]))
	p.overlay["keys"] = eng.bi.keys


func _load(i: int) -> void:
	var p: Player = list[i]
	var g: Dictionary = vm.globals
	var ov: Dictionary = p.overlay
	for k in g:
		if SHARED.has(k):
			continue
		if ov.has(k):
			g[k] = ov[k]
		else:
			# First time this player needs it: their own copy of the current value (an array
			# must never be shared, or one player's items would change the other's).
			var cur = g[k]
			if cur is Array:
				g[k] = cur.duplicate(true)
	# Globals only they have made so far.
	for k in ov:
		if not g.has(k) and not SHARED.has(k) and k != "view" and k != "keys" and not String(k).begins_with("time."):
			g[k] = ov[k]
	var t = _time()
	if t != null:
		for f in TIME_FIELDS:
			if ov.has("time." + f):
				t.v[f] = ov["time." + f]
	if ov.has("view"):
		eng.bi.view_xview[0] = ov["view"].x
		eng.bi.view_yview[0] = ov["view"].y
	eng.bi.keys = p.keys


# A player's value of a per-player global, wherever it is kept right now.
func value(i: int, k: String, def = 0.0):
	if i == loaded:
		return vm.globals.get(k, def)
	return list[i].overlay.get(k, def)


func set_value(i: int, k: String, val) -> void:
	if i == loaded:
		vm.globals[k] = val
	else:
		list[i].overlay[k] = val


# ---------------------------------------------------------------- each frame

# Before the game's step: every player's keys for this frame, and for everyone but the
# primary player the input values obj_time would have worked out (Undertale's
# control_update and arrow keys: held, and not just released).
func before_step() -> void:
	for p in list:
		if not p.active or not here(p.index):
			continue
		# Player 1's keys are this PC's, already read by the engine.
		if p.index != 0:
			p.keys.poll(p.feed.call() if p.feed.is_valid() else [])
		# A prompt of the engine's own (mp_ui.gd) takes their keys first.
		if eng.get("mpui") != null:
			eng.mpui.filter(p)
		# The lead's are worked out by the room's own obj_time.
		if p.index != primary:
			_input(p)


func _input(p: Player) -> void:
	var k = p.keys
	var ns := [k.held(90) or k.held(13), k.held(88) or k.held(16), k.held(67) or k.held(17)]
	var st: Array = _row(p, "control_state")
	var pr: Array = _row(p, "control_pressed")
	var nw: Array = _row(p, "control_new_state")
	for c in 3:
		var n := 1.0 if ns[c] else 0.0
		pr[c] = 1.0 if (float(st[c]) == 0.0 and n == 1.0) else 0.0
		st[c] = n
		nw[c] = n
	var codes := {"left": 37, "up": 38, "right": 39, "down": 40}
	for f in codes:
		p.overlay["time." + f] = 1.0 if (k.held(codes[f]) and not k.released(codes[f])) else 0.0


# The first row of a GML array in a player's overlay (made 3 long), owned by that player.
func _row(p: Player, k: String) -> Array:
	var a = p.overlay.get(k)
	if not (a is Array) or a.is_empty() or not (a[0] is Array):
		a = [[0.0, 0.0, 0.0]]
		p.overlay[k] = a
	var r: Array = a[0]
	while r.size() < 3:
		r.append(0.0)
	return r


# After the game's step (and any room change): an object a player was busy with is
# nobody's again once that is over (its talk finished, the player free, its alarms done),
# and every player has a character in the current room.
func after_step() -> void:
	if vm.claimed.size() > 0:
		var keep: Array = []
		for i in vm.claimed:
			if i.dead:
				continue
			if _done_with(i):
				i.owner = -1
			else:
				keep.append(i)
		vm.claimed = keep
	bind()
	if eng.get("mpsaves") != null:
		eng.mpsaves.after_step()
	# Each player's camera follows their own character the way the room's view does for
	# player 1 (borders, speed, kept inside the room): the room's view object means their
	# own instance in their context.
	var keep_ctx: int = vm.ctx_owner
	for p in list:
		if p.index == primary or not p.active or not here(p.index):
			continue
		switch_to(p.index)
		eng.bi.update_views()
	switch_to(keep_ctx)
	for p in list:
		if not here(p.index):
			continue
		p.prev_view = p.view
		p.view = value(p.index, "view", Vector2.ZERO) if p.index != loaded else Vector2(float(eng.bi.view_xview[0]), float(eng.bi.view_yview[0]))


func _done_with(i) -> bool:
	if float(i.v.get("myinteract", 0.0)) != 0.0:
		return false
	if i.owner < 0 or i.owner >= list.size() or float(value(i.owner, "interact")) != 0.0:
		return i.owner < 0 or i.owner >= list.size()
	for a in i.alarm:
		if float(a) > 0.0:
			return false
	return true


# Gives every player an obj_mainchara in the room. The room's own one is the primary
# player's; the others get one beside it, created in their own context so its Create
# event sees their facing and stats.
func bind() -> void:
	if obj_main < 0:
		return
	var main = null
	var free: Array = []
	for i in vm.instances:
		if i.dead or i.obj != obj_main:
			continue
		if i.owner >= 0 and (i.owner >= list.size() or not list[i.owner].active or not here(i.owner)):
			# A player who is elsewhere (a room parked with them in it, then they left it).
			i.dead = true
			vm.inst_version += 1
			continue
		if i.owner < 0:
			free.append(i)
		if i.owner == primary or (main == null and i.owner < 0):
			main = i
	for p in list:
		if not p.active or not here(p.index):
			continue
		var cur = vm.player_insts[p.index].get(obj_main)
		if cur != null and not cur.dead and cur.owner == p.index and vm.instances.has(cur):
			p.inst = cur
			continue
		p.inst = null
		vm.player_insts[p.index].erase(obj_main)
		if main == null:
			continue
		var inst = null
		for i in vm.instances:
			if not i.dead and i.obj == obj_main and i.owner == p.index:
				inst = i     # the room made theirs already (made in their context)
				break
		if inst != null:
			pass
		elif p.index == primary and main.owner < 0:
			inst = main
			inst.owner = p.index
			free.erase(main)
		elif not free.is_empty() and free[0] != main:
			inst = free.pop_front()
			inst.owner = p.index
		else:
			var keep_ctx: int = vm.ctx_owner
			switch_to(p.index)
			inst = vm.instance_create(float(main.v["x"]), float(main.v["y"]), obj_main)
			inst.owner = p.index
			switch_to(keep_ctx)
		p.inst = inst
		vm.player_insts[p.index][obj_main] = inst
		if p.index != primary:
			vm.inst_keys[inst.id] = p.keys
	# Back from a battle in a room that kept running for the others: where they were.
	for p in list:
		if p.back != null and p.inst != null and not p.inst.dead and here(p.index) and int(p.back[0]) == vm.room:
			var at = null
			if p.back[1] is String:
				# Where the room starts its player (beside its save point), as when loading.
				var rd = vm.meta["rooms"].get(vm.room_names[vm.room], {})
				for ri in rd.get("instances", []):
					if ri[0] == "obj_mainchara":
						at = Vector2(float(ri[1]), float(ri[2]))
						break
				if at == null and p.index != primary and list[primary].inst != null and not list[primary].inst.dead:
					at = Vector2(float(list[primary].inst.v["x"]), float(list[primary].inst.v["y"]))
			else:
				at = Vector2(float(p.back[1]), float(p.back[2]))
			if at != null:
				# On the 3-pixel grid walking keeps to (obj_mainchara's Create does the same).
				at = Vector2(roundf(at.x / 3.0) * 3.0, roundf(at.y / 3.0) * 3.0)
				p.inst.v["x"] = at.x
				p.inst.v["y"] = at.y
				p.inst.v["xprevious"] = at.x
				p.inst.v["yprevious"] = at.y
			p.back = null
		elif p.back != null and here(p.index) and vm.room >= 0 and int(p.back[0]) != vm.room and not eng.mprooms._private_room(vm.room):
			p.back = null     # they went somewhere else


# ---------------------------------------------------------------- local tests

# --players N --pfeed "2=SPEC;3=SPEC": several players in one game on this PC (numbered from 1;
# player 1 is the keyboard or the bot), the extra
# ones driven by SPEC: "idle", "follow" (walk towards player 1), or a list of presses as
# --press takes them ("frame:key[xframes],...").
func make_feed(spec: String, me: int) -> Callable:
	if spec == "follow":
		return func() -> Array:
			var a = list[0].inst
			var b = list[me].inst
			if a == null or b == null or a.dead or b.dead:
				return []
			var d := Vector2(float(a.v["x"]) - float(b.v["x"]), float(a.v["y"]) - float(b.v["y"]))
			var out: Array = []
			if d.x > 24.0:
				out.append(39)
			elif d.x < -24.0:
				out.append(37)
			if d.y > 24.0:
				out.append(40)
			elif d.y < -24.0:
				out.append(38)
			return out
	var presses: Array = []
	for part in spec.split(",", false):
		var fk := part.split(":")
		if fk.size() < 2:
			continue
		var kn := fk[1].split("x")
		presses.append([int(fk[0]), int(kn[0]), int(kn[1]) if kn.size() > 1 else 1])
	return func() -> Array:
		var held: Array = []
		for pr in presses:
			if eng.frames >= pr[0] and eng.frames < pr[0] + pr[2]:
				held.append(pr[1])
		return held


func log_line() -> String:
	var parts: Array = []
	for p in list:
		var at := "-"
		if p.inst != null and not p.inst.dead:
			at = "%s,%s" % [p.inst.v["x"], p.inst.v["y"]]
		var it = value(p.index, "item", [[]])
		var items: Array = it[0] if it is Array and not it.is_empty() and it[0] is Array else []
		parts.append("P%d %s at %s int=%s menu=%s face=%s hp=%s gold=%s items=%s enc=%s view=%s" % [p.index + 1, p.name, at,
			value(p.index, "interact"), value(p.index, "menuno"), value(p.index, "facing"), value(p.index, "hp"), value(p.index, "gold"),
			items.slice(0, 3), value(p.index, "encounter"), p.view])
	var owned := {}
	for i in vm.instances:
		if i.owner >= 0 and i.obj != obj_main:
			owned[vm.obj_names[i.obj]] = "P%d" % (i.owner + 1)
	return " | ".join(parts) + " | owned " + str(owned)
