class_name MwAnimState
extends RefCounted
## The original's animation object (`anim_set` $14388, `anim_advance`
## $143CA; docs/re/title.md, Animation objects), node-free and tick-driven:
## the position is 8.8 frames in a 16-bit word, advanced by speed x elapsed
## ticks; the flags' bit 7 = playing, bit 6 = loop, bits 0-2 = mode (0-1
## forward, 2 reverse, 3 ping-pong). Integer behaviour is the original's,
## quirks included (the ping-pong's way back reads one frame lower, and its
## turning point can read frame [member count]). In RAM the object is
## `+0 record.l, +4 speed.w, +6 flags.b, +7 variant.b, +8 position.w,
## +$A frame.b`.

const PLAYING := 0x80
const LOOP := 0x40

## ROM address of the animation record (+0).
var address := 0
## Variant (direction) whose frame list is shown (+7).
var variant := 0
## 8.8 frames per tick (the record's word +0).
var speed := 0
## Record byte +2 (with PLAYING set by the caller).
var flags := 0
## Frames in the animation (record byte +3).
var count := 0
## 8.8 position (16-bit).
var position := 0
## Frame index shown (+$A).
var frame := 0


## `anim_set` ($14388; $1438A with a variant): from an animation record in
## the ROM, at frame 0, flags as the record has them.
static func from_record(rom: PackedByteArray, address_: int, variant_ := 0) -> MwAnimState:
	var s := MwAnimState.new()
	s.address = address_
	s.variant = variant_
	s.speed = MwGfx.u16(rom, address_)
	s.flags = rom[address_ + 2]
	s.count = rom[address_ + 3]
	return s


## An animation object as recorded: [record, speed, flags, variant,
## position, frame] (harness/mw_harness/rink_state.py); count from the ROM.
static func from_fields(rom: PackedByteArray, f: Array) -> MwAnimState:
	var s := MwAnimState.new()
	s.address = int(f[0])
	s.speed = int(f[1])
	s.flags = int(f[2])
	s.variant = int(f[3])
	s.position = int(f[4])
	s.frame = int(f[5])
	if s.address > 0 and s.address + 3 < rom.size():
		s.count = rom[s.address + 3]
	return s


## `$1563E`: the ROM address of the frame shown and the variant's flips
## (bit 0 H, bit 1 V). The variant word at record + 8 + 2 * variant holds
## `list offset << 2 | flips`; the frame is the record's frame base (+4)
## plus the list's word for [member frame] (both offsets signed words, as
## `adda.w`).
func frame_address(rom: PackedByteArray) -> Vector2i:
	var w := MwGfx.u16(rom, address + 8 + 2 * variant)
	var lst := address + (w >> 2)
	var off := MwGfx.s16(rom, lst + 2 * frame)
	return Vector2i(MwGfx.u32(rom, address + 4) + off, w & 3)


## `$1438E`: switch to the animation record at [param address_] keeping
## the variant: speed and flags from the record, at frame 0.
func set_record(rom: PackedByteArray, address_: int) -> void:
	address = address_
	speed = MwGfx.u16(rom, address_)
	flags = rom[address_ + 2]
	count = rom[address_ + 3]
	position = 0
	frame = 0


## `$143AC`: the play mode bits (0-2, loop 6) from [param mode_flags] (0 =
## the record's own), the rest kept.
func set_mode(rom: PackedByteArray, mode_flags: int) -> void:
	if mode_flags == 0:
		mode_flags = rom[address + 2]
	flags = ((mode_flags ^ flags) & 0x47) ^ flags


## A copy of this animation object.
func copy() -> MwAnimState:
	var c := MwAnimState.new()
	c.address = address
	c.variant = variant
	c.speed = speed
	c.flags = flags
	c.count = count
	c.position = position
	c.frame = frame
	return c


## Start (again) from frame 0: what the screens do after `anim_set`.
func play() -> void:
	position = 0
	frame = 0
	flags |= PLAYING


func playing() -> bool:
	return (flags & PLAYING) != 0


## `anim_advance`: [param elapsed] ticks (a no-op when stopped).
func advance(elapsed: int) -> void:
	if not playing():
		return
	var d1 := (position + speed * elapsed) & 0xFFFF
	var full := (count << 8) & 0xFFFF
	var length := full
	var mode := flags & 7
	if mode == 3:
		length = ((full - 0x100) * 2) & 0xFFFF
	if d1 >= length:
		if flags & LOOP:
			if length == 0:
				d1 = 0                      # (the original would spin forever)
			while d1 >= length and length > 0:
				d1 -= length
		else:
			flags &= ~PLAYING
			d1 = (length - 1) & 0xFFFF
	position = d1
	var f := d1
	if mode == 2:
		f = (length - 1 - d1) & 0xFFFF
	elif mode >= 3 and d1 > full:
		f = (length - d1) & 0xFFFF
	frame = (f >> 8) & 0xFF
