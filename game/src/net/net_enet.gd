class_name MwNetEnet
extends MwNetTransport
## The real transport (plan 35 section 1): Godot's ENet over UDP, always
## encrypted with DTLS, node-free (an [ENetConnection] polled from [method
## poll]; no MultiplayerAPI, no RPCs, no node paths).
##
## * The host binds "*" - IPv4 and IPv6 on one dual-stack socket - and sets
##   up DTLS with its key and self-signed certificate ([MwNetIdentity]).
## * A client pins the host's certificate ([code]TLSOptions.client[/code]
##   with that certificate as the only trusted one, and the certificate's
##   common name): the DTLS handshake fails unless the other end holds that
##   certificate's private key, so a session's [method pinned_fingerprint]
##   is the certificate it really talks to - what the password proofs bind
##   (MwNetProtocol.proof). The first contact with a host, whose
##   certificate isn't known yet, connects unpinned
##   ([code]TLSOptions.client_unsafe[/code]) only to fetch the certificate
##   (the host sends it first thing, MwNetProtocol.cert), then connects
##   again pinned ([MwNetClient]). Godot gives no way to read the peer's
##   certificate from a DTLS session, hence the two steps.
## * Channel 0 is sent reliable, 1 and 2 unreliable and unsequenced (the
##   protocol numbers everything and takes repeats and any order).
## * ENet drops a silent peer 3-12 s after it goes quiet (section 3: P7
##   DISCONNECTED): its timeout runs from the first reliable message left
##   unanswered, a keep-alive ping within 2 s ([constant PING_INTERVAL_MS]),
##   and ends after six tries and at least 3 s, or at 10 s ([constant
##   TIMEOUT]). On 127.0.0.1 that took 3-7 s.
## * Closing is graceful: what was sent goes out at once (a flush), each
##   peer is disconnected once it has acknowledged everything (ENet drops
##   a peer's last messages if a disconnect overtakes them), and the closed
##   transport lingers - serviced by any MwNetEnet's [method poll] - until
##   its peers are gone or it has been serviced [constant LINGER_POLLS]
##   times (counted, not timed: nothing here reads a clock - the sessions
##   get the time from their caller). ([method abort]
##   drops everything at once.) Godot's DTLS server forgets a peer's session
##   the moment ENet lets the peer go, so a straggling packet of the
##   disconnect (a resent DISCONNECT, a close notify) reaches it as a new
##   handshake and the engine logs "TLS handshake error": harmless.
## * The packet size: messages are at most MwNetProtocol.MAX_MESSAGE
##   (1024) bytes; ENet's headers and DTLS's (up to ~80 bytes) keep a
##   datagram of one message under 1200. ENet may bundle several small
##   messages into one datagram up to its MTU (1392 bytes in Godot's ENet,
##   not settable from scripts).
## * ENet's packet throttle never drops anything ([constant THROTTLE]).
## * [member traffic] counts what went through (the soak's bandwidth
##   figures, docs/net.md "The soak").

## The certificate's common name, checked by pinned clients.
const COMMON_NAME := "mightyweenie"
## ENet's peer timeout (limit, minimum, maximum ms): six tries and 3 s, or 10 s.
const TIMEOUT := [32, 3000, 10000]
## ENet's keep-alive ping (ms; ENet's default is 500).
const PING_INTERVAL_MS := 2000
## ENet's packet throttle (interval ms, acceleration, deceleration) for
## every peer. ENet drops unreliable messages by a "throttle" that sinks
## each time a round trip comes in well above the usual - a busy frame on
## either machine (a screen being made, a slow CPU) - and climbs back
## slowly: the soak found up to a third of the stream (and of a client's
## inputs) thrown away on a clean link (work item 7). The protocol repeats
## and resends what it needs itself (MwNetTickLog, RESEND), so here nothing
## is thrown away: deceleration 0 keeps the throttle at its full 32. Nor
## would it save a full line: it takes its round trips from the reliable
## messages' acknowledgements, a few a minute in a match - the host paces
## the stream itself instead (MwNetPace; docs/net.md "A slow uplink").
const THROTTLE := [5000, 2, 0]
## The throttle new peers get: [constant THROTTLE] (the soak compares other
## settings: online_match.gd --throttle).
static var throttle: Array = THROTTLE.duplicate()
## How many times a closed transport is serviced at most while it finishes
## its disconnects (2 s at one poll a tick; on a good network it is done
## within a round trip).
const LINGER_POLLS := 120

static var _lingering: Array[MwNetEnet] = []

var connection: ENetConnection
## The error setting it up (OK when working).
var error := OK
## What went through, in bytes and counts: the messages themselves
## ("sent", "received") and ENet's datagrams ("enet_..."): the messages with
## ENet's own headers, acknowledgements and pings, before DTLS encrypts them
## (DTLS's records, what is on the wire, are larger again: the chaos proxy
## counts those). Counted for the transport's whole life; "sent_reliable":
## the part sent on the reliable channel; "throttle_low": the lowest packet
## throttle a peer had (32: nothing dropped), "throttle_sum" over
## "throttle_samples" its mean (a sample a peer each poll).
var traffic := {"sent": 0, "sent_messages": 0, "received": 0, "received_messages": 0,
		"sent_reliable": 0, "sent_reliable_messages": 0,
		"enet_sent": 0, "enet_sent_datagrams": 0, "enet_received": 0, "enet_received_datagrams": 0,
		"throttle_low": 32, "throttle_sum": 0, "throttle_samples": 0}
var _client := false
var _pinned := PackedByteArray()
var _peers := {}
var _ids := {}
var _next := 1
var _failed := false
var _linger := 0


## A host listening on [param port] (all addresses, IPv4 and IPv6) for
## [param max_peers] connections, encrypted with [param identity].
static func host(port: int, identity: MwNetIdentity, max_peers := 32, bind := "*") -> MwNetEnet:
	var enet := MwNetEnet.new()
	enet.connection = ENetConnection.new()
	enet.error = enet.connection.create_host_bound(bind, port, max_peers, MwNetProtocol.CHANNELS)
	if enet.error == OK:
		enet.error = enet.connection.dtls_server_setup(TLSOptions.server(identity.key, identity.cert))
	if enet.error != OK:
		enet.connection.destroy()
		enet.connection = null
	return enet


## A client connecting to [param address] (an IPv4 or IPv6 address; host
## names are resolved by the page first, plan 35 section 2) on [param
## port], pinned to the certificate [param pinned_der] (DER; empty: a first
## contact, unpinned).
static func client(address: String, port: int, pinned_der := PackedByteArray()) -> MwNetEnet:
	var enet := MwNetEnet.new()
	enet._client = true
	enet.connection = ENetConnection.new()
	enet.error = enet.connection.create_host(1, MwNetProtocol.CHANNELS)
	var options: TLSOptions
	if pinned_der.is_empty():
		options = TLSOptions.client_unsafe()
	else:
		var cert := MwNetIdentity.cert_from_der(pinned_der)
		if cert == null:
			enet.error = ERR_INVALID_DATA
		else:
			options = TLSOptions.client(cert, COMMON_NAME)
			enet._pinned = MwNetIdentity.fingerprint_of(pinned_der)
	if enet.error == OK:
		enet.error = enet.connection.dtls_client_setup(COMMON_NAME, options)
	if enet.error == OK:
		var peer := enet.connection.connect_to_host(address, port, MwNetProtocol.CHANNELS)
		if peer == null:
			enet.error = ERR_CANT_CONNECT
	if enet.error != OK:
		enet.connection.destroy()
		enet.connection = null
		enet._fail()
	return enet


## Services the closed transports still lingering, then turns ENet's events into [member events]
## (at most 1000 a call) and adds its counts to [member traffic]. A client whose connection fails
## gets one DISCONNECTED with its error, then nothing.
func poll() -> void:
	service_lingering()
	if connection == null or _linger > 0:
		return
	for _i in 1000:
		if connection == null:
			return                                   # a client's connection failed (_fail)
		var ev := connection.service(0)
		var type: int = ev[0]
		if type == ENetConnection.EVENT_NONE:
			break
		if type == ENetConnection.EVENT_ERROR:
			# a client: the connection failed (a DTLS handshake refused - the
			# wrong certificate - or the socket broke); a host goes on
			if _client:
				_fail()
				return
			break
		var peer: ENetPacketPeer = ev[1]
		match type:
			ENetConnection.EVENT_CONNECT:
				var id := _next
				_next += 1
				_peers[id] = peer
				_ids[peer] = id
				peer.set_timeout(TIMEOUT[0], TIMEOUT[1], TIMEOUT[2])
				peer.throttle_configure(throttle[0], throttle[1], throttle[2])
				peer.ping_interval(PING_INTERVAL_MS)
				_event(Kind.CONNECTED, id)
			ENetConnection.EVENT_DISCONNECT:
				var id := int(_ids.get(peer, 0))
				if id != 0:
					_ids.erase(peer)
					_peers.erase(id)
					_event(Kind.DISCONNECTED, id)
				elif _client:
					_fail()
			ENetConnection.EVENT_RECEIVE:
				var data := peer.get_packet()
				var id := int(_ids.get(peer, 0))
				if id != 0:
					traffic["received"] += data.size()
					traffic["received_messages"] += 1
					_event(Kind.PACKET, id, int(ev[3]), data)
	_count_enet()


## ENet's own counts since the last call, added to [member traffic].
func _count_enet() -> void:
	if connection == null:
		return
	for peer: ENetPacketPeer in _peers.values():
		if peer.is_active():
			var now := int(peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE))
			traffic["throttle_low"] = mini(int(traffic["throttle_low"]), now)
			traffic["throttle_sum"] += now
			traffic["throttle_samples"] += 1
	traffic["enet_sent"] += int(connection.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	traffic["enet_sent_datagrams"] += int(connection.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS))
	traffic["enet_received"] += int(connection.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	traffic["enet_received_datagrams"] += int(connection.pop_statistic(
			ENetConnection.HOST_TOTAL_RECEIVED_PACKETS))


## A client whose connection failed: one DISCONNECTED (with error), then
## nothing.
func _fail() -> void:
	if _failed:
		return
	_failed = true
	_event(Kind.DISCONNECTED, HOST_PEER, -1, PackedByteArray(), true)
	if connection != null:
		_count_enet()
		connection.destroy()
		connection = null
	_peers.clear()
	_ids.clear()


## Sends [param data] to [param peer] on [param channel] (channel 0 reliable, the others
## unsequenced) and counts it in [member traffic]; false when it can't (no such peer or channel,
## too big, ENet refused it).
func send(peer: int, channel: int, data: PackedByteArray) -> bool:
	var enet_peer: ENetPacketPeer = _peers.get(peer)
	if enet_peer == null or data.size() > MwNetProtocol.MAX_MESSAGE or channel < 0 or channel >= MwNetProtocol.CHANNELS:
		return false
	var flags := ENetPacketPeer.FLAG_RELIABLE if channel == MwNetProtocol.CH_RELIABLE \
			else ENetPacketPeer.FLAG_UNSEQUENCED
	if enet_peer.send(channel, data, flags) != OK:
		return false
	traffic["sent"] += data.size()
	traffic["sent_messages"] += 1
	if channel == MwNetProtocol.CH_RELIABLE:
		traffic["sent_reliable"] += data.size()
		traffic["sent_reliable_messages"] += 1
	return true


## Sends what ENet holds now rather than at the next [method poll]; nothing once closed.
func flush() -> void:
	if connection != null and _linger == 0:
		connection.flush()


## Ends [param peer]'s connection once it has acknowledged what was sent; [param now]: at once,
## dropping it, its DISCONNECTED event straight away.
func disconnect_peer(peer: int, now := false) -> void:
	var enet_peer: ENetPacketPeer = _peers.get(peer)
	if enet_peer == null:
		return
	if now:
		enet_peer.peer_disconnect_now()
		_peers.erase(peer)
		_ids.erase(enet_peer)
		_event(Kind.DISCONNECTED, peer)
	else:
		enet_peer.peer_disconnect_later()


## Ends every connection gracefully: flushes, disconnects each peer once it has acknowledged
## everything and lingers, serviced by any MwNetEnet's [method poll], until its peers are gone
## or [constant LINGER_POLLS] polls have passed.
func close() -> void:
	if connection == null or _linger > 0:
		return
	connection.flush()
	for id in _peers.keys():
		(_peers[id] as ENetPacketPeer).peer_disconnect_later()
	connection.flush()
	_peers.clear()
	_ids.clear()
	_linger = LINGER_POLLS
	_lingering.append(self)


## Drops every peer at once and destroys the connection (a closing transport's too).
func abort() -> void:
	_lingering.erase(self)
	if connection == null:
		return
	for id in _peers.keys():
		(_peers[id] as ENetPacketPeer).peer_disconnect_now()
	connection.flush()
	_count_enet()
	connection.destroy()
	connection = null
	_peers.clear()
	_ids.clear()


## Services every closed transport still finishing its disconnects.
static func service_lingering() -> void:
	for t in _lingering.duplicate():
		t._drain()


func _drain() -> void:
	if connection != null:
		for _i in 100:
			var ev := connection.service(0)
			if ev[0] == ENetConnection.EVENT_NONE or ev[0] == ENetConnection.EVENT_ERROR:
				break
		var active := false
		for peer in connection.get_peers():
			if peer.get_state() != ENetPacketPeer.STATE_DISCONNECTED:
				active = true
		_linger -= 1
		_count_enet()
		if active and _linger > 0:
			return
		connection.destroy()
		connection = null
	_lingering.erase(self)


## True while there is a connection and it isn't closing.
func is_open() -> bool:
	return connection != null and _linger == 0


## [param peer]'s remote IP address; empty for an unknown peer.
func peer_address(peer: int) -> String:
	var enet_peer: ENetPacketPeer = _peers.get(peer)
	return enet_peer.get_remote_address() if enet_peer != null else ""


## [param peer]'s remote port; 0 for an unknown peer.
func peer_port(peer: int) -> int:
	var enet_peer: ENetPacketPeer = _peers.get(peer)
	return enet_peer.get_remote_port() if enet_peer != null else 0


## The fingerprint of the host certificate this client is pinned to ([method client]); empty
## when unpinned and on the host.
func pinned_fingerprint() -> PackedByteArray:
	return _pinned


## The port a host listens on (when bound to port 0: the one picked).
func local_port() -> int:
	return connection.get_local_port() if connection != null else 0
