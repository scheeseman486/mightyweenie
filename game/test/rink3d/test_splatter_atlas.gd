extends "res://test/rom/rom_test_base.gd"
## The arena's paint atlas (plan 37, MwSplatterAtlas): splats land on the
## ice's and the boards' texel grids exactly, streaks keep any of the 256
## headings, pools stop at their size, and the paint is the same however it
## is reached (applied live, or seeked to back and forth for a replay).

const GEYSER := 0x20BD2


func _frame(n: int) -> int:
	var a := MwGfx.animation(rom, GEYSER)
	return int(a["frames"]) + MwGfx.anim_offsets(rom, a, 0)[n]


func _opaque(m: Dictionary) -> int:
	var n := 0
	for v in (m["px"] as PackedByteArray):
		if v != 0:
			n += 1
	return n


func _painted(at: MwSplatterAtlas) -> int:
	var n := 0
	for v in at.data:
		if v != 0:
			n += 1
	return n


func test_layout_loads() -> void:
	var board_layout := MwSplatterAtlas.layout()
	assert_false(board_layout.is_empty(), "rink_paint.json")
	assert_gt((board_layout["runs"] as Array).size(), 50, "the boards' runs")
	assert_almost_eq(float(board_layout["total"]), 2100.0, 5.0, "the boards' loop")
	assert_true(MwSplatterAtlas.on_ice(0, 0))
	assert_true(MwSplatterAtlas.on_ice(-184, 0))
	assert_false(MwSplatterAtlas.on_ice(-186, 0))
	assert_false(MwSplatterAtlas.on_ice(183, -371), "a far corner is round")


func test_ice_texels() -> void:
	# the far part: one texel per rink px, the near rows their own block
	var a := MwSplatterAtlas.ice_texel(0.2, 0.7)
	assert_eq(MwSplatterAtlas.ice_texel(1.2, 0.7), a + 1, "east: the next column")
	assert_eq(MwSplatterAtlas.ice_texel(0.2, 1.7), a + MwSplatterAtlas.SIZE, "south: the next row")
	var near := MwSplatterAtlas.ice_texel(0.5, 360.5)
	assert_gt(near / MwSplatterAtlas.SIZE, 704, "behind the near goal line: its own rows")
	assert_ne(near, MwSplatterAtlas.ice_texel(0.5, -360.5), "not the far end's texels")
	assert_eq(MwSplatterAtlas.ice_texel(0.5, 361.5), near - MwSplatterAtlas.SIZE, "mirrored rows")


## At a quarter turn and 1:1 every sprite pixel is one texel: the frame's
## pixels, exactly, on the ice's grid.
func test_ice_stamp_is_the_frame_on_the_grid() -> void:
	if not need_rom():
		return
	var f := _frame(5)
	var m := MwSplatterAtlas.mask(f)
	var w: int = m["w"]
	var h: int = m["h"]
	var px: PackedByteArray = m["px"]
	for turn in 4:
		var at := MwSplatterAtlas.new()
		var c := Vector2i(-20, -100)
		at.ice_stamp(MwSplatterAtlas.BLOOD, f, c.x, c.y, -PI / 2 + turn * PI / 2, 1.0, false)
		var up := Vector2i(roundi(cos(-PI / 2 + turn * PI / 2)), roundi(sin(-PI / 2 + turn * PI / 2)))
		var right := Vector2i(-up.y, up.x)
		var bad := 0
		for iy in h:
			for ix in w:
				# pixel (ix, iy) lies at c + right (ix - ox) - up (iy - oy), its texel's corner
				var dx := ix - int(m["ox"])
				var dy := iy - int(m["oy"])
				var point := Vector2(c) + Vector2(right) * (dx + 0.5) - Vector2(up) * (dy + 0.5)
				var t := MwSplatterAtlas.ice_texel(point.x, point.y)
				var want := MwSplatterAtlas.BLOOD if px[iy * w + ix] != 0 else 0
				if at.data[t] != want:
					bad += 1
		assert_eq(bad, 0, "quarter turn %d: the frame exactly" % turn)
		assert_eq(_painted(at), _opaque(m), "quarter turn %d: nothing else" % turn)


func test_ice_stamp_any_angle_and_scale() -> void:
	if not need_rom():
		return
	var f := _frame(2)
	var n := _opaque(MwSplatterAtlas.mask(f))
	var at := MwSplatterAtlas.new()
	at.ice_stamp(MwSplatterAtlas.OIL, f, 0, 0, 0.7, 1.0, true)
	assert_almost_eq(float(_painted(at)), float(n), n * 0.1, "turned: as many texels as pixels, within 10 %")
	var half := MwSplatterAtlas.new()
	half.ice_stamp(MwSplatterAtlas.BLOOD, f, 0, 0, 0.7, 0.5, false)
	assert_almost_eq(float(_painted(half)), n / 4.0, n * 0.05, "1:2: a quarter")


## Upright on the boards: the frame's bottom row on their foot, its columns
## along the boards (s), its rows up them (z).
func test_wall_stamp_stands_on_the_foot() -> void:
	if not need_rom():
		return
	var f := _frame(0)
	var at := MwSplatterAtlas.new()
	at.wall_stamp(MwSplatterAtlas.BLOOD, f, 40.0, 1.0, false)      # the far end's boards
	var board_layout := MwSplatterAtlas.layout()
	var lowest := INF
	var count := 0
	for r: Array in board_layout["runs"]:
		var dz_dv := (float(r[12]) - float(r[11])) / (float(r[14]) - float(r[13]))
		for col in range(int(r[1]), int(r[1]) + int(r[3])):
			for row in range(int(r[2]), int(r[2]) + int(r[4])):
				if at.data[row * MwSplatterAtlas.SIZE + col] != 0:
					count += 1
					lowest = minf(lowest, float(r[11]) + (row - int(r[6]) + 0.5 - float(r[13])) * dz_dv)
	assert_gt(count, 300, "painted on the boards")
	assert_lt(lowest, 1.0, "its bottom row at the boards' foot")
	assert_gt(lowest, 0.0)


## A skate's mark keeps its heading at every one of the 256 facing steps:
## the painted texels lie within a texel of the line.
func test_streaks_hold_their_heading() -> void:
	var worst := 0.0
	for k in 256:
		var at := MwSplatterAtlas.new()
		var a := k * TAU / 256.0
		var d := Vector2(cos(a), sin(a))
		var from := Vector2(-40.3, 20.6)
		var paint_load := MwSplatterAtlas.STREAK_LOAD
		var phase := 0
		var wet := 0
		var kind := MwSplatterAtlas.BLOOD
		var point := from
		for i in 10:                       # ten passes of 3.3 px
			var point_2 := point + d * 3.3
			var r := at.streak(kind, paint_load, phase, wet, point, point_2)
			paint_load = r[0]
			kind = r[1]
			phase = r[2]
			wet = r[3]
			point = point_2
		var n := 0
		for i in at.data.size():
			if at.data[i] == 0:
				continue
			n += 1
			var c := Vector2(i % MwSplatterAtlas.SIZE - 186 + 0.5, i / MwSplatterAtlas.SIZE - 373 + 0.5)
			var off := absf((c - from).cross(d))
			worst = maxf(worst, off)
		assert_gt(n, 20, "heading %d painted" % k)
	assert_lt(worst, 1.0, "every texel within a texel of its line (worst %.2f)" % worst)


func test_streak_picks_up_paint_and_runs_out() -> void:
	var at := MwSplatterAtlas.new()
	at.pool(MwSplatterAtlas.OIL, 0, 0, 6, 0)
	var r := at.streak(MwSplatterAtlas.CLEAR, 0, 0, 0, Vector2(-3, 0.5), Vector2(80, 0.5))
	assert_eq(r[1], MwSplatterAtlas.OIL, "picked up the pool's oil")
	var after := 0
	for x in range(8, 80):
		if at.data[MwSplatterAtlas.ice_texel(x + 0.5, 0.5)] == MwSplatterAtlas.OIL:
			after += 1
	assert_gt(after, MwSplatterAtlas.STREAK_LOAD * 2 / 3 - 2, "a track out of the pool")
	assert_lt(after, MwSplatterAtlas.STREAK_LOAD + 1, "until the load runs out")


## Crossing another skate's line (a texel or two of paint) takes nothing up:
## streaks don't spread from each other.
func test_crossing_a_line_takes_no_paint() -> void:
	var at := MwSplatterAtlas.new()
	at.streak(MwSplatterAtlas.BLOOD, MwSplatterAtlas.STREAK_LOAD, 0, 0, Vector2(0.5, -30), Vector2(0.5, 30))
	var before := at.digest()
	var r := at.streak(MwSplatterAtlas.CLEAR, 0, 0, 0, Vector2(-20, 0.5), Vector2(40, 0.5))
	assert_eq(r[0], 0, "no load")
	assert_eq(at.digest(), before, "no new paint")


## The paint and the ice's detail are separate fields: neither stamp clears
## the other, and a foot takes no paint up from the detail.
func test_paint_and_detail_apart() -> void:
	if not need_rom():
		return
	var at := MwSplatterAtlas.new()
	var f := _frame(2)
	at.ice_stamp(MwSplatterAtlas.LIGHT, f, 0, 0, 0.3, 1.0, false, MwSplatterAtlas.DETAIL)
	var light := 0
	for v in at.data:
		if v == MwSplatterAtlas.LIGHT << 2:
			light += 1
	at.ice_stamp(MwSplatterAtlas.BLOOD, f, 0, 0, 0.3, 1.0, false)
	var both := 0
	for v in at.data:
		if v == (MwSplatterAtlas.LIGHT << 2) | MwSplatterAtlas.BLOOD:
			both += 1
	assert_eq(both, light, "blood over the detail keeps it")
	var at2 := MwSplatterAtlas.new()
	at2.ice_stamp(MwSplatterAtlas.DARK, f, 0, 0, 0.0, 1.0, false, MwSplatterAtlas.DETAIL)
	var r := at2.streak(MwSplatterAtlas.CLEAR, 0, 0, 0, Vector2(-40, -30.5), Vector2(40, -30.5))
	assert_eq(r[0], 0, "no paint taken up from the detail")


## The skates' scratches: a mark's density decides how many texels turn
## light, slow ones only every other texel (checkered), all by hash.
func test_scratches() -> void:
	var at := MwSplatterAtlas.new()
	at.skates(PackedFloat32Array([-30.3, 0.4, 30.3, 0.4, 1.0, 0.0, 7]))
	var full := 0
	for v in at.data:
		if v == MwSplatterAtlas.LIGHT << 2:
			full += 1
	assert_almost_eq(full, 60, 2, "solid: every texel on the way")
	var thin := MwSplatterAtlas.new()
	thin.skates(PackedFloat32Array([-30.3, 0.4, 30.3, 0.4, 0.1, 0.0, 7]))
	var n := 0
	for v in thin.data:
		if v != 0:
			n += 1
	assert_almost_eq(float(n), 6.0, 5.0, "a tenth")
	var slow := MwSplatterAtlas.new()
	slow.skates(PackedFloat32Array([-30.3, 0.4, 30.3, 0.4, 1.0, 1.0, 7]))
	var odd := 0
	var m := 0
	for i in slow.data.size():
		if slow.data[i] != 0:
			m += 1
			if (i % MwSplatterAtlas.SIZE + i / MwSplatterAtlas.SIZE) % 2 == 1:
				odd += 1
	assert_almost_eq(m, 30, 2, "dithered: every other texel")
	assert_eq(odd, 0, "checkered")


func test_pool_stays_within_its_size() -> void:
	var at := MwSplatterAtlas.new()
	at.pool(MwSplatterAtlas.BLOOD, 10, 20, 14, 12345)
	var far := 0.0
	for i in at.data.size():
		if at.data[i] != 0:
			var c := Vector2(i % MwSplatterAtlas.SIZE - 186 + 0.5, i / MwSplatterAtlas.SIZE - 373 + 0.5)
			far = maxf(far, c.distance_to(Vector2(10, 20)))
	assert_lt(far, 14 * 1.21, "edge wobble at most a fifth")
	assert_gt(_painted(at), 450)


## [param at] painted with 160 operations of every kind; the digest after each.
func _paint_160(at: MwSplatterAtlas) -> Dictionary:
	var digests := {0: at.digest()}
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	for i in 160:
		match i % 4:
			0:
				at.ice_stamp(1 + i % 2, _frame(1 + i % 3), rng.randf_range(-150, 150), rng.randf_range(-350, 360),
						rng.randf_range(-PI, PI), 0.5, i % 3 == 0)
			1:
				at.wall_stamp(1 + i % 2, _frame(5), rng.randf_range(0, 2100), 1.0, false)
			2:
				at.pool(1, rng.randf_range(-150, 150), rng.randf_range(-350, 360), 9, i)
			3:
				at.streak(0, 0, 0, 0, Vector2(rng.randf_range(-150, 150), rng.randf_range(-300, 300)),
						Vector2(rng.randf_range(-150, 150), rng.randf_range(-300, 300)))
		digests[at.count()] = at.digest()
	return digests


## Rewinding (owner, 2026-10-15: it dropped the frame rate badly): a seek back
## one operation at a time starts from a plain copy fewer than COPY_STEP
## operations before it (not the checkpoint, up to CHECKPOINT_OPS back), at
## most COPY_KEEP copies kept; a seek with a budget gets there a share at a
## time - an operation a call at the least - and shows the same texels.
func test_rewinding_seeks_from_near_copies() -> void:
	if not need_rom():
		return
	var at := MwSplatterAtlas.new()
	var digests := _paint_160(at)
	var last := at.count()
	assert_true(at._copies.size() <= MwSplatterAtlas.COPY_KEEP)
	for n in range(last - 1, last - 60, -1):
		var near := false
		for c: Array in at._copies:
			near = near or (int(c[0]) <= n and n - int(c[0]) < MwSplatterAtlas.COPY_STEP)
		assert_true(near, "a copy just before %d" % n)
		at.seek(n)
		if digests.has(n):
			assert_eq(at.digest(), digests[n], "after %d operations" % n)
	at.seek(0)
	var calls := 0
	while at.shown() != last and calls < 1000:
		var before := at.shown()
		at.seek_toward(last, 1)
		assert_gt(at.shown(), before if before <= last else -1, "on its way")
		calls += 1
	assert_eq(at.shown(), last)
	assert_eq(at.digest(), digests[last], "the same texels, a share at a time")
	assert_true(at._copies.size() <= MwSplatterAtlas.COPY_KEEP)


## The same paint live and when reached by seeking back and forth (the
## replays), whatever copies were kept on the way.
func test_seek_gives_the_same_paint() -> void:
	if not need_rom():
		return
	var at := MwSplatterAtlas.new()
	var digests := {0: at.digest()}
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	for i in 160:
		match i % 4:
			0:
				at.ice_stamp(1 + i % 2, _frame(1 + i % 3), rng.randf_range(-150, 150), rng.randf_range(-350, 360),
						rng.randf_range(-PI, PI), 0.5, i % 3 == 0)
			1:
				at.wall_stamp(1 + i % 2, _frame(5), rng.randf_range(0, 2100), 1.0, false)
			2:
				at.pool(1, rng.randf_range(-150, 150), rng.randf_range(-350, 360), 9, i)
			3:
				at.streak(0, 0, 0, 0, Vector2(rng.randf_range(-150, 150), rng.randf_range(-300, 300)),
						Vector2(rng.randf_range(-150, 150), rng.randf_range(-300, 300)))
		digests[at.count()] = at.digest()
	var last := at.count()
	for n in [37, 3, 150, 0, 99, last, 64, 1]:
		var want: int = n
		while not digests.has(want):
			want -= 1
		at.seek(want)
		assert_eq(at.digest(), digests[want], "after %d operations" % want)


## The 3D view seeks a replay's paint at most PAINT_USEC a rendered frame
## (owner, 2026-10-15: rewinding dropped the frame rate badly, then replays
## still juddery and slow; the game's screens: auto_blend): a frame far back
## catches up over the frames after - the ticks of one slow frame never seek
## again - and shows the same texels; the live paint's latest at once, and
## without auto_blend everything at once.
func test_the_view_seeks_the_paint_a_share_a_frame() -> void:
	if not need_rom():
		return
	var at := MwSplatterAtlas.new()
	for k in 3:
		_paint_160(at)
	var target := at.count() - 1
	at.seek(target)
	var want := at.digest()
	at._copies.clear()                          # (far from any copy: from the checkpoint before)
	at.seek(0)
	var t0 := Time.get_ticks_usec()
	at.seek_toward(target, -1)
	assert_gt(Time.get_ticks_usec() - t0, 4 * MwRinkView3D.PAINT_USEC, "much more than a frame's share")
	at._copies.clear()
	at.seek(0)
	var view := (load("res://src/rink3d/rink_view_3d.tscn") as PackedScene).instantiate() as MwRinkView3D
	add_child_autofree(view)
	view._paint = at
	view._paint_ops = target
	view.auto_blend = true
	view.set_process(false)                     # (its own blends would seek too: this test's calls only)
	view._paint_seek()
	var first := at.shown()
	assert_lt(first, target, "not all in one frame")
	view._paint_seek()
	assert_eq(at.shown(), first, "nothing more in the same frame")
	var frames := 1
	while at.shown() != target and frames < 400:
		await wait_frames(1)
		view._paint_seek()
		frames += 1
	assert_eq(at.shown(), target, "caught up in %d frames" % frames)
	assert_eq(at.digest(), want, "the same texels")
	view.auto_blend = false
	at.seek(0)
	view._paint_seek()
	assert_eq(at.shown(), target, "without auto_blend: at once")
	at.seek(10)                                 # (a replay rewound it, live play goes on)
	view._paint_ops = at.count()
	view._paint_seek()
	assert_eq(at.shown(), at.count(), "the live paint's latest at once")
