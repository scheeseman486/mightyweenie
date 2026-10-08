extends "res://test/rom/rom_test_base.gd"
## The fight (MwFightSim, screen 18) on a set-up match (plan 11;
## docs/re/fight.md): who fights, the walk-in, the fighters' rules (punch,
## block, hit, knock-down, the walk and its limits, the stun), the CPU that
## never blocks, the result (knockout, decision, draw) and what it leaves
## for the rink, the pause, the penalty calls and the fight card. The
## original pass for pass: `tools/bin/screen-check` (out/sim/scr_1041_v10,
## scr_1033_v3).

const NONE := [0, 0, 0, 0]

var sim: MwRinkSim
var s: MwRinkState


## A match lined up for the faceoff, phase 4 (a fight), pad mode
## [param pads] (0: team A human on pad 1, team B CPU; 1: both human, pads
## 1 and 2; 5: both CPU).
func _match(pads: int) -> void:
	s = MwRinkState.new()
	s.rng = MlhRng.new(1234)
	sim = MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim, 4, 9, 4, pads, false, 2)
	s.period_minutes = 3
	s.clock = 150
	MwRinkPhases.new(MwRinkUpdate.new(sim)).enter(5)
	s.phase = 4
	s.tick = 1000


func _fight(pads := 1) -> MwFightSim:
	_match(pads)
	var f := MwFightSim.new(rom)
	f.enter(s, 18, 5)
	return f


## A pass of [param e] ticks with pad bytes held / newly pressed.
func _run(f: MwFightSim, e: int, held := NONE, new := NONE) -> int:
	s.tick += e
	f.begin_pass()
	return f.step(e, held, new)


## The walk-in run through (2-tick passes): the ticks it took.
func _walk_in(f: MwFightSim) -> int:
	var t := 0
	while f.state == MwFightSim.WALK_IN and t < 400:
		_run(f, 2)
		t += 2
	return t


## Pad 1 (index 0) or 2 (index 1) holding / pressing [param bits].
static func _pad(i: int, bits: int) -> Array:
	var a := [0, 0, 0, 0]
	a[i] = bits
	return a


## Team A's fighter walked right (pad 1) until it stops.
func _close_in(f: MwFightSim) -> void:
	for i in 200:
		_run(f, 1, _pad(0, 0x08))
		if f.fighters[0].motion.vel[0] == 0 and i > 0:
			break


func _sounds(f: MwFightSim) -> Array:
	return f.events.filter(func(x: Array) -> bool: return x[0] == "sound").map(func(x: Array) -> int: return int(x[1]))


# --- set-up ------------------------------------------------------------------------------------

func test_setup() -> void:
	if not need_rom():
		return
	_match(0)
	var flagged := s.teams[0].players[3]
	flagged.flags |= MwRinkState.Player.FIGHTING
	s.teams[1].players[2].flags |= MwRinkState.Player.FIGHTING
	s.teams[1].players[4].flags |= MwRinkState.Player.FIGHTING
	var rng0 := s.rng.state
	var f := MwFightSim.new(rom)
	f.enter(s, 18, 5)
	var a := f.fighters[0]
	var b := f.fighters[1]
	assert_eq(s.rng.state, rng0, "flagged fighters: no draw")
	assert_eq(a.player, flagged)
	assert_eq(b.player, s.teams[1].players[2], "the lowest flagged slot")
	assert_eq(s.projection, 1, "the side view")
	assert_eq([a.motion.pixels(), b.motion.pixels()], [Vector3i(-80, 224, 8000), Vector3i(400, 224, 8000)])
	assert_eq([a.motion.vel[0], b.motion.vel[0]], [0x180, -0x180], "walking in at 1.5 px a tick")
	assert_eq([a.attr, b.attr], [0xA8, 0xC0], "team A flipped to face right")
	assert_eq([a.pad, b.pad], [0, -1], "team A on pad 1, team B the CPU")
	for x in f.fighters:
		var fx: MwFightSim.Fighter = x
		var team := s.teams[fx.player.team]
		assert_eq(fx.health, 0x7800)
		assert_eq(fx.rating, sim.avg(team, rom[fx.record + 9] >> 4), "FIGHTING with the skulls")
		assert_eq(fx.damage, 2880 + 480 * fx.rating)
		assert_eq(fx.speed, 208 + 8 * fx.rating)
		assert_eq(fx.state, MwFightSim.STAND)
		assert_true(fx.anim.playing())
		assert_false(fx.fx.playing())
	assert_eq(f.state, MwFightSim.WALK_IN)
	assert_eq(f.fight_time, 0)
	assert_eq(f.panel.size, MwMessagePanel.SMALL)


func test_unflagged_teams_draw_their_fighter() -> void:
	if not need_rom():
		return
	_match(1)
	for t in 2:
		for p in s.teams[t].players:
			p.flags &= ~MwRinkState.Player.FIGHTING
	s.teams[0].players[1].record = 0                    # an empty slot is drawn again
	var rng0 := s.rng.state
	var f := MwFightSim.new(rom)
	f.enter(s, 18, 5)
	assert_ne(s.rng.state, rng0, "rng_range(0, 4) per team")
	for x in f.fighters:
		var fx: MwFightSim.Fighter = x
		assert_true(fx.player.present)
		assert_true(fx.player.index < 5, "never the goalie")
	assert_eq([f.fighters[0].pad, f.fighters[1].pad], [0, 2], "both human: pads 1 and 2 (word offsets)")


func test_second_pad_player() -> void:
	if not need_rom():
		return
	_match(2)                                           # team A: pads 1 and 2
	var p := s.teams[0].players[1]
	p.flags |= MwRinkState.Player.FIGHTING | MwRinkState.Player.SECOND_PAD
	var f := MwFightSim.new(rom)
	f.enter(s, 18, 5)
	assert_eq(f.fighters[0].pad, 2 * (int(s.teams[0].pads[1]) & 0xFF), "the team's second pad")


# --- the walk-in and the walk ------------------------------------------------------------------

func test_walk_in_takes_120_ticks() -> void:
	if not need_rom():
		return
	var f := _fight()
	assert_eq(_walk_in(f), 120)
	assert_eq(f.state, MwFightSim.FIGHTING)
	assert_eq([f.fighters[0].x(), f.fighters[1].x()], [100, 220])
	assert_eq([f.fighters[0].motion.vel[0], f.fighters[1].motion.vel[0]], [0, 0])
	assert_has(_sounds(f), MwFightSim.BELL, "the bell")
	assert_eq(f.stamp, s.tick, "the fight clock counts from here")


func test_walk_limits() -> void:
	if not need_rom():
		return
	var f := _fight()
	_walk_in(f)
	var a := f.fighters[0]
	var b := f.fighters[1]
	_close_in(f)
	assert_eq(a.x(), b.x() - MwFightSim.GAP, "never closer than 74 px")
	for i in 300:
		_run(f, 1, _pad(0, 0x04))
	assert_eq(a.x(), MwFightSim.LEFT_WALL, "the left wall")
	for i in 300:
		_run(f, 1, _pad(1, 0x08))
	assert_eq(b.x(), MwFightSim.RIGHT_WALL, "the right wall")
	for i in 300:
		_run(f, 1, _pad(1, 0x04 | 0x01))                # left with up: still left
	assert_eq(b.x(), a.x() + MwFightSim.GAP)
	var x := b.x()
	for i in 20:
		_run(f, 1, _pad(1, 0x0C))                       # left and right: nothing
	assert_eq(b.x(), x)


# --- punches -----------------------------------------------------------------------------------

## Team A's fighter punches (B newly pressed) and the passes run until the
## punch is over; returns the passes' sounds.
func _punch(f: MwFightSim, b_held := 0, b_new := 0) -> Array:
	var sounds := []
	var held := [0, b_held, 0, 0]
	var new := [0x10, b_new, 0, 0]
	_run(f, 1, held, new)
	sounds.append_array(_sounds(f))
	for i in 120:
		_run(f, 1, [0, b_held, 0, 0])
		sounds.append_array(_sounds(f))
		if f.fighters[0].state != MwFightSim.PUNCH:
			break
	return sounds


func test_punch_lands() -> void:
	if not need_rom():
		return
	var f := _fight()
	_walk_in(f)
	_close_in(f)
	var a := f.fighters[0]
	var b := f.fighters[1]
	var r0 := s.rng.state
	var x := b.x()
	_run(f, 1, NONE, _pad(0, 0x10))
	assert_eq(a.state, MwFightSim.PUNCH, "B punches")
	assert_eq(a.motion.pos[2], 8001 << 8, "the puncher in front")
	assert_eq(b.motion.pos[2], 8000 << 8)
	for i in 60:
		_run(f, 1)
		if b.state != MwFightSim.STAND:
			break
	assert_eq(b.state, MwFightSim.HIT)
	assert_eq([a.thrown, a.landed], [1, 1])
	assert_eq(b.stun, 0x14 - 1, "stunned 20 passes (one gone in its own step)")
	var rng := MlhRng.new(r0)
	rng.next_state()                                     # the sound
	var big := (rng.next_state() & 0xFFFF) < 0x800
	assert_eq(b.health, 0x7800 - a.damage * (4 if big else 1))
	assert_eq(s.rng.state, rng.state, "two draws: the sound, the damage")
	if b.species(rom) != 1:
		assert_true(b.fx.playing(), "the hit's second animation")
		assert_eq(b.fx.address, MwFightSim.HURT_FX)
		assert_eq(b.fx_y, 70)
	else:
		assert_false(b.fx.playing(), "none for species 1")
	_run(f, 1)
	assert_true(b.motion.vel[0] > 0, "knocked back, away from the puncher")
	assert_eq(b.motion.vel[0], MwRinkSim.asr(b.speed * 0x13, 3), "speed x stun / 8")

	for i in 40:
		_run(f, 1)
	assert_eq(b.stun, 0, "the stun runs out pass by pass")
	assert_true(b.x() > x)
	assert_eq(b.state, MwFightSim.STAND, "the hit over")


func test_block() -> void:
	if not need_rom():
		return
	var f := _fight()
	_walk_in(f)
	_close_in(f)
	var a := f.fighters[0]
	var b := f.fighters[1]
	var sounds := _punch(f, 0x40, 0x40)
	assert_has(sounds, MwFightSim.BLOCK_SOUND, "A newly pressed blocks, held keeps it")
	assert_eq(a.landed, 0)
	assert_eq(a.thrown, 1)
	var blocks := (0x7800 - b.health) / (a.damage >> 4)
	assert_eq((0x7800 - b.health) % (a.damage >> 4), 0, "a sixteenth of the damage per blocked pass")
	assert_true(blocks >= 1)
	_run(f, 1, _pad(1, 0x40), _pad(1, 0x40))
	assert_eq(b.state, MwFightSim.BLOCK)
	for i in 29:
		_run(f, 1, _pad(1, 0x40))
	assert_eq(b.state, MwFightSim.BLOCK, "held")
	_run(f, 1, _pad(1, 0x40))
	assert_eq(b.state, MwFightSim.STAND, "30 ticks at most")
	_run(f, 1, _pad(1, 0x40), _pad(1, 0x40))
	_run(f, 1)
	assert_eq(b.state, MwFightSim.STAND, "or released")


func test_held_a_does_not_block() -> void:
	if not need_rom():
		return
	var f := _fight()
	_walk_in(f)
	_close_in(f)
	_punch(f, 0x40, 0)
	assert_eq(f.fighters[0].landed, 1, "held from before: no block")


func test_punch_cancelled_into_block() -> void:
	if not need_rom():
		return
	var f := _fight()
	_walk_in(f)
	var a := f.fighters[0]
	_run(f, 1, NONE, _pad(0, 0x20))
	assert_eq(a.state, MwFightSim.PUNCH, "C punches like B")
	_run(f, 1, _pad(0, 0x40), _pad(0, 0x40))
	assert_eq(a.state, MwFightSim.BLOCK)


func test_cpu_never_blocks() -> void:
	if not need_rom():
		return
	var f := _fight(0)
	_walk_in(f)
	var b := f.fighters[1]
	var states := {}
	for i in 1500:
		var new := _pad(0, 0x10) if i % 6 == 0 else NONE
		_run(f, 1, _pad(0, 0x08), new)
		states[b.state] = true
		if f.state != MwFightSim.FIGHTING:
			break
	assert_false(states.has(MwFightSim.BLOCK), "the AI's held A never blocks")
	assert_true(states.has(MwFightSim.PUNCH), "but it punches")


func test_cpu_draws_once_per_pass() -> void:
	if not need_rom():
		return
	var f := _fight(0)
	_walk_in(f)
	var r := MlhRng.new(s.rng.state)
	_run(f, 1)
	r.next_state()
	assert_eq(s.rng.state, r.state, "one rng_next for the CPU fighter")
	_run(f, 3)
	r.next_state()
	assert_eq(s.rng.state, r.state, "per pass, whatever its length")


# --- the end -----------------------------------------------------------------------------------

func test_knockout() -> void:
	if not need_rom():
		return
	var f := _fight()
	_walk_in(f)
	_close_in(f)
	var a := f.fighters[0]
	var b := f.fighters[1]
	b.health = 1
	_run(f, 1, NONE, _pad(0, 0x10))
	for i in 60:
		_run(f, 1)
		if b.state != MwFightSim.STAND:
			break
	assert_eq(b.state, MwFightSim.KNOCKED)
	assert_eq(b.health, 0)
	assert_eq(b.fx.address, MwFightSim.KO_FX)
	assert_eq(a.memory, 0)
	var t0 := s.tick
	var time := f.fight_time
	while b.state == MwFightSim.KNOCKED and s.tick - t0 < 400:
		_run(f, 1)
	assert_eq(b.state, MwFightSim.DOWN)
	assert_true(b.motion.pixels().y >= 0x130, "fallen below the screen")
	assert_eq(f.fight_time, time, "the clock held")
	var t1 := s.tick
	while f.state == MwFightSim.FIGHTING and s.tick - t1 < 400:
		_run(f, 1)
	assert_eq(s.tick - t1, 120, "down 120 ticks, out")
	assert_eq(b.state, MwFightSim.OUT)
	assert_eq(f.state, MwFightSim.RESULT_PANEL)
	assert_eq(f.result, 2)
	assert_eq(f.winner, a)
	assert_eq(s.goal_kind, 2, "`$FFC63A` 2: a knockout")
	assert_eq(s.scorer, MwScoreboardSim.player_long(a.player))
	assert_eq(s.teams[0].stat(0x49C), 1, "team A's fights won")
	assert_eq(s.teams[1].stat(0x49C), 0)
	for i in 40:
		_run(f, 1)
		if f.state == MwFightSim.RESULT:
			break
	assert_eq(f.state, MwFightSim.RESULT, "the panel open")
	assert_ne(f.card_sound, 0, "the KO sound")
	assert_eq(f.crowd, 1333)
	_run(f, 1)
	assert_eq(f.crowd, 1333 - 11, "11 lower a pass")
	assert_has(f.events, ["crowd", 1000], "1000 at most heard")


## Fight time at 1199 with the punches landed [param la] / [param lb]: the
## pass that ends it.
func _time_up(la: int, lb: int) -> MwFightSim:
	var f := _fight()
	_walk_in(f)
	f.fighters[0].landed = la
	f.fighters[1].landed = lb
	f.fight_time = 1199
	_run(f, 1)
	return f


func test_decision() -> void:
	if not need_rom():
		return
	var f := _time_up(1, 3)
	assert_has(_sounds(f), MwFightSim.BELL)
	assert_eq(f.state, MwFightSim.RESULT_PANEL)
	assert_eq(f.result, 1)
	assert_eq(f.winner, f.fighters[1], "more punches landed")
	assert_eq(f.winner_team, 0xFFFFBC4E, "team B + $3A2")
	assert_eq(s.goal_kind, 1)
	assert_eq(s.scorer, MwScoreboardSim.player_long(f.fighters[1].player))
	assert_eq(s.teams[1].stat(0x49C), 1)


func test_draw() -> void:
	if not need_rom():
		return
	var f := _time_up(2, 2)
	assert_eq(f.result, 0)
	assert_null(f.winner)
	assert_eq(f.winner_team, 0)
	assert_eq(s.goal_kind, 0)
	assert_eq(s.scorer, 0)
	assert_eq(s.teams[0].stat(0x49C) + s.teams[1].stat(0x49C), 0, "nobody won")


func test_fight_clock() -> void:
	if not need_rom():
		return
	var f := _fight()
	_walk_in(f)
	for i in 100:
		_run(f, 3)
	assert_eq(f.fight_time, 300)
	f.begin_pass()
	f._clock_draw()
	var glyphs := f.plane_ops.map(func(o: Array) -> int: return int(o[o.size() - 1]))
	assert_eq(glyphs, [0x20, 0x30, 0x3A, 0x31, 0x35], " 0:15 left")


func test_pause() -> void:
	if not need_rom():
		return
	var f := _fight()
	_walk_in(f)
	for i in 10:
		_run(f, 1)
	var time := f.fight_time
	_run(f, 1, _pad(0, 0x80), _pad(0, 0x80))
	assert_eq(f.state, MwFightSim.PAUSING, "Start pauses")
	for i in 40:
		_run(f, 1)
	assert_eq(f.state, MwFightSim.PAUSED)
	assert_eq(f.panel.size, MwMessagePanel.BIG)
	assert_true(f.window_ops.any(func(o: Array) -> bool: return o[0] == "text" and int(o[5]) == MwFightSim.PAUSE_TEXT))
	for i in 100:
		_run(f, 1)
	_run(f, 1, _pad(0, 0x80), _pad(0, 0x80))
	assert_eq(f.state, MwFightSim.FIGHTING, "Start again resumes")
	assert_eq(f.panel.dir, -1)
	_run(f, 1)
	assert_eq(f.fight_time, time + 1, "the pause not counted")


func test_cpu_start_does_not_pause() -> void:
	if not need_rom():
		return
	var f := _fight(0)
	_walk_in(f)
	_run(f, 1, _pad(1, 0x80), _pad(1, 0x80))
	assert_eq(f.state, MwFightSim.FIGHTING, "pad 2 drives no fighter")


# --- the calls and the card --------------------------------------------------------------------

## The passes from a result to the card.
func _to_card(f: MwFightSim) -> void:
	for i in 300:
		_run(f, 1)
		if f.card:
			break


func test_penalty_calls() -> void:
	if not need_rom():
		return
	var f := _time_up(3, 1)
	s.penalties = 1
	_to_card(f)
	var a := f.fighters[0].player
	var b := f.fighters[1].player
	assert_true(f.card)
	assert_true(a.flags & MwRinkState.Player.IN_BOX and b.flags & MwRinkState.Player.IN_BOX)
	assert_eq(a.penalty, 0xF9, "the winner a minor (-7)")
	assert_eq(b.penalty, 1, "the loser a major (1)")
	assert_eq(MwRinkPenalties.byte(s.teams[0], MwRinkPenalties.PENDING), 1)
	assert_eq(MwRinkPenalties.byte(s.teams[1], MwRinkPenalties.PENDING), 1)


func test_draw_calls_both_minor() -> void:
	if not need_rom():
		return
	var f := _time_up(0, 0)
	s.penalties = 1
	_to_card(f)
	assert_eq([f.fighters[0].player.penalty, f.fighters[1].player.penalty], [0xF9, 0xF9])


func test_no_calls_with_penalties_off() -> void:
	if not need_rom():
		return
	var f := _time_up(3, 1)
	s.penalties = 0
	_to_card(f)
	for x in f.fighters:
		assert_eq((x as MwFightSim.Fighter).player.flags & MwRinkState.Player.IN_BOX, 0)


func test_card() -> void:
	if not need_rom():
		return
	var f := _time_up(3, 1)
	var t0 := s.tick
	_to_card(f)
	# the panel 21 passes (stepped twice; it stops the pass after reaching 26),
	# the result 90 ticks, the calls' pass
	assert_eq(s.tick - t0, 21 + 90 + 1)
	assert_true(f.joke >= 0 and f.joke <= 3)
	assert_eq(f.card_left, 480)
	var maps := f.window_ops.filter(func(o: Array) -> bool: return o[0] == "map")
	var rows := 0
	for m in maps:
		rows += int(m[4])
	assert_eq(rows, 28, "the card's 28 rows")
	assert_eq(f.sprite_ops.size(), 2, "the fighters stay in the sprite table")
	for i in 60:
		assert_eq(_run(f, 2, NONE, _pad(2, 0x10)), -1, "no way out in the first 120 ticks")
	assert_eq(_run(f, 2, NONE, _pad(3, 0x10)), 17, "then B on any pad")
	assert_eq(s.projection, 0, "the side view off")


func test_card_runs_out() -> void:
	if not need_rom():
		return
	var f := _time_up(0, 0)
	_to_card(f)
	var n := 0
	while _run(f, 3) < 0 and n < 400:
		n += 1
	assert_eq(n, 160, "480 ticks")


func test_card_joke_values() -> void:
	if not need_rom():
		return
	var f := _time_up(9, 3)
	_to_card(f)
	var a := f.fighters[0]
	var b := f.fighters[1]
	var counts := f.window_ops.filter(func(o: Array) -> bool: return o[0] == "glyph" and int(o[3]) == 0x12)
	assert_eq(counts.size(), 2, "a count per fighter on row 18")
	match f.joke:
		1:
			assert_eq(int(f.window_ops[f.window_ops.find(counts[1]) + 1][4]), 0x32, "black eyes: team A landed 9")
		2:
			assert_eq(int(f.window_ops[f.window_ops.find(counts[1]) + 1][4]), 0x31, "bruised ego: the loser's")
	assert_eq(f.window_ops.filter(func(o: Array) -> bool: return o[0] == "glyph" and int(o[3]) == 0xF and int(o[2]) == 0x14).size(), 1)
	assert_true(a.landed == 9 and b.landed == 3)
