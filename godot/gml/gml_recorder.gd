# Records drawing calls made by GML Draw events during a logic step, so that Draw
# events run exactly once per game frame (some of them contain game logic, e.g. the
# battle controller counts the enemy's turn down in its Draw event) and the result can
# be painted on every rendered frame.
extends RefCounted

const JUMP := 40.0   # movement larger than this between two logic frames is not smoothed
const FADE := 0.25   # alpha of what is faded for this screen (another player's SOUL)

var ops: Array = []
var prev_pos := {}     # instance id -> position at the previous logic frame
var cur_pos := {}      # instance id -> position at this logic frame
var prev_ops := {}     # instance id -> that instance's drawing ops at the previous logic frame
var view := Vector2.ZERO   # view 0's position (view_xview/yview): screen shake moves it
var prev_view := Vector2.ZERO  # its position at the previous logic frame (smoothed between)
var view_scale := Vector2.ONE  # port size / view size (the overworld draws 320x240 at 2x)
var _snap := Vector2.ONE       # smoothing rounds to whole screen pixels: 1 / this, in room units
var _owners: Array = []    # [id, index of its "@owner" op] in drawing order, this frame
var _plan := {}            # see _make_plan
var _plan_dirty := true
var shift := {}            # instance id -> extra offset (a friend's PC predicting its own walk)


func clear() -> void:
	# Keep each instance's ops for blending on the next frame.
	var keep := {}
	for k in _owners.size():
		var start: int = _owners[k][1] + 1
		var stop: int = _segment_end(start)
		keep[_owners[k][0]] = ops.slice(start, stop)
	prev_ops = keep
	_owners.clear()
	_plan_dirty = true
	ops.clear()
	prev_pos = cur_pos
	cur_pos = {}
	prev_view = view


func _segment_end(start: int) -> int:
	var i := start
	while i < ops.size():
		var name: String = ops[i][0]
		if name == "@owner" or name == "@gui":
			break
		i += 1
	return i


# Draw GUI events draw in screen space, not shifted by the view.
func gui_begin() -> void:
	ops.append(["@gui", []])


# Marks the start of one instance's drawing (called by the runtime before its Draw).
# With several players (docs/MULTIPLAYER.md stage 3): `tag` is the player the drawing is
# private to (-1: everyone's), and `anchor` the view it was drawn against when it sits on the
# screen rather than in the room (null: in the room).
# `fade`: the player it belongs to, who sees it as drawn; everyone else sees it at 25% (another
# player's SOUL in a shared battle). -1: as drawn for everyone.
func owner(id: int, pos: Vector2, tag := -1, anchor = null, fade := -1) -> void:
	cur_pos[id] = pos
	_plan_dirty = true
	_owners.append([id, ops.size()])
	ops.append(["@owner", [id, tag, anchor, fade]])


# f = how far the renderer is between the last two logic frames (0..1), so movement looks
# smooth at any frame rate while the game logic still runs 30 times a second.
# When an instance drew the same kind of calls on both frames, every position, rectangle,
# scale and angle is blended, so pieces that move and stretch together (the battle box's
# sides and corners while it resizes) stay joined. Otherwise its drawing is only shifted
# back towards where the instance was. Jumps are not smoothed. Blended pixel positions
# move in whole pixels, keeping the current frame's sub-pixel part, like the shift does.
#
# who >= 0 draws that player's screen: other players' private drawing is left out, and the
# picture follows `pview` (that player's view this logic frame; `pprev` the one before).
func replay(canvas, f := 1.0, who := -1, pview = null, pprev = null) -> void:
	var cur: Vector2 = view if pview == null else pview
	var was: Vector2 = prev_view if pprev == null else pprev
	var v := cur
	var sc := view_scale
	if f < 1.0 and sc != Vector2.ONE and cur != was and (cur - was).length() <= JUMP:
		# The view follows the player: smoothed like the instances, in whole screen pixels.
		_snap = sc
		v = cur - _px((cur - was) * (1.0 - f))
	var base := -v
	var room_base := base
	var skip := false
	var faded := false
	var offset := base
	_snap = sc
	var blend: Array = []    # previous frame's ops for the current segment, when blending
	var bi := 0
	var t := 1.0 - f
	if f < 1.0 and _plan_dirty:
		_make_plan()
	var i := 0
	var n := ops.size()
	while i < n:
		var op: Array = ops[i]
		var name: String = op[0]
		if name == "@owner":
			var meta: Array = op[1]
			skip = who >= 0 and meta.size() > 1 and int(meta[1]) >= 0 and int(meta[1]) != who
			if skip:
				i += 1
				continue
			faded = meta.size() > 3 and meta[3] != null and int(meta[3]) >= 0 and int(meta[3]) != who
			# On the screen, not in the room: where it was against the view it was drawn for.
			base = room_base if meta.size() < 3 or meta[2] == null else room_base - (meta[2] - cur)
			if not shift.is_empty():
				base += shift.get(meta[0], Vector2.ZERO)
			offset = base
			blend = []
			if f < 1.0:
				var how = _plan.get(op[1][0])
				if how is Array:
					blend = how
					bi = 0
				elif how is Vector2:
					offset = base + _px(how * t)
			canvas.draw_set_transform(offset * sc, 0.0, sc)
			i += 1
			continue
		if name == "@gui":
			skip = false
			faded = false
			room_base = Vector2.ZERO
			base = Vector2.ZERO
			offset = base
			sc = Vector2.ONE
			blend = []
			canvas.draw_set_transform(offset)
			i += 1
			continue
		if skip:
			i += 1
			continue
		var args: Array = op[1]
		if not blend.is_empty():
			args = _mix(name, blend[bi][1], args, t)
			bi += 1
		if name == "draw_set_transform":
			canvas.draw_set_transform((args[0] + offset) * sc, args[1], args[2] * sc)
		else:
			if faded:
				args = args.duplicate()
				for a in args.size():
					if args[a] is Color:
						args[a] = Color(args[a], (args[a] as Color).a * FADE)
			canvas.callv(name, args)
		i += 1
	canvas.draw_set_transform(Vector2.ZERO)


# How each instance is smoothed this logic frame, worked out once and reused on every
# rendered frame: id -> previous ops to blend with, or the position change to shift by.
func _make_plan() -> void:
	_plan = {}
	for k in _owners.size():
		var id: int = _owners[k][0]
		var start: int = _owners[k][1] + 1
		var p: Array = prev_ops.get(id, [])
		if p.size() > 0 and _same_shape(p, start):
			if _changes(p, start) == 1:
				_plan[id] = p
		elif prev_pos.has(id) and cur_pos.has(id):
			var d: Vector2 = prev_pos[id] - cur_pos[id]
			if d.length() < JUMP and d != Vector2.ZERO:
				_plan[id] = d
	_plan_dirty = false


# Same calls in the same order with the same argument types, from ops[start].
func _same_shape(p: Array, start: int) -> bool:
	if start + p.size() > ops.size():
		return false
	if start + p.size() < ops.size():
		var nx: String = ops[start + p.size()][0]
		if nx != "@owner" and nx != "@gui":
			return false
	for k in p.size():
		var a: Array = p[k]
		var b: Array = ops[start + k]
		if a[0] != b[0]:
			return false
		var aa: Array = a[1]
		var ba: Array = b[1]
		if aa.size() != ba.size():
			return false
		for j in aa.size():
			if typeof(aa[j]) != typeof(ba[j]):
				return false
			if aa[j] is PackedVector2Array and aa[j].size() != ba[j].size():
				return false
	return true


# -1: something jumped (not smoothed), 0: drawn exactly as before, 1: moved or changed.
func _changes(p: Array, start: int) -> int:
	var moved := 0
	for k in p.size():
		var aa: Array = p[k][1]
		var ba: Array = ops[start + k][1]
		for j in aa.size():
			var a = aa[j]
			var b = ba[j]
			if a == b:
				continue
			moved = 1
			match typeof(a):
				TYPE_VECTOR2:
					if (a - b).length() >= JUMP:
						return -1
				TYPE_RECT2:
					if (a.position - b.position).length() >= JUMP or (a.end - b.end).length() >= JUMP:
						return -1
	return moved


# A smoothing offset rounded to whole screen pixels (room pixels in battles, half room
# pixels in the 2x overworld), the same way for the view and for every instance, so
# whatever the view follows stays put on screen.
func _px(d: Vector2) -> Vector2:
	return (d * _snap).round() / _snap


# Blends one op's arguments: a = previous frame, b = this frame, t = weight of a.
func _mix(name: String, aa: Array, ba: Array, t: float) -> Array:
	var out := ba.duplicate()
	if name == "draw_set_transform":
		# position, angle, scale: scale and angle are not pixel positions.
		out[0] = ba[0] + _px((aa[0] - ba[0]) * t)
		out[1] = lerp_angle(float(ba[1]), float(aa[1]), t)
		out[2] = ba[2] + (aa[2] - ba[2]) * t
		return out
	for j in ba.size():
		if name == "draw_texture_rect_region" and j == 2:
			continue   # source region in the texture
		var a = aa[j]
		var b = ba[j]
		match typeof(b):
			TYPE_VECTOR2:
				out[j] = b + _px((a - b) * t)
			TYPE_RECT2:
				var p0: Vector2 = b.position + _px((a.position - b.position) * t)
				var p1: Vector2 = b.end + _px((a.end - b.end) * t)
				out[j] = Rect2(p0, p1 - p0)
			TYPE_FLOAT:
				out[j] = b + (a - b) * t
			TYPE_PACKED_VECTOR2_ARRAY:
				var pts := PackedVector2Array(b)
				for q in pts.size():
					pts[q] = b[q] + _px((a[q] - b[q]) * t)
				out[j] = pts
	return out


func draw_set_transform(p: Vector2, r := 0.0, s := Vector2.ONE) -> void:
	ops.append(["draw_set_transform", [p, r, s]])


func draw_texture(t: Texture2D, p: Vector2, m := Color.WHITE) -> void:
	ops.append(["draw_texture", [t, p, m]])


func draw_texture_rect(t: Texture2D, r: Rect2, tile: bool, m := Color.WHITE) -> void:
	ops.append(["draw_texture_rect", [t, r, tile, m]])


func draw_texture_rect_region(t: Texture2D, r: Rect2, src: Rect2, m := Color.WHITE) -> void:
	ops.append(["draw_texture_rect_region", [t, r, src, m]])


func draw_rect(r: Rect2, c: Color, filled := true, width := -1.0) -> void:
	ops.append(["draw_rect", [r, c, filled, width]])


func draw_line(a: Vector2, b: Vector2, c: Color, width := -1.0) -> void:
	ops.append(["draw_line", [a, b, c, width]])


func draw_arc(center: Vector2, radius: float, a0: float, a1: float, points: int, c: Color, width := -1.0) -> void:
	ops.append(["draw_arc", [center, radius, a0, a1, points, c, width]])


func draw_circle(center: Vector2, radius: float, c: Color) -> void:
	ops.append(["draw_circle", [center, radius, c]])


func draw_polyline(pts: PackedVector2Array, c: Color, width := -1.0) -> void:
	ops.append(["draw_polyline", [pts, c, width]])


func draw_colored_polygon(pts: PackedVector2Array, c: Color) -> void:
	ops.append(["draw_colored_polygon", [pts, c]])
