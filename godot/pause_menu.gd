# The pause menu: Esc in the game (it never reaches Undertale, whose held Esc ends the game).
#
# Resume, Leave (back to the title screen), Exit to desktop, Settings. Each PC has its own: a
# friend's PC tells the host when its player has it open (mp_net.gd "pause"). The game only
# stops when every player has it open; alone, it stops at once. While it is open, this PC's
# player gives the game no keys.
#
# Hosting, it also has Players: remove a friend from the game (they can't come back this
# session), and change the password friends join with.
#
# Leaving a game with friends in it ends the game for them too when you are the host, so that
# asks first; so does leaving or exiting with progress since the last save.
extends RefCounted

const ITEMS := ["Resume", "Leave", "Exit to desktop", "Settings"]
const HOST_ITEMS := ["Resume", "Players", "Leave", "Exit to desktop", "Settings"]
const PW_MAX := 20
const SETTING_ROWS := [1, 2, 3, 4, 5, 6]   # engine.gd _setup_value / _setup_change rows
const WHITE := 16777215
const YELLOW := 65535
const GREY := 8421504

var eng
var open := false
var page := "main"         # "main", "settings", "confirm", "players", "password"
var sel := 0
var set_sel := 0
var pl_sel := 0
var text := ""             # the password being typed
var confirm := {}          # {"lines": [...], "yes": Callable, "sel": 1 (No)}


func setup(e) -> void:
	eng = e


func toggle() -> void:
	if open:
		close()
	else:
		open = true
		page = "main"
		sel = 0
		_sound("snd_select")
		_changed()


func close() -> void:
	open = false
	page = "main"
	_changed()


func _changed() -> void:
	if eng.mpnet != null:
		eng.mpnet.set_paused(open)


# Whether the game stops: everyone who plays has the menu open (alone: you).
func game_stopped() -> bool:
	if not open:
		return false
	if eng.mp == null:
		return true
	for p in eng.mp.list:
		if p.active and not (p.index == 0 or p.paused):
			return false
	return true


func _sound(n: String) -> void:
	var vm = eng.vm
	if vm != null and vm.consts.has(n):
		eng.bi.play_sound(int(vm.consts[n]), false)


func _hosting() -> bool:
	return eng.mpnet != null and eng.mpnet.role == "host" and eng.mp != null


func items() -> Array:
	return HOST_ITEMS if _hosting() else ITEMS


# The Players page's rows: [label, player index or -1 for the password, -2 for Back].
func _player_rows() -> Array:
	var out: Array = []
	for p in eng.mp.list:
		if p.active and p.index != 0:
			out.append([p.name, p.index])
	out.append(["Password: " + ("*".repeat(eng.mpnet.password.length()) if eng.mpnet.password != "" else "none"), -1])
	out.append(["Back", -2])
	return out


# A key event while the menu is open (engine.gd _unhandled_input): typing on the password
# page, otherwise the key.
func key_event(e: InputEventKey) -> void:
	if page == "password":
		match e.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				eng.mpnet.set_password(text.strip_edges())
				eng.mp_notice("Friends now join with the new password." if text.strip_edges() != "" else "Friends now join without a password.")
				_sound("snd_select")
				page = "players"
			KEY_ESCAPE:
				page = "players"
			KEY_BACKSPACE:
				text = text.left(text.length() - 1)
			_:
				if e.unicode > 32 and e.unicode != 127 and text.length() < PW_MAX:
					text += char(e.unicode)
		return
	key(e.keycode)


# A key pressed while the menu is open. Returns true: used.
func key(code: Key) -> bool:
	var up: bool = code == KEY_UP or (eng.wasd and code == KEY_W)
	var down: bool = code == KEY_DOWN or (eng.wasd and code == KEY_S)
	var left: bool = code == KEY_LEFT or (eng.wasd and code == KEY_A)
	var right: bool = code == KEY_RIGHT or (eng.wasd and code == KEY_D)
	var ok := code == KEY_Z or code == KEY_ENTER or code == KEY_KP_ENTER
	var back := code == KEY_X or code == KEY_SHIFT or code == KEY_ESCAPE
	match page:
		"main":
			var its := items()
			sel = clampi(sel, 0, its.size() - 1)
			if up or down:
				sel = wrapi(sel + (1 if down else -1), 0, its.size())
				_sound("snd_squeak")
			elif back:
				close()
			elif ok:
				_sound("snd_select")
				_pick(its[sel])
		"players":
			if not _hosting():
				page = "main"
				return true
			var rows := _player_rows()
			pl_sel = clampi(pl_sel, 0, rows.size() - 1)
			if up or down:
				pl_sel = wrapi(pl_sel + (1 if down else -1), 0, rows.size())
				_sound("snd_squeak")
			elif back:
				page = "main"
			elif ok:
				_sound("snd_select")
				var r: Array = rows[pl_sel]
				var i: int = r[1]
				if i == -2:
					page = "main"
				elif i == -1:
					text = eng.mpnet.password
					page = "password"
				else:
					var nm: String = r[0]
					confirm = {"lines": ["* Remove %s from the game?" % nm, "* They can't come back this time."], "yes": func(): eng.mpnet.kick(i), "sel": 1, "back": "players"}
					page = "confirm"
		"settings":
			if up or down:
				set_sel = wrapi(set_sel + (1 if down else -1), 0, SETTING_ROWS.size())
				_sound("snd_squeak")
			elif left or right:
				eng._setup_change(SETTING_ROWS[set_sel], 1 if right else -1)
				_sound("snd_squeak")
			elif back or ok:
				page = "main"
		"confirm":
			if left or right or up or down:
				confirm["sel"] = 1 - int(confirm["sel"])
				_sound("snd_squeak")
			elif back:
				page = String(confirm.get("back", "main"))
			elif ok:
				page = String(confirm.get("back", "main"))
				if int(confirm["sel"]) == 0:
					(confirm["yes"] as Callable).call()
	return true


func _pick(item: String) -> void:
	match item:
		"Resume":
			close()
		"Settings":
			page = "settings"
			set_sel = 0
		"Players":
			page = "players"
			pl_sel = 0
		"Leave":
			_ask(_leave_lines(), _leave)
		"Exit to desktop":
			_ask(_leave_lines(), _exit)


func _ask(lines: Array, yes: Callable) -> void:
	if lines.is_empty():
		yes.call()
		return
	confirm = {"lines": lines, "yes": yes, "sel": 1}
	page = "confirm"


# What leaving would cost, if anything.
func _leave_lines() -> Array:
	if eng.net_client:
		return []       # your things are kept in the host's game when it is saved
	var out: Array = []
	if eng.mp != null and eng.mp.active_count() > 1:
		out.append("* Everyone's game ends with yours.")
	out.append("* Anything since your last save is lost.")
	return out


func _leave() -> void:
	open = false
	page = "main"
	if eng.net_client:
		eng.net_leave()
	else:
		eng._end_game()


func _exit() -> void:
	open = false
	if eng.net_client:
		eng.mpnet.leave()
	elif eng.mpnet != null:
		eng.mpnet.stop()
	eng.bi._ini_flush()
	eng.get_tree().quit()


# ---------------------------------------------------------------- drawing (640x480 screen)

func draw() -> void:
	if not open:
		return
	eng.draw_rect(Rect2(0, 0, 640, 480), Color(0, 0, 0, 0.5))
	match page:
		"main":
			var its := items()
			var h := 80.0 + its.size() * 38.0
			var top := 240.0 - h / 2.0
			_box(Rect2(190, top, 260, h))
			eng._text(320 - 48, top + 16, "PAUSED", WHITE, "fnt_main")
			for k in its.size():
				var y := top + 66.0 + k * 38.0
				eng._text(250, y, its[k], YELLOW if k == sel else WHITE, "fnt_main")
				if k == sel:
					eng._heart(222, y + 8)
			if eng.mp != null and eng.mp.active_count() > 1 and not game_stopped():
				eng._text(206, top + h + 10, "The game goes on for the others.", GREY, "fnt_maintext")
		"players", "password":
			var rows := _player_rows()
			var h := 90.0 + rows.size() * 36.0
			var top := 240.0 - h / 2.0
			_box(Rect2(130, top, 380, h))
			eng._text(320 - 56, top + 16, "PLAYERS", WHITE, "fnt_main")
			for k in rows.size():
				var y := top + 62.0 + k * 36.0
				var i: int = rows[k][1]
				var c := YELLOW if k == pl_sel else WHITE
				if i >= 0:
					var soul = eng.chat._soul(i) if eng.chat != null else null
					if soul != null:
						eng.draw_texture(soul, Vector2(186, y + 8))
					eng._text(212, y, String(rows[k][0]), c, "fnt_main")
					if k == pl_sel:
						eng._text(380, y + 6, "Remove", GREY, "fnt_maintext")
				else:
					eng._text(186, y, String(rows[k][0]), c, "fnt_main")
				if k == pl_sel:
					eng._heart(156, y + 8)
			if rows.size() == 2:
				eng._text(186, top + h - 30, "No friends here yet.", GREY, "fnt_maintext")
			if page == "password":
				_box(Rect2(100, 170, 440, 140))
				eng._text(176, 186, "The password friends join with", WHITE, "fnt_maintext")
				eng._text(130, 222, text + "_", YELLOW, "fnt_main")
				eng._text(130, 270, "Empty: no password.  [ENTER] OK  [ESC] Back", GREY, "fnt_maintext")
		"settings":
			_box(Rect2(100, 96, 440, 290))
			eng._text(260, 110, "SETTINGS", WHITE, "fnt_main")
			for k in SETTING_ROWS.size():
				var r: int = SETTING_ROWS[k]
				var y := 154.0 + k * 34.0
				var c := YELLOW if k == set_sel else WHITE
				if k == set_sel:
					eng._heart(122, y + 6)
				eng._text(146, y, eng.SETUP_LABELS[r], c, "fnt_maintext")
				eng._text(330, y, "< " + eng._setup_value(r) + " >", c, "fnt_maintext")
			eng._text(130, 360, "[LEFT/RIGHT] Change  [X] Back", GREY, "fnt_maintext")
		"confirm":
			_box(Rect2(70, 150, 500, 180))
			var y := 168.0
			for l in confirm["lines"]:
				eng._text(92, y, String(l), WHITE, "fnt_main")
				y += 36.0
			var s := int(confirm["sel"])
			eng._text(200, 280, "Yes", YELLOW if s == 0 else WHITE, "fnt_main")
			eng._text(400, 280, "No", YELLOW if s == 1 else WHITE, "fnt_main")
			eng._heart((200.0 if s == 0 else 400.0) - 28.0, 288)


func _box(r: Rect2) -> void:
	eng.draw_rect(r, Color.WHITE)
	eng.draw_rect(r.grow(-6), Color.BLACK)
