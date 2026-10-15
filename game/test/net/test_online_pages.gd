extends "res://test/net/net_test_base.gd"
## Plan 35 work item 3: the online pages (119-122, MwOnlineMenu) and the
## on-screen keyboard (123, MwKeyboardScreen: their text input screen)
## through the router: every page and Back, the text fields (typed on 123,
## the paste checks), the keyboard's pads;
## then machines through the pages: a host and a client into one lobby on
## real sockets (ENet with DTLS, 127.0.0.1 and ::1), a local player
## joining and leaving with a press, START GAME reaching the game's two
## calls (MwNetMatch), leaving; refusals and a changed key shown on JOIN
## GAME (the loopback network). Settings go to a test file; the clipboard,
## UPnP and the host's identity are stand-ins.

## Test input: the actions held now (the router turns them into presses).
const Pad := preload("res://test/support/pad.gd")
const RouterService := preload("res://src/flow/router_service.gd")


## One machine: a router, its pad, its session (and service).
class Machine:
	var host: Node
	var router: MwRouter
	var pad := Pad.new()

	func menu() -> MwScreen:
		return router.current()

	func net() -> MwNetService:
		return router.session.net


const HOST := "10.0.0.1"

var machines: Array[Machine] = []
## The services keep the game's own MwNetMatch calls (the end-to-end test).
var real_match := false
var calls := []
var _clip := ""
var _kept := {}
var _id: MwNetIdentity
## The loopback network (the refusal and key tests; null on real sockets)
## and the bare host on it.
var loop: MwNetLoopback
var _loop_host: MwNetHost


func before_all() -> void:
	super.before_all()
	_kept = {"path": MwSettings.path, "port": MwSettings.net_port, "address": MwSettings.net_address,
			"device": MwGlyphs.last_device, "get": MwTextField.clipboard_get, "set": MwTextField.clipboard_set}
	MwSettings.path = "user://test_online_pages_%d.cfg" % Time.get_ticks_usec()
	_id = MwNetIdentity.create()


func after_all() -> void:
	if FileAccess.file_exists(MwSettings.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.path = _kept["path"]
	MwSettings.net_port = _kept["port"]
	MwSettings.net_address = _kept["address"]
	MwGlyphs.last_device = _kept["device"]
	MwTextField.clipboard_get = _kept["get"]
	MwTextField.clipboard_set = _kept["set"]
	MwNetService.setup_new = Callable()
	super.after_all()


func before_each() -> void:
	super.before_each()
	MwSettings.net_port = MwNetProtocol.PORT
	MwSettings.net_address = ""
	MwGlyphs.last_device = -1                 # the keyboard used last
	MwTextField.clipboard_get = func() -> String: return _clip
	MwTextField.clipboard_set = func(copied: String) -> void: _clip = copied
	calls.clear()
	real_match = false
	loop = null
	_loop_host = null
	var id := _id
	MwNetService.setup_new = func(service: MwNetService) -> void:
		service.make_identity = func() -> MwNetIdentity: return id
		service.use_upnp = false
		service.make_host_transport = func(_p: int, i: MwNetIdentity) -> MwNetTransport:
			return MwNetEnet.host(0, i)               # any free port: test runs side by side
		service.local_addresses = func() -> PackedStringArray:
			return PackedStringArray(["127.0.0.1", "192.0.2.10", "fe80:0:0:0:0:0:0:9"])
		if real_match:
			return                                 # the game's own calls (work item 4)
		service.start_host_with = func(se: MwSession, r: MwRouter, sv: MwNetService) -> void:
			calls.append(["host", se, r, sv])
		service.start_client_with = func(se: MwSession, r: MwRouter, sv: MwNetService, m: int, t: int,
				rec: PackedByteArray) -> void:
			calls.append(["client", se, r, sv, m, t, rec])
		if loop != null:
			_on_loopback(service)


func after_each() -> void:
	for m in machines:
		if m.router.session.net != null:
			m.router.session.net.leave()
		m.host.free()
	machines.clear()
	var end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end and not MwNetEnet._lingering.is_empty():
		MwNetService.background()
		OS.delay_msec(2)
	_handle_dtls_errors()


## The engine's log of a disconnect's straggling packets reaching the host's
## DTLS server as a new handshake (MwNetEnet: harmless), not failures.
func _handle_dtls_errors() -> void:
	for e in get_errors():
		if e.contains_text("TLS handshake") or e.contains_text("mbedtls"):
			e.handled = true


## A machine with screen [param id] adopted (uncovered).
func _machine(id: int, data := {}) -> Machine:
	var m := Machine.new()
	m.host = Node.new()
	add_child(m.host)
	var fader := MwScreenFader.new()
	m.host.add_child(fader)
	m.router = MwRouter.new(m.host, fader)
	m.router.session = MwSession.new(1 + machines.size(), 1)
	m.router.input = m.pad
	var scene := MwRouter.instantiate_scene(id)
	scene.screen_id = id
	m.router.adopt(scene, data)
	fader.uncover()
	machines.append(m)
	return m


## One tick everywhere: each service polled (the Router autoload's work:
## real time on real sockets; on the loopback its clock moves 16 ms a
## tick), then each router.
func _tick() -> void:
	var now := Time.get_ticks_msec()
	if loop != null:
		loop.advance(16)
		now = loop.now_ms
		if _loop_host != null:
			_loop_host.poll(now)
	for m in machines:
		var service := m.router.session.net
		if service != null:
			service.router = m.router
			service.poll(now)
	MwNetService.background()
	for m in machines:
		if m.router.driver != null:            # an online match runs the ticks (the Router autoload's way)
			if not m.router.driver.call("frame", now):
				m.router.driver = null
		else:
			m.router.step()


func _run(ticks: int) -> void:
	for i in ticks:
		_tick()


## Runs until [param done] (on real sockets in real time: up to [param limit_ms]).
func _until(done: Callable, limit_ms := 15000) -> bool:
	var end := Time.get_ticks_msec() + limit_ms
	while Time.get_ticks_msec() < end:
		if done.call():
			return true
		_tick()
		if loop == null:
			OS.delay_msec(1)
	return done.call()


func _on(m: Machine, id: int) -> bool:
	return _until(func() -> bool: return m.router.current_id() == id and not m.router.busy())


func _press(m: Machine, action: String, after := 10) -> void:
	m.pad.held = {action: true}
	_run(3)
	m.pad.held = {}
	_run(after)


func _key(code: int, unicode := 0) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode
	event.pressed = true
	return event


## Types [param text] on the text input screen a field's accept pushed (123)
## after clearing its text, then Enter: back on the page.
func _type(m: Machine, text: String) -> void:
	assert_true(_on(m, MwScreens.KEYBOARD), "the field's text input screen (123)")
	var kb := m.menu() as MwKeyboardScreen
	var page: int = m.router.stack[-2].screen_id
	for i in 300:
		kb.key(_key(KEY_BACKSPACE))
	for i in text.length():
		kb.key(_key(KEY_NONE, text.unicode_at(i)))
	kb.key(_key(KEY_ENTER))
	assert_true(_on(m, page), "Enter: back on the page")


## Selects the row of [param action] (Down until it is).
func _select(m: Machine, action: String) -> void:
	for i in 6:
		var port_menu := m.menu() as MwPortMenu
		if port_menu.rows[port_menu.row].get("action", "") == action:
			return
		_press(m, "p1_ui_down" if port_menu.page == "lobby" else "ui_down")
	fail_test("no row " + action)


func _accept(m: Machine) -> void:
	_press(m, "p1_ui_accept" if (m.menu() as MwPortMenu).page == "lobby" else "ui_accept")


# --- the pages ------------------------------------------------------------------------------------

func test_the_screens_table() -> void:
	var ids := [MwScreens.ONLINE, MwScreens.HOST_GAME, MwScreens.JOIN_GAME, MwScreens.LOBBY]
	assert_eq(ids, [119, 120, 121, 122])
	assert_eq(ids.map(func(id: int) -> String: return MwScreens.entry(id)), ["online", "host", "join", "lobby"])
	for id in ids:
		assert_eq(MwScreens.info(id).scene, "online")
	assert_eq(MwScreens.KEYBOARD, 123)
	assert_eq(MwScreens.info(123).scene, "keyboard")
	assert_eq(MwScreens.contexts(123), [MwVerbs.Context.PASSWORD], "the password screen's verbs")
	assert_true(MwScreens.ONLINE in MwScreens.exits(MwScreens.PLAY_MODE))
	for pair in [[119, 120], [119, 121], [119, 106], [120, 119], [120, 122], [121, 119], [121, 122],
			[122, 120], [122, 121], [122, 119]]:
		assert_true(pair[1] in MwScreens.exits(pair[0]), "%d -> %d" % pair)


func test_every_page_and_back() -> void:
	if not need_rom():
		return
	var m := _machine(MwScreens.PLAY_MODE)
	_run(10)
	_select(m, "online")
	assert_false((m.menu() as MwPortMenu).rows[1].get("disabled", false), "ONLINE MULTIPLAYER is there")
	_accept(m)
	assert_true(_on(m, MwScreens.ONLINE))
	var page := m.menu() as MwOnlineMenu
	assert_eq(page.rows.map(func(r): return r.action), ["host", "join"])
	assert_eq(page.page_title(), "ONLINE MULTIPLAYER")
	_accept(m)
	assert_true(_on(m, MwScreens.HOST_GAME))
	page = m.menu()
	assert_eq(page.rows.map(func(r): return r.label), ["PORT", "PASSWORD", "START SERVER"])
	assert_eq(page.port_field.text, "42032", "the default port")
	_press(m, "ui_back")
	assert_true(_on(m, MwScreens.ONLINE), "120 -> 119")
	_press(m, "ui_down")
	_accept(m)
	assert_true(_on(m, MwScreens.JOIN_GAME))
	page = m.menu()
	assert_eq(page.rows.map(func(r): return r.label), ["IP ADDRESS", "PASSWORD", "CONNECT TO SERVER"])
	_press(m, "ui_back")
	assert_true(_on(m, MwScreens.ONLINE), "121 -> 119")
	_press(m, "ui_back")
	assert_true(_on(m, MwScreens.PLAY_MODE), "119 -> 106")
	var lobby := _machine(MwScreens.LOBBY)
	assert_true(_on(lobby, MwScreens.ONLINE), "a lobby without a service: back to 119")


func test_typing_into_the_fields() -> void:
	if not need_rom():
		return
	var m := _machine(MwScreens.HOST_GAME)
	_run(10)
	var host_page := m.menu() as MwOnlineMenu
	_accept(m)
	assert_true(_on(m, MwScreens.KEYBOARD), "the keyboard used last: still the text input screen")
	var kb := m.menu() as MwKeyboardScreen
	assert_same(kb.field, host_page.port_field)
	assert_true(kb.field.editing, "typed at once")
	_type(m, "5000")
	assert_false(host_page.port_field.editing)
	assert_eq(host_page.port_field.text, "5000")
	assert_eq(MwSettings.net_port, 5000, "remembered")
	_run(10)
	_accept(m)
	_type(m, "99999")
	assert_eq(host_page.lines[0], ["NOT A PORT", true], "in red")
	assert_eq(host_page.port_field.text, "5000", "back to the last good one")
	_run(10)
	_accept(m)
	_type(m, "80")
	assert_eq(host_page.lines[0], [MwOnlineMenu.LOW_PORT, false], "under 1024 warns")
	_run(10)
	_accept(m)
	assert_true(_on(m, MwScreens.KEYBOARD))
	kb = m.menu() as MwKeyboardScreen
	kb.key(_key(KEY_1, 0x31))
	kb.key(_key(KEY_ESCAPE))
	assert_true(_on(m, MwScreens.HOST_GAME))
	assert_eq(host_page.port_field.text, "80", "Esc: as it was")
	_run(10)
	_press(m, "ui_down")
	_accept(m)
	_type(m, "Hunter2")
	assert_eq(host_page.password_field.text, "Hunter2")
	assert_eq(host_page.password_field.shown(), "*******")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(MwSettings.path), OK)
	assert_eq(cfg.get_value("net", "port"), 80)
	assert_false("Hunter2" in cfg.encode_to_text(), "passwords are never saved")
	var machine := _machine(MwScreens.JOIN_GAME)
	_run(10)
	var join_page := machine.menu() as MwOnlineMenu
	_accept(machine)
	_type(machine, "[::1]:4000")
	assert_eq(join_page.address_field.text, "[::1]:4000")
	assert_eq(MwSettings.net_address, "[::1]:4000")
	_run(10)
	_accept(machine)
	_type(machine, "nope..x")
	assert_eq(join_page.lines[0], ["NOT AN ADDRESS", true])
	_clip = "  10.1.2.3:42032 \n"
	join_page.paste_into(join_page.address_field)
	assert_eq(join_page.address_field.text, "10.1.2.3:42032", "a paste checked and trimmed")
	_clip = "10.1.2.3\nrm -rf"
	join_page.paste_into(join_page.address_field)
	assert_eq(join_page.address_field.text, "10.1.2.3:42032", "a refused paste leaves it")
	assert_eq(join_page.lines[0], ["NOT AN ADDRESS", true])


func test_the_on_screen_keyboard() -> void:
	if not need_rom():
		return
	MwGlyphs.last_device = 0                   # a gamepad used last
	var m := _machine(MwScreens.JOIN_GAME)
	_run(10)
	var page := m.menu() as MwOnlineMenu
	_accept(m)
	assert_true(_on(m, MwScreens.KEYBOARD), "123 pushed over the page")
	var kb := m.menu() as MwKeyboardScreen
	assert_same(kb.field, page.address_field)
	assert_eq(kb.word_labels(), ["123", "DEL", "PASTE", "OK"])
	assert_eq(kb.keys(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ.-")
	kb.pick()                                 # A: the key under the cursor
	assert_eq(kb.field.text, "A")
	kb.move(1, 0)
	kb.pick()
	assert_eq(kb.field.text, "AB")
	kb.erase()                                # B: back one
	assert_eq(kb.field.text, "A")
	kb.move(0, -1)                            # up from the top row: the words
	assert_eq(kb.cursor, MwKeyboardScreen.KEYS)
	kb.pick()                                 # the 123 page
	assert_eq(kb.keys(), "1234567890.:-[]")
	assert_eq(kb.word_labels()[0], "ABC")
	kb.move(0, 1)                             # down from the words: the grid's top
	assert_eq(kb.cursor, 0)
	kb.erase()
	for i in 3:
		kb.pick()
	assert_eq(kb.field.text, "111")
	_clip = "not an address!"
	kb.cursor = MwKeyboardScreen.KEYS + 2      # PASTE
	kb.pick()
	assert_eq(kb.note, "NOT AN ADDRESS", "the field's checks")
	assert_eq(kb.field.text, "111")
	_clip = "10.0.0.7"
	kb.pick()
	assert_eq(kb.field.text, "10.0.0.7")
	kb.close(true)                            # Start: OK
	assert_true(_on(m, MwScreens.JOIN_GAME), "popped")
	assert_eq(page.address_field.text, "10.0.0.7")
	assert_eq(MwSettings.net_address, "10.0.0.7", "checked and remembered")
	_accept(m)
	assert_true(_on(m, MwScreens.KEYBOARD))
	kb = m.menu() as MwKeyboardScreen
	kb.pick()
	assert_eq(kb.field.text, "10.0.0.7A")
	_press(m, "ui_back")
	assert_true(_on(m, MwScreens.JOIN_GAME), "Back cancels")
	assert_eq(page.address_field.text, "10.0.0.7", "the field as it was")
	_press(m, "ui_down")
	_accept(m)
	assert_true(_on(m, MwScreens.KEYBOARD))
	kb = m.menu() as MwKeyboardScreen
	assert_eq(kb.keys(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ.-", "the password's pages")
	kb.cursor = 2
	kb.pick()
	kb.close(true)
	assert_true(_on(m, MwScreens.JOIN_GAME))
	assert_eq(page.password_field.text, "C")
	var h := _machine(MwScreens.HOST_GAME)
	_run(10)
	_accept(h)
	assert_true(_on(h, MwScreens.KEYBOARD))
	kb = h.menu() as MwKeyboardScreen
	assert_eq(kb.word_labels(), ["DEL", "PASTE", "OK"], "a port: one page of digits")
	assert_eq(kb.keys(), "1234567890")


func test_every_key_is_one_the_big_font_draws() -> void:
	if not need_rom():
		return
	var bytes := MwRom.data()
	for kind in MwTextField.PAGES:
		var probe := MwTextField.new(kind)
		for page: Array in MwTextField.PAGES[kind]:
			var keys: String = page[1]
			assert_lte(keys.length(), MwKeyboardScreen.KEYS, "a page fits the grid")
			for i in keys.length():
				var ch := keys.unicode_at(i)
				assert_true(probe.allows(ch), "the field takes '%s'" % keys[i])
				var drawn := MwKeyboardScreen.BRACKET_FROM if ch in MwKeyboardScreen.BRACKETS else ch
				assert_false(MwKeyboardScreen.key_piece(bytes, drawn).is_empty(), "the big font draws '%s'" % keys[i])
	var l := MwKeyboardScreen.key_piece(bytes, MwKeyboardScreen.BRACKET_FROM)
	var plain: Dictionary = MwGfx.frame_image(bytes, [l])
	var open: Dictionary = MwKeyboardScreen.bracket(bytes, l, false)
	var close: Dictionary = MwKeyboardScreen.bracket(bytes, l, true)
	assert_eq([open["w"], open["h"]], [plain["w"], plain["h"]], "a bracket in the letter's place")
	assert_gt((open["px"] as PackedByteArray).count(0), 0)
	assert_lt((open["px"] as PackedByteArray).count(0), (plain["px"] as PackedByteArray).count(0),
			"the L and a bar more")
	assert_ne(open["px"], close["px"], "] mirrors [")


# --- machines through the pages -------------------------------------------------------------------

func _join_through_the_pages(address_of: Callable) -> void:
	var h := _machine(MwScreens.HOST_GAME)
	var c := _machine(MwScreens.JOIN_GAME)
	_run(10)
	_select(h, "start")
	_accept(h)
	assert_true(_on(h, MwScreens.LOBBY), "START SERVER: the lobby")
	var hs := h.net()
	assert_not_null(hs)
	assert_true(hs.is_host())
	var hp := h.menu() as MwOnlineMenu
	assert_eq(hp.rows.map(func(r): return r.label), ["START GAME", "CLOSE LOBBY", "COPY ADDRESS"])
	for plane: RomPlane in hp._colours.values():
		assert_eq(plane.get_parent(), hp.page_layers, "the players' colours: the page's own layers (they fade with it)")
	_select(h, "copy")
	_accept(h)
	assert_eq(_clip, "192.0.2.10:%d" % hs.port, "COPY ADDRESS: the LAN's, with the port")
	_accept(c)
	_type(c, address_of.call(hs.port))
	_select(c, "connect")
	_accept(c)
	assert_true(_on(c, MwScreens.LOBBY), "in the lobby")
	var both := func() -> bool:
		return str(hs.lobby().numbers()) == "[1, 2]" and str(c.net().lobby().numbers()) == "[1, 2]"
	assert_true(_until(both), "both lobbies: P1 and P2")
	var cl := c.menu() as MwOnlineMenu
	assert_eq(cl.rows.map(func(r): return r.label), ["EXIT LOBBY"])
	assert_eq(c.net().number_of(1), 2, "the client's first player: P2")
	# a local player on the client joins with a press, leaves with Back
	_press(c, "p3_ui_accept")
	assert_true(_until(func() -> bool: return str(hs.lobby().numbers()) == "[1, 2, 3]"), "P3 joined from the client")
	assert_true(_until(func() -> bool: return c.net().number_of(3) == 3))
	_press(c, "p3_ui_back")
	assert_true(_until(func() -> bool: return str(hs.lobby().numbers()) == "[1, 2]"), "and left")
	_press(h, "p2_ui_accept")
	assert_eq(str(hs.lobby().numbers()), "[1, 2, 3]", "the host's second player: the next number")
	_press(h, "p2_ui_back")
	assert_eq(str(hs.lobby().numbers()), "[1, 2]")
	# START GAME: the game's calls (work item 4)
	_select(h, "start_game")
	_accept(h)
	assert_eq(calls.size(), 1)
	assert_eq(calls[0][0], "host")
	assert_same(calls[0][2], h.router, "start_host(session, router, service)")
	assert_same(calls[0][3], hs)
	var record := PackedByteArray([7, 7, 7])
	var match_id := hs.host.start_match(record)          # what start_host does (work item 4)
	assert_true(_until(func() -> bool: return calls.size() == 2), "START reaches the client")
	assert_eq(calls[1][0], "client")
	assert_same(calls[1][2], c.router)
	assert_eq(calls[1].slice(4), [match_id, 0, record])
	hs.host.end_match()
	assert_true(_until(func() -> bool: return c.net().state == MwNetService.State.LOBBY))
	# EXIT LOBBY (asked first), then CLOSE LOBBY
	_press(c, "p1_ui_back")
	assert_true(cl.confirm.active, "asked first")
	_press(c, "p1_ui_up")
	_press(c, "p1_ui_accept")
	assert_true(_on(c, MwScreens.JOIN_GAME), "EXIT LOBBY: back to JOIN GAME")
	assert_null(c.router.session.net)
	assert_true(_until(func() -> bool: return str(hs.lobby().numbers()) == "[1]"), "the host sees it")
	_select(h, "leave")
	_accept(h)
	_press(h, "p1_ui_up")
	_press(h, "p1_ui_accept")
	assert_true(_on(h, MwScreens.HOST_GAME), "CLOSE LOBBY: back to HOST GAME")
	_handle_dtls_errors()


func test_a_host_and_a_client_through_the_pages_on_ipv4() -> void:
	if not need_rom():
		return
	_join_through_the_pages(func(port: int) -> String: return "127.0.0.1:%d" % port)


func test_a_host_and_a_client_through_the_pages_on_ipv6() -> void:
	if not need_rom():
		return
	if not "0:0:0:0:0:0:0:1" in IP.get_local_addresses() and not "::1" in IP.get_local_addresses():
		pending("no IPv6 here")
		return
	_join_through_the_pages(func(port: int) -> String: return "[::1]:%d" % port)


func test_a_closed_lobby_takes_the_client_back_with_why() -> void:
	if not need_rom():
		return
	var h := _machine(MwScreens.HOST_GAME)
	var c := _machine(MwScreens.JOIN_GAME)
	_run(10)
	_select(h, "start")
	_accept(h)
	assert_true(_on(h, MwScreens.LOBBY))
	var cp := c.menu() as MwOnlineMenu
	cp.address_field.text = "127.0.0.1:%d" % h.net().port
	_select(c, "connect")
	_accept(c)
	assert_true(_on(c, MwScreens.LOBBY))
	h.net().leave()                            # CLOSE LOBBY
	assert_true(_on(c, MwScreens.JOIN_GAME))
	assert_eq((c.menu() as MwOnlineMenu).lines[0], ["THE HOST CLOSED THE LOBBY", true])
	assert_true(_on(h, MwScreens.HOST_GAME), "and the host's page back to HOST GAME")
	_handle_dtls_errors()


# --- the loopback: refusals and a changed key on JOIN GAME ----------------------------------------

func _on_loopback(service: MwNetService) -> void:
	var loopback := loop
	service.connector = func(a: String, _p: int, pinned: PackedByteArray) -> MwNetTransport:
		return loopback.connect_to(a, "10.0.1.1", MwNetIdentity.fingerprint_of(pinned) if not pinned.is_empty()
				else PackedByteArray())


## A bare host on the loopback (the client's side is what is tested).
func _loopback_host(password: String, cert_seed := 1) -> void:
	if loop == null:
		loop = MwNetLoopback.new(3)
	var der := fake_cert(cert_seed)
	_loop_host = MwNetHost.new(loop.listen(HOST, MwNetIdentity.fingerprint_of(der)), der,
			MwNetService.fold(password))
	_loop_host.open()


func test_refusals_show_on_join_game() -> void:
	if not need_rom():
		return
	_loopback_host("pw")
	var c := _machine(MwScreens.JOIN_GAME)
	_run(10)
	var page := c.menu() as MwOnlineMenu
	page.address_field.text = HOST
	_select(c, "password")
	_accept(c)
	_type(c, "nope")
	_select(c, "connect")
	_accept(c)
	assert_true(_until(func() -> bool: return page.lines[0][1] == true, 60000), "refused")
	assert_eq(page.lines[0], ["WRONG PASSWORD - WAIT 1 S", true])
	assert_null(c.router.session.net, "the service ended")
	_accept(c)
	assert_null(c.router.session.net, "no new try during the wait")
	_run(70)
	assert_eq(page.lines[0], ["WRONG PASSWORD", true], "the wait counted down")
	_select(c, "password")
	_accept(c)
	_type(c, "PW")
	_select(c, "connect")
	_accept(c)
	assert_true(_on(c, MwScreens.LOBBY), "the right password")


func test_a_changed_key_is_asked_about_on_join_game() -> void:
	if not need_rom():
		return
	_loopback_host("", 1)
	MwNetKnownHosts.remember(HOST, MwNetProtocol.PORT, fake_cert(9))     # last time: another key
	var c := _machine(MwScreens.JOIN_GAME)
	_run(10)
	var page := c.menu() as MwOnlineMenu
	page.address_field.text = HOST
	_select(c, "connect")
	_accept(c)
	assert_true(_until(func() -> bool: return page.confirm.active, 60000), "THIS HOST'S KEY HAS CHANGED")
	assert_eq(page.lines[0], ["OLD KEY " + MwNetIdentity.readable(MwNetIdentity.fingerprint_of(fake_cert(9))), false])
	assert_eq(page.lines[1], ["NEW KEY " + MwNetIdentity.readable(MwNetIdentity.fingerprint_of(fake_cert(1))), false])
	_press(c, "ui_accept")                     # NO (selected first)
	assert_null(c.router.session.net, "not connected")
	_accept(c)
	assert_true(_until(func() -> bool: return page.confirm.active, 60000))
	_press(c, "ui_up")
	_press(c, "ui_accept")                     # YES
	assert_true(_on(c, MwScreens.LOBBY), "trusted: in")


## tools/bin/net-mock (docs/net.md "The mock session") starts the game with
## [code]-- --join ADDRESS --password P[/code]: the boot goes to JOIN GAME,
## which connects at once - into the lobby - and leaves the address the
## settings remember alone.
func test_the_command_lines_join_goes_straight_in() -> void:
	if not need_rom():
		return
	assert_eq(RouterService.join_request(PackedStringArray(["--join", "127.0.0.1:42151", "--password", "MOCK"])),
			{"join": "127.0.0.1:42151", "password": "MOCK"})
	assert_eq(RouterService.join_request(PackedStringArray(["--join", "x"])), {"join": "x", "password": ""})
	assert_eq(RouterService.join_request(PackedStringArray(["--password", "x"])), {}, "no --join: the title")
	_loopback_host("pw")
	MwSettings.net_address = "192.0.2.7"
	var c := _machine(MwScreens.BOOT)
	var boot := c.menu() as MwPlaceholderScreen
	boot.auto_exit = MwScreens.JOIN_GAME           # as MwRouterService._adopt sets it for --join
	boot.auto_exit_data = {"join": HOST, "password": "pw"}
	assert_true(_on(c, MwScreens.JOIN_GAME), "the boot goes to JOIN GAME")
	var page := c.menu() as MwOnlineMenu
	assert_eq(page.address_field.text, HOST)
	assert_eq(page.password_field.text, "pw")
	assert_not_null(c.net(), "connecting at once")
	assert_true(_on(c, MwScreens.LOBBY), "in the lobby")
	assert_eq(MwSettings.net_address, "192.0.2.7", "the remembered address left alone")


## Plan 35 work items 3 and 4 together: a host and a client through the
## pages into a lobby, then START GAME - the match takes both routers to the
## game setup at the same tick, and the host's Back takes everyone back to
## the lobby.
func test_start_game_takes_both_machines_into_the_game() -> void:
	if not need_rom():
		return
	real_match = true
	var h := _machine(MwScreens.HOST_GAME)
	var c := _machine(MwScreens.JOIN_GAME)
	_run(10)
	_select(h, "start")
	_accept(h)
	assert_true(_on(h, MwScreens.LOBBY))
	var hs := h.net()
	_accept(c)
	_type(c, "127.0.0.1:%d" % hs.port)
	_select(c, "connect")
	_accept(c)
	assert_true(_on(c, MwScreens.LOBBY))
	assert_true(_until(func() -> bool: return str(hs.lobby().numbers()) == "[1, 2]"))
	_select(h, "start_game")
	_accept(h)
	assert_true(_until(func() -> bool: return h.router.current_id() == 1 and c.router.current_id() == 1, 30000),
			"both machines on the game setup")
	assert_not_null(h.router.driver, "the match drives the host")
	assert_not_null(c.router.driver, "and the client")
	assert_eq(c.router.session.local_mode, "exhibition", "the start record's")
	_handle_dtls_errors()
