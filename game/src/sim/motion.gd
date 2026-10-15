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


## A copy (plan 40: the client's dead reckoning steps copies, MwNetReckoning).
func copy() -> MwMotion:
	var motion := MwMotion.new()
	motion.pos = pos.duplicate()
	motion.vel = vel.duplicate()
	motion.acc = acc.duplicate()
	return motion


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


## Position in pixels (`asr.l #8`; plan 42: `>>` inline - arithmetic on
## a negative int as the 68000's asr, [method asr]).
func pixels() -> Vector3i:
	return Vector3i(pos[0] >> 8, pos[1] >> 8, pos[2] >> 8)


## `motion_step`: [param ticks] ticks, at most 8 at a time.
func step(params: Params, ticks: int) -> void:
	while ticks > 8:
		_chunk(params, 8)
		ticks -= 8
	if ticks > 0:
		_chunk(params, ticks)


func _chunk(params: Params, t: int) -> void:
	var on_ground := pos[2] == 0
	var factor := params.ground[t - 1] if on_ground else params.air[t - 1]
	var friction := params.friction_ground if on_ground else params.friction_air
	_axis(0, t, factor, friction, 0)
	_axis(1, t, factor, friction, 0)
	if pos[2] == 0 and vel[2] == 0 and acc[2] == 0:
		return
	for i in t:
		_axis(2, 1, 0, 0, params.gravity)
		if pos[2] < 0x100:
			pos[2] = 0
			if vel[2] < 0:
				vel[2] = ((((-vel[2]) * params.restitution >> 8) + 0x8000) & 0xFFFF) - 0x8000


## `motion_axis` for axis [param a]: [param t] ticks, decay [param factor],
## friction [param friction] (0: none), extra acceleration [param extra].
## Plan 42 (speed): the 68000's words inline - `((v + $8000) & $FFFF) -
## $8000` is MwRinkSim.s16(v), muls.w the two words multiplied (the motion
## step runs ~50 times a pass).
func _axis(a: int, t: int, factor: int, friction: int, extra: int) -> void:
	var ts := ((t + 0x8000) & 0xFFFF) - 0x8000
	if friction == 0:
		var v := vel[a]
		if v != 0:
			pos[a] += (((v + 0x8000) & 0xFFFF) - 0x8000) * ts
		var acceleration := ((acc[a] + extra + 0x8000) & 0xFFFF) - 0x8000
		if acceleration != 0:
			var d := acceleration * ts
			vel[a] = ((vel[a] + d + 0x8000) & 0xFFFF) - 0x8000
			d = (((d + 0x8000) & 0xFFFF) - 0x8000) * ((((t - 1) + 0x8000) & 0xFFFF) - 0x8000)
			pos[a] += d >> 1
		return
	var v4 := vel[a]
	var a3 := ((acc[a] + extra + 0x8000) & 0xFFFF) - 0x8000
	var d0: int
	var d1: int
	if a3 == 0:
		d0 = 0
		d1 = 0
	else:
		d1 = (((0x100 - factor + 0x8000) & 0xFFFF) - 0x8000) * a3
		d1 = divs(d1, friction)
		d0 = ts * a3
	d0 = ((d0 + v4 + 0x8000) & 0xFFFF) - 0x8000
	var d3: int
	if v4 < 0:
		d3 = -(((-v4) * factor) >> 8)
	else:
		d3 = (v4 * factor) >> 8
	d1 = ((d1 + d3 + 0x8000) & 0xFFFF) - 0x8000
	vel[a] = d1
	d0 = ((d0 - d1 + 0x8000) & 0xFFFF) - 0x8000
	if d0 != 0:
		pos[a] += divs(d0 << 8, friction)


## 68000 muls.w: 16 x 16 -> 32 bits, signed.
static func muls(a: int, b: int) -> int:
	return MwRinkSim.s16(a) * MwRinkSim.s16(b)


## 68000 divs.w: 32 / 16 -> 16-bit quotient, truncated toward zero.
static func divs(a: int, b: int) -> int:
	if b == 0:
		return 0
	var q := absi(a) / absi(b)
	return (((-q if (a < 0) != (b < 0) else q) + 0x8000) & 0xFFFF) - 0x8000       # (s16 inline: plan 42)


## Arithmetic shift right. (GDScript refuses `>>` on a negative constant
## when it parses; at run time `>>` on an int is arithmetic - plan 42.)
static func asr(v: int, n: int) -> int:
	return v >> n
