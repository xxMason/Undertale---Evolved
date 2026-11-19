# Plays the game from a walkthrough script, for testing (--bot FILE with --game).
# It only presses keys, as a player would; it reads the game's state to decide what to
# press and to check that the story went the way it should.
#
# Script lines (one command each, # comments):
#   z_until COND           tap Z (confirm) until COND holds
#   x_until COND           tap X (cancel) until COND holds
#   wait N | wait_until COND
#   hold KEYS N            hold keys (l r u d z x c, e.g. "ur") for N frames
#   tap KEY                one press
#   goto X Y               walk to the point, x first then y; fails if stuck
#   gotoy Y X              y first then x
#   path X Y               walk there around walls (plans a route through the room's solid
#                          objects as they are now, and plans again if it gets stuck)
#   face DIR               turn (one-frame tap) to l r u d
#   talk                   tap Z, then confirm until no text box is left
#   battle MODE            how to play battles: fight, spare, act:N (Nth ACT, or the monster's
#                          sparing ACT from RIGHT_ACT, then spare),
#                          acts:N (that ACT every turn, never spare), flee
#   choose N               answer choice boxes with the left (0) or right (1) option
#   expect COND            stop with a failure if COND doesn't hold
#   shot NAME              screenshot (windowed runs)
#   log TEXT
#   where OBJ              log where every OBJ is (and the player)
#   near [N]               log the objects within N pixels of the player
#   show NAME,...          log global variables (NAME.N for an array element: flag.10;
#                          OBJ.VAR for an object's variable: obj_goofyrock.conversation)
#   roam DIRS COND         walk back and forth (keys held, 30 frames per direction) until
#                          COND; a "z" in DIRS also taps Z while walking ("roam lrz battle")
#   canmove DIR            fail unless the player moves when DIR is held
#   push OBJ DIR COND      keep lining up beside OBJ and walking into it (DIR) until COND
#   use OBJ [SIDE]         walk up to OBJ (standing below it, or on SIDE l/r/u/d), face it
#                          and talk until the text is gone: "use obj_savepoint"
# Conditions (all must hold, joined with " & "):
#   room=NAME  plot>=N plot=N plot<N  interact=N  exists=OBJ  gone=OBJ  px<N px>N py<N py>N
#   battle (in a battle room)  nobattle  notext (no text box)  global.NAME=N  NAME.N=V (array element)
# Every wait has a time limit (900 frames, or "... within N"); hitting it is a failure.
extends RefCounted

const KEYS := {"l": 37, "r": 39, "u": 38, "d": 40, "z": 90, "x": 88, "c": 67}
const LIMIT := 900

var lines: Array = []
var pc := 0
var eng
var vm
var bi
var started := -1     # frame the current command started
var t := 0            # frame counter inside the current command
var failed := ""
var done := false
var battle_mode := "fight"
var choose_side := 0  # answer for choice boxes: 0 left, 1 right ("choose N")
var log_out: Array = []
var _stuck := 0
var _last := Vector2(-1, -1)
var _goto_axis := 0
var _goto_room := -1
var _use_phase := 0
var _use_t := 0
var _use_side := 0     # use: which side is being tried
var _use_said := false


func load_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "no such file: " + path
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var l := raw.strip_edges()
		var h := l.find("#")
		if h >= 0:
			l = l.substr(0, h).strip_edges()
		if l != "":
			lines.append(l)
	return ""


func _say(s: String) -> void:
	var line := "BOT f=%d %s" % [eng.frames, s]
	log_out.append(line)
	print(line)


func _fail(why: String) -> void:
	failed = "line %d (%s): %s" % [pc + 1, lines[pc] if pc < lines.size() else "-", why]
	_say("FAIL " + failed)
	done = true


func _player():
	return vm.first_of(float(vm.obj_index.get("obj_mainchara", -1)), {"self": null, "other": null})


func _g(name: String) -> float:
	var v = vm.globals.get(name, 0.0)
	return float(v) if v is float or v is int else 0.0


func in_battle() -> bool:
	var rn: String = vm.room_names[vm.room]
	if rn == "room_battle" or rn == "room_floweybattle" or rn == "room_gameover":
		return true
	return vm.instances.any(func(i): return not i.dead and vm.obj_names[i.obj] == "obj_battlecontroller")


func _text_up() -> bool:
	for i in vm.instances:
		if not i.dead:
			var n: String = vm.obj_names[i.obj]
			if n == "OBJ_WRITER" or n == "obj_dialoguer" or n == "OBJ_NOMSCWRITER":
				return true
	return false


func _exists(name: String) -> bool:
	var o = vm.obj_index.get(name)
	if o == null:
		return false
	return vm.first_of(float(o), {"self": null, "other": null}) != null


func _num(s: String) -> float:
	return float(s)


func cond(c: String) -> bool:
	for part in c.split("&", false):
		var p := part.strip_edges()
		if p == "":
			continue
		if not _cond1(p):
			return false
	return true


func _cmp(val: float, op: String, ref: float) -> bool:
	match op:
		"=": return absf(val - ref) < 0.0001
		">=": return val >= ref - 0.0001
		"<=": return val <= ref + 0.0001
		">": return val > ref
		"<": return val < ref
		"!=": return absf(val - ref) >= 0.0001
	return false


func _cond1(p: String) -> bool:
	if p == "battle":
		return in_battle()
	if p == "nobattle":
		return not in_battle()
	if p == "notext":
		return not _text_up()
	if p == "text":
		return _text_up()
	var re := RegEx.create_from_string("^([a-zA-Z_.0-9]+)\\s*(>=|<=|!=|=|<|>)\\s*(\\S+)$")
	var m := re.search(p)
	if m == null:
		_fail("bad condition " + p)
		return false
	var k := m.get_string(1)
	var op := m.get_string(2)
	var v := m.get_string(3)
	match k:
		"room":
			var rn: String = vm.room_names[vm.room]
			return (rn == v) == (op == "=")
		"exists":
			return _exists(v)
		"gone":
			return not _exists(v)
		"px", "py":
			var pl = _player()
			if pl == null:
				return false
			return _cmp(float(pl.v["x" if k == "px" else "y"]), op, _num(v))
	return _cmp(_val(k), op, _num(v))


# A global by name: "plot", "global.plot", or an array element "flag.10", "item.0".
func _val(k: String) -> float:
	if k.begins_with("global."):
		k = k.substr(7)
	if k.begins_with("obj_") and k.contains("."):
		# OBJ.VAR: a variable of the first instance of OBJ (0 when there is none).
		var o = vm.obj_index.get(k.substr(0, k.find(".")))
		var inst = vm.first_of(float(o), {"self": null, "other": null}) if o != null else null
		if inst == null:
			return 0.0
		var iv = inst.v.get(k.substr(k.find(".") + 1), 0.0)
		return float(iv) if iv is float or iv is int else 0.0
	var dot := k.rfind(".")
	if dot > 0 and k.substr(dot + 1).is_valid_int():
		return _arr(k.substr(0, dot), int(k.substr(dot + 1)))
	return _g(k)


# Keys to hold this frame (null = no override). Called once per game frame.
func keys() -> Array:
	if done:
		return []
	if pc >= lines.size():
		done = true
		_say("DONE")
		return []
	var fighting := in_battle()
	if fighting != _was_battle:
		_was_battle = fighting
		_acted_on = {}     # each battle starts with nothing acted yet
		_spares = 0
		if not fighting:
			_say("battle over: hp=%s/%s lv=%s gold=%s" % [_g("hp"), _g("maxhp"), _g("lv"), _g("gold")])
	if fighting and not _cmd_wants_battle():
		# Battles play themselves (battle MODE); a wait still ends when its condition holds,
		# and still times out.
		var l: String = lines[pc]
		if l.begins_with("wait_until") or l.begins_with("z_until") or l.begins_with("x_until") or l.begins_with("roam"):
			if started < 0:
				started = eng.frames
				t = 0
			else:
				t += 1
			var rest := l.substr(l.find(" ") + 1)
			if l.begins_with("roam"):
				rest = rest.substr(rest.find(" ") + 1)
			var lc := _limit_of(rest)
			if cond(lc[0]):
				_say("ok " + l)
				_next()
				return []
			if t >= int(lc[1]):
				_fail("timed out (in battle)")
				return []
		return _battle_keys()
	if started < 0:
		started = eng.frames
		t = 0
		_stuck = 0
		_goto_axis = 0
		_replans = 0
		_use_phase = 0
		_use_side = 0
		_use_said = false
		_route = []
		_last = Vector2(-1, -1)
	else:
		t += 1
	var out := _run(lines[pc])
	# A choice box (obj_choicer) open: move to the chosen side before confirming.
	var ci = vm.obj_index.get("obj_choicer")
	var ch = vm.first_of(float(ci), {"self": null, "other": null}) if ci != null else null
	if ch != null and int(float(ch.v.get("mychoice", 0.0))) != choose_side:
		return ([39] if choose_side > int(float(ch.v.get("mychoice", 0.0))) else [37]) if eng.frames % 4 < 2 else []
	return out


func _cmd_wants_battle() -> bool:
	var l: String = lines[pc]
	return l.begins_with("shot") or l.begins_with("log") or l.begins_with("near") or l.begins_with("show") or l.begins_with("where") or l.begins_with("battle ") or l.begins_with("choose") or l.begins_with("expect")


func _next() -> void:
	pc += 1
	started = -1


func _limit_of(l: String) -> Array:
	# "COND within N" -> [COND, N]
	var w := l.find(" within ")
	if w >= 0:
		# In co-op the friend takes every other battle turn, so battles take a lot longer.
		var mult := 6 if eng.coop != null and eng.coop.linked else 1
		return [l.substr(0, w), int(l.substr(w + 8)) * mult]
	return [l, LIMIT]


func _run(l: String) -> Array:
	var sp := l.find(" ")
	var cmd := l if sp < 0 else l.substr(0, sp)
	var arg := "" if sp < 0 else l.substr(sp + 1).strip_edges()
	match cmd:
		"where":
			var o = vm.obj_index.get(arg)
			var at: Array = []
			for i in vm.instances:
				if not i.dead and o != null and vm.is_child_of(i.obj, int(o)):
					at.append("%s,%s" % [i.v["x"], i.v["y"]])
			var pl = _player()
			_say("%s at %s; player %s" % [arg, ", ".join(at), ("%s,%s" % [pl.v["x"], pl.v["y"]]) if pl != null else "-"])
			_next()
			return []
		"near":
			# near [N]: log every object whose box is within N pixels (default 8) of the player's.
			var pl4 = _player()
			if pl4 != null:
				var nb: Rect2i = vm.bbox(pl4).grow(int(arg) if arg != "" else 8)
				var hits: Array = []
				for i in vm.instances:
					if not i.dead and i != pl4 and vm.bbox(i).intersects(nb):
						hits.append("%s%s %s" % [vm.obj_names[i.obj], " (solid)" if float(i.v.get("solid", 0.0)) >= 0.5 else "", vm.bbox(i)])
				_say("near the player %s: %s" % [vm.bbox(pl4), ", ".join(hits)])
			_next()
			return []
		"show":
			# show NAME[,NAME...]: log global variables (flag.N for global.flag[N]).
			var parts: Array = []
			for nm in arg.split(","):
				var k2 := nm.strip_edges()
				parts.append("%s=%s" % [k2, _val(k2)])
			_say(" ".join(parts))
			_next()
			return []
		"log":
			_say(arg)
			_next()
			return []
		"choose":
			choose_side = int(arg)
			_next()
			return []
		"battle":
			battle_mode = arg
			_next()
			return []
		"wait":
			if t >= int(arg):
				_next()
			return []
		"wait_until", "z_until", "x_until":
			var lc := _limit_of(arg)
			if cond(lc[0]):
				_say("ok " + l)
				_next()
				return []
			if t >= int(lc[1]):
				_fail("timed out")
				return []
			if cmd == "z_until" and t % 6 < 2:
				return [90]
			if cmd == "x_until" and t % 6 < 2:
				return [88]
			return []
		"expect":
			if cond(arg):
				_say("ok " + l)
				_next()
			else:
				_fail("not true")
			return []
		"hold":
			var p := arg.split(" ")
			if t >= int(p[1]):
				_next()
				return []
			var out: Array = []
			for ch in p[0]:
				out.append(KEYS[ch])
			return out
		"roam":
			# roam DIRS COND: walk back and forth (each direction in DIRS for 30 frames in turn,
			# keys held without a break) until COND, e.g. "roam lr battle" walks into a random
			# encounter with the keys still down. A "z" in DIRS also taps Z while walking.
			var sp2 := arg.find(" ")
			var dirs := arg.substr(0, sp2)
			var lc2 := _limit_of(arg.substr(sp2 + 1))
			if cond(lc2[0]):
				_say("ok " + l)
				_next()
				return []
			if t >= int(lc2[1]):
				_fail("timed out")
				return []
			var walk := dirs.replace("z", "")
			var out2: Array = []
			if walk != "":
				out2.append(KEYS[walk[(t / 30) % walk.length()]])
			if dirs.contains("z") and t % 4 == 0:
				out2.append(90)
			return out2
		"push":
			# push OBJ DIR COND: line up beside OBJ (on the side away from DIR) and walk into it,
			# again and again, tapping through any text, until COND. For push rocks and things
			# that move when you bump into them (Ruins 11's talking rock).
			var pp := arg.split(" ", false, 2)
			var lc3 := _limit_of(pp[2])
			if cond(lc3[0]):
				_say("ok " + l)
				_next()
				return []
			if t >= int(lc3[1]):
				_fail("timed out")
				return []
			if t % 300 == 0:
				_say("pushing %s: %s,%s conversation=%s interact=%s" % [pp[0], _val(pp[0] + ".x"), _val(pp[0] + ".y"), _val(pp[0] + ".conversation"), _g("interact")])
			if _g("interact") != 0.0 or _text_up():
				return [90] if t % 6 < 2 else []
			var po = vm.obj_index.get(pp[0])
			var target = vm.first_of(float(po), {"self": null, "other": null}) if po != null else null
			var pl3 = _player()
			if target == null or pl3 == null:
				_fail("nothing to push")
				return []
			var tb: Rect2i = vm.bbox(target)
			var pb3: Rect2i = vm.bbox(pl3)
			var px := float(pl3.v["x"])
			var py := float(pl3.v["y"])
			# Where the player's box should be: touching the object, centred on it.
			var want := Vector2(px, py)
			var dkey: int = KEYS[pp[1]]
			match pp[1]:
				"r": want = Vector2(px + (tb.position.x - 1 - pb3.end.x), py + (tb.get_center().y - pb3.get_center().y))
				"l": want = Vector2(px + (tb.end.x + 1 - pb3.position.x), py + (tb.get_center().y - pb3.get_center().y))
				"d": want = Vector2(px + (tb.get_center().x - pb3.get_center().x), py + (tb.position.y - 1 - pb3.end.y))
				"u": want = Vector2(px + (tb.get_center().x - pb3.get_center().x), py + (tb.end.y + 1 - pb3.position.y))
			var off := want - Vector2(px, py)
			# On the wrong side of it (or far away): walk round with the planner first.
			var wrong := false
			match pp[1]:
				"r": wrong = pb3.end.x > tb.position.x + 2
				"l": wrong = pb3.position.x < tb.end.x - 2
				"d": wrong = pb3.end.y > tb.position.y + 2
				"u": wrong = pb3.position.y < tb.end.y - 2
			if wrong or off.length() > 24.0:
				if _route.is_empty() or t % 30 == 0:
					_route = _plan(pl3, want.x, want.y)
				while not _route.is_empty() and (_route[0] - Vector2(px, py)).length() < 2.0:
					_route.pop_front()
				if not _route.is_empty():
					var to2: Vector2 = _route[0] - Vector2(px, py)
					var o3: Array = []
					if to2.x > 1.0:
						o3.append(39)
					elif to2.x < -1.0:
						o3.append(37)
					if to2.y > 1.0:
						o3.append(40)
					elif to2.y < -1.0:
						o3.append(38)
					return o3
			_route = []
			var keys2: Array = [dkey]
			if pp[1] == "r" or pp[1] == "l":
				if off.y > 2.0:
					keys2.append(40)
				elif off.y < -2.0:
					keys2.append(38)
			else:
				if off.x > 2.0:
					keys2.append(39)
				elif off.x < -2.0:
					keys2.append(37)
			if t % 8 == 0:
				keys2.append(90)
			return keys2
		"use":
			# use OBJ [FROM]: walk up to OBJ (from below by default; FROM l/r/u/d is the side
			# to stand on), face it and talk until the text is gone. "use obj_savepoint".
			var up := arg.split(" ", false)
			var uo = vm.obj_index.get(up[0])
			var ut = vm.first_of(float(uo), {"self": null, "other": null}) if uo != null else null
			var pl5 = _player()
			if ut == null or pl5 == null:
				_fail("nothing to use")
				return []
			# No side given: below, else whichever side can be reached (l, r, u).
			var side: String = up[1] if up.size() > 1 else ["d", "l", "r", "u"][_use_side % 4]
			var face_key: int = {"d": 38, "u": 40, "l": 39, "r": 37}[side]
			if _use_phase == 0:
				var ub: Rect2i = vm.bbox(ut)
				var pb5: Rect2i = vm.bbox(pl5)
				var ox5 := pb5.position.x - float(pl5.v["x"])
				var oy5 := pb5.position.y - float(pl5.v["y"])
				var spot := Vector2.ZERO
				match side:
					"d": spot = Vector2(ub.get_center().x - pb5.size.x / 2.0, ub.end.y + 1) - Vector2(ox5, oy5)
					"u": spot = Vector2(ub.get_center().x - pb5.size.x / 2.0, ub.position.y - pb5.size.y - 1) - Vector2(ox5, oy5)
					"l": spot = Vector2(ub.position.x - pb5.size.x - 1, ub.end.y - pb5.size.y) - Vector2(ox5, oy5)
					"r": spot = Vector2(ub.end.x + 1, ub.end.y - pb5.size.y) - Vector2(ox5, oy5)
				var here5 := Vector2(float(pl5.v["x"]), float(pl5.v["y"]))
				if (here5 - spot).length() > 3.0 and t < 600:
					if _route.is_empty() or t % 40 == 0:
						_route = _plan(pl5, spot.x, spot.y)
						var reach: Vector2 = _route[_route.size() - 1] if not _route.is_empty() else here5
						if (reach - spot).length() > 3.0 and up.size() == 1 and _use_side < 3:
							_use_side += 1     # that side can't be reached: try the next
							_route = []
							return []
					while not _route.is_empty() and (_route[0] - here5).length() < 2.0:
						_route.pop_front()
					if _g("interact") != 0.0 or _text_up():
						return [90] if t % 6 < 2 else []
					if not _route.is_empty():
						var to5: Vector2 = _route[0] - here5
						var o5: Array = []
						if to5.x > 1.0: o5.append(39)
						elif to5.x < -1.0: o5.append(37)
						if to5.y > 1.0: o5.append(40)
						elif to5.y < -1.0: o5.append(38)
						return o5
				_route = []
				_use_phase = 1
				_use_t = t
				return [face_key]
			if _use_phase == 1:
				# Turned; confirm.
				if t - _use_t < 3:
					return []
				_use_phase = 2
				_use_t = t
				return [90]
			# Confirm until the text is gone (and something was said).
			if _text_up() or _g("interact") != 0.0:
				_use_said = true
			if t - _use_t > 40 and not _use_said:
				_fail("%s said nothing (stood %s of it at %s,%s)" % [up[0], side, pl5.v["x"], pl5.v["y"]])
				return []
			if t - _use_t > 4 and _use_said and not _text_up() and _g("interact") == 0.0:
				_say("used %s" % up[0])
				_use_phase = 0
				_next()
				return []
			if t >= LIMIT + 600:
				_fail("text never closed")
				return []
			return [90] if t % 6 < 2 else []
		"canmove":
			# canmove DIR: the player must move within 20 frames of holding DIR.
			var pl2 = _player()
			if pl2 == null:
				_fail("no player")
				return []
			if t == 0:
				_last = Vector2(float(pl2.v["x"]), float(pl2.v["y"]))
			elif Vector2(float(pl2.v["x"]), float(pl2.v["y"])) != _last:
				_say("ok " + l)
				_next()
				return []
			if t >= 20:
				_fail("player can't move (interact=%s)" % _g("interact"))
				return []
			return [KEYS[arg]]
		"tap", "face":
			if t >= 3:
				_next()
				return []
			return [KEYS[arg]] if t == 0 else []
		"talk":
			# Face is already right: confirm, then keep confirming until the text is gone.
			if t == 0:
				return [90]
			if t > 4 and not _text_up() and _g("interact") == 0.0:
				_next()
				return []
			if t >= LIMIT:
				_fail("text never closed")
				return []
			return [90] if t % 6 < 2 else []
		"shot":
			if eng.has_method("bot_shot"):
				eng.bot_shot(arg)
			_next()
			return []
		"goto", "gotoy":
			return _goto(cmd == "gotoy", arg)
		"path":
			return _path(arg)
	_fail("unknown command " + cmd)
	return []


func _goto(yfirst: bool, arg: String) -> Array:
	var p := arg.split(" ")
	var tx := float(p[0])
	var ty := float(p[1])
	if yfirst:
		var s := tx
		tx = ty
		ty = s
	var pl = _player()
	if _goto_room < 0:
		_goto_room = vm.room
	if pl == null or vm.room != _goto_room:
		# A cutscene or a battle took over and moved on: the walk is over.
		_say("walk interrupted (%s)" % vm.room_names[vm.room])
		_goto_room = -1
		_next()
		return []
	var x := float(pl.v["x"])
	var y := float(pl.v["y"])
	var dx := tx - x
	var dy := ty - y
	var axes := [1, 0] if yfirst else [0, 1]
	var axis: int = axes[_goto_axis]
	var d := dx if axis == 0 else dy
	if absf(d) < 3.0:
		_goto_axis += 1
		_stuck = 0
		if _goto_axis >= 2:
			_say("at %s,%s" % [x, y])
			_goto_room = -1
			_next()
		return []
	if _g("interact") != 0.0 or _text_up():
		# Something took over (a cutscene, a text box): wait, confirming text.
		return [90] if t % 6 < 2 else []
	var here := Vector2(x, y)
	if here == _last:
		_stuck += 1
		if _stuck > 20:
			_goto_room = -1
			_fail("stuck at %s,%s going to %s,%s" % [x, y, tx, ty])
			return []
	else:
		_stuck = 0
	_last = here
	if t >= 1800:
		_fail("too long")
		return []
	if axis == 0:
		return [39 if d > 0 else 37]
	return [40 if d > 0 else 38]


# ---------------------------------------------------------------- battles

func _battle_keys() -> Array:
	var f: int = eng.frames
	var mn := _g("mnfight")
	var my := _g("myfight")
	var bkey := "%s/%s/%s/%s" % [_g("bmenuno"), _arr("bmenucoord", 0), _arr("bmenucoord", 2), my]
	if bkey != _bkey and OS.get_cmdline_user_args().has("--botbattlelog"):
		_bkey = bkey
		_say("menu bmenuno/coord0/coord2/myfight = " + bkey)
	if f % 90 == 0 and OS.get_cmdline_user_args().has("--botbattlelog"):
		_say("battle group=%s hp=%s myfight=%s mnfight=%s bmenuno=%s" % [_g("battlegroup"), _g("hp"), my, mn, _g("bmenuno")])
	if vm.room == int(vm.consts.get("room_gameover", -1.0)):
		return [90] if f % 6 < 2 else []
	if mn == 2.0:
		return _dodge(f)
	var mode := battle_mode
	if mode == "fight":
		return [90] if f % 6 < 2 else []
	# Main menu: buttons FIGHT 0, ACT 1, ITEM 2, MERCY 3 (global.bmenucoord[0]).
	var bno := _g("bmenuno")
	if my == 0.0 and mn == 0.0 and f % 6 < 2:
		var coord := _arr("bmenucoord", 0)
		if bno == 0.0:
			# ACT on every living monster once, then spare; if two spares in a row don't
			# end the battle, go round again (some monsters need more than one ACT).
			var want := 3
			if (mode.begins_with("act:") or mode.begins_with("acts:")) and _next_act_target() >= 0:
				want = 1
			if int(coord) != want:
				return [39]
			if want == 3:
				_spares += 1
				if _spares >= 2:
					_spares = 0
					_acted_on = {}
			return [90]
		if bno == 4.0:
			# MERCY: Spare 0, Flee 1.
			var c4 := int(_arr("bmenucoord", 4))
			var want4 := 1 if mode == "flee" else 0
			if c4 != want4:
				return [40 if c4 < want4 else 38]
			return [90]
		if bno == 2.0:
			# ACT target (global.bmenucoord[1]): the next monster not acted on yet.
			var tg := maxi(_next_act_target(), 0)
			if int(_arr("bmenucoord", 1)) != tg:
				return [40]
			_acted_on[tg] = true
			return [90]
		if bno == 10.0 and (mode.begins_with("act:") or mode.begins_with("acts:")):
			# ACT options (global.bmenucoord[2]): left column 0, 1, 2, right column 3, 4, 5.
			# act:N counts in reading order (Check 0, the one right of it 1, below Check 2...).
			var n := int(mode.substr(mode.find(":") + 1))
			# act:N picks the ACT that spares the targeted monster when it is known.
			var mt := int(_arr("monstertype", int(_arr("bmenucoord", 1))))
			if mode.begins_with("act:") and RIGHT_ACT.has(mt):
				n = RIGHT_ACT[mt]
			var want3 := (n / 2) + 3 * (n % 2)
			var c3 := int(_arr("bmenucoord", 2))
			if c3 != want3:
				if (c3 >= 3) != (want3 >= 3):
					return [39]
				return [40]
			return [90]
		return [90]
	return [90] if f % 6 < 2 else []


# global.monstertype -> the ACT (reading order) that lets it be spared.
const RIGHT_ACT := {1: 1, 5: 1, 6: 1, 7: 1, 8: 3, 9: 2, 12: 1}

var _acted_on := {}         # monster slots acted on in this battle
var _spares := 0
var _was_battle := false
var _bkey := ""
var _danger := {}          # object index -> true for anything that hurts the SOUL


# Objects that can hurt the SOUL: those the SOUL has a collision event with, and those with a
# collision event with the SOUL, with their children.
func _is_danger(obj: int, heart: int) -> bool:
	if _danger.has(obj):
		return _danger[obj]
	var yes := false
	for tgt in vm.collision_targets[heart]:
		if vm.is_child_of(obj, int(tgt)):
			yes = true
	if not yes:
		yes = not vm.find_event(obj, vm.EV_COLLISION, heart).is_empty()
	_danger[obj] = yes
	return yes


# Move the SOUL away from nearby bullets, pulled gently toward the middle of the box.
func _dodge(f: int) -> Array:
	var hi := int(vm.obj_index.get("obj_heart", -1))
	var h = vm.first_of(float(hi), {"self": null, "other": null}) if hi >= 0 else null
	if h == null:
		return [37 if (f / 20) % 2 == 0 else 39]
	var hb: Rect2i = vm.bbox(h)
	var hc := Vector2(hb.get_center())
	var push := Vector2.ZERO
	for i in vm.instances:
		if i.dead or i == h or not _is_danger(i.obj, hi):
			continue
		var b: Rect2i = vm.bbox(i)
		if b.size.x <= 0 or b.size.y <= 0:
			continue
		# Nearest point of the bullet's box to the SOUL.
		var near := Vector2(clampf(hc.x, b.position.x, b.end.x), clampf(hc.y, b.position.y, b.end.y))
		var d := hc - near
		var dist := maxf(d.length(), 1.0)
		if dist > 50.0:
			continue
		if d.length() < 0.5:
			d = hc - Vector2(b.get_center())
		if float(i.v.get("green", 0.0)) == 1.0:
			push -= d.normalized() * 0.6     # healing bullets (Vegetoid's carrots): go and eat them
			continue
		push += d.normalized() * (50.0 - dist) / 50.0
	var mid := Vector2((_arr("idealborder", 0) + _arr("idealborder", 1)) / 2.0, (_arr("idealborder", 2) + _arr("idealborder", 3)) / 2.0)
	if mid != Vector2.ZERO:
		push += (mid - hc) / 150.0
	var o: Array = []
	if push.x > 0.15:
		o.append(39)
	elif push.x < -0.15:
		o.append(37)
	if push.y > 0.15:
		o.append(40)
	elif push.y < -0.15:
		o.append(38)
	return o


# The first living monster (global.monster[i]) not acted on yet in this battle, or -1.
func _next_act_target() -> int:
	if battle_mode.begins_with("acts:"):
		# acts:N: ACT every turn (Napstablook is cheered up, not spared).
		for i in 3:
			if _arr("monster", i) != 0.0:
				return i
		return -1
	for i in 3:
		if _arr("monster", i) != 0.0 and not _acted_on.has(i):
			return i
	return -1


func _arr(name: String, i: int) -> float:
	# GML arrays are kept as rows: a 1-D index is row 0.
	var a = vm.globals.get(name)
	if a is Array and a.size() > 0 and a[0] is Array and i < (a[0] as Array).size():
		var e = a[0][i]
		return float(e) if e is float or e is int else 0.0
	return 0.0


# ---------------------------------------------------------------- path finding

var _route: Array = []     # remaining waypoints (player x, y)
var _route_for := Vector2(-9999, -9999)
var _replans := 0


func _walls() -> Array:
	var out: Array = []
	var sp := int(vm.obj_index.get("obj_solidparent", -1))
	var dp := int(vm.obj_index.get("obj_diagoparent", -1))
	var np := int(vm.obj_index.get("obj_solidnpcparent", -1))
	for i in vm.instances:
		if i.dead or vm.obj_names[i.obj] == "obj_mainchara":
			continue
		# Diagonal walls are left out: they are triangles that slide the player along them, so a
		# route through their bounding box is usually walkable (a stuck walk plans again).
		if dp >= 0 and vm.is_child_of(i.obj, dp):
			continue
		# Other solid objects count only when visible: invisible solid ones are story triggers
		# (Toriel's phone calls) that the player is meant to walk into.
		if (sp >= 0 and vm.is_child_of(i.obj, sp)) or (np >= 0 and vm.is_child_of(i.obj, np)) or (float(i.v.get("solid", 0.0)) >= 0.5 and float(i.v.get("visible", 1.0)) >= 0.5):
			var r: Rect2i = vm.bbox(i)
			if r.size.x > 0 and r.size.y > 0:
				# Precise masks (Toriel's stairs) are tested by their pixels, boxes by the box.
				out.append(i if vm._precise(i) else r)
	return out


# Breadth-first search on the player's own 3-pixel steps; diagonal moves allowed when both
# straight moves are free.
func _plan(pl, tx: float, ty: float) -> Array:
	# Holes in the floor (obj_holedown and children: Ruins 8 and 10) are avoided when there
	# is a way around them; when there isn't, the walk goes over them and falls.
	var hi := int(vm.obj_index.get("obj_holedown", -1))
	var pits: Array = []
	if hi >= 0:
		for i in vm.instances:
			if not i.dead and vm.is_child_of(i.obj, hi):
				pits.append(i)
	# A target inside a hole means "fall through it": walk straight there.
	var pb: Rect2i = vm.bbox(pl)
	var tr := Rect2i(int(tx) + pb.position.x - int(float(pl.v["x"])), int(ty) + pb.position.y - int(float(pl.v["y"])), pb.size.x, pb.size.y)
	for pit in pits:
		if _pit_hit(pit, tr):
			pits = []
			break
	if not pits.is_empty():
		var safe := _plan_with(pl, tx, ty, pits)
		_say("route around holes: %d steps, ends %s" % [safe.size(), safe[safe.size() - 1] if not safe.is_empty() else "-"])
		if not safe.is_empty() and (safe[safe.size() - 1] - Vector2(tx, ty)).length() < 6.0:
			return safe
	return _plan_with(pl, tx, ty, [])


# Precise test of the player's box against a hole's mask, on a 4-pixel grid of points.
func _pit_hit(pit, r: Rect2i) -> bool:
	var b: Rect2i = vm.bbox(pit)
	if not b.intersects(r):
		return false
	var xs: Array = range(r.position.x, r.end.x, 4)
	xs.append(r.end.x - 1)
	var ys: Array = range(r.position.y, r.end.y, 4)
	ys.append(r.end.y - 1)
	for y in ys:
		for x in xs:
			if vm.collide_rect(pit, Rect2i(x, y, 1, 1)):
				return true
	return false


func _plan_with(pl, tx: float, ty: float, pits: Array) -> Array:
	var walls := _walls()
	var pb: Rect2i = vm.bbox(pl)
	var ox := pb.position.x - int(float(pl.v["x"]))
	var oy := pb.position.y - int(float(pl.v["y"]))
	var sz := pb.size
	var x0 := int(float(pl.v["x"]))
	var y0 := int(float(pl.v["y"]))
	var st := 3
	var free := func(x: int, y: int) -> bool:
		if x + ox < 0 or y + oy < 0 or x + ox + sz.x > vm.room_width or y + oy + sz.y > vm.room_height:
			return false
		var r := Rect2i(x + ox, y + oy, sz.x, sz.y)
		for w in walls:
			if w is Rect2i:
				if r.intersects(w):
					return false
			elif vm.collide_rect(w, r):
				return false
		for pit in pits:
			# A margin: the walk overshoots a waypoint by a step now and then.
			if _pit_hit(pit, r.grow(3)):
				return false
		return true
	var goal := Vector2i(int(tx), int(ty))
	var start := Vector2i(x0, y0)
	var prev := {start: start}
	var q: Array = [start]
	var best := start
	var bestd := INF
	var head := 0
	while head < q.size() and head < 200000:
		var c: Vector2i = q[head]
		head += 1
		var d := Vector2(c - goal).length()
		if d < bestd:
			bestd = d
			best = c
		if d < 3.0:
			break
		for dv in [Vector2i(st, 0), Vector2i(-st, 0), Vector2i(0, st), Vector2i(0, -st), Vector2i(st, st), Vector2i(-st, st), Vector2i(st, -st), Vector2i(-st, -st)]:
			var n: Vector2i = c + dv
			if prev.has(n):
				continue
			if not free.call(n.x, n.y):
				continue
			if dv.x != 0 and dv.y != 0 and (not free.call(c.x + dv.x, c.y) or not free.call(c.x, c.y + dv.y)):
				continue
			prev[n] = c
			q.append(n)
	var pts: Array = []
	var c2 := best
	while c2 != start:
		pts.push_front(Vector2(c2))
		c2 = prev[c2]
	return pts


func _path(arg: String) -> Array:
	var p := arg.split(" ")
	var tx := float(p[0])
	var ty := float(p[1])
	var pl = _player()
	if _goto_room < 0:
		_goto_room = vm.room
	if pl == null or vm.room != _goto_room:
		_say("walk interrupted (%s)" % vm.room_names[vm.room])
		_goto_room = -1
		_route = []
		_next()
		return []
	var here := Vector2(float(pl.v["x"]), float(pl.v["y"]))
	if absf(here.x - tx) < 3.0 and absf(here.y - ty) < 3.0:
		_say("at %s,%s" % [here.x, here.y])
		_goto_room = -1
		_route = []
		_next()
		return []
	if _g("interact") != 0.0 or _text_up():
		return [90] if t % 6 < 2 else []
	if t >= 2400:
		_fail("too long")
		return []
	if _route.is_empty() or _route_for != Vector2(tx, ty) or _stuck > 8:
		if _stuck > 8:
			_replans += 1
			if _replans > 6:
				var pb: Rect2i = vm.bbox(pl)
				var near := pb.grow(6)
				var hits: Array = []
				for i in vm.instances:
					if not i.dead and i != pl and vm.bbox(i).intersects(near):
						hits.append("%s %s" % [vm.obj_names[i.obj], vm.bbox(i)])
				_say("near the player %s: %s" % [pb, ", ".join(hits)])
				_say("route was %s" % [_route.slice(0, 6)])
				_fail("can't get from %s,%s to %s,%s" % [here.x, here.y, tx, ty])
				return []
		_route = _plan(pl, tx, ty)
		_route_for = Vector2(tx, ty)
		_stuck = 0
		if _route.is_empty():
			# Already as close as walls allow (a door is usually reached by then walking into it).
			_say("closest is %s,%s" % [here.x, here.y])
			_goto_room = -1
			_next()
			return []
	# Drop waypoints already reached; head for the next one.
	while not _route.is_empty() and (_route[0] - here).length() < 2.0:
		_route.pop_front()
	if _route.is_empty():
		_route_for = Vector2(-9999, -9999)
		return []
	if here == _last:
		_stuck += 1
	else:
		_stuck = 0
	_last = here
	var to: Vector2 = _route[0] - here
	var out: Array = []
	if to.x > 1.0:
		out.append(39)
	elif to.x < -1.0:
		out.append(37)
	if to.y > 1.0:
		out.append(40)
	elif to.y < -1.0:
		out.append(38)
	return out
