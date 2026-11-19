# Per-player engine prompts and waiting notes, in Undertale's style (docs/MULTIPLAYER.md,
# "Look and feel"): "Teleport to Story Event?" with Yes / No, "Waiting for 1 more player...".
#
# The host runs them: a player's keys go to their prompt instead of the game while it is up
# (and keys still held when it closes stay away from the game until let go). The host's PC
# draws its own player's; a friend's PC gets its player's in each frame (mp_net.gd "ui") and
# draws it the same way.
extends RefCounted

const MpPMenu = preload("res://mp_pmenu.gd")

const LEFT := 37
const RIGHT := 39
const Z := 90
const ENTER := 13
const X := 88
const SHIFT := 16

var eng
var mp
var prompts := {}   # player index -> {"lines": [..], "sel": 0 (Yes) / 1 (No), "done": Callable(bool)}
var pmenu = null    # mp_pmenu.gd: the player menus (Enter facing another player)
var waits := {}     # player index -> {"text": String, "cancel": Callable()}: X calls cancel


func setup(e) -> void:
	eng = e
	mp = e.mp
	pmenu = MpPMenu.new()
	pmenu.setup(e)


func ask(p: int, lines: Array, done: Callable) -> void:
	prompts[p] = {"lines": lines, "sel": 0, "done": done}


func close(p: int) -> void:
	prompts.erase(p)


func busy(p: int) -> bool:
	return prompts.has(p) or pmenu.busy(p)


func set_wait(p: int, text: String, cancel := Callable()) -> void:
	if text == "":
		waits.erase(p)
	else:
		waits[p] = {"text": text, "cancel": cancel}


# Player p's keys this frame (already polled), before the game sees them.
func filter(p) -> void:
	var k = p.keys
	var pr = prompts.get(p.index)
	if pr != null:
		if k.pressed(LEFT) or k.pressed(RIGHT):
			pr["sel"] = 1 - int(pr["sel"])
			_sound(p.index, "snd_squeak")
		elif k.pressed(Z) or k.pressed(ENTER):
			_sound(p.index, "snd_select")
			prompts.erase(p.index)
			k.clear(-1)
			(pr["done"] as Callable).call(int(pr["sel"]) == 0)
			return
		k.clear(-1)
		return
	if pmenu.busy(p.index):
		pmenu.key(p)
		return
	var w = waits.get(p.index)
	if w != null and (k.pressed(X) or k.pressed(SHIFT)) and (w["cancel"] as Callable).is_valid():
		waits.erase(p.index)
		(w["cancel"] as Callable).call()
	# Enter facing another player: the player menu.
	if k.pressed(ENTER) and w == null and _can_menu(p):
		var to: int = pmenu.facing(p)
		if to >= 0:
			k.clear(-1)
			pmenu.open(p.index, to)


# Player p is walking about freely in a room (no text, menu or battle).
func _can_menu(p) -> bool:
	if float(mp.value(p.index, "interact", 0.0)) != 0.0 or float(mp.value(p.index, "menuno", -1.0)) >= 0.0:
		return false
	var rooms = eng.get("mprooms")
	return rooms == null or not rooms._private_room(eng.vm.room)


func _sound(p: int, name: String) -> void:
	var s := int(eng.vm.consts.get(name, -1.0))
	if s < 0:
		return
	var keep: int = eng.vm.ctx_owner
	mp.switch_to(p)
	eng.bi.play_sound(s, false)
	mp.switch_to(keep)


# What player p's screen shows of this (sent to a friend's PC with each frame).
func state_for(p: int) -> Dictionary:
	var out := {}
	var pr = prompts.get(p)
	if pr != null:
		out["p"] = [pr["lines"], int(pr["sel"])]
	var w = waits.get(p)
	if w != null:
		out["w"] = w["text"]
	var m: Dictionary = pmenu.state_for(p)
	if not m.is_empty():
		out["m"] = m
	return out


# Draws a state on the engine's screen (640x480): the waiting note at the top, the prompt as a
# text box at the bottom, Yes / No with the SOUL beside the chosen one.
static func draw(e, st: Dictionary) -> void:
	if st.has("m"):
		MpPMenu.draw(e, st["m"])
	if st.has("w"):
		var t := String(st["w"])
		var w := 16.0 * t.length() + 24.0
		e.draw_rect(Rect2(320 - w / 2, 8, w, 34), Color.WHITE)
		e.draw_rect(Rect2(323 - w / 2, 11, w - 6, 28), Color.BLACK)
		e._text(332 - w / 2, 12, t, 16777215, "fnt_main")
	if st.has("p"):
		var lines: Array = st["p"][0]
		var sel := int(st["p"][1])
		e.draw_rect(Rect2(32, 320, 576, 150), Color.WHITE)
		e.draw_rect(Rect2(38, 326, 564, 138), Color.BLACK)
		var y := 340.0
		for l in lines:
			e._text(58, y, String(l), 16777215, "fnt_main")
			y += 36.0
		var yes_x := 200.0
		var no_x := 400.0
		e._text(yes_x, 420, "Yes", 65535 if sel == 0 else 16777215, "fnt_main")
		e._text(no_x, 420, "No", 65535 if sel == 1 else 16777215, "fnt_main")
		e._heart((yes_x if sel == 0 else no_x) - 28, 428)
