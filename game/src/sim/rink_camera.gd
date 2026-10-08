class_name MwRinkCamera
extends RefCounted
## The rink camera (rink state `$FFB0E8` +4..+$16; docs/re/rink.md,
## Camera), node-free: a point in the rink map (its top-left corner on
## screen) that chases a target object.
##
## Each pass ([method update], `$56EA`) it aims at the target's position
## plus 16 ticks of its velocity, 56 px up or down the ice towards the goal
## the puck carrier attacks ([member lead], kept when nobody carries the
## puck), clamped to the map; it accelerates by `$C0` (1/256 px) per elapsed
## tick and pass, never faster than distance * elapsed / 32 px per pass, and
## never more than 32 px down or up per pass. A shake ([member shake] ticks,
## [member amp] px) adds an x offset whose sign flips every pass. [member
## shown] is what the planes and sprites use (`$FFB0B6/$FFB0B8`).
##
## Pass-rate dependence (for Stage 2): [member speed] grows per pass by
## `$C0` * elapsed (twice the passes, twice the acceleration), the 32 px
## cap is per pass and the shake's sign flips per pass; the
## distance * elapsed cap does not depend on the rate.

const MAP := 0x24CFC          ## the rink picture: width, height (cells) at +8, +$A
const STEP := 0xC0            ## acceleration per elapsed tick
const LEAD := 0x38            ## look-ahead when the puck is carried
const MAX_DY := 0x2000        ## vertical step cap (24.8)
const CENTRE := Vector2i(0xA0, 0x70)   ## half the screen

## 24.8 map position of the screen's top-left corner (+8, +$C).
var x := 0
var y := 0
## 1/256 px per pass (+6, an unsigned word).
var speed := 0
## Look-ahead in y (+$10): 0, +56 or -56.
var lead := 0
## Shake: ticks left (+$12), x amplitude (+$14), a word cleared with them (+$16).
var shake := 0
var amp := 0
var shake_16 := 0
## The integer camera the screen shows (after shake and clamp).
var shown := Vector2i.ZERO


## The camera's range: map size minus the screen (192 x 680 on the rink).
static func limits(rom: PackedByteArray) -> Vector2i:
	return Vector2i(8 * MwGfx.u16(rom, MAP + 8) - 320, 8 * MwGfx.u16(rom, MAP + 0xA) - 224)


## `$155D0`: [param v] clamped to 0..[param hi] per axis.
static func clamp_to(v: Vector2i, hi: Vector2i) -> Vector2i:
	return Vector2i(0 if v.x < 0 else mini(v.x, hi.x), 0 if v.y < 0 else mini(v.y, hi.y))


## Camera point that centres rink point ([param rx], [param ry]) (ground
## level), clamped: map (x + 256, y + 461) minus half the screen.
static func centred_on(rom: PackedByteArray, rx: int, ry: int) -> Vector2i:
	return clamp_to(Vector2i(rx + 0x100 - CENTRE.x, ry + 0x1CD - CENTRE.y), limits(rom))


## `$5BF6`: jump to centre rink point ([param rx], [param ry]); speed and
## look-ahead 0. (The shown camera follows at the next [method update].)
func place(rom: PackedByteArray, rx: int, ry: int) -> void:
	var c := centred_on(rom, rx, ry)
	x = c.x << 8
	y = c.y << 8
	speed = 0
	lead = 0


## `$56EA` (camera part): one pass of [param elapsed] ticks. [param target]
## is the followed object's motion (null: hold still); [param new_lead]
## replaces [member lead] when the puck is carried (null keeps it).
func update(rom: PackedByteArray, elapsed: int, target: MwMotion, new_lead: Variant = null) -> Vector2i:
	var hi := limits(rom)
	if target != null:
		var p := target.pixels()
		var tx := MwMotion.s16(p.x + MwMotion.asr(target.vel[0], 4))
		var ty := MwMotion.s16(p.y + MwMotion.asr(target.vel[1], 4))
		if new_lead != null:
			lead = int(new_lead)
		var want := clamp_to(Vector2i(MwMotion.s16(tx + 0x100 - CENTRE.x),
				MwMotion.s16(ty + 0x1CD - CENTRE.y + lead)), hi)
		var dx := MwMotion.s16(want.x - (x >> 8))
		var dy := MwMotion.s16(want.y - (y >> 8))
		var d := MwTrig.distance(dx, dy) & 0xFFFF
		var a := MwTrig.angle_of(rom, dx, dy)
		var lim := ((d * elapsed) << 3) & 0xFFFF        # mulu.w, lsl.w #3
		if lim < speed:
			speed = lim
		else:
			speed = (speed + STEP * elapsed) & 0xFFFF
			if speed >= lim:
				speed = lim
		var step := MwTrig.polar(rom, a, MwMotion.s16(speed))
		x += MwMotion.s16(step.x)
		y += clampi(MwMotion.s16(step.y), -MAX_DY, MAX_DY)
	var sx := MwMotion.s16(x >> 8)
	var sy := MwMotion.s16(y >> 8)
	if shake != 0:
		shake = MwMotion.s16(shake - elapsed)
		if shake > 0:
			amp = MwMotion.s16(-amp)
			sx = MwMotion.s16(sx + amp)
		else:
			shake = 0
			amp = 0
			shake_16 = 0
	shown = clamp_to(Vector2i(sx, sy), hi)
	return shown


## Start a shake of [param ticks] ticks and [param px] pixels (`$52CA`,
## `$780A`: 30 ticks, 8 px).
func start_shake(ticks: int, px: int) -> void:
	shake = ticks
	amp = px
