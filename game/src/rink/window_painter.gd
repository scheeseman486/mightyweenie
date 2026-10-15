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
##
## With [member MwSettings.team_name_colours] (owner, 2026-10-09) a team's
## name in the big font draws on its own team's line (the original puts the
## score panel's both names on team A's), and the big-font glyphs after it
## on its row - the panel's score - in greys (MwGlyphs "grey"). The
## operations stay the original's.

var plane: RomPlane
var rom: PackedByteArray
## The input context of the screen's Genesis button prompts (plan 23,
## MwPrompts): with one (and the STANDARD layout) the light font's texts show
## their prompts as the player's glyphs; -1 none.
var prompt_ctx := -1
## The prompts' glyph style ([enum MwGlyphs.Style]): see-through, or on the
## font's black where the backdrop is drawn on under the window (the
## scoreboards).
var prompt_style := MwGlyphs.Style.NORMAL
var _after := 0                      ## the x after the last text (`draw_text` returns it in d1)
## Glyphs to draw as sprites over the plane (MwPrompts.overlay: the
## instant replay's widget letters): [cells, x, y] in screen pixels, from
## the last such text painted.
var overlays: Array = []
var _shift := {}                     ## row -> cells the prompts drawn on it this paint added
var _press_row := -1                 ## the row whose last text was "PRESS" (-1 none)
var _names := {}                     ## team name address -> its team's line attr (team_name_colours)
var _name_rows := {}                 ## rows with a team's name painted this paint


func _init(plane_: RomPlane, rom_: PackedByteArray) -> void:
	plane = plane_
	rom = rom_


## Paint [param ops] in order; [param s] gives the text box's line spacing
## for a quote.
func paint(ops: Array, s: MwRinkState) -> void:
	_shift = {}
	_press_row = -1
	_names = {}
	_name_rows = {}
	if MwSettings.team_name_colours and s != null:
		for team in s.teams:
			_names[MwGfx.u32(rom, team.record + MwTeams.NAME)] = team.attr & 0x60
	for op in ops:
		var o: Array = op
		match String(o[0]):
			"text":
				if prompt_ctx >= 0 and int(o[1]) == MwPlanePainter.FONT_MENU and MwPrompts.active():
					if o[5] is int and o[5] in MwPrompts.ALL_STRINGS:
						overlays = MwPrompts.overlay(plane, rom, MwPlanePainter.FONT_MENU, _string(o[5]),
								int(o[2]), int(o[3]), int(o[4]), prompt_ctx)
					else:
						_after = _prompt_text(_string(o[5]), int(o[2]), int(o[3]), int(o[4]), false)
				elif int(o[1]) == MwRinkPhases.BIG_FONT and o[5] is int and _names.has(o[5]):
					_name_rows[int(o[3])] = true
					var attr := (int(o[4]) & ~0x60) | int(_names[o[5]])
					_after = MwPlanePainter.text(plane, rom, int(o[1]), _string(o[5]), int(o[2]), int(o[3]), attr)
				else:
					_after = MwPlanePainter.text(plane, rom, int(o[1]), _string(o[5]), int(o[2]), int(o[3]), int(o[4]))
			"text_after":
				_after = MwPlanePainter.text(plane, rom, int(o[1]), _string(o[4]), _after, int(o[2]), int(o[3]))
			"glyph":
				if int(o[1]) == MwRinkPhases.BIG_FONT and _name_rows.has(int(o[3])):
					_after = int(o[2]) + MwGlyphs.rom_glyph(plane, rom, int(o[1]), int(o[5]), int(o[2]), int(o[3]),
							int(o[4]), "grey")
				else:
					_after = int(o[2]) + MwPlanePainter.glyph(plane, rom, int(o[1]), int(o[5]), int(o[2]), int(o[3]),
							int(o[4]))
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
				MwClockHud.draw(plane, rom, int(o[2]), int(o[3]),
						(int(o[4]) if o.size() > 4 else 0) if bool(o[1]) else -1)
			_:
				push_warning("MwWindowPainter: unknown operation %s" % str(o[0]))


## A light-font text with its prompts as glyphs (MwPrompts.text): moved by
## what earlier prompts on its row added, a word after "PRESS" on the row a
## prompt (the stats' footers draw word by word). Returns the x after it.
func _prompt_text(text: PackedByteArray, x: int, y: int, attr: int, all := false) -> int:
	var at := x + int(_shift.get(y, 0))
	var after_press := _press_row == y
	_press_row = y if text.get_string_from_ascii().trim_prefix("_") == "PRESS" else -1   # 9's footer: "_PRESS"
	var end := MwPrompts.text(plane, rom, MwPlanePainter.FONT_MENU, text, at, y, attr, prompt_ctx, all, after_press,
			prompt_style)
	var extra := end - at - MwGfx.text_width(rom, MwPlanePainter.FONT_MENU, text)
	if extra != 0:
		_shift[y] = int(_shift.get(y, 0)) + extra
	return end


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
	var row_bytes := PackedByteArray()
	for x in v:
		if int(x) == 0:
			break
		row_bytes.append(int(x))
	return row_bytes
