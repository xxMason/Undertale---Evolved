# Ultimate Battle Engine (Godot): runs Undertale's original battle code through the GML
# runtime in gml/, using code and assets extracted from the player's own copy.
#
# Screens: encounter select -> battle (the original room_battle, battle controller,
# monsters and attacks) -> result -> back to the list.
# Controls in battle are Undertale's (arrows, Z, X, C). F3 toggles WASD, F4 fullscreen,
# Esc leaves a battle (or quits from the list).
#
# Self-test: --battle <index> runs one encounter with scripted input and prints a report;
# --shots <folder> saves screenshots while doing so.
extends Node2D

const VM = preload("res://gml/gml_vm.gd")
const Builtins = preload("res://gml/gml_builtins.gd")
const Keys = preload("res://gml/gml_keys.gd")
const Recorder = preload("res://gml/gml_recorder.gd")

const RETURN_ROOM := 9999   # global.currentroom: going here means the battle is over

# One battle per monster and every real boss. "bg" uses the game's own battle group;
# "solo" builds a one-monster group from the original group that monster appears in.
const ROSTER := [
	["RUINS", "Dummy", {"bg": 2}],
	["RUINS", "Froggit", {"bg": 4}],
	["RUINS", "Whimsun", {"bg": 5}],
	["RUINS", "Moldsmal", {"bg": 7}],
	["RUINS", "Migosp", {"solo": "obj_migosp", "type": 7, "x": 216, "y": 136, "music": "battle1"}],
	["RUINS", "Vegetoid", {"bg": 18}],
	["RUINS", "Loox", {"bg": 13}],
	["RUINS", "Napstablook", {"bg": 20}],
	["RUINS", "Toriel", {"bg": 22}],
	["RUINS (HARD)", "Parsnik", {"bg": 122}],
	["RUINS (HARD)", "Moldessa", {"solo": "obj_moldessa", "type": 74, "x": 216, "y": 127, "music": "battle2"}],
	["RUINS (HARD)", "Migospel", {"solo": "obj_migospel", "type": 73, "x": 216, "y": 130, "music": "battle2"}],
	["SNOWDIN", "Snowdrake", {"bg": 30}],
	["SNOWDIN", "Chilldrake", {"bg": 30, "flags": {57: 2}}],
	["SNOWDIN", "Ice Cap", {"bg": 32}],
	["SNOWDIN", "Gyftrot", {"bg": 28}],
	["SNOWDIN", "Jerry", {"bg": 34}],
	["SNOWDIN", "Glyde", {"bg": 135}],
	["SNOWDIN", "Doggo", {"bg": 23}],
	["SNOWDIN", "Lesser Dog", {"bg": 24}],
	["SNOWDIN", "Dogamy & Dogaressa", {"bg": 25}],
	["SNOWDIN", "Greater Dog", {"bg": 26}],
	["SNOWDIN", "Papyrus", {"bg": 27}],
	["WATERFALL", "Aaron", {"bg": 40}],
	["WATERFALL", "Woshua", {"bg": 43}],
	["WATERFALL", "Moldbygg", {"solo": "obj_moldsmalx", "type": 26, "x": 216, "y": 156, "music": "battle1"}],
	["WATERFALL", "Temmie", {"bg": 41}],
	["WATERFALL", "Shyren", {"bg": 44}],
	["WATERFALL", "Mad Dummy", {"bg": 45}],
	["WATERFALL", "Glad Dummy", {"bg": 93}],
	["WATERFALL", "Undyne", {"bg": 47}],
	["WATERFALL", "Undyne the Undying", {"bg": 92}],
	["HOTLAND", "Tsunderplane", {"bg": 50}],
	["HOTLAND", "Vulkin", {"bg": 51}],
	["HOTLAND", "Pyrope", {"bg": 52}],
	["HOTLAND", "Royal Guards", {"bg": 49}],
	["HOTLAND", "So Sorry", {"bg": 140}],
	["HOTLAND", "Muffet", {"bg": 56}],
	["HOTLAND", "Mettaton EX", {"bg": 81}],
	["HOTLAND", "Mettaton NEO", {"bg": 94}],
	["CORE", "Madjick", {"bg": 59}],
	["CORE", "Knight Knight", {"bg": 60}],
	["CORE", "Final Froggit", {"bg": 61}],
	["CORE", "Whimsalot", {"bg": 63}],
	["CORE", "Astigmatism", {"bg": 62}],
	["JUDGEMENT HALL", "Sans", {"bg": 95}],
	["BARRIER", "Asgore", {"bg": 101}],
	["BARRIER", "Asriel Dreemurr", {"bg": 255}],
]

# Bosses get their own tab; every other entry is a regular monster.
const BOSSES := ["Napstablook", "Toriel", "Papyrus", "Mad Dummy", "Glad Dummy", "Undyne",
	"Undyne the Undying", "Royal Guards", "So Sorry", "Muffet", "Mettaton EX", "Mettaton NEO",
	"Sans", "Asgore", "Asriel Dreemurr"]
const AREAS := ["RUINS", "SNOWDIN", "WATERFALL", "HOTLAND", "CORE", "JUDGEMENT HALL", "BARRIER"]

enum Screen { LIST, BATTLE, RESULT, ERROR }

var vm
var bi
var keys
var screen := Screen.LIST
var sel := 0
var scroll := 0
var tab_area := 0
var tab_kind := 0          # index into the area's non-empty [monsters, bosses] tabs
var setup_open := false
var setup_row := 0
var menushot := ""
var result_text := ""
var error := ""
var text_map := -1.0
var obj_time = null
var frames := 0
var lv := 1
var frame_cap := 2400
var wasd := false
var prev_real := {}
var rec = Recorder.new()
var battle_over := false
var sweep := false
var smooth := true

# --gmtrace: frame-by-frame comparison with the real game (see scripts/trace-compare.ps1).
const XP_FOR_LV := [0, 0, 10, 30, 70, 120, 200, 300, 500, 800, 1200, 1700, 2500, 3500, 5000, 7000, 10000, 15000, 25000, 50000, 99999]
const TRACE_KEYS := [37, 39, 38, 40, 90, 88, 67]   # bits 1 L, 2 R, 4 U, 8 D, 16 Z, 32 X, 64 C
var trace_seed := -1
var trace_replay = null        # frame -> key bits seen by the real game, or null for auto-play
var trace_lines: PackedStringArray = []
var trace_watch := ""          # object whose instances get a W line every frame

# self-test
var auto_index := -1
var auto_frames := 0
var tracing := false   # a --gmtrace run drives the frames itself
var shots_dir := ""
var shots_taken := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--battle")
	if i >= 0 and i + 1 < args.size():
		auto_index = int(args[i + 1])
	i = args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		shots_dir = args[i + 1]
	vm = VM.new()
	if not vm.setup(ProjectSettings.globalize_path("res://extracted")):
		error = "No extracted game data. Run scripts/prepare-godot.ps1 first."
		screen = Screen.ERROR
		return
	bi = Builtins.new(vm)
	vm.builtins = bi
	keys = Keys.new()
	bi.keys = keys
	bi.audio_root = self
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		wasd = bool(cfg.get_value("input", "wasd", false))
		lv = clampi(int(cfg.get_value("player", "lv", 1)), 1, 20)
	keys.wasd = wasd
	# The English text table is built once and kept between battles.
	vm.globals["language"] = "en"
	var boot = vm.instance_create(0, 0, vm.obj_index["obj_time"], false)
	vm.call_script("textdata_en", [], {"self": boot, "other": boot, "locals": {}, "args": []})
	text_map = vm.globals.get("text_data_en", -1.0)
	i = args.find("--frames")
	if i >= 0 and i + 1 < args.size():
		frame_cap = int(args[i + 1])
	if args.has("--interp"):
		vm.use_fast = false
	trace_hits = args.has("--hits")
	vm.alarm_log = args.has("--alarmlog")
	if args.has("--prof"):
		vm.prof = {}
	i = args.find("--lv")
	if i >= 0 and i + 1 < args.size():
		lv = clampi(int(args[i + 1]), 1, 20)
	if args.has("--collprobe"):
		# Same GML file the real game runs in the trace scenario; the COLL lines must match.
		var src := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../patches/gml/scripts/ube_coll_probe.gml"))
		var tree: Array = vm.compiler.compile(src)
		vm.exec_node(tree, {"self": boot, "other": boot, "locals": {}, "args": []})
		print(vm.take_ret())
		get_tree().quit()
		return
	i = args.find("--gmtrace")
	if i >= 0 and i + 1 < args.size():
		var o := args.find("--out")
		var r := args.find("--replay")
		await _run_trace(args[i + 1], args[r + 1] if r >= 0 and r + 1 < args.size() else "", args[o + 1] if o >= 0 and o + 1 < args.size() else "user://trace.txt")
		get_tree().quit()
		return
	i = args.find("--sweep")
	if i >= 0:
		sweep = true
		var first := int(args[i + 1]) if i + 1 < args.size() and args[i + 1].is_valid_int() else 0
		var last := int(args[i + 2]) if i + 2 < args.size() and args[i + 2].is_valid_int() else ROSTER.size() - 1
		if args.has("--warm"):
			var tw := Time.get_ticks_msec()
			while not vm.warm_step(1000000):
				pass
			print("WARM all code compiled in %d ms" % (Time.get_ticks_msec() - tw))
		_run_sweep(first, last)
		get_tree().quit()
		return
	i = args.find("--menushot")
	if i >= 0 and i + 1 < args.size():
		menushot = args[i + 1]
	i = args.find("--tab")
	if i >= 0 and i + 2 < args.size():
		tab_area = int(args[i + 1])
		tab_kind = int(args[i + 2])
	setup_open = args.has("--setup")
	if auto_index >= 0:
		start_battle(auto_index)


# ---------------------------------------------------------------- battle set-up

func _ctx(inst = null) -> Dictionary:
	# Host-run scripts execute as the obj_time stand-in, like the original start-up code.
	if inst == null:
		inst = obj_time
	return {"self": inst, "other": inst, "locals": {}, "args": []}


func _reset_runtime() -> void:
	for p in bi.players:
		p["player"].stop()
		p["player"].queue_free()
	bi.players.clear()
	bi.asset_gain.clear()
	keys.queue.clear()
	bi.asset_pitch.clear()
	vm.instances.clear()
	vm.by_id.clear()
	vm.next_id = 100001
	vm.room = -1
	vm.pending_room = -1
	vm.game_end_requested = false
	var keep_text = bi.maps.get(int(text_map))
	bi.maps.clear()
	bi.lists.clear()
	if keep_text != null:
		bi.maps[int(text_map)] = keep_text
	vm.globals.clear()
	vm.globals["text_data_en"] = text_map
	bi.draw_color = 16777215
	bi.draw_alpha = 1.0
	bi.draw_font = -1
	bi.halign = 0
	bi.valign = 0


func start_battle(index: int) -> void:
	sel = index
	var entry: Array = ROSTER[index]
	var spec: Dictionary = entry[2]
	_reset_runtime()
	var g: Dictionary = vm.globals
	g["osflavor"] = 1.0
	g["language"] = "en"
	g["locale"] = "en_US"
	g["debug"] = 0.0
	# A stand-in for the persistent obj_time (its own start-up code loads save files).
	obj_time = vm.instance_create(0, 0, vm.obj_index["obj_time"], false)
	obj_time.v["persistent"] = 1.0
	obj_time.v["visible"] = 0.0
	# The variables obj_time's Create event sets; its own Begin Step then handles input
	# every frame (control_update, the arrow-key state the SOUL reads) as in the game.
	for k in ["up", "down", "left", "right", "j_ch", "time", "paused", "idle", "idle_time", "quit", "try_up", "try_down", "try_left", "try_right", "h_skip", "jt", "j_xpos", "j_ypos", "j_dir", "j_fr", "j_fl", "j_fu", "j_fd", "j_fr_p", "j_fl_p", "j_fu_p", "j_fd_p", "debug_r", "debug_f", "spec_rtimer", "j1", "j2", "ja", "trophy_ts"]:
		obj_time.v[k] = 0.0
	obj_time.v["canquit"] = 0.0
	obj_time.v["started"] = 1.0
	vm.call_script("control_init", [], _ctx())
	vm.call_script("SCR_GAMESTART", [], _ctx())
	# Player: chosen LOVE, full HP, Stick and Bandage, a few healing items. The same rules
	# as the simulator's ube_apply_player (LV 20 is the game's own special case).
	g["charname"] = "CHARA"
	g["lv"] = float(lv)
	g["xp"] = float(XP_FOR_LV[lv])
	g["maxhp"] = 16.0 + lv * 4.0
	g["at"] = 8.0 + lv * 2.0
	g["df"] = 9.0 + ceilf(lv / 4.0)
	if lv == 20:
		g["maxhp"] = 99.0
		g["at"] = 30.0
		g["df"] = 30.0
	g["hp"] = g["maxhp"]
	vm.call_script("scr_weaponeq", [-1.0, 3.0], _ctx())
	vm.call_script("scr_armoreq", [-1.0, 4.0], _ctx())
	var items := [1.0, 1.0, 11.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	g["item"] = [items]
	vm.call_script("scr_itemnameb", [], _ctx())
	vm.call_script("scr_itemname", [], _ctx())
	if spec.has("flags"):
		var flags = g.get("flag")
		for f in spec["flags"]:
			if flags is Array:
				flags[0][int(f)] = float(spec["flags"][f])
	g["currentroom"] = float(RETURN_ROOM)
	g["inbattle"] = 0.0
	if spec.has("bg"):
		g["battlegroup"] = float(spec["bg"])
	else:
		# Solo battle: no group case matches, so the monster is added after the
		# battle controller has set up (as the original group cases do).
		g["battlegroup"] = 9000.0
		g["msc"] = 0.0
		g["msg"] = [["* " + entry[1] + " draws near!", "%%%"]]
		g["batmusic"] = -1.0
		g["actfirst"] = 0.0
		g["extraintro"] = 0.0
	screen = Screen.BATTLE
	frames = 0
	battle_over = false
	rec.clear()
	# --gmtrace: seed GameMaker's generator where the simulator does, after SCR_GAMESTART's
	# randomize() and right before the battle room is built.
	if trace_seed >= 0:
		bi.rng.set_seed(trace_seed)
	load_room(int(vm.consts["room_battle"]))
	if not spec.has("bg"):
		g["monstertype"] = [[float(spec["type"]), 0.0, 0.0]]
		var mon = vm.instance_create(float(spec["x"]), float(spec["y"]), vm.obj_index[spec["solo"]])
		var mi = g.get("monsterinstance")
		g["monsterinstance"] = vm._arr_set(mi, 0, -1, float(mon.id))
		var snd: float = vm.call_script("caster_load", ["music/%s.ogg" % spec["music"]], _ctx())
		g["batmusic"] = snd
		vm.call_script("caster_loop", [snd, 0.5, 1.0], _ctx())
	# Compile everything this battle can reach now, rather than mid-fight.
	var tc := Time.get_ticks_msec()
	var seeds: Array = ["obj_gameover", "obj_heartdefeated"]
	for ins in vm.instances:
		seeds.append(vm.obj_names[ins.obj])
	var nc: int = vm.precompile_from(seeds)
	vm.vlog("BATTLE precompiled %d code entries in %d ms" % [nc, Time.get_ticks_msec() - tc])
	if OS.get_cmdline_user_args().has("--trace") or OS.get_cmdline_user_args().has("--prof"):
		print("PRECOMPILE %d code entries in %d ms" % [nc, Time.get_ticks_msec() - tc])
	vm.vlog("BATTLE start %s (%s)" % [entry[1], str(spec)])


func load_room(r: int) -> void:
	# Room End for everyone, drop non-persistent instances, then build the new room.
	for i in vm.instances.duplicate():
		if not i.dead:
			vm.perform_event(i, vm.EV_OTHER, 5, null)
	var keep: Array = []
	for i in vm.instances:
		if not i.dead and float(i.v.get("persistent", 0.0)) >= 0.5:
			keep.append(i)
		else:
			vm.by_id.erase(i.id)
	vm.instances = keep
	vm.room = r
	var name: String = vm.room_names[r] if r >= 0 and r < vm.room_names.size() else ""
	var rooms: Dictionary = vm.meta["rooms"]
	if not rooms.has(name):
		vm.warn_once("room:" + name, "room %s is not part of the battle engine" % name)
		return
	var rd: Dictionary = rooms[name]
	vm.room_width = int(rd["width"])
	vm.room_height = int(rd["height"])
	vm.room_speed = int(rd["speed"])
	var created: Array = []
	for inst_def in rd["instances"]:
		if inst_def[0] == null or not vm.obj_index.has(inst_def[0]):
			continue
		var o: int = vm.obj_index[inst_def[0]]
		# Persistent objects already present are not created twice.
		if vm.obj_persistent[o]:
			var exists := false
			for k in vm.instances:
				if k.obj == o:
					exists = true
			if exists:
				continue
		var inst = vm.instance_create(float(inst_def[1]), float(inst_def[2]), o, false)
		inst.v["image_xscale"] = float(inst_def[3])
		inst.v["image_yscale"] = float(inst_def[4])
		created.append([inst, inst_def[6]])
	# Every placed instance exists before any Create event runs, as in GameMaker Studio
	# (measured: Sans's Create, run from obj_battlecontroller's, hides the box borders that
	# come after the controller in room_battle's list).
	for c in created:
		var inst = c[0]
		if inst.dead:
			continue
		vm.perform_event(inst, vm.EV_CREATE, 0, null)
		if c[1] != null and not inst.dead:
			vm.run_code(c[1], inst, inst)
	if rd["code"] != null:
		vm.run_code(rd["code"], null, null)
	for i in vm.instances.duplicate():
		if not i.dead:
			vm.perform_event(i, vm.EV_OTHER, 4, null)
	vm.purge_dead()


# ---------------------------------------------------------------- frames

func _physics_process(_delta: float) -> void:
	match screen:
		Screen.LIST:
			_list_input()
		Screen.RESULT:
			_poll_menu_keys()
			if _menu_pressed(90) or _menu_pressed(13) or _menu_pressed(88):
				screen = Screen.LIST
		Screen.BATTLE:
			if not tracing:
				_battle_frame()


var perf_draw_us := 0
var perf_draws := 0
var perf_draw_max := 0
var perf_logic_us := 0
var perf_logic_max := 0
var perf_ops := 0


func _battle_frame() -> void:
	var tl := Time.get_ticks_usec()
	_battle_frame_inner()
	var dt := Time.get_ticks_usec() - tl
	perf_logic_us += dt
	if frames > 1:
		perf_logic_max = maxi(perf_logic_max, dt)
		if dt > 20000 and OS.get_cmdline_user_args().has("--spikes"):
			print("SPIKE frame=%d %.1fms" % [frames, dt / 1000.0])
	perf_ops = maxi(perf_ops, rec.ops.size())


func _battle_frame_inner() -> void:
	frames += 1
	var auto = _auto_keys() if auto_index >= 0 else null
	if trace_replay != null:
		auto = []
		var bits: int = trace_replay.get(frames, 0)
		for b in TRACE_KEYS.size():
			if bits & (1 << b):
				auto.append(TRACE_KEYS[b])
	keys.poll(auto)
	if auto == null and keys.held(27):
		_end_battle("Left the battle.")
		return
	var hp0 := float(vm.globals.get("hp", 0.0))
	var clog := OS.get_cmdline_user_args().has("--colllog")
	if trace_hits or clog:
		vm.coll_log = []
	vm.step_frame(keys)
	if clog and not vm.coll_log.is_empty():
		print("COLL f=%d %s" % [frames + 1, ", ".join(vm.coll_log)])
	if trace_hits:
		_trace_hit(hp0)
	if vm.pending_room != -1:
		var r: int = vm.pending_room
		vm.pending_room = -1
		if r == RETURN_ROOM:
			var won := float(vm.globals.get("hp", 0.0)) > 0.0
			_end_battle("YOU WON!" if won else "The battle ended.")
			return
		load_room(r)
		# The runner then plays the frame's events in the new room (measured at game over:
		# obj_heartdefeated's alarm[0] = 20 fires 19 frames after the room change).
		vm.step_frame(keys)
	if vm.game_end_requested:
		_end_battle("The game asked to quit.")
		return
	rec.clear()
	bi.canvas = rec
	var hp1 := float(vm.globals.get("hp", 0.0))
	# The real game's trace line is written by a Draw event at depth -100000, so anything
	# drawn in front of that (Mettaton NEO's body once it fades to white) is logged before
	# its own Draw runs; the trace here is taken at the same point.
	if trace_seed >= 0:
		vm.draw_hook_depth = -100000.0
		vm.draw_hook = func(): _trace_line(auto)
	rec.view = Vector2(float(bi.view_xview[0]), float(bi.view_yview[0]))
	vm.draw_frame()
	vm.draw_hook = Callable()
	bi.canvas = null
	if trace_hits:
		_trace_hit(hp1, " (in Draw)")
		vm.coll_log = null
	if not sweep:
		_auto_report()


# --hits: one line per HP change, with the collision events that fired this frame.
var trace_hits := false
var hit_count := 0
var hit_total := 0.0


func _trace_hit(before: float, where := "") -> void:
	var now := float(vm.globals.get("hp", 0.0))
	if now == before:
		return
	var heart_hits: Array = []
	for c in vm.coll_log:
		if c.contains("heart") and not heart_hits.has(c):
			heart_hits.append(c)
	if now < before:
		hit_count += 1
		hit_total += before - now
	print("  HIT f=%d turn=%s hp %s -> %s%s km=%s by %s" % [frames, bi.gm_string(vm.globals.get("turn", 0.0)), bi.gm_string(before), bi.gm_string(now), where, bi.gm_string(vm.globals.get("km", 0.0)), ", ".join(heart_hits) if not heart_hits.is_empty() else "(no SOUL collision this frame)"])


func _end_battle(text: String) -> void:
	result_text = text
	battle_over = true
	if sweep:
		return
	for p in bi.players:
		p["player"].stop()
	vm.vlog("BATTLE end: " + text)
	if auto_index >= 0:
		_print_report("END " + text)
		get_tree().quit()
		return
	screen = Screen.RESULT


# ---------------------------------------------------------------- list screen

var menu_now := {}
var menu_prev := {}


func _poll_menu_keys() -> void:
	menu_prev = menu_now
	menu_now = {}
	for pair in [[KEY_UP, 38], [KEY_DOWN, 40], [KEY_LEFT, 37], [KEY_RIGHT, 39], [KEY_Z, 90], [KEY_ENTER, 13], [KEY_X, 88], [KEY_SHIFT, 88], [KEY_ESCAPE, 27], [KEY_W, 38 if wasd else 0], [KEY_S, 40 if wasd else 0]]:
		if pair[1] != 0 and Input.is_physical_key_pressed(pair[0]):
			menu_now[pair[1]] = true


func _menu_pressed(code: int) -> bool:
	return menu_now.has(code) and not menu_prev.has(code)


# Tabs present in an area: 0 = MONSTERS, 1 = BOSSES (a tab with nothing in it is left out).
func _area_tabs(area: int) -> Array:
	var out: Array = []
	for kind in 2:
		if not _entries(area, kind).is_empty():
			out.append(kind)
	return out


# Roster indexes shown under an area and tab.
func _entries(area: int, kind: int) -> Array:
	var out: Array = []
	for k in ROSTER.size():
		var e: Array = ROSTER[k]
		var a: String = e[0]
		if a.begins_with(AREAS[area]) and ((e[1] in BOSSES) == (kind == 1)):
			out.append(k)
	return out


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "wasd", wasd)
	cfg.set_value("player", "lv", lv)
	cfg.save("user://settings.cfg")


func _list_input() -> void:
	_poll_menu_keys()
	if _menu_pressed(27):
		get_tree().quit()
		return
	if setup_open:
		if _menu_pressed(38) or _menu_pressed(40):
			setup_row = 1 - setup_row
		var d := (1 if _menu_pressed(39) else 0) - (1 if _menu_pressed(37) else 0)
		if d != 0 or (_menu_pressed(90) and setup_row == 1):
			if setup_row == 0:
				lv = clampi(lv + d, 1, 20)
			else:
				wasd = not wasd
				keys.wasd = wasd
			_save_settings()
		if _menu_pressed(88) or _menu_pressed(67):
			setup_open = false
		return
	if _menu_pressed(67):
		setup_open = true
		setup_row = 0
		return
	var tabs := _area_tabs(tab_area)
	if _menu_pressed(37) or _menu_pressed(39):
		var step := 1 if _menu_pressed(39) else -1
		var pos := tab_kind + step
		if pos < 0:
			tab_area = (tab_area + AREAS.size() - 1) % AREAS.size()
			tab_kind = _area_tabs(tab_area).size() - 1
		elif pos >= tabs.size():
			tab_area = (tab_area + 1) % AREAS.size()
			tab_kind = 0
		else:
			tab_kind = pos
		sel = 0
		scroll = 0
		tabs = _area_tabs(tab_area)
	var list := _entries(tab_area, tabs[tab_kind])
	if _menu_pressed(38):
		sel = (sel + list.size() - 1) % list.size()
	if _menu_pressed(40):
		sel = (sel + 1) % list.size()
	if _menu_pressed(90) or _menu_pressed(13):
		start_battle(list[sel])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			wasd = not wasd
			keys.wasd = wasd
			_save_settings()
		elif event.keycode == KEY_F2:
			smooth = not smooth
		elif event.keycode == KEY_F4:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


# ---------------------------------------------------------------- drawing

var _menushot_wait := 0


func _process(_delta: float) -> void:
	queue_redraw()
	# Compile the game's translated code in the background while the menus are idle.
	if vm != null and (screen == Screen.LIST or screen == Screen.RESULT):
		vm.warm_step(6000)
	if menushot != "" and screen == Screen.LIST:
		_menushot_wait += 1
		if _menushot_wait == 10:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(menushot)
			get_tree().quit()


func _text(x: float, y: float, s: String, color := 16777215, font_name := "fnt_main") -> void:
	bi.canvas = self
	bi.draw_font = int(vm.consts.get(font_name, -1.0))
	bi.halign = 0
	bi.valign = 0
	bi._draw_text(x, y, s, 1.0, 1.0, 0.0, color, 1.0)
	bi.canvas = null


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 480), Color.BLACK)
	match screen:
		Screen.ERROR:
			draw_string(ThemeDB.fallback_font, Vector2(20, 40), error, HORIZONTAL_ALIGNMENT_LEFT, 600, 14)
		Screen.LIST:
			_draw_list()
		Screen.RESULT:
			_text(40, 200, result_text, 65535)
			_text(40, 260, "[Z] Back to the list", 8421504, "fnt_maintext")
		Screen.BATTLE:
			var td := Time.get_ticks_usec()
			rec.replay(self, Engine.get_physics_interpolation_fraction() if smooth else 1.0)
			perf_draw_us += Time.get_ticks_usec() - td
			perf_draws += 1
			perf_draw_max = maxi(perf_draw_max, Time.get_ticks_usec() - td)


var hits: Array = []        # [Rect2, kind, value] clickable areas of the current menu screen
var hover_kind := ""
var hover_value = null


func _hit(r: Rect2, kind: String, value = null) -> void:
	hits.append([r, kind, value])


func _hovered(kind: String, value = null) -> bool:
	return hover_kind == kind and hover_value == value


func _font_w(s: String, font_name := "fnt_maintext") -> float:
	bi.draw_font = int(vm.consts.get(font_name, -1.0))
	return bi.text_width(s)


func _draw_list() -> void:
	hits.clear()
	_text(32, 14, "ULTIMATE BATTLE ENGINE", 16777215)
	# Player setup button (top right).
	var lvtxt := "LV %d  HP %d" % [lv, 99 if lv == 20 else 16 + lv * 4]
	var bw := _font_w(lvtxt) + 20
	var br := Rect2(616 - bw, 14, bw, 26)
	draw_rect(br, Color(1, 1, 0) if _hovered("setup") else Color(0.5, 0.5, 0.5), false, 2.0)
	_text(br.position.x + 10, 20, lvtxt, 65535 if _hovered("setup") else 16777215, "fnt_maintext")
	_hit(br, "setup")
	# Area tabs.
	var x := 24.0
	for a in AREAS.size():
		var label: String = AREAS[a]
		var w := _font_w(label)
		var c := 65535 if a == tab_area else (16777215 if _hovered("area", a) else 8421504)
		_text(x, 50, label, c, "fnt_maintext")
		_hit(Rect2(x - 4, 46, w + 8, 22), "area", a)
		x += w + 18
	draw_rect(Rect2(20, 70, 600, 1), Color(0.5, 0.5, 0.5))
	# Monsters / Bosses tabs.
	var tabs := _area_tabs(tab_area)
	x = 40.0
	for t in tabs.size():
		var label := "[" + ("MONSTERS" if tabs[t] == 0 else "BOSSES") + "]"
		var on := t == tab_kind
		_text(x, 80, label, 16777215 if on or _hovered("tab", t) else 8421504, "fnt_maintext")
		_hit(Rect2(x - 4, 76, _font_w(label) + 8, 22), "tab", t)
		x += 120
	var list := _entries(tab_area, tabs[tab_kind])
	var rows := 9
	if sel < scroll:
		scroll = sel
	if sel >= scroll + rows:
		scroll = sel - rows + 1
	var y := 112
	for r in range(scroll, mini(scroll + rows, list.size())):
		var e: Array = ROSTER[list[r]]
		var c := 65535 if r == sel else 16777215
		if r == sel and not setup_open:
			_heart(46, y + 8)
		_text(72, y, e[1], c)
		if String(e[0]).ends_with("(HARD)"):
			_text(400, y + 8, "Hard Mode", 8421504, "fnt_maintext")
		_hit(Rect2(40, y - 2, 560, 32), "row", r)
		y += 34
	if list.size() > rows:
		_text(600, 112, "^" if scroll > 0 else "", 8421504, "fnt_maintext")
		_text(600, 112 + (rows - 1) * 34, "v" if scroll + rows < list.size() else "", 8421504, "fnt_maintext")
	if vm.warm_progress() < 1.0:
		_text(24, 428, "Preparing battles... %d%%" % int(vm.warm_progress() * 100.0), 8421504, "fnt_maintext")
	_text(24, 450, "[ARROWS/MOUSE] Choose  [Z/CLICK] Fight  [C] Setup  [F4] Fullscreen  [ESC] Quit", 8421504, "fnt_maintext")
	if setup_open:
		hits.clear()     # the panel takes the mouse while it is open
		draw_rect(Rect2(150, 150, 340, 160), Color.BLACK)
		draw_rect(Rect2(150, 150, 340, 160), Color.WHITE, false, 3.0)
		_text(176, 166, "PLAYER SETUP", 16777215)
		var y0 := 210
		# LV row with clickable arrows.
		var lc := 65535 if setup_row == 0 else 16777215
		_text(196, y0, "LV", lc)
		_text(250, y0, "<", 16777215 if _hovered("lv", -1) else lc)
		_hit(Rect2(244, y0 - 2, 26, 30), "lv", -1)
		_text(280, y0, "%d" % lv, lc)
		_text(324, y0, ">", 16777215 if _hovered("lv", 1) else lc)
		_hit(Rect2(318, y0 - 2, 26, 30), "lv", 1)
		_text(356, y0 + 8, "HP %d" % (99 if lv == 20 else 16 + lv * 4), 8421504, "fnt_maintext")
		_hit(Rect2(170, y0 - 2, 70, 30), "setup_row", 0)
		var mc := 65535 if setup_row == 1 else 16777215
		_text(196, y0 + 34, "Movement  " + ("WASD" if wasd else "ARROWS"), 16777215 if _hovered("move") else mc)
		_hit(Rect2(170, y0 + 32, 300, 30), "move")
		_heart(172, 218 + setup_row * 34)
		var close_r := Rect2(398, 278, 80, 24)
		draw_rect(close_r, Color(1, 1, 0) if _hovered("close") else Color(0.5, 0.5, 0.5), false, 2.0)
		_text(414, 282, "CLOSE", 65535 if _hovered("close") else 16777215, "fnt_maintext")
		_hit(close_r, "close")
		_text(166, 284, "[LEFT/RIGHT] Change", 8421504, "fnt_maintext")


func _heart(x: float, y: float) -> void:
	var heart = vm.sprite_index.get("spr_heart", -1)
	if heart >= 0:
		bi.canvas = self
		bi._draw_sprite_ext(heart, 0, x, y, 1, 1, 0, 255, 1)
		bi.canvas = null


# ---------------------------------------------------------------- mouse

func _hit_at(p: Vector2) -> Array:
	for h in hits:
		if (h[0] as Rect2).has_point(p):
			return h
	return []


func _mouse(event: InputEvent) -> void:
	var p := get_local_mouse_position()
	match screen:
		Screen.LIST:
			var h := _hit_at(p)
			hover_kind = h[1] if not h.is_empty() else ""
			hover_value = h[2] if not h.is_empty() else null
			if event is InputEventMouseMotion:
				if hover_kind == "row" and not setup_open:
					sel = hover_value
				return
			if not (event is InputEventMouseButton) or not event.pressed:
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if setup_open:
					return
				var list := _entries(tab_area, _area_tabs(tab_area)[tab_kind])
				var d := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				sel = clampi(sel + d, 0, list.size() - 1)
				return
			if event.button_index == MOUSE_BUTTON_RIGHT:
				setup_open = false
				return
			if event.button_index != MOUSE_BUTTON_LEFT:
				return
			if setup_open and h.is_empty():
				if not Rect2(150, 150, 340, 160).has_point(p):
					setup_open = false
				return
			match hover_kind:
				"setup":
					setup_open = true
					setup_row = 0
				"area":
					tab_area = hover_value
					tab_kind = 0
					sel = 0
					scroll = 0
				"tab":
					tab_kind = hover_value
					sel = 0
					scroll = 0
				"row":
					var list := _entries(tab_area, _area_tabs(tab_area)[tab_kind])
					sel = hover_value
					start_battle(list[sel])
				"lv":
					setup_row = 0
					lv = clampi(lv + int(hover_value), 1, 20)
					_save_settings()
				"setup_row":
					setup_row = 0
				"move":
					setup_row = 1
					wasd = not wasd
					keys.wasd = wasd
					_save_settings()
				"close":
					setup_open = false
		Screen.RESULT:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				screen = Screen.LIST
		Screen.BATTLE:
			_battle_mouse(event, p)


# In battle the mouse works the game's own menus by tapping keys: hover a button to select
# it, click to confirm (Z), right-click to go back (X), wheel for up and down.
const BATTLE_BUTTONS := ["obj_fightbt", "obj_talkbt", "obj_itembt", "obj_sparebt"]
var _battle_hover := -1


func _battle_button_at(p: Vector2) -> int:
	for k in BATTLE_BUTTONS.size():
		var o = vm.first_of(vm.obj_index.get(BATTLE_BUTTONS[k], -1), _ctx())
		if o != null:
			var r: Rect2i = vm.bbox(o)
			if Rect2(r).grow(2).has_point(p):
				return k
	return -1


func _in_main_menu() -> bool:
	var g: Dictionary = vm.globals
	return float(g.get("mnfight", -1.0)) == 0.0 and float(g.get("myfight", -1.0)) == 0.0 and float(g.get("bmenuno", -1.0)) == 0.0


func _select_button(k: int) -> void:
	var coord = vm.globals.get("bmenucoord")
	var cur := int(float(vm.ix(coord, 0))) if coord is Array else 0
	var steps := posmod(k - cur, 4)
	if steps == 3:
		keys.tap(37)
	else:
		for i in steps:
			keys.tap(39)


func _battle_mouse(event: InputEvent, p: Vector2) -> void:
	if auto_index >= 0:
		return
	if event is InputEventMouseMotion:
		if _in_main_menu() and keys.queue.is_empty():
			var k := _battle_button_at(p)
			if k >= 0 and k != _battle_hover:
				_select_button(k)
			_battle_hover = k
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if _in_main_menu():
				var k := _battle_button_at(p)
				if k >= 0:
					var coord = vm.globals.get("bmenucoord")
					if coord is Array and int(float(vm.ix(coord, 0))) != k:
						_select_button(k)
			keys.tap(90)
		MOUSE_BUTTON_RIGHT:
			keys.tap(88)
		MOUSE_BUTTON_WHEEL_UP:
			keys.tap(38)
		MOUSE_BUTTON_WHEEL_DOWN:
			keys.tap(40)

# ---------------------------------------------------------------- sweep
# Runs battles back to back as fast as possible (no waiting for real time) with the
# scripted input, and prints what each one did and which functions it was missing.

# --gmtrace group:seed:lv:frames [--replay real_trace.txt] [--out file]: the fight the
# simulator's "trace" scenario plays, with GameMaker's generator seeded the same way and
# (with --replay) the exact keys the real game saw, logged in the same per-frame format.
func _run_trace(spec: String, replay_path: String, out_path: String) -> void:
	var p := spec.split(":")
	var group := int(p[0])
	trace_seed = int(p[1]) if p.size() > 1 else 1
	lv = clampi(int(p[2]), 1, 20) if p.size() > 2 else 1
	frame_cap = int(p[3]) if p.size() > 3 else 1500
	trace_watch = p[4] if p.size() > 4 else ""
	var idx := -1
	for k in ROSTER.size():
		if idx < 0 and int(ROSTER[k][2].get("bg", -1)) == group:
			idx = k
	if idx < 0:
		print("TRACE no roster battle uses battlegroup %d" % group)
		return
	if replay_path != "":
		trace_replay = {}
		for l in FileAccess.get_file_as_string(replay_path).split("\n"):
			if l.begins_with("T "):
				var f := l.substr(2).split(";")
				trace_replay[int(f[0])] = int(f[1])
	else:
		auto_index = idx
	sweep = true
	trace_lines = []
	bi.fixed_seed = -1
	tracing = true
	start_battle(idx)
	# --shotsdir DIR (needs a window, not --headless): every 50th frame is drawn unblended
	# into a 640x480 image, like the real game's "@shots" trace screenshots.
	var sargs := OS.get_cmdline_user_args()
	var si := sargs.find("--shotsdir")
	var sdir: String = sargs[si + 1] if si >= 0 and si + 1 < sargs.size() else ""
	# --shotevery N saves every Nth frame; --shotblend F draws it F of the way from the
	# previous logic frame (as smooth rendering would between frames) to check blending.
	var severy := 50
	var sblend := 1.0
	if sargs.find("--shotevery") >= 0:
		severy = maxi(1, int(sargs[sargs.find("--shotevery") + 1]))
	if sargs.find("--shotblend") >= 0:
		sblend = float(sargs[sargs.find("--shotblend") + 1])
	var sv: SubViewport = null
	var painter: Node2D = null
	if sdir != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(sdir)
		sv = SubViewport.new()
		sv.size = Vector2i(640, 480)
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		painter = Node2D.new()
		painter.draw.connect(func():
			painter.draw_rect(Rect2(0, 0, 640, 480), Color.BLACK)
			rec.replay(painter, sblend))
		sv.add_child(painter)
		add_child(sv)
	while not battle_over and frames < frame_cap:
		_battle_frame()
		if painter != null and frames % severy == 0:
			painter.queue_redraw()
			await RenderingServer.frame_post_draw
			sv.get_texture().get_image().save_png(sdir.path_join("godot_%d.png" % frames))
	if sv != null:
		sv.queue_free()
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	fa.store_string("\n".join(trace_lines) + "\n")
	print("TRACE %s group=%d seed=%d lv=%d frames=%d result=%s -> %s" % [ROSTER[idx][1], group, trace_seed, lv, frames, result_text if battle_over else "RUNNING", out_path])


func _trace_line(auto) -> void:
	var g: Dictionary = vm.globals
	var s := func(v) -> String: return bi.gm_string(v)
	var f4 := func(v) -> String: return "%.4f" % float(v)
	if frames == 1:
		trace_lines.append("S %s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s" % [s.call(g.get("lv", 0.0)), s.call(g.get("maxhp", 0.0)), s.call(g.get("hp", 0.0)), s.call(g.get("at", 0.0)), s.call(g.get("df", 0.0)), s.call(g.get("wstrength", 0.0)), s.call(g.get("adef", 0.0)), s.call(g.get("weapon", 0.0)), s.call(g.get("armor", 0.0)), s.call(g.get("inv", 0.0)), s.call(g.get("battlegroup", 0.0))])
	var bits := 0
	if auto is Array:
		for b in TRACE_KEYS.size():
			if auto.has(TRACE_KEYS[b]):
				bits |= 1 << b
	var n := 0
	var sx := 0.0
	var sy := 0.0
	for ins in vm.instances:
		if ins.dead or float(ins.v.get("persistent", 0.0)) >= 0.5:
			continue
		n += 1
		sx += float(ins.v["x"])
		sy += float(ins.v["y"])
	if trace_watch != "":
		var wl := ""
		for ins in vm.instances:
			if trace_watch == "*":
				if not ins.dead and float(ins.v.get("persistent", 0.0)) < 0.5:
					wl += "%s,%.4f,%.4f,%.6f|" % [vm.obj_names[ins.obj], float(ins.v["x"]), float(ins.v["y"]), float(ins.v["image_index"])]
			elif not ins.dead and vm.obj_names[ins.obj] == trace_watch:
				wl += "%.9f,%.9f,%.6f,%.6f,%.9f,%.9f,%.9f,%.9f,%.9f|" % [float(ins.v["x"]), float(ins.v["y"]), float(ins.v["image_index"]), float(ins.v["image_speed"]), float(ins.v["image_alpha"]), float(ins.v["speed"]), float(ins.v["hspeed"]), float(ins.v["vspeed"]), float(ins.v["direction"])]
		if wl != "":
			trace_lines.append("W %d;%s" % [frames, wl])
	var wa := OS.get_cmdline_user_args().find("--watch")
	if wa >= 0:
		var wn: String = OS.get_cmdline_user_args()[wa + 1]
		for ins in vm.instances:
			if not ins.dead and vm.obj_names[ins.obj] == wn:
				print("WATCH f=%d %s id=%d x=%s y=%s image_index=%s image_speed=%s image_number=%s sprite=%s alarm0=%s" % [frames, wn, ins.id, bi.gm_string(ins.v["x"]), bi.gm_string(ins.v["y"]), "%.6f" % float(ins.v["image_index"]), "%.6f" % float(ins.v["image_speed"]), str(vm._spr(ins.v["sprite_index"])[0]) if vm._spr(ins.v["sprite_index"]) != null else "-", vm.sprite_names[int(ins.v["sprite_index"])] if int(ins.v["sprite_index"]) >= 0 else "-", str(ins.alarm[0])])
	var da := OS.get_cmdline_user_args().find("--dumpat")
	if da >= 0 and abs(int(OS.get_cmdline_user_args()[da + 1]) - frames) <= 1:
		var names: Array = []
		for ins in vm.instances:
			if not ins.dead and float(ins.v.get("persistent", 0.0)) < 0.5:
				names.append("%s(%.2f,%.2f,d=%s,id=%d)" % [vm.obj_names[ins.obj], float(ins.v["x"]), float(ins.v["y"]), bi.gm_string(ins.v["depth"]), ins.id])
		var dead := 0
		for ins in vm.instances:
			if ins.dead:
				dead += 1
		print("DUMP f=%d live=%d dead_listed=%d all=%d %s" % [frames, names.size(), dead, vm.instances.size(), " ".join(names)])
	var hh = vm.first_of(vm.obj_index["obj_heart"], _ctx())
	var hx = hh.v["x"] if hh != null else -1.0
	var hy = hh.v["y"] if hh != null else -1.0
	var rn := 1 if vm.room == int(vm.consts.get("room_gameover", -1.0)) else 0
	trace_lines.append("T %d;%d;%s;%s;%s;%s;%s;%s;%s;%s;%s;%d;%s;%s;%d" % [frames, bits, f4.call(g.get("hp", 0.0)), f4.call(g.get("km", 0.0)), f4.call(g.get("invc", 0.0)), f4.call(hx), f4.call(hy), s.call(g.get("mnfight", 0.0)), s.call(g.get("myfight", 0.0)), s.call(g.get("turn", 0.0)), s.call(g.get("bmenuno", 0.0)), n, f4.call(sx), f4.call(sy), rn])


func _run_sweep(first: int, last: int) -> void:
	for idx in range(first, last + 1):
		auto_index = idx
		var before: Dictionary = vm.warned.duplicate()
		var unknown_before: Dictionary = bi.unknown.duplicate()
		var t0 := Time.get_ticks_msec()
		var err := ""
		# Same random numbers every sweep (even through randomize()), so runs can be compared.
		bi.fixed_seed = 1000 + idx
		bi.rng.set_seed(bi.fixed_seed)
		start_battle(idx)
		while not battle_over and frames < frame_cap:
			_battle_frame()
			if OS.get_cmdline_user_args().has("--heart") and (frames % 15 == 0 or OS.get_cmdline_user_args().has("--every")):
				var hh = vm.first_of(vm.obj_index["obj_heart"], _ctx())
				if hh != null:
					print("  f=%d turn=%s mn=%s hp=%s inst=%d heart x=%s y=%s spr=%s movement=%s vspeed=%s jumpstage=%s" % [frames, bi.gm_string(vm.globals.get("turn", 0.0)), bi.gm_string(vm.globals.get("mnfight", 0.0)), bi.gm_string(vm.globals.get("hp", 0.0)), vm.instances.size(), bi.gm_string(hh.v["x"]), bi.gm_string(hh.v["y"]), vm.sprite_names[int(hh.v["sprite_index"])], bi.gm_string(hh.v.get("movement", -9)), bi.gm_string(hh.v["vspeed"]), bi.gm_string(hh.v.get("jumpstage", -9))])
			if OS.get_cmdline_user_args().has("--trace") and frames % 30 == 0 and frames <= 300:
				var gg: Dictionary = vm.globals
				var bc = vm.first_of(vm.obj_index["obj_battlecontroller"], _ctx())
				print("  f=%d active=%s cp=%s cs=%s ns=%s alarm0=%s myfight=%s mnfight=%s bmenuno=%s keys=%s writers=%d heart=%s" % [frames, str(bc.v.get("active", "?")) if bc != null else "nobc", str(gg.get("control_pressed")), str(gg.get("control_state")), str(gg.get("control_new_state")), str(bc.alarm[0]) if bc != null else "",  bi.gm_string(gg.get("myfight", 0)), bi.gm_string(gg.get("mnfight", 0)), bi.gm_string(gg.get("bmenuno", 0)), str(keys.held_list()), vm.resolve(vm.obj_index["OBJ_WRITER"], _ctx()).size(), str(vm.first_of(vm.obj_index["obj_heart"], _ctx()).v["x"]) if vm.first_of(vm.obj_index["obj_heart"], _ctx()) != null else "none"])
		var new_warn: Array = []
		for k in vm.warned:
			if not before.has(k):
				new_warn.append(k)
		var new_unknown: Array = []
		for k in bi.unknown:
			if not unknown_before.has(k):
				new_unknown.append(k)
		var g: Dictionary = vm.globals
		var names: Array = []
		var mn = g.get("monstername")
		if mn is Array and mn.size() > 0:
			for n in mn[0]:
				if str(n) != "Error":
					names.append(str(n))
		var where := ""
		if not battle_over:
			where = " room=%s myfight=%s mnfight=%s bmenuno=%s writers=%d inst=%d" % [vm.room_names[vm.room] if vm.room >= 0 else "?", bi.gm_string(g.get("myfight", 0.0)), bi.gm_string(g.get("mnfight", 0.0)), bi.gm_string(g.get("bmenuno", 0.0)), vm.resolve(vm.obj_index["OBJ_WRITER"], _ctx()).size(), vm.instances.size()]
		print("SWEEP %d %s | %s | frames=%d turn=%s hp=%s ms=%d | names=%s%s" % [idx, ROSTER[idx][1], result_text if battle_over else "RUNNING", frames, bi.gm_string(g.get("turn", 0.0)), bi.gm_string(g.get("hp", 0.0)), Time.get_ticks_msec() - t0, ",".join(names), where])
		if vm.prof != null:
			var ks: Array = vm.prof.keys()
			ks.sort_custom(func(x, y): return vm.prof[x] > vm.prof[y])
			for k in ks:
				if str(k).begins_with("alpha:") or str(k).begins_with("snd:"):
					print("   ", k)
			for k in ks.slice(0, 25):
				print("   prof %-28s %8.1f ms" % [k, vm.prof[k] / 1000.0])
			vm.prof = {}
		if not battle_over and OS.get_cmdline_user_args().has("--dump"):
			var objs := {}
			for ins in vm.instances:
				if not ins.dead:
					var on: String = vm.obj_names[ins.obj]
					objs[on] = int(objs.get(on, 0)) + 1
			print("   objects: ", objs)
		if not new_unknown.is_empty():
			print("   unknown: ", ", ".join(new_unknown))
		var other: Array = []
		for k in new_warn:
			if not str(k).begins_with("var:") and not str(k).begins_with("noinst:"):
				other.append(k)
		if not other.is_empty():
			print("   warnings: ", ", ".join(other))
		var vars: Array = []
		for k in new_warn:
			if str(k).begins_with("var:"):
				vars.append(str(k).substr(4))
		if not vars.is_empty():
			print("   unset vars: ", ", ".join(vars.slice(0, 12)), " ..." if vars.size() > 12 else "")
		for p in bi.players:
			p["player"].stop()


# ---------------------------------------------------------------- self-test

var auto_phase := 0


func _auto_keys() -> Array:
	# Confirm through text and menus (Z every 6 frames), FIGHT every turn, and weave
	# left and right during attacks.
	var out: Array = []
	var mn := float(vm.globals.get("mnfight", 0.0))
	if vm.room == int(vm.consts.get("room_gameover", -1.0)):
		if frames % 6 < 2:
			out.append(90)
		return out
	if mn == 2.0:
		if (frames / 20) % 2 == 0:
			out.append(37)
		else:
			out.append(39)
		if frames % 12 < 2:
			out.append(90)
		if (frames / 15) % 4 == 1:
			out.append(38)
	elif frames % 6 < 2:
		out.append(90)
	return out


func _auto_report() -> void:
	if auto_index < 0:
		return
	if shots_dir != "" and frames % 45 == 0 and float(vm.globals.get("mnfight", 0.0)) == 2.0 and shots_taken < 10:
		shots_taken += 1
		var n := shots_taken
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join("engine_%d_%d.png" % [auto_index, n]))
	if frames >= frame_cap:
		_print_report("TIMEOUT")
		get_tree().quit()


func _print_report(tag: String) -> void:
	var g: Dictionary = vm.globals
	var names := []
	var mn = g.get("monstername")
	if mn is Array and mn.size() > 0:
		names = mn[0]
	print("ENGINE %s battle=%s frames=%d hp=%s turn=%s monsters=%s instances=%d" % [tag, ROSTER[auto_index][1], frames, bi.gm_string(g.get("hp", 0.0)), bi.gm_string(g.get("turn", 0.0)), str(names), vm.instances.size()])
	print("PERF logic avg=%.2fms max=%.2fms | draw avg=%.2fms max=%.2fms draws=%d (%.1f per logic frame) | max ops=%d" % [perf_logic_us / 1000.0 / maxi(frames, 1), perf_logic_max / 1000.0, perf_draw_us / 1000.0 / maxi(perf_draws, 1), perf_draw_max / 1000.0, perf_draws, float(perf_draws) / maxi(frames, 1), perf_ops])
	for l in vm.log_lines:
		if l.begins_with("WARN"):
			print("  ", l)
