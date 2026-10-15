extends "res://test/rom/rom_test_base.gd"
## The FACE OFF letters in a wide picture (owner, 2026-10-09: aware of
## ultrawide pictures, the text faster the further it has to move, the
## sequence as long as ever): they fly
## in from beyond the bigger picture's edges (MwRinkDraw3D.drop_shift), in
## 2D (wide_list) and 3D (MwRink3DHost.screen_list), and land where and
## when the original's do.
## Short names: d the MwRinkDraw3D under test.

const ULTRA := Vector2i(573, 240)        ## a 3440 x 1440 window's picture (6x)
const ULTRA_OFF := Vector2i(126, 8)

var _state: MwRinkState
var _adds: Array


func before_all() -> void:
	super.before_all()
	var first_pass: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			repo_path("compare/fixtures/rink_draw.json")))["passes"][0]
	_state = MwRinkState.from_dict(rom, first_pass["state"])
	_adds = first_pass["phase_adds"]


## A pass drawn with the letters at the drop's height [param h] (`$ADDC`).
func _drawn(h: int) -> MwRinkDraw3D:
	var d := MwRinkDraw3D.new(rom)
	var ops := [["sprite_text", MwRinkPhases.BIG_FONT, 0x40 - h, 0x64, 0xA0, 0xFFFF, MwRinkPhases.T_FACE],
			["sprite_text", MwRinkPhases.BIG_FONT, 0xA0 + h, 0x64, 0xA0, 0xFFFF, MwRinkPhases.T_OFF]]
	d.build(_state, _adds, -1, [], ops)
	return d


## The letters' entries (big font pieces at the letters' row) in [param list].
func _letters(d: MwRinkDraw3D, list: Array) -> Array:
	var tiles := {}
	for piece: Array in d.pieces:
		if piece.size() > 6:
			var entry := MwRinkDraw.piece_entry(rom, int(piece[0]), int(piece[1]), int(piece[2]), int(piece[3]),
					int(piece[4]))
			tiles[[entry[1], entry[4]]] = true
	return list.filter(func(e: Array) -> bool: return tiles.has([e[1], e[4]]))


func test_the_shift() -> void:
	assert_eq(MwRinkDraw3D.drop_shift(180, 126), 126, "from the top: the whole margin further out")
	assert_eq(MwRinkDraw3D.drop_shift(90, 128), 32, "half way down: a quarter")
	assert_eq(MwRinkDraw3D.drop_shift(4, 126), 0, "landed: where the original lands them")
	assert_eq(MwRinkDraw3D.drop_shift(180, 0), 0, "not wide: the original's")
	var last := -1
	for h in range(0, 181, 10):
		assert_true(MwRinkDraw3D.drop_shift(h, 126) >= last, "further out the higher")
		last = MwRinkDraw3D.drop_shift(h, 126)


func test_the_letters_are_marked() -> void:
	if not need_rom():
		return
	var d := _drawn(120)
	var sides := {}
	for piece: Array in d.pieces:
		if piece.size() > 6:
			sides[(piece[6] as Vector2i).x] = (piece[6] as Vector2i).y
	assert_eq(sides, {-1: 120, 1: 120}, "FACE on the left, OFF! on the right, the drop's height")


func test_2d_wide_letters_fly_in_from_the_edges() -> void:
	if not need_rom():
		return
	var high := _drawn(180)
	assert_eq(_letters(high, high.wide_list(ULTRA, ULTRA_OFF, Vector2i.ZERO, [])), [],
			"at the top: beyond the wide picture's edges")
	var mid := _drawn(100)
	var wide := _letters(mid, mid.wide_list(ULTRA, ULTRA_OFF, Vector2i.ZERO, []))
	var orig := _letters(mid, mid.sprites())
	var left := wide.filter(func(e: Array) -> bool: return int(e[0]) < MwRinkDraw.SPRITE_ORIGIN)
	assert_false(left.is_empty(), "in the margin left of the original's screen: not clipped to it")
	var shift := MwRinkDraw3D.drop_shift(100, ULTRA_OFF.x)
	for letter: Array in orig:
		var moved := letter.duplicate()
		moved[0] = int(letter[0]) - shift if int(letter[0]) < MwRinkDraw.SPRITE_ORIGIN + 112 else int(letter[0]) \
				+ MwRinkDraw3D.drop_shift(100, ULTRA.x - 320 - ULTRA_OFF.x)
		assert_has(wide, moved, "each letter further out on its side")
	var low := _drawn(4)
	assert_eq(_letters(low, low.wide_list(ULTRA, ULTRA_OFF, Vector2i.ZERO, [])), _letters(low, low.sprites()),
			"landed: as the original")


func test_3d_wide_letters_too() -> void:
	if not need_rom():
		return
	var host := MwRink3DHost.new()
	host.view_size = Vector2(ULTRA)
	var d := _drawn(100)
	var orig := _letters(d, d.screen_sprites())
	assert_false(orig.is_empty())
	for arrows in [true, false]:
		var list := MwRink3DHost.screen_list(host, d.screen_sprites(), d.screen_sprites(true), [], arrows, rom,
				d.pieces)
		var letters := _letters(d, list)
		for letter: Array in orig:
			assert_false(letter in letters, "not where the original puts them")
		assert_eq(letters, MwRinkDraw3D.wide_drop(rom, d.pieces, ULTRA, host.column_origin()), "moved out, in front")
	host.view_size = Vector2(MwRink3D.SCREEN)
	assert_eq(MwRink3DHost.screen_list(host, d.screen_sprites(), d.screen_sprites(true), [], true, rom, d.pieces),
			d.screen_sprites(),
			"not wide: the original's")
	host.free()
