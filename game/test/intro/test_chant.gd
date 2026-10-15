extends "res://test/rom/rom_test_base.gd"
## The crowd's chant at the match's opening (plan 33, MwChant): its beats as
## the ROM's sample has them, its clock, the crowd shader told.


func test_the_beats_are_the_samples() -> void:
	if not need_rom():
		return
	var m := MwChant.measure(rom)
	assert_almost_eq(float(m["length"]), 1.51, 0.02, "one bar")
	assert_almost_eq(float(m["stomps"][0]), MwChant.STOMPS[0], 0.02, "the first stomp's peak")
	assert_almost_eq(float(m["stomps"][1]), MwChant.STOMPS[1], 0.02, "the second's")
	assert_almost_eq(float(m["clap"]), MwChant.CLAP, 0.02, "the clap's")


func test_its_clock() -> void:
	var chant := MwChant.new()
	assert_lt(chant.time(5.0), 0.0, "nothing before the sound")
	chant.start(1.0)
	assert_almost_eq(chant.time(1.25), 0.25, 1e-6)
	chant.start(2.6)
	assert_almost_eq(chant.period, 1.6, 1e-6, "start to start, as measured")
	assert_almost_eq(chant.time(2.59), 1.59, 1e-6, "a frame shown a little behind: the bar before")
	assert_lt(chant.time(0.5), 0.0, "nothing before the first")
	chant.start(2.9)
	assert_almost_eq(chant.period, 1.6, 1e-6, "a start held up or cut short measures nothing")
	chant.last = true
	assert_almost_eq(chant.time(3.4), 0.5, 1e-6, "the last bar plays out")
	assert_lt(chant.time(2.9 + MwChant.LAST_ENDS + 0.01), 0.0, "then no more chanting")
	if need_rom():
		assert_almost_eq(MwChant.new(rom).period, float(MwChant.measure(rom, false)["length"]) + MwChant.RESTART, 1e-6,
				"at first: the sample and the restart")


func test_the_crowd_is_told() -> void:
	if not need_rom():
		return
	var stands := MwStands3D.new()
	add_child_autofree(stands)
	var m: ShaderMaterial = stands.get_node("Figures").material_override
	stands.chant(0.4, 1.6, true)
	assert_almost_eq(float(m.get_shader_parameter("chant_time")), 0.4, 1e-6)
	assert_almost_eq(float(m.get_shader_parameter("chant_period")), 1.6, 1e-6)
	assert_true(m.get_shader_parameter("chant_first"))
	var beats: Vector3 = m.get_shader_parameter("chant_beats")
	assert_almost_eq(beats, Vector3(MwChant.STOMPS[0], MwChant.STOMPS[1], MwChant.CLAP), Vector3.ONE * 1e-6)


func test_the_view_tells_the_crowd_as_its_frames_show() -> void:
	if not need_rom():
		return
	var view := (load("res://src/rink3d/rink_view_3d.tscn") as PackedScene).instantiate() as MwRinkView3D
	add_child_autofree(view)
	var m: ShaderMaterial = view.stands.get_node("Figures").material_override
	var chant := MwChant.new(rom)
	chant.start(1.0)
	var f := {"items": [], "shot": null, "shown": Vector2.ZERO, "clock": 1.5, "chant": chant, "chant_first": true}
	view.present_frame(f, {})
	assert_almost_eq(float(m.get_shader_parameter("chant_time")), 0.5, 1e-5)
	assert_true(m.get_shader_parameter("chant_first"))
	f["clock"] = 1.6
	view.present_frame(f, {}, true)
	view.blend_to(0.5)
	assert_almost_eq(float(m.get_shader_parameter("chant_time")), 0.55, 1e-5, "between the passes")
	assert_almost_eq(view.camera.clock, 1.55, 1e-5, "the camera keeps the frame's clock")
