extends GutTest
## Plan 35 work item 3: what JOIN GAME's IP ADDRESS takes and what the
## host's COPY ADDRESS gives (MwNetAddress), and the online pages' text
## fields (MwTextField): typing, the keys, the paste checks, the window a
## long text shows.

const K := MwTextField.Kind
const R := MwTextField.Result

var _clip := ""
var _saved_get: Callable
var _saved_set: Callable


func before_each() -> void:
	_saved_get = MwTextField.clipboard_get
	_saved_set = MwTextField.clipboard_set
	MwTextField.clipboard_get = func() -> String: return _clip
	MwTextField.clipboard_set = func(copied: String) -> void: _clip = copied


func after_each() -> void:
	MwTextField.clipboard_get = _saved_get
	MwTextField.clipboard_set = _saved_set


func test_the_addresses_the_field_takes() -> void:
	var v4 := MwNetAddress.Kind.IPV4
	var v6 := MwNetAddress.Kind.IPV6
	var name_kind := MwNetAddress.Kind.NAME
	var ok := {
		"192.168.1.20": ["192.168.1.20", 42032, v4],
		"  10.0.0.1  ": ["10.0.0.1", 42032, v4],
		"192.168.1.20:5000": ["192.168.1.20", 5000, v4],
		"::1": ["::1", 42032, v6],
		"2001:DB8::5": ["2001:db8::5", 42032, v6],
		"[2001:db8::5]:42033": ["2001:db8::5", 42033, v6],
		"[::1]": ["::1", 42032, v6],
		"example.org": ["example.org", 42032, name_kind],
		"Host-1.Example.ORG:80": ["host-1.example.org", 80, name_kind],
		"localhost": ["localhost", 42032, name_kind],
		"example.org.": ["example.org.", 42032, name_kind],
	}
	for text: String in ok:
		var a := MwNetAddress.parse(text)
		assert_eq([a.get("host"), a.get("port"), a.get("kind")], ok[text], text)
	assert_true(MwNetAddress.parse("1.2.3.4:99")["port_given"])
	assert_false(MwNetAddress.parse("1.2.3.4")["port_given"])
	for bad in ["", "   ", "256.1.1.1", "1.2.3", "1.2.3.4.5", "1.2.3.4:0", "1.2.3.4:65536", "1.2.3.4:",
			"1.2.3.4:http", "1.2.3.4:5:6", "fe80::1%eth0", "[fe80::1%eth0]:42032", "[::1]42032", "[::1",
			"[1.2.3.4]:42032", "[example.org]:1", "2001:db8::g", "-bad.example", "bad-.example", "a..b",
			"under_score.org", "sp ace.org", "12.34", "x" + "a".repeat(63) + ".org",
			"café.org", "a.b:+80"]:
		assert_eq(MwNetAddress.parse(bad), {}, "refused: '%s'" % bad)
	var long_name := ".".join(["a".repeat(63), "b".repeat(63), "c".repeat(63), "d".repeat(61)])
	assert_eq(long_name.length(), 253)
	assert_false(MwNetAddress.parse(long_name).is_empty(), "253 characters: a host name's limit")
	assert_true(MwNetAddress.parse(long_name + "e").is_empty())


func test_the_addresses_to_share() -> void:
	var all := PackedStringArray(["127.0.0.1", "192.168.1.20", "169.254.3.4", "0:0:0:0:0:0:0:1",
			"fe80:0:0:0:1:2:3:4", "2001:db8:0:0:0:0:0:5", "fe80::1%eth0", "10.0.0.2", "192.168.1.20",
			"0:0:0:0:0:ffff:c000:20a"])
	assert_eq(MwNetAddress.shareable(all), PackedStringArray(["192.168.1.20", "10.0.0.2", "2001:db8::5"]),
			"no loopback, no link-local, IPv4 first, each once, IPv6 short")
	assert_eq(MwNetAddress.join("192.168.1.20", 42032), "192.168.1.20:42032")
	assert_eq(MwNetAddress.join("2001:db8::5", 42032), "[2001:db8::5]:42032")
	for a in ["192.168.1.20", "2001:db8::5"]:
		var back := MwNetAddress.parse(MwNetAddress.join(a, 4000))
		assert_eq([back["host"], back["port"]], [a, 4000], "COPY ADDRESS reads back")


func test_ipv6_short_forms() -> void:
	assert_eq(MwNetAddress.compact("2001:0db8:0000:0000:0000:ff00:0042:8329"), "2001:db8::ff00:42:8329")
	assert_eq(MwNetAddress.compact("0:0:0:0:0:0:0:1"), "::1")
	assert_eq(MwNetAddress.compact("1:0:0:2:0:0:0:3"), "1:0:0:2::3", "the longest run")
	assert_eq(MwNetAddress.compact("1:0:2:3:4:5:6:7"), "1:0:2:3:4:5:6:7", "one zero group stays")
	assert_eq(MwNetAddress.expand("::ffff:1.2.3.4"), PackedInt32Array([0, 0, 0, 0, 0, 0xFFFF, 0x0102, 0x0304]))
	var short := MwNetAddress.shorten("2001:db8:1234:5678:9abc:def0:1234:5678", 17)
	assert_eq(short.length(), 17)
	assert_true(short.begins_with("2001:db8") and short.ends_with(":5678") and ".." in short, short)
	assert_eq(MwNetAddress.shorten("10.0.0.1", 17), "10.0.0.1")


func _key(code: int, unicode := 0, mods := "", echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode
	event.pressed = true
	event.echo = echo
	event.ctrl_pressed = "ctrl" in mods
	event.shift_pressed = "shift" in mods
	return event


func _type(field: MwTextField, text: String) -> Array:
	var out := []
	for i in text.length():
		out.append(field.key(_key(KEY_NONE, text.unicode_at(i))))
	return out


func test_typing_into_a_port() -> void:
	var field := MwTextField.new(K.PORT, "42032")
	assert_eq(field.key(_key(KEY_1, 0x31)), R.NONE, "nothing while not editing")
	field.begin()
	assert_eq(field.cursor, 5)
	assert_eq(field.key(_key(KEY_BACKSPACE)), R.EDITED)
	assert_eq(field.text, "4203")
	assert_eq(_type(field, "a"), [R.REFUSED], "a port takes digits")
	assert_eq(_type(field, "19"), [R.EDITED, R.REFUSED], "five at most")
	assert_eq(field.text, "42031")
	field.key(_key(KEY_HOME))
	field.key(_key(KEY_DELETE))
	assert_eq(field.text, "2031")
	field.key(_key(KEY_RIGHT))
	field.key(_key(KEY_RIGHT))
	_type(field, "7")
	assert_eq(field.text, "20731")
	field.key(_key(KEY_LEFT))
	assert_eq(field.cursor, 2)
	field.key(_key(KEY_END))
	assert_eq(field.cursor, 5)
	assert_eq(field.key(_key(KEY_ESCAPE)), R.CANCELLED)
	assert_eq(field.text, "42032", "Esc: as it was")
	assert_false(field.editing)
	field.begin()
	field.key(_key(KEY_BACKSPACE))
	assert_eq(field.key(_key(KEY_ENTER, 0, "", true)), R.NONE, "a held Enter's repeats don't confirm")
	assert_eq(field.key(_key(KEY_ENTER)), R.CONFIRMED)
	assert_eq(field.text, "4203")


func test_the_fields_characters() -> void:
	var address_field := MwTextField.new(K.ADDRESS)
	var field := MwTextField.new(K.PASSWORD)
	for c in "aZ09.:-[]":
		assert_true(address_field.allows(c.unicode_at(0)), "address: " + c)
	for c in " _/@!%":
		assert_false(address_field.allows(c.unicode_at(0)), "address: not '%s'" % c)
	for c in "aZ09!~_@{":
		assert_true(field.allows(c.unicode_at(0)), "password: " + c)
	assert_false(field.allows(0x20), "no spaces in a password")
	assert_false(field.allows(0xE9), "ASCII only")
	field.begin()
	_type(field, "s3cret")
	assert_eq(field.text, "s3cret", "kept as typed (MwNetService folds the case)")
	assert_eq(field.shown(), "******", "shown as asterisks")
	for i in 40:
		field.type_char(0x78)
	assert_eq(field.text.length(), 32, "32 at most")
	assert_eq(address_field.cap(), 259, "a host name's 253 and a port")


func test_paste_sanity() -> void:
	var field := MwTextField.new(K.ADDRESS, "10.0.0.1")
	_clip = "  192.168.1.20:42032 \n"
	assert_true(field.paste(), "trimmed")
	assert_eq(field.text, "192.168.1.20:42032")
	assert_eq(field.cursor, field.text.length())
	for bad: String in ["1.2.3.4\n5.6.7.8", "café.org", "a b.org", "256.0.0.1", "fe80::1%eth0"]:
		_clip = bad
		assert_false(field.paste(), "refused: " + bad.c_escape())
		assert_eq(field.text, "192.168.1.20:42032", "the field as it was")
		assert_eq(field.message, "NOT AN ADDRESS")
	_clip = "x".repeat(300)
	assert_false(field.paste())
	assert_eq(field.message, "TOO LONG")
	_clip = "   "
	assert_false(field.paste())
	assert_eq(field.message, "NOTHING TO PASTE")
	_clip = "[2001:db8::5]:42032"
	assert_true(field.paste())
	assert_eq(field.message, "")
	var port := MwTextField.new(K.PORT, "42032")
	for bad in ["65536", "0", "80a", "-1", "1 2"]:
		_clip = bad
		assert_false(port.paste(), "port: " + bad)
	_clip = "8080"
	assert_true(port.paste())
	var pw := MwTextField.new(K.PASSWORD)
	_clip = "x".repeat(33)
	assert_false(pw.paste())
	assert_eq(pw.message, "TOO LONG")
	_clip = "two words"
	assert_false(pw.paste())
	_clip = "  Tr0ub4dor&3 "
	assert_true(pw.paste())
	assert_eq(pw.text, "Tr0ub4dor&3")


func test_paste_keys_while_typing() -> void:
	var field := MwTextField.new(K.ADDRESS, "1.2.3.4")
	field.begin()
	_clip = "example.org:4000"
	assert_eq(field.key(_key(KEY_V, 0, "ctrl")), R.PASTED, "Ctrl+V")
	assert_eq(field.text, "example.org:4000")
	_clip = "::1"
	assert_eq(field.key(_key(KEY_INSERT, 0, "shift")), R.PASTED, "Shift+Insert")
	assert_eq(field.text, "::1")
	assert_eq(field.key(_key(KEY_V, 0, "ctrl", true)), R.NONE, "a held paste pastes once")
	_clip = "no way"
	assert_eq(field.key(_key(KEY_V, 0, "ctrl")), R.REFUSED)
	assert_eq(field.text, "::1")
	assert_eq(field.key(_key(KEY_C, 0x63, "ctrl")), R.NONE, "other shortcuts type nothing")
	assert_eq(field.text, "::1")


func test_a_long_text_scrolls() -> void:
	var field := MwTextField.new(K.ADDRESS, "a-very-long-host-name.example.org")
	assert_eq(field.window(12), {"text": "a-very-lon..", "cursor": -1}, "its start, then ..")
	field.begin()
	var w := field.window(12)
	assert_eq([w["text"], w["cursor"]], ["example.org", 11], "typing: the end, the cursor after it")
	field.key(_key(KEY_HOME))
	w = field.window(12)
	assert_eq([w["text"], w["cursor"]], ["a-very-long-", 0])
	var short := MwTextField.new(K.PORT, "42")
	short.begin()
	assert_eq(short.window(12), {"text": "42", "cursor": 2})
