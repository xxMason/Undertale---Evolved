# The battle rules, as one step of game logic (one GameMaker frame at 30 per second).
# Copied from the original code in the player's copy of Undertale v1.08:
#   obj_heart Keyboard 37-40     red SOUL movement (4 px, 2 px while X is held)
#   obj_heart Step               invincibility counter goes down by 1 every frame
#   obj_heart Collision 759-762  push back out of the four box walls
#   blt_parent Collision 744     damage = round(dmg - (DF + armor DF) / 5), at least 1,
#                                then invincible for global.inv frames; bullet removed
#   blt_parent Collision 759-762 a bullet is removed by a wall it is moving towards
# Nothing here draws; battle.gd draws it and replay.gd checks it against a recording.
extends RefCounted

const K_LEFT := 1
const K_RIGHT := 2
const K_UP := 4
const K_DOWN := 8
const K_X := 16

var assets
var heart_x := 0
var heart_y := 0
var hp := 20
var maxhp := 20
var invc := 0
var inv := 30          # measured in the real game (see docs/GODOT_PROTOTYPE.md)
var df := 10
var adef := 0
var sp := 4
var moving := true     # obj_heart "movement == 1" (red SOUL)
# Wall object positions: obj_lborder.x, obj_uborder.y, obj_rborder.x, obj_dborder.y
var wl := 32
var wt := 250
var wr := 602
var wb := 385
var bullets: Array = []  # {spr, x, y, vx, vy, dmg, px, py}
var hits := 0
var events: Array = []   # "hurt" etc., read and cleared by the caller each step

var _heart_mask: PackedByteArray


func _init(a) -> void:
	assets = a
	_heart_mask = assets.masks["spr_heart"]


# GameMaker 1.4 keeps instance positions, speeds and directions as single-precision
# floats (measured: a speed of 3.3 is stored as 3.2999999523), so arithmetic on them is
# rounded to single precision here too.
static func f32(v: float) -> float:
	var a := PackedFloat32Array([v])
	return a[0]


# Round half to even (banker's rounding), which is how the game rounds hitbox edges.
static func rne(v: float) -> int:
	var f := floorf(v)
	var d := v - f
	if d > 0.5:
		return int(f) + 1
	if d < 0.5:
		return int(f)
	return int(f) if int(f) % 2 == 0 else int(f) + 1


func spawn(spr: String, x: float, y: float, speed: float, direction: float, dmg: int, scale := 1.0) -> void:
	var spd := f32(speed)
	var rad := deg_to_rad(f32(direction))
	# GameMaker's direction is counter-clockwise with y pointing down.
	var vx := f32(spd * cos(rad))
	var vy := f32(-spd * sin(rad))
	bullets.append({"spr": spr, "x": f32(x), "y": f32(y), "vx": vx, "vy": vy, "dmg": dmg, "px": f32(x), "py": f32(y), "scale": f32(scale)})


func step(keys: int) -> void:
	# 1. Keyboard events, in key-code order (left, up, right, down).
	if moving:
		var slow := (keys & K_X) != 0
		if keys & K_LEFT:
			heart_x -= sp
			if slow:
				heart_x += sp / 2
		if keys & K_UP:
			heart_y -= sp
			if slow:
				heart_y += sp / 2
		if keys & K_RIGHT:
			heart_x += sp
			if slow:
				heart_x -= sp / 2
		if keys & K_DOWN:
			heart_y += sp
			if slow:
				heart_y -= sp / 2
	# 2. obj_heart Step.
	invc -= 1
	# 3. Movement from speed.
	for b in bullets:
		b["px"] = b["x"]
		b["py"] = b["y"]
		b["x"] = f32(b["x"] + b["vx"])
		b["y"] = f32(b["y"] + b["vy"])
	# 4. Collisions: the SOUL's walls first (it was created first), then each bullet.
	if _heart_hits_rect(wl, wb - 135, wl + 4, wb - 1):
		heart_x = wl + 5
	if _heart_hits_rect(wl, wt, wr - 1, wt + 4):
		heart_y = wt + 5
	if _heart_hits_rect(wr, wb - 135, wr + 4, wb - 1):
		heart_x = wr - 16
	if _heart_hits_rect(wl, wb, wr - 1, wb + 4):
		heart_y = wb - 16
	var keep: Array = []
	for b in bullets:
		if _bullet_hits_heart(b):
			if invc < 1:
				var dmgamt := roundi(b["dmg"] - (df + adef) / 5.0)
				if dmgamt < 1:
					dmgamt = 1
				hp = maxi(0, hp - dmgamt)
				invc = inv
				hits += 1
				events.append("hurt")
				continue
		if _bullet_leaves(b):
			continue
		keep.append(b)
	bullets = keep


# A bullet's hitbox in whole pixels. Each edge is rounded on its own, half to even:
#   left = round(x + (margin_left - origin) * scale), right = round(x + (margin_right + 1 - origin) * scale) - 1
# Measured against 1510 logged bullet positions in the real game (all matched).
func bullet_rect(b: Dictionary) -> Rect2i:
	var info: Dictionary = assets.sprite_info(b["spr"])
	var s: float = b["scale"]
	var l := rne(b["x"] + (int(info["bbox_left"]) - int(info["xoff"])) * s)
	var r := rne(b["x"] + (int(info["bbox_right"]) + 1 - int(info["xoff"])) * s) - 1
	var t := rne(b["y"] + (int(info["bbox_top"]) - int(info["yoff"])) * s)
	var bt := rne(b["y"] + (int(info["bbox_bottom"]) + 1 - int(info["yoff"])) * s) - 1
	return Rect2i(l, t, r - l + 1, bt - t + 1)


func _heart_hits_rect(l: int, t: int, r: int, b: int) -> bool:
	var x0 := maxi(l, heart_x)
	var x1 := mini(r, heart_x + 15)
	var y0 := maxi(t, heart_y)
	var y1 := mini(b, heart_y + 15)
	if x0 > x1 or y0 > y1:
		return false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if _heart_mask[(y - heart_y) * 16 + (x - heart_x)] == 1:
				return true
	return false


func _bullet_hits_heart(b: Dictionary) -> bool:
	var info: Dictionary = assets.sprite_info(b["spr"])
	var r := bullet_rect(b)
	var precise: bool = info["mask_kind"] == "Precise"
	var w := int(info["width"])
	var ox := r.position.x - int(info["bbox_left"])
	var oy := r.position.y - int(info["bbox_top"])
	var m: PackedByteArray = assets.masks[b["spr"]]
	var x0 := maxi(r.position.x, heart_x)
	var x1 := mini(r.end.x - 1, heart_x + 15)
	var y0 := maxi(r.position.y, heart_y)
	var y1 := mini(r.end.y - 1, heart_y + 15)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if _heart_mask[(y - heart_y) * 16 + (x - heart_x)] != 1:
				continue
			if not precise or m[(y - oy) * w + (x - ox)] == 1:
				return true
	return false


# blt_parent: removed on touching a wall while moving towards it.
func _bullet_leaves(b: Dictionary) -> bool:
	var r := bullet_rect(b)
	var walls := [
		[Rect2i(wl, wb - 135, 5, 135), b["vx"] < 0],
		[Rect2i(wl, wt, wr - wl, 5), b["vy"] < 0],
		[Rect2i(wr, wb - 135, 5, 135), b["vx"] > 0],
		[Rect2i(wl, wb, wr - wl, 5), b["vy"] > 0],
	]
	for w in walls:
		if w[1] and r.intersects(w[0]):
			return true
	return false
