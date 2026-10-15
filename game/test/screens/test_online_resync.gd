extends "res://test/net/net_test_base.gd"
## Plan 35 work item 6: resync snapshots repairing a running match, a host
## and a client in one process (test/net/net_machines.gd): a client whose
## game parts from the host's (its random stream nudged) finds it, tells the
## host (DESYNC) and is repaired by a snapshot at the next safe point; a
## client whose stream has a gap the host no longer holds (a 9.5 s outage:
## the host keeps 512 ticks) asks for those ticks, so the host knows it owes
## it a snapshot, and it is repaired the same way; and a client rejoining
## over real ENet with DTLS
## on 127.0.0.1. Every hash after the repair the host's. (Rejoining on the
## loopback - in the same process, as a fresh one, at 20 % loss: test/net/
## test_net_rejoin.gd.)

const Machines := preload("res://test/net/net_machines.gd")
const NetMatchTest := preload("res://test/net/test_net_match.gd")
const RejoinTest := preload("res://test/net/test_net_rejoin.gd")


func after_all() -> void:
	MwSettings.own_match_rules()
	super.after_all()


## Repaired machine [param machine]: its hashes since its game was taken up all
## the host's, no mismatch found since, the game going on.
func _check_repaired(w: Machines, machine: Machines.Machine, mismatches_before: int, what: String) -> void:
	var c := w.compare_hashes()
	assert_true(c["ok"], "%s: every hash since the repair the host's - %s" % [what, c["why"]])
	assert_gt(machine.net_match.hashes.size(), 100, "%s: hashes made since" % what)
	assert_gt(int(machine.net_match.stats["checked"]), 50, "%s: the host's hashes checked" % what)
	assert_eq(int(machine.net_match.stats.get("mismatches", 0)), mismatches_before, "%s: none differ since" % what)


func test_a_desynced_client_is_repaired_by_a_snapshot() -> void:
	var w := Machines.new(self, 71, {}, [1])
	RejoinTest._setup(w, 71)
	w.start(NetMatchTest.matchup_record(w, {1: 0, 2: 1}, [1, 2]))
	assert_true(w.run_until(RejoinTest._on_rink(w), 3000), "on the rink")
	w.run(60)
	var machine := w.machines[1]
	assert_eq(machine.net_match.mismatches.size(), 0, "in step so far")
	machine.session.rng.state ^= 0x10                     # the client's game parts from the host's
	assert_true(w.run_until(func() -> bool: return not machine.net_match.mismatches.is_empty(), 120), \
			"the client finds it")
	w.run(60)
	assert_true("\n".join(w.machines[0].net_match.log_lines).contains("disagrees"), "the host heard (DESYNC)")
	RejoinTest._run_down_clock(w)
	assert_true(w.run_until(func() -> bool: return machine.net_match.synced_at >= 0, 3000), "a snapshot taken up")
	var found := int(machine.net_match.stats["mismatches"])
	gut.p("desync: found at %s, repaired at tick %d (screen %d), %d bytes; %d mismatches before" % [
			str(machine.net_match.mismatches[0]["tick"]), machine.net_match.synced_at, machine.net_match.synced_screen,
			machine.net_match.stats["snapshot_bytes"], found])
	assert_true(w.run_until(RejoinTest._on_rink(w), 3000), "back on the rink")
	w.run(300)
	_check_repaired(w, machine, found, "desync")
	w.free_all()


func test_a_lost_stream_is_recovered_by_a_snapshot() -> void:
	var w := Machines.new(self, 72, {"delay": 30, "jitter": 10}, [1])
	RejoinTest._setup(w, 72)
	w.start(NetMatchTest.matchup_record(w, {1: 0, 2: 1}, [1, 2]))
	assert_true(w.run_until(RejoinTest._on_rink(w), 3000), "on the rink")
	w.run(60)
	var machine := w.machines[1]
	var t0 := w.world.net.now_ms
	var outages: Array[Vector2i] = [Vector2i(t0 + 100, t0 + 9600)]
	w.world.net.outages = outages                    # longer than the host keeps the stream (512 ticks)
	var host_heard := func() -> bool:
		return "\n".join(w.host.log_lines).contains("the stream no longer holds them")
	assert_true(w.run_until(host_heard, 1200), "the client asked for ticks the host no longer keeps")
	var rx := machine.service.client.stream
	assert_gt(int(rx.stats["requests"]), 0, "it asked for them again")
	assert_lt(rx.confirmed, w.host.tick - 500, "its game stuck at the gap")
	var stuck := rx.confirmed
	RejoinTest._run_down_clock(w)
	assert_true(w.run_until(func() -> bool: return machine.net_match.synced_at >= 0, 3000), "a snapshot taken up")
	gut.p("lost: recovered at tick %d (screen %d), %d bytes"
			% [machine.net_match.synced_at, machine.net_match.synced_screen,
			machine.net_match.stats["snapshot_bytes"]])
	assert_false(machine.service.client.stream.lost, "the stream whole again")
	assert_gt(machine.net_match.synced_at, stuck + 500, "taken up past the gap")
	assert_true(w.run_until(RejoinTest._on_rink(w), 3000), "back on the rink")
	w.run(300)
	_check_repaired(w, machine, 0, "lost")
	w.free_all()


## The client's connection drops over real ENet with DTLS on 127.0.0.1; it
## comes back with its key (its pinned certificate remembered) and takes its
## game up from a snapshot sent in chunks over DTLS.
func test_a_rejoin_over_enet_with_dtls() -> void:
	var w := Machines.new(self, 73, {}, [1], 1, MwNetIdentity.create())
	assert_eq(w.clients[0].state, MwNetClient.State.LOBBY, "joined over DTLS")
	RejoinTest._setup(w, 73)
	w.start(NetMatchTest.matchup_record(w, {1: 0, 2: 1}, [1, 2]))
	assert_true(w.run_until(RejoinTest._on_rink(w), 3000), "on the rink")
	w.run(200)
	var machine := w.machines[1]
	w.drop(1)
	var end := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < end and (machine.ended < 0 or bool(w.host.lobby.machines[1]["connected"])):
		w.frame()
		OS.delay_msec(2)
	assert_eq(machine.ended, MwNetMatch.End.LOST, "the client's match ended")
	assert_false(bool(w.host.lobby.machines[1]["connected"]), "the host saw it go")
	var back := w.rejoin(1)
	end = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < end and back.net_match == null:
		w.host.poll(w.now())
		back.service.client.poll(w.now())
		OS.delay_msec(2)
	assert_not_null(back.net_match, "back in over DTLS")
	if back.net_match == null:
		w.free_all()
		return
	assert_eq(back.net_match.phase, MwNetMatch.Phase.WAITING)
	RejoinTest._run_down_clock(w)
	end = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end and back.net_match.synced_at < 0:
		w.frame()
		OS.delay_msec(1)
	assert_gt(back.net_match.synced_at, 0, "taken up from a snapshot over DTLS")
	gut.p("ENet: taken up at tick %d (screen %d), %d bytes" % [back.net_match.synced_at, back.net_match.synced_screen,
			back.net_match.stats["snapshot_bytes"]])
	end = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end and not RejoinTest._on_rink(w).call():
		w.frame()
		OS.delay_msec(1)
	w.run(300)
	var cmp := w.compare_hashes()
	assert_true(cmp["ok"], "ENet: every hash since the return the host's - %s" % cmp["why"])
	assert_gt(int(cmp["compared"]), 100, "ENet: hashes compared")
	assert_eq(back.net_match.mismatches.size(), 0)
	w.host.close()
	w.run(30)
	w.free_all()
	end = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end and not MwNetEnet._lingering.is_empty():
		MwNetEnet.service_lingering()
		OS.delay_msec(2)
	for e in get_errors():
		if e.contains_text("TLS handshake") or e.contains_text("mbedtls"):
			e.handled = true
