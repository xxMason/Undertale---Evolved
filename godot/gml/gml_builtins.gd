# GameMaker 1.4 built-in functions and built-in global variables for gml_vm.gd.
# Drawing goes to `canvas` (set by the host during the draw phase); audio players are
# children of `audio_root`; input comes from `keys` (see gml_keys.gd).
extends RefCounted

var vm
var canvas = null          # a CanvasItem or a gml_recorder.gd
var relative := false       # action_set_relative
var audio_root: Node = null
var keys
var rng = preload("res://gml/gml_random.gd").new()   # GameMaker's own generator
var fixed_seed := -1     # tests: randomize() re-seeds with this instead
# Replays: when >= 0 the clock (current_time, get_timer) is game frames, not real time,
# and randomize() draws its new seed from the generator, so a recorded fight replays exactly.
var clock_ms := -1.0

var tex_cache := {}       # "spr:frame" -> Texture2D
var mask_cache := {}      # "spr:frame" -> PackedByteArray
var bg_cache := {}        # bg index -> Texture2D
var font_cache := {}      # font index -> {tex, glyphs, line_h}
var sound_cache := {}     # sound index -> AudioStream
var players: Array = []   # [{player, sound, id, base_gain}]
var next_sound_id := 100000   # playing-sound ids, as in GameMaker (never clash with asset indexes)
var asset_gain := {}          # sound index -> gain set with audio_sound_gain(sound, ...)
var asset_pitch := {}         # sound index -> pitch set with audio_sound_pitch(sound, ...)

var draw_color := 16777215
var draw_alpha := 1.0
var draw_font := -1
var halign := 0
var valign := 0

var maps := {}
var lists := {}
var next_ds := 1
var view_xview: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var view_yview: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var view_wview: Array = [640.0, 640.0, 640.0, 640.0, 640.0, 640.0, 640.0, 640.0]
var view_hview: Array = [480.0, 480.0, 480.0, 480.0, 480.0, 480.0, 480.0, 480.0]
var keyboard_string := ""
var background_color := 0.0
var start_ms := Time.get_ticks_msec()
var unknown := {}


func _init(v) -> void:
	vm = v
	room_state_reset()


# ---------------------------------------------------------------- helpers

static func gm_string(v) -> String:
	if v is String:
		return v
	if v == null:
		return "undefined"
	var f := float(v)
	if f == floorf(f) and absf(f) < 1e15:
		return str(int(f))
	return "%.2f" % f


# The runner passes alpha to the GPU as a byte, floor(alpha * 255) (ube_draw_probe: 0.333
# draws white at 84 and 0.9 at 229 on black), so blended colours land on the same values.
static func col(c, alpha := 1.0) -> Color:
	var i := int(float(c))
	var a8 := clampf(floorf(alpha * 255.0 + 1e-6), 0.0, 255.0)
	return Color((i & 255) / 255.0, ((i >> 8) & 255) / 255.0, ((i >> 16) & 255) / 255.0, a8 / 255.0)


func texture(spr: int, frame: int) -> Texture2D:
	var si = vm._spr(spr)
	if si == null or int(si[0]) <= 0:
		return null
	var n := int(si[0])
	var f := posmod(frame, n)
	var key := "%d:%d" % [spr, f]
	if tex_cache.has(key):
		return tex_cache[key]
	var path: String = vm.base.path_join("sprites/%s_%d.png" % [vm.sprite_names[spr], f])
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
			tex.set_meta("net", (spr << 16) | f)    # its number on the network (mp_net.gd)
	tex_cache[key] = tex
	return tex


func mask_of(spr: int, frame: int) -> PackedByteArray:
	var key := "%d:%d" % [spr, frame]
	if mask_cache.has(key):
		return mask_cache[key]
	var path: String = vm.base.path_join("sprites/%s_mask%d.bin" % [vm.sprite_names[spr], frame])
	var m := PackedByteArray()
	if not FileAccess.file_exists(path):
		path = vm.base.path_join("sprites/%s_mask0.bin" % vm.sprite_names[spr])
	if FileAccess.file_exists(path):
		m = FileAccess.get_file_as_bytes(path)
	mask_cache[key] = m
	return m


func bg_texture(bg: int) -> Texture2D:
	if bg_cache.has(bg):
		return bg_cache[bg]
	var tex: Texture2D = null
	if bg >= 0 and bg < vm.bg_names.size() and vm.bg_names[bg] != null:
		var path: String = vm.base.path_join("backgrounds/%s.png" % vm.bg_names[bg])
		if FileAccess.file_exists(path):
			tex = ImageTexture.create_from_image(Image.load_from_file(path))
			tex.set_meta("net", (1 << 30) | bg)
	bg_cache[bg] = tex
	return tex


func font(idx: int) -> Dictionary:
	if font_cache.has(idx):
		return font_cache[idx]
	var f := {}
	if idx >= 0 and idx < vm.font_names.size() and vm.font_names[idx] != null:
		var name: String = vm.font_names[idx]
		var png: String = vm.base.path_join("fonts/%s.png" % name)
		if FileAccess.file_exists(png):
			var glyphs := {}
			var line_h := 0
			for line in FileAccess.get_file_as_string(vm.base.path_join("fonts/%s.glyphs" % name)).split("\n", false):
				var p := line.split(";")
				if p.size() >= 7:
					var g := PackedInt32Array([int(p[1]), int(p[2]), int(p[3]), int(p[4]), int(p[5]), int(p[6])])
					glyphs[int(p[0])] = g
					line_h = maxi(line_h, g[3])
			f = {"tex": ImageTexture.create_from_image(Image.load_from_file(png)), "glyphs": glyphs, "line_h": line_h}
			f["tex"].set_meta("net", (2 << 30) | idx)
	font_cache[idx] = f
	return f


func _a(args: Array, i: int, def = 0.0):
	return args[i] if i < args.size() else def


func _n(args: Array, i: int, def := 0.0) -> float:
	if i >= args.size() or args[i] == null or args[i] is String or args[i] is Array:
		return def
	return float(args[i])


func _s(args: Array, i: int, def := "") -> String:
	if i >= args.size():
		return def
	return gm_string(args[i])


# ---------------------------------------------------------------- built-in globals

func global_var(name: String):
	match name:
		"room":
			return float(vm.room)
		"room_width":
			return float(vm.room_width)
		"room_height":
			return float(vm.room_height)
		"room_speed":
			return float(vm.room_speed)
		"current_time":
			return floorf(clock_ms) if clock_ms >= 0.0 else float(Time.get_ticks_msec() - start_ms)
		"view_current":
			return 0.0
		"keyboard_string":
			return keyboard_string
		"keyboard_key", "keyboard_lastkey":
			return 0.0
		"fps", "fps_real":
			return 30.0
		"instance_count":
			return float(vm.instances.size())
		"background_color", "background_colour":
			return background_color
		"mouse_x", "mouse_y":
			return 0.0
		"os_type":
			return 0.0
		"room_persistent":
			return 1.0 if room_persist.get(vm.room, false) else 0.0
		"debug_mode":
			return 0.0
		"view_enabled":
			# Battles always answered 1 here; rooms answer what they say.
			return 1.0 if views_on or save_dir == "" else 0.0
		"background_showcolour":
			return 1.0 if show_colour else 0.0
		"room_first", "room_last":
			var order: Array = vm.meta.get("room_order", [])
			if order.is_empty():
				return 0.0
			return float(vm.room_names.find(order[0] if name == "room_first" else order[order.size() - 1]))
		"keyboard_lastchar":
			return ""
	if room_arr.has(name):
		return [room_arr[name]]
	return null


func set_global_var(name: String, val) -> bool:
	match name:
		"room_speed":
			vm.room_speed = int(float(val))
			return true
		"keyboard_string":
			keyboard_string = gm_string(val)
			return true
		"background_color", "background_colour":
			background_color = float(val)
			return true
		"room_persistent":
			room_persist[vm.room] = float(val) >= 0.5
			return true
		"view_enabled":
			views_on = float(val) >= 0.5
			return true
		"background_showcolour":
			show_colour = float(val) >= 0.5
			return true
	return false


func set_global_array(name: String, a: int, val) -> bool:
	if not room_arr.has(name):
		return false
	if a >= 0 and a < 8:
		room_arr[name][a] = float(val)
	return true


func view_array(name: String):
	var g = global_var(name)
	return g


# ---------------------------------------------------------------- drawing helpers

func draw_self(inst) -> void:
	var v: Dictionary = inst.v
	var spr := int(float(v["sprite_index"]))
	if spr < 0:
		return
	_draw_sprite_ext(spr, int(floorf(float(v["image_index"]))), float(v["x"]), float(v["y"]), float(v["image_xscale"]), float(v["image_yscale"]), float(v["image_angle"]), v["image_blend"], float(v["image_alpha"]))


func _draw_sprite_ext(spr: int, frame: int, x: float, y: float, xs: float, ys: float, angle: float, color, alpha: float) -> void:
	if canvas == null:
		return
	var tex := texture(spr, frame)
	if tex == null:
		return
	var si = vm._spr(spr)
	var xo := float(si[3])
	var yo := float(si[4])
	if xs == 1.0 and ys == 1.0 and angle == 0.0:
		# Same pixels as the transformed draw (whole-pixel origin), one recorded op instead
		# of three: matters with hundreds of dust pixels.
		canvas.draw_texture(tex, Vector2(x - xo, y - yo), col(color, alpha))
		return
	canvas.draw_set_transform(Vector2(x, y), -deg_to_rad(angle), Vector2(xs, ys))
	canvas.draw_texture(tex, Vector2(-xo, -yo), col(color, alpha))
	canvas.draw_set_transform(Vector2.ZERO)


func _draw_sprite_part(spr: int, frame: int, l: float, t: float, w: float, h: float, x: float, y: float, xs: float, ys: float, color, alpha: float) -> void:
	if canvas == null:
		return
	var tex := texture(spr, frame)
	if tex == null:
		return
	canvas.draw_texture_rect_region(tex, Rect2(x, y, w * xs, h * ys), Rect2(l, t, w, h), col(color, alpha))


func _text_lines(s: String) -> PackedStringArray:
	return s.replace("\r", "").replace("#", "\n").split("\n")


func text_width(s: String) -> float:
	var f := font(draw_font)
	if f.is_empty():
		return s.length() * 8.0
	var best := 0.0
	for line in _text_lines(s):
		var w := 0.0
		for i in line.length():
			var code := line.unicode_at(i)
			if f["glyphs"].has(code):
				w += f["glyphs"][code][4]
		best = maxf(best, w)
	return best


func text_height(s: String) -> float:
	var f := font(draw_font)
	var lh := float(f["line_h"]) if not f.is_empty() else 16.0
	return lh * _text_lines(s).size()


func _draw_text(x: float, y: float, s: String, xs := 1.0, ys := 1.0, angle := 0.0, color = null, alpha := -1.0) -> void:
	if canvas == null:
		return
	var f := font(draw_font)
	if f.is_empty():
		return
	var c := col(draw_color if color == null else color, draw_alpha if alpha < 0.0 else alpha)
	var lines := _text_lines(s)
	var lh: float = f["line_h"]
	canvas.draw_set_transform(Vector2(x, y), -deg_to_rad(angle), Vector2(xs, ys))
	var total_h := lh * lines.size()
	var oy := 0.0
	if valign == 1:
		oy = -total_h / 2.0
	elif valign == 2:
		oy = -total_h
	for li in lines.size():
		var line := lines[li]
		var w := 0.0
		for i in line.length():
			var code := line.unicode_at(i)
			if f["glyphs"].has(code):
				w += f["glyphs"][code][4]
		var cx := 0.0
		if halign == 1:
			cx = -roundf(w / 2.0)
		elif halign == 2:
			cx = -w
		var cy := oy + li * lh
		for i in line.length():
			var code := line.unicode_at(i)
			if not f["glyphs"].has(code):
				continue
			var g: PackedInt32Array = f["glyphs"][code]
			if g[2] > 0 and g[3] > 0:
				canvas.draw_texture_rect_region(f["tex"], Rect2(cx + g[5], cy, g[2], g[3]), Rect2(g[0], g[1], g[2], g[3]), c)
			cx += g[4]
	canvas.draw_set_transform(Vector2.ZERO)


func _rect(x1: float, y1: float, x2: float, y2: float, outline: bool, c: Color) -> void:
	if canvas == null:
		return
	if vm.prof != null and c.a < 0.99 and absf(x2 - x1) > 300 and vm.cur_self != null:
		vm.prof["alpha:bigrect " + vm.obj_names[vm.cur_self.obj]] = 1
	var l := minf(x1, x2)
	var t := minf(y1, y2)
	var r := maxf(x1, x2)
	var b := maxf(y1, y2)
	if outline:
		# Outlines land on ceil() of each coordinate (ube_draw_probe: y 16.33 -> row 17,
		# 30.7 -> row 31); filled rectangles already match as they are.
		l = ceilf(l)
		t = ceilf(t)
		r = ceilf(r)
		b = ceilf(b)
		canvas.draw_rect(Rect2(l, t, r - l + 1, 1), c)
		canvas.draw_rect(Rect2(l, b, r - l + 1, 1), c)
		canvas.draw_rect(Rect2(l, t, 1, b - t + 1), c)
		canvas.draw_rect(Rect2(r, t, 1, b - t + 1), c)
	else:
		canvas.draw_rect(Rect2(l, t, r - l + 1, b - t + 1), c)


# ---------------------------------------------------------------- audio helpers

func _stream(snd: int) -> AudioStream:
	if sound_cache.has(snd):
		return sound_cache[snd]
	var s: AudioStream = null
	var info = vm.sound_info[snd] if snd >= 0 and snd < vm.sound_info.size() else null
	if info != null:
		var file: String = info[0]
		if file.begins_with("ext:"):
			var name := file.substr(4)
			if not name.ends_with(".ogg"):
				name += ".ogg"
			var p: String = vm.base.path_join("music/" + name)
			if FileAccess.file_exists(p):
				s = AudioStreamOggVorbis.load_from_file(p)
		elif file != "":
			var p2: String = vm.base.path_join("sounds/" + file)
			if FileAccess.file_exists(p2):
				var data := FileAccess.get_file_as_bytes(p2)
				if data.size() > 4 and data.slice(0, 4).get_string_from_ascii() == "OggS":
					s = AudioStreamOggVorbis.load_from_buffer(data)
				else:
					s = AudioStreamWAV.load_from_buffer(data)
	sound_cache[snd] = s
	return s


# A sound asset index means every playing copy of it; an id from audio_play_sound means
# that one copy.
func _players_for(target) -> Array:
	var t := int(float(target))
	var out: Array = []
	for p in players:
		if (t >= 100000 and p["id"] == t) or (t < 100000 and p["sound"] == t):
			out.append(p)
	return out


func _base_volume(snd: int) -> float:
	var info = vm.sound_info[snd] if snd >= 0 and snd < vm.sound_info.size() else null
	return float(info[1]) if info != null else 1.0


func _apply_volume(p: Dictionary) -> void:
	var g: float = _base_volume(p["sound"]) * float(asset_gain.get(p["sound"], 1.0)) * float(p.get("gain", 1.0))
	p["player"].volume_db = linear_to_db(maxf(g, 0.00001))


# audio_sound_gain(target, gain, ms): sets the gain now or fades to it over ms. On a sound
# asset it changes that sound's gain (every copy, now and later); on an id, one copy.
func _set_gain(target, gain: float, ms: float) -> void:
	var t := int(float(target))
	if t < 100000:
		asset_gain[t] = gain
	for p in _players_for(t):
		if t >= 100000:
			p["gain"] = gain
		var pl: AudioStreamPlayer = p["player"]
		var g: float = _base_volume(p["sound"]) * float(asset_gain.get(p["sound"], 1.0)) * float(p["gain"])
		if p.has("tween") and p["tween"] != null:
			p["tween"].kill()
			p["tween"] = null
		if ms <= 0.0:
			pl.volume_db = linear_to_db(maxf(g, 0.00001))
		else:
			var tw := pl.create_tween()
			tw.tween_method(func(lin: float): pl.volume_db = linear_to_db(maxf(lin, 0.00001)), db_to_linear(pl.volume_db), g, ms / 1000.0)
			p["tween"] = tw

# Co-op (det_audio): whether a sound is still playing is worked out from game frames, not
# from the sound card, so two PCs running the same frames always agree on it.
var det_audio := false


func _alive(p: Dictionary) -> bool:
	if not det_audio:
		return p["player"].playing or p["paused"]
	if p.get("stopped", false):
		return false
	if p["paused"] or p.get("loop", false):
		return true
	return (vm.step_no - int(p.get("t0", 0)) - int(p.get("pt", 0))) < int(p.get("steps", 0))


func _cleanup_players() -> void:
	var keep: Array = []
	for p in players:
		var pl: AudioStreamPlayer = p["player"]
		if _alive(p):
			keep.append(p)
		else:
			pl.queue_free()
	players = keep


static func _muted_bus() -> String:
	if AudioServer.get_bus_index("mp_muted") < 0:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, "mp_muted")
		AudioServer.set_bus_mute(b, true)
	return "mp_muted"


func play_sound(snd: int, loop: bool) -> float:
	if audio_root == null:
		return -1.0
	_cleanup_players()
	var st := _stream(snd)
	if vm.prof != null:
		var inf = vm.sound_info[snd] if snd >= 0 and snd < vm.sound_info.size() else null
		vm.prof["snd:%s -> %s vol=%s%s" % [vm.sound_names[snd] if snd >= 0 and snd < vm.sound_names.size() else str(snd), inf[0] if inf != null else "?", inf[1] if inf != null else "?", " LOOP" if loop else ""]] = 1
	if st == null:
		vm.warn_once("snd:%d" % snd, "missing sound %d" % snd)
		return -1.0
	var stream := st.duplicate() if loop else st
	if loop:
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var pl := AudioStreamPlayer.new()
	pl.stream = stream
	pl.pitch_scale = maxf(float(asset_pitch.get(snd, 1.0)), 0.01)
	audio_root.add_child(pl)
	var id := next_sound_id
	next_sound_id += 1
	var entry := {"player": pl, "sound": snd, "id": id, "paused": false, "gain": 1.0,
		"loop": loop, "t0": vm.step_no, "pt": 0, "pa": -1,
		"steps": ceili(stream.get_length() * 30.0 / pl.pitch_scale)}
	# With several players: a short sound played for one player (their text's voice, their
	# menu's blips) is heard by them only; music and longer sounds are everyone's.
	entry["owner"] = vm.ctx_owner if (vm.owners_on and vm.ctx_owner >= 0 and not loop and stream.get_length() < 6.0) else -1
	if int(entry["owner"]) >= 0 and int(entry["owner"]) != vm.primary_owner:
		pl.bus = _muted_bus()    # someone else's: silent on this PC, sent to theirs (mp_net.gd)
	_apply_volume(entry)
	pl.play()
	players.append(entry)
	return float(id)


# ---------------------------------------------------------------- the functions

const FN_METHODS := {
		"abs": "_f_abs",
		"sign": "_f_sign",
		"round": "_f_round",
		"floor": "_f_floor",
		"ceil": "_f_ceil",
		"frac": "_f_frac",
		"sqrt": "_f_sqrt",
		"sqr": "_f_sqr",
		"power": "_f_power",
		"exp": "_f_exp",
		"ln": "_f_ln",
		"log2": "_f_log2",
		"log10": "_f_log10",
		"sin": "_f_sin",
		"cos": "_f_cos",
		"tan": "_f_tan",
		"arcsin": "_f_arcsin",
		"arccos": "_f_arccos",
		"arctan": "_f_arctan",
		"arctan2": "_f_arctan2",
		"dsin": "_f_dsin",
		"dcos": "_f_dcos",
		"dtan": "_f_dtan",
		"darcsin": "_f_darcsin",
		"darccos": "_f_darccos",
		"darctan": "_f_darctan",
		"darctan2": "_f_darctan2",
		"degtorad": "_f_degtorad",
		"radtodeg": "_f_radtodeg",
		"min": "_f_min",
		"max": "_f_max",
		"mean": "_f_mean",
		"clamp": "_f_clamp",
		"lerp": "_f_lerp",
		"point_direction": "_f_point_direction",
		"point_distance": "_f_point_distance",
		"lengthdir_x": "_f_lengthdir_x",
		"lengthdir_y": "_f_lengthdir_y",
		"random": "_f_random",
		"random_range": "_f_random_range",
		"irandom": "_f_irandom",
		"irandom_range": "_f_irandom_range",
		"choose": "_f_choose",
		"randomize": "_f_randomize",
		"random_set_seed": "_f_random_set_seed",
		"random_get_seed": "_f_random_get_seed",
		"is_real": "_f_is_real",
		"is_string": "_f_is_string",
		"is_undefined": "_f_is_undefined",
		"is_array": "_f_is_array",
		"real": "_f_real",
		"string": "_f_string",
		"string_format": "_f_string_format",
		"string_length": "_f_string_length",
		"string_byte_length": "_f_string_byte_length",
		"string_char_at": "_f_string_char_at",
		"string_copy": "_f_string_copy",
		"string_pos": "_f_string_pos",
		"string_delete": "_f_string_delete",
		"string_insert": "_f_string_insert",
		"string_replace": "_f_string_replace",
		"string_replace_all": "_f_string_replace_all",
		"string_upper": "_f_string_upper",
		"string_lower": "_f_string_lower",
		"string_repeat": "_f_string_repeat",
		"string_count": "_f_string_count",
		"string_digits": "_f_string_digits",
		"string_letters": "_f_string_letters",
		"chr": "_f_chr",
		"ord": "_f_ord",
		"string_width": "_f_string_width",
		"string_height": "_f_string_height",
		"string_width_ext": "_f_string_width_ext",
		"string_height_ext": "_f_string_height_ext",
		"string_hash_to_newline": "_f_string_hash_to_newline",
		"instance_create": "_f_instance_create",
		"instance_destroy": "_f_instance_destroy",
		"action_kill_object": "_f_action_kill_object",
		"instance_exists": "_f_instance_exists",
		"instance_number": "_f_instance_number",
		"instance_find": "_f_instance_find",
		"instance_nearest": "_f_instance_nearest",
		"instance_furthest": "_f_instance_furthest",
		"place_meeting": "_f_place_meeting",
		"instance_place": "_f_place_meeting",
		"place_free": "_f_place_free",
		"place_empty": "_f_place_free",
		"position_meeting": "_f_position_meeting",
		"instance_position": "_f_position_meeting",
		"collision_point": "_f_position_meeting",
		"collision_rectangle": "_f_collision_rectangle",
		"collision_line": "_f_collision_line",
		"collision_circle": "_f_collision_circle",
		"instance_deactivate_all": "_f_instance_deactivate_all",
		"instance_activate_all": "_f_instance_deactivate_all",
		"instance_deactivate_object": "_f_instance_deactivate_all",
		"instance_activate_object": "_f_instance_deactivate_all",
		"instance_deactivate_region": "_f_instance_deactivate_all",
		"instance_activate_region": "_f_instance_deactivate_all",
		"instance_change": "_f_instance_change",
		"action_set_alarm": "_f_action_set_alarm",
		"action_move_to": "_f_action_move_to",
		"action_create_object": "_f_action_create_object",
		"action_sound": "_f_action_sound",
		"action_set_relative": "_f_action_set_relative",
		"action_set_hspeed": "_f_action_set_hspeed",
		"action_set_vspeed": "_f_action_set_hspeed",
		"action_set_friction": "_f_action_set_hspeed",
		"action_set_gravity": "_f_action_set_gravity",
		"action_set_motion": "_f_action_set_motion",
		"action_move": "_f_action_move",
		"action_move_point": "_f_action_move_point",
		"action_previous_room": "_f_action_previous_room",
		"path_start": "_f_path_start",
		"path_end": "_f_path_end",
		"path_get_length": "_f_path_get_length",
		"distance_to_point": "_f_distance_to_point",
		"sprite_prefetch": "_f_sprite_prefetch",
		"sprite_prefetch_multi": "_f_sprite_prefetch",
		"texture_prefetch": "_f_sprite_prefetch",
		"texture_flush": "_f_sprite_prefetch",
		"sprite_delete": "_f_sprite_prefetch",
		"background_delete": "_f_sprite_prefetch",
		"motion_set": "_f_motion_set",
		"motion_add": "_f_motion_add",
		"move_towards_point": "_f_move_towards_point",
		"move_snap": "_f_move_snap",
		"move_wrap": "_f_move_snap",
		"move_bounce_all": "_f_move_snap",
		"move_outside_all": "_f_move_snap",
		"move_contact_solid": "_f_move_snap",
		"event_user": "_f_event_user",
		"event_perform": "_f_event_perform",
		"event_perform_object": "_f_event_perform_object",
		"event_inherited": "_f_event_inherited",
		"script_execute": "_f_script_execute",
		"script_exists": "_f_script_exists",
		"variable_global_exists": "_f_variable_global_exists",
		"variable_instance_exists": "_f_variable_instance_exists",
		"variable_global_get": "_f_variable_global_get",
		"variable_global_set": "_f_variable_global_set",
		"object_get_sprite": "_f_object_get_sprite",
		"object_get_parent": "_f_object_get_parent",
		"object_is_ancestor": "_f_object_is_ancestor",
		"object_get_name": "_f_object_get_name",
		"object_exists": "_f_object_exists",
		"sprite_get_width": "_f_sprite_get_width",
		"sprite_get_height": "_f_sprite_get_height",
		"sprite_get_xoffset": "_f_sprite_get_xoffset",
		"sprite_get_yoffset": "_f_sprite_get_yoffset",
		"sprite_get_number": "_f_sprite_get_number",
		"sprite_exists": "_f_sprite_exists",
		"sprite_get_name": "_f_sprite_get_name",
		"background_get_width": "_f_background_get_width",
		"background_get_height": "_f_background_get_height",
		"asset_get_index": "_f_asset_get_index",
		"asset_get_type": "_f_asset_get_type",
		"room_get_name": "_f_room_get_name",
		"draw_self": "_f_draw_self",
		"draw_sprite": "_f_draw_sprite",
		"draw_sprite_ext": "_f_draw_sprite_ext",
		"draw_sprite_part": "_f_draw_sprite_part",
		"draw_sprite_part_ext": "_f_draw_sprite_part_ext",
		"draw_sprite_stretched": "_f_draw_sprite_stretched",
		"draw_sprite_stretched_ext": "_f_draw_sprite_stretched",
		"draw_sprite_tiled": "_f_draw_sprite_tiled",
		"draw_sprite_tiled_ext": "_f_draw_sprite_tiled",
		"draw_background": "_f_draw_background",
		"draw_background_ext": "_f_draw_background",
		"draw_background_stretched": "_f_draw_background",
		"draw_background_part": "_f_draw_background",
		"draw_background_part_ext": "_f_draw_background",
		"draw_background_tiled": "_f_draw_background",
		"draw_text": "_f_draw_text",
		"draw_text_ext": "_f_draw_text_ext",
		"draw_text_transformed": "_f_draw_text_transformed",
		"draw_text_ext_transformed": "_f_draw_text_ext_transformed",
		"draw_text_colour": "_f_draw_text_colour",
		"draw_text_color": "_f_draw_text_colour",
		"draw_text_transformed_colour": "_f_draw_text_transformed_colour",
		"draw_text_transformed_color": "_f_draw_text_transformed_colour",
		"draw_set_color": "_f_draw_set_color",
		"draw_set_colour": "_f_draw_set_color",
		"draw_get_color": "_f_draw_get_color",
		"draw_get_colour": "_f_draw_get_color",
		"draw_set_alpha": "_f_draw_set_alpha",
		"draw_get_alpha": "_f_draw_get_alpha",
		"draw_set_font": "_f_draw_set_font",
		"draw_get_font": "_f_draw_get_font",
		"draw_set_halign": "_f_draw_set_halign",
		"draw_set_valign": "_f_draw_set_valign",
		"draw_rectangle": "_f_draw_rectangle",
		"draw_rectangle_colour": "_f_draw_rectangle_colour",
		"draw_rectangle_color": "_f_draw_rectangle_colour",
		"draw_line": "_f_draw_line",
		"draw_line_width": "_f_draw_line",
		"draw_line_colour": "_f_draw_line",
		"draw_line_color": "_f_draw_line",
		"draw_line_width_colour": "_f_draw_line",
		"draw_line_width_color": "_f_draw_line",
		"draw_point": "_f_draw_point",
		"draw_circle": "_f_draw_circle",
		"draw_circle_colour": "_f_draw_circle",
		"draw_circle_color": "_f_draw_circle",
		"draw_ellipse": "_f_draw_ellipse",
		"draw_triangle": "_f_draw_triangle",
		"draw_clear": "_f_draw_clear",
		"draw_clear_alpha": "_f_draw_clear",
		"draw_set_blend_mode": "_f_draw_set_blend_mode",
		"draw_set_blend_mode_ext": "_f_draw_set_blend_mode",
		"draw_enable_alphablend": "_f_draw_set_blend_mode",
		"texture_set_interpolation": "_f_draw_set_blend_mode",
		"draw_set_circle_precision": "_f_draw_set_blend_mode",
		"draw_set_colour_write_enable": "_f_draw_set_blend_mode",
		"draw_set_color_write_enable": "_f_draw_set_blend_mode",
		"merge_color": "_f_merge_color",
		"merge_colour": "_f_merge_color",
		"make_color_rgb": "_f_make_color_rgb",
		"make_colour_rgb": "_f_make_color_rgb",
		"make_color_hsv": "_f_make_color_hsv",
		"make_colour_hsv": "_f_make_color_hsv",
		"colour_get_red": "_f_colour_get_red",
		"color_get_red": "_f_colour_get_red",
		"colour_get_green": "_f_colour_get_green",
		"color_get_green": "_f_colour_get_green",
		"colour_get_blue": "_f_colour_get_blue",
		"color_get_blue": "_f_colour_get_blue",
		"draw_primitive_begin": "_f_draw_primitive_begin",
		"draw_primitive_end": "_f_draw_primitive_begin",
		"draw_vertex": "_f_draw_primitive_begin",
		"draw_vertex_colour": "_f_draw_primitive_begin",
		"draw_vertex_color": "_f_draw_primitive_begin",
		"surface_exists": "_f_surface_exists",
		"surface_create": "_f_surface_create",
		"surface_set_target": "_f_surface_set_target",
		"surface_reset_target": "_f_surface_set_target",
		"surface_free": "_f_surface_set_target",
		"draw_surface": "_f_surface_set_target",
		"draw_surface_ext": "_f_surface_set_target",
		"draw_surface_part": "_f_surface_set_target",
		"draw_surface_part_ext": "_f_surface_set_target",
		"surface_copy": "_f_surface_set_target",
		"surface_resize": "_f_surface_set_target",
		"surface_get_width": "_f_surface_get_width",
		"surface_get_height": "_f_surface_get_height",
		"application_surface_enable": "_f_application_surface_enable",
		"application_surface_draw_enable": "_f_application_surface_enable",
		"shader_set": "_f_application_surface_enable",
		"shader_reset": "_f_application_surface_enable",
		"shader_set_uniform_f": "_f_application_surface_enable",
		"shader_get_uniform": "_f_application_surface_enable",
		"shader_get_sampler_index": "_f_application_surface_enable",
		"sprite_create_from_surface": "_f_sprite_create_from_surface",
		"background_create_from_surface": "_f_sprite_create_from_surface",
		"audio_play_sound": "_f_audio_play_sound",
		"audio_stop_sound": "_f_audio_stop_sound",
		"audio_stop_all": "_f_audio_stop_all",
		"audio_is_playing": "_f_audio_is_playing",
		"audio_is_paused": "_f_audio_is_paused",
		"audio_sound_gain": "_f_audio_sound_gain",
		"audio_sound_pitch": "_f_audio_sound_pitch",
		"audio_sound_get_gain": "_f_audio_sound_get_gain",
		"audio_sound_get_pitch": "_f_audio_sound_get_pitch",
		"audio_pause_sound": "_f_audio_pause_sound",
		"audio_resume_sound": "_f_audio_resume_sound",
		"audio_pause_all": "_f_audio_pause_all",
		"audio_resume_all": "_f_audio_resume_all",
		"audio_sound_get_track_position": "_f_audio_sound_get_track_position",
		"audio_sound_set_track_position": "_f_audio_sound_set_track_position",
		"audio_channel_num": "_f_audio_channel_num",
		"audio_master_gain": "_f_audio_channel_num",
		"audio_group_load": "_f_audio_channel_num",
		"audio_falloff_set_model": "_f_audio_channel_num",
		"audio_emitter_create": "_f_audio_channel_num",
		"audio_listener_position": "_f_audio_channel_num",
		"audio_exists": "_f_audio_exists",
		"audio_group_is_loaded": "_f_audio_group_is_loaded",
		"keyboard_check": "_f_keyboard_check",
		"keyboard_check_direct": "_f_keyboard_check_direct",
		"keyboard_check_pressed": "_f_keyboard_check_pressed",
		"keyboard_check_released": "_f_keyboard_check_released",
		"keyboard_key_press": "_f_keyboard_key_press",
		"keyboard_key_release": "_f_keyboard_key_release",
		"keyboard_clear": "_f_keyboard_clear",
		"io_clear": "_f_keyboard_clear",
		"keyboard_set_map": "_f_keyboard_set_map",
		"keyboard_unset_map": "_f_keyboard_set_map",
		"mouse_check_button": "_f_mouse_check_button",
		"mouse_check_button_pressed": "_f_mouse_check_button",
		"mouse_check_button_released": "_f_mouse_check_button",
		"mouse_clear": "_f_mouse_check_button",
		"joystick_exists": "_f_joystick_exists",
		"joystick_check_button": "_f_joystick_exists",
		"joystick_xpos": "_f_joystick_exists",
		"joystick_ypos": "_f_joystick_exists",
		"joystick_pov": "_f_joystick_exists",
		"gamepad_is_connected": "_f_joystick_exists",
		"gamepad_button_check": "_f_joystick_exists",
		"gamepad_button_check_pressed": "_f_joystick_exists",
		"gamepad_axis_value": "_f_joystick_exists",
		"gamepad_get_device_count": "_f_joystick_exists",
		"joystick_has_pov": "_f_joystick_exists",
		"joystick_direction": "_f_joystick_direction",
		"ds_map_create": "_f_ds_map_create",
		"ds_map_add": "_f_ds_map_add",
		"ds_map_set": "_f_ds_map_add",
		"ds_map_replace": "_f_ds_map_add",
		"ds_map_find_value": "_f_ds_map_find_value",
		"ds_map_exists": "_f_ds_map_exists",
		"ds_map_delete": "_f_ds_map_delete",
		"ds_map_size": "_f_ds_map_size",
		"ds_map_destroy": "_f_ds_map_destroy",
		"ds_map_clear": "_f_ds_map_clear",
		"ds_map_find_first": "_f_ds_map_find_first",
		"ds_exists": "_f_ds_exists",
		"ds_list_create": "_f_ds_list_create",
		"ds_list_add": "_f_ds_list_add",
		"ds_list_find_value": "_f_ds_list_find_value",
		"ds_list_size": "_f_ds_list_size",
		"ds_list_destroy": "_f_ds_list_destroy",
		"ds_list_clear": "_f_ds_list_clear",
		"ds_list_delete": "_f_ds_list_delete",
		"ds_list_insert": "_f_ds_list_insert",
		"ds_list_replace": "_f_ds_list_replace",
		"ds_list_set": "_f_ds_list_replace",
		"ds_list_find_index": "_f_ds_list_find_index",
		"ds_list_shuffle": "_f_ds_list_shuffle",
		"ds_list_empty": "_f_ds_list_empty",
		"room_goto": "_f_room_goto",
		"room_goto_next": "_f_room_goto_next",
		"room_goto_previous": "_f_room_goto_previous",
		"room_restart": "_f_room_restart",
		"game_end": "_f_game_end",
		"game_restart": "_f_game_restart",
		"room_set_persistent": "_f_room_set_persistent",
		"room_exists": "_f_room_set_persistent",
		"ini_open": "_f_ini_open2",
		"ini_close": "_f_ini_open2",
		"ini_write_real": "_f_ini_open2",
		"ini_write_string": "_f_ini_open2",
		"ini_open_from_string": "_f_ini_open2",
		"ini_section_delete": "_f_ini_open2",
		"ini_key_delete": "_f_ini_open2",
		"ini_read_real": "_f_ini_open2",
		"ini_read_string": "_f_ini_open2",
		"ini_section_exists": "_f_ini_open2",
		"ini_key_exists": "_f_ini_open2",
		"file_exists": "_f_file2",
		"file_delete": "_f_file2",
		"file_copy": "_f_file2",
		"file_rename": "_f_file2",
		"directory_exists": "_f_file2",
		"directory_create": "_f_file2",
		"file_text_open_read": "_f_file2",
		"file_text_open_write": "_f_file2",
		"file_text_open_append": "_f_file2",
		"file_text_close": "_f_file2",
		"file_text_write_string": "_f_file2",
		"file_text_write_real": "_f_file2",
		"file_text_writeln": "_f_file2",
		"file_text_readln": "_f_file2",
		"file_text_eof": "_f_file2",
		"file_text_read_string": "_f_file2",
		"file_text_read_real": "_f_file2",
		"tile_layer_shift": "_f_tile_layer_shift",
		"tile_layer_hide": "_f_tile_layer_hide",
		"tile_layer_show": "_f_tile_layer_hide",
		"tile_layer_delete": "_f_tile_layer_delete",
		"tile_add": "_f_tile_add",
		"tile_delete": "_f_tile_delete",
		"tile_exists": "_f_tile_exists",
		"room_next": "_f_room_next",
		"room_previous": "_f_room_next",
		"window_get_x": "_f_window_get_zero",
		"window_get_y": "_f_window_get_zero",
		"steam_initialised": "_f_steam_initialised",
		"steam_stats_ready": "_f_steam_initialised",
		"steam_file_exists": "_f_steam_initialised",
		"steam_file_write_file": "_f_steam_initialised",
		"steam_file_delete": "_f_steam_initialised",
		"steam_set_achievement": "_f_steam_initialised",
		"steam_get_achievement": "_f_steam_initialised",
		"os_get_language": "_f_os_get_language",
		"os_get_region": "_f_os_get_region",
		"os_is_paused": "_f_os_is_paused",
		"os_is_network_connected": "_f_os_is_paused",
		"window_set_caption": "_f_window_set_caption",
		"window_set_fullscreen": "_f_window_set_caption",
		"window_set_size": "_f_window_set_caption",
		"window_center": "_f_window_set_caption",
		"window_set_cursor": "_f_window_set_caption",
		"display_reset": "_f_window_set_caption",
		"window_set_position": "_f_window_set_caption",
		"display_set_gui_size": "_f_window_set_caption",
		"window_get_fullscreen": "_f_window_get_fullscreen",
		"window_get_width": "_f_window_get_width",
		"window_get_height": "_f_window_get_height",
		"display_get_width": "_f_display_get_width",
		"display_get_height": "_f_display_get_height",
		"get_timer": "_f_get_timer",
		"date_current_datetime": "_f_date_current_datetime",
		"date_get_year": "_f_date_current_datetime",
		"date_get_month": "_f_date_current_datetime",
		"date_get_day": "_f_date_current_datetime",
		"date_get_hour": "_f_date_current_datetime",
		"date_get_minute": "_f_date_current_datetime",
		"date_get_second": "_f_date_current_datetime",
		"date_get_weekday": "_f_date_current_datetime",
		"current_year": "_f_date_current_datetime",
		"current_month": "_f_date_current_datetime",
		"current_day": "_f_date_current_datetime",
		"show_debug_message": "_f_show_debug_message",
		"show_message": "_f_show_message",
		"show_error": "_f_show_message",
		"get_integer": "_f_get_integer",
		"get_string": "_f_get_integer",
		"buffer_create": "_f_buffer_create",
		"buffer_write": "_f_buffer_create",
		"buffer_read": "_f_buffer_create",
		"buffer_seek": "_f_buffer_create",
		"buffer_delete": "_f_buffer_create",
		"buffer_save_async": "_f_buffer_create",
		"buffer_load_async": "_f_buffer_create",
		"buffer_async_group_begin": "_f_buffer_create",
		"buffer_async_group_end": "_f_buffer_create",
		"buffer_async_group_option": "_f_buffer_create",
		"buffer_get_size": "_f_buffer_create",
		"buffer_save": "_f_buffer_create",
		"buffer_load": "_f_buffer_create",
		"json_encode": "_f_json_encode",
		"json_decode": "_f_json_decode",
		"font_add_sprite": "_f_font_add_sprite",
		"font_add_sprite_ext": "_f_font_add_sprite",
		"gc_collect": "_f_gc_collect",
		"parameter_count": "_f_gc_collect",
		"parameter_string": "_f_parameter_string",
		"code_is_compiled": "_f_code_is_compiled",
		"strlen": "_f_strlen",
}


# Every GameMaker function maps to its own method (see FN_METHODS); the GML compiler calls
# them directly and the interpreter looks them up once per name.
var _fn_callables := {}


func fn(name: String, a: Array, ctx: Dictionary):
	var c = _fn_callables.get(name)
	if c == null:
		var m = FN_METHODS.get(name)
		if m != null:
			c = Callable(self, m)
			_fn_callables[name] = c
	if c != null:
		return c.call(name, a, ctx)
	if not unknown.has(name):
		unknown[name] = true
		vm.vlog("WARN unknown function " + name)
		print("[gml] unknown function ", name)
	return 0.0


func _replace_first(s: String, what: String, with_s: String) -> String:
	var i := s.find(what)
	if i < 0 or what == "":
		return s
	return s.substr(0, i) + with_s + s.substr(i + what.length())


# ---------------------------------------------------------------- function bodies

func _f_abs(name: String, a: Array, ctx: Dictionary):
	return absf(_n(a, 0))
	return 0.0


func _f_sign(name: String, a: Array, ctx: Dictionary):
	return signf(_n(a, 0))
	return 0.0


func _f_round(name: String, a: Array, ctx: Dictionary):
	return float(vm.rne(_n(a, 0)))
	return 0.0


func _f_floor(name: String, a: Array, ctx: Dictionary):
	return floorf(_n(a, 0))
	return 0.0


func _f_ceil(name: String, a: Array, ctx: Dictionary):
	return ceilf(_n(a, 0))
	return 0.0


func _f_frac(name: String, a: Array, ctx: Dictionary):
	return _n(a, 0) - float(int(_n(a, 0)))
	return 0.0


func _f_sqrt(name: String, a: Array, ctx: Dictionary):
	return sqrt(maxf(_n(a, 0), 0.0))
	return 0.0


func _f_sqr(name: String, a: Array, ctx: Dictionary):
	return _n(a, 0) * _n(a, 0)
	return 0.0


func _f_power(name: String, a: Array, ctx: Dictionary):
	return pow(_n(a, 0), _n(a, 1))
	return 0.0


func _f_exp(name: String, a: Array, ctx: Dictionary):
	return exp(_n(a, 0))
	return 0.0


func _f_ln(name: String, a: Array, ctx: Dictionary):
	return log(_n(a, 0))
	return 0.0


func _f_log2(name: String, a: Array, ctx: Dictionary):
	return log(_n(a, 0)) / log(2.0)
	return 0.0


func _f_log10(name: String, a: Array, ctx: Dictionary):
	return log(_n(a, 0)) / log(10.0)
	return 0.0


func _f_sin(name: String, a: Array, ctx: Dictionary):
	return sin(_n(a, 0))
	return 0.0


func _f_cos(name: String, a: Array, ctx: Dictionary):
	return cos(_n(a, 0))
	return 0.0


func _f_tan(name: String, a: Array, ctx: Dictionary):
	return tan(_n(a, 0))
	return 0.0


func _f_arcsin(name: String, a: Array, ctx: Dictionary):
	return asin(_n(a, 0))
	return 0.0


func _f_arccos(name: String, a: Array, ctx: Dictionary):
	return acos(_n(a, 0))
	return 0.0


func _f_arctan(name: String, a: Array, ctx: Dictionary):
	return atan(_n(a, 0))
	return 0.0


func _f_arctan2(name: String, a: Array, ctx: Dictionary):
	return atan2(_n(a, 0), _n(a, 1))
	return 0.0


func _f_dsin(name: String, a: Array, ctx: Dictionary):
	return sin(deg_to_rad(_n(a, 0)))
	return 0.0


func _f_dcos(name: String, a: Array, ctx: Dictionary):
	return cos(deg_to_rad(_n(a, 0)))
	return 0.0


func _f_dtan(name: String, a: Array, ctx: Dictionary):
	return tan(deg_to_rad(_n(a, 0)))
	return 0.0


func _f_darcsin(name: String, a: Array, ctx: Dictionary):
	return rad_to_deg(asin(_n(a, 0)))
	return 0.0


func _f_darccos(name: String, a: Array, ctx: Dictionary):
	return rad_to_deg(acos(_n(a, 0)))
	return 0.0


func _f_darctan(name: String, a: Array, ctx: Dictionary):
	return rad_to_deg(atan(_n(a, 0)))
	return 0.0


func _f_darctan2(name: String, a: Array, ctx: Dictionary):
	return rad_to_deg(atan2(_n(a, 0), _n(a, 1)))
	return 0.0


func _f_degtorad(name: String, a: Array, ctx: Dictionary):
	return deg_to_rad(_n(a, 0))
	return 0.0


func _f_radtodeg(name: String, a: Array, ctx: Dictionary):
	return rad_to_deg(_n(a, 0))
	return 0.0


func _f_min(name: String, a: Array, ctx: Dictionary):
	var m := INF
	for x in a:
		m = minf(m, float(x))
	return m
	return 0.0


func _f_max(name: String, a: Array, ctx: Dictionary):
	var m := -INF
	for x in a:
		m = maxf(m, float(x))
	return m
	return 0.0


func _f_mean(name: String, a: Array, ctx: Dictionary):
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1.0, a.size())
	return 0.0


func _f_clamp(name: String, a: Array, ctx: Dictionary):
	return clampf(_n(a, 0), _n(a, 1), _n(a, 2))
	return 0.0


func _f_lerp(name: String, a: Array, ctx: Dictionary):
	return lerpf(_n(a, 0), _n(a, 1), _n(a, 2))
	return 0.0


func _f_point_direction(name: String, a: Array, ctx: Dictionary):
	return fposmod(rad_to_deg(atan2(-(_n(a, 3) - _n(a, 1)), _n(a, 2) - _n(a, 0))), 360.0)
	return 0.0


func _f_point_distance(name: String, a: Array, ctx: Dictionary):
	return Vector2(_n(a, 0), _n(a, 1)).distance_to(Vector2(_n(a, 2), _n(a, 3)))
	return 0.0


func _f_lengthdir_x(name: String, a: Array, ctx: Dictionary):
	return _n(a, 0) * cos(deg_to_rad(_n(a, 1)))
	return 0.0


func _f_lengthdir_y(name: String, a: Array, ctx: Dictionary):
	return -_n(a, 0) * sin(deg_to_rad(_n(a, 1)))
	return 0.0


func _f_random(name: String, a: Array, ctx: Dictionary):
	return rng.random(_n(a, 0))
	return 0.0


func _f_random_range(name: String, a: Array, ctx: Dictionary):
	var lo := _n(a, 0)
	return lo + rng.frac() * (_n(a, 1) - lo)
	return 0.0


func _f_irandom(name: String, a: Array, ctx: Dictionary):
	return float(rng.irandom(int(_n(a, 0))))
	return 0.0


func _f_irandom_range(name: String, a: Array, ctx: Dictionary):
	var lo := int(_n(a, 0))
	var hi := int(_n(a, 1))
	if hi < lo:
		var sw := lo
		lo = hi
		hi = sw
	return float(lo + rng.irandom(hi - lo))
	return 0.0


func _f_choose(name: String, a: Array, ctx: Dictionary):
	return a[rng.pick(a.size())] if not a.is_empty() else 0.0
	return 0.0


func _f_randomize(name: String, a: Array, ctx: Dictionary):
	if fixed_seed >= 0:
		rng.set_seed(fixed_seed)
	elif clock_ms >= 0.0:
		rng.set_seed(rng.next() & 0x7FFFFFFF)
	else:
		rng.set_seed(int(Time.get_ticks_usec() & 0x7FFFFFFF))
	return 0.0
	return 0.0


func _f_random_set_seed(name: String, a: Array, ctx: Dictionary):
	rng.set_seed(int(_n(a, 0)))
	return 0.0
	return 0.0


func _f_random_get_seed(name: String, a: Array, ctx: Dictionary):
	return float(rng.seed_value)
	return 0.0


func _f_is_real(name: String, a: Array, ctx: Dictionary):
	return 1.0 if (a.size() > 0 and (a[0] is float or a[0] is int)) else 0.0
	return 0.0


func _f_is_string(name: String, a: Array, ctx: Dictionary):
	return 1.0 if (a.size() > 0 and a[0] is String) else 0.0
	return 0.0


func _f_is_undefined(name: String, a: Array, ctx: Dictionary):
	return 1.0 if (a.size() > 0 and a[0] == null) else 0.0
	return 0.0


func _f_is_array(name: String, a: Array, ctx: Dictionary):
	return 1.0 if (a.size() > 0 and a[0] is Array) else 0.0
	return 0.0


func _f_real(name: String, a: Array, ctx: Dictionary):
	var v = _a(a, 0)
	if v is String:
		return v.to_float() if v.is_valid_float() else 0.0
	return float(v) if v != null else 0.0
	return 0.0


func _f_string(name: String, a: Array, ctx: Dictionary):
	return gm_string(_a(a, 0))
	return 0.0


func _f_string_format(name: String, a: Array, ctx: Dictionary):
	var v := _n(a, 0)
	var dec := int(_n(a, 2))
	var tot := int(_n(a, 1))
	var s := ("%." + str(dec) + "f") % v
	return s.lpad(tot)
	return 0.0


func _f_string_length(name: String, a: Array, ctx: Dictionary):
	return float(_s(a, 0).length())
	return 0.0


func _f_string_byte_length(name: String, a: Array, ctx: Dictionary):
	return float(_s(a, 0).to_utf8_buffer().size())
	return 0.0


func _f_string_char_at(name: String, a: Array, ctx: Dictionary):
	var s := _s(a, 0)
	var i := int(_n(a, 1))
	return s[i - 1] if i >= 1 and i <= s.length() else ""
	return 0.0


func _f_string_copy(name: String, a: Array, ctx: Dictionary):
	var s := _s(a, 0)
	var i := maxi(int(_n(a, 1)), 1)
	var n := int(_n(a, 2))
	return s.substr(i - 1, maxi(n, 0)) if i - 1 < s.length() else ""
	return 0.0


func _f_string_pos(name: String, a: Array, ctx: Dictionary):
	return float(_s(a, 1).find(_s(a, 0)) + 1)
	return 0.0


func _f_string_delete(name: String, a: Array, ctx: Dictionary):
	var s := _s(a, 0)
	var i := int(_n(a, 1))
	var n := int(_n(a, 2))
	if i < 1:
		return s
	return s.substr(0, i - 1) + s.substr(i - 1 + n)
	return 0.0


func _f_string_insert(name: String, a: Array, ctx: Dictionary):
	var s := _s(a, 1)
	var i := clampi(int(_n(a, 2)), 1, s.length() + 1)
	return s.substr(0, i - 1) + _s(a, 0) + s.substr(i - 1)
	return 0.0


func _f_string_replace(name: String, a: Array, ctx: Dictionary):
	return _s(a, 0).replace(_s(a, 1), _s(a, 2)) if false else _replace_first(_s(a, 0), _s(a, 1), _s(a, 2))
	return 0.0


func _f_string_replace_all(name: String, a: Array, ctx: Dictionary):
	return _s(a, 0).replace(_s(a, 1), _s(a, 2))
	return 0.0


func _f_string_upper(name: String, a: Array, ctx: Dictionary):
	return _s(a, 0).to_upper()
	return 0.0


func _f_string_lower(name: String, a: Array, ctx: Dictionary):
	return _s(a, 0).to_lower()
	return 0.0


func _f_string_repeat(name: String, a: Array, ctx: Dictionary):
	return _s(a, 0).repeat(maxi(int(_n(a, 1)), 0))
	return 0.0


func _f_string_count(name: String, a: Array, ctx: Dictionary):
	return float(_s(a, 1).count(_s(a, 0)))
	return 0.0


func _f_string_digits(name: String, a: Array, ctx: Dictionary):
	var out := ""
	for ch in _s(a, 0):
		if ch >= "0" and ch <= "9":
			out += ch
	return out
	return 0.0


func _f_string_letters(name: String, a: Array, ctx: Dictionary):
	var out2 := ""
	for ch in _s(a, 0):
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
			out2 += ch
	return out2
	return 0.0


func _f_chr(name: String, a: Array, ctx: Dictionary):
	return String.chr(int(_n(a, 0)))
	return 0.0


func _f_ord(name: String, a: Array, ctx: Dictionary):
	var s := _s(a, 0)
	return float(s.unicode_at(0)) if s.length() > 0 else 0.0
	return 0.0


func _f_string_width(name: String, a: Array, ctx: Dictionary):
	return text_width(_s(a, 0))
	return 0.0


func _f_string_height(name: String, a: Array, ctx: Dictionary):
	return text_height(_s(a, 0))
	return 0.0


func _f_string_width_ext(name: String, a: Array, ctx: Dictionary):
	return text_width(_s(a, 0))
	return 0.0


func _f_string_height_ext(name: String, a: Array, ctx: Dictionary):
	return text_height(_s(a, 0))
	return 0.0


func _f_string_hash_to_newline(name: String, a: Array, ctx: Dictionary):
	return _s(a, 0)
	return 0.0


func _f_instance_create(name: String, a: Array, ctx: Dictionary):
	var inst = vm.instance_create(_n(a, 0), _n(a, 1), int(_n(a, 2)))
	return float(inst.id)
	return 0.0


func _f_instance_destroy(name: String, a: Array, ctx: Dictionary):
	if a.is_empty():
		vm.instance_destroy(ctx["self"])
	else:
		for i in vm.resolve(a[0], ctx):
			vm.instance_destroy(i)
	return 0.0
	return 0.0


func _f_action_kill_object(name: String, a: Array, ctx: Dictionary):
	vm.instance_destroy(ctx["self"])
	return 0.0
	return 0.0


func _f_instance_exists(name: String, a: Array, ctx: Dictionary):
	return 1.0 if not vm.resolve(_a(a, 0), ctx).is_empty() else 0.0
	return 0.0


func _f_instance_number(name: String, a: Array, ctx: Dictionary):
	return float(vm.resolve(_a(a, 0), ctx).size())
	return 0.0


func _f_instance_find(name: String, a: Array, ctx: Dictionary):
	var r: Array = vm.resolve(_a(a, 0), ctx)
	var k := int(_n(a, 1))
	return float(r[k].id) if k >= 0 and k < r.size() else vm.NOONE
	return 0.0


func _f_instance_nearest(name: String, a: Array, ctx: Dictionary):
	var best = null
	var bd := INF
	for i in vm.resolve(_a(a, 2), ctx):
		var d := Vector2(float(i.v["x"]), float(i.v["y"])).distance_to(Vector2(_n(a, 0), _n(a, 1)))
		if d < bd:
			bd = d
			best = i
	return float(best.id) if best != null else vm.NOONE
	return 0.0


func _f_instance_furthest(name: String, a: Array, ctx: Dictionary):
	var best2 = null
	var bd2 := -1.0
	for i in vm.resolve(_a(a, 2), ctx):
		var d2 := Vector2(float(i.v["x"]), float(i.v["y"])).distance_to(Vector2(_n(a, 0), _n(a, 1)))
		if d2 > bd2:
			bd2 = d2
			best2 = i
	return float(best2.id) if best2 != null else vm.NOONE
	return 0.0


func _f_place_meeting(name: String, a: Array, ctx: Dictionary):
	var me = ctx["self"]
	if me == null:
		return 0.0 if name == "place_meeting" else vm.NOONE
	var ox: float = me.v["x"]
	var oy: float = me.v["y"]
	me.v["x"] = _n(a, 0)
	me.v["y"] = _n(a, 1)
	var hit = null
	for i in vm.resolve(_a(a, 2), ctx):
		if i != me and vm.collide(me, i):
			hit = i
			break
	me.v["x"] = ox
	me.v["y"] = oy
	if name == "place_meeting":
		return 1.0 if hit != null else 0.0
	return float(hit.id) if hit != null else vm.NOONE
	return 0.0


func _f_place_free(name: String, a: Array, ctx: Dictionary):
	return 1.0
	return 0.0


func _f_position_meeting(name: String, a: Array, ctx: Dictionary):
	var obj_arg := 2
	var px := int(floorf(_n(a, 0)))
	var py := int(floorf(_n(a, 1)))
	var hit2 = null
	for i in vm.resolve(_a(a, obj_arg), ctx):
		if name == "collision_point" and _n(a, 4) > 0.5 and i == ctx["self"]:
			continue
		var pr := Rect2i(px, py, 1, 1)
		if (vm.bbox_rect(i, pr) if name == "collision_point" and _n(a, 3) < 0.5 else vm.collide_rect(i, pr)):
			hit2 = i
			break
	if name == "position_meeting":
		return 1.0 if hit2 != null else 0.0
	return float(hit2.id) if hit2 != null else vm.NOONE
	return 0.0


func _f_collision_rectangle(name: String, a: Array, ctx: Dictionary):
	var x1 := int(floorf(minf(_n(a, 0), _n(a, 2))))
	var y1 := int(floorf(minf(_n(a, 1), _n(a, 3))))
	var x2 := int(floorf(maxf(_n(a, 0), _n(a, 2))))
	var y2 := int(floorf(maxf(_n(a, 1), _n(a, 3))))
	var rect := Rect2i(x1, y1, x2 - x1 + 1, y2 - y1 + 1)
	var precise := _n(a, 5) > 0.5
	for i in vm.resolve(_a(a, 4), ctx):
		if _n(a, 6) > 0.5 and i == ctx["self"]:
			continue
		if vm.collide_rect(i, rect) if precise else vm.bbox_rect(i, rect):
			return float(i.id)
	return vm.NOONE
	return 0.0


func _f_collision_line(name: String, a: Array, ctx: Dictionary):
	var p0 := Vector2(_n(a, 0), _n(a, 1))
	var p1 := Vector2(_n(a, 2), _n(a, 3))
	var precise := _n(a, 5) > 0.5
	for i in vm.resolve(_a(a, 4), ctx):
		if _n(a, 6) > 0.5 and i == ctx["self"]:
			continue
		if vm.collide_line(i, p0, p1, precise):
			return float(i.id)
	return vm.NOONE
	return 0.0


func _f_collision_circle(name: String, a: Array, ctx: Dictionary):
	var cx := _n(a, 0)
	var cy := _n(a, 1)
	var rad := _n(a, 2)
	for i in vm.resolve(_a(a, 3), ctx):
		if _n(a, 5) > 0.5 and i == ctx["self"]:
			continue
		var bb: Rect2i = vm.bbox(i)
		var nx := clampf(cx, bb.position.x, bb.end.x)
		var ny := clampf(cy, bb.position.y, bb.end.y)
		if Vector2(nx, ny).distance_to(Vector2(cx, cy)) <= rad:
			return float(i.id)
	return vm.NOONE
	return 0.0


func _f_instance_deactivate_all(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_instance_change(name: String, a: Array, ctx: Dictionary):
	var me2 = ctx["self"]
	if me2 != null:
		me2.obj = int(_n(a, 0))
		vm.inst_version += 1
		vm.obj_changed_step = vm.step_no
		if _n(a, 1) > 0.5:
			vm.perform_event(me2, vm.EV_CREATE, 0, null)
	return 0.0
	return 0.0


func _f_action_set_alarm(name: String, a: Array, ctx: Dictionary):
	if ctx["self"] != null:
		ctx["self"].alarm[int(_n(a, 1))] = vm.alarm_value(_n(a, 0))
	return 0.0
	return 0.0


func _f_action_move_to(name: String, a: Array, ctx: Dictionary):
	var rx := float(ctx["self"].v["x"]) if relative else 0.0
	var ry := float(ctx["self"].v["y"]) if relative else 0.0
	vm.inst_set(ctx["self"], "x", rx + _n(a, 0))
	vm.inst_set(ctx["self"], "y", ry + _n(a, 1))
	return 0.0
	return 0.0


func _f_action_create_object(name: String, a: Array, ctx: Dictionary):
	vm.instance_create(_n(a, 1), _n(a, 2), int(_n(a, 0)))
	return 0.0
	return 0.0


func _f_action_sound(name: String, a: Array, ctx: Dictionary):
	play_sound(int(_n(a, 0)), _n(a, 1) > 0.5)
	return 0.0
	return 0.0


func _f_action_set_relative(name: String, a: Array, ctx: Dictionary):
	relative = _n(a, 0) > 0.5
	return 0.0
	return 0.0


func _f_action_set_hspeed(name: String, a: Array, ctx: Dictionary):
	var key: String = {"action_set_hspeed": "hspeed", "action_set_vspeed": "vspeed", "action_set_friction": "friction"}[name]
	var cur := float(ctx["self"].v.get(key, 0.0)) if relative else 0.0
	vm.inst_set(ctx["self"], key, cur + _n(a, 0))
	return 0.0
	return 0.0


func _f_action_set_gravity(name: String, a: Array, ctx: Dictionary):
	vm.inst_set(ctx["self"], "gravity_direction", _n(a, 0))
	vm.inst_set(ctx["self"], "gravity", (float(ctx["self"].v["gravity"]) if relative else 0.0) + _n(a, 1))
	return 0.0
	return 0.0


func _f_action_set_motion(name: String, a: Array, ctx: Dictionary):
	var me5 = ctx["self"]
	if relative:
		vm.inst_set(me5, "hspeed", float(me5.v["hspeed"]) + _n(a, 1) * cos(deg_to_rad(_n(a, 0))))
		vm.inst_set(me5, "vspeed", float(me5.v["vspeed"]) - _n(a, 1) * sin(deg_to_rad(_n(a, 0))))
	else:
		vm.inst_set(me5, "direction", _n(a, 0))
		vm.inst_set(me5, "speed", _n(a, 1))
	return 0.0
	return 0.0


func _f_action_move(name: String, a: Array, ctx: Dictionary):
	# 3x3 grid of allowed directions, e.g. "000001000" = right.
	var dirs := [135.0, 90.0, 45.0, 180.0, -1.0, 0.0, 225.0, 270.0, 315.0]
	var choices: Array = []
	var pattern := _s(a, 0)
	for k in mini(9, pattern.length()):
		if pattern[k] == "1":
			choices.append(dirs[k])
	if not choices.is_empty():
		var d0: float = choices[rng.pick(choices.size())]
		var sp0 := _n(a, 1)
		if d0 < 0.0:
			sp0 = 0.0
			d0 = 0.0
		vm.inst_set(ctx["self"], "direction", d0)
		vm.inst_set(ctx["self"], "speed", (float(ctx["self"].v["speed"]) if relative else 0.0) + sp0)
	return 0.0
	return 0.0


func _f_action_move_point(name: String, a: Array, ctx: Dictionary):
	var me6 = ctx["self"]
	vm.inst_set(me6, "direction", fposmod(rad_to_deg(atan2(-(_n(a, 1) - float(me6.v["y"])), _n(a, 0) - float(me6.v["x"]))), 360.0))
	vm.inst_set(me6, "speed", _n(a, 2))
	return 0.0
	return 0.0


func _f_action_previous_room(name: String, a: Array, ctx: Dictionary):
	vm.pending_room = vm.room - 1
	return 0.0
	return 0.0


func _f_path_start(name: String, a: Array, ctx: Dictionary):
	vm.path_start(ctx["self"], int(_n(a, 0)), _n(a, 1), int(_n(a, 2)), _n(a, 3) > 0.5)
	return 0.0
	return 0.0


func _f_path_end(name: String, a: Array, ctx: Dictionary):
	if ctx["self"] != null:
		ctx["self"].v["path_index"] = -1.0
	return 0.0
	return 0.0


func _f_path_get_length(name: String, a: Array, ctx: Dictionary):
	return vm.path_length(int(_n(a, 0)))
	return 0.0


func _f_distance_to_point(name: String, a: Array, ctx: Dictionary):
	var bb: Rect2i = vm.bbox(ctx["self"])
	var px := _n(a, 0)
	var py := _n(a, 1)
	var dx := 0.0
	var dy := 0.0
	if px < bb.position.x: dx = bb.position.x - px
	elif px > bb.end.x: dx = px - bb.end.x
	if py < bb.position.y: dy = bb.position.y - py
	elif py > bb.end.y: dy = py - bb.end.y
	return sqrt(dx * dx + dy * dy)
	return 0.0


func _f_sprite_prefetch(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_motion_set(name: String, a: Array, ctx: Dictionary):
	vm.inst_set(ctx["self"], "direction", _n(a, 0))
	vm.inst_set(ctx["self"], "speed", _n(a, 1))
	return 0.0
	return 0.0


func _f_motion_add(name: String, a: Array, ctx: Dictionary):
	var me3 = ctx["self"]
	var hs := float(me3.v["hspeed"]) + _n(a, 1) * cos(deg_to_rad(_n(a, 0)))
	var vs := float(me3.v["vspeed"]) - _n(a, 1) * sin(deg_to_rad(_n(a, 0)))
	vm.inst_set(me3, "hspeed", hs)
	vm.inst_set(me3, "vspeed", vs)
	return 0.0
	return 0.0


func _f_move_towards_point(name: String, a: Array, ctx: Dictionary):
	var me4 = ctx["self"]
	vm.inst_set(me4, "direction", fposmod(rad_to_deg(atan2(-(_n(a, 1) - float(me4.v["y"])), _n(a, 0) - float(me4.v["x"]))), 360.0))
	vm.inst_set(me4, "speed", _n(a, 2))
	return 0.0
	return 0.0


func _f_move_snap(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_event_user(name: String, a: Array, ctx: Dictionary):
	vm.perform_event(ctx["self"], vm.EV_OTHER, 10 + int(_n(a, 0)), ctx["other"])
	return 0.0
	return 0.0


func _f_event_perform(name: String, a: Array, ctx: Dictionary):
	vm.perform_event(ctx["self"], int(_n(a, 0)), int(_n(a, 1)), ctx["other"])
	return 0.0
	return 0.0


func _f_event_perform_object(name: String, a: Array, ctx: Dictionary):
	var found: Array = vm.find_event(int(_n(a, 0)), int(_n(a, 1)), int(_n(a, 2)))
	if not found.is_empty():
		vm._run_event(ctx["self"], found[0], found[1], int(_n(a, 1)), int(_n(a, 2)), ctx["other"])
	return 0.0
	return 0.0


func _f_event_inherited(name: String, a: Array, ctx: Dictionary):
	vm.event_inherited(ctx)
	return 0.0
	return 0.0


func _f_script_execute(name: String, a: Array, ctx: Dictionary):
	var idx := int(_n(a, 0))
	if idx >= 0 and idx < vm.script_by_index.size() and vm.script_by_index[idx] != null:
		return vm.call_script(vm.script_by_index[idx], a.slice(1), ctx)
	return 0.0
	return 0.0


func _f_script_exists(name: String, a: Array, ctx: Dictionary):
	var si2 := int(_n(a, 0))
	return 1.0 if si2 >= 0 and si2 < vm.script_by_index.size() else 0.0
	return 0.0


func _f_variable_global_exists(name: String, a: Array, ctx: Dictionary):
	return 1.0 if vm.globals.has(_s(a, 0)) else 0.0
	return 0.0


func _f_variable_instance_exists(name: String, a: Array, ctx: Dictionary):
	var vi = vm.first_of(_a(a, 0), ctx)
	return 1.0 if vi != null and vi.v.has(_s(a, 1)) else 0.0
	return 0.0


func _f_variable_global_get(name: String, a: Array, ctx: Dictionary):
	return vm.globals.get(_s(a, 0), 0.0)
	return 0.0


func _f_variable_global_set(name: String, a: Array, ctx: Dictionary):
	vm.globals[_s(a, 0)] = _a(a, 1)
	return 0.0
	return 0.0


func _f_object_get_sprite(name: String, a: Array, ctx: Dictionary):
	return float(vm.obj_sprite[int(_n(a, 0))]) if int(_n(a, 0)) >= 0 and int(_n(a, 0)) < vm.obj_sprite.size() else -1.0
	return 0.0


func _f_object_get_parent(name: String, a: Array, ctx: Dictionary):
	return float(vm.obj_parent[int(_n(a, 0))]) if int(_n(a, 0)) >= 0 and int(_n(a, 0)) < vm.obj_parent.size() else -1.0
	return 0.0


func _f_object_is_ancestor(name: String, a: Array, ctx: Dictionary):
	return 1.0 if vm.is_child_of(int(_n(a, 0)), int(_n(a, 1))) and int(_n(a, 0)) != int(_n(a, 1)) else 0.0
	return 0.0


func _f_object_get_name(name: String, a: Array, ctx: Dictionary):
	return vm.obj_names[int(_n(a, 0))] if int(_n(a, 0)) >= 0 and int(_n(a, 0)) < vm.obj_names.size() else ""
	return 0.0


func _f_object_exists(name: String, a: Array, ctx: Dictionary):
	return 1.0 if int(_n(a, 0)) >= 0 and int(_n(a, 0)) < vm.obj_names.size() else 0.0
	return 0.0


func _f_sprite_get_width(name: String, a: Array, ctx: Dictionary):
	var si3 = vm._spr(_n(a, 0))
	return float(si3[1]) if si3 != null else 0.0
	return 0.0


func _f_sprite_get_height(name: String, a: Array, ctx: Dictionary):
	var si4 = vm._spr(_n(a, 0))
	return float(si4[2]) if si4 != null else 0.0
	return 0.0


func _f_sprite_get_xoffset(name: String, a: Array, ctx: Dictionary):
	var si5 = vm._spr(_n(a, 0))
	return float(si5[3]) if si5 != null else 0.0
	return 0.0


func _f_sprite_get_yoffset(name: String, a: Array, ctx: Dictionary):
	var si6 = vm._spr(_n(a, 0))
	return float(si6[4]) if si6 != null else 0.0
	return 0.0


func _f_sprite_get_number(name: String, a: Array, ctx: Dictionary):
	var si7 = vm._spr(_n(a, 0))
	return float(si7[0]) if si7 != null else 0.0
	return 0.0


func _f_sprite_exists(name: String, a: Array, ctx: Dictionary):
	return 1.0 if vm._spr(_n(a, 0)) != null else 0.0
	return 0.0


func _f_sprite_get_name(name: String, a: Array, ctx: Dictionary):
	return vm.sprite_names[int(_n(a, 0))] if int(_n(a, 0)) >= 0 and int(_n(a, 0)) < vm.sprite_names.size() else ""
	return 0.0


func _f_background_get_width(name: String, a: Array, ctx: Dictionary):
	var t1 := bg_texture(int(_n(a, 0)))
	return float(t1.get_width()) if t1 != null else 0.0
	return 0.0


func _f_background_get_height(name: String, a: Array, ctx: Dictionary):
	var t2 := bg_texture(int(_n(a, 0)))
	return float(t2.get_height()) if t2 != null else 0.0
	return 0.0


func _f_asset_get_index(name: String, a: Array, ctx: Dictionary):
	var nm := _s(a, 0)
	return vm.consts.get(nm, -1.0) if vm.consts.has(nm) and not (vm.consts[nm] == null) else -1.0
	return 0.0


func _f_asset_get_type(name: String, a: Array, ctx: Dictionary):
	var nm2 := _s(a, 0)
	if vm.obj_index.has(nm2):
		return 0.0
	if vm.sprite_index.has(nm2):
		return 1.0
	if vm.sound_names.has(nm2):
		return 2.0
	if vm.room_names.has(nm2):
		return 3.0
	if vm.script_code.has(nm2):
		return 6.0
	if vm.font_names.has(nm2):
		return 7.0
	return -1.0
	return 0.0


func _f_room_get_name(name: String, a: Array, ctx: Dictionary):
	return vm.room_names[int(_n(a, 0))] if int(_n(a, 0)) >= 0 and int(_n(a, 0)) < vm.room_names.size() else ""
	return 0.0


func _f_draw_self(name: String, a: Array, ctx: Dictionary):
	draw_self(ctx["self"])
	return 0.0
	return 0.0


func _f_draw_sprite(name: String, a: Array, ctx: Dictionary):
	var fr := int(floorf(_n(a, 1)))
	if fr < 0 and ctx["self"] != null:
		fr = int(floorf(float(ctx["self"].v["image_index"])))
	_draw_sprite_ext(int(_n(a, 0)), fr, _n(a, 2), _n(a, 3), 1.0, 1.0, 0.0, 16777215, draw_alpha)
	return 0.0
	return 0.0


func _f_draw_sprite_ext(name: String, a: Array, ctx: Dictionary):
	var fr2 := int(floorf(_n(a, 1)))
	if fr2 < 0 and ctx["self"] != null:
		fr2 = int(floorf(float(ctx["self"].v["image_index"])))
	_draw_sprite_ext(int(_n(a, 0)), fr2, _n(a, 2), _n(a, 3), _n(a, 4, 1.0), _n(a, 5, 1.0), _n(a, 6), _a(a, 7, 16777215.0), _n(a, 8, 1.0))
	return 0.0
	return 0.0


func _f_draw_sprite_part(name: String, a: Array, ctx: Dictionary):
	_draw_sprite_part(int(_n(a, 0)), int(_n(a, 1)), _n(a, 2), _n(a, 3), _n(a, 4), _n(a, 5), _n(a, 6), _n(a, 7), 1.0, 1.0, 16777215, draw_alpha)
	return 0.0
	return 0.0


func _f_draw_sprite_part_ext(name: String, a: Array, ctx: Dictionary):
	_draw_sprite_part(int(_n(a, 0)), int(_n(a, 1)), _n(a, 2), _n(a, 3), _n(a, 4), _n(a, 5), _n(a, 6), _n(a, 7), _n(a, 8, 1.0), _n(a, 9, 1.0), _a(a, 10, 16777215.0), _n(a, 11, 1.0))
	return 0.0
	return 0.0


func _f_draw_sprite_stretched(name: String, a: Array, ctx: Dictionary):
	var t3 := texture(int(_n(a, 0)), int(_n(a, 1)))
	if canvas != null and t3 != null:
		var cc := col(16777215, draw_alpha) if name == "draw_sprite_stretched" else col(_a(a, 6, 16777215.0), _n(a, 7, 1.0))
		canvas.draw_texture_rect(t3, Rect2(_n(a, 2), _n(a, 3), _n(a, 4), _n(a, 5)), false, cc)
	return 0.0
	return 0.0


func _f_draw_sprite_tiled(name: String, a: Array, ctx: Dictionary):
	var t4 := texture(int(_n(a, 0)), int(_n(a, 1)))
	if canvas != null and t4 != null:
		var w := t4.get_width()
		var h := t4.get_height()
		var sx := fposmod(_n(a, 2), w) - w
		var sy := fposmod(_n(a, 3), h) - h
		var yy := sy
		while yy < 480:
			var xx := sx
			while xx < 640:
				canvas.draw_texture(t4, Vector2(xx, yy))
				xx += w
			yy += h
	return 0.0
	return 0.0


func _f_draw_background(name: String, a: Array, ctx: Dictionary):
	var bt := bg_texture(int(_n(a, 0)))
	if canvas != null and bt != null:
		match name:
			"draw_background":
				canvas.draw_texture(bt, Vector2(_n(a, 1), _n(a, 2)), col(16777215, draw_alpha))
			"draw_background_ext":
				canvas.draw_set_transform(Vector2(_n(a, 1), _n(a, 2)), -deg_to_rad(_n(a, 5)), Vector2(_n(a, 3, 1.0), _n(a, 4, 1.0)))
				canvas.draw_texture(bt, Vector2.ZERO, col(_a(a, 6, 16777215.0), _n(a, 7, 1.0)))
				canvas.draw_set_transform(Vector2.ZERO)
			"draw_background_stretched":
				canvas.draw_texture_rect(bt, Rect2(_n(a, 1), _n(a, 2), _n(a, 3), _n(a, 4)), false, col(16777215, draw_alpha))
			"draw_background_part":
				canvas.draw_texture_rect_region(bt, Rect2(_n(a, 5), _n(a, 6), _n(a, 3), _n(a, 4)), Rect2(_n(a, 1), _n(a, 2), _n(a, 3), _n(a, 4)), col(16777215, draw_alpha))
			"draw_background_part_ext":
				canvas.draw_texture_rect_region(bt, Rect2(_n(a, 5), _n(a, 6), _n(a, 3) * _n(a, 7, 1.0), _n(a, 4) * _n(a, 8, 1.0)), Rect2(_n(a, 1), _n(a, 2), _n(a, 3), _n(a, 4)), col(_a(a, 9, 16777215.0), _n(a, 10, 1.0)))
			"draw_background_tiled":
				canvas.draw_texture(bt, Vector2(_n(a, 1), _n(a, 2)))
	return 0.0
	return 0.0


func _f_draw_text(name: String, a: Array, ctx: Dictionary):
	_draw_text(_n(a, 0), _n(a, 1), _s(a, 2))
	return 0.0
	return 0.0


func _f_draw_text_ext(name: String, a: Array, ctx: Dictionary):
	_draw_text(_n(a, 0), _n(a, 1), _s(a, 2))
	return 0.0
	return 0.0


func _f_draw_text_transformed(name: String, a: Array, ctx: Dictionary):
	_draw_text(_n(a, 0), _n(a, 1), _s(a, 2), _n(a, 3, 1.0), _n(a, 4, 1.0), _n(a, 5))
	return 0.0
	return 0.0


func _f_draw_text_ext_transformed(name: String, a: Array, ctx: Dictionary):
	_draw_text(_n(a, 0), _n(a, 1), _s(a, 2), _n(a, 5, 1.0), _n(a, 6, 1.0), _n(a, 7))
	return 0.0
	return 0.0


func _f_draw_text_colour(name: String, a: Array, ctx: Dictionary):
	_draw_text(_n(a, 0), _n(a, 1), _s(a, 2), 1.0, 1.0, 0.0, _a(a, 3), _n(a, 7, 1.0))
	return 0.0
	return 0.0


func _f_draw_text_transformed_colour(name: String, a: Array, ctx: Dictionary):
	_draw_text(_n(a, 0), _n(a, 1), _s(a, 2), _n(a, 3, 1.0), _n(a, 4, 1.0), _n(a, 5), _a(a, 6), _n(a, 10, 1.0))
	return 0.0
	return 0.0


func _f_draw_set_color(name: String, a: Array, ctx: Dictionary):
	draw_color = int(_n(a, 0))
	return 0.0
	return 0.0


func _f_draw_get_color(name: String, a: Array, ctx: Dictionary):
	return float(draw_color)
	return 0.0


func _f_draw_set_alpha(name: String, a: Array, ctx: Dictionary):
	draw_alpha = clampf(_n(a, 0), 0.0, 1.0)
	if vm.prof != null:
		vm.prof["alpha:" + vm.obj_names[ctx["self"].obj] + "=" + str(snappedf(draw_alpha, 0.01))] = 1
	return 0.0
	return 0.0


func _f_draw_get_alpha(name: String, a: Array, ctx: Dictionary):
	return draw_alpha
	return 0.0


func _f_draw_set_font(name: String, a: Array, ctx: Dictionary):
	draw_font = int(_n(a, 0))
	return 0.0
	return 0.0


func _f_draw_get_font(name: String, a: Array, ctx: Dictionary):
	return float(draw_font)
	return 0.0


func _f_draw_set_halign(name: String, a: Array, ctx: Dictionary):
	halign = int(_n(a, 0))
	return 0.0
	return 0.0


func _f_draw_set_valign(name: String, a: Array, ctx: Dictionary):
	valign = int(_n(a, 0))
	return 0.0
	return 0.0


func _f_draw_rectangle(name: String, a: Array, ctx: Dictionary):
	_rect(_n(a, 0), _n(a, 1), _n(a, 2), _n(a, 3), _n(a, 4) > 0.5, col(draw_color, draw_alpha))
	return 0.0
	return 0.0


func _f_draw_rectangle_colour(name: String, a: Array, ctx: Dictionary):
	_rect(_n(a, 0), _n(a, 1), _n(a, 2), _n(a, 3), _n(a, 8) > 0.5, col(_a(a, 4), draw_alpha))
	return 0.0
	return 0.0


func _f_draw_line(name: String, a: Array, ctx: Dictionary):
	if canvas != null:
		var w2 := _n(a, 4, 1.0) if name.begins_with("draw_line_width") else 1.0
		var c2 := col(draw_color, draw_alpha)
		if name == "draw_line_colour" or name == "draw_line_color":
			c2 = col(_a(a, 4), draw_alpha)
		elif name.begins_with("draw_line_width_col"):
			c2 = col(_a(a, 5), draw_alpha)
		# draw_line_width: the runner fills the line's quad as if sampling each pixel at its
		# top-left corner minus half a pixel (measured with ube_draw_probe), which is Godot's
		# centre sampling with the quad moved one pixel right and down. Plain 1-pixel lines
		# were not measured and are drawn as before.
		var lo := Vector2(1.0, 1.0) if name.begins_with("draw_line_width") else Vector2.ZERO
		canvas.draw_line(Vector2(_n(a, 0), _n(a, 1)) + lo, Vector2(_n(a, 2), _n(a, 3)) + lo, c2, maxf(w2, 1.0))
	return 0.0
	return 0.0


func _f_draw_point(name: String, a: Array, ctx: Dictionary):
	if canvas != null:
		canvas.draw_rect(Rect2(_n(a, 0), _n(a, 1), 1, 1), col(draw_color, draw_alpha))
	return 0.0
	return 0.0


func _f_draw_circle(name: String, a: Array, ctx: Dictionary):
	if canvas != null:
		var c3 := col(draw_color, draw_alpha) if name == "draw_circle" else col(_a(a, 3), draw_alpha)
		var outline := _n(a, 3) > 0.5 if name == "draw_circle" else _n(a, 5) > 0.5
		if outline:
			canvas.draw_arc(Vector2(_n(a, 0), _n(a, 1)), _n(a, 2), 0, TAU, 32, c3, 1.0)
		else:
			canvas.draw_circle(Vector2(_n(a, 0), _n(a, 1)), _n(a, 2), c3)
	return 0.0
	return 0.0


func _f_draw_ellipse(name: String, a: Array, ctx: Dictionary):
	if canvas != null:
		var r2 := Rect2(Vector2(_n(a, 0), _n(a, 1)), Vector2(_n(a, 2) - _n(a, 0), _n(a, 3) - _n(a, 1)))
		canvas.draw_set_transform(r2.get_center(), 0, Vector2(r2.size.x / 2.0, r2.size.y / 2.0))
		canvas.draw_circle(Vector2.ZERO, 1.0, col(draw_color, draw_alpha))
		canvas.draw_set_transform(Vector2.ZERO)
	return 0.0
	return 0.0


func _f_draw_triangle(name: String, a: Array, ctx: Dictionary):
	if canvas != null:
		var pts := PackedVector2Array([Vector2(_n(a, 0), _n(a, 1)), Vector2(_n(a, 2), _n(a, 3)), Vector2(_n(a, 4), _n(a, 5))])
		if _n(a, 6) > 0.5:
			pts.append(pts[0])
			canvas.draw_polyline(pts, col(draw_color, draw_alpha))
		else:
			canvas.draw_colored_polygon(pts, col(draw_color, draw_alpha))
	return 0.0
	return 0.0


func _f_draw_clear(name: String, a: Array, ctx: Dictionary):
	if canvas != null:
		canvas.draw_rect(Rect2(0, 0, 640, 480), col(_a(a, 0), _n(a, 1, 1.0)))
	return 0.0
	return 0.0


func _f_draw_set_blend_mode(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_merge_color(name: String, a: Array, ctx: Dictionary):
	# Per channel, rounded: merge_color(c_red, c_maroon, 0.5) is 192 red in the runner
	# (Sans's HP bar), not 191.
	var c1 := int(_n(a, 0))
	var c2 := int(_n(a, 1))
	var t := _n(a, 2)
	var out := 0
	for sh in [0, 8, 16]:
		var v1 := float((c1 >> sh) & 255)
		var v2 := float((c2 >> sh) & 255)
		out |= clampi(int(floorf(v1 + (v2 - v1) * t + 0.5)), 0, 255) << sh
	return float(out)
	return 0.0


func _f_make_color_rgb(name: String, a: Array, ctx: Dictionary):
	return float(int(_n(a, 0)) | (int(_n(a, 1)) << 8) | (int(_n(a, 2)) << 16))
	return 0.0


func _f_make_color_hsv(name: String, a: Array, ctx: Dictionary):
	var c5 := Color.from_hsv(_n(a, 0) / 255.0, _n(a, 1) / 255.0, _n(a, 2) / 255.0)
	return float(int(c5.r * 255) | (int(c5.g * 255) << 8) | (int(c5.b * 255) << 16))
	return 0.0


func _f_colour_get_red(name: String, a: Array, ctx: Dictionary):
	return float(int(_n(a, 0)) & 255)
	return 0.0


func _f_colour_get_green(name: String, a: Array, ctx: Dictionary):
	return float((int(_n(a, 0)) >> 8) & 255)
	return 0.0


func _f_colour_get_blue(name: String, a: Array, ctx: Dictionary):
	return float((int(_n(a, 0)) >> 16) & 255)
	return 0.0


func _f_draw_primitive_begin(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_surface_exists(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_surface_create(name: String, a: Array, ctx: Dictionary):
	return -1.0
	return 0.0


func _f_surface_set_target(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_surface_get_width(name: String, a: Array, ctx: Dictionary):
	return 640.0
	return 0.0


func _f_surface_get_height(name: String, a: Array, ctx: Dictionary):
	return 480.0
	return 0.0


func _f_application_surface_enable(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_sprite_create_from_surface(name: String, a: Array, ctx: Dictionary):
	return -1.0
	return 0.0


func _f_audio_play_sound(name: String, a: Array, ctx: Dictionary):
	return play_sound(int(_n(a, 0)), _n(a, 2) > 0.5)
	return 0.0


func _f_audio_stop_sound(name: String, a: Array, ctx: Dictionary):
	for p in _players_for(_a(a, 0)):
		p["player"].stop()
		p["paused"] = false
		p["stopped"] = true
	return 0.0
	return 0.0


func _f_audio_stop_all(name: String, a: Array, ctx: Dictionary):
	for p in players:
		p["player"].stop()
		p["paused"] = false
		p["stopped"] = true
	return 0.0
	return 0.0


func _f_audio_is_playing(name: String, a: Array, ctx: Dictionary):
	_cleanup_players()
	for p in _players_for(_a(a, 0)):
		if (_alive(p) and not p["paused"]) if det_audio else p["player"].playing:
			return 1.0
	return 0.0
	return 0.0


func _f_audio_is_paused(name: String, a: Array, ctx: Dictionary):
	for p in _players_for(_a(a, 0)):
		if p["paused"]:
			return 1.0
	return 0.0
	return 0.0


func _f_audio_sound_gain(name: String, a: Array, ctx: Dictionary):
	_set_gain(_a(a, 0), maxf(_n(a, 1), 0.0), _n(a, 2))
	return 0.0
	return 0.0


func _f_audio_sound_pitch(name: String, a: Array, ctx: Dictionary):
	var tp := int(_n(a, 0))
	if tp < 100000:
		asset_pitch[tp] = maxf(_n(a, 1), 0.01)
	for p in _players_for(tp):
		p["player"].pitch_scale = maxf(_n(a, 1), 0.01)
	return 0.0
	return 0.0


func _f_audio_sound_get_gain(name: String, a: Array, ctx: Dictionary):
	var tg := int(_n(a, 0))
	if tg < 100000:
		return float(asset_gain.get(tg, 1.0))
	for p in _players_for(tg):
		return float(p.get("gain", 1.0))
	return 1.0
	return 0.0


func _f_audio_sound_get_pitch(name: String, a: Array, ctx: Dictionary):
	for p in _players_for(_a(a, 0)):
		return p["player"].pitch_scale
	return 1.0
	return 0.0


func _f_audio_pause_sound(name: String, a: Array, ctx: Dictionary):
	for p in _players_for(_a(a, 0)):
		p["player"].stream_paused = true
		if not p["paused"]:
			p["pa"] = vm.step_no
		p["paused"] = true
	return 0.0
	return 0.0


func _f_audio_resume_sound(name: String, a: Array, ctx: Dictionary):
	for p in _players_for(_a(a, 0)):
		p["player"].stream_paused = false
		if p["paused"] and int(p.get("pa", -1)) >= 0:
			p["pt"] = int(p.get("pt", 0)) + vm.step_no - int(p["pa"])
			p["pa"] = -1
		p["paused"] = false
	return 0.0
	return 0.0


func _f_audio_pause_all(name: String, a: Array, ctx: Dictionary):
	for p in players:
		p["player"].stream_paused = true
		if not p["paused"]:
			p["pa"] = vm.step_no
		p["paused"] = true
	return 0.0
	return 0.0


func _f_audio_resume_all(name: String, a: Array, ctx: Dictionary):
	for p in players:
		p["player"].stream_paused = false
		if p["paused"] and int(p.get("pa", -1)) >= 0:
			p["pt"] = int(p.get("pt", 0)) + vm.step_no - int(p["pa"])
			p["pa"] = -1
		p["paused"] = false
	return 0.0
	return 0.0


func _f_audio_sound_get_track_position(name: String, a: Array, ctx: Dictionary):
	for p in _players_for(_a(a, 0)):
		if det_audio:
			var el: int = (int(p["pa"]) if p["paused"] and int(p.get("pa", -1)) >= 0 else vm.step_no) - int(p.get("t0", 0)) - int(p.get("pt", 0))
			var ln: float = p["player"].stream.get_length() if p["player"].stream != null else 0.0
			var t: float = el / 30.0 * p["player"].pitch_scale
			return fmod(t, ln) if p.get("loop", false) and ln > 0.0 else minf(t, ln)
		return p["player"].get_playback_position()
	return 0.0
	return 0.0


func _f_audio_sound_set_track_position(name: String, a: Array, ctx: Dictionary):
	for p in _players_for(_a(a, 0)):
		p["player"].seek(_n(a, 1))
	return 0.0
	return 0.0


func _f_audio_channel_num(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_audio_exists(name: String, a: Array, ctx: Dictionary):
	return 1.0
	return 0.0


func _f_audio_group_is_loaded(name: String, a: Array, ctx: Dictionary):
	return 1.0
	return 0.0


func _f_keyboard_check(name: String, a: Array, ctx: Dictionary):
	return 1.0 if keys != null and keys.held(int(_n(a, 0))) else 0.0
	return 0.0


func _f_keyboard_check_direct(name: String, a: Array, ctx: Dictionary):
	return 1.0 if keys != null and keys.held(int(_n(a, 0))) else 0.0
	return 0.0


func _f_keyboard_check_pressed(name: String, a: Array, ctx: Dictionary):
	return 1.0 if keys != null and keys.pressed(int(_n(a, 0))) else 0.0
	return 0.0


func _f_keyboard_check_released(name: String, a: Array, ctx: Dictionary):
	return 1.0 if keys != null and keys.released(int(_n(a, 0))) else 0.0
	return 0.0


func _f_keyboard_key_press(name: String, a: Array, ctx: Dictionary):
	if keys != null:
		keys.sim_press(int(_n(a, 0)))
	return 0.0
	return 0.0


func _f_keyboard_key_release(name: String, a: Array, ctx: Dictionary):
	if keys != null:
		keys.sim_release(int(_n(a, 0)))
	return 0.0
	return 0.0


func _f_keyboard_clear(name: String, a: Array, ctx: Dictionary):
	if keys != null:
		keys.clear(int(_n(a, 0)) if not a.is_empty() else -1)
	return 0.0
	return 0.0


func _f_keyboard_set_map(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_mouse_check_button(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_joystick_exists(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_joystick_direction(name: String, a: Array, ctx: Dictionary):
	return 101.0
	return 0.0


func _f_ds_map_create(name: String, a: Array, ctx: Dictionary):
	var id := next_ds
	next_ds += 1
	maps[id] = {}
	return float(id)
	return 0.0


func _f_ds_map_add(name: String, a: Array, ctx: Dictionary):
	var m = maps.get(int(_n(a, 0)))
	if m != null:
		if name == "ds_map_add" and m.has(_a(a, 1)):
			return 0.0
		m[_a(a, 1)] = _a(a, 2)
	return 0.0
	return 0.0


func _f_ds_map_find_value(name: String, a: Array, ctx: Dictionary):
	var m2 = maps.get(int(_n(a, 0)))
	if m2 == null:
		return null
	return m2.get(_a(a, 1), null)
	return 0.0


func _f_ds_map_exists(name: String, a: Array, ctx: Dictionary):
	var m3 = maps.get(int(_n(a, 0)))
	return 1.0 if m3 != null and m3.has(_a(a, 1)) else 0.0
	return 0.0


func _f_ds_map_delete(name: String, a: Array, ctx: Dictionary):
	var m4 = maps.get(int(_n(a, 0)))
	if m4 != null:
		m4.erase(_a(a, 1))
	return 0.0
	return 0.0


func _f_ds_map_size(name: String, a: Array, ctx: Dictionary):
	var m5 = maps.get(int(_n(a, 0)))
	return float(m5.size()) if m5 != null else 0.0
	return 0.0


func _f_ds_map_destroy(name: String, a: Array, ctx: Dictionary):
	maps.erase(int(_n(a, 0)))
	return 0.0
	return 0.0


func _f_ds_map_clear(name: String, a: Array, ctx: Dictionary):
	if maps.has(int(_n(a, 0))):
		maps[int(_n(a, 0))] = {}
	return 0.0
	return 0.0


func _f_ds_map_find_first(name: String, a: Array, ctx: Dictionary):
	var m6 = maps.get(int(_n(a, 0)))
	return m6.keys()[0] if m6 != null and m6.size() > 0 else null
	return 0.0


func _f_ds_exists(name: String, a: Array, ctx: Dictionary):
	return 1.0 if maps.has(int(_n(a, 0))) or lists.has(int(_n(a, 0))) else 0.0
	return 0.0


func _f_ds_list_create(name: String, a: Array, ctx: Dictionary):
	var lid := next_ds
	next_ds += 1
	lists[lid] = []
	return float(lid)
	return 0.0


func _f_ds_list_add(name: String, a: Array, ctx: Dictionary):
	var l = lists.get(int(_n(a, 0)))
	if l != null:
		for k in range(1, a.size()):
			l.append(a[k])
	return 0.0
	return 0.0


func _f_ds_list_find_value(name: String, a: Array, ctx: Dictionary):
	var l2 = lists.get(int(_n(a, 0)))
	var k2 := int(_n(a, 1))
	return l2[k2] if l2 != null and k2 >= 0 and k2 < l2.size() else null
	return 0.0


func _f_ds_list_size(name: String, a: Array, ctx: Dictionary):
	var l3 = lists.get(int(_n(a, 0)))
	return float(l3.size()) if l3 != null else 0.0
	return 0.0


func _f_ds_list_destroy(name: String, a: Array, ctx: Dictionary):
	lists.erase(int(_n(a, 0)))
	return 0.0
	return 0.0


func _f_ds_list_clear(name: String, a: Array, ctx: Dictionary):
	if lists.has(int(_n(a, 0))):
		lists[int(_n(a, 0))] = []
	return 0.0
	return 0.0


func _f_ds_list_delete(name: String, a: Array, ctx: Dictionary):
	var l4 = lists.get(int(_n(a, 0)))
	var k4 := int(_n(a, 1))
	if l4 != null and k4 >= 0 and k4 < l4.size():
		l4.remove_at(k4)
	return 0.0
	return 0.0


func _f_ds_list_insert(name: String, a: Array, ctx: Dictionary):
	var l5 = lists.get(int(_n(a, 0)))
	if l5 != null:
		l5.insert(clampi(int(_n(a, 1)), 0, l5.size()), _a(a, 2))
	return 0.0
	return 0.0


func _f_ds_list_replace(name: String, a: Array, ctx: Dictionary):
	var l6 = lists.get(int(_n(a, 0)))
	var k6 := int(_n(a, 1))
	if l6 != null and k6 >= 0:
		while l6.size() <= k6:
			l6.append(0.0)
		l6[k6] = _a(a, 2)
	return 0.0
	return 0.0


func _f_ds_list_find_index(name: String, a: Array, ctx: Dictionary):
	var l7 = lists.get(int(_n(a, 0)))
	return float(l7.find(_a(a, 1))) if l7 != null else -1.0
	return 0.0


func _f_ds_list_shuffle(name: String, a: Array, ctx: Dictionary):
	var l8 = lists.get(int(_n(a, 0)))
	if l8 != null:
		l8.shuffle()
	return 0.0
	return 0.0


func _f_ds_list_empty(name: String, a: Array, ctx: Dictionary):
	var l9 = lists.get(int(_n(a, 0)))
	return 1.0 if l9 == null or l9.is_empty() else 0.0
	return 0.0


func _f_room_goto(name: String, a: Array, ctx: Dictionary):
	vm.pending_room = int(_n(a, 0))
	return 0.0
	return 0.0


func _f_room_goto_next(name: String, a: Array, ctx: Dictionary):
	vm.pending_room = vm.room + 1
	return 0.0
	return 0.0


func _f_room_goto_previous(name: String, a: Array, ctx: Dictionary):
	vm.pending_room = vm.room - 1
	return 0.0
	return 0.0


func _f_room_restart(name: String, a: Array, ctx: Dictionary):
	vm.pending_room = vm.room
	return 0.0
	return 0.0


func _f_game_end(name: String, a: Array, ctx: Dictionary):
	vm.game_end_requested = true
	return 0.0
	return 0.0


func _f_game_restart(name: String, a: Array, ctx: Dictionary):
	# The host starts the game again from its first room (battles: same as game_end).
	vm.game_end_requested = true
	vm.game_restart_requested = true
	return 0.0


func _f_room_set_persistent(name: String, a: Array, ctx: Dictionary):
	return 1.0
	return 0.0


func _f_steam_initialised(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_os_get_language(name: String, a: Array, ctx: Dictionary):
	return "en"
	return 0.0


func _f_os_get_region(name: String, a: Array, ctx: Dictionary):
	return "US"
	return 0.0


func _f_os_is_paused(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_window_set_caption(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_window_get_fullscreen(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_window_get_width(name: String, a: Array, ctx: Dictionary):
	return 640.0
	return 0.0


func _f_window_get_height(name: String, a: Array, ctx: Dictionary):
	return 480.0
	return 0.0


func _f_display_get_width(name: String, a: Array, ctx: Dictionary):
	return 1920.0
	return 0.0


func _f_display_get_height(name: String, a: Array, ctx: Dictionary):
	return 1080.0
	return 0.0


func _f_get_timer(name: String, a: Array, ctx: Dictionary):
	return floorf(clock_ms * 1000.0) if clock_ms >= 0.0 else float(Time.get_ticks_usec())
	return 0.0


func _f_date_current_datetime(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_show_debug_message(name: String, a: Array, ctx: Dictionary):
	vm.vlog("DEBUG " + _s(a, 0))
	return 0.0
	return 0.0


func _f_show_message(name: String, a: Array, ctx: Dictionary):
	vm.vlog("MESSAGE " + _s(a, 0))
	return 0.0
	return 0.0


func _f_get_integer(name: String, a: Array, ctx: Dictionary):
	return _a(a, 1, 0.0)
	return 0.0


func _f_buffer_create(name: String, a: Array, ctx: Dictionary):
	return -1.0
	return 0.0


func _f_json_encode(name: String, a: Array, ctx: Dictionary):
	return "{}"
	return 0.0


func _f_json_decode(name: String, a: Array, ctx: Dictionary):
	return -1.0
	return 0.0


func _f_font_add_sprite(name: String, a: Array, ctx: Dictionary):
	return -1.0
	return 0.0


func _f_gc_collect(name: String, a: Array, ctx: Dictionary):
	return 0.0
	return 0.0


func _f_parameter_string(name: String, a: Array, ctx: Dictionary):
	return ""
	return 0.0


func _f_code_is_compiled(name: String, a: Array, ctx: Dictionary):
	return 1.0
	return 0.0


func _f_strlen(name: String, a: Array, ctx: Dictionary):
	return float(_s(a, 0).length())
	return 0.0



# ---------------------------------------------------------------- rooms: views, backgrounds, tiles
# Room state the overworld needs (battles only used view 0's position). vm.load_room fills
# it from the room's data; the arrays are GameMaker's 8 views and 8 background layers.

const VIEW_KEYS := ["view_visible", "view_xview", "view_yview", "view_wview", "view_hview",
	"view_xport", "view_yport", "view_wport", "view_hport", "view_hborder", "view_vborder",
	"view_hspeed", "view_vspeed", "view_object", "view_angle"]
const BG_KEYS := ["background_visible", "background_foreground", "background_index",
	"background_x", "background_y", "background_htiled", "background_vtiled",
	"background_hspeed", "background_vspeed", "background_xscale", "background_yscale",
	"background_blend", "background_alpha"]

var room_arr := {}          # name -> Array of 8 (views and backgrounds)
var views_on := false
var show_colour := true
# Tiles: [id, background, x, y, left, top, width, height, depth, xscale, yscale, colour,
# alpha, visible], kept sorted deepest first.
var tiles: Array = []
var tiles_sorted := true
var room_persist := {}     # room index -> room_persistent set at run time
var next_tile_id := 10000000


func room_state_reset() -> void:
	for k in VIEW_KEYS + BG_KEYS:
		var a: Array = []
		a.resize(8)
		a.fill(0.0)
		room_arr[k] = a
	for v in 8:
		room_arr["view_wview"][v] = 640.0
		room_arr["view_hview"][v] = 480.0
		room_arr["view_wport"][v] = 640.0
		room_arr["view_hport"][v] = 480.0
		room_arr["view_object"][v] = -4.0
		room_arr["view_hspeed"][v] = -1.0
		room_arr["view_vspeed"][v] = -1.0
		room_arr["background_index"][v] = -1.0
		room_arr["background_xscale"][v] = 1.0
		room_arr["background_yscale"][v] = 1.0
		room_arr["background_blend"][v] = 16777215.0
		room_arr["background_alpha"][v] = 1.0
	# The battle code and the host read these directly.
	view_xview = room_arr["view_xview"]
	view_yview = room_arr["view_yview"]
	view_wview = room_arr["view_wview"]
	view_hview = room_arr["view_hview"]
	views_on = false
	show_colour = true
	tiles = []
	tiles_sorted = true


# Called by vm.load_room with the room's extracted data (see extract_engine.csx).
func room_state_load(rd: Dictionary) -> void:
	room_state_reset()
	views_on = int(rd.get("views_enabled", 0)) == 1
	show_colour = int(rd.get("show_colour", 1)) == 1
	background_color = float(int(rd.get("colour", 0)) & 0xFFFFFF)
	var vs: Array = rd.get("views", [])
	for k in mini(vs.size(), 8):
		var v: Array = vs[k]
		room_arr["view_visible"][k] = float(v[0])
		room_arr["view_xview"][k] = float(v[1])
		room_arr["view_yview"][k] = float(v[2])
		room_arr["view_wview"][k] = float(v[3])
		room_arr["view_hview"][k] = float(v[4])
		room_arr["view_xport"][k] = float(v[5])
		room_arr["view_yport"][k] = float(v[6])
		room_arr["view_wport"][k] = float(v[7])
		room_arr["view_hport"][k] = float(v[8])
		room_arr["view_hborder"][k] = float(v[9])
		room_arr["view_vborder"][k] = float(v[10])
		room_arr["view_hspeed"][k] = float(v[11])
		room_arr["view_vspeed"][k] = float(v[12])
		room_arr["view_object"][k] = float(vm.obj_index.get(v[13], -4)) if v[13] != null else -4.0
	var bs: Array = rd.get("backgrounds", [])
	for k in mini(bs.size(), 8):
		var b: Array = bs[k]
		room_arr["background_visible"][k] = float(b[0])
		room_arr["background_foreground"][k] = float(b[1])
		room_arr["background_index"][k] = float(vm.consts.get(b[2], -1.0)) if b[2] != null else -1.0
		room_arr["background_x"][k] = float(b[3])
		room_arr["background_y"][k] = float(b[4])
		room_arr["background_htiled"][k] = float(b[5])
		room_arr["background_vtiled"][k] = float(b[6])
		room_arr["background_hspeed"][k] = float(b[7])
		room_arr["background_vspeed"][k] = float(b[8])
		if int(b[9]) == 1:
			# Stretched: scaled to fill the room.
			var bgi := int(room_arr["background_index"][k])
			var tex := bg_texture(bgi)
			if tex != null:
				room_arr["background_xscale"][k] = float(vm.room_width) / tex.get_width()
				room_arr["background_yscale"][k] = float(vm.room_height) / tex.get_height()
	for t in rd.get("tiles", []):
		var bgi2 := int(vm.consts.get(t[0], -1.0)) if t[0] != null else -1
		var c := int(t[11])
		tiles.append([int(t[8]), bgi2, float(t[1]), float(t[2]), float(t[3]), float(t[4]), float(t[5]), float(t[6]), float(t[7]), float(t[9]), float(t[10]), float(c & 0xFFFFFF), float((c >> 24) & 255) / 255.0, true])
	tiles_sorted = false


func sorted_tiles() -> Array:
	if not tiles_sorted:
		# Deepest first; equal depths keep their room order.
		var idx: Array = []
		for k in tiles.size():
			idx.append([tiles[k][8], k])
		idx.sort_custom(func(p, q): return p[0] > q[0] or (p[0] == q[0] and p[1] < q[1]))
		var out: Array = []
		for p in idx:
			out.append(tiles[p[1]])
		tiles = out
		tiles_sorted = true
	return tiles


func draw_tile(t: Array) -> void:
	if not t[13] or canvas == null:
		return
	var tex := bg_texture(int(t[1]))
	if tex == null:
		return
	var dst := Rect2(t[2], t[3], t[6] * t[9], t[7] * t[10])
	canvas.draw_texture_rect_region(tex, dst, Rect2(t[4], t[5], t[6], t[7]), col(t[11], t[12]))


# Background colour and the background layers (fg = false: behind everything; true: in front).
func draw_backgrounds(fg: bool) -> void:
	if canvas == null:
		return
	if not fg and show_colour:
		var vx: float = room_arr["view_xview"][0] if views_on else 0.0
		var vy: float = room_arr["view_yview"][0] if views_on else 0.0
		var vw: float = room_arr["view_wview"][0] if views_on else float(vm.room_width)
		var vh: float = room_arr["view_hview"][0] if views_on else float(vm.room_height)
		if vm.owners_on:
			# Every player's camera is somewhere in the room, not only this one's.
			canvas.draw_rect(Rect2(-vw, -vh, vm.room_width + 2.0 * vw, vm.room_height + 2.0 * vh), col(background_color))
		else:
			canvas.draw_rect(Rect2(vx, vy, maxf(vw, vm.room_width), maxf(vh, vm.room_height)), col(background_color))
	for k in 8:
		if float(room_arr["background_visible"][k]) < 0.5 or (float(room_arr["background_foreground"][k]) >= 0.5) != fg:
			continue
		var tex := bg_texture(int(room_arr["background_index"][k]))
		if tex == null:
			continue
		var x: float = room_arr["background_x"][k]
		var y: float = room_arr["background_y"][k]
		var w: float = tex.get_width() * float(room_arr["background_xscale"][k])
		var h: float = tex.get_height() * float(room_arr["background_yscale"][k])
		var c := col(room_arr["background_blend"][k], float(room_arr["background_alpha"][k]))
		var ht := float(room_arr["background_htiled"][k]) >= 0.5
		var vt := float(room_arr["background_vtiled"][k]) >= 0.5
		var x0 := x
		var x1 := x + w
		var y0 := y
		var y1 := y + h
		if ht and w > 0:
			x0 = x - ceilf(x / w) * w
			x1 = float(vm.room_width) + w
		if vt and h > 0:
			y0 = y - ceilf(y / h) * h
			y1 = float(vm.room_height) + h
		var yy := y0
		while yy < y1:
			var xx := x0
			while xx < x1:
				canvas.draw_texture_rect(tex, Rect2(xx, yy, w, h), false, c)
				xx += w
			yy += h


# Backgrounds scroll by their speeds once a step.
func step_backgrounds() -> void:
	for k in 8:
		var hs: float = room_arr["background_hspeed"][k]
		var vs: float = room_arr["background_vspeed"][k]
		if hs != 0.0:
			room_arr["background_x"][k] = float(room_arr["background_x"][k]) + hs
		if vs != 0.0:
			room_arr["background_y"][k] = float(room_arr["background_y"][k]) + vs


# Views that follow an object (GameMaker 1.4's rule): keep the instance at least hborder /
# vborder from the view's edges, moving at most hspeed / vspeed (-1: no limit), and stay
# inside the room.
func update_views() -> void:
	if not views_on:
		return
	for k in 8:
		if float(room_arr["view_visible"][k]) < 0.5:
			continue
		var target := float(room_arr["view_object"][k])
		if target < 0.0:
			continue
		var inst = vm.first_of(target, {"self": null, "other": null})
		if inst == null:
			continue
		var ix := float(inst.v["x"])
		var iy := float(inst.v["y"])
		var vx: float = room_arr["view_xview"][k]
		var vy: float = room_arr["view_yview"][k]
		var vw: float = room_arr["view_wview"][k]
		var vh: float = room_arr["view_hview"][k]
		var hb: float = room_arr["view_hborder"][k]
		var vb: float = room_arr["view_vborder"][k]
		var nx := vx
		var ny := vy
		if 2.0 * hb >= vw:
			nx = ix - vw / 2.0
		elif ix - hb < vx:
			nx = ix - hb
		elif ix + hb > vx + vw:
			nx = ix + hb - vw
		if 2.0 * vb >= vh:
			ny = iy - vh / 2.0
		elif iy - vb < vy:
			ny = iy - vb
		elif iy + vb > vy + vh:
			ny = iy + vb - vh
		var hs: float = room_arr["view_hspeed"][k]
		var vsp: float = room_arr["view_vspeed"][k]
		if hs >= 0.0:
			nx = clampf(nx, vx - hs, vx + hs)
		if vsp >= 0.0:
			ny = clampf(ny, vy - vsp, vy + vsp)
		nx = clampf(nx, 0.0, maxf(0.0, vm.room_width - vw))
		ny = clampf(ny, 0.0, maxf(0.0, vm.room_height - vh))
		room_arr["view_xview"][k] = nx
		room_arr["view_yview"][k] = ny


func _f_tile_layer_shift(name: String, a: Array, ctx: Dictionary):
	var d := _n(a, 0)
	for t in tiles:
		if t[8] == d:
			t[2] += _n(a, 1)
			t[3] += _n(a, 2)
	return 0.0


func _f_tile_layer_hide(name: String, a: Array, ctx: Dictionary):
	var d := _n(a, 0)
	var show := name == "tile_layer_show"
	for t in tiles:
		if t[8] == d:
			t[13] = show
	return 0.0


func _f_tile_layer_delete(name: String, a: Array, ctx: Dictionary):
	var d := _n(a, 0)
	tiles = tiles.filter(func(t): return t[8] != d)
	return 0.0


func _f_tile_add(name: String, a: Array, ctx: Dictionary):
	next_tile_id += 1
	tiles.append([next_tile_id, int(_n(a, 0)), _n(a, 5), _n(a, 6), _n(a, 1), _n(a, 2), _n(a, 3), _n(a, 4), _n(a, 7), 1.0, 1.0, 16777215.0, 1.0, true])
	tiles_sorted = false
	return float(next_tile_id)


func _f_tile_delete(name: String, a: Array, ctx: Dictionary):
	var id := int(_n(a, 0))
	tiles = tiles.filter(func(t): return t[0] != id)
	return 0.0


func _f_tile_exists(name: String, a: Array, ctx: Dictionary):
	var id := int(_n(a, 0))
	for t in tiles:
		if t[0] == id:
			return 1.0
	return 0.0


func _f_room_next(name: String, a: Array, ctx: Dictionary):
	var order: Array = vm.meta.get("room_order", [])
	var r := int(_n(a, 0))
	var nm: String = vm.room_names[r] if r >= 0 and r < vm.room_names.size() else ""
	var k := order.find(nm)
	if k < 0:
		return -1.0
	k += 1 if name == "room_next" else -1
	if k < 0 or k >= order.size():
		return -1.0
	return float(vm.room_names.find(order[k]))


func _f_window_get_zero(name: String, a: Array, ctx: Dictionary):
	return 0.0


# ---------------------------------------------------------------- the game's save files
# Undertale's own files (file0, file9, undertale.ini, config.ini...) live in the engine's
# data folder, never in %LOCALAPPDATA%\UNDERTALE: only the file name is kept, any folder in
# it is dropped, so nothing can be written anywhere else. save_dir == "" (battles) keeps
# the old behaviour: no file exists and nothing is written, so battles never depend on saves.

var save_dir := ""
var on_save_read := Callable()      # called with the path of each save file read to the end (co-op)
var on_save_written := Callable()   # called with the path of each save file written (debug mark)
var ini_path := ""
var ini_data := {}          # section -> {key -> value string}, insertion ordered
var ini_dirty := false
var text_files := {}        # id -> {"path", "write": bool, "lines": PackedStringArray, "line", "col", "out"}
var next_file_id := 0


func save_path(fname: String) -> String:
	if save_dir == "":
		return ""
	var base := fname.replace("\\", "/").get_file()
	if base == "" or base == "." or base == "..":
		return ""
	DirAccess.make_dir_recursive_absolute(save_dir)
	return save_dir.path_join(base)


func _ini_parse(txt: String) -> Dictionary:
	var out := {}
	var sec := ""
	for raw in txt.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			sec = line.substr(1, line.length() - 2)
			if not out.has(sec):
				out[sec] = {}
			continue
		var eq := line.find("=")
		if eq < 0:
			continue
		var key := line.substr(0, eq).strip_edges()
		var val := line.substr(eq + 1).strip_edges()
		if val.length() >= 2 and val.begins_with("\"") and val.ends_with("\""):
			val = val.substr(1, val.length() - 2)
		if not out.has(sec):
			out[sec] = {}
		out[sec][key] = val
	return out


func _ini_text() -> String:
	var s := ""
	for sec in ini_data:
		s += "[%s]\r\n" % sec
		for key in ini_data[sec]:
			s += "%s=\"%s\"\r\n" % [key, ini_data[sec][key]]
	return s


# GameMaker writes reals into ini files with six decimals.
static func _ini_real(v: float) -> String:
	return "%.6f" % v


func _ini_flush() -> void:
	if ini_dirty and ini_path != "":
		var f := FileAccess.open(ini_path, FileAccess.WRITE)
		if f != null:
			f.store_string(_ini_text())
			f.close()
			if on_save_written.is_valid():
				on_save_written.call(ini_path)
	ini_dirty = false


func _f_ini_open2(name: String, a: Array, ctx: Dictionary):
	if save_dir == "":
		# Battles: no saves, every read answers its default (as before).
		match name:
			"ini_read_real":
				return _n(a, 2)
			"ini_read_string":
				return _a(a, 2, "")
		return 0.0
	match name:
		"ini_open":
			_ini_flush()
			ini_path = save_path(_s(a, 0))
			ini_data = {}
			if ini_path != "" and FileAccess.file_exists(ini_path):
				ini_data = _ini_parse(FileAccess.get_file_as_string(ini_path))
			return 0.0
		"ini_open_from_string":
			_ini_flush()
			ini_path = ""
			ini_data = _ini_parse(_s(a, 0))
			return 0.0
		"ini_close":
			var txt := _ini_text()
			_ini_flush()
			ini_path = ""
			ini_data = {}
			return txt
		"ini_write_real", "ini_write_string":
			var sec := _s(a, 0)
			if not ini_data.has(sec):
				ini_data[sec] = {}
			ini_data[sec][_s(a, 1)] = _ini_real(_n(a, 2)) if name == "ini_write_real" else _s(a, 2)
			ini_dirty = true
			return 0.0
		"ini_read_real":
			var v = ini_data.get(_s(a, 0), {}).get(_s(a, 1))
			if v == null or not String(v).strip_edges().is_valid_float():
				return _n(a, 2)
			return float(String(v).strip_edges())
		"ini_read_string":
			var v2 = ini_data.get(_s(a, 0), {}).get(_s(a, 1))
			return String(v2) if v2 != null else _a(a, 2, "")
		"ini_section_exists":
			return 1.0 if ini_data.has(_s(a, 0)) else 0.0
		"ini_key_exists":
			return 1.0 if ini_data.get(_s(a, 0), {}).has(_s(a, 1)) else 0.0
		"ini_section_delete":
			if ini_data.erase(_s(a, 0)):
				ini_dirty = true
			return 0.0
		"ini_key_delete":
			var sd: Dictionary = ini_data.get(_s(a, 0), {})
			if sd.erase(_s(a, 1)):
				ini_dirty = true
			return 0.0
	return 0.0


func _tf(a: Array) -> Dictionary:
	return text_files.get(int(_n(a, 0)), {})


func _f_file2(name: String, a: Array, ctx: Dictionary):
	if save_dir == "":
		return "" if name == "file_text_read_string" else 0.0
	match name:
		"file_exists":
			var p := save_path(_s(a, 0))
			return 1.0 if p != "" and FileAccess.file_exists(p) else 0.0
		"file_delete":
			var p2 := save_path(_s(a, 0))
			if p2 != "" and FileAccess.file_exists(p2):
				DirAccess.remove_absolute(p2)
			return 0.0
		"file_copy", "file_rename":
			var src := save_path(_s(a, 0))
			var dst := save_path(_s(a, 1))
			if src == "" or dst == "" or not FileAccess.file_exists(src):
				return 0.0
			if name == "file_copy":
				DirAccess.copy_absolute(src, dst)
			else:
				DirAccess.rename_absolute(src, dst)
			return 1.0
		"directory_exists":
			return 1.0 if save_dir != "" else 0.0
		"directory_create":
			return 0.0
		"file_text_open_read":
			var p3 := save_path(_s(a, 0))
			if p3 == "" or not FileAccess.file_exists(p3):
				return -1.0
			next_file_id += 1
			var txt := FileAccess.get_file_as_string(p3).replace("\r\n", "\n").replace("\r", "\n")
			text_files[next_file_id] = {"path": p3, "write": false, "lines": txt.split("\n"), "line": 0, "col": 0}
			return float(next_file_id)
		"file_text_open_write", "file_text_open_append":
			var p4 := save_path(_s(a, 0))
			if p4 == "":
				return -1.0
			next_file_id += 1
			var out := ""
			if name == "file_text_open_append" and FileAccess.file_exists(p4):
				out = FileAccess.get_file_as_string(p4)
			text_files[next_file_id] = {"path": p4, "write": true, "out": out}
			return float(next_file_id)
		"file_text_close":
			var id := int(_n(a, 0))
			var tf: Dictionary = text_files.get(id, {})
			if tf.get("write", false):
				var f := FileAccess.open(tf["path"], FileAccess.WRITE)
				if f != null:
					f.store_string(tf["out"])
					f.close()
					if on_save_written.is_valid():
						on_save_written.call(tf["path"])
			elif not tf.is_empty() and on_save_read.is_valid():
				on_save_read.call(tf["path"])
			text_files.erase(id)
			return 0.0
		"file_text_write_string":
			var tw := _tf(a)
			if tw.get("write", false):
				tw["out"] += _s(a, 1)
			return 0.0
		"file_text_write_real":
			var tw2 := _tf(a)
			if tw2.get("write", false):
				var rv := _n(a, 1)
				tw2["out"] += str(int(rv)) if rv == floorf(rv) and absf(rv) < 1e15 else String.num(rv)
			return 0.0
		"file_text_writeln":
			var tw3 := _tf(a)
			if tw3.get("write", false):
				tw3["out"] += "\r\n"
			return 0.0
		"file_text_readln":
			var tr := _tf(a)
			if tr.is_empty() or tr["write"]:
				return ""
			var lines: PackedStringArray = tr["lines"]
			var rest := lines[tr["line"]].substr(tr["col"]) if tr["line"] < lines.size() else ""
			tr["line"] += 1
			tr["col"] = 0
			return rest
		"file_text_eof":
			var te := _tf(a)
			if te.is_empty() or te["write"]:
				return 1.0
			var ls: PackedStringArray = te["lines"]
			# The text ends with a newline, which leaves one empty last "line".
			var last := ls.size() - 1 if ls.size() > 0 and ls[ls.size() - 1] == "" else ls.size()
			return 1.0 if te["line"] >= last else 0.0
		"file_text_read_string":
			var rs := _tf(a)
			if rs.is_empty() or rs["write"] or rs["line"] >= (rs["lines"] as PackedStringArray).size():
				return ""
			var s: String = rs["lines"][rs["line"]].substr(rs["col"])
			rs["col"] = (rs["lines"][rs["line"]] as String).length()
			return s
		"file_text_read_real":
			var rr := _tf(a)
			if rr.is_empty() or rr["write"] or rr["line"] >= (rr["lines"] as PackedStringArray).size():
				return 0.0
			var line: String = rr["lines"][rr["line"]]
			var c: int = rr["col"]
			while c < line.length() and line[c] == " ":
				c += 1
			var e := c
			while e < line.length() and "0123456789.-+eE".contains(line[e]):
				e += 1
			rr["col"] = e
			var num := line.substr(c, e - c)
			return float(num) if num.is_valid_float() else 0.0
	return 0.0


# Persistent rooms keep their views, layers and tiles too.
func room_state_save() -> Dictionary:
	var arr := {}
	for k in room_arr:
		arr[k] = (room_arr[k] as Array).duplicate()
	return {"arr": arr, "views_on": views_on, "show_colour": show_colour, "colour": background_color, "tiles": tiles.duplicate(true)}


func room_state_restore(s: Dictionary) -> void:
	room_arr = s["arr"]
	view_xview = room_arr["view_xview"]
	view_yview = room_arr["view_yview"]
	view_wview = room_arr["view_wview"]
	view_hview = room_arr["view_hview"]
	views_on = s["views_on"]
	show_colour = s["show_colour"]
	background_color = s["colour"]
	tiles = s["tiles"]
	tiles_sorted = false
