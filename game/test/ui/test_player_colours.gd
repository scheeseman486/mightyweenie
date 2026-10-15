extends "res://test/rom/rom_test_base.gd"
## Plan 34: the twelve players' colours (MwPlayerColours) - players 1-4 the
## original's crossbones colours, 5-12 the port's, apart from each other,
## the CPU's grey, the ice and the crossbones' own colours (the colour
## check, tools/bin/colour-check, also draws the contact sheet).


func test_ciede2000_matches_the_published_pairs() -> void:
	# Sharma, Wu and Dalal (2005), test data pairs 1, 7, 17 and 25
	var pairs := [[Vector3(50, 2.6772, -79.7751), Vector3(50, 0, -82.7485), 2.0425],
		[Vector3(50, 0, 0), Vector3(50, -1, 2), 2.3669],
		[Vector3(50, 2.5, 0), Vector3(73, 25, -18), 27.1492],
		[Vector3(60.2574, -34.0099, 36.2677), Vector3(60.4626, -34.1751, 39.4387), 1.2644]]
	for p in pairs:
		assert_almost_eq(MwPlayerColours.ciede2000_lab(p[0], p[1]), p[2], 0.0001)
		assert_almost_eq(MwPlayerColours.ciede2000_lab(p[1], p[0]), p[2], 0.0001, "symmetric")


func test_the_ports_colours_are_genesis_colours() -> void:
	assert_eq(MwPlayerColours.PORT.size(), MwPlayerColours.PLAYERS - 4)
	for w in MwPlayerColours.PORT:
		assert_eq(w & ~0xEEE, 0, "%03X: the console's levels" % w)


func test_players_one_to_four_keep_the_originals_crossbones() -> void:
	if not need_rom():
		return
	var line := MwScreenPalettes.palette(4).build(rom).slice(48, 64)
	var seen := {}
	for k in 5:
		var i := MwPlayerColours.face_index(rom, k)
		assert_true(i > 0 and i < 16, "frame %d has a colour of its own" % k)
		seen[i] = true
	assert_eq(seen.size(), 5, "five different faces")
	for pad in 4:
		assert_eq(MwPlayerColours.face(rom, pad + 1), line[MwPlayerColours.face_index(rom, pad + 1)],
				"player %d" % (pad + 1))
	assert_eq(MwPlayerColours.cpu_face(rom), line[MwPlayerColours.face_index(rom, 0)])
	assert_eq(MwPlayerColours.shared_indices(rom).size(), 3, "outline, shade and highlight in every frame")
	assert_eq(MwPlayerColours.face(rom, 5), MwPlayerColours.PORT[0])
	assert_eq(MwPlayerColours.face(rom, 12), MwPlayerColours.PORT[7])


func test_the_colours_pass_the_check() -> void:
	if not need_rom():
		return
	assert_eq(MwPlayerColours.check(rom), [] as Array[String])
	assert_gte(MwPlayerColours.closest(rom), MwPlayerColours.APART, "no two players alike")
	assert_eq(MwPlayerColours.ice(rom).size(), 3, "the bare ice's colours (two ice palettes share one)")
