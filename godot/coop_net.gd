# LAN co-op: the link between the host's PC and a friend's, in lockstep.
#
# Both PCs run the whole game, frame for frame, and only send each other their keys. A
# frame runs once both PCs' keys for it have arrived; keys are sent DELAY frames ahead, so
# on a LAN neither PC normally waits. When a friend joins, the host sends the whole game
# state once (coop_state.gd) plus its universe's save files; after that, every SUM_EVERY
# frames both compare a fingerprint of the state, and if they ever differ the host sends
# its state again and the friend's PC snaps to it.
#
# Anything both PCs must share (pause, game speed) is the host's to change.
#
# Finding games: a host announces itself on the LAN every second (UDP broadcast on
# BEACON_PORT); the Join screen lists what it hears. Join by IP covers networks that
# block broadcasts, and virtual LANs such as Tailscale or Radmin VPN.
extends Node

const CoopState = preload("res://coop_state.gd")
const Info = preload("res://engine_info.gd")
const Universes = preload("res://universes.gd")

const PORT := 7777
const BEACON_PORT := 7778
const DELAY_DEFAULT := 3
# Tests: --coopdelay 1 on both PCs, so a bot's keys land on the frame it chose them for.
var DELAY := DELAY_DEFAULT
const SUM_EVERY := 30
const KEEP := 120            # frames of keys kept, to replay after snapping to the host's state
const PROTOCOL := 1

var eng
var role := ""               # "host", "client", or "" when not in co-op
var conn: ENetConnection = null
var link: ENetPacketPeer = null   # the other PC
var partner: Dictionary = {}       # {"id", "name"} of the other player
var linked := false                # lockstep running
var frame := 0                     # the next frame both PCs run (eng.frames + 1)
var mine := {}                     # frame -> key codes from this PC
var theirs := {}                   # frame -> key codes from the other PC
# Commands that travel with the keys (a friend's own-character cheats): run on both PCs at
# the same frame, so they never put the games out of step.
var cmd_queue: Array = []
var cmd_mine := {}
var cmd_theirs := {}
var sums := {}                     # frame -> {"mine": h, "theirs": h}
var stall := 0                     # ticks spent waiting for the other PC's keys
var speed := 1.0                   # the host's game speed (both PCs run it)
var host_paused := false
var _acc := 0.0
var resyncs := 0
var mismatches := 0
var frames_run := 0

var beacon: PacketPeerUDP = null
var local_beacon: PacketPeerUDP = null
var _beacons := 0
var _beacon_ms := 0
var listen: PacketPeerUDP = null
var found := {}                    # "ip:port" -> beacon info + "ip", "seen"
var join_state := ""               # client: "", "connecting", "waiting", "refused", "failed"
var join_why := ""
var _join_ms := 0
var test_log := false


func setup(e) -> void:
	eng = e
	test_log = OS.get_cmdline_user_args().has("--cooplog")
	var a := OS.get_cmdline_user_args()
	var d := a.find("--coopdelay")
	if d >= 0 and d + 1 < a.size():
		DELAY = maxi(1, int(a[d + 1]))


func active() -> bool:
	return role != ""


func is_host() -> bool:
	return role == "host"


func is_client() -> bool:
	return role == "client"


func _log(s: String) -> void:
	if test_log:
		print("COOP %s f=%d %s" % [role, eng.frames, s])


# ------------------------------------------------------------------ what each PC checks

static func data_id() -> String:
	var p := ProjectSettings.globalize_path("res://extracted/engine.json")
	return FileAccess.get_md5(p)


# --fakever V (tests): claim another version, to check that joining is refused.
func _my_version() -> String:
	var i := OS.get_cmdline_user_args().find("--fakever")
	return OS.get_cmdline_user_args()[i + 1] if i >= 0 else Info.VERSION


func mods_id() -> Array:
	var out: Array = []
	for m in eng.mods.get("mods", []):
		out.append("%s@%s" % [m["id"], m["version"]])
	out.sort()
	return out


# ------------------------------------------------------------------ hosting

func start_host(port := PORT) -> String:
	stop()
	conn = ENetConnection.new()
	var err := conn.create_host_bound("*", port, 2, 2)
	if err != OK:
		conn = null
		return "Couldn't open port %d for co-op (error %d). Is another copy already hosting?" % [port, err]
	role = "host"
	beacon = PacketPeerUDP.new()
	beacon.set_broadcast_enabled(true)
	beacon.set_dest_address("255.255.255.255", BEACON_PORT)
	_log("hosting on port %d" % port)
	return ""


# Friends who have a character saved in this universe: {id: {"gold", "items"}}, so their
# Join card can say what they'll come back as.
func _known() -> Dictionary:
	var out := {}
	var fr: Dictionary = eng.coop_friends()
	for id in fr:
		var pr: Dictionary = (fr[id] as Dictionary).get("profile", {})
		var n := 0
		var it = pr.get("item", [[]])
		if it is Array and not it.is_empty() and it[0] is Array:
			for v in it[0]:
				if float(v) != 0.0:
					n += 1
		out[id] = {"gold": int(pr.get("gold", 0)), "items": n}
	return out


func _announce() -> void:
	if beacon == null or Time.get_ticks_msec() - _beacon_ms < 1000:
		return
	_beacon_ms = Time.get_ticks_msec()
	var u: Dictionary = eng.universe
	var lvl := int(eng.vm.globals.get("lv", 1.0))
	var info := {
		"ube": PROTOCOL, "ver": Info.VERSION, "port": conn.get_local_port() if conn != null else PORT,
		"host": eng.player()["name"], "host_id": eng.player()["id"],
		"universe": Universes.display_name(u) if not u.is_empty() else "", "universe_id": u.get("id", ""),
		"lv": lvl, "gold": int(eng.vm.globals.get("gold", 0.0)),
		"room": eng.room_title(eng.vm.room) if eng.vm.room >= 0 else "",
		"full": link != null,
		"known": _known(),
	}
	var pkt := JSON.stringify(info).to_utf8_buffer()
	var err := beacon.put_packet(pkt)
	# Also to this PC itself: some networks don't hand a PC its own broadcasts.
	if local_beacon == null:
		local_beacon = PacketPeerUDP.new()
		local_beacon.set_dest_address("127.0.0.1", BEACON_PORT)
	local_beacon.put_packet(pkt)
	if test_log and _beacons < 3:
		_beacons += 1
		_log("announced: %s" % error_string(err))


# ------------------------------------------------------------------ joining

func start_listening() -> void:
	if listen != null:
		return
	listen = PacketPeerUDP.new()
	var err := listen.bind(BEACON_PORT)
	_log("listening for games on port %d: %s" % [BEACON_PORT, error_string(err)])
	if err != OK:
		listen = null


func stop_listening() -> void:
	if listen != null:
		listen.close()
		listen = null


func games() -> Array:
	var out: Array = []
	var now := Time.get_ticks_msec()
	for k in found.keys():
		if now - int(found[k]["seen"]) > 4000:
			found.erase(k)
		else:
			out.append(found[k])
	out.sort_custom(func(a, b): return String(a.get("host", "")) < String(b.get("host", "")))
	return out


func _hear() -> void:
	if listen == null:
		return
	while listen.get_available_packet_count() > 0:
		var pkt := listen.get_packet()
		var ip := listen.get_packet_ip()
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if not (d is Dictionary) or int(d.get("ube", 0)) != PROTOCOL:
			continue
		if String(d.get("host_id", "")) == eng.player()["id"]:
			continue     # ourselves
		d["ip"] = ip
		d["seen"] = Time.get_ticks_msec()
		# One entry per host (it's heard both over the network and, on this same PC, directly):
		# its network address is kept over 127.0.0.1.
		var key := "%s:%d" % [d.get("host_id", ""), int(d.get("port", PORT))]
		if not found.has(key):
			_log("heard %s's game at %s" % [d.get("host", "?"), ip])
		elif ip == "127.0.0.1" and String(found[key]["ip"]) != "127.0.0.1":
			d["ip"] = found[key]["ip"]
		found[key] = d


func join(ip: String, port := PORT) -> void:
	stop()
	conn = ENetConnection.new()
	if conn.create_host(1, 2) != OK:
		join_state = "failed"
		join_why = "Couldn't start the network."
		conn = null
		return
	link = conn.connect_to_host(ip, port, 2)
	if link == null:
		join_state = "failed"
		join_why = "Couldn't reach " + ip
		conn = null
		return
	role = "client"
	join_state = "connecting"
	join_why = ""
	_join_ms = Time.get_ticks_msec()
	_log("joining %s:%d" % [ip, port])


func cancel_join() -> void:
	if role == "client" and not linked:
		stop()
	join_state = ""


# ------------------------------------------------------------------ the link

func stop() -> void:
	if link != null:
		link.peer_disconnect_now()
	link = null
	if conn != null:
		conn.destroy()
	conn = null
	if beacon != null:
		beacon.close()
	beacon = null
	role = ""
	linked = false
	partner = {}
	mine.clear()
	theirs.clear()
	sums.clear()
	host_paused = false
	speed = 1.0


func _send(msg: Dictionary) -> void:
	if link != null:
		link.send(0, var_to_bytes(msg), ENetPacketPeer.FLAG_RELIABLE)


func service() -> void:
	_hear()
	if conn == null:
		return
	if role == "host":
		_announce()
	if role == "client" and join_state == "connecting" and Time.get_ticks_msec() - _join_ms > 8000:
		var who := ""
		stop()
		join_state = "failed"
		join_why = "No answer. Check the address, and that the host's firewall lets the engine through." + who
		return
	for guard in 200:
		var ev: Array = conn.service(0)
		var kind: int = ev[0]
		if kind == ENetConnection.EVENT_NONE:
			break
		var peer: ENetPacketPeer = ev[1]
		match kind:
			ENetConnection.EVENT_CONNECT:
				if role == "host":
					if link != null:
						peer.peer_disconnect_later()     # already playing with someone
					else:
						link = peer
				else:
					join_state = "waiting"
					_send({"t": "hello", "proto": PROTOCOL, "ver": _my_version(), "data": data_id(), "mods": mods_id(), "player": eng.player()})
			ENetConnection.EVENT_DISCONNECT:
				if peer == link:
					_lost()
					if conn == null:
						return
			ENetConnection.EVENT_RECEIVE:
				if peer == link:
					var m = bytes_to_var(peer.get_packet())
					if m is Dictionary:
						_on(m)
						if conn == null:
							return
				else:
					peer.get_packet()
			ENetConnection.EVENT_ERROR:
				if role == "client" and not linked:
					stop()
					join_state = "failed"
					join_why = "The connection failed."
					return


func _lost() -> void:
	var who := String(partner.get("name", "Your friend"))
	var who_id := String(partner.get("id", ""))
	_log("link lost")
	if role == "host":
		link = null
		linked = false
		partner = {}
		mine.clear()
		theirs.clear()
		sums.clear()
		eng.coop_partner_left(who, who_id)
	else:
		var was_linked := linked
		link = null     # already gone
		stop()
		if was_linked:
			eng.coop_host_lost(who)
		elif join_state != "refused":
			join_state = "failed"
			join_why = "The host closed the connection."


func _on(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"hello":
			_on_hello(m)
		"refuse":
			join_state = "refused"
			join_why = String(m.get("why", ""))
			_log("refused: " + join_why)
		"welcome":
			_on_welcome(m)
		"in":
			theirs[int(m["f"])] = m["k"]
			if m.has("c"):
				cmd_theirs[int(m["f"])] = m["c"]
		"sum":
			var f := int(m["f"])
			if not sums.has(f):
				sums[f] = {}
			sums[f]["theirs"] = int(m["h"])
			_compare(f)
		"resync":
			if role == "host":
				_send_state("snap")
		"snap":
			_on_snap(m)
		"pause":
			host_paused = bool(m["on"])
			eng._toast(("Paused by " + String(partner.get("name", "the host"))) if host_paused else "Resumed", 2500)
		"speed":
			speed = float(m["x"])


# The host decides who may join: same engine, same game data, same mods.
func _on_hello(m: Dictionary) -> void:
	var p: Dictionary = m.get("player", {})
	var who := String(p.get("name", "?"))
	var why := ""
	if int(m.get("proto", 0)) != PROTOCOL or String(m.get("ver", "")) != Info.VERSION:
		why = "%s has version %s; you have %s. Whoever is older: run update.bat." % [eng.player()["name"], Info.VERSION, String(m.get("ver", "?"))]
	elif String(m.get("data", "")) != data_id():
		why = "Your game data differs from %s's. Both run setup again (clean.bat, then play.bat)." % eng.player()["name"]
	elif m.get("mods", []) != mods_id():
		why = "Your mods differ from %s's: %s. Use the same mods to play together." % [eng.player()["name"], ", ".join(mods_id()) if not mods_id().is_empty() else "none"]
	elif String(p.get("id", "")) == eng.player()["id"]:
		why = "That's this same copy of the engine."
	if why != "":
		_log("refusing %s: %s" % [who, why])
		_send({"t": "refuse", "why": why})
		link.peer_disconnect_later()
		link = null
		return
	partner = {"id": String(p.get("id", "")), "name": who}
	_log("welcoming " + who)
	eng.coop_partner_joined(partner)
	_send_state("welcome")
	_begin_lockstep(eng.frames + 1)


func _send_state(kind: String) -> void:
	# f: the lockstep frame this state is the end of; ef: the game's own frame counter, which a
	# game over sets back to 0.
	var msg := {"t": kind, "f": (frame - 1) if linked else eng.frames, "ef": eng.frames, "state": CoopState.pack(eng), "host": eng.player()}
	if kind == "welcome":
		msg["universe"] = {"id": eng.universe.get("id", ""), "name": Universes.display_name(eng.universe) if not eng.universe.is_empty() else "", "cheats": bool(eng.universe.get("cheats", true)) if not eng.universe.is_empty() else true}
		msg["files"] = eng.coop_save_files()
		msg["speed"] = speed
		msg["paused"] = eng.paused
	_send(msg)
	_log("sent %s at frame %d" % [kind, eng.frames])


func _begin_lockstep(at: int) -> void:
	linked = true
	frame = at
	mine.clear()
	theirs.clear()
	sums.clear()
	for f in range(frame, frame + DELAY):
		mine[f] = []
		theirs[f] = []
	stall = 0
	_acc = 0.0


func _on_welcome(m: Dictionary) -> void:
	partner = {"id": String(m["host"].get("id", "")), "name": String(m["host"].get("name", "?"))}
	join_state = ""
	speed = float(m.get("speed", 1.0))
	host_paused = bool(m.get("paused", false))
	eng.coop_join_start(m)
	_begin_lockstep(int(m["f"]) + 1)
	_log("joined at frame %d" % eng.frames)


func _on_snap(m: Dictionary) -> void:
	var f := int(m["f"])
	resyncs += 1
	eng.coop_apply_state(m["state"], int(m.get("ef", f)))
	frame = f + 1
	# Keys this PC never sent for the frames ahead (it may have been behind): none.
	for g in range(frame, frame + DELAY):
		if not mine.has(g):
			mine[g] = []
			_send({"t": "in", "f": g, "k": []})
	for k in sums.keys():
		if int(k) <= f:
			sums.erase(k)
	_log("snapped to the host's frame %d" % f)


func _compare(f: int) -> void:
	var s: Dictionary = sums.get(f, {})
	if not (s.has("mine") and s.has("theirs")):
		return
	sums.erase(f)
	if s["mine"] != s["theirs"]:
		mismatches += 1
		_log("DESYNC at frame %d" % f)
		if role == "client":
			_send({"t": "resync"})


# ------------------------------------------------------------------ lockstep, every tick

# Runs this tick's frames when the other PC's keys are in. Returns false when not linked
# (the engine then runs the game as usual).
func tick() -> bool:
	service()
	if not linked:
		return false
	if role == "host" and eng.paused != host_paused:
		host_paused = eng.paused
		_send({"t": "pause", "on": host_paused})
	if role == "host" and eng.game_speed != speed:
		speed = eng.game_speed
		_send({"t": "speed", "x": speed})
	if host_paused:
		if role == "host" and eng.step_once:
			eng.step_once = false
			_step()
		return true
	_acc += speed
	var n := mini(int(_acc), 8)
	_acc -= int(_acc)
	var ran := 0
	for k in n:
		if _step():
			ran += 1
		else:
			_acc = 0.0
			break
	stall = 0 if ran > 0 or n == 0 else stall + 1
	return true


func _sample(f: int) -> void:
	if mine.has(f):
		return
	var k: Array = eng.coop_local_keys(f)
	mine[f] = k
	var msg := {"t": "in", "f": f, "k": k}
	if not cmd_queue.is_empty():
		cmd_mine[f] = cmd_queue
		msg["c"] = cmd_queue
		cmd_queue = []
	_send(msg)


func _step() -> bool:
	_sample(frame + DELAY - 1)
	if not (mine.has(frame) and theirs.has(frame)):
		return false
	var hk: Array = mine[frame] if role == "host" else theirs[frame]
	var ck: Array = theirs[frame] if role == "host" else mine[frame]
	var hc: Array = cmd_mine.get(frame, []) if role == "host" else cmd_theirs.get(frame, [])
	var cc: Array = cmd_theirs.get(frame, []) if role == "host" else cmd_mine.get(frame, [])
	if not hc.is_empty() or not cc.is_empty():
		eng.coop_commands(hc, cc)
	cmd_mine.erase(frame)
	cmd_theirs.erase(frame)
	eng.coop_run_frame(hk, ck)
	frames_run += 1
	if frame % SUM_EVERY == 0:
		if not sums.has(frame):
			sums[frame] = {}
		sums[frame]["mine"] = CoopState.checksum(eng)
		_send({"t": "sum", "f": frame, "h": sums[frame]["mine"]})
		_compare(frame)
	mine.erase(frame - KEEP)
	theirs.erase(frame - KEEP)
	frame += 1
	_sample(frame + DELAY - 1)
	return true


# Queues a command to go with this PC's next keys.
func send_cmd(c: Dictionary) -> void:
	cmd_queue.append(c)


func waiting_text() -> String:
	if linked and stall > 15:
		return "Waiting for %s..." % partner.get("name", "your friend")
	return ""
