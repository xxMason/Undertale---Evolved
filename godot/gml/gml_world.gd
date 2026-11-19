# One running room: its instances, views, tiles, drawing state, random generator and
# sounds. The GML machine (gml_vm.gd) and its builtins hold the code, assets and shared
# globals once; every world keeps its own copy of the per-room state below, and the host
# switches between worlds with use() between frames. A game with one room running has one
# world and behaves exactly as before (see docs/MULTIPLAYER.md, stage 1).
#
# The machine itself still holds the active world's state in its own fields, so the hot
# paths (events, collisions, drawing) are unchanged; switching copies a few references.
extends RefCounted

const Random = preload("res://gml/gml_random.gd")

# Per-room fields of gml_vm.gd.
const VM_FIELDS := ["instances", "by_id", "next_id", "room", "room_width", "room_height",
	"room_speed", "pending_room", "step_no", "obj_changed_step", "_draw_pass",
	"scoped", "in_scope", "inst_keys", "aim_split", "aim_skip",
	# its players (mp_rooms.gd): who is in it, their instances, whose values its objects see
	"player_insts", "multi_players", "primary_owner", "claimed", "pending_owner", "scene_owner", "party_on"]
# Per-room fields of gml_builtins.gd.
const BI_FIELDS := ["keys", "canvas", "relative", "rng", "audio_root", "players", "next_sound_id",
	"draw_color", "draw_alpha", "draw_font", "halign", "valign",
	"view_xview", "view_yview", "view_wview", "view_hview", "room_arr", "views_on",
	"show_colour", "background_color", "tiles", "tiles_sorted", "next_tile_id", "heard"]
# Each world numbers its instances, sounds and tiles from its own base, so ids never
# clash when a player (and their instances) moves from one world to another. World 0
# keeps the game's own numbering.
const ID_SPACING := 1000000000.0

var index := 0
var vm_state := {}
var bi_state := {}
# Normally every world shares the machine's globals (story flags, LV...), its parked
# persistent rooms and its open save files. A test world can keep private copies of all of
# them (see private_copy), so it cannot disturb the others. (Shared worlds simply share these:
# a persistent room parked by one world is the same room for every other.)
const SHARED := [["vm", "globals"], ["vm", "room_snapshots"], ["bi", "room_persist"],
	["bi", "ini_data"], ["bi", "ini_path"], ["bi", "ini_dirty"], ["bi", "text_files"],
	["bi", "next_file_id"]]
var private = null


# The machine's current state becomes world 0.
static func from_current(vm) -> RefCounted:
	var w = load("res://gml/gml_world.gd").new()
	w.index = 0
	w.capture(vm)
	return w


# An empty world numbered k (k >= 1): no room loaded yet, nothing playing.
static func empty(vm, k: int, seed := 0) -> RefCounted:
	var w = load("res://gml/gml_world.gd").new()
	w.index = k
	var base := 100001 + int(ID_SPACING) * k
	w.vm_state = {"instances": [], "by_id": {}, "next_id": base, "room": -1,
		"room_width": 640, "room_height": 480, "room_speed": 30, "pending_room": -1,
		"step_no": 0, "obj_changed_step": -1, "_draw_pass": 0,
		"scoped": null, "in_scope": false, "inst_keys": {}, "aim_split": false, "aim_skip": {},
		"player_insts": [], "multi_players": [], "primary_owner": 0, "claimed": [], "pending_owner": -1, "scene_owner": -1, "party_on": false}
	var rng = Random.new()
	rng.set_seed(seed)
	w.bi_state = {"keys": null, "canvas": null, "relative": false, "rng": rng, "audio_root": null,
		"players": [], "next_sound_id": 100000 + int(ID_SPACING) * k,
		"draw_color": 16777215, "draw_alpha": 1.0, "draw_font": -1, "halign": 0, "valign": 0,
		"views_on": false, "show_colour": true, "background_color": 0.0,
		"tiles": [], "tiles_sorted": true, "next_tile_id": 10000000 + int(ID_SPACING) * k, "heard": true}
	# Fresh view and background arrays, made by the builtins' own reset on a scratch copy.
	var bi = vm.builtins
	var keep := {}
	for f in ["room_arr", "view_xview", "view_yview", "view_wview", "view_hview", "views_on", "show_colour", "tiles", "tiles_sorted"]:
		keep[f] = bi.get(f)
	bi.room_arr = {}
	bi.room_state_reset()
	for f in ["room_arr", "view_xview", "view_yview", "view_wview", "view_hview"]:
		w.bi_state[f] = bi.get(f)
	for f in keep:
		bi.set(f, keep[f])
	return w


func capture(vm) -> void:
	for f in VM_FIELDS:
		vm_state[f] = vm.get(f)
	for f in BI_FIELDS:
		bi_state[f] = vm.builtins.get(f)


func apply(vm) -> void:
	for f in VM_FIELDS:
		vm.set(f, vm_state[f])
	for f in BI_FIELDS:
		vm.builtins.set(f, bi_state[f])
	# Every cache keyed on the instance list starts over.
	vm.inst_version += 1


static func private_copy(vm) -> Dictionary:
	var d := _get_shared(vm)
	d["vm.globals"] = (d["vm.globals"] as Dictionary).duplicate(true)
	d["vm.room_snapshots"] = {}
	d["bi.room_persist"] = (d["bi.room_persist"] as Dictionary).duplicate()
	d["bi.ini_data"] = {}
	d["bi.ini_path"] = ""
	d["bi.ini_dirty"] = false
	d["bi.text_files"] = {}
	return d


static func _get_shared(vm) -> Dictionary:
	var d := {}
	for f in SHARED:
		d[f[0] + "." + f[1]] = (vm if f[0] == "vm" else vm.builtins).get(f[1])
	return d


static func _set_shared(vm, d: Dictionary) -> void:
	for f in SHARED:
		(vm if f[0] == "vm" else vm.builtins).set(f[1], d[f[0] + "." + f[1]])


# Switches the machine from world `from` (whose state is saved) to this one. Worlds that
# share hand the shared state along; a private world swaps its own in, and the shared state
# waits on the machine until a sharing world is used again.
func use(vm, from) -> void:
	if from == self:
		return
	var from_priv: bool = from != null and from.private != null
	if from != null:
		from.capture(vm)
		if from_priv:
			from.private = _get_shared(vm)
	if private != null:
		if not from_priv:
			vm.set_meta("shared_state", _get_shared(vm))
		_set_shared(vm, private)
	elif from_priv:
		_set_shared(vm, vm.get_meta("shared_state"))
	apply(vm)
