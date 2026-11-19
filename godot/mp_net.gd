# Multiplayer over the network, the host runs the game (docs/MULTIPLAYER.md, stage 4).
#
# Only the host runs the game. Every other PC sends the keys its player holds, and gets
# back the picture of its own screen each frame: the drawing commands the host recorded
# (gml_recorder.gd) without other players' private drawing, plus the sounds that player
# hears. Textures travel by name ("s12:3" is sprite 12, frame 3), so each PC draws them from
# its own Undertale files and nothing from Undertale goes over the network.
#
# Channels: 0 reliable (hello, welcome, refusals, notices), 1 keys (unreliable, newest
# wins, but every frame's keys are queued on the host so a quick tap is never lost),
# 2 frames (unreliable, newest wins).
extends RefCounted

const MpPlayers = preload("res://mp_players.gd")
const Recorder = preload("res://gml/gml_recorder.gd")
const Universes = preload("res://universes.gd")

const PORT := 7790
const BEACON_PORT := 7789  # the host says "a game is here" on the local network once a second
const PROTOCOL := 1
const OPS := ["@owner", "@gui", "draw_set_transform", "draw_texture", "draw_texture_rect",
	"draw_texture_rect_region", "draw_rect", "draw_line", "draw_arc", "draw_circle",
	"draw_polyline", "draw_colored_polygon"]
# Which argument of each op is a texture.
const TEX_ARG := {"draw_texture": 0, "draw_texture_rect": 0, "draw_texture_rect_region": 0}
const KEY_QUEUE := 4       # host: frames of a friend's keys kept waiting at most
const BUFFER := 1          # friend: frames held back to even out the network's timing
const HELLO_WAIT_MS := 5000

var eng
var role := ""             # "host", "client" or ""
var conn: ENetConnection = null
var password := ""
var kicked := {}            # names (lower case) the host removed: not let back in this session
var log_on := false

# Host: peer -> {"index", "name", "keys": [frame key lists], "held", "frames_sent", "bytes"}
var peers := {}
var _sent_frame := -1
var _op_index := {}

# Client
var link: ENetPacketPeer = null
var me := -1               # my player index on the host
var state := ""            # "connecting", "waiting", "playing", "refused", "lost"
var why := ""
var _queue: Array = []     # frames received, oldest first
var _tex := {}             # texture name -> Texture2D
var _sounds := {}          # host sound id -> {"player", "sound"}
var _sent_keys := 0
var _hello_ms := 0
var _my_name := ""
var _my_pw := ""
var stats := {"frames": 0, "bytes": 0, "late": 0, "dropped": 0, "repeats": 0, "jerks": 0}

# Testing a bad network on a friend's PC: --netloss PCT drops that share of the frames coming
# in and the keys going out; --netlag MS holds both back that long, --netjitter MS up to that
# much more at random (so packets also arrive out of order).
var sim_loss := 0.0
var sim_lag := 0
var sim_jitter := 0
var _sim_rng := RandomNumberGenerator.new()
var _sim_in: Array = []      # [due msec, frame bytes]
var _sim_out: Array = []     # [due msec, key bytes]


func setup(e) -> void:
	eng = e
	var args := OS.get_cmdline_user_args()
	log_on = args.has("--netlog")
	for opt in ["--netloss", "--netlag", "--netjitter"]:
		var k := args.find(opt)
		if k >= 0 and k + 1 < args.size():
			match opt:
				"--netloss": sim_loss = float(args[k + 1]) / 100.0
				"--netlag": sim_lag = int(args[k + 1])
				"--netjitter": sim_jitter = int(args[k + 1])
	_sim_rng.seed = 4242
	for k in OPS.size():
		_op_index[OPS[k]] = k


func _log(s: String) -> void:
	if log_on:
		print("NET %s f=%d %s" % [role, eng.frames, s])


func active() -> bool:
	return role != ""


func is_host() -> bool:
	return role == "host"


func is_client() -> bool:
	return role == "client"


# ---------------------------------------------------------------- host

# Starts hosting the game already running on this PC. The host is player 1.
func start_host(port := PORT, pw := "") -> String:
	conn = ENetConnection.new()
	var err := conn.create_host_bound("*", port, 3, 3)
	if err != OK:
		conn = null
		return "Could not open port %d (error %d)." % [port, err]
	conn.compress(ENetConnection.COMPRESS_ZSTD)
	role = "host"
	password = pw
	beacon = PacketPeerUDP.new()
	beacon.set_broadcast_enabled(true)
	beacon.set_dest_address("255.255.255.255", BEACON_PORT)
	if eng.mp == null:
		eng.mp = MpPlayers.new()
		eng.mp.setup(eng, [eng.net_name()])
		eng.mp_started()
	_log("hosting on port %d" % port)
	return ""


func _host_service() -> void:
	_announce()
	while true:
		var ev: Array = conn.service()
		var t: int = ev[0]
		if t == ENetConnection.EVENT_NONE or t == ENetConnection.EVENT_ERROR:
			break
		var peer: ENetPacketPeer = ev[1]
		if t == ENetConnection.EVENT_CONNECT:
			peers[peer] = {"index": -1, "name": "", "keys": [], "held": [], "since": Time.get_ticks_msec(), "bytes": 0, "frames": 0}
			_log("connection from %s" % peer.get_remote_address())
		elif t == ENetConnection.EVENT_DISCONNECT:
			_host_lost(peer)
		elif t == ENetConnection.EVENT_RECEIVE:
			var ch: int = ev[3]
			var data := peer.get_packet()
			if not peers.has(peer):
				continue
			if ch == 1:
				_host_keys(peer, data)
			else:
				var m = bytes_to_var(data)
				if m is Dictionary:
					_host_msg(peer, m)
	# Anyone who connected but never said hello is let go.
	for peer in peers.keys():
		if peers[peer]["index"] < 0 and Time.get_ticks_msec() - int(peers[peer]["since"]) > HELLO_WAIT_MS:
			peer.peer_disconnect_now(0)
			peers.erase(peer)


# ---------------------------------------------------------------- finding games (LAN)

var beacon: PacketPeerUDP = null
var _local_beacon: PacketPeerUDP = null
var _beacon_ms := 0
var listen: PacketPeerUDP = null
var found := {}            # "host id:port" -> what its beacon said, plus "ip" and "seen"


func _announce() -> void:
	if beacon == null or Time.get_ticks_msec() - _beacon_ms < 1000:
		return
	_beacon_ms = Time.get_ticks_msec()
	var u: Dictionary = eng.universe
	var n: int = eng.mp.active_count() if eng.mp != null else 1
	var info := {
		"ube_mp": PROTOCOL, "ver": eng.coop._my_version(), "port": conn.get_local_port() if conn != null else PORT,
		"host": eng.net_name(), "host_id": String(eng.player().get("id", "")),
		"universe": Universes.display_name(u) if not u.is_empty() else "",
		"lv": int(eng.vm.globals.get("lv", 1.0)),
		"room": eng.room_title(eng.vm.room) if eng.vm.room >= 0 else "",
		"players": n, "max": MpPlayers.MAX, "locked": password != "",
	}
	var pkt := JSON.stringify(info).to_utf8_buffer()
	beacon.put_packet(pkt)
	# Also to this PC itself: some networks don't hand a PC its own broadcasts.
	if _local_beacon == null:
		_local_beacon = PacketPeerUDP.new()
		_local_beacon.set_dest_address("127.0.0.1", BEACON_PORT)
	_local_beacon.put_packet(pkt)


func start_listening() -> void:
	if listen != null:
		return
	listen = PacketPeerUDP.new()
	if listen.bind(BEACON_PORT) != OK:
		listen = null


func stop_listening() -> void:
	if listen != null:
		listen.close()
		listen = null
	found.clear()


# Games heard in the last 4 seconds, by host name.
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
		if not (d is Dictionary) or int(d.get("ube_mp", 0)) != PROTOCOL:
			continue
		if String(d.get("host_id", "")) == String(eng.player().get("id", "")) and not OS.get_cmdline_user_args().has("--jointest"):
			continue     # ourselves
		d["ip"] = ip
		d["seen"] = Time.get_ticks_msec()
		# One entry per host (on this same PC it's heard twice): its network address is kept
		# over 127.0.0.1.
		var key := "%s:%d" % [d.get("host_id", ""), int(d.get("port", PORT))]
		if found.has(key) and ip == "127.0.0.1" and String(found[key]["ip"]) != "127.0.0.1":
			d["ip"] = found[key]["ip"]
		found[key] = d


# On the title screen: games heard, and a join in progress.
func menu_service() -> void:
	_hear()
	if role == "client" and conn != null and state != "playing":
		_client_service()


# The host sends a player away (the player menu's Kick).
func kick(index: int) -> void:
	for peer in peers:
		if int(peers[peer]["index"]) == index:
			peers[peer]["kicked"] = true
			kicked[String(peers[peer]["name"]).to_lower()] = true
			_refuse(peer, "%s removed you from the game." % eng.net_name())


# A chat line typed on this PC: a friend's goes to the host, the host's straight to everyone.
func chat(text: String) -> void:
	if role == "client" and link != null and state == "playing":
		link.send(0, var_to_bytes({"t": "chat", "text": text}), ENetPacketPeer.FLAG_RELIABLE)
	elif role == "host":
		_chat_from(0, text)


# The host passes player i's line on to everyone (and shows it here).
func _chat_from(i: int, text: String) -> void:
	text = text.strip_edges().left(eng.Chat.MAX_LEN)
	if text == "" or eng.mp == null or i >= eng.mp.list.size():
		return
	var nm: String = eng.mp.list[i].name
	eng.chat.add(i, nm, text)
	for peer in peers:
		if int(peers[peer]["index"]) >= 0:
			_send(peer, {"t": "chat", "i": i, "name": nm, "text": text})


# This PC's player opened or closed the pause menu: a friend's PC tells the host.
func set_paused(on: bool) -> void:
	if role == "client" and link != null and state == "playing":
		link.send(0, var_to_bytes({"t": "pause", "on": on}), ENetPacketPeer.FLAG_RELIABLE)


# The host's new password: friends already in stay; anyone joining needs the new one.
func set_password(pw: String) -> void:
	password = pw


func _send(peer: ENetPacketPeer, m: Dictionary) -> void:
	peer.send(0, var_to_bytes(m), ENetPacketPeer.FLAG_RELIABLE)


func _refuse(peer: ENetPacketPeer, reason: String) -> void:
	_send(peer, {"t": "refused", "why": reason})
	peer.peer_disconnect_later(0)
	_log("refused: " + reason)


func _host_msg(peer: ENetPacketPeer, m: Dictionary) -> void:
	match str(m.get("t", "")):
		"hello":
			if int(peers[peer]["index"]) >= 0:
				return      # already playing: a second hello is ignored
			if not (m.get("proto") is int) or int(m["proto"]) != PROTOCOL or str(m.get("v", "")) != eng.coop._my_version():
				_refuse(peer, "Different versions: the host has %s, you have %s. Run update.bat." % [eng.coop._my_version(), m.get("v", "?")])
				return
			if typeof(m.get("mods", [])) != typeof(eng.coop.mods_id()) or m.get("mods", []) != eng.coop.mods_id():
				_refuse(peer, "Different mods: everyone needs the same ones as the host.")
				return
			if password != "" and str(m.get("pw", "")) != password:
				_refuse(peer, "Wrong password.")
				return
			var nm := str(m.get("name", "")).strip_edges().left(12)
			if nm == "":
				nm = "Friend"
			if kicked.has(nm.to_lower()):
				_refuse(peer, "You were removed from this game.")
				return
			for p in eng.mp.list:
				if p.active and p.name == nm:
					nm = nm.left(10) + str(p.index + 2)
			var idx: int = eng.mp.add_player(nm)
			if idx < 0:
				_refuse(peer, "The game is full (4 players).")
				return
			peers[peer]["index"] = idx
			peers[peer]["name"] = nm
			eng.mp.list[idx].feed = func() -> Array: return _keys_for(peer)
			_send(peer, {"t": "welcome", "index": idx, "name": nm})
			notice("%s joined." % nm)
			_log("%s is player %d" % [nm, idx + 1])
		"bye":
			_host_lost(peer)
		"pause":
			var i := int(peers[peer]["index"])
			if i >= 0 and i < eng.mp.list.size():
				eng.mp.list[i].paused = m.get("on") is bool and bool(m["on"])
		"chat":
			var i := int(peers[peer]["index"])
			if i >= 0 and m.get("text") is String and _chat_allowed(peers[peer]):
				_chat_from(i, String(m["text"]))


# At most CHAT_BURST lines in CHAT_WINDOW_MS from one friend; the rest are dropped, so
# nobody can flood everyone's screen (or the network) with lines.
const CHAT_BURST := 5
const CHAT_WINDOW_MS := 4000


func _chat_allowed(p: Dictionary) -> bool:
	var now := Time.get_ticks_msec()
	var times: Array = p.get("chat_at", [])
	while not times.is_empty() and now - int(times[0]) > CHAT_WINDOW_MS:
		times.pop_front()
	if times.size() >= CHAT_BURST:
		return false
	times.append(now)
	p["chat_at"] = times
	return true


func _host_lost(peer: ENetPacketPeer) -> void:
	if not peers.has(peer):
		return
	var p: Dictionary = peers[peer]
	peers.erase(peer)
	if int(p["index"]) >= 0:
		eng.mp.remove_player(int(p["index"]))
		notice(("%s was removed." if p.get("kicked", false) else "%s left.") % p["name"])
		_log("%s left" % p["name"])


# Keys: [first frame number, [codes], [codes], ...] - the last few frames, newest last.
func _host_keys(peer: ENetPacketPeer, data: PackedByteArray) -> void:
	var a = bytes_to_var(data)
	if not (a is Array) or a.size() < 2:
		return
	if not (a[0] is int or a[0] is float):
		return
	var p: Dictionary = peers[peer]
	var first := int(a[0])
	var last_seen := int(p.get("kf", -1))
	for k in range(1, a.size()):
		var f := first + k - 1
		if f > last_seen:
			p["keys"].append([f, _allowed(a[k])])
			last_seen = f
	p["kf"] = last_seen
	# A friend far behind (or sending too much) never builds up more than a few seconds.
	if (p["keys"] as Array).size() > KEYS_KEPT:
		p["keys"] = (p["keys"] as Array).slice(-KEYS_KEPT)
	while p["keys"].size() > KEY_QUEUE:
		p["keys"].pop_front()


# Keys a friend's PC may give the game: not Esc (held, Undertale ends the game, the host's and
# everyone's; a friend leaves with it on their own PC) nor the F keys (fullscreen, debug).
const KEYS_KEPT := 90      # frames of a friend's keys waiting at most (3 s)


func _allowed(held) -> Array:
	var out: Array = []
	if held is Array:
		for c in held:
			if out.size() >= 16 or not (c is int or c is float):
				break
			var k := int(c)
			if k != 27 and (k < 112 or k > 123):
				out.append(k)
	return out


# A friend's keys for this frame: the oldest waiting frame, or what they held last.
func _keys_for(peer: ENetPacketPeer) -> Array:
	if not peers.has(peer):
		return []
	var p: Dictionary = peers[peer]
	var q: Array = p["keys"]
	# Frames this PC already played with the friend's held keys while waiting for theirs:
	# those frames, when they come with the same keys, were played, so a held key lasts as
	# long as the friend held it.
	while int(p.get("ahead", 0)) > 0 and not q.is_empty():
		if q[0][1] != p["held"]:
			p["ahead"] = 0
			break
		p["ack"] = q.pop_front()[0]
		p["ahead"] = int(p["ahead"]) - 1
	# A backlog (from joining, or a burst of packets) would delay every key after it: frames
	# holding the same keys as the next one are merged, so no tap is ever lost.
	while q.size() > 2 and q[0][1] == q[1][1]:
		q.pop_front()
	if not q.is_empty():
		var e: Array = q.pop_front()
		p["ack"] = e[0]
		p["held"] = e[1]
	elif not (p["held"] as Array).is_empty():
		p["ahead"] = mini(int(p.get("ahead", 0)) + 1, 6)
	return p["held"]


# After the host's game frames this tick: every friend gets the newest frame.
func _host_send() -> void:
	if eng.frames == _sent_frame:
		return
	_sent_frame = eng.frames
	for peer in peers:
		var p: Dictionary = peers[peer]
		if int(p["index"]) < 0:
			continue
		var data := encode_frame(int(p["index"]))
		peer.send(2, data, ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT)
		p["bytes"] += data.size()
		p["frames"] += 1
		if int(p["frames"]) % 30 == 1:
			# What it costs on the wire (ENet compresses it the same way).
			p["zlast"] = data.compress(FileAccess.COMPRESSION_ZSTD).size()


# A notice every player sees ("Greg joined."): shown on the host, sent to everyone.
func notice(text: String) -> void:
	if eng.has_method("mp_notice"):
		eng.mp_notice(text)
	if role == "host":
		for peer in peers:
			if int(peers[peer]["index"]) >= 0:
				_send(peer, {"t": "notice", "text": text})


# A notice on one player's screen: this PC's player (the host's, index 0), or a friend's.
func tell(index: int, text: String) -> void:
	if index == 0:
		if eng.has_method("mp_notice"):
			eng.mp_notice(text)
		return
	for peer in peers:
		if int(peers[peer]["index"]) == index:
			_send(peer, {"t": "notice", "text": text})
			return
	print("NOTICE to player %d: %s" % [index + 1, text])


# ---------------------------------------------------------------- frames

# Player `who`'s screen this frame, as bytes: a small header (var_to_bytes) and the drawing
# packed by _put (about a third of var_to_bytes' size before compression).
func encode_frame(who: int) -> PackedByteArray:
	var pl = eng.mp.list[who]
	# The world they're in (players can be in different rooms, mp_rooms.gd).
	var rooms = eng.mprooms
	var r = rooms.room_of(who) if rooms != null else null
	var here: bool = r == null or r == rooms.cur
	var rec = eng.rec if r == null else r.rec
	var lead: int = eng.mp.primary if r == null else r.lead
	var b := StreamPeerBuffer.new()
	var skip := false
	var n := 0
	for op in rec.ops:
		var name: String = op[0]
		if name == "@owner":
			var meta: Array = op[1]
			var id: int = meta[0]
			var tag: int = meta[1] if meta.size() > 1 else -1
			skip = tag >= 0 and tag != who
			if skip:
				continue
			b.put_u8(0)
			b.put_32(id)
			_put_v2(b, rec.cur_pos.get(id, Vector2.ZERO))
			b.put_8(tag)
			var anchor = meta[2] if meta.size() > 2 else null
			var fade: int = meta[3] if meta.size() > 3 and meta[3] != null else -1
			b.put_u8((0 if anchor == null else 1) | (2 if fade >= 0 and fade != who else 0))
			if anchor != null:
				_put_v2(b, anchor)
			n += 1
			continue
		if name == "@gui":
			skip = false
			b.put_u8(1)
			n += 1
			continue
		if skip:
			continue
		var args: Array = op[1]
		b.put_u8(int(_op_index.get(name, 255)))
		b.put_u8(args.size())
		for a in args:
			_put(b, a)
		n += 1
	var view: Vector2 = rec.view if who == lead else pl.view
	var vs: Dictionary = {} if here else r.w.vm_state
	var frame := {"f": eng.frames, "v": view, "sc": rec.view_scale, "n": n, "o": b.data_array,
		"s": _sounds_for(who, eng.bi.players if here else r.w.bi_state.get("players", [])),
		"rw": eng.vm.room_width if here else vs.get("room_width", 640), "rh": eng.vm.room_height if here else vs.get("room_height", 480)}
	# For the friend's own movement prediction: their character, whether it can walk, and the
	# last of their key frames the game has used.
	var inst = pl.inst
	if inst != null and not inst.dead:
		frame["me"] = inst.id
		frame["pp"] = Vector2(float(inst.v["x"]), float(inst.v["y"]))
		frame["dx"] = float(inst.v["x"]) - float(inst.v.get("xprevious", inst.v["x"]))
		frame["mv"] = float(inst.v.get("movement", 0.0)) == 1.0 and float(eng.mp.value(who, "interact")) == 0.0 and int(eng.vm.pending_room if here else vs.get("pending_room", -1)) == -1 and not (eng.mpui != null and eng.mpui.busy(who))
	elif eng.get("mpbattles") != null and r != null:
		# In a shared battle: their SOUL, moving inside the box at the battle's speed.
		var h = eng.mpbattles.heart_for(who, r, here)
		if h != null:
			var ib = eng.mp.value(lead, "idealborder", null)
			var row: Array = ib[0] if ib is Array and not ib.is_empty() and ib[0] is Array and (ib[0] as Array).size() >= 4 else []
			frame["me"] = h.id
			frame["pp"] = Vector2(float(h.v["x"]), float(h.v["y"]))
			frame["dx"] = float(h.v["x"]) - float(h.v.get("xprevious", h.v["x"]))
			frame["mv"] = float(h.v.get("movement", 0.0)) == 1.0 and float(eng.mp.value(lead, "mnfight", 0.0)) == 2.0 and not row.is_empty()
			frame["spd"] = float(eng.mp.value(lead, "sp", 4.0))
			if not row.is_empty():
				frame["box"] = [float(row[0]) + 4.0, float(row[1]) - 16.0, float(row[2]) + 4.0, float(row[3]) - 16.0]
	if eng.mpui != null:
		var ust: Dictionary = eng.mpui.state_for(who)
		if not ust.is_empty():
			frame["ui"] = ust
	for peer in peers:
		if int(peers[peer]["index"]) == who:
			frame["ack"] = int(peers[peer].get("ack", -1))
	return var_to_bytes(frame)


func _put_v2(b: StreamPeerBuffer, v: Vector2) -> void:
	b.put_float(v.x)
	b.put_float(v.y)


# One argument: a type byte, then the value.
func _put(b: StreamPeerBuffer, a) -> void:
	match typeof(a):
		TYPE_NIL:
			b.put_u8(0)
		TYPE_FLOAT:
			b.put_u8(1)
			b.put_float(a)
		TYPE_INT:
			b.put_u8(2)
			b.put_32(a)
		TYPE_BOOL:
			b.put_u8(3 if a else 4)
		TYPE_VECTOR2:
			b.put_u8(5)
			_put_v2(b, a)
		TYPE_RECT2:
			b.put_u8(6)
			_put_v2(b, a.position)
			_put_v2(b, a.size)
		TYPE_COLOR:
			b.put_u8(7)
			b.put_u32((a as Color).to_rgba32())
		TYPE_PACKED_VECTOR2_ARRAY:
			b.put_u8(8)
			b.put_u16(a.size())
			for v in a:
				_put_v2(b, v)
		TYPE_OBJECT:
			b.put_u8(9)
			b.put_u32(int(a.get_meta("net", 0xFFFFFFFF)) if a != null else 0xFFFFFFFF)
		_:
			b.put_u8(0)


func _take(b: StreamPeerBuffer):
	match b.get_u8():
		1:
			return b.get_float()
		2:
			return b.get_32()
		3:
			return true
		4:
			return false
		5:
			return Vector2(b.get_float(), b.get_float())
		6:
			return Rect2(b.get_float(), b.get_float(), b.get_float(), b.get_float())
		7:
			return Color.hex(b.get_u32())
		8:
			var pts := PackedVector2Array()
			pts.resize(b.get_u16())
			for k in pts.size():
				pts[k] = Vector2(b.get_float(), b.get_float())
			return pts
		9:
			return _texture(b.get_u32())
	return null


func _sounds_for(who: int, list: Array) -> Array:
	var out: Array = []
	for p in list:
		var o := int(p.get("owner", -1))
		if o >= 0 and o != who:
			continue
		if p.get("stopped", false):
			continue
		var pl: AudioStreamPlayer = p["player"]
		if not (pl.playing or p["paused"]):
			continue
		out.append([int(p["id"]), int(p["sound"]), bool(p.get("loop", false)), pl.volume_db, pl.pitch_scale, bool(p["paused"]), pl.get_playback_position()])
	return out


# ---------------------------------------------------------------- client

func join(ip: String, port := PORT, pname := "Friend", pw := "") -> void:
	conn = ENetConnection.new()
	conn.create_host(1, 3)
	conn.compress(ENetConnection.COMPRESS_ZSTD)
	link = conn.connect_to_host(ip, port, 3)
	role = "client"
	state = "connecting"
	why = ""
	_my_name = pname
	_my_pw = pw
	_hello_ms = Time.get_ticks_msec()
	_log("joining %s:%d" % [ip, port])


func _sim_delay() -> int:
	return sim_lag + (_sim_rng.randi_range(0, sim_jitter) if sim_jitter > 0 else 0)


func _frame_in(data: PackedByteArray) -> void:
	stats["bytes"] += data.size()
	var fr = bytes_to_var(data)
	if not (fr is Dictionary):
		return
	var f := int(fr["f"])
	# Older than what's on screen already: no use. Out of order but not shown yet: put in its
	# place (the network may have overtaken it).
	if f <= _shown_f:
		stats["late"] += 1
		return
	var at := _queue.size()
	while at > 0 and int(_queue[at - 1]["f"]) >= f:
		if int(_queue[at - 1]["f"]) == f:
			return
		at -= 1
	_queue.insert(at, fr)


# What the simulated bad network lets through by now.
func _sim_release() -> void:
	var now := Time.get_ticks_msec()
	for box in [_sim_in, _sim_out]:
		var keep: Array = []
		for e in box:
			if int(e[0]) <= now:
				if box == _sim_in:
					_frame_in(e[1])
				elif link != null:
					link.send(1, e[1], ENetPacketPeer.FLAG_UNSEQUENCED)
			else:
				keep.append(e)
		box.assign(keep)


func _client_service() -> void:
	if not _sim_in.is_empty() or not _sim_out.is_empty():
		_sim_release()
	while conn != null:
		var ev: Array = conn.service()
		var t: int = ev[0]
		if t == ENetConnection.EVENT_NONE or t == ENetConnection.EVENT_ERROR:
			break
		if t == ENetConnection.EVENT_CONNECT:
			state = "waiting"
			link.send(0, var_to_bytes({"t": "hello", "proto": PROTOCOL, "v": eng.coop._my_version(), "mods": eng.coop.mods_id(), "name": _my_name, "pw": _my_pw}), ENetPacketPeer.FLAG_RELIABLE)
		elif t == ENetConnection.EVENT_DISCONNECT:
			if state != "refused":
				state = "lost"
				why = "The connection to the host was lost." if why == "" else why
			_log("disconnected: " + why)
			eng.mp_net_ended(why)
			conn = null
			return
		elif t == ENetConnection.EVENT_RECEIVE:
			var ch: int = ev[3]
			var data: PackedByteArray = (ev[1] as ENetPacketPeer).get_packet()
			if ch == 2:
				if sim_loss > 0.0 and _sim_rng.randf() < sim_loss:
					continue
				if sim_lag > 0 or sim_jitter > 0:
					_sim_in.append([Time.get_ticks_msec() + _sim_delay(), data])
					continue
				_frame_in(data)
			else:
				var m = bytes_to_var(data)
				if m is Dictionary:
					_client_msg(m)
	if state == "connecting" and Time.get_ticks_msec() - _hello_ms > HELLO_WAIT_MS:
		why = "No game answered at that address."
		state = "lost"
		eng.mp_net_ended(why)
		stop()


func _client_msg(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"welcome":
			me = int(m["index"])
			state = "playing"
			_log("I am player %d (%s)" % [me + 1, m.get("name", "")])
			eng.mp_net_joined(me, String(m.get("name", "")))
		"refused":
			state = "refused"
			why = String(m.get("why", "Refused."))
			_log("refused: " + why)
		"notice":
			if eng.has_method("mp_notice"):
				eng.mp_notice(String(m.get("text", "")))
		"chat":
			eng.chat.add(int(m.get("i", 0)), String(m.get("name", "?")), String(m.get("text", "")))


var _key_hist: Array = []
const KEY_HIST := 8
var _pending := {}          # my key frame -> arrow direction, not yet used by the host
var _last_pp = null
var _blocked := Vector2i.ZERO
var predict := true
var predicted := Vector2.ZERO


# One tick of the friend's PC: send this frame's keys, show the next frame from the host.
func client_tick(local_keys: Array) -> void:
	_client_service()
	if state != "playing":
		return
	_sent_keys += 1
	_sent_dirs.erase(_sent_keys - 120)
	_pending[_sent_keys] = Vector2i((1 if local_keys.has(39) else 0) - (1 if local_keys.has(37) else 0), (1 if local_keys.has(40) else 0) - (1 if local_keys.has(38) else 0))
	_sent_dirs[_sent_keys] = _pending[_sent_keys]
	_key_hist.append(local_keys)
	# Each packet repeats the last KEY_HIST frames, so a key gets through unless that many
	# packets in a row are lost.
	while _key_hist.size() > KEY_HIST:
		_key_hist.pop_front()
	var pkt: Array = [_sent_keys - _key_hist.size() + 1]
	pkt.append_array(_key_hist)
	if sim_loss > 0.0 and _sim_rng.randf() < sim_loss:
		pass
	elif sim_lag > 0 or sim_jitter > 0:
		_sim_out.append([Time.get_ticks_msec() + _sim_delay(), var_to_bytes(pkt)])
	else:
		link.send(1, var_to_bytes(pkt), ENetPacketPeer.FLAG_UNSEQUENCED)
	# Play the frames at the host's pace with a small buffer: one per tick, catching up when
	# too many are waiting, holding the last one when none has come.
	if _queue.is_empty():
		stats["repeats"] += 1
		# No new frame: the last one stays, but my own walking goes on with the keys sent since.
		if _last_fr != null:
			eng.rec.view = _last_fr["v"]
			_predict(_last_fr, true)
			_measure(_last_fr)
		return
	while _queue.size() > BUFFER + 2:
		_queue.pop_front()
		stats["dropped"] += 1
	if stats["frames"] == 0 and _queue.size() < BUFFER + 1:
		return
	_apply(_queue.pop_front())
	stats["frames"] += 1


func _texture(code: int) -> Texture2D:
	if code == 0xFFFFFFFF:
		return null
	if _tex.has(code):
		return _tex[code]
	var t: Texture2D = null
	var bi = eng.bi
	match code >> 30:
		0:
			t = bi.texture(code >> 16, code & 0xFFFF)
		1:
			t = bi.bg_texture(code & 0x3FFFFFFF)
		2:
			t = bi.font(code & 0x3FFFFFFF).get("tex")
	_tex[code] = t
	return t


func _apply(fr: Dictionary) -> void:
	_shown_f = int(fr["f"])
	_last_fr = fr
	var rec = eng.rec
	rec.clear()
	rec.view = fr["v"]
	rec.view_scale = fr["sc"]
	var b := StreamPeerBuffer.new()
	b.data_array = fr["o"]
	for _k in int(fr["n"]):
		var code := b.get_u8()
		if code == 0:
			var id := b.get_32()
			var pos := Vector2(b.get_float(), b.get_float())
			var tag := b.get_8()
			var fl := b.get_u8()
			var anchor = Vector2(b.get_float(), b.get_float()) if fl & 1 else null
			# Faded on this screen: someone else's (any player but this PC's).
			rec.owner(id, pos, tag, anchor, 99 if fl & 2 else -1)
		elif code == 1:
			rec.gui_begin()
		else:
			var cnt := b.get_u8()
			var args: Array = []
			for _a in cnt:
				args.append(_take(b))
			if code >= OPS.size():
				continue
			var name: String = OPS[code]
			var ti = TEX_ARG.get(name)
			if ti != null and args[ti] == null:
				continue
			rec.ops.append([name, args])
	eng.net_frame = int(fr["f"])
	eng.mp_ui_state = fr.get("ui", {})
	_predict(fr)
	_measure(fr)
	if log_on and fr.has("pp"):
		var shown: Vector2 = fr["pp"] + predicted
		print("PRED f=%d host_f=%d ack=%d pending=%d host_x=%.0f shown_x=%.0f step=%.0f view_x=%.0f" % [eng.frames, int(fr["f"]), int(fr.get("ack", -1)), _pending.size(), fr["pp"].x, shown.x, shown.x - _last_shown.x, eng.rec.view.x])
		_last_shown = shown
	_play_sounds(fr["s"])


# My own walking shows at once: the keys the host hasn't used yet move my character (and the
# camera with it) the way Undertale's walk would, until the host's frames catch up.
func _predict(fr: Dictionary, again := false) -> void:
	var rec = eng.rec
	rec.shift.clear()
	predicted = Vector2.ZERO
	var ack := int(fr.get("ack", -1))
	for f in _pending.keys():
		if f <= ack:
			_pending.erase(f)
	if not fr.has("me"):
		_last_pp = null
		return
	var pp: Vector2 = fr["pp"]
	var mv := bool(fr.get("mv", false))
	# A direction the host's character didn't move in while it was held is blocked (a wall):
	# it isn't predicted until that key is let go or turned round.
	var used = _sent_dirs.get(ack)
	if again:
		pass      # the same frame again: nothing new about walls
	elif _last_pp != null and used != null and mv and _last_mv:
		if used.x != 0 and absf(pp.x - _last_pp.x) < 0.01:
			_blocked.x = used.x
		if used.y != 0 and absf(pp.y - _last_pp.y) < 0.01:
			_blocked.y = used.y
	if not again:
		_last_pp = pp
		_last_mv = mv
	var keys := _pending.keys()
	keys.sort()
	var newest = _pending[keys[-1]] if not keys.is_empty() else used
	if newest == null or newest.x != _blocked.x:
		_blocked.x = 0
	if newest == null or newest.y != _blocked.y:
		_blocked.y = 0
	if not predict or not mv:
		return
	var off := Vector2.ZERO
	# Undertale walks 3 pixels a frame (left and right together cancel out); a SOUL moves at the
	# battle's speed.
	var spd := float(fr.get("spd", 3.0))
	for f in keys:
		var d: Vector2i = _pending[f]
		if d.x != 0 and d.x != _blocked.x:
			off.x += d.x * spd
		if d.y != 0 and d.y != _blocked.y:
			off.y += d.y * spd
	if fr.has("box"):
		# A SOUL stays in the box (as obj_heart's Step keeps it).
		var bx: Array = fr["box"]
		var to: Vector2 = pp + off
		to.x = clampf(to.x, float(bx[0]), maxf(float(bx[0]), float(bx[1])))
		to.y = clampf(to.y, float(bx[2]), maxf(float(bx[2]), float(bx[3])))
		off = to - pp
	if off == Vector2.ZERO:
		return
	predicted = off
	rec.shift[int(fr["me"])] = off
	if fr.has("box"):
		return     # a battle's view doesn't move
	# The camera follows, inside the room.
	var vw := 640.0 / maxf(rec.view_scale.x, 0.01)
	var vh := 480.0 / maxf(rec.view_scale.y, 0.01)
	var rw := float(fr.get("rw", 0))
	var rh := float(fr.get("rh", 0))
	var v: Vector2 = rec.view
	var nv := v + off
	nv.x = clampf(nv.x, 0.0, rw - vw) if rw > vw else v.x
	nv.y = clampf(nv.y, 0.0, rh - vh) if rh > vh else v.y
	rec.view = nv


var _sent_dirs := {}
var _last_mv := false
var _last_shown := Vector2.ZERO
var _shown_f := -1           # the host frame on screen
var _last_fr = null          # and the frame itself
var _m_last = null           # where my character showed last frame (null: not walking)


# Smoothness of my own walking as shown here: a jerk is a frame where it jumps (more than two
# steps) or steps back against the key held. A room change or no character isn't counted.
func _measure(fr: Dictionary) -> void:
	if not fr.has("pp") or not bool(fr.get("mv", false)) or fr.has("box"):
		_m_last = null
		return
	var shown: Vector2 = fr["pp"] + predicted
	if _m_last != null:
		var d: Vector2 = shown - _m_last
		var held = _pending[_pending.keys().max()] if not _pending.is_empty() else null
		var back: bool = held != null and ((held.x != 0 and d.x * held.x < -0.5) or (held.y != 0 and d.y * held.y < -0.5))
		if d.length() < 100.0 and (d.length() > 7.0 or back):
			stats["jerks"] += 1
	_m_last = shown


func _play_sounds(list: Array) -> void:
	var bi = eng.bi
	var seen := {}
	for s in list:
		var id: int = s[0]
		seen[id] = true
		var cur = _sounds.get(id)
		if cur == null:
			var st = bi._stream(int(s[1]))
			if st == null:
				continue
			var stream = st.duplicate() if s[2] else st
			if s[2]:
				if stream is AudioStreamOggVorbis:
					stream.loop = true
				elif stream is AudioStreamWAV:
					stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
					stream.loop_end = int(stream.get_length() * stream.mix_rate)
			var pl := AudioStreamPlayer.new()
			pl.stream = stream
			eng.add_child(pl)
			pl.volume_db = s[3]
			pl.pitch_scale = maxf(float(s[4]), 0.01)
			pl.play(float(s[6]))
			cur = {"player": pl, "sound": int(s[1])}
			_sounds[id] = cur
		var p: AudioStreamPlayer = cur["player"]
		p.volume_db = s[3]
		if absf(p.pitch_scale - float(s[4])) > 0.0001:
			p.pitch_scale = maxf(float(s[4]), 0.01)
		if p.stream_paused != bool(s[5]):
			p.stream_paused = bool(s[5])
	for id in _sounds.keys():
		if not seen.has(id):
			_sounds[id]["player"].queue_free()
			_sounds.erase(id)


func leave() -> void:
	if role == "client" and link != null and conn != null:
		link.send(0, var_to_bytes({"t": "bye"}), ENetPacketPeer.FLAG_RELIABLE)
		conn.flush()
		link.peer_disconnect(0)
		for k in 10:
			conn.service(10)
	stop()


func stop() -> void:
	kicked = {}
	if conn != null:
		if role == "host":
			for peer in peers:
				peer.peer_disconnect(0)
			conn.flush()
		conn.destroy()
	conn = null
	link = null
	for id in _sounds:
		_sounds[id]["player"].queue_free()
	_sounds.clear()
	peers.clear()
	_queue.clear()
	_shown_f = -1
	_last_fr = null
	_sim_in.clear()
	_sim_out.clear()
	role = ""
	state = ""
	beacon = null


# Between game frames: receive whatever has arrived.
func poll() -> void:
	if conn == null:
		return
	if role == "host":
		_host_service()
	elif role == "client":
		_client_service()


# Called once per engine tick, before the game's frames (host) or instead of them (friend).
func service() -> void:
	if role == "host" and conn != null:
		_host_service()


func after_frames() -> void:
	if role == "host" and conn != null:
		_host_send()
		conn.flush()


func status_line() -> String:
	if role == "host":
		var parts: Array = []
		for peer in peers:
			var p: Dictionary = peers[peer]
			if int(p["index"]) >= 0:
				parts.append("%s rtt=%dms kq=%d %dB/f (%dB compressed)" % [p["name"], peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), p["keys"].size(), int(p["bytes"]) / maxi(1, int(p["frames"])), int(p.get("zlast", 0))])
		return "host: " + ", ".join(parts)
	if role == "client":
		return "client %s: frames=%d late=%d dropped=%d repeats=%d jerks=%d queue=%d %dB/f rtt=%dms" % [state, stats["frames"], stats["late"], stats["dropped"], stats["repeats"], stats["jerks"], _queue.size(), int(stats["bytes"]) / maxi(1, int(stats["frames"])), link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if link != null else -1]
	return ""
