# The second player in the overworld, run by the engine on both PCs from the frame's keys.
#
# The game itself has one player (obj_mainchara): whoever is the "leader". The other player
# walks the same room with the same sprites, blocked by the same walls, frozen while text
# or a cutscene runs, and drawn among the room's objects by depth like the real one.
#
# Leader swap: when the other player presses Z (talk, check, shop, save) or walks into a
# door, the two quietly change places: positions, facing, and each player's own stats
# (HP, items, gold, weapon and armor). The other player is then the game's real player,
# and Undertale's own code does the rest. Each PC's camera follows its own player, so
# nobody sees the swap. Nothing swaps while a text box or cutscene runs.
extends RefCounted

const CoopBattle = preload("res://coop_battle.gd")
const SPEED := 3.0
# Each player's own things; LV, EXP and the story are shared.
const OWN := ["hp", "gold", "weapon", "armor", "wstrength", "adef"]
const OWN_ARRAYS := ["item"]

var eng
var vm
var x := 0.0
var y := 0.0
var facing := 0              # as global.facing: 0 down, 1 right, 2 up, 3 left
var frame := 0.0             # walk animation
var moving := false
var room := -1
var leader := "host"         # whose character is the game's obj_mainchara
var profile: Dictionary = {} # the non-leader's own stats (see OWN)
var _prev_keys: Array = []
var swaps := 0
var _tried := Vector2(-9999, -9999)
var _door_armed := false
var battle                   # coop_battle.gd: the two SOULs in battle


func setup(e) -> void:
	eng = e
	vm = e.vm
	battle = CoopBattle.new()
	battle.setup(self)


func to_dict() -> Dictionary:
	return {"x": x, "y": y, "facing": facing, "frame": frame, "moving": moving, "room": room, "armed": _door_armed, "tried": _tried,
		"leader": leader, "profile": profile.duplicate(true), "prev": _prev_keys.duplicate(), "swaps": swaps,
		"battle": battle.to_dict()}


func from_dict(d: Dictionary) -> void:
	x = d["x"]
	y = d["y"]
	facing = d["facing"]
	frame = d["frame"]
	moving = d["moving"]
	room = d["room"]
	leader = d["leader"]
	profile = (d["profile"] as Dictionary).duplicate(true)
	_prev_keys = (d["prev"] as Array).duplicate()
	swaps = d.get("swaps", 0)
	_door_armed = d.get("armed", false)
	_tried = d.get("tried", Vector2(x, y))
	battle.from_dict(d.get("battle", {}))


# A new friend's stats: full HP for the shared LV, an empty bag, half the host's gold.
func new_profile(host_gold: float) -> void:
	var g: Dictionary = vm.globals
	profile = {"hp": g.get("maxhp", 20.0), "gold": floorf(host_gold / 2.0), "weapon": 3.0, "armor": 4.0, "wstrength": 0.0, "adef": 0.0}
	profile["item"] = bag([])


# A bag as the game keeps global.item: one row of 9 (8 items, and a 9th the game uses
# for item shuffling, scr_itemshift).
static func bag(items: Array) -> Array:
	var row: Array = []
	for i in 9:
		row.append(float(items[i]) if i < items.size() else 0.0)
	return [row]


func _player():
	return vm.first_of(float(vm.obj_index.get("obj_mainchara", -1)), {"self": null, "other": null})


func visible() -> bool:
	return _player() != null and not eng.in_battle_room()


func _free() -> bool:
	return float(vm.globals.get("interact", 0.0)) == 0.0


# ------------------------------------------------------------------ every frame

# Before the game's own step: moves the other player, and swaps leaders when they act.
# keys: the non-leader's keys this frame (GameMaker codes).
func before_step(keys: Array) -> void:
	var pl = _player()
	if pl == null:
		_prev_keys = keys.duplicate()
		return
	if vm.room != room:
		_arrive(pl)
	if eng.in_battle_room() or not _free():
		moving = false
		_prev_keys = keys.duplicate()
		return
	var z_now := keys.has(90) or keys.has(13)
	var z_before := _prev_keys.has(90) or _prev_keys.has(13)
	# C (or Ctrl) opens the menu, with this player's own items and stats: they lead for it.
	var c_now := keys.has(67) or keys.has(17)
	var c_before := _prev_keys.has(67) or _prev_keys.has(17)
	_prev_keys = keys.duplicate()
	_walk(pl, keys)
	# A door only counts once this player has stepped off the one they arrived on.
	var door := _at_door()
	if not door:
		_door_armed = true
	if (z_now and not z_before) or (c_now and not c_before) or (door and _door_armed):
		swap(pl)


func _arrive(pl) -> void:
	room = vm.room
	x = float(pl.v["x"])
	y = float(pl.v["y"])
	facing = int(vm.globals.get("facing", 0.0))
	moving = false
	_door_armed = false
	_tried = Vector2(x, y)
	# Beside the leader rather than on top of them, where there's floor to stand on.
	var behind: Vector2 = [Vector2(0, -18), Vector2(-18, 0), Vector2(0, 18), Vector2(18, 0)][facing]
	# Beside first: behind is usually the door just come through.
	for o in [Vector2(-18, 0), Vector2(18, 0), behind, Vector2(0, 18), Vector2(0, -18)]:
		var px: float = x + o.x
		var py: float = y + o.y
		if px >= 0 and py >= 0 and px < vm.room_width - 10 and py < vm.room_height - 10 and not _blocked(pl, px, py):
			x = px
			y = py
			break


func _walk(pl, keys: Array) -> void:
	var dx := (SPEED if keys.has(39) else 0.0) - (SPEED if keys.has(37) else 0.0)
	var dy := (SPEED if keys.has(40) else 0.0) - (SPEED if keys.has(38) else 0.0)
	moving = dx != 0.0 or dy != 0.0
	if not moving:
		frame = 0.0
		_tried = Vector2(x, y)
		return
	if dy > 0:
		facing = 0
	elif dy < 0:
		facing = 2
	if dx > 0 and dy == 0:
		facing = 1
	elif dx < 0 and dy == 0:
		facing = 3
	# Where the step tried to go: the real player moves first and is pushed back by walls after,
	# so it touches a door in a wall's way in that same frame.
	_tried = Vector2(x + dx, y + dy)
	var ox := x
	var oy := y
	if dx != 0.0 and not _blocked(pl, x + dx, y):
		x += dx
	if dy != 0.0 and not _blocked(pl, x, y + dy):
		y += dy
	x = clampf(x, 0.0, float(vm.room_width) - 1.0)
	y = clampf(y, 0.0, float(vm.room_height) - 1.0)
	frame += 0.2
	# Both players' steps count toward random encounters (as obj_mainchara's End Step does).
	if x != ox or y != oy:
		vm.globals["encounter"] = float(vm.globals.get("encounter", 0.0)) + 1.0


# The player's own collision box, moved to (px, py).
func _box(pl, px: float, py: float) -> Rect2i:
	var r: Rect2i = vm.bbox(pl)
	return Rect2i(r.position + Vector2i(int(px - float(pl.v["x"])), int(py - float(pl.v["y"]))), r.size)


# Walls as the real player meets them: solid objects (visible ones: invisible solids are
# story triggers), tested by their pixels when their mask is precise.
func _blocked(pl, px: float, py: float) -> bool:
	var box := _box(pl, px, py)
	var sp := int(vm.obj_index.get("obj_solidparent", -1))
	var np := int(vm.obj_index.get("obj_solidnpcparent", -1))
	var dp := int(vm.obj_index.get("obj_diagoparent", -1))
	for i in vm.instances:
		if i.dead or i == pl:
			continue
		var solid: bool = (sp >= 0 and vm.is_child_of(i.obj, sp)) or (np >= 0 and vm.is_child_of(i.obj, np))
		if not solid and float(i.v.get("solid", 0.0)) >= 0.5 and float(i.v.get("visible", 1.0)) >= 0.5:
			solid = true
		if not solid:
			continue
		var diag: bool = dp >= 0 and vm.is_child_of(i.obj, dp)
		var r: Rect2i = vm.bbox(i)
		if not r.intersects(box):
			continue
		if diag or vm._precise(i):
			if vm.collide_rect(i, box):
				_why(i, box)
				return true
		else:
			_why(i, box)
			return true
	return false


func _why(i, box: Rect2i) -> void:
	if OS.get_cmdline_user_args().has("--doorlog") and int(eng.frames) % 10 == 0:
		print("BLOCK f=%d by %s %s (solid=%s vis=%s) partner box %s" % [eng.frames, vm.obj_names[i.obj], vm.bbox(i), i.v.get("solid"), i.v.get("visible"), box])


func _at_door() -> bool:
	var pl = _player()
	var box := _box(pl, x, y).merge(_box(pl, _tried.x, _tried.y))
	for i in vm.instances:
		if i.dead:
			continue
		var nm: String = vm.obj_names[i.obj]
		if nm.begins_with("obj_door"):
			var r: Rect2i = vm.bbox(i)
			if r.position.x < box.end.x and box.position.x < r.end.x and r.position.y < box.end.y and box.position.y < r.end.y:
				return true
		if nm.begins_with("obj_door") and OS.get_cmdline_user_args().has("--doorlog") and int(eng.frames) % 30 == 0:
			print("DOOR f=%d %s %s vs partner %s at %s,%s" % [eng.frames, nm, vm.bbox(i), box, x, y])
	return false


# The two players change places: the other one becomes the game's own player.
func swap(pl) -> void:
	var ox := float(pl.v["x"])
	var oy := float(pl.v["y"])
	var of := int(vm.globals.get("facing", 0.0))
	pl.v["x"] = x
	pl.v["y"] = y
	pl.v["xprevious"] = x
	pl.v["yprevious"] = y
	vm.globals["facing"] = float(facing)
	var spr: String = ["dsprite", "rsprite", "usprite", "lsprite"][facing]
	if pl.v.has(spr):
		pl.v["sprite_index"] = pl.v[spr]
	x = ox
	y = oy
	facing = of
	moving = false
	frame = 0.0
	_swap_profiles()
	leader = "client" if leader == "host" else "host"
	swaps += 1


func _swap_profiles() -> void:
	var g: Dictionary = vm.globals
	var theirs := profile
	var mine := {}
	for k in OWN:
		mine[k] = g.get(k, 0.0)
		if theirs.has(k):
			g[k] = theirs[k]
	for k in OWN_ARRAYS:
		mine[k] = (g.get(k, [[]]) as Array).duplicate(true)
		if theirs.has(k):
			g[k] = (theirs[k] as Array).duplicate(true)
	profile = mine


# The leader's and the other player's stats, whoever is leading: {"host": {...}, "client": {...}}.
func profiles() -> Dictionary:
	var cur := {}
	for k in OWN:
		cur[k] = vm.globals.get(k, 0.0)
	for k in OWN_ARRAYS:
		cur[k] = (vm.globals.get(k, [[]]) as Array).duplicate(true)
	var other := leader_other()
	return {leader: cur, other: profile.duplicate(true)}


func leader_other() -> String:
	return "client" if leader == "host" else "host"


# ------------------------------------------------------------------ drawing

func _sprite(pl) -> int:
	var nm: String = ["dsprite", "rsprite", "usprite", "lsprite"][facing]
	return int(pl.v.get(nm, vm.sprite_index.get("spr_maincharad", -1)))


func depth() -> float:
	var pl = _player()
	var sp := _sprite(pl)
	var h := float(vm.spr_info[sp][2]) if sp >= 0 else 0.0
	return 50000.0 - (y * 10.0 + h * 10.0)


# Drawn by the game's own draw pass at this depth (engine.gd sets the hook).
func draw() -> void:
	var pl = _player()
	if pl == null:
		return
	var sp := _sprite(pl)
	if sp < 0:
		return
	var bi = eng.bi
	var rec = bi.canvas
	if rec != null and rec.has_method("owner"):
		rec.owner(-900001, Vector2(x, y))
	var n := int(vm.spr_info[sp][0])
	var fr := (int(floorf(frame)) % n) if moving and n > 0 else 0
	bi._draw_sprite_ext(sp, fr, x, y, 1, 1, 0, 16777215, 1)


# Name tags above both players, after everything else (in the room, so they move with it).
# The game's own drawing state (font, alignment) is left as it was.
func draw_names(host_name: String, client_name: String) -> void:
	var pl = _player()
	if pl == null:
		return
	var bi = eng.bi
	var keep: Array = [bi.draw_font, bi.halign, bi.valign, bi.draw_color, bi.draw_alpha]
	var lead_name := host_name if leader == "host" else client_name
	var other_name := client_name if leader == "host" else host_name
	if not _free():
		# Text, a menu or a cutscene: no tags over it. When the menu open is the other
		# player's, say so (the items in it are theirs).
		if float(vm.globals.get("interact", 0.0)) == 5.0 and leader != eng.coop.role:
			var vx := float(bi.view_xview[0]) if bi.views_on else 0.0
			var vy := float(bi.view_yview[0]) if bi.views_on else 0.0
			var vw := float(bi.view_wview[0]) if bi.views_on else 320.0
			_tag(vx + vw / 2.0, vy + 4.0, "%s's menu" % lead_name)
		bi.draw_font = keep[0]
		bi.halign = keep[1]
		bi.valign = keep[2]
		bi.draw_color = keep[3]
		bi.draw_alpha = keep[4]
		return
	var rec = bi.canvas
	var sp := int(pl.v.get("sprite_index", -1))
	var w := float(vm.spr_info[sp][1]) if sp >= 0 else 20.0
	var px := float(pl.v["x"])
	var py := float(pl.v["y"])
	if rec != null and rec.has_method("owner"):
		rec.owner(-900002, Vector2(px, py))
	_tag(px + w / 2.0, py - 14.0, lead_name)
	if rec != null and rec.has_method("owner"):
		rec.owner(-900003, Vector2(x, y))
	# Side by side, the second name goes up a row so the two don't run into each other.
	var oy := -14.0
	if absf(px - x) < 44.0 and absf(py - y) < 12.0:
		oy = -24.0
	_tag(x + w / 2.0, y + oy, other_name)
	bi.draw_font = keep[0]
	bi.halign = keep[1]
	bi.valign = keep[2]
	bi.draw_color = keep[3]
	bi.draw_alpha = keep[4]


func _tag(cx: float, ty: float, s: String) -> void:
	var bi = eng.bi
	var f := int(vm.consts.get("fnt_small", vm.consts.get("fnt_maintext", -1.0)))
	bi.draw_font = f
	bi.halign = 0
	bi.valign = 0
	var sc := 1.0
	var w: float = bi.text_width(s) * sc
	var lx := cx - w / 2.0
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		bi._draw_text(lx + o.x, ty + o.y, s, sc, sc, 0.0, 0, 1.0)
	bi._draw_text(lx, ty, s, sc, sc, 0.0, 16777215, 1.0)
