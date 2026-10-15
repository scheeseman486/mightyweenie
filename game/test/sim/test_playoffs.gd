extends "res://test/rom/rom_test_base.gd"
## MwPlayoffs against the original (compare/fixtures/playoffs.json, from
## GPGX: mw_harness playoff-vectors): new runs and their bracket, passwords
## typed into the original and the one it showed; the series rules.

var _cases: Dictionary


func before_all() -> void:
	super.before_all()
	_cases = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/playoffs.json")))["cases"]


## The original's 21 state bytes as an MwPlayoffs.
static func _from_ram(hex: String) -> MwPlayoffs:
	var b := hex.hex_decode()
	var playoffs := MwPlayoffs.new()
	playoffs.rng.state = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
	playoffs.dead = PackedInt32Array([(b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7],
			(b[8] << 24) | (b[9] << 16) | (b[10] << 8) | b[11]])
	playoffs.seed = (b[12] << 8) | b[13]
	playoffs.pair = b[14]
	playoffs.conference = b[15]
	playoffs.best_of_3 = b[16]
	playoffs.flag_11 = b[17]
	playoffs.series = b[18]
	playoffs.round = b[19]
	playoffs.flags = b[20]
	return playoffs


func _check_bracket(case: Dictionary, want: MwPlayoffs, tag: String) -> void:
	var playoffs := MwPlayoffs.new()
	playoffs.seed = want.seed
	playoffs.flag_11 = want.flag_11
	playoffs.round = want.round
	playoffs.reseed()
	var t := want.teams()
	playoffs.build_bracket(rom, t.x, t.y)
	var got := []
	for side in 2:
		got.append_array(Array(playoffs.sides[side]))
	assert_eq(got, case["bracket"].map(func(x: Variant) -> int: return int(x)), tag + ": bracket and results")
	assert_eq(playoffs.rng.state, want.rng.state, tag + ": stream after")
	var g := playoffs.game_teams()
	assert_eq([g.x, g.y], case["teams"].map(func(x: Variant) -> int: return int(x)), tag + ": the round's teams")


func test_new_run_from_the_main_menu() -> void:
	if not need_rom():
		return
	var case: Dictionary = _cases["new_run"]
	var want := _from_ram(case["state"])
	_check_bracket(case, want, "new run")
	var setup := MwMatchSetup.new()
	setup.play_mode = 1
	setup.team_a = 0
	setup.team_b = 5
	var main := MlhRng.new(193114104)        # the original's main stream before Start (GPGX)
	var playoffs := MwPlayoffs.new()
	playoffs.start(setup, main)
	assert_eq([playoffs.seed, playoffs.pair, playoffs.round, playoffs.flags, playoffs.best_of_3],
			[want.seed, want.pair, want.round, want.flags, want.best_of_3])


func test_a_rerolls_the_bracket() -> void:
	if not need_rom():
		return
	var case: Dictionary = _cases["reroll"]
	_check_bracket(case, _from_ram(case["state"]), "re-rolled")


func test_typed_passwords() -> void:
	if not need_rom():
		return
	for case_name in ["typed_best_of_3", "typed_single"]:
		var case: Dictionary = _cases[case_name]
		var want := _from_ram(case["state"])
		var pw := PackedByteArray()
		for i in case["typed"]:
			pw.append(rom[MwPlayoffs.ALPHABET + int(i)])
		var playoffs := MwPlayoffs.new()
		assert_true(playoffs.enter_password(rom, pw), case_name + " accepted")
		assert_eq([playoffs.dead[0], playoffs.dead[1], playoffs.seed, playoffs.pair, playoffs.conference,
				playoffs.best_of_3, playoffs.flag_11, playoffs.series, playoffs.round],
				[want.dead[0], want.dead[1], want.seed, want.pair, want.conference, want.best_of_3, want.flag_11,
				want.series, want.round], case_name)
		_check_bracket(case, want, case_name)


func test_shown_password() -> void:
	if not need_rom():
		return
	var case: Dictionary = _cases["shown"]
	var poked := _from_ram(case["poke"])
	var pw := poked.make_password(rom, 0, 0, 0)
	var indices := []
	for c in pw:
		for j in 28:
			if rom[MwPlayoffs.ALPHABET + j] == c:
				indices.append(j)
	assert_eq(indices, case["password"].map(func(x: Variant) -> int: return int(x)))
	assert_eq(poked.dead[1], _from_ram(case["state"]).dead[1], "check value")
	assert_eq(poked.flags, _from_ram(case["state"]).flags)
	var playoffs := MwPlayoffs.new()
	assert_true(playoffs.enter_password(rom, pw), "our decoder takes it")
	playoffs.pair = 66
	assert_false(MwPlayoffs.new().enter_password(rom, playoffs.make_password(rom, 0, 0, 0)), "A and B the same team")


func test_series_rules() -> void:
	var best_of_three := MwPlayoffs.new()
	best_of_three.best_of_3 = 1
	best_of_three.round = MwPlayoffs.FIRST_ROUND
	assert_eq(best_of_three.game_over(false), MwPlayoffs.Result.LOST_GAME)
	assert_eq(best_of_three.game_over(true), MwPlayoffs.Result.NEXT_GAME, "1-1: game 3")
	assert_eq(best_of_three.series, 3)
	assert_eq(best_of_three.game_over(true), MwPlayoffs.Result.NEXT_GAME, "won game 3: next round")
	assert_eq([best_of_three.series, best_of_three.round], [0, 0])
	assert_eq(best_of_three.game_over(true), MwPlayoffs.Result.NEXT_GAME)
	assert_eq(best_of_three.game_over(true), MwPlayoffs.Result.WON_SERIES, "2-0")
	assert_eq(best_of_three.round, 1)
	best_of_three.round = MwPlayoffs.CUP_FINAL
	best_of_three.game_over(true)
	assert_eq(best_of_three.game_over(true), MwPlayoffs.Result.CHAMPION)
	assert_true(best_of_three.flags & MwPlayoffs.CHAMPION != 0)
	var playoffs := MwPlayoffs.new()
	assert_eq(playoffs.game_over(false), MwPlayoffs.Result.ELIMINATED, "single games: one loss")
	assert_true(playoffs.flags & MwPlayoffs.ELIMINATED != 0 and playoffs.flags & MwPlayoffs.SHOW_PASSWORD == 0)
