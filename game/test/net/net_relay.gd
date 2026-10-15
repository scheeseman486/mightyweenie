extends RefCounted
## Plan 35 work item 7: a man in the middle on real sockets. The relay
## listens where clients expect the host, ends their DTLS with a key and
## certificate of its own (it has no other private key), and for each
## client opens a DTLS session of its own to the real host, passing every
## message on both ways - but the host's certificate (CERT), which it
## replaces by its own, as a man in the middle must: a client pinned to the
## host's certificate can't finish DTLS with him at all.
##
## What the client then does (docs/net.md "The handshake", section 6 of the
## plan): a client that knew the host finds THIS HOST'S KEY HAS CHANGED
## (trust on first use) and asks before going on - plan 45 (M3): with a
## password too; trusted anyway, its proof binds the relay's certificate -
## the one its session is pinned to - so the host refuses it (WRONG
## PASSWORD). [method check] runs both cases (test_net_mitm.gd, net-soak
## through mitm_check.gd).

const C := preload("res://src/net/net_client.gd")

## Where clients connect: the relay's own ENet with DTLS.
var transport: MwNetEnet
var identity: MwNetIdentity
var host_address := ""
var host_port := 0
## Replace the host's CERT by the relay's own (false: pass it on unchanged).
var replace_cert := true
## Messages passed on: "up" (client to host), "down", "certs" replaced.
var counts := {"up": 0, "down": 0, "certs": 0}
var _up := {}          # client peer -> MwNetEnet to the host
var _queued := {}      # client peer -> [[channel, data] ...] until the host's session is up
var _ready := {}       # client peer -> true once its host session connected


## A relay on [param port] (all addresses) with [param identity_], passing
## everything to the host at [param address]:[param port_to]. Its
## [member transport]'s error says whether it could bind.
static func listen(port: int, identity_: MwNetIdentity, address: String, port_to: int) -> RefCounted:
	var r: RefCounted = (load("res://test/net/net_relay.gd") as GDScript).new()
	r.identity = identity_
	r.host_address = address
	r.host_port = port_to
	r.transport = MwNetEnet.host(port, identity_)
	return r


func poll() -> void:
	transport.poll()
	for ev in transport.take_events():
		var peer := int(ev["peer"])
		match int(ev["kind"]):
			MwNetTransport.Kind.CONNECTED:
				# any certificate will do for him: an unpinned session
				_up[peer] = MwNetEnet.client(host_address, host_port)
				_queued[peer] = []
			MwNetTransport.Kind.DISCONNECTED:
				if _up.has(peer):
					(_up[peer] as MwNetEnet).abort()
				_up.erase(peer)
				_queued.erase(peer)
				_ready.erase(peer)
			MwNetTransport.Kind.PACKET:
				if _ready.has(peer):
					(_up[peer] as MwNetEnet).send(MwNetTransport.HOST_PEER, int(ev["channel"]), ev["data"])
					counts["up"] += 1
				elif _queued.has(peer):
					(_queued[peer] as Array).append([int(ev["channel"]), ev["data"]])
	for peer: int in _up.keys():
		var up: MwNetEnet = _up[peer]
		up.poll()
		for ev in up.take_events():
			match int(ev["kind"]):
				MwNetTransport.Kind.CONNECTED:
					_ready[peer] = true
					for packet: Array in _queued.get(peer, []):
						up.send(MwNetTransport.HOST_PEER, int(packet[0]), packet[1])
						counts["up"] += 1
					_queued[peer] = []
				MwNetTransport.Kind.DISCONNECTED:
					transport.disconnect_peer(peer)
				MwNetTransport.Kind.PACKET:
					var data: PackedByteArray = ev["data"]
					if replace_cert and MwNetProtocol.peek(data).x == MwNetProtocol.Type.CERT:
						data = MwNetProtocol.cert(identity.der)
						counts["certs"] += 1
					transport.send(peer, int(ev["channel"]), data)
					counts["down"] += 1


func close() -> void:
	for peer: int in _up.keys():
		(_up[peer] as MwNetEnet).abort()
	_up.clear()
	transport.abort()


## The man-in-the-middle check on real sockets (ENet with DTLS) at
## [param address] (127.0.0.1 or ::1), every endpoint in this process:
##
## 1. a host (its own key) with [param password] on a port; a client joins
##    it directly and remembers it (trust on first use), then leaves;
## 2. the host moves to another port and the relay takes the host's old one
##    - the address the client knows - with a key of its own;
## 3. the client joins the same address again.
##
## {ok, joined (step 1), state, fail, refusal, changed (key_changed's
## fingerprints, or []), host_refused (the host's refusals), certs (the
## relay's certificates sent), text (one line saying what happened)}.
## The client must stop in TRUST with the host's old fingerprint and the
## relay's new one; with a password (plan 45: asked too) it is then
## trusted anyway, and the client must be REFUSED (WRONG PASSWORD) and the
## host must have refused it. Nobody ends up in the
## lobby either way. With [param replace] false the relay passes the
## host's certificate on unchanged: the client, pinned to it, can't finish
## DTLS with the relay and gives up (NO ANSWER). [param info] is what the
## endpoints claim to be (MwNetHost.local_info, or a test's).
static func check(address: String, password: String, info: Dictionary, host_id: MwNetIdentity,
		relay_id: MwNetIdentity, replace := true, limit_ms := 20000) -> Dictionary:
	var out := {"ok": false, "joined": false, "state": -1, "fail": 0, "refusal": 0, "changed": [],
			"host_refused": [], "certs": 0, "text": ""}
	var enet := MwNetEnet.host(0, host_id)
	if enet.error != OK:
		out["text"] = "the host couldn't bind"
		return out
	var port := enet.local_port()
	var host := MwNetHost.new(enet, host_id.der, password, info)
	host.open()
	var client := MwNetClient.new()
	client.info = info
	client.connect_to(address, port, password, 1)
	out["joined"] = _pump([host], [client], func() -> bool: return client.state in [C.State.LOBBY, C.State.DONE], \
			limit_ms) \
			and client.state == C.State.LOBBY
	client.exit_lobby()
	_pump([host], [client], func() -> bool: return host.lobby.players.size() == 1, 3000)
	host.close()
	_pump([host], [], func() -> bool: return MwNetEnet._lingering.is_empty(), 3000)
	if not out["joined"]:
		out["text"] = "the first, direct join failed (state %d, fail %d)" % [client.state, client.fail]
		return out
	# the real host elsewhere; the relay at the address the client knows
	var t2 := MwNetEnet.host(0, host_id)
	var host2 := MwNetHost.new(t2, host_id.der, password, info)
	host2.open()
	host2.refused.connect(func(_a: String, code: int) -> void: (out["host_refused"] as Array).append(code))
	var relay: RefCounted = listen(port, relay_id, address, t2.local_port())
	relay.replace_cert = replace
	if relay.transport.error != OK:
		out["text"] = "the relay couldn't bind the host's old port"
		host2.transport.abort()
		return out
	var c2 := MwNetClient.new()
	c2.info = info
	c2.key_changed.connect(func(a: PackedByteArray, b: PackedByteArray) -> void: out["changed"] = [a, b])
	c2.connect_to(address, port, password, 1)
	_pump([host2, relay], [c2], func() -> bool: return c2.state in [C.State.LOBBY, C.State.TRUST, C.State.DONE],
			limit_ms)
	var asked := c2.state == C.State.TRUST
	if asked and password != "":
		# plan 45 (M3): asked with a password too - trusted anyway, the proofs still refuse him
		c2.trust_new_key()
		_pump([host2, relay], [c2], func() -> bool: return c2.state in [C.State.LOBBY, C.State.DONE], limit_ms)
	out["state"] = c2.state
	out["fail"] = c2.fail
	out["refusal"] = c2.refusal
	out["certs"] = relay.counts["certs"]
	if not replace:
		out["ok"] = c2.state == C.State.DONE and c2.fail == C.Fail.NO_ANSWER and host2.lobby.players.size() == 1
		out["text"] = "passing the host's certificate on: %s" % ("NO ANSWER (DTLS pinned to the host's key " \
				+ "never completes with the relay)" if out["ok"] else "state %d, fail %d" % [c2.state, c2.fail])
	elif password != "":
		var ch: Array = out["changed"]
		out["ok"] = asked and ch.size() == 2 and ch[0] == host_id.fingerprint and ch[1] == relay_id.fingerprint \
				and c2.state == C.State.DONE and c2.fail == C.Fail.REFUSED \
				and c2.refusal == MwNetProtocol.Refusal.WRONG_PASSWORD \
				and MwNetProtocol.Refusal.WRONG_PASSWORD in out["host_refused"] and host2.lobby.players.size() == 1
		var refused_text: String = MwNetProtocol.REFUSAL_TEXT.get(c2.refusal, "?")
		out["text"] = "with a password: %s" % ("THIS HOST'S KEY HAS CHANGED asked; trusted anyway, REFUSED - "
				+ refused_text + " (the host saw the relay's certificate in the proof)" if out["ok"]
				else "NOT asked and refused (asked %s, state %d, fail %d, refusal %d)"
				% [str(asked), c2.state, c2.fail, c2.refusal])
	else:
		var ch: Array = out["changed"]
		out["ok"] = c2.state == C.State.TRUST and ch.size() == 2 and ch[0] == host_id.fingerprint \
				and ch[1] == relay_id.fingerprint and host2.lobby.players.size() == 1
		out["text"] = "without a password: %s" % ("THIS HOST'S KEY HAS CHANGED (%s -> %s), asked before going on"
				% [MwNetIdentity.readable(host_id.fingerprint).left(9), MwNetIdentity.readable(
				relay_id.fingerprint).left(9)] if out["ok"]
				else "NOT flagged (state %d, fail %d)" % [c2.state, c2.fail])
	c2.cancel()
	relay.close()
	host2.close()
	host2.transport.abort()
	return out


## Polls [param sessions] (hosts, relays) and [param clients] in real time
## until [param done] (or [param limit_ms]); true if it held.
static func _pump(sessions: Array, clients: Array, done: Callable, limit_ms: int) -> bool:
	var end := Time.get_ticks_msec() + limit_ms
	while Time.get_ticks_msec() < end:
		var now := Time.get_ticks_msec()
		for session: Object in sessions:
			if session is MwNetHost:
				(session as MwNetHost).poll(now)
			else:
				session.call("poll")
		for client: MwNetClient in clients:
			client.poll(now)
		MwNetEnet.service_lingering()
		if done.call():
			return true
		OS.delay_msec(1)
	return done.call()
