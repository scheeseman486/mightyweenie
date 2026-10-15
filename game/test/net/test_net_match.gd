extends "res://test/net/net_test_base.gd"
## Plan 35 work item 4: the game over the network (MwNetMatch). A host and
## three clients in one process on the loopback network, each running the
## whole game through its own router, bots on their own players: through
## the menus into a match at 0 % and 20 % loss, into a match from the
## matchup at 5 % and 40 % (delay, jitter, duplicates, reordering,
## outages) - every client's hash equals the host's at every pass and screen,
## a scripted press pattern arrives whole, stalls stay bounded. And the
## pieces: the two forms of a tick, the status bits, the start record on the
## wire. (The match's events - QUIT GAME, REJOIN, a lagging machine, a kick,
## the host leaving - and a run over real ENet: test/screens/
## test_online_events.gd.)

const Machines := preload("res://test/net/net_machines.gd")
const Bots := preload("res://test/support/bots.gd")

var _saved_view := -1


## Every test plays a game: pending without the ROM (plan 40's B4). Untyped
## like GutTest's.
func should_skip_script():
	return rom_or_skip()


func before_all() -> void:
	super.before_all()
	_saved_view = MwSettings.start_view


func after_all() -> void:
	MwSettings.start_view = _saved_view
	MwSettings.own_match_rules()
	super.after_all()


# --- the pieces ------------------------------------------------------------------------------------

func test_tick_input_converts_both_forms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var states := []
	for n in MwNetInput.PLAYERS:
		var state := MwNetInput.blank()
		for v in MwNetInput.COUNT:
			if rng.randf() < 0.3:
				state[v >> 3] |= 1 << (v & 7)
			state[MwNetInput.COUNTERS + v] = rng.randi_range(0, 255)
		state[MwNetInput.STICK] = rng.randi_range(0, 255)
		state[MwNetInput.STICK + 1] = 0 if n == 3 else rng.randi_range(1, 255)
		state = MwNetInput.with_status(state, n % 4)
		state[MwNetInput.HEIGHT] = n % 4
		states.append(state)
	var t := MwNetInput.make_tick(states)
	var ti := MwTickInput.from_wire(t)
	var bad := 0
	for n in range(1, MwNetInput.PLAYERS + 1):
		var bytes: PackedByteArray = states[n - 1]
		for v in MwNetInput.COUNT:
			var a := MwVerbs.player_action(n, MwNetInput.VERBS[v])
			var i := MwTickInput.index_of(a)
			if ti.is_held(i) != MwNetInput.is_held(bytes, v) or ti.counts[i] != MwNetInput.counter(bytes, v):
				bad += 1
		var st := MwNetInput.stick(bytes)
		assert_eq(ti.sticks[n - 1], 0 if st.y == 0 else (st.x << 8) | st.y, "P%d's stick code" % n)
		assert_eq(ti.status[n - 1], (n - 1) % 4, "P%d's status" % n)
		assert_eq(ti.heights[n - 1], (n - 1) % 4, "P%d's shot height" % n)
	assert_eq(bad, 0, "every player's verbs: held and counters")
	for v in MwVerbs.menu_verbs():
		var i := MwTickInput.index_of(v)
		var j := MwNetInput.index_of(v)
		assert_eq(ti.is_held(i), MwNetInput.is_held(states[0], j), "shared %s: the host's P1's" % v)
		assert_eq(ti.counts[i], MwNetInput.counter(states[0], j))
	assert_eq(ti.away().size(), 9, "statuses not HERE")
	# the status survives the stream's own coding (recordings)
	var stream := MwInputStream.new()
	stream.append(ti)
	stream.append(MwTickInput.from_wire(MwNetInput.blank_tick()))
	var back := MwInputStream.from_bytes(stream.to_bytes())
	assert_true(back.at(1).equals(ti) and back.at(2).equals(stream.at(2)),
			"statuses and shot heights in a saved stream")


func test_status_bits_travel_and_the_merge_owns_them() -> void:
	var merge := MwNetMerge.new()
	merge.set_players([1, 2])
	var mine := MwNetInput.with_status(MwNetInput.next_state(MwNetInput.blank(), PackedInt32Array([3]),
			PackedInt32Array()), 3)
	merge.feed(2, mine)
	merge.set_status(1, MwTickInput.LAGGING)
	var t := merge.tick()
	assert_eq(MwNetInput.status(MwNetInput.player(t, 1)), MwTickInput.LAGGING)
	assert_eq(MwNetInput.status(MwNetInput.player(t, 2)), 0, "a machine can't set its own status")
	assert_true(MwNetInput.is_held(MwNetInput.player(t, 2), 3))
	var reader := MwNetBytes.Reader.new(MwNetInput.encode_tick(MwNetInput.blank_tick(), t))
	assert_eq(MwNetInput.read_tick(reader, MwNetInput.blank_tick()), t, "status bits decode")


func test_start_record_fits_and_round_trips() -> void:
	var world := World.new(3)
	world.host.join_local(2)
	var client := world.join("", 2)
	assert_true(world.run_until(func() -> bool: return client.state == MwNetClient.State.LOBBY))
	var r := MwNetMatch.host_record(MwSession.new(5, 6), world.host.lobby)
	var b := MwNetMatch.encode_record(r)
	gut.p("the start record: %d bytes on the wire (%d raw)" % [b.size(), var_to_bytes(r).size()])
	assert_between(b.size(), 1, MwNetProtocol.MAX_RECORD, "fits START")
	var back := MwNetMatch.decode_record(b)
	assert_eq(MwNetHash.digest(back), MwNetHash.digest(r), "the same record")
	var session := MwSession.from_record(back)
	assert_eq(session.online_players(), [1, 2, 3, 4])
	assert_eq(session.machine_of(1), 0)
	assert_eq(session.machine_of(3), client.machine)
	assert_eq(session.local_mode, "exhibition")
	assert_eq(session.humans.total(), 0, "nobody on a team before the controller selection")
	assert_true(bool(session.rules["front_menu"]) and not bool(session.rules["idle_attract"]))
	assert_true(MwSelection.captain_mode(session), "online: captains always")
	assert_eq(MwNetMatch.decode_record(PackedByteArray([1, 2, 3, 4, 5, 6])), {}, "garbage isn't a record")


# --- whole games -----------------------------------------------------------------------------------

## A run: 4 machines (the host P1; clients P2, P3+P4, P5) under
## [param conditions]; [param from_menus]: START GAME from the game options
## through the controller selection (A: P1 P3; B: P2 P4 P5 - five players:
## character selection, the captain vote) into the match, else from the
## matchup with the teams and captains set. Runs [param rink_frames] frames
## of the rink with taps, then [param quiet] without; [param height_every]:
## the bots' shot heights (NetBot.height_every); [param prepare] called with
## the machines before the start. Returns the machines.
func _game(seed_value: int, conditions: Dictionary, from_menus: bool, rink_frames: int, quiet := 120,
		height_every := 0, prepare := Callable()) -> Machines:
	var w := Machines.new(self, seed_value, conditions)
	var teams := {1: 0, 3: 0, 2: 1, 4: 1, 5: 1}
	for peer in w.machines:
		peer.bot.height_every = height_every
		peer.bot.expected = teams.size()
		for p in peer.bot.players:
			peer.bot.teams[p] = teams[p]
			peer.bot.game_bots[p] = Bots.GameBot.new(p, seed_value)
		peer.bot.tap_every = 23
	var record := {}
	if not from_menus:
		record = matchup_record(w, teams, [1, 2])
	if prepare.is_valid():
		prepare.call(w)
	if height_every > 0:
		w.machines[0].watch("heights", func(mm: Machines.Machine) -> Array:
			var r := mm.rink()
			return Array(r.pad_heights) if r != null else [])
	w.start(record)
	var t0 := w.world.net.now_ms
	var outages: Array[Vector2i] = []
	for o: Vector2i in conditions.get("outages", []):
		outages.append(Vector2i(t0 + o.x, t0 + o.y))
	w.world.net.outages = outages
	var on_rink := func() -> bool:
		for computer in w.machines:
			if computer.router.current_id() not in [4, 5, 6]:
				return false
		return true
	assert_true(w.run_until(on_rink, 6000), "every machine on the rink (%s)" % str(w.machines.map(
			func(m: Machines.Machine) -> int: return m.router.current_id())))
	w.run(rink_frames)
	for machine in w.machines:
		machine.bot.tap_until = machine.router.tick
	w.run(quiet)
	return w


## A start record from the matchup: [param teams] (number -> team) on the
## teams, [param captains], the online player table of the world's lobby.
static func matchup_record(w: Machines, teams: Dictionary, captains: Array) -> Dictionary:
	var r := MwNetMatch.host_record(MwSession.new(11, 12), w.host.lobby)
	var session := MwSession.from_record(r)
	for p: int in teams:
		session.humans.set_team(p, int(teams[p]))
	session.humans.captains = captains.duplicate()
	session.humans.apply_to(session.setup)
	session.pad_map = session.humans.pad_players(MwRom.data())
	return session.to_record(3, 0)


func _check(w: Machines, what: String, stall_bound_ms: int) -> void:
	var c := w.compare_hashes()
	assert_true(c["ok"], "%s: every hash the host's - %s" % [what, c["why"]])
	assert_gt(int(c["compared"]), 200, "%s: hashes compared (%d)" % [what, c["compared"]])
	for m in w.machines.slice(1):
		assert_eq(m.net_match.mismatches.size(), 0, "%s: %s found no mismatch" % [what, m.name])
		assert_gt(int(m.net_match.stats["checked"]), 0, "%s: %s checked the host's hashes on the way" % [what, m.name])
	# the press pattern: every tap of every machine's players in the host's stream, one a tick
	var taps := 0
	for machine in w.machines:
		for p: int in machine.bot.tapped:
			taps += int(machine.bot.tapped[p])
			assert_eq(int(w.taps_seen.get(p, 0)), int(machine.bot.tapped[p]),
					"%s: P%d's %d taps all arrived" % [what, p, machine.bot.tapped[p]])
	assert_gt(taps, 20, "%s: taps made" % what)
	assert_eq(w.double_taps, 0, "%s: one tap a tick" % what)
	assert_lt(w.max_stall_ms, stall_bound_ms, "%s: the longest stall %d ms" % [what, w.max_stall_ms])
	gut.p("%s: %d hashes compared, longest stall %d ms, clients held %s frames, doubled %s, checked %s" % [what,
			c["compared"], w.max_stall_ms,
			str(w.machines.slice(1).map(func(m: Machines.Machine) -> int: return m.net_match.stats["held"])),
			str(w.machines.slice(1).map(func(m: Machines.Machine) -> int: return m.net_match.stats["doubled"])),
			str(w.machines.slice(1).map(func(m: Machines.Machine) -> int: return m.net_match.stats["checked"]))])


func test_through_the_menus_clean() -> void:
	var w := _game(21, {}, true, 600)
	_check(w, "0 %", 150)
	var humans := w.machines[0].session.humans
	assert_eq(humans.total(), 5, "five players on the teams")
	assert_true(humans.captain_of(0) in [1, 3] and humans.captain_of(1) in [2, 4, 5], "captains voted")
	assert_true(humans.owners(), "five players picked their positions")
	w.free_all()


## The line-ups online (owner, 2026-10-10): Reserves on, the captains' panels
## after the vote; team A's captain backs out of theirs - Back on a panel
## that isn't READY: every machine back at the controller selection, the
## positions and captains as the selection found them - and the selection
## runs again (the picks, the vote, the panels) into the match, every hash
## the host's. The second time team A's captain browses C's candidates
## (Down: the card alone shows the next one on every machine) and accept
## commits him, the next accept is DONE: every machine's line-up the same,
## changed.
func test_through_the_menus_line_ups_and_back() -> void:
	var phase := {}                                # bot -> 0 to back out, 1 backed, 2 at 110 again
	var backs := {}
	var browsed := {}                              # bot -> true: Down pressed on the panel (2nd time)
	var previewed := {}                            # machine's bot -> true: its panel showed a browsed one
	var w := _game(23, {}, true, 300, 120, 0, func(w_: Machines) -> void:
		w_.machines[0].session.setup.reserves = 1
		for m in w_.machines:
			m.bot.hook = func(bot: Machines.NetBot) -> void:
				var k := bot.get_instance_id()
				var ph := int(phase.get(k, 0))
				if ph == 1 and bot.screen == MwScreens.CONTROLLER_SELECT:
					phase[k] = 2
					return
				var cs := bot.router.current() as MwCharacterSelect
				if cs == null or cs.stage != MwCharacterSelect.Stage.PANELS:
					return
				if cs.panels[0].preview >= 0:
					previewed[k] = true
				var mine := bot.players.filter(func(p: int) -> bool: return p in cs.panels[0].drivers)
				if ph >= 2:
					if browsed.has(k) or mine.is_empty():
						return
					for p: int in mine:
						bot._hold.erase(MwVerbs.player_action(p, "ui_accept"))   # not before browsing
					if cs.panels.all(func(pn: MwLineupPanel) -> bool: return pn.landed()) \
							and not cs.panels[0].is_ready:
						bot.pulse(MwVerbs.player_action(int(mine[0]), "ui_down"))
						browsed[k] = true
					return
				for p: int in mine:
					bot._hold.erase(MwVerbs.player_action(p, "ui_accept"))   # not DONE yet
				if ph == 0 and not mine.is_empty() and cs.panels.all(func(pn: MwLineupPanel) -> bool:
						return pn.landed()) and not cs.panels[0].is_ready:
					bot.pulse(MwVerbs.player_action(int(mine[0]), "ui_back"))
					backs[int(mine[0])] = true
					phase[k] = 1)
	_check(w, "line-ups and back", 150)
	assert_eq(backs.size(), 1, "team A's captain backed out")
	for peer in w.machines:
		assert_eq(int(peer.bot.visits.get(MwScreens.CONTROLLER_SELECT, 0)), 2,
				"%s: the controller selection twice" % peer.name)
		assert_eq(int(peer.bot.visits.get(MwScreens.CHARACTER_SELECT, 0)), 2, "%s: the selection again" % peer.name)
	var humans := w.machines[0].session.humans
	assert_true(humans.captain_of(0) in [1, 3] and humans.captain_of(1) in [2, 4, 5], "captains voted")
	assert_eq(w.machines[0].session.setup.reserves, 1, "Reserves on")
	assert_eq(browsed.size(), 1, "team A's captain browsed the second time")
	var kept: PackedInt32Array = humans.lineups[0]
	assert_eq(kept.size(), MwLineup.POSITIONS, "the browsed one committed: team A's line-up changed")
	for machine in w.machines:
		assert_true(previewed.has(machine.bot.get_instance_id()), "%s: the browsed one shown" % machine.name)
		assert_eq(machine.session.humans.lineups[0], kept, "%s: the same line-up" % machine.name)
	w.free_all()


func test_through_the_menus_20_percent() -> void:
	var w := _game(22, {"loss": 0.2, "delay": 120, "jitter": 30, "duplicate": 0.05, "reorder": 0.1,
			"outages": [Vector2i(3000, 3500), Vector2i(12000, 12500)]}, true, 400)
	_check(w, "20 %", 3500)
	w.free_all()


func test_from_the_matchup_5_percent() -> void:
	var w := _game(23, {"loss": 0.05, "delay": 40, "jitter": 30, "duplicate": 0.02, "reorder": 0.05},
			false, 500)
	_check(w, "5 %", 1000)
	w.free_all()


func test_from_the_matchup_40_percent() -> void:
	var w := _game(24, {"loss": 0.4, "delay": 250, "jitter": 30, "duplicate": 0.05, "reorder": 0.1,
			"outages": [Vector2i(4000, 4500), Vector2i(9000, 9500)]}, false, 500, 240)
	_check(w, "40 %", 7000)
	w.free_all()


## The shot heights online (MwSettings.shot_heights): each machine samples
## its own players' heights, they travel in the stream (MwTickInput.heights,
## MwNetInput.HEIGHT) and every machine's rink gives each pad its player's -
## the rink's hash includes them, so every hash equal means every machine
## played the same heights.
func test_shot_heights_travel() -> void:
	var w := _game(25, {"loss": 0.05, "delay": 40, "jitter": 30, "duplicate": 0.02, "reorder": 0.05},
			false, 400, 120, 17)
	_check(w, "shot heights", 1000)
	assert_gt(w.height_ticks, 100, "the host's stream carried heights (%d ticks)" % w.height_ticks)
	var seen := {}
	for event: Array in w.machines[0].events["heights"]:
		for h in event[1]:
			seen[h] = true
	for h in [0, 1, 2]:
		assert_true(seen.has(h), "the host's rink gave a pad height %d (%s)" % [h, str(seen.keys())])
	w.free_all()


## Plan 36: the host's TICK RATE ORIGINAL plays as APPROXIMATED online
## (MwSettings.rink_tick_rate): every machine paces the rink's passes from
## the shared game alone - the same passes at the same ticks, the same
## hashes, with nothing more on the network - under 20 % loss.
func test_tick_rate_original_plays_approximated_alike() -> void:
	var was := MwSettings.tick_rate
	MwSettings.tick_rate = "ORIGINAL"         # the host's: a match rule in its start record
	var conditions := {"loss": 0.2, "delay": 80, "jitter": 30, "duplicate": 0.05, "reorder": 0.1}
	var w := Machines.new(self, 26, conditions)
	var teams := {1: 0, 3: 0, 2: 1, 4: 1, 5: 1}
	var lens := []                            # per machine: the rink passes' elapsed ticks, in order
	for peer in w.machines:
		peer.bot.expected = teams.size()
		for p in peer.bot.players:
			peer.bot.teams[p] = teams[p]
			peer.bot.game_bots[p] = Bots.GameBot.new(p, 26)
		peer.bot.tap_every = 23
		var l := []
		lens.append(l)
		peer.router.pass_ended.connect(func(b: Dictionary) -> void:
			if int(b.screen) in [4, 5, 6]:
				l.append(int(b.elapsed)))
	var record := matchup_record(w, teams, [1, 2])
	assert_eq(str(record["rules"]["tick_rate"]), "ORIGINAL", "the host's rule in the start record")
	w.start(record)
	var on_rink := func() -> bool:
		for computer in w.machines:
			if computer.router.current_id() not in [4, 5, 6]:
				return false
		return true
	assert_true(w.run_until(on_rink, 6000), "every machine on the rink")
	assert_eq(MwSettings.rink_tick_rate(true), "APPROXIMATED", "online: the deterministic model")
	w.run(900)
	for machine in w.machines:
		machine.bot.tap_until = machine.router.tick
	w.run(240)
	_check(w, "APPROXIMATED, 20 %", 3500)
	var host: Array = lens[0]
	var seen := {}
	for e in host:
		seen[e] = int(seen.get(e, 0)) + 1
	gut.p("host's rink passes: %d, elapsed %s" % [host.size(), str(seen)])
	assert_gt(host.size(), 100, "rink passes")
	assert_true(seen.has(3) and seen.has(4), "paced as the original (3 and 4 ticks), not every 2")
	for i in range(1, lens.size()):
		var mine: Array = lens[i]
		var n := mini(mine.size(), host.size())
		assert_gt(n, 100, "machine %d's rink passes" % i)
		assert_eq(mine.slice(0, n), host.slice(0, n), "machine %d: the host's pass lengths" % i)
	w.free_all()
	MwSettings.tick_rate = was
