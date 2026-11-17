# Loads the assets extracted from the player's own copy of Undertale (see
# scripts/prepare-godot.ps1) at runtime: sprite frames, collision masks, fonts and sounds.
extends RefCounted

var base := ""
var meta := {}
var frames := {}   # sprite name -> Array of ImageTexture
var masks := {}    # sprite name -> PackedByteArray, width * height, 1 = solid
var fonts := {}    # font name -> {"tex": ImageTexture, "glyphs": {code: PackedInt32Array}, "line_h": int}
var sounds := {}   # sound name -> AudioStream
var music: AudioStream = null
var error := ""


func load_all(dir: String) -> bool:
	base = dir
	var path := base.path_join("assets.json")
	if not FileAccess.file_exists(path):
		error = "No extracted assets in %s. Run scripts/prepare-godot.ps1 first." % base
		return false
	meta = JSON.parse_string(FileAccess.get_file_as_string(path))
	for name in meta["sprites"]:
		var info: Dictionary = meta["sprites"][name]
		var arr: Array = []
		for i in int(info["frames"]):
			var img := Image.load_from_file(base.path_join("sprites/%s_%d.png" % [name, i]))
			arr.append(ImageTexture.create_from_image(img))
		frames[name] = arr
		masks[name] = _load_mask(name, int(info["width"]), int(info["height"]))
	for name in meta["fonts"]:
		_load_font(name)
	for name in meta["sounds"]:
		var wav := base.path_join("sounds/%s.wav" % name)
		var stream = AudioStreamWAV.load_from_file(wav)
		if stream != null:
			sounds[name] = stream
	var ogg := base.path_join("music/mus_battle1.ogg")
	if FileAccess.file_exists(ogg):
		music = AudioStreamOggVorbis.load_from_file(ogg)
		if music != null:
			music.loop = true
	return true


func sprite_info(name: String) -> Dictionary:
	return meta["sprites"][name]


func _load_mask(name: String, w: int, h: int) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(w * h)
	var rows := FileAccess.get_file_as_string(base.path_join("sprites/%s_mask0.txt" % name)).split("\n", false)
	for y in mini(h, rows.size()):
		var row: String = rows[y]
		for x in mini(w, row.length()):
			m[y * w + x] = 1 if row[x] == "1" else 0
	return m


func _load_font(name: String) -> void:
	var img := Image.load_from_file(base.path_join("fonts/%s.png" % name))
	var glyphs := {}
	var line_h := 0
	for line in FileAccess.get_file_as_string(base.path_join("fonts/%s.glyphs" % name)).split("\n", false):
		var p := line.split(";")
		if p.size() < 7:
			continue
		var g := PackedInt32Array([int(p[1]), int(p[2]), int(p[3]), int(p[4]), int(p[5]), int(p[6])])
		glyphs[int(p[0])] = g
		line_h = maxi(line_h, g[3])
	fonts[name] = {"tex": ImageTexture.create_from_image(img), "glyphs": glyphs, "line_h": line_h}


# Draws text the way GameMaker does with a sprite font: each glyph at x + offset, then
# advance by its shift. "\n" starts a new line.
func draw_text(canvas: CanvasItem, font_name: String, x: float, y: float, text: String, color := Color.WHITE, scale := 1.0) -> float:
	var f: Dictionary = fonts[font_name]
	var cx := x
	var cy := y
	for i in text.length():
		var code := text.unicode_at(i)
		if code == 10:
			cx = x
			cy += f["line_h"] * scale
			continue
		if not f["glyphs"].has(code):
			continue
		var g: PackedInt32Array = f["glyphs"][code]
		if g[2] > 0 and g[3] > 0:
			canvas.draw_texture_rect_region(f["tex"], Rect2(cx + g[5] * scale, cy, g[2] * scale, g[3] * scale), Rect2(g[0], g[1], g[2], g[3]), color)
		cx += g[4] * scale
	return cx - x


func text_width(font_name: String, text: String) -> float:
	var f: Dictionary = fonts[font_name]
	var w := 0.0
	for i in text.length():
		var code := text.unicode_at(i)
		if f["glyphs"].has(code):
			w += f["glyphs"][code][4]
	return w
