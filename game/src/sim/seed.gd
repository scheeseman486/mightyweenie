class_name MwSeed
extends RefCounted
## Plan 40 (S9): the port's seed arithmetic in one place - integers only,
## so the same on every machine and every engine version (Godot's
## [code]hash()[/code] promises neither: the survey's B5).
## * [method mul32], [method mix32]: a 32-bit multiply and MurmurHash3's
##   finaliser (the session's streams, plan 35: MwSession);
## * [method mix] / [method unit]: a new derivation from a few integers;
## * [method knuth]: Knuth's multiplicative scramble as the crowd, the
##   stands and the paint seed their generators (their outputs are the
##   matches' looks and the saved replays' paint: unchanged);
## * [method engine_hash_ints] / [method engine_hash_bytes]: Godot 4's
##   [code]hash()[/code] of a Vector3i / a PackedByteArray, reproduced - the
##   stands' filling order and an old replay's paint seed came from it, and
##   stay what they were (test_seed checks it against this engine).
## The generators themselves stay as they are (the splatter's LCG,
## MwBench3D.rand, MlhRng).

## Knuth's multiplier (2^32 / the golden ratio).
const KNUTH := 2654435761
const _MURMUR_SEED := 0x7F07C65
const _C1 := 0xCC9E2D51
const _C2 := 0x1B873593


## [param a] x [param b] modulo 2^32 (no 64-bit overflow on the way).
static func mul32(a: int, b: int) -> int:
	a &= 0xFFFFFFFF
	b &= 0xFFFFFFFF
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF


## MurmurHash3's 32-bit finaliser: every input bit moves every output bit.
static func mix32(x: int) -> int:
	x &= 0xFFFFFFFF
	x ^= x >> 16
	x = mul32(x, 0x85EBCA6B)
	x ^= x >> 13
	x = mul32(x, 0xC2B2AE35)
	x ^= x >> 16
	return x


## A seed (32 bits) from [param values] in order: each mixed into the last.
static func mix(values: Array) -> int:
	var h := 0
	for v in values:
		h = mix32(h ^ mix32(int(v)))
	return h


## A number in [0, 1) from [param seed_value] and [param salt] ([method mix]).
static func unit(seed_value: int, salt: int) -> float:
	return float(mix([seed_value, salt])) / 4294967296.0


## Knuth's scramble: [param offset] + [param x] x [constant KNUTH] (64-bit,
## as the callers always made it; each masks it its own way).
static func knuth(x: int, offset := 0) -> int:
	return offset + x * KNUTH


## Godot 4's hash() of Vector3i([param x], [param y], [param z]): MurmurHash3
## steps over the three 32-bit components and its finaliser.
static func engine_hash_ints(x: int, y: int, z: int) -> int:
	var h := _murmur_step(x, _MURMUR_SEED)
	h = _murmur_step(y, h)
	h = _murmur_step(z, h)
	return mix32(h)


## Godot 4's hash() of the PackedByteArray [param b]: MurmurHash3 (32-bit)
## over its bytes, the length mixed in.
static func engine_hash_bytes(b: PackedByteArray) -> int:
	var n := b.size()
	if n == 0:
		return -1                                # (not used: an empty frame never comes)
	var h := _MURMUR_SEED
	var blocks := n >> 2
	for i in blocks:
		var o := i << 2
		h = _murmur_step(b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24), h)
	var tail := blocks << 2
	var k := 0
	match n & 3:
		3:
			k = b[tail] | (b[tail + 1] << 8) | (b[tail + 2] << 16)
		2:
			k = b[tail] | (b[tail + 1] << 8)
		1:
			k = b[tail]
	if n & 3 != 0:
		k = mul32(k, _C1)
		k = _rotl(k, 15)
		k = mul32(k, _C2)
		h ^= k
	h ^= n
	return mix32(h)


static func _murmur_step(k: int, h: int) -> int:
	k = mul32(k, _C1)
	k = _rotl(k, 15)
	k = mul32(k, _C2)
	h = (h ^ k) & 0xFFFFFFFF
	h = _rotl(h, 13)
	return (h * 5 + 0xE6546B64) & 0xFFFFFFFF


static func _rotl(x: int, r: int) -> int:
	x &= 0xFFFFFFFF
	return ((x << r) | (x >> (32 - r))) & 0xFFFFFFFF
