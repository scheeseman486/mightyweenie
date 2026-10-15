extends "res://test/net/net_test_base.gd"
## Plan 45: what a hostile peer can no longer do (the audit,
## out/plan45/audit/net-security.md) - one address filling the host's
## unauthenticated connections (M1), a known host's changed certificate let
## through because a password is set and the rejoin key sent to whoever
## holds it (M3), a host growing a client's hashes without bound (L4).
## Short names: c the MwNetClient under test.

const P := preload("res://src/net/net_protocol.gd")
const C := preload("res://src/net/net_client.gd")
## [method _messages]' type for a connection that ended.
const DISCONNECTED := -2


## A host of the test's own at [param address] showing the certificate
## [param der]: it answers HELLO with a CHALLENGE (a password set) and notes
## every message it gets ([member types]) and each HELLO ([member hellos]).
class FakeHost:
	var endpoint: MwNetLoopback.Endpoint
	var der := PackedByteArray()
	var types: Array[int] = []
	var hellos: Array[Dictionary] = []

	func _init(net: MwNetLoopback, address: String, der_: PackedByteArray) -> void:
		der = der_
		endpoint = net.listen(address, MwNetIdentity.fingerprint_of(der_))

	func poll() -> void:
		endpoint.poll()
		for ev in endpoint.take_events():
			if ev["kind"] == MwNetTransport.Kind.CONNECTED:
				endpoint.send(ev["peer"], P.CH_RELIABLE, P.cert(der))
			elif ev["kind"] == MwNetTransport.Kind.PACKET:
				var m := P.decode(ev["data"])
				types.append(int(m.get("type", -1)))
				if m.get("type") == P.Type.HELLO:
					hellos.append(m)
					endpoint.send(ev["peer"], P.CH_RELIABLE, P.challenge(P.random_bytes(P.NONCE_BYTES), true))


func _in(c: MwNetClient) -> Callable:
	return func() -> bool: return c.state == C.State.LOBBY or c.state == C.State.RUNNING


## A client on [param net] at 10.0.1.1 (not connected yet).
func _client(net: MwNetLoopback) -> MwNetClient:
	var c := MwNetClient.new()
	c.info = net_info()
	c.connector = func(a: String, _p: int, pinned: PackedByteArray) -> MwNetTransport:
		return net.connect_to(a, "10.0.1.1", MwNetIdentity.fingerprint_of(pinned) if not pinned.is_empty()
				else PackedByteArray())
	return c


## Runs [param c] against [param fake] until [param done] (or 10 s of the loopback's time).
func _pump(net: MwNetLoopback, fake: FakeHost, c: MwNetClient, done: Callable) -> void:
	for i in 1000:
		if done.call():
			return
		net.advance(10)
		fake.poll()
		c.poll(net.now_ms)


## What [param endpoint] received: the decoded messages, and {type: [constant DISCONNECTED]}.
func _messages(endpoint: MwNetLoopback.Endpoint) -> Array[Dictionary]:
	endpoint.poll()
	var out: Array[Dictionary] = []
	for ev in endpoint.take_events():
		if ev["kind"] == MwNetTransport.Kind.PACKET:
			out.append(P.decode(ev["data"]))
		elif ev["kind"] == MwNetTransport.Kind.DISCONNECTED:
			out.append({"type": DISCONNECTED})
	return out


## A raw connection from [param from] to [param w]'s host, pinned to its
## certificate, saying HELLO with [param key_of] (the client's nonce -> HELLO's
## key field); the answer: a refusal's code, or 0 for a CHALLENGE.
func _hello_answer(w: World, from: String, key_of: Callable) -> int:
	var endpoint := w.net.connect_to(World.HOST_ADDRESS, from, MwNetIdentity.fingerprint_of(w.der))
	w.run(100)
	_messages(endpoint)                                  # the certificate
	var nonce := P.random_bytes(P.NONCE_BYTES)
	var info := net_info()
	endpoint.send(MwNetTransport.HOST_PEER, P.CH_RELIABLE, P.hello(str(info["build"]), info["rom"],
			int(info["schema"]), nonce, 1, key_of.call(nonce)))
	w.run(100)
	for m in _messages(endpoint):
		if int(m.get("type", -1)) == P.Type.REFUSE:
			return int(m["code"])
		if int(m.get("type", -1)) == P.Type.CHALLENGE:
			return 0
	return -1


# --- M1: the unauthenticated connections ----------------------------------------------------------

func test_one_address_cant_fill_the_pending_connections() -> void:
	var w := World.new(21, "pw")
	var endpoints: Array[MwNetLoopback.Endpoint] = []
	for i in MwNetHost.MAX_PENDING:
		endpoints.append(w.net.connect_to(World.HOST_ADDRESS, "10.9.9.9"))
	w.run(100)
	assert_eq(w.host.peer_counts()["pending"], MwNetHost.MAX_PENDING_PER, "one address holds its share, no more")
	var busy := 0
	for endpoint in endpoints:
		for m in _messages(endpoint):
			if int(m.get("type", -1)) == P.Type.REFUSE and int(m.get("code", 0)) == P.Refusal.BUSY:
				busy += 1
	assert_eq(busy, MwNetHost.MAX_PENDING - MwNetHost.MAX_PENDING_PER, "the rest: THE HOST IS BUSY")
	var c := w.join("pw")
	assert_true(w.run_until(_in(c)), "a machine elsewhere joins meanwhile")


func test_a_connection_that_never_says_hello_goes_early() -> void:
	var w := World.new(22)
	var silent := w.net.connect_to(World.HOST_ADDRESS, "10.9.9.8")
	var talking := w.net.connect_to(World.HOST_ADDRESS, "10.9.9.7")
	w.run(100)
	var info := net_info()
	talking.send(MwNetTransport.HOST_PEER, P.CH_RELIABLE, P.hello(str(info["build"]), info["rom"],
			int(info["schema"]), P.random_bytes(P.NONCE_BYTES), 1, PackedByteArray()))
	w.run(MwNetHost.HELLO_DEADLINE_MS + 100)
	assert_lt(MwNetHost.HELLO_DEADLINE_MS, MwNetHost.HANDSHAKE_MS)
	assert_eq(w.host.peer_counts()["pending"], 1, "the silent one dropped; the one that said HELLO waits on")
	assert_eq(_messages(silent)[-1].get("type"), DISCONNECTED, "told so")
	w.run(MwNetHost.HANDSHAKE_MS)
	assert_eq(w.host.peer_counts()["pending"], 0, "the handshake's own time")


# --- M3: a changed certificate, the rejoin key -------------------------------------------------------

func test_a_changed_key_is_asked_about_with_a_password_too() -> void:
	var net := MwNetLoopback.new(23)
	var fake := FakeHost.new(net, "10.0.0.80", World.fake_cert(81))
	MwNetKnownHosts.remember("10.0.0.80", P.PORT, World.fake_cert(80))      # last time: another key
	MwNetRejoin.save("10.0.0.80", P.PORT, 7, P.random_bytes(P.KEY_BYTES))
	var c := _client(net)
	var changed := []
	c.key_changed.connect(func(a: PackedByteArray, b: PackedByteArray) -> void: changed.append([a, b]))
	c.connect_to("10.0.0.80", P.PORT, "pw", 1)
	_pump(net, fake, c, func() -> bool: return c.state == C.State.TRUST or c.state == C.State.DONE)
	assert_eq(c.state, C.State.TRUST, "THIS HOST'S KEY HAS CHANGED: asked, though a password is set")
	assert_eq(changed, [[MwNetIdentity.fingerprint_of(World.fake_cert(80)),
			MwNetIdentity.fingerprint_of(World.fake_cert(81))]])
	assert_true(fake.types.is_empty(), "nothing went to the new key's holder: no HELLO, no proof (%s)"
			% str(fake.types))
	c.cancel()


func test_the_rejoin_key_never_travels() -> void:
	var net := MwNetLoopback.new(24)
	var der := World.fake_cert(82)
	var fake := FakeHost.new(net, "10.0.0.82", der)
	MwNetKnownHosts.remember("10.0.0.82", P.PORT, der)
	var key := P.random_bytes(P.KEY_BYTES)
	MwNetRejoin.save("10.0.0.82", P.PORT, 7, key)
	var c := _client(net)
	c.connect_to("10.0.0.82", P.PORT, "pw", 1)
	_pump(net, fake, c, func() -> bool: return not fake.hellos.is_empty() or c.state == C.State.DONE)
	assert_eq(fake.hellos.size(), 1, "HELLO came")
	var hello := fake.hellos[0]
	assert_ne(hello["key"], key, "not the key itself")
	assert_eq(hello["key"], P.rejoin_proof(key, hello["nonce"], MwNetIdentity.fingerprint_of(der)),
			"its proof, bound to the client's nonce and the certificate it is pinned to")
	c.cancel()


func test_the_host_takes_a_rejoin_keys_proof_not_the_key() -> void:
	var w := World.new(25, "pw")
	var client := w.join("pw")
	assert_true(w.run_until(_in(client)))
	var match_id := w.host.start_match(PackedByteArray([1]))
	for i in 10:
		w.host.step()
		w.run(17)
	var key := client.rejoin_key()
	assert_eq(key.size(), P.KEY_BYTES)
	client.transport.disconnect_peer(MwNetTransport.HOST_PEER, true)
	w.clients.erase(client)
	w.run(200)
	assert_false(bool(w.host.lobby.machines[client.machine]["connected"]), "kept for a rejoin")
	var fp := MwNetIdentity.fingerprint_of(w.der)
	var elsewhere := MwNetIdentity.fingerprint_of(World.fake_cert(66))
	var bare := func(_n: PackedByteArray) -> PackedByteArray: return key
	var for_another := func(n: PackedByteArray) -> PackedByteArray: return P.rejoin_proof(key, n, elsewhere)
	var proof := func(n: PackedByteArray) -> PackedByteArray: return P.rejoin_proof(key, n, fp)
	assert_eq(_hello_answer(w, "10.9.7.1", bare), P.Refusal.RUNNING, "the bare key (version 5's HELLO) is no proof")
	assert_eq(_hello_answer(w, "10.9.7.2", for_another), P.Refusal.RUNNING,
			"a proof made for another certificate (a man in the middle's) is none either")
	assert_eq(_hello_answer(w, "10.9.7.3", proof), 0, "its proof: on to the password")
	MwNetRejoin.save(World.HOST_ADDRESS, P.PORT, match_id, key)
	var back := w.join("pw")
	assert_true(w.run_until(_in(back)))
	assert_eq([back.state, back.machine], [C.State.RUNNING, client.machine], "back on its machine")


# --- L4: the host's hashes -------------------------------------------------------------------------

func test_a_hosts_hashes_cant_grow_without_bound() -> void:
	var w := World.new(26)
	var c := w.join()
	assert_true(w.run_until(_in(c)))
	w.host.start_match(PackedByteArray([1]))
	var value := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	var most := 0
	for i in 2400:
		for j in P.MAX_HASHES:
			var k := i * P.MAX_HASHES + j
			# half far past anything the stream holds, half within its window but ahead of it
			var hash_tick := 1000000 + k if j % 2 == 0 else w.host.tick + 1 + k % 1000
			w.host.add_hash(hash_tick, k & 3, value)
		w.host.step()
		w.net.advance(17)
		w.poll()
		most = maxi(most, c.host_hashes.size())
	var far := 0
	for h: int in c.host_hashes:
		if (h >> 2) > c.stream.confirmed + MwNetTickReceiver.WINDOW:
			far += 1
	assert_eq(c.state, C.State.RUNNING)
	assert_eq(far, 0, "nothing past the stream's window kept")
	assert_between(most, 1, C.HASHES_KEPT, "at most HASHES_KEPT kept (%d at the most)" % most)
	var at := w.host.tick
	w.host.add_hash(at, 1, value)
	for i in 5:
		w.host.step()
		w.net.advance(17)
		w.poll()
	assert_eq(c.host_hash(at, 1), value, "an honest hash still arrives")
