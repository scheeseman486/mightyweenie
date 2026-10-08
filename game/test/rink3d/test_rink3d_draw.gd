extends "res://test/rom/rom_test_base.gd"
## MwRinkDraw3D (plan 14): the draw pass that also places every frame in the
## world. The original's sprite list must come out exactly as MwRinkDraw's
## (the 2D view and rink-check depend on it), and each draw_frame call must
## get the right place. Passes: compare/fixtures/rink_draw.json.

var _passes: Array


func before_all() -> void:
	super.before_all()
	_passes = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/rink_draw.json")))["passes"]


func _built(p: Dictionary) -> MwRinkDraw3D:
	var d := MwRinkDraw3D.new(rom)
	d.build(MwRinkState.from_dict(rom, p["state"]), p["phase_adds"])
	return d


func test_the_2d_output_is_unchanged() -> void:
	if not need_rom():
		return
	for p in _passes:
		var s := MwRinkState.from_dict(rom, p["state"])
		var a := MwRinkDraw.new(rom)
		var want := a.build(s, p["phase_adds"])
		var b := MwRinkDraw3D.new(rom)
		var got := b.build(MwRinkState.from_dict(rom, p["state"]), p["phase_adds"])
		assert_eq(got, want, "%s: sprite list" % p["name"])
		assert_eq(b.calls, a.calls, "%s: draw calls" % p["name"])
		assert_eq(b.items.size(), b.calls.size(), "%s: one item per draw_frame" % p["name"])


func test_players_stand_at_their_positions() -> void:
	if not need_rom():
		return
	var n := 0
	for p in _passes:
		var s := MwRinkState.from_dict(rom, p["state"])
		var d := _built(p)
		for t in s.teams:
			for pl in t.players:
				if not pl.present:
					continue
				var at := Vector3(pl.motion.pixels())
				var found := d.items.any(func(it: Dictionary) -> bool:
					return it["place"] == MwRinkDraw3D.UPRIGHT and it["at"] == at)
				assert_true(found, "%s: player at %s" % [p["name"], at])
				n += 1
	assert_gt(n, 50)


func test_shadows_markers_and_hazards_lie_on_the_ice() -> void:
	if not need_rom():
		return
	var kinds := {}
	for p in _passes:
		for it: Dictionary in _built(p).items:
			var f: int = it["frame"]
			if f == MwRinkDraw.SHADOW or f == MwRinkDraw.PUCK_SHADOW or f == MwRinkDraw.POSSESSION:
				assert_eq(it["place"], MwRinkDraw3D.GROUND, "frame %X on the ice" % f)
				assert_eq((it["at"] as Vector3).z, 0.0)
				kinds[f] = true
			if it["place"] == MwRinkDraw3D.GROUND:
				assert_between(int(it["depth"]), 1, MwRinkDraw.DEPTH_MARKER)
	assert_eq(kinds.size(), 3, "shadows, puck shadows and possession arcs seen")


func test_lamp_stands_keep_their_rom_points_or_their_2d_spot() -> void:
	if not need_rom():
		return
	var d := _built(_passes[0])
	var stands := d.items.filter(func(it: Dictionary) -> bool: return it["frame"] == MwRinkDraw.STAND_FRAME)
	assert_eq(stands.size(), 2)
	for i in 2:
		var a: int = MwRinkDraw.STANDS[i]
		var rom_at := Vector3(MwGfx.s16(rom, a), MwGfx.s16(rom, a + 2), MwGfx.s16(rom, a + 4))
		var at: Vector3 = stands[i]["at"]
		assert_eq(stands[i]["place"], MwRinkDraw3D.UPRIGHT)
		assert_eq(at.y - at.z, rom_at.y - rom_at.z, "same map row")
		assert_eq(at.x, rom_at.x)
		if rom_at.y > 0:    # the near one moved inside the near boards
			assert_true(at.y <= MwRinkDraw3D.NEAR_BOARDS_Y + 2 and at.z >= 0.0, "inside the near boards: %s" % at)
			assert_false(stands[i].has("pin"), "the near one stands on the ice")
		else:               # the far one in front of the far glass, pinned to it with its lamp
			assert_true(at.y > MwRinkDraw3D.FAR_BOARDS_Y, "in front of the far boards: %s" % at)
			assert_eq(stands[i].get("pin"), MwRinkDraw3D.FAR_PIN_Z, "pinned to the far glass")
	var lamps := d.items.filter(func(it: Dictionary) -> bool:
		return it["place"] == MwRinkDraw3D.UPRIGHT and (it["at"] as Vector3).y == MwRinkDraw3D.FAR_BOARDS_Y + 1 \
				and it["frame"] != MwRinkDraw.STAND_FRAME)
	assert_eq(lamps.size(), 1, "the skull")
	assert_eq(lamps[0].get("pin"), MwRinkDraw3D.FAR_PIN_Z, "the skull pinned with its stand")


func test_keys_are_unique_and_follow_their_subject() -> void:
	if not need_rom():
		return
	for p in _passes:
		var d := _built(p)
		var keys := {}
		for it: Dictionary in d.items:
			assert_false(keys.has(it["key"]), "%s: key %s once" % [p["name"], it["key"]])
			keys[it["key"]] = true
		var s := MwRinkState.from_dict(rom, p["state"])
		for ti in s.teams.size():
			for pi in s.teams[ti].players.size():
				var pl := s.teams[ti].players[pi]
				if not pl.present:
					continue
				var subject := "t%d.p%d.%X/" % [ti, pi, pl.record]
				assert_true(keys.has(subject + "body"), "%s: %sbody" % [p["name"], subject])
				if pl.motion.pixels().z != 0:
					assert_true(keys.has(subject + "f%X" % MwRinkDraw.SHADOW), "%s: its shadow follows it" % p["name"])


func test_keys_do_not_depend_on_positions() -> void:
	if not need_rom():
		return
	var p: Dictionary = _passes[1]
	var keys := func(d: MwRinkDraw3D) -> Array:
		return d.items.filter(func(it: Dictionary) -> bool: return it["place"] != MwRinkDraw3D.SCREEN) \
				.map(func(it: Dictionary) -> String: return it["key"])
	var a: Array = keys.call(_built(p))
	var s := MwRinkState.from_dict(rom, p["state"])
	for t in s.teams:
		for pl in t.players:
			pl.motion.pos[0] += 3 << 8       # every skater a few pixels on, as from one pass to the next
			pl.motion.pos[1] -= 2 << 8
	var d := MwRinkDraw3D.new(rom)
	d.build(s, p["phase_adds"])
	assert_eq(keys.call(d), a)


func test_screen_pieces_are_the_screen_calls() -> void:
	if not need_rom():
		return
	var with_screen := 0
	var with_arrows := 0
	for p in _passes:
		var d := _built(p)
		var screen_calls := d.items.filter(func(it: Dictionary) -> bool: return it["place"] == MwRinkDraw3D.SCREEN)
		var pieces := d.screen_sprites()
		var all := d.sprites()
		for e in pieces:
			assert_true(all.has(e), "%s: screen piece in the list" % p["name"])
		if screen_calls.is_empty() and (p["phase_adds"] as Array).is_empty():
			assert_eq(pieces.size(), 0, "%s: nothing in screen space" % p["name"])
		elif not pieces.is_empty():
			with_screen += 1
		# plan 20: without the off-screen arrows (the views that frame otherwise)
		var no_arrows := d.screen_sprites(true)
		for e in no_arrows:
			assert_true(pieces.has(e), "%s: a piece of the full list" % p["name"])
		var arrows := screen_calls.filter(func(it: Dictionary) -> bool: return String(it["key"]).contains(".arrow"))
		if arrows.is_empty():
			assert_eq(no_arrows.size(), pieces.size(), "%s: no arrows, nothing left out" % p["name"])
		else:
			with_arrows += 1
			assert_lt(no_arrows.size(), pieces.size(), "%s: the arrows left out" % p["name"])
	assert_gt(with_screen, 0, "some passes draw arrows or ref icons")
	assert_gt(with_arrows, 0, "some passes draw arrows")


func test_directional_frames_say_how_to_turn() -> void:
	if not need_rom():
		return
	var bodies := 0
	var weapons := 0
	var nets := 0
	var flat := 0
	for p in _passes:
		for it: Dictionary in _built(p).items:
			if it.has("dir"):
				var d: Dictionary = it["dir"]
				var f := MwRinkFacing3D._frame(rom, int(d["anim"]), int(d["variant"]), int(d["aframe"]))
				assert_eq(f.x, int(it["frame"]), "%s: %s frame from its record" % [p["name"], it["key"]])
				assert_eq(int(d["attr0"]) ^ (f.y << 3), int(it["attr"]), "%s: %s flips" % [p["name"], it["key"]])
				if d.has("hot"):
					var h: Array = d["hot"]
					assert_eq(MwRinkFacing3D.hotspot(rom, int(h[0]), int(d["variant"]), int(h[1]), int(h[2])),
							it["offset"], "%s: weapon at the body's hotspot" % p["name"])
					weapons += 1
				else:
					bodies += 1
			if it.has("net"):
				var n: Dictionary = it["net"]
				var v := 1 if int(n["mouth"]) == 1 else 0
				assert_eq(MwRinkFacing3D._frame(rom, int(n["anim"]), v, int(n["aframe"])).x, int(it["frame"]))
				nets += 1
			if it.get("flat", false):
				flat += 1
	assert_gt(bodies, 100, "players' bodies turn")
	assert_gt(nets, 10, "nets have two views")
	assert_gt(flat, 10, "lamp stands are flat")
	gut.p("directional bodies %d, weapons %d, nets %d, flat %d" % [bodies, weapons, nets, flat])
