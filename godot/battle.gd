# Playable battle-core prototype. Game logic runs in _physics_process at 30 steps per
# second (ut_sim.gd holds the SOUL/bullet rules that replay.gd checks against the real
# game). Drawing happens every rendered frame; with SMOOTH on (F2) the SOUL, bullets and
# box walls are drawn between their last two logic positions.
#
# The battle flow follows obj_battlecontroller: menu buttons -> FIGHT (target list, attack
# bar, slash, damage) / ACT (target list, act list, reply) / ITEM / MERCY (Spare, Flee)
# -> the enemy's turn -> back to the menu.
#
# Controls: arrows (or WASD, toggled with F3) move, Z/Enter confirm, X/Shift back or slow
# down, F2 smooth on/off, F4 fullscreen, Esc quit.
extends Node2D

const Assets = preload("res://ut_assets.gd")
const Sim = preload("res://ut_sim.gd")
const Writer = preload("res://ut_writer.gd")

enum Phase { MENU, TARGET, ACTS, ITEMS, MERCY, REPLY, BAR, STRIKE, ENEMY, RETURN, DEATH, WIN, FLED, GAMEOVER }

const K_Z := 32
const BUTTONS := [["spr_fightbt", 32], ["spr_talkbt", 185], ["spr_itembt", 345], ["spr_sparebt", 500]]
const FULL_BOX := Rect2i(32, 250, 570, 135)      # border preset 0
const ATTACK_BOX := Rect2i(220, 245, 200, 140)
const ATTACK_LEN := 180
const MX := 271            # dummy's top-left corner
const MY := 128
const MWD := 100           # "wd" the original uses for damage-bar width

# The prototype's own enemy and text (no game text is copied into this file).
const ENEMY_NAME := "Dummy"
const ENEMY_MAXHP := 40
const ENEMY_DEF := 0
const ENEMY_GOLD := 3
const BULLET_DMG := 6      # 4 damage at LV 1 after the defence formula
const INTRO := "* Dummy blocks the way!"
const FLAVOR := ["* Dummy stands there,&  waiting for you to move.", "* Dummy looks at you&  with its button eye.", "* Smells like old cotton."]
const CHECK_TEXT := "* DUMMY - ATK 4 DEF 0&* A practice dummy.&* Talk to it to calm it down."
const TALK_TEXT := "* You chat with Dummy.&* Dummy seems calmer now."
const ITEM_NAMES := ["Candy", "Candy", "Pie"]
const ITEM_HEAL := [10, 10, 99]

var assets
var sim
var writer
var phase := Phase.MENU
var sel := 0           # menu button (bmenucoord[0])
var cur := 0           # cursor inside a list
var from_button := 0   # which button opened the target list (0 FIGHT, 1 ACT)
var tick := 0
var phase_t := 0
var flavor_i := 0
var error := ""

var enemy_hp := ENEMY_MAXHP
var spareable := false
var items: Array = []
var lv := 1
var at := 10           # 8 + LV * 2
var wstrength := 0     # Stick

# Walls: top (ux, uy, width uw*5), bottom (dx, dy, width dw*5), left lx, right rx.
var ux := 32
var uy := 250
var uw := 114
var dx := 32
var dy := 385
var dw := 115
var lx := 32
var rx := 602
var prev_walls := PackedInt32Array([32, 250, 114, 32, 385, 115, 32, 602])
var target := Rect2i(FULL_BOX)

# Attack bar / strike state.
var bar_x := 0.0
var bar_v := 0.0
var bar_hit := false
var bar_blink := 0.0
var tgt_alpha := 1.0
var tgt_scale := 1.0
var tgt_x := 0.0
var tgt_fading := false
var damage := 0
var stretch := 1.0
var slice_speed := 0.5
var slice_scale := 1.0
var slice_t := 0.0
var damagetimer := 0
var shudder := 0
var shake_x := 0
var hurt_frame := 0
var dmg_show := false
var dmg_y := 0.0
var dmg_v := 0.0
var dmg_y0 := 0.0
var dmg_apparent := 0.0
var dmg_left := 0
var miss := false
var death_t := 0

var prev_heart := Vector2.ZERO
var smooth := true
var wasd := false
var shake := 0
var rng := RandomNumberGenerator.new()
var keys_prev := 0
var player := AudioStreamPlayer.new()
var blip := AudioStreamPlayer.new()
var music := AudioStreamPlayer.new()

# Self-test mode: --shots <folder> plays through FIGHT, ACT, ITEM and MERCY by itself,
# saves a screenshot of each new phase, then quits.
var shots_dir := ""
var auto := false
var auto_plan := ["fight", "act", "item", "spare"]
var auto_step := 0
var auto_wait := 0
var shot_taken := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		shots_dir = args[i + 1]
		auto = true
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		wasd = bool(cfg.get_value("input", "wasd", false))
	assets = Assets.new()
	if not assets.load_all(ProjectSettings.globalize_path("res://extracted")):
		error = assets.error
		return
	sim = Sim.new(assets)
	writer = Writer.new()
	writer.sound_cb = func(): _blip()
	rng.seed = 7
	add_child(player)
	add_child(blip)
	add_child(music)
	if assets.sounds.has("SND_TXT2"):
		blip.stream = assets.sounds["SND_TXT2"]
	_reset_battle()


func _reset_battle() -> void:
	enemy_hp = ENEMY_MAXHP
	spareable = false
	items = [0, 1, 2]
	sim.hp = sim.maxhp
	sim.invc = 0
	sim.bullets.clear()
	flavor_i = 0
	sel = 0
	target = Rect2i(FULL_BOX)
	if assets.music != null:
		music.stream = assets.music
		music.volume_db = linear_to_db(0.5)
		music.play()
	_enter(Phase.MENU)
	writer.start(INTRO)


func _play(name: String) -> void:
	if assets.sounds.has(name):
		player.stream = assets.sounds[name]
		player.play()


func _blip() -> void:
	if blip.stream != null:
		blip.stop()
		blip.play()


func _enter(p: int) -> void:
	phase = p
	phase_t = 0
	cur = 0


# ---------------------------------------------------------------- input

func _read_keys() -> int:
	if auto:
		return _auto_keys()
	var k := 0
	if Input.is_key_pressed(KEY_LEFT) or (wasd and Input.is_key_pressed(KEY_A)):
		k |= Sim.K_LEFT
	if Input.is_key_pressed(KEY_RIGHT) or (wasd and Input.is_key_pressed(KEY_D)):
		k |= Sim.K_RIGHT
	if Input.is_key_pressed(KEY_UP) or (wasd and Input.is_key_pressed(KEY_W)):
		k |= Sim.K_UP
	if Input.is_key_pressed(KEY_DOWN) or (wasd and Input.is_key_pressed(KEY_S)):
		k |= Sim.K_DOWN
	if Input.is_key_pressed(KEY_X) or Input.is_key_pressed(KEY_SHIFT):
		k |= Sim.K_X
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_ENTER):
		k |= K_Z
	return k


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			wasd = not wasd
			var cfg := ConfigFile.new()
			cfg.set_value("input", "wasd", wasd)
			cfg.save("user://settings.cfg")
		elif event.keycode == KEY_F2:
			smooth = not smooth
		elif event.keycode == KEY_F4:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


# ---------------------------------------------------------------- logic

func _physics_process(_delta: float) -> void:
	if sim == null:
		return
	tick += 1
	phase_t += 1
	var keys := _read_keys()
	var pressed := keys & ~keys_prev
	keys_prev = keys
	prev_heart = Vector2(sim.heart_x, sim.heart_y)
	prev_walls = PackedInt32Array([ux, uy, uw, dx, dy, dw, lx, rx])
	if shake > 0:
		shake -= 1
	writer.tick()

	match phase:
		Phase.MENU:
			_menu(pressed)
		Phase.TARGET:
			_target_list(pressed)
		Phase.ACTS:
			_act_list(pressed)
		Phase.ITEMS:
			_item_list(pressed)
		Phase.MERCY:
			_mercy_list(pressed)
		Phase.REPLY:
			_reply(pressed)
		Phase.BAR:
			_bar(pressed)
		Phase.STRIKE:
			_strike()
		Phase.ENEMY:
			_enemy(keys)
		Phase.RETURN:
			if lx == FULL_BOX.position.x:
				# Back to the menu with the next flavour line (the original waits for
				# the left wall to arrive, then starts the writer).
				_enter(Phase.MENU)
				writer.start(FLAVOR[flavor_i % FLAVOR.size()])
				flavor_i += 1
		Phase.DEATH:
			death_t += 1
			if death_t >= 40:
				_win()
		Phase.WIN, Phase.FLED:
			if phase == Phase.FLED:
				sim.heart_x -= 3
			if pressed & K_Z and writer.page_done() and phase_t > 10:
				_reset_battle()
		Phase.GAMEOVER:
			if pressed & K_Z and phase_t > 15:
				_reset_battle()
	# Walls move after the battle controller has set the box's target for this frame.
	# Top and bottom walls move in the Step event (before collisions):
	var tl := target.position.x
	var tt := target.position.y
	var tr := target.end.x
	var tb := target.end.y
	ux = _approach(ux, tl, 15)
	if ux == tl or uy < tt:
		uy = _approach(uy, tt, 15)
	uw = _approach(uw, Sim.rne((tr - tl) / 5.0), 6)
	dx = _approach(dx, tl, 15)
	dy = _approach(dy, tb, 15)
	dw = _approach(dw, Sim.rne((tr - tl) / 5.0) + 1, 6)
	sim.wl = lx
	sim.wt = uy
	sim.wr = rx
	sim.wb = dy

	if phase == Phase.ENEMY:
		_enemy_collide(keys)
	_tick_target_fade()
	_tick_damage_number()

	# Side walls move in the End Step (after collisions).
	lx = _approach(lx, target.position.x, 15)
	rx = _approach(rx, target.end.x, 15)
	_auto_shots()


func _approach(v: int, to: int, step: int) -> int:
	if absi(v - to) <= step:
		return to
	return v - step if v > to else v + step


func _box_text_ok(pressed: int) -> bool:
	# X fast-forwards the text (obj_battlecontroller: OBJ_WRITER.stringpos = length).
	if pressed & Sim.K_X and not writer.page_done():
		writer.skip()
		return false
	return true


func _menu(pressed: int) -> void:
	_box_text_ok(pressed)
	if pressed & Sim.K_LEFT:
		sel = (sel + 3) % 4
		_play("snd_squeak")
	if pressed & Sim.K_RIGHT:
		sel = (sel + 1) % 4
		_play("snd_squeak")
	sim.heart_x = BUTTONS[sel][1] + 8
	sim.heart_y = 432 + 14
	if pressed & K_Z:
		_play("snd_select")
		match sel:
			0, 1:
				from_button = sel
				_enter(Phase.TARGET)
				writer.start("  " + ("\\Y" if spareable else "") + "* " + ENEMY_NAME, true)
			2:
				if items.is_empty():
					return
				_enter(Phase.ITEMS)
				writer.start(_item_text(), true)
			3:
				_enter(Phase.MERCY)
				writer.start("  " + ("\\Y" if spareable else "") + "* Spare\\W&  * Flee", true)


func _cursor(col_x: int, line: int) -> void:
	sim.heart_x = FULL_BOX.position.x + col_x
	sim.heart_y = FULL_BOX.position.y + 28 + line * 32


func _target_list(pressed: int) -> void:
	_cursor(32, 0)
	if pressed & Sim.K_X:
		_back_to_menu()
	elif pressed & K_Z:
		_play("snd_select")
		if from_button == 0:
			_start_bar()
		else:
			_enter(Phase.ACTS)
			writer.start("  * Check       * Talk", true)


func _act_list(pressed: int) -> void:
	# Two columns like the original: Check in slot 0 (left), Talk in slot 3 (right).
	if pressed & (Sim.K_LEFT | Sim.K_RIGHT):
		cur = 1 - cur
		_play("snd_squeak")
	_cursor(32 if cur == 0 else 292, 0)
	if pressed & Sim.K_X:
		_enter(Phase.TARGET)
		writer.start("  " + ("\\Y" if spareable else "") + "* " + ENEMY_NAME, true)
	elif pressed & K_Z:
		_play("snd_select")
		if cur == 0:
			_reply_text(CHECK_TEXT)
		else:
			spareable = true
			_reply_text(TALK_TEXT)


func _item_text() -> String:
	# Items in two columns, two rows (English layout of the original's item menu).
	var s := ""
	for k in mini(items.size(), 4):
		var t: String = "  * " + ITEM_NAMES[items[k]]
		if k % 2 == 0:
			s += t.rpad(16)
		else:
			s += t + "&"
	return s


func _item_list(pressed: int) -> void:
	var n := mini(items.size(), 4)
	if pressed & (Sim.K_LEFT | Sim.K_RIGHT) and n > 1:
		cur = (cur ^ 1) if (cur ^ 1) < n else cur
		_play("snd_squeak")
	if pressed & (Sim.K_UP | Sim.K_DOWN) and n > 2:
		cur = (cur ^ 2) if (cur ^ 2) < n else cur
		_play("snd_squeak")
	sim.heart_x = FULL_BOX.position.x + (32 if cur % 2 == 0 else 280)
	sim.heart_y = FULL_BOX.position.y + (28 if cur < 2 else 60)
	if pressed & Sim.K_X:
		_back_to_menu()
	elif pressed & K_Z:
		var id: int = items[cur]
		items.remove_at(cur)
		var heal: int = ITEM_HEAL[id]
		var before: int = sim.hp
		sim.hp = mini(sim.maxhp, sim.hp + heal)
		_play("snd_heal_c")
		var got := "* Your HP was maxed out." if sim.hp == sim.maxhp else "* You recovered %d HP!" % (sim.hp - before)
		_reply_text("* You ate the " + ITEM_NAMES[id] + ".&" + got)


func _mercy_list(pressed: int) -> void:
	if pressed & (Sim.K_UP | Sim.K_DOWN):
		cur = 1 - cur
		_play("snd_squeak")
	_cursor(32, cur)
	if pressed & Sim.K_X:
		_back_to_menu()
	elif pressed & K_Z:
		_play("snd_select")
		if cur == 0:
			if spareable:
				_play("snd_vaporized")
				_enter(Phase.WIN)
				death_t = -1
				music.stop()
				writer.start("* YOU WON!&* You earned 0 EXP and 0 gold.")
			else:
				_start_enemy_turn()
		else:
			# Fleeing always works while wearing the Bandage (scr_runaway).
			_play("snd_escaped")
			_enter(Phase.FLED)
			music.stop()
			writer.start("* Escaped...", true)


func _back_to_menu() -> void:
	_enter(Phase.MENU)
	writer.start(FLAVOR[(flavor_i + FLAVOR.size() - 1) % FLAVOR.size()] if flavor_i > 0 else INTRO, true)


func _reply_text(t: String) -> void:
	_enter(Phase.REPLY)
	writer.start(t)


func _reply(pressed: int) -> void:
	sim.heart_x = -400
	if not _box_text_ok(pressed):
		return
	if pressed & K_Z and writer.page_done():
		if not writer.next_page():
			_start_enemy_turn()


# ---- FIGHT: attack bar (obj_target / obj_targetchoice) -------------------------

func _start_bar() -> void:
	_enter(Phase.BAR)
	writer.active = false
	tgt_x = FULL_BOX.position.x + 6
	tgt_alpha = 1.0
	tgt_scale = 1.0
	tgt_fading = false
	bar_x = tgt_x - 16
	bar_v = 11.0 + rng.randf() * 2.0   # global.attackspeed + random(global.attackspeedr)
	bar_hit = false
	bar_blink = 0.0
	sim.heart_x = -400


func _bar(pressed: int) -> void:
	if not bar_hit:
		bar_x += bar_v
		if bar_x > tgt_x + 562:
			# Missed: the bar ran off the end (damage 0, "MISS").
			damage = 0
			miss = true
			_show_damage_number()
			_start_enemy_turn()
			return
		if pressed & K_Z:
			bar_hit = true
			miss = false
			# scr_attackcalc + obj_targetchoice
			var dmg := float(wstrength + at - ENEMY_DEF) + rng.randf() * 2.0
			var myx := bar_x + 7.0
			var perfect := tgt_x + 281.0
			var bonus := absf(myx - perfect)
			if bonus == 0.0:
				bonus = 1.0
			stretch = (562.0 - bonus) / 562.0
			if bonus <= 12.0:
				damage = Sim.rne(dmg * 2.2)
			else:
				damage = Sim.rne(dmg * stretch * 2.0)
			# obj_slice
			slice_speed = 0.5 - stretch / 4.0
			if slice_speed == 0.0:
				slice_speed = 0.1
			slice_scale = stretch * 2.0 - 0.5
			slice_t = 0.0
			damagetimer = int((1.0 / slice_speed) * 6.0) + 3
			_play("snd_laz")
			_enter(Phase.STRIKE)
			shudder = 0


func _strike() -> void:
	bar_blink += 0.4
	slice_t += slice_speed
	if phase_t == damagetimer:
		# Monster Alarm 3: damage number appears, hurt sound, shake starts.
		_show_damage_number()
		_play("snd_damage")
		hurt_frame = 1
		shudder = 16
	if phase_t == damagetimer + 11:
		_play("snd_ehurt1")
	if phase_t > damagetimer and (phase_t - damagetimer) % 2 == 1:
		shake_x += shudder
		shudder = -(shudder + 2) if shudder < 0 else -shudder
		if shudder == 0:
			shake_x = 0
			enemy_hp -= damage
			dmg_left = 15
			if enemy_hp >= 1:
				hurt_frame = 0
				_start_enemy_turn()
			else:
				_play("snd_vaporized")
				music.stop()
				death_t = 0
				_enter(Phase.DEATH)


func _show_damage_number() -> void:
	dmg_show = true
	dmg_y0 = MY - 24
	dmg_y = dmg_y0
	dmg_v = -4.0 if damage != 0 else 0.0
	dmg_apparent = enemy_hp
	dmg_left = -1 if damage != 0 else 30


func _tick_damage_number() -> void:
	if not dmg_show:
		return
	dmg_v += 0.5
	dmg_y += dmg_v
	if dmg_y > dmg_y0:
		dmg_y = dmg_y0
		dmg_v = 0.0
	if tick % 2 == 0:
		dmg_apparent = maxf(dmg_apparent - damage / 15.0, enemy_hp - damage if dmg_left < 0 else enemy_hp)
	if dmg_left > 0:
		dmg_left -= 1
		if dmg_left == 0:
			dmg_show = false


func _tick_target_fade() -> void:
	if not tgt_fading:
		return
	tgt_alpha -= 0.08
	tgt_scale -= 0.06
	tgt_x += 15.8


func _win() -> void:
	_enter(Phase.WIN)
	writer.start("* YOU WON!&* You earned 0 EXP and %d gold." % ENEMY_GOLD)


# ---- Enemy turn ------------------------------------------------------------------

func _start_enemy_turn() -> void:
	if bar_hit or phase == Phase.BAR:
		tgt_fading = true
	_enter(Phase.ENEMY)
	writer.active = false
	target = Rect2i(ATTACK_BOX)
	sim.heart_x = roundi((ATTACK_BOX.position.x + ATTACK_BOX.end.x) / 2.0) - 8
	sim.heart_y = roundi((ATTACK_BOX.position.y + ATTACK_BOX.end.y) / 2.0) - 8
	prev_heart = Vector2(sim.heart_x, sim.heart_y)


func _enemy(_keys: int) -> void:
	_spawn_pattern()
	if phase_t >= ATTACK_LEN:
		sim.bullets.clear()
		target = Rect2i(FULL_BOX)
		sim.heart_x = -400
		_enter(Phase.RETURN)


func _enemy_collide(keys: int) -> void:
	if auto:
		sim.invc = maxi(sim.invc, 2)   # self-test only: the scripted SOUL cannot dodge
	sim.step(keys)
	for e in sim.events:
		if e == "hurt":
			_play("snd_hurt1")
			shake = 6
	sim.events.clear()
	if sim.hp <= 0:
		_enter(Phase.GAMEOVER)
		sim.bullets.clear()
		music.stop()
		writer.start("* You were defeated.&  [Z] Try again", true)


# Demo attack: bullets rain from above the box, and every second wave one is aimed at
# the SOUL from the side.
func _spawn_pattern() -> void:
	if phase_t < 10 or phase_t > ATTACK_LEN - 30:
		return
	if phase_t % 12 == 0:
		for n in 2:
			var x := rng.randf_range(ATTACK_BOX.position.x + 6, ATTACK_BOX.end.x - 18)
			sim.spawn("spr_bulletmd", x, ATTACK_BOX.position.y - 6, 3.0, 270.0, BULLET_DMG)
	if phase_t % 24 == 6:
		var side := ATTACK_BOX.position.x - 20 if rng.randi() % 2 == 0 else ATTACK_BOX.end.x + 8
		var y := rng.randf_range(ATTACK_BOX.position.y + 10, ATTACK_BOX.end.y - 20)
		var dir := rad_to_deg(atan2(-(sim.heart_y + 8 - (y + 6)), sim.heart_x + 8 - (side + 6)))
		sim.spawn("spr_bulletsm", side, y, 4.0, dir, BULLET_DMG)


# ---------------------------------------------------------------- drawing

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if error != "":
		draw_rect(Rect2(0, 0, 640, 480), Color.BLACK)
		draw_string(ThemeDB.fallback_font, Vector2(20, 40), error, HORIZONTAL_ALIGNMENT_LEFT, 600, 14)
		return
	var f := Engine.get_physics_interpolation_fraction() if smooth else 1.0
	var off := Vector2.ZERO
	if shake > 0:
		off = Vector2(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
	draw_set_transform(off)
	draw_rect(Rect2(0, 0, 640, 480), Color.BLACK)
	draw_texture(assets.frames["spr_battlebg"][0], Vector2.ZERO)
	_draw_enemy()

	# Box walls, drawn between their last two logic positions when smooth.
	var w := PackedFloat32Array()
	var now := [ux, uy, uw, dx, dy, dw, lx, rx]
	for k in 8:
		w.append(lerpf(prev_walls[k], now[k], f))
	var wux := roundf(w[0])
	var wuy := roundf(w[1])
	var wdx := roundf(w[3])
	var wdy := roundf(w[4])
	var wlx := roundf(w[6])
	var wrx := roundf(w[7])
	draw_rect(Rect2(wux + 5, wuy + 5, wrx - wux - 5, wdy - wuy - 5), Color.BLACK)
	draw_rect(Rect2(wux, wuy, roundf(w[2] * 5), 5), Color.WHITE)
	draw_rect(Rect2(wdx, wdy, roundf(w[5] * 5), 5), Color.WHITE)
	draw_rect(Rect2(wlx, wuy, 5, wdy - wuy), Color.WHITE)
	draw_rect(Rect2(wrx, wuy, 5, wdy - wuy), Color.WHITE)

	# Box text (the writer is created at the box's target corner).
	var L := FULL_BOX.position.x
	var T := FULL_BOX.position.y
	writer.draw(self, assets, L + 20, T + 20, L + FULL_BOX.size.x - 55)

	# Attack bar.
	if phase == Phase.BAR or phase == Phase.STRIKE or (tgt_fading and tgt_scale >= 0.08):
		var tex: Texture2D = assets.frames["spr_target"][0]
		draw_texture_rect(tex, Rect2(tgt_x, T + 6, 562 * tgt_scale, 128), false, Color(1, 1, 1, maxf(tgt_alpha, 0.0)))
		if phase == Phase.BAR or phase == Phase.STRIKE:
			var bf := int(bar_blink) % 2 if bar_hit else 0
			var bx := bar_x if bar_hit else lerpf(bar_x - bar_v, bar_x, f)
			draw_texture(assets.frames["spr_targetchoice"][bf], Vector2(roundf(bx), T + 6))

	# Slash over the enemy.
	if phase == Phase.STRIKE and slice_t < 6.0:
		var st: Texture2D = assets.frames["spr_strike"][int(slice_t)]
		var sx := MX + MWD / 2.0 - 5.0 - (slice_scale - 1.0) * 13.0
		var sy := MY - 5.0 - (slice_scale - 1.0) * 55.0
		draw_texture_rect(st, Rect2(sx, sy, 26 * slice_scale, 110 * slice_scale), false)

	_draw_damage_number()

	# Bullets.
	for b in sim.bullets:
		var p := Vector2(lerpf(b["px"], b["x"], f), lerpf(b["py"], b["y"], f))
		draw_texture(assets.frames[b["spr"]][0], p.round())

	# Buttons, then the SOUL over them.
	for i in 4:
		var lit := 1 if (phase == Phase.MENU and i == sel) else 0
		draw_texture(assets.frames[BUTTONS[i][0]][lit], Vector2(BUTTONS[i][1], 432))
	if sim.heart_x > -100 and phase != Phase.GAMEOVER and phase != Phase.WIN:
		var hp_pos := Vector2(sim.heart_x, sim.heart_y)
		if phase == Phase.ENEMY:
			hp_pos = prev_heart.lerp(hp_pos, f).round()
		var frame := 0
		var spr := "spr_heart"
		if phase == Phase.FLED:
			spr = "spr_heartgtfo"
			frame = int(phase_t / 2) % 2
		elif sim.invc > 0 and phase == Phase.ENEMY:
			frame = int(sim.invc / 2) % 2
		draw_texture(assets.frames[spr][frame], hp_pos)

	# Name, LV and HP bar (scr_binfowrite).
	var nw: float = assets.draw_text(self, "fnt_curs", 30, 400, "CHARA")
	assets.draw_text(self, "fnt_curs", 30 + nw, 400, "   LV %d" % lv)
	draw_texture(assets.frames["spr_hpname"][0], Vector2(240, 400))
	draw_rect(Rect2(275, 400, sim.maxhp * 1.2, 21), Color.RED)
	draw_rect(Rect2(275, 400, sim.hp * 1.2, 21), Color.YELLOW)
	var hpw := ("0" + str(sim.hp)) if sim.hp < 10 else str(sim.hp)
	assets.draw_text(self, "fnt_curs", 290 + sim.maxhp * 1.2, 400, hpw + " / " + str(sim.maxhp))

	draw_set_transform(Vector2.ZERO)
	var info := "PROTOTYPE   SMOOTH %s [F2]   MOVE %s [F3]   %d fps" % ["ON" if smooth else "OFF", "WASD" if wasd else "ARROWS", Engine.get_frames_per_second()]
	assets.draw_text(self, "fnt_small", 4, 2, info, Color(0.6, 0.6, 0.6))


func _draw_enemy() -> void:
	var tex: Texture2D = assets.frames["spr_dummybattle"][hurt_frame]
	if phase == Phase.DEATH:
		# Dissolves from the top down (an approximation of obj_vaporized_new).
		var cut := clampf(death_t / 40.0, 0.0, 1.0) * 106.0
		draw_texture_rect_region(tex, Rect2(MX, MY + cut, 98, 106 - cut), Rect2(0, cut, 98, 106 - cut), Color(1, 1, 1, 1.0 - death_t / 50.0))
		return
	if phase == Phase.WIN and death_t != 0:
		if death_t == -1:
			# Spared: drawn faded (obj_spared).
			draw_texture(tex, Vector2(MX, MY), Color(1, 1, 1, 0.5))
		return
	if phase == Phase.WIN:
		return
	draw_texture(tex, Vector2(MX + shake_x, MY))


func _draw_damage_number() -> void:
	if not dmg_show:
		return
	var x := MX + 1.0
	if miss or damage == 0:
		draw_texture(assets.frames["spr_dmgmiss_o"][0], Vector2(x - 10, dmg_y - 16), Color(0.75, 0.75, 0.75))
		return
	var sf := float(MWD) / ENEMY_MAXHP
	draw_rect(Rect2(x - 1, dmg_y0 + 7, ENEMY_MAXHP * sf + 2, 15), Color.BLACK)
	draw_rect(Rect2(x, dmg_y0 + 8, ENEMY_MAXHP * sf, 13), Color(0.25, 0.25, 0.25))
	if dmg_apparent > 0:
		draw_rect(Rect2(x, dmg_y0 + 8, dmg_apparent * sf, 13), Color(0, 1, 0))
	var digits := str(damage)
	var place := digits.length() - 1
	for i in digits.length():
		var d := int(digits[i])
		var pi := place - i
		draw_texture(assets.frames["spr_dmgnum_o"][d], Vector2(x + 30 - pi * 32 + place * 16, dmg_y - 28), Color.RED)


# ---- Self-test: plays FIGHT, ACT, ITEM and MERCY, saving screenshots ---------------

func _auto_keys() -> int:
	if auto_wait > 0:
		auto_wait -= 1
		return 0
	var step: String = auto_plan[auto_step] if auto_step < auto_plan.size() else ""
	var want_button: int = {"fight": 0, "act": 1, "item": 2, "spare": 3}.get(step, 0)
	var k := 0
	match phase:
		Phase.MENU:
			if phase_t < 20:
				return 0
			if sel != want_button:
				k = Sim.K_RIGHT
			else:
				k = K_Z
		Phase.TARGET:
			k = K_Z
		Phase.ACTS:
			k = Sim.K_RIGHT if cur == 0 else K_Z
		Phase.ITEMS, Phase.MERCY:
			k = K_Z
		Phase.REPLY:
			k = K_Z if writer.page_done() else 0
		Phase.BAR:
			# Stop the bar near the middle.
			if bar_x + 7 >= tgt_x + 281 - 8 and not bar_hit:
				k = K_Z
				auto_step += 1
			return k
		Phase.ENEMY:
			return Sim.K_LEFT if (phase_t / 30) % 2 == 0 else Sim.K_RIGHT
		_:
			return 0
	if k == K_Z and phase in [Phase.ACTS, Phase.ITEMS, Phase.MERCY]:
		auto_step += 1
	auto_wait = 8
	return k


func _auto_shots() -> void:
	if not auto:
		return
	var name: String = Phase.keys()[phase].to_lower()
	var wanted := {"menu": 25, "target": 6, "acts": 6, "items": 6, "mercy": 6, "reply": 40, "bar": 10, "strike": 30, "enemy": 70, "return": 6, "win": 40}
	if wanted.has(name) and phase_t == wanted[name] and not shot_taken.has(name):
		shot_taken[name] = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots_dir.path_join("flow_%s.png" % name))
		print("SHOT ", name)
	if phase == Phase.WIN and phase_t == 60:
		print("FLOW done enemy_hp=%d hp=%d items=%d spareable=%s" % [enemy_hp, sim.hp, items.size(), str(spareable)])
		get_tree().quit()
	if tick > 3000:
		print("FLOW timeout phase=", name)
		get_tree().quit()
