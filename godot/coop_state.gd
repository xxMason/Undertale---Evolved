# The whole running game as bytes, for co-op: the host sends it when a friend joins (and
# again if the two PCs ever drift apart), so both run the same frames from the same state.
# Builds on debug_state.gd (instances, globals, room, data structures, random generator)
# and adds what a second PC also needs: the frame clock, key history, open ini data, sound
# ids and the sounds playing, so that "is this sound playing?" agrees on both PCs.
extends RefCounted

const VM = preload("res://gml/gml_vm.gd")
const DebugState = preload("res://debug_state.gd")


static func _inst_out(list: Array) -> Array:
	var out: Array = []
	for i in list:
		out.append([i.id, i.obj, i.v, i.alarm, i.created, i.born])
	return out


static func _inst_in(list: Array) -> Array:
	var out: Array = []
	for a in list:
		var c = VM.Inst.new()
		c.id = a[0]
		c.obj = a[1]
		c.v = a[2]
		c.alarm = a[3]
		c.created = a[4]
		c.born = a[5]
		out.append(c)
	return out


static func pack(eng) -> Dictionary:
	var vm = eng.vm
	var bi = eng.bi
	var s: Dictionary = DebugState.capture(vm, bi, eng)
	s["instances"] = _inst_out(s["instances"])
	for r in s["room_snapshots"]:
		s["room_snapshots"][r]["instances"] = _inst_out(s["room_snapshots"][r]["instances"])
	# Undertale's text tables are the same on both PCs and never change: not sent, rebuilt there.
	(s["maps"] as Dictionary).erase(int(eng.text_map))
	var tmaps := {}
	for g in ["text_data_en", "text_data_ja"]:
		var id := int(vm.globals.get(g, -1.0))
		if id >= 0 and id != int(eng.text_map) and (s["maps"] as Dictionary).has(id):
			(s["maps"] as Dictionary).erase(id)
			tmaps[g] = id
	s["text_maps"] = tmaps
	s["step_no"] = vm.step_no
	s["game_started"] = vm.game_started
	s["next_sound_id"] = bi.next_sound_id
	s["asset_gain"] = bi.asset_gain.duplicate()
	s["asset_pitch"] = bi.asset_pitch.duplicate()
	s["draw"] = [bi.draw_color, bi.draw_alpha, bi.draw_font, bi.halign, bi.valign]
	s["keyboard_string"] = bi.keyboard_string
	s["ini"] = [bi.ini_path.get_file(), bi.ini_data.duplicate(true), bi.ini_dirty]
	s["next_file_id"] = bi.next_file_id
	s["keys"] = [eng.keys.now.duplicate(), eng.keys.prev.duplicate(), eng.keys.cleared.duplicate(), eng.keys.sim.duplicate()]
	var snd: Array = []
	for p in bi.players:
		if not bi._alive(p):
			continue
		var e: Dictionary = p.duplicate()
		e.erase("player")
		e["pitch"] = p["player"].pitch_scale
		snd.append(e)
	s["sounds"] = snd
	s["partner"] = eng.partner.to_dict() if eng.partner != null else {}
	var raw := var_to_bytes(s)
	return {"z": raw.compress(FileAccess.COMPRESSION_ZSTD), "n": raw.size()}


# Puts the state into this PC's game. The save folder stays this PC's own.
static func unpack(eng, pk: Dictionary) -> void:
	var vm = eng.vm
	var bi = eng.bi
	var s: Dictionary = bytes_to_var((pk["z"] as PackedByteArray).decompress(int(pk["n"]), FileAccess.COMPRESSION_ZSTD))
	s["instances"] = _inst_in(s["instances"])
	for r in s["room_snapshots"]:
		s["room_snapshots"][r]["instances"] = _inst_in(s["room_snapshots"][r]["instances"])
	var tm := int(eng.text_map)
	if bi.maps.has(tm):
		s["maps"][tm] = bi.maps[tm]
	DebugState.restore(vm, bi, eng, s)
	for g in s.get("text_maps", {}):
		_rebuild_text(eng, g, int(s["text_maps"][g]))
	vm.step_no = s["step_no"]
	vm.game_started = s["game_started"]
	bi.next_sound_id = s["next_sound_id"]
	bi.asset_gain = s["asset_gain"]
	bi.asset_pitch = s["asset_pitch"]
	var d: Array = s["draw"]
	bi.draw_color = d[0]
	bi.draw_alpha = d[1]
	bi.draw_font = d[2]
	bi.halign = d[3]
	bi.valign = d[4]
	bi.keyboard_string = s["keyboard_string"]
	var ini: Array = s["ini"]
	bi.ini_path = bi.save_dir.path_join(ini[0]) if ini[0] != "" else ""
	bi.ini_data = ini[1]
	bi.ini_dirty = ini[2]
	bi.next_file_id = s["next_file_id"]
	var k: Array = s["keys"]
	eng.keys.now = k[0]
	eng.keys.prev = k[1]
	eng.keys.cleared = k[2]
	eng.keys.sim = k[3]
	var pd: Dictionary = s.get("partner", {})
	if pd.is_empty():
		eng.partner = null
	else:
		eng.partner = eng.CoopPartner.new()
		eng.partner.setup(eng)
		eng.partner.from_dict(pd)
	# The sounds: same ids, same place in the song.
	for p in bi.players:
		p["player"].stop()
		p["player"].queue_free()
	bi.players.clear()
	for e in s["sounds"]:
		var st = bi._stream(int(e["sound"]))
		if st == null:
			continue
		var stream = st.duplicate() if e.get("loop", false) else st
		if e.get("loop", false):
			if stream is AudioStreamOggVorbis:
				stream.loop = true
			elif stream is AudioStreamWAV:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_end = int(stream.get_length() * stream.mix_rate)
		var pl := AudioStreamPlayer.new()
		pl.stream = stream
		pl.pitch_scale = float(e.get("pitch", 1.0))
		bi.audio_root.add_child(pl)
		var entry: Dictionary = e.duplicate()
		entry.erase("pitch")
		entry["player"] = pl
		bi.players.append(entry)
		bi._apply_volume(entry)
		var el: int = (int(e["pa"]) if e["paused"] and int(e.get("pa", -1)) >= 0 else vm.step_no) - int(e.get("t0", 0)) - int(e.get("pt", 0))
		var at: float = el / 30.0 * pl.pitch_scale
		var ln: float = stream.get_length()
		if ln > 0.0:
			at = fmod(at, ln) if e.get("loop", false) else minf(at, ln)
		pl.play(at)
		if e["paused"]:
			pl.stream_paused = true


# A fingerprint of the game state, compared between the PCs every second.
static func checksum(eng) -> int:
	var vm = eng.vm
	var parts: Array = [vm.room, vm.step_no, vm.next_id, eng.bi.rng.index, vm.instances.size()]
	for g in ["plot", "hp", "maxhp", "xp", "gold", "lv", "interact", "kills", "turn", "mnfight", "myfight", "bmenuno"]:
		parts.append(vm.globals.get(g, 0.0))
	if eng.partner != null:
		parts.append(eng.partner.to_dict())
	for i in vm.instances:
		if i.dead:
			continue
		parts.append(i.id)
		parts.append(i.obj)
		parts.append(snappedf(float(i.v.get("x", 0.0)), 0.01))
		parts.append(snappedf(float(i.v.get("y", 0.0)), 0.01))
		parts.append(i.v.get("sprite_index", 0.0))
	return str(parts).hash()


# A text table the game made (global.text_data_en / _ja), rebuilt under the same map id.
static func _rebuild_text(eng, g: String, id: int) -> void:
	var vm = eng.vm
	var bi = eng.bi
	if g == "text_data_en" and bi.maps.has(int(eng.text_map)):
		bi.maps[id] = bi.maps[int(eng.text_map)]
		return
	var keep_ds: int = bi.next_ds
	var keep_g = vm.globals.get(g)
	var ctx := {"self": vm.instances[0] if not vm.instances.is_empty() else null, "other": null, "locals": {}, "args": []}
	ctx["other"] = ctx["self"]
	vm.call_script(g.replace("text_data_", "textdata_"), [], ctx)
	var made := int(vm.globals.get(g, -1.0))
	if made >= 0 and bi.maps.has(made):
		bi.maps[id] = bi.maps[made]
		if made != id:
			bi.maps.erase(made)
	vm.globals[g] = keep_g
	bi.next_ds = keep_ds