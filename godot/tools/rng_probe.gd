# Finds which WELL512a seeding / scaling reproduces the real runner's random numbers.
#   godot --headless --path godot --script res://tools/rng_probe.gd
extends SceneTree

const M := 0xFFFFFFFF
# random(1) x6 after random_set_seed(1), irandom(1000000) x4 after random_set_seed(1),
# random(1) x3 after random_set_seed(12345), from the real runner (trace scenario).
const R1 := [0.09149607783183456, 0.40309398807585239, 0.88373534218408167, 0.39058241993188858, 0.01607629400677979, 0.70126173319295049]
const I1 := [951164, 576511, 648019, 304018]
const R12345 := [0.39950493490323424, 0.12580747343599796, 0.50793713354505599]

var state: Array = []
var index := 0


func well() -> int:
	var a: int = state[index]
	var c: int = state[(index + 13) & 15]
	var b: int = (a ^ c ^ ((a << 16) & M) ^ ((c << 15) & M)) & M
	c = state[(index + 9) & 15]
	c = (c ^ (c >> 11)) & M
	a = (b ^ c) & M
	state[index] = a
	var d: int = (a ^ ((a << 5) & 0xDA442D24)) & M
	index = (index + 15) & 15
	a = state[index]
	state[index] = (a ^ b ^ d ^ ((a << 2) & M) ^ ((b << 18) & M) ^ ((c << 28) & M)) & M
	return state[index]


func irnd(n: int) -> int:
	var w1 := well()
	var w2 := well() & 0x7FFFFFFF
	var m := n + 1
	return ((w2 % m) * (4294967296 % m) + w1) % m


func seed_with(kind: int, s: int) -> void:
	state = []
	index = 0
	var x := s & M
	for i in 16:
		match kind:
			0:  # MSVC rand(): state = 15-bit outputs
				x = (x * 214013 + 2531011) & M
				state.append((x >> 16) & 0x7FFF)
			1:  # chained on the shifted value
				x = (((x * 214013 + 2531011) & M) >> 16) & 0x7FFFFFFF
				state.append(x)
			2:  # full 32-bit LCG state
				x = (x * 214013 + 2531011) & M
				state.append(x)
			3:  # LCG state shifted, chained on the full state
				x = (x * 214013 + 2531011) & M
				state.append((x >> 16) & 0xFFFF)
			4:  # (((s * 214013 + 2531011) >> 16) & 0x7fffffff), signed 32-bit arithmetic
				var t := (x * 214013 + 2531011) & M
				if t >= 0x80000000:
					t -= 0x100000000
				x = (t >> 16) & 0x7FFFFFFF
				state.append(x)


func _init() -> void:
	# Full check of the matching variant (kind 4, / 2^32).
	seed_with(4, 1)
	var a: Array = []
	for i in 6:
		a.append(float(well()) / 4294967296.0)
	print("R1 got ", a, "\n   want ", R1)
	seed_with(4, 1)
	var ia: Array = []
	var ib: Array = []
	for i in 4:
		var w := well()
		ia.append(w % 1000001)
		ib.append(int(floor(float(w) / 4294967296.0 * 1000001.0)))
	print("I1 mod ", ia, " floor ", ib, " want ", I1)
	var m := 1000001
	var p32 := 4294967296 % m
	var cands := {}
	for name in ["hi1lo2 mod", "hi2lo1 mod", "xor-mod", "53bit-floor", "53bit-floor-rev"]:
		cands[name] = []
	seed_with(4, 1)
	for i in 4:
		var w1 := well()
		var w2 := well()
		cands["hi1lo2 mod"].append(((w1 % m) * p32 + w2) % m)
		cands["hi2lo1 mod"].append(((w2 % m) * p32 + w1) % m)
		cands["xor-mod"].append((w1 ^ w2) % m)
		# Signed 64-bit: if w2's top bit is set the value is v - 2^64; C's % truncates
		# toward zero, then the runner takes the absolute value.
		var vm_ := ((w2 % m) * p32 + w1) % m
		if w2 >= 0x80000000:
			var two64 := ((p32 * p32) % m)
			cands.get_or_add("signed-abs", []).append((two64 - vm_ + m) % m)
		else:
			cands.get_or_add("signed-abs", []).append(vm_)
		cands.get_or_add("w2-top", []).append(1 if w2 >= 0x80000000 else 0)
		var w2m := w2 & 0x7FFFFFFF
		cands.get_or_add("mask63", []).append(((w2m % m) * p32 + w1) % m)
		cands["53bit-floor"].append(int(floor((float(w1 >> 5) * 67108864.0 + float(w2 >> 6)) / 9007199254740992.0 * m)))
		cands["53bit-floor-rev"].append(int(floor((float(w2 >> 5) * 67108864.0 + float(w1 >> 6)) / 9007199254740992.0 * m)))
	for k in cands:
		print("I1 cand %s %s" % [k, str(cands[k])])
	seed_with(4, 12345)
	a = []
	for i in 3:
		a.append(float(well()) / 4294967296.0)
	print("R12345 got ", a, " want ", R12345)
	seed_with(4, 7)
	print("rr 5+r*5 = %.14f want 9.66494638938456770" % (5.0 + float(well()) / 4294967296.0 * 5.0))
	var irm: Array = []
	var irf: Array = []
	var st := state.duplicate()
	var ix := index
	for i in 4:
		irm.append(3 + well() % 7)
	state = st.duplicate()
	index = ix
	for i in 4:
		irf.append(3 + int(floor(float(well()) / 4294967296.0 * 7.0)))
	print("irandom_range mod ", irm, " floor ", irf, " want [4, 9, 7, 3]")
	# irandom/choose via the 63-bit two-draw method, continuing after the rr draw.
	seed_with(4, 7)
	well()
	var ir2: Array = []
	for i in 4:
		ir2.append(3 + irnd(6))
	var c2: Array = []
	for i in 4:
		c2.append([10, 20, 30, 40][irnd(3)])
	print("irandom_range 63bit ", ir2, " want [4, 9, 7, 3]; choose 63bit ", c2, " want [20, 10, 40, 10]")
	seed_with(4, 7)
	well()
	var c3: Array = []
	for i in 4:
		irnd(6)
	for i in 4:
		c3.append([10, 20, 30, 40][int(floor(float(well()) / 4294967296.0 * 4.0))])
	print("choose by floor(random*n) ", c3)
	var variants := {
		"irnd(n)": func(): return irnd(4),
		"irnd(n-1)+skip": func(): var r := irnd(3); well(); return r,
		"w%n": func(): return well() % 4,
		"irnd(n) clamp": func(): return mini(irnd(4), 3),
		"floor(r*n) 2 draws": func(): well(); return int(floor(float(well()) / 4294967296.0 * 4.0)),
		"floor(r*(n-1)+0.5)": func(): return int(floor(float(well()) / 4294967296.0 * 3.0 + 0.5)),
		"round(r*(n-1))": func(): return int(roundf(float(well()) / 4294967296.0 * 3.0)),
	}
	for vn in variants:
		seed_with(4, 7)
		well()
		for i in 4:
			irnd(6)
		var out: Array = []
		for i in 4:
			var k: int = variants[vn].call()
			out.append([10, 20, 30, 40][clampi(k, 0, 3)])
		print("choose variant %s %s" % [vn, str(out)])
	quit()
	return
	var scales := {"2^32": 4294967296.0, "2^32-1": 4294967295.0}
	for kind in 5:
		for sk in scales:
			seed_with(kind, 1)
			var got: Array = []
			for i in 6:
				got.append(float(well()) / scales[sk])
			var ok: bool = absf(got[0] - R1[0]) < 1e-9
			print("seed kind %d scale %s: %s %s" % [kind, sk, str(got.slice(0, 3)), "MATCH" if ok else ""])
			# Also try 31-bit outputs.
			seed_with(kind, 1)
			got = []
			for i in 3:
				got.append(float(well() & 0x7FFFFFFF) / 2147483648.0)
			if absf(got[0] - R1[0]) < 1e-9:
				print("   31-bit MATCH kind %d" % kind)
	quit()
