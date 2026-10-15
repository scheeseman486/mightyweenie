extends GutTest
## Plan 40 (I1): the settings' table (MwSettings.SAVED) writes and reads
## settings.cfg as the hand-written code did - the same sections, keys,
## order and text (pinned from plan 38's build; plan 44's two EXTENDED
## switches after TICK RATE, its CAMERA by name as ever; 2026-10-15's REPLAY
## BLOOD after REPLAY LENGTH) - and every row is
## a setting the options and the match rules step and show alike.

const EXPECTED := """[game]

camera="3D EXTENDED"
replay_length="ORIGINAL"
replay_paint=false
character_select="5+ PLAYERS"
captain_mode="5+ PLAYERS"
lineup_select=true
tick_rate="ORIGINAL"
extended_penalties=false
extended_cpu=false

[audio]

enhance=true

[display]

fullscreen=false
aspect="WIDE"
blood=false
ice_detail=true
reflections=true

[controls]

analogue=true
shot_heights=false
layout_p2="GENESIS"

[net]

port=12345
address="host.example:7"
"""

var _path_was := ""


func before_each() -> void:
	_path_was = MwSettings.path
	MwSettings.path = "user://test/settings_file.cfg"
	MwSettings.load_file()


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwSettings.path))
	MwSettings.path = _path_was
	MwSettings.load_file()


func test_the_file_is_as_it_was() -> void:
	MwSettings.camera = MwSettings.CAMERAS.find("3D EXTENDED")
	MwSettings.aspect = "WIDE"
	MwSettings.tick_rate = "ORIGINAL"
	MwSettings.net_port = 12345
	MwSettings.net_address = "host.example:7"
	MwSettings.blood = false
	MwSettings.replay_length = "ORIGINAL"
	MwSettings.layouts = {2: "GENESIS"}
	MwSettings.save()
	assert_eq(FileAccess.get_file_as_string(MwSettings.path), EXPECTED)
	MwSettings.camera = 0
	MwSettings.aspect = "ORIGINAL"
	MwSettings.load_file()
	assert_eq([MwSettings.camera, MwSettings.aspect, MwSettings.tick_rate, MwSettings.net_port, MwSettings.blood],
			[MwSettings.CAMERAS.find("3D EXTENDED"), "WIDE", "ORIGINAL", 12345, false], "read back")


func test_bad_values_read_as_the_defaults() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "camera", "NOPE")
	cfg.set_value("display", "aspect", 7)
	cfg.set_value("net", "port", 70000)
	cfg.set_value("net", "address", ["x"])
	cfg.set_value("game", "tick_rate", "FAST")
	cfg.save(MwSettings.path)
	MwSettings.load_file()
	assert_eq([MwSettings.camera, MwSettings.aspect, MwSettings.net_port, MwSettings.net_address, MwSettings.tick_rate],
			[0, "ORIGINAL", MwNetProtocol.PORT, "", "OVERCLOCKED"])


func test_every_row_steps_and_shows() -> void:
	var sc: GDScript = MwSettings
	for setting_name: String in MwSettings.SAVED:
		var row: Array = MwSettings.SAVED[setting_name]
		assert_eq(row.size(), 4, setting_name)
		assert_eq(typeof(sc.get(setting_name)), typeof(row[2]), setting_name + ": a setting of the row's type")
		if setting_name in ["net_port", "net_address", "fullscreen"]:
			continue                         # (not steppable here: the window; no options row for the net)
		var was: Variant = sc.get(setting_name)
		var shown := MwSettings.text(setting_name)
		MwSettings.step(setting_name, 1)
		assert_ne(MwSettings.text(setting_name), shown, setting_name + " changed")
		MwSettings.step(setting_name, -1)
		assert_eq(sc.get(setting_name), was, setting_name + " back")
	for k in MwSettings.MATCH_RULES:
		if MwSettings.SAVED.has(k):
			assert_eq(MwSettings.match_rules()[k], sc.get(k), k + ": the rule is the setting")
