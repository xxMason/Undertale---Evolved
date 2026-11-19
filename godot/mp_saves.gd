# Saving with several players (docs/MULTIPLAYER.md, "Items, menus and saves").
#
# Anyone can save at a save point, and it saves the universe for everyone: Undertale's file0
# keeps the host's own things (as in the one-player game) and players.json beside it keeps
# everyone's (items, gold, weapon, armour, stats), by name, so a friend who joins again later
# gets theirs back. Everyone is told who saved. Saving is refused while another player is in a
# menu or a battle: the save menu doesn't open, and the player is told why.
extends RefCounted

const FILE := "players.json"
# A player's own things kept in the save. LV and EXP are everyone's (shared globals).
const KEYS := ["hp", "maxhp", "at", "df", "wstrength", "adef", "gold", "weapon", "armor", "item"]
# file0's lines for them (Undertale's scr_save order).
const LINES := {"maxhp": 2, "at": 4, "wstrength": 5, "df": 6, "adef": 7, "gold": 10, "weapon": 28, "armor": 29}

var eng
var mp
var _menu_was := {}     # player index -> their menuno last frame
var _lv := -1.0         # the shared LV last frame


func setup(e) -> void:
	eng = e
	mp = e.mp
	_lv = float(eng.vm.globals.get("lv", 1.0))


# Player i's own things, as kept in the save.
func profile(i: int) -> Dictionary:
	var out := {}
	for k in KEYS:
		var v = mp.value(i, k, null)
		if v != null:
			out[k] = (v as Array).duplicate(true) if v is Array else v
	return out


func apply(i: int, prof: Dictionary) -> void:
	for k in KEYS:
		if prof.has(k):
			var v = prof[k]
			mp.set_value(i, k, (v as Array).duplicate(true) if v is Array else v)


func _path() -> String:
	return eng.bi.save_path(FILE)


func _read() -> Dictionary:
	var path := _path()
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


# ---------------------------------------------------------------- saving

# Why player p can't save right now ("" if they can): another player is in a menu or battle.
func refusal(p: int) -> String:
	for o in mp.list:
		if o.index == p or not o.active:
			continue
		var r = eng.mprooms.room_of(o.index) if eng.mprooms != null else null
		var rn: String = eng.mprooms.room_name(r) if r != null else ""
		if rn == "room_battle" or rn == "room_floweybattle":
			return "%s is in a battle." % o.name
		if rn.begins_with("room_gameover"):
			return "%s is in a battle." % o.name
		if float(mp.value(o.index, "menuno", -1.0)) >= 0.0:
			return "%s is in a menu." % o.name
	return ""


# After each step of a world: a save menu that just opened is closed again if saving isn't
# allowed now (as if Return was chosen), and an LV gained by anyone is everyone's.
func after_step() -> void:
	for p in mp.list:
		if not p.active or not mp.here(p.index):
			continue
		var m := float(mp.value(p.index, "menuno", -1.0))
		var was := float(_menu_was.get(p.index, -1.0))
		_menu_was[p.index] = m
		if m == 4.0 and was != 4.0 and mp.active_count() > 1:
			var why := refusal(p.index)
			if why != "":
				mp.set_value(p.index, "menuno", -1.0)
				mp.set_value(p.index, "interact", 0.0)
				var mc = mp.value(p.index, "menucoord", null)
				if mc is Array and not mc.is_empty() and mc[0] is Array and (mc[0] as Array).size() > 4:
					mc[0][4] = 0.0
				_menu_was[p.index] = -1.0
				tell(p.index, "Can't save now: " + why)
	var lv := float(eng.vm.globals.get("lv", 1.0))
	if lv != _lv:
		if lv > _lv:
			_level_up(lv)
		_lv = lv


# Undertale's scr_levelup for the player who gained it; the same stats for everyone else.
func _level_up(lv: float) -> void:
	var hp := 16.0 + lv * 4.0
	var at := 8.0 + lv * 2.0
	var df := 9.0 + ceilf(lv / 4.0)
	if lv >= 20.0:
		hp = 99.0
		at = 99.0
		df = 99.0
	for p in mp.list:
		if not p.active:
			continue
		mp.set_value(p.index, "maxhp", hp)
		mp.set_value(p.index, "at", at)
		mp.set_value(p.index, "df", df)


# The game wrote a save file (engine.gd). file0 is the universe's save: it keeps the host's
# own things whoever saved, and everyone's go to players.json.
func written(path: String) -> void:
	if path.get_file() != "file0":
		return
	var saver: int = eng.vm.ctx_owner if eng.vm.ctx_owner >= 0 else mp.primary
	if saver != 0:
		_patch(path, profile(0))
	var all := _read()
	for p in mp.list:
		if p.name == "":
			continue
		var prof := profile(p.index)
		prof["saved"] = Time.get_datetime_string_from_system()
		all[p.name] = prof
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(all, " "))
	if mp.active_count() > 1 and saver >= 0 and saver < mp.list.size():
		tell_all("%s saved the game." % mp.list[saver].name, saver)


func _patch(path: String, prof: Dictionary) -> void:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var num := func(v) -> String:
		var r := float(v)
		return str(int(r)) if r == floorf(r) and absf(r) < 1e15 else String.num(r)
	var setl := func(i: int, v) -> void:
		if i < lines.size():
			lines[i] = num.call(v) + ("\r" if lines[i].ends_with("\r") else "")
	for k in LINES:
		if prof.has(k):
			setl.call(LINES[k], prof[k])
	var items = prof.get("item", [[]])
	if items is Array and not items.is_empty() and items[0] is Array:
		for i in mini(8, (items[0] as Array).size()):
			setl.call(12 + i * 2, items[0][i])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))


# ---------------------------------------------------------------- loading

# The game read file0 (a load: Continue, or a reset): everyone else's things as saved.
func read(path: String) -> void:
	if path.get_file() != "file0":
		return
	var all := _read()
	for p in mp.list:
		if p.index != 0 and p.active and all.has(p.name):
			apply(p.index, all[p.name])


# A player joined: their things as last saved in this universe, if they have played here.
func joined(i: int) -> void:
	var all := _read()
	var pl = mp.list[i]
	if all.has(pl.name):
		apply(i, all[pl.name])


# ---------------------------------------------------------------- telling players

var told: Array = []    # [player index, text] of every note, for the checks


# A note on one player's screen only.
func tell(i: int, text: String) -> void:
	told.append([i, text])
	if eng.mpnet != null and eng.mpnet.role == "host":
		eng.mpnet.tell(i, text)
	elif i == eng.view_as or i == 0:
		eng.mp_notice(text)
	else:
		print("NOTICE to %s: %s" % [mp.list[i].name, text])


func tell_all(text: String, skip := -1) -> void:
	for p in mp.list:
		if p.active and p.index != skip:
			tell(p.index, text)
