# Universes: worlds of their own, like Minecraft's, each with everything Undertale ever writes
# (file0..file9, undertale.ini, the True Reset file) in its own folder, so a reset, a route or
# Flowey's memory in one universe never reaches another. Solo and co-op use the same list.
#
#   user://universes/<id>/universe.json   name, cheats, who has played, times
#   user://universes/<id>/save/           the game's own save files
#
# The solo save from before universes (user://undertale) is copied into a universe of its
# own the first time (the old folder is left where it was).
extends RefCounted

const Settings = preload("res://engine_save.gd")

static var ROOT := "user://universes"   # tests point this elsewhere (--universesdir)
static var testing := false             # tests: deleting removes the folder instead of using the Recycle Bin
const KIND := "ube-universe"
const FORMAT := 1
static var LEGACY_SAVES := "user://undertale"
const NAME_MAX := 24


static func new_id() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()


static func dir_of(id: String) -> String:
	return ROOT.path_join(id)


static func save_dir(id: String) -> String:
	return ProjectSettings.globalize_path(dir_of(id).path_join("save"))


static func default_name(player_name: String) -> String:
	var n := player_name.strip_edges()
	if n == "":
		return "New Universe"
	return n + ("'" if n.ends_with("s") else "'s") + " Universe"


# The name to show: as given, else "<first player's name>'s Universe".
static func display_name(u: Dictionary) -> String:
	var n := String(u.get("name", "")).strip_edges()
	if n != "":
		return n
	var ps: Dictionary = u.get("players", {})
	var first := ""
	if ps.has(u.get("owner", "")):
		first = String(ps[u["owner"]].get("name", ""))
	elif not ps.is_empty():
		first = String(ps[ps.keys()[0]].get("name", ""))
	return default_name(first)


static func load_one(id: String) -> Dictionary:
	var r: Dictionary = Settings.read_json(dir_of(id).path_join("universe.json"), KIND, FORMAT)
	if not r["ok"]:
		return {}
	var u: Dictionary = r["data"]
	u["id"] = id
	return u


static func save_one(u: Dictionary) -> void:
	var d := u.duplicate()
	var id: String = d["id"]
	d.erase("id")
	d.erase("save")
	DirAccess.make_dir_recursive_absolute(dir_of(id))
	Settings.write_json(dir_of(id).path_join("universe.json"), KIND, FORMAT, d)


# Every universe, most recently played first, each with "save": what its file0 says.
static func list() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(ROOT):
		return out
	for id in DirAccess.get_directories_at(ROOT):
		var u := load_one(id)
		if u.is_empty():
			continue
		u["save"] = read_save(save_dir(id))
		out.append(u)
	out.sort_custom(func(a, b): return float(a.get("last_played", 0)) > float(b.get("last_played", 0)))
	return out


static func create(uname: String, cheats: bool, player: Dictionary) -> Dictionary:
	var id := new_id()
	var now := Time.get_unix_time_from_system()
	var u := {
		"id": id,
		"name": uname.strip_edges().substr(0, NAME_MAX),
		"cheats": cheats,
		"cheats_since": now if cheats else 0,
		"created": now,
		"last_played": now,
		"owner": player.get("id", ""),
		"players": {},
	}
	_add_player(u, player)
	DirAccess.make_dir_recursive_absolute(save_dir(id))
	save_one(u)
	return u


static func _add_player(u: Dictionary, player: Dictionary) -> void:
	var pid: String = player.get("id", "")
	if pid == "":
		return
	var ps: Dictionary = u.get("players", {})
	ps[pid] = {"name": player.get("name", ""), "last_played": Time.get_unix_time_from_system()}
	u["players"] = ps


static func touch(u: Dictionary, player: Dictionary) -> void:
	u["last_played"] = Time.get_unix_time_from_system()
	_add_player(u, player)
	save_one(u)


static func rename(u: Dictionary, uname: String) -> void:
	u["name"] = uname.strip_edges().substr(0, NAME_MAX)
	save_one(u)


# Cheats can be turned on later, never off again.
static func enable_cheats(u: Dictionary) -> void:
	if u.get("cheats", false):
		return
	u["cheats"] = true
	u["cheats_since"] = Time.get_unix_time_from_system()
	save_one(u)


# To the Recycle Bin, so a mistake can still be undone from Windows.
static func delete(u: Dictionary) -> Error:
	var p := ProjectSettings.globalize_path(dir_of(u["id"]))
	if testing:
		for fn in DirAccess.get_files_at(p.path_join("save")):
			DirAccess.remove_absolute(p.path_join("save").path_join(fn))
		DirAccess.remove_absolute(p.path_join("save"))
		DirAccess.remove_absolute(p.path_join("universe.json"))
		return DirAccess.remove_absolute(p)
	return OS.move_to_trash(p)


# What the card shows, from the save Undertale wrote (scr_saveprocess: name, LV, ... gold on
# line 11, ..., the room and the play time in frames last).
static func read_save(dir: String) -> Dictionary:
	var p := dir.path_join("file0")
	if not FileAccess.file_exists(p):
		return {}
	var lines := FileAccess.get_file_as_string(p).split("\n")
	var clean: Array = []
	for l in lines:
		clean.append(l.strip_edges())
	while not clean.is_empty() and clean[-1] == "":
		clean.pop_back()
	if clean.size() < 12:
		return {}
	return {
		"charname": clean[0],
		"lv": int(float(clean[1])),
		"gold": int(float(clean[10])),
		"room": int(float(clean[clean.size() - 2])),
		"time": float(clean[clean.size() - 1]),
	}


static func time_text(frames: float) -> String:
	var s := int(frames / 30.0)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


static func date_text(unix: float) -> String:
	if unix <= 0:
		return "-"
	var d := Time.get_datetime_dict_from_unix_time(int(unix + Time.get_time_zone_from_system()["bias"] * 60))
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %d" % [d["day"], MONTHS[d["month"] - 1], d["year"]]


# The solo save from before universes, copied into one universe the first time. Returns it,
# or {} when there was nothing to bring over.
static func migrate_legacy(player: Dictionary) -> Dictionary:
	var src := ProjectSettings.globalize_path(LEGACY_SAVES)
	if not DirAccess.dir_exists_absolute(src) or DirAccess.get_files_at(src).is_empty():
		return {}
	var u := create(default_name(player.get("name", "")), false, player)
	var dst := save_dir(u["id"])
	for fn in DirAccess.get_files_at(src):
		DirAccess.copy_absolute(src.path_join(fn), dst.path_join(fn))
	var sv := read_save(dst)
	if not sv.is_empty():
		u["imported"] = true
		save_one(u)
	return u
