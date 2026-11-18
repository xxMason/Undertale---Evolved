# Ultimate Battle Engine (Godot): runs Undertale's original battle code through the GML
# runtime in gml/, using code and assets extracted from the player's own copy.
#
# Screens: encounter select -> battle (the original room_battle, battle controller,
# monsters and attacks) -> result -> back to the list.
# Controls in battle are Undertale's (arrows, Z, X, C). F3 toggles WASD, F4 fullscreen,
# Esc leaves a battle (or quits from the list).
# Testing keys: F9 debug overlay, F10 pause, F11 one frame while paused, F12 bug report
# (a replay of the fight so far, a screenshot and a summary; --playback FILE replays one).
#
# Self-test: --battle <index> runs one encounter with scripted input and prints a report;
# --shots <folder> saves screenshots while doing so.
extends Node2D

const VM = preload("res://gml/gml_vm.gd")
const Builtins = preload("res://gml/gml_builtins.gd")
const Keys = preload("res://gml/gml_keys.gd")
const Recorder = preload("res://gml/gml_recorder.gd")
const FightReplay = preload("res://fight_replay.gd")
const Info = preload("res://engine_info.gd")
const Settings = preload("res://engine_save.gd")
const ModLoader = preload("res://mod_loader.gd")
const GameBot = preload("res://game_bot.gd")
const DebugMenu = preload("res://debug_menu.gd")

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

enum Screen { LIST, BATTLE, RESULT, ERROR, GAME }

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
const TRACE_ONLY := -2         # start_battle index for a traced group not in ROSTER
var trace_entry: Array = []

# self-test
var auto_index := -1
var auto_frames := 0
var tracing := false   # a --gmtrace run drives the frames itself
var shots_dir := ""
var shots_taken := 0

# Bug reports and replays (fight_replay.gd).
var recording = null           # FightReplay of the current fight, kept after it ends for F12
var playback = null            # FightReplay being played back (--playback FILE)
var playback_checked := false
var report_at := -1            # --reportat F DIR: save a report at frame F (tests)
var report_dir := ""
var toast := ""
var toast_until := 0
# Debugging.
var overlay := false
var paused := false
var step_once := false
var last_logic_us := 0
# Display options (saved in settings).
var window_scale := 2
var pixel_perfect := true
var fullscreen := false
var mods: Dictionary = {}      # mod_loader.gd result
var debug = null               # the debug menu (F5, debug_menu.gd)
var debug_used: Array = []     # what was changed with it, for saves and bug reports
var game_speed := 1.0          # debug menu: game frames per physics tick
var _speed_acc := 0.0
var settings: Dictionary = {}


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
	settings = Settings.load_settings()
	wasd = bool(settings["input/wasd"])
	lv = clampi(int(settings["player/lv"]), 1, 20)
	smooth = bool(settings["display/smooth"])
	window_scale = clampi(int(settings["display/window_scale"]), 1, 4)
	pixel_perfect = bool(settings["display/pixel_perfect"])
	fullscreen = bool(settings["display/fullscreen"])
	overlay = bool(settings["debug/overlay"])
	if args.has("--overlay"):
		overlay = true
	keys.wasd = wasd
	if DisplayServer.get_name() != "headless" and not args.has("--shotsdir") and menushot == "" and shots_dir == "":
		_apply_display(true)
	# Mods: found and checked at start-up (they don't change anything yet; docs/MODDING.md).
	var mdirs: Array = ModLoader.DEFAULT_DIRS.duplicate()
	i = args.find("--modsdir")
	if i >= 0 and i + 1 < args.size():
		mdirs = [args[i + 1]]
	mods = ModLoader.scan(mdirs)
	if args.has("--mods"):
		for m in mods["mods"]:
			print("MOD %s %s (%s)" % [m["id"], m["version"], m["name"]])
		for d in mods["disabled"]:
			print("MOD DISABLED %s" % d)
		for pr in mods["problems"]:
			print("MOD PROBLEM %s" % pr)
		print("MODS loaded=%d problems=%d" % [mods["mods"].size(), mods["problems"].size()])
		get_tree().quit()
		return
	# The English text table is built once and kept between battles.
	vm.globals["language"] = "en"
	var boot = vm.instance_create(0, 0, vm.obj_index["obj_time"], false)
	vm.call_script("textdata_en", [], {"self": boot, "other": boot, "locals": {}, "args": []})
	text_map = vm.globals.get("text_data_en", -1.0)
	debug = DebugMenu.new()
	add_child(debug)
	debug.setup(self)
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
	i = args.find("--reportat")
	if i >= 0 and i + 2 < args.size():
		report_at = int(args[i + 1])
		report_dir = args[i + 2]
	i = args.find("--playback")
	if i >= 0 and i + 1 < args.size():
		var rp = FightReplay.new()
		var why: String = rp.load_file(args[i + 1])
		if why != "":
			print("PLAYBACK error: " + why)
			get_tree().quit(2)
			return
		await _start_playback(rp, DisplayServer.get_name() == "headless" or args.has("--fast"))
		return
	if auto_index >= 0:
		start_battle(auto_index)
	elif args.has("--game"):
		start_game()
		if DisplayServer.get_name() == "headless":
			# Tests: as fast as possible, not at 30 frames a second.
			while screen == Screen.GAME and frames < frame_cap:
				_game_frame()
			if screen != Screen.GAME:
				get_tree().quit()


# The debug menu's view of the engine.
func in_play() -> bool:
	return screen == Screen.GAME or screen == Screen.BATTLE


func is_game() -> bool:
	return screen == Screen.GAME


func in_battle_room() -> bool:
	return vm.room >= 0 and (vm.room_names[vm.room] == "room_battle" or vm.room_names[vm.room] == "room_floweybattle")


func debug_note(what: String) -> void:
	debug_used.append("f%d %s: %s" % [frames, vm.room_names[vm.room] if vm.room >= 0 else "-", what])
	vm.vlog("DEBUG " + what)


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
	vm.game_restart_requested = false
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
	# Room state: battles never touch save files and never run Game Start.
	bi.room_state_reset()
	bi.room_persist.clear()
	bi.save_dir = ""
	bi.ini_data = {}
	bi.ini_path = ""
	bi.text_files.clear()
	vm.room_snapshots.clear()
	vm.game_started = true
	rec.view_scale = Vector2.ONE


# ---------------------------------------------------------------- the game (overworld)

# Undertale itself, from its first room. Its save files (file0, undertale.ini...) live in
# the engine's data folder (%APPDATA%/UltimateBattleEngine/undertale), never the real ones.
func start_game() -> void:
	_reset_runtime()
	vm.globals.clear()
	var args := OS.get_cmdline_user_args()
	bi.save_dir = ProjectSettings.globalize_path("user://undertale")
	var sd := args.find("--savedir")
	if sd >= 0 and sd + 1 < args.size():
		# Tests: a folder of their own, emptied first, so runs never see each other's saves.
		bi.save_dir = args[sd + 1]
		DirAccess.make_dir_recursive_absolute(bi.save_dir)
		for fn in DirAccess.get_files_at(bi.save_dir):
			DirAccess.remove_absolute(bi.save_dir.path_join(fn))
	vm.game_started = false
	var gs := args.find("--seed")
	bi.rng.set_seed(int(args[gs + 1]) if gs >= 0 and gs + 1 < args.size() else (randi() & 0x7FFFFFFF))
	game_clock = gs >= 0
	bi.clock_ms = 0.0 if game_clock else -1.0
	recording = null
	paused = false
	frames = 0
	rec.clear()
	screen = Screen.GAME
	var order: Array = vm.meta.get("room_order", [])
	var first := int(vm.consts.get(String(order[0]), 0.0)) if not order.is_empty() else 0
	var bf := args.find("--bot")
	if bf >= 0 and bf + 1 < args.size():
		bot = GameBot.new()
		bot.eng = self
		bot.vm = vm
		bot.bi = bi
		var why: String = bot.load_file(args[bf + 1])
		if why != "":
			print("BOT error: " + why)
			bot = null
	vm.load_room(first)
	# --room NAME (testing): boot normally; once the boot leaves its first room, go straight
	# to that room instead (see _game_jump).
	var r := OS.get_cmdline_user_args().find("--room")
	_jump_to = int(vm.consts.get(OS.get_cmdline_user_args()[r + 1], -1.0)) if r >= 0 and r + 1 < OS.get_cmdline_user_args().size() else -1
	vm.vlog("GAME start in %s" % vm.room_names[first])


var _game_room_seen := -1
var _bot_exit := false
var game_clock := false    # --seed: the clock runs on game frames too, so a run repeats exactly
var _game_press = null     # --press "F:K[xN],...": key K held from frame F for N frames (testing)
var _game_shots := {}      # --gameshot "F,F,..." DIR: screenshots at those frames


var bot = null    # --bot FILE: a walkthrough script plays the game (game_bot.gd)


func bot_shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var dir := "user://botshots"
	var i := OS.get_cmdline_user_args().find("--shotsdir")
	if i >= 0 and i + 1 < OS.get_cmdline_user_args().size():
		dir = OS.get_cmdline_user_args()[i + 1]
	_game_shots[frames] = dir
	_bot_shot_names[frames] = name


var _bot_shot_names := {}


func _game_auto_keys():
	if _game_press == null:
		var args := OS.get_cmdline_user_args()
		var i := args.find("--press")
		_game_press = []
		if i >= 0 and i + 1 < args.size():
			for part in args[i + 1].split(",", false):
				var fk := part.split(":")
				var kn := fk[1].split("x")
				_game_press.append([int(fk[0]), int(kn[0]), int(kn[1]) if kn.size() > 1 else 1])
		i = args.find("--gameshot")
		if i >= 0 and i + 2 < args.size():
			for f in args[i + 1].split(",", false):
				_game_shots[int(f)] = args[i + 2]
	if bot != null:
		var k: Array = bot.keys()
		if bot.done:
			print("BOT %s at frame %d in %s" % ["FAILED" if bot.failed != "" else "FINISHED", frames, vm.room_names[vm.room]])
			if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--botexit"):
				_bot_exit = true
		return k
	if _game_press.is_empty():
		return null
	var held: Array = []
	for p in _game_press:
		if frames >= p[0] and frames < p[0] + p[2]:
			held.append(p[1])
	return held


func _game_shot_check() -> void:
	if _game_shots.has(frames):
		var dir: String = _game_shots[frames]
		var f := frames
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(dir)
		var nm: String = _bot_shot_names.get(f, vm.room_names[vm.room])
		get_viewport().get_texture().get_image().save_png(dir.path_join("f%05d_%s.png" % [f, nm]))


var _jump_to := -1


func _game_jump() -> void:
	vm.pending_room = -1
	vm.globals["interact"] = 0.0
	# --set "plot=5,flag.10=1" (testing): story state for the room.
	var st := OS.get_cmdline_user_args().find("--set")
	if st >= 0 and st + 1 < OS.get_cmdline_user_args().size():
		for kv in OS.get_cmdline_user_args()[st + 1].split(",", false):
			var p := kv.split("=")
			if p[0].begins_with("flag."):
				var fl = vm.globals.get("flag")
				vm.globals["flag"] = vm._arr_set(fl, int(p[0].substr(5)), -1, float(p[1]))
			else:
				vm.globals[p[0]] = float(p[1])
	var r := _jump_to
	_jump_to = -1
	vm.load_room(r)


func _game_frame() -> void:
	var tl := Time.get_ticks_usec()
	frames += 1
	if game_clock:
		bi.clock_ms = (frames - 1) * 1000.0 / 30.0
	var gk = _game_auto_keys()
	if gk == null and debug != null and debug.open:
		gk = []     # the debug menu has the keyboard
	keys.poll(gk)
	vm.step_frame(keys)
	vm.room_frame_end()
	var guard := 0
	while vm.pending_room != -1 and guard < 4:
		guard += 1
		var r: int = vm.pending_room
		vm.pending_room = -1
		vm.load_room(r)
		vm.step_frame(keys)
		vm.room_frame_end()
	if _jump_to >= 0 and vm.room != int(vm.consts.get(String(vm.meta["room_order"][0]), 0.0)):
		_game_jump()
	if vm.room != _game_room_seen:
		_game_room_seen = vm.room
		if DisplayServer.get_name() == "headless":
			print("ROOM %s frame %d" % [vm.room_names[vm.room], frames])
	if vm.game_end_requested:
		if vm.game_restart_requested:
			vm.game_restart_requested = false
			start_game()
			return
		_end_game()
		return
	if _bot_exit or ((DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--gameshot") or bot != null) and frames >= frame_cap):
		var pl = vm.first_of(float(vm.obj_index.get("obj_mainchara", -1)), {"self": null, "other": null})
		print("GAME stopped at frame %d in %s, %d instances, player %s, plot %s" % [frames, vm.room_names[vm.room], vm.instances.size(), ("%s,%s" % [pl.v["x"], pl.v["y"]]) if pl != null else "-", bi.gm_string(vm.globals.get("plot", 0.0))])
		if OS.get_cmdline_user_args().has("--dumpinst"):
			for ins in vm.instances:
				var al: Array = []
				for k in ins.alarm.size():
					if float(ins.alarm[k]) >= 0.0:
						al.append("%d=%s" % [k, ins.alarm[k]])
				print("  %d %s (%s,%s) depth=%s vis=%s %s" % [ins.id, vm.obj_names[ins.obj], ins.v["x"], ins.v["y"], ins.v["depth"], ins.v["visible"], " ".join(al)])
			print("  globals plot=%s interact=%s" % [vm.globals.get("plot"), vm.globals.get("interact")])
		screen = Screen.RESULT
		get_tree().quit()
		return
	rec.clear()
	bi.canvas = rec
	if bi.views_on:
		rec.view = Vector2(float(bi.view_xview[0]), float(bi.view_yview[0]))
		var wv := maxf(1.0, float(bi.view_wview[0]))
		var hv := maxf(1.0, float(bi.view_hview[0]))
		rec.view_scale = Vector2(float(bi.room_arr["view_wport"][0]) / wv, float(bi.room_arr["view_hport"][0]) / hv)
	else:
		rec.view = Vector2.ZERO
		rec.view_scale = Vector2.ONE
	vm.draw_frame()
	bi.canvas = null
	if OS.get_cmdline_user_args().has("--viewlog") and frames % 50 == 0:
		print("VIEW f=%d on=%s view=%s scale=%s port=%s" % [frames, bi.views_on, rec.view, rec.view_scale, bi.room_arr["view_wport"][0]])
	last_logic_us = Time.get_ticks_usec() - tl
	if OS.get_cmdline_user_args().has("--watch") and frames % 10 == 0:
		var wl := "WATCH f=%d %s plot=%s interact=%s" % [frames, vm.room_names[vm.room], bi.gm_string(vm.globals.get("plot", 0.0)), bi.gm_string(vm.globals.get("interact", 0.0))]
		for ins in vm.instances:
			var nm: String = vm.obj_names[ins.obj]
			if nm.begins_with("obj_tor") or nm == "obj_mainchara":
				var sp := int(ins.v["sprite_index"])
				wl += " | %s (%s,%s) %s dir=%s pp=%s" % [nm, ins.v["x"], ins.v["y"], vm.sprite_names[sp] if sp >= 0 else "-", ins.v["direction"], bi.gm_string(ins.v.get("path_position", 0.0))]
		print(wl)
	if debug != null:
		debug.test_hooks(frames)
	if not _game_shots.is_empty():
		_game_shot_check()
	if OS.get_cmdline_user_args().has("--smoothprobe"):
		_smooth_probe()
	if not bi.unknown.is_empty() and OS.get_cmdline_user_args().has("--unknown"):
		for k in bi.unknown:
			if bi.unknown[k] == true:
				print("UNKNOWN %s (room %s, frame %d)" % [k, vm.room_names[vm.room], frames])
				bi.unknown[k] = 2


# --smoothprobe (testing): where the player's sprite lands on screen at in-between render
# moments, to check that smoothing moves it evenly and in step with the view.
class ProbeCanvas:
	var xf := Transform2D.IDENTITY
	var owner_ok := false
	var hits: Array = []
	func draw_set_transform(p: Vector2, r := 0.0, s := Vector2.ONE) -> void:
		xf = Transform2D(r, s, 0.0, p)
	func draw_texture(_t, p: Vector2, _m := Color.WHITE) -> void:
		hits.append(xf * p)
	func draw_texture_rect(_t, r: Rect2, _tile := false, _m := Color.WHITE) -> void:
		hits.append(xf * r.position)
	func draw_texture_rect_region(_t, r: Rect2, _src := Rect2(), _m := Color.WHITE) -> void:
		hits.append(xf * r.position)
	func _noop(_a = null, _b = null, _c = null, _d = null, _e = null) -> void:
		pass
	func draw_rect(_a = null, _b = null, _c = null, _d = null) -> void: pass
	func draw_line(_a = null, _b = null, _c = null, _d = null) -> void: pass
	func draw_arc(_a = null, _b = null, _c = null, _d = null, _e = null, _f = null, _g = null) -> void: pass
	func draw_circle(_a = null, _b = null, _c = null) -> void: pass
	func draw_polyline(_a = null, _b = null, _c = null) -> void: pass
	func draw_colored_polygon(_a = null, _b = null) -> void: pass
	func draw_string(_a = null, _b = null, _c = null, _d = null, _e = null, _f = null, _g = null) -> void: pass


func _smooth_probe() -> void:
	var pl = vm.first_of(float(vm.obj_index.get("obj_mainchara", -1)), {"self": null, "other": null})
	if pl == null:
		return
	# Only the player's own drawing: keep its segment of ops.
	var keep: Array = rec.ops
	var start := -1
	for k in keep.size():
		if keep[k][0] == "@owner" and keep[k][1][0] == pl.id:
			start = k
			break
	if start < 0:
		return
	var out := "SMOOTH f=%d x=%s y=%s view=%s" % [frames, pl.v["x"], pl.v["y"], rec.view]
	for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var pc := ProbeCanvas.new()
		rec.replay(pc, f)
		# the player's sprite is the first texture after its owner op: find by replaying only up to it
		var n_before := 0
		for k in start:
			var nm: String = keep[k][0]
			if nm.begins_with("draw_texture"):
				n_before += 1
		var p: Vector2 = pc.hits[n_before] if n_before < pc.hits.size() else Vector2(-1, -1)
		out += "  %.2f:%s" % [f, p]
	print(out)


func _end_game() -> void:
	bi._ini_flush()
	if DisplayServer.get_name() == "headless":
		print("GAME ended (game_end) at frame %d" % frames)
		screen = Screen.LIST
		get_tree().quit()
		return
	for p in bi.players:
		p["player"].stop()
	vm.vlog("GAME end")
	screen = Screen.LIST


func start_battle(index: int) -> void:
	sel = index
	var entry: Array = trace_entry if index == TRACE_ONLY else ROSTER[index]
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
		bi.clock_ms = -1.0
		recording = null
	elif not sweep:
		# Normal play is recorded for bug reports: a known seed here, the clock on game
		# frames, every key per frame (see fight_replay.gd).
		var rs: int = playback.seed if playback != null else (randi() & 0x7FFFFFFF)
		bi.rng.set_seed(rs)
		bi.clock_ms = 0.0
		recording = FightReplay.new()
		recording.begin(_battle_info(index), lv, rs)
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
	vm.load_room(r)


# ---------------------------------------------------------------- frames

func _physics_process(_delta: float) -> void:
	match screen:
		Screen.LIST:
			_list_input()
		Screen.RESULT:
			_poll_menu_keys()
			if _menu_pressed(90) or _menu_pressed(13) or _menu_pressed(88):
				screen = Screen.LIST
		Screen.BATTLE, Screen.GAME:
			if tracing and screen == Screen.BATTLE:
				return
			# Game speed (debug menu): several frames per tick, or a frame every few ticks.
			var n := 0
			if step_once:
				n = 1
			elif not paused:
				_speed_acc += game_speed
				n = int(_speed_acc)
				_speed_acc -= n
			step_once = false
			for k in mini(n, 8):
				if debug != null:
					debug.before_frame()
				if screen == Screen.BATTLE:
					_battle_frame()
				elif screen == Screen.GAME:
					_game_frame()
				else:
					break


var perf_draw_us := 0
var perf_draws := 0
var perf_draw_max := 0
var perf_logic_us := 0
var perf_logic_max := 0
var perf_ops := 0


func _battle_frame() -> void:
	var tl := Time.get_ticks_usec()
	var before: Dictionary = vm.prof.duplicate() if vm.prof != null else {}
	_battle_frame_inner()
	var dt := Time.get_ticks_usec() - tl
	last_logic_us = dt
	perf_logic_us += dt
	if frames > 1:
		perf_logic_max = maxi(perf_logic_max, dt)
		var lim := 8000 if vm.prof != null else 20000
		if dt > lim and OS.get_cmdline_user_args().has("--spikes"):
			var top := ""
			if vm.prof != null:
				# With --prof: where this frame's time went.
				var d := {}
				for k in vm.prof:
					var v: int = int(vm.prof[k]) - int(before.get(k, 0))
					if v > 300:
						d[k] = v
				var ks: Array = d.keys()
				ks.sort_custom(func(x, y): return d[x] > d[y])
				for k in ks.slice(0, 8):
					top += " %s=%.1f" % [k, d[k] / 1000.0]
			print("SPIKE frame=%d %.1fms inst=%d%s" % [frames, dt / 1000.0, vm.instances.size(), top])
	perf_ops = maxi(perf_ops, rec.ops.size())


func _battle_frame_inner() -> void:
	frames += 1
	var auto = _auto_keys() if auto_index >= 0 else null
	if playback != null:
		auto = playback.keys_at(frames)
	if trace_replay != null:
		auto = []
		var bits: int = trace_replay.get(frames, 0)
		for b in TRACE_KEYS.size():
			if bits & (1 << b):
				auto.append(TRACE_KEYS[b])
	if auto == null and debug != null and debug.open:
		auto = []     # the debug menu has the keyboard
	keys.poll(auto)
	if (auto == null and keys.held(27)) or (playback != null and not sweep and Input.is_physical_key_pressed(KEY_ESCAPE)):
		_end_battle("Left the battle.")
		return
	if recording != null:
		recording.add_frame(keys.real.keys())
		bi.clock_ms = (frames - 1) * 1000.0 / 30.0
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
	var tdraw := Time.get_ticks_usec()
	vm.draw_frame()
	if vm.prof != null:
		vm.prof["#draw_events"] = vm.prof.get("#draw_events", 0) + Time.get_ticks_usec() - tdraw
	vm.draw_hook = Callable()
	bi.canvas = null
	if trace_hits:
		_trace_hit(hp1, " (in Draw)")
		vm.coll_log = null
	if debug != null:
		debug.test_hooks(frames)
	if not sweep:
		_auto_report()
	if report_at == frames:
		_save_report(report_dir)
	if playback != null:
		_playback_frame()


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
	if playback != null:
		_playback_frame(true)
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
	for pair in [[KEY_UP, 38], [KEY_DOWN, 40], [KEY_LEFT, 37], [KEY_RIGHT, 39], [KEY_Z, 90], [KEY_ENTER, 13], [KEY_X, 88], [KEY_SHIFT, 88], [KEY_ESCAPE, 27], [KEY_C, 67], [KEY_G, 71], [KEY_W, 38 if wasd else 0], [KEY_S, 40 if wasd else 0]]:
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
	settings["input/wasd"] = wasd
	settings["player/lv"] = lv
	settings["display/smooth"] = smooth
	settings["display/window_scale"] = window_scale
	settings["display/pixel_perfect"] = pixel_perfect
	settings["display/fullscreen"] = fullscreen
	settings["debug/overlay"] = overlay
	Settings.save_settings(settings)


# Window size (a multiple of 640x480), scaling (whole multiples only, or fill the window
# keeping 4:3) and fullscreen. The game itself always renders at 640x480.
func _apply_display(resize := false) -> void:
	var win := get_window()
	win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if pixel_perfect else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		resize = true
	if resize:
		var screen_size := DisplayServer.screen_get_usable_rect(win.current_screen).size
		var n := window_scale
		while n > 1 and (640 * n > screen_size.x or 480 * n > screen_size.y):
			n -= 1
		win.size = Vector2i(640 * n, 480 * n)
		win.move_to_center()


func _list_input() -> void:
	_poll_menu_keys()
	if _menu_pressed(27):
		get_tree().quit()
		return
	if setup_open:
		if _menu_pressed(38):
			setup_row = (setup_row + SETUP_ROWS - 1) % SETUP_ROWS
		if _menu_pressed(40):
			setup_row = (setup_row + 1) % SETUP_ROWS
		var d := (1 if _menu_pressed(39) else 0) - (1 if _menu_pressed(37) else 0)
		if d == 0 and _menu_pressed(90) and setup_row != 0:
			d = 1
		if d != 0:
			_setup_change(setup_row, d)
		if _menu_pressed(88) or _menu_pressed(67):
			setup_open = false
		return
	if _menu_pressed(71):
		start_game()
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
		if debug != null and debug.open:
			# Clicks on the game while the debug menu is open pick objects (Inspect) or move
			# the player; the game itself gets none.
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				debug.game_click(event.position)
			return
		_mouse(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			wasd = not wasd
			keys.wasd = wasd
			_save_settings()
		elif event.keycode == KEY_F2:
			smooth = not smooth
			_save_settings()
		elif event.keycode == KEY_F4:
			fullscreen = DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
			_apply_display()
			_save_settings()
		elif event.keycode == KEY_F9:
			overlay = not overlay
			_save_settings()
		elif event.keycode == KEY_F10 and (screen == Screen.BATTLE or screen == Screen.GAME):
			paused = not paused
			_toast("Paused (F11: one frame, F10: resume)" if paused else "Resumed")
		elif event.keycode == KEY_F11 and (screen == Screen.BATTLE or screen == Screen.GAME):
			paused = true
			step_once = true
		elif event.keycode == KEY_F12:
			_save_report()


# ---------------------------------------------------------------- drawing

var _menushot_wait := 0


var _hitch_t := 0
var _hitch_logic := 0
var _hitch_draw := 0


func _process(_delta: float) -> void:
	queue_redraw()
	# --hitchlog: report every displayed frame that took over 25 ms, with the game logic
	# and drawing time spent in it (the rest is Godot's rendering and waiting).
	if screen == Screen.BATTLE and OS.get_cmdline_user_args().has("--hitchlog"):
		var now := Time.get_ticks_usec()
		if _hitch_t > 0 and now - _hitch_t > 25000:
			print("HITCH frame=%d dt=%.1fms logic=%.1fms draw=%.1fms inst=%d ops=%d" % [frames, (now - _hitch_t) / 1000.0, (perf_logic_us - _hitch_logic) / 1000.0, (perf_draw_us - _hitch_draw) / 1000.0, vm.instances.size(), rec.ops.size()])
		_hitch_t = now
		_hitch_logic = perf_logic_us
		_hitch_draw = perf_draw_us
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
		Screen.BATTLE, Screen.GAME:
			var td := Time.get_ticks_usec()
			rec.replay(self, Engine.get_physics_interpolation_fraction() if smooth and not paused else 1.0)
			perf_draw_us += Time.get_ticks_usec() - td
			perf_draws += 1
			perf_draw_max = maxi(perf_draw_max, Time.get_ticks_usec() - td)
			if overlay:
				_draw_overlay()
			elif paused or playback != null:
				_small(8, 14, ("PAUSED  " if paused else "") + ("REPLAY" if playback != null else ""), Color(1, 1, 0))
	if toast != "" and Time.get_ticks_msec() < toast_until:
		var w := ThemeDB.fallback_font.get_string_size(toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(316 - w / 2, 452, w + 8, 20), Color(0, 0, 0, 0.8))
		_small(320 - w / 2, 466, toast, Color(1, 1, 0.6))


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
	_text(24, 450, "[ARROWS/MOUSE] Choose  [Z/CLICK] Fight  [C] Setup  [G] Play the game  [ESC] Quit", 8421504, "fnt_maintext")
	var mod_n: int = mods.get("mods", []).size()
	var mod_p: int = mods.get("problems", []).size()
	if mod_n > 0 or mod_p > 0:
		_text(616 - _font_w("Mods: %d" % mod_n), 428, "Mods: %d%s" % [mod_n, "  (%d with problems)" % mod_p if mod_p > 0 else ""], 16776960 if mod_p > 0 else 8421504, "fnt_maintext")
	if setup_open:
		hits.clear()     # the panel takes the mouse while it is open
		draw_rect(SETUP_RECT, Color.BLACK)
		draw_rect(SETUP_RECT, Color.WHITE, false, 3.0)
		_text(SETUP_RECT.position.x + 26, SETUP_RECT.position.y + 14, "SETUP", 16777215)
		var y0 := int(SETUP_RECT.position.y) + 56
		for r in SETUP_ROWS:
			var ry := y0 + r * SETUP_ROW_H
			var c := 65535 if setup_row == r else 16777215
			var label: String = SETUP_LABELS[r]
			var value := _setup_value(r)
			_text(196, ry, label, c, "fnt_maintext")
			_text(354, ry, "<", 16777215 if _hovered("adj", [r, -1]) else c, "fnt_maintext")
			_hit(Rect2(346, ry - 4, 22, 24), "adj", [r, -1])
			_text(374, ry, value, c, "fnt_maintext")
			_text(484, ry, ">", 16777215 if _hovered("adj", [r, 1]) else c, "fnt_maintext")
			_hit(Rect2(476, ry - 4, 22, 24), "adj", [r, 1])
			_hit(Rect2(170, ry - 4, 170, 24), "setup_row", r)
			if r == setup_row:
				_heart(172, ry + 2)
		if setup_row == 0:
			_text(196, y0 + SETUP_ROWS * SETUP_ROW_H + 2, "HP %d" % (99 if lv == 20 else 16 + lv * 4), 8421504, "fnt_maintext")
		var close_r := Rect2(SETUP_RECT.end.x - 96, SETUP_RECT.end.y - 34, 80, 24)
		draw_rect(close_r, Color(1, 1, 0) if _hovered("close") else Color(0.5, 0.5, 0.5), false, 2.0)
		_text(close_r.position.x + 16, close_r.position.y + 4, "CLOSE", 65535 if _hovered("close") else 16777215, "fnt_maintext")
		_hit(close_r, "close")
		_text(SETUP_RECT.position.x + 16, SETUP_RECT.end.y - 30, "[UP/DOWN] Choose  [LEFT/RIGHT] Change", 8421504, "fnt_maintext")


const SETUP_RECT := Rect2(150, 96, 370, 300)
const SETUP_ROW_H := 30
const SETUP_ROWS := 6
const SETUP_LABELS := ["LV", "Movement", "Smooth motion", "Window size", "Scaling", "Fullscreen"]


func _setup_value(r: int) -> String:
	match r:
		0:
			return "%d" % lv
		1:
			return "WASD" if wasd else "ARROWS"
		2:
			return "ON" if smooth else "OFF"
		3:
			return "%dx (%dx%d)" % [window_scale, 640 * window_scale, 480 * window_scale]
		4:
			return "PIXEL-PERFECT" if pixel_perfect else "FILL"
		5:
			return "ON" if fullscreen else "OFF"
	return ""


# Smooth motion draws between the game's 30 frames a second at the screen's own rate;
# the game logic itself always runs at 30, exactly like the original.
func _setup_change(r: int, d: int) -> void:
	setup_row = r
	match r:
		0:
			lv = clampi(lv + d, 1, 20)
		1:
			wasd = not wasd
			keys.wasd = wasd
		2:
			smooth = not smooth
		3:
			window_scale = wrapi(window_scale + d, 1, 5)
			fullscreen = false
			_apply_display(true)
		4:
			pixel_perfect = not pixel_perfect
			_apply_display()
		5:
			fullscreen = not fullscreen
			_apply_display(true)
	_save_settings()


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
				if not SETUP_RECT.has_point(p):
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
				"adj":
					_setup_change(int(hover_value[0]), int(hover_value[1]))
				"setup_row":
					setup_row = int(hover_value)
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
	if auto_index >= 0 or playback != null:
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

# ---------------------------------------------------------------- bug reports, replays, overlay

func _toast(t: String, ms := 4000) -> void:
	toast = t
	toast_until = Time.get_ticks_msec() + ms
	vm.vlog("TOAST " + t)


func _small(x: float, y: float, t: String, c := Color.WHITE) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)


func _battle_info(index: int) -> Dictionary:
	var e: Array = trace_entry if index == TRACE_ONLY else ROSTER[index]
	return {"index": index, "area": e[0], "name": e[1], "spec": e[2]}


# A short fingerprint of the fight's state; a replay must reach the same one.
func _state_sig() -> String:
	var n := 0
	var sx := 0.0
	var sy := 0.0
	for ins in vm.instances:
		if ins.dead or float(ins.v.get("persistent", 0.0)) >= 0.5:
			continue
		n += 1
		sx += float(ins.v["x"])
		sy += float(ins.v["y"])
	var g: Dictionary = vm.globals
	return "f=%d hp=%s turn=%s n=%d sx=%.4f sy=%.4f room=%d" % [frames, bi.gm_string(g.get("hp", 0.0)), bi.gm_string(g.get("turn", 0.0)), n, sx, sy, vm.room]


# F12: the fight so far as a replay, a screenshot and a readable summary, in its own folder.
func _save_report(dir := "") -> void:
	if screen == Screen.GAME:
		_save_game_report()
		return
	if recording == null or recording.frames.is_empty():
		_toast("Nothing to report yet: start a fight first.")
		return
	if dir == "":
		dir = "user://reports/" + Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	DirAccess.make_dir_recursive_absolute(dir)
	recording.check = {"frame": frames, "state": _state_sig()}
	var err: Error = recording.save(dir.path_join("replay.json"))
	if err != OK:
		_toast("Couldn't save the bug report (error %d)." % err)
		return
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(dir.path_join("screenshot.png"))
	var counts := {}
	for ins in vm.instances:
		if not ins.dead:
			var nm: String = vm.obj_names[ins.obj]
			counts[nm] = counts.get(nm, 0) + 1
	var objs: Array = []
	for k in counts:
		objs.append("%s x%d" % [k, counts[k]])
	objs.sort()
	var g: Dictionary = vm.globals
	var lines := [
		"%s %s bug report" % [Info.NAME, Info.VERSION],
		"Saved: %s" % Time.get_datetime_string_from_system(false, true),
		"Battle: %s (%s), group %s" % [recording.battle.get("name", "?"), recording.battle.get("area", "?"), bi.gm_string(g.get("battlegroup", 0.0))],
		"Player: LV %d, HP %s / %s" % [recording.lv, bi.gm_string(g.get("hp", 0.0)), bi.gm_string(g.get("maxhp", 0.0))],
		"Frame: %d (%s)" % [frames, result_text if battle_over else "in battle"],
		"State: %s" % recording.check["state"],
		"Seed: %d" % recording.seed,
		"Objects: " + ", ".join(objs),
		"Debug menu: " + ("; ".join(debug_used) + " (the replay doesn't repeat these changes)" if not debug_used.is_empty() else "not used"),
		"",
		"Describe what went wrong here:",
		"",
		"",
		"Replay it (from the project folder):",
		"  godot --path godot -- --playback \"%s\"" % ProjectSettings.globalize_path(dir.path_join("replay.json")),
	]
	var f := FileAccess.open(dir.path_join("summary.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
	var where := ProjectSettings.globalize_path(dir)
	print("REPORT saved frame=%d state=%s -> %s" % [frames, recording.check["state"], where])
	_toast("Bug report saved: " + where, 6000)


# The overworld has no replays yet: its report is a screenshot, where the player is, and a
# copy of the game's save files (load them to get back to the same place).
func _save_game_report() -> void:
	var dir := "user://reports/" + Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	DirAccess.make_dir_recursive_absolute(dir.path_join("saves"))
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(dir.path_join("screenshot.png"))
	bi._ini_flush()
	for fn in DirAccess.get_files_at(bi.save_dir):
		DirAccess.copy_absolute(bi.save_dir.path_join(fn), ProjectSettings.globalize_path(dir.path_join("saves/" + fn)))
	var g: Dictionary = vm.globals
	var pl = vm.first_of(float(vm.obj_index.get("obj_mainchara", -1)), {"self": null, "other": null})
	var lines := [
		"%s %s bug report (overworld)" % [Info.NAME, Info.VERSION],
		"Saved: %s" % Time.get_datetime_string_from_system(false, true),
		"Room: %s, frame %d" % [vm.room_names[vm.room], frames],
		"Player: %s" % (("(%s, %s)" % [pl.v["x"], pl.v["y"]]) if pl != null else "-"),
		"Story: plot %s, interact %s, HP %s / %s, LV %s" % [bi.gm_string(g.get("plot", 0.0)), bi.gm_string(g.get("interact", 0.0)), bi.gm_string(g.get("hp", 0.0)), bi.gm_string(g.get("maxhp", 0.0)), bi.gm_string(g.get("lv", 0.0))],
		"saves/ holds the game's save files at this moment.",
		"Debug menu: " + ("; ".join(debug_used) if not debug_used.is_empty() else "not used"),
		"",
		"Describe what went wrong here (and what real Undertale does instead):",
		"",
	]
	var f := FileAccess.open(dir.path_join("summary.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("
".join(lines) + "
")
	var where := ProjectSettings.globalize_path(dir)
	print("REPORT saved (overworld) -> " + where)
	_toast("Bug report saved: " + where, 6000)


# --playback FILE: replays a recorded fight. Fast (headless or --fast) runs it through,
# checks the state at the report's frame and quits; otherwise it plays on screen and hands
# the controls to the player when the recording runs out.
func _start_playback(rp, fast: bool) -> void:
	playback = rp
	playback_checked = false
	lv = rp.lv
	var b: Dictionary = rp.battle
	var idx := int(b.get("index", -1))
	if idx < 0 or idx >= ROSTER.size() or ROSTER[idx][1] != b.get("name", ""):
		trace_entry = [b.get("area", "TRACE"), b.get("name", "?"), b.get("spec", {})]
		idx = TRACE_ONLY
	print("PLAYBACK %s lv=%d seed=%d frames=%d check=%s" % [b.get("name", "?"), rp.lv, rp.seed, rp.frames.size(), str(rp.check.get("frame", "-"))])
	if not fast:
		start_battle(idx)
		_toast("Replaying a recorded fight (Esc leaves)")
		return
	tracing = true
	start_battle(idx)
	var last := maxi(rp.frames.size(), int(rp.check.get("frame", 0)))
	while not battle_over and frames < last:
		_battle_frame()
	if not playback_checked:
		_playback_frame(true)
	var ok := String(rp.check.get("state", "")) == _state_sig()
	print("PLAYBACK END frames=%d %s" % [frames, result_text if battle_over else "RUNNING"])
	get_tree().quit(0 if ok else 1)


func _playback_frame(ended := false) -> void:
	var cf := int(playback.check.get("frame", -1))
	if not playback_checked and (frames == cf or (ended and cf >= 0 and frames >= cf)):
		playback_checked = true
		var now := _state_sig()
		var want := String(playback.check.get("state", ""))
		if now == want:
			print("PLAYBACK CHECK frame=%d MATCH %s" % [frames, now])
			_toast("Replay reached the reported moment in the same state.")
		else:
			print("PLAYBACK CHECK frame=%d DIFF want: %s got: %s" % [frames, want, now])
			_toast("Replay DIFFERS from the report at frame %d." % frames, 8000)
	if not tracing and (ended or frames >= playback.frames.size()):
		playback = null
		if not ended:
			_toast("Replay finished: you have the controls.")


# F9: every instance's collision box (red: the SOUL, yellow: has collision events, green:
# the rest), the fight's state, and the instances under the mouse.
func _draw_overlay() -> void:
	var view := Vector2(float(bi.view_xview[0]), float(bi.view_yview[0]))
	var mouse := get_local_mouse_position()
	var under: Array = []
	for ins in vm.instances:
		if ins.dead:
			continue
		var r: Rect2i = vm.bbox(ins)
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		var rr := Rect2((Vector2(r.position) - view) * rec.view_scale, Vector2(r.size) * rec.view_scale)
		var nm: String = vm.obj_names[ins.obj]
		var c := Color(0.3, 1, 0.3, 0.5)
		if nm == "obj_heart":
			c = Color(1, 0.2, 0.2, 0.95)
		elif not (vm.collision_targets[ins.obj] as Array).is_empty():
			c = Color(1, 1, 0, 0.8)
		draw_rect(rr, c, false, 1.0)
		if rr.has_point(mouse):
			under.append(ins)
	var g: Dictionary = vm.globals
	var s := func(k: String) -> String: return bi.gm_string(g.get(k, 0.0))
	var room_name: String = vm.room_names[vm.room] if vm.room >= 0 and vm.room < vm.room_names.size() else "-"
	var lines := [
		"frame %d  logic %.1f ms  instances %d%s%s" % [frames, last_logic_us / 1000.0, vm.instances.size(), "  PAUSED" if paused else "", "  REPLAY" if playback != null else ""],
		"room %s  group %s  seed %s" % [room_name, s.call("battlegroup"), str(recording.seed) if recording != null else "-"],
		"hp %s/%s  invc %s  km %s  turn %s" % [s.call("hp"), s.call("maxhp"), s.call("invc"), s.call("km"), s.call("turn")],
		("plot %s  interact %s  entrance %s  view %d,%d" % [s.call("plot"), s.call("interact"), s.call("entrance"), int(view.x), int(view.y)]) if screen == Screen.GAME else ("mnfight %s  myfight %s  bmenuno %s  turntimer %s" % [s.call("mnfight"), s.call("myfight"), s.call("bmenuno"), s.call("turntimer")]),
		"F10 pause  F11 step  F12 bug report  F9 hide" if screen != Screen.GAME else "F10 pause  F11 step  F9 hide",
	]
	draw_rect(Rect2(2, 2, 330, lines.size() * 14 + 6), Color(0, 0, 0, 0.7))
	for k in lines.size():
		_small(6, 15 + k * 14, lines[k], Color(1, 1, 0.6) if k == 0 else Color.WHITE)
	if under.is_empty():
		return
	var info: Array = []
	for ins in under.slice(0, 6):
		var v: Dictionary = ins.v
		var al: Array = []
		for a in ins.alarm.size():
			if int(ins.alarm[a]) > 0:
				al.append("a%d=%d" % [a, int(ins.alarm[a])])
		var spr := int(v["sprite_index"])
		var sname: String = vm.sprite_names[spr] if spr >= 0 and spr < vm.sprite_names.size() else "-"
		info.append("%s #%d (%.2f, %.2f) depth %s %s img %.2f %s" % [vm.obj_names[ins.obj], ins.id, float(v["x"]), float(v["y"]), bi.gm_string(v["depth"]), sname, float(v["image_index"]), " ".join(al)])
	var y0 := 476 - info.size() * 14
	draw_rect(Rect2(2, y0 - 12, 636, info.size() * 14 + 6), Color(0, 0, 0, 0.75))
	for k in info.size():
		_small(6, y0 + k * 14, info[k])


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
		# Any of the game's battle groups can be traced, not only the fight-select ones
		# (Moldessa, Migosp... appear only in groups the roster doesn't list).
		trace_entry = ["TRACE", "Group %d" % group, {"bg": group}]
		idx = TRACE_ONLY
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
	print("TRACE %s group=%d seed=%d lv=%d frames=%d result=%s -> %s" % [(trace_entry if idx == TRACE_ONLY else ROSTER[idx])[1], group, trace_seed, lv, frames, result_text if battle_over else "RUNNING", out_path])


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
