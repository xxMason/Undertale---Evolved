# F5 for a co-op friend in a universe with cheats on: their own character only (HP, gold,
# items). Nothing changes here directly: Apply sends the change with this PC's keys
# (coop_net.gd send_cmd), and both PCs make it on the same frame (engine.gd coop_commands),
# so the host's copy of the friend's character stays the one that counts.
extends CanvasLayer

var eng
var panel: PanelContainer
var hp_box: SpinBox
var gold_box: SpinBox
var item_boxes: Array = []
var open := false


func setup(e) -> void:
	eng = e
	layer = 50
	panel = PanelContainer.new()
	panel.position = Vector2(30, 30)
	panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.92)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	var th := Theme.new()
	th.default_font_size = 13
	panel.theme = th
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var title := Label.new()
	title.text = "Your character (cheats are on in this universe)"
	v.add_child(title)
	var note := Label.new()
	note.text = "In co-op you can change your own HP, gold and items.\nThe rest of the debug menu is the host's."
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	v.add_child(note)
	hp_box = _spin(v, "HP", 1, 999)
	gold_box = _spin(v, "Gold", 0, 99999)
	var ids: Array = eng.debug._item_ids
	var grid := GridContainer.new()
	grid.columns = 4
	v.add_child(grid)
	for i in 8:
		var l := Label.new()
		l.text = "Item %d" % (i + 1)
		grid.add_child(l)
		var ob := OptionButton.new()
		for it in ids:
			ob.add_item(String(it[1]))
		ob.custom_minimum_size.x = 170
		grid.add_child(ob)
		item_boxes.append(ob)
	var buttons := HBoxContainer.new()
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_apply)
	buttons.add_child(apply)
	var close := Button.new()
	close.text = "Close (F5)"
	close.pressed.connect(toggle)
	buttons.add_child(close)
	v.add_child(buttons)


func _spin(parent: Control, label: String, lo: float, hi: float) -> SpinBox:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 70
	row.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.custom_minimum_size.x = 120
	row.add_child(sb)
	parent.add_child(row)
	return sb


func toggle() -> void:
	open = not open
	panel.visible = open
	if open:
		_load()


func _load() -> void:
	var me: Dictionary = eng.coop_character(eng.coop.role)
	hp_box.value = float(me.get("hp", 20.0))
	gold_box.value = float(me.get("gold", 0.0))
	var ids: Array = eng.debug._item_ids
	var items: Array = me.get("item", [[]])[0] if me.get("item", [[]]) is Array and not (me.get("item", [[]]) as Array).is_empty() else []
	for i in 8:
		var want := float(items[i]) if i < items.size() else 0.0
		var k := 0
		for j in ids.size():
			if float(ids[j][0]) == want:
				k = j
		(item_boxes[i] as OptionButton).select(k)


func _apply() -> void:
	var ids: Array = eng.debug._item_ids
	var items: Array = []
	for i in 8:
		items.append(float(ids[(item_boxes[i] as OptionButton).selected][0]))
	eng.coop.send_cmd({"cheat": "self", "hp": hp_box.value, "gold": gold_box.value, "item": items})
	eng._toast("Sent to %s's game." % eng.coop.partner.get("name", "the host"), 2000)
