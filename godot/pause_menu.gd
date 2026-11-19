# The pause menu: Esc in the game (it never reaches Undertale, whose held Esc ends the game).
#
# Resume, Leave (back to the title screen), Exit to desktop, Settings. Each PC has its own: a
# friend's PC tells the host when its player has it open (mp_net.gd "pause"). The game only
# stops when every player has it open; alone, it stops at once. While it is open, this PC's
# player gives the game no keys.
#
# Leaving a game with friends in it ends the game for them too when you are the host, so that
# asks first; so does leaving or exiting with progress since the last save.
extends RefCounted

const ITEMS := ["Resume", "Leave", "Exit to desktop", "Settings"]
const SETTING_ROWS := [1, 2, 3, 4, 5]      # engine.gd _setup_value / _setup_change rows
const WHITE := 16777215
const YELLOW := 65535
const GREY := 8421504

var eng
var open := false
var page := "main"         # "main", "settings", "confirm"
var sel := 0
var set_sel := 0
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


# A key pressed while the menu is open (engine.gd _unhandled_input). Returns true: used.
func key(code: Key) -> bool:
	var up: bool = code == KEY_UP or (eng.wasd and code == KEY_W)
	var down: bool = code == KEY_DOWN or (eng.wasd and code == KEY_S)
	var left: bool = code == KEY_LEFT or (eng.wasd and code == KEY_A)
	var right: bool = code == KEY_RIGHT or (eng.wasd and code == KEY_D)
	var ok := code == KEY_Z or code == KEY_ENTER or code == KEY_KP_ENTER
	var back := code == KEY_X or code == KEY_SHIFT or code == KEY_ESCAPE
	match page:
		"main":
			if up or down:
				sel = wrapi(sel + (1 if down else -1), 0, ITEMS.size())
				_sound("snd_squeak")
			elif back:
				close()
			elif ok:
				_sound("snd_select")
				_pick(ITEMS[sel])
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
				page = "main"
			elif ok:
				page = "main"
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
			_box(Rect2(190, 120, 260, 230))
			eng._text(320 - 48, 136, "PAUSED", WHITE, "fnt_main")
			for k in ITEMS.size():
				var y := 186.0 + k * 38.0
				eng._text(250, y, ITEMS[k], YELLOW if k == sel else WHITE, "fnt_main")
				if k == sel:
					eng._heart(222, y + 8)
			if eng.mp != null and eng.mp.active_count() > 1 and not game_stopped():
				eng._text(206, 326, "The game goes on for the others.", GREY, "fnt_maintext")
		"settings":
			_box(Rect2(100, 110, 440, 260))
			eng._text(260, 124, "SETTINGS", WHITE, "fnt_main")
			for k in SETTING_ROWS.size():
				var r: int = SETTING_ROWS[k]
				var y := 170.0 + k * 34.0
				var c := YELLOW if k == set_sel else WHITE
				if k == set_sel:
					eng._heart(122, y + 6)
				eng._text(146, y, eng.SETUP_LABELS[r], c, "fnt_maintext")
				eng._text(330, y, "< " + eng._setup_value(r) + " >", c, "fnt_maintext")
			eng._text(130, 340, "[LEFT/RIGHT] Change  [X] Back", GREY, "fnt_maintext")
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
