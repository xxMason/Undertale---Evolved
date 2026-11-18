# The engine's own files, kept apart from Undertale's: they live in the engine's data
# folder (%APPDATA%\UltimateBattleEngine on Windows, set in project.godot), never in
# Undertale's %LOCALAPPDATA%\UNDERTALE, so nothing a mod saves can touch a real save.
#
# Every file carries a format number. Readers accept older formats by migrating them one
# step at a time, and refuse newer ones (left untouched on disk) instead of misreading them.
extends RefCounted

const Info = preload("res://engine_info.gd")

const SETTINGS_PATH := "user://settings.cfg"
# Settings file as written by builds before the engine had its own data folder.
const LEGACY_DIR := "Godot/app_userdata/UBE Battle Prototype"

const DEFAULTS := {
	"input/wasd": false,
	"player/lv": 1,
	"display/smooth": true,
	"display/window_scale": 2,
	"display/pixel_perfect": true,
	"display/fullscreen": false,
	"debug/overlay": false,
}


# Returns every setting (defaults filled in). "_readonly" is set when the file comes from a
# newer engine, so saving won't overwrite it.
static func load_settings(path := SETTINGS_PATH) -> Dictionary:
	var out := DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK and path == SETTINGS_PATH:
		var legacy := OS.get_environment("APPDATA").path_join(LEGACY_DIR).path_join("settings.cfg")
		if FileAccess.file_exists(legacy):
			err = cfg.load(legacy)
	if err != OK:
		return out
	var fmt := int(cfg.get_value("meta", "format", 0))
	if fmt > Info.SETTINGS_FORMAT:
		push_warning("settings.cfg is format %d, newer than this engine (%d): using defaults" % [fmt, Info.SETTINGS_FORMAT])
		out["_readonly"] = true
		return out
	_migrate_settings(cfg, fmt)
	for k in DEFAULTS:
		var p: PackedStringArray = k.split("/")
		out[k] = cfg.get_value(p[0], p[1], DEFAULTS[k])
	return out


static func save_settings(s: Dictionary, path := SETTINGS_PATH) -> void:
	if s.get("_readonly", false):
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "format", Info.SETTINGS_FORMAT)
	cfg.set_value("meta", "engine", Info.VERSION)
	for k in DEFAULTS:
		var p: PackedStringArray = k.split("/")
		cfg.set_value(p[0], p[1], s.get(k, DEFAULTS[k]))
	cfg.save(path)


# One step per format change. Format 0 is the unversioned file (same keys as format 1).
static func _migrate_settings(cfg: ConfigFile, fmt: int) -> void:
	while fmt < Info.SETTINGS_FORMAT:
		match fmt:
			0:
				pass
		fmt += 1


# Versioned JSON files (game saves will use this): {"format": kind, "version": N, ...}.
# migrate(data, from_version) -> data upgrades one version; returns {"ok", "data", "error"}.
static func read_json(path: String, kind: String, current: int, migrate := Callable()) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		return {"ok": false, "data": {}, "error": "can't read " + path}
	var d = JSON.parse_string(txt)
	if not (d is Dictionary) or d.get("format", "") != kind:
		return {"ok": false, "data": {}, "error": "%s is not a %s file" % [path, kind]}
	var v := int(d.get("version", 0))
	if v > current:
		return {"ok": false, "data": d, "error": "%s is version %d, newer than this engine understands (%d)" % [path, v, current]}
	while v < current:
		if not migrate.is_valid():
			return {"ok": false, "data": d, "error": "no upgrade from version %d" % v}
		d = migrate.call(d, v)
		v += 1
		d["version"] = v
	return {"ok": true, "data": d, "error": ""}


static func write_json(path: String, kind: String, version: int, data: Dictionary) -> Error:
	var d := data.duplicate()
	d["format"] = kind
	d["version"] = version
	d["engine"] = Info.VERSION
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, " ", false))
	return OK
