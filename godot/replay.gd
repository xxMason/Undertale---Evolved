# Checks the Godot battle rules against a recording from the real game.
#   godot --headless --path godot --script res://replay.gd -- <ube_record.txt>
# The recording (scenario "record" of UltimateBattleEngine.exe --selftest) holds, for
# every frame of a scripted attack: the keys held, the SOUL's position, HP, the
# invincibility counter, the wall positions and the bullets spawned. This replays the
# same keys and spawns through ut_sim.gd and compares every frame.
extends SceneTree

const Assets = preload("res://ut_assets.gd")
const Sim = preload("res://ut_sim.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: --script res://replay.gd -- <recording>")
		quit(2)
		return
	var assets = Assets.new()
	if not assets.load_all(ProjectSettings.globalize_path("res://extracted")):
		print("REPLAY error: ", assets.error)
		quit(2)
		return
	var lines := FileAccess.get_file_as_string(args[0]).split("\n", false)
	var recs: Array = []
	var spawns := {}      # frame index -> Array of spawn lines
	var box := {}
	var pending: Array = []
	for line in lines:
		if line.begins_with("BOX "):
			for part in line.substr(4).split(";"):
				if part.contains("="):
					var kv := part.split("=")
					box[kv[0]] = float(kv[1])
		elif line.begins_with("SPAWN "):
			pending.append(line.substr(6).split(";"))
		elif line.begins_with("REC "):
			var p := line.substr(4).split(";")
			recs.append({"f": int(p[0]), "keys": int(p[1]), "x": int(p[2]), "y": int(p[3]), "hp": int(p[4]), "invc": int(p[5]), "wl": int(p[6]), "wt": int(p[7]), "wr": int(p[8]), "wb": int(p[9]), "n": int(p[10]), "bl": (p[11] if p.size() > 11 else "")})
			if not pending.is_empty():
				spawns[recs.size() - 1] = pending
				pending = []
	var sim = Sim.new(assets)
	sim.df = int(box.get("df", 10))
	sim.adef = int(box.get("adef", 0))
	sim.inv = int(box.get("inv", 30))
	sim.sp = int(box.get("sp", 4))
	var r0: Dictionary = recs[0]
	sim.heart_x = r0["x"]
	sim.heart_y = r0["y"]
	sim.hp = r0["hp"]
	sim.invc = r0["invc"]
	var mismatches := 0
	var pos_bad := 0
	var pos_report: Array = []
	var report: Array = []
	for i in range(1, recs.size()):
		var prev: Dictionary = recs[i - 1]
		var cur: Dictionary = recs[i]
		sim.wl = prev["wl"]
		sim.wt = prev["wt"]
		sim.wr = prev["wr"]
		sim.wb = prev["wb"]
		# Bullets created in this frame's Step already exist when collisions run.
		if spawns.has(i):
			for s in spawns[i]:
				sim.spawn(s[0], float(s[1]), float(s[2]), float(s[3]), float(s[4]), int(s[5]), float(s[6]) if s.size() > 6 else 1.0)
		sim.step(prev["keys"])
		var got := [sim.heart_x, sim.heart_y, sim.hp, sim.invc, sim.bullets.size()]
		var want := [cur["x"], cur["y"], cur["hp"], cur["invc"], cur["n"]]
		var pos_note := _compare_bullets(sim, cur["bl"])
		if pos_note != "":
			pos_bad += 1
			if pos_report.size() < 8:
				pos_report.append("frame %d  %s" % [cur["f"], pos_note])
		if got != want:
			mismatches += 1
			if report.size() < 12:
				report.append("frame %d keys=%d  godot x,y,hp,invc,bullets=%s  game=%s" % [cur["f"], prev["keys"], str(got), str(want)])
	print("REPLAY frames=%d mismatches=%d bullet_position_mismatches=%d hits=%d final_hp=%d" % [recs.size() - 1, mismatches, pos_bad, sim.hits, sim.hp])
	for r in pos_report:
		print("  ", r)
	for r in report:
		print("  ", r)
	quit(0 if mismatches == 0 and pos_bad == 0 else 1)


# Compares bullet positions with the recording (printed to 6 decimals there).
func _compare_bullets(sim, field: String) -> String:
	if field == "":
		return ""
	var want := field.split("|", false)
	if want.size() != sim.bullets.size():
		return ""
	for i in want.size():
		var xy := want[i].split(",")
		var gx := float(xy[0])
		var gy := float(xy[1])
		var b: Dictionary = sim.bullets[i]
		if absf(b["x"] - gx) > 0.00001 or absf(b["y"] - gy) > 0.00001:
			return "bullet %d godot=(%.6f, %.6f) game=(%.6f, %.6f)" % [i, b["x"], b["y"], gx, gy]
	return ""
