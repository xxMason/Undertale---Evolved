# A GameMaker: Studio 1.4 runtime for the parts of Undertale the battle engine needs.
# It runs the original game's code (extracted from the player's own copy, compiled by
# gml_compiler.gd) with GameMaker's semantics: instances, object inheritance, events in
# GameMaker's frame order, alarms, motion, collisions, with/other/global scoping,
# arrays and scripts. Built-in functions live in gml_builtins.gd.
#
# Measured behaviour copied from the real game (see docs/GODOT_PROTOTYPE.md):
#   positions, speeds and directions are single-precision floats;
#   bounding boxes round each edge separately, half to even.
extends RefCounted

const Compiler = preload("res://gml/gml_compiler.gd")
const C = preload("res://gml/gml_compiler.gd")
const Transpiler = preload("res://gml/gml_transpiler.gd")

# Event types (GameMaker 1.4 numbering)
const EV_CREATE := 0
const EV_DESTROY := 1
const EV_ALARM := 2
const EV_STEP := 3
const EV_COLLISION := 4
const EV_KEYBOARD := 5
const EV_OTHER := 7
const EV_DRAW := 8
const EV_KEYPRESS := 9
const EV_KEYRELEASE := 10

const SIG_NONE := 0
const SIG_BREAK := 1
const SIG_CONTINUE := 2
const SIG_EXIT := 3
const SIG_RETURN := 4

const NOONE := -4.0
const ALL := -3.0
const SELF := -1.0
const OTHER := -2.0
const GLOBAL := -5.0

var base := ""
var meta := {}
var compiler = Compiler.new()
var builtins       # gml_builtins.gd instance
var code_cache := {}     # code entry name -> compiled tree (or [] if missing)
var use_fast := true     # run code translated to GDScript (false: tree interpreter only)
var fast_cache := {}     # code entry name -> [script object, Callable] or [] if not translatable
var fast_failures: Array = []
var fast_src := {}       # code entry name -> generated GDScript (kept for tools)
var keep_src := false
var fast_refs := {}      # code entry name -> ["o:object", "s:script"] it refers to
var transpiler = Transpiler.new()
var consts := {}         # constant and asset names -> value
var script_code := {}    # script name -> code entry name
var script_by_index: Array = []
var obj_names: Array = []
var obj_index := {}      # object name -> index
var obj_parent: Array = []   # object index -> parent index or -1
var obj_events: Array = []   # object index -> {"type,sub": code}
var obj_sprite: Array = []
var obj_mask: Array = []
var obj_depth: Array = []
var obj_visible: Array = []
var obj_persistent: Array = []
var obj_solid: Array = []
var prof = null                  # name -> usec when profiling
var collision_targets: Array = []  # object index -> [target object indices], inherited included
var coll_log = null                # Array of "a>b" collision events this frame, when tracing hits
var step_no := 0                   # frames stepped so far
var event_watch = null             # debug menu inspector: the instance whose events are logged
var event_log: Array = []          # [step_no, code entry] of its last events
var alarm_log := false             # debugging: print alarms set to non-whole values
var sprite_names: Array = []
var sprite_index := {}
var spr_info: Array = []     # [frames, w, h, xo, yo, l, r, t, b, kind, masks]
var sound_names: Array = []
var sound_info: Array = []
var room_names: Array = []
var font_names: Array = []
var bg_names: Array = []
var paths: Array = []        # index -> [closed, smooth, precision, [[x, y, speed]...]] or null

var globals := {}
var instances: Array = []      # live instances, creation order
var by_id := {}
var next_id := 100001
var room := -1
var room_width := 640
var room_height := 480
var room_speed := 30
var pending_room := -1:
	set(v):
		pending_room = v
		pending_owner = ctx_owner    # whose room_goto it was (mp_rooms.gd moves only them)
var pending_owner := -1
# Called once during Draw, just before the first instance deeper in front than
# draw_hook_depth (the trace recorder's place in the real game's draw order).
var draw_hook := Callable()
var draw_hook_depth := -100000.0
# Co-op battles: a second SOUL (`scoped`) runs its events with the other player's keys and
# stats. scope_enter/scope_exit swap them in and out around any event whose self or other
# is that SOUL; while inside, reading obj_heart.x gives that SOUL. inst_keys: instance id ->
# keys object for its Keyboard / Key Press / Key Release events.
var scoped = null
var in_scope := false
var scope_enter := Callable()
var scope_exit := Callable()
var inst_keys := {}
# While dodging (set by coop_battle.gd): attacks that read "the SOUL" (obj_heart.x, ...) each
# get one of the two, by the id of the instance doing it, so both players get aimed at.
# aim_skip: objects that always mean the game's own SOUL (the battle's own bookkeeping).
var aim_split := false
var aim_skip := {}
var aim_obj := -1                # obj_heart, for a shared battle's aiming (_aim)
var _src_cache := {}
var party_name := Callable()        # the name a shared battle's HP bar shows (mp_battles.gd)
var party_draw := Callable()        # after the room's drawing, with several players (mp_battles.gd)
var draw_end_hook := Callable()     # after the room's drawing, before Draw GUI (co-op name tags)
# Players (docs/MULTIPLAYER.md stage 2, mp_players.gd). With owners_on, every instance may
# belong to a player (Inst.owner). An event of a player's instance, or one whose `other` is
# a player's instance (a door touched by them), runs in that player's context: owner_switch
# swaps their own globals in (input, HP, items, text...). Instances created in a player's
# context belong to them; an object a player talks to (scr_interact) is theirs until its
# talk ends. In a player's context, the objects in player_insts (their character) mean
# their own instance. ctx_owner is the player whose context is running, -1 for the world.
var owners_on := false
var ctx_owner := -1
var owner_switch := Callable()
var player_insts: Array = []     # player index -> {object index: Inst}
var claimed: Array = []          # instances claimed through scr_interact
# Private objects (text boxes, faces): each player only sees their own and the world's;
# the world sees its own and the primary player's (as in the one-player game).
var private_objs := {}           # object index -> true (children included)
var faded_objs := {}             # object index -> true: a player's own is drawn faded on the others' screens (SOULs)
var primary_owner := 0
# Per-player objects (the overworld menu): one instance in the room, but its events run once
# for each player in multi_players, in their context and with their own copy of its
# variables (Inst.pv), so several players can have it open at once.
var multi_objs := {}             # object index -> true
var gate_objs := {}              # object index -> true: story triggers that can wait for everyone
var party_on := false            # a battle several players share (mp_battles.gd): its state is everyone's
var scene_owner := -1            # the player whose story scene this world is playing: their text is everyone's
var event_gate := Callable()     # (instance, player) -> bool: may the trigger run now
var multi_players: Array = []    # player indices
# Drawing (stage 3): world objects whose Draw places things relative to the view (faders,
# text boxes, HUD) are "anchored": the recorder keeps the view they were drawn against, so on
# another player's screen they stay where they were on screen rather than in the room.
var anchored_objs := {}          # object index -> true
var _in_multi = null
var game_end_requested := false
var game_restart_requested := false
var ret_val = 0.0
var warned := {}
var log_lines: Array = []

# Current event context (for event_inherited and other).
var cur_self = null
var cur_other = null
var cur_event_obj := -1
var cur_event_type := -1
var cur_event_sub := -1


class Inst:
	var id := 0
	var obj := 0
	var owner := -1       # player index (see owners_on), -1 for none
	var pv = null         # per-player objects: player index -> their copy of v
	var v := {}
	var alarm: Array = []
	var dead := false
	var created := false
	var born := -1        # step_no of the frame it was created in
	var drawn := -1       # draw pass number it was last drawn in (see draw_frame)


func setup(extracted_dir: String) -> bool:
	base = extracted_dir
	var path := base.path_join("engine.json")
	if not FileAccess.file_exists(path):
		return false
	meta = JSON.parse_string(FileAccess.get_file_as_string(path))
	sprite_names = meta["sprite_names"]
	sound_names = meta["sound_names"]
	obj_names = meta["object_names"]
	room_names = meta["room_names"]
	font_names = meta["font_names"]
	bg_names = meta["background_names"]
	script_code = meta["script_code"]
	script_by_index = meta["script_names"]
	for i in sprite_names.size():
		if sprite_names[i] != null:
			consts[sprite_names[i]] = float(i)
			sprite_index[sprite_names[i]] = i
		var si = meta["sprites"].get(sprite_names[i]) if sprite_names[i] != null else null
		spr_info.append(si)
	for i in sound_names.size():
		if sound_names[i] != null:
			consts[sound_names[i]] = float(i)
		sound_info.append(meta["sounds"].get(sound_names[i]) if sound_names[i] != null else null)
	for i in room_names.size():
		if room_names[i] != null:
			consts[room_names[i]] = float(i)
	for i in font_names.size():
		if font_names[i] != null:
			consts[font_names[i]] = float(i)
	for i in bg_names.size():
		if bg_names[i] != null:
			consts[bg_names[i]] = float(i)
	for i in script_by_index.size():
		if script_by_index[i] != null:
			consts[script_by_index[i]] = float(i)
	var objs: Array = meta["objects"]
	for i in objs.size():
		var o: Dictionary = objs[i]
		obj_index[o["name"]] = i
		consts[o["name"]] = float(i)
	for i in objs.size():
		var o: Dictionary = objs[i]
		obj_parent.append(obj_index.get(o["parent"], -1) if o["parent"] != null else -1)
		obj_sprite.append(sprite_index.get(o["sprite"], -1) if o["sprite"] != null else -1)
		obj_mask.append(sprite_index.get(o["mask"], -1) if o["mask"] != null else -1)
		obj_depth.append(float(o["depth"]))
		obj_visible.append(int(o["visible"]) == 1)
		obj_persistent.append(int(o["persistent"]) == 1)
		obj_solid.append(int(o.get("solid", 0)) == 1)
		var ev := {}
		var targets: Array = []
		for e in o["events"]:
			ev["%d,%d" % [int(e[0]), int(e[1])]] = e[2]
			if int(e[0]) == EV_COLLISION:
				targets.append(int(e[1]))
		obj_events.append(ev)
		collision_targets.append(targets)
	# Collision events are inherited: a child with no collision event of its own still
	# collides through its parent's (Sans's bone walls and slam bones work this way).
	# A child's own event for the same target overrides the parent's; find_event picks it.
	var own: Array = collision_targets.duplicate(true)
	for i in objs.size():
		var all: Array = own[i].duplicate()
		var p: int = obj_parent[i]
		var guard := 0
		while p >= 0 and guard < 64:
			for t in own[p]:
				if not all.has(t):
					all.append(t)
			p = obj_parent[p]
			guard += 1
		# The runner checks collision events in ascending target-object order (measured:
		# a Moldbygg bullet touching both the SOUL (744) and the top border (760) on the
		# same frame hits the SOUL first; the data file lists the events descending).
		all.sort()
		collision_targets[i] = all
	var pn: Array = meta.get("path_names", [])
	for i in pn.size():
		if pn[i] != null:
			consts[pn[i]] = float(i)
		paths.append(meta.get("paths", {}).get(pn[i]) if pn[i] != null else null)
	_init_consts()
	return true


func _init_consts() -> void:
	var c := {
		"true": 1.0, "false": 0.0, "pi": PI, "noone": NOONE, "all": ALL, "self": SELF, "other": OTHER, "global": GLOBAL,
		"c_white": 16777215.0, "c_black": 0.0, "c_red": 255.0, "c_lime": 65280.0, "c_blue": 16711680.0, "c_yellow": 65535.0,
		"c_aqua": 16776960.0, "c_fuchsia": 16711935.0, "c_gray": 8421504.0, "c_grey": 8421504.0, "c_silver": 12632256.0,
		"c_dkgray": 4210752.0, "c_ltgray": 12632256.0, "c_maroon": 128.0, "c_navy": 8388608.0, "c_green": 32768.0,
		"c_olive": 32896.0, "c_purple": 8388736.0, "c_teal": 8421376.0, "c_orange": 4235519.0,
		"vk_nokey": 0.0, "vk_anykey": 1.0, "vk_left": 37.0, "vk_up": 38.0, "vk_right": 39.0, "vk_down": 40.0,
		"vk_enter": 13.0, "vk_escape": 27.0, "vk_space": 32.0, "vk_shift": 16.0, "vk_control": 17.0, "vk_alt": 18.0,
		"vk_backspace": 8.0, "vk_tab": 9.0, "vk_home": 36.0, "vk_end": 35.0, "vk_delete": 46.0, "vk_insert": 45.0,
		"vk_pageup": 33.0, "vk_pagedown": 34.0, "vk_f1": 112.0, "vk_f2": 113.0, "vk_f3": 114.0, "vk_f4": 115.0,
		"vk_f5": 116.0, "vk_f6": 117.0, "vk_f7": 118.0, "vk_f8": 119.0, "vk_f9": 120.0, "vk_f10": 121.0,
		"vk_numpad0": 96.0, "vk_lshift": 160.0, "vk_rshift": 161.0, "vk_lcontrol": 162.0, "vk_rcontrol": 163.0,
		"fa_left": 0.0, "fa_center": 1.0, "fa_right": 2.0, "fa_top": 0.0, "fa_middle": 1.0, "fa_bottom": 2.0,
		"bm_normal": 0.0, "bm_add": 1.0, "bm_max": 2.0, "bm_subtract": 3.0,
		"os_windows": 0.0, "os_macosx": 1.0, "os_linux": 6.0, "os_ps4": 14.0, "os_psvita": 13.0, "os_type": 0.0,
		"asset_object": 0.0, "asset_sprite": 1.0, "asset_sound": 2.0, "asset_room": 3.0, "asset_background": 4.0,
		"asset_path": 5.0, "asset_script": 6.0, "asset_font": 7.0, "asset_timeline": 8.0, "asset_unknown": -1.0,
		"gp_face1": 32769.0, "gp_face2": 32770.0, "gp_face3": 32771.0, "gp_face4": 32772.0,
		"gp_padu": 32781.0, "gp_padd": 32782.0, "gp_padl": 32783.0, "gp_padr": 32784.0,
		"gp_axislh": 32785.0, "gp_axislv": 32786.0, "mb_left": 1.0, "mb_right": 2.0, "mb_middle": 3.0,
		"ev_other": 7.0, "ev_user0": 10.0, "ev_step": 3.0, "ev_draw": 8.0, "ev_alarm": 2.0, "ev_create": 0.0,
		"pr_trianglelist": 4.0, "pr_trianglestrip": 5.0, "pr_linelist": 2.0, "pr_linestrip": 3.0, "pr_pointlist": 1.0,
		"application_surface": -10.0, "undefined": null, "path_action_stop": 0.0, "path_action_restart": 1.0, "path_action_continue": 2.0, "path_action_reverse": 3.0,
	}
	for k in c:
		consts[k] = c[k]


func vlog(msg: String) -> void:
	log_lines.append(msg)
	if log_lines.size() > 400:
		log_lines.remove_at(0)


func warn_once(key: String, msg: String) -> void:
	if not warned.has(key):
		warned[key] = true
		vlog("WARN " + msg)
		print("[gml] ", msg)


# ---------------------------------------------------------------- code

func get_code(name: String) -> Array:
	if code_cache.has(name):
		return code_cache[name]
	var path := base.path_join("code/" + name + ".gml")
	var tree: Array = []
	if FileAccess.file_exists(path):
		tree = compiler.compile(FileAccess.get_file_as_string(path))
		if compiler.error != "":
			warn_once("parse:" + name, "parse error in %s: %s" % [name, compiler.error])
			tree = []
	code_cache[name] = tree
	return tree


# The code entry translated to GDScript and loaded, or null (then the interpreter runs it).
func get_fast(name: String):
	var hit = fast_cache.get(name)
	if hit != null:
		return hit[1] if not hit.is_empty() else null
	# Pre-translated source from prepare-godot.ps1: only Godot's compile is left to do.
	var pre := base.path_join("gd/" + name + ".gd")
	if not keep_src and FileAccess.file_exists(pre):
		var psrc := FileAccess.get_file_as_string(pre)
		if psrc.begins_with(fast_stamp() + "\n") and not psrc.contains("exec_node("):
			return _load_fast(name, psrc, [])
	var tree := get_code(name)
	if tree.is_empty():
		fast_cache[name] = []
		return null
	if transpiler.consts.is_empty():
		transpiler.consts = consts
		transpiler.scripts = script_code
		transpiler.fn_methods = builtins.FN_METHODS
		transpiler.objects = obj_index
	var src: String = fast_stamp() + "\n" + transpiler.translate(tree)
	if transpiler.error != "":
		fast_failures.append(name + ": " + transpiler.error)
		fast_cache[name] = []
		return null
	if keep_src:
		fast_src[name] = src
		fast_refs[name] = transpiler.refs.keys()
	return _load_fast(name, src, transpiler.nodes.duplicate())


func _load_fast(name: String, src: String, nodes: Array):
	var gd := GDScript.new()
	gd.source_code = src
	if gd.reload() != OK:
		fast_failures.append(name + ": GDScript did not compile")
		if OS.get_cmdline_user_args().has("--dumpfail"):
			FileAccess.open("user://fail_" + name + ".gd", FileAccess.WRITE).store_string(src)
		fast_cache[name] = []
		return null
	var obj = gd.new()
	obj.nodes = nodes
	var c := Callable(obj, "run")
	fast_cache[name] = [obj, c]
	return c


# Compiles not-yet-loaded translated scripts for up to `budget_usec`, so they are ready
# before a battle needs them (called while the fight-select screen is idle).
var _warm_list: Array = []
var _warm_pos := 0


func warm_step(budget_usec: int) -> bool:
	if not use_fast:
		return true
	if _warm_list.is_empty() and _warm_pos == 0:
		var d := DirAccess.open(base.path_join("gd"))
		if d == null:
			_warm_pos = -1
			return true
		var first: Array = []
		var rest: Array = []
		for f in d.get_files():
			if not f.ends_with(".gd"):
				continue
			var n := f.get_basename()
			# The battle's own machinery first: controller, text, SOUL, box, buttons, scripts.
			if n.begins_with("gml_Script_") or n.contains("battlecontroller") or n.contains("writer") or n.contains("obj_heart") or n.contains("border") or n.contains("bt_") or n.contains("hpname"):
				first.append(n)
			else:
				rest.append(n)
		_warm_list = first + rest
	if _warm_pos < 0 or _warm_pos >= _warm_list.size():
		return true
	var t0 := Time.get_ticks_usec()
	while _warm_pos < _warm_list.size() and Time.get_ticks_usec() - t0 < budget_usec:
		var n: String = _warm_list[_warm_pos]
		_warm_pos += 1
		if not fast_cache.has(n):
			get_fast(n)
	return _warm_pos >= _warm_list.size()


func warm_progress() -> float:
	if _warm_list.is_empty():
		return 1.0
	return float(_warm_pos) / float(_warm_list.size())


# First line of every translation; saved translations with another stamp are redone
# (they would call built-in methods by names that may have changed).
var _stamp := ""


func fast_stamp() -> String:
	if _stamp == "":
		_stamp = "# ube-gd %d %d" % [Transpiler.VERSION, str(builtins.FN_METHODS).hash()]
	return _stamp


# Everything a battle can reach from the given objects: their events (and their parents'),
# the objects and scripts that code refers to, and so on. Compiles all of it now, so the
# fight does not stop to compile code the first time something new appears.
const CLOSURE_SKIP := ["scr_battlegroup", "textdata_en", "textdata_ja", "scr_text", "scr_gettext"]
# Objects whose own code is compiled but whose references are not followed: they reach
# most of the game (overworld, menus), not just the battle.
const CLOSURE_LEAF := ["obj_time"]


func precompile_from(objects: Array, budget_ms := 4000) -> int:
	if not use_fast:
		return 0
	if fast_refs.is_empty():
		var p := base.path_join("gd/_refs.json")
		if FileAccess.file_exists(p):
			var j = JSON.parse_string(FileAccess.get_file_as_string(p))
			if j is Dictionary:
				fast_refs = j
	var t0 := Time.get_ticks_msec()
	var seen_obj := {}
	var seen_code := {}
	var todo: Array = []
	for o in objects:
		todo.append("o:" + str(o))
	var compiled := 0
	while not todo.is_empty() and Time.get_ticks_msec() - t0 < budget_ms:
		var item: String = todo.pop_back()
		var codes: Array = []
		var leaf := false
		if item.begins_with("o:"):
			var on := item.substr(2)
			var oi := int(obj_index.get(on, -1)) if not on.is_valid_int() else int(on)
			leaf = on in CLOSURE_LEAF
			while oi >= 0 and not seen_obj.has(oi):
				seen_obj[oi] = true
				codes.append_array(obj_events[oi].values())
				oi = obj_parent[oi]
		else:
			var sn := item.substr(2)
			if sn in CLOSURE_SKIP:
				continue
			var cn: String = script_code.get(sn, "")
			if cn != "":
				codes.append(cn)
		for cn in codes:
			if seen_code.has(cn):
				continue
			seen_code[cn] = true
			if not fast_cache.has(cn):
				get_fast(cn)
				compiled += 1
			if not leaf:
				for r in fast_refs.get(cn, []):
					todo.append(r)
	return compiled


func exec_node(node: Array, ctx: Dictionary) -> int:
	return _exec(node, ctx)


func take_ret():
	var r = ret_val
	ret_val = 0.0
	return r


func run_code(name: String, inst, other, args: Array = []):
	if use_fast:
		var f = get_fast(name)
		if f != null:
			return f.call(self, builtins, {"self": inst, "other": other, "locals": {}, "args": args})
	var tree := get_code(name)
	if tree.is_empty():
		return 0.0
	var ctx := {"self": inst, "other": other, "locals": {}, "args": args}
	ret_val = 0.0
	_exec(tree, ctx)
	var r = ret_val
	ret_val = 0.0
	return r


func call_script(name: String, args: Array, ctx: Dictionary):
	var code: String = script_code.get(name, "")
	if code == "":
		return null
	if owners_on and ctx_owner >= 0 and name == "scr_interact" and ctx["self"] is Inst and ctx["self"].owner < 0:
		ctx["self"].owner = ctx_owner
		claimed.append(ctx["self"])
	if use_fast:
		var f = get_fast(code)
		if f != null:
			return f.call(self, builtins, {"self": ctx["self"], "other": ctx["other"], "locals": {}, "args": args})
	var tree := get_code(code)
	if tree.is_empty():
		return 0.0
	var sub := {"self": ctx["self"], "other": ctx["other"], "locals": {}, "args": args}
	var saved = ret_val
	ret_val = 0.0
	_exec(tree, sub)
	var r = ret_val
	ret_val = saved
	return r


# ---------------------------------------------------------------- instances

func is_child_of(obj: int, ancestor: int) -> bool:
	if obj == ancestor:
		return true
	var ck := obj * 65536 + ancestor
	var hit = _child_cache.get(ck)
	if hit != null:
		return hit
	var res := _is_child_of(obj, ancestor)
	_child_cache[ck] = res
	return res


func _is_child_of(obj: int, ancestor: int) -> bool:
	var o := obj
	var guard := 0
	while o >= 0 and guard < 32:
		if o == ancestor:
			return true
		o = obj_parent[o]
		guard += 1
	return false


func instance_create(x: float, y: float, obj: int, run_create := true) -> Inst:
	var inst := Inst.new()
	inst.id = next_id
	next_id += 1
	inst.born = step_no
	inst.obj = obj
	inst.alarm.resize(12)
	inst.alarm.fill(-1.0)
	var v: Dictionary = inst.v
	v["x"] = f32(x)
	v["y"] = f32(y)
	v["xstart"] = v["x"]
	v["ystart"] = v["y"]
	v["xprevious"] = v["x"]
	v["yprevious"] = v["y"]
	v["hspeed"] = 0.0
	v["vspeed"] = 0.0
	v["speed"] = 0.0
	v["direction"] = 0.0
	v["friction"] = 0.0
	v["gravity"] = 0.0
	v["gravity_direction"] = 270.0
	v["sprite_index"] = float(obj_sprite[obj])
	v["mask_index"] = float(obj_mask[obj])
	v["image_index"] = 0.0
	v["image_speed"] = 1.0
	v["image_xscale"] = 1.0
	v["image_yscale"] = 1.0
	v["image_angle"] = 0.0
	v["image_alpha"] = 1.0
	v["image_blend"] = 16777215.0
	v["depth"] = obj_depth[obj]
	v["visible"] = 1.0 if obj_visible[obj] else 0.0
	v["persistent"] = 1.0 if obj_persistent[obj] else 0.0
	v["solid"] = 1.0 if obj_solid[obj] else 0.0
	v["path_index"] = -1.0
	v["path_position"] = 0.0
	v["path_speed"] = 0.0
	inst.owner = ctx_owner if owners_on else -1
	_insert_by_depth(inst)
	by_id[inst.id] = inst
	inst_version += 1
	if run_create:
		perform_event(inst, EV_CREATE, 0, null)
	inst.created = true
	return inst


# The instance list is kept the way the 1.4 runner keeps it (measured with the trace
# scenario's with(all) order): sorted by depth, highest first, and an instance that is
# created or changes depth goes in front of the others at its depth. Every event (and
# drawing) runs in this order, so equal-depth instances run newest first.
#
# by_object(instances) is asked for many times a frame (every event pass, and the collision
# pass for each colliding instance), so the ordering of the live list is cached until an
# instance is created, removed or changes object, and is sorted natively on (object, id)
# keys. Callers only read the returned array.
var _bo_src: Array = []
var _bo_ver := -1
var _bo_n := -1
var _bo_out: Array = []


func by_object(list: Array) -> Array:
	var cached := is_same(list, instances)
	if cached and is_same(_bo_src, list) and _bo_ver == inst_version and _bo_n == list.size():
		return _bo_out
	var keys := PackedInt64Array()
	keys.resize(list.size())
	var at := {}
	for k in list.size():
		var i: Inst = list[k]
		var key := (i.obj << 32) | i.id
		keys[k] = key
		at[key] = i
	keys.sort()
	var out: Array = []
	out.resize(keys.size())
	for k in keys.size():
		out[k] = at[keys[k]]
	if cached:
		_bo_src = list
		_bo_ver = inst_version
		_bo_n = list.size()
		_bo_out = out
		_bo_runs = _make_runs(out)
	return out


# [start, end, object] for each object's stretch of a by_object list, so a pass can skip
# every instance of an object that has no handler for its event in one step.
var _bo_runs: Array = []


func runs_of(list: Array) -> Array:
	if is_same(list, _bo_out):
		return _bo_runs
	return _make_runs(list)


static func _make_runs(list: Array) -> Array:
	var runs: Array = []
	var start := 0
	for k in range(1, list.size() + 1):
		if k == list.size() or list[k].obj != list[start].obj:
			runs.append([start, k, list[start].obj])
			start = k
	return runs


# Runs one event for every instance in a by_object list, object by object, skipping objects
# without a handler. Stops once a room change is pending.
var obj_changed_step := -1   # step_no of the last instance_change


func _event_pass(list: Array, type: int, sub: int) -> void:
	for r in runs_of(list):
		var found := find_event(r[2], type, sub)
		if found.is_empty() and obj_changed_step != step_no:
			continue
		for k in range(r[0], r[1]):
			if pending_room != -1:
				return
			var i: Inst = list[k]
			if i.dead:
				continue
			if i.obj != r[2]:
				perform_event(i, type, sub, null)   # changed object earlier this frame
			elif not found.is_empty():
				_run_event(i, found[0], found[1], type, sub, null)


func _insert_by_depth(inst: Inst) -> void:
	# The list is always sorted by depth, highest first (depth only changes through
	# set_depth, which re-inserts), so the first place whose depth is <= d is found by
	# binary search: the same place a front-to-back scan finds.
	var d := float(inst.v["depth"])
	var lo := 0
	var hi := instances.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if float(instances[mid].v["depth"]) <= d:
			hi = mid
		else:
			lo = mid + 1
	instances.insert(lo, inst)


func set_depth(inst: Inst, d: float) -> void:
	if float(inst.v["depth"]) == d:
		return
	inst.v["depth"] = d
	var k := instances.find(inst)
	if k >= 0:
		instances.remove_at(k)
		_insert_by_depth(inst)
		inst_version += 1


func instance_destroy(inst: Inst) -> void:
	if inst == null or inst.dead:
		return
	inst.dead = true
	inst_version += 1
	perform_event(inst, EV_DESTROY, 0, null)


# Keyboard events of an instance that has its own keys (the co-op partner's SOUL).
func _own_keys(i: Inst, k) -> void:
	for code in k.held_list():
		if not i.dead and pending_room == -1:
			perform_event(i, EV_KEYBOARD, code, null)
	if not k.held_list().is_empty() and not i.dead:
		perform_event(i, EV_KEYBOARD, 1, null)
	for code in k.pressed_list():
		if not i.dead and pending_room == -1:
			perform_event(i, EV_KEYPRESS, code, null)
	for code in k.released_list():
		if not i.dead and pending_room == -1:
			perform_event(i, EV_KEYRELEASE, code, null)


func purge_dead() -> void:
	var keep: Array = []
	for i in instances:
		if i.dead:
			by_id.erase(i.id)
		else:
			keep.append(i)
	instances = keep


# Instances an id/object/keyword refers to (live only).
var inst_version := 0     # bumped whenever the set of live instances changes
var _resolve_cache := {}


func resolve(target, ctx: Dictionary) -> Array:
	if target is Inst:
		return [] if target.dead else [target]
	if target == null:
		return []
	var t := float(target)
	if t == SELF:
		return [ctx["self"]] if ctx["self"] != null else []
	if t == OTHER:
		return [ctx["other"]] if ctx["other"] != null else []
	if t == ALL:
		var r: Array = []
		for i in instances:
			if not i.dead:
				r.append(i)
		return r
	if t == NOONE or t < 0:
		return []
	var n := int(t)
	if n >= 100000:
		var inst = by_id.get(n)
		return [] if inst == null or inst.dead else [inst]
	if owners_on:
		if ctx_owner >= 0:
			var own = player_insts[ctx_owner].get(n)
			if own != null:
				return [] if own.dead else [own]
		if private_objs.has(n):
			var me := ctx_owner if ctx_owner >= 0 else primary_owner
			var mine: Array = []
			for i in instances:
				if not i.dead and is_child_of(i.obj, n) and (i.owner < 0 or i.owner == me):
					mine.append(i)
			return mine
	# Cached per object until an instance is created, destroyed or changes object.
	var hit = _resolve_cache.get(n)
	var out: Array
	if hit != null and hit[0] == inst_version:
		out = hit[1]
	else:
		out = []
		for i in instances:
			if not i.dead and is_child_of(i.obj, n):
				out.append(i)
		_resolve_cache[n] = [inst_version, out]
	# A player's code doesn't see what belongs to another player (their battle starting,
	# their fade, the sign they are reading): each acts as if alone.
	if owners_on and ctx_owner >= 0:
		for i in out:
			if i.owner >= 0 and i.owner != ctx_owner:
				return out.filter(func(x): return x.owner < 0 or x.owner == ctx_owner)
	return out


func first_of(target, ctx: Dictionary):
	# Reading object.var takes the oldest instance (measured: Aaron's
	# blt_muscbul.vspeed -= 0.02 gives every bullet the first bullet's speed).
	var r := resolve(target, ctx)
	if r.is_empty():
		return null
	if party_on and r.size() > 1 and ctx_owner < 0 and aim_obj >= 0 and (target is float or target is int) and int(target) == aim_obj:
		return _aim(r)
	if scoped != null and r.size() > 1 and r.has(scoped):
		if in_scope:
			return scoped
		if aim_split and cur_self != null and cur_self is Inst and int(cur_self.id) % 2 == 1 and not aim_skip.has(int(cur_self.obj)):
			return scoped
		var b2 = null
		for i in r:
			if i != scoped and (b2 == null or i.id < b2.id):
				b2 = i
		return b2
	var best = r[0]
	for i in r:
		if i.id < best.id:
			best = i
	return best


# A shared battle's SOULs (mp_battles.gd), read as obj_heart by the world's objects: the
# battle's own bookkeeping (aim_skip) means the SOUL of the player whose turn it is; anything
# else (a bullet aiming) one SOUL by its id, so attacks spread over the party.
func _aim(r: Array):
	var hs := r.duplicate()
	hs.sort_custom(func(a, b): return a.id < b.id)
	var me = cur_self
	if me is Inst and me.owner < 0 and not aim_skip.has(int(me.obj)):
		return hs[int(me.id) % hs.size()]
	for h in hs:
		if h.owner == primary_owner:
			return h
	return hs[0]


# Runs a piece of GML source (compiled once) as `inst`; co-op uses it for the Revive turn.
func run_source(src: String, inst = null):
	var tree = _src_cache.get(src)
	if tree == null:
		tree = compiler.compile(src)
		if compiler.error != "":
			push_error("run_source: " + compiler.error)
			tree = []
		_src_cache[src] = tree
	var ctx := {"self": inst, "other": inst, "locals": {}, "args": []}
	ret_val = 0.0
	_exec(tree, ctx)
	ret_val = 0.0


# ---------------------------------------------------------------- events

var _ev_cache := {}
var _child_cache := {}

func find_event(obj: int, type: int, sub: int) -> Array:
	# Returns [code_name, defining_object] walking up the parents (cached).
	var ck := (obj * 16 + type) * 65536 + sub
	var hit = _ev_cache.get(ck)
	if hit != null:
		return hit
	var res := _find_event(obj, type, sub)
	_ev_cache[ck] = res
	return res


func _find_event(obj: int, type: int, sub: int) -> Array:
	var o := obj
	var key := "%d,%d" % [type, sub]
	var guard := 0
	while o >= 0 and guard < 32:
		var ev: Dictionary = obj_events[o]
		if ev.has(key):
			return [ev[key], o]
		o = obj_parent[o]
		guard += 1
	return []


func perform_event(inst: Inst, type: int, sub: int, other) -> bool:
	var found := find_event(inst.obj, type, sub)
	if found.is_empty():
		return false
	_run_event(inst, found[0], found[1], type, sub, other)
	return true


func _run_event(inst: Inst, code: String, def_obj: int, type: int, sub: int, other) -> void:
	# A story scene touched by one player while others are elsewhere may wait for them
	# (mp_scenes.gd): its trigger does nothing until then.
	if type == EV_COLLISION and gate_objs.has(inst.obj) and owners_on and inst.owner < 0 and other is Inst and other.owner >= 0 and event_gate.is_valid():
		if not event_gate.call(inst, other.owner):
			return
	var pt := Time.get_ticks_usec() if prof != null else 0
	if event_watch != null and inst == event_watch:
		event_log.append([step_no, code])
		if event_log.size() > 60:
			event_log.pop_front()
	var s_self = cur_self
	var s_other = cur_other
	var s_obj := cur_event_obj
	var s_t := cur_event_type
	var s_s := cur_event_sub
	cur_self = inst
	cur_other = other
	cur_event_obj = def_obj
	cur_event_type = type
	cur_event_sub = sub
	var enter: bool = scoped != null and not in_scope and (inst == scoped or (other != null and other == scoped))
	if enter:
		in_scope = true
		scope_enter.call()
	# A player's instance (or one touched by a player's) runs in that player's context; an
	# unowned one keeps the context of whatever ran it (the world's, for the frame's passes).
	var oc := ctx_owner
	if owners_on and inst.owner < 0 and multi_objs.has(inst.obj) and _in_multi != inst:
		_run_multi(inst, code, other, type)
	else:
		var busy0 = null
		if owners_on:
			var o := inst.owner
			if o < 0 and other is Inst:
				o = other.owner
			if o >= 0 and o != oc:
				owner_switch.call(o)
			if inst.owner < 0 and ctx_owner >= 0:
				busy0 = globals.get("interact", 0.0)
		run_code(code, inst, other if other != null else inst)
		# A world object that just made a player busy (a hole they fell in, a trigger) is
		# theirs until that is over: its alarms and steps then act on that player.
		if busy0 != null and inst.owner < 0 and not inst.dead and float(busy0) == 0.0 and float(globals.get("interact", 0.0)) != 0.0:
			inst.owner = ctx_owner
			claimed.append(inst)
		if owners_on and ctx_owner != oc:
			owner_switch.call(oc)
	if enter:
		scope_exit.call()
		in_scope = false
	cur_self = s_self
	cur_other = s_other
	cur_event_obj = s_obj
	cur_event_type = s_t
	cur_event_sub = s_s
	if prof != null:
		prof["ev:" + code] = prof.get("ev:" + code, 0) + Time.get_ticks_usec() - pt


# A per-player object's event, once for each player with their own variables. Afterwards
# the instance shows the primary player's copy.
# Its drawing is recorded as one segment per player, private to them.
func _run_multi(inst: Inst, code: String, other, type := -1) -> void:
	var oc := ctx_owner
	var keep = _in_multi
	_in_multi = inst
	if inst.pv == null:
		inst.pv = {}
	var rec = builtins.canvas if type == EV_DRAW and builtins.canvas != null and builtins.canvas.has_method("owner") else null
	for p in multi_players:
		if inst.dead:
			break
		if not inst.pv.has(p):
			inst.pv[p] = inst.v.duplicate(true) if p != primary_owner else inst.v
		inst.v = inst.pv[p]
		if p != ctx_owner:
			owner_switch.call(p)
		if rec != null:
			rec.owner(-(inst.id * 8 + p + 1), Vector2(float(inst.v["x"]), float(inst.v["y"])), p, null)
		run_code(code, inst, other if other != null else inst)
		inst.pv[p] = inst.v
	if inst.pv.has(primary_owner):
		inst.v = inst.pv[primary_owner]
	if ctx_owner != oc:
		owner_switch.call(oc)
	_in_multi = keep


func event_inherited(ctx: Dictionary) -> void:
	if cur_event_obj < 0:
		return
	var parent: int = obj_parent[cur_event_obj]
	if parent < 0:
		return
	var found := find_event(parent, cur_event_type, cur_event_sub)
	if found.is_empty():
		return
	_run_event(ctx["self"], found[0], found[1], cur_event_type, cur_event_sub, ctx["other"])


# ---------------------------------------------------------------- variables

static var _f32buf := PackedFloat32Array([0.0])

# Alarms are whole numbers in the runner: a fraction is rounded to nearest (half to even)
# when stored. Traces: 18.83 fires on the 19th step, 20.28 on the 20th.
static func alarm_value(val) -> float:
	var x := float(val)
	var r := roundf(x)
	if absf(x - floorf(x)) == 0.5:
		r = 2.0 * roundf(x / 2.0)
	return r


# Reverses a list built last-to-first (translated calls; see gml_transpiler._call).
const EPS := 0.00001   # GameMaker 1.4's default math epsilon (math_set_epsilon)


static func rv(a: Array) -> Array:
	a.reverse()
	return a


static func f32(v: float) -> float:
	_f32buf[0] = v
	return _f32buf[0]


static func rne(v: float) -> int:
	var fl := floorf(v)
	var d := v - fl
	if d > 0.5:
		return int(fl) + 1
	if d < 0.5:
		return int(fl)
	return int(fl) if int(fl) % 2 == 0 else int(fl) + 1


func inst_get(inst: Inst, name: String):
	if inst == null:
		return 0.0
	var v: Dictionary = inst.v
	if v.has(name):
		return v[name]
	match name:
		"id":
			return float(inst.id)
		"object_index":
			return float(inst.obj)
		"image_number":
			var si = _spr(v["sprite_index"])
			return float(si[0]) if si != null else 0.0
		"sprite_width":
			var si = _spr(v["sprite_index"])
			return float(si[1]) * float(v["image_xscale"]) if si != null else 0.0
		"sprite_height":
			var si = _spr(v["sprite_index"])
			return float(si[2]) * float(v["image_yscale"]) if si != null else 0.0
		"sprite_xoffset":
			var si = _spr(v["sprite_index"])
			return float(si[3]) if si != null else 0.0
		"sprite_yoffset":
			var si = _spr(v["sprite_index"])
			return float(si[4]) if si != null else 0.0
		"bbox_left":
			return float(bbox(inst).position.x)
		"bbox_top":
			return float(bbox(inst).position.y)
		"bbox_right":
			return float(bbox(inst).end.x - 1)
		"bbox_bottom":
			return float(bbox(inst).end.y - 1)
		"alarm":
			return inst.alarm
	warn_once("var:" + obj_names[inst.obj] + "." + name, "read of unset variable %s.%s" % [obj_names[inst.obj], name])
	return 0.0


func inst_set(inst: Inst, name: String, val) -> void:
	if inst == null:
		return
	var v: Dictionary = inst.v
	match name:
		"x", "y", "xprevious", "yprevious":
			v[name] = f32(float(val))
		"speed":
			v["speed"] = f32(float(val))
			_sync_hv(v)
		"direction":
			v["direction"] = f32(fposmod(float(val), 360.0))
			_sync_hv(v)
		"hspeed", "vspeed":
			v[name] = f32(float(val))
			_sync_speed(v)
		"image_index", "image_speed", "image_xscale", "image_yscale", "image_angle", "image_alpha", "gravity", "friction":
			# Single precision in the 1.4 runner too; animation ends land on the same frame and
			# Moldsmal's squash (yscale += 0.01 until < 0.9) turns on the same step as the game.
			v[name] = f32(float(val))
		"depth":
			set_depth(inst, float(val))
		"alarm":
			pass
		_:
			v[name] = val


# Converting between direction/speed and hspeed/vspeed works as in the 1.4 runner, measured
# with ube_motion_probe (trace scenario): degrees become radians with a single-precision pi,
# rounded to single precision; cos/sin are single precision; and hspeed, vspeed and speed
# are snapped to the nearest whole number when within 0.0001 of it (direction 270.2455 at
# speed 7 gives vspeed exactly 7, and hspeed 0.03 with vspeed 7 reads back as speed 7).
# Gravity adds to hspeed/vspeed without snapping (heart shards on the game-over screen).
const PI_F32 := 3.1415927410125732


static func _snap(x: float) -> float:
	var r := roundf(x)
	return r if absf(x - r) < 0.0001 else x


func _sync_hv(v: Dictionary) -> void:
	var r := f32(float(v["direction"]) * PI_F32 / 180.0)
	var s := float(v["speed"])
	v["hspeed"] = f32(_snap(s * f32(cos(r))))
	v["vspeed"] = f32(_snap(-s * f32(sin(r))))


func _sync_speed(v: Dictionary) -> void:
	var h := float(v["hspeed"])
	var vs := float(v["vspeed"])
	v["speed"] = f32(_snap(f32(sqrt(f32(h * h + vs * vs)))))
	if h != 0.0 or vs != 0.0:
		var d := f32(atan2(-vs, h)) * 180.0 / PI_F32
		if d < 0.0:
			d += 360.0
		v["direction"] = f32(d)


func _spr(idx):
	var i := int(idx)
	if i < 0 or i >= spr_info.size():
		return null
	return spr_info[i]


# Bounding box in whole pixels (end exclusive). Each edge rounded half to even.
func bbox(inst: Inst) -> Rect2i:
	var v: Dictionary = inst.v
	var mi := int(v["mask_index"])
	if mi < 0:
		mi = int(v["sprite_index"])
	var si = _spr(mi)
	if si == null:
		return Rect2i(rne(v["x"]), rne(v["y"]), 0, 0)
	var x := float(v["x"])
	var y := float(v["y"])
	var sx := float(v["image_xscale"])
	var sy := float(v["image_yscale"])
	var ang := float(v["image_angle"])
	var l := float(si[5]) - float(si[3])
	var r := float(si[6]) + 1.0 - float(si[3])
	var t := float(si[7]) - float(si[4])
	var b := float(si[8]) + 1.0 - float(si[4])
	if ang == 0.0:
		# Measured with ube_coll_probe against the real runner: the edge of the mask's first
		# column (row) is rounded (half to even), and the other edge is
		# round(that + scaled size), so the box's size depends on where it starts: a 1.5 px
		# mask covers 1 px from an odd pixel and 2 from an even one; 16.5 px from 119 ends at
		# 135. Mirrored masks start from their other side the same way (yscale -0.75 at
		# y = 98.375: 94-94).
		# In doubles: at scale 1.6 (1.60000002) and y = 98.5 the edge 106.5000001 rounds to 107.
		var x0 := x + l * sx
		var x1 := x + r * sx
		var y0 := y + t * sy
		var y1 := y + b * sy
		var ax := rne(x0)
		var bx := rne(float(ax) + (x1 - x0))
		var ay := rne(y0)
		var by := rne(float(ay) + (y1 - y0))
		return Rect2i(mini(ax, bx), mini(ay, by), absi(bx - ax), absi(by - ay))
	var rad := deg_to_rad(-ang)
	var cs := cos(rad)
	var sn := sin(rad)
	var mnx := INF
	var mny := INF
	var mxx := -INF
	var mxy := -INF
	for c in [Vector2(l * sx, t * sy), Vector2(r * sx, t * sy), Vector2(l * sx, b * sy), Vector2(r * sx, b * sy)]:
		var px: float = x + c.x * cs - c.y * sn
		var py: float = y + c.x * sn + c.y * cs
		mnx = minf(mnx, px)
		mny = minf(mny, py)
		mxx = maxf(mxx, px)
		mxy = maxf(mxy, py)
	var L2 := rne(mnx)
	var T2 := rne(mny)
	return Rect2i(L2, T2, rne(mxx) - L2, rne(mxy) - T2)


# Does pixel (px, py) (world) hit inst's collision mask?
func _mask_hit(inst: Inst, px: int, py: int) -> bool:
	var v: Dictionary = inst.v
	var mi := int(v["mask_index"])
	if mi < 0:
		mi = int(v["sprite_index"])
	var si = _spr(mi)
	if si == null:
		return false
	var rect := int(si[9]) != 1
	var m := PackedByteArray()
	if not rect:
		# Rectangle masks are tested pixel by pixel like the others (rotated: the rotated
		# rectangle, so Glyde's spinning shots miss the SOUL at the box's corner; flipped:
		# a star drop at yscale -2 does not reach its bounding box's first row).
		m = builtins.mask_of(mi, int(float(v["image_index"])) if int(si[10]) > 1 else 0)
		if m.is_empty():
			return true
	var x := float(v["x"])
	var y := float(v["y"])
	var sx := float(v["image_xscale"])
	var sy := float(v["image_yscale"])
	# The mask sits on the position rounded to a whole pixel (half to even), and the world
	# pixel's corner (not its centre) is mapped into the mask; rotation is done in single
	# precision. All measured with ube_coll_probe against the real runner (1/8 px sweeps at
	# scales 1, 1.5, 2, -1, -2 and angles 0, 30, 45, 90, 200).
	var dx := float(px - rne(x))
	var dy := float(py - rne(y))
	var ang := float(v["image_angle"])
	if ang != 0.0:
		var rad := f32(deg_to_rad(f32(ang)))
		var cs := f32(cos(rad))
		var sn := f32(sin(rad))
		var rx := f32(f32(dx * cs) - f32(dy * sn))
		var ry := f32(f32(dx * sn) + f32(dy * cs))
		dx = rx
		dy = ry
	if sx == 0.0 or sy == 0.0:
		return false
	# The offset is multiplied by the single-precision reciprocal of the scale: 1/1.6 is
	# 0.625, so 8 px at scale 1.6 is column 5, while 1/0.6 is 1.66666663, so 3 px at
	# scale 0.6 is 4.99999988, column 4 (both measured: probe and Knight Knight's sun bullets).
	var lx := int(floorf(dx * f32(1.0 / sx) + float(si[3])))
	var ly := int(floorf(dy * f32(1.0 / sy) + float(si[4])))
	var w := int(si[1])
	var h := int(si[2])
	if rect:
		return lx >= int(si[5]) and lx <= int(si[6]) and ly >= int(si[7]) and ly <= int(si[8])
	if lx < 0 or ly < 0 or lx >= w or ly >= h:
		return false
	return m[ly * w + lx] == 1


func _precise(inst: Inst) -> bool:
	var mi := int(inst.v["mask_index"])
	if mi < 0:
		mi = int(inst.v["sprite_index"])
	var si = _spr(mi)
	return si != null and int(si[9]) == 1


func collide(a: Inst, b: Inst) -> bool:
	var ra := bbox(a)
	var rb := bbox(b)
	if ra.size.x <= 0 or ra.size.y <= 0 or rb.size.x <= 0 or rb.size.y <= 0:
		return false
	var r := ra.intersection(rb)
	if r.size.x <= 0 or r.size.y <= 0:
		return false
	# Two rectangle masks: the bounding boxes decide, even when one is rotated (measured
	# with ube_coll_probe: a rotated spr_crosszap meets the box border as its rotated box,
	# but meets the precise heart as the rotated rectangle).
	if not _precise(a) and not _precise(b):
		return true
	for py in range(r.position.y, r.end.y):
		for px in range(r.position.x, r.end.x):
			if _mask_hit(a, px, py) and _mask_hit(b, px, py):
				return true
	return false


# Bounding boxes only (GameMaker's non-precise checks).
func bbox_rect(a: Inst, rect: Rect2i) -> bool:
	var r := bbox(a).intersection(rect)
	return r.size.x > 0 and r.size.y > 0


# Whether the segment p0-p1 touches the instance: its bounding box, then (precise) its
# mask, stepping pixel by pixel only through the part of the line inside the box.
func collide_line(a: Inst, p0: Vector2, p1: Vector2, precise: bool) -> bool:
	var bb := bbox(a)
	if bb.size.x <= 0 or bb.size.y <= 0:
		return false
	var lo := Vector2(bb.position)
	var hi := Vector2(bb.end) - Vector2(1, 1)
	# Liang-Barsky clip of the segment to the closed box [lo, hi].
	var t0 := 0.0
	var t1 := 1.0
	var d := p1 - p0
	for axis in 2:
		var pd: float = d[axis]
		var lo_d: float = lo[axis] - p0[axis]
		var hi_d: float = hi[axis] - p0[axis]
		if absf(pd) < 0.000001:
			if lo_d > 0.0 or hi_d < 0.0:
				return false
		else:
			var ta := lo_d / pd
			var tb := hi_d / pd
			if ta > tb:
				var sw := ta
				ta = tb
				tb = sw
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return false
	if not precise:
		return true
	var q0 := p0 + d * t0
	var q1 := p0 + d * t1
	var steps := maxi(1, int(ceilf(q0.distance_to(q1))))
	for k in steps + 1:
		var q := q0.lerp(q1, float(k) / steps)
		if _mask_hit(a, int(floorf(q.x)), int(floorf(q.y))):
			return true
	return false


func collide_rect(a: Inst, rect: Rect2i) -> bool:
	var ra := bbox(a)
	var r := ra.intersection(rect)
	if r.size.x <= 0 or r.size.y <= 0:
		return false
	# An unrotated rectangle mask is its bounding box for point and rectangle checks
	# (measured: collision_point on a scaled spr_sunbullet is true exactly on its box).
	if not _precise(a) and float(a.v["image_angle"]) == 0.0:
		return true
	for py in range(r.position.y, r.end.y):
		for px in range(r.position.x, r.end.x):
			if _mask_hit(a, px, py):
				return true
	return false


# ---------------------------------------------------------------- paths
# Paths are followed at path_speed pixels per step (scaled by each point's speed / 100).
# Smooth paths are subdivided the way GameMaker does (corner-cutting between the
# midpoints of neighbouring segments, `precision` levels deep).

var _path_cache := {}

func _path_points(p: int) -> Array:
	if p < 0 or p >= paths.size() or paths[p] == null:
		return []
	if _path_cache.has(p):
		return _path_cache[p]
	var src: Array = paths[p][3]
	var closed := int(paths[p][0]) == 1
	var pts: Array = []
	if int(paths[p][1]) == 1 and src.size() >= 3:
		var n := src.size()
		var prec := int(paths[p][2])
		if not closed:
			pts.append(src[0])
		var count := n if closed else n - 2
		for i in count:
			var a: Array = src[i % n]
			var b: Array = src[(i + 1) % n]
			var c: Array = src[(i + 2) % n]
			_path_piece(pts, prec, [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, (a[2] + b[2]) / 2.0], b, [(b[0] + c[0]) / 2.0, (b[1] + c[1]) / 2.0, (b[2] + c[2]) / 2.0])
		if not closed:
			pts.append(src[n - 1])
		elif not pts.is_empty():
			pts.append(pts[0])
	else:
		pts = src.duplicate()
		if closed and not pts.is_empty():
			pts.append(pts[0])
	_path_cache[p] = pts
	return pts


func _path_piece(out: Array, depth: int, p1: Array, p2: Array, p3: Array) -> void:
	if depth == 0:
		return
	var m := [(p1[0] + 2.0 * p2[0] + p3[0]) / 4.0, (p1[1] + 2.0 * p2[1] + p3[1]) / 4.0, (p1[2] + 2.0 * p2[2] + p3[2]) / 4.0]
	var far: bool = (p1[0] - p3[0]) * (p1[0] - p3[0]) + (p1[1] - p3[1]) * (p1[1] - p3[1]) > 16.0
	if far:
		_path_piece(out, depth - 1, p1, [(p2[0] + p1[0]) / 2.0, (p2[1] + p1[1]) / 2.0, (p2[2] + p1[2]) / 2.0], m)
	out.append(m)
	if far:
		_path_piece(out, depth - 1, m, [(p3[0] + p2[0]) / 2.0, (p3[1] + p2[1]) / 2.0, (p3[2] + p2[2]) / 2.0], p3)


func path_length(p: int) -> float:
	var pts := _path_points(p)
	var total := 0.0
	for k in range(1, pts.size()):
		total += Vector2(pts[k][0], pts[k][1]).distance_to(Vector2(pts[k - 1][0], pts[k - 1][1]))
	return total


# [x, y, speed factor] at position t (0..1) along the path.
func path_point(p: int, t: float) -> Array:
	var pts := _path_points(p)
	if pts.is_empty():
		return [0.0, 0.0, 100.0]
	if pts.size() == 1:
		return [float(pts[0][0]), float(pts[0][1]), float(pts[0][2])]
	var total := path_length(p)
	var want := clampf(t, 0.0, 1.0) * total
	var acc := 0.0
	for k in range(1, pts.size()):
		var a := Vector2(pts[k - 1][0], pts[k - 1][1])
		var b := Vector2(pts[k][0], pts[k][1])
		var seg := a.distance_to(b)
		if acc + seg >= want or k == pts.size() - 1:
			var f := (want - acc) / seg if seg > 0.0 else 0.0
			var q := a.lerp(b, clampf(f, 0.0, 1.0))
			return [q.x, q.y, lerpf(float(pts[k - 1][2]), float(pts[k][2]), clampf(f, 0.0, 1.0))]
		acc += seg
	var last: Array = pts[pts.size() - 1]
	return [float(last[0]), float(last[1]), float(last[2])]


func path_start(inst: Inst, p: int, speed: float, endaction: int, absolute: bool) -> void:
	if inst == null:
		return
	var v := inst.v
	v["path_index"] = float(p)
	v["path_speed"] = speed
	v["path_position"] = 0.0
	v["path_endaction"] = float(endaction)
	var p0 := path_point(p, 0.0)
	if absolute:
		v["path_xoff"] = 0.0
		v["path_yoff"] = 0.0
	else:
		v["path_xoff"] = float(v["x"]) - p0[0]
		v["path_yoff"] = float(v["y"]) - p0[1]
	inst_set(inst, "x", float(v["path_xoff"]) + p0[0])
	inst_set(inst, "y", float(v["path_yoff"]) + p0[1])


func _path_step(inst: Inst) -> void:
	var v := inst.v
	var p := int(float(v["path_index"]))
	var length := path_length(p)
	if length <= 0.0:
		return
	var here := path_point(p, float(v["path_position"]))
	var spd := float(v["path_speed"])
	var pos: float = float(v["path_position"]) + spd * (float(here[2]) / 100.0) / length
	var endaction := int(float(v.get("path_endaction", 0.0)))
	# A path ends only when it is moved past an end, so a path started at speed 0 (an NPC
	# waiting for the player, like Toriel in the Ruins) stays on it.
	if (spd > 0.0 and pos >= 1.0) or (spd < 0.0 and pos <= 0.0):
		match endaction:
			0:
				pos = clampf(pos, 0.0, 1.0)
				v["path_index"] = -1.0
			1:
				pos = fposmod(pos, 1.0)
			2:
				var e1 := path_point(p, 1.0)
				var e0 := path_point(p, 0.0)
				v["path_xoff"] = float(v["path_xoff"]) + (e1[0] - e0[0])
				v["path_yoff"] = float(v["path_yoff"]) + (e1[1] - e0[1])
				pos = fposmod(pos, 1.0)
			3:
				v["path_speed"] = -float(v["path_speed"])
				pos = clampf(pos, 0.0, 1.0)
	v["path_position"] = pos
	var q := path_point(p, pos)
	var ox := float(v["x"])
	var oy := float(v["y"])
	inst_set(inst, "x", float(v["path_xoff"]) + q[0])
	inst_set(inst, "y", float(v["path_yoff"]) + q[1])
	# The runner turns an instance on a path to face the way it moved (Undertale's NPCs pick
	# their walking sprite from direction: Toriel in the Ruins).
	var nx := float(v["x"])
	var ny := float(v["y"])
	if nx != ox or ny != oy:
		v["direction"] = f32(fposmod(rad_to_deg(atan2(-(ny - oy), nx - ox)), 360.0))


# ---------------------------------------------------------------- frame

func step_frame(keys) -> void:
	# keys: object with held(code), pressed(code), released(code) and lists.
	# Once a room change is pending (room_goto), no further events run this frame: measured
	# at game over, where obj_battlecontroller's Step calls room_goto and obj_heart's Step
	# (later in object order) does not count invincibility down that frame.
	step_no += 1
	_mark("")
	# xprevious/yprevious hold the position at the start of the step, before any event
	# runs, so code that moves an instance in Step (the SOUL does) counts as movement.
	# Blue attacks rely on this: they hurt only when x differs from xprevious.
	for i in instances:
		var pv: Dictionary = i.v
		pv["xprevious"] = pv["x"]
		pv["yprevious"] = pv["y"]
	# Every event except Draw runs object by object in object-index order (each object's
	# own instances in creation order), not in the depth-sorted list; measured with the
	# trace scenario (Froggit: obj_targetchoice's Step runs before obj_target's).
	var list := by_object(instances)
	_event_pass(list, EV_STEP, 1)
	_mark("#begin_step")
	# Animation (image_index += image_speed, Animation End) runs after Begin Step and before
	# the alarms, not at the end of the frame: measured with the trace scenario (vaporize dust,
	# obj_whtpxlgrav dies of Animation End before obj_blkpxltall's Step checks it, same frame).
	for i in by_object(instances):
		if i.dead or pending_room != -1:
			continue
		var v: Dictionary = i.v
		var sp := float(v["image_speed"])
		# An instance created earlier in this frame (Begin Step) keeps image_index for now.
		if sp != 0.0 and i.born != step_no:
			var si = _spr(v["sprite_index"])
			var n := float(si[0]) if si != null else 0.0
			var idx := f32(f32(float(v["image_index"])) + f32(sp))
			if n > 0.0 and idx >= n:
				idx = f32(idx - n)
				v["image_index"] = idx
				perform_event(i, EV_OTHER, 7, null)
			elif n > 0.0 and idx < 0.0:
				idx += n
				v["image_index"] = idx
				perform_event(i, EV_OTHER, 7, null)
			else:
				v["image_index"] = idx
	_mark("#animation")
	# Alarms: alarm 0 for everyone, then alarm 1, ... An alarm only counts down when the
	# object (or a parent) has that alarm event, as in the runner.
	var runs := runs_of(list)
	for a in 12:
		for r in runs:
			if obj_changed_step != step_no and find_event(r[2], EV_ALARM, a).is_empty():
				continue
			for k in range(r[0], r[1]):
				var i: Inst = list[k]
				if i.dead or pending_room != -1:
					continue
				var t := float(i.alarm[a])
				if t > 0.0 and not find_event(i.obj, EV_ALARM, a).is_empty():
					t -= 1.0
					i.alarm[a] = t
					if t <= 0.0:
						i.alarm[a] = -1.0
						perform_event(i, EV_ALARM, a, null)
	_mark("#alarms")
	# Keyboard, key press, key release events.
	# The key lists are read once; an event that runs may clear keys, so after one has run
	# they are read again before each use, as before.
	var held: Array = keys.held_list()
	var pressed: Array = keys.pressed_list()
	var released: Array = keys.released_list()
	var fired := false
	for i in list:
		if i.dead or pending_room != -1:
			continue
		if not inst_keys.is_empty() and inst_keys.has(i.id):
			_own_keys(i, inst_keys[i.id])
			continue
		if not fired and held.is_empty() and pressed.is_empty() and released.is_empty():
			if inst_keys.is_empty():
				break
			continue
		if fired:
			held = keys.held_list()
		for code in held:
			if not i.dead and pending_room == -1:
				fired = perform_event(i, EV_KEYBOARD, code, null) or fired
		if fired:
			held = keys.held_list()
		if not held.is_empty() and not i.dead:
			fired = perform_event(i, EV_KEYBOARD, 1, null) or fired
		if fired:
			pressed = keys.pressed_list()
		for code in pressed:
			if not i.dead and pending_room == -1:
				fired = perform_event(i, EV_KEYPRESS, code, null) or fired
		if fired:
			released = keys.released_list()
		for code in released:
			if not i.dead and pending_room == -1:
				fired = perform_event(i, EV_KEYRELEASE, code, null) or fired
	list = by_object(instances)
	_event_pass(list, EV_STEP, 0)
	_mark("#step")
	# Motion.
	for i in instances:
		if i.dead or pending_room != -1:
			continue
		var v: Dictionary = i.v
		var fr := float(v["friction"])
		if fr != 0.0:
			var sp := float(v["speed"])
			if sp > 0.0:
				inst_set(i, "speed", maxf(0.0, sp - fr))
			elif sp < 0.0:
				inst_set(i, "speed", minf(0.0, sp + fr))
		var gr := float(v["gravity"])
		if gr != 0.0:
			# Radians rounded to single precision (with the exact pi here): straight-down
			# gravity nudges hspeed by about 2e-9 a step, as in the game.
			var gd := f32(float(v["gravity_direction"]) * PI / 180.0)
			v["hspeed"] = f32(float(v["hspeed"]) + gr * cos(gd))
			v["vspeed"] = f32(float(v["vspeed"]) - gr * sin(gd))
			_sync_speed(v)
		if float(v.get("path_index", -1.0)) >= 0.0:
			_path_step(i)
		var h := float(v["hspeed"])
		var vs := float(v["vspeed"])
		if h != 0.0:
			v["x"] = f32(float(v["x"]) + h)
		if vs != 0.0:
			v["y"] = f32(float(v["y"]) + vs)
	_mark("#motion")
	# Outside Room (Other 0): every step the instance's box lies entirely outside the room.
	var olist := by_object(instances)
	for r in runs_of(olist):
		if obj_changed_step != step_no and find_event(r[2], EV_OTHER, 0).is_empty():
			continue
		for k in range(r[0], r[1]):
			_outside_check(olist[k])
	_mark("#outside")
	# Collisions (objects without collision events are skipped as a whole).
	list = by_object(instances)
	for r in runs_of(list):
		if obj_changed_step != step_no and (collision_targets[r[2]] as Array).is_empty():
			continue
		for k in range(r[0], r[1]):
			var i: Inst = list[k]
			if i.dead or pending_room != -1:
				continue
			for target in collision_targets[i.obj]:
				_collision_pass(i, int(target))
	_mark("#collisions")
	# End Step.
	list = by_object(instances)
	_event_pass(list, EV_STEP, 2)
	purge_dead()
	_mark("#end_step")


func _outside_check(i: Inst) -> void:
	if i.dead or pending_room != -1 or find_event(i.obj, EV_OTHER, 0).is_empty():
		return
	var bb := bbox(i)
	var right := bb.end.x - 1 if bb.size.x > 0 else bb.position.x
	var bottom := bb.end.y - 1 if bb.size.y > 0 else bb.position.y
	if right < 0 or bb.position.x > room_width or bottom < 0 or bb.position.y > room_height:
		perform_event(i, EV_OTHER, 0, null)


# Time since the previous mark, summed per phase when profiling (--prof).
var _mark_t := 0


func _mark(phase: String) -> void:
	if prof == null:
		return
	var now := Time.get_ticks_usec()
	if phase != "":
		prof[phase] = prof.get(phase, 0) + now - _mark_t
	_mark_t = now


# Instances of obj (or its children) in by_object order, cached like by_object itself:
# every bullet's collision check with the SOUL would otherwise walk the whole list.
var _io_cache := {}
var _io_key: Array = []


func _instances_of(obj: int) -> Array:
	var all := by_object(instances)
	if _io_key.size() != 1 or not is_same(_io_key[0], all):
		_io_cache = {}
		_io_key = [all]
	var hit = _io_cache.get(obj)
	if hit != null:
		return hit
	var out: Array = []
	for o in all:
		if is_child_of(o.obj, obj):
			out.append(o)
	_io_cache[obj] = out
	return out


func _collision_pass(inst: Inst, target_obj: int) -> void:
	# The event defined for target_obj fires for every live instance of it (or its
	# children) that overlaps inst.
	var found := find_event(inst.obj, EV_COLLISION, target_obj)
	if found.is_empty():
		return
	for o in _instances_of(target_obj):
		if inst.dead:
			return
		if o == inst or o.dead:
			continue
		if collide(inst, o):
			if coll_log != null:
				coll_log.append("%s>%s" % [obj_names[inst.obj], obj_names[o.obj]])
				if OS.has_environment("UBE_COLLDBG"):
					print("COLLDBG %s x=%s y=%s sx=%s sy=%s ang=%s box=%s | %s box=%s" % [obj_names[inst.obj], inst.v["x"], inst.v["y"], inst.v["image_xscale"], inst.v["image_yscale"], inst.v["image_angle"], bbox(inst), obj_names[o.obj], bbox(o)])
			# With a solid instance on either side, the runner first puts both back where
			# they were at the start of the step, runs the event, then lets their speed move
			# them again unless that collides once more. (Undertale's push rocks are solid:
			# their event moves the rock and the player by 3, so the player can't walk into
			# or through them.)
			var solid := float(inst.v.get("solid", 0.0)) >= 0.5 or float(o.v.get("solid", 0.0)) >= 0.5
			if solid:
				_to_previous(inst)
				_to_previous(o)
			_run_event(inst, found[0], found[1], EV_COLLISION, target_obj, o)
			if solid and not inst.dead and not o.dead:
				for a in [inst, o]:
					var hs := float(a.v.get("hspeed", 0.0))
					var vs := float(a.v.get("vspeed", 0.0))
					if hs != 0.0 or vs != 0.0:
						inst_set(a, "x", float(a.v["x"]) + hs)
						inst_set(a, "y", float(a.v["y"]) + vs)
						if collide(inst, o):
							_to_previous(a)


func _to_previous(a: Inst) -> void:
	inst_set(a, "x", float(a.v["xprevious"]))
	inst_set(a, "y", float(a.v["yprevious"]))


var _draw_pass := 0


func draw_frame() -> void:
	# A shared battle (mp_battles.gd): the battle's HP bar names the player whose turn it is.
	var name_keep = null
	if party_on and owners_on and party_name.is_valid():
		name_keep = globals.get("charname", "")
		globals["charname"] = party_name.call()
	_draw_frame()
	if name_keep != null:
		globals["charname"] = name_keep


func _draw_frame() -> void:
	# The instance list is already in drawing order (deepest first, see _insert_by_depth).
	# The live list is walked, as the runner does: an instance created during a Draw event
	# at a later place in the list (lower depth) is drawn in the same frame (Sans's Gaster
	# Blasters, created in his body's Draw at depth -1, take their first Draw step at once).
	_draw_pass += 1
	var pass_no := _draw_pass
	var k := 0
	var hook := draw_hook
	var rec = builtins.canvas if builtins.canvas != null and builtins.canvas.has_method("owner") else null
	# Rooms: the background colour and back layers first, then tiles among the instances by
	# depth (a tile goes before instances of the same depth), then the front layers.
	var tl: Array = builtins.sorted_tiles()
	var ti := 0
	var room_draw: bool = builtins.save_dir != ""
	var seg := -1     # the room's own drawing (tiles, layers) as recorder segments -1, -2, ...
	if room_draw:
		if rec != null:
			rec.owner(seg, Vector2.ZERO)
			seg -= 1
		builtins.draw_backgrounds(false)
	while k < instances.size():
		var i: Inst = instances[k]
		k += 1
		if i.drawn == pass_no:
			continue
		if ti < tl.size() and float(tl[ti][8]) >= float(i.v["depth"]):
			if rec != null:
				rec.owner(seg, Vector2.ZERO)
				seg -= 1
			ti = _draw_tiles_until(tl, ti, float(i.v["depth"]), rec)
		if hook.is_valid() and float(i.v["depth"]) < draw_hook_depth:
			hook.call()
			hook = Callable()
		i.drawn = pass_no
		if i.dead or float(i.v["visible"]) < 0.5:
			continue
		if rec != null:
			if owners_on:
				var anchor = null
				if i.owner < 0 and anchored_objs.has(i.obj):
					anchor = Vector2(float(builtins.view_xview[0]), float(builtins.view_yview[0]))
				rec.owner(i.id, Vector2(float(i.v["x"]), float(i.v["y"])), i.owner if (i.owner >= 0 and i.owner != scene_owner and private_objs.has(i.obj)) else -1, anchor,
					i.owner if (i.owner >= 0 and faded_objs.has(i.obj)) else -1)
			else:
				rec.owner(i.id, Vector2(float(i.v["x"]), float(i.v["y"])))
		var n0 := instances.size()
		if not perform_event(i, EV_DRAW, 0, null):
			builtins.draw_self(i)
		if instances.size() != n0 or k > instances.size() or instances[k - 1] != i:
			k = instances.find(i) + 1
	if hook.is_valid():
		hook.call()
	if ti < tl.size() or room_draw:
		if rec != null:
			rec.owner(seg, Vector2.ZERO)
			seg -= 1
		ti = _draw_tiles_until(tl, ti, -INF, rec)
		if room_draw:
			builtins.draw_backgrounds(true)
	if draw_end_hook.is_valid():
		draw_end_hook.call()
	if party_draw.is_valid() and owners_on:
		party_draw.call()
	if builtins.canvas != null and builtins.canvas.has_method("gui_begin"):
		builtins.canvas.gui_begin()
	var list: Array = instances.duplicate()
	for i in list:
		if not i.dead and float(i.v["visible"]) >= 0.5:
			perform_event(i, EV_DRAW, 64, null)


# ---------------------------------------------------------------- interpreter

func truthy(v) -> bool:
	if v is float or v is int:
		return float(v) > 0.5
	if v is bool:
		return v
	return false


func _exec(node: Array, ctx: Dictionary) -> int:
	match int(node[0]):
		C.S_BLOCK:
			for s in node[1]:
				var sig := _exec(s, ctx)
				if sig != SIG_NONE:
					return sig
			return SIG_NONE
		C.S_EXPR:
			_eval(node[1], ctx)
			return SIG_NONE
		C.S_ASSIGN:
			_assign(node[1], node[2], node[3], ctx)
			return SIG_NONE
		C.S_INCDEC:
			var cur = _eval(node[1], ctx)
			_store(node[1], float(cur) + float(node[2]), ctx)
			return SIG_NONE
		C.S_VAR:
			var loc: Dictionary = ctx["locals"]
			for d in node[1]:
				loc[d[0]] = _eval(d[1], ctx) if d[1] != null else 0.0
			return SIG_NONE
		C.S_IF:
			if truthy(_eval(node[1], ctx)):
				return _exec(node[2], ctx)
			elif node[3] != null:
				return _exec(node[3], ctx)
			return SIG_NONE
		C.S_WHILE:
			var guard := 0
			while truthy(_eval(node[1], ctx)):
				var sig := _exec(node[2], ctx)
				if sig == SIG_BREAK:
					break
				if sig == SIG_EXIT or sig == SIG_RETURN:
					return sig
				guard += 1
				if guard > 200000:
					warn_once("loop", "while loop limit hit")
					break
			return SIG_NONE
		C.S_DO:
			var guard := 0
			while true:
				var sig := _exec(node[1], ctx)
				if sig == SIG_BREAK:
					break
				if sig == SIG_EXIT or sig == SIG_RETURN:
					return sig
				if truthy(_eval(node[2], ctx)):
					break
				guard += 1
				if guard > 200000:
					warn_once("loop", "do loop limit hit")
					break
			return SIG_NONE
		C.S_FOR:
			_exec(node[1], ctx)
			var guard := 0
			while truthy(_eval(node[2], ctx)):
				var sig := _exec(node[4], ctx)
				if sig == SIG_BREAK:
					break
				if sig == SIG_EXIT or sig == SIG_RETURN:
					return sig
				_exec(node[3], ctx)
				guard += 1
				if guard > 200000:
					warn_once("loop", "for loop limit hit")
					break
			return SIG_NONE
		C.S_REPEAT:
			var n := int(float(_eval(node[1], ctx)))
			for k in maxi(n, 0):
				var sig := _exec(node[2], ctx)
				if sig == SIG_BREAK:
					break
				if sig == SIG_EXIT or sig == SIG_RETURN:
					return sig
			return SIG_NONE
		C.S_WITH:
			var targets := resolve(_eval(node[1], ctx), ctx)
			var s_self = ctx["self"]
			var s_other = ctx["other"]
			var result := SIG_NONE
			for t in targets:
				if t.dead:
					continue
				ctx["other"] = s_self
				ctx["self"] = t
				var sig := _exec(node[2], ctx)
				if sig == SIG_BREAK:
					break
				if sig == SIG_EXIT or sig == SIG_RETURN:
					result = sig
					break
			ctx["self"] = s_self
			ctx["other"] = s_other
			return result
		C.S_SWITCH:
			var val = _eval(node[1], ctx)
			var hit := false
			for c in node[2]:
				if not hit:
					if c[0] == null:
						continue
					if not _eq(val, _eval(c[0], ctx)):
						continue
					hit = true
				for s in c[1]:
					var sig := _exec(s, ctx)
					if sig == SIG_BREAK:
						return SIG_NONE
					if sig != SIG_NONE:
						return sig
			if not hit:
				# default case
				var run := false
				for c in node[2]:
					if c[0] == null:
						run = true
					if run:
						for s in c[1]:
							var sig := _exec(s, ctx)
							if sig == SIG_BREAK:
								return SIG_NONE
							if sig != SIG_NONE:
								return sig
			return SIG_NONE
		C.S_BREAK:
			return SIG_BREAK
		C.S_CONTINUE:
			return SIG_CONTINUE
		C.S_EXIT:
			return SIG_EXIT
		C.S_RETURN:
			ret_val = _eval(node[1], ctx) if node[1] != null else 0.0
			return SIG_RETURN
	return SIG_NONE


func _eq(a, b) -> bool:
	if (a is String) != (b is String):
		return false
	if a is String:
		return a == b
	if a == null or b == null:
		return a == b
	return absf(float(a) - float(b)) < EPS


func _eval(node: Array, ctx: Dictionary):
	match int(node[0]):
		C.E_NUM:
			return node[1]
		C.E_STR:
			return node[1]
		C.E_IDENT:
			return _get_ident(node[1], ctx)
		C.E_MEMBER:
			var tgt = _eval(node[1], ctx)
			var name: String = node[2]
			if tgt is float and float(tgt) == GLOBAL:
				return globals.get(name, 0.0)
			var inst = first_of(tgt, ctx)
			if inst == null:
				warn_once("noinst:" + name, "read of %s on a missing instance" % name)
				return 0.0
			return inst_get(inst, name)
		C.E_INDEX:
			var arr = _container_get(node[1], ctx)
			var idx: Array = node[2]
			if arr is Array:
				var a := int(float(_eval(idx[0], ctx)))
				if idx.size() == 1:
					# alarm[] is a flat array; other arrays are rows (1D = row 0).
					if arr.size() > 0 and not (arr[0] is Array):
						return arr[a] if a >= 0 and a < arr.size() else 0.0
					var row0 = arr[0] if arr.size() > 0 else []
					return row0[a] if a >= 0 and a < row0.size() else 0.0
				var b := int(float(_eval(idx[1], ctx)))
				if a >= 0 and a < arr.size() and arr[a] is Array and b >= 0 and b < arr[a].size():
					return arr[a][b]
				return 0.0
			return 0.0
		C.E_CALL:
			# Arguments are evaluated last to first, as the 1.4 runner pushes them (Mad Dummy:
			# instance_create(x + random(a), y + random(10), ...) draws y's number first).
			var src: Array = node[2]
			var args: Array = []
			args.resize(src.size())
			for k in range(src.size() - 1, -1, -1):
				args[k] = _eval(src[k], ctx)
			return call_function(node[1], args, ctx)
		C.E_BIN:
			return _bin(node[1], _eval(node[2], ctx), _eval(node[3], ctx))
		C.E_UN:
			var v = _eval(node[2], ctx)
			match node[1]:
				"!":
					return 0.0 if truthy(v) else 1.0
				"-":
					return -float(v)
				"~":
					return float(~int(float(v)))
			return v
		C.E_AND:
			if not truthy(_eval(node[1], ctx)):
				return 0.0
			return 1.0 if truthy(_eval(node[2], ctx)) else 0.0
		C.E_OR:
			if truthy(_eval(node[1], ctx)):
				return 1.0
			return 1.0 if truthy(_eval(node[2], ctx)) else 0.0
		C.E_TERN:
			return _eval(node[2], ctx) if truthy(_eval(node[1], ctx)) else _eval(node[3], ctx)
		C.E_INCDEC:
			var cur := float(_eval(node[1], ctx))
			var nv := cur + float(node[2])
			_store(node[1], nv, ctx)
			return nv if node[3] else cur
	return 0.0


func _bin(op: String, a, b):
	if a is String or b is String:
		match op:
			"+":
				return str(a) + str(b) if (a is String and b is String) else (str(a) + _numstr(b) if a is String else _numstr(a) + str(b))
			"==":
				return 1.0 if _eq(a, b) else 0.0
			"!=":
				return 0.0 if _eq(a, b) else 1.0
			"<":
				return 1.0 if str(a) < str(b) else 0.0
			">":
				return 1.0 if str(a) > str(b) else 0.0
			"<=":
				return 1.0 if str(a) <= str(b) else 0.0
			">=":
				return 1.0 if str(a) >= str(b) else 0.0
		return 0.0
	if a == null or b == null:
		match op:
			"==":
				return 1.0 if a == b else 0.0
			"!=":
				return 0.0 if a == b else 1.0
		return 0.0
	var x := float(a)
	var y := float(b)
	match op:
		"+":
			return x + y
		"-":
			return x - y
		"*":
			return x * y
		"/":
			return x / y if y != 0.0 else 0.0
		"div":
			return float(int(x / y)) if y != 0.0 else 0.0
		"mod":
			return fmod(x, y) if y != 0.0 else 0.0
		# Numbers within EPS of each other are equal, for every comparison (GameMaker's math
		# epsilon; Undyne's darkener is removed when its alpha reaches 0.000000014 <= 0).
		"==":
			return 1.0 if absf(x - y) < EPS else 0.0
		"!=":
			return 0.0 if absf(x - y) < EPS else 1.0
		"<":
			return 1.0 if x - y <= -EPS else 0.0
		">":
			return 1.0 if x - y >= EPS else 0.0
		"<=":
			return 1.0 if x - y < EPS else 0.0
		">=":
			return 1.0 if x - y > -EPS else 0.0
		"&":
			return float(int(x) & int(y))
		"|":
			return float(int(x) | int(y))
		"^":
			return float(int(x) ^ int(y))
		"<<":
			return float(int(x) << int(y))
		">>":
			return float(int(x) >> int(y))
		"^^":
			return 1.0 if (x > 0.5) != (y > 0.5) else 0.0
	return 0.0


func _numstr(v) -> String:
	return builtins.gm_string(v)


func _get_ident(name: String, ctx: Dictionary):
	var loc: Dictionary = ctx["locals"]
	if loc.has(name):
		return loc[name]
	var me = ctx["self"]
	if me != null and me.v.has(name):
		return me.v[name]
	if name.begins_with("argument"):
		if name == "argument_count":
			return float(ctx["args"].size())
		var n := name.substr(8)
		if n.is_valid_int():
			var a: Array = ctx["args"]
			var k := int(n)
			return a[k] if k < a.size() else 0.0
		if name == "argument":
			return [ctx["args"]]
	var inst = ctx["self"]
	if inst != null and inst.v.has(name):
		return inst.v[name]
	if consts.has(name):
		return consts[name]
	var g = builtins.global_var(name)
	if g != null:
		return g
	if inst != null:
		return inst_get(inst, name)
	return 0.0


# Resolves the container (variable holding an array) for E_INDEX.
func _container_get(base_node: Array, ctx: Dictionary):
	if base_node[0] == C.E_IDENT:
		var name: String = base_node[1]
		if name == "alarm" and ctx["self"] != null:
			return ctx["self"].alarm
		if name == "argument":
			return [ctx["args"]]
		return _get_ident(name, ctx)
	if base_node[0] == C.E_MEMBER:
		var tgt = _eval(base_node[1], ctx)
		var name: String = base_node[2]
		if tgt is float and float(tgt) == GLOBAL:
			return globals.get(name, null)
		var inst = first_of(tgt, ctx)
		if inst == null:
			return null
		if name == "alarm":
			return inst.alarm
		return inst.v.get(name, builtins.view_array(name))
	return null


func _assign(lv: Array, op: String, expr: Array, ctx: Dictionary) -> void:
	var val = _eval(expr, ctx)
	if op != "=":
		var cur = _eval(lv, ctx)
		match op:
			"+=":
				val = _bin("+", cur, val)
			"-=":
				val = _bin("-", cur, val)
			"*=":
				val = _bin("*", cur, val)
			"/=":
				val = _bin("/", cur, val)
			"|=":
				val = _bin("|", cur, val)
			"&=":
				val = _bin("&", cur, val)
			"^=":
				val = _bin("^", cur, val)
			"%=":
				val = _bin("mod", cur, val)
			"<<=":
				val = _bin("<<", cur, val)
			">>=":
				val = _bin(">>", cur, val)
	_store(lv, val, ctx)


# Writes argumentN of the running script; arguments the caller left out read as 0.
func arg_set(a: Array, k: int, val) -> void:
	while a.size() <= k:
		a.append(0.0)
	a[k] = val


func _store(lv: Array, val, ctx: Dictionary) -> void:
	match int(lv[0]):
		C.E_IDENT:
			var name: String = lv[1]
			var loc: Dictionary = ctx["locals"]
			if loc.has(name):
				loc[name] = val
				return
			if builtins.set_global_var(name, val):
				return
			# argument0..15 belong to the running script, never to the instance.
			if name.begins_with("argument") and name.substr(8).is_valid_int():
				arg_set(ctx["args"], int(name.substr(8)), val)
				return
			inst_set(ctx["self"], name, val)
		C.E_MEMBER:
			var tgt = _eval(lv[1], ctx)
			var name: String = lv[2]
			if tgt is float and float(tgt) == GLOBAL:
				globals[name] = val
				return
			for inst in resolve(tgt, ctx):
				inst_set(inst, name, val)
		C.E_INDEX:
			var idx: Array = lv[2]
			var a := int(float(_eval(idx[0], ctx)))
			var b := -1
			if idx.size() > 1:
				b = int(float(_eval(idx[1], ctx)))
			var basen: Array = lv[1]
			# alarm[n]
			if (basen[0] == C.E_IDENT and basen[1] == "alarm") or (basen[0] == C.E_MEMBER and basen[2] == "alarm"):
				var owners: Array = [ctx["self"]] if basen[0] == C.E_IDENT else resolve(_eval(basen[1], ctx), ctx)
				for o in owners:
					if o != null and a >= 0 and a < 12:
						o.alarm[a] = alarm_value(val)
				return
			if basen[0] == C.E_IDENT:
				var name: String = basen[1]
				var loc: Dictionary = ctx["locals"]
				if loc.has(name):
					loc[name] = _arr_set(loc[name], a, b, val)
					return
				if builtins.set_global_array(name, a, val):
					return
				var inst = ctx["self"]
				if inst != null:
					inst.v[name] = _arr_set(inst.v.get(name), a, b, val)
			elif basen[0] == C.E_MEMBER:
				var tgt = _eval(basen[1], ctx)
				var name: String = basen[2]
				if tgt is float and float(tgt) == GLOBAL:
					globals[name] = _arr_set(globals.get(name), a, b, val)
					return
				for inst in resolve(tgt, ctx):
					inst.v[name] = _arr_set(inst.v.get(name), a, b, val)


func _arr_set(arr, a: int, b: int, val) -> Array:
	if not (arr is Array) or (arr.size() > 0 and not (arr[0] is Array)):
		arr = [[]]
	var row := 0
	var col := a
	if b >= 0:
		row = a
		col = b
	if row < 0 or col < 0:
		return arr
	while arr.size() <= row:
		arr.append([])
	var r: Array = arr[row]
	if r.size() <= col:
		var old := r.size()
		r.resize(col + 1)
		for k in range(old, col + 1):
			r[k] = 0.0
	r[col] = val
	return arr


func call_function(name: String, args: Array, ctx: Dictionary):
	if prof != null:
		var t0 := Time.get_ticks_usec()
		var r = call_script(name, args, ctx) if script_code.has(name) else builtins.fn(name, args, ctx)
		prof[name] = prof.get(name, 0) + Time.get_ticks_usec() - t0
		return r
	if script_code.has(name):
		return call_script(name, args, ctx)
	return builtins.fn(name, args, ctx)


# ---------------------------------------------------------------- helpers for translated code

func rd(me, name: String):
	if me == null:
		return 0.0
	var v: Dictionary = me.v
	if v.has(name):
		return v[name]
	return inst_get(me, name)


func mrd(t, name: String, ctx: Dictionary):
	if t is float and t == GLOBAL:
		return globals.get(name, 0.0)
	var inst = first_of(t, ctx)
	if inst == null:
		warn_once("noinst:" + name, "read of %s on a missing instance" % name)
		return 0.0
	return inst_get(inst, name)


func mwr(t, name: String, val, ctx: Dictionary) -> void:
	if t is float and t == GLOBAL:
		globals[name] = val
		return
	for inst in resolve(t, ctx):
		inst_set(inst, name, val)


func mcont(t, name: String, ctx: Dictionary):
	var inst = first_of(t, ctx)
	if inst == null:
		return null
	if name == "alarm":
		return inst.alarm
	return inst.v.get(name, builtins.view_array(name))


func marr_set(t, name: String, a: int, b: int, val, ctx: Dictionary) -> void:
	if t is float and t == GLOBAL:
		globals[name] = _arr_set(globals.get(name), a, b, val)
		return
	for inst in resolve(t, ctx):
		inst.v[name] = _arr_set(inst.v.get(name), a, b, val)


func arr_set(arr, a: int, b: int, val) -> Array:
	return _arr_set(arr, a, b, val)


func set_alarm(inst, a: int, val) -> void:
	if inst != null and a >= 0 and a < 12:
		if alarm_log and float(val) != floorf(float(val)):
			print("ALARMSET step=%d %s alarm[%d] = %s" % [step_no, obj_names[inst.obj], a, str(val)])
		inst.alarm[a] = alarm_value(val)


func set_alarm_of(t, a: int, val, ctx: Dictionary) -> void:
	for o in resolve(t, ctx):
		set_alarm(o, a, val)


func ix(arr, a):
	if not (arr is Array):
		return 0.0
	var k := int(float(a))
	if arr.size() > 0 and not (arr[0] is Array):
		return arr[k] if k >= 0 and k < arr.size() else 0.0
	if arr.is_empty():
		return 0.0
	var row0: Array = arr[0]
	return row0[k] if k >= 0 and k < row0.size() else 0.0


func ix2(arr, a, b):
	if not (arr is Array):
		return 0.0
	var i := int(float(a))
	var j := int(float(b))
	if i >= 0 and i < arr.size() and arr[i] is Array and j >= 0 and j < arr[i].size():
		return arr[i][j]
	return 0.0


func add(a, b):
	if a is float and b is float:
		return a + b
	return _bin("+", a, b)


func fdiv(a, b) -> float:
	var y := float(b)
	return float(a) / y if y != 0.0 else 0.0


func idiv(a, b) -> float:
	var y := float(b)
	return float(int(float(a) / y)) if y != 0.0 else 0.0


func fmod2(a, b) -> float:
	var y := float(b)
	return fmod(float(a), y) if y != 0.0 else 0.0


func eq(a, b) -> bool:
	return _eq(a, b)


func eqn(a, b: float) -> bool:
	if a is float:
		return absf(a - b) < EPS
	if a is int or a is bool:
		return absf(float(a) - b) < EPS
	return false


func cmp(op: String, a, b) -> bool:
	return truthy(_bin(op, a, b))


# ---------------------------------------------------------------- rooms

var room_snapshots := {}   # room index -> {instances, state} saved when a persistent room is left
var game_started := false  # Game Start has run (the first room loaded)


# GameMaker 1.4's room change: Room End for everyone, then the old room is either kept
# (persistent: its instances wait, untouched, for the player to come back) or its
# non-persistent instances go, without Destroy events. A new room's placed instances all
# exist before any Create runs; then each one's Create and creation code, Game Start (first
# room only), the room's creation code, and Room Start for everyone. A kept room comes back
# as it was: no Create, no creation code, only Room Start.
func load_room(r: int) -> bool:
	for i in instances.duplicate():
		if not i.dead:
			perform_event(i, EV_OTHER, 5, null)
	var keep: Array = []
	var stay: Array = []
	for i in instances:
		if i.dead:
			by_id.erase(i.id)
		elif float(i.v.get("persistent", 0.0)) >= 0.5:
			keep.append(i)
		else:
			stay.append(i)
			by_id.erase(i.id)
	if room >= 0 and builtins.room_persist.get(room, false):
		room_snapshots[room] = {"instances": stay, "state": builtins.room_state_save()}
	instances = keep
	inst_version += 1
	var prev := room
	room = r
	var name: String = room_names[r] if r >= 0 and r < room_names.size() else ""
	var rooms: Dictionary = meta["rooms"]
	if not rooms.has(name):
		warn_once("room:" + name, "room %s is missing from the extracted data" % name)
		return false
	var rd: Dictionary = rooms[name]
	room_width = int(rd["width"])
	room_height = int(rd["height"])
	room_speed = int(rd["speed"])
	if not builtins.room_persist.has(r):
		builtins.room_persist[r] = int(rd.get("persistent", 0)) == 1
	var snap = room_snapshots.get(r) if builtins.room_persist.get(r, false) else null
	room_snapshots.erase(r)
	if snap != null:
		builtins.room_state_restore(snap["state"])
		for i in snap["instances"]:
			_insert_by_depth(i)
			by_id[i.id] = i
		inst_version += 1
	else:
		builtins.room_state_load(rd)
		var created: Array = []
		for inst_def in rd["instances"]:
			if inst_def[0] == null or not obj_index.has(inst_def[0]):
				continue
			var o: int = obj_index[inst_def[0]]
			# A persistent object already present is not placed twice.
			if obj_persistent[o]:
				var exists := false
				for k in instances:
					if k.obj == o:
						exists = true
				if exists:
					continue
			var inst = instance_create(float(inst_def[1]), float(inst_def[2]), o, false)
			inst.v["image_xscale"] = float(inst_def[3])
			inst.v["image_yscale"] = float(inst_def[4])
			if inst_def.size() > 8:
				inst.v["image_angle"] = float(inst_def[7])
				inst.v["image_blend"] = float(int(inst_def[8]) & 0xFFFFFF)
			created.append([inst, inst_def[6]])
		# Every placed instance exists before any Create event runs, as in GameMaker Studio
		# (measured: Sans's Create, run from obj_battlecontroller's, hides the box borders that
		# come after the controller in room_battle's list).
		for c in created:
			var inst = c[0]
			if inst.dead:
				continue
			perform_event(inst, EV_CREATE, 0, null)
			if c[1] != null and not inst.dead:
				run_code(c[1], inst, inst)
		if not game_started:
			game_started = true
			for i in instances.duplicate():
				if not i.dead:
					perform_event(i, EV_OTHER, 2, null)
		if rd["code"] != null:
			run_code(rd["code"], null, null)
	for i in instances.duplicate():
		if not i.dead:
			perform_event(i, EV_OTHER, 4, null)
	purge_dead()
	return true


# Room-level per-frame work the runner does after End Step: backgrounds scroll and views
# follow their objects.
func room_frame_end() -> void:
	builtins.step_backgrounds()
	builtins.update_views()


# Tiles and backgrounds behind the instances; tiles are drawn among the instances by depth.
func _draw_tiles_until(tl: Array, at: int, depth: float, rec) -> int:
	while at < tl.size() and float(tl[at][8]) >= depth:
		builtins.draw_tile(tl[at])
		at += 1
	return at
