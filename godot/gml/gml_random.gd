# GameMaker: Studio 1.4's random number generator, reproduced exactly.
#
# Measured against the real runner (scenario "trace" logs raw results for known seeds;
# godot/tools/rng_probe.gd checks them): WELL512a, seeded by a signed 32-bit LCG.
#   random(n)            = next() / 2^32 * n
#   random_range(a, b)   = a + next() / 2^32 * (b - a)
#   irandom(n)           = (((next2 & 0x7FFFFFFF) << 32) | next1) mod (n + 1)   (two draws)
#   irandom_range(a, b)  = a + irandom(b - a)
#   choose(x0..xk)       = x[next() mod (k + 1)]                                (one draw)
# With the same seed, a fight therefore rolls the same numbers as the original game.
extends RefCounted

const M := 0xFFFFFFFF

var state := PackedInt64Array()
var index := 0
var seed_value := 0


func _init() -> void:
	set_seed(int(Time.get_ticks_usec() & 0x7FFFFFFF))


func set_seed(s: int) -> void:
	seed_value = s
	state.resize(16)
	index = 0
	var x := s & M
	for i in 16:
		var t := (x * 214013 + 2531011) & M
		if t >= 0x80000000:
			t -= 0x100000000
		x = (t >> 16) & 0x7FFFFFFF
		state[i] = x


func next() -> int:
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


func frac() -> float:
	return float(next()) / 4294967296.0


func random(n: float) -> float:
	return frac() * n


# irandom(n) for n >= 0 (negative n mirrors, as the runner works on the magnitude).
func irandom(n: int) -> int:
	if n < 0:
		return -irandom(-n)
	var w1 := next()
	var w2 := next() & 0x7FFFFFFF
	var m := n + 1
	return ((w2 % m) * (4294967296 % m) + w1) % m


# A uniform pick among n items with one draw (choose, and runner functions like it).
func pick(n: int) -> int:
	if n <= 0:
		return 0
	return next() % n
