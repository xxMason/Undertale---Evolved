# Battles several players share (docs/MULTIPLAYER.md, "Encounters and battles").
#
# A player's encounter pulls in the players close by in the same room who are free (not in a
# menu, a text box or a prompt); the battle then runs as one world with all of them in it. Its
# state (the menu, the turn, the enemies, their words) is everyone's (mp_players.gd PERSONAL:
# only HP, stats, items, gold and keys stay each player's own). Every player has their own
# SOUL, an obj_heart of their own that moves with their keys and takes the hits that touch it
# (a bullet's collision runs in the context of the SOUL it touches, so Undertale's own damage
# code lowers that player's HP). Other players' SOULs are drawn at 25% on your screen.
#
# Turns go in order: each new menu turn the next player up becomes the world's lead, and the
# battle's own objects (the menu, the text) see that player's HP, items and keys.
#
# A player at 0 HP is down: their SOUL goes, the others fight on. After 3 turns down, MERCY gets
# "Revive <name>" (the whole turn; back at 30% HP). The downed get up on 1 HP when the battle
# ends. Everyone down is Undertale's game over.
#
# A player who wasn't pulled in sees "<name> is in a battle" where that player stood; Enter
# there asks "Join Battle?", and a Yes joins at the start of the next turn.
#
# Rewards: EXP is everyone's (shared); the gold the battle gives goes to each player.
extends RefCounted

# Data, not code: mods can change them.
const PULL_RANGE := 160.0      # pixels between characters for a player to be pulled in (default)
const JOIN_RANGE := 48.0       # how close to the spot to ask to join
const REVIVE_TURNS := 3
const REVIVE_PART := 0.3
const REVIVE_SAFE := 90.0      # frames of invulnerability after a Revive
# Co-op Difficulty Scaling (a setting, off by default): enemies get this much more HP for each
# player past the first.
const SCALE_PER_PLAYER := 0.5
const BATTLE_ROOMS := ["room_battle"]   # rooms a battle is shared in (Flowey's first is a scene)
# Objects whose "obj_heart" is the SOUL of the player whose turn it is (the battle's own
# bookkeeping), not a target to aim at.
const AIM_SKIP := ["obj_battlecontroller", "obj_heart", "obj_lborder", "obj_rborder", "obj_uborder",
	"obj_dborder", "OBJ_WRITER", "OBJ_INSTAWRITER", "obj_time", "obj_shaker"]
const ENTER := 13


class Battle:
	var first := -1        # whose battle it was (the lead again when it ends)
	var down := {}         # player -> turns spent down
	var turn := -1.0       # the game's global.turn last seen
	var joining: Array = []    # players who said Yes, joining at the next turn
	var gold := []         # [lead, their gold] last frame
	var revive_sel := false
	var scale := 1.0       # how much the enemies' HP has been raised (Co-op Difficulty Scaling)


var eng
var vm
var mp
var obj_heart := -1
var pull_range := PULL_RANGE   # 0: nobody is pulled in (solo-only fights)
var battles := {}          # Room (mp_rooms.gd) -> Battle
var _moves: Array = []     # [player, Room]: joins to make after this frame's worlds ran
var told: Array = []       # for the checks: what happened ("down Greg", "revive Greg", "turn Greg")


func setup(e) -> void:
	eng = e
	vm = e.vm
	mp = e.mp
	obj_heart = int(vm.obj_index.get("obj_heart", -1))
	if obj_heart >= 0:
		vm.faded_objs[obj_heart] = true
		vm.aim_obj = obj_heart
	vm.party_draw = _draw
	vm.party_name = func() -> String: return mp.list[eng.mprooms.cur.lead].name


func _log(s: String) -> void:
	told.append(s)
	if eng.mprooms.log_on:
		print("BATTLE f=%d %s" % [eng.frames, s])


func _g(k: String, d = 0.0):
	return vm.globals.get(k, d)


func is_battle_room(k: int) -> bool:
	return k >= 0 and k < vm.room_names.size() and BATTLE_ROOMS.has(String(vm.room_names[k]))


# ---------------------------------------------------------------- pulling in

# Player p's encounter takes them to room `to`: the players in the same world close enough and
# free to fight with them.
func pull_in(p: int, to: int) -> Array:
	var out: Array = []
	if not is_battle_room(to):
		return out
	var me = mp.list[p].inst
	if me == null or me.dead:
		return out
	var at := Vector2(float(me.v["x"]), float(me.v["y"]))
	for m in eng.mprooms.cur.members:
		if m == p or not mp.list[m].active:
			continue
		var c = mp.list[m].inst
		if c == null or c.dead or not _free(m):
			continue
		if Vector2(float(c.v["x"]), float(c.v["y"])).distance_to(at) <= pull_range:
			out.append(m)
	return out


func _free(m: int) -> bool:
	if eng.mpui.busy(m):
		return false
	return float(mp.value(m, "interact", 0.0)) == 0.0 and float(mp.value(m, "menuno", -1.0)) < 0.0


# ---------------------------------------------------------------- each frame of a battle world

# Before the world's step (mp_players.gd, after everyone's keys were read).
func before_step() -> void:
	var r = eng.mprooms.cur
	var b = battles.get(r)
	if b == null:
		return
	_revive_keys(b)


# After the world's step (mp_players.gd).
func after_step() -> void:
	var r = eng.mprooms.cur
	var b = battles.get(r)
	if not is_battle_room(vm.room):
		if b != null:
			battles.erase(r)
		return
	if b == null:
		if r.members.size() < 2:
			return
		b = Battle.new()
		b.turn = float(_g("turn"))
		battles[r] = b
	if b.first < 0:
		b.first = r.lead
	if not vm.party_on:
		if r.members.size() < 2:
			_new_turn(r, b)     # one player so far: others join at the next turn
			return
		_start(r)
	for m in b.down.keys():
		if not r.members.has(m):
			b.down.erase(m)
	_hearts(r, b)
	_scale(r, b)
	_downs(r, b)
	_new_turn(r, b)
	_share_gold(r, b)
	_visibility(r, b)
	if b.revive_sel:
		var lh = _heart_of(r.lead)
		if lh != null:
			lh.v["y"] = _row_y(_mercy_rows())


func _start(r) -> void:
	mp.set_party(true)
	if vm.aim_skip.is_empty():
		for n in AIM_SKIP:
			if vm.obj_index.has(n):
				vm.aim_skip[int(vm.obj_index[n])] = true
	_log("party %s" % ",".join(r.members.map(func(m): return mp.list[m].name)))


func _hearts_now() -> Array:
	var out: Array = []
	for i in vm.instances:
		if not i.dead and i.obj == obj_heart:
			out.append(i)
	return out


# Player p's SOUL in shared battle world r, loaded or not (mp_net.gd predicts its movement).
func heart_for(p: int, r, here: bool):
	if not battles.has(r):
		return null
	var list: Array = vm.instances if here else r.w.vm_state.get("instances", [])
	for i in list:
		if not i.dead and i.obj == obj_heart and i.owner == p:
			return i
	return null


func _heart_of(p: int):
	for i in _hearts_now():
		if i.owner == p:
			return i
	return null


# Every player up has their own SOUL: the room's own one is the lead's, the others are copies
# of it (copied, not created: obj_heart's Create resets the battle menu).
func _hearts(r, b: Battle) -> void:
	var hs := _hearts_now()
	if hs.is_empty():
		return
	var src = null
	for h in hs:
		if h.owner >= 0 and (not r.members.has(h.owner) or b.down.has(h.owner)):
			h.dead = true      # left the battle, or down
			vm.inst_version += 1
			continue
		if h.owner < 0:
			h.owner = r.lead
		if src == null or h.owner == r.lead:
			src = h
	if src == null:
		return
	for m in r.members:
		if b.down.has(m) or _heart_of(m) != null:
			continue
		var h = vm.instance_create(float(src.v["x"]), float(src.v["y"]), obj_heart, false)
		for k in src.v:
			var val = src.v[k]
			h.v[k] = val.duplicate(true) if val is Array or val is Dictionary else val
		h.alarm = src.alarm.duplicate()
		h.owner = m
	for h in _hearts_now():
		vm.inst_keys[h.id] = mp.list[h.owner].keys


func scaling_on() -> bool:
	return bool(eng.settings.get("multiplayer/difficulty_scaling", false)) or OS.get_cmdline_user_args().has("--mpscale")


# Co-op Difficulty Scaling: the enemies' HP (and max HP) raised for the players in the battle,
# again when someone joins.
func _scale(r, b: Battle) -> void:
	if not scaling_on():
		return
	var want := 1.0 + SCALE_PER_PLAYER * float(r.members.size() - 1)
	if want <= b.scale:
		return
	var f: float = want / b.scale
	for k in ["monstermaxhp", "monsterhp"]:
		var a = _g(k, null)
		if a is Array and not a.is_empty() and a[0] is Array:
			var row: Array = a[0]
			for i in row.size():
				if float(row[i]) > 0.0:
					row[i] = ceilf(float(row[i]) * f)
	b.scale = want
	_log("scaled x%s" % want)


# A SOUL of someone whose turn it isn't is seen while dodging only (in the menu the lead's SOUL
# is the cursor).
func _visibility(r, b: Battle) -> void:
	var lh = _heart_of(r.lead)
	var seen := 0.0
	if lh != null and float(_g("mnfight")) != 0.0:
		seen = float(lh.v.get("visible", 1.0))
	for h in _hearts_now():
		if h != lh:
			h.v["visible"] = seen


func _alive(r, b: Battle) -> Array:
	return r.members.filter(func(m): return mp.list[m].active and not b.down.has(m))


func _downs(r, b: Battle) -> void:
	for m in r.members.duplicate():
		if b.down.has(m) or float(mp.value(m, "hp", 1.0)) > 0.0:
			continue
		var others := _alive(r, b).filter(func(o): return o != m)
		if others.is_empty():
			return     # the last one standing: Undertale's own game over
		b.down[m] = 0
		var h = _heart_of(m)
		if h != null:
			h.dead = true
			vm.inst_version += 1
		_log("down %s" % mp.list[m].name)
		eng.mpsaves.tell_all("%s is down!" % mp.list[m].name)
		if m == r.lead:
			_set_lead(r, _next_up(r, b, m))


func _next_up(r, b: Battle, after: int) -> int:
	var order: Array = r.members
	var k := order.find(after)
	for d in range(1, order.size() + 1):
		var m: int = order[(k + d) % order.size()]
		if mp.list[m].active and not b.down.has(m):
			return m
	return after


func _set_lead(r, p: int) -> void:
	if p == r.lead:
		return
	r.lead = p
	eng.mprooms._apply_people(r)
	mp.switch_to(-1)
	_log("turn %s" % mp.list[p].name)


# A new menu turn (the game counts global.turn): the next player up has it, the downed count
# it, and players who asked to join come in.
func _new_turn(r, b: Battle) -> void:
	var t := float(_g("turn"))
	if t == b.turn or float(_g("myfight")) != 0.0 or float(_g("mnfight")) != 0.0:
		return
	b.turn = t
	b.revive_sel = false
	for m in b.down:
		b.down[m] += 1
	_set_lead(r, _next_up(r, b, r.lead))
	for q in b.joining:
		_moves.append([q, r])
	b.joining.clear()


# The gold a battle gives goes to every player in it (the game gives it to its lead).
func _share_gold(r, b: Battle) -> void:
	var g := float(mp.value(r.lead, "gold", 0.0))
	if b.gold.size() == 2 and int(b.gold[0]) == r.lead and g > float(b.gold[1]):
		var d: float = g - float(b.gold[1])
		for m in r.members:
			if m != r.lead:
				mp.set_value(m, "gold", float(mp.value(m, "gold", 0.0)) + d)
	b.gold = [r.lead, g]


# The battle world leaves its battle room for room `to` (mp_rooms.gd, before anyone moves).
func ending(r, to: int) -> void:
	var b = battles.get(r)
	if b == null:
		return
	var over: bool = eng.mprooms._is_gameover(to)
	if not over:
		for m in b.down:
			mp.set_value(m, "hp", 1.0)
	if b.first >= 0 and r.members.has(b.first):
		_set_lead(r, b.first)
	mp.set_party(false)
	battles.erase(r)
	_log("end %s" % ("game over" if over else "won"))


# ---------------------------------------------------------------- joining

# Player p's keys (mp_players.gd before_step): Enter by the spot of a battle in this room asks
# to join it.
func filter(p) -> void:
	if not p.keys.pressed(ENTER) or eng.mpui.busy(p.index) or not _free(p.index):
		return
	var r = eng.mprooms.room_of(p.index)
	if r == null or r != eng.mprooms.cur or eng.mprooms._private_room(vm.room) or p.inst == null or p.inst.dead:
		return
	var at := Vector2(float(p.inst.v["x"]), float(p.inst.v["y"]))
	for s in spots():
		if s[1].distance_to(at) <= JOIN_RANGE:
			p.keys.clear(ENTER)
			var who: String = mp.list[s[0]].name
			var br = s[2]
			eng.mpui.ask(p.index, ["* %s is in a battle." % who, "* Join Battle?"], _join.bind(p.index, br))
			return


func _join(yes: bool, q: int, br) -> void:
	if not yes or not eng.mprooms.rooms.has(br):
		return
	var b = battles.get(br)
	if b == null:
		# One player in it so far: it becomes shared when the joiner comes in.
		b = Battle.new()
		b.turn = float(mp.value(br.lead, "turn", -1.0))
		battles[br] = b
	if not b.joining.has(q):
		b.joining.append(q)
	eng.mpsaves.tell(q, "You'll join at the next turn.")


# Battles going on whose players stood in the loaded world's room: [player, where, battle world].
func spots() -> Array:
	var out: Array = []
	for br in eng.mprooms.rooms:
		if br == eng.mprooms.cur or not is_battle_room(eng.mprooms.room_index(br)):
			continue
		for m in br.members:
			var bk = mp.list[m].back
			if bk is Array and bk.size() >= 3 and int(bk[0]) == vm.room and not (bk[1] is String):
				out.append([m, Vector2(float(bk[1]), float(bk[2])), br])
				break
	return out


# After every world's frame (engine.gd): joins.
func end_frame() -> void:
	var rooms = eng.mprooms
	for m in _moves:
		var q: int = m[0]
		var br = m[1]
		var src = rooms.room_of(q)
		if src == null or src == br or not rooms.rooms.has(br) or not mp.list[q].active:
			continue
		var keep = rooms.cur
		rooms.switch(src)
		_log("join %s" % mp.list[q].name)
		rooms._send(q, rooms.room_index(br), br)
		rooms.switch(keep)
	_moves.clear()


# ---------------------------------------------------------------- Revive (in MERCY)

func _to_revive(b: Battle) -> int:
	var best := -1
	for m in b.down:
		if best < 0 or int(b.down[m]) > int(b.down[best]):
			best = m
	return best


func _revive_shown(b: Battle) -> bool:
	return not b.down.is_empty() and float(_g("myfight")) == 0.0 and float(_g("mnfight")) == 0.0 \
		and float(_g("bmenuno")) == 4.0


func _mercy_rows() -> int:
	return 1 if float(_g("mercy")) >= 1.0 else 2


func _bm(i: int) -> float:
	var a = _g("bmenucoord", [[0.0]])
	if a is Array and not a.is_empty() and a[0] is Array and (a[0] as Array).size() > i:
		return float(a[0][i])
	return 0.0


func _set_bm(i: int, v: float) -> void:
	var a = _g("bmenucoord", [[0.0]])
	if a is Array and not a.is_empty() and a[0] is Array and (a[0] as Array).size() > i:
		a[0][i] = v


func _snd(n: String) -> void:
	if vm.consts.has(n):
		eng.bi.play_sound(int(vm.consts[n]), false)


# The lead's keys before the game sees them: Down / Up move onto and off "Revive", and Z on it
# revives instead of reaching the game.
func _revive_keys(b: Battle) -> void:
	if not _revive_shown(b):
		b.revive_sel = false
		return
	var k = mp.list[eng.mprooms.cur.lead].keys
	var coord := _bm(4)
	if not b.revive_sel:
		if k.pressed(40) and coord >= float(_mercy_rows() - 1):
			b.revive_sel = true
			k.clear(40)
			_snd("snd_squeak")
		elif k.pressed(38) and coord == 0.0:
			b.revive_sel = true
			k.clear(38)
			_snd("snd_squeak")
		return
	for c in [38, 40]:
		if k.pressed(c):
			b.revive_sel = false
			_set_bm(4, float(_mercy_rows() - 1) if c == 38 else 0.0)
			_snd("snd_squeak")
	for c in [37, 38, 39, 40]:
		if k.held(c):
			k.clear(c)
	if k.pressed(90) or k.pressed(ENTER):
		k.clear(90)
		k.clear(ENTER)
		var m := _to_revive(b)
		if m >= 0 and int(b.down[m]) >= REVIVE_TURNS:
			_revive(b, m)


func _revive(b: Battle, m: int) -> void:
	b.down.erase(m)
	b.revive_sel = false
	var mx := float(mp.value(m, "maxhp", 20.0))
	var hp := maxf(1.0, ceilf(mx * REVIVE_PART))
	mp.set_value(m, "hp", hp)
	# Back up in time for the enemy's attack: a moment safe from it, as after a hit (the SOUL
	# flashes meanwhile), so they live to take their own turn.
	mp.set_value(m, "invc", REVIVE_SAFE)
	var who: String = mp.list[m].name.replace("\"", "'")
	_log("revive %s" % mp.list[m].name)
	vm.run_source("""with (OBJ_WRITER) halt = 3;
with (OBJ_INSTAWRITER) halt = 3;
global.typer = 1;
global.msc = 0;
global.msg[0] = "* You helped %s back up!&* %s recovered %d HP!/%%";
instance_create(global.idealborder[0], global.idealborder[2], OBJ_WRITER);
global.myfight = 4;
obj_heart.x = -200;
snd_play(snd_heal_c);
control_clear(0);""" % [who, who, int(hp)])


func _row_y(row: int) -> float:
	return float(vm.call_script("scr_battlemenu_cursor_y", [float(row)], {"self": null, "other": null, "locals": {}, "args": []}))


# ---------------------------------------------------------------- drawing

# After the room's drawing (gml_vm.gd party_draw), into the world's picture: what each player
# sees of the party on their own screen (tagged theirs), and "<name> is in a battle" in the
# rooms they left.
func _draw() -> void:
	var rooms = eng.mprooms
	if rooms == null:
		return
	var r = rooms.cur
	var rec = eng.bi.canvas
	if rec == null or not rec.has_method("owner"):
		return
	var bi = eng.bi
	var keep: Array = [bi.draw_font, bi.halign, bi.valign, bi.draw_color, bi.draw_alpha]
	var b = battles.get(r)
	if b != null and is_battle_room(vm.room):
		if vm.party_on:
			_draw_party(r, b, rec)
	elif not rooms._private_room(vm.room):
		var sp := spots()
		if not sp.is_empty():
			rec.owner(-900000, Vector2.ZERO, -1)
			for s in sp:
				var t := "%s is in a battle" % mp.list[s[0]].name
				bi.draw_font = int(vm.consts.get("fnt_small", -1.0))
				var w: float = bi.text_width(t)
				_text(s[1].x + 10.0 - w / 2.0, s[1].y - 14.0, t, 16777215, "fnt_small", 1.0)
	bi.draw_font = keep[0]
	bi.halign = keep[1]
	bi.valign = keep[2]
	bi.draw_color = keep[3]
	bi.draw_alpha = keep[4]


func _draw_party(r, b: Battle, rec) -> void:
	var lead: int = r.lead
	var mx := float(_g("maxhp", 20.0))
	for me in r.members:
		rec.owner(-900001 - me, Vector2.ZERO, me)
		# Everyone else's HP, top-right (the lead's is the game's own, at the bottom; the
		# engine's notices are top-left).
		var y := 8.0
		for m in r.members:
			if m == lead:
				continue
			var line := "%s  HP %d/%d" % [mp.list[m].name, int(mp.value(m, "hp", 0.0)), int(float(mp.value(m, "maxhp", mx)))]
			var col := 16777215
			if b.down.has(m):
				var left: int = REVIVE_TURNS - int(b.down[m])
				line = "%s  DOWN" % mp.list[m].name + (("  revive in %d" % left) if left > 0 else "  can be revived")
				col = 4210943   # red (BGR)
			_text_right(630.0, y, line, col)
			y += 22.0
		if me != lead and float(_g("myfight")) == 0.0 and float(_g("mnfight")) == 0.0:
			_text_right(630.0, y, "%s's turn" % mp.list[lead].name, 65535)
		# The others' SOULs get their names.
		if float(_g("mnfight")) != 0.0:
			for h in _hearts_now():
				if h.owner == me or h.owner < 0 or float(h.v.get("visible", 1.0)) < 0.5:
					continue
				var nm: String = mp.list[h.owner].name
				eng.bi.draw_font = int(vm.consts.get("fnt_small", -1.0))
				var w: float = eng.bi.text_width(nm)
				_text(float(h.v["x"]) + 8.0 - w / 2.0, float(h.v["y"]) - 12.0, nm, 16777215, "fnt_small", 1.0)
	# MERCY: the Revive row (everyone sees the menu of the player whose turn it is).
	if _revive_shown(b):
		rec.owner(-900010, Vector2.ZERO, -1)
		var m := _to_revive(b)
		var ib = _g("idealborder", [[32.0]])
		var bx: float = float(ib[0][0]) if ib is Array and not ib.is_empty() and ib[0] is Array else 32.0
		var t: String = "*  Revive  " + mp.list[m].name
		var ready: bool = int(b.down[m]) >= REVIVE_TURNS
		if not ready:
			t += " (%d)" % (REVIVE_TURNS - int(b.down[m]))
		_text(bx + 68.0, _row_y(_mercy_rows()) - 6.0, t, 16777215 if ready else 8421504, "fnt_main", 1.0)


func _text_right(right: float, y: float, s: String, col: int) -> void:
	eng.bi.draw_font = int(vm.consts.get("fnt_small", -1.0))
	_text(right - eng.bi.text_width(s) * 2.0, y, s, col, "fnt_small", 2.0)


func _text(x: float, y: float, s: String, col: int, font: String, sc: float) -> void:
	var bi = eng.bi
	bi.draw_font = int(vm.consts.get(font, vm.consts.get("fnt_small", -1.0)))
	bi.halign = 0
	bi.valign = 0
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		bi._draw_text(x + o.x, y + o.y, s, sc, sc, 0.0, 0, 1.0)
	bi._draw_text(x, y, s, sc, sc, 0.0, col, 1.0)
