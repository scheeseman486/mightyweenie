extends "res://test/rom/rom_test_base.gd"
## Plan 34, work item 9: the control layer in the game (MwRinkControl) -
## ownership (the faceoff line-up, SWITCH, RECLAIM and its bumps, control
## taken by the game and the return, the pass, a loose puck picked up, Waste
## the Goalie), the invariants (a player drives at most one skater, a
## skater has at most one driver) every pass of bot-driven matches, QUIT
## GAME and REJOIN, a whole team out and back, captains (only they pause,
## their decisions between plays, a captain leaving), everyone else's own
## menu (it never stops the passes: the game with a menu opened and closed
## is the same game with that player's skater CPU-driven meanwhile). The
## set-ups the original could have had run the original's code with the
## layer there: the same match byte for byte. Plan 35: a player whose
## machine is away (the stream's status) counts as gone between plays as
## one who left does.
## Short names: h the MwHumans under test.

const RIGHT := 0x08
const B := 0x10
const C := 0x20
const A := 0x40
const START := 0x80
const HUMAN := MwRinkState.Player.HUMAN

var sim: MwRinkSim
var s: MwRinkState
var update: MwRinkUpdate
var phases: MwRinkPhases
var control: MwRinkControl
var humans: MwHumans
## Plan 35: what the stream says of the players' machines (player ->
## MwTickInput status; the others HERE), handed to the control layer every
## pass ([method _stream_away]).
var statuses := {}


## CPU players that stay put (plan 40: test/support/idle_cpu.gd).
const Idle := preload("res://test/support/idle_cpu.gd")


## Players: team A's numbers, team B's; [param positions] player -> own
## position; [param captains] [A's, B's].
static func _humans(a: Array, b: Array, positions := {}, captains := [0, 0]) -> MwHumans:
	var h := MwHumans.new()
	for p in a:
		h.set_team(p, 0)
	for p in b:
		h.set_team(p, 1)
	for p in positions:
		h.positions[p] = positions[p]
	h.captains = captains.duplicate()
	return h


## A match of teams 9 and 4 at stadium 4 for [param h]'s players with the
## control layer, lined up for the opening faceoff (phase handler entry 4).
func _match(h: MwHumans, ai := false, reserves := false, with_control := true) -> MwRinkState:
	humans = h
	statuses = {}
	s = MwRinkState.new()
	s.rng = MlhRng.new(1234)
	sim = MwRinkSim.new(rom, s)
	sim.cpu = MwRinkAI.new() if ai else Idle.new()
	update = MwRinkUpdate.new(sim)
	phases = MwRinkPhases.new(update)
	phases.port_menu = func(_pad: int) -> bool: return true
	var su := MwMatchSetup.from_rom(rom, MwMatchSetup.BOOT_DEFAULTS)
	su.team_a = 9
	su.team_b = 4
	su.stadium = 4
	su.reserves = 1 if reserves else 0
	su.period_minutes = 3
	h.apply_to(su)
	su.extended = h.match_pads()             # the rink's entry's (plan 40, S13: MwSelection.for_the_rink)
	control = MwRinkControl.make(h, h.pad_players(rom), rom) if with_control else null
	s.control = control
	MwRink.enter_match(sim, phases, su, true, null, false, 4)
	return s


## One 2-tick rink pass with pad bytes [param held] / [param new] ({pad:
## byte}) and own-menu verbs [param verbs] ({player: {verb: true}}); returns
## the phase handler's exit (-1 none).
func _rink_pass(held := {}, new := {}, verbs := {}, direct := {}) -> int:
	s.tick += 2
	update.pass_start(2)
	while sim.human.direct.size() < s.pads_held.size():
		sim.human.direct.append([])
	for p in s.pads_held.size():
		s.pads_held[p] = int(held.get(p, 0))
		s.pads_new[p] = int(new.get(p, 0))
		sim.human.direct[p] = (direct.get(p, []) as Array).duplicate()
	if control != null:
		control.verbs = verbs
		control.set_net(_stream_away())          # as MwRink: whose machine is away
	sim.run(2)
	update.after_segment(2)
	var to := phases.pass_end(2)
	if to < 0 and not phases.paused:
		update.draws([], MwRinkPhases.RULES_DRAWN, phases.overlays, phases.sprite_ops)
	return to


## Plan 35: an online match's table (player -> machine, 0 the host's), as
## MwRink hands it to the control layer (MwRinkControl.go_online).
func _online(machines: Dictionary) -> void:
	var ms := {}
	for p in machines:
		ms[str(p)] = machines[p]
	control.go_online({"players": machines.keys(), "machines": ms})


## [member statuses] as a stream tick carries them (MwTickInput.status) and
## the scenes hand them on every pass (MwInputFrame.away ->
## MwRinkControl.set_net).
func _stream_away() -> Dictionary:
	var ti := MwTickInput.new()
	for p in statuses:
		ti.status[int(p) - 1] = int(statuses[p])
	return ti.away()


func _until_play() -> void:
	for i in 2000:
		if s.phase == MwRinkState.PHASE_PLAY:
			return
		var skip := {}
		if i % 20 == 0:
			for seat in control.seats if control else []:
				skip[seat.pad] = B
		_rink_pass({}, skip)


func _seat(player: int) -> MwRinkControl.Seat:
	return control.seat_of(player)


func _drives(player: int) -> MwRinkState.Player:
	return control.driven_by(_seat(player))


## Team [param t]'s skater at position [param pos].
func _at(t: int, pos: int) -> MwRinkState.Player:
	for p in s.teams[t].players:
		if p.present and p.position == pos:
			return p
	return null


func _ok(what: String) -> bool:
	var text := control.check(s)
	if text != "":
		fail_test("%s: %s" % [what, text])
		return false
	return true


## A CPU-driven skater (not a goalie) of team [param t], not [param but].
func _cpu_skater(t: int, but: MwRinkState.Player = null) -> MwRinkState.Player:
	for p in s.teams[t].players:
		if p.present and not p.flags & HUMAN and p.position != 5 and p != but:
			return p
	return null


# --- the seats ------------------------------------------------------------------------------------

func test_seats_take_the_pads_the_simulation_reads() -> void:
	if not need_rom():
		return
	var h := _humans([3, 7], [5])               # 2 v 1: pad mode 3, the original's
	var rink_control := MwRinkControl.make(h, h.pad_players(rom), rom)
	assert_eq(rink_control.seats.map(func(x: MwRinkControl.Seat) -> int: return x.player), [3, 5, 7], \
			"player-number order")
	assert_eq(rink_control.seat_of(3).pad, h.pad_players(rom).find(3), "the original's pad the router gives them")
	assert_eq(rink_control.seat_of(7).slot, 1, "team A's second slot")
	assert_false(rink_control.owned, "positions need an extended set-up")
	var extended := _humans([1, 2, 3], [9], {1: 2, 2: 0, 3: 5}, [2, 9])
	rink_control = MwRinkControl.make(extended, extended.pad_players(rom), rom)
	assert_eq(rink_control.seat_of(9).pad, 8, "an extended set-up: the match pad")
	assert_eq(rink_control.seat_of(9).slot, -1)
	assert_true(rink_control.owned)
	assert_eq(rink_control.seat_of(1).own, 2)
	assert_true(rink_control.captain_mode)
	assert_eq(rink_control.captains, [2, 9])
	assert_eq(rink_control.owner_of(0, 5), rink_control.seat_of(3))
	assert_null(rink_control.owner_of(0, 4), "nobody owns RD")


# --- the faceoff line-up ---------------------------------------------------------------------------

func test_the_line_up_puts_everyone_on_their_own_position() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4, 5, 6], {1: 2, 2: 5, 3: 0, 4: 4, 5: 1, 6: 3}))
	for p: int in [1, 2, 3, 4, 5, 6]:
		var mine := _drives(p)
		assert_not_null(mine, "player %d drives" % p)
		assert_eq(mine.position, humans.positions[p], "player %d on their own position" % p)
	assert_true(_ok("line-up"))
	var before := s.rng.state
	MwRinkMatch.lineup(sim, s.teams[0], 0, 0)
	assert_eq(s.rng.state, before, "no random draw")


func test_an_own_position_off_the_ice_gets_the_originals_choice_and_waits() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4], {1: 0, 2: 1, 3: 2, 4: 0}))
	var lw := _at(0, 1)
	sim.players.off_ice(lw)                    # player 2's LW off the ice (`$D2C`)
	MwRinkMatch.lineup(sim, s.teams[0], 0, 0)
	var got := _drives(2)
	assert_not_null(got, "the original's choice of a CPU-driven team-mate")
	assert_ne(got.position, 0, "not player 1's")
	assert_true(_seat(2).back, "returns to LW when it is back")
	assert_true(_ok("line-up"))


func test_with_no_one_left_to_drive_a_player_waits() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3, 4, 5, 6], [7], {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5}))
	assert_true(_ok("line-up"))
	sim.players.off_ice(_at(0, 4))             # RD gone: player 5 has nothing left
	MwRinkMatch.lineup(sim, s.teams[0], 0, 0)
	assert_null(_drives(5), "every skater driven: player 5 waits with nobody")
	assert_true(_ok("line-up"))


# --- SWITCH, RECLAIM, bumps -------------------------------------------------------------------------

func test_switch_takes_the_originals_pick_owned_or_not() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4], {1: 0, 2: 1, 3: 2}))
	_until_play()
	var mine := _drives(1)
	var want := sim.human.best_mate(s.teams[0], mine)
	sim.human.change_player(mine)
	assert_eq(_drives(1), want, "the original's pick")
	assert_true(want.position == 3 or want.position == 4 or want.position == 5, "a CPU-driven team-mate")
	assert_true(_ok("switch"))


func test_reclaim_and_the_bumps() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4], {1: 0, 2: 1, 3: 2}))
	_until_play()
	var c0 := _at(0, 0)
	var lw := _at(0, 1)
	var ld := _at(0, 3)
	var rd := _at(0, 4)
	# player 1 leaves C for LD, player 2 takes C, player 3 takes LW (player 2's)
	control._drive(sim, _seat(1), ld)
	control._drive(sim, _seat(2), c0)
	control._drive(sim, _seat(3), lw)
	assert_true(_ok("set-up"))
	_rink_pass({}, {}, {}, {0: [MwVerbs.RECLAIM]})  # player 1's RECLAIM
	assert_eq(_drives(1), c0, "RECLAIM: back on C")
	assert_eq(ld.flags & HUMAN, 0, "the skater left goes to the CPU")
	assert_ne(_drives(2), null, "player 2 bumped ...")
	assert_ne(_drives(2), lw, "... not to LW (player 3 drives it) ...")
	assert_true(_drives(2) == ld or _drives(2) == rd or _drives(2) == _at(0, 2) or _drives(2) == _at(0, 5),
			"... but the original's choice")
	assert_true(_ok("bump to the original's choice"))
	# player 3 on RD; player 2 on RW (player 3's own); player 3 reclaims: player 2 bumped to LW, free again
	control._drive(sim, _seat(3), rd)
	control._drive(sim, _seat(2), _at(0, 2))
	_rink_pass({}, {}, {}, {2: [MwVerbs.RECLAIM]})
	assert_eq(_drives(3), _at(0, 2), "player 3 back on RW")
	assert_eq(_drives(2), lw, "player 2 bumped to their own LW (free)")
	assert_true(_ok("bump to their own"))
	_rink_pass({}, {}, {}, {1: [MwVerbs.RECLAIM]})
	assert_eq(_drives(2), lw, "RECLAIM on the own player: nothing")


func test_reclaim_without_owners_does_nothing() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4]))
	_until_play()
	var before := []
	for seat in control.seats:
		before.append(control.driven_by(seat))
	_rink_pass({}, {}, {}, {0: [MwVerbs.RECLAIM], 1: [MwVerbs.RECLAIM]})
	var after := []
	for seat in control.seats:
		after.append(control.driven_by(seat))
	assert_eq(after, before)


func test_b_tapped_twice_reclaims_with_the_genesis_layout() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4], {1: 0, 2: 1, 3: 2}))
	_until_play()
	_seat(1).taps = true
	var c0 := _at(0, 0)
	var rd := _at(0, 4)
	control._drive(sim, _seat(1), rd)
	_rink_pass({0: B}, {0: B})
	_rink_pass()
	_rink_pass({0: B}, {0: B})                       # 4 ticks later
	assert_eq(_drives(1), c0, "the second tap within 10 ticks: RECLAIM")
	assert_true(_ok("tap"))
	# taps further apart: none
	control._drive(sim, _seat(1), rd)
	_seat(1).tap = -1
	_rink_pass({0: B}, {0: B})
	var switched := _drives(1)
	for i in 6:
		_rink_pass()
	_rink_pass({0: B}, {0: B})
	if switched != c0:
		assert_ne(_drives(1), c0, "12 ticks apart: two switches, no RECLAIM")
	# the STANDARD layout: B twice switches
	_seat(1).taps = false
	control._drive(sim, _seat(1), rd)
	_seat(1).tap = -1
	_rink_pass({0: B}, {0: B})
	_rink_pass()
	_rink_pass({0: B}, {0: B})
	assert_eq(_seat(1).tap, -1, "no taps watched without the GENESIS layout")


# --- control taken by the game, the return ------------------------------------------------------------

func test_control_taken_by_the_game_and_the_return() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4], {1: 0, 2: 1, 3: 2}))
	_until_play()
	var c0 := _at(0, 0)
	sim.players.off_ice(c0)                    # `$D2C`: taken off (penalty, Reserves...)
	assert_true(_seat(1).back, "the game took player 1's own")
	var meanwhile := _drives(1)
	assert_not_null(meanwhile, "the original's choice meanwhile")
	assert_ne(meanwhile.position, 0)
	sim.players.substitute(c0)                 # a substitute comes on at C
	c0.state = 0
	assert_eq(c0.flags & HUMAN, 0, "the substitute comes on CPU-driven")
	_rink_pass()
	assert_eq(_drives(1), c0, "the owner returns to C")
	assert_false(_seat(1).back)
	assert_eq(meanwhile.flags & HUMAN, 0)
	assert_true(_ok("return"))


func test_no_return_when_they_had_left_it_themselves() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4], {1: 0, 2: 1, 3: 2}))
	_until_play()
	var c0 := _at(0, 0)
	sim.human.change_player(c0)                # player 1 switches away (B)
	var now := _drives(1)
	assert_ne(now, c0)
	sim.players.off_ice(c0)
	assert_false(_seat(1).back, "not their own any more: no return")
	sim.players.substitute(c0)
	c0.state = 0
	_rink_pass()
	assert_eq(_drives(1), now, "stays where they went")


# --- pick-ups and Waste the Goalie ----------------------------------------------------------------------

func test_a_pass_brings_the_passer_along_and_a_loose_puck_nobody() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4], {1: 0, 2: 1, 3: 2}))
	var team := s.teams[0]
	var mine := _drives(1)
	var ld := _at(0, 3)
	s.puck.carrier = mine
	assert_eq(sim.human.pickup_switch(ld, team), mine, "a pass to a CPU-driven team-mate: the passer follows ($53F0)")
	s.puck.carrier = null
	for i in 3:
		assert_null(sim.human.pickup_switch(ld, team), "a loose puck: nobody moves (owner)")
	assert_not_null(sim.human.pickup_switch(team.goalie(), team, true), "Waste the Goalie: the original's turns")


func test_the_goalie_wasted_and_reclaimed_by_his_owner() -> void:
	if not need_rom():
		return
	_match(_humans([1], [4, 5, 6], {1: 0, 4: 0, 5: 1, 6: 5}))
	_until_play()
	var player := s.teams[1].goalie()
	control._drive(sim, _seat(6), _at(1, 3))   # the goalie's owner (player 6) out on LD
	s.teams[0].special = 3
	var carrier := _drives(1)
	s.puck.carrier = carrier
	s.puck.flags |= MwRinkState.Puck.CARRIED
	assert_true(sim.special._waste_goalie(carrier, s.teams[0], s.teams[1]))
	var taker := control.driver_of(player)
	assert_not_null(taker, "a player of team B takes the goalie (the original's turns)")
	assert_true(_ok("waste the goalie"))
	if taker != _seat(6):
		_rink_pass({}, {}, {}, {5: [MwVerbs.RECLAIM]})
		assert_eq(_drives(6), player, "the goalie's owner reclaims him")
		assert_ne(control.driven_by(taker), null, "the taker bumped to their own")
	assert_true(_ok("reclaimed"))


# --- QUIT GAME, REJOIN, a whole team out ---------------------------------------------------------------------

func test_quit_game_and_rejoin() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4], {1: 0, 2: 1, 3: 2}))
	_until_play()
	var lw := _drives(2)
	control.request(2, "quit")
	_rink_pass({1: RIGHT | A}, {1: A})
	assert_true(_seat(2).out)
	assert_eq(lw.flags & HUMAN, 0, "the CPU drives their skater")
	assert_eq(s.pads_held[1], 0, "their pad reaches nothing in the game")
	assert_eq(control.owner_of(0, 1), _seat(2), "the position stays theirs")
	assert_eq(humans.owner_of(0, 1), 2)
	control._drive(sim, _seat(3), lw)          # a team-mate can switch to it
	assert_eq(_drives(3), lw)
	assert_true(_ok("quit"))
	_rink_pass({1: START}, {1: START})              # their Start: the menu with REJOIN
	assert_eq(_seat(2).menu["items"], [MwRinkControl.REJOIN, MwRinkControl.RESUME])
	assert_false(phases.paused, "a player who left never pauses")
	_rink_pass({}, {}, {2: {"select": true}})
	assert_false(_seat(2).out, "REJOIN")
	assert_eq(_drives(2), lw, "back on their own position (as a RECLAIM)")
	assert_eq(_drives(3), _at(0, 2), "player 3 bumped to their own")
	assert_true(_seat(2).menu.is_empty())
	assert_true(_ok("rejoin"))


func test_a_whole_team_out_and_back() -> void:
	if not need_rom():
		return
	_match(_humans([1], [4, 5]), true, true)
	_until_play()
	assert_true(s.has_players(s.teams[1]))
	control.request(4, "quit")
	control.request(5, "quit")
	_rink_pass()
	assert_false(control.anyone_in(1))
	assert_false(s.has_players(s.teams[1]), "nobody left: the CPU team's decisions")
	assert_ne(s.teams[1].flags4 & 4, 0, "the bit itself stays (the replay ring reads it)")
	for p in s.teams[1].players:
		assert_eq(p.flags & HUMAN, 0, "every team B skater CPU-driven")
	var rolls := s.rng.state
	MwRinkMatch.lineup(sim, s.teams[1], 0, 0)
	assert_ne(s.rng.state, rolls, "the line-up rolls the CPU coach's line changes and special play")
	for p in s.teams[1].players:
		assert_eq(p.flags & HUMAN, 0, "the line-up gives nobody a skater")
	assert_eq(MwSpecialPlaysSim.layout_mode(s), 0, "the special plays: team B's page idles")
	control.request(5, "rejoin")
	_rink_pass()
	assert_true(s.has_players(s.teams[1]), "someone back: the team's own decisions")
	assert_not_null(_drives(5), "player 5 drives again")
	assert_true(_ok("back"))


func test_a_captain_leaving_and_back() -> void:
	if not need_rom():
		return
	_match(_humans([2, 5, 9], [4], {2: 0, 5: 1, 9: 2}, [5, 4]))
	assert_eq(control.captains, [5, 4])
	control.request(5, "quit")
	_rink_pass()
	assert_eq(control.captains[0], 2, "the team's lowest-numbered player still in")
	control.request(2, "quit")
	_rink_pass()
	assert_eq(control.captains[0], 9)
	control.request(9, "quit")
	_rink_pass()
	assert_eq(control.captains[0], 0, "nobody in")
	control.request(9, "rejoin")
	_rink_pass()
	assert_eq(control.captains[0], 9)
	control.request(5, "rejoin")
	_rink_pass()
	assert_eq(control.captains[0], 5, "the captain again")


# --- captains: the pause, the own menus ------------------------------------------------------------------------

func test_only_captains_pause() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4, 5], {}, [2, 5]))
	_until_play()
	var to := _rink_pass({0: START}, {0: START})
	assert_ne(to, MwRinkPhases.PAUSED, "player 1's Start doesn't pause ...")
	assert_false(_seat(1).menu.is_empty(), "... it opens their own menu")
	assert_eq(_seat(1).menu["items"], [MwRinkControl.RESUME, MwRinkControl.QUIT])
	to = _rink_pass({1: START}, {1: START})
	assert_eq(to, MwRinkPhases.PAUSED, "the captain's pauses")
	assert_eq(s.pause_pad, 2 * 1)
	assert_false(MwRinkPhases.QUIT in phases.menu["items"],
			"the captain's pause menu has no QUIT GAME (owner, 2026-10-10: a spectated match's alone)")


func test_without_captains_anyone_pauses() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4, 5]))
	_until_play()
	var to := _rink_pass({2: START}, {2: START})
	assert_eq(to, MwRinkPhases.PAUSED)
	var items: Array = ["REPLAY", "TIMEOUT", "TEAM INFO", "FORFEIT"] if s.pause_offer != 0 \
			else ["REPLAY", "TEAM INFO", "FORFEIT"]
	assert_eq(phases.menu["items"], items,
			"no QUIT GAME for the player who paused (owner, 2026-10-10: a spectated match's alone; plan 34 had it)")
	assert_true(_seat(3).menu.is_empty())
	phases.menu["sel"] = items.find("FORFEIT")
	phases.menu_press({"select": true})
	assert_eq(phases.menu["ask"], "FORFEIT", "ARE YOU SURE? asks about FORFEIT ...")
	phases.menu_press({"select": true})
	assert_false(phases.menu["confirm"], "... NO: back")
	assert_eq(phases.menu_press({"resume": true}), -1, "Start resumes")
	_rink_pass()
	for seat in control.seats:
		assert_false(seat.out, "nobody left")


func test_the_own_menus_quit_game_asks_first() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2], [4], {}, [1, 4]))
	_until_play()
	_rink_pass({1: START}, {1: START})
	_rink_pass({}, {}, {2: {"down": true}})
	assert_eq(_seat(2).menu["sel"], 1, "QUIT GAME")
	_rink_pass({}, {}, {2: {"select": true}})
	assert_true(_seat(2).menu["confirm"], "ARE YOU SURE?")
	_rink_pass({}, {}, {2: {"select": true}})
	assert_false(_seat(2).menu["confirm"], "NO: back")
	assert_false(_seat(2).out)
	_rink_pass({}, {}, {2: {"select": true}})
	_rink_pass({}, {}, {2: {"up": true}})
	_rink_pass({}, {}, {2: {"select": true}})
	assert_true(_seat(2).out, "YES: left")
	assert_true(_seat(2).menu.is_empty(), "the menu closes")
	_rink_pass({1: START}, {1: START})
	assert_eq(_seat(2).menu["items"][0], MwRinkControl.REJOIN)
	_rink_pass({}, {}, {2: {"back": true}})
	assert_true(_seat(2).menu.is_empty() and _seat(2).out, "Back closes it, still out")


## A player's own menu never stops the passes: the game with player 2's
## menu opened (Start) and closed (RESUME) equals the same game with player
## 2's skater CPU-driven meanwhile (the control layer's requests, no menu
## input) - the same states pass for pass, the passes running throughout.
func test_an_own_menu_never_stops_the_passes() -> void:
	if not need_rom():
		return
	var runs := []
	for via_menu in [true, false]:
		_match(_humans([1, 2, 3], [4], {}, [1, 4]), true)
		_until_play()
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var states := []
		var ticks := []
		for i in 120:
			var held := {0: [0, 1, 2, 4, 8][rng.randi_range(0, 4)], 3: [0, 1, 2, 4, 8][rng.randi_range(0, 4)]}
			var new := {}
			var verbs := {}
			var p2: int = [0, 1, 2, 4, 8, 0x10][rng.randi_range(0, 5)]
			if i >= 20 and i < 80:
				held[1] = p2                         # menu verbs on the pad: nothing reaches the game
				if not via_menu:
					held.erase(1)
			else:
				held[1] = p2
			if i == 20:
				if via_menu:
					held[1] = START
					new[1] = START
				else:
					control.request(2, "open")
			if via_menu and i in [30, 31, 50]:
				verbs[2] = {"down": true}
			if via_menu and i in [40, 60]:
				verbs[2] = {"up": true}
			if via_menu and i == 70:
				verbs[2] = {"down": true}
			if i == 79:
				if via_menu:
					verbs[2] = {"select": true}      # RESUME (down, down, up, down, up, down: selected again)
				else:
					control.request(2, "close")
			var tick := s.tick
			_rink_pass(held, new, verbs)
			ticks.append(s.tick - tick)
			states.append(MwSimDict.to_dict(s))
			if i == 50:
				assert_false(_seat(2).menu.is_empty(), "the menu open at pass 50")
				assert_null(_drives(2), "the CPU drives player 2's skater meanwhile")
		assert_true(_seat(2).menu.is_empty(), "closed")
		assert_not_null(_drives(2), "back on their skater")
		assert_eq(ticks.count(2), ticks.size(), "every pass ran (never paused)")
		assert_false(phases.paused)
		runs.append(states)
	var differ := -1
	for i in runs[0].size():
		if not MwSimDict.diff(runs[0][i], runs[1][i]).is_empty():
			differ = i
			break
	assert_eq(differ, -1, "the same game pass for pass (first difference: pass %d)" % differ)


# --- between plays -------------------------------------------------------------------------------------------------

func test_captains_decide_between_plays() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4, 5], {}, [2, 5]))
	var held := []
	var new := []
	for i in 12:
		held.append(A)
		new.append(A)
	control.screen_pads(12, held, new)
	for pad in 12:
		var want := A if pad == 1 or pad == 4 else 0
		assert_eq(int(new[pad]), want, "the scoreboard: pad %d" % pad)
	held.fill(A)
	new.fill(A)
	control.screen_pads(18, held, new)
	assert_eq(new.count(A), 12, "the fight: everyone as they are")
	control.request(3, "quit")
	_rink_pass()
	held.fill(A)
	new.fill(A)
	control.screen_pads(18, held, new)
	assert_eq(int(new[2]), 0, "a player who left presses nothing")
	# the special plays page: the captain's presses only
	_match(_humans([1, 2, 3], [], {}, [3, 0]), false, true)
	s.period = 1
	s.tick = 1000
	var sp := MwSpecialPlaysSim.new(rom)
	sp.enter(s, 10, 4)
	var cursor := sp.pages[0].cursor
	var h12 := []
	var n12 := []
	for i in 12:
		h12.append(0)
		n12.append(0)
	h12[0] = 0x02
	n12[0] = 0x02
	control.screen_pads(10, h12, n12)
	s.tick += 3
	sp.begin_pass()
	sp.step(3, h12, n12)
	assert_eq(sp.pages[0].cursor, cursor, "player 1's Down: not the captain's")
	h12[2] = 0x02
	n12[2] = 0x02
	control.screen_pads(10, h12, n12)
	s.tick += 3
	sp.begin_pass()
	sp.step(3, h12, n12)
	assert_ne(sp.pages[0].cursor, cursor, "the captain's (player 3)")


func test_the_fight_and_the_message_go_to_captains_and_players_still_in() -> void:
	if not need_rom():
		return
	_match(_humans([4, 9, 10], [11]))
	var cpu := _cpu_skater(0)
	assert_eq(control.fight_pad(0, cpu, 77), 77, "no captains, nobody away: the original's choice")
	control.request(4, "quit")
	_rink_pass()
	assert_eq(control.fight_pad(0, cpu, 77), 2 * 8, "player 4 left: the lowest-numbered still in (9)")
	_match(_humans([4, 9, 10], [11], {}, [10, 11]))
	assert_eq(control.fight_pad(0, cpu, 77), 2 * 9, "with captains: the captain (10)")
	var driven := _drives(4)
	assert_eq(control.fight_pad(0, driven, 77), 2 * 3, "a fighter's driver fights")
	MwRinkPenalties.set_flags(s.teams[1], MwRinkPenalties.STOP)
	assert_eq(MwMessageScoreboardSim._fouled_pad(s.teams[0], s.teams[1], 0, control), 9,
			"the captain skips the messages")
	control.request(4, "quit")
	control.request(9, "quit")
	control.request(10, "quit")
	_rink_pass()
	assert_eq(control.fight_pad(0, cpu, 77), -1, "nobody in: the CPU fights")
	assert_eq(MwMessageScoreboardSim._fouled_pad(s.teams[0], s.teams[1], 3, control), 3, "nobody in: as a CPU team")


# --- a team with nobody in never holds the game up
# ---------------------------------------------------------------------

## A pass of screen sim [param sb] (screen [param screen]) with the pads
## [param new] ({pad: byte}, held too) as MwBetweenPlays hands them over:
## the stream's statuses to the control layer, the players counted by it
## (MwRinkControl.set_net, screen_pads).
func _screen_pass(sb: MwScreenSim, screen: int, e: int, new := {}) -> int:
	var held := []
	var nw := []
	for p in s.pads_held.size():
		held.append(int(new.get(p, 0)))
		nw.append(int(new.get(p, 0)))
	control.set_net(_stream_away())
	control.screen_pads(screen, held, nw)
	s.tick += e
	sb.begin_pass()
	return sb.step(e, held, nw)


## Screen 17 with a new referee's message (phase 12), past its first pass.
func _referee() -> MwMessageScoreboardSim:
	s.phase = MwRinkState.PHASE_REF
	s.scoring = 0xFFFF0000 | int(MwScoreboardSim.TEAM_WORDS[0])
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 19)
	_screen_pass(sb, 17, 1)
	return sb


## Team A's coach always speaks at a period start, a CPU's too, which no
## pad skips: with nobody left in team A, team B's players skip it (as the
## original hands a goal speech's skip to the other team).
func test_a_team_with_nobody_in_never_holds_up_its_coachs_speech() -> void:
	if not need_rom():
		return
	_match(_humans([1], [2]))
	control.request(1, "quit")
	for i in 600:
		if s.phase == MwRinkState.PHASE_START and s.subphase == 1:
			break
		_rink_pass()
	assert_eq([s.phase, s.subphase, s.speaker], [MwRinkState.PHASE_START, 1, 0], "team A's coach speaks")
	assert_false(s.has_players(s.teams[0]), "team A: nobody in")
	_rink_pass({}, {_seat(1).pad: B})
	assert_eq(s.speaker, 0, "player 1 (out) skips nothing")
	_rink_pass({}, {_seat(2).pad: B})
	assert_eq([s.subphase, s.speaker], [1, 1], "player 2 skips it: team B's coach now")
	_rink_pass({}, {_seat(2).pad: B})
	assert_eq(s.subphase, 2, "and their own: the drop")
	# the original's set-up with everyone in: team B's pad never skips team A's coach
	_match(_humans([1], [2]))
	for i in 600:
		if s.phase == MwRinkState.PHASE_START and s.subphase == 1:
			break
		_rink_pass()
	_rink_pass({}, {_seat(2).pad: B})
	assert_eq([s.subphase, s.speaker], [1, 0], "team A has its player: only theirs skips")


## The referee's message (a new referee, a forfeit) waits for Start on the
## one pad the original reads there, pad 1 (team A's first): with captains
## team A's captain's, with team A out team B's player's - someone still
## in - and with everyone out every pad counts again.
func test_the_referee_message_waits_on_someone_still_in() -> void:
	if not need_rom():
		return
	_match(_humans([1], [2]))
	assert_eq(MwMessageScoreboardSim._first_pad(s), 0, "nobody away, no captains: the original's pad 1")
	_match(_humans([1, 2], [], {}, [2, 0]))            # 2 v 0, captain mode: player 2 captain
	assert_eq(MwMessageScoreboardSim._first_pad(s), _seat(2).pad, "the captain's")
	var sb := _referee()
	assert_eq(_screen_pass(sb, 17, 180, {_seat(1).pad: START}), -1, "player 1's Start: not the captain's")
	assert_eq(_screen_pass(sb, 17, 1, {_seat(2).pad: START}), 5, "the captain's: a new referee")
	_match(_humans([1], [2]))
	control.request(1, "quit")
	_rink_pass()
	assert_eq(MwMessageScoreboardSim._first_pad(s), _seat(2).pad, "team A out: team B's player")
	sb = _referee()
	assert_eq(_screen_pass(sb, 17, 180, {_seat(1).pad: START}), -1, "player 1 left: nothing")
	assert_eq(_screen_pass(sb, 17, 1, {_seat(2).pad: START}), 5, "player 2, still in")
	control.request(2, "quit")
	_rink_pass()
	assert_true(control.everyone_out())
	assert_eq(MwMessageScoreboardSim._first_pad(s), _seat(1).pad, "everyone out: team A's first player")
	sb = _referee()
	assert_eq(_screen_pass(sb, 17, 180, {_seat(1).pad: START}), 5, "their Start counts: nobody is in")


## With everyone out both teams are the CPU's: the screens between plays
## read every pad as in the original's CPU v CPU match (captains or not),
## so a menu waiting on the players never waits on nobody.
func test_with_everyone_out_every_pad_counts_between_plays() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4, 5], {}, [2, 5]))
	for p in [1, 2, 3, 4]:
		control.request(p, "quit")
	_rink_pass()
	assert_false(control.everyone_out(), "player 5 still in")
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 10)                                  # back from the special plays: the menu
	assert_eq(_screen_pass(sb, 17, 1, {0: START}), -1, "player 1 left: their Start counts for nothing")
	control.request(5, "quit")
	_rink_pass()
	assert_true(control.everyone_out())
	var held := []
	var new := []
	for i in 12:
		held.append(A)
		new.append(A)
	control.screen_pads(12, held, new)
	assert_eq(new.count(A), 12, "every pad as it is")
	assert_eq(MwSpecialPlaysSim.layout_mode(s), 0, "the special plays: no page plays")
	assert_eq(control.fight_pad(0, _cpu_skater(0), 77), -1, "the fights: the CPU's")
	sb = MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 10)
	assert_eq(_screen_pass(sb, 17, 1, {0: START}), 5, "player 1's Start goes on")


# --- plan 35: a machine away is gone
# -----------------------------------------------------------------------------------

## The referee's message waits for Start on pad 1 alone (team A's first):
## a player whose machine is away (the stream's status) is gone as one who
## left - before the screen (no captains: the finding's set-up, the host's
## P1 on team B) and while it waits (captains, as online always has: the
## skip passes on that pass).
func test_a_machine_away_at_the_referees_message() -> void:
	if not need_rom():
		return
	_match(_humans([2], [1]))                           # 1 v 1: P2 on machine 1, the host's P1
	_online({1: 0, 2: 1})
	assert_eq(_seat(2).pad, 0, "P2 on pad 1")
	assert_eq(MwMessageScoreboardSim._first_pad(s), 0, "everyone here: the original's pad 1")
	statuses = {2: MwTickInput.DISCONNECTED}
	_rink_pass()
	assert_true(control.reshaped(), "a machine away: who answers changes")
	assert_eq(MwMessageScoreboardSim._first_pad(s), _seat(1).pad, "P2's machine away: the host's P1")
	var sb := _referee()
	assert_eq(_screen_pass(sb, 17, 180, {_seat(2).pad: START}), -1, "P2's pad: nothing")
	assert_eq(_screen_pass(sb, 17, 1, {_seat(1).pad: START}), 5, "P1's Start: a new referee")
	# captains, P2's machine going away while the message waits
	_match(_humans([2], [1], {}, [2, 1]))
	_online({1: 0, 2: 1})
	sb = _referee()
	assert_eq(sb.pad >> 1, _seat(2).pad, "team A's captain's pad")
	assert_eq(_screen_pass(sb, 17, 180, {_seat(1).pad: START}), -1, "P1's Start: not team A's captain's")
	statuses = {2: MwTickInput.LAGGING}
	assert_eq(_screen_pass(sb, 17, 1, {_seat(1).pad: START}), 5, "P2's machine lags: the skip is P1's that pass")
	assert_eq(sb.pad >> 1, _seat(1).pad)
	# the skip pad's player here: it stays as the set-up made it
	_match(_humans([2], [1], {}, [2, 1]))
	_online({1: 0, 2: 1})
	sb = _referee()
	statuses = {1: MwTickInput.LAGGING}
	assert_eq(_screen_pass(sb, 17, 180, {}), -1)
	assert_eq(sb.pad >> 1, _seat(2).pad, "another machine away: team A's captain's still")


## A coach's speech whose team's one player's machine lags is the other
## team's players' to skip (MwRinkState.has_players), as with QUIT GAME.
func test_a_machine_away_never_holds_up_its_coachs_speech() -> void:
	if not need_rom():
		return
	_match(_humans([1], [2]))
	_online({1: 1, 2: 0})                                # P1 on machine 1, the host's P2
	statuses = {1: MwTickInput.LAGGING}
	for i in 600:
		if s.phase == MwRinkState.PHASE_START and s.subphase == 1:
			break
		_rink_pass()
	assert_eq([s.phase, s.subphase, s.speaker], [MwRinkState.PHASE_START, 1, 0], "team A's coach speaks")
	assert_false(s.has_players(s.teams[0]), "team A: its machine lags - nobody in")
	_rink_pass({}, {_seat(1).pad: B})
	assert_eq(s.speaker, 0, "P1's pad skips nothing")
	_rink_pass({}, {_seat(2).pad: B})
	assert_eq([s.subphase, s.speaker], [1, 1], "the host's P2 skips it: team B's coach now")


## The host's players left with QUIT GAME and the one still in has a
## machine away: everyone is gone, so the screens between plays read every
## pad (the host's players' too) and the menus go on; nobody in at all, the
## referee's message is a player's whose machine is here.
func test_with_everyone_else_out_a_machine_away_holds_up_nothing() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 3], [4, 5], {}, [2, 5]))
	_online({1: 0, 2: 0, 3: 0, 4: 0, 5: 1})
	for p in [1, 2, 3, 4]:
		control.request(p, "quit")
	_rink_pass()
	assert_false(control.everyone_out(), "P5 still in")
	statuses = {5: MwTickInput.LAGGING}
	_rink_pass()
	assert_true(control.everyone_out(), "P5's machine lags: nobody can answer")
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 10)                                  # back from the special plays: the menu
	assert_eq(_screen_pass(sb, 17, 1, {0: START}), 5, "player 1's Start goes on")
	statuses = {}
	sb = MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 10)
	assert_eq(_screen_pass(sb, 17, 1, {0: START}), -1, "P5 back: the menu waits for them again")
	assert_false(control.everyone_out())
	# nobody in: the referee's message goes to a player whose machine is here
	_match(_humans([2], [1]))
	_online({1: 0, 2: 1})
	control.request(1, "quit")
	statuses = {2: MwTickInput.DISCONNECTED}
	_rink_pass()
	assert_true(control.everyone_out())
	assert_eq(MwMessageScoreboardSim._first_pad(s), _seat(1).pad, "the host's P1 (left, here), not P2 (away)")
	sb = _referee()
	assert_eq(_screen_pass(sb, 17, 180, {_seat(1).pad: START}), 5, "their Start counts: nobody is in")


# --- the original's set-ups -------------------------------------------------------------------------------------------

## The control layer in every set-up the original could have had, without
## captains and with nobody away: the same match byte for byte (the
## original's code alone).
func test_the_originals_set_ups_unchanged_with_the_layer() -> void:
	if not need_rom():
		return
	for mode in 6:
		var states := []
		for with_control in [false, true]:
			_match(MwHumans.from_pad_mode(rom, mode), true, true, with_control)
			for i in 400:
				var pad := i % 4
				var new := {pad: [B, C, A, 0, 0][i % 5]} if i % 7 == 0 else {}
				var held := {pad: [RIGHT, 1, 2, 4][(i / 9) % 4]}
				if _rink_pass(held, new) >= 0:
					break
			states.append(MwSimDict.to_dict(s))
		assert_eq(MwSimDict.diff(states[0], states[1]), {}, "pad mode %d: byte for byte" % mode)


func test_captain_mode_in_an_original_set_up() -> void:
	if not need_rom():
		return
	var h := MwHumans.from_pad_mode(rom, 2)     # 2 v 0: players 1 and 2 on team A
	h.captains = [2, 0]
	_match(h)
	_until_play()
	var to := _rink_pass({0: START}, {0: START})
	assert_ne(to, MwRinkPhases.PAUSED, "player 1 (not captain): no pause")
	assert_false(_seat(1).menu.is_empty(), "their own menu")
	assert_null(_drives(1), "the CPU drives their skater")
	assert_true(_ok("menu"))
	_rink_pass({}, {}, {1: {"resume": true}})
	assert_not_null(_drives(1), "back")
	to = _rink_pass({1: START}, {1: START})
	assert_eq(to, MwRinkPhases.PAUSED, "the captain pauses")
	assert_true(_ok("original set-up"))


# --- whole matches: bots on every pad, the invariants every pass
# ---------------------------------------------------------

## [param passes] rink passes of [param h]'s match with a random bot on every
## player's pad (presses, RECLAIM, B taps), players quitting, rejoining and
## opening their menus now and then, a faceoff every 200 passes (the
## line-up with players away); the invariants every pass. Returns what
## happened.
func _bot_match(h: MwHumans, passes: int, seed_value: int) -> Dictionary:
	_match(h, true, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for seat in control.seats:
		seat.taps = rng.randf() < 0.5
	var bots := {}
	var seen := {"passes": 0, "quits": 0, "rejoins": 0, "menus": 0, "reclaims": 0, "exits": 0}
	for i in passes:
		var held := {}
		var new := {}
		var direct := {}
		var verbs := {}
		for seat in control.seats:
			var pad := seat.pad
			if not bots.has(pad) or rng.randf() < 0.05:
				bots[pad] = [0, 1, 2, 4, 8, 5, 9, 6, 10][rng.randi_range(0, 8)]
			var b: int = bots[pad]
			if rng.randf() < 0.08:
				b |= [B, C, A][rng.randi_range(0, 2)]
			held[pad] = b
			new[pad] = b & ~0x0F if rng.randf() < 0.5 else 0
			if control.owned and rng.randf() < 0.02:
				direct[pad] = [MwVerbs.RECLAIM]
				seen["reclaims"] += 1
			var r := rng.randf()
			if r < 0.004:
				control.request(seat.player, "rejoin" if seat.out else "quit")
				seen["rejoins" if seat.out else "quits"] += 1
			elif r < 0.008:
				control.request(seat.player, "close" if not seat.menu.is_empty() else "open")
				seen["menus"] += 1
			if not seat.menu.is_empty() and rng.randf() < 0.1:
				verbs[seat.player] = {["up", "down", "select", "back"][rng.randi_range(0, 3)]: true}
		var to := _rink_pass(held, new, verbs, direct)
		seen["passes"] += 1
		if to < 0 and i % 200 == 199:
			to = 5                                   # a stoppage: the faceoff's line-up
		if phases.paused:
			phases.menu_press({"resume": true})
		if to >= 0:
			seen["exits"] += 1
			MwRinkMatch.rink_exit(sim, to)
			if s.period > 3 or to in [15, 16, 17]:
				break
			phases.enter(5)
		if not _ok("pass %d" % i):
			break
	return seen


func test_whole_matches_keep_the_invariants() -> void:
	if not need_rom():
		return
	var cases := [
		_humans([1, 2, 3], [4, 5, 6], {1: 0, 2: 3, 3: 5, 4: 1, 5: 2, 6: 0}),
		_humans([1, 2, 3, 4, 5, 6], [7, 8, 9, 10, 11, 12], {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5,
				7: 5, 8: 4, 9: 3, 10: 2, 11: 1, 12: 0}, [3, 10]),
		_humans([1, 2, 3, 4, 5], [], {1: 4, 2: 3, 3: 2, 4: 1, 5: 0}),
		_humans([2, 4, 6], [1, 3]),
		MwHumans.from_pad_mode(rom, 4),
	]
	for i in cases.size():
		var h: MwHumans = cases[i]
		var seen := _bot_match(h, 900, 31 + i)
		assert_gt(int(seen["passes"]), 300, "%s: played" % str(h.teams))
		gut.p("%s: %s" % [str(h.teams), str(seen)])


# --- the marks: the owners' hollow mark, the captain's C ------------------------------------------------------

## The port calls drawn with plate slot [param slot] (MwPlate: bank and
## frame) as [x, y, attr].
func _marks(slot: int) -> Array:
	var out := []
	for c: Array in update.drawer.port_calls:
		if int(c[4]) == MwRinkDraw.PLATES + 8 * (slot & 3) and (int(c[3]) >> 20) & 15 == slot >> 2:
			out.append(c)
	return out


func test_the_hollow_mark_and_the_captains_c() -> void:
	if not need_rom():
		return
	_match(_humans([1, 2, 7], [4], {1: 0, 2: 1, 7: 2}, [1, 4]))
	_until_play()
	_rink_pass()
	assert_eq(_marks(MwPlate.RING_SLOT + 1).size(), 0, "everyone on their own: no hollow mark")
	assert_eq(_marks(MwPlate.CAPTAIN_SLOT).size(), 1, "the captain's C (player 1: pad 1's colour)")
	assert_eq(_marks(MwPlate.CAPTAIN_SLOT + 3).size(), 1, "team B's captain (player 4)")
	control.request(2, "open")
	control.request(7, "quit")
	_rink_pass()
	var lw := _at(0, 1)
	var ring := _marks(MwPlate.RING_SLOT + 1)
	assert_eq(ring.size(), 1, "player 2's LW, CPU-driven: their hollow mark (their colour)")
	var g := update.drawer.to_sprite(update.drawer.project(lw.motion.pixels().x, lw.motion.pixels().y, 0))
	assert_eq(Vector2i(int(ring[0][0]), int(ring[0][1])), Vector2i(g.x, g.y) + MwRinkDraw.RING_AT, "round his feet")
	var r7 := _marks(MwPlate.RING_SLOT)
	assert_eq(r7.size(), 1, "player 7 (left): their mark on RW, pad 1's variant ...")
	assert_eq(MwRinkDraw.line_of(int(r7[0][3])), 6, "... on their own line (player 7)")
	control._drive(sim, _seat(1), lw)           # player 1 drives player 2's LW
	_rink_pass()
	assert_eq(_marks(MwPlate.RING_SLOT + 1).size(), 1, "driven by someone else: still the owner's mark")
	assert_eq(_marks(MwPlate.RING_SLOT).size(), 2, "player 1's C, now the CPU's, and player 7's RW")
	var tiles := MwPlate.ram_tiles(rom, s.plates)
	assert_false(MwPlate.ram_tiles(rom, MwRinkState.new().plates).has(MwRinkDraw.PLATE_TILES + 8 * MwPlate.RING_SLOT),
			"the original's four plates alone: none")
	assert_true(MwPlate.ram_tiles(rom, MwRinkState.new().plates,
			true).has(MwRinkDraw.PLATE_TILES + 8 * MwPlate.CAPTAIN_SLOT),
			"captains in the original's set-ups: the C")
	for slot in [MwPlate.RING_SLOT, MwPlate.CAPTAIN_SLOT + 3]:
		assert_true(tiles.has(MwRinkDraw.PLATE_TILES + 8 * slot), "slot %d's tiles" % slot)


func test_the_captains_c_in_an_original_set_up_and_nothing_without() -> void:
	if not need_rom():
		return
	var h := MwHumans.from_pad_mode(rom, 2)
	h.captains = [2, 0]
	_match(h)
	_until_play()
	_rink_pass()
	var cap := _marks(MwPlate.CAPTAIN_SLOT + 1)
	assert_eq(cap.size(), 1, "player 2 (pad 2): a C beside their plate")
	assert_eq(int(cap[0][3]) & 0xFFFF, 0x60, "line 3, as the original's crossbones")
	var calls := []
	for with_control in [false, true]:
		_match(MwHumans.from_pad_mode(rom, 4), false, false, with_control)
		_until_play()
		_rink_pass()
		calls.append([update.drawer.calls.duplicate(true), update.drawer.port_calls.size(),
				update.sprites.duplicate(true)])
	assert_eq(calls[1][0], calls[0][0], "no captains, no owners: the original's draws")
	assert_eq(calls[1][1], 0, "and no port marks")
	assert_eq(calls[1][2], calls[0][2], "the same sprite list")
