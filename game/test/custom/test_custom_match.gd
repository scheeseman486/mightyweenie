extends "res://test/rom/rom_test_base.gd"
## A custom team in the game (plan 38): CPU matches run headless through the
## rink's simulation. The original's teams play exactly as before with
## custom teams in the bank; an unchanged copy of a team plays exactly as
## its original; a changed one plays a whole period without trouble.

const PASSES := 1500


func after_each() -> void:
	MwCustomTeams.clear()


## [param passes] passes of a CPU match (2 ticks each); a digest per 50.
func _match(stadium: int, a: int, b: int, passes := PASSES) -> Array:
	var rom_bytes := MwRom.data()
	var s := MwRinkState.new()
	s.rng = MlhRng.new(4321)
	var sim := MwRinkSim.new(rom_bytes, s)
	sim.cpu = MwRinkAI.new()
	var up := MwRinkUpdate.new(sim)
	var phases := MwRinkPhases.new(up)
	MwRinkMatch.start(sim, stadium, a, b, 0, true, 2)
	s.period_minutes = 3
	s.clock = 180
	phases.enter(5)
	var out := []
	var h := 0
	for i in passes:
		s.tick += 2
		up.pass_start(2)
		sim.run(2)
		up.after_segment(2)
		var left := phases.pass_end(2)
		up.draws([], MwRinkPhases.RULES_DRAWN, phases.overlays, phases.sprite_ops)
		if left >= 0:
			phases.enter(5)
		h = hash([h, s.rng.state, s.puck.motion.pos, s.teams[0].score, s.teams[1].score, s.phase])
		for team in s.teams:
			for p in team.players:
				h = hash([h, p.motion.pos, p.present])
		if i % 50 == 49:
			out.append(h)
	out.append([s.teams[0].score, s.teams[1].score, s.period])
	return out


func test_originals_play_as_before_with_custom_teams() -> void:
	if not need_rom():
		return
	var before := _match(3, 3, 7)
	var c := MwCustomTeam.from_original(MwRom.archive().bytes(), 12)
	c.rink.gravity = -12
	MwCustomTeams.teams.append(c)
	MwCustomTeams.rebuild()
	assert_eq(_match(3, 3, 7), before)


func test_an_unchanged_copy_plays_as_its_original() -> void:
	if not need_rom():
		return
	var original := _match(3, 3, 7)
	var c := MwCustomTeam.from_original(MwRom.archive().bytes(), 3)
	MwCustomTeams.teams.append(c)
	MwCustomTeams.rebuild()
	assert_eq(_match(23, 23, 7), original, "team 3's copy at its copied rink")


func test_a_custom_team_plays_a_period() -> void:
	if not need_rom():
		return
	var rom_bytes := MwRom.archive().bytes()
	var c := MwCustomTeam.from_original(rom_bytes, 9)
	c.city = "Custom"
	c.name = "Customs"
	for s in [0, 3, 7, 11]:
		var player := MwCustomPlayer.from_record(rom_bytes, MwTeams.player(rom_bytes, 9, s))
		player.name = "Player %d" % s
		player.ratings["speed"] = 10
		player.face = s % 11
		c.players.append(player)
		c.roster[s] = {"player": c.players.size() - 1}
	c.specials = PackedInt32Array([1, 10, 3])
	c.nasty = PackedInt32Array([6, 7, 8])
	c.coach.colours = PackedInt32Array([0x00E, 0x00A, 0x0E0, 0x0A0, 0xE00, 0xA00, 0x444])
	c.coach.voice = 0x0D
	c.rink.gravity = -16
	c.rink.net = 2
	c.rink.hazards.clear()
	for x in [-150, -90, 90, 150]:
		c.rink.hazards.append({"kind": "pit", "x": x, "y": 180, "mirror": false})
		c.rink.hazards.append({"kind": "mine", "x": x, "y": -180, "mirror": false})
	c.rink.hazards.append({"kind": "shark", "x": 0, "y": 200, "mirror": false})
	c.rink.hazards.append({"kind": "spikes", "x": 185, "y": 190, "mirror": true})
	c.validate(rom_bytes)
	assert_eq(c.rink.hazards.size(), 10)
	MwCustomTeams.teams.append(c)
	MwCustomTeams.rebuild()
	var r := _match(23, 23, 4, 3000)
	var end: Array = r[r.size() - 1]
	assert_gte(int(end[0]) + int(end[1]), 0)
	# and as team B at an original's rink
	r = _match(4, 4, 23, 1000)
	assert_eq(r.size(), 21)
