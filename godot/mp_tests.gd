# Checks for the multiplayer rework (docs/MULTIPLAYER.md), run by scripts/check.ps1:
#   --mpcheck NAME with the room, keys and players the scenario below expects.
# Each scenario looks at the players on chosen frames and prints MPCHECK lines.
extends RefCounted

var eng
var name := ""
var failed := 0
var seen := {}


func setup(e, n: String) -> void:
	eng = e
	name = n


func _ok(cond: bool, what: String) -> void:
	print("MPCHECK %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		failed += 1


func _at(k: int) -> Vector2:
	var p = eng.mp.list[k]
	if p.inst == null or p.inst.dead:
		return Vector2(-1, -1)
	return Vector2(float(p.inst.v["x"]), float(p.inst.v["y"]))


func _owner_of(obj_name: String) -> int:
	var o := int(eng.vm.obj_index.get(obj_name, -1))
	for i in eng.vm.instances:
		if not i.dead and i.obj == o:
			return i.owner
	return -9


func _v(k: int, g: String):
	return eng.mp.value(k, g)


func _items(k: int) -> Array:
	var it = _v(k, "item")
	return (it[0] as Array).slice(0, 2) if it is Array and not it.is_empty() and it[0] is Array else []


# Called after every game frame.
func frame(f: int) -> void:
	if eng.mp == null:
		return
	match name:
		"sign":
			# Player 2 reads the sign in room_ruins9 while player 1 walks right and back.
			if f == 70:
				seen["p1"] = _at(0)
			if f == 90:
				_ok(float(_v(1, "interact")) == 1.0, "player 2 is busy reading (interact %s)" % _v(1, "interact"))
				_ok(float(_v(0, "interact")) == 0.0, "player 1 is not (interact %s)" % _v(0, "interact"))
				_ok(_at(0) != seen["p1"], "player 1 kept walking while player 2 read (%s -> %s)" % [seen["p1"], _at(0)])
				_ok(_owner_of("OBJ_WRITER") == 1, "the text belongs to player 2")
			if f == 170:
				_ok(float(_v(1, "interact")) == 0.0, "player 2 is free after the text")
				_ok(_owner_of("obj_readable_room1") == -1, "the sign is nobody's again")
				_end()
		"menu":
			# Both start on 10 HP with two Monster Candies; player 2 eats one from their menu.
			if f == 80:
				seen["p1"] = _at(0)
				_ok(float(_v(1, "interact")) == 5.0, "player 2's menu is open")
			if f == 100:
				_ok(_at(0) != seen["p1"], "player 1 walked while player 2's menu was open")
			if f == 200:
				_ok(float(_v(1, "hp")) == 20.0 and float(_v(0, "hp")) == 10.0, "only player 2 was healed (HP %s and %s)" % [_v(0, "hp"), _v(1, "hp")])
				_ok(_items(1) == [1.0, 0.0] and _items(0) == [1.0, 1.0], "only player 2's candy was eaten (%s and %s)" % [_items(0), _items(1)])
				_ok(float(_v(1, "interact")) == 0.0 and float(_v(1, "menuno")) == -1.0, "player 2's menu closed")
				_end()
		"hole":
			# Player 2 falls through a hole in room_ruins8; player 1 stands still.
			if f == 5:
				seen["p1"] = _at(0)
			if f == 150:
				_ok(_at(0) == seen["p1"], "player 1 was not moved by player 2's fall (%s -> %s)" % [seen["p1"], _at(0)])
				_ok(_at(1).y > 400.0, "player 2 landed below (%s)" % _at(1))
				_ok(float(_v(1, "interact")) == 0.0 and float(_v(1, "phasing")) == 0.0, "player 2 is free again")
				_ok(_owner_of("obj_holedown2") == -1, "the hole is nobody's again")
				_end()


func _end() -> void:
	print("MPCHECK %s done, %d failed" % [name, failed])
