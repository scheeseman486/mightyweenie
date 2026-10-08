extends "res://test/rom/rom_test_base.gd"
## The scoreboards (MwScoreboardSim, screens 12-16) and the message
## scoreboard (MwMessageScoreboardSim, 17) on a set-up match (plan 11;
## docs/re/scoreboards.md): set-ups, the menu and its exits, 12's comment,
## the event team's line-up, the Zamboni, 17's penalty sequence, its skip,
## the referee's message and the box display. The original pass for pass:
## `tools/bin/screen-check` (out/sim/scr_*).

var sim: MwRinkSim
var s: MwRinkState
const NONE := [0, 0, 0, 0]


class Idle:
	func think(_sim: MwRinkSim, _p: MwRinkState.Player, _team: MwRinkState.Team, _other: MwRinkState.Team) -> void:
		pass


func before_each() -> void:
	if rom.is_empty():
		return
	s = MwRinkState.new()
	s.rng = MlhRng.new(1234)
	sim = MwRinkSim.new(rom, s)
	sim.cpu = Idle.new()
	MwRinkMatch.start(sim, 4, 9, 4, 0, false, 2)
	s.period_minutes = 3
	s.clock = 150
	var phases := MwRinkPhases.new(MwRinkUpdate.new(sim))
	phases.enter(5)                          # everyone lined up
	s.tick = 1000


static func _team_long(t: int) -> int:
	return 0xFFFF0000 | int(MwScoreboardSim.TEAM_WORDS[t])


## A pass of [param e] ticks (the tick counter moved on first).
func _run_pass(sb: MwScreenSim, e: int, new := NONE) -> int:
	s.tick += e
	sb.begin_pass()
	return sb.step(e, new, new)


func _goal(kind: int, scorer: MwRinkState.Player) -> void:
	s.phase = 3
	s.goal_kind = kind
	s.scoring = _team_long(0)
	s.scorer = MwScoreboardSim.player_long(scorer)


func _events(sb: MwScreenSim, kind: String) -> Array:
	return sb.events.filter(func(x: Array) -> bool: return x[0] == kind)


# --- 12-16 ---------------------------------------------------------------------------------------

func test_goal_comment() -> void:
	if not need_rom():
		return
	var scorer := s.teams[0].players[1]
	_goal(0, scorer)
	var sb := MwScoreboardSim.new(rom)
	sb.enter(s, 12, 5)
	assert_eq(sb.flag, 1)
	assert_eq(sb.menu, 0, "no menu yet")
	assert_eq(sb.comment, 1, "the scorer comments")
	assert_eq(sb.name, MwGfx.u32(rom, scorer.original), "his name")
	assert_true(sb.portrait.anim.playing(), "his portrait talks")
	assert_eq(sb.portrait.size, 0, "no border")
	assert_eq(sb.quote_at, 0xFFFFC4FE)
	assert_ne(s.quote[0], 0, "a quote")
	assert_eq(s.box_fill, 1, "the speech box filled at the set-up")
	assert_eq([s.text_box.x, s.text_box.y, s.text_box.w, s.text_box.h], [2, 2, 36, 5])
	assert_eq(s.projection, 1, "the side view")
	assert_eq(scorer.state, MwScoreboardSim.CELEBRATE, "the scorer celebrates")
	for p in s.teams[0].players:
		if p != scorer:
			assert_eq(p.state, 0)
			assert_eq(p.anim.variant, 4, "facing the camera")
	assert_eq(_events(sb, "crowd_off").size(), 1)
	# a pass: the portrait, the speech box framed, the quote, the tail, the name
	_run_pass(sb, 2)
	assert_eq(s.box_fill, 0)
	var kinds := sb.sprite_ops.map(func(x: Array) -> String: return x[0])
	assert_true(kinds.has("portrait") and kinds.has("piece"))
	assert_eq(kinds.count("anim"), 6, "the six players")
	var celebrating: Array = sb.sprite_ops.filter(func(x: Array) -> bool: return x[0] == "anim" and x[5] == 0xBC + 0x18)
	assert_eq(celebrating.size(), 1, "the scorer 24 px lower")
	assert_eq(celebrating[0][4], 0x32 + 0x2D * scorer.position)
	assert_eq(celebrating[0].size(), 8, "the scorer in front of the boards: not cut")
	var standing: Array = sb.sprite_ops.filter(func(x: Array) -> bool: return x[0] == "anim" and x[5] == 0xBC)
	assert_eq(standing.size(), 5)
	for op: Array in standing:
		assert_eq(op[8], MwScoreboardSim.BOARDS_BOTTOM, "the others cut below the boards")
	# their pieces carry the row; the sprite layer leaves nothing below it
	var row := MwScoreboardSim.BOARDS_BOTTOM + MwRinkDraw.SPRITE_ORIGIN
	var list := MwScreenDraw.new(rom).list(s, sb.sprite_ops)
	var cut: Array = list.filter(func(e: Array) -> bool: return e.size() > 6)
	assert_gt(cut.size(), 0)
	assert_true(cut.all(func(e: Array) -> bool: return int(e[6]) == row))
	assert_true(cut.any(func(e: Array) -> bool: return int(e[1]) + 8 * ((int(e[2]) & 3) + 1) > row),
			"a piece reaching below the boards")
	var layer := MwSpriteLayer.new()
	add_child_autofree(layer)
	for e: Array in cut:
		var w := 8 * (((int(e[2]) >> 2) & 3) + 1)
		var img := layer._cut(e, []).get_image()
		for y in img.get_height():
			for x in w:
				if int(e[1]) + y >= row:
					assert_eq(img.get_pixel(x, y).r8, 0, "nothing below the boards")
	MwScreenDraw.cut_rows = false
	assert_true(MwScreenDraw.new(rom).list(s, sb.sprite_ops).all(func(e: Array) -> bool: return e.size() == 6),
			"the original's pixels when off (the visual check)")
	MwScreenDraw.cut_rows = true
	assert_true(sb.window_ops.any(func(x: Array) -> bool: return x[0] == "quote"))
	assert_true(sb.plane_ops.any(func(x: Array) -> bool: return x[0] == "text" and x[5] == sb.name))


func test_own_goal_menu_at_once() -> void:
	if not need_rom():
		return
	_goal(6, null)
	var sb := MwScoreboardSim.new(rom)
	sb.enter(s, 12, 5)
	assert_eq(sb.menu, 1, "an own goal: the menu at once")
	assert_eq(sb.panel.dir, 1, "the panel opening")
	assert_true(sb.music >= 0, "the music on")
	assert_eq(_events(sb, "music").size(), 1)
	assert_eq(sb.comment, 0)


func test_menu_opens_and_choices() -> void:
	if not need_rom():
		return
	_goal(0, s.teams[0].players[2])
	for want in [[0x80, 5], [0x40, 8], [0x10, 10], [0x20, 7]]:
		var sb := MwScoreboardSim.new(rom)
		sb.enter(s, 12, 5)
		assert_eq(_run_pass(sb, 2, [0, 0x80, 0, 0]), -1, "Start (any pad) shows the menu")
		assert_eq(sb.menu, 1)
		assert_eq(_run_pass(sb, 2), -1)
		assert_eq(sb.comment, 0, "the comment ended")
		assert_false(sb.portrait.anim.playing())
		var to := _run_pass(sb, 2, [int(want[0]), 0, 0, 0])
		assert_eq(to, int(want[1]), "menu button %02X" % int(want[0]))
		assert_eq(s.projection, 0, "the teardown")
		assert_true(sb.events.any(func(x: Array) -> bool: return x[0] == "fade_out"))


func test_panel_opens_in_40_ticks() -> void:
	if not need_rom():
		return
	_goal(6, null)
	var sb := MwScoreboardSim.new(rom)
	sb.enter(s, 12, 5)
	var texts := 0
	for i in 20:
		_run_pass(sb, 2)
		texts = sb.window_ops.filter(func(x: Array) -> bool: return x[0] == "text").size()
		assert_eq(texts, 0, "no menu texts while it opens")
	assert_eq(sb.panel.size, MwMessagePanel.BIG, "fully open after 40 ticks")
	assert_eq(sb.panel.dir, 1, "still moving: it stops on the next step (27 -> 26)")
	_run_pass(sb, 2)
	texts = sb.window_ops.filter(func(x: Array) -> bool: return x[0] == "text").size()
	assert_eq(sb.panel.dir, 0)
	assert_eq(texts, 4, "A, B, C, Start")


func test_menu_after_600_ticks() -> void:
	if not need_rom():
		return
	_goal(0, s.teams[0].players[2])
	var sb := MwScoreboardSim.new(rom)
	sb.enter(s, 12, 5)
	for i in 299:
		_run_pass(sb, 2)
	assert_eq(sb.menu, 0, "598 ticks")
	_run_pass(sb, 2)
	assert_eq(sb.menu, 1, "600 ticks")


func test_return_shows_menu_and_ends_comment() -> void:
	if not need_rom():
		return
	_goal(0, s.teams[0].players[2])
	var sb := MwScoreboardSim.new(rom)
	sb.enter(s, 12, 8)
	assert_eq(sb.menu, 1, "back from 8: the menu at once")
	assert_eq(sb.comment, 1, "the quote picked again")
	_run_pass(sb, 1)
	assert_eq(sb.comment, 0, "and rubbed out on the first pass")
	assert_true(sb.window_ops.any(func(x: Array) -> bool: return x[0] == "fill" and x[5] == 0x8000))


func test_standing_players_roll_every_pass() -> void:
	if not need_rom():
		return
	_goal(6, null)
	var sb := MwScoreboardSim.new(rom)
	sb.enter(s, 12, 5)
	var team := s.teams[0]
	for p in team.players:
		sim.players.stop(p)
		p.anim.flags &= ~MwAnimState.PLAYING
		p.state = 0
	sb.log_rng = true
	sb.rng_log.clear()
	_run_pass(sb, 1)
	assert_true(sb.rng_log.size() >= 6, "one draw per standing player (a goalie's taunt may draw twice)")


func test_game_over_screens() -> void:
	if not need_rom():
		return
	s.phase = 10
	s.scoring = _team_long(1)
	for scr in [15, 16]:
		var sb := MwScoreboardSim.new(rom)
		sb.enter(s, scr, 5)
		assert_true(sb.music >= 0, "music from the entry")
		assert_eq(_run_pass(sb, 2, [0x10, 0, 0, 0]), -1, "B shows the menu in the intro")
		assert_eq(sb.menu, 1)
		assert_eq(_run_pass(sb, 2, [0x10, 0, 0, 0]), -1, "B does nothing in the menu")
		assert_eq(_run_pass(sb, 2, [0x80, 0, 0, 0]), 1 if scr == 15 else 11)


func test_zamboni() -> void:
	if not need_rom():
		return
	s.phase = 5
	var sb := MwScoreboardSim.new(rom)
	sb.enter(s, 14, 5)
	var z := sb.zamboni
	assert_eq(sb.flag, 0)
	assert_true(sb.music >= 0, "music from the entry")
	assert_eq([z.x, z.target, z.attr, z.y, z.depth], [-92, 480, 0xA0, 0xD8, 0xF000])
	for i in 4:
		assert_true(z.debris_x[i] >= 32 + 80 * i and z.debris_x[i] < 96 + 80 * i, "debris %d spread out" % i)
	var turned := false
	for i in 800:
		_run_pass(sb, 1)
		if z.target < 0:
			turned = true
			break
	assert_true(turned, "turned at 480")
	assert_eq(z.attr & 8, 8, "flipped")
	for i in 4:
		assert_eq(z.debris_x[i], MwScoreboardSim.Zamboni.GONE, "debris %d picked up" % i)
	# D-pad presses queue cracks
	_run_pass(sb, 1, [0x01, 0, 0, 0])
	_run_pass(sb, 1, [0, 0x08, 0, 0])
	assert_eq(z.cracks, 2)
	for i in 400:
		_run_pass(sb, 1)
	assert_eq(z.cracks, 0, "the cracks played")


# --- 17 ------------------------------------------------------------------------------------------

func _call(p: MwRinkState.Player, code: int) -> void:
	p.flags |= MwRinkState.Player.IN_BOX
	p.penalty = code & 0xFF
	var t := sim.team_of(p)
	MwRinkPenalties.set_byte(t, MwRinkPenalties.PENDING, MwRinkPenalties.byte(t, MwRinkPenalties.PENDING) + 1)


func test_penalty_sequence() -> void:
	if not need_rom():
		return
	s.penalties = 1
	s.phase = 2
	var a := s.teams[0].players[2]
	var b := s.teams[1].players[1]
	_call(b, -3)
	_call(a, -4)
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 5)
	assert_eq(sb.state, 0)
	assert_eq(sb.lockout, 0)
	_run_pass(sb, 1)
	assert_eq(sb.current, a, "team A's called player first")
	assert_eq(sb.state, 1)
	assert_eq(sb.panel.dir, 1, "the panel opens")
	var states := [1]
	var order := [a]
	for i in 3000:
		_run_pass(sb, 1)
		if states[states.size() - 1] != sb.state:
			states.append(sb.state)
		if sb.current != null and order[order.size() - 1] != sb.current:
			order.append(sb.current)
		if sb.state == MwMessageScoreboardSim.MENU and sb.menu != 0:
			break
	assert_eq(order, [a, b], "then team B's")
	assert_eq(sb.side, -1)
	assert_eq(states.slice(0, 6), [1, 2, 3, 4, 5, 6], "(7 may end in 6's pass)")
	assert_eq(sb.state, MwMessageScoreboardSim.MENU, "the menu by itself")
	assert_eq(MwRinkPenalties.count(s.teams[0]), 1)
	assert_eq(MwRinkPenalties.count(s.teams[1]), 1)
	assert_false(a.present, "off the ice")
	for t in 2:
		assert_true(MwRinkPenalties.byte(s.teams[t], MwRinkPenalties.entry(0) + 6) & 0x80 != 0, "entry shown")
	# the walker stopped level with his entry, in the box's column
	assert_eq(b.motion.pixels().x, MwMessageScoreboardSim.BOX_DOOR)
	assert_true(absi(b.motion.pixels().y) >= 52)
	for i in 30:
		_run_pass(sb, 1)
	assert_eq(_run_pass(sb, 1, [0, 0, 0x40, 0]), 8, "A (any pad) -> 8")


func test_skip_on_the_fouled_pad() -> void:
	if not need_rom():
		return
	s.penalties = 1
	s.phase = 2
	s.teams[1].flags4 |= 4
	s.teams[1].pads[0] = 1
	MwRinkPenalties.set_flags(s.teams[0], MwRinkPenalties.STOP)
	var a1 := s.teams[0].players[1]
	var a2 := s.teams[0].players[3]
	_call(a1, -3)
	_call(a2, 2)
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 5)
	assert_eq(sb.pad, 2, "pad 2 (team B's) skips")
	for i in 10:
		_run_pass(sb, 1)
	assert_eq(_run_pass(sb, 1, [0x80, 0, 0, 0]), -1)
	assert_ne(sb.state, MwMessageScoreboardSim.MENU, "Start on pad 1 ignored")
	_run_pass(sb, 1, [0, 0x80, 0, 0])
	assert_eq(sb.state, MwMessageScoreboardSim.MENU, "skipped")
	assert_eq(MwRinkPenalties.count(s.teams[0]), 2, "both in the box at once")
	for i in 2:
		assert_true(MwRinkPenalties.byte(s.teams[0], MwRinkPenalties.entry(i) + 6) & 0x80 != 0)
	assert_eq(sb.menu, 0)
	_run_pass(sb, 1)
	assert_eq(sb.menu, 1, "the menu on the next pass")


func test_referee_message_and_forfeit() -> void:
	if not need_rom():
		return
	s.phase = 12
	s.scoring = _team_long(1)
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 19)
	assert_eq([sb.state, sb.lockout], [8, 180])
	_run_pass(sb, 1)
	assert_eq(sb.state, 9)
	assert_eq(sb.portrait_on, 1)
	assert_eq(sb.portrait.data, MwScoreboardSim.NO_PORTRAIT, "the referee's face")
	assert_eq(sb.portrait.mode, 1, "pulling a face")
	var boxes := sb.window_ops.filter(func(x: Array) -> bool: return x[0] == "box")
	assert_eq(boxes.map(func(x: Array) -> bool: return x[5]), [true, false], "filled at the set-up, framed by the pass")
	assert_eq(s.box_fill, 0)
	assert_ne(s.quote[0], 0, "the new referee's quote")
	assert_eq(sb.team_a3, s.teams[1], "about the event team")
	assert_eq(_run_pass(sb, 100, [0x80, 0, 0, 0]), -1, "locked")
	assert_eq(_run_pass(sb, 81, [0x40, 0, 0, 0]), -1, "A does nothing")
	assert_eq(_run_pass(sb, 1, [0x80, 0, 0, 0]), 5, "Start: a new referee, back to the rink")
	# a forfeit: the other team wins
	s.phase = 13
	s.scoring = _team_long(0)
	s.play_mode = 0
	sb = MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 5)
	_run_pass(sb, 181)
	assert_eq(_run_pass(sb, 1, [0x80, 0, 0, 0]), 15)
	assert_eq(s.scoring, _team_long(1))


func test_return_to_menu_mode() -> void:
	if not need_rom():
		return
	s.phase = 2
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 10)
	assert_eq(sb.state, MwMessageScoreboardSim.MENU)
	assert_eq(sb.menu, 1)
	assert_true(sb.music >= 0)
	assert_eq(_run_pass(sb, 1, [0x80, 0, 0, 0]), 5)


func test_box_display() -> void:
	if not need_rom():
		return
	s.penalties = 1
	var a := s.teams[0].players[2]
	_call(a, -3)
	var i := sim.penalties.put_in_box(a)
	var team := s.teams[0]
	var at := MwRinkPenalties.entry(i)
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 10)
	sb.begin_pass()
	MwMessageScoreboardSim.box_display(sb, 2)
	assert_eq(sb.sprite_ops.size(), 0, "not shown yet")
	MwRinkPenalties.set_byte(team, at + 6, MwRinkPenalties.byte(team, at + 6) | 0x80)
	var before := MwRinkPenalties.word(team, at + 8)
	MwMessageScoreboardSim.box_display(sb, 2)
	assert_eq(sb.sprite_ops.size(), 1)
	var op: Array = sb.sprite_ops[0]
	assert_eq([op[4], op[5], op[7]], [-52 + 160, 377 - 189, team.attr], "team A's first y, side view")
	assert_ne(MwRinkPenalties.word(team, at + 8), before, "its animation advanced")


func test_human_sent_to_the_box_hands_control_on() -> void:
	if not need_rom():
		return
	s.penalties = 1
	s.phase = 2
	var team := s.teams[0]
	for p in team.players:
		p.flags &= ~MwRinkState.Player.HUMAN
	var called := team.players[3]
	called.flags |= MwRinkState.Player.HUMAN
	_call(called, -3)
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 5)
	# `$1856` reads 17's stack frame as the puck: a neutral-zone point at (-77, 0)
	var v := sb.rink.human.a6_view
	assert_eq([MwRinkSim.asr(v.x, 8), v.y, v.vx, v.vy, v.flags & 1], [-0x4D, 0, 0, 0, 0])
	for i in 400:
		_run_pass(sb, 1)
		if not called.present:
			break
	assert_false(called.present, "in the box")
	assert_eq(called.flags & MwRinkState.Player.HUMAN, 0, "control handed on")
	var humans := team.players.filter(func(p: MwRinkState.Player) -> bool: return p.flags & MwRinkState.Player.HUMAN != 0)
	assert_eq(humans.size(), 1, "to one team-mate")


func test_zone_of_a_long() -> void:
	for y in [0, 50, -50, 120, -120, 400, -400]:
		for d4 in [0, -1]:
			assert_eq(MwHumanControl.zone_of_long(y * 256, d4), _zone(y, d4), "y %d, d4 %d" % [y, d4])


## `$439C` for a y that fits a word (the rink's port, `_zone_of`).
static func _zone(y: int, d4: int) -> int:
	var ny := -absi(y)
	var d0 := 0
	if ny <= -0x6C:
		d0 = -1
		if ny <= -0x149:
			d0 = -2
	if ((-1 if y < 0 else 0) ^ d4) != 0:
		d0 = -d0
	return d0 + 2
