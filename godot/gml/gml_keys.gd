# Keyboard state for the GML runtime, in GameMaker key codes. Real keys come from
# Godot each logic frame; keyboard_key_press/release simulate keys like the original.
extends RefCounted

var real := {}      # code -> true (held this frame)
var sim := {}       # simulated held keys
var now := {}
var prev := {}
var cleared := {}   # keyboard_clear: ignore until the key is released
var wasd := false
var queue: Array = []    # taps from the mouse: one key code (or 0 = nothing) per frame

const MAP := {
	KEY_LEFT: 37, KEY_UP: 38, KEY_RIGHT: 39, KEY_DOWN: 40, KEY_ENTER: 13, KEY_KP_ENTER: 13,
	KEY_SHIFT: 16, KEY_CTRL: 17, KEY_ALT: 18, KEY_SPACE: 32, KEY_BACKSPACE: 8, KEY_TAB: 9,
	KEY_HOME: 36, KEY_END: 35, KEY_DELETE: 46, KEY_INSERT: 45, KEY_PAGEUP: 33, KEY_PAGEDOWN: 34,
	KEY_F1: 112, KEY_F2: 113, KEY_F3: 114, KEY_F4: 115, KEY_F5: 116, KEY_F6: 117, KEY_ESCAPE: 27,
}


func poll(auto_keys = null) -> void:
	real = {}
	if auto_keys != null:
		for k in auto_keys:
			real[int(k)] = true
	else:
		for gk in MAP:
			if Input.is_physical_key_pressed(gk):
				real[MAP[gk]] = true
		for c in range(KEY_A, KEY_Z + 1):
			if Input.is_physical_key_pressed(c):
				real[c] = true      # KEY_A..KEY_Z are 65..90, as in GameMaker
		for c in range(KEY_0, KEY_9 + 1):
			if Input.is_physical_key_pressed(c):
				real[c] = true
		if wasd:
			if real.has(87):
				real[38] = true
			if real.has(65):
				real[37] = true
			if real.has(83):
				real[40] = true
			if real.has(68):
				real[39] = true
	if not queue.is_empty():
		var q := int(queue.pop_front())
		if q > 0:
			real[q] = true
	prev = now
	now = {}
	for k in real:
		now[k] = true
	for k in sim:
		now[k] = true
	for k in cleared.keys():
		if not now.has(k):
			cleared.erase(k)
		else:
			now.erase(k)


# The keys held on this PC right now, as poll() would see them (co-op sends these).
func sample_local() -> Array:
	var r := {}
	for gk in MAP:
		if Input.is_physical_key_pressed(gk):
			r[MAP[gk]] = true
	for c in range(KEY_A, KEY_Z + 1):
		if Input.is_physical_key_pressed(c):
			r[c] = true
	for c in range(KEY_0, KEY_9 + 1):
		if Input.is_physical_key_pressed(c):
			r[c] = true
	if wasd:
		for pair in [[87, 38], [65, 37], [83, 40], [68, 39]]:
			if r.has(pair[0]):
				r[pair[1]] = true
	if not queue.is_empty():
		var q := int(queue.pop_front())
		if q > 0:
			r[q] = true
	return r.keys()


func held(code: int) -> bool:
	if code == 1:
		return not now.is_empty()
	if code == 0:
		return now.is_empty()
	return now.has(code)


func pressed(code: int) -> bool:
	if code == 1:
		for k in now:
			if not prev.has(k):
				return true
		return false
	return now.has(code) and not prev.has(code)


func released(code: int) -> bool:
	return prev.has(code) and not now.has(code)


func held_list() -> Array:
	return now.keys()


func pressed_list() -> Array:
	var out: Array = []
	for k in now:
		if not prev.has(k):
			out.append(k)
	return out


func released_list() -> Array:
	var out: Array = []
	for k in prev:
		if not now.has(k):
			out.append(k)
	return out


func sim_press(code: int) -> void:
	sim[code] = true


func sim_release(code: int) -> void:
	sim.erase(code)


func clear(code: int) -> void:
	if code < 0:
		for k in now.keys():
			cleared[k] = true
		now.clear()
	else:
		cleared[code] = true
		now.erase(code)


# Queues a tap (held one frame, released the next) after any taps already queued.
func tap(code: int) -> void:
	queue.append(code)
	queue.append(0)
