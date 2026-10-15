extends "res://test/rom/rom_test_base.gd"
## CREATE-A-TEAM's data (plan 38): the custom structs, their JSON, the bank
## and the overlay the game reads them through. The original's teams must
## read exactly as before; a copy of one reads as the original wherever the
## copy didn't change anything.

const TEST_DIR := "user://test_custom_teams"


var _dir := ""


func before_all() -> void:
	MwCustomTeams.clear()
	super.before_all()
	_dir = MwCustomTeams.dir                      # (the run's test folder, pre_run.gd: put back after)


func after_each() -> void:
	MwCustomTeams.clear()
	MwCustomTeams.dir = _dir
	var d := DirAccess.open(TEST_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(TEST_DIR)


func _plain() -> PackedByteArray:
	return MwRom.archive().bytes()


func test_no_custom_team_reads_the_rom_alone() -> void:
	if not need_rom():
		return
	assert_eq(MwRom.data().size(), MwCustomOverlay.BASE)
	assert_eq(MwRom.data(), _plain())
	assert_eq(MwTeams.count(), 23)
	for t in 23:
		assert_eq(MwTeams.record(t), 0x18D8A + 0x9E * t)
		assert_eq(MwTeams.id_of(MwTeams.record(t)), t)
	var order := MwCustomTeams.menu_order(_plain())
	for i in 23:
		assert_eq(order[i], _plain()[0x1C1A4 + i], "menu position %d" % i)


func test_every_original_round_trips_through_json() -> void:
	if not need_rom():
		return
	for t in 23:
		var original := MwCustomTeam.from_original(_plain(), t)
		var d := original.to_dict()
		var text := JSON.stringify(d, "\t", false)
		var team := MwCustomTeam.from_dict(_plain(), JSON.parse_string(text))
		assert_eq(JSON.stringify(team.to_dict()), JSON.stringify(d), "team %d" % t)


func test_a_copy_reads_as_its_original() -> void:
	if not need_rom():
		return
	var base := _plain()
	for t in [0, 4, 9, 10, 16, 22]:
		MwCustomTeams.clear()
		var team := MwCustomTeam.from_original(base, t)
		MwCustomTeams.teams.append(team)
		MwCustomTeams.rebuild()
		var v := MwRom.data()
		assert_eq(v.slice(0, MwCustomOverlay.BASE), base, "the ROM's bytes untouched")
		var id := MwCustomTeams.id_of_team(team)
		assert_eq(id, 23)
		var o := MwTeams.record(id)
		var r := MwTeams.record(t)
		assert_true(MwCustomOverlay.is_custom(o))
		assert_eq(MwTeams.id_of(o), id)
		for f in [0, 4]:
			assert_eq(MwGfx.rom_string(v, MwGfx.u32(v, o + f)), MwGfx.rom_string(base, MwGfx.u32(base, r + f)))
		for off in range(0x0B, 0x0C) + range(0x14, 0x17) + range(0x80, 0x88) + range(0x90, 0x96):
			assert_eq(v[o + off], base[r + off], "team %d +%X" % [t, off])
		for slot in 24:
			assert_eq(MwTeams.player(v, id, slot), MwTeams.player(base, t, slot), "slot %d" % slot)
		assert_eq(MwTeams.logo_frame(v, id), MwTeams.logo_frame(base, t))
		assert_eq(MwGfx.words(v, MwTeams.panel_colours(v, id), 7), MwGfx.words(base, MwTeams.panel_colours(base, t), 7))
		for i in 3:
			assert_eq(MwCustomOverlay.special(v, o, i), 9 + i)
		# the coach: name, face, voice, lines
		var oc := MwTeams.coach(v, id)
		var rc := MwTeams.coach(base, t)
		assert_eq(MwGfx.rom_string(v, MwGfx.u32(v, oc)), MwGfx.rom_string(base, MwGfx.u32(base, rc)))
		var od := MwPortrait.coach_data(v, oc)
		var rd := MwPortrait.coach_data(base, rc)
		assert_eq(v.slice(od, od + 10), base.slice(rd, rd + 10), "the coach's portrait data")
		var oe := MwCustomTeams.coach_entry(v, oc)
		var re := MwCustomTeams.coach_entry(base, rc)
		assert_eq(MwGfx.u16(v, oe + 8), MwGfx.u16(base, re + 8) if re != 0 else 0, "the coach's lines")
		assert_eq(MwCustomOverlay.coach_colours(v, oc).size(), 0)
		# the rink: the record from +5 on, the ice colours
		var os := MwRinkState.stadium_record(v, id)
		var rs := MwRinkState.stadium_record(base, t)
		var n := 0xC + 6 * (base[rs + 9] + base[rs + 0xA])
		assert_eq(v[os + 5], base[rs + 5], "stadium %d's net" % t)      # +6, +7 have no reader
		assert_eq(v.slice(os + 8, os + n), base.slice(rs + 8, rs + n), "stadium %d" % t)
		assert_eq(MwPalettes.ice_line(v, id), MwPalettes.ice_line(base, t))
		assert_eq(MwGfx.rom_string(v, MwGfx.u32(v, os)), MwGfx.rom_string(base, MwGfx.u32(base, rs)))


func test_custom_players_copy_records_byte_for_byte() -> void:
	if not need_rom():
		return
	var plain := _plain()
	for t in 23:
		for slot in 24:
			var r := MwTeams.player(plain, t, slot)
			var player := MwCustomPlayer.from_record(plain, r)
			var b := player.record_bytes(MwGfx.u32(plain, r))
			assert_eq(b, plain.slice(r, r + b.size()), "team %d slot %d" % [t, slot])


## Plan 40 (S11): CREATE-A-TEAM's FIT is the game's position rating
## (`$1121E`) of the player's record bytes: every original player rates
## the same from his copy as from the ROM, at every position.
func test_fit_is_the_games_position_rating() -> void:
	if not need_rom():
		return
	var plain := _plain()
	for t in 23:
		for slot in 24:
			var r := MwTeams.player(plain, t, slot)
			var copied := MwCustomPlayer.from_record(plain, r).record_bytes(0)
			for pos in 6:
				assert_eq(MwSimPlayers.position_rating(copied, 0, pos), MwSimPlayers.position_rating(plain, r, pos),
						"team %d slot %d at %d" % [t, slot, pos])
	var player := MwCustomPlayer.new()
	player.side = 1
	var b := player.record_bytes(0)
	assert_eq(MwSimPlayers.position_rating(b, 0, 2) - MwSimPlayers.position_rating(b, 0, 1), 0x14,
			"a right-sided player: the bonus at RW")


func test_custom_stars_and_coaches_in_the_tables() -> void:
	if not need_rom():
		return
	var plain := _plain()
	var team := MwCustomTeam.from_original(plain, 0)
	var star_player := MwCustomPlayer.from_record(plain, MwTeams.player(plain, 0, 1))
	star_player.face = 3
	team.players.append(star_player)
	var player := MwCustomPlayer.from_record(plain, MwTeams.player(plain, 0, 2))
	player.face = -1
	team.players.append(player)
	team.roster[1] = {"player": 0}
	team.roster[2] = {"player": 1}
	team.coach.face = 4
	team.coach.voice = 0x31
	team.coach.style = 6
	team.coach.colours = PackedInt32Array([0x00E, 0x00A, 0x0E0, 0x0A0, 0xE00, 0xA00, 0x444])
	var free := 1
	while free in team.nasty:
		free += 1
	team.specials = PackedInt32Array([free, 9, 11])
	team.validate(plain)
	MwCustomTeams.teams.append(team)
	MwCustomTeams.rebuild()
	var v := MwRom.data()
	var id := 23
	var star := MwPortrait.star_entry(v, MwTeams.player(v, id, 1))
	assert_ne(star, 0)
	assert_eq(MwGfx.u32(v, star + 4), MwCustomTeams.player_faces(plain)[3][0])
	assert_eq(MwPortrait.star_entry(v, MwTeams.player(v, id, 2)), 0, "his species' face: no star entry")
	var coach := MwTeams.coach(v, id)
	var data := MwPortrait.coach_data(v, coach)
	var face: int = MwCustomTeams.coach_faces(plain)[4]
	assert_eq(MwGfx.u32(v, data), MwGfx.u32(plain, face), "the face's talking")
	assert_eq(MwGfx.u16(v, data + 8), 0x31, "his own voice")
	assert_eq(MwGfx.u16(v, MwCustomTeams.coach_entry(v, coach) + 8), 6)
	assert_eq(MwCustomOverlay.coach_colours(v, coach), team.coach.colours)
	assert_eq(team.specials[1], 10, "slot 2 is always Waste the Ref")
	assert_eq(MwCustomOverlay.special(v, MwTeams.record(id), 0), free)
	assert_eq(MwCustomOverlay.special(v, MwTeams.record(id), 2), 11)
	# the coach's colours on his face's line
	var pal := RomPalette.make(2, PackedStringArray(["screen_palette", "coach_colours a 1"]), id, id)
	var cols := pal.colours()
	for i in 7:
		assert_eq(cols[16 + MwCustomCoach.COLOUR_INDICES[i]], team.coach.colours[i])


func test_validation() -> void:
	if not need_rom():
		return
	var plain := _plain()
	var team := MwCustomTeam.from_original(plain, 3)
	team.city = "A very long city name {with codes}"
	team.nasty = PackedInt32Array([5, 5, 10])
	team.specials = PackedInt32Array([5, 9, 5])
	team.skulls = 9
	team.roster[0] = team.roster[5]            # a goalie at centre
	team.roster[7] = team.roster[8]            # somebody twice
	team.rink.hazards = [{"kind": "pit", "x": 0, "y": 0}, {"kind": "mine", "x": 0, "y": 200},
			{"kind": "worm", "x": 0, "y": -200}]
	team.validate(plain)
	assert_eq(team.city, "A very lon")
	assert_eq(team.skulls, 6)
	assert_eq(team.specials[1], 10)
	var plays := Array(team.nasty) + Array(team.specials)
	for v in plays:
		assert_eq(plays.count(v), 1, "play %d once" % v)
	for v in team.nasty:
		assert_between(v, 1, 8)
	var seen := {}
	for slot in 24:
		var entry := team.roster[slot]
		var rec := MwTeams.player(plain, int(entry["team"]), int(entry["slot"]))
		assert_eq((plain[rec + 7] & 0x0F) == 4, slot % 6 == 5, "slot %d" % slot)
		assert_false(seen.has(rec), "slot %d twice" % slot)
		seen[rec] = true
	assert_eq(team.rink.hazards.size(), 1, "the centre spot is kept clear, unknown kinds dropped")
	assert_eq(team.rink.hazards[0]["kind"], "mine")


func test_original_hazards_are_clear_of_the_zones() -> void:
	if not need_rom():
		return
	for t in 23:
		var custom_rink := MwCustomRink.from_stadium(_plain(), t)
		var rs := MwRinkState.stadium_record(_plain(), t)
		assert_eq(custom_rink.hazards.size(), _plain()[rs + 9] + _plain()[rs + 0xA], "stadium %d" % t)
		assert_eq(custom_rink.mask(), _plain()[rs + 0xB], "stadium %d's matchup words" % t)


## A hazard's point stays on the ice: in the corners within the boards'
## curve (the survey of plan 40: the rectangle let one sit off the ice), the
## stadiums' own hazards untouched.
func test_hazards_stay_inside_the_corners() -> void:
	if not need_rom():
		return
	var rink := MwCustomRink.new()
	rink.hazards = [{"kind": "mine", "x": 185, "y": -360}, {"kind": "mine", "x": -185, "y": 360},
			{"kind": "mine", "x": 185, "y": 150}]
	rink.validate()
	for h in rink.hazards:
		var y := int(h["y"])
		assert_lte(absi(int(h["x"])), MwRinkShape.half_width(_plain(), y), "on the ice at y %d" % y)
	assert_eq(rink.hazards[2]["x"], 185, "the straight boards as before")
	assert_lt(rink.hazards[0]["x"], 185, "pulled in from the corner")
	assert_eq(MwCustomRink.on_ice(185, -400), Vector2i(MwRinkShape.half_width(_plain(), -360), -360))
	for t in 23:
		var custom_rink := MwCustomRink.from_stadium(_plain(), t)
		for h in custom_rink.hazards:
			assert_eq(MwCustomRink.on_ice(int(h["x"]), int(h["y"])), Vector2i(int(h["x"]), int(h["y"])),
					"stadium %d's hazards where they are" % t)


func test_rink_slots_gravity() -> void:
	if not need_rom():
		return
	var plain := _plain()
	for t in 23:
		var state := MwRinkState.new()
		state.setup(plain, t)
		assert_eq(state.hazards.size(), 4)
		assert_eq(state.objects.size(), 8)
		assert_eq(state.player_params.gravity, -24)
		assert_eq(state.puck_params.gravity, -24)
	var team := MwCustomTeam.from_original(plain, 5)
	team.rink.gravity = -12
	for i in 6:
		team.rink.hazards.append({"kind": "pit", "x": -150 + 60 * i, "y": 180, "mirror": false})
		team.rink.hazards.append({"kind": "fire", "x": -150 + 60 * i, "y": -180, "mirror": false})
	team.validate(plain)
	MwCustomTeams.teams.append(team)
	MwCustomTeams.rebuild()
	var s := MwRinkState.new()
	s.setup(MwRom.data(), 23)
	assert_eq(s.hazards.size(), 6)
	assert_eq(s.objects.size(), 10, "6 placed + 4 spare")
	assert_eq(s.stadium_objects, 6)
	for i in 6:
		assert_eq(s.hazards[i].kind, 2)
		assert_eq(s.objects[i].kind, MwRinkState.KIND_FIRE)
	assert_eq(s.player_params.gravity, -12)
	assert_eq(s.puck_params.gravity, -12)
	s.setup(MwRom.data(), 5)
	assert_eq(s.hazards.size(), 4, "an original stadium after a custom one")
	assert_eq(s.objects.size(), 8)
	assert_eq(s.player_params.gravity, -24)


func test_bank_saves_and_loads() -> void:
	if not need_rom():
		return
	MwCustomTeams.dir = TEST_DIR
	var first := MwCustomTeam.from_original(_plain(), 2)
	first.city = "Testville"
	first.name = "Testers"
	first.menu_after = 22
	var id := MwCustomTeams.save(first)
	assert_eq(id, 23)
	assert_eq(first.id, "testville_testers")
	var team := MwCustomTeam.from_original(_plain(), 2)
	team.city = "Testville"
	team.name = "Testers"
	team.menu_after = -1
	MwCustomTeams.save(team)
	assert_eq(team.id, "testville_testers_2")
	assert_eq(MwTeams.count(), 25)
	var order := MwCustomTeams.menu_order(_plain())
	assert_eq(order.size(), 25)
	assert_eq(order[0], MwCustomTeams.id_of_team(team))
	assert_eq(order[2], MwCustomTeams.id_of_team(first), "after the first original (22)")
	MwCustomTeams.clear()
	assert_eq(MwRom.data().size(), MwCustomOverlay.BASE)
	MwCustomTeams.load_bank()
	assert_eq(MwCustomTeams.count(), 2)
	assert_eq(MwCustomTeams.team(23).id, "testville_testers")
	assert_eq(MwCustomTeams.team(23).to_dict(), first.to_dict())
	assert_eq(MwGfx.rom_string(MwRom.data(), MwTeams.city(MwRom.data(), 24)).get_string_from_ascii(), "Testville")
	MwCustomTeams.delete(MwCustomTeams.team(23))
	assert_eq(MwCustomTeams.count(), 1)
	assert_false(FileAccess.file_exists(TEST_DIR.path_join("testville_testers.json")))


func test_the_attract_demo_keeps_the_originals() -> void:
	if not need_rom():
		return
	MwCustomTeams.dir = TEST_DIR
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	for t in 3:
		MwCustomTeams.save(MwCustomTeam.from_original(_plain(), t))
	assert_gt(MwTeams.count(), 23)
	var session := MwSession.new(7, 1)
	for i in 300:
		session.begin_attract()
		assert_lt(maxi(maxi(session.setup.team_a, session.setup.team_b), session.setup.stadium), 23,
				"owner: the attract demo plays the original's teams only")
		session.end_attract()


func test_name_colours_of_their_own() -> void:
	if not need_rom():
		return
	var team := MwCustomTeam.from_original(_plain(), 4)
	assert_true(team.name_colours.is_empty(), "a copy: the game's (the shirt's)")
	team.name_colours = PackedInt32Array([0x0E0E, 0x0606])
	var back := MwCustomTeam.from_dict(_plain(), JSON.parse_string(JSON.stringify(team.to_dict())))
	back.validate(_plain())
	assert_eq(back.name_colours, PackedInt32Array([0x0E0E, 0x0606]), "kept in the JSON")
	MwCustomTeams.edit(back)
	var id := MwCustomTeams.editing_id()
	var bytes := MwRom.data()
	assert_eq(MwCustomOverlay.name_colours(bytes, MwTeams.record(id)), PackedInt32Array([0x0E0E, 0x0606]))
	assert_true(MwCustomOverlay.name_colours(bytes, MwTeams.record(4)).is_empty(), "an original's: none")
	var base := RomPalette.make(2, PackedStringArray(["screen_palette", "team_line a 1 1"]), id, id)
	var names := RomPalette.follow(base, PackedStringArray(["name_colours a 1"]))
	var c := names.colours()
	var b := base.colours()
	assert_eq([c[18], c[19]], [0x0E0E, 0x0606], "the letters' face and shade on the line")
	assert_eq(b[18], back.kit[0], "the shared palette keeps the shirt")
	for i in 64:
		if i != 18 and i != 19:
			assert_eq(c[i], b[i], "colour %d as the shared one" % i)
	base.team_a = 4
	assert_eq(names.team_a, 4, "the names' palette follows")
	assert_eq(names.colours(), base.colours(), "an original team: the game's colours")


func test_teams_switched_off_leave_the_game() -> void:
	if not need_rom():
		return
	MwCustomTeams.dir = TEST_DIR
	var made: Array[MwCustomTeam] = []
	for k in 3:
		var team := MwCustomTeam.from_original(_plain(), k)
		team.city = "Town%d" % k
		team.name = "Team"
		MwCustomTeams.save(team)
		made.append(team)
	assert_true(made[1].to_dict().get("enabled", true), "on: the file as before (no flag)")
	assert_false(made[1].to_dict().has("enabled"))
	var on_file := JSON.stringify(made[0].to_dict())
	MwCustomTeams.set_enabled(made[1], false)
	assert_eq(MwCustomTeams.count(), 2, "off: out of the game's teams")
	assert_eq(MwTeams.count(), 25)
	assert_eq(MwCustomTeams.id_of_team(made[1]), -1, "no game id")
	assert_eq(MwCustomTeams.id_of_team(made[2]), 24, "the next one moves down, as after a delete")
	assert_false(MwCustomTeams.menu_order(_plain()).has(25))
	assert_eq(MwCustomTeams.record_teams(null)["teams"].size(), 2, "not carried by a start record")
	assert_eq(MwCustomTeams.all(), [made[0], made[1], made[2]] as Array[MwCustomTeam], "the editor's list keeps it")
	assert_eq(JSON.stringify(made[0].to_dict()), on_file, "the others' files unchanged")
	MwCustomTeams.clear()
	MwCustomTeams.load_bank()
	assert_eq(MwCustomTeams.count(), 2, "off in its file")
	assert_eq(MwCustomTeams.disabled.size(), 1)
	var off := MwCustomTeams.disabled[0]
	assert_false(off.enabled)
	assert_eq(off.id, made[1].id)
	assert_eq(MwCustomTeams.all().size(), 3)
	# editing an off team: the game reads the copy past the bank, saved it stays off
	var copy := MwCustomTeam.from_dict(_plain(), off.to_dict())
	copy.id = off.id
	MwCustomTeams.edit(copy, off)
	assert_eq(MwCustomTeams.editing_id(), 25)
	copy.skulls = 6
	MwCustomTeams.save(copy)
	MwCustomTeams.stop_editing()
	assert_eq(MwCustomTeams.count(), 2)
	assert_eq(MwCustomTeams.disabled, [copy] as Array[MwCustomTeam], "in place of the one it copies")
	MwCustomTeams.set_enabled(copy, true)
	assert_eq(MwCustomTeams.count(), 3, "on again: back in the game")
	assert_eq(MwCustomTeams.id_of_team(copy), 24, "in its file's place")
	assert_true(MwCustomTeams.disabled.is_empty())
	MwCustomTeams.clear()
	MwCustomTeams.load_bank()
	assert_eq(MwCustomTeams.count(), 3)
	assert_eq(MwCustomTeams.team(24).skulls, 6)
	MwCustomTeams.set_enabled(MwCustomTeams.team(23), false)
	MwCustomTeams.delete(MwCustomTeams.disabled[0])
	assert_eq(MwCustomTeams.all().size(), 2, "an off team deletes")
	assert_false(FileAccess.file_exists(TEST_DIR.path_join(made[0].id + ".json")))
