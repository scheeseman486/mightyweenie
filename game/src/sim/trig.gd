class_name MwTrig
extends RefCounted
## The original's sine table and velocity helper (`$14214` sin, `$1423C`
## cos, `$14248` polar -> x/y, table `$1F628`: a quarter wave of 65 words,
## 0..$7FFF), its distance estimate (`$1425E`) and angle (`$14290`, a
## search through `$1F6AA`). Angles are bytes: 0 = +x, $40 = +y, $80 = -x.

const TABLE := 0x1F628
const ATAN := 0x1F6AA
## Plan 42: the ratios [method _search] can be asked about (0 .. $7FFD; at
## $7FFE and over the angle is $20 without a search).
const RATIOS := 0x7FFE

## Plan 42 (speed): [method _search]'s answer for every ratio, worked out
## once per ROM ([method _table]) - the walk costs ~3 us in GDScript and the
## rink asks ~150 angles a pass (the geometry, the AI, the collisions).
static var _atan := PackedByteArray()
static var _atan_rom_size := -1
static var _sin := PackedInt32Array()
static var _sin_rom_size := -1


## `$14214`: the sine of byte angle [param angle] from the quarter-wave table in
## [param rom], -$7FFF..$7FFF.
static func sin_(rom: PackedByteArray, angle: int) -> int:
	var i := angle & 0x3F
	if angle & 0x40:
		i = 0x40 - i
	if _sin_rom_size != rom.size():
		_sines(rom)
	var v := _sin[i]
	return -v if angle & 0x80 else v


## Plan 42 (speed): the quarter wave's 65 words read once per ROM ([member _sin]).
static func _sines(rom: PackedByteArray) -> void:
	var t := PackedInt32Array()
	for i in 65:
		t.append(MwGfx.s16(rom, TABLE + 2 * i))
	_sin = t
	_sin_rom_size = rom.size()


## `$1423C`: the cosine of byte angle [param angle] ([method sin_] a quarter
## turn on).
static func cos_(rom: PackedByteArray, angle: int) -> int:
	return sin_(rom, (angle + 0x40) & 0xFF)


## `$14248`: (cos(angle) * length >> 15, sin(angle) * length >> 15).
static func polar(rom: PackedByteArray, angle: int, length: int) -> Vector2i:
	return Vector2i(_asr15(cos_(rom, angle) * length), _asr15(sin_(rom, angle) * length))


static func _asr15(v: int) -> int:
	return v >> 15 if v >= 0 else ~((~v) >> 15)


## `$1425E`: (2 * max + min - min / 8) / 2 of |dx|, |dy| (about the length).
static func distance(dx: int, dy: int) -> int:
	var a := absi(dx)
	var b := absi(dy)
	if a < b:
		var t := a
		a = b
		b = t
	return (2 * a + b - (b >> 3)) >> 1


## `$14290`: the angle (0-255) of (dx, dy). The ratio small/big (`$7FFF`
## = 1) is looked up in `$1F6AA`, a 32-entry table the code walks like a
## binary tree (transcribed step by step: some steps move the table pointer
## without counting), then folded into the octant.
static func angle_of(rom: PackedByteArray, dx: int, dy: int) -> int:
	var octant := 0
	if dx < 0:
		dx = -dx
		octant += 4
	if dy < 0:
		dy = -dy
		octant += 8
	var a := 0
	if dx == dy:
		a = 0x20
	else:
		if dx < dy:
			var t := dx
			dx = dy
			dy = t
			octant += 2
		var q := ((dy << 16) >> 1) / dx
		if q >= RATIOS:
			a = 0x20
		else:
			if _atan_rom_size != rom.size():
				_table(rom)
			a = _atan[q]
	match octant:
		2: a = 0x40 - a
		4: a = 0x80 - a
		6: a = 0x40 + a
		8: a = 0x100 - a
		10: a = 0xC0 + a
		12: a = 0x80 + a
		14: a = 0xC0 - a
	return a & 0xFF


## Plan 42: [method _search] for every ratio into [member _atan]. The walk's
## answer rises with the ratio, a step at a time (32 steps over the table's
## 32 entries: test_trig_table checks every ratio), so each step's last
## ratio is found by halving - some 500 walks, not 32766. Keyed by the ROM's
## size: the game has one ROM (MwRom.data(); the sim's, the camera's, the
## AI's are it).
static func _table(rom: PackedByteArray) -> void:
	var t := PackedByteArray()
	t.resize(RATIOS)
	var q := 0
	while q < RATIOS:
		var v := _search(rom, q)
		var lo := q
		var hi := RATIOS - 1
		if _search(rom, hi) == v:
			lo = hi
		else:
			while hi - lo > 1:                  # _search(lo) == v, _search(hi) != v
				var mid := (lo + hi) >> 1
				if _search(rom, mid) == v:
					lo = mid
				else:
					hi = mid
		for k in range(q, lo + 1):
			t[k] = v
		q = lo + 1
	_atan = t
	_atan_rom_size = rom.size()


## The table walk at `$142B8` (labels are the code's addresses).
static func _search(rom: PackedByteArray, q: int) -> int:
	var p := 0
	var a := 0
	var at := 0x142C0
	while true:
		var t := MwGfx.s16(rom, ATAN + 2 * p)
		match at:
			0x142C0: at = 0x142F4 if q >= t else 0x142C4
			0x142C4:
				p += 1
				at = 0x14300 if q >= MwGfx.s16(rom, ATAN + 2 * p) else 0x142CC
			0x142CC:
				p += 1
				at = 0x1430A if q >= MwGfx.s16(rom, ATAN + 2 * p) else 0x142D4
			0x142D4:
				p += 1
				at = 0x14314 if q >= MwGfx.s16(rom, ATAN + 2 * p) else 0x142DC
			0x142DC:
				p += 1
				at = 0x1431E if q >= MwGfx.s16(rom, ATAN + 2 * p) else 0x142E4
			0x142E4:
				return a
			0x142F4:
				p += 16
				a += 16
				at = 0x142CC if q < MwGfx.s16(rom, ATAN + 2 * p) else 0x14300
			0x14300:
				p += 8
				a += 8
				at = 0x142D4 if q < MwGfx.s16(rom, ATAN + 2 * p) else 0x1430A
			0x1430A:
				p += 4
				a += 4
				at = 0x142DC if q < MwGfx.s16(rom, ATAN + 2 * p) else 0x14314
			0x14314:
				p += 2
				a += 2
				at = 0x142E4 if q < MwGfx.s16(rom, ATAN + 2 * p) else 0x1431E
			0x1431E:
				return a + 1
	return a
