extends "res://test/rom/rom_test_base.gd"
## Screen 10, the special plays with the Reserves page (MwSpecialPlaysSim;
## plan 11, docs/re/special-plays.md) on a set-up match: the set-up
## by pad mode, the plays page's choices (team +$4A5), the cursor, the
## positions and substitution lists, line changes (`player_create`), the
## refusals, the Demon Net, the done page and the exit, the idle page's
## players. The original pass for pass: `tools/bin/screen-check` (out/sim/scr_*).

const NONE := [0, 0, 0, 0]
const UP := 0x01
const DOWN := 0x02
const B := 0x10
const C := 0x20
const A := 0x40
const START := 0x80

var sim: MwRinkSim
var s: MwRinkState


class Idle:
	func think(_sim: MwRinkSim, _p: MwRinkState.Player, _team: MwRinkState.Team, _other: MwRinkState.Team) -> void:
		pass


func _match(pad_mode: int, reserves: bool) -> void:
	s = MwRinkState.new()
	s.rng = MlhRng.new(1234)
	sim = MwRinkSim.new(rom, s)
	sim.cpu = Idle.new()
	MwRinkMatch.start(sim, 4, 9, 4, pad_mode, reserves, 2)
	s.period = 1
	s.tick = 1000


func _screen(pad_mode: int, reserves: bool, from := 4) -> MwSpecialPlaysSim:
	_match(pad_mode, reserves)
	var sp := MwSpecialPlaysSim.new(rom)
	sp.enter(s, 10, from)
	return sp


## A pass of [param e] ticks; [param p1] / [param p2]: pads 1 / 2's newly pressed buttons.
func _run_pass(sp: MwScreenSim, p1 := 0, p2 := 0, e := 1) -> int:
	s.tick += e
	sp.begin_pass()
	var new := [p1, p2, 0, 0]
	return sp.step(e, new, new)


func _sounds(sp: MwScreenSim) -> Array:
	return sp.events.filter(func(x: Array) -> bool: return x[0] == "sound").map(func(x: Array) -> int: return x[1])


func _roster(t: int, i: int) -> int:
	return MwGfx.u32(rom, s.teams[t].record + 0x18 + 4 * i)


# --- set-up --------------------------------------------------------------------------------------

func test_setup_one_pad_team() -> void:
	if not need_rom():
		return
	var sp := _screen(0, false)
	var a: MwSpecialPlaysSim.Page = sp.pages[0]
	var b: MwSpecialPlaysSim.Page = sp.pages[1]
	assert_eq(a.handler, MwSpecialPlaysSim.PLAYS_PASS, "team A's special plays (set up in the first pass)")
	assert_eq(a.cursor, 1)
	for i in 3:
		assert_eq(a.items[1 + 2 * i], MwGfx.u32(rom, MwSpecialPlaysSim.PLAYS + 4 * (9 + i)), "Bribe / Waste the Ref / Jail Break")
	assert_eq([a.attr, a.row, a.done], [0x20, 0, 0])
	assert_eq(b.handler, MwSpecialPlaysSim.IDLE_PASS, "team B has no pad: the idle page")
	assert_eq([b.attr, b.row, b.done], [0x40, 0xE, 1])
	assert_eq(sp.mode2, 0)
	assert_eq(s.projection, 1, "the side view")
	assert_true(sp.events.any(func(x: Array) -> bool: return x[0] == "menu_music"))
	assert_eq(sp.plane_ops.filter(func(x: Array) -> bool: return x[0] == "map").size(), 3, "the line-up backdrop")
	assert_eq(MwSpecialPlaysSim.pictures(rom, 0).size(), 2)
	for p in s.teams[0].players:
		assert_eq(p.anim_id, 0xFF, "team A's players stopped")
		assert_eq(p.anim.variant, 4, "facing the camera")


func test_setup_two_pages_with_reserves() -> void:
	if not need_rom():
		return
	var sp := _screen(1, true)
	var a: MwSpecialPlaysSim.Page = sp.pages[0]
	var b: MwSpecialPlaysSim.Page = sp.pages[1]
	assert_eq(a.handler, MwSpecialPlaysSim.POSITIONS_PASS, "Reserves on: the positions")
	assert_eq(b.handler, MwSpecialPlaysSim.POSITIONS_PASS, "team B has a pad: its own page")
	assert_eq([b.row, b.done], [0xD, 0])
	assert_eq(sp.mode2, 2)
	assert_eq(a.items[6], 0, "no seventh position")
	assert_eq(sp.plane_ops.filter(func(x: Array) -> bool: return x[0] == "map").size(), 1, "the full backdrop")


# --- the special plays page -------------------------------------------------------------------------

func test_plays_choices_arm_team_special() -> void:
	if not need_rom():
		return
	var cases := [[A, s_nasty()], [B, 9], [C, 0], [START, -1]]
	for c in cases:
		var sp := _screen(0, false)
		var team := s.teams[0]
		team.special = 0x55
		assert_eq(_run_pass(sp, int(c[0])), -1, "the choice's pass")
		assert_eq(team.special, 0x55 if int(c[1]) < 0 else int(c[1]), "button %02X" % int(c[0]))
		assert_eq(sp.pages[0].done, 1, "Reserves off: done")
		assert_eq(_sounds(sp), [MwSpecialPlaysSim.SND_MOVE])
		assert_eq(_run_pass(sp), 5, "both pages done: a faceoff after a timeout")
		assert_eq(s.projection, 0, "the teardown")
		assert_true(sp.events.any(func(x: Array) -> bool: return x[0] == "fade_out"))


## Team A's nasty play of period 1 (team +$330) as the match set it up.
func s_nasty() -> int:
	_match(0, false)
	return s.teams[0].x330[0]


func test_special_play_by_cursor_and_overtime() -> void:
	if not need_rom():
		return
	var sp := _screen(0, false, 12)
	_run_pass(sp, DOWN)
	assert_eq(sp.pages[0].cursor, 3)
	_run_pass(sp, B)
	assert_eq(s.teams[0].special, 10, "the highlighted play: Waste the Ref")
	assert_eq(_run_pass(sp), 12, "back to the scoreboard it came from")
	sp = _screen(0, false)
	s.period = 4
	_run_pass(sp, A)
	assert_eq(s.teams[0].special, 0, "no nasty play in overtime")


func test_cursor_moves_and_wraps() -> void:
	if not need_rom():
		return
	var sp := _screen(0, false)
	var a: MwSpecialPlaysSim.Page = sp.pages[0]
	var seen := []
	for i in 3:
		_run_pass(sp, DOWN)
		seen.append(a.cursor)
	assert_eq(seen, [3, 5, 1], "the plays' rows, wrapping")
	_run_pass(sp, UP)
	assert_eq(a.cursor, 5, "up from the first: the last")
	assert_eq(_sounds(sp), [MwSpecialPlaysSim.SND_MOVE])
	assert_eq(a.comment, 0)


# --- positions and the substitution list ---------------------------------------------------------------

## Page A from the positions to the substitution list of [param slot].
func _open_slot(sp: MwSpecialPlaysSim, slot: int, pad := 0) -> void:
	for i in slot:
		_run_pass(sp, DOWN if pad == 0 else 0, DOWN if pad == 1 else 0)
	_run_pass(sp, A if pad == 0 else 0, A if pad == 1 else 0)


func test_substitution_list() -> void:
	if not need_rom():
		return
	var sp := _screen(1, true)
	_open_slot(sp, 1)
	var a: MwSpecialPlaysSim.Page = sp.pages[0]
	assert_eq(a.handler, MwSpecialPlaysSim.SUBST_PASS)
	assert_eq([a.slot, a.cursor], [1, 1])
	assert_eq(a.player, s.teams[0].players[1], "a3: the left wing's object")
	assert_eq(a.items[0], MwGfx.u32(rom, MwSpecialPlaysSim.T_ON_ICE))
	assert_eq(a.records[1], _roster(0, 1), "the left wing on the ice")
	assert_eq(a.items[1], MwGfx.u32(rom, _roster(0, 1)), "his name")
	assert_eq([a.records[3], a.records[4], a.records[5]], [_roster(0, 7), _roster(0, 13), _roster(0, 19)],
			"the other lines' left wings")
	var extra := a.records[6]
	assert_ne(extra, 0, "one more of another skater position")
	var i := range(24).filter(func(k: int) -> bool: return _roster(0, k) == extra)[0] as int
	assert_true(i % 6 != 1 and i % 6 != 5 and i >= 6, "not a left wing, not a goalie, not on the ice")
	assert_eq(a.records[7], 0)
	assert_true(a.portrait.anim.playing(), "the coach talks")
	assert_eq(a.portrait.size, 0)


func test_line_change() -> void:
	if not need_rom():
		return
	var sp := _screen(1, true)
	_open_slot(sp, 1)
	var a: MwSpecialPlaysSim.Page = sp.pages[0]
	_run_pass(sp, DOWN)
	assert_eq(a.cursor, 3, "item 2 is empty")
	var lw := s.teams[0].players[1]
	var before := s.rng.state
	var probe := MlhRng.new(0)
	probe.state = before
	probe.next_state()
	_run_pass(sp, A)
	assert_eq(lw.record, _roster(0, 7), "the line-2 left wing in")
	assert_eq(lw.original, _roster(0, 7))
	assert_eq([lw.index, lw.slot, lw.position], [1, 7, 1])
	assert_eq(lw.init_roll, probe.state & 0xF, "player_create's roll")
	assert_eq(s.rng.state, probe.state, "one rng_next")
	assert_eq(_sounds(sp), [MwSpecialPlaysSim.SND_CHANGE])
	assert_eq(sp.refresh, 1, "the idle page told")
	assert_eq([a.cursor, a.records[1]], [1, _roster(0, 7)], "the list made again")
	assert_true(_roster(0, 1) in [a.records[3], a.records[4], a.records[5], a.records[6]], "the old one a candidate now")


func test_refusals() -> void:
	if not need_rom():
		return
	# the slot's player in the penalty box
	var sp := _screen(1, true)
	var team := s.teams[0]
	team.stats[0x10] = 1                      # box entry 0 in use ...
	team.stats[0xE] = 1                       # ... by roster slot 1
	_open_slot(sp, 1)
	assert_eq(sp.pages[0].items[0], MwGfx.u32(rom, MwSpecialPlaysSim.T_PENALTY_BOX))
	_run_pass(sp, DOWN)
	_run_pass(sp, A)
	assert_eq(team.players[1].record, _roster(0, 1), "nobody leaves the box")
	assert_eq(_sounds(sp), [MwSpecialPlaysSim.SND_REFUSED])
	# a dead candidate: refused, the list made again
	sp = _screen(1, true)
	team = s.teams[0]
	team.health[7] = 0
	_open_slot(sp, 1)
	_run_pass(sp, DOWN)
	assert_eq(sp.pages[0].comment, MwGfx.u32(rom, MwSpecialPlaysSim.T_DEAD))
	assert_true(sp.sprite_ops.any(func(x: Array) -> bool: return x[0] == "frame" and x[1] == MwSpecialPlaysSim.FIGURE_DEAD))
	_run_pass(sp, A)
	assert_eq(team.players[1].record, _roster(0, 1))
	assert_eq(_sounds(sp), [MwSpecialPlaysSim.SND_REFUSED])
	assert_eq(sp.refresh, 1, "made again all the same")
	# item 1 (the player already there): nothing
	sp = _screen(1, true)
	_open_slot(sp, 1)
	_run_pass(sp, C)
	assert_eq(_sounds(sp), [MwSpecialPlaysSim.SND_MOVE])
	assert_eq(sp.refresh, 0)


func test_comments() -> void:
	if not need_rom():
		return
	var sp := _screen(1, true)
	var team := s.teams[0]
	team.health[13] = 0x300000                # line 3's left wing hurting
	_open_slot(sp, 1)
	var a: MwSpecialPlaysSim.Page = sp.pages[0]
	_run_pass(sp, DOWN)
	var rec := _roster(0, 7)
	var t := MwGfx.u32(rom, MwGfx.u32(rom, MwGfx.u32(rom, MwSpecialPlaysSim.QUOTES + 4 * 9) + 4 * 1) + 4 * a.quote_set)
	var count := MwGfx.u16(rom, t + 2)
	var want := MwGfx.u32(rom, t + 4 + 4 * (MwGfx.u16(rom, rec + 4) % count))
	if rom[rec + 0xD] >> 4 != 0:
		want = MwGfx.u32(rom, MwSpecialPlaysSim.T_ENFORCER)
	assert_eq(a.comment, want, "the coach's word on a line-2 player (no RNG)")
	assert_true(sp.window_ops.any(func(x: Array) -> bool: return x[0] == "box"), "the speech frame")
	_run_pass(sp, DOWN)
	assert_eq(a.comment, MwGfx.u32(rom, MwSpecialPlaysSim.T_HURTIN))


func test_start_back_to_positions() -> void:
	if not need_rom():
		return
	var sp := _screen(1, true)
	_open_slot(sp, 3)
	_run_pass(sp, DOWN)
	_run_pass(sp, START)
	var a: MwSpecialPlaysSim.Page = sp.pages[0]
	assert_eq(a.handler, MwSpecialPlaysSim.POSITIONS_PASS)
	assert_eq(a.cursor, 3, "on the position it came from")


func test_demon_net() -> void:
	if not need_rom():
		return
	var sp := _screen(1, true)               # team B attacks down and has the Demon Net (+4 bits 1, 3)
	_open_slot(sp, 5, 1)
	var b: MwSpecialPlaysSim.Page = sp.pages[1]
	assert_eq(b.handler, MwSpecialPlaysSim.SUBST_PASS, "page B on pad 2")
	assert_eq(b.records[6], MwSpecialPlaysSim.DEMON_NET, "the Demon Net after the other lines' goalies")
	for i in 4:
		_run_pass(sp, 0, DOWN)
	assert_eq(b.cursor, 6, "items 3-5: the other lines' goalies")
	assert_eq(b.comment, MwGfx.u32(rom, MwSpecialPlaysSim.T_EVIL))
	_run_pass(sp, 0, A)
	var g := s.teams[1].players[5]
	assert_eq(s.nets[0].style, 0, "the Demon Net in")
	assert_eq(g.record, 0, "the goalie's slot empty")
	assert_eq(b.records[1], MwSpecialPlaysSim.DEMON_NET, "shown in the slot")
	assert_eq([b.records[3], b.records[6], b.records[7]], [_roster(1, 5), _roster(1, 23), 0],
			"the four goalies, no second Demon Net")
	_run_pass(sp, 0, DOWN)
	_run_pass(sp, 0, DOWN)
	_run_pass(sp, 0, A)
	assert_eq(g.record, _roster(1, 11), "the line-2 goalie in")
	assert_eq(s.nets[0].style, rom[MwRinkState.stadium_record(rom, s.stadium) + 5], "the stadium's net back")


# --- done, the exit, the idle page ------------------------------------------------------------------------

func test_done_page_and_exit() -> void:
	if not need_rom():
		return
	var sp := _screen(1, true)
	var a: MwSpecialPlaysSim.Page = sp.pages[0]
	_run_pass(sp, START)
	assert_eq([a.handler, a.done, a.cursor], [MwSpecialPlaysSim.DONE_PASS, 1, 8])
	_run_pass(sp, START)
	assert_eq(a.done, 1, "Start: still done")
	_run_pass(sp, DOWN)
	assert_eq([a.handler, a.done, a.cursor], [MwSpecialPlaysSim.POSITIONS_PASS, 0, 0], "any other button: back")
	_run_pass(sp, START)
	assert_eq(_run_pass(sp), -1, "page B not done yet")
	_run_pass(sp, 0, START)
	assert_eq(_run_pass(sp), 5)


func test_idle_page_players() -> void:
	if not need_rom():
		return
	var sp := _screen(0, false)
	var before := s.rng.state
	_run_pass(sp, 0, 0, 4)
	assert_eq(sp.idle_e, 4)
	assert_ne(s.rng.state, before, "the standing players roll their taunts")
	var anims: Array = sp.sprite_ops.filter(func(x: Array) -> bool: return x[0] == "anim")
	assert_eq(anims.size(), 6, "team A's six players")
	for i in 6:
		assert_eq([anims[i][4], anims[i][5], anims[i][7]], [0x32 + 0x2D * i, 0xA4, 0x20])
		assert_eq(anims[i][8], MwSpecialPlaysSim.BOARDS_BOTTOM, "cut below the boards")
	# a substitution on page A sets the idle page up again in the same pass
	_match(2, true)
	sp = MwSpecialPlaysSim.new(rom)
	sp.enter(s, 10, 4)
	_open_slot(sp, 1)
	_run_pass(sp, DOWN)
	_run_pass(sp, A)
	assert_eq(sp.refresh, 0, "the idle page set up again")
	assert_false(sp.sprite_ops.any(func(x: Array) -> bool: return x[0] == "anim" and x[5] == 0xA4), "no line-up that pass")
	assert_eq(s.teams[0].players[1].anim_id, 0xFF, "the new left wing stopped")
