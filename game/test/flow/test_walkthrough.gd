extends GutTest
## The whole placeholder flow, driven like a player through an input script
## (scripted pads -> verbs per screen context), headless.

const SCRIPT := """
@screen 0 +40 P1 START      # developer logo -> title
@screen 0 +100 P1 A         # title -> credits
@screen 0 +200 P1 C         # credits -> main menu
@screen 1 +40 P1 START
@screen 4 +300 P1 A         # skips team A's coach at the period start
@screen 4 +700 P1 START     # open play: Start pauses
@screen 4 +740 P1 A         # A - REPLAY -> the instant replay
@screen 7 +40 P1 START      # its exit -> play goes on (6)
@screen 6 +40 END
"""

var host: Node
var _front_menu := true


func before_all() -> void:
	_front_menu = MwSettings.front_menu
	MwSettings.front_menu = false         # the original's flow (title -> credits -> main menu)


func after_all() -> void:
	MwSettings.front_menu = _front_menu


func after_each() -> void:
	if host:
		host.queue_free()


func test_walk_from_boot_to_the_instant_replay_and_back() -> void:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(1, 1)      # the match plays the same every run
	var script := MwInputScript.parse(SCRIPT, "walkthrough")
	assert_eq(script.error, "")
	var player := MwScriptPlayer.new(script)
	var source := MwScriptedInput.new(player)
	source.attach(router)
	router.input = source
	var boot := (load(MwScreens.scene_path(MwScreens.BOOT)) as PackedScene).instantiate() as MwScreen
	fader.cover()
	router.adopt(boot)
	var n := 0
	while not player.ended() and n < 5000:
		router.step()
		n += 1
	assert_true(player.ended(), "reached END (ticks: %d)" % n)
	assert_eq(router.history, [-1, 0, 1, 3, 4, 7, 6])
	assert_eq(router.current().entry, "continue")
