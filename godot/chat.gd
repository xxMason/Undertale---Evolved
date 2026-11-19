# Chat (docs/MULTIPLAYER.md, "Chat"): T opens it in a game with friends. Each line is marked with
# a SOUL in its player's colour (mp_players.gd COLOURS: host red, then blue, green, yellow).
#
# Every PC types its own lines (the keyboard is this PC's) and keeps its own list: a friend's
# line goes to the host, which sends it to everyone (mp_net.gd "chat"). While typing, this PC's
# player gives the game no keys. Lines show for a while after they come in; all of the last
# few show while the chat is open.
extends RefCounted

const MAX_LEN := 60
const KEEP := 40           # lines kept
const SHOWN := 6           # lines shown while it's open
const FRESH_MS := 8000     # how long a new line shows with the chat closed
const WHITE := 16777215
const GREY := 8421504

var eng
var open := false
var text := ""
var lines: Array = []      # {"i": player index, "name": String, "text": String, "at": msec}
var _souls := {}           # player index -> the SOUL sprite in their colour
var _blink := 0


func setup(e) -> void:
	eng = e


# There's someone to talk to: a game with other players (here, or this PC joined one).
func usable() -> bool:
	return eng.net_client or (eng.mp != null and eng.mpnet != null and eng.mpnet.role == "host")


func start() -> void:
	open = true
	text = ""


func close() -> void:
	open = false
	text = ""


# A key while typing (engine.gd _unhandled_input). Always used.
func key_event(e: InputEventKey) -> void:
	match e.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			var t := text.strip_edges()
			close()
			if t != "":
				eng.mpnet.chat(t)
		KEY_ESCAPE:
			close()
		KEY_BACKSPACE:
			text = text.left(text.length() - 1)
		_:
			if e.unicode >= 32 and e.unicode != 127 and text.length() < MAX_LEN:
				text += char(e.unicode)


# A line from player i (from the host, or the host's own).
func add(i: int, name: String, t: String) -> void:
	lines.append({"i": i, "name": name, "text": t, "at": Time.get_ticks_msec()})
	while lines.size() > KEEP:
		lines.pop_front()
	print("CHAT %s: %s" % [name, t])
	_sound("snd_squeak")


func _sound(n: String) -> void:
	var vm = eng.vm
	if vm != null and vm.consts.has(n):
		eng.bi.play_sound(int(vm.consts[n]), false)


# The SOUL sprite recoloured for player i (Undertale's is red, so it is painted, not tinted).
func _soul(i: int) -> Texture2D:
	if _souls.has(i):
		return _souls[i]
	var spr := int(eng.vm.sprite_index.get("spr_heart", -1))
	var tex: Texture2D = eng.bi.texture(spr, 0) if spr >= 0 else null
	if tex == null:
		return null
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var c: Color = eng.MpPlayers.COLOURS[posmod(i, eng.MpPlayers.COLOURS.size())]
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a > 0.0:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	var out := ImageTexture.create_from_image(img)
	_souls[i] = out
	return out


# Drawn over the game (640x480), bottom left.
func draw() -> void:
	var now := Time.get_ticks_msec()
	var show: Array = []
	if open:
		show = lines.slice(maxi(0, lines.size() - SHOWN))
	else:
		for l in lines:
			if now - int(l["at"]) < FRESH_MS:
				show.append(l)
		show = show.slice(maxi(0, show.size() - 4))
	var bottom := 432.0 if open else 470.0
	var y := bottom - show.size() * 22.0
	for l in show:
		var a := 1.0
		if not open:
			a = clampf(float(FRESH_MS - (now - int(l["at"]))) / 1000.0, 0.0, 1.0)
		var s := "%s: %s" % [l["name"], l["text"]]
		eng.bi.draw_font = int(eng.vm.consts.get("fnt_maintext", -1.0))
		var w: float = eng.bi.text_width(s)
		eng.draw_rect(Rect2(8, y - 2, w + 36, 22), Color(0, 0, 0, 0.7 * a))
		var soul := _soul(int(l["i"]))
		if soul != null:
			eng.draw_texture(soul, Vector2(14, y + 1), Color(1, 1, 1, a))
		eng._text(36, y, s, WHITE, "fnt_maintext")
		y += 22.0
	if open:
		_blink += 1
		eng.draw_rect(Rect2(8, 438, 624, 36), Color.WHITE)
		eng.draw_rect(Rect2(11, 441, 618, 30), Color.BLACK)
		var me: int = eng.mpnet.me if eng.net_client else 0
		var soul := _soul(me)
		if soul != null:
			eng.draw_texture(soul, Vector2(18, 448))
		var caret := "_" if (_blink / 15) % 2 == 0 else " "
		eng._text(42, 446, text + caret, WHITE, "fnt_maintext")
		if text == "":
			eng._text(400, 446, "[ENTER] Send  [ESC] Close", GREY, "fnt_maintext")
