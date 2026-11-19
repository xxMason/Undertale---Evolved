# The player menu (docs/MULTIPLAYER.md, "Items, menus and saves"): Enter facing another player
# opens it, in Undertale's style: Give item, Give gold, Heal, Check.
#
# The host runs it like the other prompts (mp_ui.gd): the player's keys go to it while it is
# open, and a friend's PC draws what the host sends with each frame. Items move with
# Undertale's own scripts (scr_itemshift, scr_itemname), and Heal runs the item's own use code
# (scr_itemuseb) for the player being healed, so it heals what the item heals.
extends RefCounted

const UP := 38
const DOWN := 40
const LEFT := 37
const RIGHT := 39
const Z := 90
const ENTER := 13
const X := 88
const SHIFT := 16
const REACH := 34.0        # how near (pixels) the other player stands in front of you
const MAIN := ["Give item", "Give gold", "Heal", "Check"]
const SLOTS := 8           # Undertale's inventory

var eng
var mp
var vm
var menus := {}            # player index -> {"to": index, "page": String, "sel": int, "amt": int}
var _food := {}            # item ids whose use heals (scr_itemuseb calls scr_recoitem for them)
var done: Array = []       # what was done, for the checks: [giver, "item"/"gold"/"heal", to, detail]


func setup(e) -> void:
	eng = e
	mp = e.mp
	vm = e.vm
	_find_food()


# Items whose use in scr_itemuseb heals: their case calls scr_recoitem.
func _find_food() -> void:
	var src := FileAccess.get_file_as_string("res://extracted/code/gml_Script_scr_itemuseb.gml")
	var cur := -1
	for line in src.split("\n"):
		var t := line.strip_edges()
		if line.begins_with("    case ") and t.ends_with(":"):
			var n := t.substr(5, t.length() - 6)
			cur = int(n) if n.is_valid_int() else -1
		elif line.begins_with("    default"):
			cur = -1
		elif cur > 0 and t.contains("scr_recoitem"):
			_food[cur] = true


func busy(p: int) -> bool:
	return menus.has(p)


func close(p: int) -> void:
	menus.erase(p)


# Who player p stands facing, near enough to open the menu for: -1 for nobody.
func facing(p) -> int:
	if p.inst == null or p.inst.dead:
		return -1
	var at := Vector2(float(p.inst.v["x"]), float(p.inst.v["y"]))
	var dir := int(mp.value(p.index, "facing", 0.0))
	var ahead: Vector2 = [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)][clampi(dir, 0, 3)]
	var best := -1
	var best_d := INF
	for q in mp.list:
		if q.index == p.index or not q.active or not mp.here(q.index) or q.inst == null or q.inst.dead:
			continue
		var d: Vector2 = Vector2(float(q.inst.v["x"]), float(q.inst.v["y"])) - at
		var along := d.dot(ahead)
		var side := absf(d.dot(Vector2(ahead.y, ahead.x)))
		if along > 0.0 and along <= REACH and side <= 20.0 and along < best_d:
			best = q.index
			best_d = along
	return best


func open(p: int, to: int) -> void:
	menus[p] = {"to": to, "page": "main", "sel": 0, "amt": 1}
	_sound(p, "snd_squeak")


# Player p's keys while their menu is open (mp_ui.gd filter). The game gets none of them.
func key(p) -> void:
	var k = p.keys
	var m: Dictionary = menus[p.index]
	var to: int = m["to"]
	var q = mp.list[to] if to < mp.list.size() else null
	if q == null or not q.active or not mp.here(to):
		menus.erase(p.index)
		eng.mpsaves.tell(p.index, "%s went away." % (q.name if q != null else "They"))
		k.clear(-1)
		return
	var up: bool = k.pressed(UP)
	var down: bool = k.pressed(DOWN)
	var left: bool = k.pressed(LEFT)
	var right: bool = k.pressed(RIGHT)
	var ok: bool = k.pressed(Z) or k.pressed(ENTER)
	var back: bool = k.pressed(X) or k.pressed(SHIFT)
	k.clear(-1)
	var page: String = m["page"]
	match page:
		"main":
			if up or down:
				m["sel"] = wrapi(int(m["sel"]) + (1 if down else -1), 0, MAIN.size())
				_sound(p.index, "snd_squeak")
			elif back:
				menus.erase(p.index)
			elif ok:
				_sound(p.index, "snd_select")
				match int(m["sel"]):
					0:
						if _items(p.index).is_empty():
							_sound(p.index, "snd_nosound")
							eng.mpsaves.tell(p.index, "You have no items.")
						else:
							m["page"] = "item"
							m["sel"] = 0
					1:
						if _gold(p.index) <= 0:
							eng.mpsaves.tell(p.index, "You have no gold.")
						else:
							m["page"] = "gold"
							m["amt"] = mini(10, _gold(p.index))
					2:
						if _items(p.index).filter(func(s): return _food.has(s[1])).is_empty():
							eng.mpsaves.tell(p.index, "You have nothing to heal with.")
						else:
							m["page"] = "heal"
							m["sel"] = 0
					3:
						m["page"] = "check"
		"item", "heal":
			var items := _items(p.index)
			if items.is_empty():
				m["page"] = "main"
				return
			m["sel"] = clampi(int(m["sel"]), 0, items.size() - 1)
			if up or down:
				m["sel"] = wrapi(int(m["sel"]) + (1 if down else -1), 0, items.size())
				_sound(p.index, "snd_squeak")
			elif back:
				m["page"] = "main"
				m["sel"] = 0 if page == "item" else 2
			elif ok:
				var slot: Array = items[int(m["sel"])]
				if page == "item":
					_give_item(p.index, to, int(slot[0]))
				elif _food.has(slot[1]):
					_heal(p.index, to, int(slot[0]))
				else:
					_sound(p.index, "snd_nosound")
		"gold":
			var have := _gold(p.index)
			if left or right or up or down:
				var step := 1 if left or right else 10
				m["amt"] = clampi(int(m["amt"]) + (step if right or up else -step), 1, maxi(1, have))
				_sound(p.index, "snd_squeak")
			elif back:
				m["page"] = "main"
				m["sel"] = 1
			elif ok:
				_give_gold(p.index, to, mini(int(m["amt"]), have))
		"check":
			if ok or back:
				m["page"] = "main"
				m["sel"] = 3


# ---------------------------------------------------------------- what the choices do

# Player i's items: [slot, id] for each one held.
func _items(i: int) -> Array:
	var it = mp.value(i, "item", [])
	var out: Array = []
	if it is Array and not it.is_empty() and it[0] is Array:
		for s in mini(SLOTS, (it[0] as Array).size()):
			var id := int(it[0][s])
			if id > 0:
				out.append([s, id])
	return out


func _gold(i: int) -> int:
	return int(float(mp.value(i, "gold", 0.0)))


func _item_name(id: int) -> String:
	return String(vm.call_script("scr_gettext", ["item_name_%d" % id], _ctx()))


# Scripts run as the world's obj_time, like the engine's own start-up code.
func _ctx() -> Dictionary:
	return eng._ctx(mp._time())


# Runs f with player i's values loaded (and as their context: sounds, objects).
func _as(i: int, f: Callable):
	var keep: int = vm.ctx_owner
	mp.switch_to(i)
	var r = f.call()
	mp.switch_to(keep)
	return r


func _give_item(i: int, to: int, slot: int) -> void:
	var row = mp.value(to, "item", [])
	var free := -1
	if row is Array and not row.is_empty() and row[0] is Array:
		for s in mini(SLOTS, (row[0] as Array).size()):
			if float(row[0][s]) == 0.0:
				free = s
				break
	if free < 0:
		_sound(i, "snd_nosound")
		eng.mpsaves.tell(i, "%s can't carry any more." % mp.list[to].name)
		return
	var id := int(mp.value(i, "item", [[]])[0][slot])
	_as(i, func(): vm.call_script("scr_itemshift", [float(slot), 0.0], _ctx()))
	_as(to, func():
		vm.globals["item"][0][free] = float(id)
		vm.call_script("scr_itemnameb", [], _ctx())
		vm.call_script("scr_itemname", [], _ctx()))
	var nm := _item_name(id)
	done.append([i, "item", to, id])
	_sound(i, "snd_item")
	eng.mpsaves.tell(i, "You gave %s the %s." % [mp.list[to].name, nm])
	eng.mpsaves.tell(to, "%s gave you the %s." % [mp.list[i].name, nm])
	_after(i)


func _give_gold(i: int, to: int, n: int) -> void:
	if n <= 0:
		return
	mp.set_value(i, "gold", float(_gold(i) - n))
	mp.set_value(to, "gold", float(_gold(to) + n))
	done.append([i, "gold", to, n])
	_sound(i, "snd_item")
	eng.mpsaves.tell(i, "You gave %s %dG." % [mp.list[to].name, n])
	eng.mpsaves.tell(to, "%s gave you %dG." % [mp.list[i].name, n])
	menus.erase(i)


# Player i uses their item in `slot` on player `to`: the item's own code runs as `to`, with
# the item put in their last slot for the moment (their own items are put back after).
func _heal(i: int, to: int, slot: int) -> void:
	var id := int(mp.value(i, "item", [[]])[0][slot])
	var before := float(mp.value(to, "hp", 0.0))
	_as(to, func():
		var g: Dictionary = vm.globals
		var keep_items: Array = (g["item"] as Array).duplicate(true)
		var keep_msg = g.get("msg", []).duplicate(true) if g.get("msg") is Array else g.get("msg")
		g["item"][0][SLOTS - 1] = float(id)
		vm.call_script("scr_itemuseb", [float(SLOTS - 1), float(id)], _ctx())
		g["item"] = keep_items
		if keep_msg != null:
			g["msg"] = keep_msg
		vm.call_script("scr_itemnameb", [], _ctx())
		vm.call_script("scr_itemname", [], _ctx()))
	_as(i, func(): vm.call_script("scr_itemshift", [float(slot), 0.0], _ctx()))
	var got := int(float(mp.value(to, "hp", 0.0)) - before)
	var nm := _item_name(id)
	done.append([i, "heal", to, got])
	var to_name: String = mp.list[to].name
	eng.mpsaves.tell(i, "%s ate the %s: %s." % [to_name, nm, "HP maxed out" if float(mp.value(to, "hp", 0.0)) >= float(mp.value(to, "maxhp", 20.0)) else "+%d HP" % got])
	eng.mpsaves.tell(to, "%s gave you the %s to eat: +%d HP." % [mp.list[i].name, nm, got])
	_after(i)


# After an item went: back to the list, or the main page once there's nothing left in it.
func _after(i: int) -> void:
	var m = menus.get(i)
	if m == null:
		return
	var items := _items(i)
	if m["page"] == "heal":
		items = items.filter(func(s): return _food.has(s[1]))
	if items.is_empty():
		menus.erase(i)
	else:
		m["sel"] = clampi(int(m["sel"]), 0, _items(i).size() - 1)


func _sound(p: int, name: String) -> void:
	eng.mpui._sound(p, name)


# ---------------------------------------------------------------- the picture

# What player p's screen shows of their menu (sent with each frame to a friend's PC).
func state_for(p: int) -> Dictionary:
	var m = menus.get(p)
	if m == null:
		return {}
	var to: int = m["to"]
	var out := {"n": String(mp.list[to].name).to_upper(), "pg": m["page"], "s": int(m["sel"])}
	match String(m["page"]):
		"main":
			out["rows"] = MAIN
		"item", "heal":
			var rows: Array = []
			var dim: Array = []
			for s in _items(p):
				rows.append(_item_name(int(s[1])))
				dim.append(m["page"] == "heal" and not _food.has(s[1]))
			out["rows"] = rows
			out["dim"] = dim
			out["head"] = "Give %s which item?" % mp.list[to].name if m["page"] == "item" else "Heal %s with?" % mp.list[to].name
		"gold":
			out["head"] = "Give %s how much?" % mp.list[to].name
			out["amt"] = int(m["amt"])
			out["have"] = _gold(p)
		"check":
			out["rows"] = _stat_lines(to)
	return out


# Player i's STAT page, in Undertale's own words (its scr_gettext lines).
func _stat_lines(i: int) -> Array:
	return _as(i, func():
		var g: Dictionary = vm.globals
		var c: Dictionary = _ctx()
		var t := func(key: String, args: Array) -> String:
			return String(vm.call_script("scr_gettext", [key] + args, c))
		var armor := int(float(g.get("armor", 0.0)))
		var armorname: String = t.call("stat_armor_temmie", []) if armor == 64 else t.call("item_name_%d" % armor, [])
		return [
			"\"%s\"" % mp.list[i].name,
			t.call("stat_menu_lv", [str(int(float(g.get("lv", 1.0))))]),
			t.call("stat_menu_hp", [str(int(float(g.get("hp", 20.0)))), str(int(float(g.get("maxhp", 20.0))))]),
			t.call("stat_menu_at", [str(int(float(g.get("at", 10.0)) - 10.0)), str(int(float(g.get("wstrength", 0.0))))]),
			t.call("stat_menu_df", [str(int(float(g.get("df", 10.0)) - 10.0)), str(int(float(g.get("adef", 0.0))))]),
			t.call("stat_menu_weapon", [t.call("item_name_%d" % int(float(g.get("weapon", 3.0))), [])]),
			t.call("stat_menu_armor", [armorname]),
			t.call("stat_menu_gold", []),
		])


# Draws a menu state on the engine's screen (640x480), like Undertale's overworld menu.
static func draw(e, st: Dictionary) -> void:
	const W := 16777215
	const Y := 65535
	const G := 8421504
	var pg := String(st.get("pg", "main"))
	var sel := int(st.get("s", 0))
	# The name box, top left, as Undertale's menu has yours.
	_box(e, Rect2(32, 52, 196, 54))
	e._text(46, 60, String(st.get("n", "")), W, "fnt_main")
	match pg:
		"main":
			_box(e, Rect2(32, 114, 196, 166))
			var rows: Array = st.get("rows", [])
			for k in rows.size():
				var y := 128.0 + k * 36.0
				e._text(76, y, String(rows[k]), Y if k == sel else W, "fnt_main")
				if k == sel:
					e._heart(48, y + 8)
		"item", "heal":
			_box(e, Rect2(242, 52, 366, 316))
			e._text(262, 64, String(st.get("head", "")), W, "fnt_maintext")
			var rows: Array = st.get("rows", [])
			var dim: Array = st.get("dim", [])
			for k in rows.size():
				var y := 104.0 + k * 32.0
				var c := G if k < dim.size() and dim[k] else (Y if k == sel else W)
				e._text(294, y, String(rows[k]), c, "fnt_main")
				if k == sel:
					e._heart(266, y + 8)
		"gold":
			_box(e, Rect2(242, 52, 366, 170))
			e._text(262, 64, String(st.get("head", "")), W, "fnt_maintext")
			e._text(304, 112, "< %dG >" % int(st.get("amt", 0)), Y, "fnt_main")
			e._text(262, 156, "You have %dG." % int(st.get("have", 0)), G, "fnt_maintext")
			e._text(262, 184, "[LEFT/RIGHT] 1  [UP/DOWN] 10", G, "fnt_maintext")
		"check":
			_box(e, Rect2(242, 52, 366, 316))
			var rows: Array = st.get("rows", [])
			for k in rows.size():
				e._text(270, 68 + k * 36 + (12 if k > 0 else 0), String(rows[k]), W, "fnt_main")


static func _box(e, r: Rect2) -> void:
	e.draw_rect(r, Color.WHITE)
	e.draw_rect(r.grow(-6), Color.BLACK)
