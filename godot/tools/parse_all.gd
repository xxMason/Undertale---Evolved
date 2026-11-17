# Parses every extracted code file and reports failures.
#   godot --headless --path godot --script res://tools/parse_all.gd
extends SceneTree

const Compiler = preload("res://gml/gml_compiler.gd")


func _init() -> void:
	var dir := ProjectSettings.globalize_path("res://extracted/code")
	var d := DirAccess.open(dir)
	if d == null:
		print("no code folder")
		quit(2)
		return
	var c = Compiler.new()
	var ok := 0
	var bad := 0
	var shown := 0
	var t0 := Time.get_ticks_msec()
	for f in d.get_files():
		if not f.ends_with(".gml"):
			continue
		c.compile(FileAccess.get_file_as_string(dir.path_join(f)))
		if c.error == "":
			ok += 1
		else:
			bad += 1
			if shown < 25:
				print("  ", f, ": ", c.error)
				shown += 1
	print("PARSE ok=%d failed=%d ms=%d" % [ok, bad, Time.get_ticks_msec() - t0])
	quit(0 if bad == 0 else 1)
