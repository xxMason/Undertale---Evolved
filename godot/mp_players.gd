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
# Globals that belong to each player. Data, not code: mods can add their own.
const PER_PLAYER := [
	# input (obj_time computes these for the primary player; see _input)
	"control_state", "control_pressed", "control_new_state",
	# where they are and what they are doing
	"facing", "interact", "phasing", "entrance", "encounter", "currentroom",
	"menuno", "menucoord", "menuchoice",
	# their character
	"hp", "maxhp", "at", "df", "weapon", "armor", "wstrength", "adef", "gold",
	"item", "itemname", "phone", "phonename",
	# their text box
	"msg", "msc", "typer", "choice", "choices", "facechoice", "faceemotion", "facechange",
]
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
	var overlay := {}            # their PER_PLAYER globals while someone else's are loaded
	var inst = null              # their obj_mainchara in the current room
	var view := Vector2.ZERO     # their camera (view 0's position)


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
	vm.owners_on = list.size() > 1


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
	for k in PER_PLAYER:
		if g.has(k):
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
	for k in PER_PLAYER:
		if ov.has(k):
			g[k] = ov[k]
		elif g.has(k):
			# First time this player needs it: their own copy of the current value (an array
			# must never be shared, or one player's items would change the other's).
			g[k] = g[k].duplicate(true) if g[k] is Array else g[k]
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
		if p.index == primary:
			continue
		p.keys.poll(p.feed.call() if p.feed.is_valid() else [])
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
	for p in list:
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
		if i.owner < 0:
			free.append(i)
		if i.owner == primary or (main == null and i.owner < 0):
			main = i
	for p in list:
		var cur = vm.player_insts[p.index].get(obj_main)
		if cur != null and not cur.dead and cur.owner == p.index and vm.instances.has(cur):
			p.inst = cur
			continue
		p.inst = null
		vm.player_insts[p.index].erase(obj_main)
		if main == null:
			continue
		var inst = null
		if p.index == primary and main.owner < 0:
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
