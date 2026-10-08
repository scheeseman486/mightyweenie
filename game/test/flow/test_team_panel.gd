extends "res://test/rom/rom_test_base.gd"
## The main menu's team panels (MwTeamPanel): a team change while a player
## is shown, and the skater kept inside its panel's window.

var host: Node
var router: MwRouter
var menu: MwMainMenu


func before_each() -> void:
	if not need_rom():
		return
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	router = MwRouter.new(host, fader)
	router.session = MwSession.new(0x61F2415D, 0x1234567)
	router.input = MwLiveInput.new()          # nothing pressed
	menu = (load(MwScreens.scene_path(1)) as PackedScene).instantiate() as MwMainMenu
	menu.screen_id = 1
	router.adopt(menu)


func after_each() -> void:
	if host:
		host.free()
		host = null


## Steps until [param done] holds (at most [param limit] steps).
func _until(done: Callable, limit := 5000) -> bool:
	for i in limit:
		if done.call():
			return true
		router.step()
	return done.call()


func test_a_team_change_takes_the_portrait_away() -> void:
	if not need_rom():
		return
	var hit := [-1]                 # lambdas capture locals by value
	assert_true(_until(func() -> bool:
		for i in 2:
			if menu.panels[i].state == 100 and menu.panels[i].portrait.visible:
				hit[0] = i
				return true
		return false), "a star's portrait shows")
	if hit[0] < 0:
		return
	var p: MwTeamPanel = menu.panels[hit[0]]
	router.step()
	p.reset(p.team ^ 1)
	router.step()
	assert_false(p.portrait.visible, "the portrait goes with the old team")
	assert_eq(p.state, 0, "the new team's logo")
	assert_false(p.team_colours, "the panel colours are back")


func test_a_team_change_takes_the_skater_away() -> void:
	if not need_rom():
		return
	var hit := [-1]                 # lambdas capture locals by value
	assert_true(_until(func() -> bool:
		for i in 2:
			if menu.panels[i].skater.visible:
				hit[0] = i
				return true
		return false), "a skater shows")
	if hit[0] < 0:
		return
	var p: MwTeamPanel = menu.panels[hit[0]]
	p.reset(p.team ^ 1)
	router.step()
	assert_false(p.skater.visible)


func test_the_skater_is_clipped_to_its_window() -> void:
	if not need_rom():
		return
	for i in 2:
		var p: MwTeamPanel = menu.panels[i]
		var w: Rect2i = MwTeamPanel.WINDOWS[i]
		assert_true(p.skater_clip.clip_contents)
		assert_eq(Rect2i(p.skater_clip.get_rect()), w, "panel %d window" % i)
		assert_eq(p.skater.get_parent(), p.skater_clip)
	assert_true(_until(func() -> bool:
		return menu.panels[0].skater.visible or menu.panels[1].skater.visible), "a skater shows")
	for i in 2:
		var p: MwTeamPanel = menu.panels[i]
		if p.skater.visible:
			var at := p.skater.global_position
			var want := Vector2(RomStarfield.asr8(p.pos.x), RomStarfield.asr8(p.pos.y))
			assert_eq(at, want, "the skater stays where the original puts it")
