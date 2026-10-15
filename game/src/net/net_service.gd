class_name MwNetService
extends RefCounted
## What the online pages (plan 35 section 2: 119-123, work item 3) work
## through: this machine's part of an online game, hosting or joining,
## from START SERVER / CONNECT TO SERVER until the lobby closes. Kept in
## the session ([member MwSession.net]) and polled every tick with the time
## ([method poll]: the Router autoload hands it the clock - net code reads
## none; tests run it on their own clock). Node-free.
##
## * **Hosting** ([method host_game]): the host's key and certificate
##   ([MwNetIdentity], made at the first START SERVER), ENet with DTLS on
##   the port ([MwNetEnet]: IPv4 and IPv6 on one socket), the lobby
##   ([MwNetHost]) with this machine's first player as P1; UPnP tried at
##   once ([MwNetUpnp], owner: automatic; a failure is shown, never fatal);
##   the addresses to share ([method addresses]: the public one UPnP found,
##   then the machine's LAN addresses - IPv4 and IPv6, no loopback or
##   link-local) for COPY ADDRESS.
## * **Joining** ([method join_game]): the address as the field reads it
##   ([MwNetAddress]: an address or a host name, an optional port); a host
##   name is resolved without blocking the menus (RESOLVING..., owner:
##   accepted and resolved) and every address it gives is tried in turn
##   while none answers; then [MwNetClient]: the certificate check (trust
##   on first use: a changed key is asked about first - plan 45: with a
##   password too - TRUST, [method trust_new_key] or [method cancel]), the
##   handshake (a refusal says why: [member message], [method
##   refusal_text]), the lobby. A rejoin key kept for the address goes
##   along as its proof (MwNetRejoin; REJOIN on the pages).
## * **The lobby:** this machine's other local players join with a press
##   and leave with their Back ([method join_local], [method leave_local]);
##   the machine's first player can't - their Back is [method leave], CLOSE
##   LOBBY / EXIT LOBBY. [member revision] moves whenever something the
##   pages show changed (players, machines, pings, UPnP, the state).
## * **The game** (work item 4, [MwNetMatch]): the host's START GAME calls
##   [code]MwNetMatch.start_host(session, router, service)[/code]
##   ([method start_game]); a client's START calls
##   [code]MwNetMatch.start_client(session, router, service, match_id,
##   first_tick, record)[/code]; a client back in a running match with its
##   key (work item 6) calls [code]MwNetMatch.start_rejoin(session, router,
##   service)[/code] - its game comes with the host's snapshot at the next
##   faceoff ([method rejoining]: the lobby page says so meanwhile).
##   [member router] is set by whoever polls the service (the Router
##   autoload; tests set it).
## * **Passwords ignore case** (MwTextField: the menu fonts have no lower
##   case and the field shows asterisks): both ends fold them to upper case
##   before deriving the key ([method fold]).
##
## Everything outside is a member tests replace: the host's transport, the
## client's connector, the resolver, the machine's addresses, the UPnP
## object, the identity, what HELLO claims ([member info]) and the two
## MwNetMatch calls; [member setup_new] runs on every new service (the
## pages make theirs) so tests can put their stand-ins in.

enum Role { NONE, HOST, CLIENT }
## IDLE (nothing yet), RESOLVING (a host name), CONNECTING (the
## certificate, DTLS, the handshake), TRUST (the key changed: asked), LOBBY,
## RUNNING (a match), DONE (over: [member message] says why, "" when this
## machine chose it).
enum State { IDLE, RESOLVING, CONNECTING, TRUST, LOBBY, RUNNING, DONE }
## The device kinds the lobby rows draw a glyph for (MwNetLobby's byte per
## player): the keyboard, a gamepad by family (MwGlyphs.family).
enum Device { KEYS, PAD, XB, PS, NS }
const DEVICE_FAMILIES := {"PAD": Device.PAD, "XB": Device.XB, "PS": Device.PS, "NS": Device.NS}

const NO_SUCH_HOST := "NO SUCH HOST"
const NO_IDENTITY := "CAN'T MAKE THE HOST'S KEY"
const PORT_TAKEN := "CAN'T OPEN PORT %d"
## A local player's join waits this long for the host's answer before
## another press asks again (ms).
const JOIN_AGAIN_MS := 1000

## Called with every new service (tests: their stand-ins).
static var setup_new: Callable = Callable()

var role := Role.NONE
var state := State.IDLE
## The session this service belongs to (the pages').
var session: MwSession
## The router running this machine's screens (set by whoever polls).
var router: MwRouter
var host: MwNetHost
var client: MwNetClient
var identity: MwNetIdentity
var upnp := MwNetUpnp.new()
## Try UPnP when hosting (owner: automatic; tests on the loopback don't).
var use_upnp := true
## The port hosted on or joined.
var port := MwNetProtocol.PORT
## What the pages show when it ended or was refused ("" nothing).
var message := ""
## TRUST: the old and new keys' fingerprints (MwNetIdentity.readable).
var fingerprints := PackedStringArray()
## Moves whenever something the pages show changed.
var revision := 0

## The host's transport on a port (default: ENet with DTLS, MwNetEnet).
var make_host_transport: Callable = func(p: int, id: MwNetIdentity) -> MwNetTransport:
	return MwNetEnet.host(p, id)
## The client's transports (MwNetClient.connector; invalid: its default).
var connector: Callable = Callable()
## Resolves host names: start(name) -> id, status(id) -> IP.ResolverStatus,
## addresses(id) -> Array, forget(id) ([Resolver]: the system's).
var resolver: Object = Resolver.new()
## The machine's own addresses (default: IP.get_local_addresses).
var local_addresses: Callable = func() -> PackedStringArray: return IP.get_local_addresses()
## The host's key and certificate (default: MwNetIdentity.load_or_create).
var make_identity: Callable = func() -> MwNetIdentity: return MwNetIdentity.load_or_create()
## What HELLO claims and the host checks ({}: this build's,
## MwNetHost.local_info).
var info := {}
var start_host_with: Callable = Callable(MwNetMatch, "start_host")
var start_client_with: Callable = Callable(MwNetMatch, "start_client")
var start_rejoin_with: Callable = Callable(MwNetMatch, "start_rejoin")

var _now := 0
var _password := ""
var _candidates := PackedStringArray()
var _resolving := -1
var _addresses := PackedStringArray()
var _refused_at := 0
var _shown_wait := -1
var _join_asked := {}
var _rtt := -1
var _pings := 0


## The system's resolver (IP's queue: it never blocks).
class Resolver:
	func start(name: String) -> int:
		return IP.resolve_hostname_queue_item(name, IP.TYPE_ANY)

	func status(id: int) -> int:
		return IP.get_resolve_item_status(id)

	func addresses(id: int) -> Array:
		return IP.get_resolve_item_addresses(id)

	func forget(id: int) -> void:
		IP.erase_resolve_item(id)


func _init(for_session: MwSession = null) -> void:
	session = for_session
	if setup_new.is_valid():
		setup_new.call(self)


## Services what ended services leave behind (ENet's graceful closes,
## UPnP mappings being removed): the Router autoload, every tick.
static func background() -> void:
	MwNetEnet.service_lingering()
	MwNetUpnp.service()


## A password as both ends use it: upper case (see the class notes).
static func fold(password: String) -> String:
	return password.to_upper()


# --- hosting --------------------------------------------------------------------------------------

## START SERVER: hosts on [param on_port] with [param password] ("" none).
## False when it couldn't ([member message] says why).
func host_game(on_port: int, password: String) -> bool:
	if role != Role.NONE:
		return false
	identity = make_identity.call()
	if identity == null:
		return _end(NO_IDENTITY)
	var transport: MwNetTransport = make_host_transport.call(on_port, identity)
	if transport == null or (transport is MwNetEnet and (transport as MwNetEnet).error != OK):
		return _end(PORT_TAKEN % on_port)
	port = on_port
	if transport is MwNetEnet and (transport as MwNetEnet).local_port() > 0:
		port = (transport as MwNetEnet).local_port()       # the port really bound
	host = MwNetHost.new(transport, identity.der, fold(password), info)
	host.open(device_of(1))
	host.lobby.changed.connect(_bump)
	role = Role.HOST
	_set_state(State.LOBBY)
	if use_upnp:
		upnp.open(port)
	_list_addresses()
	return true


## The addresses to share, each with the port as JOIN GAME reads it: the
## public one (UPnP's), then the LAN's - IPv4, then IPv6.
func addresses() -> PackedStringArray:
	return _addresses


func _list_addresses() -> void:
	var all := PackedStringArray()
	if upnp.external != "":
		all.append(upnp.external)
	all.append_array(local_addresses.call())
	_addresses.clear()
	for a in MwNetAddress.shareable(all):
		_addresses.append(MwNetAddress.join(a, port))
	_bump()


## The UPnP line of the host's lobby ("" none).
func upnp_text() -> String:
	if role != Role.HOST or not use_upnp:
		return ""
	match upnp.state:
		MwNetUpnp.State.TRYING:
			return "OPENING PORT %d ..." % port
		MwNetUpnp.State.OPEN:
			return "PORT OPEN"
		MwNetUpnp.State.FAILED:
			return "OPEN PORT %d ON YOUR ROUTER" % port
	return ""


## START GAME (the host's first player): the match begins (work item 4,
## MwNetMatch.start_host). False when this isn't an open lobby's host.
func start_game() -> bool:
	if role != Role.HOST or state != State.LOBBY or host.lobby.state != MwNetLobby.State.OPEN:
		return false
	start_host_with.call(session, router, self)
	return true


# --- joining --------------------------------------------------------------------------------------

## CONNECT TO SERVER: joins [param address_text] (as MwNetAddress reads it)
## with [param password]. False when it can't start ([member message]).
func join_game(address_text: String, password: String) -> bool:
	if role != Role.NONE:
		return false
	var a := MwNetAddress.parse(address_text)
	if a.is_empty():
		return _end(MwTextField.NOT_TEXT[MwTextField.Kind.ADDRESS])
	role = Role.CLIENT
	port = int(a["port"])
	_password = fold(password)
	message = ""
	if int(a["kind"]) == MwNetAddress.Kind.NAME:
		_resolving = int(resolver.call("start", str(a["host"])))
		if _resolving < 0:
			return _end(NO_SUCH_HOST)
		_set_state(State.RESOLVING)
		return true
	_candidates = PackedStringArray([str(a["host"])])
	_try_next()
	return true


func _try_next() -> void:
	if _candidates.is_empty():
		return
	var address := _candidates[0]
	_candidates.remove_at(0)
	client = MwNetClient.new()
	if not info.is_empty():
		client.info = info
	if connector.is_valid():
		client.connector = connector
	client.state_changed.connect(_on_client_state)
	client.key_changed.connect(_on_key_changed)
	client.failed.connect(_on_client_failed)
	client.started.connect(_on_started)
	client.rejoined.connect(_on_rejoined)
	client.lobby.changed.connect(_bump)
	_rtt = -1
	_set_state(State.CONNECTING)
	client.connect_to(address, port, _password, 1)


## The address this client is joining or joined ("" none).
func joined_address() -> String:
	return client.address if client != null else ""


## TRUST: goes on with the host's new key.
func trust_new_key() -> void:
	if state == State.TRUST and client != null:
		fingerprints = PackedStringArray()
		_set_state(State.CONNECTING)
		client.trust_new_key()


## Stops joining (Back on JOIN GAME): resolving, connecting or asked.
func cancel() -> void:
	if role != Role.CLIENT or not state in [State.RESOLVING, State.CONNECTING, State.TRUST]:
		return
	_forget_resolve()
	_candidates.clear()
	if client != null:
		client.cancel()
	_end("")


func _on_client_state(client_state: int) -> void:
	match client_state:
		MwNetClient.State.FETCHING, MwNetClient.State.CONNECTING, MwNetClient.State.HANDSHAKE:
			_set_state(State.CONNECTING)
		MwNetClient.State.TRUST:
			_set_state(State.TRUST)
		MwNetClient.State.LOBBY:
			_set_state(State.LOBBY)
		MwNetClient.State.RUNNING:
			_set_state(State.RUNNING)


func _on_key_changed(old_fp: PackedByteArray, new_fp: PackedByteArray) -> void:
	fingerprints = PackedStringArray([MwNetIdentity.readable(old_fp), MwNetIdentity.readable(new_fp)])
	_bump()


func _on_client_failed(reason: int) -> void:
	if reason == MwNetClient.Fail.NO_ANSWER and not _candidates.is_empty():
		_try_next()                          # the host name's next address
		return
	match reason:
		MwNetClient.Fail.CANCELLED, MwNetClient.Fail.EXITED:
			_end("")
		MwNetClient.Fail.REFUSED:
			_refused_at = _now
			_shown_wait = wait_left()
			_end(refusal_text(client.refusal, _shown_wait))
		_:
			_end(str(MwNetClient.FAIL_TEXT.get(reason, MwNetClient.FAIL_TEXT[MwNetClient.Fail.LOST])))


func _on_started(match_id: int, first_tick: int, record: PackedByteArray) -> void:
	start_client_with.call(session, router, self, match_id, first_tick, record)


## Work item 6: in again with the key while the match runs - the game waits
## for the host's snapshot.
func _on_rejoined(_match_id: int, _first_tick: int) -> void:
	start_rejoin_with.call(session, router, self)
	_bump()


## Work item 6: true while this machine, back in a running match, waits
## for the snapshot its game comes with (the lobby page: REJOINING AT THE
## NEXT FACE OFF).
func rejoining() -> bool:
	return router != null and router.driver is MwNetMatch \
			and (router.driver as MwNetMatch).phase == MwNetMatch.Phase.WAITING


## A refusal's text ([constant MwNetProtocol.REFUSAL_TEXT]) with [param
## wait_s] seconds left of its wait: a wrong password's (WRONG PASSWORD -
## WAIT 2 S), too many tries'.
static func refusal_text(code: int, wait_s: int) -> String:
	var text := str(MwNetProtocol.REFUSAL_TEXT.get(code, "REFUSED"))
	if code == MwNetProtocol.Refusal.WAIT:
		return text % maxi(wait_s, 1)
	if code == MwNetProtocol.Refusal.WRONG_PASSWORD and wait_s > 0:
		return "%s - WAIT %d S" % [text, wait_s]
	return text


## Seconds left of the wait a refusal gave (0 none).
func wait_left() -> int:
	if client == null or client.fail != MwNetClient.Fail.REFUSED or client.refusal_wait <= 0:
		return 0
	return maxi(0, ceili((_refused_at + client.refusal_wait * 1000 - _now) / 1000.0))


## True when [param address_text] leads where the rejoin key kept on this
## machine is for (JOIN GAME offers REJOIN).
static func rejoin_matches(address_text: String) -> bool:
	var a := MwNetAddress.parse(address_text)
	if a.is_empty() or int(a["kind"]) == MwNetAddress.Kind.NAME:
		return false
	return not MwNetRejoin.key_for(str(a["host"]), int(a["port"])).is_empty()


## The kept rejoin key's address as the field takes it ("" none).
static func rejoin_address() -> String:
	var r := MwNetRejoin.read()
	if r.is_empty():
		return ""
	return MwNetAddress.join(str(r["address"]), int(r["port"]))


# --- the lobby ------------------------------------------------------------------------------------

## The lobby this machine is in: the host's or the client's (null with neither).
func lobby() -> MwNetLobby:
	if host != null:
		return host.lobby
	if client != null:
		return client.lobby
	return null


## This machine's id in the lobby (the host's 0; -1 none yet).
func my_machine() -> int:
	if role == Role.HOST:
		return MwNetLobby.HOST_MACHINE
	return client.machine if client != null else -1


## Whether this machine hosts the game (its role is the host's).
func is_host() -> bool:
	return role == Role.HOST


## True in the lobby or a match.
func in_lobby() -> bool:
	return state == State.LOBBY or state == State.RUNNING


## The player number of this machine's local player [param local] (0: not in).
func number_of(local: int) -> int:
	var net_lobby := lobby()
	return net_lobby.player_of(my_machine(), local) if net_lobby != null and my_machine() >= 0 else 0


## This machine's local player [param local] (their bindings: player
## [param local]'s) joins with a press. True when asked (a client: the
## host's LOBBY brings the number) or done (the host).
func join_local(local: int) -> bool:
	if state != State.LOBBY or local < 2 or local > MwNetLobby.MAX_PLAYERS or number_of(local) != 0:
		return false
	var device := device_of(local)
	if role == Role.HOST:
		return host.join_local(local, device) != 0
	if _join_asked.has(local) and _now - int(_join_asked[local]) < JOIN_AGAIN_MS:
		return false
	_join_asked[local] = _now
	client.join_local(local, device)
	return true


## Local player [param local] leaves with their Back (not the machine's
## first: theirs is [method leave]).
func leave_local(local: int) -> bool:
	var n := number_of(local)
	if state != State.LOBBY or local == 1 or n == 0:
		return false
	_join_asked.erase(local)
	if role == Role.HOST:
		return host.leave_local(n)
	client.leave_local(n)
	return true


## A machine's ping for its lobby row (ms; -1 none): the host's measure of
## each client; a client's own round trip for the host.
func ping_of(machine: int) -> int:
	var net_lobby := lobby()
	if net_lobby == null or not net_lobby.machines.has(machine):
		return -1
	if role == Role.CLIENT and machine == MwNetLobby.HOST_MACHINE:
		return client.rtt_ms if client != null and client.rtt_ms > 0 else -1
	var p := int(net_lobby.machines[machine]["ping"])
	return p if p > 0 else -1


## CLOSE LOBBY (the host: every machine told, the port's mapping removed)
## or EXIT LOBBY (a client); also stops joining.
func leave() -> void:
	match role:
		Role.HOST:
			if host != null and state != State.DONE:
				host.close()
			upnp.close()
			_end("")
		Role.CLIENT:
			_forget_resolve()
			_candidates.clear()
			if client != null and client.state != MwNetClient.State.DONE:
				if client.state == MwNetClient.State.LOBBY or client.state == MwNetClient.State.RUNNING:
					client.exit_lobby()
				else:
					client.cancel()
			_end("")


## Player [param local]'s device kind ([enum Device]): their gamepad's
## family when it is there, else the keyboard when they have it.
static func device_of(local: int) -> int:
	var d := MwInputMap.pad_device(local)
	if d in Input.get_connected_joypads():
		return DEVICE_FAMILIES.get(MwGlyphs.family(d), Device.PAD)
	return Device.KEYS if MwInputMap.uses_keyboard(local) else Device.PAD


## Device kind [param kind] ([enum Device]) as a gamepad family
## (MwGlyphs.family): "" the keyboard.
static func device_family(kind: int) -> String:
	if kind == Device.KEYS:
		return ""
	for f in DEVICE_FAMILIES:
		if DEVICE_FAMILIES[f] == kind:
			return f
	return "PAD"


# --- polling --------------------------------------------------------------------------------------

## Handles everything that arrived, at time [param now_ms].
func poll(now_ms: int) -> void:
	_now = now_ms
	match role:
		Role.HOST:
			if host != null and state != State.DONE:
				host.poll(now_ms)
				var new_state := State.RUNNING if host.lobby.state == MwNetLobby.State.RUNNING else State.LOBBY
				if new_state != state:
					_set_state(new_state)
				var pings := 0
				for id in host.lobby.machines:
					pings = (pings * 31 + int(host.lobby.machines[id]["ping"])) & 0x7FFFFFFF
				if pings != _pings:             # the lobby's pings moved (no signal of their own)
					_pings = pings
					_bump()
			if upnp.poll():
				_list_addresses()
		Role.CLIENT:
			if state == State.RESOLVING:
				_poll_resolve()
			if client != null:
				client.poll(now_ms)
				if client.rtt_ms != _rtt and in_lobby():
					_rtt = client.rtt_ms
					_bump()
			if state == State.DONE and client != null and client.fail == MwNetClient.Fail.REFUSED:
				var left := wait_left()
				if left != _shown_wait:
					_shown_wait = left
					message = refusal_text(client.refusal, left)
					_bump()


func _poll_resolve() -> void:
	var st := int(resolver.call("status", _resolving))
	if st == IP.RESOLVER_STATUS_WAITING:
		return
	var found := PackedStringArray()
	if st == IP.RESOLVER_STATUS_DONE:
		for a in resolver.call("addresses", _resolving):
			var text := str(a)
			if text.is_valid_ip_address() and not "%" in text and not text in found:
				found.append(text)
	_forget_resolve()
	if found.is_empty():
		_end(NO_SUCH_HOST)
		return
	_candidates = found
	_try_next()


func _forget_resolve() -> void:
	if _resolving >= 0:
		resolver.call("forget", _resolving)
		_resolving = -1


func _set_state(new_state: int) -> void:
	if state != new_state:
		state = new_state
		_bump()


func _end(why: String) -> bool:
	message = why
	_set_state(State.DONE)
	_bump()
	return false


func _bump() -> void:
	revision += 1
