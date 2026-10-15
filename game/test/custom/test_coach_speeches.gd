extends "res://test/rom/rom_test_base.gd"
## A custom coach's own speeches (CREATE-A-TEAM's SPEECHES; owner,
## 2026-10-14: speeches could not be written or changed): the lines as
## kept (team names as tokens), their JSON, the overlay's quote sets the
## rink reads them through, and a rink speech saying one of them. Tests
## build their own lines (port text); the original's lines are only read.

## Port text: lines of the tests' own.
const OWN := ["#THEM can't stop us!", "Another one for the #US."]


func before_all() -> void:
	MwCustomTeams.clear()
	super.before_all()


func after_each() -> void:
	MwCustomTeams.clear()


func _plain() -> PackedByteArray:
	return MwRom.archive().bytes()


## A copy of original team [param t] with [param speeches], shown to the
## game (custom id 23); the view.
func _view_with(t: int, speeches: Dictionary, colours := false) -> PackedByteArray:
	var team := MwCustomTeam.from_original(_plain(), t)
	team.coach.speeches = speeches
	if colours:
		team.coach.colours = PackedInt32Array([0x00E, 0x00A, 0x0E0, 0x0A0, 0xACE, 0x68A, 0x222])
	team.validate(_plain())
	MwCustomTeams.teams.append(team)
	MwCustomTeams.rebuild()
	return MwRom.data()


func test_situations_cover_the_rinks_speeches() -> void:
	var seen := {}
	for i in MwCoachSpeeches.OCCASIONS.size():
		assert_eq(MwCoachSpeeches.category_of(i), i, "the occasions in the rink's categories' order")
		for st: Array in MwCoachSpeeches.situations_of(i):
			var k := MwCoachSpeeches.key(i, int(st[0]))
			assert_true(MwCoachSpeeches.valid_key(k), k)
			assert_false(seen.has(k), "%s once" % k)
			seen[k] = true
			assert_ne(MwCoachSpeeches.label(i, int(st[0])), "")
	assert_eq(seen.size(), MwCoachSpeeches.situation_count())
	assert_eq(seen.size(), 32, "every situation the rink asks for (a goal's 4 never is)")
	assert_false(seen.has("7.4"))
	for k in ["8.0", "7.7", "2.5", "-1.0", "x", "1", "1.0.0"]:
		assert_false(MwCoachSpeeches.valid_key(k), k)


func test_tokens_are_the_quote_codes() -> void:
	assert_eq(MwCoachSpeeches.clean_line("  the #them's  goalie,   #usfull and #Us  "),
			"the #THEM's goalie, #USFULL and #US", "tokens in capitals however typed, one space apart")
	assert_eq(MwCoachSpeeches.to_codes("the #THEM's goalie, #USFULL and #US"), "the }'s goalie, [ and {")
	assert_eq(MwCoachSpeeches.from_codes("the }'s goalie, [ and {@"), "the #THEM's goalie, #USFULL and #US")
	assert_eq(MwCoachSpeeches.clean_line("no <codes> [here] {or} $there^"), "no codes here or there",
			"nothing the fonts lack, no quote code")
	assert_eq(MwCoachSpeeches.clean_line("x".repeat(400)).length(), MwCoachSpeeches.LINE_MAX)
	var shown := MwCoachSpeeches.expanded("The #THEM's goalie fears the #US of #USFULL.", "Hounds", "Hell", "Bots")
	assert_eq(shown.get_string_from_ascii(), "The Bots' goalie fears the Hounds of Hell Hounds.",
			"the names filled in, the port's possessive")


func test_every_original_line_reads_back_as_its_codes() -> void:
	if not need_rom():
		return
	var plain := _plain()
	var n := 0
	for c in MwCoachSpeeches.SITUATIONS.size():
		for st in int(MwCoachSpeeches.SITUATIONS[c]):
			for style in 8:
				var t := MwQuotes.set_at(plain, c, st, style)
				var lines := MwCoachSpeeches.original_lines(plain, c, st, style)
				assert_eq(lines.size(), MwQuotes.strings(plain, t).size())
				assert_true(lines.size() <= MwCoachSpeeches.LINES_MAX, "%d.%d/%d: room for them all" % [c, st, style])
				for i in lines.size():
					var text := MwGfx.rom_string(plain, MwQuotes.strings(plain, t)[i]).get_string_from_ascii()
					while text.contains("  "):
						text = text.replace("  ", " ")
					assert_true(lines[i].length() < MwCoachSpeeches.LINE_MAX, "%d.%d/%d line %d" % [c, st, style, i])
					assert_eq(MwCoachSpeeches.to_codes(lines[i]), text.strip_edges(),
							"%d.%d/%d line %d: kept whole" % [c, st, style, i])
					n += 1
	assert_gt(n, 100)


func test_validate_keeps_the_rinks_situations_and_clean_lines() -> void:
	var v := MwCoachSpeeches.validate({"7.3": ["  a  line ", "", "<>"], "7.4": ["the goal the rink never asks for"],
			"9.0": ["x"], "x": ["y"], 3: ["z"], "0.0": ["1", "2", "3", "4", "5", "6", "7"], "6.0": []})
	assert_eq(v.keys(), ["7.3", "0.0"])
	assert_eq(v["7.3"], PackedStringArray(["a line"]))
	assert_eq(v["0.0"].size(), MwCoachSpeeches.LINES_MAX)
	var coach := MwCustomCoach.new()
	coach.speeches = {"6.0": PackedStringArray(["one", "two"])}
	assert_eq(MwCoachSpeeches.own_count(coach), 1)
	assert_eq(MwCoachSpeeches.own_count(coach, 6), 1)
	assert_eq(MwCoachSpeeches.own_count(coach, 7), 0)


func test_speeches_round_trip_through_json() -> void:
	if not need_rom():
		return
	var team := MwCustomTeam.from_original(_plain(), 5)
	assert_false(team.to_dict()["coach"].has("speeches"), "none of his own: no key (older files read the same)")
	team.coach.speeches = {"7.3": PackedStringArray(OWN), "3.0": PackedStringArray(["We go on."])}
	team.validate(_plain())
	var text := JSON.stringify(team.to_dict())
	var back := MwCustomTeam.from_dict(_plain(), JSON.parse_string(text))
	assert_eq(back.coach.speeches.size(), 2)
	assert_eq(back.coach.speeches["7.3"], PackedStringArray(OWN))
	assert_eq(JSON.stringify(back.to_dict()), text)
	# a file's own nonsense comes out valid
	var d: Dictionary = JSON.parse_string(text)
	d["coach"]["speeches"] = {"7.3": "not a list", "1.1": ["", "three", "  four  ", null], "99.0": ["no"],
			"7.4": ["no"]}
	var odd := MwCustomTeam.from_dict(_plain(), d)
	assert_eq(odd.coach.speeches.keys(), ["1.1"])
	assert_eq(odd.coach.speeches["1.1"], PackedStringArray(["three", "four"]))


func test_the_overlay_holds_his_own_sets() -> void:
	if not need_rom():
		return
	var v := _view_with(3, {"7.3": PackedStringArray(OWN)})
	var coach := MwTeams.coach(v, 23)
	var style := MwGfx.u16(v, MwCustomTeams.coach_entry(v, coach) + 8)
	var own := MwCustomOverlay.coach_speech_set(v, coach, 7, 3)
	assert_ne(own, 0, "his hat trick set")
	assert_true(MwCustomOverlay.is_custom(own))
	assert_eq(MwQuotes.coach_set_at(v, 7, 3, style, coach), own)
	assert_eq(MwQuotes.value_of(v, own), MwQuotes.value_of(v, MwQuotes.set_at(v, 7, 3, style)),
			"the base set's value word: the portrait talks as it did")
	var strings := MwQuotes.strings(v, own)
	assert_eq(strings.size(), 2)
	for i in 2:
		assert_eq(MwGfx.rom_string(v, strings[i]).get_string_from_ascii(), MwCoachSpeeches.to_codes(OWN[i]))
	for cs in [[7, 0], [0, 1], [6, 0], [7, 4]]:
		assert_eq(MwCustomOverlay.coach_speech_set(v, coach, cs[0], cs[1]), 0, "%s: the original's" % [cs])
		assert_eq(MwQuotes.coach_set_at(v, cs[0], cs[1], style, coach), MwQuotes.set_at(v, cs[0], cs[1], style))
	for cs in [[8, 0], [7, 7], [-1, 0], [3, 1]]:
		assert_eq(MwCustomOverlay.coach_speech_set(v, coach, cs[0], cs[1]), 0, "%s: no such situation" % [cs])
	assert_true(MwCustomOverlay.coach_colours(v, coach).is_empty(), "speeches aren't colours")
	for t in 23:
		assert_eq(MwCustomOverlay.coach_speech_set(v, MwTeams.coach(v, t), 7, 3), 0, "team %d: the original's" % t)


func test_colours_and_speeches_together() -> void:
	if not need_rom():
		return
	var v := _view_with(8, {"6.0": PackedStringArray(["Sit down, #US."])}, true)
	var coach := MwTeams.coach(v, 23)
	assert_eq(MwCustomOverlay.coach_colours(v, coach).size(), 7)
	assert_ne(MwCustomOverlay.coach_speech_set(v, coach, 6, 0), 0)
	MwCustomTeams.clear()
	v = _view_with(8, {}, true)
	coach = MwTeams.coach(v, 23)
	assert_eq(MwCustomOverlay.coach_colours(v, coach).size(), 7)
	assert_eq(MwCustomOverlay.coach_speech_set(v, coach, 6, 0), 0, "colours alone: no table read")


func test_a_broken_table_is_none() -> void:
	if not need_rom():
		return
	var v := _view_with(3, {"7.3": PackedStringArray(OWN)})
	var coach := MwTeams.coach(v, 23)
	var table := MwGfx.u32(v, coach + MwCustomOverlay.COACH_SPEECHES)
	var bad := v.duplicate()
	MwGfx.put_u32(bad, coach + MwCustomOverlay.COACH_SPEECHES, v.size() + 0x100)
	assert_eq(MwCustomOverlay.coach_speech_set(bad, coach, 7, 3), 0, "a table past the view")
	bad = v.duplicate()
	var set_ptr := MwGfx.u32(v, MwGfx.u32(v, table + 4 * 7) + 4 * 3)
	MwGfx.put_u16(bad, set_ptr + 2, 200)
	assert_eq(MwCustomOverlay.coach_speech_set(bad, coach, 7, 3), 0, "a count past the most")
	bad = v.duplicate()
	MwGfx.put_u32(bad, set_ptr + 4, 0x100)
	assert_eq(MwCustomOverlay.coach_speech_set(bad, coach, 7, 3), 0, "a line outside the view")
	bad = v.duplicate()
	MwGfx.put_u16(bad, coach + MwCustomOverlay.COACH_COLOURS, 0)
	assert_eq(MwCustomOverlay.coach_speech_set(bad, coach, 7, 3), 0, "no flag (a view from before): no table")


func test_a_rink_speech_says_his_own_lines() -> void:
	if not need_rom():
		return
	var v := _view_with(3, {"7.3": PackedStringArray([OWN[0]]), "6.0": PackedStringArray(OWN)})
	var s := MwRinkState.new()
	s.rng = MlhRng.new(1234)
	var sim := MwRinkSim.new(v, s)
	MwRinkMatch.start(sim, 9, 23, 9, 0, false, 2)
	var phases := MwRinkPhases.new(MwRinkUpdate.new(sim))
	var team := s.teams[0]
	var other := s.teams[1]
	var coach := MwGfx.u32(v, team.record + MwTeams.COACH)
	var style := MwGfx.u16(v, MwCustomTeams.coach_entry(v, coach) + 8)
	var them := MwGfx.rom_string(v, MwGfx.u32(v, other.record + 4)).get_string_from_ascii()
	phases._quote(style, 7, 3, team, other)
	var said := s.quote.slice(0, s.quote.find(0)).get_string_from_ascii()
	assert_eq(said, OWN[0].replace("#THEM", them), "one line: it, with the names")
	assert_eq(s.quote_value, MwQuotes.value_of(v, MwQuotes.set_at(v, 7, 3, style)))
	var heard := {}
	for k in 40:
		phases._quote(style, 6, 0, team, other)
		heard[s.quote.slice(0, s.quote.find(0)).get_string_from_ascii()] = true
	assert_eq(heard.size(), 2, "two lines: picked as the original picks among its")
	var base := MwQuotes.strings(v, MwQuotes.set_at(v, 7, 0, style))
	phases._quote(style, 7, 0, team, other)
	var plain := s.quote.slice(0, s.quote.find(0))
	var originals := []
	for a in base:
		originals.append(MwQuotes.expand(MwGfx.rom_string(v, a), MwQuotes.fields(v, team.record, other.record)))
	assert_true(plain in originals, "a situation without his own: the original's")


func test_a_coach_with_every_line_travels_online() -> void:
	if not need_rom():
		return
	var team := MwCustomTeam.from_original(_plain(), 6)
	var line := ("#THEM " + "x".repeat(300)).substr(0, MwCoachSpeeches.LINE_MAX)
	for o in MwCoachSpeeches.OCCASIONS.size():
		for st: Array in MwCoachSpeeches.situations_of(o):
			var lines := PackedStringArray()
			for i in MwCoachSpeeches.LINES_MAX:
				lines.append(line)
			team.coach.speeches[MwCoachSpeeches.key(o, int(st[0]))] = lines
	team.validate(_plain())
	assert_eq(MwCoachSpeeches.own_count(team.coach), MwCoachSpeeches.situation_count())
	var d := team.to_dict()
	assert_true(MwPlain.plain_ok(d), "within a carried team's bounds (an online start record's)")
	var carried: Variant = MwCustomTeams.parse_carried({"teams": [d], "playoff": -1})
	assert_true(carried is Array and (carried as Array).size() == 1)
	if carried is Array and (carried as Array).size() == 1:
		var back: MwCustomTeam = carried[0]
		assert_eq(back.coach.speeches.size(), MwCoachSpeeches.situation_count())
		assert_eq(back.coach.speeches["7.6"][4], line)
