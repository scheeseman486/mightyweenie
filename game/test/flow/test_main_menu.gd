extends "res://test/rom/rom_test_base.gd"
## The main menu against the original: the same input scripts
## (compare/scripts/menu_*.mwi) leave the same setup bytes and stadium mode
## (compare/fixtures/menu_cases.json, recorded from the original), plus the
## menu data read from the ROM (docs/re/menus.md).

var host: Node
var _fixture: Dictionary


func before_all() -> void:
	super.before_all()
	_fixture = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/menu_cases.json")))


func after_each() -> void:
	if host:
		host.free()
		host = null


## Plays compare/scripts/<name>.mwi from the main menu; returns the visits
## [{screen, visit, setup, stadium_mode}] as the fixture has them.
func _play(case_name: String) -> Array:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(0x61F2415D, 0x1234567)
	var text := FileAccess.get_file_as_string(repo_path("compare/scripts/%s.mwi" % case_name))
	var script := MwInputScript.parse(text, case_name)
	assert_eq(script.error, "")
	var player := MwScriptPlayer.new(script)
	var source := MwScriptedInput.new(player)
	source.attach(router)
	router.input = source
	var visits := []
	router.screen_entered.connect(func(id: int, visit: int, _t: int, _p: int) -> void:
		visits.append({"screen": id, "visit": visit, "setup": "", "stadium_mode": null}))
	router.pass_ended.connect(func(_b: Dictionary) -> void:
		var v: Dictionary = visits.back()
		v["setup"] = router.session.setup.to_bytes().hex_encode()
		var cur := router.current()
		if cur is MwMainMenu:
			v["stadium_mode"] = (cur as MwMainMenu).stadium_mode & 0xFF)
	var menu := (load(MwScreens.scene_path(1)) as PackedScene).instantiate() as MwScreen
	menu.screen_id = 1
	router.adopt(menu)
	var n := 0
	while not player.ended() and n < 20000:
		router.step()
		n += 1
	assert_true(player.ended(), "%s reached END" % case_name)
	return visits


func _check(case_name: String) -> void:
	if not need_rom():
		return
	var want: Array = _fixture["cases"][case_name]["visits"]
	want = want.filter(func(v: Dictionary) -> bool: return int(v["screen"]) != 0)   # we start at the menu
	var got := _play(case_name)
	assert_eq(got.size(), want.size(), "%s: screens visited" % case_name)
	for i in mini(got.size(), want.size()):
		var g: Dictionary = got[i]
		var w: Dictionary = want[i]
		assert_eq(g["screen"], int(w["screen"]), "%s visit %d: screen" % [case_name, i])
		assert_eq(g["setup"], w["setup"], "%s visit %d (screen %d): setup bytes" % [case_name, i, int(w["screen"])])
		if w.has("stadium_mode"):
			assert_eq(g["stadium_mode"], int(w["stadium_mode"]), "%s visit %d: stadium mode" % [case_name, i])


func test_rows_like_the_original() -> void:
	_check("menu_rows")


func test_players_like_the_original() -> void:
	_check("menu_players")


func test_playoff_modes_like_the_original() -> void:
	_check("menu_playoffs")


func test_start_and_return_like_the_original() -> void:
	_check("menu_start")


func test_menu_data_from_the_rom() -> void:
	if not need_rom():
		return
	var rows := MwMenuRows.new(rom)
	assert_eq(rows.count(0), 23, "teams")
	assert_eq(rows.count(2), 5, "pad modes")
	assert_eq(rows.count(3), 5, "play modes")
	assert_false(rows.has_row(5), "the minutes byte has no row")
	assert_true(rows.has_row(MwMenuRows.STADIUM_ROW))
	assert_eq([rows.up(0), rows.up(1), rows.down(0), rows.down(4), rows.up(6)], [1, 0, 2, 6, 4])
	for t in MwTeams.COUNT:
		assert_eq(MwGfx.rom_string(rom, rows.string_of(0, 1, t)), MwGfx.rom_string(rom, MwTeams.name(rom, t)))


## Rows 3-9 draw into plane A (their items' plane object): the play mode
## row's highlight frame has its top edge on row 15 of plane A - not the
## window's, where the backdrop's skull is - and plane A shows below the
## window only (its row 15's last line through the 1-pixel scroll), as the
## original's VDP (owner's bug, 2026-10-08: a black line across the
## highlight, the skull's jaw cut).
func test_play_mode_highlight_in_plane_a() -> void:
	if not need_rom():
		return
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(1, 1)
	var menu := (load(MwScreens.scene_path(1)) as PackedScene).instantiate() as MwMainMenu
	menu.screen_id = 1
	router.adopt(menu)
	for i in 30:
		router.step()
	var window := menu.plane
	var plane_a := window.lower
	var clip := plane_a.get_parent() as Control
	assert_not_null(clip, "plane A in a clip")
	assert_true(clip.clip_contents)
	assert_eq(clip.position.y, 128.0, "below the window's 16 rows")
	assert_eq(plane_a.global_position.y, 1.0, "scrolled down 1 pixel")
	var row15 := func() -> Array:
		var out := []
		for x in 40:
			out.append(window.cell(x, 15))
		return out
	var backdrop: Array = row15.call()
	menu._move(3)
	for i in 10:
		router.step()
	assert_eq(row15.call(), backdrop, "the window's row 15 (the skull) untouched")
	assert_ne(int(plane_a.cell(10, 15)["key"]), 0, "the frame's top edge in plane A")
	menu._move(4)
	for i in 10:
		router.step()
	assert_eq(int(plane_a.cell(10, 15)["key"]), 0, "erased with the highlight")
	assert_eq(row15.call(), backdrop)
