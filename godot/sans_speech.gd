# The text box a co-op friend gets the first time they press F5 in a universe without cheats.
# Drawn on their screen only, over the game (which carries on for both players: the friend's
# keys are held back from it while the box is up). Z or Enter goes to the next box.
extends RefCounted

const LINES := [
	"* heya.",
	"* whatcha doin' pokin' around in there?",
	"* lookin' for a shortcut?",
	"* heh. hate to break it to ya, pal...",
	"* but the only thing you're debugging...",
	"* is your dignity.",
	"* cheats are disabled.",
	"* guess you'll have to get good the old-fashioned way.",
	"* ...what a sansational disappointment.",
	"* heh heh heh.",
]
const FACES := ["spr_face_sans", "spr_face_sans", "spr_face_sanswink", "spr_face_sans", "spr_face_sans",
	"spr_face_sanswink", "spr_face_sansblink", "spr_face_sans", "spr_face_sanschuckle", "spr_face_sanschuckle2"]
const WRAP := 22                 # characters per line, as Undertale wraps beside a face

var eng
var open := false
var page := 0
var shown := 0.0                 # letters typed so far
var _prev := false


func setup(e) -> void:
	eng = e


func start() -> void:
	open = true
	page = 0
	shown = 0.0
	_prev = true


# Once a frame (real time, this PC only). z: Z or Enter held.
func tick(z: bool) -> void:
	if not open:
		return
	var text: String = LINES[page]
	if shown < text.length():
		var before := int(shown)
		shown = minf(shown + 1.0, float(text.length()))
		if int(shown) != before and text[before] != " " and before % 2 == 0:
			_snd("snd_txtsans")
	if z and not _prev:
		if shown < text.length():
			shown = float(text.length())
		else:
			page += 1
			shown = 0.0
			if page >= LINES.size():
				open = false
	_prev = z


func _snd(n: String) -> void:
	var vm = eng.vm
	if vm.consts.has(n):
		eng.bi.play_sound(int(vm.consts[n]), false)


func _wrap(s: String) -> Array:
	var out: Array = []
	var line := ""
	for w in s.split(" "):
		if line != "" and (line + " " + w).length() > WRAP:
			out.append(line)
			line = "  " + w
		else:
			line = w if line == "" else line + " " + w
	if line != "":
		out.append(line)
	return out


# Draws into the game's picture (bi.canvas is set), after the room, in screen coordinates.
func draw() -> void:
	if not open:
		return
	var bi = eng.bi
	var vm = eng.vm
	# After the room's drawing the picture is in screen space (640 x 480): Undertale's
	# 320 x 240 text box at twice the size.
	var vx := 0.0
	var vy := 0.0
	var sc := 2.0
	var keep: Array = [bi.draw_font, bi.halign, bi.valign, bi.draw_color, bi.draw_alpha]
	var x0 := vx + 16.0 * sc
	var y0 := vy + 160.0 * sc
	bi._rect(x0, y0, x0 + 289.0 * sc, y0 + 76.0 * sc, false, Color.WHITE)
	bi._rect(x0 + 3.0 * sc, y0 + 3.0 * sc, x0 + 286.0 * sc, y0 + 73.0 * sc, false, Color.BLACK)
	var face := int(vm.sprite_index.get(FACES[page], -1))
	if face >= 0:
		bi._draw_sprite_ext(face, 0, x0 + 10.0 * sc, y0 + 8.0 * sc, sc, sc, 0, 16777215, 1)
	bi.draw_font = int(vm.consts.get("fnt_comicsans", vm.consts.get("fnt_maintext", -1.0)))
	bi.halign = 0
	bi.valign = 0
	var text: String = (LINES[page] as String).substr(0, int(shown))
	var ty := y0 + 10.0 * sc
	for l in _wrap(text):
		bi._draw_text(x0 + 68.0 * sc, ty, l, sc, sc, 0.0, 16777215, 1.0)
		ty += 18.0 * sc
	bi.draw_font = keep[0]
	bi.halign = keep[1]
	bi.valign = keep[2]
	bi.draw_color = keep[3]
	bi.draw_alpha = keep[4]
