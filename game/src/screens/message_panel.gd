class_name MwMessagePanel
extends RefCounted
## The framed panel of the scoreboards' window (`$EE50` / `$EE68`; plan 11,
## docs/re/scoreboards.md): an object of a direction (1 opening, -1 closing,
## 0 still), a tick remainder and a size (6..26 cells wide). While it moves
## it grows or shrinks one cell per 2 ticks and is redrawn at its size, a
## frame centred on column 20: `(size - 4) / 5 + 3` rounded up to odd rows
## of inside plus the frame, from the row-kind table `$1D31C` (4 variants by
## the parity of the size and of the rows; an outer ring of blank cells
## rubs out what a bigger panel left).

const TILES := 0x1D31C
const SMALL := 6
const BIG := 0x1A

var dir := 0          ## +0
var remainder := 0    ## +2
var size := SMALL     ## +4


## `$EE50`: still, closed.
func reset() -> void:
	dir = 0
	remainder = 0
	size = SMALL


## Starts opening (1) or closing (-1).
func move(direction: int) -> void:
	dir = direction


## `$EE68`: [param elapsed] ticks of motion; when it moved, its cells are
## appended to [param ops] (MwWindowPainter "fill" operations, the window).
## Returns whether it moved (and was drawn).
func step(elapsed: int, rom: PackedByteArray, ops: Array) -> bool:
	if dir == 0:
		return false
	var t := (elapsed & 0xFFFF) + remainder
	remainder = t % 2
	var steps := t / 2
	if steps == 0:
		return false
	var d := size + (steps if dir > 0 else -steps)
	if d < SMALL:
		dir = 0
		d = SMALL
	elif d > BIG:
		dir = 0
		d = BIG
	size = d
	draw(rom, ops)
	return true


## `$EEB4`: the panel at its size as fill operations.
func draw(rom: PackedByteArray, ops: Array) -> void:
	var w := size
	var rows := (w - 4) / 5 + 3
	var a := TILES
	if rows & 1:
		a += 0x64
	if w & 1:
		a += 0x32
	rows |= 1
	w = (w + 1) & ~1
	var y := (0x13 - rows) >> 1
	_row(rom, a, w, y, ops)
	y += 1
	_row(rom, a + 10, w, y, ops)
	for i in rows - 2:
		y += 1
		_row(rom, a + 20, w, y, ops)
	y += 1
	_row(rom, a + 30, w, y, ops)
	y += 1
	_row(rom, a + 40, w, y, ops)


## `$EF22`: one row: edge, edge, the middle (width - 4), edge, edge.
static func _row(rom: PackedByteArray, a: int, w: int, y: int, ops: Array) -> void:
	var x := 0x14 - (w >> 1)
	ops.append(["fill", x, y, 1, 1, MwGfx.u16(rom, a)])
	ops.append(["fill", x + 1, y, 1, 1, MwGfx.u16(rom, a + 2)])
	ops.append(["fill", x + 2, y, w - 4, 1, MwGfx.u16(rom, a + 4)])
	var r := 0x14 + (w >> 1) - 2
	ops.append(["fill", r, y, 1, 1, MwGfx.u16(rom, a + 6)])
	ops.append(["fill", r + 1, y, 1, 1, MwGfx.u16(rom, a + 8)])
