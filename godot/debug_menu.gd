# The debug menu (F5), for testing by hand: the player's stats, items, the story counter and
# flags, warps, battles, cheats, game speed, quick saves and an object inspector.
#
# While it is open the game gets no keys (it goes on running; Space pauses it). Mouse and
# keyboard both work: Tab / arrows move between fields, PageUp / PageDown change tab, Esc or
# F5 closes. Cheats are switched off again at every start. Anything changed here is noted,
# and saves written afterwards get a "<save>.debug" file next to them listing it (the save
# itself stays in Undertale's own format); F12 bug reports list it too.
extends CanvasLayer

const DebugState = preload("res://debug_state.gd")

const W := 330
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
# Genocide counters: global.flag[N] counts the kills in an area; the area runs out at "of".
const AREAS := [["Ruins", 202, 20], ["Snowdin", 203, 16], ["Waterfall", 204, 18], ["Hotland / Core", 205, 40]]
# Story points the walkthrough bot has played from: room and the story state to set.
const CHECKPOINTS := [
	["Ruins 7: Toriel's first call", "room_ruins7", {"plot": 9.0}],
	["Ruins 14: the floor that gives way", "room_ruins14", {"plot": 12.0}],
	["Ruins 15B: the switch rooms", "room_ruins15B", {"plot": 13.0}],
	["Ruins 16: before Toriel finds you", "room_ruins16", {"plot": 16.0}],
	["Toriel's house: ask how to leave", "room_torhouse2", {"plot": 19.0}],
	["Basement 4: Toriel's fight", "room_basement4", {"plot": 24.0}],
	["Snowdin: the first room", "room_tundra1", {"plot": 30.0}],
]

var eng
var vm
var bi
var open := false

# Cheats (all off at start).
var no_damage := false
var keep_hp := false
var noclip := false
var no_encounters := false
var auto_text := false
var click_move := false

var panel: PanelContainer
var tabs: TabContainer
var status: Label
var watch_label: Label
var watch_names: PackedStringArray = []
var _loading := false
var _tick := 0
var _on_left := false
var _undo = null            # snapshot taken when the menu opened
var _slots := [null, null, null]
var _slot_labels: Array = []
var _item_ids: Array = []   # [id, name] for every item, 0 = empty
var _phone_ids: Array = []
var _rooms: Array = []      # room names in game order
var _inspect = null         # the instance shown in Inspect

# Widgets read back by _refresh.
var w := {}


func setup(engine) -> void:
	eng = engine
	vm = engine.vm
	bi = engine.bi
	layer = 50
	var th := Theme.new()
	th.default_font = ThemeDB.fallback_font
	th.default_font_size = 10
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.09, 0.93)
	sb.border_color = Color(1, 1, 0, 0.6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	th.set_stylebox("panel", "PanelContainer", sb)
	panel = PanelContainer.new()
	panel.theme = th
	panel.size = Vector2(W, 480)
	panel.visible = false
	add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "DEBUG  (F5 / Esc close, Space pause)"
	title.add_theme_color_override("font_color", Color(1, 1, 0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_button(head, "<>", func(): _on_left = not _on_left; _place())
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.7, 0.9, 1))
	root.add_child(status)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_changed.connect(func(_t): _refresh())
	root.add_child(tabs)
	watch_label = Label.new()
	watch_label.theme = th
	watch_label.position = Vector2(6, 26)
	watch_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	watch_label.add_theme_color_override("font_outline_color", Color.BLACK)
	watch_label.add_theme_constant_override("outline_size", 3)
	add_child(watch_label)
	_collect_names()
	_build_player()
	_build_items()
	_build_story()
	_build_warp()
	_build_battle()
	_build_world()
	_build_saves()
	_build_inspect()
	_place()
	bi.on_save_written = _save_written


# ------------------------------------------------------------------ open / close, keys

func toggle() -> void:
	if not open and not eng.in_play():
		return
	if not open and not eng.cheats_allowed():
		eng.cheats_refused()
		return
	# A co-op friend only gets their own character (coop_cheats.gd).
	if eng.coop.active() and not eng.coop.is_host():
		eng.friend_cheats.toggle()
		return
	open = not open
	panel.visible = open
	if open:
		_undo = DebugState.capture(vm, bi, eng)
		_refresh()
		# The tab bar has the keys first (left/right change tab, Tab goes into the page), so
		# Space pauses until a text field is clicked into.
		tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
		tabs.get_tab_bar().grab_focus()
	else:
		var f := panel.get_viewport().gui_get_focus_owner()
		if f != null:
			f.release_focus()
		vm.event_watch = null


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F5:
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not open:
		return
	var typing := panel.get_viewport().gui_get_focus_owner() is LineEdit and not (panel.get_viewport().gui_get_focus_owner().get_parent() is SpinBox)
	match event.keycode:
		KEY_ESCAPE:
			toggle()
		KEY_SPACE:
			if typing:
				return
			eng.paused = not eng.paused
			eng._toast("Paused (Space to resume)" if eng.paused else "Resumed", 1500)
		KEY_PAGEUP:
			tabs.current_tab = (tabs.current_tab + tabs.get_tab_count() - 1) % tabs.get_tab_count()
		KEY_PAGEDOWN:
			tabs.current_tab = (tabs.current_tab + 1) % tabs.get_tab_count()
		_:
			return
	get_viewport().set_input_as_handled()


func _place() -> void:
	panel.position = Vector2(0 if _on_left else 640 - W, 0)


# A click on the game itself (not on the panel), in screen pixels.
func game_click(p: Vector2) -> void:
	var rp: Vector2 = eng.rec.view + p / eng.rec.view_scale
	if click_move:
		var pl = _player()
		if pl != null:
			vm.inst_set(pl, "x", round(rp.x - 10))
			vm.inst_set(pl, "y", round(rp.y - 25))
			pl.v["xprevious"] = pl.v["x"]
			pl.v["yprevious"] = pl.v["y"]
			note("moved the player to %d,%d" % [int(rp.x), int(rp.y)])
		return
	# Inspect: the frontmost instance under the click (visible ones first).
	var best = null
	for i in vm.instances:
		if i.dead or not Rect2(vm.bbox(i)).has_point(rp):
			continue
		if best == null or _front(i, best):
			best = i
	if best != null:
		_inspect = best
		vm.event_watch = best
		vm.event_log = []
		tabs.current_tab = tabs.get_tab_idx_from_control(w["inspect_tab"])
		_refresh()


func _front(a, b) -> bool:
	var va := float(a.v.get("visible", 1.0)) >= 0.5
	var vb := float(b.v.get("visible", 1.0)) >= 0.5
	if va != vb:
		return va
	return float(a.v.get("depth", 0.0)) < float(b.v.get("depth", 0.0))


# ------------------------------------------------------------------ every game frame

# Called by the engine before each game frame.
func before_frame() -> void:
	var g: Dictionary = vm.globals
	if no_damage:
		g["invc"] = maxf(float(g.get("invc", 0.0)), 2.0)
	if keep_hp and g.has("maxhp"):
		g["hp"] = g["maxhp"]
	if no_encounters and g.has("encounter"):
		g["encounter"] = 0.0
	if noclip and eng.is_game():
		g["phasing"] = 1.0
		for i in vm.instances:
			if not i.dead and float(i.v.get("solid", 0.0)) >= 0.5 and _is_wall(i.obj):
				i.v["solid"] = 0.0
	if auto_text and not open and eng.bot == null and eng.frames % 6 == 0:
		if _exists("OBJ_WRITER") and not _exists("obj_choicer"):
			eng.keys.queue.append(88 if eng.frames % 12 == 0 else 90)


func _process(_d: float) -> void:
	_tick += 1
	_update_watch()
	if not open:
		return
	status.text = _status_line()
	if _tick % 10 == 0:
		_refresh_live()


func _status_line() -> String:
	if vm.room < 0:
		return ""
	var pl = _player()
	var s := "%s  f%d  plot %s  interact %s" % [vm.room_names[vm.room], eng.frames, _gs("plot"), _gs("interact")]
	if pl != null:
		s += "  @%s,%s" % [pl.v["x"], pl.v["y"]]
	if eng.paused:
		s += "  PAUSED"
	if eng.game_speed != 1.0:
		s += "  x%s" % eng.game_speed
	return s


# ------------------------------------------------------------------ tabs

func _page(name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func _build_player() -> void:
	var p := _page("Player")
	var name_edit := LineEdit.new()
	name_edit.text_submitted.connect(func(t): _set_g("charname", t, "name"))
	name_edit.focus_exited.connect(func(): if not _loading and name_edit.text != _gs("charname"): _set_g("charname", name_edit.text, "name"))
	_row(p, "Name", name_edit)
	w["name"] = name_edit
	var lvbox := HBoxContainer.new()
	var lvs := _spin(1, 20, 1)
	lvbox.add_child(lvs)
	_button(lvbox, "Set LV", func(): _apply_lv(int(lvs.value)))
	_row(p, "LV", lvbox)
	w["lv"] = lvs
	for f in [["HP", "hp", 999], ["Max HP", "maxhp", 999], ["AT", "at", 999], ["DF", "df", 999], ["EXP", "xp", 99999], ["Gold", "gold", 99999], ["Kills", "kills", 9999]]:
		var key: String = f[1]
		var sp := _spin(0, f[2], 1)
		sp.value_changed.connect(func(val): if not _loading: _set_g(key, float(val), f[0]))
		_row(p, f[0], sp)
		w[key] = sp
	var hb := HBoxContainer.new()
	_button(hb, "Full HP", func(): _set_g("hp", float(vm.globals.get("maxhp", 20.0)), "HP"); _refresh())
	_button(hb, "1 HP", func(): _set_g("hp", 1.0, "HP"); _refresh())
	p.add_child(hb)
	_note_label(p, "Set LV also sets EXP, max HP, AT and DF to match. AT and DF are the game's own values (LV 1: 10 and 10); weapon and armour add to them.")


func _apply_lv(n: int) -> void:
	var g: Dictionary = vm.globals
	g["lv"] = float(n)
	g["xp"] = float(eng.XP_FOR_LV[n])
	g["maxhp"] = 99.0 if n == 20 else 16.0 + n * 4.0
	g["at"] = 30.0 if n == 20 else 8.0 + n * 2.0
	g["df"] = 30.0 if n == 20 else 9.0 + ceilf(n / 4.0)
	g["hp"] = g["maxhp"]
	note("LV set to %d" % n)
	_refresh()


func _build_items() -> void:
	var p := _page("Items")
	for i in 8:
		var ob := _item_picker(_item_ids)
		var slot := i
		ob.item_selected.connect(func(k): if not _loading: _set_item(slot, _item_ids[k][0]))
		_row(p, "Slot %d" % (i + 1), ob)
		w["item%d" % i] = ob
	var wp := _item_picker(_item_ids)
	wp.item_selected.connect(func(k): if not _loading: _equip("scr_weaponeq", _item_ids[k][0], "weapon"))
	_row(p, "Weapon", wp)
	w["weapon"] = wp
	var ar := _item_picker(_item_ids)
	ar.item_selected.connect(func(k): if not _loading: _equip("scr_armoreq", _item_ids[k][0], "armour"))
	_row(p, "Armour", ar)
	w["armor"] = ar
	var hb := HBoxContainer.new()
	_button(hb, "Empty all slots", func():
		for i in 8:
			_set_item(i, 0.0)
		_refresh())
	p.add_child(hb)
	var ph := Label.new()
	ph.text = "Phone"
	p.add_child(ph)
	for i in 4:
		var ob2 := _item_picker(_phone_ids)
		var slot2 := i
		ob2.item_selected.connect(func(k): if not _loading: _set_arr("phone", slot2, _phone_ids[k][0], "phone slot %d" % (slot2 + 1)); _call("scr_phonename"))
		_row(p, "Phone %d" % (i + 1), ob2)
		w["phone%d" % i] = ob2
	_note_label(p, "Weapons and armour are equipped with the game's own scripts (scr_weaponeq / scr_armoreq), so their AT/DF bonus applies.")


func _set_item(slot: int, id: float) -> void:
	_set_arr("item", slot, id, "item slot %d" % (slot + 1))
	_call("scr_itemname")


func _equip(script: String, id: float, what: String) -> void:
	_call(script, [-1.0, id])
	note("%s set to %s" % [what, _name_of(_item_ids, id)])


func _build_story() -> void:
	var p := _page("Story")
	var pl := _spin(0, 1000, 0.1)
	pl.value_changed.connect(func(val): if not _loading: _set_g("plot", float(val), "plot"))
	_row(p, "Plot", pl)
	w["plot"] = pl
	var fh := HBoxContainer.new()
	var fn := _spin(0, 600, 1)
	var fv := _spin(-99999, 99999, 1)
	fn.value_changed.connect(func(_v2): _loading = true; fv.value = _arr("flag", int(fn.value)); _loading = false)
	fh.add_child(fn)
	fh.add_child(fv)
	_button(fh, "Set", func(): _set_arr("flag", int(fn.value), fv.value, "flag %d" % int(fn.value)))
	_row(p, "Flag  # / value", fh)
	w["flagn"] = fn
	w["flagv"] = fv
	var we := LineEdit.new()
	we.placeholder_text = "plot, interact, flag.202, obj_toroverworld3.x"
	we.text_changed.connect(func(t): watch_names = PackedStringArray(Array(t.split(",", false)).map(func(s): return s.strip_edges())))
	_row(p, "On screen", we)
	w["watch"] = we
	_note_label(p, "\"On screen\" keeps those values in the top-left corner, menu open or not: globals, flag.N / item.N array elements, or OBJ.VAR.")
	var lb := Label.new()
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD
	p.add_child(lb)
	w["used"] = lb


func _build_warp() -> void:
	var p := _page("Warp")
	var cp := ItemList.new()
	cp.custom_minimum_size = Vector2(0, 110)
	for c in CHECKPOINTS:
		cp.add_item(c[0])
	cp.item_activated.connect(func(k): _warp(CHECKPOINTS[k][1], CHECKPOINTS[k][2]))
	var cl := Label.new()
	cl.text = "Story points (Enter / double-click): room and plot set to match"
	p.add_child(cl)
	p.add_child(cp)
	var search := LineEdit.new()
	search.placeholder_text = "search rooms (ruins, tundra, water...)"
	p.add_child(search)
	var rl := ItemList.new()
	rl.custom_minimum_size = Vector2(0, 150)
	p.add_child(rl)
	var fill := func(t: String):
		rl.clear()
		for r in _rooms:
			if t == "" or r.contains(t):
				rl.add_item(r)
	fill.call("")
	search.text_changed.connect(fill)
	search.text_submitted.connect(func(_t): if rl.item_count > 0: _warp(rl.get_item_text(0), {}))
	rl.item_activated.connect(func(k): _warp(rl.get_item_text(k), {}))
	var cm := _toggle("Click on the game to move the player there")
	cm.toggled.connect(func(on): click_move = on)
	p.add_child(cm)
	w["clickmove"] = cm
	_note_label(p, "A room warp keeps the story as it is, so a room may be in a state the story never reaches.")


func _warp(room_name: String, sets: Dictionary) -> void:
	if not eng.is_game():
		eng._toast("Warps work in the game (G on the start screen)")
		return
	var r := int(vm.consts.get(room_name, -1.0))
	if r < 0:
		return
	for k in sets:
		vm.globals[k] = sets[k]
	vm.globals["interact"] = 0.0
	vm.globals["phasing"] = 0.0
	vm.globals["entrance"] = 0.0
	vm.pending_room = -1
	vm.load_room(r)
	note("warped to %s%s" % [room_name, (" " + str(sets)) if not sets.is_empty() else ""])
	_refresh()


func _build_battle() -> void:
	var p := _page("Battle")
	var groups := OptionButton.new()
	var gl: Array = []
	for e in eng.ROSTER:
		if (e[2] as Dictionary).has("bg"):
			gl.append([e[2]["bg"], "%s - %s" % [e[0], e[1]]])
	for x in gl:
		groups.add_item("%d  %s" % [x[0], x[1]])
	var num := _spin(1, 300, 1)
	groups.item_selected.connect(func(k): num.value = gl[k][0])
	if not gl.is_empty():
		groups.select(0)
		num.value = gl[0][0]
	_row(p, "Group", groups)
	var hb := HBoxContainer.new()
	hb.add_child(num)
	_button(hb, "Start this battle here", func(): _start_battle(int(num.value)))
	_row(p, "Number", hb)
	var nd := _toggle("No damage (the SOUL stays invulnerable)")
	nd.toggled.connect(func(on): no_damage = on; note("no damage " + ("on" if on else "off")))
	p.add_child(nd)
	var kh := _toggle("Keep HP full (refilled every frame)")
	kh.toggled.connect(func(on): keep_hp = on; note("keep HP full " + ("on" if on else "off")))
	p.add_child(kh)
	var hb2 := HBoxContainer.new()
	_button(hb2, "Monsters to 1 HP", func(): _monsters_hp())
	_button(hb2, "Make spareable", func(): _spareable())
	p.add_child(hb2)
	var ml := Label.new()
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD
	p.add_child(ml)
	w["monsters"] = ml
	_note_label(p, "Battles started here begin like a random encounter (the \"!\" and the flash) and bring you back where you stood.")


func _start_battle(group: int) -> void:
	if not eng.is_game() or _player() == null or eng.in_battle_room():
		eng._toast("Start a battle from the overworld")
		return
	vm.globals["battlegroup"] = float(group)
	var pl = _player()
	vm.instance_create(float(pl.v["x"]), float(pl.v["y"]), int(vm.obj_index["obj_battleblcon"]))
	note("started battle group %d" % group)
	toggle()


func _monsters_hp() -> void:
	for i in 3:
		if _arr("monster", i) != 0.0:
			_set_arr("monsterhp", i, 1.0, "")
	note("monsters set to 1 HP")


func _spareable() -> void:
	var n := 0
	for i in vm.instances:
		if not i.dead and i.v.has("mercymod") and i.v.has("myself"):
			i.v["mercymod"] = 999.0
			n += 1
	note("made %d monster(s) spareable" % n)


func _build_world() -> void:
	var p := _page("World")
	var sp := OptionButton.new()
	for s in SPEEDS:
		sp.add_item("x%s" % s)
	sp.select(SPEEDS.find(1.0))
	sp.item_selected.connect(func(k): eng.game_speed = SPEEDS[k]; note("game speed x%s" % SPEEDS[k]))
	_row(p, "Game speed", sp)
	w["speed"] = sp
	var nc := _toggle("Walk through walls")
	nc.toggled.connect(_set_noclip)
	p.add_child(nc)
	var ne := _toggle("No random encounters")
	ne.toggled.connect(func(on): no_encounters = on; note("encounters " + ("off" if on else "on")))
	p.add_child(ne)
	var eh := HBoxContainer.new()
	_button(eh, "Encounter now", func(): vm.globals["encounter"] = 99999.0; note("forced an encounter"))
	var el := Label.new()
	eh.add_child(el)
	w["steps"] = el
	p.add_child(eh)
	var at := Label.new()
	at.text = "Monsters left per area (genocide)"
	p.add_child(at)
	for a in AREAS:
		var hb := HBoxContainer.new()
		var lb := Label.new()
		lb.custom_minimum_size = Vector2(150, 0)
		hb.add_child(lb)
		var flag_no: int = a[1]
		var pop: int = a[2]
		var area: String = a[0]
		_button(hb, "1 left", func(): _set_arr("flag", flag_no, float(pop - 1), "%s: 1 monster left" % area); _refresh())
		_button(hb, "none", func(): _set_arr("flag", flag_no, float(pop), "%s: none left" % area); _refresh())
		_button(hb, "reset", func(): _set_arr("flag", flag_no, 0.0, "%s: kill count reset" % area); _refresh())
		p.add_child(hb)
		w["area" + area] = lb
	var tx := _toggle("Auto-advance text (taps X, then Z)")
	tx.toggled.connect(func(on): auto_text = on; note("auto text " + ("on" if on else "off")))
	p.add_child(tx)
	var fh := HBoxContainer.new()
	var fun := _spin(1, 100, 1)
	fh.add_child(fun)
	_button(fh, "Set FUN", func(): _set_arr("flag", 5, fun.value, "FUN"))
	_row(p, "FUN (flag 5)", fh)
	w["fun"] = fun
	var rh := HBoxContainer.new()
	var seed_e := LineEdit.new()
	seed_e.placeholder_text = "seed"
	seed_e.custom_minimum_size = Vector2(80, 0)
	rh.add_child(seed_e)
	_button(rh, "Reseed random", func():
		if seed_e.text.is_valid_int():
			bi.rng.set_seed(int(seed_e.text))
			note("random seed %s" % seed_e.text))
	_row(p, "Random", rh)
	_note_label(p, "Cheats switch off again at every start. Walking through walls also skips holes and triggers that need a wall.")


func _set_noclip(on: bool) -> void:
	noclip = on
	note("walk through walls " + ("on" if on else "off"))
	if not on:
		vm.globals["phasing"] = 0.0
		for i in vm.instances:
			if not i.dead and _is_wall(i.obj):
				i.v["solid"] = 1.0 if vm.obj_solid[i.obj] else 0.0


func _build_saves() -> void:
	var p := _page("Saves")
	_button(p, "Save the game (as at a save point)", func(): _save_game())
	for k in 3:
		var hb := HBoxContainer.new()
		var slot := k
		_button(hb, "Quick save %d" % (k + 1), func(): _slots[slot] = DebugState.capture(vm, bi, eng); note("quick save %d" % (slot + 1)); _refresh())
		_button(hb, "Load", func(): _load_slot(slot))
		var lb := Label.new()
		hb.add_child(lb)
		_slot_labels.append(lb)
		p.add_child(hb)
	_button(p, "Undo everything since the menu opened", func():
		if _undo != null:
			DebugState.restore(vm, bi, eng, _undo)
			note("undo")
			_refresh())
	_button(p, "Open the save folder", func(): OS.shell_open(bi.save_dir if bi.save_dir != "" else ProjectSettings.globalize_path("user://")))
	_note_label(p, "Quick saves keep the exact moment (every object, the room, the random generator) until the engine closes. The music isn't part of it. The game's own save is the save point's.")


func _save_game() -> void:
	if not eng.is_game() or _player() == null:
		eng._toast("Saving works in the overworld")
		return
	vm.call_script("scr_save", [], {"self": _player(), "other": _player(), "locals": {}, "args": []})
	bi._ini_flush()
	note("saved the game")
	eng._toast("Saved")


func _load_slot(k: int) -> void:
	if _slots[k] == null:
		return
	DebugState.restore(vm, bi, eng, _slots[k])
	note("quick load %d" % (k + 1))
	_refresh()


func _build_inspect() -> void:
	var p := _page("Inspect")
	w["inspect_tab"] = p.get_parent()
	var pick := OptionButton.new()
	pick.item_selected.connect(func(k):
		var id := pick.get_item_id(k)
		_inspect = vm.by_id.get(id)
		vm.event_watch = _inspect
		vm.event_log = []
		_refresh_live())
	_row(p, "Object", pick)
	w["pick"] = pick
	_button(p, "Refresh the list", func(): _fill_pick())
	var eh := HBoxContainer.new()
	var vn := LineEdit.new()
	vn.placeholder_text = "variable"
	vn.custom_minimum_size = Vector2(90, 0)
	var vv := LineEdit.new()
	vv.placeholder_text = "value"
	vv.custom_minimum_size = Vector2(90, 0)
	eh.add_child(vn)
	eh.add_child(vv)
	_button(eh, "Set", func():
		if _inspect != null and vn.text != "":
			var val = float(vv.text) if vv.text.is_valid_float() else vv.text
			vm.inst_set(_inspect, vn.text, val)
			note("%s.%s = %s" % [vm.obj_names[_inspect.obj], vn.text, vv.text]))
	p.add_child(eh)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	info.custom_minimum_size = Vector2(W - 24, 0)
	p.add_child(info)
	w["info"] = info
	_note_label(p, "Click an object in the game to inspect it (on the panel's other side: <> moves the panel).")


func _fill_pick() -> void:
	var pick: OptionButton = w["pick"]
	pick.clear()
	for i in vm.instances:
		if not i.dead:
			pick.add_item("%s  #%d" % [vm.obj_names[i.obj], i.id], i.id)
	pick.select(pick.get_item_index(_inspect.id) if _inspect != null and not _inspect.dead and pick.get_item_index(_inspect.id) >= 0 else -1)
	if pick.selected < 0:
		pick.text = "(click an object, or pick one)"


# ------------------------------------------------------------------ refreshing

func _refresh() -> void:
	if not open:
		return
	_loading = true
	var g: Dictionary = vm.globals
	w["name"].text = _gs("charname")
	w["lv"].value = float(g.get("lv", 1.0))
	for k in ["hp", "maxhp", "at", "df", "xp", "gold", "kills"]:
		w[k].value = float(g.get(k, 0.0)) if (g.get(k, 0.0) is float or g.get(k, 0.0) is int) else 0.0
	for i in 8:
		_select(w["item%d" % i], _item_ids, _arr("item", i))
	_select(w["weapon"], _item_ids, float(g.get("weapon", 0.0)))
	_select(w["armor"], _item_ids, float(g.get("armor", 0.0)))
	for i in 4:
		_select(w["phone%d" % i], _phone_ids, _arr("phone", i))
	w["plot"].value = float(g.get("plot", 0.0))
	w["flagv"].value = _arr("flag", int(w["flagn"].value))
	w["fun"].value = _arr("flag", 5)
	for k in 3:
		var s = _slots[k]
		_slot_labels[k].text = ("%s %s" % [s["room_name"], s["time"]]) if s != null else "(empty)"
	w["used"].text = ("Changed with this menu:\n" + "\n".join(eng.debug_used.slice(-12))) if not eng.debug_used.is_empty() else "Nothing changed with this menu yet."
	if (w["pick"] as OptionButton).item_count == 0 or tabs.get_current_tab_control() == w["inspect_tab"]:
		_fill_pick()
	_loading = false
	_refresh_live()


# The read-only parts, updated a few times a second.
func _refresh_live() -> void:
	var g: Dictionary = vm.globals
	var steps := "-"
	var enc = _first("obj_encountererparent")
	if enc != null:
		steps = "%s / %s" % [_gs("encounter"), bi.gm_string(enc.v.get("steps", 0.0))]
	w["steps"].text = "  steps " + steps
	for a in AREAS:
		var killed := _arr("flag", a[1])
		w["area" + a[0]].text = "%s: %d left (%d killed)" % [a[0], maxi(0, a[2] - int(killed)), int(killed)]
	var ms: Array = []
	for i in 3:
		if _arr("monster", i) != 0.0:
			ms.append("slot %d: HP %s / %s" % [i, bi.gm_string(_arr("monsterhp", i)), bi.gm_string(_arr("monstermaxhp", i))])
	w["monsters"].text = "In battle: " + (", ".join(ms) if not ms.is_empty() else "none")
	var info: Label = w["info"]
	if _inspect == null or _inspect.dead:
		info.text = "Nothing picked." if _inspect == null else "That object is gone."
		return
	var i = _inspect
	var spr := int(i.v.get("sprite_index", -1))
	var lines := ["%s  #%d  (parent %s)" % [vm.obj_names[i.obj], i.id, vm.obj_names[vm.obj_parent[i.obj]] if vm.obj_parent[i.obj] >= 0 else "-"],
		"x %s  y %s  depth %s  visible %s  solid %s" % [i.v["x"], i.v["y"], i.v.get("depth"), i.v.get("visible"), i.v.get("solid")],
		"sprite %s  frame %s  box %s" % [vm.sprite_names[spr] if spr >= 0 else "-", bi.gm_string(i.v.get("image_index", 0.0)), vm.bbox(i)]]
	var al: Array = []
	for k in i.alarm.size():
		if float(i.alarm[k]) >= 0.0:
			al.append("%d=%s" % [k, i.alarm[k]])
	lines.append("alarms: " + (" ".join(al) if not al.is_empty() else "none"))
	var keys: Array = i.v.keys()
	keys.sort()
	var vs: Array = []
	for k in keys:
		if k in ["x", "y", "depth", "visible", "solid", "sprite_index", "image_index"]:
			continue
		var val = i.v[k]
		var t: String = bi.gm_string(val) if (val is float or val is int) else str(val)
		vs.append("%s=%s" % [k, t.substr(0, 40)])
	lines.append("variables: " + "  ".join(vs))
	var ev: Array = []
	for e in vm.event_log.slice(-12):
		ev.append("%d %s" % [e[0], String(e[1]).replace("gml_Object_" + vm.obj_names[i.obj] + "_", "")])
	lines.append("last events: " + (", ".join(ev) if not ev.is_empty() else "none yet"))
	info.text = "\n".join(lines)


func _update_watch() -> void:
	if watch_names.is_empty() or vm.room < 0:
		watch_label.text = ""
		return
	var parts: Array = []
	for n in watch_names:
		if n != "":
			parts.append("%s=%s" % [n, _watch_val(n)])
	watch_label.text = "\n".join(parts)


func _watch_val(k: String) -> String:
	if k.begins_with("global."):
		k = k.substr(7)
	if k.begins_with("obj_") and k.contains("."):
		var o = _first(k.substr(0, k.find(".")))
		if o == null:
			return "-"
		var iv = o.v.get(k.substr(k.find(".") + 1))
		return bi.gm_string(iv) if (iv is float or iv is int) else str(iv)
	var dot := k.rfind(".")
	if dot > 0 and k.substr(dot + 1).is_valid_int():
		return bi.gm_string(_arr(k.substr(0, dot), int(k.substr(dot + 1))))
	var v = vm.globals.get(k)
	return "-" if v == null else (bi.gm_string(v) if (v is float or v is int) else str(v))


# ------------------------------------------------------------------ tests

# --debugopen F [TAB]: open the menu at game frame F (screenshots of it with --gameshot).
# --debugtest F: at frame F, use every part of the menu once and print what came of it.
func test_hooks(f: int) -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--debugopen")
	if i >= 0 and i + 1 < a.size() and f == int(a[i + 1]):
		if not open:
			toggle()
		if i + 2 < a.size() and a[i + 2].is_valid_int():
			tabs.current_tab = int(a[i + 2])
	i = a.find("--debugtest")
	if i >= 0 and i + 1 < a.size() and f == int(a[i + 1]):
		self_test()
	i = a.find("--debugkeys")
	if i >= 0 and i + 1 < a.size() and f == int(a[i + 1]):
		_kt = 0
	i = a.find("--debugtest2")
	if i >= 0 and i + 1 < a.size() and f == int(a[i + 1]):
		_monsters_hp()
		_spareable()
		var mm: Array = []
		for k in vm.instances:
			if not k.dead and k.v.has("mercymod") and k.v.has("myself"):
				mm.append("%s mercymod=%s" % [vm.obj_names[k.obj], k.v["mercymod"]])
		_check(_arr("monsterhp", 0) == 1.0 and not mm.is_empty(), "in battle: monster HP %s, %s" % [_arr("monsterhp", 0), ", ".join(mm)])
		print("DEBUGTEST2 done")


# --debugkeys F (windowed): real key events from frame F: F5 opens, arrows don't reach the
# game, Space pauses and resumes, Esc closes and the arrows walk again.
var _kt := -1
var _kx := 0.0


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _keys_test_step() -> void:
	var pl = _player()
	match _kt:
		0:
			_key(KEY_F5, true)
		1:
			_key(KEY_F5, false)
			_check(open, "F5 opens the menu")
			_kx = pl.v["x"]
			_key(KEY_RIGHT, true)
		40:
			_check(pl.v["x"] == _kx, "arrows held with the menu open: player x %s -> %s" % [_kx, pl.v["x"]])
			_key(KEY_RIGHT, false)
			_key(KEY_SPACE, true)
		41:
			_key(KEY_SPACE, false)
			_check(eng.paused, "Space pauses")
			_kx = float(eng.frames)
		60:
			_check(float(eng.frames) == _kx, "paused: frame stays %s" % eng.frames)
			_key(KEY_SPACE, true)
		61:
			_key(KEY_SPACE, false)
			_check(not eng.paused, "Space resumes")
			_key(KEY_ESCAPE, true)
		62:
			_key(KEY_ESCAPE, false)
			_check(not open, "Esc closes the menu")
			_kx = pl.v["x"]
			_key(KEY_LEFT, true)
		90:
			_key(KEY_LEFT, false)
			_check(pl.v["x"] < _kx, "arrows walk again: x %s -> %s" % [_kx, pl.v["x"]])
			eng.game_speed = 4.0
			_kx = float(eng.frames)
		120:
			_check(float(eng.frames) - _kx == 120.0, "speed x4: %s frames in 30 ticks" % (float(eng.frames) - _kx))
			eng.game_speed = 0.5
			_kx = float(eng.frames)
		150:
			_check(float(eng.frames) - _kx == 15.0, "speed x0.5: %s frames in 30 ticks" % (float(eng.frames) - _kx))
			eng.game_speed = 1.0
			toggle()
			tabs.current_tab = 0
			# Click the player on screen.
			var sp: Vector2 = (Vector2(pl.v["x"] + 8, pl.v["y"] + 20) - eng.rec.view) * eng.rec.view_scale
			var m := InputEventMouseButton.new()
			m.button_index = MOUSE_BUTTON_LEFT
			m.pressed = true
			m.position = get_viewport().get_final_transform() * sp     # window pixels
			Input.parse_input_event(m)
			var m2 := m.duplicate()
			m2.pressed = false
			Input.parse_input_event(m2)
		152:
			_check(_inspect != null and vm.obj_names[_inspect.obj] == "obj_mainchara" and tabs.get_current_tab_control() == w["inspect_tab"], "click picks %s" % (vm.obj_names[_inspect.obj] if _inspect != null else "nothing"))
			_check(String(w["info"].text).begins_with("obj_mainchara"), "inspector shows it")
			print("DEBUGKEYS done, %d failed" % _test_fail)
	_kt += 1


func _physics_process(_d: float) -> void:
	if _kt >= 0 and _kt <= 152:
		_keys_test_step()


func _check(ok: bool, what: String) -> void:
	print("DEBUGTEST %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_test_fail += 1


var _test_fail := 0


func self_test() -> void:
	if not open:
		toggle()
	var g: Dictionary = vm.globals
	_apply_lv(7)
	_check(g["lv"] == 7.0 and g["xp"] == float(eng.XP_FOR_LV[7]) and g["maxhp"] == 44.0 and g["at"] == 22.0 and g["df"] == 11.0 and g["hp"] == 44.0, "LV 7 sets EXP %s, HP %s, AT %s, DF %s" % [g["xp"], g["maxhp"], g["at"], g["df"]])
	_set_item(0, 7.0)
	_check(_arr("item", 0) == 7.0 and String(g["itemname"][0][0]).length() > 0, "item slot 1 = %s" % g["itemname"][0][0])
	_equip("scr_weaponeq", 13.0, "weapon")
	_check(g["weapon"] == 13.0 and g["wstrength"] == 3.0, "weapon 13, wstrength %s" % g.get("wstrength"))
	_set_arr("flag", 202, 19.0, "")
	_refresh_live()
	_check(String(w["areaRuins"].text).begins_with("Ruins: 1 left"), "kill count: " + w["areaRuins"].text)
	var room0: int = vm.room
	var snap = DebugState.capture(vm, bi, eng)
	var pl = _player()
	var px: float = pl.v["x"] if pl != null else 0.0
	_warp("room_ruins16", {"plot": 16.0})
	_check(vm.room_names[vm.room] == "room_ruins16" and g["plot"] == 16.0, "warp: %s plot %s" % [vm.room_names[vm.room], vm.globals["plot"]])
	DebugState.restore(vm, bi, eng, snap)
	pl = _player()
	_check(vm.room == room0 and pl != null and pl.v["x"] == px and vm.globals["lv"] == 7.0, "quick load back to %s, player x %s" % [vm.room_names[vm.room], pl.v["x"] if pl != null else "-"])
	g = vm.globals
	_set_noclip(true)
	before_frame()
	var walls := 0
	for i in vm.instances:
		if not i.dead and _is_wall(i.obj) and float(i.v["solid"]) >= 0.5:
			walls += 1
	_check(g["phasing"] == 1.0 and walls == 0, "walk through walls: phasing %s, solid walls %d" % [g["phasing"], walls])
	_set_noclip(false)
	no_damage = true
	before_frame()
	_check(float(g.get("invc", 0.0)) >= 2.0, "no damage: invc %s" % g.get("invc"))
	no_damage = false
	eng.debug_used.append("test")
	_save_game()
	_check(FileAccess.file_exists(bi.save_dir.path_join("file0")) and FileAccess.file_exists(bi.save_dir.path_join("file0.debug")), "save + file0.debug in " + bi.save_dir)
	var hp0: float = g["hp"]
	_start_battle(int(a_group()))
	_check(_exists("obj_battleblcon"), "battle started (battleblcon) from %s" % vm.room_names[vm.room])
	print("DEBUGTEST done, %d failed" % _test_fail)


func a_group() -> int:
	return 4     # Froggit, the Ruins' first encounter group


# ------------------------------------------------------------------ helpers

func note(what: String) -> void:
	if what != "":
		eng.debug_note(what)


func _save_written(path: String) -> void:
	if eng.debug_used.is_empty() or path.ends_with(".debug"):
		return
	var f := FileAccess.open(path + ".debug", FileAccess.WRITE)
	if f != null:
		f.store_string("This save was made after using the debug menu (F5):\n" + "\n".join(eng.debug_used) + "\n")


func _collect_names() -> void:
	var tm = bi.maps.get(int(eng.text_map))
	_item_ids = [[0.0, "(empty)"]]
	_phone_ids = [[0.0, "(empty)"]]
	if tm is Dictionary:
		var ids: Array = []
		var pids: Array = []
		for k in tm:
			var ks := String(k)
			if ks.begins_with("item_name_") and ks.substr(10).is_valid_int():
				ids.append(int(ks.substr(10)))
			elif ks.begins_with("phonename_") and ks.substr(10).is_valid_int():
				pids.append(int(ks.substr(10)))
		ids.sort()
		pids.sort()
		for n in ids:
			if n > 0:
				_item_ids.append([float(n), "%d %s" % [n, String(tm["item_name_%d" % n])]])
		for n in pids:
			if n > 0:
				_phone_ids.append([float(n), "%d %s" % [n, String(tm["phonename_%d" % n])]])
	var order: Array = vm.meta.get("room_order", [])
	for r in order:
		_rooms.append(String(r) if not (r is float or r is int) else vm.room_names[int(r)])


func _item_picker(list: Array) -> OptionButton:
	var ob := OptionButton.new()
	ob.fit_to_longest_item = false
	ob.custom_minimum_size = Vector2(180, 0)
	for x in list:
		ob.add_item(x[1])
	return ob


func _select(ob: OptionButton, list: Array, id: float) -> void:
	for k in list.size():
		if list[k][0] == id:
			ob.select(k)
			return
	ob.select(-1)
	ob.text = "%s (?)" % bi.gm_string(id)


func _name_of(list: Array, id: float) -> String:
	for x in list:
		if x[0] == id:
			return x[1]
	return bi.gm_string(id)


func _row(parent: Control, label: String, c: Control) -> void:
	var hb := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(80, 0)
	hb.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(c)
	parent.add_child(hb)


func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(80, 0)
	s.select_all_on_focus = true
	return s


# An on/off switch that shows its state: "[x] text".
func _toggle(text: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "[  ] " + text
	b.toggled.connect(func(on): b.text = ("[x] " if on else "[  ] ") + text)
	return b


func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	parent.add_child(b)
	return b


func _note_label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	parent.add_child(l)


func _player():
	return _first("obj_mainchara")


func _first(name: String):
	var o = vm.obj_index.get(name)
	return vm.first_of(float(o), {"self": null, "other": null}) if o != null else null


func _exists(name: String) -> bool:
	return _first(name) != null


func _is_wall(obj: int) -> bool:
	for p in ["obj_solidparent", "obj_readablesolid", "obj_solidnpcparent"]:
		var pi = vm.obj_index.get(p)
		if pi != null and vm.is_child_of(obj, int(pi)):
			return true
	return false


func _gs(name: String) -> String:
	var v = vm.globals.get(name, "")
	return bi.gm_string(v) if (v is float or v is int) else str(v)


func _set_g(name: String, val, what: String) -> void:
	vm.globals[name] = val
	note("%s set to %s" % [what, str(val)])


# GML arrays are kept as rows: a 1-D index is row 0.
func _arr(name: String, i: int) -> float:
	var a = vm.globals.get(name)
	if a is Array and a.size() > 0 and a[0] is Array and i < (a[0] as Array).size():
		var v = a[0][i]
		return float(v) if (v is float or v is int) else 0.0
	return 0.0


func _set_arr(name: String, i: int, val: float, what: String) -> void:
	vm.globals[name] = vm._arr_set(vm.globals.get(name), i, -1, val)
	if what != "":
		note("%s set to %s" % [what, bi.gm_string(val)])


func _call(script: String, args := []) -> void:
	var pl = _player()
	var me = pl if pl != null else (vm.instances[0] if not vm.instances.is_empty() else null)
	vm.call_script(script, args, {"self": me, "other": me, "locals": {}, "args": args})
