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
	var p := MwPlayoffs.new()
	p.rng.state = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
	p.dead = PackedInt32Array([(b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7], (b[8] << 24) | (b[9] << 16) | (b[10] << 8) | b[11]])
	p.seed = (b[12] << 8) | b[13]
	p.pair = b[14]
	p.conference = b[15]
	p.best_of_3 = b[16]
	p.flag_11 = b[17]
	p.series = b[18]
	p.round = b[19]
	p.flags = b[20]
	return p


func _check_bracket(case: Dictionary, want: MwPlayoffs, tag: String) -> void:
	var p := MwPlayoffs.new()
	p.seed = want.seed
	p.flag_11 = want.flag_11
	p.round = want.round
	p.reseed()
	var t := want.teams()
	p.build_bracket(rom, t.x, t.y)
	var got := []
	for side in 2:
		got.append_array(Array(p.sides[side]))
	assert_eq(got, case["bracket"].map(func(x: Variant) -> int: return int(x)), tag + ": bracket and results")
	assert_eq(p.rng.state, want.rng.state, tag + ": stream after")
	var g := p.game_teams()
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
	var p := MwPlayoffs.new()
	p.start(setup, main)
	assert_eq([p.seed, p.pair, p.round, p.flags, p.best_of_3], [want.seed, want.pair, want.round, want.flags, want.best_of_3])


func test_a_rerolls_the_bracket() -> void:
	if not need_rom():
		return
	var case: Dictionary = _cases["reroll"]
	_check_bracket(case, _from_ram(case["state"]), "re-rolled")


func test_typed_passwords() -> void:
	if not need_rom():
		return
	for name in ["typed_best_of_3", "typed_single"]:
		var case: Dictionary = _cases[name]
		var want := _from_ram(case["state"])
		var pw := PackedByteArray()
		for i in case["typed"]:
			pw.append(rom[MwPlayoffs.ALPHABET + int(i)])
		var p := MwPlayoffs.new()
		assert_true(p.enter_password(rom, pw), name + " accepted")
		assert_eq([p.dead[0], p.dead[1], p.seed, p.pair, p.conference, p.best_of_3, p.flag_11, p.series, p.round],
				[want.dead[0], want.dead[1], want.seed, want.pair, want.conference, want.best_of_3, want.flag_11, want.series, want.round], name)
		_check_bracket(case, want, name)


func test_shown_password() -> void:
	if not need_rom():
		return
	var case: Dictionary = _cases["shown"]
	var p := _from_ram(case["poke"])
	var pw := p.make_password(rom, 0, 0, 0)
	var idx := []
	for c in pw:
		for j in 28:
			if rom[MwPlayoffs.ALPHABET + j] == c:
				idx.append(j)
	assert_eq(idx, case["password"].map(func(x: Variant) -> int: return int(x)))
	assert_eq(p.dead[1], _from_ram(case["state"]).dead[1], "check value")
	assert_eq(p.flags, _from_ram(case["state"]).flags)
	var q := MwPlayoffs.new()
	assert_true(q.enter_password(rom, pw), "our decoder takes it")
	q.pair = 66
	assert_false(MwPlayoffs.new().enter_password(rom, q.make_password(rom, 0, 0, 0)), "A and B the same team")


func test_series_rules() -> void:
	var p := MwPlayoffs.new()
	p.best_of_3 = 1
	p.round = MwPlayoffs.FIRST_ROUND
	assert_eq(p.game_over(false), MwPlayoffs.Result.LOST_GAME)
	assert_eq(p.game_over(true), MwPlayoffs.Result.NEXT_GAME, "1-1: game 3")
	assert_eq(p.series, 3)
	assert_eq(p.game_over(true), MwPlayoffs.Result.NEXT_GAME, "won game 3: next round")
	assert_eq([p.series, p.round], [0, 0])
	assert_eq(p.game_over(true), MwPlayoffs.Result.NEXT_GAME)
	assert_eq(p.game_over(true), MwPlayoffs.Result.WON_SERIES, "2-0")
	assert_eq(p.round, 1)
	p.round = MwPlayoffs.CUP_FINAL
	p.game_over(true)
	assert_eq(p.game_over(true), MwPlayoffs.Result.CHAMPION)
	assert_true(p.flags & MwPlayoffs.CHAMPION != 0)
	var q := MwPlayoffs.new()
	assert_eq(q.game_over(false), MwPlayoffs.Result.ELIMINATED, "single games: one loss")
	assert_true(q.flags & MwPlayoffs.ELIMINATED != 0 and q.flags & MwPlayoffs.SHOW_PASSWORD == 0)
