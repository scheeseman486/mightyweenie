class_name MwGlyphs
extends RefCounted
## The input glyphs (plan 23): the key caps and gamepad buttons the port
## draws where the original prints a Genesis button prompt, and in the
## bindings menu. Port art, not ROM data (`res://assets/glyphs/CREDITS.md`):
## the keyboard from "Virtual key codes tileset" (YellowAfterlife, CC0; it
## wins where both sheets have a glyph - owner), the gamepad from "Pixel
## Button Prompt" (FrankTheApe), and the shoulder, stick and Back glyphs
## neither has, composed here in the second sheet's style.
##
## Every glyph is a row of 8 x 8 cells (the menus' grid). No sheet colour is
## shown (owner: the game's own palette mapped onto them): each sheet colour
## is a role (label, body, edge) and the roles become indices of palette line
## [constant LINE] - the light menu font's line, whose black (5), white (9)
## and grey (10) and the dark grey beside them (11) are the same on every
## screen with a prompt. The cells are tiles like the ROM's: [RomTileSet]
## adds [method tiles] under keys from [constant KEY_BASE], and a
## [RomPlane] draws them on the screen's palette, fades included.

const KEYS_SHEET := "res://assets/glyphs/virtual_key_codes/vk.png"
const PAD_SHEET := "res://assets/glyphs/pixel_button_prompt/PixelButtonPrompt.png"
## Tile keys of the glyph cells: above every VRAM tile and ROM tile number.
const KEY_BASE := 0x100000
## The palette line the glyphs are drawn on (the light font's).
const LINE := 3
const BLACK := 5
const WHITE := 9
const GREY := 10
const DARK := 11

## Where a glyph goes: NORMAL see-through - its own dark edge gives the
## contrast (owner); SELECTED on a selection bar (the port menus' white
## highlight); TEXT on the light font's black, for the scoreboards' window,
## whose letters' opaque cells hide the backdrop drawn on under it (owner:
## only there).
enum Style { NORMAL, SELECTED, TEXT }
## Role -> palette index, per style. Keys: a black keycap (owner); gamepad
## buttons: dark grey, or grey with a black label on a selection bar. "bg":
## the pixels around the glyph - see-through; on a selection bar its white
## (owner: the highlight goes on under the glyphs, as under the dark font,
## whose cells are white); in a text line the light font's black.
const KEY_ROLES := [{"label": WHITE, "body": BLACK, "edge": GREY},
		{"label": WHITE, "body": BLACK, "edge": GREY, "bg": WHITE},
		{"label": WHITE, "body": BLACK, "edge": GREY, "bg": BLACK}]
const PAD_ROLES := [{"label": WHITE, "body": DARK, "edge": BLACK},
		{"label": BLACK, "body": GREY, "edge": BLACK, "bg": WHITE},
		{"label": WHITE, "body": DARK, "edge": BLACK, "bg": BLACK}]

## The key sheet: 16 x 16 tiles of 23 x 8 at offset 1, spacing 1, by Windows
## virtual key code. Its first codes sit early in the author's sheet (a
## comment on its page): code -> the tile that has it.
const VK_TILE := 23
const VK_EARLY := {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 8: 6, 9: 7}
## Godot keys -> virtual key codes (letters and digits are their ASCII codes).
const VK := {
	KEY_BACKSPACE: 0x08, KEY_TAB: 0x09, KEY_ENTER: 0x0D, KEY_KP_ENTER: 0x0D, KEY_SHIFT: 0x10,
	KEY_CTRL: 0x11, KEY_ALT: 0x12, KEY_PAUSE: 0x13, KEY_CAPSLOCK: 0x14, KEY_ESCAPE: 0x1B,
	KEY_SPACE: 0x20, KEY_PAGEUP: 0x21, KEY_PAGEDOWN: 0x22, KEY_END: 0x23, KEY_HOME: 0x24,
	KEY_LEFT: 0x25, KEY_UP: 0x26, KEY_RIGHT: 0x27, KEY_DOWN: 0x28, KEY_PRINT: 0x2C,
	KEY_INSERT: 0x2D, KEY_DELETE: 0x2E, KEY_META: 0x5B, KEY_MENU: 0x5D,
	KEY_KP_0: 0x60, KEY_KP_1: 0x61, KEY_KP_2: 0x62, KEY_KP_3: 0x63, KEY_KP_4: 0x64,
	KEY_KP_5: 0x65, KEY_KP_6: 0x66, KEY_KP_7: 0x67, KEY_KP_8: 0x68, KEY_KP_9: 0x69,
	KEY_KP_MULTIPLY: 0x6A, KEY_KP_ADD: 0x6B, KEY_KP_SUBTRACT: 0x6D, KEY_KP_PERIOD: 0x6E,
	KEY_KP_DIVIDE: 0x6F, KEY_NUMLOCK: 0x90, KEY_SCROLLLOCK: 0x91,
	KEY_SEMICOLON: 0xBA, KEY_EQUAL: 0xBB, KEY_COMMA: 0xBC, KEY_MINUS: 0xBD, KEY_PERIOD: 0xBE,
	KEY_SLASH: 0xBF, KEY_QUOTELEFT: 0xC0, KEY_BRACKETLEFT: 0xDB, KEY_BACKSLASH: 0xDC,
	KEY_BRACKETRIGHT: 0xDD, KEY_APOSTROPHE: 0xDE,
}

## The gamepad sheet's glyphs: name -> [column, row, tiles] (8 x 8 tiles).
const PAD := {
	"A": [4, 7, 1], "B": [5, 7, 1], "X": [6, 7, 1], "Y": [7, 7, 1],
	"TRIANGLE": [8, 7, 1], "CIRCLE": [9, 7, 1], "CROSS": [10, 7, 1], "SQUARE": [11, 7, 1],
	"START": [4, 6, 3], "L1": [13, 7, 1], "L2": [14, 7, 1], "R1": [13, 6, 1], "R2": [14, 6, 1],
	"DPAD_LEFT": [8, 4, 1], "DPAD_UP": [9, 4, 1], "DPAD_RIGHT": [10, 4, 1], "DPAD_DOWN": [11, 4, 1],
	"STICK": [7, 6, 1], "STICK_UP": [8, 6, 1], "STICK_RIGHT": [9, 6, 1], "STICK_DOWN": [10, 6, 1],
	"STICK_LEFT": [11, 6, 1],
}
## Glyphs composed in that sheet's style (port art): two-letter chips on
## the shape of its L1 chip, and a Back pill on the shape of its START.
const CHIPS := ["LB", "RB", "LT", "RT", "LS", "RS", "L3", "R3", "ZL", "ZR", "L", "R", "+", "-"]
const PILLS := ["BACK"]
## 3 x 5 letters for them, in the sheet's square style (rows top down).
const MINI := {
	"A": ["###", "#.#", "###", "#.#", "#.#"], "B": ["###", "#.#", "##.", "#.#", "###"],
	"C": ["###", "#..", "#..", "#..", "###"], "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
	"L": ["#..", "#..", "#..", "#..", "###"], "R": ["###", "#.#", "###", "##.", "#.#"],
	"S": ["###", "#..", "###", "..#", "###"], "T": ["###", ".#.", ".#.", ".#.", ".#."],
	"Z": ["###", "..#", ".#.", "#..", "###"], "3": ["###", "..#", ".##", "..#", "###"],
	"+": ["...", ".#.", "###", ".#.", "..."], "-": ["...", "...", "###", "...", "..."],
}

## Live cells (prompts): per verb and style, [constant LIVE_CELLS] tile keys
## from here whose drawing is the verb's glyph on the device used last,
## redrawn in place when the device changes ([method refresh_live]), so a
## screen's prompts follow the player's hands without being repainted.
const LIVE_BASE := KEY_BASE + 0x10000
const LIVE_CELLS := 4
## Past the live cells' keys (the port's single cells sit at the top of the
## range, [constant SOLID_BLACK] and [constant PLUS_KEYS]).
const LIVE_END := LIVE_BASE + 0xF000

## ROM tiles recoloured at load (plan 23, owner): the pause menu's title in
## greys whatever the team (in the team's colours it read as one more item),
## its player's line framed by the menus' selection frame in black, and
## (owner, 2026-10-09) its items in the pausing team's two colours - the
## selected one in its primary (the big font's own face and shade: a team
## line's colours 2-3, record +$80), the others in its secondary (colours
## 5-6, record +$84; MwPalettes `_team_colours`); the score panel's scores
## always in the title's greys (owner, 2026-10-09; MwWindowPainter). Index
## maps, and the glyphs each applies to (font, characters).
const REMAPS := {
	"grey": {2: 13, 3: 14},          # the big font's face and shade -> the team lines' grey and dark grey
	"black": {9: 5},                 # the selection frame's white -> line 3's black
	"secondary": {2: 5, 3: 6},       # the big font's face and shade -> the team's second colour pair
}
const REMAP_GLYPHS := [
	# every letter (owner, 2026-10-12: SAVE REPLAY?'s V and L were in the
	# team's colours - the list had only PAUSE / ARE YOU SURE?'s; CONNECT?
	# missed C, N, T): a title in greys can say anything
	[0x246FA, "ABCDEFGHIJKLMNOPQRSTUVWXYZ?!0123456789", "grey"],
	[0x1F958, [0x40, 0x7B, 0x7C, 0x7D, 0x7E], "black"],
	[0x246FA, "ABCDEFGHIJKLMNOPQRSTUVWXYZ?!", "secondary"],
]
const REMAP_BASE := KEY_BASE + 0x20000
## A cell of line 3's black (the black frame's fill).
const SOLID_BLACK := KEY_BASE + 0x1FFFF
## The plate's grey ([method black_label]): line 3's black is $222 in the
## rink's window palette (ROM palette `$1BD8A`, colour 5), where the pause
## menu draws its plate, but $000 on the port menus; [method plate_palette]
## puts that word back for a plate's layer.
const PLATE_GREY := "word 1BD94 53"
## The menu fonts have no "+" (the bindings menu's separator, owner, and its
## page names): the port's own, one cell per font, in the colours of the
## font's "-" (ink and background) - a cross of 2-pixel strokes centred
## where the "-" is.
const PLUS_KEYS := {MwPlanePainter.FONT_MENU: KEY_BASE + 0x1FFFE, MwPlanePainter.FONT_SMALL: KEY_BASE + 0x1FFFD}
const PLUS := [
	"..##....",
	"..##....",
	"######..",
	"######..",
	"..##....",
	"..##....",
	"........",
	"........",
]
## Plan 35's text fields (the online pages, [method field_text]) need more
## than the menu fonts give: "*" (a password is shown as asterisks; the
## fonts have none) and "[" "]" (an IPv6 address with its port; the dark
## font has none, the light font's are other signs), drawn the same way
## (the "-"'s ink and background), and the field's cursor (the fonts' "_"
## is blank): an underline on a see-through cell, for a layer over the text.
## Tile keys from [constant FIELD_BASE], a block of 128 per font.
const FIELD_CHARS := {
	0x2A: [
		"........",
		".#.#.#..",
		"..###...",
		".#####..",
		"..###...",
		".#.#.#..",
		"........",
		"........",
	],
	0x5B: [
		".####...",
		".##.....",
		".##.....",
		".##.....",
		".##.....",
		".##.....",
		".####...",
		"........",
	],
	0x5D: [
		".####...",
		"...##...",
		"...##...",
		"...##...",
		"...##...",
		"...##...",
		".####...",
		"........",
	],
}
const CURSOR := [
	"........",
	"........",
	"........",
	"........",
	"........",
	"........",
	"........",
	"#######.",
]
## The cursor's slot in a font's block (no character uses it).
const CURSOR_SLOT := 0
const FIELD_BASE := KEY_BASE + 0x1F800
const FIELD_FONTS := [MwPlanePainter.FONT_MENU, MwPlanePainter.FONT_SMALL]

## The input the screens show glyphs for: -1 the keyboard, else the gamepad
## that was used last ([method note_input]).
static var last_device := -1
## Whether the player has pressed anything yet ([method note_input]).
static var _chosen := false
static var _remapped := {}           # "font|char|remap" -> {w, h, keys (column-major)}
## Counts the live cells' redraws (sprite layers cache their textures until it moves).
static var generation := 0

static var _tiles := {}              # key -> 64 indices
static var _cells := {}              # "id|style" -> PackedInt32Array of keys
static var _roles_of := {}           # id -> roles ({w, px}), for the live cells
static var _live_w := {}             # verb -> the live cells' width when last drawn
## The live cells cut once per glyph, width and style ("id|w|style" ->
## tiles; owner, 2026-10-12: a stutter whenever another device was used -
## every live cell cut again, every switch).
static var _cut_cache := {}
static var _built := false
static var _fixed_hash := ""
static var _live_hash := ""
static var _live_hash_gen := -1


## Every glyph tile: key -> 64 palette indices (empty without the sheets).
static func tiles() -> Dictionary:
	_build()
	return _tiles


## The cells of glyph [param id] ("vk:<code>", "pad:<name>") in [param
## style]: tile keys left to right; empty when there is no such glyph.
static func cells(id: String, style := Style.NORMAL) -> PackedInt32Array:
	_build()
	return _cells.get("%s|%d" % [id, style], PackedInt32Array())


## The glyph of input [param event] (a key, a gamepad button or axis
## direction), "" for none (the caller shows its name instead). A stick
## direction is two glyphs: [method stick_glyphs].
static func glyph_of(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var vk := _vk(code)
		return "vk:%d" % vk if vk > 0 and not cells("vk:%d" % vk).is_empty() else ""
	if event is InputEventJoypadButton:
		var name := button_name(event.button_index, family(event.device))
		return "pad:" + name if name != "" else ""
	if event is InputEventJoypadMotion:
		var f := family(event.device)
		match event.axis:
			JOY_AXIS_TRIGGER_LEFT:
				return "pad:" + {"PS": "L2", "NS": "ZL"}.get(f, "LT")
			JOY_AXIS_TRIGGER_RIGHT:
				return "pad:" + {"PS": "R2", "NS": "ZR"}.get(f, "RT")
		var g := stick_glyphs(event)
		return g[1] if g.size() == 2 else ""
	return ""


## A stick direction's two glyphs: the stick (LS / RS), then the direction.
static func stick_glyphs(event: InputEvent) -> PackedStringArray:
	var out := PackedStringArray()
	if not event is InputEventJoypadMotion or event.axis > JOY_AXIS_RIGHT_Y:
		return out
	out.append("pad:" + ("LS" if event.axis <= JOY_AXIS_LEFT_Y else "RS"))
	var y: bool = event.axis == JOY_AXIS_LEFT_Y or event.axis == JOY_AXIS_RIGHT_Y
	var neg: bool = event.axis_value < 0
	out.append("pad:STICK_" + (("UP" if neg else "DOWN") if y else ("LEFT" if neg else "RIGHT")))
	return out


## Gamepad button [param index]'s glyph name for gamepad family [param f]
## (Godot's buttons are by place: index 0 is the bottom face button, which
## a PlayStation pad marks with a cross and a Nintendo pad with B).
static func button_name(index: int, f: String) -> String:
	var faces := {"PS": ["CROSS", "CIRCLE", "SQUARE", "TRIANGLE"], "NS": ["B", "A", "Y", "X"]}
	match index:
		JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y:
			return faces.get(f, ["A", "B", "X", "Y"])[index]
		JOY_BUTTON_BACK:
			return "-" if f == "NS" else "BACK"
		JOY_BUTTON_START:
			return "+" if f == "NS" else "START"
		JOY_BUTTON_LEFT_STICK:
			return "L3" if f == "PS" else "LS"
		JOY_BUTTON_RIGHT_STICK:
			return "R3" if f == "PS" else "RS"
		JOY_BUTTON_LEFT_SHOULDER:
			return {"PS": "L1", "NS": "L"}.get(f, "LB")
		JOY_BUTTON_RIGHT_SHOULDER:
			return {"PS": "R1", "NS": "R"}.get(f, "RB")
		JOY_BUTTON_DPAD_UP:
			return "DPAD_UP"
		JOY_BUTTON_DPAD_DOWN:
			return "DPAD_DOWN"
		JOY_BUTTON_DPAD_LEFT:
			return "DPAD_LEFT"
		JOY_BUTTON_DPAD_RIGHT:
			return "DPAD_RIGHT"
	return ""


## The family of gamepad [param device] from the name SDL gives it: "XB"
## (Xbox), "PS" (PlayStation), "NS" (Nintendo), "PAD" (anything else, and
## a gamepad not connected).
static func family(device: int) -> String:
	if device < 0 or not device in Input.get_connected_joypads():
		return "PAD"
	return family_of_name(Input.get_joy_name(device))


## The family of a gamepad SDL calls [param name], by the words in it: "XB", "PS", "NS"
## or "PAD" (anything else; [method family]).
static func family_of_name(name: String) -> String:
	var n := name.to_lower()
	for w in ["xbox", "xinput", "x-box", "microsoft"]:
		if w in n:
			return "XB"
	for w in ["playstation", "dualshock", "dualsense", "sony", "ps3", "ps4", "ps5"]:
		if w in n:
			return "PS"
	for w in ["nintendo", "switch", "joy-con", "joycon", "pro controller"]:
		if w in n:
			return "NS"
	return "PAD"


## The bindings menu's tag of gamepad [param device] (owner: a short form of
## the device, 4 or so characters): its family and number - "XB1", "PS2",
## "NS1", "PAD3". None for the keyboard (one of it).
static func tag(device: int) -> String:
	return "%s%d" % [family(device), device + 1] if device >= 0 else ""


## Notes the device of input [param event] (a key, a gamepad button, or a
## stick or trigger pushed past the dead zone); true when the screens'
## glyphs should change to it.
static func note_input(event: InputEvent) -> bool:
	var d := last_device
	if event is InputEventKey and event.pressed:
		d = -1
		_chosen = true
	elif event is InputEventJoypadButton and event.pressed:
		d = event.device
		_chosen = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= MwInputMap.DEADZONE:
		d = event.device
		_chosen = true
	if d == last_device:
		return false
	last_device = d
	refresh_live()
	return true


## A gamepad connected or unplugged ([signal Input.joy_connection_changed]):
## until the player presses anything the glyphs follow the first gamepad
## connected - Godot finds the pads a moment after the start, and the
## glyphs are drawn before that (plan 27: at the start, in the background)
## - and an unplugged gamepad's glyphs go to another one, or the keyboard.
static func joy_changed(device: int, connected: bool) -> void:
	var d := last_device
	if connected and d < 0 and not _chosen:
		d = device
	elif not connected and device == d:
		var pads := Input.get_connected_joypads()
		pads.erase(device)
		d = pads[0] if not pads.is_empty() else -1
	if d == last_device:
		return
	last_device = d
	refresh_live()


## The glyph [param player]'s verb [param verb] shows on [param device]
## (-1 the keyboard, else a gamepad; default: the one used last): its first
## input there (a gamepad: that gamepad's, or any gamepad's), else its first
## input at all; "" for none.
static func verb_glyph(player: int, verb: String, device := -2) -> String:
	if device == -2:
		device = last_device
	var events := MwInputMap.verb_events(player, verb)
	var pads := events.filter(func(e: InputEvent) -> bool: return not e is InputEventKey)
	var keys := events.filter(func(e: InputEvent) -> bool: return e is InputEventKey)
	var order: Array = []
	if device >= 0:
		order.append_array(pads.filter(func(e: InputEvent) -> bool: return e.device == device))
		order.append_array(pads)
		order.append_array(keys)
	else:
		order.append_array(keys)
		order.append_array(pads)
	for e in order:
		if e is InputEventJoypadMotion and e.axis <= JOY_AXIS_RIGHT_Y:
			continue                     # a stick direction: two glyphs, not a button's place
		if device >= 0 and e is InputEventKey and not pads.is_empty():
			break                        # on a gamepad, its stick before the keyboard's key (below)
		var g := glyph_of(e)
		if g != "":
			return g
	# a verb a gamepad has only on a stick direction (the rink editor's view,
	# the text entry's scroll): that stick's glyph while the gamepad's in use
	if device >= 0:
		for e in pads:
			if e is InputEventJoypadMotion and e.axis <= JOY_AXIS_RIGHT_Y:
				var st := stick_glyphs(e)
				if st.size() == 2 and not cells(st[0]).is_empty():
					return st[0]
		for e in keys:
			var g := glyph_of(e)
			if g != "":
				return g
	return ""


## The glyph of [param player]'s verb [param verb] on the device they play
## on ([method verb_glyph]): their gamepad while it is connected - the
## keyboard instead when they have it and it was used last, or their
## gamepad isn't there. For a hint beside one player's choice (the line-up
## panels' DONE), where the screens' prompts follow whoever pressed last.
static func player_glyph(player: int, verb: String) -> String:
	var pad := MwInputMap.pad_device(player)
	var device := pad
	if MwInputMap.uses_keyboard(player) and (last_device < 0 or not pad in Input.get_connected_joypads()):
		device = -1
	return verb_glyph(player, verb, device)


## The glyph [param verb] has by default in layout [param layout]
## (MwInputMap.LAYOUTS) on a gamepad of family [param f] ("XB", "PS", "NS",
## "PAD"), or with [param f] "" on the keyboard (player 1's keys): for a
## player whose bindings are another machine's (plan 35: the lobby knows
## only their device's kind). "" for none.
static func layout_glyph(verb: String, layout: String, f: String) -> String:
	for event in MwInputMap.default_events(1, verb, layout):
		if f == "" and event is InputEventKey:
			return glyph_of(event)
		if f != "" and event is InputEventJoypadButton:
			var n := button_name(event.button_index, f)
			return "pad:" + n if n != "" else ""
	return ""


## The live cells of [param verb] (player 1's, the screens' prompts) in
## [param style]: as many as its widest glyph needs, keyboard or gamepad;
## empty when the verb has no glyph on either.
static func live_cells(verb: String, style := Style.NORMAL) -> PackedInt32Array:
	_build()
	var out := PackedInt32Array()
	var i := _verb_at(verb)
	var w := _live_width(verb)
	if i < 0 or w == 0:
		return out
	if _live_w.get(verb, 0) != w:
		_live_w[verb] = w
		var t := _live_tiles(verb)
		_tiles.merge(t, true)
		_live_drawn.erase(verb)                   # ([method refresh_live] looks at it again)
		generation += 1
		RomTileSet.update_tiles(t)
	for c in w:
		out.append(_live_key(i, style, c))
	return out


## Redraws every live cell for the device used last and the current
## bindings (after [method note_input] or a change of bindings).
##
## Only the cells whose pixels change are drawn again into the tile sets
## (owner, 2026-10-12: the controller menu stuttered going from one input
## to another - every press on another device redrew all ~900 live cells
## into every atlas: ~60 ms on the VM, a hitch of a few frames).
static func refresh_live() -> void:
	if not _built:
		return
	var changed := {}
	var ids := _live_ids()
	for v in MwVerbs.all_verbs():
		var id: Variant = ids.get(v)
		var drawn := "%s|%d" % [id, int(_live_w.get(v, 0))]
		if _live_drawn.get(v, "") == drawn:
			continue                         # its glyph as drawn already
		_live_drawn[v] = drawn
		var t := _live_tiles(v, id)
		for k in t:
			if _tiles.get(k) != t[k]:
				changed[k] = t[k]
	if changed.is_empty():
		return
	_tiles.merge(changed, true)          # sprites read them from here (MwSpriteLayer)
	generation += 1
	RomTileSet.update_tiles(changed)


## Whether tile [param key] is a live cell ([method refresh_live] redraws it).
static func is_live(key: int) -> bool:
	return key >= LIVE_BASE and key < LIVE_END


## A hash of the live cells as drawn now (a tile set's atlas compares it
## with the cells it holds: RomTileSet, plan 27).
static func live_hash() -> String:
	_build()
	if _live_hash_gen != generation:
		_live_hash = live_hash_of(_tiles)
		_live_hash_gen = generation
	return _live_hash


## A hash of the live cells in [param tiles_] (a copy of [method tiles]).
## Safe on a worker.
static func live_hash_of(tiles_: Dictionary) -> String:
	return _hash(tiles_, true)


## A hash of every tile but the live cells, and of which live cells there
## are: other glyph art or another set of verbs draws the cached atlases
## again (RomTileSet, plan 27).
static func fixed_hash() -> String:
	_build()
	if _fixed_hash == "":
		_fixed_hash = _hash(_tiles, false)
	return _fixed_hash


static func _hash(tiles_: Dictionary, live: bool) -> String:
	var keys := tiles_.keys()
	keys.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	for k: int in keys:
		if is_live(k) != live:
			if not live:
				ctx.update(PackedInt32Array([k]).to_byte_array())   # the live cells' keys
			continue
		ctx.update(PackedInt32Array([k]).to_byte_array())
		var t: PackedByteArray = tiles_[k]
		if not t.is_empty():
			ctx.update(t)
	return ctx.finish().hex_encode()


static func _live_key(verb_index: int, style: int, cell: int) -> int:
	return LIVE_BASE + (verb_index * Style.size() + style) * LIVE_CELLS + cell


## Cells the widest of [param verb]'s glyphs needs (keyboard and gamepad).
static func _live_width(verb: String) -> int:
	var w := 0
	for d in [-1, maxi(last_device, 0)]:
		var id := verb_glyph(1, verb, d)
		if _roles_of.has(id):
			w = maxi(w, int(ceil(_roles_of[id]["w"] / 8.0)))
	return mini(w, LIVE_CELLS)


## Every verb's glyph for the device used last (player 1's: [method
## verb_glyph]), worked out once per device and state of the bindings - a
## device switch looks them up (owner, 2026-10-12: the stutter switching
## devices; ~70 verbs' inputs were built again at every switch).
static func _live_ids() -> Dictionary:
	var k := "%d|%d|%d|%d|%s|%d" % [last_device, MwSettings.bindings.hash(), MwSettings.sticks.hash(),
			MwSettings.layouts.hash(), MwSettings.shot_heights, MwInputMap.devices_changed]
	if not _ids_by.has(k):
		if _ids_by.size() > 16:
			_ids_by.clear()                  # (bindings changed: the old states go)
		var ids := {}
		for v in MwVerbs.all_verbs():
			ids[v] = verb_glyph(1, v)
		_ids_by[k] = ids
	return _ids_by[k]


static var _ids_by := {}                 # state of the device and bindings -> verb -> glyph id
static var _verb_index := {}             # verb -> its place in MwVerbs.all_verbs() (the live cells' keys)


## [param verb]'s place in MwVerbs.all_verbs() (-1: none), looked up once.
static func _verb_at(verb: String) -> int:
	if _verb_index.is_empty():
		var all := MwVerbs.all_verbs()
		for i in all.size():
			_verb_index[all[i]] = i
	return int(_verb_index.get(verb, -1))
static var _live_drawn := {}                  # verb -> "glyph id|width" its live cells hold now


## The live cells of [param verb], every style, drawn now: key -> indices
## ([param id]: its glyph when known, [method _live_ids]).
static func _live_tiles(verb: String, id: Variant = null) -> Dictionary:
	var out := {}
	var i := _verb_at(verb)
	if i < 0:
		return out
	if id == null:
		id = verb_glyph(1, verb)
	var w: int = _live_w[verb] if _live_w.has(verb) else _live_width(verb)
	var tk := "%d|%s|%d" % [i, id, w]
	if _tiles_cache.has(tk):
		return _tiles_cache[tk]
	for style in Style.values():
		var ck := "%s|%d|%d" % [id, w, style]
		if not _cut_cache.has(ck):
			_cut_cache[ck] = _cut(_roles_of.get(id, {}), maxi(w, 1),
					KEY_ROLES[style] if id.begins_with("vk:") else PAD_ROLES[style])
		var t: Array[PackedByteArray] = _cut_cache[ck]
		for c in LIVE_CELLS:
			out[_live_key(i, style, c)] = t[c] if c < t.size() else PackedByteArray()
	for k in out:
		if (out[k] as PackedByteArray).is_empty():
			var blank := PackedByteArray()
			blank.resize(64)
			out[k] = blank
	_tiles_cache[tk] = out               # (read only: callers merge it, never change it)
	return out


static var _tiles_cache := {}            # "verb's place|glyph id|width" -> its live cells


static func _vk(code: int) -> int:
	if (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9):
		return code
	if code >= KEY_F1 and code <= KEY_F24:
		return 0x70 + code - KEY_F1
	return VK.get(code, 0)


# --- building ------------------------------------------------------------------------------------

## Roles per pixel: 0 none, 1 body, 2 label, 3 edge.
const NONE := 0
const BODY := 1
const LABEL := 2
const EDGE := 3


## What the glyphs are cut from: editing one cuts them again (plan 27's cache).
const SOURCES := ["res://src/ui/glyphs.gd", "res://src/rom/gfx.gd", KEYS_SHEET, PAD_SHEET]


## Cuts every glyph from the sheets (or reads the cut back from the disk
## cache, MwCache - plan 27), then draws the live cells.
static func _build() -> void:
	if _built:
		return
	_built = true
	if not _restore(MwCache.read("glyphs", SOURCES)):
		if not _cut_sheets():
			return
		MwCache.write("glyphs", SOURCES, {"tiles": _tiles, "cells": _cells, "roles": _roles_of, "remapped": _remapped})
	if last_device < 0 and not _chosen and not Input.get_connected_joypads().is_empty():
		last_device = Input.get_connected_joypads()[0]      # (a key pressed already: the keyboard stays)
	var joy := Callable(MwGlyphs, "joy_changed")
	if not Input.joy_connection_changed.is_connected(joy):
		Input.joy_connection_changed.connect(joy)
	var verbs := MwVerbs.all_verbs()
	for i in verbs.size():
		_live_w[verbs[i]] = _live_width(verbs[i])
		_tiles.merge(_live_tiles(verbs[i]))


## Takes a cut kept by [method _build]; false if [param kept] isn't one.
static func _restore(kept: Variant) -> bool:
	if not (kept is Dictionary and kept.get("tiles") is Dictionary and kept.get("cells") is Dictionary
			and kept.get("roles") is Dictionary and kept.get("remapped") is Dictionary):
		return false
	if (kept["tiles"] as Dictionary).is_empty():
		return false
	_tiles = kept["tiles"]
	_cells = kept["cells"]
	_roles_of = kept["roles"]
	_remapped = kept["remapped"]
	return true


## Cuts the glyphs from the sheets and the recoloured ROM glyphs; false
## without the sheets.
static func _cut_sheets() -> bool:
	var keys := _image(KEYS_SHEET)
	var pad := _image(PAD_SHEET)
	if keys == null or pad == null:
		return false
	for code in 256:
		var r := _vk_roles(keys, code)
		if not r.is_empty():
			_add("vk:%d" % code, r, KEY_ROLES)
	for name in PAD:
		var cell: Array = PAD[name]
		_add("pad:" + name, _pad_roles(pad, cell[0], cell[1], cell[2]), PAD_ROLES)
	var chip := _pad_roles(pad, 13, 7, 1)           # L1: the chip's shape
	var pill := _pad_roles(pad, 4, 6, 3)            # START: the pill's shape
	for name in CHIPS:
		_add("pad:" + name, _chip(chip, name), PAD_ROLES)
	for name in PILLS:
		_add("pad:" + name, _pill(pill, name), PAD_ROLES)
	_build_remaps()
	return true


static func _build_remaps() -> void:
	if not MwRom.available():
		return
	var rom := MwRom.data()
	var solid := PackedByteArray()
	solid.resize(64)
	solid.fill(BLACK)
	_tiles[SOLID_BLACK] = solid
	for font in PLUS_KEYS:
		var g := MwGfx.font_glyph(rom, font, 0x2D)
		if g < 0:
			continue
		var minus := MwGfx.tile_indices(rom, int(MwGfx.piece(rom, font + 8 + 6 * g)["tile"]) * 32)
		var ink: int = minus[2 * 8 + 1]
		var plus := PackedByteArray()
		plus.resize(64)
		plus.fill(minus[0])
		for y in 8:
			for x in 8:
				if PLUS[y][x] == "#":
					plus[y * 8 + x] = ink
		_tiles[PLUS_KEYS[font]] = plus
		for ch in FIELD_CHARS:
			_tiles[field_key(font, ch)] = _drawn(FIELD_CHARS[ch], ink, minus[0])
		_tiles[field_key(font, CURSOR_SLOT)] = _drawn(CURSOR, ink, 0)
	for spec in REMAP_GLYPHS:
		var font: int = spec[0]
		var map: Dictionary = REMAPS[spec[2]]
		var chars: Array = []
		if spec[1] is String:
			for c in spec[1] as String:
				chars.append(c.unicode_at(0))
		else:
			chars = spec[1]
		for ch in chars:
			var g := MwGfx.font_glyph(rom, font, ch)
			if g < 0 or _remapped.has("%d|%d|%s" % [font, ch, spec[2]]):
				continue
			var piece := MwGfx.piece(rom, font + 8 + 6 * g)
			var keys := PackedInt32Array()
			for t in int(piece["w"]) * int(piece["h"]):
				var px := MwGfx.tile_indices(rom, (int(piece["tile"]) + t) * 32)
				for i in px.size():
					px[i] = map.get(px[i], px[i])
				var key := REMAP_BASE + _remapped.size() * 16 + t
				_tiles[key] = px
				keys.append(key)
			_remapped["%d|%d|%s" % [font, ch, spec[2]]] = {"w": piece["w"], "h": piece["h"], "keys": keys}


## Character [param ch] of [param font] recoloured by [param char_map]
## ([constant REMAPS]) at (x, y) like [method MwPlanePainter.glyph]: bottom
## on the font's baseline, tiles column-major. Returns the cells advanced
## (the plain glyph when there is no such recoloured one).
static func rom_glyph(plane: RomPlane, rom: PackedByteArray, font: int, ch: int, x: int, y: int, attr: int,
		char_map: String) -> int:
	_build()
	var r: Dictionary = _remapped.get("%d|%d|%s" % [font, ch, char_map], {})
	if r.is_empty():
		return MwPlanePainter.glyph(plane, rom, font, ch, x, y, attr)
	var w: int = r["w"]
	var h: int = r["h"]
	var top := y + MwGfx.s16(rom, font) - h
	plane.priority = (attr & 0x80) != 0
	for cy in h:
		for cx in w:
			plane.put(x + cx, top + cy, r["keys"][cx * h + cy], (attr >> 5) & 3, (attr & 0x08) != 0, (attr & 0x10) != 0)
	return w


## Text [param bytes] in [param font] recoloured by [param char_map] (as
## [method MwPlanePainter.text]). Returns the x after it.
static func rom_text(plane: RomPlane, rom: PackedByteArray, font: int, bytes: PackedByteArray, x: int, y: int,
		attr: int, char_map: String) -> int:
	for ch in bytes:
		if ch == 0x20:
			x += MwGfx.u16(rom, font + 2)
		else:
			x += rom_glyph(plane, rom, font, ch, x, y, attr, char_map)
	return x


## [method MwPlanePainter.text] with "+" as well (the port's, [constant
## PLUS_KEYS]; the menu fonts have none). Returns the x after it.
static func text(plane: RomPlane, rom: PackedByteArray, font: int, bytes: PackedByteArray, x: int, y: int,
		attr: int) -> int:
	return _text_with(plane, rom, font, bytes, x, y, attr, _port_keys(font, false))


## The cells [method text] advances for [param bytes].
static func text_width(rom: PackedByteArray, font: int, bytes: PackedByteArray) -> int:
	return _width_with(rom, font, bytes, _port_keys(font, false))


## A text field's text (plan 35): [method text] with the port's "*", "["
## and "]" too ([constant FIELD_CHARS]). Returns the x after it.
static func field_text(plane: RomPlane, rom: PackedByteArray, font: int, bytes: PackedByteArray, x: int, y: int,
		attr: int) -> int:
	return _text_with(plane, rom, font, bytes, x, y, attr, _port_keys(font, true))


## The cells [method field_text] advances for [param bytes].
static func field_width(rom: PackedByteArray, font: int, bytes: PackedByteArray) -> int:
	return _width_with(rom, font, bytes, _port_keys(font, true))


## The tile key of the port's character [param ch] (or the cursor,
## [constant CURSOR_SLOT]) for [param font].
static func field_key(font: int, ch: int) -> int:
	return FIELD_BASE + 128 * maxi(FIELD_FONTS.find(font), 0) + (ch & 127)


## A field's cursor at cell ([param x], [param y]) of [param plane] (a layer
## over the text: the cell is see-through but its underline).
static func field_cursor(plane: RomPlane, rom: PackedByteArray, font: int, x: int, y: int, attr: int) -> void:
	_build()
	var key := field_key(font, CURSOR_SLOT)
	if _tiles.has(key):
		plane.priority = (attr & 0x80) != 0
		plane.put(x, y + MwGfx.s16(rom, font) - 1, key, (attr >> 5) & 3)


## The port's own characters [param font] gets: char -> tile key ("+"
## always; with [param field] the field's too).
static func _port_keys(font: int, field: bool) -> Dictionary:
	_build()
	var out := {}
	if _tiles.has(PLUS_KEYS.get(font, -1)):
		out[0x2B] = PLUS_KEYS[font]
	if field and font in FIELD_FONTS:
		for ch in FIELD_CHARS:
			if _tiles.has(field_key(font, ch)):
				out[ch] = field_key(font, ch)
	return out


static func _text_with(plane: RomPlane, rom: PackedByteArray, font: int, bytes: PackedByteArray, x: int, y: int,
		attr: int, keys: Dictionary) -> int:
	if keys.is_empty():
		return MwPlanePainter.text(plane, rom, font, bytes, x, y, attr)
	var start := 0
	for i in bytes.size():
		if not keys.has(bytes[i]):
			continue
		x = MwPlanePainter.text(plane, rom, font, bytes.slice(start, i), x, y, attr)
		plane.priority = (attr & 0x80) != 0
		plane.put(x, y + MwGfx.s16(rom, font) - 1, keys[bytes[i]], (attr >> 5) & 3)
		x += 1
		start = i + 1
	return MwPlanePainter.text(plane, rom, font, bytes.slice(start), x, y, attr)


static func _width_with(rom: PackedByteArray, font: int, bytes: PackedByteArray, keys: Dictionary) -> int:
	var w := 0
	var start := 0
	for i in bytes.size():
		if keys.has(bytes[i]):
			w += MwGfx.text_width(rom, font, bytes.slice(start, i)) + 1
			start = i + 1
	return w + MwGfx.text_width(rom, font, bytes.slice(start))


## An 8 x 8 cell from [param rows] ("#" [param ink], else [param bg]).
static func _drawn(rows: Array, ink: int, bg: int) -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(64)
	px.fill(bg)
	for y in 8:
		for x in 8:
			if (rows[y] as String)[x] == "#":
				px[y * 8 + x] = ink
	return px


## The menus' selection frame (MwPlanePainter.frame) in black around the
## cells (x, y, w, h), filled black: [method black_label]'s plate.
static func black_frame(plane: RomPlane, rom: PackedByteArray, x: int, y: int, w: int, h: int) -> void:
	var f := MwPlanePainter.FONT_SMALL
	var g := func(ch: int, gx: int, gy: int, a: int) -> void:
		rom_glyph(plane, rom, f, ch, gx, gy, a, "black")
	for i in w:
		g.call(MwPlanePainter.CH_EDGE_H, x + i, y - 1, 0xE0)
		g.call(MwPlanePainter.CH_EDGE_H, x + i, y + h, 0xF0)
	for side in [[x - 1, 0xE0], [x + w, 0xE8]]:
		if h == 1:
			g.call(MwPlanePainter.CH_EDGE_ONE, side[0], y, side[1])
		else:
			g.call(MwPlanePainter.CH_EDGE_TOP, side[0], y, side[1])
			for i in range(1, h - 1):
				g.call(MwPlanePainter.CH_EDGE_MID, side[0], y + i, side[1])
			g.call(MwPlanePainter.CH_EDGE_TOP, side[0], y + h - 1, side[1] | 0x10)
	g.call(MwPlanePainter.CH_CORNER, x - 1, y - 1, 0xE0)
	g.call(MwPlanePainter.CH_CORNER, x - 1, y + h, 0xF0)
	g.call(MwPlanePainter.CH_CORNER, x + w, y - 1, 0xE8)
	g.call(MwPlanePainter.CH_CORNER, x + w, y + h, 0xF8)
	plane.priority = true
	for yy in h:
		for xx in w:
			plane.put(x + xx, y + yy, SOLID_BLACK, LINE)


## A label on a black plate: [param bytes] in [param font] from cell
## ([param x], [param y]), in [method black_frame] as wide as the text - the
## pause menu's player line (plan 23), the port menus' page titles. The
## plate is line 3's black, dark grey as on the pause menu when the layer's
## palette is [method plate_palette]'s. Returns the x after the text.
static func black_label(plane: RomPlane, rom: PackedByteArray, font: int, bytes: PackedByteArray, x: int, y: int,
		attr: int) -> int:
	black_frame(plane, rom, x, y, text_width(rom, font, bytes), 1)
	return text(plane, rom, font, bytes, x, y, attr)


## Plan 40 (M6): glyph cells [param glyph_cells] on [param plane] from cell
## [param x] on the letter row [param cell_row] (MwPrompts.row), at priority
## [param priority]; returns the x after them - every glyph a menu, a
## prompt, the lobby or a panel puts on its letter row.
static func put_cells(plane: RomPlane, glyph_cells: PackedInt32Array, x: int, cell_row: int, priority := true) -> int:
	plane.priority = priority
	for c in glyph_cells.size():
		plane.put(x + c, cell_row, glyph_cells[c], LINE)
	return x + glyph_cells.size()


## The live cells of verb [param verb] in [param style] (the keyboard's or
## the gamepad's, whichever was used last); none without the glyph sheets.
static func verb_cells(verb: String, style := Style.NORMAL) -> PackedInt32Array:
	return live_cells(verb, style) if tiles().size() > 0 else PackedInt32Array()


## Plan 40 (M2): a page's title on its plate ([method black_label]) on
## [param layer] (the title's own), centred on [param twice_centre] half
## cells to the half cell - an odd leftover moves the layer 4 px right -
## on row [param y]: the port menus', CREATE-A-TEAM's, the text entry's,
## the controller and character selections' titles.
static func plate_title(layer: RomPlane, rom: PackedByteArray, font: int, bytes: PackedByteArray, y: int, attr: int,
		twice_centre := 40) -> void:
	var c := MwMenuRow.centred_x(rom, font, bytes, twice_centre)
	layer.position.x = 4 * c.y
	black_label(layer, rom, font, bytes, c.x, y, attr)


## [param base] with line 3's black the pause menu plate's grey
## ([constant PLATE_GREY]): the palette of a layer that holds plates only
## (the light font's cells are black there too, so not the screen's text).
static func plate_palette(base: RomPalette) -> RomPalette:
	return RomPalette.derived(base, PackedStringArray([PLATE_GREY]))


static func _image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		push_warning("MwGlyphs: %s missing" % path)
		return null
	var t := load(path) as Texture2D
	var img := t.get_image() if t else null
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## A glyph's roles: {w, h (8), px: PackedByteArray of roles}.
static func _roles(w: int) -> Dictionary:
	var px := PackedByteArray()
	px.resize(w * 8)
	return {"w": w, "px": px}


## Key [param code]'s cap from the key sheet, trimmed to its width.
static func _vk_roles(img: Image, code: int) -> Dictionary:
	if code < 10 and not VK_EARLY.has(code):
		return {}                        # the sheet's first tiles hold codes 1-9
	var t: int = VK_EARLY.get(code, code)
	var x0 := 1 + (t % 16) * (VK_TILE + 1)
	var y0 := 1 + (t / 16) * 9
	var first := -1
	var last := -1
	for x in VK_TILE:
		for y in 8:
			if img.get_pixel(x0 + x, y0 + y).a8 > 0:
				if first < 0:
					first = x
				last = x
	if first < 0:
		return {}
	var r := _roles(last - first + 1)
	for y in 8:
		for x in r["w"]:
			var c := img.get_pixel(x0 + first + x, y0 + y)
			var role := NONE
			if c.a8 == 255:
				role = LABEL if c.r8 > 200 else (EDGE if c.r8 + c.g8 + c.b8 == 0 else BODY)
			elif c.a8 >= 128:
				role = EDGE
			r["px"][y * r["w"] + x] = role
	return r


## Tiles ([param tile_count] wide) at column [param c], row [param r] of the
## gamepad sheet, trimmed to the drawing's width.
static func _pad_roles(img: Image, c: int, r: int, tile_count: int) -> Dictionary:
	var x0 := c * 8
	var y0 := r * 8
	var first := -1
	var last := -1
	for x in tile_count * 8:
		for y in 8:
			if img.get_pixel(x0 + x, y0 + y).a8 > 0:
				if first < 0:
					first = x
				last = x
	if first < 0:
		return _roles(8)
	var out := _roles(last - first + 1)
	for y in 8:
		for x in out["w"]:
			var px := img.get_pixel(x0 + first + x, y0 + y)
			out["px"][y * out["w"] + x] = NONE if px.a8 == 0 else (LABEL if px.r8 > 200 else BODY)
	return out


## A chip of [param shape]'s outline with [param letters] (one or two 3 x 5
## letters, rows 2-6) in it.
static func _chip(shape: Dictionary, letters: String) -> Dictionary:
	var out := _roles(shape["w"])
	for i in shape["px"].size():
		out["px"][i] = BODY if shape["px"][i] != NONE else NONE
	var x := 1 if letters.length() == 2 else int((shape["w"] - 3) / 2)
	for ch in letters:
		_letter(out, ch, x, 2)
		x += 4
	return out


## A pill of [param shape]'s ends around [param letters] (3 x 5 letters, one
## column apart).
static func _pill(shape: Dictionary, letters: String) -> Dictionary:
	var w := 4 * letters.length() + 1
	var out := _roles(w)
	var sw: int = shape["w"]
	for y in 8:
		for x in w:
			# the left end as the shape's, the middle its column 1, the right end its last columns
			var sx := x if x < 2 else (sw - (w - x) if x >= w - 2 else 1)
			out["px"][y * w + x] = BODY if shape["px"][y * sw + sx] != NONE else NONE
	var x := 1
	for ch in letters:
		_letter(out, ch, x, 2)
		x += 4
	return out


static func _letter(r: Dictionary, ch: String, x: int, y: int) -> void:
	var rows: Array = MINI.get(ch, [])
	for dy in rows.size():
		for dx in 3:
			if rows[dy][dx] == "#":
				r["px"][(y + dy) * r["w"] + x + dx] = LABEL


## Registers glyph [param id]: its roles cut into whole cells (centred) in
## every style, as tiles.
static func _add(id: String, r: Dictionary, roles: Array) -> void:
	_roles_of[id] = r
	var n := int(ceil(r["w"] / 8.0))
	for style in Style.values():
		var keys := PackedInt32Array()
		for t in _cut(r, n, roles[style]):
			var key := KEY_BASE + _tiles.size()
			_tiles[key] = t
			keys.append(key)
		_cells["%s|%d" % [id, style]] = keys


## Roles [param r] centred in [param n] cells, as tiles of the indices
## [param map] gives the roles (an empty [param r]: blank cells).
static func _cut(r: Dictionary, n: int, map: Dictionary) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var w: int = r.get("w", 0)
	var off := int((n * 8 - w) / 2)
	for cell in n:
		var t := PackedByteArray()
		t.resize(64)
		t.fill(map.get("bg", 0))
		for y in 8:
			for x in 8:
				var sx := cell * 8 + x - off
				if sx < 0 or sx >= w:
					continue
				var role: int = r["px"][y * w + sx]
				if role != NONE:
					t[y * 8 + x] = map[["", "body", "label", "edge"][role]]
		out.append(t)
	return out
