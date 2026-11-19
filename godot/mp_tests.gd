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
		"lossy":
			# Host side of a friend on a bad network (--netloss / --netlag / --netjitter on their
			# PC): every Z they tap (--taps N of them) must reach the game, and they must walk.
			var gi := _index_of("Greg")
			if gi >= 0:
				seen["was"] = true
				if eng.mp.list[gi].keys.pressed(90):
					seen["taps"] = int(seen.get("taps", 0)) + 1
				var x := _at(gi).x
				if x > 0:
					seen["minx"] = minf(float(seen.get("minx", x)), x)
					seen["maxx"] = maxf(float(seen.get("maxx", x)), x)
			elif seen.has("was") and not seen.has("done"):
				seen["done"] = f
				var args := OS.get_cmdline_user_args()
				var want := int(args[args.find("--taps") + 1]) if args.has("--taps") else 0
				_ok(int(seen.get("taps", 0)) == want, "every tap arrived (%d of %d)" % [int(seen.get("taps", 0)), want])
				_ok(float(seen.get("maxx", 0)) - float(seen.get("minx", 0)) > 60.0, "Greg walked (%.0f to %.0f)" % [float(seen.get("minx", 0)), float(seen.get("maxx", 0))])
				_end()
		"spam":
			# Host side: Eve's PC misbehaves (--mpspam: pause on and off, a flood of chat, a second
			# hello, packets that aren't what the host expects) while Greg plays normally.
			if eng.mp.active_count() == 3 and not seen.has("both"):
				seen["both"] = f
				seen["g0"] = _at(_index_of("Greg"))
			if seen.has("both") and _index_of("Greg") >= 0 and _at(_index_of("Greg")).x > 0 and _at(_index_of("Greg")) != seen["g0"]:
				seen["gmoved"] = 1
			if seen.has("both") and f == int(seen["both"]) + 500:
				_ok(_index_of("Again") < 0, "a second hello didn't add a player")
				var gi := _index_of("Greg")
				_ok(gi >= 0 and eng.mprooms.room_of(gi) != null and float(seen.get("gmoved", 0)) > 0, "Greg still plays (moved, now in %s)" % eng.mprooms.status())
				var times: Array = eng.chat.lines.filter(func(l): return String(l["name"]) == "Eve").map(func(l): return int(l["at"]))
				var worst := 0
				for k in times.size():
					var n := 0
					for t in times:
						if t >= int(times[k]) and t - int(times[k]) <= eng.mpnet.CHAT_WINDOW_MS:
							n += 1
					worst = maxi(worst, n)
				_ok(times.size() > 0 and worst <= eng.mpnet.CHAT_BURST, "Eve's chat was let through %d at a time at most (%d lines kept)" % [worst, times.size()])
				var ei := _index_of("Eve")
				_ok(ei >= 0 and eng.mpnet.peers.values().all(func(pp): return (pp["keys"] as Array).size() <= eng.mpnet.KEYS_KEPT), "nobody's keys pile up")
				_end()
		"pmenu":
			# Player 2 faces player 1 and opens the player menu with Enter: Check, Give item
			# (a candy), Give gold, Heal (a candy, on player 1 at 10 HP).
			var pm = eng.mpui.pmenu
			if f % 10 == 0 and f <= 300 and OS.get_cmdline_user_args().has("--mpverbose"):
				print("PM f=%d p1=%s p2=%s face2=%s menu=%s ui=%s" % [f, _at(0), _at(1), _v(1, "facing"), pm.menus.get(1), eng.mpui.state_for(1).get("m", {}).get("rows", [])])
			if f == 60:
				_ok(pm.menus.has(1) and int(pm.menus[1]["to"]) == 0, "Enter facing player 1 opens player 2's player menu (%s)" % [pm.menus.get(1)])
				_ok(float(_v(1, "interact")) == 0.0, "the game didn't take the Enter")
			if f == 90:
				var rows: Array = eng.mpui.state_for(1).get("m", {}).get("rows", [])
				_ok(rows.size() == 8 and String(rows[0]).contains("Kyle") or rows.size() == 8 and String(rows[0]).length() > 2, "Check shows player 1's STAT page (%s)" % [rows])
				print("MPCHECK info Check: %s" % [rows])
			if f == 200:
				var d: Array = pm.done
				_ok(d.any(func(x): return x[1] == "item" and x[2] == 0), "player 2 gave an item (%s)" % [d])
				_ok(d.any(func(x): return x[1] == "gold" and x[2] == 0), "player 2 gave gold")
				_ok(d.any(func(x): return x[1] == "heal" and x[2] == 0 and int(x[3]) > 0), "player 2 healed player 1")
				_ok(float(_v(0, "gold")) == 30.0 and float(_v(1, "gold")) == 10.0, "10G went from player 2 to player 1 (%s and %s)" % [_v(0, "gold"), _v(1, "gold")])
				_ok(float(_v(0, "hp")) > 10.0, "player 1 was healed (HP %s)" % _v(0, "hp"))
				_ok(_items(1) == [0.0, 0.0] and _items(0)[0] == 1.0, "player 2's two candies went: one given, one eaten by player 1 (%s and %s)" % [_items(0), _items(1)])
				_end()
		"kick":
			# Host side: the host removes the friend from the Players page of the pause menu,
			# then changes the password there.
			var pz = eng.pause
			if eng.mp.active_count() == 2 and not seen.has("joined"):
				seen["joined"] = f
			if not seen.has("joined"):
				return
			var j := int(seen["joined"])
			if f == j + 20:
				pz.toggle()
				pz.key(KEY_DOWN)        # Players
				pz.key(KEY_Z)
				_ok(pz.page == "players" and pz._player_rows()[0][0] == eng.mp.list[1].name, "the host's Players page lists the friend (%s)" % [pz._player_rows()])
				pz.key(KEY_Z)           # the friend
				_ok(pz.page == "confirm", "removing asks first")
				pz.key(KEY_LEFT)        # Yes
				pz.key(KEY_Z)
				_ok(pz.page == "players", "back on the Players page")
				pz.close()              # (alone, an open menu stops the game)
			if f == j + 80:
				_ok(eng.mp.active_count() == 1, "the friend is out of the game (%d players)" % eng.mp.active_count())
				var pz2 = eng.pause
				pz2.toggle()
				pz2.key(KEY_DOWN)
				pz2.key(KEY_Z)
				_ok(pz2.page == "players" and pz2._player_rows().size() == 2, "the Players page now has only the password and Back")
				pz2.key(KEY_Z)          # Password
				for c in "abc":
					var e := InputEventKey.new()
					e.keycode = OS.find_keycode_from_string(c.to_upper())
					e.unicode = c.unicode_at(0)
					e.pressed = true
					pz2.key_event(e)
				var en := InputEventKey.new()
				en.keycode = KEY_ENTER
				en.pressed = true
				pz2.key_event(en)
				_ok(eng.mpnet.password == "abc", "the password is changed (%s)" % eng.mpnet.password)
				pz2.close()
			if f == j + 400:
				_ok(eng.mp.active_count() == 1, "the removed friend didn't get back in, even with the password")
				_end()
		"pause":
			# Host side: the host opens the pause menu just after the friend joins; the game
			# goes on until the friend opens theirs too (--mppause), then stops until they close it.
			var now := Engine.get_physics_frames()
			if eng.mp.active_count() == 2 and not seen.has("joined"):
				seen["joined"] = f
				seen["last"] = now
			if not seen.has("joined"):
				return
			if f == int(seen["joined"]) + 10:
				eng.pause.toggle()
			if f == int(seen["joined"]) + 40:
				_ok(eng.pause.open and not eng.mp.list[1].paused, "the game goes on with only the host paused")
			var gap := now - int(seen["last"])
			seen["last"] = now
			if gap > 40 and not seen.has("stopped"):
				seen["stopped"] = gap
				_ok(eng.pause.open, "the game stopped while both were paused (%d physics frames)" % gap)
				_ok(not eng.mp.list[1].paused, "it went on once the friend resumed")
				eng.pause.close()
			if seen.has("stopped") and f == int(seen["joined"]) + 200:
				_end()
			if f == int(seen["joined"]) + 600 and not seen.has("stopped"):
				_ok(false, "the game never stopped")
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
		"chaos":
			# Stress: every player mashes keys at random for a long time (--pfeed chaos). Nothing
			# is checked about the story; what must always hold is checked every 30 frames, and
			# how long each frame of the whole game takes is measured. --warm: all the game's
			# code compiled first, as playing does between frames (tests run frames back to back).
			if not seen.has("warmed") and OS.get_cmdline_user_args().has("--warm"):
				var tw := Time.get_ticks_msec()
				while not eng.vm.warm_step(1000000):
					pass
				print("CHAOS warmed in %d ms" % (Time.get_ticks_msec() - tw))
				seen["warmed"] = true
				seen.erase("t")
			var now := Time.get_ticks_usec()
			if seen.has("t"):
				var dt := now - int(seen["t"])
				seen["sum"] = int(seen.get("sum", 0)) + dt
				seen["n"] = int(seen.get("n", 0)) + 1
				seen["max"] = maxi(int(seen.get("max", 0)), dt)
				if dt > 33000:
					seen["slow"] = int(seen.get("slow", 0)) + 1
					print("CHAOS slow frame %d: %.1f ms (%s)" % [f, dt / 1000.0, eng.mprooms.status()])
			seen["t"] = now
			var mr = eng.mprooms
			if f % 30 == 0:
				var bad: Array = []
				for p in eng.mp.list:
					if not p.active:
						continue
					var r = mr.room_of(p.index)
					if r == null:
						bad.append("%s has no room" % p.name)
						continue
					var hp := float(_v(p.index, "hp"))
					var mx := float(_v(p.index, "maxhp"))
					if is_nan(hp) or hp > mx + 0.5 and not eng.mpbattles.battles.has(r):
						bad.append("%s HP %s/%s" % [p.name, hp, mx])
				# One character per player in the loaded world, inside the room.
				var per := {}
				for i in eng.vm.instances:
					if not i.dead and i.obj == eng.mp.obj_main and i.owner >= 0:
						per[i.owner] = int(per.get(i.owner, 0)) + 1
						var x := float(i.v["x"])
						var y := float(i.v["y"])
						if x < -64 or y < -64 or x > float(eng.vm.room_width) + 64 or y > float(eng.vm.room_height) + 64:
							bad.append("%s's character is outside the room (%d,%d in %dx%d)" % [eng.mp.list[i.owner].name, x, y, eng.vm.room_width, eng.vm.room_height])
				for o in per:
					if int(per[o]) > 1:
						bad.append("%s has %d characters" % [eng.mp.list[o].name, per[o]])
				# Nobody who left is still in a world, and every world's lead is one of its own.
				for r in mr.rooms:
					for m in r.members:
						if m >= eng.mp.list.size() or not eng.mp.list[m].active:
							bad.append("player %d left but is still in %s" % [m + 1, mr.room_name(r)])
					if not r.members.is_empty() and not r.members.has(r.lead):
						bad.append("the lead of %s (player %d) isn't in it" % [mr.room_name(r), r.lead + 1])
				var total := 0
				for r in mr.rooms:
					total += (eng.vm.instances.size() if r == mr.cur else (r.w.vm_state.get("instances", []) as Array).size())
				seen["peak_inst"] = maxi(int(seen.get("peak_inst", 0)), total)
				if total > 3000:
					bad.append("%d instances" % total)
				if mr.rooms.size() > eng.mp.list.size() * 2:
					bad.append("%d worlds" % mr.rooms.size())
				for b in bad:
					if not seen.has("bad:" + b):
						seen["bad:" + b] = true
						_ok(false, "f=%d %s (%s)" % [f, b, mr.status()])
				if f % 600 == 0:
					var rn: Array = []
					for p in eng.mp.list.filter(func(q): return q.active):
						rn.append("%s:%s:%d" % [p.name, mr.room_name(mr.room_of(p.index)), int(float(_v(p.index, "hp")))])
					print("CHAOS f=%d worlds=%d inst=%d avg=%.2fms max=%.1fms slow=%d battles=%d %s" % [f, mr.rooms.size(), total, float(seen.get("sum", 0)) / maxf(1.0, float(seen.get("n", 1))) / 1000.0, float(seen.get("max", 0)) / 1000.0, int(seen.get("slow", 0)), eng.mpbattles.told.filter(func(t): return String(t).begins_with("party")).size(), rn])
			if f == int(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--frames") + 1]) - 2:
				_ok(true, "ran %d frames: avg %.2f ms, worst %.1f ms, %d over 33 ms, peak %d instances" % [f, float(seen.get("sum", 0)) / maxf(1.0, float(seen.get("n", 1))) / 1000.0, float(seen.get("max", 0)) / 1000.0, int(seen.get("slow", 0)), int(seen.get("peak_inst", 0))])
				_end()
		"spears":
			# Undyne's battle with two players: each has their own green-SOUL shield, and her
			# spears come at each of them in turn.
			var mr = eng.mprooms
			var bt = eng.mpbattles
			var g: Dictionary = eng.vm.globals
			if f == 20:
				eng.mp.switch_to(0)
				eng.vm.run_source("global.border = 12; global.battlegroup = 47; global.mercy = 1; instance_create(0, 0, obj_battler);")
				eng.mp.switch_to(-1)
			var rn: String = mr.room_name(mr.room_of(0))
			if rn == "room_battle" and not seen.has("battle"):
				seen["battle"] = f
				_ok(mr.room_of(0) == mr.room_of(1), "player 2 is in Undyne's battle too (%s)" % mr.status())
			if rn == "room_battle" and not seen.has("hp"):
				seen["hp"] = true
				for k in 2:
					eng.mp.set_value(k, "maxhp", 99.0)
					eng.mp.set_value(k, "hp", 99.0)
			var b = bt.battles.get(mr.room_of(0))
			if rn == "room_battle" and f % 6 == 0 and b != null:
				var k = eng.mp.list[mr.room_of(0).lead].keys
				if float(g.get("myfight", 0.0)) == 0.0 and float(g.get("mnfight", 0.0)) == 0.0 and float(g.get("bmenuno", 0.0)) == 0.0:
					k.tap(39 if bt._bm(0) != 1.0 else 90)     # ACT
				else:
					k.tap(90)
			if rn == "room_battle" and bt.obj_blocker >= 0:
				var bl: Array = []
				var sp := {}
				for i in eng.vm.instances:
					if i.dead:
						continue
					if i.obj == bt.obj_blocker:
						bl.append(i.owner)
						var dd: Dictionary = seen.get("dirs", {})
						dd["%d:%s" % [i.owner, i.v.get("idealdir")]] = true
						seen["dirs"] = dd
					elif bt.obj_spears.has(i.obj):
						sp[i.owner] = true
				bl.sort()
				if OS.get_cmdline_user_args().has("--mpverbose") and not bl.is_empty() and f % 5 == 0:
					var d: Array = []
					for i in eng.vm.instances:
						if not i.dead and (i.obj == bt.obj_blocker or bt.obj_spears.has(i.obj)):
							d.append("%s:%d@%d,%d %s" % [eng.vm.obj_names[i.obj].substr(4, 6), i.owner, int(i.v["x"]), int(i.v["y"]), ("dir%s/%s" % [i.v.get("dir"), i.v.get("idealdir")]) if i.obj == bt.obj_blocker else ("s%s v%s,%s" % [i.v.get("site"), i.v.get("hspeed"), i.v.get("vspeed")])])
					print("SP f=%d hp=%s,%s invc=%s,%s %s" % [f, _v(0, "hp"), _v(1, "hp"), _v(0, "invc"), _v(1, "invc"), d])
				if not bl.is_empty():
					seen["blockers"] = bl
					if seen.has("first"):
						seen["second"] = true
					var so: Array = sp.keys()
					so.sort()
					if so.size() > seen.get("spear_owners", []).size():
						seen["spear_owners"] = so
				# The first attack (all from above) ends; the second has spears from the sides.
				if bl.is_empty() and seen.has("blockers") and not seen.has("first"):
					seen["first"] = f
				if bl.is_empty() and seen.get("second", false) and not seen.has("over"):
					seen["over"] = f
					_ok(seen["blockers"] == [0, 1], "each player had their own shield (%s)" % [seen["blockers"]])
					_ok(seen.get("spear_owners", []) == [0, 1], "spears came at both players (%s)" % [seen.get("spear_owners", [])])
					var left := 0
					for i in eng.vm.instances:
						if not i.dead and (i.obj == bt.obj_blocker or bt.obj_spears.has(i.obj)):
							left += 1
					_ok(left == 0, "no shields or spears left after the attack (%d)" % left)
					if not OS.get_cmdline_user_args().has("--spearleft"):
						_ok(float(_v(0, "hp")) < 99.0 and float(_v(1, "hp")) < 99.0, "unblocked spears hurt each player (HP %s and %s)" % [_v(0, "hp"), _v(1, "hp")])
					if OS.get_cmdline_user_args().has("--spearleft"):
						var dd: Dictionary = seen.get("dirs", {})
						_ok(dd.has("1:0.0") and not dd.has("0:0.0"), "player 2's Left turned only player 2's shield (%s)" % [dd.keys()])
					_end()
			if f == 2900 and not seen.has("over"):
				_ok(false, "a spear attack came (%s)" % [seen])
				_end()
		"loadscene":
			# Toriel's scene at the training dummy starts as room_ruins4 loads. Player 1 goes in
			# while player 2 is in room_ruins3: the scene waits, player 2 says Yes, is brought
			# beside player 1, and then it plays, Toriel following player 1.
			var mr = eng.mprooms
			var args := OS.get_cmdline_user_args()
			var lroom: String = args[args.find("--lsroom") + 1] if args.has("--lsroom") else "room_ruins4"
			var lobj: String = args[args.find("--lsobj") + 1] if args.has("--lsobj") else "obj_toroverworld4"
			if f == 20:
				var keep: int = eng.vm.ctx_owner
				mr.switch(mr.room_of(0))
				mr._send(0, eng.vm.room_names.find(lroom))
				eng.mp.switch_to(keep)
			if f == 40:
				_ok(mr.room_name(mr.room_of(0)) == lroom and mr.room_of(1) != mr.room_of(0), "player 1 is in %s, player 2 elsewhere (%s)" % [lroom, mr.status()])
				_ok(eng.mpui.waits.has(0), "player 1 is waiting (%s)" % [eng.mpui.waits.get(0)])
				_ok(eng.mpui.prompts.has(1), "player 2 is asked to come")
				var keep = mr.cur
				mr.switch(mr.room_of(0))
				_ok(_count(lobj) == 0 and float(_v(0, "interact")) == 0.0, "Toriel's scene hasn't started")
				mr.switch(keep)
			if f == 80:
				_ok(mr.room_of(0) == mr.room_of(1), "player 2 was brought to player 1 (%s)" % mr.status())
				var keep = mr.cur
				mr.switch(mr.room_of(0))
				_ok(_count(lobj) == 1, "Toriel's scene started (%d Toriels)" % _count(lobj))
				_ok(eng.vm.follow_owner == 0, "she follows player 1 (%s)" % eng.vm.follow_owner)
				mr.switch(keep)
				_end()
		"pickup":
			# The Faded Ribbon in room_ruins14: each player has their own. Player 1 takes theirs;
			# player 2's is still there for them, and they take it too.
			var ro := int(eng.vm.obj_index.get("obj_ribbon_pickup", -1))
			var copies: Array = []
			for i in eng.vm.instances:
				if not i.dead and i.obj == ro:
					copies.append(i.owner)
			copies.sort()
			if OS.get_cmdline_user_args().has("--mpverbose") and f % 20 == 0:
				print("PU f=%d p1=%s p2=%s copies=%s flags=%s %s items=%s %s int=%s %s" % [f, _at(0), _at(1), copies, _v(0, "mp_pflags"), eng.mp.value(1, "mp_pflags", {}), _items(0), _items(1), _v(0, "interact"), _v(1, "interact")])
			if f == 10:
				_ok(copies == [0, 1], "each player has their own ribbon (%s)" % [copies])
			var put := func(k: int, at: Vector2) -> void:
				var pi = eng.mp.list[k].inst
				for key in ["x", "xprevious"]:
					pi.v[key] = at.x
				for key in ["y", "yprevious"]:
					pi.v[key] = at.y
			if f == 5:
				put.call(0, Vector2(177, 663))
				put.call(1, Vector2(120, 684))
			if f == 110:
				_ok(float(_v(0, "mp_pflags").get("100", 0.0)) == 1.0 and _items(0)[0] == 12.0, "player 1 took the ribbon (flags %s, items %s)" % [_v(0, "mp_pflags"), _items(0)])
				_ok(copies == [1], "player 2's ribbon is still there (%s)" % [copies])
				_ok(float(eng.mp.value(1, "mp_pflags", {}).get("100", 0.0)) == 0.0, "player 2 hasn't taken one")
				put.call(1, Vector2(177, 663))
			if f == 240:
				_ok(float(eng.mp.value(1, "mp_pflags", {}).get("100", 0.0)) == 1.0 and _items(1)[0] == 12.0, "player 2 took their own ribbon (items %s)" % [_items(1)])
				_ok(copies.is_empty(), "no ribbons left (%s)" % [copies])
				_ok(_items(0)[0] == 12.0, "player 1 still has theirs")
				_end()
		"who":
			# In a shared battle player 1 picks ITEM, a Monster Candy, and "Who?" Greg: Greg
			# gets the 10 HP, player 1 keeps their own.
			var mr = eng.mprooms
			var bt = eng.mpbattles
			var g: Dictionary = eng.vm.globals
			var rn: String = mr.room_name(mr.room_of(0))
			if rn == "room_battle" and not seen.has("battle"):
				seen["battle"] = f
				eng.mp.set_value(0, "maxhp", 99.0)
				eng.mp.set_value(0, "hp", 90.0)
				eng.mp.set_value(1, "hp", 5.0)
			var b = bt.battles.get(mr.room_of(0))
			if rn == "room_battle":
				eng.mp.set_value(0, "invc", 30.0)
				eng.mp.set_value(1, "invc", 30.0)
			var fed: bool = bt.told.any(func(t): return String(t).begins_with("fed Greg"))
			if rn == "room_battle" and f % 6 == 0 and b != null and mr.room_of(0).lead == 0 and not fed:
				var k = eng.mp.list[0].keys
				var bm := float(g.get("bmenuno", 0.0))
				if float(g.get("myfight", 0.0)) == 0.0 and float(g.get("mnfight", 0.0)) == 0.0:
					if bm == 0.0:
						k.tap(39 if bt._bm(0) != 2.0 else 90)
					elif bm >= 3.0 and bm < 4.0:
						if b.who == 1 and not seen.has("shot"):
							seen["shot"] = true
							eng.bot_shot("who")
						k.tap(90 if b.who != 0 else 40)
					else:
						k.tap(90)
				else:
					k.tap(90)
			if fed and not seen.has("fed"):
				seen["fed"] = f
				_ok(float(_v(1, "hp")) == 15.0, "Greg got the candy's 10 HP (%s)" % _v(1, "hp"))
				_ok(float(_v(0, "hp")) == 90.0, "player 1 kept their own HP (%s)" % _v(0, "hp"))
				_ok(_items(0) == [0.0, 0.0] or float(eng.mp.value(0, "item", [[0]])[0][0]) == 0.0, "player 1's candy is gone (%s)" % [_items(0)])
				_ok(_told(1, "Kyle gave you an item: +10 HP."), "Greg was told")
			if seen.has("fed") and f == int(seen["fed"]) + 30:
				_end()
			if f == 1490 and not seen.has("fed"):
				_ok(false, "the item was used on Greg in time (%s)" % [bt.told])
				_end()
		"afk":
			# Player 2 is pulled into player 1's battle and then presses nothing: on their turn,
			# after the AFK time (1.5 s here), the menu passes back to player 1.
			var mr = eng.mprooms
			var bt = eng.mpbattles
			var g: Dictionary = eng.vm.globals
			bt.afk_frames = 45
			var rn: String = mr.room_name(mr.room_of(0))
			if rn == "room_battle" and not seen.has("battle"):
				seen["battle"] = f
				for k in 2:
					eng.mp.set_value(k, "maxhp", 99.0)
					eng.mp.set_value(k, "hp", 99.0)
			var b = bt.battles.get(mr.room_of(0))
			if rn == "room_battle" and f % 6 == 0 and b != null and mr.room_of(0).lead == 0:
				var k = eng.mp.list[0].keys
				if float(g.get("myfight", 0.0)) == 0.0 and float(g.get("mnfight", 0.0)) == 0.0 and float(g.get("bmenuno", 0.0)) == 0.0:
					k.tap(39 if bt._bm(0) != 3.0 else 90)
				else:
					k.tap(90)
			if bt.told.has("turn Greg") and not seen.has("greg"):
				seen["greg"] = f
			if bt.told.has("away Greg") and not seen.has("away"):
				seen["away"] = f
				_ok(int(f) - int(seen.get("greg", f)) >= 44, "Greg's turn lasted the AFK time (%d frames)" % (int(f) - int(seen.get("greg", f))))
				_ok(mr.room_of(0).lead == 0, "the menu went back to Kyle")
				_ok(_told(0, "Greg is away: Kyle's turn.") and _told(1, "Greg is away: Kyle's turn."), "both were told")
			if seen.has("away") and f == int(seen["away"]) + 60:
				_ok(rn == "room_battle" or bt.told.has("end won"), "the battle went on")
				_end()
			if f == 1490 and not seen.has("away"):
				_ok(false, "Greg was passed over in time (%s)" % [bt.told])
				_end()
		"leavelead":
			# Three players in one battle; player 2 leaves the game on their own turn (they are
			# the world's lead then). They must really go: out of the battle, the turn passed on,
			# and their place free for someone new.
			var mr = eng.mprooms
			var bt = eng.mpbattles
			var g: Dictionary = eng.vm.globals
			var rn: String = mr.room_name(mr.room_of(0))
			if rn == "room_battle" and not seen.has("battle"):
				seen["battle"] = f
				for k in 3:
					eng.mp.set_value(k, "maxhp", 99.0)
					eng.mp.set_value(k, "hp", 99.0)
			var r0 = mr.room_of(0)
			if rn == "room_battle" and f % 6 == 0 and bt.battles.get(r0) != null and r0.lead == 0 and seen.has("rejoined"):
				var k = eng.mp.list[0].keys
				if float(g.get("myfight", 0.0)) == 0.0 and float(g.get("mnfight", 0.0)) == 0.0 and float(g.get("bmenuno", 0.0)) == 0.0:
					k.tap(39 if bt._bm(0) != 3.0 else 90)
				else:
					k.tap(90)
			if rn == "room_battle" and not seen.has("given") and bt.battles.get(r0) != null and eng.vm.party_on and float(g.get("myfight", 0.0)) == 0.0 and float(g.get("mnfight", 0.0)) == 0.0:
				seen["given"] = f
				bt._set_lead(r0, 1)     # Greg's turn
			if seen.has("given") and not seen.has("left") and r0 != null and r0.lead == 1:
				seen["left"] = f
				eng.mp.remove_player(1)
				_ok(not eng.mp.list[1].active, "Greg is gone")
				_ok(mr.room_of(1) == null, "Greg isn't in any world")
				_ok(r0.lead != 1 and r0.members.has(r0.lead), "the turn went to someone still there (player %d)" % (r0.lead + 1))
				_ok(eng.mp.active_count() == 2, "two players left (%d)" % eng.mp.active_count())
			if seen.has("left") and f == int(seen["left"]) + 30:
				var idx: int = eng.mp.add_player("Dan")
				_ok(idx == 1, "a new friend takes the free place (player %d)" % (idx + 1))
				seen["rejoined"] = f
			if seen.has("rejoined") and f == int(seen["rejoined"]) + 60:
				_ok(eng.mp.list[1].active and eng.mp.list[1].name == "Dan" and mr.room_of(1) != null, "Dan is playing (%s)" % mr.status())
				_ok(rn == "room_battle" or bt.told.has("end won"), "the battle went on")
				_end()
			if f == 1490 and not seen.has("left"):
				_ok(false, "Greg never had the turn (%s)" % [bt.told])  # (given at the battle's first menu)
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
			# Toriel's welcome in her house waits for the party too (it starts as the room loads):
			# player 1 is asked first and says No, so it plays for player 2 alone.
			var mr = eng.mprooms
			var ui = eng.mpui
			if f == 70:
				_ok(ui.prompts.has(0), "player 2's scene in the house asks player 1 first")
			if f == 200:
				_ok(ui.waits.has(0) and String(ui.waits[0]["text"]).begins_with("Waiting for 1 more player"), "player 1 is waiting for player 2 (%s)" % [ui.waits.get(0)])
				_ok(float(_v(0, "interact")) == 0.0, "the scene hasn't started")
				_ok(not ui.prompts.has(1) and float(_v(1, "interact")) != 0.0, "player 2, still reading, isn't asked yet")
			if ui.prompts.has(1) and not seen.has("asked"):
				seen["asked"] = f
			if seen.has("asked") and not seen.has("tp") and mr.room_of(1) == mr.room_of(0):
				seen["tp"] = f
				_ok(_at(1).distance_to(_at(0)) > 12.0 and _at(1).distance_to(_at(0)) < 40.0, "player 2 stands beside player 1, not on them (%s and %s)" % [_at(1), _at(0)])
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


# The player with that name still playing, or -1.
func _index_of(nm: String) -> int:
	for p in eng.mp.list:
		if p.active and p.name == nm:
			return p.index
	return -1
