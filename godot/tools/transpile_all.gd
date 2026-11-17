# Translates every extracted code entry to GDScript and compiles it; prints failures.
#   godot --headless --path godot --script res://tools/transpile_all.gd [-- filter]
# --write saves the translations to extracted/gd/ (done by scripts/prepare-godot.ps1).
extends SceneTree

const VM = preload("res://gml/gml_vm.gd")
const Builtins = preload("res://gml/gml_builtins.gd")


func _init() -> void:
	var vm = VM.new()
	if not vm.setup(ProjectSettings.globalize_path("res://extracted")):
		print("no extracted data")
		quit(2)
		return
	vm.builtins = Builtins.new(vm)
	vm.keep_src = true
	var filter := ""
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0 and not ua[0].begins_with("--"):
		filter = ua[0]
	var dir := ProjectSettings.globalize_path("res://extracted/code")
	var ok := 0
	var t0 := Time.get_ticks_msec()
	for f in DirAccess.open(dir).get_files():
		if not f.ends_with(".gml") or (filter != "" and not f.contains(filter)):
			continue
		var name := f.get_basename()
		if vm.get_fast(name) != null or vm.get_code(name).is_empty():
			ok += 1
	print("TRANSPILE ok=%d failed=%d ms=%d" % [ok, vm.fast_failures.size(), Time.get_ticks_msec() - t0])
	# Time Godot's compile alone, as the runtime would pay it with pre-translated sources.
	var t1 := Time.get_ticks_msec()
	var n := 0
	for name in vm.fast_src:
		var gd := GDScript.new()
		gd.source_code = vm.fast_src[name]
		gd.reload()
		n += 1
	print("RECOMPILE scripts=%d ms=%d" % [n, Time.get_ticks_msec() - t1])
	# --write: save every translation to extracted/gd/ so the engine only has to compile.
	if OS.get_cmdline_user_args().has("--write"):
		var gdir := ProjectSettings.globalize_path("res://extracted/gd")
		DirAccess.make_dir_recursive_absolute(gdir)
		for name in vm.fast_src:
			FileAccess.open(gdir.path_join(name + ".gd"), FileAccess.WRITE).store_string(vm.fast_src[name])
		FileAccess.open(gdir.path_join("_refs.json"), FileAccess.WRITE).store_string(JSON.stringify(vm.fast_refs))
		print("WROTE %d translated scripts to %s" % [vm.fast_src.size(), gdir])
	for l in vm.fast_failures.slice(0, 30):
		print("  ", l)
	quit(0 if vm.fast_failures.is_empty() else 1)
