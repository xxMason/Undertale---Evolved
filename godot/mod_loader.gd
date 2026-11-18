# Finds mods, checks their manifests and decides the load order. Mods don't change
# anything yet (the content they will be able to replace comes with the Ruins port); this
# fixes the format early so mods made later don't need rewriting. See docs/MODDING.md.
#
# A mod is a folder with a mod.json:
#   {"format": 1, "id": "author.mod_name", "name": "...", "version": "1.0.0",
#    "engine": ">=0.3.0", "description": "...", "authors": ["..."],
#    "requires": ["other.id"], "load_after": ["other.id"], "conflicts": ["other.id"],
#    "enabled": true}
# Mods never contain Undertale's own files: the engine reads those from the player's copy.
extends RefCounted

const Info = preload("res://engine_info.gd")

const DEFAULT_DIRS := ["user://mods"]


# Returns {"mods": [manifest, ...] in load order, "problems": ["...", ...],
#          "disabled": [id, ...]}. A mod with a problem is left out, never half-loaded.
static func scan(dirs: Array = DEFAULT_DIRS) -> Dictionary:
	var problems: Array = []
	var found := {}
	var disabled: Array = []
	for root in dirs:
		var da := DirAccess.open(root)
		if da == null:
			continue
		for sub in da.get_directories():
			var dir: String = String(root).path_join(sub)
			var mpath := dir.path_join("mod.json")
			if not FileAccess.file_exists(mpath):
				continue
			var m = JSON.parse_string(FileAccess.get_file_as_string(mpath))
			var why := _check(m)
			if why != "":
				problems.append("%s: %s" % [sub, why])
				continue
			m["dir"] = dir
			if not bool(m.get("enabled", true)):
				disabled.append(m["id"])
				continue
			if found.has(m["id"]):
				problems.append("%s: id %s is used by two mods (%s)" % [sub, m["id"], found[m["id"]]["dir"]])
				continue
			found[m["id"]] = m
	# Dependencies and conflicts, repeated until nothing more drops out.
	var changed := true
	while changed:
		changed = false
		for id in found.keys():
			var m: Dictionary = found[id]
			for r in m.get("requires", []):
				if not found.has(r):
					problems.append("%s: needs %s, which isn't installed or failed to load" % [id, r])
					found.erase(id)
					changed = true
					break
			if not found.has(id):
				continue
			for c in m.get("conflicts", []):
				if found.has(c):
					problems.append("%s: conflicts with %s" % [id, c])
					found.erase(id)
					changed = true
					break
	# Load order: requires and load_after first, otherwise alphabetical by id.
	var order: Array = []
	var state := {}   # id -> 1 visiting, 2 done
	var ids: Array = found.keys()
	ids.sort()
	for id in ids:
		_visit(id, found, state, order, problems)
	var out: Array = []
	for id in order:
		out.append(found[id])
	return {"mods": out, "problems": problems, "disabled": disabled}


static func _visit(id: String, found: Dictionary, state: Dictionary, order: Array, problems: Array) -> void:
	if state.get(id, 0) == 2:
		return
	if state.get(id, 0) == 1:
		problems.append("%s: load order loops back to itself" % id)
		return
	state[id] = 1
	var m: Dictionary = found[id]
	var before: Array = []
	for d in m.get("requires", []) + m.get("load_after", []):
		if found.has(d) and not before.has(d):
			before.append(d)
	before.sort()
	for d in before:
		_visit(d, found, state, order, problems)
	state[id] = 2
	order.append(id)


static func _check(m) -> String:
	if not (m is Dictionary):
		return "mod.json is not valid JSON"
	var fmt := int(m.get("format", 0))
	if fmt < 1 or fmt > Info.MOD_FORMAT:
		return "manifest format %s is not supported (this engine reads %d)" % [str(m.get("format")), Info.MOD_FORMAT]
	var id := String(m.get("id", ""))
	var re := RegEx.create_from_string("^[a-z0-9_]+(\\.[a-z0-9_]+)+$")
	if re.search(id) == null:
		return "id \"%s\" must look like author.mod_name (lower case, digits, _)" % id
	if String(m.get("name", "")) == "":
		return "no name"
	if parse_version(String(m.get("version", ""))).is_empty():
		return "version \"%s\" must be like 1.2.3" % str(m.get("version"))
	var need := String(m.get("engine", ""))
	if need != "" and not version_matches(Info.VERSION, need):
		return "needs engine %s, this is %s" % [need, Info.VERSION]
	for key in ["requires", "load_after", "conflicts", "authors"]:
		if m.has(key) and not (m[key] is Array):
			return "%s must be a list" % key
	return ""


static func parse_version(v: String) -> Array:
	var p := v.strip_edges().split(".")
	if p.size() < 1 or p.size() > 3:
		return []
	var out: Array = []
	for x in p:
		if not x.is_valid_int() or int(x) < 0:
			return []
		out.append(int(x))
	while out.size() < 3:
		out.append(0)
	return out


static func _cmp(a: Array, b: Array) -> int:
	for i in 3:
		if a[i] != b[i]:
			return -1 if a[i] < b[i] else 1
	return 0


# Space-separated conditions, all must hold: ">=0.3", "<1.0.0", "=0.3.0", "0.3.0", "^0.3".
static func version_matches(have: String, spec: String) -> bool:
	var h := parse_version(have)
	for cond in spec.split(" ", false):
		var op := ""
		for o in [">=", "<=", ">", "<", "=", "^"]:
			if cond.begins_with(o):
				op = o
				break
		var v := parse_version(cond.substr(op.length()))
		if v.is_empty():
			return false
		var c := _cmp(h, v)
		match op:
			">=":
				if c < 0: return false
			"<=":
				if c > 0: return false
			">":
				if c <= 0: return false
			"<":
				if c >= 0: return false
			"^":
				# Same major version (same minor while the major is 0), and at least v.
				if c < 0 or h[0] != v[0] or (v[0] == 0 and h[1] != v[1]): return false
			_:
				if c != 0: return false
	return true
