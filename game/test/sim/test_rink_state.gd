extends "res://test/rom/rom_test_base.gd"
## MwRinkState.setup (the stadium part of `rink_setup` $5572) against the
## rink objects of the first recorded pass of each recording
## (compare/fixtures/rink_draw.json "setups"), and the stadium records.

var _setups: Array


func before_all() -> void:
	super.before_all()
	_setups = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/rink_draw.json")))["setups"]


static func _ints(a: Array) -> Array:
	return a.map(func(v: Variant) -> int: return int(v))


func test_setup_matches_the_original() -> void:
	if not need_rom():
		return
	assert_gt(_setups.size(), 4)
	for st in _setups:
		var s := MwRinkState.new()
		s.setup(rom, int(st["stadium"]))
		var tag := "%s (stadium %d)" % [st["name"], st["stadium"]]
		for i in 2:
			var n: Dictionary = st["nets"][i]
			assert_eq(s.nets[i].style, int(n["style"]), tag + " net style")
			assert_eq([s.nets[i].anim.address, s.nets[i].anim.variant], [int(n["anim"][0]), int(n["anim"][3])], tag + " net anim")
			assert_eq(Array(s.nets[i].motion.pos), _ints(n["motion"]).slice(0, 3), tag + " net position")
			var l: Dictionary = st["lamps"][i]
			assert_eq(Array(s.lamps[i].motion.pos), _ints(l["motion"]).slice(0, 3), tag + " lamp")
			assert_eq(s.lamps[i].anim.address, int(l["anim"][0]), tag + " lamp anim")
		for i in 4:
			var h: Array = _ints(st["hazards"][i])
			var got := s.hazards[i]
			if h[2] == 0:
				assert_eq(got.kind, 0, tag + " hazard %d empty" % i)
			else:
				assert_eq([got.x, got.y, got.kind, got.flags], h, tag + " hazard %d" % i)
		for i in 8:
			var o: Dictionary = st["objects"][i]
			var got := s.objects[i]
			assert_eq(got.kind, int(o["kind"]), tag + " object %d kind" % i)
			if got.kind == 0:
				continue
			assert_eq(got.flags, int(o["flags"]), tag + " object %d flags" % i)
			assert_eq(Array(got.motion.pos), _ints(o["motion"]).slice(0, 3), tag + " object %d position" % i)
			assert_eq([got.anim.address, got.anim.variant], [int(o["anim"][0]), int(o["anim"][3])], tag + " object %d anim" % i)
			assert_eq(got.anim.flags & MwAnimState.PLAYING, int(o["anim"][2]) & MwAnimState.PLAYING, tag + " object %d playing" % i)


func test_every_stadium_sets_up() -> void:
	if not need_rom():
		return
	for st in 23:
		var s := MwRinkState.new()
		s.setup(rom, st)
		var style := s.nets[0].style
		assert_true(style == 1 or style == 2, "stadium %d net style" % st)
		assert_eq(s.nets[0].anim.variant, 1, "top net variant")
		assert_eq(s.nets[1].anim.variant, 0, "bottom net variant")
		assert_eq(s.camera.x >> 8, 96)
		assert_eq(s.camera.y >> 8, 349)
