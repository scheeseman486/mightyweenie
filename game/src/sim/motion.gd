class_name MwMotion
extends RefCounted
## The original's motion objects (`motion_init` $15402, `motion_step`
## $15368, `motion_axis` $152EE, `motion_params` $15554): x, y, z positions in
## 24.8 fixed point with 16-bit velocities and accelerations (1/256 pixel per
## tick), friction per axis group, and a z axis with gravity that bounces at
## 0 with a restitution factor. Integer arithmetic as on the 68000 (muls /
## divs truncate toward zero). Used by the starfield, the team description's
## page drops and, in plan 08, players and the puck.

## Position (24.8), velocity, acceleration per axis: [x, y, z].
var pos := PackedInt32Array([0, 0, 0])
var vel := PackedInt32Array([0, 0, 0])
var acc := PackedInt32Array([0, 0, 0])


## Motion parameters (`$15554`): gravity on z, restitution (/256) of a
## bounce, friction on the ground and in the air (/256 per tick); the decay
## factors for 1-8 ticks are tabulated like the original's.
class Params:
	var gravity := 0
	var restitution := 0
	var friction_ground := 0
	var friction_air := 0
	var ground := PackedInt32Array()   ## factor for 1..8 ticks (index 0 = 1 tick)
	var air := PackedInt32Array()

	func _init(g := 0, r := 0, fg := 0, fa := 0) -> void:
		gravity = g
		restitution = r
		friction_ground = fg
		friction_air = fa
		ground = _powers(fg)
		air = _powers(fa)

	static func _powers(f: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		var base := (0x100 - f) & 0xFFFF
		var v := base
		for i in 8:
			out.append(v)
			v = ((v * base) >> 8) & 0xFFFF   # mulu.w uses the low word
		return out


## `motion_init`: positions in whole pixels, velocities 0.
func init(x: int, y: int, z := 0) -> void:
	pos = PackedInt32Array([x << 8, y << 8, z << 8])
	vel = PackedInt32Array([0, 0, 0])
	acc = PackedInt32Array([0, 0, 0])


## Position in pixels (`asr.l #8`).
func pixels() -> Vector3i:
	return Vector3i(asr(pos[0], 8), asr(pos[1], 8), asr(pos[2], 8))


## `motion_step`: [param ticks] ticks, at most 8 at a time.
func step(params: Params, ticks: int) -> void:
	while ticks > 8:
		_chunk(params, 8)
		ticks -= 8
	if ticks > 0:
		_chunk(params, ticks)


func _chunk(p: Params, t: int) -> void:
	var on_ground := pos[2] == 0
	var factor := p.ground[t - 1] if on_ground else p.air[t - 1]
	var friction := p.friction_ground if on_ground else p.friction_air
	_axis(0, t, factor, friction, 0)
	_axis(1, t, factor, friction, 0)
	if pos[2] == 0 and vel[2] == 0 and acc[2] == 0:
		return
	for i in t:
		_axis(2, 1, 0, 0, p.gravity)
		if pos[2] < 0x100:
			pos[2] = 0
			if vel[2] < 0:
				vel[2] = s16(((-vel[2]) * p.restitution) >> 8)


## `motion_axis` for axis [param a]: [param t] ticks, decay [param factor],
## friction [param friction] (0: none), extra acceleration [param extra].
func _axis(a: int, t: int, factor: int, friction: int, extra: int) -> void:
	if friction == 0:
		var v := vel[a]
		if v != 0:
			pos[a] += muls(v, t)
		var acceleration := s16(acc[a] + extra)
		if acceleration != 0:
			var d := muls(acceleration, t)
			vel[a] = s16(vel[a] + d)
			d = muls(s16(d), t - 1)
			pos[a] += asr(d, 1)
		return
	var v4 := vel[a]
	var a3 := s16(acc[a] + extra)
	var d0: int
	var d1: int
	if a3 == 0:
		d0 = 0
		d1 = 0
	else:
		d1 = muls(s16(0x100 - factor), a3)
		d1 = divs(d1, friction)
		d0 = muls(t, a3)
	d0 = s16(d0 + v4)
	var d3: int
	if v4 < 0:
		d3 = -(((-v4) * factor) >> 8)
	else:
		d3 = (v4 * factor) >> 8
	d1 = s16(d1 + d3)
	vel[a] = d1
	d0 = s16(d0 - d1)
	if d0 != 0:
		pos[a] += divs(d0 << 8, friction)


static func s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


## 68000 muls.w: 16 x 16 -> 32 bits, signed.
static func muls(a: int, b: int) -> int:
	return s16(a) * s16(b)


## 68000 divs.w: 32 / 16 -> 16-bit quotient, truncated toward zero.
static func divs(a: int, b: int) -> int:
	if b == 0:
		return 0
	var q := absi(a) / absi(b)
	return s16(-q if (a < 0) != (b < 0) else q)


## Arithmetic shift right (GDScript refuses `>>` on negative numbers).
static func asr(v: int, n: int) -> int:
	return v >> n if v >= 0 else ~((~v) >> n)
