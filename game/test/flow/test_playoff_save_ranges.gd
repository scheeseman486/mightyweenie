extends GutTest
## Plan 45 (L1): a playoff save carries the run's 21 bytes and the setup's
## 10 whole - more than a password, whose decoder (`$1266C`) only makes
## fields of its widths - so a save is taken only when every field is one
## the original's password and game setup can make; its other values are
## read through MwPlain.

const DIR := "user://test/playoff_save_ranges"

var _dir := ""


func before_each() -> void:
	_dir = MwPlayoffSave.dir
	MwPlayoffSave.dir = DIR


func after_each() -> void:
	for slot in MwPlayoffSave.slots():
		MwPlayoffSave.delete(slot)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	MwPlayoffSave.dir = _dir


## A run as the game makes one: first round over, teams 3 and 7, a random
## opponent's dead (the check value), the password shown.
static func _run() -> MwPlayoffs:
	var playoffs := MwPlayoffs.new()
	playoffs.rng.state = 0x12345678
	playoffs.seed = 0x102
	playoffs.pair = 37
	playoffs.dead = PackedInt32Array([0x15, 0x2E37C])
	playoffs.flags = MwPlayoffs.SHOW_PASSWORD | MwPlayoffs.RANDOM_DEAD
	return playoffs


static func _setup() -> MwMatchSetup:
	return MwMatchSetup.from_bytes(PackedByteArray([3, 7, 0, 1, 1, 5, 22, 0, 0, 0]))


func test_the_games_own_runs_are_taken() -> void:
	assert_true(MwPlayoffSave.valid(_setup().to_bytes(), _run().to_bytes(), false))
	var best_of_3 := _run()
	best_of_3.best_of_3 = 1
	best_of_3.series = 3
	best_of_3.round = 0
	best_of_3.conference = 1
	best_of_3.flag_11 = 1
	assert_true(MwPlayoffSave.valid(_setup().to_bytes(), best_of_3.to_bytes(), false))
	var custom := _setup()
	custom.team_a = 30
	custom.stadium = 30
	assert_true(MwPlayoffSave.valid(custom.to_bytes(), _run().to_bytes(), true), "a custom team's, under its id")
	assert_false(MwPlayoffSave.valid(custom.to_bytes(), _run().to_bytes(), false), "... named by the save only")


func test_a_field_past_the_passwords_widths_is_refused() -> void:
	var changes := {"seed": 0x1000, "pair": 100, "conference": 2, "best_of_3": 2, "flag_11": 2, "series": 4,
			"round": 4, "flags": 0x20}
	for field: String in changes:
		var playoffs := _run()
		playoffs.set(field, changes[field])
		assert_false(MwPlayoffSave.valid(_setup().to_bytes(), playoffs.to_bytes(), false), field)
	var same := _run()
	same.pair = 33
	assert_false(MwPlayoffSave.valid(_setup().to_bytes(), same.to_bytes(), false), "a team against itself")
	for t in 2:
		var dead := _run()
		dead.dead[t] = 1 << 18
		assert_false(MwPlayoffSave.valid(_setup().to_bytes(), dead.to_bytes(), false), "dead %d" % t)


func test_a_setup_past_the_menus_is_refused() -> void:
	var changes := {"team_a": 20, "team_b": 20, "pads": 5, "play_mode": 5, "period_index": 3, "stadium": 23,
			"penalties": 2, "reserves": 2, "death_index": 5}
	for field: String in changes:
		var su := _setup()
		su.set(field, changes[field])
		assert_false(MwPlayoffSave.valid(su.to_bytes(), _run().to_bytes(), false), field)


func test_the_list_reads_a_damaged_save_as_empty() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "version", MwPlayoffSave.VERSION)
	cfg.set_value("save", "time", "yesterday")
	cfg.set_value("save", "setup", _setup().to_bytes().hex_encode())
	cfg.set_value("save", "run", _run().to_bytes().hex_encode())
	cfg.set_value("save", "password", ["not", "text"])
	assert_true(MwUserFile.write_config(cfg, MwPlayoffSave.path(1)))
	var info := MwPlayoffSave.info(1)
	assert_eq([info.get("time"), info.get("password"), info.get("team_a"), info.get("round")], [0, "", 3, 0],
			"wrong types: their defaults")
	var bad := _run()
	bad.round = 7
	cfg.set_value("save", "run", bad.to_bytes().hex_encode())
	MwUserFile.write_config(cfg, MwPlayoffSave.path(2))
	assert_eq(MwPlayoffSave.info(2), {}, "a run the game can't make: empty")
	assert_false(MwPlayoffSave.load_into(MwSession.new(1, 1), 2), "and never loaded")
	cfg.set_value("save", "run", "-" + _run().to_bytes().hex_encode().substr(1))
	MwUserFile.write_config(cfg, MwPlayoffSave.path(3))
	assert_eq(MwPlayoffSave.info(3), {}, "a signed number isn't the run's hex")
