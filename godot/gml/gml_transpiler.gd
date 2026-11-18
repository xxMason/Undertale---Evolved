# Translates one compiled GML tree (from gml_compiler.gd) into GDScript source, so the
# game's code runs as native GDScript instead of being walked node by node.
#
# The generated script has one static-free method:  run(vm, bi, ctx)  that returns the
# script's result. Semantics follow gml_vm.gd's interpreter exactly:
#   - `var` locals become GDScript locals (declared at the top, as GML scopes them);
#   - names are resolved at translation time: locals, argumentN, constants and asset
#     names, GameMaker's built-in globals, else the current instance's variables;
#   - `with` swaps `me`/`other` (and ctx, which built-ins read);
#   - switch keeps fall-through; GML `continue` inside a switch continues the loop;
#   - loops keep the interpreter's 200000-iteration guard;
#   - a statement this translator does not handle (++/-- used as a value) runs through
#     the interpreter with the locals synchronised around it.
extends RefCounted

const C = preload("res://gml/gml_compiler.gd")
const VERSION := 11     # bump when the generated code changes

# Built-in variables gml_builtins.global_var answers (read) and set_global_var (write).
const BI_READ := ["room", "room_width", "room_height", "room_speed", "current_time", "view_xview",
	"view_yview", "view_wview", "view_hview", "view_current", "keyboard_string", "keyboard_key",
	"keyboard_lastkey", "fps", "fps_real", "instance_count", "background_color",
	"background_colour", "mouse_x", "mouse_y", "os_type", "room_persistent", "debug_mode",
	"view_enabled", "background_showcolour", "room_first", "room_last", "keyboard_lastchar",
	"view_visible", "view_xport", "view_yport", "view_wport", "view_hport", "view_hborder",
	"view_vborder", "view_hspeed", "view_vspeed", "view_object", "view_angle",
	"background_visible", "background_foreground", "background_index", "background_x",
	"background_y", "background_htiled", "background_vtiled", "background_hspeed",
	"background_vspeed", "background_xscale", "background_yscale", "background_blend",
	"background_alpha"]
const BI_WRITE := ["room_speed", "keyboard_string", "background_color", "background_colour", "room_persistent",
	"view_enabled", "background_showcolour"]
const BI_ARRAY_WRITE := ["view_visible", "view_xview", "view_yview", "view_wview", "view_hview",
	"view_xport", "view_yport", "view_wport", "view_hport", "view_hborder", "view_vborder",
	"view_hspeed", "view_vspeed", "view_object", "view_angle", "background_visible",
	"background_foreground", "background_index", "background_x", "background_y", "background_htiled",
	"background_vtiled", "background_hspeed", "background_vspeed", "background_xscale",
	"background_yscale", "background_blend", "background_alpha"]
# Instance variables whose writes have side effects (vm.inst_set).
const SPECIAL_SET := ["x", "y", "xprevious", "yprevious", "speed", "direction", "hspeed", "vspeed", "image_index", "image_speed", "image_xscale", "image_yscale", "image_angle", "image_alpha", "gravity", "friction", "depth", "alarm"]
const SIMPLE_MATH := {"abs": "absf", "floor": "floorf", "ceil": "ceilf", "sin": "sin", "cos": "cos",
	"degtorad": "deg_to_rad", "radtodeg": "rad_to_deg", "sign": "signf"}

var consts := {}           # vm.consts
var scripts := {}          # vm.script_code
var fn_methods := {}       # builtins FN_METHODS
var nodes: Array = []      # AST nodes handed to the interpreter fallback
var objects := {}           # vm.obj_index (object name -> index)
var refs := {}              # objects ("o:name") and scripts ("s:name") this code refers to
var error := ""

var _out: PackedStringArray
var _locals := {}
var _tmp := 0
var _loops: Array = []     # [{brk: String, cont: String}] innermost last
var _assigned := {}        # bare names assigned in this code (never treated as constants)


func translate(tree: Array) -> String:
	error = ""
	nodes = []
	refs = {}
	_out = PackedStringArray()
	_locals = {}
	_tmp = 0
	_loops = []
	_assigned = {}
	_scan(tree)
	_line(0, "extends RefCounted")
	_line(0, "")
	_line(0, "var nodes: Array = []")
	_line(0, "")
	_line(0, "func run(vm, bi, ctx: Dictionary):")
	_line(1, "var me = ctx[\"self\"]")
	_line(1, "var other = ctx[\"other\"]")
	_line(1, "var args: Array = ctx[\"args\"]")
	_line(1, "var _t = null")
	for n in _locals:
		_line(1, "var %s = 0.0" % _lv(n))
	_stmt(tree, 1)
	_line(1, "return 0.0")
	return "\n".join(_out)


func _line(depth: int, s: String) -> void:
	_out.append("\t".repeat(depth) + s)


func _lv(name: String) -> String:
	return "l_" + name


func _t() -> String:
	_tmp += 1
	return "_g%d" % _tmp


# Collects `var` names and names assigned directly.
func _scan(n) -> void:
	if not (n is Array) or n.is_empty():
		return
	var k = n[0]
	if k is int or k is float:
		var kind := int(k)
		if kind == C.S_VAR:
			for d in n[1]:
				_locals[d[0]] = true
		elif kind == C.S_ASSIGN or kind == C.S_INCDEC or kind == C.E_INCDEC:
			var lv: Array = n[1]
			if lv[0] == C.E_IDENT:
				_assigned[lv[1]] = true
	for c in n:
		if c is Array:
			_scan(c)


# Like _has_value_incdec for a whole statement, except that a statement which is just
# `x++` / `x--` only counts the operand (an index like a[i++] still counts).
func _stmt_has_value_incdec(s: Array) -> bool:
	var kind := int(s[0])
	if kind == C.S_EXPR and s[1] is Array and int(s[1][0]) == C.E_INCDEC:
		return _has_value_incdec(s[1][1])
	if kind == C.S_INCDEC:
		return _has_value_incdec(s[1])
	return _has_value_incdec(s.slice(1))


func _has_value_incdec(n) -> bool:
	if not (n is Array) or n.is_empty():
		return false
	if (n[0] is int or n[0] is float) and int(n[0]) == C.E_INCDEC:
		return true
	for c in n:
		if c is Array and _has_value_incdec(c):
			return true
	return false


# ---------------------------------------------------------------- statements

func _block(n, depth: int) -> void:
	var before := _out.size()
	if n != null:
		_stmt(n, depth)
	if _out.size() == before:
		_line(depth, "pass")


func _stmt(n: Array, d: int) -> void:
	var kind := int(n[0])
	# Statements whose own expressions use ++/-- as a value go to the interpreter. A bare
	# `x++;` is not a value use: it is translated below as a statement.
	if kind in [C.S_EXPR, C.S_ASSIGN, C.S_VAR, C.S_RETURN] and _stmt_has_value_incdec(n):
		_fallback(n, d)
		return
	match kind:
		C.S_BLOCK:
			for s in n[1]:
				_stmt(s, d)
		C.S_EXPR:
			var e: Array = n[1]
			if int(e[0]) == C.E_INCDEC:
				_incdec_stmt(e[1], float(e[2]), d)
			else:
				_line(d, "_t = " + _expr(e))
		C.S_VAR:
			for decl in n[1]:
				_line(d, "%s = %s" % [_lv(decl[0]), _expr(decl[1]) if decl[1] != null else "0.0"])
		C.S_ASSIGN:
			_assign(n[1], n[2], n[3], d)
		C.S_INCDEC:
			_incdec_stmt(n[1], float(n[2]), d)
		C.S_IF:
			if _has_value_incdec(n[1]):
				_fallback(n, d)
				return
			_line(d, "if %s:" % _cond(n[1]))
			_block(n[2], d + 1)
			if n[3] != null:
				_line(d, "else:")
				_block(n[3], d + 1)
		C.S_WHILE:
			if _has_value_incdec(n[1]):
				_fallback(n, d)
				return
			var g := _t()
			_line(d, "var %s := 0" % g)
			_line(d, "while %s:" % _cond(n[1]))
			_guard(g, d + 1)
			_loop_body(n[2], d + 1, "")
		C.S_DO:
			if _has_value_incdec(n[2]):
				_fallback(n, d)
				return
			var g := _t()
			_line(d, "var %s := 0" % g)
			_line(d, "while true:")
			_guard(g, d + 1)
			_loop_body(n[1], d + 1, "if %s:\n\tbreak" % _cond(n[2]))
		C.S_FOR:
			if _has_value_incdec(n[2]) or (n[3] != null and _stmt_has_value_incdec(n[3])) or (n[1] != null and _stmt_has_value_incdec(n[1])):
				_fallback(n, d)
				return
			if n[1] != null:
				_stmt(n[1], d)
			var g := _t()
			_line(d, "var %s := 0" % g)
			_line(d, "while %s:" % (_cond(n[2]) if n[2] != null else "true"))
			_guard(g, d + 1)
			var step := ""
			if n[3] != null:
				var saved := _out
				_out = PackedStringArray()
				_stmt(n[3], 0)
				step = "\n".join(_out)
				_out = saved
			_loop_body(n[4], d + 1, step)
		C.S_REPEAT:
			if _has_value_incdec(n[1]):
				_fallback(n, d)
				return
			var r := _t()
			_line(d, "for %s in maxi(int(float(%s)), 0):" % [r, _expr(n[1])])
			_loops.append({"brk": "break", "cont": "continue"})
			_block(n[2], d + 1)
			_loops.pop_back()
		C.S_WITH:
			if _has_value_incdec(n[1]):
				_fallback(n, d)
				return
			var sm := _t()
			var so := _t()
			var it := _t()
			_line(d, "var %s = me" % sm)
			_line(d, "var %s = other" % so)
			_line(d, "for %s in vm.resolve(%s, ctx):" % [it, _expr(n[1])])
			_line(d + 1, "if %s.dead:" % it)
			_line(d + 2, "continue")
			_line(d + 1, "me = %s" % it)
			_line(d + 1, "other = %s" % sm)
			_line(d + 1, "ctx[\"self\"] = me")
			_line(d + 1, "ctx[\"other\"] = other")
			_loops.append({"brk": "break", "cont": "continue"})
			_block(n[2], d + 1)
			_loops.pop_back()
			_line(d, "me = %s" % sm)
			_line(d, "other = %s" % so)
			_line(d, "ctx[\"self\"] = me")
			_line(d, "ctx[\"other\"] = other")
		C.S_SWITCH:
			_switch(n, d)
		C.S_BREAK:
			if _loops.is_empty():
				_line(d, "return 0.0")
			else:
				for l in String(_loops.back()["brk"]).split("\n"):
					_line(d, l)
		C.S_CONTINUE:
			if _loops.is_empty():
				_line(d, "return 0.0")
			else:
				for l in String(_loops.back()["cont"]).split("\n"):
					_line(d, l)
		C.S_EXIT:
			_line(d, "return 0.0")
		C.S_RETURN:
			_line(d, "return %s" % (_expr(n[1]) if n[1] != null else "0.0"))
		_:
			error = "unknown statement %d" % kind


func _guard(g: String, d: int) -> void:
	_line(d, "%s += 1" % g)
	_line(d, "if %s > 200000:" % g)
	_line(d + 1, "vm.warn_once(\"loop\", \"loop limit hit\")")
	_line(d + 1, "break")


# Loop body followed by `tail` (a for-loop step or a do-until test). When the body uses
# `continue`, it is wrapped in a one-pass loop so that continue still runs the tail.
func _loop_body(body, d: int, tail: String) -> void:
	if tail == "" or not _uses_continue(body):
		_loops.append({"brk": "break", "cont": "continue"})
		_block(body, d)
		_loops.pop_back()
	else:
		var b := _t()
		var once := _t()
		_line(d, "var %s := false" % b)
		_line(d, "for %s in 1:" % once)
		_loops.append({"brk": "%s = true\nbreak" % b, "cont": "break"})
		_block(body, d + 1)
		_loops.pop_back()
		_line(d, "if %s:" % b)
		_line(d + 1, "break")
	for l in tail.split("\n"):
		if l != "":
			_line(d, l)


# Whether `continue` appears at this loop level (not inside a nested loop).
func _uses_continue(n) -> bool:
	if not (n is Array) or n.is_empty():
		return false
	if n[0] is int or n[0] is float:
		var k := int(n[0])
		if k == C.S_CONTINUE:
			return true
		if k in [C.S_WHILE, C.S_DO, C.S_FOR, C.S_REPEAT, C.S_WITH]:
			return false
	for c in n:
		if c is Array and _uses_continue(c):
			return true
	return false


func _switch(n: Array, d: int) -> void:
	for c in n[2]:
		if c[0] != null and _has_value_incdec(c[0]):
			_fallback(n, d)
			return
	if _has_value_incdec(n[1]):
		_fallback(n, d)
		return
	var v := _t()
	var m := _t()
	var once := _t()
	var cf := _t()
	var cases: Array = n[2]
	_line(d, "var %s = %s" % [v, _expr(n[1])])
	var default_at := 1000000
	var first := true
	for i in cases.size():
		if cases[i][0] == null:
			default_at = i
			continue
		_line(d, "%s %s:" % ["if" if first else "elif", "vm.eq(%s, %s)" % [v, _expr(cases[i][0])]])
		_line(d + 1, "_t = %d" % i)
		first = false
	if first:
		_line(d, "_t = %d" % default_at)
	else:
		_line(d, "else:")
		_line(d + 1, "_t = %d" % default_at)
	_line(d, "var %s: int = _t" % m)
	_line(d, "var %s := false" % cf)
	_line(d, "for %s in 1:" % once)
	var outer_cont := "continue"
	if not _loops.is_empty():
		outer_cont = _loops.back()["cont"]
	_loops.append({"brk": "break", "cont": "%s = true\nbreak" % cf})
	var any := false
	for i in cases.size():
		var body: Array = cases[i][1]
		if body.is_empty():
			continue
		_line(d + 1, "if %s <= %d:" % [m, i])
		var before := _out.size()
		for s in body:
			_stmt(s, d + 2)
		if _out.size() == before:
			_line(d + 2, "pass")
		any = true
	if not any:
		_line(d + 1, "pass")
	_loops.pop_back()
	if _uses_continue_in_switch(cases):
		_line(d, "if %s:" % cf)
		if _loops.is_empty():
			_line(d + 1, "return 0.0")
		else:
			for l in String(outer_cont).split("\n"):
				_line(d + 1, l)


func _uses_continue_in_switch(cases: Array) -> bool:
	for c in cases:
		for s in c[1]:
			if _uses_continue(s):
				return true
	return false


# Runs one statement through the interpreter, with this function's locals copied in and out.
func _fallback(n: Array, d: int) -> void:
	nodes.append(n)
	var idx := nodes.size() - 1
	_line(d, "var _loc%d: Dictionary = ctx[\"locals\"]" % idx)
	for l in _locals:
		_line(d, "_loc%d[\"%s\"] = %s" % [idx, l, _lv(l)])
	_line(d, "var _sig%d: int = vm.exec_node(nodes[%d], ctx)" % [idx, idx])
	for l in _locals:
		_line(d, "%s = _loc%d[\"%s\"]" % [_lv(l), idx, l])
	_line(d, "if _sig%d == 3:" % idx)
	_line(d + 1, "return 0.0")
	_line(d, "if _sig%d == 4:" % idx)
	_line(d + 1, "return vm.take_ret()")
	if not _loops.is_empty():
		_line(d, "if _sig%d == 1:" % idx)
		for l in String(_loops.back()["brk"]).split("\n"):
			_line(d + 1, l)
		_line(d, "if _sig%d == 2:" % idx)
		for l in String(_loops.back()["cont"]).split("\n"):
			_line(d + 1, l)


# ---------------------------------------------------------------- assignment

func _incdec_stmt(lv: Array, delta: float, d: int) -> void:
	if lv[0] == C.E_IDENT and _locals.has(lv[1]):
		_line(d, "%s = float(%s) + %s" % [_lv(lv[1]), _lv(lv[1]), _num(delta)])
		return
	_store(lv, "float(%s) + %s" % [_expr(lv), _num(delta)], d)


func _assign(lv: Array, op: String, e: Array, d: int) -> void:
	if op == "=":
		_store(lv, _expr(e), d)
		return
	var cur := _expr(lv)
	var rhs := _expr(e)
	var val := ""
	match op:
		"+=":
			val = "vm.add(%s, %s)" % [cur, rhs]
		"-=":
			val = "float(%s) - float(%s)" % [cur, rhs]
		"*=":
			val = "float(%s) * float(%s)" % [cur, rhs]
		"/=":
			val = "vm.fdiv(%s, %s)" % [cur, rhs]
		"|=":
			val = "float(int(float(%s)) | int(float(%s)))" % [cur, rhs]
		"&=":
			val = "float(int(float(%s)) & int(float(%s)))" % [cur, rhs]
		"^=":
			val = "float(int(float(%s)) ^ int(float(%s)))" % [cur, rhs]
		"%=":
			val = "vm.fmod2(%s, %s)" % [cur, rhs]
		"<<=":
			val = "float(int(float(%s)) << int(float(%s)))" % [cur, rhs]
		">>=":
			val = "float(int(float(%s)) >> int(float(%s)))" % [cur, rhs]
		_:
			error = "unknown assignment " + op
	_store(lv, val, d)


func _store(lv: Array, val: String, d: int) -> void:
	match int(lv[0]):
		C.E_IDENT:
			var name: String = lv[1]
			if _locals.has(name):
				_line(d, "%s = %s" % [_lv(name), val])
			elif name.begins_with("argument") and name.substr(8).is_valid_int():
				var k := int(name.substr(8))
				_line(d, "vm.arg_set(args, %d, %s)" % [k, val])
			elif name in BI_WRITE:
				_line(d, "bi.set_global_var(\"%s\", %s)" % [name, val])
			elif name in SPECIAL_SET:
				_line(d, "vm.inst_set(me, \"%s\", %s)" % [name, val])
			else:
				_line(d, "me.v[\"%s\"] = %s" % [name, val])
		C.E_MEMBER:
			var name: String = lv[2]
			var tgt: Array = lv[1]
			if _is_ident(tgt, "global"):
				_line(d, "vm.globals[\"%s\"] = %s" % [name, val])
			elif _is_ident(tgt, "self"):
				if _locals.has(name):
					_line(d, "vm.inst_set(me, \"%s\", %s)" % [name, val])
				else:
					_store([C.E_IDENT, name], val, d)
			else:
				_line(d, "vm.mwr(%s, \"%s\", %s, ctx)" % [_expr(tgt), name, val])
		C.E_INDEX:
			var idx: Array = lv[2]
			var a := "int(float(%s))" % _expr(idx[0])
			var b := "int(float(%s))" % _expr(idx[1]) if idx.size() > 1 else "-1"
			var basen: Array = lv[1]
			if (basen[0] == C.E_IDENT and basen[1] == "alarm") or (basen[0] == C.E_MEMBER and basen[2] == "alarm"):
				if basen[0] == C.E_IDENT:
					_line(d, "vm.set_alarm(me, %s, %s)" % [a, val])
				else:
					_line(d, "vm.set_alarm_of(%s, %s, %s, ctx)" % [_expr(basen[1]), a, val])
				return
			if basen[0] == C.E_IDENT:
				var name: String = basen[1]
				if _locals.has(name):
					_line(d, "%s = vm.arr_set(%s, %s, %s, %s)" % [_lv(name), _lv(name), a, b, val])
				elif name in BI_ARRAY_WRITE:
					_line(d, "bi.set_global_array(\"%s\", %s, %s)" % [name, a, val])
				else:
					_line(d, "me.v[\"%s\"] = vm.arr_set(me.v.get(\"%s\"), %s, %s, %s)" % [name, name, a, b, val])
			elif basen[0] == C.E_MEMBER:
				var name: String = basen[2]
				if _is_ident(basen[1], "global"):
					_line(d, "vm.globals[\"%s\"] = vm.arr_set(vm.globals.get(\"%s\"), %s, %s, %s)" % [name, name, a, b, val])
				else:
					_line(d, "vm.marr_set(%s, \"%s\", %s, %s, %s, ctx)" % [_expr(basen[1]), name, a, b, val])
		_:
			error = "bad assignment target"


func _is_ident(n: Array, name: String) -> bool:
	return int(n[0]) == C.E_IDENT and n[1] == name and not _locals.has(name)


# ---------------------------------------------------------------- expressions

func _num(v: float) -> String:
	if is_nan(v) or is_inf(v):
		return "NAN" if is_nan(v) else ("INF" if v > 0 else "-INF")
	var s := var_to_str(v)
	if not ("." in s or "e" in s):
		s += ".0"
	return "(" + s + ")" if v < 0 else s


func _value(v) -> String:
	if v == null:
		return "null"
	if v is String:
		return "\"" + v.c_escape() + "\""
	return _num(float(v))


# Kind of a value an expression always produces: "num", "str" or "any".
func _kind(e: Array) -> String:
	match int(e[0]):
		C.E_NUM:
			return "num"
		C.E_STR:
			return "str"
		C.E_BIN:
			match String(e[1]):
				"+":
					return "num" if _kind(e[2]) == "num" and _kind(e[3]) == "num" else "any"
				_:
					return "num"
		C.E_UN, C.E_AND, C.E_OR:
			return "num"
		C.E_IDENT:
			var name: String = e[1]
			if not _locals.has(name) and not _assigned.has(name) and consts.has(name) and (consts[name] is float or consts[name] is int):
				return "num"
		C.E_CALL:
			if SIMPLE_MATH.has(e[1]) and not scripts.has(e[1]):
				return "num"
	return "any"


func _f(e: Array) -> String:
	var s := _expr(e)
	return s if _kind(e) == "num" else "float(%s)" % s


func _cond(e: Array) -> String:
	var k := int(e[0])
	if k == C.E_BIN and String(e[1]) in ["==", "!=", "<", ">", "<=", ">=", "^^"]:
		return _bool_bin(e)
	if k == C.E_AND:
		return "(%s and %s)" % [_cond(e[1]), _cond(e[2])]
	if k == C.E_OR:
		return "(%s or %s)" % [_cond(e[1]), _cond(e[2])]
	if k == C.E_UN and e[1] == "!":
		return "(not %s)" % _cond(e[2])
	if _kind(e) == "num":
		return "(%s > 0.5)" % _expr(e)
	return "vm.truthy(%s)" % _expr(e)


func _bool_bin(e: Array) -> String:
	var op: String = e[1]
	var ka := _kind(e[2])
	var kb := _kind(e[3])
	match op:
		"==", "!=":
			var s := ""
			if ka == "num" and kb == "num":
				s = "absf(%s - %s) < 0.00001" % [_expr(e[2]), _expr(e[3])]
			elif kb == "num":
				s = "vm.eqn(%s, %s)" % [_expr(e[2]), _expr(e[3])]
			elif ka == "num":
				s = "vm.eqn(%s, %s)" % [_expr(e[3]), _expr(e[2])]
			else:
				s = "vm.eq(%s, %s)" % [_expr(e[2]), _expr(e[3])]
			return "(%s)" % s if op == "==" else "(not %s)" % s
		"^^":
			return "(%s != %s)" % [_cond(e[2]), _cond(e[3])]
	if ka == "str" or kb == "str":
		return "vm.cmp(\"%s\", %s, %s)" % [op, _expr(e[2]), _expr(e[3])]
	# Comparisons with GameMaker's epsilon (see gml_vm._bin).
	match op:
		"<":
			return "((%s - %s) <= -0.00001)" % [_f(e[2]), _f(e[3])]
		">":
			return "((%s - %s) >= 0.00001)" % [_f(e[2]), _f(e[3])]
		"<=":
			return "((%s - %s) < 0.00001)" % [_f(e[2]), _f(e[3])]
		">=":
			return "((%s - %s) > -0.00001)" % [_f(e[2]), _f(e[3])]
	return "(%s %s %s)" % [_f(e[2]), op, _f(e[3])]


func _expr(e: Array) -> String:
	match int(e[0]):
		C.E_NUM:
			return _num(float(e[1]))
		C.E_STR:
			return _value(String(e[1]))
		C.E_IDENT:
			return _ident(e[1])
		C.E_MEMBER:
			var tgt: Array = e[1]
			var name: String = e[2]
			if _is_ident(tgt, "global"):
				return "vm.globals.get(\"%s\", 0.0)" % name
			if _is_ident(tgt, "self"):
				return "vm.rd(me, \"%s\")" % name
			if _is_ident(tgt, "other"):
				return "vm.rd(other, \"%s\")" % name
			return "vm.mrd(%s, \"%s\", ctx)" % [_expr(tgt), name]
		C.E_INDEX:
			var idx: Array = e[2]
			var cont := _container(e[1])
			if idx.size() == 1:
				return "vm.ix(%s, %s)" % [cont, _expr(idx[0])]
			return "vm.ix2(%s, %s, %s)" % [cont, _expr(idx[0]), _expr(idx[1])]
		C.E_CALL:
			return _call(e[1], e[2])
		C.E_BIN:
			var op: String = e[1]
			if op in ["==", "!=", "<", ">", "<=", ">=", "^^"]:
				return "(1.0 if %s else 0.0)" % _bool_bin(e)
			match op:
				"+":
					if _kind(e[2]) == "num" and _kind(e[3]) == "num":
						return "(%s + %s)" % [_expr(e[2]), _expr(e[3])]
					return "vm.add(%s, %s)" % [_expr(e[2]), _expr(e[3])]
				"-", "*":
					return "(%s %s %s)" % [_f(e[2]), op, _f(e[3])]
				"/":
					return "vm.fdiv(%s, %s)" % [_expr(e[2]), _expr(e[3])]
				"div":
					return "vm.idiv(%s, %s)" % [_expr(e[2]), _expr(e[3])]
				"mod", "%":
					return "vm.fmod2(%s, %s)" % [_expr(e[2]), _expr(e[3])]
				"&", "|", "^", "<<", ">>":
					return "float(int(%s) %s int(%s))" % [_f(e[2]), op, _f(e[3])]
			error = "unknown operator " + op
			return "0.0"
		C.E_UN:
			match String(e[1]):
				"!":
					return "(0.0 if %s else 1.0)" % _cond(e[2])
				"-":
					return "(-%s)" % _f(e[2])
				"~":
					return "float(~int(%s))" % _f(e[2])
			return _expr(e[2])
		C.E_AND, C.E_OR:
			return "(1.0 if %s else 0.0)" % _cond(e)
		C.E_TERN:
			return "(%s if %s else %s)" % [_expr(e[2]), _cond(e[1]), _expr(e[3])]
		C.E_INCDEC:
			error = "++/-- as a value"
			return "0.0"
	error = "unknown expression %s" % str(e[0])
	return "0.0"


func _ident(name: String) -> String:
	if _locals.has(name):
		return _lv(name)
	if name.begins_with("argument"):
		if name == "argument_count":
			return "float(args.size())"
		if name == "argument":
			return "[args]"
		var n := name.substr(8)
		if n.is_valid_int():
			return "(args[%s] if %s < args.size() else 0.0)" % [n, n]
	if scripts.has(name):
		refs["s:" + name] = true     # a script passed by name (script_execute)
	if consts.has(name) and not _assigned.has(name):
		if name == "self":
			return "-1.0"
		return _value(consts[name])
	if name in BI_READ:
		return "bi.global_var(\"%s\")" % name
	return "vm.rd(me, \"%s\")" % name


func _note_objects(n) -> void:
	if not (n is Array) or n.is_empty():
		return
	if (n[0] is int or n[0] is float) and int(n[0]) == C.E_IDENT and objects.has(n[1]):
		refs["o:" + n[1]] = true
		return
	for c in n:
		if c is Array:
			_note_objects(c)


func _container(base: Array) -> String:
	if int(base[0]) == C.E_IDENT:
		var name: String = base[1]
		if _locals.has(name):
			return _lv(name)
		if name == "alarm":
			return "me.alarm"
		if name == "argument":
			return "[args]"
		return _ident(name)
	if int(base[0]) == C.E_MEMBER:
		var name: String = base[2]
		if _is_ident(base[1], "global"):
			return "vm.globals.get(\"%s\")" % name
		return "vm.mcont(%s, \"%s\", ctx)" % [_expr(base[1]), name]
	error = "bad index base"
	return "null"


# Does this expression call a function (whose order of evaluation could be seen)?
func _has_call(e) -> bool:
	if not (e is Array) or e.is_empty():
		return false
	if (e[0] is int or e[0] is float) and int(e[0]) == C.E_CALL:
		return true
	for c in e:
		if c is Array and _has_call(c):
			return true
	return false


func _call(name: String, args: Array) -> String:
	var parts: PackedStringArray = []
	for a in args:
		parts.append(_expr(a))
	# Objects whose code can run because this code creates them.
	if name in ["instance_create", "instance_change", "action_create_object", "event_perform_object"]:
		_note_objects(args)
	var list := "[" + ", ".join(parts) + "]"
	# The runner evaluates arguments last to first; that only matters when two or more of
	# them call something (random numbers, scripts). Then build the list backwards.
	var impure := 0
	for a in args:
		if _has_call(a):
			impure += 1
	if impure >= 2:
		var rparts: PackedStringArray = []
		for k in range(parts.size() - 1, -1, -1):
			rparts.append(parts[k])
		list = "vm.rv([" + ", ".join(rparts) + "])"
	if scripts.has(name):
		refs["s:" + name] = true
		return "vm.call_script(\"%s\", %s, ctx)" % [name, list]
	if SIMPLE_MATH.has(name) and args.size() == 1:
		return "%s(%s)" % [SIMPLE_MATH[name], _f(args[0])]
	if name == "round" and args.size() == 1:
		return "float(vm.rne(%s))" % _f(args[0])
	if name == "sqrt" and args.size() == 1:
		return "sqrt(maxf(%s, 0.0))" % _f(args[0])
	if fn_methods.has(name):
		return "bi.%s(\"%s\", %s, ctx)" % [fn_methods[name], name, list]
	return "bi.fn(\"%s\", %s, ctx)" % [name, list]
