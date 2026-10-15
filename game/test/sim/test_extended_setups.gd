extends "res://test/rom/rom_test_base.gd"
## Plan 34, work item 8: extended set-ups - matches with more players than
## the original's pad modes allow (a team with 3-6 players, team B only,
## 1 v 2). Each playing human is a match pad of their own (player n: pad
## n - 1); a team keeps up to six pad slots (MwRinkState.Team.port_pads)
## and each player object the pad of the human driving it, beside the
## original's two slot bytes (the nearest mode's). The readers of section
## 6's table: the team set-up (markers, arrows, plates), the line-up, human
## control, switches and pick-ups, the pause, the speech skip, the fight,
## the message scoreboard, the special plays, the password; the draw pass's
## markers in the players' colours; the replays; whole matches with a bot
## on every player's pad. The original's set-ups keep the original's code
## paths: the comparison suites (sim, pass and screen checks) prove it.

const NONE := [0, 0, 0, 0]
const RIGHT := 0x08
const B := 0x10
const C := 0x20
const A := 0x40
const START := 0x80

var sim: MwRinkSim
var s: MwRinkState
var update: MwRinkUpdate
var phases: MwRinkPhases


## CPU players that stay put (plan 40: test/support/idle_cpu.gd).
const Idle := preload("res://test/support/idle_cpu.gd")


## Players: team A's numbers [param a], team B's [param b].
static func _humans(a: Array, b: Array) -> MwHumans:
	var humans := MwHumans.new()
	for p in a:
		humans.set_team(p, 0)
	for p in b:
		humans.set_team(p, 1)
	return humans


## A match of teams 9 and 4 at stadium 4 for [param humans]'s players, lined up
## for the opening faceoff (phase handler entry 4); [param ai]: the CPU's
## AI (else CPU players stand still).
func _match(humans: MwHumans, ai := false, reserves := false) -> MwRinkState:
	s = MwRinkState.new()
	s.rng = MlhRng.new(1234)
	sim = MwRinkSim.new(rom, s)
	sim.cpu = MwRinkAI.new() if ai else Idle.new()
	update = MwRinkUpdate.new(sim)
	phases = MwRinkPhases.new(update)
	var su := MwMatchSetup.from_rom(rom, MwMatchSetup.BOOT_DEFAULTS)
	su.team_a = 9
	su.team_b = 4
	su.stadium = 4
	su.reserves = 1 if reserves else 0
	su.period_minutes = 3
	humans.apply_to(su)
	su.extended = humans.match_pads()             # the rink's entry's (plan 40, S13: MwSelection.for_the_rink)
	MwRink.enter_match(sim, phases, su, true, null, false, 4)
	return s


## One 2-tick rink pass with match pad bytes [param held] / [param new]
## ({pad: byte}); returns the phase handler's exit (-1 none).
func _rink_pass(held := {}, new := {}) -> int:
	s.tick += 2
	update.pass_start(2)
	for p in s.pads_held.size():
		s.pads_held[p] = int(held.get(p, 0))
		s.pads_new[p] = int(new.get(p, 0))
	sim.run(2)
	update.after_segment(2)
	var to := phases.pass_end(2)
	if to < 0 and not phases.paused:
		update.draws([], MwRinkPhases.RULES_DRAWN, phases.overlays, phases.sprite_ops)
	return to


func _until_play() -> void:
	for i in 2000:
		if s.phase == MwRinkState.PHASE_PLAY:
			return
		# Start skips the coaches' speeches (any of a team's players)
		_rink_pass({}, {} if i % 20 else _all_pads(B))


func _all_pads(bits: int) -> Dictionary:
	var out := {}
	for team in s.teams:
		for p in team.port_pads:
			out[p] = bits
	return out


func _driver(pad: int) -> MwRinkState.Player:
	for team in s.teams:
		for p in team.players:
			if p.present and p.flags & MwRinkState.Player.HUMAN and p.pad == pad:
				return p
	return null


## Every match pad drives at most one player, of its own team; every
## human-driven player has its team's pad.
func _invariants(what: String) -> bool:
	var seen := {}
	for t in 2:
		for p in s.teams[t].players:
			if not p.present or not p.flags & MwRinkState.Player.HUMAN:
				continue
			if not p.pad in s.teams[t].port_pads:
				fail_test("%s: team %d's player %d driven by pad %d, not one of its own" % [what, t, p.index, p.pad])
				return false
			if seen.has(p.pad):
				fail_test("%s: pad %d drives two players" % [what, p.pad])
				return false
			seen[p.pad] = true
	return true


# --- MwHumans: the players and the pads -------------------------------------------------------------

func test_the_nearest_mode_keeps_team_bs_pad() -> void:
	var want := {Vector2i(3, 0): 2, Vector2i(6, 0): 2, Vector2i(0, 1): 4, Vector2i(0, 2): 4, Vector2i(1, 2): 1,
			Vector2i(1, 6): 1, Vector2i(3, 1): 3, Vector2i(3, 3): 4, Vector2i(4, 2): 4, Vector2i(6, 6): 4}
	for k: Vector2i in want:
		var players := MwHumans.new()
		for i in k.x:
			players.set_team(i + 1, 0)
		for i in k.y:
			players.set_team(7 + i, 1)
		assert_false(players.original(), "%s is extended" % k)
		assert_eq(players.nearest_mode(), want[k], "%s: the nearest mode" % k)
	for a in 7:
		for b in 7:
			var humans := MwHumans.new()
			for i in a:
				humans.set_team(i + 1, 0)
			for i in b:
				humans.set_team(7 + i, 1)
			var mode := humans.nearest_mode()
			assert_eq(mode != 0 and mode != 2 and mode != 5, b > 0,
					"%d v %d: the mode says whether team B has players (the password's swap)" % [a, b])


func test_each_player_is_their_own_match_pad() -> void:
	if not need_rom():
		return
	var players := _humans([3, 9, 12], [5])
	assert_eq(players.pad_index(9), 8, "player n: pad n - 1")
	assert_eq(players.pad_index(1), -1, "not playing")
	assert_eq(players.match_pads(), [PackedInt32Array([2, 8, 11]), PackedInt32Array([4])])
	assert_true(MwHumans.identity(players.pad_players(rom)), "nothing remapped")
	var su := MwMatchSetup.new()
	players.apply_to(su)
	assert_eq(su.pads, 3, "the nearest mode (2 v 1)")
	assert_eq(su.extended, [], "the players hold their pads (plan 40, S13)")
	var ses := MwSession.new(1, 1)
	ses.humans = players
	MwSelection.for_the_rink(ses, su)
	assert_eq(su.extended, players.match_pads(), "the rink's entry gives them to the match")
	assert_eq(su.copy().extended, su.extended, "copies keep them")
	var humans := _humans([4], [6])
	humans.apply_to(su)
	ses.humans = humans
	MwSelection.for_the_rink(ses, su)
	assert_eq(su.pads, 1)
	assert_eq(su.extended, [], "an original set-up: its pad mode alone")


## The set-ups the original could have had: the players give back the pad
## mode and nothing else - the match is the one the pad mode makes.
func test_original_set_ups_play_the_original_match() -> void:
	if not need_rom():
		return
	for mode in 6:
		var humans := MwHumans.from_pad_mode(rom, mode)
		var states := []
		for direct in [false, true]:
			var state := MwRinkState.new()
			state.rng = MlhRng.new(99)
			var rink_sim := MwRinkSim.new(rom, state)
			rink_sim.cpu = MwRinkAI.new()
			var up := MwRinkUpdate.new(rink_sim)
			var ph := MwRinkPhases.new(up)
			var su := MwMatchSetup.from_rom(rom, MwMatchSetup.BOOT_DEFAULTS)
			if direct:
				su.pads = mode
			else:
				humans.apply_to(su)
				assert_eq(su.pads, mode, "mode %d derived" % mode)
				assert_eq(su.extended, [], "mode %d: no extended players" % mode)
			MwRink.enter_match(rink_sim, ph, su, true, null, false, 4)
			for i in 200:
				if up.run_pass(2, ph, func() -> void: state.pads_new[0] = 0x10 if i % 25 == 0 else 0) >= 0:
					break
			assert_false(state.extended)
			states.append(MwSimDict.to_dict(state))
		assert_eq(MwSimDict.diff(states[0], states[1]), {}, "mode %d: the pad mode's match, byte for byte" % mode)


func test_the_router_remaps_the_sticks_with_the_buttons() -> void:
	var sticks := []
	for p in 12:
		sticks.append(Vector2i(p + 1, 0))
	var got := MwHumans.by_pad(sticks, PackedInt32Array([5, 2, 0, 4]), Vector2i.ZERO)
	assert_eq(got.slice(0, 4), [Vector2i(5, 0), Vector2i(2, 0), Vector2i.ZERO, Vector2i(4, 0)],
			"pad k: its player's stick")
	assert_eq(got[6], Vector2i.ZERO, "past pad 4: none")
	assert_eq(MwHumans.by_pad([], PackedInt32Array([5, 2, 3, 4]), Vector2i.ZERO), [])


## The shot heights (MwSettings.shot_heights) go with the buttons as the
## sticks do; a pad without a player has the D-pad's (-1).
func test_the_router_remaps_the_shot_heights_with_the_buttons() -> void:
	var heights := [1, 2, 0, -1, 2, 1, 0, 0, 0, 0, 0, 2]
	var got := MwHumans.by_pad(heights, PackedInt32Array([5, 2, 0, 12]), -1)
	assert_eq(got.slice(0, 4), [2, 2, -1, 2], "pad k: its player's height")
	assert_eq(got[6], -1, "past pad 4: the D-pad's")
	assert_eq(MwHumans.by_pad([], PackedInt32Array([5, 2, 3, 4]), -1), [])


# --- the team set-up and the line-up ------------------------------------------------------------------

func test_team_set_up() -> void:
	if not need_rom():
		return
	_match(_humans([1, 5, 9, 11], [2, 7]))
	assert_true(s.extended)
	assert_eq(s.pads_held.size(), 12, "twelve match pads")
	assert_eq(s.plates.size(), MwRinkState.PLATES_EXTENDED)
	var team_a := s.teams[0]
	var team := s.teams[1]
	assert_eq(team_a.port_pads, PackedInt32Array([0, 4, 8, 10]))
	assert_eq(team.port_pads, PackedInt32Array([1, 6]))
	var mode := 4 * 4                       # 4 v 2: mode 4's slots
	assert_eq(team_a.pads, [rom[MwRinkMatch.PAD_MODES + mode], rom[MwRinkMatch.PAD_MODES + mode + 1]],
			"the original's slot bytes: the nearest mode's (2 v 2)")
	assert_eq(team.pads, [rom[MwRinkMatch.PAD_MODES + mode + 2], rom[MwRinkMatch.PAD_MODES + mode + 3]])
	assert_ne(team_a.flags4 & 4, 0, "has players")
	assert_eq(team_a.markers.size(), 5, "a marker per player and the CPU carrier's")
	assert_eq(team_a.arrows.size(), 4)
	for k in 4:
		assert_eq(team_a.markers[k].plate, team_a.port_pads[k], "a player's plate: their pad's")
	assert_eq(team_a.markers[4].plate, MwRinkState.CARRIER_PLATE, "the carrier's own")
	assert_eq(team.markers[2].plate, MwRinkState.CARRIER_PLATE + 1)
	assert_eq(team_a.arrows[0].address, MwGfx.u32(rom, MwRinkMatch.ARROWS), "player 1: pad 1's arrow")
	assert_eq(team.arrows[0].address, MwGfx.u32(rom, MwRinkMatch.ARROWS + 4), "player 2: pad 2's")
	assert_eq(team_a.arrows[1].address, MwGfx.u32(rom, MwRinkMatch.ARROWS), "player 5: pad 1's shape (in their colour)")


func test_a_team_without_players() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], []))
	var team := s.teams[1]
	assert_eq(team.port_pads.size(), 0)
	assert_eq(team.flags4 & 4, 0, "team B: the CPU's")
	assert_eq(team.markers[0].plate, MwRinkState.CARRIER_PLATE + 1, "its carrier's marker on its own plate")
	_match(_humans([], [6, 8]))
	assert_eq(s.teams[0].flags4 & 4, 0, "team B only: team A has no pad, whatever the nearest mode's slots")
	assert_ne(s.teams[1].flags4 & 4, 0)


func test_the_line_up_puts_the_players_on_c_lw_rw_ld_rd_in_number_order() -> void:
	if not need_rom():
		return
	_match(_humans([2, 4, 6, 8, 10], [1, 3, 5, 7, 9, 11]))
	for t in 2:
		var team := s.teams[t]
		for p in team.players:
			var k := p.position
			if k < team.port_pads.size():
				assert_ne(p.flags & MwRinkState.Player.HUMAN, 0, "team %d position %d driven" % [t, k])
				assert_eq(p.pad, team.port_pads[k], "team %d position %d: the %d-th lowest number" % [t, k, k + 1])
			else:
				assert_eq(p.flags & MwRinkState.Player.HUMAN, 0, "team %d position %d: the CPU's" % [t, k])
	assert_eq(s.teams[1].goalie().pad, 10, "a sixth player in goal")
	assert_true(_invariants("line-up"))


func test_the_line_up_draws_no_random_number() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4, 5]))
	var before := s.rng.state
	MwRinkMatch.lineup_players(s.teams[0])
	assert_eq(s.rng.state, before)
	# the same line-up twice gives the same drivers
	var first := []
	for p in s.teams[0].players:
		first.append(p.pad if p.flags & MwRinkState.Player.HUMAN else -1)
	MwRinkMatch.lineup(sim, s.teams[0], 0, 0)
	var again := []
	for p in s.teams[0].players:
		again.append(p.pad if p.flags & MwRinkState.Player.HUMAN else -1)
	assert_eq(again, first)


# --- human control ------------------------------------------------------------------------------------

func test_each_player_steers_their_own_skater() -> void:
	if not need_rom():
		return
	_match(_humans([1, 7, 12], [3]))
	_until_play()
	assert_eq(s.phase, MwRinkState.PHASE_PLAY)
	var p7 := _driver(6)
	assert_not_null(p7)
	var x7 := p7.motion.pixels().x
	for i in 20:
		_rink_pass({6: RIGHT})
	assert_gt(p7.motion.pixels().x, x7 + 10, "player 7's Right moves the skater they drive")
	assert_eq(sim.human.pad_held(p7, s.teams[0]), RIGHT, "the pad from the player's pad field")
	assert_eq(s.teams[0].pad_held[s.teams[0].control_slot(p7)], RIGHT, "the team's copy in the player's slot")
	assert_true(_invariants("play"))


## Plan 34 with the shot heights: each of the twelve match pads has its
## height (MwRinkState.pad_heights grows with the pads), the shooter's is
## his own pad's (MwHumanControl.height by pad_index), and an away player's
## pad has none.
func test_each_player_shoots_at_their_own_pads_height() -> void:
	if not need_rom():
		return
	_match(_humans([1, 7, 12], [3]))
	_until_play()
	assert_eq(s.pad_heights.size(), 12, "a height per match pad")
	var p12 := _driver(11)
	assert_not_null(p12)
	var team := sim.team_of(p12)
	s.pad_heights[11] = 2
	s.pad_heights[3] = 1                    # pad 12 & 3: not his
	assert_eq(sim.human.height(p12, team), 2, "player 12's pad, not pad 4's")
	s.pad_heights[11] = -1
	assert_eq(sim.human.height(p12, team), -1, "the D-pad's")


func test_a_switch_takes_the_players_pad_along() -> void:
	if not need_rom():
		return
	_match(_humans([1, 7, 12], [3]))
	_until_play()
	var p7 := _driver(6)
	var team := s.teams[0]
	var other: MwRinkState.Player = null
	for q in team.players:
		if q.present and not q.flags & MwRinkState.Player.HUMAN and q.position != 5:
			other = q
	sim.human._switch(p7, other)
	assert_eq(other.pad, 6)
	assert_ne(other.flags & MwRinkState.Player.HUMAN, 0)
	assert_eq(p7.flags & MwRinkState.Player.HUMAN, 0)
	assert_eq(_driver(6), other)
	assert_true(_invariants("switch"))


func test_pick_ups_take_turns_among_the_players() -> void:
	if not need_rom():
		return
	_match(_humans([1, 7, 12], [3]))
	var team := s.teams[0]
	var cpu: MwRinkState.Player = null
	for q in team.players:
		if q.present and not q.flags & MwRinkState.Player.HUMAN:
			cpu = q
			break
	s.puck.carrier = null
	var got := []
	for i in 4:
		var player := sim.human.pickup_switch(cpu, team)
		got.append(player.pad if player else -1)
	assert_eq(got, [0, 6, 11, 0], "each player in turn")


# --- the match flow: pause, the speech skip -------------------------------------------------------------

func test_any_player_pauses_for_their_team() -> void:
	if not need_rom():
		return
	_match(_humans([1, 7, 8], [3, 12]))
	_until_play()
	var to := _rink_pass({}, {11: START})
	assert_eq(to, MwRinkPhases.PAUSED)
	assert_eq(s.pause_pad, 2 * 11, "player 12's pad")
	assert_eq(s.pause_team, MwRinkPhases.TEAM_WORDS[1], "for team B")
	if not phases.menu.is_empty():
		assert_eq(int(phases.menu["player"]), 12, "the port's menu: player 12's")


func test_the_speech_skip_by_any_of_the_teams_players() -> void:
	if not need_rom():
		return
	_match(_humans([1, 7, 12], []))
	assert_false(phases._skips(s.teams[1]), "no players: no skip")
	s.pads_new[11] = B
	assert_true(phases._skips(s.teams[0]), "player 12's B")
	s.pads_new[11] = 0
	s.pads_held[6] = START
	assert_true(phases._skips(s.teams[0]), "player 7's Start held")
	s.pads_held[6] = 0
	s.pads_new[2] = START
	assert_false(phases._skips(s.teams[0]), "player 3 isn't on the team")


## Team B only: team A's coach (the CPU's: team A always speaks at a
## period start) is team B's players' to skip - nothing waits on a team
## without players.
func test_team_b_only_skips_team_as_coach() -> void:
	if not need_rom():
		return
	_match(_humans([], [5, 6]))
	for i in 600:
		if s.phase == MwRinkState.PHASE_START and s.subphase == 1:
			break
		_rink_pass()
	assert_eq([s.phase, s.subphase, s.speaker], [MwRinkState.PHASE_START, 1, 0], "team A's coach speaks")
	_rink_pass({}, {0: B})
	assert_eq(s.speaker, 0, "player 1 (not playing): nothing")
	_rink_pass({}, {5: B})
	assert_eq([s.subphase, s.speaker], [1, 1], "player 6 skips it: team B's coach now")


# --- the screens between plays ----------------------------------------------------------------------------

func _pads12(pad: int, bits: int) -> Array:
	var a := []
	a.resize(12)
	a.fill(0)
	a[pad] = bits
	return a


func test_the_fight_goes_to_the_fighters_driver_or_the_teams_lowest_number() -> void:
	if not need_rom():
		return
	_match(_humans([4, 9, 10], [11]))
	var team := s.teams[1]
	var driven := _driver(8)
	driven.flags |= MwRinkState.Player.FIGHTING
	var cpu_b: MwRinkState.Player = null
	for q in team.players:
		if q.present and not q.flags & MwRinkState.Player.HUMAN and q.position != 5:
			cpu_b = q
			break
	cpu_b.flags |= MwRinkState.Player.FIGHTING
	s.phase = 4
	s.tick = 1000
	var fight := MwFightSim.new(rom)
	fight.enter(s, 18, 5)
	assert_eq(fight.fighters[0].pad, 2 * 8, "team A's fighter: player 9 drives him")
	assert_eq(fight.fighters[1].pad, 2 * 10, "team B's CPU-driven fighter: its lowest number (player 11)")
	s.tick += 1
	fight.begin_pass()
	fight.step(1, _pads12(10, START), _pads12(10, START))
	assert_eq(fight._pad_word(fight.fighters[1], fight.fighters[0]) & 0xFF, START, "player 11's pad read")


func test_the_fouled_teams_lowest_number_skips_the_messages() -> void:
	if not need_rom():
		return
	_match(_humans([2], [7, 5]))
	MwRinkPenalties.set_flags(s.teams[0], MwRinkPenalties.STOP)
	assert_eq(MwMessageScoreboardSim._fouled_pad(s.teams[1], s.teams[0], 0), 4, "team B's lowest: player 5")
	assert_eq(MwMessageScoreboardSim._fouled_pad(s.teams[0], s.teams[1], 9), 9, "the other team's box didn't stop play")


## The referee's message (a new referee, a forfeit) waits for Start on the
## original's pad 1 (team A's first): team A's lowest number, or team B's
## with team B only - never a player who isn't playing.
func test_the_referee_message_waits_on_the_lowest_number() -> void:
	if not need_rom():
		return
	_match(_humans([7, 5, 6], [9]))
	assert_eq(MwMessageScoreboardSim._first_pad(s), 4, "team A's lowest: player 5")
	_match(_humans([], [7, 5]))
	assert_eq(MwMessageScoreboardSim._first_pad(s), 4, "team B only: its lowest (player 5)")
	s.phase = MwRinkState.PHASE_REF
	s.scoring = 0xFFFF0000 | int(MwScoreboardSim.TEAM_WORDS[1])
	s.tick = 1000
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 19)
	for e in [1, 180]:
		s.tick += e
		sb.begin_pass()
		assert_eq(sb.step(e, _pads12(0, START), _pads12(0, START)), -1, "player 1 (not playing): nothing")
	s.tick += 1
	sb.begin_pass()
	assert_eq(sb.step(1, _pads12(4, START), _pads12(4, START)), 5, "player 5's Start: a new referee")


func test_the_scoreboards_menus_take_any_players_pad() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [9]))
	var held := _pads12(0, 0)
	var new := _pads12(10, A)
	assert_eq(MwScreenSim.pads_word(held, new) & 0xFF, A, "player 11's A among the twelve")
	MwScoreboardSim.read_pads(s, held, new)
	assert_eq(s.pads_new[10], A)


func _special(humans: MwHumans) -> MwSpecialPlaysSim:
	_match(humans, false, true)
	s.period = 1
	s.tick = 1000
	var sp := MwSpecialPlaysSim.new(rom)
	sp.enter(s, 10, 4)
	return sp


func test_special_plays_pages_by_who_has_players() -> void:
	if not need_rom():
		return
	var sp := _special(_humans([1, 2, 3], []))
	assert_eq(MwSpecialPlaysSim.layout_mode(s), 0, "one team with players: one page plays")
	assert_eq(sp.pages[0].done, 0)
	assert_eq(sp.pages[1].handler, MwSpecialPlaysSim.IDLE_PASS, "team B idles")
	sp = _special(_humans([1], [2, 3]))
	assert_eq(MwSpecialPlaysSim.layout_mode(s), 1, "both play")
	assert_eq(sp.pages[1].done, 0)
	assert_eq(sp.pages[1].row, 0xD)
	sp = _special(_humans([], [5, 6]))
	assert_eq(sp.live_page, 1, "team B only: page B plays ...")
	assert_eq(sp.pages[1].row, 0, "... in page A's rows")
	assert_eq(sp.pages[0].handler, MwSpecialPlaysSim.IDLE_PASS, "page A idles")
	assert_eq(sp.pages[0].done, 1)
	s.tick += 3
	sp.begin_pass()
	sp.step(3, NONE, NONE)
	var shown := sp.sprite_ops.filter(func(o: Array) -> bool: return o[0] == "anim" and int(o[5]) == 0xA4) \
			.map(func(o: Array) -> int: return int(o[7]))
	assert_true(shown.size() > 0 and shown.all(func(attr: int) -> bool: return attr == sp.pages[1].attr),
			"the idle page shows team B's players")


func test_special_plays_pages_read_their_teams_players() -> void:
	if not need_rom():
		return
	var sp := _special(_humans([], [5, 6]))
	var cursor := sp.pages[1].cursor
	s.tick += 3
	sp.begin_pass()
	sp.step(3, _pads12(5, 0x02), _pads12(5, 0x02))
	assert_ne(sp.pages[1].cursor, cursor, "player 6's Down moves page B's cursor")
	cursor = sp.pages[1].cursor
	s.tick += 3
	sp.begin_pass()
	sp.step(3, _pads12(0, 0x02), _pads12(0, 0x02))
	assert_eq(sp.pages[1].cursor, cursor, "player 1 (not playing) doesn't")


func test_the_password_swaps_when_team_b_has_players() -> void:
	if not need_rom():
		return
	for h in [_humans([1, 2, 3], []), _humans([1], [2, 3]), _humans([], [4]), _humans([1, 2, 3], [4])]:
		var po := MwPlayoffs.new()
		po.round = 0
		po.series = 0
		po.flag_11 = 1
		var with_b: bool = h.count(1) > 0
		var pw := po.make_password(rom, 0x111, 0x222, h.nearest_mode())
		assert_eq(po.dead[0], 0x222 if with_b else 0x111, "%s: swapped when team B has players" % str(h.teams))
		assert_gt(pw.size(), 0)


# --- markers, plates, arrows: the draw pass -----------------------------------------------------------------

func test_markers_in_the_players_colours() -> void:
	if not need_rom():
		return
	_match(_humans([1, 5, 9], [2, 12]))
	_until_play()
	_rink_pass()
	var drawer := update.drawer
	var crossbones := {}
	var plates := {}
	var tags := {}
	for c in drawer.port_calls:
		var frame: int = c[4]
		var attr: int = c[3]
		if frame == MwGfx.u32(rom, MwRinkDraw.CROSSBONES + 4) or frame == MwGfx.u32(rom, MwRinkDraw.CROSSBONES + 8):
			crossbones[MwRinkDraw.line_of(attr)] = frame
		elif frame >= MwRinkDraw.PLATES and frame < MwRinkDraw.PLATES + 32:
			var tile := MwRinkDraw.tile_of(MwGfx.frame_pieces(rom, frame)[0]["tile"], attr)
			var slot := (tile - MwRinkDraw.PLATE_TILES) / 8
			if slot >= MwPlate.TAG_SLOT:
				tags[slot - MwPlate.TAG_SLOT] = MwRinkDraw.line_of(attr)
			else:
				plates[slot] = true
	assert_eq(crossbones.get(3), MwGfx.u32(rom, MwRinkDraw.CROSSBONES + 8), "player 2: pad 2's crossbones (line 3)")
	for pad in [4, 8, 11]:
		assert_true(crossbones.has(pad), "player %d: pad 1's crossbones on their own line %d" % [pad + 1, pad])
	for pad in [0, 1, 4, 8, 11]:
		assert_true(plates.has(pad), "player %d's plate" % [pad + 1])
		assert_eq(tags.get(pad), pad if pad >= 4 else 3, "player %d's number tag, in their colour" % [pad + 1])
	assert_eq(drawer.calls.filter(func(c: Array) -> bool: return int(c[2]) == MwRinkDraw.DEPTH_MARKER).size(), 0,
			"no marker among the original's draws (the replay ring's)")
	var entries := update.sprites.filter(func(e: Array) -> bool: return int(e[3]) >= MwRinkDraw.PORT_LINE)
	assert_gt(entries.size(), 0, "the sprite list keeps the players' lines")


func test_the_palettes_player_lines() -> void:
	if not need_rom():
		return
	var plain := RomPalette.make(4, PackedStringArray(["screen_palette", "rom 1BD8A 3"]))
	var palette := RomPalette.make(4, PackedStringArray(["screen_palette", "rom 1BD8A 3", "player_lines"]))
	var c := palette.colours()
	assert_eq(c.size(), 192)
	assert_eq(c.slice(0, 64), plain.colours(), "the original's four lines as they are")
	var face := MwPlayerColours.face_index(rom, 1)
	for player in range(5, 13):
		var line := c.slice(16 * (player - 1), 16 * player)
		assert_eq(line[face], MwPlayerColours.face(rom, player), "player %d's colour in the face index" % player)
		for i in 16:
			if i != face:
				assert_eq(line[i], c[48 + i], "the rest is line 3")
	assert_eq(MwPalettes.texture(c).get_width(), 192)
	assert_eq(MwRinkDraw.player_attr(2), 0x60, "players 1-4: line 3")
	assert_eq(MwRinkDraw.line_of(MwRinkDraw.player_attr(9)), 9, "player 10: line 9")
	assert_eq(MwRinkDraw.line_of(0x40), 2, "the original's lines as they are")


func test_number_tags() -> void:
	if not need_rom():
		return
	var t12 := MwPlate.tag_tiles(rom, 12)
	var t7 := MwPlate.tag_tiles(rom, 7)
	assert_eq(t12.size(), 256)
	assert_ne(t12.slice(0, 32), t12.slice(64, 96), "two digits")
	assert_eq(t7.slice(64, 96).count(0), 32, "one digit")
	var face := MwPlayerColours.face_index(rom, 1)
	var found := false
	for b in t7:
		if b >> 4 == face or b & 15 == face:
			found = true
	assert_true(found, "the outline in the face index")
	var ext := MwRinkState.new()
	ext.extend(rom, 0, PackedInt32Array([0]))
	var tiles := MwPlate.ram_tiles(rom, ext.plates)
	assert_false(MwPlate.ram_tiles(rom, MwRinkState.new().plates).has(MwRinkDraw.PLATE_TILES + 8 * MwPlate.TAG_SLOT),
			"no tags with the original's four")
	assert_true(tiles.has(MwRinkDraw.PLATE_TILES + 8 * (MwPlate.TAG_SLOT + 11)), "the tags with fourteen plates")


func test_the_sprite_layer_draws_a_players_line() -> void:
	if not need_rom():
		return
	var layer := MwSpriteLayer.new()
	add_child_autofree(layer)
	layer.palette = RomPalette.make(4, PackedStringArray(["screen_palette", "rom 1BD8A 3", "player_lines"]))
	var piece := MwGfx.u32(rom, MwRinkDraw.CROSSBONES + 4) + 2
	var entry := MwRinkDraw.piece_entry(rom, 200, 200, 3, MwRinkDraw.player_attr(6), piece)
	assert_eq(MwRinkDraw.line_of(int(entry[3])), 6)
	layer.show_list([entry])
	var px := layer._pixel_cache.get(Vector3i(int(entry[4]), int(entry[2]), 6), PackedByteArray()) as PackedByteArray
	assert_gt(px.size(), 0)
	var lines := {}
	for v in px:
		if v != 0:
			lines[v >> 4] = true
	assert_eq(lines.keys(), [6], "its pixels on line 6")


func test_the_3d_views_frames_take_the_players_lines_and_plates() -> void:
	if not need_rom():
		return
	var sp := MwSprites3D.new()
	var cross := MwGfx.u32(rom, MwRinkDraw.CROSSBONES + 4)
	var f := sp.frame_texture(rom, cross, MwRinkDraw.player_attr(7))
	var lines := {}
	for v in (f["tex"] as ImageTexture).get_image().get_data():
		if v != 0:
			lines[v >> 4] = true
	assert_eq(lines.keys(), [7], "player 8's crossbones on line 7")
	assert_ne(f["key"], sp.frame_texture(rom, cross, 0x60)["key"], "not the line-3 frame's cache entry")
	var clipped := sp.frame_texture(rom, cross, MwRinkDraw.player_attr(7), 0)
	assert_eq(clipped["key"], str(f["key"]) + ":c0", "plan 37's clip (MwSplatter's drops) keyed beside the line")
	var ext := MwRinkState.new()
	ext.extend(rom, 0, PackedInt32Array([9]))
	ext.plates[9] = [42, 2, 0xFF]
	sp.ram_tiles = MwPlate.ram_tiles(rom, ext.plates)
	var plate := sp.frame_texture(rom, MwRinkDraw.PLATES + 8 * (9 & 3), 0x60 | (9 >> 2) * MwRinkDraw.PORT_BANK)
	var want := MwPlate.tiles(rom, 42, 2, 0xFF)
	var got := (plate["tex"] as ImageTexture).get_image().get_data()
	var lit := 0
	for v in got:
		if v != 0:
			lit += 1
	assert_gt(lit, 0, "plate slot 9's tiles (a bank further) drawn")
	assert_eq(lit, 2 * (want.size() - want.count(0)) - _half_zero(want), "its pixels: those values'")
	sp.free()


## Pixels of [param b] (4 bits each) that are 0 in bytes not all 0.
static func _half_zero(b: PackedByteArray) -> int:
	var n := 0
	for v in b:
		if v != 0 and (v >> 4 == 0 or v & 15 == 0):
			n += 1
	return n


# --- replays ------------------------------------------------------------------------------------------------

func test_replays_keep_every_marker() -> void:
	if not need_rom():
		return
	_match(_humans([1, 5, 9], [2, 12]), true)
	s.full_replay = MwFullReplay.new()
	_until_play()
	for i in 30:
		_rink_pass()
	assert_gt(s.full_replay.size(), 10)
	var side := s.full_replay.side(s.full_replay.size() - 1)
	var marks: Array = side.get("marks", [])
	assert_gt(marks.size(), 10, "the frame's side-record: every marker, plate and tag")
	assert_eq((side.get("plates", []) as Array).size(), MwRinkState.PLATES_EXTENDED)
	# the ring's frames: the original's two markers a team, as the original writes them
	var w := s.full_replay.words(s.full_replay.size() - 1)
	var n := w.size()
	assert_gt(n, 2 + 2 + 2 * 3 * 2)
	# played back: the frame's marks drawn with their lines, the plates written
	var pb := MwFullReplayPlayback.new(s, rom, s.full_replay)
	pb.start_first(0)
	assert_eq((pb.shown.get("marks", []) as Array).size() > 0, true)
	var rs := MwReplaySim.new(rom)
	rs.saved = s.full_replay
	rs.enter(s, 7, 4)
	var ops := rs.sprite_ops.filter(func(o: Array) -> bool: return o[0] == "piece" \
			and int(o[4]) >= MwRinkDraw.PORT_LINE)
	assert_gt(ops.size(), 0, "the replay draws players 5-12's markers in their colours")


func test_an_extended_match_saved_and_opened() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3, 4, 5, 6], [7, 8, 9, 10, 11, 12]), true)
	var back := MwSimDict.from_dict(MwSimDict.to_dict(s))
	assert_true(back.extended)
	assert_eq(back.teams[0].markers.size(), 7, "markers grown as they were")
	assert_eq(back.teams[1].arrows.size(), 6)
	assert_eq(back.teams[1].port_pads, s.teams[1].port_pads)
	assert_eq(back.teams[1].goalie().pad, 11)


# --- whole matches: a bot on every player's pad ---------------------------------------------------------------

## [param passes] rink passes of [param humans]'s match with a random bot on every
## playing human's pad (no Start), the screens the phase handler leaves for
## counted and the faceoff entered again; the invariants every pass.
func _bot_match(humans: MwHumans, passes: int, seed_value: int) -> Dictionary:
	_match(humans, true)
	s.full_replay = MwFullReplay.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bots := {}
	var exits := {}
	var moved := {}
	var in_play := 0
	for i in passes:
		if s.phase == MwRinkState.PHASE_PLAY:
			in_play += 1
		for side in s.teams:
			for p in side.players:
				if p.present and p.flags & MwRinkState.Player.HUMAN and (p.motion.vel[0] != 0 or p.motion.vel[1] != 0):
					moved[p.pad] = true
		var held := {}
		var new := {}
		for team in s.teams:
			for pad in team.port_pads:
				if not bots.has(pad) or rng.randf() < 0.05:
					bots[pad] = [0, 1, 2, 4, 8, 5, 9, 6, 10][rng.randi_range(0, 8)]
				var b: int = bots[pad]
				if rng.randf() < 0.08:
					b |= [B, C, A][rng.randi_range(0, 2)]
				held[pad] = b
				new[pad] = b & ~0x0F if rng.randf() < 0.5 else 0
		var to := _rink_pass(held, new)
		if to >= 0:
			exits[to] = int(exits.get(to, 0)) + 1
			MwRinkMatch.rink_exit(sim, to)
			if s.period > 3 or to in [15, 16, 17]:
				break
			phases.enter(5)
		if not _invariants("pass %d" % i):
			break
	exits["in_play"] = in_play
	exits["moved"] = moved.size()
	return exits


func test_whole_matches_with_bots() -> void:
	if not need_rom():
		return
	var cases := [[[1, 2, 3], []], [[1, 2, 3, 4, 5, 6], [7, 8, 9, 10, 11, 12]], [[], [4, 9]], [[3], [1, 2]],
			[[1, 2, 3, 4], [5, 6]]]
	for i in cases.size():
		var humans := _humans(cases[i][0], cases[i][1])
		var exits := _bot_match(humans, 700, 17 + i)
		assert_true(s.extended, "%s: extended" % str(humans.teams))
		assert_gt(int(exits["in_play"]), 100, "%s: open play" % str(humans.teams))
		assert_eq(int(exits["moved"]), humans.total(), "%s: every player skated" % str(humans.teams))
		gut.p("%s: exits %s, score %d-%d" % [str(humans.teams), str(exits), s.teams[0].score, s.teams[1].score])
	# CPU v CPU stays the original's
	_match(MwHumans.new(), true)
	assert_false(s.extended, "CPU v CPU: pad mode 5, the original's")
	assert_eq(s.pad_mode, 5)
