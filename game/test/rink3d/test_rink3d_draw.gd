extends "res://test/rom/rom_test_base.gd"
## MwRinkDraw3D (plan 14): the draw pass that also places every frame in the
## world. The original's sprite list must come out exactly as MwRinkDraw's
## (the 2D view and rink-check depend on it), and each draw_frame call must
## get the right place. Passes: compare/fixtures/rink_draw.json.

var _passes: Array


func before_all() -> void:
	super.before_all()
	_passes = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/rink_draw.json")))["passes"]


func _built(fixture_pass: Dictionary) -> MwRinkDraw3D:
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(MwRinkState.from_dict(rom, fixture_pass["state"]), fixture_pass["phase_adds"])
	return drawer


func test_the_2d_output_is_unchanged() -> void:
	if not need_rom():
		return
	for p in _passes:
		var s := MwRinkState.from_dict(rom, p["state"])
		var drawer_2d := MwRinkDraw.new(rom)
		var want := drawer_2d.build(s, p["phase_adds"])
		var drawer := MwRinkDraw3D.new(rom)
		var got := drawer.build(MwRinkState.from_dict(rom, p["state"]), p["phase_adds"])
		assert_eq(got, want, "%s: sprite list" % p["name"])
		assert_eq(drawer.calls, drawer_2d.calls, "%s: draw calls" % p["name"])
		assert_eq(drawer.items.size(), drawer.calls.size(), "%s: one item per draw_frame" % p["name"])


func test_players_stand_at_their_positions() -> void:
	if not need_rom():
		return
	var n := 0
	for p in _passes:
		var s := MwRinkState.from_dict(rom, p["state"])
		var drawer := _built(p)
		for team in s.teams:
			for pl in team.players:
				if not pl.present:
					continue
				var at := Vector3(pl.motion.pixels())
				var found := drawer.items.any(func(it: Dictionary) -> bool:
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
	var drawer := _built(_passes[0])
	var stands := drawer.items.filter(func(it: Dictionary) -> bool: return it["frame"] == MwRinkDraw.STAND_FRAME)
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
	var lamps := drawer.items.filter(func(it: Dictionary) -> bool:
		return it["place"] == MwRinkDraw3D.UPRIGHT and (it["at"] as Vector3).y == MwRinkDraw3D.FAR_BOARDS_Y + 1 \
				and it["frame"] != MwRinkDraw.STAND_FRAME)
	assert_eq(lamps.size(), 1, "the skull")
	assert_eq(lamps[0].get("pin"), MwRinkDraw3D.FAR_PIN_Z, "the skull pinned with its stand")


func test_keys_are_unique_and_follow_their_subject() -> void:
	if not need_rom():
		return
	for p in _passes:
		var drawer := _built(p)
		var keys := {}
		for it: Dictionary in drawer.items:
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
	var fixture_pass: Dictionary = _passes[1]
	var keys := func(draw_pass: MwRinkDraw3D) -> Array:
		return draw_pass.items.filter(func(it: Dictionary) -> bool: return it["place"] != MwRinkDraw3D.SCREEN) \
				.map(func(it: Dictionary) -> String: return it["key"])
	var a: Array = keys.call(_built(fixture_pass))
	var s := MwRinkState.from_dict(rom, fixture_pass["state"])
	for team in s.teams:
		for pl in team.players:
			pl.motion.pos[0] += 3 << 8       # every skater a few pixels on, as from one pass to the next
			pl.motion.pos[1] -= 2 << 8
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(s, fixture_pass["phase_adds"])
	assert_eq(keys.call(drawer), a)


func test_screen_pieces_are_the_screen_calls() -> void:
	if not need_rom():
		return
	var with_screen := 0
	var with_arrows := 0
	for p in _passes:
		var drawer := _built(p)
		var screen_calls := drawer.items.filter(func(it: Dictionary) -> bool: return it["place"] == MwRinkDraw3D.SCREEN)
		var pieces := drawer.screen_sprites()
		var all := drawer.sprites()
		for e in pieces:
			assert_true(all.has(e), "%s: screen piece in the list" % p["name"])
		if screen_calls.is_empty() and (p["phase_adds"] as Array).is_empty():
			assert_eq(pieces.size(), 0, "%s: nothing in screen space" % p["name"])
		elif not pieces.is_empty():
			with_screen += 1
		# plan 20: without the off-screen arrows (the views that frame otherwise)
		var no_arrows := drawer.screen_sprites(true)
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


## Plan 25: the arrows drawn again for a wide picture. With no extra width
## they are the 2D pass's own; wider, a player within the extra strip loses
## his and the edge arrows move out with the edges.
func test_wide_arrows() -> void:
	if not need_rom():
		return
	var n := 0
	for p in _passes:
		var s := MwRinkState.from_dict(rom, p["state"])
		var drawer := MwRinkDraw3D.new(rom)
		drawer.build(s, p["phase_adds"])
		var low := drawer.screen_sprites(true)
		var arrows := drawer.screen_sprites().filter(func(e: Array) -> bool: return not low.has(e))
		var marks := MwRinkDraw.arrow_marks(s)
		var all := Vector2i(-0x8000, 0x8000)
		var same := MwRinkDraw.list_of(rom, MwRinkDraw.wide_arrows(rom, marks, Vector2i.ZERO, Vector2i.ZERO), all)
		var a := arrows.map(func(e: Array) -> String: return str(e))
		var b := same.map(func(e: Array) -> String: return str(e))
		a.sort()
		b.sort()
		assert_eq(b, a, "%s: as the original draws them" % p["name"])
		if arrows.is_empty():
			continue
		n += 1
		var ext := Vector2i(39, 0)
		for mk: Dictionary in marks:
			var one := MwRinkDraw.wide_arrows(rom, [mk], ext, ext)
			var at: Vector2i = mk["at"]
			var inside := at.x >= 8 - ext.x and at.x < 312 + ext.x and at.y >= 8 and at.y < 216
			if not mk["goalie"] and inside:
				assert_eq(one.size(), 0, "%s: a player in sight has none" % p["name"])
			var was := MwRinkDraw.wide_arrows(rom, [mk], Vector2i.ZERO, Vector2i.ZERO)
			if not one.is_empty() and not was.is_empty() and at.x >= 312 + ext.x and at.y >= 8 and at.y < 216:
				assert_eq(int(one[0][0]), int(was[0][0]) + ext.x, "%s: at the wide right edge" % p["name"])
	assert_gt(n, 0, "some passes draw arrows")


## Plan 25: the list built again from every piece the pass put is the
## original's (its clip and cap); the wide 2D list from them.
func test_lists_from_the_pieces() -> void:
	if not need_rom():
		return
	var moved := 0
	for p in _passes:
		var drawer := _built(p)
		var ps := drawer.pieces.map(func(a: Array) -> Array: return a.slice(0, 5))
		assert_eq(MwRinkDraw.list_of(rom, ps, Vector2i(MwRinkDraw.CLIP_MIN, MwRinkDraw.CLIP_X), MwRinkDraw.MAX_COUNT),
				drawer.sprites(), "%s: the original's list" % p["name"])
		var s := MwRinkState.from_dict(rom, p["state"])
		var marks := MwRinkDraw.arrow_marks(s)
		var str_sorted := func(l: Array) -> Array:
			var out := l.map(func(e: Array) -> String: return str(e))
			out.sort()
			return out
		if drawer.sprites().size() < MwRinkDraw.MAX_COUNT - 1:
			assert_eq(str_sorted.call(drawer.wide_list(MwRink3D.SCREEN, Vector2i.ZERO, Vector2i.ZERO, marks)),
					str_sorted.call(drawer.sprites()),
					"%s: no wider, no slide: the original's pieces" % p["name"])
		var wide := drawer.wide_list(Vector2i(480, 270), Vector2i(80, 23), Vector2i(24, -10), marks)
		var world := 0
		for pc: Array in drawer.pieces:
			if int(pc[5]) == MwRinkDraw3D.PIECE_WORLD:
				world += 1
		if world > 0 and not wide.is_empty():
			moved += 1
		for sprite: Array in wide:
			assert_between(int(sprite[0]), MwRinkDraw.CLIP_MIN - 80, MwRinkDraw.SPRITE_ORIGIN + 400,
					"%s: inside the wide picture" % p["name"])
			assert_between(int(sprite[1]), MwRinkDraw.CLIP_MIN - 23, MwRinkDraw.SPRITE_ORIGIN + 247,
					"%s: and its height" % p["name"])
	assert_gt(moved, 0)


func test_the_wide_rink_slides_inside_its_picture() -> void:
	assert_eq(MwRinkPresenter.wide_slide(100, 480, 80, 512), 0, "room both sides: centred on the original's")
	assert_eq(MwRinkPresenter.wide_slide(0, 480, 80, 512), -80,
			"at the left boards: the picture's edge at the screen's")
	assert_eq(MwRinkPresenter.wide_slide(192, 480, 80, 512), 80, "at the right boards")
	assert_eq(MwRinkPresenter.wide_slide(50, 640, 160, 512), -46, "wider than the picture: centred on it")
	assert_eq(MwRinkPresenter.wide_slide(70, 320, 0, 512), 0, "not wide: as the original")
	assert_eq(MwRinkPresenter.wide_slides(Vector2i(100, 0), Vector2i(480, 270), Vector2i(80, 23), Vector2i(512, 904)),
			Vector2i(0, -23), "taller too: at the top of the picture, kept inside it")
	if need_rom():
		assert_eq(MwRinkPresenter.rink_picture_size(rom), Vector2i(512, 904))
