# Battle text writer, following OBJ_WRITER with text type 1 (SCR_TEXTTYPE / SCR_TEXTSETUP):
#   font fnt_main, white, starts 20 px into the box, 16 px per letter, 32 px per line,
#   one letter per logic frame, the SND_TXT2 blip on every letter that is not a space,
#   wraps to a new line when past the right edge.
# Text codes handled: "&" new line, "/" end of a page (Z goes on), "%" ignored,
#   "\Y" "\W" "\R" "\G" "\B" "\O" "\L" "\P" "\p" "\X" colours, "^n" a pause of n*10 frames.
extends RefCounted

const SPACING := 16
const LINE := 32

var pages: PackedStringArray = []
var page := 0
var pos := 0          # characters of the current page revealed (codes included)
var wait := 0         # frames left before the next letter
var sound_cb: Callable
var active := false


func start(text: String, instant := false) -> void:
	pages = text.split("/", false)
	if pages.is_empty():
		pages = PackedStringArray([""])
	page = 0
	pos = 0
	wait = 0
	active = true
	if instant:
		skip()


func current() -> String:
	return pages[page].replace("%", "")


func page_done() -> bool:
	return pos >= current().length()


func is_last_page() -> bool:
	return page >= pages.size() - 1


# Show the whole page at once (X does this in the original).
func skip() -> void:
	pos = current().length()


# Z on a finished page: go to the next page. Returns false when there is none.
func next_page() -> bool:
	if page < pages.size() - 1:
		page += 1
		pos = 0
		wait = 0
		return true
	return false


func tick() -> void:
	if not active or page_done():
		return
	if wait > 0:
		wait -= 1
		return
	var s := current()
	var advance := 1
	var sound := false
	while pos < s.length() and advance > 0:
		var ch := s[pos]
		pos += 1
		if ch == "^":
			if pos < s.length():
				var n := int(s[pos])
				pos += 1
				if n > 0:
					wait = n * 10 - 1
					advance = 0
		elif ch == "\\":
			pos += 1
		elif ch != "&":
			advance -= 1
			if ch != " ":
				sound = true
	if sound and sound_cb.is_valid():
		sound_cb.call()


func draw(canvas: CanvasItem, assets, x: float, y: float, xend: float) -> void:
	if not active:
		return
	var s := current()
	var font: Dictionary = assets.fonts["fnt_main"]
	var color := Color.WHITE
	var cx := x
	var cy := y
	var i := 0
	while i < pos and i < s.length():
		var ch := s[i]
		i += 1
		if ch == "^":
			i += 1
			continue
		if ch == "\\":
			if i < s.length():
				color = _code_color(s[i], color)
			i += 1
			continue
		if ch == "&":
			cx = x
			cy += LINE
			continue
		if cx > xend:
			cx = x
			cy += LINE
		var code := ch.unicode_at(0)
		if font["glyphs"].has(code):
			var g: PackedInt32Array = font["glyphs"][code]
			if g[2] > 0 and g[3] > 0:
				canvas.draw_texture_rect_region(font["tex"], Rect2(cx + g[5], cy, g[2], g[3]), Rect2(g[0], g[1], g[2], g[3]), color)
		cx += SPACING


func _code_color(c: String, fallback: Color) -> Color:
	match c:
		"R": return Color(1, 0, 0)
		"G": return Color(0, 1, 0)
		"W": return Color(1, 1, 1)
		"Y": return Color(1, 1, 0)
		"X": return Color(0, 0, 0)
		"B": return Color(0, 0, 1)
		"O": return Color(1, 0.627, 0.251)
		"L": return Color(0.055, 0.753, 0.992)
		"P": return Color(1, 0, 1)
		"p": return Color(1, 0.733, 0.831)
	return fallback
