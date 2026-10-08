extends "res://test/rom/rom_test_base.gd"
## [MwBetweenPlays]' hook for the checks: [member MwBetweenPlays.on_sim_made]
## gets the sim once, made but not set up yet (`test/screens/visual_check.gd`
## gives it the recording's hooks and RAM there).


func test_on_sim_made_comes_before_the_set_up() -> void:
	if not need_rom():
		return
	var node: MwBetweenPlays = (load(MwScreens.scene_path(12)) as PackedScene).instantiate()
	node.screen_id = 12
	node.previous = 5
	var seen := []
	node.on_sim_made = func(sim: MwScreenSim) -> void: seen.append([sim, sim.s])
	add_child_autofree(node)
	node._enter_screen({})
	assert_eq(seen.size(), 1, "called once")
	assert_eq(seen[0][0], node.sim, "with the scene's sim")
	assert_null(seen[0][1], "before its set-up gave it the game's state")
	assert_not_null(node.sim.s, "then set up")


func test_without_the_hook_nothing_changes() -> void:
	if not need_rom():
		return
	var node: MwBetweenPlays = (load(MwScreens.scene_path(12)) as PackedScene).instantiate()
	node.screen_id = 12
	node.previous = 5
	add_child_autofree(node)
	node._enter_screen({})
	assert_false(node.on_sim_made.is_valid())
	assert_not_null(node.sim.s)
	assert_null(node.sim.hooks, "live play: no comparison hooks")
