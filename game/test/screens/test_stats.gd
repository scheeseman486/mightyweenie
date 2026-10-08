extends "res://test/rom/rom_test_base.gd"
## The game stats (screen 8) and the player stats inside it (9) on a set-up
## match (MwStatsSim; plan 11, docs/re/stats.md): the set-up, the formatted
## values, plane A's scrolling, the starfield on the second random stream,
## 9's pages and teams, the exits. The original pass for pass:
## `tools/bin/screen-check --only 8` (out/sim/scr_*).

var sim: MwRinkSim
var s: MwRinkState
const NONE := [0, 0, 0, 0]
const UP := 0x01
const DOWN := 0x02
const LEFT := 0x04
const B := 0x10
const C := 0x20
const A := 0x40
const START := 0x80


func before_each() -> void:
	if rom.is_empty():
		return
	s = MwRinkState.new()
	s.rng = MlhRng.new(1234)
	sim = MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim, 4, 9, 4, 0, false, 2)
	s.tick = 1000


## A stats screen entered from the scoreboard 14, its aux stream seeded.
func _enter(aux_seed := 0x12345678) -> MwStatsSim:
	var st := MwStatsSim.new(rom)
	st.aux = MlhRng.new(aux_seed)
	st.enter(s, 8, 14)
	return st


## A pass of [param e] ticks (the tick counter moved on first): [param
## held] / [param new] on pad 1.
func _run_pass(st: MwStatsSim, held := 0, new := 0, e := 1) -> int:
	s.tick += e
	st.begin_pass()
	return st.step(e, [held, 0, 0, 0], [new, 0, 0, 0])


## A button tapped: newly pressed and held in one pass.
func _tap(st: MwStatsSim, button: int) -> int:
	return _run_pass(st, button, button)


func _texts(ops: Array) -> Array:
	return ops.filter(func(o: Array) -> bool: return o[0] == "text")


func _events(st: MwStatsSim, kind: String) -> Array:
	return st.events.filter(func(x: Array) -> bool: return x[0] == kind)


static func _ascii(v: Variant) -> String:
	return (v as PackedByteArray).get_string_from_ascii()


func test_setup() -> void:
	if not need_rom():
		return
	var main_rng := s.rng.state
	var aux := MlhRng.new(0x12345678)
	var st := _enter()
	assert_eq(st.shown, 8)
	assert_eq(s.rng.state, main_rng, "the main stream untouched")
	var k := aux.next_state() & 0xE
	assert_eq(st.aux.state, aux.state, "one draw for the starfield's direction")
	assert_eq(st.star.vel[0], MwGfx.s16(rom, MwStatsSim.STAR_VX + k))
	assert_eq(st.star.vel[1], MwGfx.s16(rom, MwStatsSim.STAR_VY + k))
	assert_eq(st.star.pos[0], MwStatsSim.STAR_SETUP_TICKS * st.star.vel[0], "9 ticks along at the first boundary")
	assert_eq(st.stars_on, 0xFF)
	assert_eq(st.scroll_a, MwStatsSim.SCROLL_TOP, "the first row at the top")
	assert_eq(st.window_rows, 9)
	assert_eq(st.formatter, 4, "four special rows")
	assert_eq(st.handle, 0)
	assert_eq([st.labels[0].x, st.labels[0].y, st.labels[1].x, st.labels[1].y], [2, 26, 38, 26])
	assert_eq(st.labels[0].text, 0xFFFFC432)
	assert_eq(st.labels[1].plane, MwStatsSim.PLANE_A)
	# the window: cleared, the title, two team names on row 7
	var w := _texts(st.window_ops)
	assert_eq(st.window_ops[0][0], "fill")
	assert_eq(w.size(), 3)
	assert_eq(w[0][5], MwGfx.u32(rom, MwStatsSim.TITLE + 6))
	assert_eq([w[1][3], w[2][3]], [7, 7])
	var name_b := MwGfx.rom_string(rom, MwGfx.u32(rom, s.teams[1].record + 4))
	assert_eq(int(w[2][2]) + MwGfx.text_width(rom, MwStatsSim.NAME_FONT, name_b), 38, "team B right-aligned")
	# plane A: cleared, 13 rows of (team A value, team B value, label)
	var p := _texts(st.plane_a_ops)
	assert_eq(p.size(), 13 * 3)
	for i in 13:
		assert_eq(int(p[3 * i][3]), 2 * i, "row %d two rows apart" % i)
		assert_eq(p[3 * i + 2][5], MwGfx.u32(rom, MwStatsSim.ROWS + 6 * i), "row %d's label" % i)
	# sprites: only the down arrow at the first row, then both logos
	assert_eq(st.sprite_ops[0][1], MwStatsSim.ARROW)
	assert_eq(st.sprite_ops[0][4], MwGfx.u16(rom, MwStatsSim.ARROW_DOWN + 6))
	assert_ne(st.sprite_ops[1][1], MwStatsSim.ARROW)
	assert_eq(_events(st, "music_track").size(), 1, "the stats music")


func test_values() -> void:
	if not need_rom():
		return
	var ta := s.teams[0]
	var tb := s.teams[1]
	ta.score = 7
	ta.add_stat(0x482, 105)               # shots
	ta.add_stat(0x486, 2)                 # power plays 2/5
	ta.add_stat(0x488, 5)
	ta.add_stat(0x48A, 3)                 # penalties 3/6:00
	ta.add_stat(0x48C, 6)
	ta.add_stat(0x496, 12)                # passing 12/40 (30%)
	ta.add_stat(0x498, 40)
	tb.add_stat(0x490, 1000)              # hard checks: 1000 has no fourth digit
	tb.add_stat(0x496, 5)                 # passing 5/0: no percentage
	var st := _enter()
	var p := _texts(st.plane_a_ops)
	var row := func(i: int, t: int) -> String: return _ascii(p[3 * i + t][5])
	assert_eq(row.call(0, 0), "7")
	assert_eq(row.call(0, 1), "0")
	assert_eq(row.call(1, 0), "105")
	assert_eq(row.call(3, 0), "2/5")
	assert_eq(row.call(4, 0), "3/6:00")
	assert_eq(row.call(8, 0), "12/40 (30%)")
	assert_eq(row.call(8, 1), "5/0")
	assert_eq(row.call(6, 1), ":00", "1000: the hundreds' digit is 10 (':')")
	assert_eq(row.call(12, 0), "", "the last row has no values")
	var label_x := int(p[3 * 1 + 2][2])
	var w := MwGfx.text_width(rom, MwStatsSim.BOX_FONT, MwGfx.rom_string(rom, MwGfx.u32(rom, MwStatsSim.ROWS + 6)))
	assert_eq(label_x, (40 - w) >> 1, "labels centred")


func test_scroll() -> void:
	if not need_rom():
		return
	var st := _enter()
	assert_eq(_run_pass(st, DOWN, DOWN), -1)
	assert_eq([st.scroll_step, st.scroll_left, st.scroll_a], [2, -16, -80], "a step starts")
	for i in 7:
		_run_pass(st, B, B)                    # pads not read while the step runs
		assert_eq(st.scroll_a, -78 + 2 * i)
	assert_eq(st.stars_on, 0xFF, "B ignored during the step")
	_run_pass(st)
	assert_eq([st.scroll_left, st.scroll_step, st.scroll_a], [0, 0, -64], "16 px, the step over")
	assert_eq(st.sprite_ops.filter(func(o: Array) -> bool: return o[1] == MwStatsSim.ARROW).size(), 2, "both arrows")
	for i in 1 + 3 * 8:
		_run_pass(st, DOWN)                # a pass starts the step, 8 move it (the last starts the next)
	assert_eq(st.scroll_a, MwStatsSim.SCROLL_BOTTOM)
	_run_pass(st, DOWN)
	_run_pass(st, DOWN)
	assert_eq(st.scroll_a, MwStatsSim.SCROLL_BOTTOM, "not past the last row")
	assert_eq(st.sprite_ops[0][4], MwGfx.u16(rom, MwStatsSim.ARROW_UP + 6), "only the up arrow")
	_run_pass(st, LEFT)
	for i in 8:
		_run_pass(st)
	assert_eq(st.scroll_a, -32, "left scrolls up")
	assert_eq(_events(st, "sound").size(), 0, "no sound for scrolling")


func test_starfield() -> void:
	if not need_rom():
		return
	var main_rng := s.rng.state
	var st := _enter()
	var aux := st.aux.state
	var x := st.star.pos[0]
	_tap(st, B)
	assert_eq([st.stars_on, st.star.vel[0], st.star.vel[1]], [0, 0, 0], "B holds it")
	assert_eq(st.aux.state, aux, "no draw")
	assert_eq(st.star.pos[0], x, "it stays")
	_tap(st, C)
	assert_eq(st.aux.state, aux, "C does nothing while held")
	assert_eq(_events(st, "sound").size(), 0)
	_tap(st, B)
	assert_eq(st.stars_on, 0xFF)
	assert_ne(st.aux.state, aux, "B starts it in a new direction")
	assert_eq(st.star.pos[0] & 0xFF, (st.star.vel[0] * 1) & 0xFF, "its fraction dropped, then one tick")
	aux = st.aux.state
	_tap(st, C)
	assert_ne(st.aux.state, aux, "C re-aims it")
	assert_eq(_events(st, "sound")[0][1], MwStatsSim.BUTTON)
	assert_eq(s.scroll_b, Vector2i(MwRinkSim.asr(st.star.pos[0], 8), MwRinkSim.asr(st.star.pos[1], 8)), "plane B's scroll")
	assert_eq(s.rng.state, main_rng, "the main stream untouched")


func test_player_stats() -> void:
	if not need_rom():
		return
	var main_rng := s.rng.state
	var st := _enter()
	assert_eq(_tap(st, A), -1, "9 runs inside 8")
	assert_eq(st.shown, 9)
	assert_eq(_events(st, "fade_out").size(), 1)
	assert_eq(_events(st, "music_fade").size(), 0, "the music plays on")
	assert_eq([st.page, st.team_shown, st.redraw, st.stars_on], [0, 0, 1, 0xFF])
	assert_eq([st.scroll_a, st.hscroll_a], [0, 0])
	assert_eq(st.box_at, MwStatsSim.BOX_W, "drawn into plane A, the window next")
	assert_eq(st.window_rows, 0, "plane A shows")
	assert_eq(st.row, 9 + 5 * 3)
	assert_eq(st.saved_font, MwStatsSim.BOX_FONT)
	var p := _texts(st.plane_a_ops)
	var rows := p.filter(func(o: Array) -> bool: return int(o[2]) == 1 and int(o[3]) >= 9)
	assert_eq(rows.size(), 5, "5 jersey numbers")
	assert_eq(_ascii(rows[0][5]).length(), 2, "two digits")
	assert_eq(st.sprite_ops.size() > 2, true, "the logo and two arrows")
	# Down: the next page drawn into the window, which then covers the screen
	var aux := st.aux.state
	_tap(st, DOWN)
	assert_eq(st.page, 1)
	assert_eq(st.box_at, MwStatsSim.BOX_A)
	assert_eq(st.window_rows, 28)
	assert_gt(_texts(st.window_ops).size(), 10)
	assert_eq(st.aux.state, aux)
	# a pass without input keeps the sprites up and draws nothing
	_run_pass(st)
	assert_eq(st.window_ops.size() + st.plane_a_ops.size(), 0)
	assert_gt(st.sprite_ops.size(), 2)
	_tap(st, UP)
	_tap(st, UP)
	assert_eq(st.page, 4, "Up from 0: the goalies")
	assert_eq(st.row, 9 + 4 * 3, "4 goalies")
	_tap(st, DOWN)
	assert_eq(st.page, 0, "Down from 4: the starters")
	_tap(st, A)
	assert_eq(st.team_shown, 1, "A: the other team")
	assert_eq(st.page, 0, "the page kept")
	assert_ne(st.aux.state, aux, "A re-aims the starfield")
	aux = st.aux.state
	assert_eq(_tap(st, START), -1, "Start: back to 8")
	assert_eq(st.shown, 8)
	assert_eq(st.scroll_a, MwStatsSim.SCROLL_TOP, "8 set up again")
	assert_eq(st.window_rows, 9)
	assert_eq(st.handle, 0)
	assert_ne(st.aux.state, aux, "the starfield started again")
	assert_eq(_events(st, "music_track").size(), 0, "its music still playing")
	assert_eq(s.rng.state, main_rng, "the main stream untouched")


func test_player_values() -> void:
	if not need_rom():
		return
	var t := s.teams[0]
	var slot := 2                           # line 1's third slot
	t.add_stat(0x3A2 + 8 * slot + 4, 3)     # G
	t.add_stat(0x3A2 + 8 * slot + 6, 12)    # PTS
	t.add_stat(0x3A2 + 8 * slot + 2, 7)     # SOG
	t.add_stat(0x3A2 + 8 * slot, 25)        # PIM
	var goalie := 5                         # line 1's goalie
	t.add_stat(0x3A2 + 8 * goalie + 4, 9)   # goals against
	t.add_stat(0x3A2 + 8 * goalie + 2, 4)   # shots: fewer than goals, SAV 0
	var st := _enter()
	_tap(st, A)
	var y := 9 + 3 * slot + 1
	var at_row := _texts(st.plane_a_ops).filter(func(o: Array) -> bool: return int(o[3]) == y and int(o[2]) >= 20)
	var got := at_row.map(func(o: Array) -> Array: return [int(o[2]) + _ascii(o[5]).length(), _ascii(o[5])])
	assert_eq(got, [[24, "3"], [29, "12"], [34, "7"], [39, "25"]], "right-aligned to 24 / 29 / 34 / 39")
	_tap(st, UP)                            # goalies, into the window
	var g := _texts(st.window_ops).filter(func(o: Array) -> bool: return int(o[3]) == 10 and int(o[2]) >= 20)
	assert_eq(g.map(func(o: Array) -> String: return _ascii(o[5])), ["9", "0", "4"], "G, SAV, SOG")


func test_leave() -> void:
	if not need_rom():
		return
	var st := _enter()
	_run_pass(st)
	assert_eq(_tap(st, START), 14, "back to the scoreboard it came from")
	assert_eq(_events(st, "music_fade")[0][1], 32)
	assert_eq(_events(st, "fade_out")[0][1], 32)
	assert_eq(_events(st, "sound").size(), 1)
	assert_false(st.star_task, "the starfield freed")
