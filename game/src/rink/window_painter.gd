class_name MwWindowPainter
extends RefCounted
## Paints the window plane operations of a rink pass ([member
## MwRinkPhases.window_ops] - the phase handler's and the pause menu's texts,
## fills, the speech box and its quote, the clock widget - and [member
## MwRinkUpdate.window_ops] - the clock's texts at the pass start) onto the
## rink's window [RomPlane], with the ported drawing routines
## ([MwPlanePainter], [MwTextBox], [MwClockHud]). The operations are the
## original's calls in its order (checked call by call against recordings:
## `tools/bin/visit-check --draws`); what they draw stays on the window until
## something is drawn over it, as on the VDP's name table.

var plane: RomPlane
var rom: PackedByteArray
var _after := 0                      ## the x after the last text (`draw_text` returns it in d1)


func _init(plane_: RomPlane, rom_: PackedByteArray) -> void:
	plane = plane_
	rom = rom_


## Paint [param ops] in order; [param s] gives the text box's line spacing
## for a quote.
func paint(ops: Array, s: MwRinkState) -> void:
	for op in ops:
		var o: Array = op
		match String(o[0]):
			"text":
				_after = MwPlanePainter.text(plane, rom, int(o[1]), _string(o[5]), int(o[2]), int(o[3]), int(o[4]))
			"text_after":
				_after = MwPlanePainter.text(plane, rom, int(o[1]), _string(o[4]), _after, int(o[2]), int(o[3]))
			"glyph":
				_after = int(o[2]) + MwPlanePainter.glyph(plane, rom, int(o[1]), int(o[5]), int(o[2]), int(o[3]), int(o[4]))
			"glyph_after":
				# ["glyph_after", font, y, attr, char]: right after the last glyph or text
				_after += MwPlanePainter.glyph(plane, rom, int(o[1]), int(o[4]), _after, int(o[2]), int(o[3]))
			"map":
				# ["map", map, stride (words), w, h, x, y]: `map_copy` of name-table words
				MwPlanePainter.map_rect(plane, rom, int(o[1]), int(o[2]), int(o[3]), int(o[4]), int(o[5]), int(o[6]))
			"fill":
				MwPlanePainter.fill(plane, int(o[1]), int(o[2]), int(o[3]), int(o[4]), int(o[5]))
			"box":
				MwPlanePainter.frame(plane, rom, int(o[1]), int(o[2]), int(o[3]), int(o[4]), bool(o[5]))
			"quote":
				var tb := MwTextBox.new(plane, int(o[1]), Rect2i(int(o[2]), int(o[3]), int(o[6]), int(o[7])),
						s.text_box.spacing if s != null else 0)
				tb.home()
				tb.write(rom, _string(o[5]), int(o[4]))
			"widget":
				# `$25AA`: the frame and texts; in the power-play form the
				# power-play clock text follows from the pass start's ops
				MwClockHud.draw(plane, rom, int(o[2]), int(o[3]), (int(o[4]) if o.size() > 4 else 0) if bool(o[1]) else -1)
			_:
				push_warning("MwWindowPainter: unknown operation %s" % str(o[0]))


## A text operand: a ROM string's address (up to its 0) or the bytes.
func _string(v: Variant) -> PackedByteArray:
	if v is int:
		var out := PackedByteArray()
		var a: int = v
		while a < rom.size() and rom[a] != 0:
			out.append(rom[a])
			a += 1
		return out
	if v is PackedByteArray:
		var b: PackedByteArray = v
		var z := b.find(0)
		return b if z < 0 else b.slice(0, z)
	var arr := PackedByteArray()
	for x in v:
		if int(x) == 0:
			break
		arr.append(int(x))
	return arr
