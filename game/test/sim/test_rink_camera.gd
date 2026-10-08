extends "res://test/rom/rom_test_base.gd"
## The rink camera (MwRinkCamera, MwRinkState.choose_camera_target) pass for
## pass against the original (compare/fixtures/rink_camera.json, recorded in
## BlastEm; mw_harness rink-fixtures). The FACE OFF! drop shake (phase 9
## part 2) writes the shown x itself and is plan 09's; shakes start in the
## simulation (here: from the recording).

var _seqs: Array


func before_all() -> void:
	super.before_all()
	_seqs = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/rink_camera.json")))["sequences"]


static func _cam(c: MwRinkCamera, d: Dictionary) -> void:
	c.x = int(d["x"])
	c.y = int(d["y"])
	c.speed = int(d["speed"])
	c.lead = int(d["lead"])
	c.shake = int(d["shake"])
	c.amp = int(d["amp"])
	c.shake_16 = int(d["shake_16"])
	c.shown = Vector2i(int(d["shown"][0]), int(d["shown"][1]))


static func _vals(c: MwRinkCamera) -> Array:
	return [c.x, c.y, c.speed, c.lead, c.shake, c.amp, c.shown]


## A state with what the target choice and the look-ahead read.
static func _state(p: Dictionary, phase: int) -> MwRinkState:
	var s := MwRinkState.new()
	s.phase = phase
	s.puck.flags = int(p["puck_flags"])
	for t in 2:
		s.teams[t].flags4 = int(p["flags4"][t])
		s.teams[t].flags5 = int(p["flags5"][t])
	for i in 6:
		s.teams[0].players[i].flags = int(p["fighting"][i])
	s.puck.carrier = s._ref(p["carrier"]) as MwRinkState.Player
	s.camera_target = s._ref(p["previous_target"])
	return s


func test_camera_follows_like_the_original() -> void:
	if not need_rom():
		return
	var n := 0
	for seq in _seqs:
		for p in seq["passes"]:
			var tag := "%s pass %d" % [seq["name"], n]
			var s := _state(p, int(p["phase_before"]))
			# the target: chosen with the phase as it was, or as the pass left it
			s.choose_camera_target()
			var chosen := s.camera_target
			var s2 := _state(p, int(p["phase"]))
			s2.choose_camera_target()
			var want_target := s._ref(p["target"])
			var want_target2 := s2._ref(p["target"])
			assert_true(chosen == want_target or s2.camera_target == want_target2, tag + ": target")
			var target: MwRinkState.Actor = want_target
			if target != null and p["target_motion"] != null:
				MwRinkState._motion(target.motion, p["target_motion"])
			_cam(s.camera, p["before"])
			if int(p["after"]["shake"]) > int(p["before"]["shake"]):
				s.camera.start_shake(30, 8)
			var lead: Variant = null
			if s.puck.flags & MwRinkState.Puck.CARRIED:
				var t := s.teams[1] if s.puck.flags & MwRinkState.Puck.BY_TEAM_B else s.teams[0]
				lead = MwRinkCamera.LEAD if t.flags4 & 2 else -MwRinkCamera.LEAD
			s.camera.update(rom, int(p["e"]), target.motion if target else null, lead)
			var got := _vals(s.camera)
			var want_cam := MwRinkCamera.new()
			_cam(want_cam, p["after"])
			var want := _vals(want_cam)
			if int(p["phase"]) == MwRinkState.PHASE_START and int(p["subphase"]) == 2:
				got[6] = Vector2i(want[6].x, got[6].y)
			assert_eq(got, want, tag)
			n += 1
	assert_gt(n, 200)


func test_placement_and_limits() -> void:
	if not need_rom():
		return
	assert_eq(MwRinkCamera.limits(rom), Vector2i(192, 680))
	var c := MwRinkCamera.new()
	c.place(rom, 0, 0)
	assert_eq(Vector2i(c.x >> 8, c.y >> 8), Vector2i(96, 349), "matchup / rink set-up view")
	c.place(rom, 0, -56)
	assert_eq(Vector2i(c.x >> 8, c.y >> 8), Vector2i(96, 293), "centre faceoff")
	c.place(rom, 104, 256 - 56)
	assert_eq(Vector2i(c.x >> 8, c.y >> 8), Vector2i(192, 549), "clamped at the right")


func test_distance_and_angle() -> void:
	if not need_rom():
		return
	assert_eq(MwTrig.distance(16, 0), 16)
	assert_eq(MwTrig.distance(-3, 4), (2 * 4 + 3 - 0) >> 1)
	assert_eq(MwTrig.angle_of(rom, 10, 0), 0)
	assert_eq(MwTrig.angle_of(rom, 0, 10), 0x40)
	assert_eq(MwTrig.angle_of(rom, -10, 0), 0x80)
	assert_eq(MwTrig.angle_of(rom, 0, -10), 0xC0)
	assert_eq(MwTrig.angle_of(rom, 5, 5), 0x20)


func test_shake_flips_every_pass_and_ends() -> void:
	if not need_rom():
		return
	var c := MwRinkCamera.new()
	c.place(rom, 0, 0)
	c.start_shake(30, 8)
	var xs := []
	for i in 12:
		xs.append(c.update(rom, 3, null).x)
	assert_eq(xs, [88, 104, 88, 104, 88, 104, 88, 104, 88, 96, 96, 96])
