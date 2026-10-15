extends RefCounted
## Plan 40 (T3): a screen test's rig - a router on a host node under the
## test (its fader, a session, the input: a [Pad]), the screen it starts on,
## the steps, the presses and the waits the screen tests share. Every timing
## is a parameter: each test keeps the presses and settles its assertions
## were written for. Free it with [method free_host] (after_each).
##
##   var rig := ScreenRig.new()
##   rig.make(self)                 # a GutTest is the parent
##   rig.open(MwScreens.FRONT_MENU)
##   rig.press("ui_down")
##   assert_true(rig.until(MwScreens.OPTIONS))

const Pad := preload("res://test/support/pad.gd")

var host: Node
var router: MwRouter
var pad: Pad


## A router on a new host node under [param parent] (the test): its fader,
## [param session] (null: MwSession.new(1, 1)), [param input] (null: a new
## [Pad], [member pad]).
func make(parent: Node, session: MwSession = null, input: MwInputSource = null) -> MwRouter:
	host = Node.new()
	parent.add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	router = MwRouter.new(host, fader)
	router.session = session if session != null else MwSession.new(1, 1)
	if input == null:
		pad = Pad.new()
		input = pad
	router.input = input
	return router


## Screen [param id] adopted with [param data] (MwRouter.instantiate_scene),
## the fader uncovered after it - or, [param covered], covered before it and
## left so (the title's own fade-in). Returns the screen.
func open(id: int, data := {}, covered := false) -> MwScreen:
	var scene := MwRouter.instantiate_scene(id)
	scene.screen_id = id
	if covered:
		router.fader.cover()
	router.adopt(scene, data)
	if not covered:
		router.fader.uncover()
	return scene


## [param ticks] router steps.
func run(ticks: int) -> void:
	for i in ticks:
		router.step()


## [param actions] held for [param hold_ticks] ticks, then let go and [param after]
## ticks run.
func hold(actions: Dictionary, hold_ticks: int, after: int) -> void:
	pad.held = actions
	run(hold_ticks)
	pad.held = {}
	run(after)


## A press of [param action]: the bare menu action, with [param player]
## (> 0) also its "p<player>_" twin; held [param hold_ticks], then [param
## after] ticks.
func press(action: String, hold_ticks := 3, after := 10, player := 0) -> void:
	var a := {action: true}
	if player > 0:
		a["p%d_%s" % [player, action]] = true
	hold(a, hold_ticks, after)


## Steps until screen [param id] is the current one and the router is not
## busy (at most [param limit] steps), then [param settle] more; true if it
## got there.
func until(id: int, limit := 900, settle := 0) -> bool:
	for i in limit:
		router.step()
		if router.current_id() == id and not router.busy():
			run(settle)
			return true
	return false


## Steps until [param done] says so (at most [param limit] steps); true if it did.
func until_true(done: Callable, limit := 900) -> bool:
	for i in limit:
		if done.call():
			return true
		router.step()
	return done.call()


## The current screen (the top of the stack).
func current() -> Node:
	return router.current()


## The host freed (after_each): the screens, the fader, the router's nodes.
func free_host() -> void:
	if host != null and is_instance_valid(host):
		host.free()
	host = null
