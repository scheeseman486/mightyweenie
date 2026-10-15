class_name MwPrompts
extends RefCounted
## The original's Genesis button prompts drawn with the player's inputs
## (plan 23; the survey in its plan): in the STANDARD layout each button
## word of a prompt (a letter before ":" or "-" as the scoreboards and the
## password screen print them, a button named after "PRESS" as the stats
## footers do, every letter of the instant replay's widget) becomes the glyph
## of the verb that button means on that screen ([MwVerbs] context), on the
## live cells of [MwGlyphs] - the keyboard's or the gamepad's, whichever was
## used last, changing in place. The rest of the text moves by the glyph's
## width. The GENESIS layout keeps the original's letters (fidelity).

## The Genesis buttons a prompt names (START first: "START" is not "S").
const BUTTONS: Array[String] = ["START", "A", "B", "C"]
## ROM strings whose every button word is a prompt (the instant replay's
## widget: "A_B_C" over its rewind / slow / play symbols).
const ALL_STRINGS := [0x5062B]


## The contexts whose screens print Genesis button prompts (the survey).
const PROMPT_CONTEXTS := [MwVerbs.Context.SCOREBOARD, MwVerbs.Context.STATS, MwVerbs.Context.REPLAY,
		MwVerbs.Context.PASSWORD, MwVerbs.Context.PLAYOFFS, MwVerbs.Context.SPECIAL_PLAYS]


## A screen's prompt context from its contexts ([constant MwScreens.TABLE]),
## -1 for a screen without prompts.
static func context_for(contexts: Array) -> int:
	for c in contexts:
		if c in PROMPT_CONTEXTS:
			return c
	return -1


## True when the screens draw glyphs: player 1 plays the STANDARD layout
## and the glyph sheets are there.
static func active() -> bool:
	return MwSettings.layout(1) == "STANDARD" and not MwGlyphs.tiles().is_empty()


## Paints [param bytes] as [method MwPlanePainter.text] does (from cell
## [param x], baseline row [param y]), each Genesis button prompt in it as
## the glyph of the verb the button means in context [param ctx]. A prompt:
## a button word followed by ":" or "-" (or " -"), or after "PRESS"; with
## [param all] every button word; with [param after_press] a button word
## that starts the text (a word painted on its own after a "PRESS"). The
## glyphs in [param style] ([enum MwGlyphs.Style]: see-through, or TEXT on
## the font's black). Returns the x after it.
static func text(plane: RomPlane, rom: PackedByteArray, font: int, bytes: PackedByteArray, x: int, y: int,
		attr: int, ctx: int, all := false, after_press := false, style := MwGlyphs.Style.NORMAL) -> int:
	var at := x
	var start := 0
	var i := 0
	while i < bytes.size():
		var b := _button_at(bytes, i)
		if b != "" and (all or (after_press and i == 0) or _is_prompt(bytes, i, b)):
			if i > start:
				at = MwPlanePainter.text(plane, rom, font, bytes.slice(start, i), at, y, attr)
			at = _glyph(plane, rom, font, b, ctx, at, y, attr, style)
			i += b.length()
			start = i
			continue
		i += 1
	if start < bytes.size():
		at = MwPlanePainter.text(plane, rom, font, bytes.slice(start), at, y, attr)
	return at


## Draws [param bytes] where the original does (cell [param x], row [param y]):
## with its prompts as glyphs when [method active], else the original's
## text. [param centred]: the line keeps the original's centre whatever
## width the glyphs give it. Returns the x after it.
static func draw(plane: RomPlane, rom: PackedByteArray, font: int, bytes: PackedByteArray, x: int, y: int, attr: int,
		ctx: int, all := false, centred := false) -> int:
	if not active():
		return MwPlanePainter.text(plane, rom, font, bytes, x, y, attr)
	if centred:
		x += int((MwGfx.text_width(rom, font, bytes) - width(rom, font, bytes, ctx, all)) / 2)
	return text(plane, rom, font, bytes, x, y, attr, ctx, all)


## The cells [param bytes] takes with its prompts as glyphs ([method text]).
static func width(rom: PackedByteArray, font: int, bytes: PackedByteArray, ctx: int, all := false) -> int:
	var w := 0
	var start := 0
	var i := 0
	while i < bytes.size():
		var b := _button_at(bytes, i)
		if b != "" and (all or _is_prompt(bytes, i, b)):
			w += MwGfx.text_width(rom, font, bytes.slice(start, i))
			var button_verbs := MwVerbs.verbs_of(ctx, b)
			var cells := MwGlyphs.live_cells(button_verbs[0]) if not button_verbs.is_empty() else PackedInt32Array()
			w += cells.size() if not cells.is_empty() else MwGfx.text_width(rom, font, b.to_ascii_buffer())
			i += b.length()
			start = i
			continue
		i += 1
	return w + MwGfx.text_width(rom, font, bytes.slice(start))


## The cell row [param font]'s letters stand on when text is drawn at
## baseline row [param y]: their bottom cell.
static func row(rom: PackedByteArray, font: int, y: int) -> int:
	return y + MwGfx.s16(rom, font) - 1


## Paints [param bytes] with its button words left out (their cells blank) and
## returns where their glyphs go, centred on them, to be drawn as sprites
## ([method MwRinkDraw.glyph_entry]): [cells, x, y] in screen pixels. For a
## line whose letters sit over a picture (the instant replay's widget: each
## letter over its symbol), which a wider glyph must not push along.
static func overlay(plane: RomPlane, rom: PackedByteArray, font: int, bytes: PackedByteArray, x: int, y: int,
		attr: int, ctx: int) -> Array:
	var out := []
	var at := x
	var start := 0
	var i := 0
	var cy := row(rom, font, y) * 8 + 4
	while i < bytes.size():
		var b := _button_at(bytes, i)
		if b == "":
			i += 1
			continue
		if i > start:
			at = MwPlanePainter.text(plane, rom, font, bytes.slice(start, i), at, y, attr)
		var w := MwGfx.text_width(rom, font, b.to_ascii_buffer())
		var button_verbs := MwVerbs.verbs_of(ctx, b)
		var cells := MwGlyphs.live_cells(button_verbs[0]) if not button_verbs.is_empty() else PackedInt32Array()
		if cells.is_empty():
			MwPlanePainter.text(plane, rom, font, b.to_ascii_buffer(), at, y, attr)
		else:
			out.append([cells, at * 8 + 4 * w, cy])
		at += w
		i += b.length()
		start = i
	if start < bytes.size():
		MwPlanePainter.text(plane, rom, font, bytes.slice(start), at, y, attr)
	return out


## The button word at [param i] of [param bytes] ("" none): a whole word.
static func _button_at(bytes: PackedByteArray, i: int) -> String:
	if i > 0 and _letter(bytes[i - 1]):
		return ""
	for b in BUTTONS:
		var n := b.length()
		if i + n > bytes.size() or bytes.slice(i, i + n).get_string_from_ascii() != b:
			continue
		if i + n < bytes.size() and _letter(bytes[i + n]):
			continue
		return b
	return ""


## True when the button word [param b] at [param i] is a prompt: ":" or "-"
## after it (" -" too), or "PRESS " before it.
static func _is_prompt(bytes: PackedByteArray, i: int, b: String) -> bool:
	var j := i + b.length()
	if j < bytes.size():
		var c := char(bytes[j])
		if c == ":" or c == "-":
			return true
		if c == " " and j + 1 < bytes.size() and char(bytes[j + 1]) == "-":
			return true
	return i >= 6 and bytes.slice(i - 6, i).get_string_from_ascii() == "PRESS "


static func _letter(c: int) -> bool:
	return (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A) or (c >= 0x30 and c <= 0x39)


## Draws the glyph of button [param b]'s verb in context [param ctx] at
## cell [param x] on the font's letter row; the letters when the verb has
## no glyph. Returns the x after it.
static func _glyph(plane: RomPlane, rom: PackedByteArray, font: int, b: String, ctx: int, x: int, y: int, attr: int,
		style: int) -> int:
	var button_verbs := MwVerbs.verbs_of(ctx, b)
	var cells := MwGlyphs.live_cells(button_verbs[0], style) if not button_verbs.is_empty() else PackedInt32Array()
	if cells.is_empty():
		return MwPlanePainter.text(plane, rom, font, b.to_ascii_buffer(), x, y, attr)
	return MwGlyphs.put_cells(plane, cells, x, row(rom, font, y), (attr & 0x80) != 0)


## Plan 40 (M6): prompts [[verb, label], ...] ([verb, label, verb]: both
## verbs' glyphs before the one label) - each verb's glyph
## (MwGlyphs.verb_cells), then its label - centred on [param cx] on row
## [param y] in the light menu font; a verb without a glyph shows its label
## alone (CREATE-A-TEAM, the text entry, the rink editor; moved from
## MwEditorDraw).
static func verbs(plane: RomPlane, rom: PackedByteArray, parts: Array, y: int, attr: int, cx := 20) -> void:
	var font := MwPlanePainter.FONT_MENU
	var total := 0
	var cells := []
	for part: Array in parts:
		var c := MwGlyphs.verb_cells(str(part[0]))
		if part.size() > 2:
			var second := MwGlyphs.verb_cells(str(part[2]))     # [verb, label, verb]: two glyphs, one label
			if not c.is_empty() and not second.is_empty():
				c.append(0)                                  # (a blank cell between them)
			c.append_array(second)
		cells.append(c)
		total += c.size() + MwGlyphs.text_width(rom, font, (" " + str(part[1])).to_ascii_buffer()) + 2
	total -= 2
	@warning_ignore("integer_division")
	var x := cx - total / 2
	var cell_row := row(rom, font, y)
	for i in parts.size():
		x = MwGlyphs.put_cells(plane, cells[i], x, cell_row)
		x = MwGlyphs.text(plane, rom, font, (" " + str(parts[i][1])).to_ascii_buffer(), x, y, attr) + 2
