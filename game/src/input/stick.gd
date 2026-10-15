class_name MwStick
extends RefCounted
## An analogue stick quantised at the input layer (plan 35, docs/net.md):
## an angle and a travel, a byte each, before the game sees it - so a stick
## is two bytes in the input stream and every machine decodes it to the same
## vector.
##
## A code is [code]angle << 8 | travel[/code]: the angle in the game's units
## (0 = right, $40 = down, $80 = left: 256 steps, the units the simulation's
## readers already use - MwHumanControl.stick_angle, `$14290`), the travel
## 0-255 of the stick's way past its dead zone (0: no stick - the D-pad, as
## the original). [method decode] turns it back into the vector the readers
## take (each axis -256..256, x right, y down) with the original's sine
## table (`$1F628`, MwTrig) and integer arithmetic only: the same vector on
## every machine. Encoding runs where the stick is (floats are fine there:
## only its bytes travel).

## A code for no stick.
const NONE := 0


## The code of stick [param v] (each axis -256..256, x right, y down, its
## length the travel: MwLiveInput.stick_of); [constant NONE] for none.
static func encode(v: Vector2i) -> int:
	if v == Vector2i.ZERO:
		return NONE
	var f := Vector2(v)
	var travel_byte := clampi(roundi(f.length() * 255.0 / 256.0), 0, 255)
	if travel_byte == 0:
		return NONE
	var angle_byte := posmod(roundi(atan2(f.y, f.x) * 128.0 / PI), 256)
	return (angle_byte << 8) | travel_byte


## The stick's angle (0-255) in [param code].
static func angle(code: int) -> int:
	return (code >> 8) & 0xFF


## The stick's travel (0-255) in [param code].
static func travel(code: int) -> int:
	return code & 0xFF


## [param code] turned [param eighths] of a turn clockwise (the turned
## views, MwLiveInput.turns): exactly 32 angle steps an eighth.
static func turned(code: int, eighths: int) -> int:
	if code == NONE or eighths % 8 == 0:
		return code
	return (((angle(code) + 32 * eighths) & 0xFF) << 8) | travel(code)


## The eighth (0 right, 1 down-right, 2 down ... 7 up-right) [param code]
## points into, as a D-pad would hold it (MwLiveInput.with_eighth).
static func eighth(code: int) -> int:
	return ((angle(code) + 16) >> 5) & 7


## The vector the game reads for [param code] (each axis -256..256, x right,
## y down; ZERO for none): the travel scaled to 256 at full (255), along the
## angle, through the original's sine table [param rom] (MwTrig), rounded.
static func decode(code: int, rom: PackedByteArray = PackedByteArray()) -> Vector2i:
	if travel(code) == 0:
		return Vector2i.ZERO
	if rom.is_empty():
		rom = MwRom.data()
	@warning_ignore("integer_division")
	var length := (travel(code) * 256 + 127) / 255
	var a := angle(code)
	return Vector2i(_scale(MwTrig.cos_(rom, a), length), _scale(MwTrig.sin_(rom, a), length))


## ([param sine] * [param length]) / $8000, rounded to the nearest (halves away from 0).
static func _scale(sine: int, length: int) -> int:
	var p := sine * length
	return (p + 0x4000) >> 15 if p >= 0 else -((-p + 0x4000) >> 15)


## [param v] as the game sees it: encoded and decoded.
static func quantised(v: Vector2i, rom: PackedByteArray = PackedByteArray()) -> Vector2i:
	return decode(encode(v), rom)
