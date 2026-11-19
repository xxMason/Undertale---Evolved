# Players in different rooms (docs/MULTIPLAYER.md, stage 5).
#
# Every room with a player in it is a running world (gml_world.gd) on the host. Each world
# has a lead: the player whose values the room's own objects see (its view, its doors' and
# cutscenes' "player"). A world's other members are in it as well, with their own character.
#
# A door goes through room_goto. When the door was used for one player and others stay
# behind, only that player goes: their character (and anything persistent they own, like the
# fader of the door) leaves this world and joins the world already running the room they go
# to, or a new world that loads it with them as lead. When everyone in a world leaves together
# (a door with one player in the room, or a cutscene moving the room), the world itself
# changes room as in the one-player game, or, if another world already runs that room, its
# players join that world and this one ends.
#
# Story flags, the save file and parked persistent rooms are shared by all worlds.
extends RefCounted

const World = preload("res://gml/gml_world.gd")
const Recorder = preload("res://gml/gml_recorder.gd")


class Room:
	var w                      # gml_world.gd
	var lead := 0              # player index
	var members: Array = []    # player indices, the lead included
	var rec                    # gml_recorder.gd: this world's picture this frame


var eng
var vm
var mp
var rooms: Array = []
var cur: Room = null           # the world loaded in the machine right now
var _next := 1
var log_on := false


func setup(e) -> void:
	eng = e
	vm = e.vm
	mp = e.mp
	log_on = OS.get_cmdline_user_args().has("--roomlog")
	var r := Room.new()
	r.w = World.from_current(vm)
	r.lead = mp.primary
	for p in mp.list:
		if p.active:
			r.members.append(p.index)
	r.rec = eng.rec
	rooms = [r]
	cur = r


func _log(s: String) -> void:
	if log_on:
		print("ROOMS f=%d %s" % [eng.frames, s])


func room_of(p: int) -> Room:
	for r in rooms:
		if r.members.has(p):
			return r
	return null


func room_index(r: Room) -> int:
	return vm.room if r == cur else int(r.w.vm_state.get("room", -1))


# Player p goes to player `to`'s room, beside them (a story event they said Yes to).
func teleport(p: int, to: int) -> void:
	var src := room_of(p)
	var dst := room_of(to)
	if src == null or dst == null or src == dst or _private_room(room_index(dst)):
		return
	var k := room_index(dst)
	var keep: int = vm.ctx_owner
	switch(src)
	var ti = mp.list[to].inst
	if ti != null and not ti.dead:
		mp.list[p].back = [k, float(ti.v["x"]), float(ti.v["y"]), "beside"]
	_log("%s teleports to %s in %s" % [mp.list[p].name, mp.list[to].name, vm.room_names[k]])
	_send(p, k)
	mp.switch_to(keep)


func room_name(r: Room) -> String:
	if r == null:
		return "-"
	var k: int = vm.room if r == cur else int(r.w.vm_state.get("room", -1))
	return vm.room_names[k] if k >= 0 and k < vm.room_names.size() else "-"


# Loads world r into the machine, with its lead and members.
func switch(r: Room) -> void:
	if r == cur:
		return
	mp.park()
	r.w.use(vm, cur.w)
	cur = r
	_apply_people(r)
	mp.unpark()


func _apply_people(r: Room) -> void:
	mp.primary = r.lead
	vm.primary_owner = r.lead
	var on: Array = []
	for m in r.members:
		if mp.list[m].active:
			on.append(m)
	vm.multi_players = on
	while vm.player_insts.size() < mp.list.size():
		vm.player_insts.append({})
	mp.members = on


# A player joined the game: they start in the host's world.
func joined(p: int) -> void:
	var r := room_of(p)
	if r != null:
		return
	r = room_of(0)
	if r == null:
		r = rooms[0]
	r.members.append(p)
	if r == cur:
		_apply_people(r)


func left(p: int) -> void:
	var r := room_of(p)
	if r == null:
		return
	r.members.erase(p)
	if r.members.is_empty() and rooms.size() > 1:
		_drop(r)
	elif r.lead == p and not r.members.is_empty():
		r.lead = r.members[0]
		if r == cur:
			_apply_people(r)


# Player p is leaving the game: if they lead their world, the next one still in it does.
func hand_over(p: int) -> void:
	var r := room_of(p)
	if r == null or r.lead != p:
		return
	for m in r.members:
		if m != p and mp.list[m].active:
			r.lead = m
			if r == cur:
				_apply_people(r)
			return


# ---------------------------------------------------------------- room changes

# The world in the machine asked for room `to` (room_goto). Returns true when the machine's
# world changed room itself (the caller runs that room's first step, as for one player).
func room_change(to: int) -> bool:
	var p: int = vm.pending_owner
	var r := cur
	# A player downed alone while others play on sees Undertale's game over, then comes back at
	# the last save point instead of loading it (which would take everyone's story back).
	if _is_gameover(to) and not _is_gameover(vm.room) and _others_playing(r):
		for m in r.members:
			mp.list[m].respawn = true
	elif _is_gameover(vm.room) and r.members.any(func(m): return mp.list[m].respawn):
		to = _respawn(r, to)
	# A shared battle ends: everyone leaves it with its state (the downed get up on 1 HP), and a
	# player who joined from another room goes back there.
	var bt = eng.get("mpbattles")
	if bt != null and bt.is_battle_room(vm.room) and to != vm.room:
		if bt.battles.has(r):
			p = -1     # a shared battle: everyone in it leaves together
		bt.ending(r, to)
		if not _private_room(to):
			for m in r.members.duplicate():
				var bk = mp.list[m].back
				if r.members.size() > 1 and bk is Array and int(bk[0]) != to and int(bk[0]) >= 0:
					_log("%s goes back to %s" % [mp.list[m].name, vm.room_names[int(bk[0])]])
					_send(m, int(bk[0]))
	var others: Array = r.members.filter(func(m): return m != p)
	# An encounter pulls in the players close by (mp_battles.gd).
	var pulled: Array = bt.pull_in(p, to) if bt != null and p >= 0 and r.members.has(p) else []
	var stay: Array = others.filter(func(m): return not pulled.has(m))
	if p >= 0 and r.members.has(p) and not stay.is_empty():
		_log("%s goes from %s to %s, %s stay%s" % [mp.list[p].name, room_name(r), vm.room_names[to], stay, (", %s with them" % [pulled]) if not pulled.is_empty() else ""])
		vm.pending_room = -1
		_send(p, to)
		var into := room_of(p)
		for m in pulled:
			_send(m, to, into)
		return false
	var there := _running(to, r)
	if there != null:
		_log("everyone in %s goes to %s, already running" % [room_name(r), vm.room_names[to]])
		vm.pending_room = -1
		var all: Array = r.members.duplicate()
		for m in all:
			_send(m, to)
		return false
	vm.pending_room = -1
	if _private_room(to) and not _private_room(vm.room):
		for m in r.members:
			var c = mp.list[m].inst
			if c != null and not c.dead:
				mp.list[m].back = [vm.room, c.v["x"], c.v["y"]]
	mp.switch_to(-1)
	vm.load_room(to)
	return true


func _running(to: int, not_this: Room) -> Room:
	if _private_room(to):
		return null
	for r in rooms:
		if r == not_this:
			continue
		var k: int = vm.room if r == cur else int(r.w.vm_state.get("room", -1))
		if k == to:
			return r
	return null


func _is_gameover(k: int) -> bool:
	return k >= 0 and k < vm.room_names.size() and vm.room_names[k] != null and String(vm.room_names[k]).begins_with("room_gameover")


# Someone outside world r is still playing (so r's players being downed isn't game over).
func _others_playing(r: Room) -> bool:
	for pl in mp.list:
		if pl.active and not r.members.has(pl.index):
			return true
	return false


# The world in the machine (on the game over screen) sends its downed players back: full HP,
# items as they were, at the room of the last save, by its save point. Returns that room.
func _respawn(r: Room, fallback: int) -> int:
	var go_objs: Array = []
	for nm in ["obj_gameover", "obj_gameoverbg"]:
		if vm.obj_index.has(nm):
			go_objs.append(int(vm.obj_index[nm]))
	for i in vm.instances:
		if not i.dead and go_objs.has(i.obj):
			i.dead = true     # it would load the temporary save in the next room
	vm.inst_version += 1
	eng.bi._f_audio_stop_all("", [], {})
	var room := _last_save_room()
	if room < 0:
		room = fallback
	var keep: int = vm.ctx_owner
	for m in r.members:
		var pl = mp.list[m]
		if not pl.respawn:
			continue
		pl.respawn = false
		mp.switch_to(m)
		vm.globals["hp"] = vm.globals.get("maxhp", 20.0)
		vm.globals["interact"] = 0.0
		pl.back = [room, "save"]
		_log("%s comes back at %s" % [pl.name, vm.room_names[room]])
		eng.mpsaves.tell_all("%s died." % pl.name, m)
	mp.switch_to(keep)
	return room


# The room of the universe's last save (Undertale writes it to undertale.ini).
func _last_save_room() -> int:
	var path: String = eng.bi.save_path("undertale.ini")
	if path == "" or not FileAccess.file_exists(path):
		return -1
	var ini: Dictionary = eng.bi._ini_parse(FileAccess.get_file_as_string(path))
	var v = ini.get("General", {}).get("Room", "")
	if not String(v).is_valid_float():
		return -1
	var k := int(float(v))
	return k if k >= 0 and k < vm.room_names.size() else -1


# Rooms every player gets their own copy of: a battle (players are pulled into one together,
# never by walking in), the game over screen.
func _private_room(k: int) -> bool:
	if k < 0 or k >= vm.room_names.size() or vm.room_names[k] == null:
		return false
	var n := String(vm.room_names[k])
	return n == "room_battle" or n == "room_floweybattle" or n.begins_with("room_gameover")


# Player p goes from the world in the machine to room `to`: to the world `into` (a battle they
# are pulled into or join), else the one running that room, else a new one.
func _send(p: int, to: int, into: Room = null) -> void:
	var from := cur
	var keep_ctx: int = vm.ctx_owner
	# What goes with them: their character is made afresh there (its Create puts it at the
	# door's marker); their persistent things (the door's fader) move; their text boxes close.
	var carry: Array = []
	for i in vm.instances:
		if i.dead or i.owner != p:
			continue
		if i.obj == mp.obj_main:
			if _private_room(to) and not _private_room(vm.room):
				mp.list[p].back = [vm.room, i.v["x"], i.v["y"]]
			i.dead = true
		elif float(i.v.get("persistent", 0.0)) >= 0.5:
			carry.append(i)
		else:
			# Their things in this room (the door's fade to black, text boxes) end as at the
			# end of the room for them.
			i.dead = true
	# The door they went through is ready for the others again (Undertale's doors work once
	# per room: `touched`).
	for i in vm.instances:
		if not i.dead and i.v.has("touched") and String(vm.obj_names[i.obj]).begins_with("obj_door"):
			i.v["touched"] = 0.0
	for i in carry:
		vm.instances.erase(i)
		vm.by_id.erase(i.id)
	vm.claimed = vm.claimed.filter(func(i): return not i.dead and i.owner != p)
	vm.player_insts[p] = {}
	vm.inst_version += 1
	mp.list[p].inst = null
	from.members.erase(p)
	if from.lead == p and not from.members.is_empty():
		from.lead = from.members[0]
	# Everything persistent nobody owns (obj_time, the overworld controller...) exists once in
	# every world: a new world starts with copies of this one's.
	var shared: Array = []
	for i in vm.instances:
		if not i.dead and i.owner < 0 and float(i.v.get("persistent", 0.0)) >= 0.5:
			shared.append(i)
	var to_room := into if into != null and rooms.has(into) else _running(to, from)
	if to_room == null:
		to_room = Room.new()
		to_room.w = World.empty(vm, _next, (eng.bi.rng.next() ^ (_next * 104729)) & 0x7FFFFFFF)
		_next += 1
		to_room.w.bi_state["keys"] = mp.list[p].keys
		var ar := Node.new()
		ar.name = "world_audio_%d" % to_room.w.index
		eng.add_child(ar)
		to_room.w.bi_state["audio_root"] = ar
		to_room.w.bi_state["heard"] = false
		to_room.lead = p
		to_room.members = [p]
		to_room.rec = Recorder.new()
		rooms.append(to_room)
		var clones: Array = []
		for i in shared:
			clones.append(_clone(i))
		switch(to_room)
		vm.player_insts = []
		while vm.player_insts.size() < mp.list.size():
			vm.player_insts.append({})
		vm.claimed = []
		vm.inst_keys = {}
		vm.multi_players = [p]
		for c in clones:
			vm._insert_by_depth(c)
			vm.by_id[c.id] = c
		for c in carry:
			vm._insert_by_depth(c)
			vm.by_id[c.id] = c
		vm.inst_version += 1
		# The room's own objects are nobody's (as for any room); with p the lead, the world's
		# context has their values, and their character is bound to them.
		mp.switch_to(-1)
		vm.load_room(to)
		mp.bind()
		_log("%s starts a world for %s (%d worlds)" % [mp.list[p].name, vm.room_names[to], rooms.size()])
	else:
		to_room.members.append(p)
		switch(to_room)
		for c in carry:
			vm._insert_by_depth(c)
			vm.by_id[c.id] = c
		vm.inst_version += 1
		if _private_room(to):
			# A battle: no character there (their SOUL is made by mp_battles.gd).
			_log("%s joins the world in %s" % [mp.list[p].name, vm.room_names[to]])
			switch(from)
			mp.switch_to(keep_ctx)
			if from.members.is_empty():
				_drop(from)
			return
		# Their character, made in their own context: Undertale's Create puts it at the marker
		# of the door they came through.
		mp.switch_to(p)
		var inst = vm.instance_create(0.0, 0.0, mp.obj_main)
		inst.owner = p
		var lead_inst = mp.list[to_room.lead].inst
		if float(inst.v["x"]) == 0.0 and float(inst.v["y"]) == 0.0 and lead_inst != null and not lead_inst.dead:
			# Not through a door (back from a battle or a game over): beside the lead until put
			# where they belong.
			inst.v["x"] = lead_inst.v["x"]
			inst.v["y"] = lead_inst.v["y"]
		vm.player_insts[p][mp.obj_main] = inst
		mp.list[p].inst = inst
		if p != to_room.lead:
			vm.inst_keys[inst.id] = mp.list[p].keys
		_log("%s joins the world in %s" % [mp.list[p].name, vm.room_names[to]])
	switch(from)
	mp.switch_to(keep_ctx)
	if from.members.is_empty():
		_drop(from)


func _clone(i):
	var c = vm.Inst.new()
	c.id = i.id
	c.obj = i.obj
	c.owner = -1
	c.v = i.v.duplicate(true)
	c.alarm = i.alarm.duplicate()
	c.created = true
	c.born = i.born
	return c


# A world nobody is in any more: a persistent room is parked as when leaving it alone.
func _drop(r: Room) -> void:
	if rooms.size() <= 1:
		return
	var back = cur if cur != r else null
	if back == null:
		for o in rooms:
			if o != r:
				back = o
				break
	switch(r)
	var k: int = vm.room
	if k >= 0 and eng.bi.room_persist.get(k, false):
		var stay: Array = []
		for i in vm.instances:
			if not i.dead and float(i.v.get("persistent", 0.0)) < 0.5 and i.obj != mp.obj_main:
				stay.append(i)
		vm.room_snapshots[k] = {"instances": stay, "state": eng.bi.room_state_save()}
	var ar = eng.bi.audio_root
	_log("the world in %s ends" % room_name(r))
	switch(back)
	rooms.erase(r)
	if ar != null and String(ar.name).begins_with("world_audio_"):
		ar.queue_free()


# ---------------------------------------------------------------- each frame

# The other worlds' frames, after the host's own world has run its frame (engine.gd).
func step_others() -> void:
	var home := cur
	for r in rooms.duplicate():
		if r == home or not rooms.has(r):
			continue
		switch(r)
		mp.before_step()
		var k = eng.bi.keys
		vm.step_frame(k)
		vm.room_frame_end()
		var guard := 0
		while vm.pending_room != -1 and guard < 4:
			guard += 1
			_log("%s asks for %s (for player %d)" % [room_name(r), vm.room_names[vm.pending_room] if vm.pending_room >= 0 else "?", vm.pending_owner])
			if room_change(vm.pending_room):
				vm.step_frame(k)
				vm.room_frame_end()
		if not rooms.has(r) or cur != r:
			continue
		mp.after_step()
		draw(r)
	if rooms.has(home):
		switch(home)


# Records world r's picture (the machine has r loaded).
func draw(r: Room) -> void:
	var bi = eng.bi
	r.rec.clear()
	bi.canvas = r.rec
	if bi.views_on:
		r.rec.view = Vector2(float(bi.view_xview[0]), float(bi.view_yview[0]))
		var wv := maxf(1.0, float(bi.view_wview[0]))
		var hv := maxf(1.0, float(bi.view_hview[0]))
		r.rec.view_scale = Vector2(float(bi.room_arr["view_wport"][0]) / wv, float(bi.room_arr["view_hport"][0]) / hv)
	else:
		r.rec.view = Vector2.ZERO
		r.rec.view_scale = Vector2.ONE
	vm.draw_frame()
	bi.canvas = null


# After everyone's frame: the machine holds the host's world, and the engine's picture is
# that world's.
func settle() -> void:
	var r := room_of(0)
	if r != null and r != cur:
		switch(r)
		_hear_only(r)
	if cur.rec != eng.rec:
		eng.rec = cur.rec


# This PC plays the sounds of the host's world only; the others' go to their players.
func _hear_only(home: Room) -> void:
	for o in rooms:
		var on: bool = o == home
		var bs: Dictionary = o.w.bi_state
		var list: Array = eng.bi.players if o == cur else bs.get("players", [])
		if o == cur:
			eng.bi.heard = on
		else:
			bs["heard"] = on
		for e in list:
			var muted: bool = not on or int(e.get("owner", -1)) > 0
			e["player"].bus = eng.bi._muted_bus() if muted else &"Master"


func status() -> String:
	var parts: Array = []
	for r in rooms:
		var names: Array = []
		for m in r.members:
			names.append(mp.list[m].name + ("*" if m == r.lead else ""))
		parts.append("%s[%s] ops=%d%s" % [room_name(r), ",".join(names), r.rec.ops.size(), " (engine's)" if r.rec == eng.rec else ""])
	return " ".join(parts)
