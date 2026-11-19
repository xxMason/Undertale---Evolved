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
				# Stage 3: the text box is drawn on player 2's screen only.
				seen["n90"] = [_drawn(0), _drawn(1)]
				_ok(seen["n90"][1] > seen["n90"][0] + 10, "player 2's screen has the text box, player 1's doesn't (%d and %d draws)" % [seen["n90"][0], seen["n90"][1]])
			if f == 170:
				_ok(float(_v(1, "interact")) == 0.0, "player 2 is free after the text")
				_ok(_owner_of("obj_readable_room1") == -1, "the sign is nobody's again")
				_ok(_drawn(0) == _drawn(1), "after the text both screens draw the same things (%d and %d)" % [_drawn(0), _drawn(1)])
				_end()
		"menu":
			# Both start on 10 HP with two Monster Candies; player 2 eats one from their menu.
			if f == 40:
				_ok(float(_v(1, "hp")) == 10.0 and _items(1) == [1.0, 1.0], "player 2 starts like player 1 (HP %s, items %s)" % [_v(1, "hp"), _items(1)])
			if f == 80:
				seen["p1"] = _at(0)
				_ok(float(_v(1, "interact")) == 5.0, "player 2's menu is open")
			if f == 100:
				_ok(_at(0) != seen["p1"], "player 1 walked while player 2's menu was open")
			if f == 200:
				_ok(float(_v(1, "hp")) == 20.0 and float(_v(0, "hp")) == 10.0, "only player 2 was healed (HP %s and %s)" % [_v(0, "hp"), _v(1, "hp")])
				_ok(_items(1) == [1.0, 0.0] and _items(0) == [1.0, 1.0], "only player 2's candy was eaten (%s and %s)" % [_items(0), _items(1)])
				_ok(float(_v(1, "interact")) == 0.0 and float(_v(1, "menuno")) == -1.0, "player 2's menu closed (interact %s, menuno %s)" % [_v(1, "interact"), _v(1, "menuno")])
				_end()
		"net":
			# Host side of a network game (stage 4): a friend joins, walks right, reads the
			# sign, and leaves.
			if eng.mp.active_count() == 2 and not seen.has("joined"):
				seen["joined"] = f
				seen["p2"] = _at(1)
			if seen.has("joined") and f == int(seen["joined"]) + 2:
				seen["p1"] = _at(0)
			if seen.has("joined") and f == int(seen["joined"]) + 40:
				_ok(_at(1).x > seen["p2"].x + 2.0, "the friend walked right (%s -> %s)" % [seen["p2"], _at(1)])
				_ok(_at(0) == seen.get("p1", _at(0)), "the host's character stayed put")
			if seen.has("joined") and not seen.has("read") and float(_v(1, "interact")) == 1.0:
				seen["read"] = f
			if seen.has("read") and f == int(seen["read"]) + 5:
				_ok(_owner_of("OBJ_WRITER") == 1, "the friend's text is theirs")
			if seen.has("joined") and not seen.has("left") and eng.mp.active_count() == 1:
				seen["left"] = f
				_ok(seen.has("read"), "the friend read the sign before leaving")
				_ok(eng.mp.list[1].inst == null, "the friend's character went when they left")
				_end()
		"rooms":
			# Stage 5: player 2 goes left into room_ruins8 alone and falls through its hole;
			# then player 1 follows into the world player 2's room is running.
			var mr = eng.mprooms
			if f == 80:
				_ok(mr.rooms.size() == 2, "two rooms are running (%d)" % mr.rooms.size())
				_ok(mr.room_name(mr.room_of(0)) == "room_ruins9" and mr.room_name(mr.room_of(1)) == "room_ruins8", "player 1 is in room_ruins9, player 2 in room_ruins8 (%s, %s)" % [mr.room_name(mr.room_of(0)), mr.room_name(mr.room_of(1))])
				_ok(_count("obj_unfader") == 0, "player 2's fade to black ended with them leaving (%d left)" % _count("obj_unfader"))
				_ok(_count("obj_mainchara") == 1, "player 1's room has one character (%d)" % _count("obj_mainchara"))
				_ok(_drawn(0) > 50 and _drawn(1) > 50, "both screens show their room (%d and %d draws)" % [_drawn(0), _drawn(1)])
				var touched := 0
				for i in eng.vm.instances:
					if not i.dead and String(eng.vm.obj_names[i.obj]).begins_with("obj_door") and float(i.v.get("touched", 0.0)) != 0.0:
						touched += 1
				_ok(touched == 0, "the door player 2 used works again for player 1")
			if f == 200:
				_ok(_at(1).y > 480.0 and _at(1).y < 520.0, "player 2 landed on the leaves below (%s)" % _at(1))
				_ok(float(_v(1, "interact")) == 0.0, "player 2 is free again")
			if f == 300:
				_ok(mr.rooms.size() == 1, "one room is running again (%d)" % mr.rooms.size())
				_ok(mr.room_name(mr.room_of(0)) == "room_ruins8" and mr.room_of(0) == mr.room_of(1), "both players are in room_ruins8")
				_ok(_at(0).x > 200.0 and _at(0).y < 150.0, "player 1 came in at the door (%s)" % _at(0))
				_ok(_count("obj_mainchara") == 2, "the room has both characters (%d)" % _count("obj_mainchara"))
				_ok(_drawn(0) > 50 and _drawn(1) > 50, "both screens show the room (%d and %d draws)" % [_drawn(0), _drawn(1)])
				_end()
		"battles":
			# Stage 6: both players walk back and forth in room_ruins9 and get random battles on
			# the same frame; each fights their own (Z), and both come back where they were.
			var mr = eng.mprooms
			if f == 150:
				seen["p1"] = _at(0)
				seen["p2"] = _at(1)
			if f == 200:
				_ok(mr.rooms.size() == 2 and mr.room_of(0) != mr.room_of(1), "two battles are running (%d worlds)" % mr.rooms.size())
				_ok(mr.room_name(mr.room_of(0)) == "room_battle" and mr.room_name(mr.room_of(1)) == "room_battle", "each player is in their own battle")
			if f == 950:
				_ok(mr.rooms.size() == 1 and mr.room_name(mr.room_of(0)) == "room_ruins9", "both are back in room_ruins9 (%s)" % mr.status())
				_ok(_at(0).distance_to(seen["p1"]) < 8.0, "player 1 is where they were (%s, was %s)" % [_at(0), seen["p1"]])
				_ok(_at(1).distance_to(seen["p2"]) < 8.0, "player 2 is where they were (%s, was %s)" % [_at(1), seen["p2"]])
				_ok(float(_v(0, "gold")) > 0.0 and float(_v(1, "gold")) > 0.0, "both won their gold (%s and %s)" % [_v(0, "gold"), _v(1, "gold")])
				_ok(_count("obj_mainchara") == 2, "the room has both characters (%d)" % _count("obj_mainchara"))
				_end()
		"party":
			# Stage 8: player 2 stands by player 1, who gets a random battle: both are in it,
			# each with their own SOUL; turns go in order; both win the gold and come back.
			var mr = eng.mprooms
			var bt = eng.mpbattles
			if f == 150:
				seen["p1"] = _at(0)
				seen["p2"] = _at(1)
			var rn: String = mr.room_name(mr.room_of(0))
			if rn == "room_battle" and not seen.has("battle"):
				seen["battle"] = f
			if seen.has("battle") and f == int(seen["battle"]) + 5:
				_ok(mr.room_of(0) == mr.room_of(1), "player 2 was pulled into the battle (%s)" % mr.status())
			if rn == "room_battle" and float(eng.vm.globals.get("mnfight", 0.0)) == 2.0 and not seen.has("souls"):
				seen["souls"] = true
				var owners: Array = []
				for i in eng.vm.instances:
					if not i.dead and i.obj == bt.obj_heart:
						owners.append(i.owner)
				owners.sort()
				_ok(owners == [0, 1], "each player has a SOUL while dodging (owners %s)" % [owners])
			if rn != "room_battle" and seen.has("battle") and not seen.has("back"):
				seen["back"] = f
			if seen.has("back") and f == int(seen["back"]) + 30:
				_ok(bt.told.has("turn Greg"), "player 2 had a turn (%s)" % [bt.told])
				_ok(bt.told.has("end won"), "the battle was won")
				_ok(mr.rooms.size() == 1 and mr.room_name(mr.room_of(0)) == "room_ruins9", "both are back in room_ruins9 (%s)" % mr.status())
				_ok(_at(0).distance_to(seen["p1"]) < 30.0, "player 1 is about where they were (%s, was %s)" % [_at(0), seen["p1"]])
				_ok(_at(1).distance_to(seen["p2"]) < 8.0, "player 2 is where they were (%s, was %s)" % [_at(1), seen["p2"]])
				_ok(float(_v(0, "gold")) > 0.0 and float(_v(0, "gold")) == float(_v(1, "gold")), "both won the gold (%s and %s)" % [_v(0, "gold"), _v(1, "gold")])
				_ok(not eng.vm.party_on, "the battle's shared state ended")
				_end()
		"revive":
			# Stage 8: as "party", but player 2 comes in on 1 HP and goes down; player 1 only
			# uses MERCY (so the battle lasts) and after 3 turns revives them from it.
			var mr = eng.mprooms
			var bt = eng.mpbattles
			var g: Dictionary = eng.vm.globals
			var rn: String = mr.room_name(mr.room_of(0))
			if rn == "room_battle" and not seen.has("battle"):
				seen["battle"] = f
				eng.mp.set_value(0, "maxhp", 99.0)
				eng.mp.set_value(0, "hp", 99.0)
				eng.mp.set_value(1, "hp", 1.0)
			var b = bt.battles.get(mr.room_of(0))
			if b != null and b.down.has(1) and not seen.has("down"):
				seen["down"] = f
				eng.bot_shot("down")
				_ok(bt._heart_of(1) == null, "player 2's SOUL is gone while down")
				_ok(mr.room_of(0).lead == 0, "player 1 fights on")
			if rn == "room_battle":
				eng.mp.set_value(0, "invc", 30.0)    # the hits go through to player 2's SOUL
			if rn == "room_battle" and f % 6 == 0 and b != null:
				var k = eng.mp.list[mr.room_of(0).lead].keys
				if float(g.get("myfight", 0.0)) == 0.0 and float(g.get("mnfight", 0.0)) == 0.0:
					var bm := float(g.get("bmenuno", 0.0))
					if bm == 0.0:
						k.tap(39 if bt._bm(0) != 3.0 else 90)
					elif bm == 4.0:
						if b.down.has(1) and int(b.down[1]) >= bt.REVIVE_TURNS:
							k.tap(90 if b.revive_sel else 40)
							if b.revive_sel and not seen.has("shot"):
								seen["shot"] = f
								eng.bot_shot("revive_row")
						else:
							k.tap(90)
					else:
						k.tap(90)
				else:
					k.tap(90)
			if bt.told.has("revive Greg") and not seen.has("revived"):
				seen["revived"] = f
				_ok(float(_v(1, "hp")) == ceilf(float(_v(1, "maxhp")) * 0.3), "player 2 is back on 30%% HP (%s)" % _v(1, "hp"))
			if seen.has("revived") and f == int(seen["revived"]) + 200:
				_ok(bt._heart_of(1) != null or rn != "room_battle", "player 2 has a SOUL again")
				_ok(not bt.told.has("end game over"), "no game over")
				_end()
			if f == 1490 and not seen.has("revived"):
				_ok(false, "revived in time (%s)" % [bt.told])
				_end()
		"join":
			# Stage 8: player 2 has their menu open, so player 1's battle doesn't pull them in;
			# then they close it and, by where player 1 stood ("Kyle is in a battle"), press
			# Enter, say Yes, and join at the next turn.
			var mr = eng.mprooms
			var bt = eng.mpbattles
			if not seen.has("battle"):
				eng.mp.set_value(1, "encounter", 0.0)    # no battle of their own on the way
			var rn: String = mr.room_name(mr.room_of(0))
			if rn == "room_battle" and not seen.has("battle"):
				seen["battle"] = f
			if seen.has("battle") and f == int(seen["battle"]) + 5:
				_ok(mr.room_of(0) != mr.room_of(1), "player 2, in their menu, wasn't pulled in (%s)" % mr.status())
			if f == 225 and mr.room_of(1) != mr.room_of(0):
				var keep = mr.cur
				mr.switch(mr.room_of(1))
				var sp: Array = bt.spots()
				_ok(sp.size() == 1 and sp[0][0] == 0, "player 2's room shows where player 1 is in a battle (%s)" % [sp])
				seen["p2"] = _at(1)
				mr.switch(keep)
			if f == 236:
				_ok(eng.mpui.busy(1), "Enter asked player 2 to join")
			if bt.told.has("join Greg") and not seen.has("joined"):
				seen["joined"] = f
				_ok(_told(1, "You'll join at the next turn."), "player 2 was told when they'd join")
			if seen.has("joined") and f == int(seen["joined"]) + 5:
				_ok(mr.room_of(0) == mr.room_of(1), "player 2 is in the battle (%s)" % mr.status())
			if rn == "room_battle" and seen.has("joined") and float(eng.vm.globals.get("mnfight", 0.0)) == 2.0 and not seen.has("souls"):
				seen["souls"] = true
				var owners: Array = []
				for i in eng.vm.instances:
					if not i.dead and i.obj == bt.obj_heart:
						owners.append(i.owner)
				owners.sort()
				_ok(owners == [0, 1], "both have a SOUL (owners %s)" % [owners])
			if rn != "room_battle" and seen.has("battle") and not seen.has("back"):
				seen["back"] = f
			if seen.has("back") and f == int(seen["back"]) + 30:
				_ok(mr.rooms.size() == 1 and mr.room_of(0) == mr.room_of(1), "both are back in one room (%s)" % mr.status())
				_ok(_at(1).distance_to(seen.get("p2", Vector2.ZERO)) < 8.0, "player 2 is where they joined from (%s, was %s)" % [_at(1), seen.get("p2")])
				_ok(float(_v(0, "gold")) > 0.0 and float(_v(0, "gold")) == float(_v(1, "gold")), "both won the gold (%s and %s)" % [_v(0, "gold"), _v(1, "gold")])
				_end()
			if f == 2390 and not seen.has("back"):
				_ok(false, "the battle ended in time (%s)" % [bt.told])
				_end()
		"save":
			# Stage 6: player 2 has their menu open, so player 1's save is refused; then player
			# 2 closes it and player 1 saves for both (room_ruins7's save point).
			if f == 165:
				_ok(float(_v(0, "menuno")) == -1.0 and float(_v(0, "interact")) == 0.0, "player 1's save menu didn't open")
				_ok(_told(0, "Can't save now: Greg is in a menu."), "player 1 is told why (%s)" % [eng.mpsaves.told])
				_ok(not FileAccess.file_exists(eng.bi.save_path("file0")), "nothing was saved")
			if f == 370:
				_ok(FileAccess.file_exists(eng.bi.save_path("file0")), "the game was saved")
				var all = JSON.parse_string(FileAccess.get_file_as_string(eng.bi.save_path("players.json")))
				_ok(all is Dictionary and all.has("Kyle") and all.has("Greg"), "both players' things were saved (%s)" % [all.keys() if all is Dictionary else all])
				_ok(_told(1, "Kyle saved the game."), "player 2 is told who saved")
				_end()
		"death":
			# Stage 6: player 1 saves in room_ruins7; player 2 (1 HP) gets a battle there and is
			# downed alone. After the game over screen they come back at the save, on full HP;
			# player 1 is told, and nothing else changes.
			var mr = eng.mprooms
			eng.mpbattles.pull_range = 0.0     # player 2 fights alone
			var rn2: String = mr.room_name(mr.room_of(1))
			if rn2 == "room_battle" and not seen.has("battle"):
				seen["battle"] = f
			if rn2.begins_with("room_gameover") and not seen.has("over"):
				seen["over"] = f
				_ok(mr.room_name(mr.room_of(0)) == "room_ruins7", "player 1 stays in room_ruins7 meanwhile")
			if seen.has("over") and not seen.has("back") and mr.room_of(1) == mr.room_of(0):
				seen["back"] = f
				_ok(FileAccess.file_exists(eng.bi.save_path("file0")), "player 1 had saved")
				_ok(float(_v(1, "hp")) == float(_v(1, "maxhp")), "player 2 is on full HP (%s of %s)" % [_v(1, "hp"), _v(1, "maxhp")])
				_ok(_at(1) == Vector2(210, 99), "player 2 is at the save point (%s)" % _at(1))
				_ok(_told(0, "Greg died."), "player 1 was told (%s)" % [eng.mpsaves.told])
				_ok(float(eng.vm.globals.get("plot", 0.0)) == 11.0, "the story didn't go back (plot %s)" % eng.vm.globals.get("plot"))
				_ok(mr.rooms.size() == 1, "one room is running (%s)" % mr.status())
				_end()
			if f == 2400 and not seen.has("back"):
				_ok(false, "player 2 came back (battle %s, game over %s)" % [seen.get("battle"), seen.get("over")])
				_end()
		"gather":
			# Stage 6: player 2 goes ahead into Toriel's house (and reads her words there);
			# player 1 walks into Toriel's scene in room_ruins19. The scene waits; player 2 is
			# asked once their text is over, says Yes, and is brought beside player 1; the
			# scene then plays, on both screens.
			var mr = eng.mprooms
			var ui = eng.mpui
			if f == 200:
				_ok(ui.waits.has(0) and String(ui.waits[0]["text"]).begins_with("Waiting for 1 more player"), "player 1 is waiting for player 2 (%s)" % [ui.waits.get(0)])
				_ok(float(_v(0, "interact")) == 0.0, "the scene hasn't started")
				_ok(not ui.prompts.has(1) and float(_v(1, "interact")) != 0.0, "player 2, still reading, isn't asked yet")
			if ui.prompts.has(1) and not seen.has("asked"):
				seen["asked"] = f
			if seen.has("asked") and not seen.has("tp") and mr.room_of(1) == mr.room_of(0):
				seen["tp"] = f
				_ok(_at(1).distance_to(_at(0)) < 4.0, "player 2 is beside player 1 (%s and %s)" % [_at(1), _at(0)])
			if seen.has("tp") and f == int(seen["tp"]) + 30:
				_ok(float(_v(0, "interact")) == 1.0, "the scene started for player 1")
				_ok(not ui.waits.has(0), "player 1 isn't waiting any more")
				_ok(_drawn(0) == _drawn(1) and _drawn(0) > 100, "both screens show Toriel's words (%d and %d draws)" % [_drawn(0), _drawn(1)])
				_end()
			if f == 690 and not seen.has("tp"):
				_ok(false, "player 2 was brought to the scene (asked at %s)" % seen.get("asked"))
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


# How many drawing commands player k's screen would make this frame.
func _drawn(k: int) -> int:
	var c := Counter.new()
	var p = eng.mp.list[k]
	var r = eng.mprooms.room_of(k) if eng.mprooms != null else null
	var rec = r.rec if r != null else eng.rec
	if k == (r.lead if r != null else eng.mp.primary):
		rec.replay(c, 1.0, k)
	else:
		rec.replay(c, 1.0, k, p.view, p.prev_view)
	return c.n


class Counter:
	var n := 0
	func draw_set_transform(_p = null, _r = 0.0, _s = null) -> void: pass
	func draw_texture(_a = null, _b = null, _c = null) -> void: n += 1
	func draw_texture_rect(_a = null, _b = null, _c = null, _d = null) -> void: n += 1
	func draw_texture_rect_region(_a = null, _b = null, _c = null, _d = null) -> void: n += 1
	func draw_rect(_a = null, _b = null, _c = null, _d = null) -> void: n += 1
	func draw_line(_a = null, _b = null, _c = null, _d = null) -> void: n += 1
	func draw_arc(_a = null, _b = null, _c = null, _d = null, _e = null, _f = null, _g = null) -> void: n += 1
	func draw_circle(_a = null, _b = null, _c = null) -> void: n += 1
	func draw_polyline(_a = null, _b = null, _c = null) -> void: n += 1
	func draw_colored_polygon(_a = null, _b = null) -> void: n += 1


func _end() -> void:
	print("MPCHECK %s done, %d failed" % [name, failed])


func _count(obj_name: String) -> int:
	var o := int(eng.vm.obj_index.get(obj_name, -1))
	var n := 0
	for i in eng.vm.instances:
		if not i.dead and i.obj == o:
			n += 1
	return n


func _told(k: int, text: String) -> bool:
	for t in eng.mpsaves.told:
		if int(t[0]) == k and String(t[1]) == text:
			return true
	return false
