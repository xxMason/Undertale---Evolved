# Compiles GameMaker Language (as decompiled from Undertale v1.08 by UndertaleModTool)
# into a tree of Arrays that gml_vm.gd runs. Node layout: [TYPE, ...fields].
extends RefCounted

# ---- Statement nodes
const S_BLOCK := 1        # [S_BLOCK, [stmts]]
const S_EXPR := 2         # [S_EXPR, expr]
const S_VAR := 3          # [S_VAR, [[name, expr_or_null], ...]]
const S_IF := 4           # [S_IF, cond, then, else_or_null]
const S_WHILE := 5        # [S_WHILE, cond, body]
const S_DO := 6           # [S_DO, body, cond]
const S_FOR := 7          # [S_FOR, init, cond, step, body]
const S_REPEAT := 8       # [S_REPEAT, count, body]
const S_WITH := 9         # [S_WITH, target, body]
const S_SWITCH := 10      # [S_SWITCH, expr, [[case_expr_or_null, [stmts]], ...]]
const S_BREAK := 11
const S_CONTINUE := 12
const S_EXIT := 13
const S_RETURN := 14      # [S_RETURN, expr_or_null]
const S_ASSIGN := 15      # [S_ASSIGN, lvalue, op, expr]   op: "=", "+=", ...
const S_INCDEC := 16      # [S_INCDEC, lvalue, delta]

# ---- Expression nodes
const E_NUM := 30         # [E_NUM, value]
const E_STR := 31         # [E_STR, value]
const E_IDENT := 32       # [E_IDENT, name]
const E_MEMBER := 33      # [E_MEMBER, target_expr, name]
const E_INDEX := 34       # [E_INDEX, base (E_IDENT or E_MEMBER), [index exprs]]
const E_CALL := 35        # [E_CALL, name, [args]]
const E_BIN := 36         # [E_BIN, op, a, b]
const E_UN := 37          # [E_UN, op, a]
const E_AND := 38         # [E_AND, a, b]
const E_OR := 39          # [E_OR, a, b]
const E_TERN := 40        # [E_TERN, cond, a, b]
const E_INCDEC := 41      # [E_INCDEC, lvalue, delta, is_prefix]

var src := ""
var toks: Array = []      # [kind, value, line]
var p := 0
var error := ""

const T_NUM := 0
const T_STR := 1
const T_ID := 2
const T_OP := 3
const T_EOF := 4

const OPS := ["<<=", ">>=", "==", "!=", "<=", ">=", "&&", "||", "^^", "++", "--", "+=", "-=", "*=", "/=", "|=", "&=", "^=", "%=", "<<", ">>", ":=",
	"+", "-", "*", "/", "%", "<", ">", "=", "!", "~", "&", "|", "^", "(", ")", "[", "]", "{", "}", ",", ";", ".", ":", "?"]


func compile(text: String) -> Array:
	src = text
	error = ""
	toks = []
	p = 0
	_lex()
	var stmts: Array = []
	while _peek()[0] != T_EOF:
		stmts.append(_statement())
		if error != "":
			return []
	return [S_BLOCK, stmts]


# ---------------------------------------------------------------- lexer

func _lex() -> void:
	var i := 0
	var n := src.length()
	var line := 1
	while i < n:
		var c := src[i]
		if c == "\n":
			line += 1
			i += 1
			continue
		if c == " " or c == "\t" or c == "\r":
			i += 1
			continue
		if c == "/" and i + 1 < n and src[i + 1] == "/":
			while i < n and src[i] != "\n":
				i += 1
			continue
		if c == "/" and i + 1 < n and src[i + 1] == "*":
			var e := src.find("*/", i + 2)
			if e < 0:
				e = n - 2
			for k in range(i, e + 2):
				if src[k] == "\n":
					line += 1
			i = e + 2
			continue
		if c.is_valid_int() or (c == "." and i + 1 < n and src[i + 1].is_valid_int()):
			var j := i
			while j < n and (src[j].is_valid_int() or src[j] == "."):
				j += 1
			# exponent (rare)
			if j < n and (src[j] == "e" or src[j] == "E") and j + 1 < n and (src[j + 1].is_valid_int() or src[j + 1] == "-"):
				j += 2
				while j < n and src[j].is_valid_int():
					j += 1
			toks.append([T_NUM, src.substr(i, j - i).to_float(), line])
			i = j
			continue
		if c == "$" and i + 1 < n and src[i + 1].is_valid_hex_number():
			var j := i + 1
			while j < n and src[j].is_valid_hex_number():
				j += 1
			toks.append([T_NUM, float(("0x" + src.substr(i + 1, j - i - 1)).hex_to_int()), line])
			i = j
			continue
		if c == "#" and i + 6 < n and src.substr(i + 1, 6).is_valid_hex_number():
			var rgb := src.substr(i + 1, 6)
			var r := rgb.substr(0, 2).hex_to_int()
			var g := rgb.substr(2, 2).hex_to_int()
			var b := rgb.substr(4, 2).hex_to_int()
			toks.append([T_NUM, float((b << 16) | (g << 8) | r), line])
			i += 7
			continue
		if c == "\"" or c == "'":
			var j := i + 1
			var s := ""
			while j < n and src[j] != c:
				if src[j] == "\n":
					line += 1
				s += src[j]
				j += 1
			toks.append([T_STR, s, line])
			i = j + 1
			continue
		if _is_id_start(c):
			var j := i
			while j < n and _is_id_char(src[j]):
				j += 1
			var word := src.substr(i, j - i)
			# GML keyword operators
			match word:
				"and":
					toks.append([T_OP, "&&", line])
				"or":
					toks.append([T_OP, "||", line])
				"xor":
					toks.append([T_OP, "^^", line])
				"not":
					toks.append([T_OP, "!", line])
				"div", "mod":
					toks.append([T_OP, word, line])
				"begin":
					toks.append([T_OP, "{", line])
				"end":
					toks.append([T_OP, "}", line])
				_:
					toks.append([T_ID, word, line])
			i = j
			continue
		var matched := false
		for op in OPS:
			if src.substr(i, op.length()) == op:
				toks.append([T_OP, op, line])
				i += op.length()
				matched = true
				break
		if not matched:
			i += 1   # unknown character: skip
	toks.append([T_EOF, null, line])


func _is_id_start(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


func _is_id_char(c: String) -> bool:
	return _is_id_start(c) or (c >= "0" and c <= "9")


# ---------------------------------------------------------------- parser helpers

func _peek(o := 0) -> Array:
	return toks[mini(p + o, toks.size() - 1)]


func _next() -> Array:
	var t: Array = toks[p]
	if p < toks.size() - 1:
		p += 1
	return t


func _is_op(v: String, o := 0) -> bool:
	var t := _peek(o)
	return t[0] == T_OP and t[1] == v


func _is_word(v: String) -> bool:
	var t := _peek()
	return t[0] == T_ID and t[1] == v


func _accept(v: String) -> bool:
	if _is_op(v):
		p += 1
		return true
	return false


func _expect(v: String) -> void:
	if not _accept(v):
		var t := _peek()
		if error == "":
			error = "line %d: expected '%s' but found '%s'" % [t[2], v, str(t[1])]
		# Skip a token so parsing always advances.
		_next()


# ---------------------------------------------------------------- statements

func _statement() -> Array:
	while _accept(";"):
		pass
	var t := _peek()
	if t[0] == T_EOF:
		return [S_BLOCK, []]
	if t[0] == T_OP and t[1] == "{":
		_next()
		var stmts: Array = []
		while not _is_op("}") and _peek()[0] != T_EOF:
			stmts.append(_statement())
			if error != "":
				break
		_expect("}")
		return [S_BLOCK, stmts]
	if t[0] == T_ID:
		match t[1]:
			"var", "globalvar":
				_next()
				var decls: Array = []
				while true:
					var name: String = _next()[1]
					var init = null
					if _accept("=") or _accept(":="):
						init = _expr()
					decls.append([name, init])
					if not _accept(","):
						break
				_accept(";")
				return [S_VAR, decls]
			"if":
				_next()
				var cond := _expr()
				_accept("then")
				if _is_word("then"):
					_next()
				var th := _statement()
				var el = null
				if _is_word("else"):
					_next()
					el = _statement()
				return [S_IF, cond, th, el]
			"while":
				_next()
				var cond := _expr()
				if _is_word("do"):
					_next()
				return [S_WHILE, cond, _statement()]
			"do":
				_next()
				var body := _statement()
				if _is_word("until"):
					_next()
				var cond := _expr()
				_accept(";")
				return [S_DO, body, cond]
			"for":
				_next()
				_expect("(")
				var init: Array = [S_BLOCK, []] if _is_op(";") else (_var_decl() if _is_word("var") else _simple_statement())
				_accept(";")
				var cond = [E_NUM, 1.0] if _is_op(";") else _expr()
				_accept(";")
				var step: Array = [S_BLOCK, []] if _is_op(")") else _simple_statement()
				_expect(")")
				return [S_FOR, init, cond, step, _statement()]
			"repeat":
				_next()
				var cnt := _expr()
				return [S_REPEAT, cnt, _statement()]
			"with":
				_next()
				var tg := _expr()
				return [S_WITH, tg, _statement()]
			"switch":
				_next()
				var e := _expr()
				_expect("{")
				var cases: Array = []
				while not _is_op("}") and _peek()[0] != T_EOF:
					var ce = null
					if _is_word("case"):
						_next()
						ce = _expr()
					elif _is_word("default"):
						_next()
					else:
						# statements before any case: skip
						_statement()
						continue
					_expect(":")
					var body: Array = []
					while not _is_word("case") and not _is_word("default") and not _is_op("}") and _peek()[0] != T_EOF:
						body.append(_statement())
						if error != "":
							break
					cases.append([ce, body])
				_expect("}")
				return [S_SWITCH, e, cases]
			"break":
				_next()
				_accept(";")
				return [S_BREAK]
			"continue":
				_next()
				_accept(";")
				return [S_CONTINUE]
			"exit":
				_next()
				_accept(";")
				return [S_EXIT]
			"return":
				_next()
				var rv = null
				if not _is_op(";") and not _is_op("}"):
					rv = _expr()
				_accept(";")
				return [S_RETURN, rv]
	var s := _simple_statement()
	_accept(";")
	return s


func _var_decl() -> Array:
	_next()
	var decls: Array = []
	while true:
		var name: String = _next()[1]
		var init = null
		if _accept("=") or _accept(":="):
			init = _expr()
		decls.append([name, init])
		if not _accept(","):
			break
	return [S_VAR, decls]


# Assignment, ++/--, or an expression (call).
func _simple_statement() -> Array:
	if _is_op("++") or _is_op("--"):
		var d := 1.0 if _next()[1] == "++" else -1.0
		return [S_INCDEC, _postfix(), d]
	var lhs := _expr_noassign()
	var t := _peek()
	if t[0] == T_OP:
		match t[1]:
			"=", ":=", "+=", "-=", "*=", "/=", "|=", "&=", "^=", "%=", "<<=", ">>=":
				_next()
				var op: String = "=" if t[1] == ":=" else t[1]
				return [S_ASSIGN, lhs, op, _expr()]
			"++", "--":
				_next()
				return [S_INCDEC, lhs, 1.0 if t[1] == "++" else -1.0]
	return [S_EXPR, lhs]


# ---------------------------------------------------------------- expressions

func _expr() -> Array:
	var e := _expr_noassign()
	# In conditions GML treats a lone "=" as comparison.
	if _is_op("=") and not _is_op("==", 1):
		_next()
		return [E_BIN, "==", e, _expr_noassign()]
	return e


func _expr_noassign() -> Array:
	var c := _or()
	if _is_op("?"):
		_next()
		var a := _expr()
		_expect(":")
		var b := _expr()
		return [E_TERN, c, a, b]
	return c


func _or() -> Array:
	var a := _and()
	while true:
		if _is_op("||"):
			_next()
			a = [E_OR, a, _and()]
		elif _is_op("^^"):
			_next()
			a = [E_BIN, "^^", a, _and()]
		else:
			break
	return a


func _and() -> Array:
	var a := _cmp()
	while _is_op("&&"):
		_next()
		a = [E_AND, a, _cmp()]
	return a


func _cmp() -> Array:
	var a := _bitor()
	while true:
		var t := _peek()
		if t[0] == T_OP and t[1] in ["==", "!=", "<", ">", "<=", ">="]:
			_next()
			a = [E_BIN, t[1], a, _bitor()]
		else:
			break
	return a


func _bitor() -> Array:
	var a := _shift()
	while true:
		var t := _peek()
		if t[0] == T_OP and t[1] in ["|", "&", "^"]:
			_next()
			a = [E_BIN, t[1], a, _shift()]
		else:
			break
	return a


func _shift() -> Array:
	var a := _add()
	while true:
		var t := _peek()
		if t[0] == T_OP and t[1] in ["<<", ">>"]:
			_next()
			a = [E_BIN, t[1], a, _add()]
		else:
			break
	return a


func _add() -> Array:
	var a := _mul()
	while true:
		var t := _peek()
		if t[0] == T_OP and t[1] in ["+", "-"]:
			_next()
			a = [E_BIN, t[1], a, _mul()]
		else:
			break
	return a


func _mul() -> Array:
	var a := _unary()
	while true:
		var t := _peek()
		if t[0] == T_OP and t[1] in ["*", "/", "%", "div", "mod"]:
			_next()
			var op: String = "mod" if t[1] == "%" else t[1]
			a = [E_BIN, op, a, _unary()]
		else:
			break
	return a


func _unary() -> Array:
	var t := _peek()
	if t[0] == T_OP:
		match t[1]:
			"!", "-", "~", "+":
				_next()
				var e := _unary()
				if t[1] == "+":
					return e
				if t[1] == "-" and e[0] == E_NUM:
					return [E_NUM, -e[1]]
				return [E_UN, t[1], e]
			"++", "--":
				_next()
				return [E_INCDEC, _postfix(), 1.0 if t[1] == "++" else -1.0, true]
	var e := _postfix()
	if _is_op("++") or _is_op("--"):
		# Postfix ++ inside an expression (rare in decompiled code).
		if _peek(1)[0] != T_EOF and not (_peek(1)[0] == T_OP and _peek(1)[1] in [";", ")", "}", ",", "]"]):
			return e
		var d := 1.0 if _next()[1] == "++" else -1.0
		return [E_INCDEC, e, d, false]
	return e


func _postfix() -> Array:
	var e := _primary()
	while true:
		if _is_op("."):
			_next()
			var name: String = _next()[1]
			e = [E_MEMBER, e, name]
		elif _is_op("["):
			_next()
			# Accessors like [@ ...] are not used by GMS 1.4 code; ignore the marker.
			if _peek()[0] == T_OP and _peek()[1] in ["@", "|", "?", "#"]:
				_next()
			var idx: Array = [_expr()]
			while _accept(","):
				idx.append(_expr())
			_expect("]")
			e = [E_INDEX, e, idx]
		else:
			break
	return e


func _primary() -> Array:
	var t := _next()
	match t[0]:
		T_NUM:
			return [E_NUM, t[1]]
		T_STR:
			return [E_STR, t[1]]
		T_ID:
			var name: String = t[1]
			if _is_op("("):
				_next()
				var args: Array = []
				if not _is_op(")"):
					args.append(_expr())
					while _accept(","):
						args.append(_expr())
				_expect(")")
				return [E_CALL, name, args]
			return [E_IDENT, name]
		T_OP:
			if t[1] == "(":
				var e := _expr()
				_expect(")")
				return e
	if error == "":
		error = "line %d: unexpected '%s'" % [t[2], str(t[1])]
	return [E_NUM, 0.0]
