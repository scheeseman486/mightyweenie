extends RefCounted
## The chaos run shared by test_net_chaos (fast, in every test run) and
## net_soak.gd (long): a host and three clients on the loopback network
## (MwNetLoopback) under a link condition, every machine's players pressing
## a seeded pattern, then a quiet drain. Reports what the checks need:
## whether every client rebuilt exactly the host's stream, whether every
## press arrived (and one a tick), the stalls (a tick's wait from the host
## making it to the client holding it with all before: the longest overall,
## and the longest among ticks made after the client had START - the first
## ticks wait for START itself, then for a resend), traffic.
##
## Machines: the host with players 1 and 6 (its second local joined in the
## lobby), clients with 1, 2 and 1 local players (2, 3-4, 5).

const I := preload("res://src/net/net_input.gd")
const P := preload("res://src/net/net_protocol.gd")
const NetBase := preload("res://test/net/net_test_base.gd")
## The verbs the pattern presses (a few of each kind).
const VERBS := [0, 3, 4, 7, 10, 13, 14, 23, 27, 30]


## One player's scripted input.
class Presser:
	var rng := RandomNumberGenerator.new()
	var state := MwNetInput.blank()
	var held := {}
	var presses := {}
	var stick := Vector2i.ZERO

	func _init(seed_value: int) -> void:
		rng.seed = seed_value

	## The next tick's state ([param active]: still pressing; else
	## releasing everything).
	func next(active: bool) -> PackedByteArray:
		var pressed := PackedInt32Array()
		for v in held.keys():
			held[v] -= 1
			if held[v] <= 0:
				held.erase(v)
		if active:
			for v in VERBS:
				if not held.has(v) and rng.randf() < 0.04:
					held[v] = rng.randi_range(1, 7)
					pressed.append(v)
					presses[v] = int(presses.get(v, 0)) + 1
			if rng.randf() < 0.05:
				stick = Vector2i(rng.randi_range(0, 255), rng.randi_range(0, 255))
		else:
			stick = Vector2i.ZERO
		var hv := PackedInt32Array()
		for v in held:
			hv.append(v)
		state = MwNetInput.next_state(state, hv, pressed, stick)
		return state


## Runs a match under [param conditions] (MwNetLoopback.set_conditions;
## "outages" relative to the match's start) for [param ticks] ticks of
## presses and [param drain] quiet ones. Returns a report.
static func run(conditions: Dictionary, seed_value: int, ticks: int, drain := 300) -> Dictionary:
	var started := Time.get_ticks_msec()
	var link := conditions.duplicate()
	link.erase("outages")
	var world := NetBase.World.new(seed_value, "pw", link)
	var report := {"ok": false, "why": ""}
	world.host.join_local(2)
	var clients: Array[MwNetClient] = [world.join("pw", 1), world.join("pw", 2), world.join("pw", 1)]
	var all_in := func() -> bool:
		for c in clients:
			if c.state != MwNetClient.State.LOBBY:
				return false
		return true
	if not world.run_until(all_in, 60000):
		report["why"] = "not all joined: %s" % str(clients.map(func(c: MwNetClient) -> int: return c.state))
		return report
	report["join_ms"] = world.net.now_ms
	world.run(500)
	world.host.start_match(PackedByteArray([1]))
	var t0 := world.net.now_ms
	var outages: Array[Vector2i] = []
	for o: Vector2i in conditions.get("outages", []):
		outages.append(Vector2i(t0 + o.x, t0 + o.y))
	world.net.outages = outages
	var pressers := {}
	for n in range(1, 7):
		pressers[n] = Presser.new(seed_value * 100 + n)
	var host_ticks: Array[PackedByteArray] = []
	var host_time := PackedInt32Array()
	var got: Array = [[], [], []]
	var got_time: Array = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	var max_stall := 0
	var max_stall_tick := -1
	var max_steady := 0
	var stall_sum := 0
	var stall_n := 0
	var run_at := [-1, -1, -1]
	var all_running := false
	var press_from := -1
	for step in ticks + drain:
		var dt := 17 if step % 3 != 2 else 16
		world.net.advance(dt)
		world.poll()
		if not all_running:
			all_running = clients.all(func(c: MwNetClient) -> bool: return c.state == MwNetClient.State.RUNNING)
			if all_running:
				press_from = step
		var active := all_running and step < ticks
		for ci in clients.size():
			var c := clients[ci]
			var states := {}
			for n in c.numbers:
				states[n] = (pressers[n] as Presser).next(active)
			c.send_input(states)
		var local := {1: (pressers[1] as Presser).next(active), 6: (pressers[6] as Presser).next(active)}
		host_ticks.append(world.host.step(local))
		host_time.append(world.net.now_ms)
		for ci in clients.size():
			var c := clients[ci]
			var mine: Array = got[ci]
			if run_at[ci] < 0 and c.state == MwNetClient.State.RUNNING:
				run_at[ci] = world.net.now_ms
			while mine.size() <= c.stream.confirmed:
				mine.append(c.stream.get_tick(mine.size()))
				(got_time[ci] as PackedInt32Array).append(world.net.now_ms)
				var made: int = host_time[mine.size() - 1]
				var stall: int = world.net.now_ms - made
				if stall > max_stall:
					max_stall = stall
					max_stall_tick = mine.size() - 1
				# a tick made once the client knew the match had started
				if made >= int(run_at[ci]):
					max_steady = maxi(max_steady, stall)
				stall_sum += stall
				stall_n += 1
	report["ticks"] = host_ticks.size()
	report["max_stall_ms"] = max_stall
	report["max_stall_tick"] = max_stall_tick
	report["max_steady_stall_ms"] = max_steady
	report["start_ms"] = run_at.map(func(t: int) -> int: return t - t0)
	report["mean_stall_ms"] = stall_sum / maxi(1, stall_n)
	report["press_from"] = press_from
	# every client rebuilt the host's stream exactly
	for ci in clients.size():
		var mine: Array = got[ci]
		report["confirmed_%d" % ci] = mine.size()
		if clients[ci].state != MwNetClient.State.RUNNING:
			report["why"] = "client %d ended: %d" % [ci, clients[ci].fail]
			return report
		if mine.size() < host_ticks.size() - 30:
			report["why"] = "client %d confirmed %d of %d ticks" % [ci, mine.size(), host_ticks.size()]
			return report
		for i in mine.size():
			if mine[i] != host_ticks[i]:
				report["why"] = "client %d tick %d differs" % [ci, i]
				return report
	# every press arrived, one a tick
	var counted := {}
	var prev := MwNetInput.blank_tick()
	for t in host_ticks:
		for n in range(1, 7):
			var a := MwNetInput.player(prev, n)
			var b := MwNetInput.player(t, n)
			for v in VERBS:
				var d := MwNetInput.presses(a, b, v)
				if d > 1:
					report["why"] = "two presses of one verb in one tick"
					return report
				counted[n * 100 + v] = int(counted.get(n * 100 + v, 0)) + d
		prev = t
	var total := 0
	for n in range(1, 7):
		for v in VERBS:
			var want := int((pressers[n] as Presser).presses.get(v, 0))
			total += want
			if int(counted.get(n * 100 + v, 0)) != want:
				report["why"] = "player %d verb %d: %d presses arrived of %d" % [n, v,
						int(counted.get(n * 100 + v, 0)), want]
				return report
	report["presses"] = total
	report["net"] = world.net.stats.duplicate()
	report["requests"] = clients.map(func(c: MwNetClient) -> int: return c.stream.stats["requests"])
	report["wall_ms"] = Time.get_ticks_msec() - started
	report["ok"] = true
	return report
