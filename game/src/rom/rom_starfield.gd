@tool
class_name RomStarfield
extends Node2D
## The scrolling starfield behind the credits and the main menu
## (docs/re/title.md, Credits): picture `$4546C` (32x32 cells) repeated on
## plane B and scrolled one step per 60 Hz tick by the original's VBlank task
## ($134E2): position (24.8 fixed point) += velocity, hscroll = x >> 8,
## vscroll = y >> 8. The velocity is one of 8 directions read from the
## original's tables ($13470 x, $1346C y), picked with the second random
## stream ($13480). The screen calls [method step] every tick.

const PICTURE := "picture_04546c"
const VX_TABLE := 0x13470
const VY_TABLE := 0x1346C
const SIZE := 256              # the picture's period in pixels

@export var palette: RomPalette:
	set(v):
		palette = v
		if _layer:
			_layer.palette = v

## Position, 1/256 pixels (the motion object's +0 / +8).
var x := 0
var y := 0
## Velocity, 1/256 pixels per tick.
var vx := 0
var vy := 0

var _layer: RomTileMapLayer


func _ready() -> void:
	_layer = RomTileMapLayer.new()
	_layer.name = "Plane"
	var ts := RomTileSet.new()
	ts.banks = PackedStringArray([PICTURE])
	_layer.tiles = ts
	_layer.palette = palette
	_layer.map = PICTURE
	_layer.repeat = Vector2i(3, 2)     # 768x512: covers 320x224 at any scroll
	add_child(_layer)
	_place()


## `starfield_scroll_start`: position 0, direction from [param rng]
## (`rng_next & $E` indexes the tables).
func start(rng: MlhRng) -> void:
	set_direction((rng.next_state() & 0xE) >> 1)


## Direction 0-7 (the tables' order: (100, 0), (72, 72), (0, 100), ...).
func set_direction(d: int) -> void:
	x = 0
	y = 0
	if MwRom.available():
		var rom := MwRom.data()
		vx = MwGfx.s16(rom, VX_TABLE + 2 * d)
		vy = MwGfx.s16(rom, VY_TABLE + 2 * d)
	_place()


## `$134A4`: another direction from [param rng] (the position's
## fractions dropped).
func redirect(rng: MlhRng) -> void:
	var d := (rng.next_state() & 0xE) >> 1
	x &= ~0xFF
	y &= ~0xFF
	if MwRom.available():
		var rom := MwRom.data()
		vx = MwGfx.s16(rom, VX_TABLE + 2 * d)
		vy = MwGfx.s16(rom, VY_TABLE + 2 * d)


## `$134D0`: the starfield stays where it is (velocity 0).
func hold() -> void:
	vx = 0
	vy = 0


## One tick of the VBlank task.
func step() -> void:
	x += vx
	y += vy
	_place()


## Plane B's scroll values in pixels (hscroll, vscroll): `asr.l #8`.
func scroll() -> Vector2i:
	return Vector2i(asr8(x), asr8(y))


## Arithmetic shift right by 8 (GDScript refuses `>>` on negative numbers).
static func asr8(v: int) -> int:
	return v >> 8 if v >= 0 else ~((~v) >> 8)


func _place() -> void:
	if _layer == null:
		return
	var s := scroll()
	# Screen (sx, sy) shows picture pixel ((sx - h) mod 256, (sy + v) mod 256).
	_layer.position = Vector2(posmod(s.x, SIZE) - SIZE, -posmod(s.y, SIZE))
