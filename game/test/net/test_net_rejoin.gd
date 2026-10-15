extends "res://test/net/net_test_base.gd"
## Plan 35 work item 6: rejoining a running match. A host and a client in
## one process (test/net/net_machines.gd: every machine its own router,
## screens and sound driver model, bots on its own players) on the
## loopback: the client's connection drops in mid-match, it comes back with
## its key - the same process, or a fresh one with only the rejoin record on
## disk - waits (REJOINING AT THE NEXT FACE OFF) for the host's snapshot at
## the next safe point, takes its game up from it and plays on: every hash
## after its return the host's, its player the CPU's until it is synced and
## its own again after. (A desynced client and a lost stream repaired, and
## a rejoin over real ENet: test/screens/test_online_resync.gd.)

const Machines := preload("res://test/net/net_machines.gd")
const Bots := preload("res://test/support/bots.gd")
const NetMatchTest := preload("res://test/net/test_net_match.gd")
const LOSSY := {"loss": 0.2, "delay": 120, "jitter": 30, "duplicate": 0.05, "reorder": 0.1}


func after_all() -> void:
	MwSettings.own_match_rules()
	super.after_all()


## Bots on every machine's players; P2's network status watched (as every
## machine's control layer has it) and every machine's screens.
static func _setup(w: Machines, seed_value: int) -> void:
	for m in w.machines:
		_bots(m, seed_value)


static func _bots(m: Machines.Machine, seed_value: int) -> void:
	for p in m.bot.players:
		m.bot.game_bots[p] = Bots.GameBot.new(p, seed_value)
	m.watch("net2", func(x: Machines.Machine) -> Variant:
		var c := x.rink().control if x.rink() != null else null
		return c.seat_of(2).net if c != null and c.seat_of(2) != null else null)


static func _on_rink(w: Machines) -> Callable:
	return func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool:
			return m.net_match != null and m.net_match.phase == MwNetMatch.Phase.PLAYING \
					and m.router.current_id() in [4, 5, 6])


## The period's clock run down on every machine running the game, a few
## ticks from the host's now: the period ends soon - a safe point.
static func _run_down_clock(w: Machines) -> void:
	var h := w.machines[0]
	w.at_tick(h.net_match.stream_tick(h.router.tick) + 10, func(m: Machines.Machine) -> void:
		if m.rink() != null:
			m.rink().clock = mini(m.rink().clock, 2))


## The rejoined machine [param m]'s state after its return: its hashes all
## the host's, none found to differ, its player's status DISCONNECTED (the
## CPU's) until it was synced, then HERE - on the host as on itself.
func _check_back(w: Machines, m: Machines.Machine, what: String) -> void:
	var c := w.compare_hashes()
	assert_true(c["ok"], "%s: every hash the host's - %s" % [what, c["why"]])
	assert_gt(m.net_match.hashes.size(), 100, "%s: hashes made since the return" % what)
	assert_eq(m.net_match.mismatches.size(), 0, "%s: no mismatch found" % what)
	assert_gt(int(m.net_match.stats["checked"]), 50, "%s: the host's hashes checked on the way" % what)
	var host_net: Array = w.machines[0].events["net2"]
	var codes := host_net.map(func(e: Array) -> Variant: return e[1])
	assert_true(MwTickInput.DISCONNECTED in codes, "%s: P2 the CPU's while away: %s" % [what, str(host_net)])
	assert_eq(codes.back(), MwTickInput.HERE, "%s: P2 theirs again: %s" % [what, str(host_net)])
	var mine: Array = m.events["net2"]
	assert_false(mine.is_empty())
	assert_eq(mine.back()[1], MwTickInput.HERE, "%s: on the rejoined machine too" % what)
	var back_at := int(host_net.back()[0])
	assert_gt(back_at, m.net_match.synced_at, "%s: back after the snapshot's tick" % what)
	assert_true(mine.any(func(e: Array) -> bool: return int(e[0]) == back_at),
			"%s: the same tick on both: %s / %s" % [what, str(mine), str(host_net)])
	# its FULL GAME replay starts at its return; the match's count is the host's
	var fr := m.rink().full_replay
	var host_fr := w.machines[0].rink().full_replay
	assert_eq(fr.before + fr.size(), fr.recorded())
	assert_between(fr.recorded(), host_fr.recorded() - 30, host_fr.recorded(),
			"%s: the match's frames counted as the host's (%d, %d)" % [what, fr.recorded(), host_fr.recorded()])


## A client's connection drops in mid-match (20 % loss, 120 ms delay); the
## same process comes back with its key and takes its game up at the next
## safe point - the period's end, the scoreboard's screen - then plays on
## into the next period. Then its player leaves with DISCONNECT (the own
## menu's): the key kept, it comes back again the same way.
func test_a_dropped_client_rejoins_by_key_at_20_percent() -> void:
	var w := Machines.new(self, 61, LOSSY, [1])
	_setup(w, 61)
	w.start(NetMatchTest.matchup_record(w, {1: 0, 2: 1}, [1, 2]))
	assert_true(w.run_until(_on_rink(w), 3000), "on the rink")
	w.run(240)
	var machine := w.machines[1]
	var key := machine.service.client.rejoin_key()
	assert_eq(key.size(), 32)
	w.drop(1)
	assert_true(w.run_until(func() -> bool: return machine.ended >= 0, 600), "the client's match ends")
	assert_eq(machine.ended, MwNetMatch.End.LOST, "connection lost")
	assert_eq(MwNetRejoin.key_for(World.HOST_ADDRESS, MwNetProtocol.PORT), key, "the key kept on disk")
	w.run(120)
	assert_false(bool(w.host.lobby.machines[1]["connected"]), "the host keeps it, away")
	var back := w.rejoin(1)
	assert_true(w.run_until(func() -> bool: return back.net_match != null, 1200), "back in")
	assert_eq(back.net_match.phase, MwNetMatch.Phase.WAITING, "waiting for the next faceoff")
	assert_eq(back.service.client.numbers, [2], "the same player number")
	_run_down_clock(w)
	assert_true(w.run_until(func() -> bool: return back.net_match.synced_at >= 0, 4000), "taken up from a snapshot")
	gut.p("rejoined: taken up at tick %d (screen %d), %d bytes; host: %s" % [back.net_match.synced_at,
			back.net_match.synced_screen, back.net_match.stats["snapshot_bytes"],
			str(w.machines[0].net_match.log_lines.slice(-4))])
	assert_eq(int(w.machines[0].net_match.stats["snapshots"]), 1, "one snapshot sent")
	assert_true(w.run_until(_on_rink(w), 3000), "both on the rink again")
	assert_not_null(back.session.reckoning, "plan 40's B2: a rejoined client draws with dead reckoning too")
	assert_eq(back.session.reckoning, back.net_match.reckoning, "its match's, kept through the snapshot")
	w.run(300)
	_check_back(w, back, "20 %")
	var fr := back.rink().full_replay
	assert_gt(fr.before, 0, "the first period was recorded before its return")
	assert_true(w.run_until(func() -> bool: return fr.size() > 0, 1500), "it records the match from its return")
	assert_lt(fr.size(), w.machines[0].rink().full_replay.size(), "its FULL GAME replay: less than the host's")
	# DISCONNECT: this machine leaves the match itself; its key is kept
	back.enter()
	back.net_match.leave()
	back.leave()
	assert_eq(back.net_match.end_reason, MwNetMatch.End.LEFT)
	back.ended = back.net_match.end_reason
	assert_false(MwNetRejoin.read().is_empty(), "DISCONNECT keeps the key")
	assert_true(w.run_until(func() -> bool: return not bool(w.host.lobby.machines[1]["connected"]), 600),
			"the host sees it go")
	w.run(120)
	var again := w.rejoin(1)
	assert_true(w.run_until(func() -> bool: return again.net_match != null, 1200), "REJOIN after DISCONNECT")
	_run_down_clock(w)
	assert_true(w.run_until(func() -> bool: return again.net_match.synced_at >= 0, 4000), "taken up again")
	assert_eq(int(w.machines[0].net_match.stats["snapshots"]), 2, "a second snapshot")
	assert_true(w.run_until(_on_rink(w), 3000), "both on the rink again")
	w.run(300)
	_check_back(w, again, "after DISCONNECT")
	w.free_all()


## The client's process dies on the matchup (5 % loss, 40 ms): a fresh
## process - a new router, session and sound driver, nothing of the old game
## but the rejoin record on its disk - joins the same address, offers the key
## and takes its game up at the next safe point: the rink entered at the
## period's start, the faceoff line-up.
func test_a_restarted_client_rejoins_from_its_record_at_the_faceoff() -> void:
	var w := Machines.new(self, 62, {"loss": 0.05, "delay": 40, "jitter": 20, "duplicate": 0.02, "reorder": 0.05}, [1])
	_setup(w, 62)
	w.start(NetMatchTest.matchup_record(w, {1: 0, 2: 1}, [1, 2]))
	var on_matchup := func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool:
			return m.net_match != null and m.router.current_id() == 3)
	assert_true(w.run_until(on_matchup, 600), "on the matchup")
	var h := w.machines[0]
	h.bot.quiet = true                         # the host's P1 waits on the matchup a moment
	var record := MwNetRejoin.read()
	assert_eq((record["key"] as PackedByteArray).size(), 32, "the rejoin record on disk")
	w.drop(1)
	w.machines[1].frozen = true                # the process is gone
	w.run(20)
	var back := w.rejoin(1, true)
	assert_ne(back.session, null)
	assert_eq(back.router.current(), null, "a fresh process: no game at all")
	_bots(back, 62)
	assert_true(w.run_until(func() -> bool: return back.net_match != null, 600), "back in with the key")
	assert_eq(back.net_match.phase, MwNetMatch.Phase.WAITING)
	assert_eq(back.service.client.machine, 1, "the same machine")
	h.bot.quiet = false
	assert_true(w.run_until(func() -> bool: return back.net_match.synced_at >= 0, 3000), "taken up from a snapshot")
	gut.p("restarted: taken up at tick %d (screen %d), %d bytes" % [back.net_match.synced_at,
			back.net_match.synced_screen, back.net_match.stats["snapshot_bytes"]])
	assert_true(back.net_match.synced_screen in [4, 5], "at the faceoff line-up (screen %d)"
			% back.net_match.synced_screen)
	assert_eq(back.session.online_players(), [1, 2], "the online table from the host")
	assert_eq(back.session.humans.team_of(2), 1, "its player on its team")
	assert_eq(back.session.humans.captain_of(1), 2, "and its team's captain")
	assert_true(w.run_until(_on_rink(w), 600), "both on the rink")
	w.run(400)
	_check_back(w, back, "restarted")
	w.free_all()


## Plan 36: the host's TICK RATE ORIGINAL (played as APPROXIMATED online).
## The rink's pacer is the rink scene's, made anew at each rink entry, and
## snapshots are taken as a screen is entered - so a fresh process taken up
## at the faceoff line-up paces the passes as the host does: the same pass
## lengths at the same stream ticks from then on, every hash the host's
## (the pacer's state in them).
func test_a_restarted_client_rejoins_paced_as_the_host() -> void:
	var was := MwSettings.tick_rate
	MwSettings.tick_rate = "ORIGINAL"
	var w := Machines.new(self, 63, {"loss": 0.05, "delay": 40, "jitter": 20, "duplicate": 0.02, "reorder": 0.05}, [1])
	_setup(w, 63)
	var record := NetMatchTest.matchup_record(w, {1: 0, 2: 1}, [1, 2])
	assert_eq(str(record["rules"]["tick_rate"]), "ORIGINAL", "the host's rule")
	w.start(record)
	var on_matchup := func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool:
			return m.net_match != null and m.router.current_id() == 3)
	assert_true(w.run_until(on_matchup, 600), "on the matchup")
	var h := w.machines[0]
	h.bot.quiet = true
	w.drop(1)
	w.machines[1].frozen = true
	w.run(20)
	# (one process: MwSettings is every machine's, so the fresh process's own
	# TICK RATE can't differ here; the snapshot's session puts the host's
	# rules in force on it, MwNetMatch._load)
	var back := w.rejoin(1, true)
	_bots(back, 63)
	var lens := {}                             # machine -> {stream tick: elapsed} of its rink passes
	for m in [h, back]:
		var mine := {}
		lens[m] = mine
		var mm: Machines.Machine = m
		m.router.pass_ended.connect(func(b: Dictionary) -> void:
			if int(b.screen) in [4, 5, 6] and mm.net_match != null:
				mine[mm.net_match.stream_tick(mm.router.tick)] = int(b.elapsed))
	assert_true(w.run_until(func() -> bool: return back.net_match != null, 600), "back in with the key")
	h.bot.quiet = false
	assert_true(w.run_until(func() -> bool: return back.net_match.synced_at >= 0, 3000), "taken up from a snapshot")
	assert_true(back.net_match.synced_screen in [4, 5], "at the faceoff line-up (screen %d)"
			% back.net_match.synced_screen)
	assert_true(w.run_until(_on_rink(w), 600), "both on the rink")
	w.run(600)
	_check_back(w, back, "paced")
	assert_eq(MwSettings.rink_tick_rate(true), "APPROXIMATED", "the host's rule in force, online")
	var hl: Dictionary = lens[h]
	var bl: Dictionary = lens[back]
	var from := back.net_match.stream_tick(back.net_match.synced_at)
	var upto := mini(h.net_match.stream_tick(h.router.tick), back.net_match.stream_tick(back.router.tick))
	var same := 0
	var odd := 0
	for t: int in hl:
		if t <= from or t > upto:
			continue
		assert_eq(bl.get(t, -1), hl[t], "stream tick %d: the host's pass, as long" % t)
		same += 1
		if int(hl[t]) != 2:
			odd += 1
	for t: int in bl:
		if t > from and t <= upto:
			assert_true(hl.has(t), "stream tick %d: no pass of its own" % t)
	assert_gt(same, 100, "rink passes compared after the return")
	assert_gt(odd, same / 4, "paced (%d of %d not 2 ticks)" % [odd, same])
	gut.p("paced rejoin: taken up at tick %d (screen %d); %d passes the host's, %d not of 2 ticks" % [
			back.net_match.synced_at, back.net_match.synced_screen, same, odd])
	w.free_all()
	MwSettings.tick_rate = was
