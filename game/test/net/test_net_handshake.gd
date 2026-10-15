extends "res://test/net/net_test_base.gd"
## Plan 35 work item 2: joining a host over the loopback (MwNetHost,
## MwNetClient) - the first contact and the pinned reconnect, the lobby,
## local players joining and leaving, every refusal (wrong password with a
## growing wait, versions, ROM, full, a match running, too many tries,
## blocked, busy), rejoining with the key, a man in the middle with and
## without a password (trust on first use), a host that can't prove the
## password, garbage and floods dropping the peer.
## Short names: c the MwNetClient under test.

const P := preload("res://src/net/net_protocol.gd")
const C := preload("res://src/net/net_client.gd")


func _in(c: MwNetClient) -> Callable:
	return func() -> bool: return c.state == C.State.LOBBY or c.state == C.State.RUNNING


func _settled(c: MwNetClient) -> Callable:
	return func() -> bool: return not c.state in [C.State.FETCHING, C.State.CONNECTING, C.State.HANDSHAKE]


func _done(c: MwNetClient) -> Callable:
	return func() -> bool: return c.state == C.State.DONE


## A raw connection to the host: [peer events], for sending by hand.
func _raw(w: World, from := "10.9.9.9", pinned := PackedByteArray()) -> MwNetLoopback.Endpoint:
	return w.net.connect_to(World.HOST_ADDRESS, from, pinned)


func _raw_messages(ep: MwNetLoopback.Endpoint) -> Array:
	ep.poll()
	var out := []
	for ev in ep.take_events():
		if ev["kind"] == MwNetTransport.Kind.PACKET:
			out.append(P.decode(ev["data"]))
		elif ev["kind"] == MwNetTransport.Kind.DISCONNECTED:
			out.append({"type": "disconnected"})
	return out


func test_first_contact_joins_and_pins() -> void:
	var w := World.new(1, "pw")
	var c := w.join("pw")
	var seen := []
	c.state_changed.connect(func(state: int) -> void: seen.append(state))
	assert_true(w.run_until(_in(c)), "joined")
	assert_eq(seen, [C.State.CONNECTING, C.State.HANDSHAKE, C.State.LOBBY],
			"fetched the certificate unpinned, then pinned to it")
	assert_eq(c.numbers, [2] as Array[int])
	assert_eq(c.machine, 1)
	assert_eq(w.host.lobby.numbers(), [1, 2] as Array[int])
	w.run(200)
	assert_eq(c.lobby.to_wire(), w.host.lobby.to_wire(), "the client's lobby is the host's")
	assert_eq(MwNetKnownHosts.lookup(World.HOST_ADDRESS, P.PORT), w.der, "remembered")
	assert_eq(MwNetRejoin.key_for(World.HOST_ADDRESS, P.PORT), c.rejoin_key(), "the key kept")
	assert_eq(c.rejoin_key().size(), 32)
	var joined := []
	c.lobby.player_joined.connect(func(n: int) -> void: joined.append(n))
	var c2 := w.join("pw", 2)
	assert_true(w.run_until(_in(c2)))
	assert_eq(c2.numbers, [3, 4] as Array[int], "a machine's local players")
	w.run(200)
	assert_eq(joined, [3, 4], "the others hear of it")
	var c3 := w.join("pw")
	var states := []
	c3.state_changed.connect(func(client_state: int) -> void: states.append(client_state))
	assert_true(w.run_until(_in(c3)))
	assert_eq(states[0], C.State.HANDSHAKE, "a known host: straight to the pinned connection")


func test_wrong_password_waits_grow() -> void:
	var w := World.new(2, "secret")
	var waits := []
	for i in 3:
		var c := w.join("guess%d" % i, 1, {}, "10.0.1.50")
		assert_true(w.run_until(_done(c)))
		assert_eq(c.fail, C.Fail.REFUSED)
		assert_eq(c.refusal, P.Refusal.WRONG_PASSWORD)
		waits.append(c.refusal_wait)
		var early := w.join("secret", 1, {}, "10.0.1.50")
		assert_true(w.run_until(_done(early)))
		assert_eq(early.refusal, P.Refusal.WAIT, "turned away during the wait, even with the right password")
		w.run(c.refusal_wait * 1000 + 50)
	assert_eq(waits, [1, 2, 4], "the wait grows")
	w.run(MwNetHost.HELLO_WINDOW_MS)    # six tries in ten seconds: the tries' limit too
	var ok := w.join("secret", 1, {}, "10.0.1.50")
	assert_true(w.run_until(_in(ok)), "the right password after the wait")
	assert_eq(MwNetKnownHosts.lookup(World.HOST_ADDRESS, P.PORT), w.der)
	assert_true(w.host.log_lines.size() > 0)
	for line in w.host.log_lines:
		assert_false("secret" in line or "guess" in line, "no password in the log")


func test_refusals() -> void:
	var w := World.new(3)
	var other_build := net_info()
	other_build["build"] = "another build"
	var other_schema := net_info()
	other_schema["schema"] = 12345
	var other_rom := net_info()
	other_rom["rom"] = PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
	var cases := [[other_build, P.Refusal.VERSION], [other_schema, P.Refusal.VERSION], [other_rom, P.Refusal.ROM]]
	for k in cases:
		var c := w.make_client(k[0])
		c.connect_to(World.HOST_ADDRESS, P.PORT, "", 1)
		assert_true(w.run_until(_done(c)))
		assert_eq([c.fail, c.refusal], [C.Fail.REFUSED, k[1]])
	# another protocol version: its HELLO's layout may differ - the type byte is enough
	var ep := _raw(w, "10.9.9.1")
	w.run(50)
	_raw_messages(ep)
	var hello := P.hello("x", PackedByteArray(), 0, PackedByteArray(), 1, PackedByteArray())
	hello[1] = P.VERSION + 1
	ep.send(MwNetTransport.HOST_PEER, P.CH_RELIABLE, hello)
	w.run(50)
	var got := _raw_messages(ep)
	assert_eq(got[0].get("type"), P.Type.REFUSE)
	assert_eq(got[0].get("code"), P.Refusal.VERSION)
	assert_eq(w.host.lobby.players.size(), 1, "nobody came in")


func test_full_at_twelve() -> void:
	var w := World.new(4)
	for local in range(2, 6):
		assert_ne(w.host.join_local(local, 1), 0)
	var four := w.join("", 4)
	var client := w.join("", 3)
	assert_true(w.run_until(func() -> bool: return four.state == C.State.LOBBY and client.state == C.State.LOBBY))
	assert_eq(w.host.lobby.players.size(), 12)
	var c := w.join("", 1)
	assert_true(w.run_until(_done(c)))
	assert_eq(c.refusal, P.Refusal.FULL)
	var freed := client.numbers[1]
	client.leave_local(freed)
	w.run(100)
	assert_eq(w.host.lobby.players.size(), 11)
	var two := w.join("", 2)
	assert_true(w.run_until(_done(two)))
	assert_eq(two.refusal, P.Refusal.FULL, "two players don't fit one place")
	var one := w.join("", 1)
	assert_true(w.run_until(_in(one)))
	assert_eq(one.numbers, [freed] as Array[int], "the freed number")
	assert_eq(w.host.lobby.players.size(), 12)


func test_numbers_reused_lowest_first() -> void:
	var w := World.new(5)
	var first := w.join()
	var second := w.join()
	var c := w.join()
	assert_true(w.run_until(func() -> bool: return c.state == C.State.LOBBY and second.state == C.State.LOBBY))
	assert_eq([first.numbers, second.numbers, c.numbers], [[2], [3], [4]])
	second.exit_lobby()
	w.run(200)
	assert_eq(w.host.lobby.numbers(), [1, 2, 4] as Array[int], "nobody renumbered")
	assert_eq(MwNetRejoin.read(), {}, "the key goes with EXIT LOBBY")
	var client := w.join()
	assert_true(w.run_until(_in(client)))
	assert_eq(client.numbers, [3] as Array[int], "the freed number goes to the next joiner")
	first.join_local(2, 7)
	w.run(200)
	assert_eq(first.numbers, [2, 5] as Array[int])
	assert_eq(int(w.host.lobby.players[5]["device"]), 7)
	assert_eq(client.lobby.numbers(), [1, 2, 3, 4, 5] as Array[int], "everyone sees it")
	first.leave_local(2)
	w.run(200)
	assert_true(w.host.lobby.players.has(2), "a machine's first player can't leave on their own")
	first.leave_local(5)
	w.run(200)
	assert_eq(first.numbers, [2] as Array[int])
	assert_eq(w.host.join_local(2), 5, "the host's own second player")
	assert_false(w.host.leave_local(1), "P1 stays")


func test_match_running_and_rejoin() -> void:
	var w := World.new(6, "pw", {"delay": 20, "jitter": 10})
	var observer := w.join("pw")
	var client := w.join("pw", 2)
	assert_true(w.run_until(func() -> bool: return observer.state == C.State.LOBBY and client.state == C.State.LOBBY))
	var record := PackedByteArray([9, 8, 7])
	var got := []
	observer.started.connect(func(id: int, first: int, rec: PackedByteArray) -> void: got.append([id, first, rec]))
	var match_id := w.host.start_match(record)
	assert_ne(match_id, 0)
	for i in 30:
		w.host.step()
		w.run(17)
	assert_eq(got, [[match_id, 0, record]], "START carries the record")
	assert_eq(observer.state, C.State.RUNNING)
	var h := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	w.host.add_hash(w.host.tick, 0, h)
	var at := w.host.tick
	for i in 5:
		w.host.step()
		w.run(17)
	assert_eq(observer.host_hash(at, 0), h, "the host's hashes reach the clients")
	assert_eq(observer.host_hash(at, 1), PackedByteArray())
	w.run(1500)
	assert_between(observer.rtt_ms, 30, 120, "the round trip measured (%d ms)" % observer.rtt_ms)
	assert_between(int(w.host.lobby.machines[observer.machine]["ping"]), 30, 120, "and the host's ping for the lobby")
	MwNetRejoin.clear()   # (every client of the test shares one rejoin file)
	var late := w.join("pw")
	assert_true(w.run_until(_done(late)))
	assert_eq(late.refusal, P.Refusal.RUNNING, "no new machines in a running match")
	# b's game crashes: its connection drops; its key stays on disk
	var key := client.rejoin_key()
	var numbers := client.numbers
	client.transport.disconnect_peer(MwNetTransport.HOST_PEER, true)
	w.clients.erase(client)
	w.run(200)
	assert_false(bool(w.host.lobby.machines[client.machine]["connected"]), "kept for a rejoin")
	assert_eq(w.host.lobby.numbers_of(client.machine), numbers)
	MwNetRejoin.save(World.HOST_ADDRESS, P.PORT, match_id, key)
	var back := w.join("pw")
	assert_true(w.run_until(_in(back)))
	assert_eq(back.state, C.State.RUNNING)
	assert_eq(back.machine, client.machine)
	assert_eq(back.numbers, numbers, "the same player numbers")
	assert_eq(back.stream.floor_no, w.host.tick + 1, "the stream follows from the next tick")
	for i in 30:
		w.host.step()
		w.run(17)
	assert_true(back.stream.confirmed >= w.host.tick - 3, "and arrives")
	assert_true(bool(w.host.lobby.machines[client.machine]["connected"]))
	MwNetRejoin.save(World.HOST_ADDRESS, P.PORT, match_id, P.random_bytes(32))
	var forged := w.join("pw")
	assert_true(w.run_until(_done(forged)))
	assert_eq(forged.refusal, P.Refusal.RUNNING, "a wrong key is no key")
	w.host.end_match()
	w.run(200)
	assert_eq(observer.state, C.State.LOBBY, "back to the lobby")
	assert_eq(MwNetRejoin.read(), {}, "keys die with the match")


## A man in the middle relays between the client and the host, showing the
## client his own certificate.
class Mitm:
	var front: MwNetLoopback.Endpoint
	var back: MwNetLoopback.Endpoint
	var net: MwNetLoopback
	var der: PackedByteArray
	var rewrite := true
	var client_peer := -1

	func _init(loopback: MwNetLoopback, own_der: PackedByteArray, address: String) -> void:
		net = loopback
		der = own_der
		front = loopback.listen(address, MwNetIdentity.fingerprint_of(own_der))

	func poll() -> void:
		front.poll()
		for ev in front.take_events():
			match ev["kind"]:
				MwNetTransport.Kind.CONNECTED:
					client_peer = ev["peer"]
					back = net.connect_to("10.0.0.1", "10.6.6.6",
							MwNetIdentity.fingerprint_of(World.fake_cert(6)))
				MwNetTransport.Kind.PACKET:
					if back != null:
						back.send(MwNetTransport.HOST_PEER, ev["channel"], ev["data"])
		if back == null:
			return
		back.poll()
		for ev in back.take_events():
			if ev["kind"] == MwNetTransport.Kind.PACKET:
				var data: PackedByteArray = ev["data"]
				if rewrite and data[0] == MwNetProtocol.Type.CERT:
					data = MwNetProtocol.cert(der)
				front.send(client_peer, ev["channel"], data)


func _with_mitm(password: String, rewrite: bool, client_password := "") -> Array:
	var w := World.new(6, password, {}, World.fake_cert(6))
	var mitm := Mitm.new(w.net, World.fake_cert(66), "10.0.0.66")
	mitm.rewrite = rewrite
	var c := w.make_client()
	c.connect_to("10.0.0.66", P.PORT, client_password if client_password != "" else password, 1)
	var end := w.net.now_ms + 20000
	while w.net.now_ms < end and c.state != C.State.DONE and c.state != C.State.TRUST:
		w.net.advance(10)
		mitm.poll()
		w.poll()
	return [w, c, mitm]


func test_man_in_the_middle_with_password() -> void:
	var r := _with_mitm("pw", true)
	var w: World = r[0]
	var c: MwNetClient = r[1]
	assert_eq(c.state, C.State.DONE)
	assert_eq([c.fail, c.refusal], [C.Fail.REFUSED, P.Refusal.WRONG_PASSWORD],
			"the client's proof names the middle man's certificate: the host refuses it")
	assert_eq(w.host.lobby.players.size(), 1, "nobody got in")
	assert_eq(MwNetKnownHosts.lookup("10.0.0.66", P.PORT), PackedByteArray(), "nothing remembered")
	assert_eq(MwNetRejoin.read(), {}, "no key")
	var r2 := _with_mitm("pw", false)
	var c2: MwNetClient = r2[1]
	assert_eq(c2.fail, C.Fail.NO_ANSWER, "passing the host's certificate on, he can't hold the pinned session")
	assert_eq((r2[0] as World).host.lobby.players.size(), 1)


func test_man_in_the_middle_without_password_is_flagged() -> void:
	var w := World.new(6, "", {}, World.fake_cert(6))
	MwNetKnownHosts.remember("10.0.0.66", P.PORT, World.fake_cert(6))   # been there before, directly
	var mitm := Mitm.new(w.net, World.fake_cert(66), "10.0.0.66")
	var c := w.make_client()
	var changed := []
	c.key_changed.connect(func(a: PackedByteArray, b: PackedByteArray) -> void: changed.append([a, b]))
	c.connect_to("10.0.0.66", P.PORT, "", 1)
	var end := w.net.now_ms + 20000
	while w.net.now_ms < end and c.state != C.State.TRUST and c.state != C.State.DONE:
		w.net.advance(10)
		mitm.poll()
		w.poll()
	assert_eq(c.state, C.State.TRUST, "THIS HOST'S KEY HAS CHANGED: asked")
	assert_eq(changed, [[MwNetIdentity.fingerprint_of(World.fake_cert(6)),
			MwNetIdentity.fingerprint_of(World.fake_cert(66))]])
	c.cancel()
	assert_eq(c.fail, C.Fail.CANCELLED)
	assert_eq(MwNetKnownHosts.lookup("10.0.0.66", P.PORT), World.fake_cert(6), "the old certificate kept")


func test_changed_key_trusted_or_proved() -> void:
	var w := World.new(7, "", {}, World.fake_cert(70))
	var c := w.join()
	assert_true(w.run_until(_in(c)))
	c.exit_lobby()
	w.run(100)
	# the host's data was wiped: a new certificate at the same address
	w.host.close()
	w.host = MwNetHost.new(w.net.listen(World.HOST_ADDRESS, MwNetIdentity.fingerprint_of(World.fake_cert(71))),
			World.fake_cert(71), "", net_info())
	w.host.open()
	var c2 := w.join()
	assert_true(w.run_until(func() -> bool: return c2.state == C.State.TRUST))
	c2.trust_new_key()
	assert_true(w.run_until(_in(c2)), "trusted: in")
	assert_eq(MwNetKnownHosts.lookup(World.HOST_ADDRESS, P.PORT), World.fake_cert(71), "the new one remembered")
	# plan 45 (M3): with a password it is asked too - our proof would go to the new key's holder
	w.host.close()
	w.host = MwNetHost.new(w.net.listen(World.HOST_ADDRESS, MwNetIdentity.fingerprint_of(World.fake_cert(72))),
			World.fake_cert(72), "pw", net_info())
	w.host.open()
	var c3 := w.join("pw")
	assert_true(w.run_until(func() -> bool: return c3.state == C.State.TRUST), "asked with a password too")
	c3.trust_new_key()
	assert_true(w.run_until(_in(c3)))
	assert_eq(MwNetKnownHosts.lookup(World.HOST_ADDRESS, P.PORT), World.fake_cert(72))


func test_host_that_cant_prove_the_password() -> void:
	var net := MwNetLoopback.new(8)
	var der := World.fake_cert(80)
	var fake := net.listen("10.0.0.80", MwNetIdentity.fingerprint_of(der))
	var c := MwNetClient.new()
	c.info = net_info()
	c.connector = func(a: String, _p: int, pinned: PackedByteArray) -> MwNetTransport:
		return net.connect_to(a, "10.0.1.1", MwNetIdentity.fingerprint_of(pinned) if not pinned.is_empty()
				else PackedByteArray())
	c.connect_to("10.0.0.80", P.PORT, "pw", 1)
	for i in 300:
		net.advance(10)
		fake.poll()
		for ev in fake.take_events():
			if ev["kind"] == MwNetTransport.Kind.CONNECTED:
				fake.send(ev["peer"], P.CH_RELIABLE, P.cert(der))
			elif ev["kind"] == MwNetTransport.Kind.PACKET:
				var m := P.decode(ev["data"])
				if m.get("type") == P.Type.HELLO:
					fake.send(ev["peer"], P.CH_RELIABLE, P.challenge(P.random_bytes(16), true))
				elif m.get("type") == P.Type.AUTH:   # accepts anything, can't prove anything
					fake.send(ev["peer"], P.CH_RELIABLE, P.welcome(P.random_bytes(32), 1, P.random_bytes(32),
							5, P.NONE, [2], {"state": 0, "match": 5, "machines": [{"id": 0}, {"id": 1}],
							"players": [{"number": 1, "machine": 0, "local": 1},
							{"number": 2, "machine": 1, "local": 1}]}))
		c.poll(net.now_ms)
		if c.state == C.State.DONE:
			break
	assert_eq(c.fail, C.Fail.HOST_PROOF)
	assert_eq(MwNetKnownHosts.lookup("10.0.0.80", P.PORT), PackedByteArray(), "not remembered")
	assert_eq(MwNetRejoin.read(), {}, "its key not kept")


func test_garbage_and_floods_drop_the_peer() -> void:
	var w := World.new(9)
	var c := w.join()
	assert_true(w.run_until(_in(c)))
	c.transport.send(MwNetTransport.HOST_PEER, P.CH_RELIABLE, PackedByteArray([P.Type.LOBBY, P.VERSION, 1]))
	w.run(200)
	assert_eq(c.fail, C.Fail.PROTOCOL, "told it was dropped")
	assert_eq(w.host.lobby.players.size(), 1, "its machine gone")
	var c2 := w.join()
	assert_true(w.run_until(_in(c2)))
	c2.transport.send(MwNetTransport.HOST_PEER, P.CH_RELIABLE, P.leave_local(1))
	w.run(200)
	assert_eq(c2.state, C.State.DONE, "another machine's player: dropped")
	var c3 := w.join()
	assert_true(w.run_until(_in(c3)))
	for i in MwNetHost.PACKET_LIMIT + 5:
		c3.transport.send(MwNetTransport.HOST_PEER, P.CH_PING, P.ping(i, 0))
	w.run(100)
	assert_eq(c3.state, C.State.DONE, "a flood: dropped")
	var ep := _raw(w, "10.9.9.2")
	w.run(50)
	ep.send(MwNetTransport.HOST_PEER, P.CH_RELIABLE, P.auth(P.random_bytes(32)))
	w.run(50)
	assert_eq(_raw_messages(ep)[-1].get("type"), "disconnected", "out of turn: dropped")
	assert_eq(w.host.peer_counts(), {"pending": 0, "in": 0})


func test_slow_handshakes_rate_limits_and_busy() -> void:
	var w := World.new(10)
	var eps := []
	for i in MwNetHost.MAX_PENDING + 1:
		eps.append(_raw(w, "10.9.8.%d" % i))
	w.run(100)
	assert_eq(w.host.peer_counts()["pending"], MwNetHost.MAX_PENDING)
	var last := _raw_messages(eps[-1])
	assert_eq(last[0].get("code"), P.Refusal.BUSY, "too many half-open connections")
	w.run(MwNetHost.HANDSHAKE_MS + 100)
	assert_eq(w.host.peer_counts()["pending"], 0, "dropped when they never finish")
	var results := []
	for i in MwNetHost.HELLO_LIMIT + 1:
		var c := w.join("", 1, {}, "10.7.7.7")
		w.run_until(func() -> bool: return c.state == C.State.DONE or c.state == C.State.LOBBY)
		results.append(c.refusal)
		c.exit_lobby()
		w.run(100)
	assert_eq(results, [0, 0, 0, 0, 0, P.Refusal.WAIT], "too many tries from one address in 10 s")
	w.run(MwNetHost.HELLO_WINDOW_MS)
	var later := w.join("", 1, {}, "10.7.7.7")
	w.run(1000)
	assert_eq(later.state, C.State.LOBBY, "fine again after the window")


func test_kick_blocks_and_erases() -> void:
	var w := World.new(11)
	var c := w.join()
	assert_true(w.run_until(_in(c)))
	w.host.kick(c.machine)
	assert_true(w.run_until(_done(c)))
	assert_eq(c.fail, C.Fail.KICKED)
	assert_eq(MwNetRejoin.read(), {}, "its key erased")
	w.clients.erase(c)
	var again := w.join()     # the same address ("10.0.1.1")
	assert_true(w.run_until(_done(again)))
	assert_eq(again.refusal, P.Refusal.BLOCKED)
	assert_eq(MwNetHost.block_key("2001:db8:1:2:aaaa::1"), MwNetHost.block_key("2001:DB8:1:2::5"),
			"an IPv6 address blocked by its /64")
	assert_ne(MwNetHost.block_key("2001:db8:1:3::1"), MwNetHost.block_key("2001:db8:1:2::1"))
	assert_eq(MwNetHost.block_key("0:0:0:0:0:0:0:1"), MwNetHost.block_key("::1"))
	assert_eq(MwNetHost.block_key("192.168.1.9"), "192.168.1.9")


func test_close_lobby() -> void:
	var w := World.new(12)
	var first := w.join()
	var client := w.join()
	assert_true(w.run_until(func() -> bool: return first.state == C.State.LOBBY and client.state == C.State.LOBBY))
	w.host.close()
	w.run(300)
	assert_eq([first.fail, client.fail], [C.Fail.CLOSED, C.Fail.CLOSED])
	assert_eq(MwNetRejoin.read(), {})
	assert_eq(w.host.lobby.state, MwNetLobby.State.CLOSED)


## Mutated messages from a machine that is in, and from a host to a client
## in the lobby and in a match: the sessions never crash, and drop (or
## leave) the sender.
func test_sessions_survive_mutated_messages() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var w := World.new(13)
	var good := w.join()
	assert_true(w.run_until(_in(good)))
	var tick := MwNetInput.encode_tick(MwNetInput.blank_tick(), MwNetInput.with_player(MwNetInput.blank_tick(), 3,
			MwNetInput.next_state(MwNetInput.blank(), PackedInt32Array([1]), PackedInt32Array([1]))))
	var samples: Array[PackedByteArray] = [P.input(0, P.NONE, P.NONE, 0, 1, tick), P.join_local(2, 1),
			P.leave_local(3), P.resend_request(0, 5), P.pong(1, 0, P.NONE), P.bye(), P.lobby(good.lobby.to_wire())]
	w.host.start_match()
	w.run(100)
	MwNetRejoin.clear()   # (the test's clients share one rejoin file: theirs must not be good's key)
	for i in 40:
		var c := w.join("", 1, {}, "10.3.%d.1" % i)
		if not w.run_until(_settled(c), 5000):
			continue
		var msg := samples[rng.randi_range(0, samples.size() - 1)].duplicate()
		for k in rng.randi_range(0, 3):
			msg[rng.randi_range(0, msg.size() - 1)] = rng.randi_range(0, 255)
		if c.transport.is_open():
			c.transport.send(MwNetTransport.HOST_PEER, rng.randi_range(0, 2), msg)
		w.run(50)
		if i == 20:
			w.host.end_match()
	assert_eq(good.state, C.State.LOBBY, "a well-behaved machine unaffected")
	var after := w.join("", 1, {}, "10.4.0.1")
	assert_true(w.run_until(_in(after)), "and the host still lets machines in")
	assert_true(w.host.lobby.players.size() <= 12)
	# the other way: a host sending mutated messages to a client
	var net := MwNetLoopback.new(14)
	var der := World.fake_cert(14)
	var fake := net.listen("10.0.0.90", MwNetIdentity.fingerprint_of(der))
	var to_client: Array[PackedByteArray] = [P.lobby(good.lobby.to_wire()), P.start(1, 0, 0, 0, 1, PackedByteArray()),
			P.stream(1, 0, P.NONE, 0, 1, tick), P.resend(1, P.NONE, 0, 1, tick), P.hashes(1, [{"tick": 0, "kind": 0,
			"value": PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])}]), P.close(1), P.cert(der)]
	var survived := 0
	for i in 30:
		var c := MwNetClient.new()
		c.info = net_info()
		c.connector = func(a: String, _p: int, pinned: PackedByteArray) -> MwNetTransport:
			return net.connect_to(a, "10.0.2.%d" % i, MwNetIdentity.fingerprint_of(pinned) if not pinned.is_empty()
					else PackedByteArray())
		c.connect_to("10.0.0.90", P.PORT, "", 1)
		var peer := -1
		var nonce := PackedByteArray()
		for k in 400:
			net.advance(5)
			fake.poll()
			for ev in fake.take_events():
				if ev["kind"] == MwNetTransport.Kind.CONNECTED:
					peer = ev["peer"]
					fake.send(peer, P.CH_RELIABLE, P.cert(der))
				elif ev["kind"] == MwNetTransport.Kind.PACKET:
					var m := P.decode(ev["data"])
					if m.get("type") == P.Type.HELLO:
						nonce = m["nonce"]
						fake.send(peer, P.CH_RELIABLE, P.challenge(P.random_bytes(16), false))
					elif m.get("type") == P.Type.AUTH:
						pass
			c.poll(net.now_ms)
			if c.state == C.State.HANDSHAKE and not nonce.is_empty():
				break
		var msg := to_client[rng.randi_range(0, to_client.size() - 1)].duplicate()
		for k in rng.randi_range(0, 3):
			msg[rng.randi_range(0, msg.size() - 1)] = rng.randi_range(0, 255)
		fake.send(peer, rng.randi_range(0, 2), msg)
		for k in 20:
			net.advance(5)
			fake.poll()
			fake.take_events()
			c.poll(net.now_ms)
		survived += 1
	assert_eq(survived, 30, "the client survived every one")
