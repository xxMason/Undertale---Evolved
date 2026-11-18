# Fight recordings for bug reports: which battle, the player, the random seed and every
# key held on every game frame. Playing one back reproduces the fight exactly, because the
# battle code is deterministic once the seed, the keys and the clock are fixed (the engine
# runs the clock on game frames while recording; see Builtins.clock_ms).
#
# File: JSON, {"format": "ube-replay", "version": 1, ...}. Keys are stored run-length
# encoded as [[frames, [codes...]], ...], codes in GameMaker numbers in the order the
# engine saw them (that order decides keyboard event order, so it is kept).
extends RefCounted

const Info = preload("res://engine_info.gd")

var battle: Dictionary = {}   # {"index", "name", "area", "spec"}
var lv := 1
var seed := 0
var frames: Array = []        # one Array of key codes per game frame
var check := {}               # {"frame": N, "state": "..."} state when the report was made
var note := ""


func begin(battle_info: Dictionary, player_lv: int, rng_seed: int) -> void:
	battle = battle_info
	lv = player_lv
	seed = rng_seed
	frames = []
	check = {}


func add_frame(codes: Array) -> void:
	frames.append(codes.duplicate())


func to_dict() -> Dictionary:
	var runs: Array = []
	for f in frames:
		if not runs.is_empty() and runs[-1][1] == f:
			runs[-1][0] += 1
		else:
			runs.append([1, f])
	return {
		"format": "ube-replay",
		"version": Info.REPLAY_FORMAT,
		"engine": Info.VERSION,
		"created": Time.get_datetime_string_from_system(false, true),
		"battle": battle,
		"player": {"lv": lv},
		"seed": seed,
		"frame_count": frames.size(),
		"keys": runs,
		"check": check,
		"note": note,
	}


# Returns "" on success, otherwise why the file can't be used.
func from_dict(d: Dictionary) -> String:
	if d.get("format", "") != "ube-replay":
		return "not a replay file"
	var v := int(d.get("version", 0))
	if v < 1 or v > Info.REPLAY_FORMAT:
		return "replay format %d is newer than this engine understands (%d)" % [v, Info.REPLAY_FORMAT]
	battle = d.get("battle", {})
	lv = int(d.get("player", {}).get("lv", 1))
	seed = int(d.get("seed", 0))
	check = d.get("check", {})
	note = String(d.get("note", ""))
	frames = []
	for r in d.get("keys", []):
		var codes: Array = []
		for c in r[1]:
			codes.append(int(c))
		for k in int(r[0]):
			frames.append(codes)
	return ""


func save(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), " ", false))
	return OK


func load_file(path: String) -> String:
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		return "can't read " + path
	var d = JSON.parse_string(txt)
	if not (d is Dictionary):
		return "not valid JSON: " + path
	return from_dict(d)


# Keys for a frame (1-based, as the engine counts), empty once the recording runs out.
func keys_at(frame: int) -> Array:
	return frames[frame - 1] if frame >= 1 and frame <= frames.size() else []
