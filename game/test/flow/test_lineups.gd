extends "res://test/rom/rom_test_base.gd"
## Plan 34 work items 9-10, the selection steps' rules (MwSelection,
## MwLineup, MwCaptainVote): the gates by setting, the line-ups' candidates
## (the Demon Net never among them), swaps, locks and refusals, the changes
## made at the rink's entry as the Reserves page's own, an untouched line-up
## leaving the match the original's, the captain votes.
## Short names: l the MwLineup under test, v the MwCaptainVote under test.

const DEMON_NET := MwSpecialPlaysSim.DEMON_NET

var _settings := []


func before_each() -> void:
	_settings = [MwSettings.character_select, MwSettings.captain_mode, MwSettings.lineup_select, MwSettings.front_menu]
	MwSettings.front_menu = true


func after_each() -> void:
	MwSettings.character_select = _settings[0]
	MwSettings.captain_mode = _settings[1]
	MwSettings.lineup_select = _settings[2]
	MwSettings.front_menu = _settings[3]


static func humans(a: Array, b: Array) -> MwHumans:
	var who_plays := MwHumans.new()
	for p in a:
		who_plays.set_team(p, 0)
	for p in b:
		who_plays.set_team(p, 1)
	return who_plays


func _session(a: Array, b: Array, mode := "exhibition") -> MwSession:
	var session := MwSession.new(1, 1)
	session.humans = humans(a, b)
	session.local_mode = mode
	return session


# --- the gates -------------------------------------------------------------------------------------

func test_character_selections_gate() -> void:
	MwSettings.character_select = MwSettings.CHARACTER_SELECTS[0]           # 5+ PLAYERS
	assert_true(MwSelection.character_select(humans([1, 2, 3], [4, 5])), "five on teams")
	assert_true(MwSelection.character_select(humans([1, 2, 3, 4, 5, 6], [])), "six on one team")
	assert_false(MwSelection.character_select(humans([1, 2, 3], [4])), "four: the co-op")
	assert_false(MwSelection.character_select(humans([1, 2, 3, 4], [])), "four on one team: the co-op")
	MwSettings.character_select = MwSettings.CHARACTER_SELECTS[1]           # 3+ ON A TEAM
	assert_true(MwSelection.character_select(humans([1, 2, 3], [4])), "a team of three")
	assert_true(MwSelection.character_select(humans([], [1, 2, 3, 4])), "a team of four")
	assert_false(MwSelection.character_select(humans([1, 2], [3, 4])), "two and two")
	assert_false(MwSelection.character_select(humans([1], [])), "one player")
	assert_true(MwSelection.character_select(humans([1, 2], [3, 4, 5])), "five: always")


func test_captain_modes_gate() -> void:
	MwSettings.captain_mode = MwSettings.CAPTAIN_MODES[0]                  # 5+ PLAYERS
	assert_false(MwSelection.captain_mode(_session([1, 2, 3], [4, 5], "exhibition")), "never a local exhibition")
	assert_true(MwSelection.captain_mode(_session([1, 2, 3], [4, 5], "playoffs")), "five in the playoffs")
	assert_false(MwSelection.captain_mode(_session([1, 2], [3, 4], "playoffs")), "four")
	MwSettings.captain_mode = MwSettings.CAPTAIN_MODES[1]                  # 2+ PLAYERS
	assert_true(MwSelection.captain_mode(_session([1, 2], [], "playoffs")), "a 2-player playoff vote")
	assert_false(MwSelection.captain_mode(_session([1], [], "playoffs")), "one player never needs a captain")
	assert_false(MwSelection.captain_mode(_session([1, 2], [3], "exhibition")))
	MwSettings.front_menu = false
	assert_false(MwSelection.captain_mode(_session([1, 2], [3], "playoffs")), "the original's flow: none")


func test_line_ups_gate() -> void:
	var session := _session([1], [])
	session.setup.reserves = 1
	MwSettings.lineup_select = true
	assert_true(MwSelection.lineups_on(session))
	assert_eq(MwSelection.panel_teams(session), [0] as Array[int], "a panel for the team with players")
	MwSettings.lineup_select = false
	assert_false(MwSelection.lineups_on(session), "LINE-UP SELECT off")
	MwSettings.lineup_select = true
	session.setup.reserves = 0
	assert_false(MwSelection.lineups_on(session), "Reserves off")


func test_the_steps_that_apply() -> void:
	MwSettings.character_select = MwSettings.CHARACTER_SELECTS[0]
	MwSettings.captain_mode = MwSettings.CAPTAIN_MODES[1]
	MwSettings.lineup_select = true
	var session := _session([1, 2, 3], [4, 5])
	assert_eq(MwFlow.after_controllers(session), MwScreens.CHARACTER_SELECT, "five: character selection")
	session = _session([1, 2], [3], "playoffs")
	session.humans.positions = {1: 0}
	assert_eq(MwFlow.after_controllers(session), MwScreens.CAPTAIN_VOTE, "a 2+ playoff game: the vote's own screen")
	assert_true(session.humans.positions.is_empty(), "no character selection: nobody owns a position")
	assert_eq(session.humans.captains, [0, 3], "a team of one: its player is captain")
	session = _session([1], [])
	session.setup.reserves = 1
	assert_eq(MwFlow.after_controllers(session), MwScreens.LINEUPS, "Reserves on: the line-up panel alone")
	session = _session([1], [2])
	session.humans.captains = [1, 2]
	session.humans.lineups[0] = PackedInt32Array([0, 1, 2, 3, 4, 11])
	assert_eq(MwFlow.after_controllers(session), 3, "nothing applies: the matchup")
	assert_eq(session.humans.captains, [0, 0], "an exhibition has no captains")
	assert_eq(session.humans.lineups[0], PackedInt32Array(), "line-ups off: the original's starters")
	assert_eq(MwSelection.chosen_lineups(session), [], "and nothing for the rink's entry")
	session = _session([], [])
	session.setup.reserves = 1
	assert_eq(MwFlow.after_controllers(session), 3, "CPU v CPU: no panels")


func test_a_captain_kept_votes_no_more() -> void:
	MwSettings.captain_mode = MwSettings.CAPTAIN_MODES[1]
	var session := _session([1, 2], [3, 4], "playoffs")
	session.humans.captains = [2, 0]
	assert_eq(MwSelection.voting_teams(session), [1] as Array[int], "team A's captain still plays: only B votes")
	session.humans.set_team(2, MwHumans.MIDDLE)
	session.humans.set_team(5, 0)
	assert_eq(MwSelection.voting_teams(session), [0, 1] as Array[int], "the captain doesn't play the next game: a vote")


# --- line-ups -------------------------------------------------------------------------------------------

func test_candidates_are_the_reserves_pages_then_the_others() -> void:
	if not need_rom():
		return
	var l := MwLineup.new(rom, 3, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	for pos in MwLineup.POSITIONS:
		var c := l.candidates(pos)
		for line in 4:
			if l.record(6 * line + pos) != 0:
				assert_eq(c[line], 6 * line + pos, "position %d: each line's player first" % pos)
		if pos == MwLineup.GOALIE:
			assert_eq(c.size(), 4, "goalies only: the lines' four")
			continue
		var rest := c.slice(4)
		for i in rest.size():
			assert_false(MwLineup.is_goalie_slot(rest[i]), "no goalie on the ice")
			assert_ne(rest[i] % 6, pos, "the others: other positions")
			if i > 0:
				assert_true(l.rating(rest[i - 1], pos) >= l.rating(rest[i], pos), "best rating first")
		assert_eq(c.size(), 4 + 16, "every skater")


func test_never_the_demon_net_nor_a_dead_player() -> void:
	if not need_rom():
		return
	for team in MwTeams.COUNT:
		for dead in [0, 0x2A5, 0x3FFFF & ~0x3F]:
			var l := MwLineup.new(rom, team, PackedInt32Array([0, 1, 2, 3, 4, 5]), dead)
			for pos in MwLineup.POSITIONS:
				for slot in l.candidates(pos):
					var r := l.record(slot)
					assert_ne(r, DEMON_NET)
					assert_ne(r, 0)
					assert_eq(dead & (1 << slot), 0, "never a dead player")
					assert_eq(MwLineup.is_goalie_slot(slot), pos == MwLineup.GOALIE,
							"only real goalies in goal, and only there")
					if pos == MwLineup.GOALIE:
						assert_eq(rom[r + 7] & 0xF, 4, "a goalie (team %d)" % team)
			for slot in l.slots:
				assert_ne(l.record(slot), DEMON_NET)
	# the team set-up gives every team the Demon Net (+4 bit 3): the pre-game lists still never have it
	var session := MwSession.new(1, 1)
	var rehearsal := MwMatchRehearsal.run(rom, session.setup, session.rng.state)
	for t in 2:
		assert_ne(rehearsal.state.teams[t].flags4 & 8, 0, "the team holds the Demon Net")
		var l := MwLineup.new(rom, [session.setup.team_a, session.setup.team_b][t], MwLineup.starters_of(rehearsal, t))
		assert_false(DEMON_NET in Array(l.candidates(MwLineup.GOALIE)).map(func(x: int) -> int: return l.record(x)))


func test_dead_starters_are_replaced() -> void:
	if not need_rom():
		return
	var l := MwLineup.new(rom, 0, PackedInt32Array([0, 1, 2, 3, 4, 5]), (1 << 2) | (1 << 5))
	assert_eq(l.slots[2], 8, "RW: the second line's")
	assert_eq(l.slots[5], 11, "G: the second line's goalie")
	assert_true(l.changed(), "the rink's entry makes the change")


func test_swaps_locks_and_refusals() -> void:
	if not need_rom():
		return
	var l := MwLineup.new(rom, 3, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	assert_true(l.place(0, 1), "LW's starter to centre")
	assert_eq(l.slots.slice(0, 2), PackedInt32Array([1, 0]), "swapped with the centre")
	assert_false(l.place(1, 1, [0]), "a locked position's character is refused")
	assert_false(l.place(0, 5), "a goalie never skates")
	assert_false(l.place(5, 0), "nor a skater in goal")
	# stepping passes over a locked one with the refusal
	l = MwLineup.new(rom, 3, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	var c := l.candidates(1)
	var at := c.find(1)
	var next := c[at + 1]
	var holder := l.slots.find(next)
	assert_eq(l.step(1, 1), MwLineup.SOUND_MOVE)
	assert_eq(l.slots[1], next, "Right: the next candidate")
	l.slots[1] = 1
	if holder >= 0:
		assert_eq(l.step(1, 1, [holder]), MwLineup.SOUND_REFUSED, "a locked candidate refused")
		assert_eq(l.slots[1], c[at + 2], "and passed over")
	var lineup := MwLineup.new(rom, 3, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	for i in 4:
		assert_eq(lineup.step(5, 1), MwLineup.SOUND_MOVE)
	assert_eq(lineup.slots[5], 5, "the goalies go round")


# --- at the rink's entry -----------------------------------------------------------------------------

func _entry(su: MwMatchSetup, seed_value: int) -> MwRinkState:
	return MwMatchRehearsal.run(rom, su, seed_value).state


func test_an_untouched_line_up_is_the_originals_match() -> void:
	if not need_rom():
		return
	var session := MwSession.new(7, 1)
	session.setup.team_a = 4
	session.setup.team_b = 11
	var plain := _entry(session.setup, 0x1234567)
	var su := session.setup.copy()
	var l := MwLineup.new(rom, 4, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	su.lineups = [l.slots, PackedInt32Array()]
	var same := _entry(su, 0x1234567)
	assert_eq(MwSimDict.diff(MwSimDict.to_dict(plain), MwSimDict.to_dict(same)), {}, "byte for byte")
	assert_eq(same.rng.state, plain.rng.state, "no random number drawn")


func test_the_changes_are_the_reserves_pages() -> void:
	if not need_rom():
		return
	var su := MwMatchSetup.from_rom(rom, MwMatchSetup.BOOT_DEFAULTS)
	su.team_a = 2
	su.team_b = 9
	su.reserves = 1
	var la := MwLineup.new(rom, 2, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	la.place(0, 1)                        # a swap: C <-> LW
	la.place(3, 9)                        # LD from the second line
	la.place(5, 17)                       # the third goalie
	var lb := MwLineup.new(rom, 9, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	lb.place(2, 20)
	var lineups := [la.slots, lb.slots]
	# ours: MwLineup.apply right after the team set-up
	var ours := MwRinkState.new()
	ours.rng = MlhRng.new(99)
	var sim_a := MwRinkSim.new(rom, ours)
	MwRinkMatch.matchup_setup(sim_a, su.copy(), 0)
	MwLineup.apply(sim_a, lineups)
	# the original's Reserves page making the same changes, card by card
	var state := MwRinkState.new()
	state.rng = MlhRng.new(99)
	var sim_b := MwRinkSim.new(rom, state)
	MwRinkMatch.matchup_setup(sim_b, su.copy(), 0)
	var page_sim := MwSpecialPlaysSim.new(rom)
	page_sim.s = state
	page_sim.rink = sim_b
	page_sim.hooks = RefCounted.new()
	var changes := 0
	for t in 2:
		var team := state.teams[t]
		for k in 6:
			var slot: int = lineups[t][k]
			if team.players[k].slot == slot:
				continue
			var page := MwSpecialPlaysSim.Page.new()
			page.team = team
			page.slot = k
			page.player = team.players[k]
			page.records[3] = MwGfx.u32(rom, team.record + 0x18 + 4 * slot)
			page.cursor = 3
			page_sim._change(page)
			changes += 1
	assert_eq(changes, 5, "five line changes (a swap is two)")
	assert_eq(MwSimDict.diff(MwSimDict.to_dict(ours), MwSimDict.to_dict(state)), {}, "the same state")
	assert_eq(ours.rng.state, state.rng.state, "the same draws")
	for k in 6:
		assert_eq(ours.teams[0].players[k].slot, la.slots[k])


func test_the_rehearsal_shows_the_chosen_starters() -> void:
	if not need_rom():
		return
	var session := MwSession.new(3, 1)
	var l := MwLineup.new(rom, session.setup.team_a, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	l.place(4, 10)
	session.setup.lineups = [l.slots, PackedInt32Array()]
	var rehearsal := MwMatchRehearsal.run(rom, session.setup, session.rng.state, session.playoffs)
	assert_eq(MwLineup.starters_of(rehearsal, 0), l.slots, "the 3D opening's starters are the chosen ones")
	var keys := rehearsal.starters().map(func(st: Dictionary) -> int: return int(st["record"]))
	assert_true(l.record(10) in keys)


func test_the_rinks_entry_makes_them() -> void:
	if not need_rom():
		return
	var host := Node.new()
	add_child_autofree(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(5, 1)
	var su := router.session.setup
	su.reserves = 1                          # line-ups on (MwSelection.lineups_on)
	var was := MwSettings.lineup_select
	MwSettings.lineup_select = true
	var l := MwLineup.new(rom, su.team_a, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	l.place(1, 7)
	# the players' choice: the rink's entry works the line-ups out from it
	# (plan 40, S13: MwSelection.for_the_rink), its rehearsal too
	router.session.humans.lineups[0] = l.slots
	var rehearsal := MwMatchRehearsal.run(rom, MwSelection.for_the_rink(router.session, su.copy()),
			router.session.rng.state, router.session.playoffs)
	router.go(4, {"new_match": true}, false)
	router.step()
	var rk := router.current() as MwRink
	assert_eq(MwSimDict.diff(MwSimDict.to_dict(rk.state), MwSimDict.to_dict(rehearsal.state)), {},
			"the rehearsal is the rink's entry")
	assert_eq(rk.state.teams[0].players[1].slot, 7, "LW from the second line")
	MwSettings.lineup_select = was


# --- the captain vote ----------------------------------------------------------------------------------

func test_the_most_votes_win() -> void:
	var v := MwCaptainVote.new(0, [1, 3, 5], [1, 3, 5])
	assert_true(v.vote(1, 3))
	assert_false(v.all_voted())
	v.vote(3, 3)
	v.vote(5, 1)
	assert_false(v.vote(9, 1), "not a voter")
	assert_eq(v.count(MlhRng.new(1)), 3)
	assert_false(v.drawn)


func test_a_tie_votes_again_then_draws() -> void:
	var v := MwCaptainVote.new(1, [2, 4, 6, 8], [2, 4, 6, 8])
	v.vote(2, 2)
	v.vote(4, 4)
	v.vote(6, 2)
	v.vote(8, 4)
	assert_eq(v.count(MlhRng.new(1)), 0, "tied")
	assert_eq(v.round, 2)
	assert_eq(v.candidates, [2, 4] as Array[int], "the tied vote again")
	assert_false(v.vote(6, 6), "only the tied")
	for p in [2, 6]:
		v.vote(p, 2)
	for p in [4, 8]:
		v.vote(p, 4)
	var w := v.count(MlhRng.new(77))
	assert_true(w in [2, 4], "a draw between the tied")
	assert_true(v.drawn)
	# the draw is the port stream's, the same for the same session
	var voting_session := _session([2, 4], [])
	var r1 := MwCaptainVote.stream(voting_session)
	assert_same(MwCaptainVote.stream(voting_session), r1, "one stream a session")
	var main_before := voting_session.rng.state
	r1.range_value(0, 1)
	assert_eq(voting_session.rng.state, main_before, "never the original's streams")
	var session := _session([2, 4], [])
	assert_eq(MwCaptainVote.stream(session).state, MwCaptainVote.stream(_session([2, 4], [])).state,
			"seeded from the session")


func test_a_second_round_can_decide() -> void:
	var v := MwCaptainVote.new(0, [1, 2, 3], [1, 2, 3])
	v.vote(1, 1)
	v.vote(2, 2)
	v.vote(3, 3)
	assert_eq(v.count(MlhRng.new(1)), 0)
	assert_eq(v.candidates.size(), 3)
	v.vote(1, 2)
	v.vote(2, 2)
	v.vote(3, 3)
	assert_eq(v.count(MlhRng.new(1)), 2, "decided in the second round")
	assert_false(v.drawn)


# --- saves ----------------------------------------------------------------------------------------------

func test_saves_keep_picks_captains_and_line_ups() -> void:
	if not need_rom():
		return
	var saved_session := _session([1, 4, 6], [2, 3], "playoffs")
	saved_session.humans.positions = {1: 0, 4: 5, 6: 2, 2: 1, 3: 3}
	saved_session.humans.captains = [4, 3]
	saved_session.humans.lineups = [PackedInt32Array([6, 1, 2, 3, 4, 17]), PackedInt32Array([0, 13, 2, 3, 4, 5])]
	saved_session.run_started = true
	saved_session.run_games = 1
	# a run the game makes (plan 45: a save outside the password's ranges is refused at load)
	saved_session.setup.team_a = 3
	saved_session.setup.team_b = 7
	saved_session.setup.play_mode = MwPlayoffs.MODE_PLAYOFFS
	saved_session.playoffs.start(saved_session.setup, MlhRng.new(5))
	saved_session.playoffs.build_bracket(rom, saved_session.setup.team_a, saved_session.setup.team_b)
	saved_session.run_checkpoint = saved_session.setup.to_bytes() + saved_session.playoffs.to_bytes()
	assert_true(MwPlayoffSave.save(saved_session, 3))
	var session := MwSession.new(2, 2)
	assert_true(MwPlayoffSave.load_into(session, 3))
	assert_eq([session.humans.teams, session.humans.positions, session.humans.captains, session.humans.lineups],
			[saved_session.humans.teams, saved_session.humans.positions, saved_session.humans.captains,
			saved_session.humans.lineups], "the round trip")
	MwPlayoffSave.delete(3)
