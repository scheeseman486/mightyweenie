class_name MwNetLoopback
extends RefCounted
## An in-process network for the net tests (plan 35 sections 1 and 7): a
## host and any number of clients in one process, on a virtual clock
## ([member now_ms], moved by [method advance]), with seeded loss, delay,
## jitter, duplication, reordering and outages - so every part of the net
## code is testable fast, repeatably, without sockets.
##
## Each endpoint ([method listen], [method connect_to]) is an
## [MwNetTransport]. Like ENet, channel 0 is reliable and ordered: a lost
## send is sent again a timeout later (an outage holds it back until it
## ends), and nothing overtakes it. Channels 1 and 2 are unreliable and
## unsequenced: lost, delayed by the delay plus up to the jitter (which
## reorders on its own), held back further with probability [member
## reorder], and doubled with probability [member duplicate]. Connecting
## and disconnecting travel like reliable messages.
##
## Encryption isn't simulated, but its one visible effect is: a host
## endpoint has a certificate fingerprint and a client may pin one
## (MwNetTransport.pinned_fingerprint); pinned to another, the connection
## fails as a DTLS handshake would. A test's man in the middle listens with
## a fingerprint of its own.

## A connection to an address nobody listens on fails after this.
const CONNECT_TIMEOUT_MS := 1000

var loss := 0.0
var delay_ms := 0
var jitter_ms := 0
var duplicate := 0.0
var reorder := 0.0
## Vector2i(start, end) in ms: nothing gets through in [start, end).
var outages: Array[Vector2i] = []
var now_ms := 0
var rng := RandomNumberGenerator.new()
var stats := {"sent": 0, "lost": 0, "duplicated": 0, "retried": 0, "delivered": 0}
var _listening := {}
var _flights: Array = []
var _seq := 0


func _init(seed_value := 1) -> void:
	rng.seed = seed_value


## Sets the link's conditions from a dictionary (any of loss, delay,
## jitter, duplicate, reorder, outages).
func set_conditions(d: Dictionary) -> void:
	loss = float(d.get("loss", loss))
	delay_ms = int(d.get("delay", delay_ms))
	jitter_ms = int(d.get("jitter", jitter_ms))
	duplicate = float(d.get("duplicate", duplicate))
	reorder = float(d.get("reorder", reorder))
	if d.has("outages"):
		outages.assign(d["outages"])


## Moves the clock on by [param ms].
func advance(ms: int) -> void:
	now_ms += ms


## True when nothing gets through at [param t].
func is_down(t: int) -> bool:
	for o in outages:
		if t >= o.x and t < o.y:
			return true
	return false


## A host endpoint at [param address] whose certificate has [param
## fingerprint].
func listen(address: String, fingerprint := PackedByteArray()) -> Endpoint:
	var ep := Endpoint.new(self, address)
	ep.fingerprint = fingerprint
	ep.listening = true
	_listening[address] = ep
	return ep


## A client endpoint at [param from_address] connecting to [param address],
## its encryption pinned to [param pinned] (empty: not pinned).
func connect_to(address: String, from_address: String, pinned := PackedByteArray()) -> Endpoint:
	var ep := Endpoint.new(self, from_address)
	ep.pinned = pinned
	var host: Endpoint = _listening.get(address)
	if host == null or not host.listening:
		_fly(now_ms + CONNECT_TIMEOUT_MS, ep, null, MwNetTransport.Kind.DISCONNECTED,
				MwNetTransport.HOST_PEER, -1, PackedByteArray(), true)
		return ep
	var t1 := _reliable_time(now_ms)
	var t2 := _reliable_time(t1)
	if not pinned.is_empty() and pinned != host.fingerprint:
		_fly(t2, ep, null, MwNetTransport.Kind.DISCONNECTED, MwNetTransport.HOST_PEER, -1,
				PackedByteArray(), true)
		return ep
	var link := Link.new()
	link.client = ep
	link.host = host
	link.host_peer = host._next_peer
	host._next_peer += 1
	ep._links[MwNetTransport.HOST_PEER] = link
	host._links[link.host_peer] = link
	link.last[host.get_instance_id()] = t1
	link.last[ep.get_instance_id()] = t2
	_fly(t1, host, link, MwNetTransport.Kind.CONNECTED, link.host_peer)
	_fly(t2, ep, link, MwNetTransport.Kind.CONNECTED, MwNetTransport.HOST_PEER)
	return ep


## Delivers everything due by now to its endpoint.
func deliver() -> void:
	if _flights.is_empty():
		return
	var due := []
	var keep := []
	for f in _flights:
		(due if int(f[0]) <= now_ms else keep).append(f)
	if due.is_empty():
		return
	_flights = keep
	due.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or a[0] == b[0] and a[1] < b[1])
	for f in due:
		var ep: Endpoint = f[2]
		var link: Link = f[3]
		var ev: Dictionary = f[4]
		var peer := int(ev["peer"])
		if link != null and ep._links.get(peer) != link:
			continue
		if ev["kind"] == MwNetTransport.Kind.DISCONNECTED and link != null:
			ep._links.erase(peer)
		if ev["kind"] == MwNetTransport.Kind.PACKET:
			stats["delivered"] += 1
		ep.events.append(ev)


func _latency() -> int:
	return delay_ms + (rng.randi_range(0, jitter_ms) if jitter_ms > 0 else 0)


func _lost(t: int) -> bool:
	return is_down(t) or (loss > 0.0 and rng.randf() < loss)


## When a reliable send at [param t] arrives: tried again a timeout later
## each time it is lost.
func _reliable_time(t: int) -> int:
	while _lost(t):
		stats["retried"] += 1
		t += 2 * (delay_ms + jitter_ms) + 40
	return t + _latency()


func _fly(at: int, ep: Endpoint, link: Link, kind: int, peer: int, channel := -1,
		data := PackedByteArray(), error := false) -> void:
	_seq += 1
	_flights.append([at, _seq, ep, link,
			{"kind": kind, "peer": peer, "channel": channel, "data": data, "error": error}])


func _send(from: Endpoint, link: Link, channel: int, data: PackedByteArray) -> void:
	stats["sent"] += 1
	var to := link.other(from)
	var peer := link.peer_at(to)
	if channel == MwNetProtocol.CH_RELIABLE:
		var key := to.get_instance_id()
		var reliable_at := maxi(_reliable_time(now_ms), int(link.last.get(key, 0)))
		link.last[key] = reliable_at
		_fly(reliable_at, to, link, MwNetTransport.Kind.PACKET, peer, channel, data.duplicate())
		return
	if _lost(now_ms):
		stats["lost"] += 1
		return
	var at := now_ms + _latency()
	if reorder > 0.0 and rng.randf() < reorder:
		at += rng.randi_range(1, delay_ms + jitter_ms + 20)
	_fly(at, to, link, MwNetTransport.Kind.PACKET, peer, channel, data.duplicate())
	if duplicate > 0.0 and rng.randf() < duplicate:
		stats["duplicated"] += 1
		_fly(now_ms + _latency(), to, link, MwNetTransport.Kind.PACKET, peer, channel, data.duplicate())


func _disconnect(from: Endpoint, link: Link, at_once: bool) -> void:
	var to := link.other(from)
	var key := to.get_instance_id()
	var at := now_ms + _latency() if at_once else maxi(_reliable_time(now_ms), int(link.last.get(key, 0)))
	link.last[key] = at
	from._links.erase(link.peer_at(from))
	_fly(at, to, link, MwNetTransport.Kind.DISCONNECTED, link.peer_at(to))
	from._fly_local(MwNetTransport.Kind.DISCONNECTED, link.peer_at(from))


## One connection between a client endpoint and a host endpoint.
class Link:
	var client: Endpoint
	var host: Endpoint
	var host_peer := 0
	## The latest reliable arrival time toward each endpoint (by instance id).
	var last := {}

	func other(ep: Endpoint) -> Endpoint:
		return host if ep == client else client

	## The peer number [param ep] knows the other end by.
	func peer_at(ep: Endpoint) -> int:
		return MwNetTransport.HOST_PEER if ep == client else host_peer


## One end: a listening host or a connecting client.
class Endpoint extends MwNetTransport:
	var net: MwNetLoopback
	var address := ""
	var fingerprint := PackedByteArray()
	var pinned := PackedByteArray()
	var listening := false
	var _links := {}
	var _next_peer := 1
	var _local: Array[Dictionary] = []

	func _init(loopback: MwNetLoopback, a: String) -> void:
		net = loopback
		address = a

	func poll() -> void:
		events.append_array(_local)
		_local.clear()
		net.deliver()

	func send(peer: int, channel: int, data: PackedByteArray) -> bool:
		var link: Link = _links.get(peer)
		if link == null or data.size() > MwNetProtocol.MAX_MESSAGE or channel < 0 \
				or channel >= MwNetProtocol.CHANNELS:
			return false
		net._send(self, link, channel, data)
		return true

	func disconnect_peer(peer: int, now := false) -> void:
		var link: Link = _links.get(peer)
		if link != null:
			net._disconnect(self, link, now)

	func close() -> void:
		for peer in _links.keys():
			disconnect_peer(peer)
		listening = false

	func abort() -> void:
		for peer in _links.keys():
			disconnect_peer(peer, true)
		listening = false

	func is_open() -> bool:
		return listening or not _links.is_empty()

	func peer_address(peer: int) -> String:
		var link: Link = _links.get(peer)
		return link.other(self).address if link != null else ""

	func pinned_fingerprint() -> PackedByteArray:
		return pinned

	func _fly_local(kind: int, peer: int) -> void:
		_local.append({"kind": kind, "peer": peer, "channel": -1, "data": PackedByteArray(), "error": false})
