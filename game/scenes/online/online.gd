class_name MwOnlineMenu
extends MwPortMenu
## The online pages (plan 35 section 2, work item 3; their layout the
## owner's), in the port menus' look ([MwPortMenu]: the starfield, the logo,
## the titles on the pause menu's plate, the menu fonts, the highlight frame,
## sound $25 on moves and $2E on refusals) - one scene for four screens, an
## entry each:
##
## * 119 ONLINE MULTIPLAYER (`online`): HOST GAME, JOIN GAME - and REJOIN
##   while this machine keeps a rejoin key (MwNetRejoin: a crash or a
##   restart mid-match; JOIN GAME to that address at once). Back: PLAY MODE.
## * 120 HOST GAME (`host`): PORT (42032 by default; digits, 1-65535, one
##   under 1024 warns), PASSWORD (empty: none), START SERVER -> the lobby.
## * 121 JOIN GAME (`join`): IP ADDRESS (an address, a host name, an
##   optional port: MwNetAddress), PASSWORD, CONNECT TO SERVER (REJOIN when
##   a kept key is for that address) -> RESOLVING... / CONNECTING... (Back
##   cancels) -> the lobby. What went wrong shows on the page in red: a
##   refusal (a wrong password with its wait counting down, too many tries,
##   full, a match running, another version or ROM, blocked, busy), no
##   answer, no such host, a lobby that ended (closed, kicked, lost). A known
##   host whose key changed is asked about first, password or not (plan 45;
##   THIS HOST'S KEY HAS CHANGED, the old and new keys under it).
## * 122 LOBBY (`lobby`): the players by number - P1-P12 in their colours
##   (MwPlayerColours), their machine (LOCAL, HOST, or the remote machine's
##   address, shortened), their device's glyph, the machine's ping; the
##   host: START GAME, CLOSE LOBBY, COPY ADDRESS (Left / Right: the
##   addresses to share - the public one UPnP found, then the LAN's - put
##   on the OS clipboard) and the UPnP line (PORT OPEN, or OPEN PORT 42032
##   ON YOUR ROUTER); a client: EXIT LOBBY. The menu is the machine's first
##   player's; any other local player's press joins them (the next free
##   number), their Back leaves; the first player's Back is CLOSE / EXIT
##   LOBBY, asked first. A machine back in a running match with its key
##   waits here for its game (REJOINING AT THE NEXT FACE OFF: plan 35 work
##   item 6, MwNetMatch.start_rejoin).
##
## Text fields ([MwTextField]): accept on a field pushes the on-screen
## keyboard (123, [MwKeyboardScreen]: a text input screen, the scheme of
## CREATE-A-TEAM's text entry) over the page with it - the keyboard types
## (the keys bound to verbs drive none meanwhile: MwKeyGate; Enter keeps,
## Esc drops) and the pads pick from its keys, both at once. Ctrl+V and
## Shift+Insert on a field's row paste into it without opening it. The
## last port and address are remembered ([member MwSettings.net_port],
## [member MwSettings.net_address]); passwords never (kept while the game
## runs).
##
## The pages work through [MwNetService] ([member MwSession.net], polled by
## the Router autoload every tick); START GAME and a client's START go on
## to the game (work item 4, MwNetMatch).
## Short names: f a text field (MwTextField).

## The pages' titles (on the pause menu's plate).
const PAGE_TITLES := {"online": "ONLINE MULTIPLAYER", "host": "HOST GAME", "join": "JOIN GAME",
		"lobby": "LOBBY"}
## The field pages: the fields' rows (two apart), the button's row after a
## gap, and the two lines under them (what is happening, what went wrong).
const FIELD_Y := 15
const BUTTON_Y := 20
const NOTE_Y := 23
const NOTE2_Y := 25
## The lobby: its title (no logo: twelve players need the rows), the
## players' first row (one a row), the items' first row (two apart), the
## lines under them.
const LOBBY_TITLE_Y := 2
const PLAYER_Y := 5
const LOBBY_ITEM_Y := 18
const LOBBY_NOTE_Y := 24
const LOBBY_HINT_Y := 26
## A player row's columns (cells): the number, the machine (at most
## [constant MACHINE_CELLS]), the device's glyph; the ping ends at the
## rows' right edge.
const COL_NUMBER := 4
const COL_MACHINE := 8
const MACHINE_CELLS := 17
const COL_GLYPH := 26
## A port under this warns (the system may keep it for itself).
const PORT_LOW := 1024
## The device glyph of a lobby row by MwNetService.Device (MwGlyphs).
const DEVICE_GLYPHS := {MwNetService.Device.KEYS: "vk:13", MwNetService.Device.PAD: "pad:START",
		MwNetService.Device.XB: "pad:A", MwNetService.Device.PS: "pad:CROSS", MwNetService.Device.NS: "pad:B"}
const LOW_PORT := "A PORT UNDER 1024 MAY NOT WORK"
const COPIED := "COPIED"
const NO_ADDRESS := "NO ADDRESS TO SHARE"
const JOIN_HINT := "PRESS A BUTTON TO JOIN"
const WAITING := "WAITING FOR THE HOST"
const RUNNING := "A MATCH IS ON"

var port_field: MwTextField
var password_field: MwTextField
var address_field: MwTextField
## The page's two lines: [text, red] each (NOTE_Y and NOTE2_Y; the lobby's
## second is LOBBY_HINT_Y's).
var lines := [["", false], ["", false]]
var _pushed: MwTextField = null       # the field the on-screen keyboard edits
var _starfield_back := []             # where the keyboard leaves the starfield
var _colours := {}                    # player number -> RomPlane (their colour)
var _seen := -1                       # the service's revision drawn last
var _leaving := false                 # an exit asked: the page waits for it
var _addr := 0                        # COPY ADDRESS: the address shown
var _refusal := 0                     # a refusal with a wait: its code ...
var _wait_ticks := 0                  # ... and the wait's ticks left
var _copied := false
var _keep_address := false            # joined from the command line: MwSettings.net_address kept


func _enter_screen(data: Dictionary) -> void:
	resume_fresh = true                    # plan 40, S12 (B9): the keyboard's time isn't caught up
	super._enter_screen(data)
	if rom.is_empty() or not PAGE_TITLES.has(page):
		return
	var why := str(data.get("message", ""))
	if why != "":
		_line(0, why, true)
	match page:
		"online":
			_drop_service()                  # nothing online goes on from here
		"join":
			if data.get("rejoin", false):
				address_field.set_text(MwNetService.rejoin_address())
				_build_rows()
				_connect()
			elif data.has("join"):
				# the command line's --join (tools/bin/net-mock): its address and
				# password in the fields, connected at once (REJOIN with a kept
				# key for it), the address the settings remember left alone
				address_field.set_text(str(data["join"]))
				password_field.set_text(str(data.get("password", "")))
				_keep_address = true
				_build_rows()
				_connect()
		"lobby":
			confirm.player = 1               # the machine's first player answers
			for n in range(1, MwNetLobby.MAX_PLAYERS + 1):
				# the page's own: they fade with it
				_colours[n] = page_layer("Player%d" % n, -1, MwPlayerColours.colour(rom, n))
	_draw()


## The service this machine's online play goes through (null: none).
func _service() -> MwNetService:
	return session.net if session != null else null


## Ends and forgets the session's service (CLOSE / EXIT LOBBY, leaving the
## online pages).
func _drop_service() -> void:
	if session != null and session.net != null:
		session.net.leave()
		session.net = null


# --- rows -------------------------------------------------------------------------------------------

func _build_rows() -> void:
	if not PAGE_TITLES.has(page):
		super._build_rows()
		return
	rows.clear()
	_make_fields()
	match page:
		"online":
			var items := [["HOST GAME", "host"], ["JOIN GAME", "join"]]
			if MwNetService.rejoin_address() != "":
				items.append(["REJOIN", "rejoin"])
			_item_w = ITEM_W
			for i in items.size():
				rows.append({"kind": Kind.ITEM, "label": items[i][0], "action": items[i][1],
						"y": ITEM_Y + ITEM_STEP * i, "centred": true})
				if not rom.is_empty():
					_item_w = maxi(_item_w, _width(FONT_LIGHT, _ascii(items[i][0])) + 4)
			_item_w += _item_w % 2
		"host":
			rows.append({"kind": Kind.CHOICE, "label": "PORT", "action": "port", "field": port_field, "y": FIELD_Y})
			rows.append({"kind": Kind.CHOICE, "label": "PASSWORD", "action": "password", "field": password_field,
					"y": FIELD_Y + 2, "empty": "NONE"})
			rows.append({"kind": Kind.ITEM, "label": "START SERVER", "action": "start", "y": BUTTON_Y})
		"join":
			rows.append({"kind": Kind.CHOICE, "label": "IP ADDRESS", "action": "address", "field": address_field,
					"y": FIELD_Y})
			rows.append({"kind": Kind.CHOICE, "label": "PASSWORD", "action": "password", "field": password_field,
					"y": FIELD_Y + 2, "empty": "NONE"})
			rows.append({"kind": Kind.ITEM, "label": connect_label(), "action": "connect", "y": BUTTON_Y})
		"lobby":
			var svc := _service()
			if svc != null and svc.is_host():
				rows.append({"kind": Kind.ITEM, "label": "START GAME", "action": "start_game", "y": LOBBY_ITEM_Y})
				rows.append({"kind": Kind.ITEM, "label": "CLOSE LOBBY", "action": "leave", "y": LOBBY_ITEM_Y + 2})
				rows.append({"kind": Kind.CHOICE, "label": "COPY ADDRESS", "action": "copy", "y": LOBBY_ITEM_Y + 4})
			else:
				rows.append({"kind": Kind.ITEM, "label": "EXIT LOBBY", "action": "leave", "y": LOBBY_ITEM_Y})
	row = clampi(row, 0, maxi(rows.size() - 1, 0))


## JOIN GAME's button: REJOIN when a rejoin key is kept for the address.
func connect_label() -> String:
	return "REJOIN" if MwNetService.rejoin_matches(address_field.text) else "CONNECT TO SERVER"


## The fields, as this page had them last (the port and address as the
## settings remember them).
func _make_fields() -> void:
	if port_field != null:
		return
	var st: Dictionary = session.screens.get(screen_id, {}) if session else {}
	port_field = MwTextField.new(MwTextField.Kind.PORT, str(st.get("port", str(MwSettings.net_port))))
	password_field = MwTextField.new(MwTextField.Kind.PASSWORD, str(st.get("password", "")))
	address_field = MwTextField.new(MwTextField.Kind.ADDRESS, str(st.get("address", MwSettings.net_address)))
	port_field.id = "port"
	password_field.id = "password"
	address_field.id = "address"
	_addr = int(st.get("addr", 0))


func _remember() -> void:
	super._remember()
	if session == null or not PAGE_TITLES.has(page) or port_field == null:
		return
	var st: Dictionary = session.screens[screen_id]
	st["port"] = port_field.text
	st["password"] = password_field.text          # in memory only: never saved
	st["address"] = address_field.text
	st["addr"] = _addr


## The page's title: the online pages' own ([constant PAGE_TITLES]), else [MwPortMenu]'s.
func page_title() -> String:
	return PAGE_TITLES.get(page, super.page_title())


# --- passes -----------------------------------------------------------------------------------------

func _screen_pass(elapsed: int, input: MwInputFrame) -> void:
	if rom.is_empty() or not PAGE_TITLES.has(page):
		super._screen_pass(elapsed, input)
		return
	if _menu_pass(elapsed):
		_net_pass()                          # leaving by a cut (MwPortMenu): the service still runs
		return
	_net_pass()
	_count_wait(elapsed)
	if _leaving:
		for i in elapsed:
			starfield.step()
		return
	if page == "lobby":
		_lobby_pass(elapsed, input)
		return
	if _joining() and not confirm.active:
		for i in elapsed:
			starfield.step()
		if input != null and input.is_pressed("ui_back"):
			_service().cancel()              # Back cancels connecting
			MwSound.play(SOUND_MOVE)
		return
	super._screen_pass(elapsed, input)


## The lobby's pass: the first player drives the menu; the others' presses
## join them, their Back takes them out.
func _lobby_pass(elapsed: int, input: MwInputFrame) -> void:
	for i in elapsed:
		starfield.step()
	if input == null:
		return
	if confirm.handle(input):
		return
	var svc := _service()
	if svc == null:
		return
	for p in range(2, MwVerbs.PLAYERS + 1):
		if not _pressed_any(input, p):
			continue
		if svc.number_of(p) != 0:
			if input.menu_pressed(p, "ui_back") and svc.leave_local(p):
				MwSound.play(SOUND_MOVE)
		elif not input.menu_pressed(p, "ui_back") and svc.join_local(p):
			MwSound.play(SOUND_MOVE)
	if input.menu_pressed(1, "ui_back"):
		_ask_leave()
	elif input.menu_pressed(1, "ui_up"):
		_move(-1)
	elif input.menu_pressed(1, "ui_down"):
		_move(1)
	elif input.menu_pressed(1, "ui_left"):
		_change(-1)
	elif input.menu_pressed(1, "ui_right"):
		_change(1)
	elif input.menu_pressed(1, "ui_accept"):
		_accept()


## True when player [param p] newly pressed anything (their own actions).
static func _pressed_any(input: MwInputFrame, p: int) -> bool:
	for a: String in input.pressed:
		if int(MwVerbs.parse_action(a)[0]) == p:
			return true
	return false


## Follows the service: its state moves the pages on, its changes redraw.
func _net_pass() -> void:
	var svc := _service()
	if svc == null:
		if page == "lobby" and not _leaving:
			_leaving = true
			exit_to(MwScreens.ONLINE)
		return
	if svc.revision == _seen or _leaving:
		return
	_seen = svc.revision
	match page:
		"join":
			_join_progress(svc)
		"lobby":
			_lobby_progress(svc)
	if not _leaving:
		_draw()


func _join_progress(svc: MwNetService) -> void:
	match svc.state:
		MwNetService.State.RESOLVING:
			_line(0, "RESOLVING ...")
			_line(1, "BACK TO CANCEL")
		MwNetService.State.CONNECTING:
			_line(0, "CONNECTING ...")
			_line(1, "BACK TO CANCEL")
		MwNetService.State.TRUST:
			if svc.fingerprints.size() == 2:
				_line(0, "OLD KEY " + svc.fingerprints[0])
				_line(1, "NEW KEY " + svc.fingerprints[1])
			if not confirm.active:
				_asked = "trust"
				confirm.open("THIS HOST'S KEY HAS CHANGED", "CONNECT?")
		MwNetService.State.LOBBY, MwNetService.State.RUNNING:
			_leaving = true
			_remember()
			exit_to(MwScreens.LOBBY)
		MwNetService.State.DONE:
			if confirm.active:
				confirm.close()
			_asked = ""
			_line(0, svc.message, true)
			_line(1, "")
			if svc.client != null and svc.client.fail == MwNetClient.Fail.REFUSED:
				_refusal = svc.client.refusal
				_wait_ticks = svc.wait_left() * MwRouter.TICK_HZ
			if svc.message != "":
				MwSound.play(SOUND_REFUSED)
			session.net = null
			_build_rows()


func _lobby_progress(svc: MwNetService) -> void:
	if svc.state == MwNetService.State.DONE:
		_leaving = true
		var data := {"message": svc.message}
		var back := MwScreens.HOST_GAME if svc.is_host() else MwScreens.JOIN_GAME
		session.net = null
		exit_to(back, data)


## A refusal's wait counting down on the page (WRONG PASSWORD - WAIT 3 S).
func _count_wait(elapsed: int) -> void:
	if _wait_ticks <= 0:
		return
	var before := ceili(_wait_ticks / float(MwRouter.TICK_HZ))
	_wait_ticks = maxi(_wait_ticks - elapsed, 0)
	var now := ceili(_wait_ticks / float(MwRouter.TICK_HZ))
	if now != before:
		_line(0, MwNetService.refusal_text(_refusal, now), true)
		_draw()


## True while joining (resolving, connecting, asked about a key).
func _joining() -> bool:
	var svc := _service()
	return svc != null and svc.role == MwNetService.Role.CLIENT and svc.state in [
			MwNetService.State.RESOLVING, MwNetService.State.CONNECTING, MwNetService.State.TRUST]


# --- actions ----------------------------------------------------------------------------------------

func _accept() -> void:
	if not PAGE_TITLES.has(page):
		super._accept()
		return
	_remember()
	if rows.is_empty():
		return
	var r := rows[row]
	if r.has("field"):
		_edit(r.field)
		return
	match r.action:
		"host":
			exit_to(MwScreens.HOST_GAME)
		"join":
			exit_to(MwScreens.JOIN_GAME)
		"rejoin":
			exit_to(MwScreens.JOIN_GAME, {"rejoin": true})
		"start":
			_start_server()
		"connect":
			_connect()
		"start_game":
			if _service() != null and _service().start_game():
				MwSound.play(SOUND_MOVE)
			else:
				MwSound.play(SOUND_REFUSED)
		"leave":
			_ask_leave()
		"copy":
			_copy_address()


func _back() -> void:
	if not PAGE_TITLES.has(page):
		super._back()
		return
	_remember()
	match page:
		"online":
			_drop_service()
			exit_to(MwScreens.PLAY_MODE)
		"host", "join":
			exit_to(MwScreens.ONLINE)
		"lobby":
			_ask_leave()


## The lobby's COPY ADDRESS: Left / Right step through the addresses.
func _change(d: int) -> void:
	if not PAGE_TITLES.has(page):
		super._change(d)
		return
	if rows.is_empty() or rows[row].get("action", "") != "copy" or _service() == null:
		return
	var n := _service().addresses().size()
	if n < 2:
		return
	_addr = posmod(_addr + d, n)
	_copied = false
	MwSound.play(SOUND_MOVE)
	_draw()


## START SERVER: the service hosts; the lobby next.
func _start_server() -> void:
	var p := MwNetAddress.port_of(port_field.text)
	if p == 0:
		_refuse(MwTextField.NOT_TEXT[MwTextField.Kind.PORT])
		return
	var svc := MwNetService.new(session)
	if not svc.host_game(p, password_field.text):
		_refuse(svc.message)
		return
	session.net = svc
	MwSettings.net_port = p
	MwSettings.save()
	MwSound.play(SOUND_MOVE)
	_leaving = true
	exit_to(MwScreens.LOBBY)


## CONNECT TO SERVER (or REJOIN): the service joins; the lobby once in.
func _connect() -> void:
	if _service() != null:
		return
	if _wait_ticks > 0:
		MwSound.play(SOUND_REFUSED)
		return
	if MwNetAddress.parse(address_field.text).is_empty():
		_refuse(MwTextField.NOT_TEXT[MwTextField.Kind.ADDRESS])
		return
	var svc := MwNetService.new(session)
	if not svc.join_game(address_field.text, password_field.text):
		_refuse(svc.message)
		return
	session.net = svc
	if not _keep_address:
		MwSettings.net_address = address_field.text.strip_edges()
		MwSettings.save()
	MwSound.play(SOUND_MOVE)
	_seen = -1
	_net_pass()


## Asks before CLOSE LOBBY / EXIT LOBBY.
func _ask_leave() -> void:
	var svc := _service()
	_asked = "leave"
	confirm.open("CLOSE THE LOBBY" if svc != null and svc.is_host() else "LEAVE THE LOBBY")


func _answered(yes: bool) -> void:
	var what := _asked
	if not what in ["trust", "leave"]:
		super._answered(yes)
		return
	_asked = ""
	var svc := _service()
	match what:
		"trust":
			if svc != null:
				if yes:
					svc.trust_new_key()
				else:
					svc.cancel()
		"leave":
			if yes:
				var to_host := svc != null and svc.is_host()
				_drop_service()
				_leaving = true
				exit_to(MwScreens.HOST_GAME if to_host else MwScreens.JOIN_GAME)
				return
	_draw()


## COPY ADDRESS: the address shown goes on the OS clipboard.
func _copy_address() -> void:
	var a := _shown_address()
	if a == "":
		_line(1, NO_ADDRESS)
		MwSound.play(SOUND_REFUSED)
		_draw()
		return
	MwTextField.clipboard_set.call(a)
	_copied = true
	MwSound.play(SOUND_MOVE)
	_draw()


func _shown_address() -> String:
	var svc := _service()
	if svc == null or svc.addresses().is_empty():
		return ""
	return svc.addresses()[clampi(_addr, 0, svc.addresses().size() - 1)]


func _refuse(why: String) -> void:
	_line(0, why, true)
	_line(1, "")
	MwSound.play(SOUND_REFUSED)
	_draw()


func _line(i: int, text: String, red := false) -> void:
	lines[i] = [text, red]


# --- text fields ------------------------------------------------------------------------------------

## Accept on a field: the on-screen keyboard (123) over the page with it -
## typed on the keyboard, picked with the pads.
func _edit(f: MwTextField) -> void:
	_line(0, "")
	_line(1, "")
	_pushed = f
	_starfield_back = starfield.state()
	push(MwScreens.KEYBOARD, {"field": f, "starfield": _starfield_back})


## Back from the on-screen keyboard: its field checked, its starfield kept
## (resume_fresh: not stepped on by the time away), a refusal's wait counted
## down by it.
func _resume_screen(_r := {}) -> void:
	starfield.restore(_starfield_back)
	_count_wait(away)
	if _pushed != null:
		var f := _pushed
		_pushed = null
		_field_done(f)


## A field's new text checked: a port 1-65535 (under 1024 warns), an
## address that reads as one (or nothing); the good ones remembered.
func _field_done(f: MwTextField) -> void:
	match f.kind:
		MwTextField.Kind.PORT:
			var p := MwNetAddress.port_of(f.text)
			if p == 0:
				_line(0, MwTextField.NOT_TEXT[f.kind], true)
				f.set_text(str(MwSettings.net_port))
				MwSound.play(SOUND_REFUSED)
			else:
				f.set_text(str(p))
				_line(0, LOW_PORT if p < PORT_LOW else "")
				MwSettings.net_port = p
				MwSettings.save()
		MwTextField.Kind.ADDRESS:
			f.set_text(f.text.strip_edges())
			if f.text != "" and MwNetAddress.parse(f.text).is_empty():
				_line(0, MwTextField.NOT_TEXT[f.kind], true)
				MwSound.play(SOUND_REFUSED)
			else:
				MwSettings.net_address = f.text
				MwSettings.save()
	_remember()
	_build_rows()
	_draw()


## Ctrl+V / Shift+Insert on a field's row pastes into it.
func _input(event: InputEvent) -> void:
	if not PAGE_TITLES.has(page) or rom.is_empty():
		super._input(event)
		return
	if not visible or not event is InputEventKey or not event.is_pressed():
		return
	var k := event as InputEventKey
	if MwTextField.is_paste(k) and not k.echo and selected_field() != null and not confirm.active and not _leaving:
		get_viewport().set_input_as_handled()
		paste_into(selected_field())


## Pastes the OS clipboard into [param f] (its checks; tests call it).
func paste_into(f: MwTextField) -> void:
	if f.paste():
		MwSound.play(SOUND_MOVE)
		_field_done(f)
	else:
		_refuse(f.message)


## The field on the selected row (null: none).
func selected_field() -> MwTextField:
	if rows.is_empty() or _joining():
		return null
	return rows[row].get("field")


# --- drawing ----------------------------------------------------------------------------------------

## The lobby has its title where the logo and the hanging top are.
func _shows_logo() -> bool:
	return page != "lobby" and super._shows_logo()


func _shows_top() -> bool:
	return page != "lobby" and super._shows_top()


func _draw() -> void:
	if not PAGE_TITLES.has(page):
		super._draw()
		return
	_clear_red()
	for layer: RomPlane in _colours.values():
		layer.clear()
	if page == "lobby":
		_draw_lobby()
		return
	super._draw()
	for i in 2:
		_draw_line(lines[i], NOTE_Y if i == 0 else NOTE2_Y)


func _draw_row(i: int, selected: bool) -> void:
	var r := rows[i]
	if r.has("field"):
		_draw_field(r, selected)
	elif r.get("action", "") == "copy":
		_draw_copy(r, selected)
	else:
		super._draw_row(i, selected)


## A field's row: its label, its text right-aligned (its start and ".."
## when too long; a password as asterisks).
func _draw_field(r: Dictionary, selected: bool) -> void:
	var y: int = r.y
	var on := _on(plane, r.get("dy", 0))        # placed as every row ([method MwPortMenu._draw_row])
	MwMenuRow.frame(on, rom, ROW_X, y, ROW_W, selected)      # plan 40 (M1): MwMenuRow's look
	var font := MwMenuRow.font(selected)
	var label := _ascii(r.label)
	_text(label, ROW_X, y, font, r.get("dy", 0))
	var f: MwTextField = r.field
	var room := MwMenuRow.room(rom, font, label, ROW_W)
	var text: String = f.window(room)["text"]
	if text == "":
		text = str(r.get("empty", ""))
	var b := _ascii(text)
	MwGlyphs.field_text(on, rom, font, b, ROW_X + ROW_W - MwGlyphs.field_width(rom, font, b), y, TEXT_ATTR)


## COPY ADDRESS's row: the address shown (or COPIED once copied).
func _draw_copy(r: Dictionary, selected: bool) -> void:
	var y: int = r.y
	var on := _on(plane, r.get("dy", 0))
	MwMenuRow.frame(on, rom, ROW_X, y, ROW_W, selected)
	var font := MwMenuRow.font(selected)
	var label := _ascii(r.label)
	_text(label, ROW_X, y, font, r.get("dy", 0))
	var a := _shown_address()
	var v := COPIED if _copied else (a if a != "" else "NONE")
	var room := MwMenuRow.room(rom, font, label, ROW_W)
	var b := _ascii(v if v.length() <= room else v.left(room - 2) + "..")
	MwGlyphs.field_text(on, rom, font, b, ROW_X + ROW_W - MwGlyphs.field_width(rom, font, b), y, TEXT_ATTR)


func _draw_line(l: Array, y: int) -> void:
	var text: String = l[0]
	if text == "":
		return
	var b := _ascii(text)
	var w := MwGlyphs.field_width(rom, FONT_LIGHT, b)
	@warning_ignore("integer_division")
	var x := maxi((40 - w) / 2, 0)
	MwGlyphs.field_text(_red if l[1] else plane, rom, FONT_LIGHT, b, x, y, TEXT_ATTR)


## The lobby: the title, a row per player, the items, the lines.
func _draw_lobby() -> void:
	_clear(plane)
	_clear(half_plane)
	_clear(_plate)
	_clear(_dim)
	_centred(page_title(), LOBBY_TITLE_Y, FONT_LIGHT, true)
	var svc := _service()
	var lobby := svc.lobby() if svc != null else null
	if lobby != null:
		var y := PLAYER_Y
		for n in lobby.numbers():
			_draw_player(svc, lobby, n, y)
			y += 1
	for i in rows.size():
		_draw_row(i, i == row)
	_fill = false
	if svc == null:
		return
	var first := WAITING
	if svc.state == MwNetService.State.RUNNING:
		first = MwNetMatch.REJOINING_TEXT if svc.rejoining() else RUNNING
	elif svc.is_host():
		first = svc.upnp_text()
	_draw_line([first, false], LOBBY_NOTE_Y)
	var hint: String = lines[1][0]
	if hint == "" and lobby != null and lobby.free_slots() > 0 and svc.state == MwNetService.State.LOBBY:
		hint = JOIN_HINT
	_draw_line([hint, false], LOBBY_HINT_Y)


## One player's row: P<n> in their colour, their machine, their device's
## glyph, the machine's ping (AWAY: dropped from a running match).
func _draw_player(svc: MwNetService, lobby: MwNetLobby, n: int, y: int) -> void:
	var lobby_player: Dictionary = lobby.players[n]
	var m := int(lobby_player["machine"])
	var machine: Dictionary = lobby.machines.get(m, {})
	var disconnected := not bool(machine.get("connected", true))
	var on := _dim if disconnected else plane
	if _colours.has(n):
		MwGlyphs.text(_colours[n], rom, FONT_LIGHT, _ascii("P%d" % n), COL_NUMBER, y, TEXT_ATTR)
	var who := "LOCAL"
	if m != svc.my_machine():
		who = "HOST" if m == MwNetLobby.HOST_MACHINE \
				else MwNetAddress.shorten(str(machine.get("address", "")), MACHINE_CELLS)
	MwGlyphs.field_text(on, rom, FONT_LIGHT, _ascii(who), COL_MACHINE, y, TEXT_ATTR)
	var cells := MwGlyphs.cells(str(DEVICE_GLYPHS.get(int(lobby_player.get("device", 0)), "")), MwGlyphs.Style.NORMAL)
	MwGlyphs.put_cells(on, cells, COL_GLYPH, MwPrompts.row(rom, FONT_LIGHT, y))
	if m == svc.my_machine():
		return
	var ping := svc.ping_of(m)
	var t := "AWAY" if disconnected else ("%d MS" % ping if ping >= 0 else "")
	var b := _ascii(t)
	MwGlyphs.text(on, rom, FONT_LIGHT, b, ROW_X + ROW_W - _width(FONT_LIGHT, b), y, TEXT_ATTR)
