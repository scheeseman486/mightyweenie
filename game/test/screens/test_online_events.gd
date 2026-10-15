extends "res://test/net/net_test_base.gd"
## Plan 35 work item 4: an online match's events, a host and three clients
## in one process (test/net/net_machines.gd) - QUIT GAME and REJOIN from a
## player's own menu, a silent machine (a captain's) taken by the CPU
## (LAGGING) and given back with the captaincy, a KICK from the host's pause
## menu (PLAYERS), the host leaving - each event at the same tick on every
## machine, every hash the host's; a referee's message whose player's
## machine drops while it waits; and a match over real ENet with DTLS on
## 127.0.0.1. (The stream under loss, the menus: test/net/test_net_match.gd.)

const Machines := preload("res://test/net/net_machines.gd")
const Bots := preload("res://test/support/bots.gd")
const NetMatchTest := preload("res://test/net/test_net_match.gd")


## Every test plays a game: pending without the ROM (plan 40's B4). Untyped
## like GutTest's.
func should_skip_script():
	return rom_or_skip()


func after_all() -> void:
	MwSettings.own_match_rules()
	super.after_all()


## The events of a match, at 5 % loss from the matchup (A: P1 P3, captain
## P1; B: P2 P4 P5, captain P2; machines: the host P1, 1: P2, 2: P3 P4,
## 3: P5): P3 leaves with QUIT GAME from their own menu and comes back with
## REJOIN; machine 1 (B's captain) goes silent - the CPU takes P2 after
## 3 s (LAGGING), the captaincy passes to P4 - and comes back; the host's
## P1 pauses, opens PLAYERS and KICKs machine 3 (P5); then the host leaves.
## Every machine sees each event at the same tick, every hash the host's.
func test_quit_rejoin_lag_kick_and_the_host_leaving() -> void:
	var w := Machines.new(self, 31, {"loss": 0.05, "delay": 40, "jitter": 20, "duplicate": 0.02, "reorder": 0.05})
	var teams := {1: 0, 3: 0, 2: 1, 4: 1, 5: 1}
	for machine in w.machines:
		for p in machine.bot.players:
			machine.bot.game_bots[p] = Bots.GameBot.new(p, 31)
		for probe: Array in [["out3", 3, "out"], ["net2", 2, "net"], ["net5", 5, "net"]]:
			machine.watch(probe[0], func(x: Machines.Machine) -> Variant:
				var rink_control := x.rink().control if x.rink() != null else null
				return rink_control.seat_of(int(probe[1])).get(str(probe[2])) if rink_control != null else null)
		machine.watch("captain_b", func(x: Machines.Machine) -> Variant:
			return x.rink().control.captains[1] if x.rink() != null and x.rink().control != null else null)
	w.start(NetMatchTest.matchup_record(w, teams, [1, 2]))
	var on_rink := func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool: return m.router.current_id() in [4, 5, 6])
	assert_true(w.run_until(on_rink, 3000), "on the rink")
	# QUIT GAME and REJOIN: P3's own menu (Start), QUIT GAME, YES; later REJOIN
	var p3 := w.machines[2]
	var t := p3.router.tick + 120
	for s in [[0, "p3_pause"], [20, "p3_ui_down"], [40, "p3_ui_accept"], [60, "p3_ui_up"], [80, "p3_ui_accept"],
			[400, "p3_pause"], [420, "p3_ui_accept"]]:
		p3.bot.presses.append([t + int(s[0]), 3, s[1], 4])
	w.run(600)
	var quit := _same_events(w, "out3")
	assert_eq(quit.map(func(e: Array) -> Variant: return e[1]).filter(func(v: Variant) -> bool: return v != null),
			[false, true, false], "P3 out and back in, the same ticks everywhere: %s" % str(quit))
	# a silent machine: B's captain's
	var m1 := w.machines[1]
	m1.frozen = true
	w.run(300)
	m1.frozen = false
	w.run(400)
	var lag := _same_events(w, "net2")
	assert_true(lag.any(func(e: Array) -> bool: return e[1] == MwTickInput.LAGGING), "P2 LAGGING: %s" % str(lag))
	assert_eq(lag.back()[1], MwTickInput.HERE, "P2 back")
	var caps := _same_events(w, "captain_b")
	assert_true(caps.any(func(e: Array) -> bool: return e[1] == 4), "B's captaincy to P4 meanwhile: %s" % str(caps))
	assert_eq(caps.back()[1], 2, "and back to P2")
	# KICK: the host's P1 pauses, PLAYERS, machine 3, YES, resume
	var host := w.machines[0]
	var kicker := KickBot.new(3)
	host.bot.hook = kicker.step
	assert_true(w.run_until(func() -> bool: return w.machines[3].ended >= 0, 1500), "machine 3 kicked")
	assert_eq(w.machines[3].ended, MwNetMatch.End.KICKED, "machine 3's match ended: kicked")
	assert_eq(w.machines[3].router.pending_id(), MwFlow.ONLINE_MENU, "back to ONLINE MULTIPLAYER")
	assert_false(w.host.lobby.machines.has(3), "its machine gone from the lobby")
	w.run(300)
	host.bot.hook = Callable()
	var kicked := _same_events(w, "net5", [1, 2])
	assert_eq(kicked.back()[1], MwTickInput.KICKED, "P5 KICKED for the others: %s" % str(kicked))
	assert_false(host.rink().control != null and (host.router.current() as MwRink) != null \
			and (host.router.current() as MwRink).phases.paused, "play on")
	var c := w.compare_hashes()
	assert_true(c["ok"], c["why"])
	gut.p("events: %d hashes compared; quit %s; lag %s; captain B %s; kicked %s" % [c["compared"], str(quit),
			str(lag), str(caps), str(kicked)])
	# the host leaves
	w.host.close()
	w.run(60)
	for m in w.machines.slice(1, 3):
		assert_eq(m.ended, MwNetMatch.End.HOST_LEFT, "%s: the host left" % m.name)
		assert_eq(m.router.pending_id(), MwFlow.ONLINE_MENU, "%s: back to ONLINE MULTIPLAYER" % m.name)
	w.free_all()


## Every machine's (or [param which]'s) [param what] events, the same
## everywhere up to the tick the slowest has reached; the host's list.
func _same_events(w: Machines, what: String, which: Array = []) -> Array:
	var host_ev: Array = w.machines[0].events[what]
	for i in range(1, w.machines.size()):
		if not which.is_empty() and not i in which:
			continue
		var machine := w.machines[i]
		var reached := machine.net_match.stream_tick(machine.router.tick) \
				if machine.net_match.phase == MwNetMatch.Phase.PLAYING \
				else machine.net_match._end_tick
		var theirs: Array = machine.events[what]
		var mine := host_ev.filter(func(e: Array) -> bool: return int(e[0]) <= reached)
		assert_eq(theirs, mine, "%s: %s's events as the host's" % [what, machine.name])
	return host_ev


## The host's P1 kicking machine [member target] from the pause menu:
## Start, Down to PLAYERS, its line, YES, then Back to play on.
class KickBot extends RefCounted:
	var target := 0
	var done := false
	var _wait := 0

	func _init(machine: int) -> void:
		target = machine

	func step(bot: Machines.NetBot) -> void:
		_wait -= 1
		if _wait > 0:
			return
		_wait = 12
		var rink := bot.router.current() as MwRink
		if rink == null or rink.phases == null:
			return
		var ph := rink.phases
		if not ph.paused:
			if not done:
				bot.pulse("p1_pause")
			return
		var m := ph.menu
		if m.is_empty():
			return
		if done:
			bot.pulse("p1_ui_back")
			return
		if m.get("confirm", false):
			if int(m["sure"]) != 0:
				bot.pulse("p1_ui_up")
			else:
				bot.pulse("p1_ui_accept")
				done = true
			return
		var items: Array = m["items"]
		var want := items.find(MwRinkControl.PLAYERS)
		if m.get("players", false):
			want = (m["targets"] as Array).find(target)
		if want < 0:
			return
		if int(m["sel"]) != want:
			bot.pulse("p1_ui_down")
		else:
			bot.pulse("p1_ui_accept")


## A forfeit (the port's FORFEIT, made on every machine at the same stream
## tick) and its referee's message, which waits for Start on team A's
## captain's pad alone (A: P2 captain, P3; B: the host's P1 - machines: the
## host P1, 1: P2, 2: P3). P2's machine drops while the message waits: P2
## DISCONNECTED in the stream, the captaincy and the skip pass to P3 at the
## same tick on the machines still in, and P3's Start goes on to the game
## over - the match never waits for a machine that is gone. Every hash the
## host's.
func test_the_referees_message_never_waits_for_a_machine_gone() -> void:
	var w := Machines.new(self, 35, {"loss": 0.02, "delay": 40, "jitter": 10}, [1, 1])
	for peer in w.machines:
		for p in peer.bot.players:
			peer.bot.game_bots[p] = Bots.GameBot.new(p, 35)
		peer.watch("screen", func(x: Machines.Machine) -> Variant: return x.router.current_id())
		peer.watch("net2", func(x: Machines.Machine) -> Variant:
			var rink_control := x.rink().control if x.rink() != null else null
			return rink_control.seat_of(2).net if rink_control != null else null)
		peer.watch("captain_a", func(x: Machines.Machine) -> Variant:
			return x.rink().control.captains[0] if x.rink() != null and x.rink().control != null else null)
		peer.watch("skip", func(x: Machines.Machine) -> Variant:
			var b := x.router.current() as MwBetweenPlays
			var sb := b.sim as MwMessageScoreboardSim if b != null else null
			return sb.pad >> 1 if sb != null else null)
	w.start(NetMatchTest.matchup_record(w, {2: 0, 3: 0, 1: 1}, [2, 1]))
	var machine := w.machines[0]
	var in_play := func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool: return m.router.current_id() in [4, 5, 6]) \
				and machine.rink().phase == MwRinkState.PHASE_PLAY
	assert_true(w.run_until(in_play, 3000), "in play")
	w.at_tick(machine.net_match.stream_tick(machine.router.tick) + 10, func(m: Machines.Machine) -> void:
		var state := m.rink()
		if state == null:
			return
		state.phase = MwRinkMatch.PHASE_FORFEIT                  # as MwRinkPhases._forfeit
		state.forfeit_manual = true
		state.subphase = 0
		state.scoring = 0xFFFF0000 | (MwRinkRam.TEAMS[1] & 0xFFFF)
		# its 300 ticks of FORFEIT! (`$101F6`) over: the message at the next pass,
		# before play (the bots, the CPU) can call anything else
		state.phase_tick = (state.tick - 300) & 0xFFFFFFFF)
	assert_true(w.run_until(func() -> bool: return machine.router.current_id() == 17, 1200), "the forfeit's message")
	var control := machine.rink().control
	assert_eq(machine.rink().phase, MwRinkMatch.PHASE_FORFEIT)
	w.drop(1)
	assert_true(w.run_until(func() -> bool: return machine.router.current_id() == 15 \
			and w.machines[2].router.current_id() == 15,
			1500), "on to the game over: the message didn't wait")
	var screens := _same_events(w, "screen", [2])
	var at17 := -1
	for event: Array in screens:
		if event[1] == 17:
			at17 = int(event[0])
	var net2 := _same_events(w, "net2", [2])
	assert_eq(net2.back()[1], MwTickInput.DISCONNECTED, "P2 DISCONNECTED: %s" % str(net2))
	assert_gt(int(net2.back()[0]), at17, "while the message waited (entered at %d): %s" % [at17, str(net2)])
	assert_eq(_same_events(w, "captain_a", [2]).back()[1], 3, "team A's captaincy to P3")
	var skips := _same_events(w, "skip", [2]).map(func(e: Array) -> Variant: return e[1]) \
			.filter(func(v: Variant) -> bool: return v != null)
	assert_eq(skips, [control.seat_of(2).pad, control.seat_of(3).pad], "the skip: P2's pad, then P3's")
	var c := w.compare_hashes()
	assert_true(c["ok"], c["why"])
	assert_gt(int(c["compared"]), 100, "hashes compared")
	w.free_all()


## One match over real ENet with DTLS on 127.0.0.1: the host and a client
## (P2), from the matchup into the rink; every hash the host's.
func test_over_enet_with_dtls() -> void:
	var w := Machines.new(self, 41, {}, [1], 1, MwNetIdentity.create())
	assert_eq(w.clients[0].state, MwNetClient.State.LOBBY, "joined over DTLS")
	var teams := {1: 0, 2: 1}
	for peer in w.machines:
		for p in peer.bot.players:
			peer.bot.game_bots[p] = Bots.GameBot.new(p, 41)
		peer.bot.tap_every = 17
	w.start(NetMatchTest.matchup_record(w, teams, [1, 2]))
	var on_rink := func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool: return m.router.current_id() in [4, 5, 6])
	assert_true(w.run_until(on_rink, 3000), "on the rink")
	w.run(400)
	for machine in w.machines:
		machine.bot.tap_until = machine.router.tick
	w.run(60)
	var c := w.compare_hashes()
	assert_true(c["ok"], "ENet: every hash the host's - %s" % c["why"])
	assert_gt(int(c["compared"]), 100, "ENet: hashes compared")
	for p: int in w.machines[1].bot.tapped:
		assert_eq(int(w.taps_seen.get(p, 0)), int(w.machines[1].bot.tapped[p]), "ENet: P%d's taps arrived" % p)
	assert_eq(w.machines[1].net_match.mismatches.size(), 0)
	gut.p("ENet: %d hashes compared, longest stall %d ms" % [c["compared"], w.max_stall_ms])
	w.host.close()
	w.run(30)
	assert_eq(w.machines[1].ended, MwNetMatch.End.HOST_LEFT)
	w.free_all()
	var end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end and not MwNetEnet._lingering.is_empty():
		MwNetEnet.service_lingering()
		OS.delay_msec(2)
	for e in get_errors():
		if e.contains_text("TLS handshake") or e.contains_text("mbedtls"):
			e.handled = true


## A game that parts from the host's (a client's random stream nudged): the
## client finds it at the next hash, tells the host (DESYNC), and both
## states are dumped - the client's and the host's for that tick.
func test_a_desync_is_found_and_both_states_dumped() -> void:
	var dir := "user://test_net/desync"
	var w := Machines.new(self, 51, {}, [1])
	w.start(NetMatchTest.matchup_record(w, {1: 0, 2: 1}, [1, 2]))
	for peer in w.machines:
		peer.bot.game_bots[peer.id + 1] = Bots.GameBot.new(peer.id + 1, 51)
	var on_rink := func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool: return m.router.current_id() in [4, 5, 6])
	w.run_until(func() -> bool: return w.machines.all(func(m: Machines.Machine) -> bool: return m.net_match != null), \
			600)
	for peer in w.machines:
		peer.net_match.dumps = true
		peer.net_match.dump_dir = dir
	assert_true(w.run_until(on_rink, 3000), "on the rink")
	w.run(60)
	var machine := w.machines[1]
	assert_eq(machine.net_match.mismatches.size(), 0, "in step so far")
	machine.session.rng.state ^= 0x10                     # the client's game parts from the host's
	assert_true(w.run_until(func() -> bool: return not machine.net_match.mismatches.is_empty(), 120), \
			"the client finds it")
	w.run(30)
	var first: Dictionary = machine.net_match.mismatches[0]
	var host_log := "\n".join(w.machines[0].net_match.log_lines)
	assert_true(host_log.contains("disagrees at tick %d" % int(first["tick"])), "the host heard: %s" % host_log)
	var files := DirAccess.get_files_at(dir)
	var tag := "%d_%d_%d_" % [machine.net_match.match_id, int(first["tick"]), int(first["kind"])]
	assert_true(files.has(tag + "client1.txt") and files.has(tag + "host.txt"), "both states dumped: %s" % str(files))
	gut.p("desync: %s; dumps %s" % [str(first), str(files)])
	for f in files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	w.free_all()


## The own menus' online items (MwRinkControl): the host's players have
## PLAYERS (the kick list: the remote machines, BACK), a remote machine
## whose players have all left gets DISCONNECT; a kick asked from the list.
func test_own_menus_online_items() -> void:
	var humans := MwHumans.new()
	for p in [1, 3]:
		humans.set_team(p, 0)
	for p in [2, 4, 5]:
		humans.set_team(p, 1)
	humans.captains = [1, 2]
	var control := MwRinkControl.make(humans, PackedInt32Array([1, 2, 3, 4]), MwRom.data())
	control.go_online({"players": [1, 2, 3, 4, 5], "machines": {"1": 0, "2": 1, "3": 2, "4": 2, "5": 3}})
	assert_eq(control.own_items(control.seat_of(1)), [MwRinkControl.RESUME, MwRinkControl.QUIT, MwRinkControl.PLAYERS],
			"the host's player: PLAYERS")
	assert_eq(control.own_items(control.seat_of(3)), [MwRinkControl.RESUME, MwRinkControl.QUIT])
	control.seat_of(3).out = true
	assert_eq(control.own_items(control.seat_of(3)), [MwRinkControl.REJOIN, MwRinkControl.RESUME],
			"P4 still in on machine 2")
	control.seat_of(4).out = true
	assert_eq(control.own_items(control.seat_of(3)), [MwRinkControl.REJOIN, MwRinkControl.RESUME,
			MwRinkControl.DISCONNECT],
			"machine 2's players all out: DISCONNECT")
	var m := {"items": control.own_items(control.seat_of(1)), "sel": 2, "confirm": false, "sure": 1}
	control.open_players(m)
	assert_eq(m["items"], ["P2", "P3+P4", "P5", MwRinkControl.BACK], "the remote machines")
	m["sel"] = 1
	control.players_select(m)
	assert_true(m["confirm"] and m["target"] == 2, "ARE YOU SURE? for machine 2")
	control.kick(2)
	assert_eq(control.kicks, [2])
	control.close_players(m)
	assert_eq(m["items"], [MwRinkControl.RESUME, MwRinkControl.QUIT, MwRinkControl.PLAYERS], "back to the menu")
	control.set_net({5: MwTickInput.KICKED})
	assert_eq(control.kick_list().map(func(e: Dictionary) -> String: return e["label"]), ["P2"],
			"kicked machines leave the list")
	assert_true(control.seat_of(5).away() and control.seat_of(5).gone(), "a kicked player is away")
	control.set_net({})
	assert_false(control.seat_of(5).away(), "back")
	assert_eq(control.requests, [[5, "back"]], "comes back at the next pass")


## Online only the VIEW switch picks a view (owner: debug cameras off).
func test_debug_views_off_online() -> void:
	var f1 := InputEventKey.new()
	f1.physical_keycode = KEY_F1
	f1.pressed = true
	assert_eq(MwRinkViews.picked(f1, MwRinkViews.FOLLOW), MwRinkViews.FLAT, "offline: F1 is 2D")
	assert_eq(MwRinkViews.picked(f1, MwRinkViews.FOLLOW, false), -1, "online: no F keys")
	var v := InputEventKey.new()
	v.physical_keycode = MwInputMap.VIEW_KEY
	v.pressed = true
	assert_eq(MwRinkViews.picked(v, MwRinkViews.FLAT, false), MwRinkViews.FOLLOW, "online: VIEW still switches")


## A match left mid-play for the online pages stops its sounds there (owner,
## 2026-10-13: quitting a multiplayer game to the menu left the crowd's noise
## playing): a client's DISCONNECT (on the driver it hears - plan 41's split
## undone), the host's CLOSE (its one driver) and the other client's
## THE HOST LEFT - the crowd off on each as it goes to ONLINE MULTIPLAYER,
## the others' playing on until then (MwNetMatch._sounds_off).
func test_leaving_a_match_stops_its_sounds() -> void:
	var w := Machines.new(self, 32, {"delay": 40, "jitter": 10}, [1, 1])
	for peer in w.machines:
		for p in peer.bot.players:
			peer.bot.game_bots[p] = Bots.GameBot.new(p, 32)
	w.start(NetMatchTest.matchup_record(w, {1: 0, 2: 1, 3: 1}, [1, 2]))
	var crowd := func(machine: Machines.Machine) -> bool:
		return machine.router.audio.s68k.crowd_sounding()
	assert_true(w.run_until(func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool:
			return m.router.current_id() in [4, 5, 6] and crowd.call(m)), 3000), \
					"on the rink, the crowd heard everywhere")
	# a client's DISCONNECT (its own menu's: MwNetMatch.leave)
	var leaver := w.machines[1]
	leaver.enter()
	leaver.net_match.leave()
	leaver.leave()
	leaver.ended = leaver.net_match.end_reason
	assert_eq(leaver.router.pending_id(), MwFlow.ONLINE_MENU, "the client back to ONLINE MULTIPLAYER")
	assert_false(crowd.call(leaver), "its crowd off")
	w.run(60)
	assert_true(crowd.call(w.machines[0]) and crowd.call(w.machines[2]), "the others' crowd on")
	# the host's CLOSE: its own sounds, and the other client's (THE HOST LEFT)
	var host := w.machines[0]
	host.enter()
	host.net_match.leave()
	host.leave()
	assert_false(crowd.call(host), "the host's crowd off")
	assert_true(w.run_until(func() -> bool: return w.machines[2].ended >= 0, 600), "the other client's match over")
	assert_eq(w.machines[2].ended, MwNetMatch.End.HOST_LEFT, "the host left")
	assert_false(crowd.call(w.machines[2]), "its crowd off")
	w.free_all()
