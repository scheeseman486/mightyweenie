extends "res://test/rom/rom_test_base.gd"
## The match's opening's players (plan 33, MwIntroCast): out of the east
## door one by one, teams alternating; showing off from a seed of their
## own; on the press, the starters to the rink's first frame and the
## reserves through the east passage to their benches.
## Short names: c the MwIntroCast under test.

var rehearsal: MwMatchRehearsal


func before_all() -> void:
	super.before_all()
	if not rom.is_empty():
		var session := MwSession.new(5, 1)
		session.setup.team_a = 2
		session.setup.team_b = 9
		rehearsal = MwMatchRehearsal.run(rom, session.setup, session.rng.state)


func _run(c: MwIntroCast, ticks: int) -> void:
	for i in ticks / 2:
		c.step(2)


func test_out_of_the_door_one_by_one() -> void:
	if not need_rom():
		return
	var c := MwIntroCast.new(rom, rehearsal, 7)
	assert_eq(c.figs.size(), 48)
	for i in c.figs.size():
		assert_eq(int(c.figs[i]["team"]), i % 2, "teams alternating")
	_run(c, MwIntroCast.ENTER_AT - 2)
	assert_eq(c.items().size(), 0, "nobody before the crowd's shots are over")
	_run(c, 4)
	var items := c.items()
	assert_eq(items.size(), 1, "the first one")
	var at: Vector3 = items[0]["at"]
	assert_gt(at.x, 255.0, "at the door")
	assert_lt(float(items[0].get("shade", 1.0)), 0.5, "still in the arch's dark")
	_run(c, MwIntroCast.ENTER_EVERY * 47 + 120)
	for f in c.figs:
		assert_ne(int(f["state"]), MwIntroCast.WAITING, "all out")
		assert_lt(c.position(f).x, 180.0, "on the ice")


func test_the_same_seed_the_same_show() -> void:
	if not need_rom():
		return
	var first := MwIntroCast.new(rom, rehearsal, 3)
	var cast := MwIntroCast.new(rom, rehearsal, 3)
	var other := MwIntroCast.new(rom, rehearsal, 4)
	_run(first, 1800)
	_run(cast, 1800)
	_run(other, 1800)
	assert_eq(first.items(), cast.items())
	assert_ne(first.items(), other.items(), "another seed, another show")


func test_the_line_up_ends_on_the_rinks_first_frame() -> void:
	if not need_rom():
		return
	for press in [300, 900, 2400]:
		var c := MwIntroCast.new(rom, rehearsal, 11)
		_run(c, press)
		c.line_up()
		var outs := {}
		for f in c.figs:
			if int(f["state"]) == MwIntroCast.OUT:
				outs[Vector2i(f["team"], f["slot"])] = true
		var n := 0
		while not c.lined_up() and n < 1200:
			c.step(2)
			n += 2
			for f in c.figs:
				if int(f["state"]) == MwIntroCast.OUT:
					outs[Vector2i(f["team"], f["slot"])] = true
		assert_true(c.lined_up(), "everyone placed (pressed at %d) in %d ticks" % [press, n])
		assert_lt(n, 700, "soon")
		var by_key := {}
		for it: Dictionary in c.items():
			by_key[it["key"]] = it
		for st: Dictionary in rehearsal.starters():
			var it: Dictionary = by_key["cast.t%d.s%d/body" % [st["team"], st["slot"]]]
			var at: Vector3 = it["at"]
			assert_eq(Vector2(at.x, at.y), st["at"], "a starter on his spot")
			assert_eq(int(it["dir"]["variant"]), int(st["variant"]), "facing as the rink has him")
		var f: PackedFloat32Array = rehearsal.bench["figs"]
		for i in range(0, f.size(), MwBenchLife.FIG):
			var t := int(f[i])
			var it: Dictionary = by_key["cast.t%d.s%d/body" % [t, int(f[i + 1])]]
			var at: Vector3 = it["at"]
			assert_eq(Vector2(at.x, at.y), MwBench3D.place_at(t, int(f[i + 3])), "a reserve in his place")
			assert_true(outs.has(Vector2i(t, int(f[i + 1]))), "by way of the dark")


func test_the_door_kept_clear() -> void:
	# owner: the players crowded the entrance as they came in; the opening is
	# kept free of them.
	if not need_rom():
		return
	for seed_value in [2, 11]:
		var c := MwIntroCast.new(rom, rehearsal, seed_value)
		var most := 0
		for i in 1800:
			c.step(2)
			var n := 0
			for f in c.figs:
				var st := int(f["state"])
				if st == MwIntroCast.WAITING:
					continue
				var point := c.position(f)
				if point.x > MwIntroCast.IN_X:
					continue                  # (on the way in, through the door)
				if MwIntroCast.in_clear(point):
					assert_ne(st, MwIntroCast.SHOWING, "nobody shows off there (tick %d)" % c.tick)
					# (well inside: the ways round it may cut its edges)
					if point.x > MwIntroCast.CLEAR_X + 10.0 \
							and absf(point.y - MwIntroCast.DOOR.y) < MwIntroCast.CLEAR_Y - 10.0:
						n += 1
			most = maxi(most, n)
		# the newcomers on their way out of it (one every ENTER_EVERY ticks: the
		# one just in, two leaving), now and then one more going by
		assert_lte(most, 4, "a few skating through at most (seed %d)" % seed_value)
