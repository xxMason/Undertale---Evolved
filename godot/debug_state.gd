# Snapshots of the whole running game for the debug menu's quick save/load and undo: every
# instance with its variables and alarms, the globals, data structures, the room's views,
# backgrounds and tiles, kept rooms, and the random generator. Sounds aren't kept: after a
# load the music that was playing goes on playing.
extends RefCounted

const VM = preload("res://gml/gml_vm.gd")


static func capture(vm, bi, eng) -> Dictionary:
	var snaps := {}
	for r in vm.room_snapshots:
		var s: Dictionary = vm.room_snapshots[r]
		snaps[r] = {"instances": _clone_list(vm, s["instances"]), "state": _dup_state(s["state"])}
	return {
		"instances": _clone_list(vm, vm.instances),
		"globals": vm.globals.duplicate(true),
		"next_id": vm.next_id,
		"room": vm.room,
		"room_size": [vm.room_width, vm.room_height, vm.room_speed],
		"room_snapshots": snaps,
		"room_state": _dup_state(bi.room_state_save()),
		"maps": bi.maps.duplicate(true),
		"lists": bi.lists.duplicate(true),
		"next_ds": bi.next_ds,
		"room_persist": bi.room_persist.duplicate(true),
		"next_tile_id": bi.next_tile_id,
		"rng": [bi.rng.state.duplicate(), bi.rng.index, bi.rng.seed_value],
		"frames": eng.frames,
		"room_name": vm.room_names[vm.room] if vm.room >= 0 else "-",
		"time": Time.get_time_string_from_system(),
	}


static func restore(vm, bi, eng, s: Dictionary) -> void:
	vm.instances = _clone_list(vm, s["instances"])
	vm.by_id.clear()
	for i in vm.instances:
		vm.by_id[i.id] = i
	vm.globals = (s["globals"] as Dictionary).duplicate(true)
	vm.next_id = s["next_id"]
	vm.room = s["room"]
	vm.room_width = s["room_size"][0]
	vm.room_height = s["room_size"][1]
	vm.room_speed = s["room_size"][2]
	vm.pending_room = -1
	var snaps := {}
	for r in s["room_snapshots"]:
		var rs: Dictionary = s["room_snapshots"][r]
		snaps[r] = {"instances": _clone_list(vm, rs["instances"]), "state": _dup_state(rs["state"])}
	vm.room_snapshots = snaps
	bi.room_state_restore(_dup_state(s["room_state"]))
	bi.maps = (s["maps"] as Dictionary).duplicate(true)
	bi.lists = (s["lists"] as Dictionary).duplicate(true)
	bi.next_ds = s["next_ds"]
	bi.room_persist = (s["room_persist"] as Dictionary).duplicate(true)
	bi.next_tile_id = s["next_tile_id"]
	bi.rng.state = (s["rng"][0] as PackedInt64Array).duplicate()
	bi.rng.index = s["rng"][1]
	bi.rng.seed_value = s["rng"][2]
	# Every cache keyed on the set of live instances.
	vm.inst_version += 1
	vm._resolve_cache = {}
	vm._io_key = []
	vm._bo_src = []
	eng.frames = s["frames"]


static func _dup_state(st: Dictionary) -> Dictionary:
	var arr := {}
	for k in st["arr"]:
		arr[k] = (st["arr"][k] as Array).duplicate(true)
	var out := st.duplicate()
	out["arr"] = arr
	out["tiles"] = (st["tiles"] as Array).duplicate(true)
	return out


static func _clone_list(vm, list: Array) -> Array:
	var out: Array = []
	for i in list:
		if i.dead:
			continue
		var c = VM.Inst.new()
		c.id = i.id
		c.obj = i.obj
		c.v = i.v.duplicate(true)
		c.alarm = i.alarm.duplicate()
		c.created = i.created
		c.born = i.born
		c.drawn = -1
		out.append(c)
	return out
