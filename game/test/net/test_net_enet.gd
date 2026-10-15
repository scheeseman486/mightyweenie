extends "res://test/net/net_test_base.gd"
## Plan 35 work item 2: real sockets - a host and a client in this process
## over ENet with DTLS (MwNetEnet) on 127.0.0.1 and ::1 (the host bound to
## both on one socket): the first contact fetches the certificate, the
## pinned session joins with the password, a short match streams both ways;
## a client pinned to another certificate can't complete DTLS and finds the
## key changed. Work item 7: busy frames make ENet's packet throttle drop
## nothing (MwNetEnet.THROTTLE).

const C := preload("res://src/net/net_client.gd")

var _id: MwNetIdentity
var _other: MwNetIdentity


func before_all() -> void:
	super.before_all()
	_id = MwNetIdentity.create()
	_other = MwNetIdentity.create()


## The engine's log of DTLS handshakes it refused (a pinned client meeting
## another certificate) or of a disconnect's straggling packets reaching the
## host's DTLS server as a new handshake (MwNetEnet): expected, not failures.
func _handle_dtls_errors() -> void:
	for e in get_errors():
		if e.contains_text("TLS handshake") or e.contains_text("mbedtls"):
			e.handled = true


## Lets closed transports finish (so nothing lingers into the next test).
func after_each() -> void:
	var end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end and not MwNetEnet._lingering.is_empty():
		MwNetEnet.service_lingering()
		OS.delay_msec(2)
	_handle_dtls_errors()


## Polls [param host] and [param clients] in real time until [param done]
## (or [param limit_ms]).
func _pump(host: MwNetHost, clients: Array, done: Callable, limit_ms := 5000) -> bool:
	var end := Time.get_ticks_msec() + limit_ms
	while Time.get_ticks_msec() < end:
		var now := Time.get_ticks_msec()
		host.poll(now)
		for client: MwNetClient in clients:
			client.poll(now)
		if done.call():
			return true
		OS.delay_msec(1)
	return done.call()


func _host(password: String) -> MwNetHost:
	var enet := MwNetEnet.host(0, _id)
	assert_eq(enet.error, OK, "bound")
	var host := MwNetHost.new(enet, _id.der, password, net_info())
	host.open()
	return host


func _client() -> MwNetClient:
	var client := MwNetClient.new()
	client.info = net_info()
	return client


func _has_ipv6() -> bool:
	for a in IP.get_local_addresses():
		if a == "0:0:0:0:0:0:0:1" or a == "::1":
			return true
	return false


func _join_and_stream(address: String) -> void:
	var host := _host("pw")
	var port := (host.transport as MwNetEnet).local_port()
	var client := _client()
	var states := []
	client.state_changed.connect(func(new_state: int) -> void: states.append(new_state))
	client.connect_to(address, port, "pw", 1)
	assert_true(_pump(host, [client], func() -> bool: return client.state == C.State.LOBBY \
			or client.state == C.State.DONE),
			"joined over %s" % address)
	assert_eq(client.state, C.State.LOBBY, "fail %d refusal %d" % [client.fail, client.refusal])
	if client.state != C.State.LOBBY:
		host.close()
		return
	assert_eq(states, [C.State.FETCHING, C.State.CONNECTING, C.State.HANDSHAKE, C.State.LOBBY],
			"fetched the certificate, then a pinned DTLS session")
	assert_true(client.transport is MwNetEnet)
	assert_eq(client.transport.pinned_fingerprint(), _id.fingerprint, "pinned to the host's certificate")
	assert_eq(MwNetKnownHosts.lookup(address, port), _id.der)
	assert_eq(client.numbers, [2] as Array[int])
	# plan 38 (protocol version 4): a start record of 12 chunks - the host's custom teams - over DTLS
	var record := MwNetProtocol.random_bytes(MwNetProtocol.RECORD_CHUNK * 11 + 33)
	var got := []
	client.started.connect(func(_m: int, _t: int, r: PackedByteArray) -> void: got.append(r))
	host.start_match(record)
	assert_true(_pump(host, [client], func() -> bool: return not got.is_empty()))
	assert_eq(client.state, C.State.RUNNING)
	assert_eq(got, [record], "START's chunks: the record whole")
	var mine := MwNetInput.blank()
	var presses := 0
	for i in 60:
		var pressed := PackedInt32Array()
		if i % 6 == 0 and i < 40:
			pressed.append(4)
			presses += 1
		mine = MwNetInput.next_state(mine, PackedInt32Array([0]) if i % 12 < 6 else PackedInt32Array(), pressed)
		client.send_input({2: mine})
		host.step({1: MwNetInput.blank()})
		var until := Time.get_ticks_msec() + 16
		_pump(host, [client], func() -> bool: return Time.get_ticks_msec() >= until, 50)
	assert_true(_pump(host, [client], func() -> bool: return client.stream.confirmed >= host.tick), \
			"the stream arrived")
	var same := true
	var counted := 0
	var prev := MwNetInput.blank_tick()
	for n in range(0, host.tick + 1):
		var t := host.stream.get_tick(n)
		same = same and client.stream.get_tick(n) == t
		counted += MwNetInput.presses(MwNetInput.player(prev, 2), MwNetInput.player(t, 2), 4)
		prev = t
	assert_true(same, "the client holds exactly the host's ticks")
	assert_eq(counted, presses, "every press of the client's reached the host's stream")
	assert_gt(client.rtt_ms + 1, 0)
	client.exit_lobby()
	assert_true(_pump(host, [], func() -> bool: return host.lobby.players.size() == 1), "EXIT LOBBY reached the host")
	host.close()
	_pump(host, [], func() -> bool: return MwNetEnet._lingering.is_empty(), 3000)
	_handle_dtls_errors()


func test_dtls_over_ipv4() -> void:
	_join_and_stream("127.0.0.1")


func test_dtls_over_ipv6() -> void:
	if not _has_ipv6():
		pending("this machine has no IPv6 loopback")
		return
	_join_and_stream("::1")


func test_pinned_to_another_certificate() -> void:
	var host := _host("")
	var port := (host.transport as MwNetEnet).local_port()
	MwNetKnownHosts.remember("127.0.0.1", port, _other.der)   # what it saw "last time"
	var client := _client()
	var changed := []
	client.key_changed.connect(func(a: PackedByteArray, b: PackedByteArray) -> void: changed.append([a, b]))
	client.connect_to("127.0.0.1", port, "", 1)
	assert_true(_pump(host, [client], func() -> bool: return client.state == C.State.TRUST \
			or client.state == C.State.DONE))
	_handle_dtls_errors()     # mbedTLS reports the handshake it refused
	assert_eq(client.state, C.State.TRUST, "DTLS refused the pinned session; the certificate fetched again differs")
	assert_eq(changed, [[_other.fingerprint, _id.fingerprint]])
	assert_eq(host.lobby.players.size(), 1, "nobody got in meanwhile")
	client.trust_new_key()
	assert_true(_pump(host, [client], func() -> bool: return client.state == C.State.LOBBY \
			or client.state == C.State.DONE))
	assert_eq(client.state, C.State.LOBBY, "in once trusted")
	assert_eq(MwNetKnownHosts.lookup("127.0.0.1", port), _id.der)
	client.cancel()
	host.close()
	host.transport.abort()    # nobody left to tell
	_handle_dtls_errors()


func test_wrong_password_over_dtls() -> void:
	var host := _host("right")
	var port := (host.transport as MwNetEnet).local_port()
	var client := _client()
	client.connect_to("127.0.0.1", port, "wrong", 1)
	assert_true(_pump(host, [client], func() -> bool: return client.state == C.State.DONE))
	assert_eq([client.fail, client.refusal], [C.Fail.REFUSED, MwNetProtocol.Refusal.WRONG_PASSWORD])
	assert_eq(client.refusal_wait, 1)
	host.close()
	host.transport.abort()
	_handle_dtls_errors()


## Work item 7 (found in the soak): ENet drops unreliable messages by its
## packet throttle, which sinks each time a round trip comes in well above
## the lowest of the last 5 s - a busy frame on either machine - and the
## soak saw it throw away up to a third of the stream (and of a client's
## inputs) on a clean link. MwNetEnet configures every peer, host's and
## client's, so the throttle never sinks (deceleration 0): checked on both
## ends of a connection, then every message of a busy exchange arrives and
## the traffic counters agree.
func test_the_throttle_never_drops() -> void:
	var host_end := MwNetEnet.host(0, _id)
	var client_end := MwNetEnet.client("127.0.0.1", host_end.local_port(), _id.der)
	var peer := -1
	var end := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < end and (peer < 0 or not client_end.is_open()
			or client_end.connection.get_peers().is_empty()):
		host_end.poll()
		client_end.poll()
		for event in host_end.take_events():
			if event["kind"] == MwNetTransport.Kind.CONNECTED:
				peer = int(event["peer"])
		client_end.take_events()
		OS.delay_msec(1)
	assert_gt(peer, 0, "connected")
	for enet: MwNetEnet in [host_end, client_end]:
		for enet_peer in enet.connection.get_peers():
			if enet_peer.is_active():
				assert_eq(int(enet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_DECELERATION)),
						MwNetEnet.THROTTLE[2], "the throttle never sinks (%s)"
						% ("host" if enet == host_end else "client"))
				assert_eq(int(enet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE_INTERVAL)),
						MwNetEnet.THROTTLE[0])
	assert_eq(MwNetEnet.THROTTLE[2], 0)
	var data := PackedByteArray()
	data.resize(80)
	var got := 0
	for i in 120:
		host_end.send(peer, MwNetProtocol.CH_RELIABLE, data.slice(0, 20))     # acknowledged: round trips measured
		host_end.send(peer, MwNetProtocol.CH_INPUT, data)
		client_end.send(MwNetTransport.HOST_PEER, MwNetProtocol.CH_INPUT, data)
		host_end.poll()
		OS.delay_msec(120 if i % 12 == 6 else 8)                         # now and then a busy frame
		client_end.poll()
		for event in client_end.take_events():
			if event["kind"] == MwNetTransport.Kind.PACKET and int(event["channel"]) == MwNetProtocol.CH_INPUT:
				got += 1
		host_end.poll()
		host_end.take_events()
	OS.delay_msec(50)
	client_end.poll()
	for event in client_end.take_events():
		if event["kind"] == MwNetTransport.Kind.PACKET and int(event["channel"]) == MwNetProtocol.CH_INPUT:
			got += 1
	assert_eq(got, 120, "every unreliable message arrived")
	assert_eq(int(host_end.traffic["throttle_low"]), 32, "the throttle stayed full")
	assert_eq(int(client_end.traffic["received"]), int(host_end.traffic["sent"]),
			"counted: what the host sent, the client received")
	assert_eq(int(client_end.traffic["received_messages"]), 240)
	assert_gt(int(host_end.traffic["enet_sent"]), int(host_end.traffic["sent"]),
			"ENet's datagrams carry the messages and more")
	assert_gt(int(client_end.traffic["enet_received_datagrams"]), 0)
	client_end.abort()
	host_end.abort()
	_handle_dtls_errors()


## Work item 7: ENet's own keep-alive pings are reliable messages, and under
## heavy loss every reliable message is a chance for ENet to give up on the
## peer (its retransmissions back off and it drops the peer once one goes
## unanswered for about six tries). The protocol pings on its own
## (unreliable), so ENet pings every 2 s instead of every 500 ms: an idle
## connection's client sends a third of the datagrams it used to.
func test_enet_pings_every_two_seconds() -> void:
	var host_end := MwNetEnet.host(0, _id)
	var enet := MwNetEnet.client("127.0.0.1", host_end.local_port(), _id.der)
	var end := Time.get_ticks_msec() + 5000
	var up := false
	while Time.get_ticks_msec() < end and not up:
		host_end.poll()
		enet.poll()
		for event in enet.take_events():
			up = up or event["kind"] == MwNetTransport.Kind.CONNECTED
		host_end.take_events()
		OS.delay_msec(2)
	assert_true(up, "connected")
	var settle := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < settle:
		host_end.poll()
		enet.poll()
		OS.delay_msec(5)
	var before := int(enet.traffic["enet_sent_datagrams"])
	var idle := Time.get_ticks_msec() + 4500
	while Time.get_ticks_msec() < idle:
		host_end.poll()
		enet.poll()
		host_end.take_events()
		enet.take_events()
		OS.delay_msec(5)
	var sent := int(enet.traffic["enet_sent_datagrams"]) - before
	assert_eq(MwNetEnet.PING_INTERVAL_MS, 2000)
	# ENet's default (500 ms) made 18 here: its pings and its answers to the host's
	assert_between(sent, 1, 9, "an idle client's datagrams in 4.5 s: its pings every 2 s, its answers to the host's")
	enet.abort()
	host_end.abort()
	_handle_dtls_errors()
