extends "res://test/net/net_test_base.gd"
## The soak's slow uplink (docs/net.md "A slow uplink"): the host's pace
## (MwNetPace) keeps a STREAM every tick on a steady line, busy frames and
## jitter included; a queue standing in front of the line makes it every
## second tick (a gap waiting for a resend doesn't), and the line clear for a
## while makes it every tick again - after a relapse only after twice as
## long. On the loopback a machine whose round trip stands high gets its
## stream every second tick and still holds every tick and every press, its
## buffer's step 2 (MwNetTickReceiver.step).

const Chaos := preload("res://test/net/net_chaos.gd")

var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	super.before_each()
	_rng.seed = 7


## Feeds [param pace] a round trip a frame from [param from_ms] for [param
## ms]: [param rtt] plus up to [param jitter]. The time after.
func _feed(pace: MwNetPace, from_ms: int, ms: int, rtt: int, jitter := 10) -> int:
	var t := from_ms
	while t < from_ms + ms:
		pace.sample(rtt + _rng.randi_range(0, jitter), t)
		t += 17
	return t


func test_round_trips_from_the_acknowledgements() -> void:
	var pace := MwNetPace.new()
	pace.sent(10, 1000)
	pace.sent(12, 1033)
	pace.sent(12, 1050)                         # the same newest again: its first send counts
	pace.sent(14, 1067)
	pace.acked(12, 1150)
	assert_eq(pace.round_trip, 117, "the newest packet the acknowledgement covers: tick 12's, sent at 1033")
	pace.acked(12, 1180)
	assert_eq(pace.round_trip, 117, "nothing newly acknowledged: no round trip")
	pace.acked(20, 1250)
	assert_eq(pace.round_trip, 183, "tick 14's")
	pace.sent(16, 1300)
	pace.forget()
	pace.acked(16, 1400)
	assert_eq(pace.round_trip, 183, "forgotten (a resync snapshot): no round trip")


func test_a_steady_line_keeps_every_tick() -> void:
	var pace := MwNetPace.new()
	var t := _feed(pace, 0, 5000, 100, 30)
	for i in 10:
		# a screen being made on one machine: nothing for 350 ms, then the late ones, then as before
		t += 350
		pace.sample(450, t)
		pace.sample(430, t + 17)
		t = _feed(pace, t + 34, 3000, 100, 30)
	assert_eq(pace.stride, 1, "every tick")
	assert_eq(pace.stats["slowed"], 0)
	assert_between(pace.queue_ms, 0, MwNetPace.CLEAR_MS)


## Heavy loss isn't a full line: the stream stuck at a gap acknowledges
## nothing until a resend fills it, then the late acknowledgements come at
## once - a few high round trips after a stretch of none, no window of
## their own.
func test_a_gap_waiting_for_a_resend_is_no_queue() -> void:
	var pace := MwNetPace.new()
	var t := _feed(pace, 0, 3000, 300, 30)
	for i in 6:
		t += 1500
		for k in 3:
			pace.sample(1800 - 17 * k, t)
			t += 17
		t = _feed(pace, t, 1500, 300, 30)
	assert_eq(pace.stride, 1, "every tick")
	assert_eq(pace.stats["slowed"], 0)


func test_a_queue_slows_it_and_a_clear_line_speeds_it_up() -> void:
	var pace := MwNetPace.new()
	var t := _feed(pace, 0, 3000, 80)
	assert_eq(pace.stride, 1)
	# the line fills: the round trip climbs 50 ms every 100 ms to a 250 ms queue, and stays
	for k in 5:
		t = _feed(pace, t, 100, 80 + 50 * (k + 1))
	var full := t
	while pace.stride == 1 and t < full + 3000:
		t = _feed(pace, t, 17, 330)
	assert_eq(pace.stride, 2, "a standing queue: every second tick")
	assert_lt(t - full, 1100, "within a window or two")
	# every second tick drains it
	t = _feed(pace, t, MwNetPace.BACK_MS - 1000, 85)
	assert_eq(pace.stride, 2, "not yet: clear for less than BACK_MS")
	t = _feed(pace, t, 2000, 85)
	assert_eq(pace.stride, 1, "clear for BACK_MS: every tick again")
	# straight back into the queue: a relapse, so the next wait is twice as long
	t = _feed(pace, t, 1500, 330)
	assert_eq(pace.stride, 2)
	t = _feed(pace, t, MwNetPace.BACK_MS + 1500, 85)
	assert_eq(pace.stride, 2, "after a relapse it waits twice as long")
	t = _feed(pace, t, MwNetPace.BACK_MS, 85)
	assert_eq(pace.stride, 1)
	assert_eq(pace.stats["slowed"], 2)
	assert_gt(int(pace.stats["slow_ms"]), 3 * MwNetPace.BACK_MS)
	assert_gt(int(pace.stats["queue_max_ms"]), 200)


## The loopback (no line to fill, so the queue is a longer delay): one
## client at 30 ms, then 160 ms - a 130 ms queue - for 5 s, then 30 ms
## again. The host's stream to it goes every second tick and back; the
## client's step follows; every tick, hash and press arrives.
func test_a_slow_line_gets_every_second_tick() -> void:
	var world := World.new(5, "", {"delay": 30, "jitter": 5})
	var client := world.join("", 1)
	assert_true(world.run_until(func() -> bool: return client.state == MwNetClient.State.LOBBY), "joined")
	world.host.start_match(PackedByteArray([1]))
	var presser := Chaos.Presser.new(11)
	var host_ticks: Array[PackedByteArray] = []
	var phases := [[3000, 30], [5000, 160], [MwNetPace.BACK_MS + 4000, 30], [1500, 30]]
	var seen := {}                              # phase -> [strides seen, client steps seen, packets, ticks]
	var hashed := PackedInt32Array()
	for ph in phases.size():
		world.net.set_conditions({"delay": phases[ph][1]})
		var end: int = world.net.now_ms + int(phases[ph][0])
		var strides := {}
		var steps := {}
		var packets0 := int(client.stream.stats["packets"])
		var ticks0 := host_ticks.size()
		while world.net.now_ms < end:
			world.net.advance(17 if world.net.now_ms % 3 != 2 else 16)
			world.poll()
			var active := client.state == MwNetClient.State.RUNNING and ph < phases.size() - 1
			client.send_input({2: presser.next(active)})
			host_ticks.append(world.host.step({1: MwNetInput.blank()}))
			if world.host.tick % 2 == 0:
				var h := PackedByteArray([world.host.tick & 0xFF, 1, 2, 3, 4, 5, 6, 7])
				world.host.add_hash(world.host.tick, 0, h)
				hashed.append(world.host.tick)
			strides[world.host.pace_of(1).stride] = true
			steps[client.stream.step()] = true
		seen[ph] = [strides.keys(), steps.keys(), int(client.stream.stats["packets"]) - packets0,
				host_ticks.size() - ticks0]
	var pace := world.host.pace_of(1)
	assert_eq(seen[0][0], [1], "30 ms: every tick")
	assert_has(seen[1][0], 2, "a 130 ms queue: every second tick")
	assert_eq(int(pace.stats["slowed"]), 1)
	assert_lt(int(seen[1][2]), int(seen[1][3]) * 3 / 4, "fewer STREAM packets than ticks: %s" % str(seen[1]))
	assert_has(seen[1][1], 2, "the client's buffer sees two ticks a packet")
	assert_eq(pace.stride, 1, "30 ms again for BACK_MS: every tick")
	assert_eq(client.stream.step(), 1)
	# everything arrived (the last ticks' packets still on their way)
	world.run_until(func() -> bool: return client.stream.confirmed >= world.host.tick, 2000)
	assert_eq(client.state, MwNetClient.State.RUNNING)
	assert_eq(client.stream.confirmed, world.host.tick, "the client holds every tick")
	var same := true
	var counted := {}
	var prev := MwNetInput.blank_tick()
	for i in host_ticks.size():
		same = same and client.stream.get_tick(i) == host_ticks[i] if client.stream.has(i) else same
		for v in Chaos.VERBS:
			counted[v] = int(counted.get(v, 0)) + MwNetInput.presses(MwNetInput.player(prev, 2),
					MwNetInput.player(host_ticks[i], 2), v)
		prev = host_ticks[i]
	assert_true(same, "the ticks it still holds are the host's")
	for v in Chaos.VERBS:
		assert_eq(int(counted.get(v, 0)), int(presser.presses.get(v, 0)), "every press of verb %d" % v)
	var missing := 0
	for n in hashed:
		if n < world.host.tick - 2 * MwNetProtocol.MAX_TICKS and client.host_hash(n, 0).is_empty():
			missing += 1
	assert_eq(missing, 0, "every hash came (each goes out every %d ticks while recent)" % MwNetHost.HASH_EVERY)
