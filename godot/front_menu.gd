# The front end: your name (asked once, on the first start), the UNDERTALE: Evolved title
# screen, the universe list for Start Game and Host Game, Create, Rename, Delete (asked
# twice, then to the Recycle Bin), Join and Settings. Drawn in Undertale's own fonts with
# its menu music and sounds, all from the extracted game data.
#
# The engine calls tick() every physics frame, key_event() for typed names, mouse() and
# draw() while its screen is FRONT.
extends RefCounted

const Universes = preload("res://universes.gd")

const WHITE := 16777215
const YELLOW := 65535
const GREY := 8421504
const RED := 255
const NAME_MAX := 12

const TITLE_ITEMS := ["Start Game", "Host Game", "Join", "Battle Engine", "Settings", "Quit"]
const ACTIONS := ["PLAY", "RENAME", "CHEATS", "DELETE"]
const SETTINGS_ROWS := ["Your name", "Movement", "Smooth motion", "Window size", "Scaling", "Fullscreen", "Battle Engine LV"]
# Settings rows 1..6 are the engine's own setup rows (engine.gd _setup_value/_setup_change).
const SETUP_ROW_OF := {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 0}
const CARDS := 4
const CARD_H := 66

var eng
var vm
var bi

var page := "title"
var title_sel := 0
var mode := "start"          # universe list for "start" (solo) or "host"
var unis: Array = []
var uni_sel := 0
var uni_scroll := 0
var action := 0
var create_row := 0
var create_name := ""
var create_cheats := false
var settings_row := 0
var text := ""               # the name being typed (name and rename pages)
var text_back := "title"     # where Esc on the name page goes ("" on the first start: nowhere)
var rename_u: Dictionary = {}
var confirm: Dictionary = {} # {"lines": [...], "yes": Callable, "back": page, "sel": 0}
var message: Array = []      # lines for the message page
var message_back := "title"
var music_id := -1.0
var blink := 0
var _hold := 0                # frames the menu keys are ignored (the Enter that ended typing)


func setup(e) -> void:
	eng = e
	vm = e.vm
	bi = e.bi


# ------------------------------------------------------------------ entering

func begin() -> void:
	eng.screen = eng.Screen.FRONT
	if String(eng.settings.get("player/name", "")) == "":
		text = ""
		text_back = ""
		page = "name"
	else:
		_go_title()
	_music(true)


# Screenshots and tests (--front PAGE [MODE]).
func open_page(p: String, m: String) -> void:
	match p:
		"universes":
			_open_list(m if m != "" else "start")
		"create":
			_open_list("start")
			create_name = m
			create_row = 0
			page = "create"
		"delete":
			_open_list("start")
			action = ACTIONS.find("DELETE")
			_uni_pick()
		"name":
			text = m
			text_back = "title"
			page = "name"
		"join":
			_open_join()
		_:
			page = p


func _go_title() -> void:
	page = "title"
	_music(true)
	# Like Minecraft's LAN worlds: the network is listened to from the title screen on, so
	# games are already in the Join list when it opens.
	eng.coop.start_listening()


func back_to_title() -> void:
	eng.screen = eng.Screen.FRONT
	_go_title()


func _music(on: bool) -> void:
	if on:
		if music_id >= 0.0 and _music_playing():
			return
		var snd: int = vm.sound_names.find("mus_menu0")
		if snd >= 0:
			music_id = bi.play_sound(snd, true)
	else:
		for p in bi.players:
			if float(p["id"]) == music_id:
				p["player"].stop()
		music_id = -1.0


func _music_playing() -> bool:
	for p in bi.players:
		if float(p["id"]) == music_id and p["player"].playing:
			return true
	return false


func _sound(name: String) -> void:
	var snd: int = vm.sound_names.find(name)
	if snd >= 0:
		bi.play_sound(snd, false)


func _move() -> void:
	_sound("snd_squeak")


func _select() -> void:
	_sound("snd_select")


# ------------------------------------------------------------------ keys

func editing_text() -> bool:
	return page == "name" or page == "rename" or page == "ipentry" or (page == "create" and create_row == 0)


# Typed names: letters, digits, space and a few marks. Z, X and C are letters here; only
# Enter, Backspace, Esc and the arrows do anything else.
func key_event(ev: InputEventKey) -> bool:
	if not editing_text() or not ev.pressed:
		return false
	var limit := NAME_MAX if page == "name" else (40 if page == "ipentry" else Universes.NAME_MAX)
	match ev.keycode:
		KEY_BACKSPACE:
			if page == "create":
				create_name = create_name.substr(0, maxi(0, create_name.length() - 1))
			else:
				text = text.substr(0, maxi(0, text.length() - 1))
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if ev.echo:
				return true
			_hold = 1
			_text_done()
			return true
		KEY_ESCAPE:
			if ev.echo:
				return true
			_hold = 1
			_text_cancel()
			return true
		KEY_UP, KEY_DOWN:
			if page == "create" and not ev.echo:
				create_row = 1 if ev.keycode == KEY_DOWN else 3
				_move()
			return true
	var ch := ev.unicode
	if ch >= 32 and ch < 127 and not ev.ctrl_pressed and not ev.alt_pressed:
		var c := char(ch)
		if page == "create":
			if create_name.length() < limit:
				create_name += c
		elif text.length() < limit:
			text += c
		return true
	return false


func _text_done() -> void:
	match page:
		"name":
			var n := text.strip_edges()
			if n == "":
				_sound("snd_nosound")
				return
			_select()
			var first := String(eng.settings.get("player/name", "")) == ""
			eng.set_player_name(n)
			if first and not Universes.testing:
				var u: Dictionary = Universes.migrate_legacy(eng.player())
				eng.settings["universes/migrated"] = true
				eng._save_settings()
				if not u.is_empty():
					_show(["Your saved game from before has been", "moved into a universe of its own:", "", u["name"]], "title")
					return
			page = text_back if text_back != "" else "title"
		"rename":
			var n := text.strip_edges()
			if n == "":
				_sound("snd_nosound")
				return
			_select()
			Universes.rename(rename_u, n)
			_open_list(mode, String(rename_u["id"]))
		"create":
			create_row = 1
			_move()
		"ipentry":
			var addr := text.strip_edges()
			if addr == "":
				_sound("snd_nosound")
				return
			_select()
			eng.settings["coop/last_ip"] = addr
			eng._save_settings()
			var hp := addr.rsplit(":", true, 1)
			var port: int = int(hp[1]) if hp.size() > 1 and hp[1].is_valid_int() else eng.CoopNet.PORT
			joining = hp[0] if hp.size() > 1 and hp[1].is_valid_int() else addr
			page = "join"
			eng.coop.join(joining, port)


func _text_cancel() -> void:
	match page:
		"name":
			if text_back != "":
				page = text_back
		"rename":
			page = "universes"
		"create":
			page = "universes"
		"ipentry":
			page = "join"


func tick() -> void:
	eng._poll_menu_keys()
	blink += 1
	if _hold > 0:
		_hold -= 1
		return
	if editing_text():
		return
	var up: bool = eng._menu_pressed(38)
	var down: bool = eng._menu_pressed(40)
	var left: bool = eng._menu_pressed(37)
	var right: bool = eng._menu_pressed(39)
	var ok: bool = eng._menu_pressed(90) or eng._menu_pressed(13)
	var back: bool = eng._menu_pressed(88) or eng._menu_pressed(27)
	match page:
		"title":
			if up or down:
				title_sel = wrapi(title_sel + (1 if down else -1), 0, TITLE_ITEMS.size())
				_move()
			if ok:
				_title_pick(title_sel)
			elif eng._menu_pressed(27):
				eng.get_tree().quit()
		"universes":
			var n := unis.size() + 1
			if up or down:
				uni_sel = wrapi(uni_sel + (1 if down else -1), 0, n)
				_move()
			if (left or right) and uni_sel < unis.size():
				action = wrapi(action + (1 if right else -1), 0, ACTIONS.size())
				_move()
			if ok:
				_uni_pick()
			elif back:
				_go_title()
		"create":
			if up or down:
				create_row = wrapi(create_row + (1 if down else -1), 0, 4)
				_move()
			if (left or right or ok) and create_row == 1:
				create_cheats = not create_cheats
				_move()
			elif ok and create_row == 2:
				_create_now()
			elif (ok and create_row == 3) or back:
				page = "universes"
		"confirm":
			if left or right:
				confirm["sel"] = 1 - int(confirm.get("sel", 0))
				_move()
			if ok:
				var yes := int(confirm.get("sel", 0)) == 1
				_select()
				page = confirm.get("back", "universes")
				if yes:
					(confirm["yes"] as Callable).call()
			elif back:
				page = confirm.get("back", "universes")
		"settings":
			if up or down:
				settings_row = wrapi(settings_row + (1 if down else -1), 0, SETTINGS_ROWS.size())
				_move()
			var d := (1 if right else 0) - (1 if left else 0)
			if settings_row == 0:
				if ok:
					text = String(eng.settings.get("player/name", ""))
					text_back = "settings"
					page = "name"
			else:
				if d == 0 and ok and settings_row != 6:
					d = 1
				if d != 0:
					eng._setup_change(SETUP_ROW_OF[settings_row], d)
					_move()
			if back:
				_go_title()
		"join":
			_join_tick(up, down, ok, back)
		"message":
			if ok or back:
				page = message_back


func _title_pick(i: int) -> void:
	_select()
	match i:
		0:
			_open_list("start")
		1:
			_open_list("host")
		2:
			_open_join()
		3:
			_music(false)
			eng.screen = eng.Screen.LIST
		4:
			settings_row = 0
			page = "settings"
		5:
			eng.get_tree().quit()


func _open_list(m: String, keep_id := "") -> void:
	mode = m
	unis = Universes.list()
	uni_sel = 0
	if keep_id != "":
		for k in unis.size():
			if unis[k]["id"] == keep_id:
				uni_sel = k
	if unis.is_empty():
		uni_sel = 0     # only "create"
	action = 0
	page = "universes"


func _uni_pick() -> void:
	if uni_sel >= unis.size():
		_select()
		create_name = ""
		create_cheats = false
		create_row = 0
		page = "create"
		return
	var u: Dictionary = unis[uni_sel]
	_select()
	match ACTIONS[action]:
		"PLAY":
			_music(false)
			if mode == "host":
				eng.host_universe(u)
			else:
				eng.play_universe(u)
		"RENAME":
			rename_u = u
			text = Universes.display_name(u)
			page = "rename"
		"CHEATS":
			if u.get("cheats", false):
				_show(["Cheats are on in this universe.", "", "Once on, they stay on."], "universes")
			else:
				_ask(["Turn cheats on in", Universes.display_name(u) + "?", "", "This can't be undone: once on,", "cheats stay on in this universe."],
					func(): Universes.enable_cheats(u); _open_list(mode, String(u["id"])), "universes")
		"DELETE":
			_ask(["Delete " + Universes.display_name(u) + "?", "", "Its story, memory and characters", "will be gone."],
				func(): _ask(["Are you really sure?", "", Universes.display_name(u), "goes to the Recycle Bin."],
					func(): _delete(u), "universes"), "universes")


func _delete(u: Dictionary) -> void:
	var err: Error = Universes.delete(u)
	_open_list(mode)
	if err != OK:
		_show(["Couldn't delete that universe.", "(error %d)" % err], "universes")


func _create_now() -> void:
	var n := create_name.strip_edges()
	if n == "":
		n = Universes.default_name(String(eng.settings.get("player/name", "")))
	_select()
	var u: Dictionary = Universes.create(n, create_cheats, eng.player())
	_open_list(mode, String(u["id"]))


func _ask(lines: Array, yes: Callable, back: String) -> void:
	confirm = {"lines": lines, "yes": yes, "back": back, "sel": 0}
	page = "confirm"


func _show(lines: Array, back: String) -> void:
	message = lines
	message_back = back
	page = "message"


# ------------------------------------------------------------------ mouse

func mouse(event: InputEvent, p: Vector2) -> void:
	var h: Array = eng._hit_at(p)
	eng.hover_kind = h[1] if not h.is_empty() else ""
	eng.hover_value = h[2] if not h.is_empty() else null
	if event is InputEventMouseMotion:
		match eng.hover_kind:
			"title":
				if title_sel != int(eng.hover_value):
					title_sel = int(eng.hover_value)
					_move()
			"uni":
				if uni_sel != int(eng.hover_value):
					uni_sel = int(eng.hover_value)
					_move()
			"action":
				action = int(eng.hover_value)
			"crow":
				create_row = int(eng.hover_value)
			"srow":
				settings_row = int(eng.hover_value)
			"yesno":
				confirm["sel"] = int(eng.hover_value)
			"jrow":
				join_sel = int(eng.hover_value)
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if page == "universes":
			uni_sel = clampi(uni_sel + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 0, unis.size())
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		match page:
			"universes", "settings", "join":
				_go_title()
			"create", "rename":
				page = "universes"
			"confirm", "message":
				page = confirm.get("back", "universes") if page == "confirm" else message_back
		return
	if event.button_index != MOUSE_BUTTON_LEFT or h.is_empty():
		return
	match h[1]:
		"jrow":
			# A game: one click picks it, a double-click joins. The other rows are buttons.
			var was := join_sel
			join_sel = int(h[2])
			if join_sel >= eng.coop.games().size() or event.double_click:
				_join_tick(false, false, true, false)
			elif was != join_sel:
				_move()
		"title":
			_title_pick(int(h[2]))
		"uni":
			uni_sel = int(h[2])
			if uni_sel >= unis.size():
				_uni_pick()
		"action":
			action = int(h[2])
			_uni_pick()
		"crow":
			create_row = int(h[2])
			if create_row == 1:
				create_cheats = not create_cheats
			elif create_row == 2:
				_create_now()
			elif create_row == 3:
				page = "universes"
		"srow":
			settings_row = int(h[2])
			if settings_row == 0:
				text = String(eng.settings.get("player/name", ""))
				text_back = "settings"
				page = "name"
		"adj":
			eng._setup_change(SETUP_ROW_OF[int(h[2][0])], int(h[2][1]))
		"yesno":
			confirm["sel"] = int(h[2])
			var yes := int(h[2]) == 1
			page = confirm.get("back", "universes")
			if yes:
				(confirm["yes"] as Callable).call()
		"ok":
			if page == "message":
				page = message_back
			elif page == "join":
				_go_title()
		"back":
			_go_title()


# ------------------------------------------------------------------ drawing

func _t(x: float, y: float, s: String, color := WHITE, font := "fnt_main", sc := 1.0, center := false) -> float:
	bi.canvas = eng
	bi.draw_font = int(vm.consts.get(font, -1.0))
	bi.halign = 0
	bi.valign = 0
	var w: float = bi.text_width(s) * sc
	if center:
		x -= w / 2.0
	bi._draw_text(x, y, s, sc, sc, 0.0, color, 1.0)
	bi.canvas = null
	return w


func _w(s: String, font := "fnt_maintext") -> float:
	bi.draw_font = int(vm.consts.get(font, -1.0))
	return bi.text_width(s)


func draw() -> void:
	eng.hits.clear()
	match page:
		"name":
			_draw_name()
		"title":
			_draw_title()
		"universes":
			_draw_universes()
		"create":
			_draw_create()
		"rename":
			_draw_rename()
		"confirm":
			if confirm.get("back", "") == "universes":
				_draw_universes()
			_draw_confirm()
		"settings":
			_draw_settings()
		"join", "ipentry":
			_draw_join()
		"message":
			_draw_message()


func _caret() -> String:
	return "_" if (blink / 15) % 2 == 0 else " "


func _draw_name() -> void:
	_t(320, 96, "What is your name?", WHITE, "fnt_main", 1.0, true)
	_t(320, 196, text + _caret(), YELLOW, "fnt_main", 2.0, true)
	_t(320, 300, "Your own name, not the fallen human's.", GREY, "fnt_maintext", 1.0, true)
	_t(320, 322, "It's shown above your head in co-op.", GREY, "fnt_maintext", 1.0, true)
	_t(320, 440, "[TYPE] Name  [ENTER] Done" + ("  [ESC] Back" if text_back != "" else ""), GREY, "fnt_maintext", 1.0, true)


func _draw_title() -> void:
	_t(320, 70, "UNDERTALE", WHITE, "fnt_main", 2.0, true)
	_t(320, 140, "Evolved", YELLOW, "fnt_main", 1.0, true)
	var y := 210
	for k in TITLE_ITEMS.size():
		var on := k == title_sel
		var w := _t(320, y, TITLE_ITEMS[k], YELLOW if on else WHITE, "fnt_main", 1.0, true)
		if on:
			eng._heart(320 - w / 2.0 - 30, y + 8)
		eng._hit(Rect2(320 - w / 2.0 - 40, y - 2, w + 80, 34), "title", k)
		y += 36
	var who := String(eng.settings.get("player/name", ""))
	_t(12, 456, "Playing as " + who, GREY, "fnt_maintext")
	var ver: String = "v" + eng.Info.VERSION
	_t(628 - _w(ver), 456, ver, GREY, "fnt_maintext")


func _draw_universes() -> void:
	_t(320, 16, "HOST GAME" if mode == "host" else "START GAME", WHITE, "fnt_main", 1.0, true)
	_t(320, 52, "Choose a universe to open to your network." if mode == "host" else "Choose a universe to play.", GREY, "fnt_maintext", 1.0, true)
	var n := unis.size() + 1
	if uni_sel < uni_scroll:
		uni_scroll = uni_sel
	if uni_sel >= uni_scroll + CARDS:
		uni_scroll = uni_sel - CARDS + 1
	var y := 84
	for k in range(uni_scroll, mini(n, uni_scroll + CARDS)):
		var on := k == uni_sel and page == "universes"
		var r := Rect2(40, y, 560, CARD_H - 6)
		eng.draw_rect(r, Color(1, 1, 0) if on else Color(0.35, 0.35, 0.35), false, 2.0)
		eng._hit(r, "uni", k)
		if on:
			eng._heart(52, y + 22)
		if k < unis.size():
			var u: Dictionary = unis[k]
			_t(76, y + 6, Universes.display_name(u), YELLOW if on else WHITE, "fnt_maintext")
			var sv: Dictionary = u.get("save", {})
			var line2 := "Not started yet"
			if not sv.is_empty():
				line2 = "LV %d      %s      %s" % [sv["lv"], eng.room_title(int(sv["room"])), Universes.time_text(float(sv["time"]))]
			_t(76, y + 24, line2, WHITE if on else GREY, "fnt_maintext")
			var names: Array = []
			for pid in u.get("players", {}):
				names.append(String(u["players"][pid].get("name", "?")))
			var line3 := ", ".join(names) + "  -  last played " + Universes.date_text(float(u.get("last_played", 0)))
			_t(76, y + 41, line3, GREY, "fnt_maintext")
			if u.get("cheats", false):
				_t(588 - _w("CHEATS"), y + 6, "CHEATS", RED, "fnt_maintext")
		else:
			_t(76, y + 20, "+ Create a new universe", YELLOW if on else WHITE, "fnt_maintext")
		y += CARD_H
	if uni_scroll > 0:
		_t(612, 84, "^", GREY, "fnt_maintext")
	if uni_scroll + CARDS < n:
		_t(612, 84 + (CARDS - 1) * CARD_H + 40, "v", GREY, "fnt_maintext")
	# Actions for the chosen universe.
	if uni_sel < unis.size():
		var x := 80.0
		for a in ACTIONS.size():
			var label: String = ACTIONS[a]
			if label == "PLAY" and mode == "host":
				label = "HOST"
			if label == "CHEATS":
				label = "CHEATS: " + ("ON" if unis[uni_sel].get("cheats", false) else "OFF")
			var on: bool = a == action and page == "universes"
			var w := _w(label)
			if on:
				eng._heart(x - 22, 364)
			_t(x, 358, label, YELLOW if on else WHITE, "fnt_maintext")
			eng._hit(Rect2(x - 26, 352, w + 34, 26), "action", a)
			x += w + 56
	_t(320, 440, "[UP/DOWN] Universe  [LEFT/RIGHT] Action  [Z] Choose  [X] Back", GREY, "fnt_maintext", 1.0, true)


func _draw_create() -> void:
	_t(320, 40, "CREATE A UNIVERSE", WHITE, "fnt_main", 1.0, true)
	var rows := ["Name", "Cheats", "CREATE", "BACK"]
	var y := 130
	for k in rows.size():
		var on := k == create_row
		if on:
			eng._heart(110, y + 6)
		eng._hit(Rect2(100, y - 6, 440, 34), "crow", k)
		match k:
			0:
				_t(140, y, "Name", YELLOW if on else WHITE, "fnt_maintext")
				var shown := create_name if create_name != "" else ""
				var c := YELLOW if on else WHITE
				if shown == "" and not on:
					_t(260, y, Universes.default_name(String(eng.settings.get("player/name", ""))), GREY, "fnt_maintext")
				else:
					_t(260, y, shown + (_caret() if on else ""), c, "fnt_maintext")
			1:
				_t(140, y, "Cheats", YELLOW if on else WHITE, "fnt_maintext")
				_t(260, y, "ON" if create_cheats else "OFF", RED if create_cheats else (YELLOW if on else WHITE), "fnt_maintext")
			_:
				_t(140, y + 10, rows[k], YELLOW if on else WHITE, "fnt_maintext")
		y += 50 if k < 2 else 40
	_t(140, 340, "Cheats let you open the debug menu (F5) here.", GREY, "fnt_maintext")
	_t(140, 360, "They can be turned on later, but never off.", GREY, "fnt_maintext")
	if create_row == 0:
		_t(320, 440, "[TYPE] Name (empty = %s)  [ENTER] Next" % Universes.default_name(String(eng.settings.get("player/name", ""))), GREY, "fnt_maintext", 1.0, true)
	else:
		_t(320, 440, "[UP/DOWN] Choose  [Z] Change / Choose  [X] Back", GREY, "fnt_maintext", 1.0, true)


func _draw_rename() -> void:
	_t(320, 96, "Rename the universe", WHITE, "fnt_main", 1.0, true)
	_t(320, 200, text + _caret(), YELLOW, "fnt_maintext", 2.0, true)
	_t(320, 440, "[TYPE] Name  [ENTER] Done  [ESC] Back", GREY, "fnt_maintext", 1.0, true)


func _box(r: Rect2) -> void:
	eng.draw_rect(r, Color.BLACK)
	eng.draw_rect(r, Color.WHITE, false, 3.0)


func _draw_confirm() -> void:
	eng.hits.clear()
	var r := Rect2(80, 120, 480, 230)
	_box(r)
	var y := 140
	for l in confirm.get("lines", []):
		_t(320, y, String(l), WHITE, "fnt_maintext", 1.0, true)
		y += 22
	var sel := int(confirm.get("sel", 0))
	for k in 2:
		var label: String = ["No", "Yes"][k]
		var x := 220 if k == 0 else 380
		var on := k == sel
		var w := _t(x, 304, label, YELLOW if on else WHITE, "fnt_main", 1.0, true)
		if on:
			eng._heart(x - w / 2.0 - 26, 312)
		eng._hit(Rect2(x - w / 2.0 - 30, 300, w + 40, 34), "yesno", k)


func _draw_message() -> void:
	var r := Rect2(80, 120, 480, 230)
	_box(r)
	var y := 140
	for l in message:
		_t(320, y, String(l), WHITE, "fnt_maintext", 1.0, true)
		y += 22
	var w := _t(320, 304, "OK", YELLOW, "fnt_main", 1.0, true)
	eng._heart(320 - w / 2.0 - 26, 312)
	eng._hit(Rect2(260, 300, 120, 34), "ok", null)


func _draw_settings() -> void:
	_t(320, 30, "SETTINGS", WHITE, "fnt_main", 1.0, true)
	var y := 110
	for k in SETTINGS_ROWS.size():
		var on := k == settings_row
		var c := YELLOW if on else WHITE
		if on:
			eng._heart(110, y + 4)
		_t(140, y, SETTINGS_ROWS[k], c, "fnt_maintext")
		eng._hit(Rect2(100, y - 4, 200, 26), "srow", k)
		if k == 0:
			_t(330, y, String(eng.settings.get("player/name", "")), c, "fnt_maintext")
		else:
			var er: int = SETUP_ROW_OF[k]
			_t(330, y, "<", c, "fnt_maintext")
			eng._hit(Rect2(322, y - 4, 22, 26), "adj", [k, -1])
			_t(350, y, eng._setup_value(er), c, "fnt_maintext")
			_t(520, y, ">", c, "fnt_maintext")
			eng._hit(Rect2(512, y - 4, 22, 26), "adj", [k, 1])
		y += 34
	_t(320, 440, "[UP/DOWN] Choose  [LEFT/RIGHT] Change  [Z] Edit name  [X] Back", GREY, "fnt_maintext", 1.0, true)


# ------------------------------------------------------------------ test (--fronttest)

# Drives the menus with real key events, as a player would: types a name on the first start,
# picks Start Game, creates a universe with cheats on, and plays it. Prints FRONTTEST lines.
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print("FRONTTEST %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _press(code: Key, ch := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = ch if down else 0
		e.pressed = down
		Input.parse_input_event(e)
		for k in 3:
			await eng.get_tree().physics_frame


func _type(s: String) -> void:
	for c in s:
		var code := OS.find_keycode_from_string(c.to_upper())
		await _press(code, c.unicode_at(0))


func run_test() -> void:
	for k in 5:
		await eng.get_tree().physics_frame
	_check(page == "name", "first start asks your name")
	await _type("Kyle")
	await _press(KEY_BACKSPACE)
	await _type("e")
	await _press(KEY_ENTER)
	_check(page == "title" and eng.settings.get("player/name", "") == "Kyle", "name typed (Z and X are letters there): " + String(eng.settings.get("player/name", "")))
	await _press(KEY_DOWN)
	await _press(KEY_UP)
	await _press(KEY_Z)
	_check(page == "universes" and mode == "start" and unis.is_empty(), "Start Game opens an empty universe list")
	await _press(KEY_Z)
	_check(page == "create", "the only entry creates one")
	await _type("Zx Test")
	await _press(KEY_ENTER)
	_check(create_row == 1 and create_name == "Zx Test", "universe name typed: " + create_name)
	await _press(KEY_Z)
	_check(create_cheats, "cheats switched on")
	await _press(KEY_DOWN)
	await _press(KEY_Z)
	_check(page == "universes" and unis.size() == 1 and Universes.display_name(unis[0]) == "Zx Test" and bool(unis[0]["cheats"]), "created and listed with cheats on")
	await _press(KEY_RIGHT)
	await _press(KEY_RIGHT)
	await _press(KEY_RIGHT)
	await _press(KEY_Z)
	_check(page == "confirm", "delete asks")
	await _press(KEY_Z)
	_check(page == "universes" and unis.size() == 1, "No keeps it")
	await _press(KEY_Z)
	await _press(KEY_RIGHT)
	await _press(KEY_Z)
	_check(page == "confirm" and String(confirm["lines"][0]).begins_with("Are you really"), "Yes asks a second time")
	await _press(KEY_X)
	_check(page == "universes" and unis.size() == 1, "X at the second question keeps it")
	await _press(KEY_LEFT)
	await _press(KEY_LEFT)
	await _press(KEY_LEFT)
	await _press(KEY_Z)
	_check(eng.screen == eng.Screen.GAME and eng.bi.save_dir == Universes.save_dir(unis[0]["id"]), "PLAY starts the game in the universe's own save folder")
	_check(eng.cheats_allowed(), "cheats allowed in it")
	print("FRONTTEST done, %d failed" % _fails)
	eng.get_tree().quit()

# ------------------------------------------------------------------ join

var join_sel := 0
var joining := ""             # who we're connecting to (shown while it happens)


func _open_join() -> void:
	join_sel = 0
	joining = ""
	eng.coop.start_listening()
	page = "join"


func _join_tick(up: bool, down: bool, ok: bool, back: bool) -> void:
	var c = eng.coop
	if c.join_state == "connecting" or c.join_state == "waiting":
		if back:
			c.cancel_join()
			_move()
		return
	if c.join_state == "failed" or c.join_state == "refused":
		var why: String = c.join_why
		var head := ("%s didn't let you in:" % joining) if c.join_state == "refused" else "Couldn't join " + joining + "."
		c.join_state = ""
		_show([head, ""] + _wrap(why, 44), "join")
		return
	var games: Array = c.games()
	var n := games.size() + 2
	join_sel = clampi(join_sel, 0, n - 1)
	if up or down:
		join_sel = wrapi(join_sel + (1 if down else -1), 0, n)
		_move()
	if back:
		c.stop_listening()
		_go_title()
		return
	if not ok:
		return
	if join_sel < games.size():
		var g: Dictionary = games[join_sel]
		if g.get("full", false):
			_sound("snd_nosound")
			return
		_select()
		joining = String(g.get("host", "?"))
		c.join(String(g["ip"]), int(g.get("port", eng.CoopNet.PORT)))
	elif join_sel == games.size():
		_select()
		text = String(eng.settings.get("coop/last_ip", ""))
		page = "ipentry"
	else:
		c.stop_listening()
		_go_title()


func _wrap(s: String, width: int) -> Array:
	var out: Array = []
	var line := ""
	for w in s.split(" "):
		if line.length() + w.length() + 1 > width and line != "":
			out.append(line)
			line = w
		else:
			line = w if line == "" else line + " " + w
	if line != "":
		out.append(line)
	return out


func _draw_join() -> void:
	var c = eng.coop
	_t(320, 16, "JOIN", WHITE, "fnt_main", 1.0, true)
	var games: Array = c.games()
	_t(320, 52, "Games on your network" if not games.is_empty() else "Looking for games on your network" + ".".repeat((blink / 15) % 4), GREY, "fnt_maintext", 1.0, true)
	var y := 84
	for k in games.size():
		var g: Dictionary = games[k]
		var on := k == join_sel
		var r := Rect2(40, y, 560, 60)
		eng.draw_rect(r, Color(1, 1, 0) if on else Color(0.35, 0.35, 0.35), false, 2.0)
		eng._hit(r, "jrow", k)
		if on:
			eng._heart(52, y + 22)
		_t(76, y + 6, ("%s's game  -  %s" % [g.get("host", "?"), g.get("universe", "")]) if String(g.get("universe", "")) != "" else "%s's game" % g.get("host", "?"), YELLOW if on else WHITE, "fnt_maintext")
		_t(76, y + 24, "LV %d      %s" % [int(g.get("lv", 1)), g.get("room", "")], WHITE if on else GREY, "fnt_maintext")
		var me: Dictionary = (g.get("known", {}) as Dictionary).get(String(eng.player()["id"]), {})
		var note := "New here: you'll start at LV %d with %dG." % [int(g.get("lv", 1)), int(g.get("gold", 0)) / 2]
		if not me.is_empty():
			note = "Your character: LV %d, %dG, %d item%s." % [int(g.get("lv", 1)), int(me.get("gold", 0)), int(me.get("items", 0)), "" if int(me.get("items", 0)) == 1 else "s"]
		if g.get("full", false):
			note = "Full: someone is already playing with %s." % g.get("host", "them")
		_t(76, y + 41, note, GREY, "fnt_maintext")
		y += 66
		if k >= 3:
			break
	var extra := ["Join by IP address...", "Back"]
	for e in 2:
		var idx: int = games.size() + e
		var on := idx == join_sel
		if on:
			eng._heart(52, y + 10)
		_t(76, y + 4, extra[e], YELLOW if on else WHITE, "fnt_maintext")
		eng._hit(Rect2(40, y, 560, 28), "jrow", idx)
		y += 32
	_t(320, 412, "Same network: games show up here by themselves. Elsewhere, try a", GREY, "fnt_maintext", 1.0, true)
	_t(320, 430, "virtual LAN (Tailscale, Radmin VPN) and Join by IP.", GREY, "fnt_maintext", 1.0, true)
	_t(320, 456, "[UP/DOWN] Choose  [Z] or double-click: Join  [X] Back", GREY, "fnt_maintext", 1.0, true)
	if page == "ipentry":
		var b := Rect2(80, 150, 480, 170)
		_box(b)
		_t(320, 170, "The host's address", WHITE, "fnt_maintext", 1.0, true)
		_t(320, 214, text + _caret(), YELLOW, "fnt_maintext", 1.0, true)
		_t(320, 256, "e.g. 192.168.1.20  (or 192.168.1.20:7777)", GREY, "fnt_maintext", 1.0, true)
		_t(320, 290, "[ENTER] Join  [ESC] Back", GREY, "fnt_maintext", 1.0, true)
	elif c.join_state == "connecting" or c.join_state == "waiting":
		var b := Rect2(80, 170, 480, 120)
		_box(b)
		var who := joining if joining != "" else "the host"
		_t(320, 196, ("Connecting to %s" if c.join_state == "connecting" else "Waiting for %s's game") % who + ".".repeat((blink / 15) % 4), WHITE, "fnt_maintext", 1.0, true)
		_t(320, 250, "[X] Cancel", GREY, "fnt_maintext", 1.0, true)

# --jointest: on the Join page, waits for a game to show up and joins it with Z.
func run_join_test() -> void:
	_open_join()
	for k in 600:
		await eng.get_tree().physics_frame
		if not eng.coop.games().is_empty():
			break
	print("JOINTEST games heard: %d" % eng.coop.games().size())
	await _press(KEY_Z)
	for k in 600:
		await eng.get_tree().physics_frame
		if eng.coop.linked:
			break
	print("JOINTEST linked: %s, playing with %s" % [eng.coop.linked, eng.coop.partner.get("name", "-")])
	if not eng.coop.linked:
		await eng.get_tree().physics_frame
		await eng.get_tree().physics_frame
		print("JOINTEST page %s: %s" % [page, " / ".join(message)])
		eng.get_tree().quit()