class_name MwNetTransport
extends RefCounted
## What the net sessions ([MwNetHost], [MwNetClient]) send through (plan 35
## section 1): connections to numbered peers, three channels (0 reliable
## and ordered, 1 and 2 unreliable: [constant MwNetProtocol.CH_RELIABLE]
## ...), whole messages of at most [constant MwNetProtocol.MAX_MESSAGE]
## bytes. Polled, never blocking, node-free. Two implementations: ENet with
## DTLS for real ([MwNetEnet]) and an in-process loopback with seeded loss,
## delay, jitter, duplication, reordering and outages for tests
## ([MwNetLoopback]).
##
## [method poll] gathers what happened into [member events], each a
## dictionary {kind ([enum Kind]), peer, channel, data, error}. A client's
## transport has one peer, the host, numbered [constant HOST_PEER].

enum Kind { CONNECTED, DISCONNECTED, PACKET }
const HOST_PEER := 1

var events: Array[Dictionary] = []


## Moves pending traffic and fills [member events].
func poll() -> void:
	pass


## The events since the last call (and clears them).
func take_events() -> Array[Dictionary]:
	var taken := events
	events = []
	return taken


## Sends [param data] to [param peer] on [param channel]; false when it
## can't (no such peer, too big, closed).
func send(_peer: int, _channel: int, _data: PackedByteArray) -> bool:
	return false


## Sends what is waiting now rather than at the next [method poll] (the
## host after each machine's share of a tick, MwNetHost.step).
func flush() -> void:
	pass


## Ends [param peer]'s connection, after what was sent to it ([param now]:
## at once, dropping it).
func disconnect_peer(_peer: int, _now := false) -> void:
	pass


## Ends every connection and stops, gracefully: what was sent still goes
## out first.
func close() -> void:
	pass


## Ends every connection and stops at once (nothing more needs to arrive:
## a certificate fetched, a refusal received).
func abort() -> void:
	close()


## Whether the transport is up: listening or connected, and not closing.
func is_open() -> bool:
	return false


## [param peer]'s address (an IP address, no port).
func peer_address(_peer: int) -> String:
	return ""


## [param _peer]'s port (0: no such peer).
func peer_port(_peer: int) -> int:
	return 0


## A client's: the fingerprint (SHA-256 of the DER) of the host certificate
## its encryption is pinned to - what the handshake's proofs bind to
## (MwNetProtocol.proof). Empty when not pinned (a first contact, which only
## fetches the certificate) and on the host.
func pinned_fingerprint() -> PackedByteArray:
	return PackedByteArray()


func _event(kind: int, peer: int, channel := -1, data := PackedByteArray(), error := false) -> void:
	events.append({"kind": kind, "peer": peer, "channel": channel, "data": data, "error": error})
