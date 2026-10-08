class_name MwMenuRows
extends RefCounted
## The main menu's rows, read from the original's own menu data at run time
## (docs/re/menus.md, Main menu rows): `$1F4FA` lists one 36-byte record per
## setup byte (`$FFB0DE` + row; the period-minutes byte has none):
##
## [codeblock]
## +0  change handler        +4  fill word of an unselected item
## +6  value count (wrap)    +8  label item     +$16 value item
## item: +0 string list, +4 stride, +6 plane, +$A x, +$B y, +$C width, +$D centred
## [/codeblock]
##
## The string of an item is the pointer at `list + setup[row] * stride`
## (stride 0: a fixed label). The stadium row lives in RAM (`$FFC7D0`, copied
## from `$1F46A`) because its value list - the stadiums' names - is built at
## run time from the team records.

const TABLE := 0x1F4FA
const ROWS := 10
const RECORD_SIZE := 36
const STADIUM_ROW := 6
const STADIUM_TEMPLATE := 0x1F46A
## Up / Down: the next row for each row (`$139A8`, `$139B2`).
const UP := 0x139A8
const DOWN := 0x139B2
## Highlighted items: fill word (tile $DD, line 3) and the dark font.
const SELECTED_FILL := 0x60DD
## Text attr of the rows (line 3, priority).
const TEXT_ATTR := 0xE0
## The plane objects an item names (+6): plane A's (`$FFB09A`); the others
## (the window's, `$FFB0CA`) draw where the plane routes the row.
const PLANE_A := 0xFFB09A

var rom: PackedByteArray
## Record address per row (0 = none); the stadium row's is the ROM template.
var records := PackedInt32Array()
## Stadium names (string addresses) by stadium/team index.
var stadium_names := PackedInt32Array()


func _init(rom_bytes: PackedByteArray) -> void:
	rom = rom_bytes
	for i in ROWS:
		var a := MwGfx.u32(rom, TABLE + 4 * i)
		if a >= 0xFF0000:
			a = STADIUM_TEMPLATE if i == STADIUM_ROW else 0
		records.append(a)
	for t in MwTeams.COUNT:
		stadium_names.append(MwGfx.u32(rom, MwTeams.stadium_record(rom, t)))


func has_row(row: int) -> bool:
	return row >= 0 and row < ROWS and records[row] != 0


## Handler address of a row (0 = none).
func handler(row: int) -> int:
	return MwGfx.u32(rom, records[row])


func fill_word(row: int) -> int:
	return MwGfx.u16(rom, records[row] + 4)


## How many values the row has (Left/Right wrap).
func count(row: int) -> int:
	return rom[records[row] + 6]


## Item [param which] (0 label, 1 value): {list, stride, x, y, w, centred}.
func item(row: int, which: int) -> Dictionary:
	var a := records[row] + (8 if which == 0 else 0x16)
	return {"list": MwGfx.u32(rom, a), "stride": MwGfx.u16(rom, a + 4),
			"x": rom[a + 10], "y": rom[a + 11], "w": rom[a + 12], "centred": rom[a + 13] != 0}


## Where item [param which] of [param row] draws: its plane object (+6). The
## menu's rows 3-9 name plane A: everything of theirs goes there, also the
## top edge of the play mode row's highlight frame on row 15 - a row the
## window shows (with the backdrop's skull), plane A only its last pixel
## line, through its 1-pixel scroll. [param plane] is the window's
## [RomPlane]; its [member RomPlane.lower] is plane A.
func plane_of(plane: RomPlane, row: int, which: int) -> RomPlane:
	var a := records[row] + (8 if which == 0 else 0x16) + 6
	if MwGfx.u32(rom, a) & 0xFFFFFF == PLANE_A and plane.lower != null:
		return plane.lower
	return plane


## Address of the string an item shows for setup value [param value].
func string_of(row: int, which: int, value: int) -> int:
	var it := item(row, which)
	if row == STADIUM_ROW and which == 1:
		return stadium_names[value]
	return MwGfx.u32(rom, int(it["list"]) + value * int(it["stride"]))


## The next row for Up / Down.
func up(row: int) -> int:
	return rom[UP + row]


func down(row: int) -> int:
	return rom[DOWN + row]


## `$12D1E` / `$12D18`: draws a row's label and value for setup value
## [param value]. [param selected]: highlighted (`$C7C6` is this row);
## [param text_only] (`$12D18`): the cells are not cleared first.
func draw(plane: RomPlane, row: int, value: int, selected: bool, text_only := false) -> void:
	for which in 2:
		var it := item(row, which)
		var target := plane_of(plane, row, which)
		var x: int = it["x"]
		var y: int = it["y"]
		var w: int = it["w"]
		if not text_only:
			MwPlanePainter.fill(target, x, y, w, 1, SELECTED_FILL if selected else fill_word(row))
		var s := MwGfx.rom_string(rom, string_of(row, which, value))
		if it["centred"]:
			x += ((w - MwGfx.text_width(rom, MwPlanePainter.FONT_MENU, s)) & 0xFF) >> 1
		var font := MwPlanePainter.FONT_SMALL if selected else MwPlanePainter.FONT_MENU
		MwPlanePainter.text(target, rom, font, s, x, y, TEXT_ATTR)


## `$135F2`: the highlight of a selected row (a frame, filled when
## [param filled] - right after the selection moved).
func highlight(plane: RomPlane, row: int, filled: bool) -> void:
	var l := item(row, 0)
	var lp := plane_of(plane, row, 0)
	if row == 2:
		var v := item(row, 1)
		MwPlanePainter.frame(lp, rom, l["x"], l["y"], 7, 1, filled)
		MwPlanePainter.frame(plane_of(plane, row, 1), rom, v["x"], v["y"], 7, 1, filled)
	elif row < 2:
		if filled:
			MwPlanePainter.fill(lp, l["x"], l["y"], 10, 2, SELECTED_FILL)
	else:
		MwPlanePainter.frame(lp, rom, l["x"], l["y"], 0x22, 1, filled)


## `$1366A`: removes a row's highlight.
func unhighlight(plane: RomPlane, row: int) -> void:
	var l := item(row, 0)
	var lp := plane_of(plane, row, 0)
	if row == 2:
		var v := item(row, 1)
		MwPlanePainter.erase_frame(lp, l["x"], l["y"], 7, 1)
		MwPlanePainter.erase_frame(plane_of(plane, row, 1), v["x"], v["y"], 7, 1)
	elif row < 2:
		MwPlanePainter.fill(lp, l["x"], l["y"], 10, 2, fill_word(row))
	else:
		MwPlanePainter.erase_frame(lp, l["x"], l["y"], 0x22, 1)


## `$12DD8`: a name in a team row's two lines (the panel header): split at
## the first space when it is wider than 10 cells, each line centred.
func draw_name(plane: RomPlane, row: int, name_bytes: PackedByteArray, selected: bool) -> void:
	var l := item(row, 0)
	var v := item(row, 1)
	MwPlanePainter.fill(plane, l["x"], l["y"], 10, 2, SELECTED_FILL if selected else fill_word(row))
	var font := MwPlanePainter.FONT_SMALL if selected else MwPlanePainter.FONT_MENU
	var first := PackedByteArray()
	var i := 0
	var split := MwGfx.text_width(rom, font, name_bytes) > 10
	if split:                               # first word (up to 10 chars)
		var last := 0
		while i < name_bytes.size() and first.size() < 10:
			last = name_bytes[i]
			first.append(last)
			i += 1
			if last == 0x20:
				break
		if last == 0x20:
			first.remove_at(first.size() - 1)
		if i < name_bytes.size() and name_bytes[i] == last:
			i += 1
	var rest := name_bytes.slice(i, mini(i + 10, name_bytes.size()))
	var line1 := first if split else rest
	var line2 := rest if split else PackedByteArray()
	var w1 := MwGfx.text_width(rom, font, line1)
	if w1 == 0:
		return
	MwPlanePainter.text(plane, rom, font, line1, int(l["x"]) + (((int(l["w"]) - w1) & 0xFF) >> 1), l["y"], TEXT_ATTR)
	var w2 := MwGfx.text_width(rom, font, line2)
	if w2 == 0:
		return
	MwPlanePainter.text(plane, rom, font, line2, int(v["x"]) + (((int(v["w"]) - w2) & 0xFF) >> 1), v["y"], TEXT_ATTR)
