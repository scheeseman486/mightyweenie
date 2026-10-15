extends "res://test/rom/rom_test_base.gd"
## The port's manual-forfeit lines (plan 26): FORFEIT on the port's pause
## menu marks the state ([member MwRinkState.forfeit_manual]); screen 17's
## referee then says one of [constant MwQuotes.MANUAL_FORFEIT] with the
## team names filled in - and only then (the original's forfeit keeps the
## ROM's set); the main random stream moves the same either way; every line
## fits the speech box and the quote buffer with every pair of teams; a
## name ending in "s" takes "'" for "'s" in the port's lines only.

var sim: MwRinkSim
var s: MwRinkState
var _sb: MwMessageScoreboardSim
const NONE := [0, 0, 0, 0]


## CPU players that stay put (plan 40: test/support/idle_cpu.gd).
const Idle := preload("res://test/support/idle_cpu.gd")


func before_each() -> void:
	if rom.is_empty():
		return
	s = MwRinkState.new()
	s.rng = MlhRng.new(1234)
	sim = MwRinkSim.new(rom, s)
	sim.cpu = Idle.new()
	MwRinkMatch.start(sim, 4, 9, 4, 0, false, 2)
	s.period_minutes = 3
	s.clock = 150
	var phases := MwRinkPhases.new(MwRinkUpdate.new(sim))
	phases.enter(5)                          # everyone lined up
	s.tick = 1000


## Screen 17 entered after a forfeit by [param forfeiter] (0 team A, 1 team
## B; [param manual]: from the pause menu), the main stream seeded with
## [param seed_value]; its first pass run (the referee's message set up).
func _forfeit_message(forfeiter: int, manual: bool, seed_value: int) -> MwMessageScoreboardSim:
	s.phase = MwRinkMatch.PHASE_FORFEIT
	s.scoring = 0xFFFF0000 | int(MwScoreboardSim.TEAM_WORDS[forfeiter])
	s.forfeit_manual = manual
	s.rng = MlhRng.new((seed_value * 0x9E3779B1) & 0xFFFFFFFF)   # spread: small states pick low
	s.rng.warm_up()
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 5)
	s.tick += 1
	sb.begin_pass()
	sb.step(1, NONE, NONE)
	return sb


func _quote_text() -> String:
	return s.quote.slice(0, s.quote.find(0)).get_string_from_ascii()


func _text_at(at: int) -> String:
	return MwGfx.rom_string(rom, at).get_string_from_ascii()


## [param line] as the referee says it: `[` the forfeiting team's city and
## name, `{` its name, `}` the winner's name; a name ending in "s" takes
## "'" for "'s".
func _said(line: String, forfeiter: MwRinkState.Team, winner: MwRinkState.Team) -> String:
	var team_name := _text_at(MwGfx.u32(rom, forfeiter.record + 4))
	var codes := {
		"[": _text_at(MwGfx.u32(rom, forfeiter.record)) + " " + team_name,
		"{": team_name,
		"}": _text_at(MwGfx.u32(rom, winner.record + 4)),
	}
	for c: String in codes:
		var v: String = codes[c]
		if v.ends_with("s"):
			line = line.replace(c + "'s", v + "'")
		line = line.replace(c, v)
	return line


func test_manual_forfeit_says_the_port_lines() -> void:
	if not need_rom():
		return
	for forfeiter in 2:
		var said := MwQuotes.MANUAL_FORFEIT.map(func(l: String) -> String:
			return _said(l, s.teams[forfeiter], s.teams[1 - forfeiter]))
		var seen := {}
		for seed_value in range(1, 41):
			var sb := _forfeit_message(forfeiter, true, seed_value)
			assert_eq(sb.state, 9, "the referee's message")
			assert_eq(sb.team_a3, s.teams[forfeiter], "about the forfeiting team")
			var text := _quote_text()
			assert_has(said, text, "one of the port's lines, names filled in")
			seen[text] = true
		assert_eq(seen.size(), MwQuotes.MANUAL_FORFEIT.size(), "every line comes up")


func test_original_forfeit_keeps_the_rom_lines() -> void:
	if not need_rom():
		return
	assert_false(MwRinkState.new().forfeit_manual, "a new match: not a manual forfeit")
	var said := MwQuotes.MANUAL_FORFEIT.map(func(l: String) -> String:
		return _said(l, s.teams[0], s.teams[1]))
	for seed_value in range(1, 21):
		_forfeit_message(0, false, seed_value)
		assert_ne(_quote_text(), "", "the ROM's forfeit line")
		assert_does_not_have(said, _quote_text(), "never the port's")


func test_new_referee_ignores_the_flag() -> void:
	if not need_rom():
		return
	s.phase = 12
	s.scoring = 0xFFFF0000 | int(MwScoreboardSim.TEAM_WORDS[1])
	s.forfeit_manual = true
	var sb := MwMessageScoreboardSim.new(rom)
	sb.enter(s, 17, 19)
	s.tick += 1
	sb.begin_pass()
	sb.step(1, NONE, NONE)
	var said := MwQuotes.MANUAL_FORFEIT.map(func(l: String) -> String:
		return _said(l, s.teams[1], s.teams[0]))
	assert_does_not_have(said, _quote_text(), "the new referee keeps his own lines")


func test_same_random_draws_as_the_original() -> void:
	if not need_rom():
		return
	for seed_value in [7, 99, 4321]:
		_forfeit_message(1, false, seed_value)
		var original := s.rng.state
		_forfeit_message(1, true, seed_value)
		assert_eq(s.rng.state, original, "the main stream moves as with the ROM's set")


## `$15860`'s layout ([method MwScoreboardSim.print_quote]): words of
## `!`-`~` by the font's glyph widths, a word that doesn't fit starts a new
## line unless the line is empty, spaces by the font's width. Returns the
## lines used, or -1 when the text runs below the box (cut).
func _lines_used(text: PackedByteArray, w: int, h: int) -> int:
	var f := MwScoreboardSim.SPEECH_FONT
	var line := MwGfx.u16(rom, f)
	var l := MwTextBox.layout(rom, f, text, w, h, line)     # plan 40 (D2): the game's own layout
	if l["cut"]:
		return -1
	return int(l["cursor_y"]) / line + 1


func test_every_line_fits_with_every_pair_of_teams() -> void:
	if not need_rom():
		return
	var rect := MwScoreboardSim.rect_at(rom, MwMessageScoreboardSim.SPEECH_RECT)
	var f := MwScoreboardSim.SPEECH_FONT
	var forfeiter := MwRinkState.Team.new()
	var winner := MwRinkState.Team.new()
	for line: String in MwQuotes.MANUAL_FORFEIT:
		for ch in line.to_ascii_buffer():
			if ch != 0x20 and ch != 0x5B and ch != 0x7B and ch != 0x7D:
				assert_true(ch < 0x7F and MwGfx.font_glyph(rom, f, ch) >= 0,
						"the speech font has '%s' (%s)" % [char(ch), line])
		assert_false(line.contains("@"), "no record behind the referee's quote")
		var worst := 0
		for a in MwTeams.COUNT:
			for b in MwTeams.COUNT:
				if a == b:
					continue
				forfeiter.record = MwTeams.record(a)
				winner.record = MwTeams.record(b)
				s.quote.fill(0xFF)
				sim_quote(line, forfeiter, winner)
				var n := s.quote.find(0)
				assert_true(n >= 0 and n < MwRinkState.QUOTE_SIZE, "fits the quote buffer")
				var used := _lines_used(s.quote.slice(0, n), rect[2], rect[3])
				assert_ne(used, -1, "not cut: %s" % s.quote.slice(0, n).get_string_from_ascii())
				worst = maxi(worst, used)
		gut.p("%d lines at most: %s" % [worst, line])


## [method MwScoreboardSim.quote_expand] of [param line] into the state's
## buffer, as the port's lines are (the plural possessive).
func sim_quote(line: String, team: MwRinkState.Team, other: MwRinkState.Team) -> void:
	sim_quote_raw(line, team, other, true)


## [param template] expanded with team A forfeiting [param a] and team B
## [param b] (team indices); [param possessive] as the port's lines.
func _expand(template: String, a: int, b: int, possessive: bool) -> String:
	var ta := MwRinkState.Team.new()
	var tb := MwRinkState.Team.new()
	ta.record = MwTeams.record(a)
	tb.record = MwTeams.record(b)
	s.quote.fill(0xFF)
	sim_quote_raw(template, ta, tb, possessive)
	return s.quote.slice(0, s.quote.find(0)).get_string_from_ascii()


func sim_quote_raw(line: String, team: MwRinkState.Team, other: MwRinkState.Team, possessive: bool) -> void:
	if _sb == null:
		_sb = MwMessageScoreboardSim.new(rom)
	_sb.s = s
	MwScoreboardSim.quote_expand(_sb, line.to_ascii_buffer(), team, other, -1, possessive)


func test_plural_possessive() -> void:
	if not need_rom():
		return
	var s1 := 6                              # teams whose names end in "s"
	var s2 := 4
	var z1 := 8                              # and two whose names don't
	var z2 := 13
	var n1 := _text_at(MwTeams.name(rom, s1))
	var n2 := _text_at(MwTeams.name(rom, s2))
	var m1 := _text_at(MwTeams.name(rom, z1))
	var m2 := _text_at(MwTeams.name(rom, z2))
	var full := _text_at(MwTeams.city(rom, s1)) + " " + n1
	assert_true(n1.ends_with("s") and n2.ends_with("s"), "the cases: names ending in s")
	assert_false(m1.ends_with("s") or m2.ends_with("s"), "and not")
	assert_eq(_expand("all of the {'s players", s1, z1, true), "all of the %s' players" % n1)
	assert_eq(_expand("} won. {'s", s1, s2, true), "%s won. %s'" % [n2, n1], "at the end too")
	assert_eq(_expand("the {'s, the }'s", z1, z2, true), "the %s's, the %s's" % [m1, m2], "no s: kept")
	assert_eq(_expand("[ and ['s bench", s1, z1, true), "%s and %s' bench" % [full, full], "city and name")
	assert_eq(_expand("{'sake", s1, z1, true), "%s'sake" % n1, "not a possessive: kept")
	assert_eq(_expand("bus's {", s1, z1, true), "bus's %s" % n1, "only after a code")
	assert_eq(_expand("all of the {'s players", s1, z1, false), "all of the %s's players" % n1,
			"the ROM's quotes: copied as the original copies them")
