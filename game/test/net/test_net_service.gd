extends "res://test/net/net_test_base.gd"
## Plan 35 work item 3: the service behind the online pages (MwNetService)
## on the loopback network - hosting, joining, the lobby with local players
## joining and leaving, refusals and what they say, trust on first use's
## question, host names resolved (every address tried in turn), UPnP (a
## stand-in gateway), the addresses to share, leaving, and the seam to the
## game (MwNetMatch's two calls).

const HOST := "10.0.0.1"

var net: MwNetLoopback
var services: Array[MwNetService] = []
var _id: MwNetIdentity
var calls := []


func before_each() -> void:
	super.before_each()
	net = MwNetLoopback.new(7)
	services.clear()
	calls.clear()
	_id = _identity(1)


func after_each() -> void:
	MwNetService.setup_new = Callable()


## A stand-in identity: certificate bytes only (the loopback hashes them).
func _identity(seed_value: int) -> MwNetIdentity:
	var id := MwNetIdentity.new()
	id.der = fake_cert(seed_value)
	id.fingerprint = MwNetIdentity.fingerprint_of(id.der)
	return id


func _host(password := "", id: MwNetIdentity = null) -> MwNetService:
	var service := MwNetService.new(MwSession.new(1, 1))
	var ident := id if id != null else _id
	var n := net
	service.info = net_info()
	service.use_upnp = false
	service.make_identity = func() -> MwNetIdentity: return ident
	service.make_host_transport = func(_p: int, i: MwNetIdentity) -> MwNetTransport:
		return n.listen(HOST, MwNetIdentity.fingerprint_of(i.der))
	service.local_addresses = func() -> PackedStringArray:
		return PackedStringArray(["127.0.0.1", "192.0.2.10", "2001:db8:0:0:0:0:0:10", "fe80:0:0:0:0:0:0:9"])
	service.start_host_with = func(se: MwSession, r: MwRouter, sv: MwNetService) -> void:
		calls.append(["host", se, r, sv])
	assert_true(service.host_game(MwNetProtocol.PORT, password), "hosting")
	services.append(service)
	return service


func _client(from: String, info := {}) -> MwNetService:
	var service := MwNetService.new(MwSession.new(2, 2))
	var n := net
	service.info = info if not info.is_empty() else net_info()
	service.connector = func(a: String, _p: int, pinned: PackedByteArray) -> MwNetTransport:
		return n.connect_to(a, from, MwNetIdentity.fingerprint_of(pinned) if not pinned.is_empty()
				else PackedByteArray())
	service.start_client_with = func(se: MwSession, r: MwRouter, sv: MwNetService, m: int, t: int,
			rec: PackedByteArray) -> void:
		calls.append(["client", se, r, sv, m, t, rec])
	service.start_rejoin_with = func(se: MwSession, r: MwRouter, sv: MwNetService) -> void:
		calls.append(["rejoin", se, r, sv])
	services.append(service)
	return service


func _run(ms: int) -> void:
	var end := net.now_ms + ms
	while net.now_ms < end:
		net.advance(10)
		for service in services:
			service.poll(net.now_ms)


func _run_until(done: Callable, limit_ms := 20000) -> bool:
	var end := net.now_ms + limit_ms
	while net.now_ms < end:
		if done.call():
			return true
		net.advance(10)
		for service in services:
			service.poll(net.now_ms)
	return done.call()


func test_a_client_joins_the_hosts_lobby() -> void:
	var h := _host()
	assert_eq(h.state, MwNetService.State.LOBBY)
	assert_true(h.is_host())
	assert_eq(h.number_of(1), 1, "the host's first player is P1")
	assert_eq(h.addresses(), PackedStringArray(["192.0.2.10:42032", "[2001:db8::10]:42032"]),
			"the LAN's to share: no loopback, no link-local")
	var c := _client("10.0.1.1")
	var rev := c.revision
	assert_true(c.join_game(HOST, ""))
	assert_eq(c.state, MwNetService.State.CONNECTING)
	assert_true(_run_until(func() -> bool: return c.state == MwNetService.State.LOBBY), "in the lobby")
	assert_gt(c.revision, rev, "the pages see it")
	assert_eq(c.number_of(1), 2, "the next number")
	assert_eq(c.my_machine(), 1)
	assert_eq(c.joined_address(), HOST)
	_run(200)
	assert_eq(str(h.lobby().numbers()), "[1, 2]")
	assert_eq(str(c.lobby().numbers()), "[1, 2]", "the client's copy")
	_run(3000)
	assert_gt(h.ping_of(1), -1, "the host measures the client")
	assert_gt(c.ping_of(0), -1, "the client its round trip to the host")
	assert_eq(h.ping_of(0), -1, "and nobody the host's own")


func test_local_players_join_with_a_press_and_leave_with_back() -> void:
	var h := _host()
	var c := _client("10.0.1.1")
	c.join_game(HOST, "")
	assert_true(_run_until(func() -> bool: return c.state == MwNetService.State.LOBBY))
	assert_true(h.join_local(2), "the host's second player")
	assert_eq(h.number_of(2), 3)
	assert_false(h.join_local(2), "once")
	assert_true(c.join_local(4), "the client's fourth player asks")
	assert_false(c.join_local(4), "a press while the host answers doesn't ask again")
	assert_true(_run_until(func() -> bool: return c.number_of(4) != 0))
	assert_eq(c.number_of(4), 4, "the lowest free number")
	_run(100)
	assert_eq(str(h.lobby().numbers()), "[1, 2, 3, 4]")
	assert_false(c.leave_local(1), "the first player's Back is EXIT LOBBY")
	assert_false(h.leave_local(1))
	assert_true(h.leave_local(2))
	assert_true(c.leave_local(4))
	assert_true(_run_until(func() -> bool: return c.number_of(4) == 0))
	_run(100)
	assert_eq(str(h.lobby().numbers()), "[1, 2]", "freed")
	assert_true(c.join_local(5), "a new press joins again")
	assert_true(_run_until(func() -> bool: return c.number_of(5) == 3), "the freed number goes to the next")


func test_refusals_say_why() -> void:
	var h := _host("Pw")
	var c := _client("10.0.1.1")
	c.join_game(HOST, "wrong")
	assert_true(_run_until(func() -> bool: return c.state == MwNetService.State.DONE))
	assert_eq(c.message, "WRONG PASSWORD - WAIT 1 S", "the wait the host gave")
	assert_eq(c.wait_left(), 1)
	_run(1100)
	assert_eq(c.wait_left(), 0)
	assert_eq(c.message, "WRONG PASSWORD", "counted down")
	var other := net_info()
	other["build"] = "another build"
	var wrong_build := _client("10.0.1.2", other)
	wrong_build.join_game(HOST, "pw")
	assert_true(_run_until(func() -> bool: return wrong_build.state == MwNetService.State.DONE))
	assert_eq(wrong_build.message, MwNetProtocol.REFUSAL_TEXT[MwNetProtocol.Refusal.VERSION])
	var wrong_rom_info := net_info()
	var zero := PackedByteArray()
	zero.resize(MwNetProtocol.SHA1_BYTES)
	wrong_rom_info["rom"] = zero
	var wrong_rom := _client("10.0.1.3", wrong_rom_info)
	wrong_rom.join_game(HOST, "pw")
	assert_true(_run_until(func() -> bool: return wrong_rom.state == MwNetService.State.DONE))
	assert_eq(wrong_rom.message, MwNetProtocol.REFUSAL_TEXT[MwNetProtocol.Refusal.ROM])
	for local in range(2, 13):
		h.join_local(local)
	assert_eq(h.lobby().free_slots(), 0)
	var service := _client("10.0.1.4")
	service.join_game(HOST, "pw")
	assert_true(_run_until(func() -> bool: return service.state == MwNetService.State.DONE))
	assert_eq(service.message, "THE LOBBY IS FULL")
	var bad := MwNetService.new()
	assert_false(bad.join_game("not an address!", ""))
	assert_eq(bad.message, "NOT AN ADDRESS")


func test_passwords_ignore_case() -> void:
	_host("Secret")
	var c := _client("10.0.1.1")
	c.join_game(HOST, "sECRET")
	assert_true(_run_until(func() -> bool: return c.state == MwNetService.State.LOBBY), "the same password")
	assert_eq(MwNetService.fold("aBc1!"), "ABC1!")


func test_a_running_match_turns_newcomers_away() -> void:
	var h := _host()
	h.host.start_match(PackedByteArray())
	_run(50)
	assert_eq(h.state, MwNetService.State.RUNNING)
	var c := _client("10.0.1.1")
	c.join_game(HOST, "")
	assert_true(_run_until(func() -> bool: return c.state == MwNetService.State.DONE))
	assert_eq(c.message, "A MATCH IS RUNNING")
	h.host.end_match()
	_run(50)
	assert_eq(h.state, MwNetService.State.LOBBY, "back to the lobby")


## A resolver that answers from a table after a few polls.
class FakeResolver:
	var table := {}
	var asked := []
	var forgotten := []
	var _polls := {}
	var _names := {}

	func start(name: String) -> int:
		asked.append(name)
		var id := asked.size()
		_names[id] = name
		_polls[id] = 0
		return id

	func status(id: int) -> int:
		_polls[id] += 1
		if _polls[id] < 3:
			return IP.RESOLVER_STATUS_WAITING
		return IP.RESOLVER_STATUS_DONE if table.has(_names[id]) else IP.RESOLVER_STATUS_ERROR

	func addresses(id: int) -> Array:
		return table.get(_names[id], [])

	func forget(id: int) -> void:
		forgotten.append(id)


func test_host_names_are_resolved_and_each_address_tried() -> void:
	_host()
	var c := _client("10.0.1.1")
	var res := FakeResolver.new()
	res.table = {"rink.example.org": ["2001:db8::99", "", "fe80::1%eth0", HOST]}
	c.resolver = res
	assert_true(c.join_game("Rink.Example.org:42032", ""))
	assert_eq(c.state, MwNetService.State.RESOLVING, "RESOLVING ...: the menus go on")
	assert_eq(res.asked, ["rink.example.org"])
	assert_true(_run_until(func() -> bool: return c.state == MwNetService.State.LOBBY, 40000),
			"nobody at the first address: the next one")
	assert_eq(c.joined_address(), HOST)
	assert_eq(res.forgotten, [1], "the resolver's item let go")
	var service := _client("10.0.1.2")
	service.resolver = res
	service.join_game("nowhere.example.org", "")
	assert_true(_run_until(func() -> bool: return service.state == MwNetService.State.DONE))
	assert_eq(service.message, MwNetService.NO_SUCH_HOST)


func test_a_changed_key_is_asked_about() -> void:
	var h := _host()
	var c := _client("10.0.1.1")
	c.join_game(HOST, "")
	assert_true(_run_until(func() -> bool: return c.state == MwNetService.State.LOBBY), "first use: trusted")
	c.leave()
	h.leave()
	_run(200)
	net = MwNetLoopback.new(8)                 # the host again, with another key
	services.clear()
	var other := _identity(2)
	_host("", other)
	var returning_client := _client("10.0.1.1")
	returning_client.join_game(HOST, "")
	assert_true(_run_until(func() -> bool: return returning_client.state == MwNetService.State.TRUST), \
			"THIS HOST'S KEY HAS CHANGED")
	assert_eq(returning_client.fingerprints, PackedStringArray([MwNetIdentity.readable(_id.fingerprint),
			MwNetIdentity.readable(other.fingerprint)]), "the old key and the new")
	returning_client.cancel()
	assert_eq(returning_client.state, MwNetService.State.DONE)
	assert_eq(returning_client.message, "", "the player chose")
	var service := _client("10.0.1.1")
	service.join_game(HOST, "")
	assert_true(_run_until(func() -> bool: return service.state == MwNetService.State.TRUST))
	service.trust_new_key()
	assert_true(_run_until(func() -> bool: return service.state == MwNetService.State.LOBBY), "trusted: in")
	assert_eq(MwNetKnownHosts.lookup(HOST, MwNetProtocol.PORT), other.der, "the new key remembered")


func test_start_game_and_start_reach_the_game() -> void:
	var h := _host()
	var c := _client("10.0.1.1")
	c.join_game(HOST, "")
	assert_true(_run_until(func() -> bool: return c.state == MwNetService.State.LOBBY))
	assert_false(c.start_game(), "only the host starts")
	assert_true(h.start_game())
	assert_eq(calls.size(), 1)
	assert_eq(calls[0][0], "host")
	assert_same(calls[0][1], h.session)
	assert_same(calls[0][3], h)
	var record := PackedByteArray([1, 2, 3, 4])
	var id := h.host.start_match(record)        # what work item 4's start_host does
	assert_true(_run_until(func() -> bool: return calls.size() == 2), "START reaches the client")
	assert_eq(calls[1][0], "client")
	assert_same(calls[1][1], c.session)
	assert_eq(calls[1].slice(4), [id, 0, record], "the match, its first tick, the start record")
	assert_eq(c.state, MwNetService.State.RUNNING)
	_run(50)
	assert_false(h.start_game(), "not while a match runs")


## Work item 6: a machine back in a running match with its key goes to
## the game's rejoin (its game comes with a snapshot) - the lobby page says
## REJOINING AT THE NEXT FACE OFF while its match waits.
func test_a_rejoin_into_a_running_match_waits_for_its_game() -> void:
	var h := _host()
	var c := _client("10.0.1.1")
	c.join_game(HOST, "")
	assert_true(_run_until(func() -> bool: return c.state == MwNetService.State.LOBBY))
	var id := h.host.start_match(PackedByteArray([1]))
	assert_true(_run_until(func() -> bool: return calls.size() == 1), "START")
	var key := c.client.rejoin_key()
	c.client.transport.disconnect_peer(MwNetTransport.HOST_PEER, true)    # the machine's connection drops
	assert_true(_run_until(func() -> bool: return c.state == MwNetService.State.DONE))
	assert_eq(MwNetService.rejoin_address(), HOST + ":42032", "REJOIN offered")
	var again := _client("10.0.1.1")
	assert_true(MwNetService.rejoin_matches(HOST))
	MwNetRejoin.save(HOST, MwNetProtocol.PORT, id, key)
	again.join_game(HOST, "")
	assert_true(_run_until(func() -> bool: return calls.size() == 2), "back in")
	assert_eq(calls[1][0], "rejoin", "the game's rejoin, not START")
	assert_same(calls[1][1], again.session)
	assert_same(calls[1][3], again)
	assert_eq(again.state, MwNetService.State.RUNNING)
	assert_eq(again.client.numbers, [2], "its old number")
	assert_false(again.rejoining(), "no router: no match")
	var node := Node.new()
	add_child_autofree(node)
	var fader := MwScreenFader.new()
	node.add_child(fader)
	again.router = MwRouter.new(node, fader)
	var waiting := MwNetMatch.new()
	waiting.phase = MwNetMatch.Phase.WAITING
	again.router.driver = waiting
	assert_true(again.rejoining(), "its match waits: REJOINING AT THE NEXT FACE OFF")
	waiting.phase = MwNetMatch.Phase.PLAYING
	assert_false(again.rejoining(), "until it plays")


func test_the_seam_to_work_item_4() -> void:
	var service := MwNetService.new()
	assert_eq(service.start_host_with.get_method(), "start_host")
	assert_eq(service.start_client_with.get_method(), "start_client")
	assert_eq(service.start_rejoin_with.get_method(), "start_rejoin", "work item 6's")
	assert_eq(service.start_host_with.get_object(), MwNetMatch, "work item 4's match")


func test_leaving_ends_it_for_the_right_machines() -> void:
	var h := _host()
	var c := _client("10.0.1.1")
	c.join_game(HOST, "")
	var kicked_client := _client("10.0.1.2")
	kicked_client.join_game(HOST, "")
	assert_true(_run_until(func() -> bool: return c.in_lobby() and kicked_client.in_lobby()))
	c.leave()
	assert_eq(c.state, MwNetService.State.DONE)
	assert_eq(c.message, "", "EXIT LOBBY: chosen")
	assert_true(_run_until(func() -> bool: return str(h.lobby().numbers()) == "[1, 3]"), "the host sees it")
	h.host.kick(2)
	assert_true(_run_until(func() -> bool: return kicked_client.state == MwNetService.State.DONE))
	assert_eq(kicked_client.message, "THE HOST KICKED YOU")
	var service := _client("10.0.1.3")
	service.join_game(HOST, "")
	assert_true(_run_until(func() -> bool: return service.in_lobby()))
	h.leave()
	assert_eq(h.state, MwNetService.State.DONE)
	assert_true(_run_until(func() -> bool: return service.state == MwNetService.State.DONE))
	assert_eq(service.message, "THE HOST CLOSED THE LOBBY")


func test_a_rejoin_key_offers_rejoin() -> void:
	assert_eq(MwNetService.rejoin_address(), "")
	var key := PackedByteArray()
	key.resize(MwNetProtocol.KEY_BYTES)
	MwNetRejoin.save("2001:db8::7", 42032, 9, key)
	assert_eq(MwNetService.rejoin_address(), "[2001:db8::7]:42032")
	assert_true(MwNetService.rejoin_matches("[2001:DB8::7]:42032"))
	assert_true(MwNetService.rejoin_matches("2001:db8::7"), "the default port")
	assert_false(MwNetService.rejoin_matches("[2001:db8::7]:42033"))
	assert_false(MwNetService.rejoin_matches("10.0.0.1"))


## A stand-in for Godot's UPNP (and its gateway).
class FakeGateway:
	extends RefCounted
	func is_valid_gateway() -> bool:
		return true


class FakeUpnp:
	extends RefCounted
	var works := true
	var mapped := []
	var deleted := []

	func discover(_timeout: int, _ttl: int, _filter: String) -> int:
		return UPNP.UPNP_RESULT_SUCCESS if works else UPNP.UPNP_RESULT_NO_DEVICES

	func get_gateway() -> Object:
		return FakeGateway.new() if works else null

	func add_port_mapping(p: int, _internal: int, _desc: String, _proto: String, _duration: int) -> int:
		mapped.append(p)
		return UPNP.UPNP_RESULT_SUCCESS

	func query_external_address() -> String:
		return "203.0.113.7"

	func delete_port_mapping(p: int, _proto: String) -> int:
		deleted.append(p)
		return UPNP.UPNP_RESULT_SUCCESS


## A host on the loopback whose UPnP is [param gw].
func _upnp_host(gw: FakeUpnp, addresses: PackedStringArray) -> MwNetService:
	MwNetService.setup_new = func(new_service: MwNetService) -> void:
		new_service.upnp.factory = func() -> Object: return gw
	var service := MwNetService.new(MwSession.new(1, 1))
	MwNetService.setup_new = Callable()
	var n := net
	var id := _id
	service.info = net_info()
	service.make_identity = func() -> MwNetIdentity: return id
	service.make_host_transport = func(_p: int, i: MwNetIdentity) -> MwNetTransport:
		return n.listen(HOST, MwNetIdentity.fingerprint_of(i.der))
	service.local_addresses = func() -> PackedStringArray: return addresses
	assert_true(service.host_game(42032, ""))
	return service


func _wait_upnp(service: MwNetService) -> void:
	var end := Time.get_ticks_msec() + 3000
	while service.upnp.state == MwNetUpnp.State.TRYING and Time.get_ticks_msec() < end:
		service.poll(net.now_ms)
		OS.delay_msec(2)


func test_upnp_opens_the_port_and_shares_the_public_address() -> void:
	var gw := FakeUpnp.new()
	var service := _upnp_host(gw, PackedStringArray(["192.0.2.10"]))
	assert_eq(service.upnp_text(), "OPENING PORT 42032 ...", "at START SERVER, on a thread")
	_wait_upnp(service)
	assert_eq(service.upnp.state, MwNetUpnp.State.OPEN)
	assert_eq(gw.mapped, [42032])
	assert_eq(service.upnp_text(), "PORT OPEN")
	assert_eq(service.addresses(), PackedStringArray(["203.0.113.7:42032", "192.0.2.10:42032"]), "the public one first")
	service.leave()
	var end := Time.get_ticks_msec() + 3000
	while not MwNetUpnp._closing.is_empty() and Time.get_ticks_msec() < end:
		MwNetService.background()
		OS.delay_msec(2)
	assert_eq(gw.deleted, [42032], "CLOSE LOBBY: the mapping goes")


func test_a_failed_upnp_is_shown_not_fatal() -> void:
	var gw := FakeUpnp.new()
	gw.works = false
	var service := _upnp_host(gw, PackedStringArray())
	_wait_upnp(service)
	assert_eq(service.upnp.state, MwNetUpnp.State.FAILED)
	assert_eq(service.upnp_text(), "OPEN PORT 42032 ON YOUR ROUTER")
	assert_eq(service.state, MwNetService.State.LOBBY, "the lobby goes on")
	assert_eq(service.addresses(), PackedStringArray())
	service.leave()
	MwNetService.background()
	assert_eq(gw.deleted, [], "nothing to remove")
	assert_true(MwNetUpnp._closing.is_empty())
