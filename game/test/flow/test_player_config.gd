extends GutTest
## Plan 45 (M1): every player's [code].cfg[/code] file is read through
## MwUserFile.read_config, which refuses a file the engine's text parser would
## build objects from (Object(...), Resource("...") loading a script and
## running its _init), load a class for (a typed container) or recurse into
## without a limit (about 20 000 brackets overflow its stack) - and reads
## every file the engine itself writes as before. A refused file is a missing
## one: the reader's defaults.

const Marker := preload("res://test/flow/config_marker.gd")
const DIR := "user://test/player_config"
const MARKER_PATH := "res://test/flow/config_marker.gd"

var _paths := {}


func before_each() -> void:
	Marker.made = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_paths = {"settings": MwSettings.path, "rejoin": MwNetRejoin.path, "known": MwNetKnownHosts.path,
			"saves": MwPlayoffSave.dir}


func after_each() -> void:
	MwSettings.path = _paths["settings"]
	MwNetRejoin.path = _paths["rejoin"]
	MwNetKnownHosts.path = _paths["known"]
	MwPlayoffSave.dir = _paths["saves"]
	MwSettings.load_file()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))


func _write(file_name: String, text: String) -> String:
	var path := DIR.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


## An object the parser would make from the marker script (its _init counts it).
func _object() -> String:
	return "Object(RefCounted,\"script\":Resource(\"%s\"))" % MARKER_PATH


func test_what_the_engine_writes_reads_as_before() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "camera", "3D EXTENDED")
	cfg.set_value("game", "quoted", "a \"quote\", [brackets] (parens) {braces}; a semicolon\nand a line")
	cfg.set_value("game", "looks_like_code", "Object(RefCounted) Resource(\"res://x.gd\") #ff0000 = 'x'")
	cfg.set_value("net", "port", 42032)
	cfg.set_value("net", "ratio", 0.5)
	cfg.set_value("save", "humans", {"a": [1, 2], "b": [], "positions": {"3": 1}, "lineups": [[1, 2], []]})
	cfg.set_value("save", "bytes", PackedByteArray([1, 2, 3]))
	cfg.set_value("save", "ints", PackedInt32Array([-1, 70000]))
	cfg.set_value("save", "at", Vector2i(3, -4))
	cfg.set_value("save", "typed", [1, 2] as Array[int])
	cfg.set_value("bindings", "p1_ui_left", "key:Left")
	cfg.set_value("0a1b2c", "cert", "QUJD")
	var text := cfg.encode_to_text()
	assert_true(MwUserFile.plain_config(text.to_utf8_buffer()), "plain:\n" + text)
	var back := MwUserFile.read_config(_write("engine.cfg", text))
	assert_not_null(back)
	if back == null:
		return
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			assert_eq(back.get_value(section, key), cfg.get_value(section, key), "%s/%s" % [section, key])


func test_a_comment_written_by_hand_is_fine() -> void:
	var path := _write("comment.cfg", "; my settings\n[game]\n\ncamera=\"2D\" ; the original's\n")
	var cfg := MwUserFile.read_config(path)
	assert_not_null(cfg)
	if cfg != null:
		assert_eq(cfg.get_value("game", "camera"), "2D")


func test_objects_and_resources_are_never_made() -> void:
	var texts := [
		"[s]\nx=%s\n" % _object(),
		"[s]\nx=Resource(\"%s\")\n" % MARKER_PATH,
		"[s]\nx=[1, {\"k\": %s}]\n" % _object(),
		"[s]\nx=Object (RefCounted,\"script\":Resource(\"%s\"))\n" % MARKER_PATH,
		"[s]\nx=Object\n(RefCounted,\"script\":Resource(\"%s\"))\n" % MARKER_PATH,
		"[s]\nx=Object ; a comment\n(RefCounted)\n",
		"[s]\nx=ExtResource(\"1\")\n",
		"[s]\nx=SubResource(\"1\")\n",
		"[s]\nx=Callable()\n",
		"[s]\nx=Array[Resource(\"%s\")]([])\n" % MARKER_PATH,
		"[s]\nx=Array[MwSettings]([])\n",
		"[s]\nx=Array\n[MwSettings]([])\n",
		"[s]\nx=Dictionary[String, MwSettings]({})\n",
		# where a naive reading would take code for a string or a comment
		"; \"\n[s]\nx=%s\n; \"\n" % _object(),
		"[s\"]\nx=%s\n[t\"]\n" % _object(),
		"[s]\nk\"=1\"\nx=%s\n" % _object(),
		"[s]\nx=1 y=%s\n" % _object(),
		"[s]\nx=\"a\" \"b\"=%s\n" % _object(),
		"[s]\nx=[1, ; \"\n%s]\n" % _object(),
		"[s]\nx=#ff0000\n",
	]
	for text: String in texts:
		assert_false(MwUserFile.plain_config(text.to_utf8_buffer()), "refused:\n" + text)
		assert_null(MwUserFile.read_config(_write("crafted.cfg", text)), "read as missing:\n" + text)
	assert_eq(Marker.made, 0, "nothing was made while reading")


func test_deep_nesting_is_refused_before_the_parser_sees_it() -> void:
	var deep := "[s]\nx=" + "[".repeat(20000) + "]".repeat(20000) + "\n"
	assert_null(MwUserFile.read_config(_write("deep.cfg", deep)), "20 000 levels: refused (the parser would crash)")
	var limit := MwUserFile.CONFIG_DEPTH
	var ok := "[s]\nx=" + "[".repeat(limit) + "]".repeat(limit) + "\n"
	assert_not_null(MwUserFile.read_config(_write("ok.cfg", ok)), "%d levels: read" % limit)
	var over := "[s]\nx=" + "[".repeat(limit + 1) + "]".repeat(limit + 1) + "\n"
	assert_null(MwUserFile.read_config(_write("over.cfg", over)), "%d levels: refused" % (limit + 1))
	var strings := "[s]\nx=[" + "\"]\", [".repeat(limit) + "]".repeat(limit + 1) + "\n"
	assert_null(MwUserFile.read_config(_write("hidden.cfg", strings)), "brackets in strings don't hide the depth")


func test_a_file_bigger_than_settings_are_is_refused() -> void:
	var big := "[s]\nx=\"" + "a".repeat(MwUserFile.CONFIG_MAX) + "\"\n"
	assert_null(MwUserFile.read_config(_write("big.cfg", big)))
	assert_null(MwUserFile.read_config(DIR.path_join("missing.cfg")), "a missing file: null")


func test_every_player_cfg_reader_takes_a_crafted_file_as_missing() -> void:
	var crafted := _object()
	MwSettings.path = _write("settings.cfg", "[game]\n\ncamera=%s\n\n[display]\n\nblood=false\n" % crafted)
	MwSettings.load_file()
	assert_true(MwSettings.blood, "the settings: the defaults")
	MwNetRejoin.path = _write("rejoin.cfg", "[rejoin]\naddress=\"a\"\nport=1\nmatch=1\nkey=%s\n" % crafted)
	assert_eq(MwNetRejoin.read(), {}, "the rejoin key: none")
	MwNetKnownHosts.path = _write("known_hosts.cfg", "[%s]\ncert=%s\n" % ["ab", crafted])
	assert_eq(MwNetKnownHosts.lookup("x", 1), PackedByteArray(), "the known hosts: none")
	MwPlayoffSave.dir = DIR
	_write(MwPlayoffSave.path(1).get_file(), "[save]\nversion=1\ntime=%s\n" % crafted)
	assert_eq(MwPlayoffSave.info(1), {}, "a playoff save: empty")
	assert_eq(Marker.made, 0, "nothing was made while reading")
