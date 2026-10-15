extends "res://test/net/net_test_base.gd"
## Plan 35 work item 6, the pieces of rejoin and resync: the object graph
## codec a snapshot uses (MwNetGraph: shared objects stay shared, typed
## arrays typed, random number generators and floats exact, a machine's own
## left alone, only the game's classes made, garbage never crashes it); the
## snapshot's bytes (MwNetSnapshot); its chunks (MwNetChunks: any order,
## duplicates, contradictions, stale ones); a snapshot over the loopback at
## 20 % loss (the stream started again at its tick, RESYNC and SYNCED
## heard); a kicked machine's key refused; a stale key let go. (Whole
## matches: test_net_rejoin.gd and test/screens/test_online_resync.gd.)
## Short names: g the MwNetGraph under test.

const P := preload("res://src/net/net_protocol.gd")


## A session with a rink state in it: the rink's random stream and playoffs
## the session's, a control layer pointing back at it, a camera target and
## a carrier inside it, a crowd and benches with their own random numbers
## and floats, a replay ring with bytes in it, a whole-match recording.
static func _session() -> MwSession:
	var session := MwSession.new(5, 6)
	session.port_stream(MwSession.STREAM_CROWD).next_state()
	session.online = {"players": [1, 2], "machines": {"1": 0, "2": 1}}
	session.screens["starfield"] = [1, 2, 3, 4]
	session.lineup_teams = [3, 8]
	var state := MwRinkState.new()
	state.rng = session.rng
	state.playoffs = session.playoffs
	state.camera_target = state.teams[0].players[2]
	state.puck.carrier = state.teams[1].players[4]
	state.teams[0].players[2].motion.pos = PackedInt32Array([100, -200, 0])
	state.clock = 123
	var control := MwRinkControl.new()
	for p in [1, 2]:
		var seat := MwRinkControl.Seat.new()
		seat.player = p
		seat.team = p - 1
		seat.menu = {"items": ["RESUME", "QUIT GAME"], "sel": 1}
		control.seats.append(seat)
	control.kicks.append(3)
	control._s = state
	state.control = control
	state.crowd_life = MwCrowdLife.new(77)
	state.crowd_life.step(2, 900, Vector2i(2, 1), true)
	state.crowd_life.start_wave()
	state.bench_life = MwBenchLife.new(77)
	state.bench_life.figs["0.1"] = {"team": 0, "p": 0.25, "from": Vector2(3.5, -1.25)}
	state.splatter = MwSplatter.new(77)
	state.replay.reset()
	state.replay.open_frame(2)
	state.replay.put_long(0x12345678)
	state.replay.close_frame()
	state.replay.side[0] = {"presentation": true}
	state.full_replay = MwFullReplay.new()
	state.full_replay.add_frame(PackedByteArray([1, 2, 3, 4]), {})
	state.full_replay.add_frame(PackedByteArray([5, 6, 7, 8]), {})
	session.screens["rink"] = state
	return session


func _round_trip(encoded: Variant) -> Variant:
	return bytes_to_var(var_to_bytes(encoded))


func test_a_session_graph_round_trips() -> void:
	var original := _session()
	var g := MwNetSnapshot.codec()
	var encoded: Variant = g.encode(original)
	assert_eq(g.errors, PackedStringArray(), "everything carried")
	var session := MwSession.new(9, 9)
	var service := MwNetService.new()
	session.net = service
	session.machine = 4
	@warning_ignore("int_as_enum_without_match")
	session.view = 3
	var graph := MwNetSnapshot.codec()
	assert_true(graph.decode_into(session, _round_trip(encoded)))
	assert_eq(graph.errors, PackedStringArray(), "everything taken")
	var state: MwRinkState = session.screens["rink"]
	var was: MwRinkState = original.screens["rink"]
	assert_same(state.rng, session.rng, "the rink's stream is the session's")
	assert_same(state.playoffs, session.playoffs, "and its playoffs")
	assert_same(session.playoffs.hardware, session.streams[MwSession.STREAM_HARDWARE], "the hardware stream shared")
	assert_same(state.control._s, state, "the control layer points back at the state")
	assert_same(state.camera_target, state.teams[0].players[2], "the camera's target inside the state")
	assert_same(state.puck.carrier, state.teams[1].players[4], "the carrier too")
	assert_true(state.teams.is_typed() and state.control.seats.is_typed() and state.control.kicks.is_typed(),
			"typed arrays stay typed")
	assert_eq(state.control.seats[1].menu, {"items": ["RESUME", "QUIT GAME"], "sel": 1})
	assert_eq(MwNetHash.rink(state), MwNetHash.rink(was), "the rink's hash")
	assert_eq(MwNetHash.session(session), MwNetHash.session(original), "the session's hash")
	assert_eq(session.screens["starfield"], [1, 2, 3, 4])
	# the crowd: floats exact, its random numbers going on alike
	assert_eq(state.crowd_life.life, was.crowd_life.life)
	assert_eq(state.crowd_life.wave_from, was.crowd_life.wave_from)
	assert_eq(state.crowd_life.snapshot(), was.crowd_life.snapshot())
	state.crowd_life.start_wave()
	was.crowd_life.start_wave()
	assert_eq(state.crowd_life.wave_from, was.crowd_life.wave_from, "its random numbers go on alike")
	assert_eq(state.bench_life.figs, was.bench_life.figs)
	assert_null(state.splatter, "the arena's paint is presentation: the rink's entry makes it afresh (plan 37)")
	# the replay ring whole, its 3D side-store left out; the whole match's recording as its count
	assert_eq(state.replay.ring_bytes, was.replay.ring_bytes)
	assert_eq([state.replay.write, state.replay.frames], [was.replay.write, was.replay.frames])
	assert_eq(state.replay.side, {}, "the 3D side-store is presentation")
	assert_eq(state.full_replay.size(), 0, "a rejoiner's FULL GAME replay starts at its return")
	assert_eq(state.full_replay.recorded(), 2, "but the match's count is kept")
	# the machine's own stays
	assert_same(session.net, service, "the online service is this machine's")
	assert_eq([session.machine, session.view], [4, 3], "and its id and view")
	# every main stream number goes on alike
	for i in 5:
		assert_eq(session.rng.next_state(), original.rng.next_state())


func test_the_openings_paint_is_left_out_of_the_entry_data() -> void:
	var life := MwCrowdLife.new(5)
	var data := {"crowd_life": life, "splatter": MwSplatter.new(5)}
	var carried: Dictionary = MwNetSnapshot.carried_data(data)
	assert_eq(carried.keys(), ["crowd_life"], "the crowd goes, the paint stays the machine's own (plan 37)")
	assert_same(carried["crowd_life"], life)
	assert_true(data.has("splatter"), "the screen's own data untouched")
	assert_eq(MwNetSnapshot.carried_data({"a": 1}), {"a": 1})


func test_only_the_games_classes_are_made() -> void:
	for key in ["MwNetService", "MwNetHost", "MwAudio", "MwRink", "Node", "GutTest", "MwNoSuchClass",
			"MwRinkState.NoSuch", "MwNetGraph"]:
		var graph := MwNetGraph.new()
		var v: Variant = graph.decode([MwNetGraph.Tag.OBJECT, 0, key])
		assert_null(v, "%s not made" % key)
		assert_false(graph.errors.is_empty(), "%s refused" % key)
	var g := MwNetGraph.new()
	assert_true(g.decode([MwNetGraph.Tag.OBJECT, 0, "MwRinkState.Player"]) is MwRinkState.Player, "an inner class")
	assert_eq(MwNetGraph.key_of(MwRinkControl.Seat), "MwRinkControl.Seat")
	assert_eq(MwNetGraph.key_of(MwMotion.Params), "MwMotion.Params")


func test_what_isnt_the_games_is_left_out() -> void:
	var node := Node.new()
	var g := MwNetGraph.new()
	var encoded: Variant = g.encode([node, func() -> void: pass, 5, {"a": node, "b": 2}, Image.new()])
	assert_eq(encoded, [MwNetGraph.Tag.ARRAY, null, null, 5, [MwNetGraph.Tag.DICT, "b", 2], null])
	node.free()
	assert_false(MwNetGraph.carried(Image.new()), "a Resource")
	assert_false(MwNetGraph.carried(Callable()), "a callable")
	assert_true(MwNetGraph.carried(RandomNumberGenerator.new()), "Godot's random numbers")
	assert_true(MwNetGraph.carried(MwMotion.new()), "the game's objects")


func test_garbage_never_crashes_the_codec() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var good: Variant = MwNetSnapshot.codec().encode(_session())
	var made := 0
	for i in 400:
		var encoded: Variant = _mutate(good.duplicate(true), rng, 6)
		var g := MwNetSnapshot.codec()
		var target := MwSession.new(1, 1)
		if g.decode_into(target, encoded):
			made += 1
		g.decode(encoded)
	assert_gt(made, 0, "some mutations still decode (the codec went deep)")


## [param v] with a few of its leaves or tags changed at random.
static func _mutate(v: Variant, rng: RandomNumberGenerator, n: int) -> Variant:
	for k in n:
		var path: Array = []
		var at: Variant = v
		while at is Array and not (at as Array).is_empty() and rng.randf() < 0.85:
			var i := rng.randi_range(0, (at as Array).size() - 1)
			path.append(i)
			if not at[i] is Array:
				break
			at = at[i]
		if path.is_empty():
			continue
		var container: Variant = v
		for j in path.size() - 1:
			container = container[path[j]]
		var choices := [null, -1, 99999, "x", [], [MwNetGraph.Tag.REF, 9999], [MwNetGraph.Tag.OBJECT, 0, "MwHumans"],
				PackedByteArray([1]), 1.5, true, [MwNetGraph.Tag.TYPED, TYPE_INT, "", "", "y"]]
		container[path[-1]] = choices[rng.randi_range(0, choices.size() - 1)]
	return v


func test_snapshot_bytes_checked() -> void:
	var d := {"format": MwNetSnapshot.FORMAT, "tick": 10, "base": 1, "screen": 5, "previous": 12, "fade": true,
			"ticks": -1, "session": [], "data": [], "audio": {}, "sound": {}, "router": {}, "seen": PackedByteArray()}
	var b := MwNetSnapshot.to_bytes(d)
	assert_eq(MwNetSnapshot.from_bytes(b), d)
	var wrong := d.duplicate()
	wrong["tick"] = "10"
	assert_eq(MwNetSnapshot.from_bytes(MwNetSnapshot.to_bytes(wrong)), {}, "a key of another type")
	wrong = d.duplicate()
	wrong.erase("router")
	assert_eq(MwNetSnapshot.from_bytes(MwNetSnapshot.to_bytes(wrong)), {}, "a key missing")
	wrong = d.duplicate()
	wrong["format"] = 99
	assert_eq(MwNetSnapshot.from_bytes(MwNetSnapshot.to_bytes(wrong)), {}, "another format")
	assert_eq(MwNetSnapshot.from_bytes(b.slice(0, b.size() - 3)), {}, "cut short")
	var big := b.duplicate()
	big[0] = 0x7F
	assert_eq(MwNetSnapshot.from_bytes(big), {}, "a length over the cap")
	assert_eq(MwNetSnapshot.from_bytes(PackedByteArray([0, 0, 0, 4, 1, 2, 3])), {}, "garbage")


# --- chunks -----------------------------------------------------------------------------------------

func _chunk_messages(id: int, tick: int, data: PackedByteArray) -> Array:
	var out := []
	var parts := MwNetChunks.split(data)
	for i in parts.size():
		out.append(P.decode(P.snapshot(77, id, tick, data.size(), i, parts.size(), parts[i])))
	return out


func test_chunks_come_together_in_any_order() -> void:
	var data := PackedByteArray()
	for i in 5000:
		data.append(i * 7 & 0xFF)
	var msgs := _chunk_messages(3, 400, data)
	assert_eq(msgs.size(), 6, "5000 bytes in chunks of %d" % P.SNAPSHOT_CHUNK)
	for m in msgs:
		assert_false((m as Dictionary).is_empty(), "every chunk decodes")
	var order := [4, 0, 5, 0, 2, 1, 3]                 # one twice
	var chunks := MwNetChunks.new()
	var results := []
	for i in order:
		results.append(chunks.take(msgs[i]))
	assert_eq(results.slice(0, -1), [0, 0, 0, 0, 0, 0], "MORE (a duplicate too)")
	assert_eq(results[-1], MwNetChunks.Result.DONE)
	assert_eq(chunks.use(), data, "the blob whole")
	assert_eq(chunks.take(msgs[2]), MwNetChunks.Result.STALE, "taken: its chunks are stale")
	# a newer one replaces an unfinished one; an older one is stale
	var d2 := data.slice(0, 2000)
	var c2 := MwNetChunks.new()
	var m5 := _chunk_messages(5, 500, d2)
	c2.take(m5[0])
	assert_true(c2.began)
	var m6 := _chunk_messages(6, 600, d2)
	c2.take(m6[1])
	assert_true(c2.began, "a newer snapshot begins")
	assert_eq(c2.tick, 600)
	assert_eq(c2.take(m5[1]), MwNetChunks.Result.STALE, "an older one's chunk")
	assert_eq(c2.take(m6[0]), MwNetChunks.Result.MORE)
	assert_eq(c2.take(m6[2]), MwNetChunks.Result.DONE)
	assert_eq(c2.use(), d2)
	var wrapped := MwNetChunks.new()
	wrapped.take(_chunk_messages(0xFFFF, 1, d2)[0])
	wrapped.take(_chunk_messages(1, 2, d2)[0])
	assert_eq(wrapped.id, 1, "ids wrap: 1 is newer than 65535")


func test_contradicting_chunks_are_bad() -> void:
	var data := PackedByteArray()
	data.resize(3000)
	var msgs := _chunk_messages(9, 50, data)
	var chunks := MwNetChunks.new()
	chunks.take(msgs[0])
	var other: Dictionary = msgs[0].duplicate()
	var bytes: PackedByteArray = (other["chunk"] as PackedByteArray).duplicate()
	bytes[5] = 1
	other["chunk"] = bytes
	assert_eq(chunks.take(other), MwNetChunks.Result.BAD, "the same chunk with other bytes")
	var other_tick: Dictionary = msgs[1].duplicate()
	other_tick["tick"] = 51
	assert_eq(chunks.take(other_tick), MwNetChunks.Result.BAD, "another tick under the same id")
	# the decoder already refuses chunks whose numbers don't agree
	assert_true(P.decode(P.snapshot(1, 1, 5, 3000, 0, 3, data.slice(0, 900))).is_empty(), "a short middle chunk")
	assert_false(P.decode(P.snapshot(1, 1, 5, 3000, 3, 4, data.slice(0, 120))).is_empty(), "the last of four")
	assert_true(P.decode(P.snapshot(1, 1, 5, 3000, 3, 5, data.slice(0, 120))).is_empty(), "the wrong count")
	assert_true(P.decode(P.snapshot(1, 1, 5, 3000, 4, 4, data.slice(0, 120))).is_empty(), "index past the count")
	assert_true(P.decode(P.snapshot(1, 1, 5, P.MAX_SNAPSHOT + 1, 0, 1093, data.slice(0, P.SNAPSHOT_CHUNK))).is_empty(),
			"over the cap")
	assert_true(P.decode(P.snapshot(1, 1, P.NONE, 10, 0, 1, data.slice(0, 10))).is_empty(), "no tick")
	assert_true(P.decode(P.resync(1, 0)).is_empty() and P.decode(P.resync(1, 3)).is_empty(), "no such reason")


# --- over the loopback ----------------------------------------------------------------------------

## A host and a client in a running match at 20 % loss: the host sends a
## snapshot at its tick - the client's stream starts again there, the blob
## comes whole, the tick arrives; RESYNC and SYNCED reach the host.
func test_a_snapshot_over_a_lossy_link() -> void:
	var w := World.new(8, "pw", {"loss": 0.2, "delay": 60, "jitter": 20, "duplicate": 0.05, "reorder": 0.1})
	var client := w.join("pw")
	assert_true(w.run_until(func() -> bool: return client.state == MwNetClient.State.LOBBY))
	w.host.start_match(PackedByteArray([1]))
	for i in 120:
		w.host.step()
		w.run(17)
	var data := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 40000:
		data.append(rng.randi_range(0, 255))
	var at := w.host.tick
	var id := w.host.send_snapshot(client.machine, at, data)
	assert_gt(id, 0, "sent")
	assert_eq(w.host.send_snapshot(9, at, data), 0, "no such machine")
	assert_eq(w.host.send_snapshot(client.machine, at + 5, data), 0, "not a tick the host made")
	var heard := []
	w.host.synced.connect(func(m: int, sid: int) -> void: heard.append(["synced", m, sid]))
	w.host.resync_requested.connect(func(m: int, r: int) -> void: heard.append(["resync", m, r]))
	var snapshot_arrived := func() -> bool:
		w.host.step()
		return client.snapshot_ready()
	assert_true(w.run_until(snapshot_arrived, 20000, 17), "the snapshot whole and its tick in the stream")
	assert_eq(client.stream.floor_no, at, "the stream started again at the snapshot's tick")
	var got := client.take_snapshot()
	assert_eq([got["id"], got["tick"]], [id, at])
	assert_eq(got["data"], data, "every byte")
	assert_false(client.snapshot_ready(), "taken once")
	assert_false(client.snapshot_pending())
	client.report_synced(id)
	client.request_resync(P.Resync.LOST)
	client.request_resync(P.Resync.LOST)              # (again at once: ignored, one a second)
	assert_true(w.run_until(func() -> bool: return heard.size() >= 2, 5000))
	w.run(500)
	assert_eq(heard, [["synced", client.machine, id], ["resync", client.machine, P.Resync.LOST]])
	for i in 60:
		w.host.step()
		w.run(17)
	assert_true(client.stream.confirmed > at + 30, "the stream goes on from there")


## A kicked machine's key is erased and its address blocked: back from its
## address it is BLOCKED; from another with the old key, the key is no key
## (A MATCH IS RUNNING) and the client lets it go.
func test_a_kicked_machines_key_is_refused() -> void:
	var w := World.new(9, "pw")
	var client := w.join("pw")
	assert_true(w.run_until(func() -> bool: return client.state == MwNetClient.State.LOBBY))
	var match_id := w.host.start_match(PackedByteArray([1]))
	w.run(200)
	var key := client.rejoin_key()
	assert_eq(key.size(), 32)
	w.host.kick(client.machine)
	assert_true(w.run_until(func() -> bool: return client.state == MwNetClient.State.DONE))
	assert_eq(client.fail, MwNetClient.Fail.KICKED)
	assert_eq(MwNetRejoin.read(), {}, "the kicked client's key gone from its disk")
	MwNetRejoin.save(World.HOST_ADDRESS, P.PORT, match_id, key)
	var back := w.join("pw", 1, {}, "10.0.1.1")
	assert_true(w.run_until(func() -> bool: return back.state == MwNetClient.State.DONE))
	assert_eq(back.refusal, P.Refusal.BLOCKED, "its address blocked")
	MwNetRejoin.save(World.HOST_ADDRESS, P.PORT, match_id, key)
	var elsewhere := w.join("pw", 1, {}, "10.0.9.9")
	assert_true(w.run_until(func() -> bool: return elsewhere.state == MwNetClient.State.DONE))
	assert_eq(elsewhere.refusal, P.Refusal.RUNNING, "its key erased: no key")
	assert_eq(MwNetRejoin.read(), {}, "a key turned away is let go")


## Keys die with the match: once it is over, a machine coming back with its
## old key joins the open lobby as a new machine (the key ignored), and the
## kept key is the new one.
func test_keys_die_with_the_match() -> void:
	var w := World.new(10, "pw")
	var client := w.join("pw")
	assert_true(w.run_until(func() -> bool: return client.state == MwNetClient.State.LOBBY))
	var match_id := w.host.start_match(PackedByteArray([1]))
	w.run(200)
	var key := client.rejoin_key()
	var machine := client.machine
	client.transport.disconnect_peer(MwNetTransport.HOST_PEER, true)
	w.clients.erase(client)
	w.run(200)
	assert_true(w.host.lobby.machines.has(machine), "kept for a rejoin while the match runs")
	w.host.end_match()
	assert_false(w.host.lobby.machines.has(machine), "gone with the match")
	MwNetRejoin.save(World.HOST_ADDRESS, P.PORT, match_id, key)
	var back := w.join("pw")
	assert_true(w.run_until(func() -> bool: return back.state == MwNetClient.State.LOBBY))
	assert_ne(back.rejoin_key(), key, "a new key")
	assert_eq(MwNetRejoin.key_for(World.HOST_ADDRESS, P.PORT), back.rejoin_key())


## A stream stuck at a gap while the host goes on far past it: the ticks
## past the window are FAR - the gap lost, the connection kept (a snapshot
## starts the run again) - while the host's input receiver still calls such
## a packet garbage; skip_to starts the run at the snapshot's tick.
func test_a_stream_far_past_its_gap_is_lost_not_garbage() -> void:
	var tx := MwNetTickLog.new(0)
	var rx := MwNetTickReceiver.new(0)
	for i in 3:
		tx.push(MwNetInput.blank_tick())
	var packet := tx.encode(P.NONE)
	assert_eq(rx.receive(packet["base"], packet["first"], packet["count"], packet["body"]), MwNetTickReceiver.Result.OK)
	assert_eq(rx.confirmed, 2)
	var t := MwNetInput.blank_tick()
	var near := {}
	for i in MwNetTickReceiver.WINDOW + 40:
		t = MwNetInput.with_player(t, 1, MwNetInput.next_state(MwNetInput.player(t, 1), PackedInt32Array([i % 5]),
				PackedInt32Array()))
		tx.push(t)
		if tx.newest == 12:
			near = tx.encode_range(10, 12, 10)[0]          # (from blank)
	assert_eq(rx.receive(near["base"], near["first"], near["count"], near["body"]), MwNetTickReceiver.Result.OK,
			"a gap (3-9 missing)")
	var far := tx.encode(P.NONE)
	assert_eq(rx.receive(far["base"], far["first"], far["count"], far["body"]), MwNetTickReceiver.Result.FAR)
	assert_true(rx.lost, "the gap can't be filled in time any more")
	var hx := MwNetTickReceiver.new(0)
	hx.skip_gaps = true
	assert_eq(hx.receive(far["base"], far["first"], far["count"], far["body"]), MwNetTickReceiver.Result.BAD,
			"the host's inputs: garbage still")
	var at := int(far["first"])
	rx.skip_to(at)
	assert_false(rx.lost, "a snapshot's tick: the run starts again")
	assert_eq([rx.floor_no, rx.confirmed], [at, at - 1])
	assert_eq(rx.receive(far["base"], far["first"], far["count"], far["body"]), MwNetTickReceiver.Result.OK)
	assert_eq(rx.confirmed, tx.newest, "and goes on")
	assert_eq(rx.get_tick(tx.newest), tx.get_tick(tx.newest))
	assert_eq(rx.get_tick(11), PackedByteArray(), "nothing before it kept")
