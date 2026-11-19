# Story scenes with several players (docs/MULTIPLAYER.md, "Story scenes").
#
# Gather scenes (Toriel's, Flowey's...) wait for the party: when a player walks into one while
# others are in other rooms, the scene's trigger does nothing yet, the player sees "Waiting
# for 1 more player..." and everyone elsewhere is asked "Teleport to Story Event?". Yes brings
# them beside the player who found it; No is reported to that player. A player who is busy (a
# menu, a text box, a battle) is asked once they are free. When everyone has answered (or the
# player who found it presses X to go on without them), the trigger works again and the scene
# plays for whoever is there.
#
# Room scenes and personal ones (signs, simple talks, shops) are the rest: they play for the
# players in the room, or the player who started them, as the room's own objects already do.
extends RefCounted

# Data, not code: mods can add their own.
const GATHER := [
	"obj_floweytrigger", "obj_floweytrigger2",
	"obj_torieltrigger1", "obj_torieltrigger2", "obj_torieltrigger4", "obj_torieltrigger5",
	"obj_torieltrigger6", "obj_torieltrigger7", "obj_torieltrigger8", "obj_torieltrigger9",
	"obj_torieltrigger10", "obj_torieltrigger11", "obj_torieltrigger12",
]

# Scenes that start as their room loads (Toriel at the training dummy, in her house): the
# event that starts them waits the same way, and runs once everyone has answered.
const LOAD_GATE := {"obj_torieltrigger3": [7, 4], "obj_torieltrigger6": [0, 0]}   # [event type, sub]: room start, Create

var eng
var vm
var mp
var ui
var gather = null     # the scene waiting now: {"inst", "by", "ask": {player: "asked" / "queued" / "yes" / "no"}, "open"}
var playing := []     # scenes playing: [trigger instance, player, world, frames that player has been free]
var _moves: Array = []   # [player, to player]: teleports to make after this frame's worlds ran


func setup(e) -> void:
	eng = e
	vm = e.vm
	mp = e.mp
	ui = e.mpui
	for nm in GATHER:
		if vm.obj_index.has(nm):
			vm.gate_objs[int(vm.obj_index[nm])] = true
	for nm in LOAD_GATE:
		if vm.obj_index.has(nm):
			vm.load_gate_objs[int(vm.obj_index[nm])] = LOAD_GATE[nm]
	vm.event_gate = gate


# The machine is about to run a story trigger's collision with player p's character.
func gate(inst, p: int) -> bool:
	# A room-load scene held for someone who went ahead (Toriel's house, before her scene in
	# the room before it) gives way to another player's scene: the story goes in order, and
	# the held one plays again when its room next loads.
	if gather != null and gather["inst"] != inst and gather.has("replay") and not gather["open"] and int(gather["by"]) != p:
		_drop_gather()
	if gather != null:
		if gather["inst"] == inst:
			if gather["open"]:
				gather = null      # it runs now, for whoever is here
				_play(inst, p)
				return true
			return false
		return true       # another scene: not held up by this one
	var away := _away(p)
	if away.is_empty():
		_play(inst, p)
		return true
	gather = {"inst": inst, "by": p, "ask": {}, "open": false}
	if vm.load_gate_objs.has(inst.obj):
		# Its start runs again once the party has answered, in this world.
		gather["replay"] = vm.load_gate_objs[inst.obj]
		gather["room"] = eng.mprooms.cur
		if int(gather["replay"][0]) == vm.EV_CREATE:
			inst.v["conversation"] = 0.0     # its Step reads it meanwhile
	for o in away:
		gather["ask"][o] = "queued"
	_ask_free()
	_update_wait()
	return false


# Active players not in player p's world.
func _away(p: int) -> Array:
	var out: Array = []
	var r = eng.mprooms.room_of(p)
	for o in mp.list:
		if o.active and o.index != p and eng.mprooms.room_of(o.index) != r:
			out.append(o.index)
	return out


func _busy(o: int) -> bool:
	if ui.busy(o):
		return true
	var r = eng.mprooms.room_of(o)
	if r != null and eng.mprooms._private_room(eng.mprooms.room_index(r)):
		return true
	return float(mp.value(o, "interact", 0.0)) != 0.0


func _ask_free() -> void:
	var by: String = mp.list[gather["by"]].name
	for o in gather["ask"]:
		if gather["ask"][o] == "queued" and not _busy(o):
			gather["ask"][o] = "asked"
			ui.ask(o, ["* %s found a story event." % by, "* Teleport to Story Event?"], _answer.bind(o))


func _answer(yes: bool, o: int) -> void:
	if gather == null or not gather["ask"].has(o):
		return
	gather["ask"][o] = "yes" if yes else "no"
	if yes:
		_moves.append([o, gather["by"]])
	else:
		eng.mpsaves.tell(gather["by"], "%s said no." % mp.list[o].name)
	_update_wait()


func _left() -> int:
	var n := 0
	for o in gather["ask"]:
		if gather["ask"][o] == "asked" or gather["ask"][o] == "queued":
			n += 1
	return n


func _update_wait() -> void:
	var by: int = gather["by"]
	var n := _left()
	if n == 0:
		gather["open"] = true
		ui.set_wait(by, "")
		return
	ui.set_wait(by, "Waiting for %d more player%s... (X: go on)" % [n, "" if n == 1 else "s"], _go_on)


# The player who found the scene goes on without the ones still to answer.
func _go_on() -> void:
	if gather == null:
		return
	for o in gather["ask"]:
		if gather["ask"][o] == "asked" or gather["ask"][o] == "queued":
			ui.close(o)
			gather["ask"][o] = "no"
	_update_wait()


# The scene plays for everyone in the room: what the player who started it reads (Toriel's
# words) shows on every screen there, until the scene is over (its trigger gone, or that
# player free again for two seconds).
func _play(inst, p: int) -> void:
	for s in playing:
		if s[0] == inst:
			return
	vm.scene_owner = p
	vm.follow_owner = p
	playing.append([inst, p, eng.mprooms.cur, 0])


# Before a world's step (mp_players.gd): a room-load scene everyone has answered for starts.
func before_step() -> void:
	if gather == null or not gather["open"] or not gather.has("replay") or gather["room"] != eng.mprooms.cur:
		return
	var inst = gather["inst"]
	var rp: Array = gather["replay"]
	gather.erase("replay")
	if inst.dead:
		gather = null
		return
	var keep: int = vm.ctx_owner
	mp.switch_to(int(gather["by"]))
	vm.perform_event(inst, int(rp[0]), int(rp[1]), null)
	mp.switch_to(keep)


func _scenes_frame() -> void:
	for s in playing.duplicate():
		var r = s[2]
		var p: int = s[1]
		s[3] = int(s[3]) + 1 if float(mp.value(p, "interact", 0.0)) == 0.0 else 0
		if s[0].dead or not eng.mprooms.rooms.has(r) or eng.mprooms.room_of(p) != r or int(s[3]) > 60:
			playing.erase(s)
			if eng.mprooms.rooms.has(r):
				if r == eng.mprooms.cur:
					vm.scene_owner = -1
				else:
					r.w.vm_state["scene_owner"] = -1


# After every world's frame (engine.gd), before the host's world is loaded again: teleports,
# and players who became free get their question.
func _drop_gather() -> void:
	for o in gather["ask"]:
		ui.close(o)
	ui.set_wait(gather["by"], "")
	gather = null


func end_frame() -> void:
	_scenes_frame()
	if gather != null:
		var inst = gather["inst"]
		var left_room: bool = gather.has("room") and eng.mprooms.room_of(int(gather["by"])) != gather["room"]
		if inst == null or inst.dead or not mp.list[gather["by"]].active or left_room:
			_drop_gather()
		else:
			_ask_free()
	for m in _moves:
		eng.mprooms.teleport(int(m[0]), int(m[1]))
	_moves.clear()
