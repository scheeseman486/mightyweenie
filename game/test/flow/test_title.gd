extends "res://test/rom/rom_test_base.gd"
## Screen 0 (developer logo, title, credits) against the original: its
## timeline (compare/fixtures/title_timeline.json, traced from the original),
## the title's band and sprites (positions from the original's tables), the
## sparkle rules and the starfield (docs/re/title.md).

## Load-time differences: the original spends 0-3 ticks drawing a page or
## loading a part; we spend fixed ticks (MwTitleScreen constants).
const TOLERANCE := 4

var host: Node
var router: MwRouter
var title: MwTitleScreen
var events := {}
var pages := []
var _fixture: Dictionary


var _front_menu := true


func before_all() -> void:
	super.before_all()
	_fixture = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/title_timeline.json")))
	_front_menu = MwSettings.front_menu
	MwSettings.front_menu = false         # the original's title -> credits -> main menu


func after_all() -> void:
	MwSettings.front_menu = _front_menu


func after_each() -> void:
	if host:
		host.free()
		host = null
	if is_instance_valid(title) and not title.is_inside_tree():
		title.free()              # left by the router (queued for deletion)


## A router with the title adopted at tick 0 (covered, as after boot).
func _start(script_text := "") -> MwScriptPlayer:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	router = MwRouter.new(host, fader)
	router.session = MwSession.new(0x61F2415D, 0x1234567)
	var player: MwScriptPlayer = null
	if script_text != "":
		var script := MwInputScript.parse(script_text, "title")
		assert_eq(script.error, "")
		player = MwScriptPlayer.new(script)
		var source := MwScriptedInput.new(player)
		source.attach(router)
		router.input = source
	title = (load("res://scenes/title/title.tscn") as PackedScene).instantiate() as MwTitleScreen
	events = {}
	pages = []
	title.milestone.connect(_on_milestone)
	router.screen_entered.connect(func(id: int, _v: int, tick: int, _p: int) -> void:
		if id == 1 and not events.has("menu"):
			events["menu"] = tick)
	fader.cover()
	router.adopt(title)
	return player


func _on_milestone(milestone_name: String, at: int) -> void:
	match milestone_name:
		"page":
			pages.append([at])
		"page_fade_in", "page_fade_out":
			pages.back().append(at)
		_:
			if not events.has(milestone_name):
				events[milestone_name] = at


func _run_until_menu(limit := 7000) -> void:
	var n := 0
	while not events.has("menu") and n < limit:
		router.step()
		n += 1


func _near(got: int, want: int, what: String) -> void:
	assert_almost_eq(got, want, TOLERANCE, "%s: %d vs the original's %d" % [what, got, want])


func test_timeline_without_input_matches_the_original() -> void:
	_start()
	_run_until_menu()
	var want: Dictionary = _fixture["no_input"]
	for k in ["logo_start", "logo_end", "title_start", "title_fade_in", "title_fade_out", "credits",
			"credits_end", "credits_done", "menu"]:
		assert_true(events.has(k), k)
		_near(int(events.get(k, -999)), int(want[k]), k)
	var wp: Array = want["pages"]
	assert_eq(pages.size(), wp.size(), "19 pages")
	for i in mini(pages.size(), wp.size()):
		for j in 3:
			_near(int(pages[i][j]), int(wp[i][j]), "page %d [%d]" % [i, j])
		# what the code fixes exactly: fade in 30 + hold 120, fade out 30
		assert_eq(int(pages[i][2]) - int(pages[i][1]), int(wp[i][2]) - int(wp[i][1]), "page %d shown" % i)
		if i + 1 < pages.size():
			assert_eq(int(pages[i + 1][0]) - int(pages[i][2]), int(wp[i + 1][0]) - int(wp[i][2]), "page %d out" % i)
	assert_eq(int(events["logo_end"]) - int(events["logo_start"]), 180)
	assert_eq(int(events["credits_end"]) - int(pages.back()[2]), 30)
	assert_eq(int(events["credits_done"]) - int(events["credits_end"]), 30)


func test_skips_match_the_original() -> void:
	var presses: Array = _fixture["skips"]["presses"]
	var lines := PackedStringArray()
	for p in presses:
		lines.append("@screen 0 +%d P1 %s" % [int(p["tick"]), str(p["button"])])
	lines.append("@screen 1 +10 END")
	_start("\n".join(lines))
	_run_until_menu(4000)
	var want: Dictionary = _fixture["skips"]["events"]
	for k in ["logo_end", "title_start", "title_fade_out", "credits", "credits_end"]:
		_near(int(events.get(k, -999)), int(want[k]), "skip " + k)
	assert_eq(pages.size(), (want["pages"] as Array).size(), "pages shown before the skip")
	# Known difference: we fade out (30 ticks) before entering the main menu;
	# the original enters it at once and the fade overlaps the menu's load.
	assert_almost_eq(int(events["menu"]) - int(events["credits_end"]), int(want["menu"]) - int(want["credits_end"]), 2,
			"the menu follows the skip at once")


func test_title_layout_comes_from_the_original_tables() -> void:
	if not need_rom():
		return
	_start()
	# band table $1BABA: row bytes, VRAM, dest stride, src stride, rows, source
	var pic := MwGfx.picture(rom, 0x30148)
	var map_base := int(pic["map"])
	var layers := [title.get_node("Title/Top"), title.get_node("Title/Bottom")] + title.bands
	var a := 0x1BABA
	for i in 6:
		var vram := MwGfx.u16(rom, a + 2)
		var rows := MwGfx.u16(rom, a + 8)
		var src := MwGfx.u32(rom, a + 10)
		var layer: RomTileMapLayer = layers[i]
		assert_eq(layer.region, Rect2i(0, (src - map_base) / 80, 40, rows), "band table %d" % i)
		assert_eq(layer.at, Vector2i(0, (vram - 0xE000) / 128), "band table %d plane row" % i)
		a += 14
	# sprites: $1BB16 drip, $1BB0E left eye, x $B6 (code) + $1BB12 right eye
	assert_eq(title.drip.position, Vector2(MwGfx.u16(rom, 0x1BB16), MwGfx.u16(rom, 0x1BB18)))
	assert_eq(title.drip.attr_xor, MwGfx.u16(rom, 0x1BB1C))
	assert_eq(title.eyes[0].position, Vector2(MwGfx.u16(rom, 0x1BB0E), MwGfx.u16(rom, 0x1BB10)))
	assert_eq(title.eyes[1].position, Vector2(MwGfx.u16(rom, 0x12BE), MwGfx.u16(rom, 0x1BB10)))
	assert_eq(title.eyes[0].attr_xor, MwGfx.u16(rom, 0x1BB14))
	assert_eq(title.sparkles[0].attr_xor, MwGfx.u16(rom, 0x1BB20))
	# developer logo: map_copy params at $142A -> VRAM $F400 = window ($F000) row 8
	assert_eq(MwGfx.u16(rom, 0x142C), 0xF400)
	assert_eq(title.logo.at, Vector2i(0, (0xF400 - 0xF000) / 128))
	assert_eq(title.logo.map, "picture_039b9e")


func test_band_cycles_every_7_ticks() -> void:
	_start()
	while title.part != MwTitleScreen.Part.TITLE:
		router.step()
	var start := router.tick
	var seen := []
	for i in 7 * 8:
		router.step()
		if (router.tick - start) % 7 == 0:
			seen.append(title.band)
	assert_eq(seen, [1, 2, 3, 0, 1, 2, 3, 0])
	var shown := title.bands.filter(func(b: RomTileMapLayer) -> bool: return b.visible)
	assert_eq(shown.size(), 1)


func test_title_sprites_animate_on_ticks() -> void:
	if not need_rom():
		return
	_start()
	while title.part != MwTitleScreen.Part.TITLE:
		router.step()
	var speed := MwGfx.u16(rom, 0x4B70E)        # 8.8 frames per tick
	var steps := 200
	for i in steps:
		router.step()
	var expect := (((1 + steps) * speed) & 0xFFFF) % (MwGfx.u8(rom, 0x4B70E + 3) << 8) >> 8
	assert_eq(title.eyes[0].state.frame, expect)
	assert_eq(title.eyes[0].frame, expect)
	assert_true(title.eyes[0].is_running(), "the eyes loop")


func test_sparkles_follow_the_original_rules() -> void:
	_start()
	while title.part != MwTitleScreen.Part.TITLE:
		router.step()
	var spawned := 0
	for i in 2000:
		var before := title.sparkles.map(func(s: RomSprite) -> bool: return s.visible)
		router.step()
		for k in 3:
			var s: RomSprite = title.sparkles[k]
			if s.visible and not before[k]:
				spawned += 1
				var p := Vector2i(s.position)
				assert_between(p.y, 24, 104)
				assert_between(p.x, 24, 296)
				assert_true(p.y <= 27 or p.x < 76 or p.x > 209, "outside the logo's middle: %s" % p)
	assert_between(spawned, 20, 200, "about 1 in 64 per idle sparkle and pass")
	var rng := MlhRng.new(99)
	for i in 500:
		var p := MwTitleScreen.sparkle_position(rng)
		assert_true(p.y <= 27 or p.x < 76 or p.x > 209)


func test_credit_pages_from_the_rom() -> void:
	if not need_rom():
		return
	_start()
	while title.page < 1:
		router.step()
	# page 2 (index 1): a heading in $22BEC on row 7, body lines from row 11 every 3
	var lines := title.page_root.get_children()
	var strings := MwGfx.string_list(rom, MwGfx.u32(rom, MwTitleScreen.PAGES + 4))
	assert_eq(lines.size(), strings.size())
	var head: RomText = lines[0]
	assert_eq(head.font, "font_022bec")
	assert_eq(head.cell.y, 7)
	assert_eq(head.start_cell().x, (40 - head.width) / 2, "centred")
	for i in range(1, lines.size()):
		var l: RomText = lines[i]
		assert_eq(l.font, "font_022ee0")
		assert_eq(l.cell.y, 11 + 3 * (i - 1))
		assert_eq(l.string_address, strings[i])
	while title.page < MwTitleScreen.PAGE_COUNT - 1:
		router.step()
	var sprites := title.page_root.get_children().filter(func(n: Node) -> bool: return n is RomSprite)
	assert_eq(sprites.size(), 2, "the last page's two sprites")
	assert_eq((sprites[0] as RomSprite).position, Vector2(160, 104))
	assert_eq((sprites[1] as RomSprite).position, Vector2(160, 131))


func test_starfield_scrolls_one_step_per_tick() -> void:
	if not need_rom():
		return
	var sf := RomStarfield.new()
	add_child_autofree(sf)
	var dirs := []
	for d in 8:
		sf.set_direction(d)
		dirs.append(Vector2i(sf.vx, sf.vy))
	assert_eq(dirs, [Vector2i(100, 0), Vector2i(72, 72), Vector2i(0, 100), Vector2i(-72, 72),
			Vector2i(-100, 0), Vector2i(-72, -72), Vector2i(0, -100), Vector2i(72, -72)])
	sf.set_direction(5)
	for i in 600:
		sf.step()
	assert_eq(sf.scroll(), Vector2i(floori(-72 * 600 / 256.0), floori(-72 * 600 / 256.0)))
	assert_eq(RomStarfield.asr8(-1), -1)
	assert_eq(RomStarfield.asr8(-256), -1)
	assert_eq(RomStarfield.asr8(-257), -2)
	assert_eq(RomStarfield.asr8(511), 1)
	var plane: RomTileMapLayer = sf.get_node("Plane")
	var s := sf.scroll()
	assert_eq(plane.position, Vector2(posmod(s.x, 256) - 256, -posmod(s.y, 256)))
	var rng := MlhRng.new(7)
	var expect := ((MlhRng.new(7).next_state() & 0xE) >> 1)
	sf.start(rng)
	assert_eq(Vector2i(sf.vx, sf.vy), dirs[expect])
	assert_eq(sf.scroll(), Vector2i.ZERO)
