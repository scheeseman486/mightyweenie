class_name MwRouter
extends RefCounted
## Moves between screens by the original's screen IDs and drives them on the
## 60 Hz tick (docs/scenes.md, docs/re/timing.md).
##
## [method step] is one tick: the fader advances, a pending screen change
## happens once its fade-out has finished (at once without one), and the top screen gets a pass
## whenever its pass clock says so (menus every tick, gameplay every 2 ticks;
## or the original's recorded passes in replay mode). A pass sees the input
## sampled when it started. The `Router` autoload steps it from
## _physics_process; tests step it by hand.

signal tick_started(tick: int)
signal screen_entered(id: int, visit: int, tick: int, previous: int)
signal screen_resumed(id: int, visit: int, tick: int)
## After a screen's pass: {"screen", "visit", "pass", "tick", "elapsed"}.
signal pass_ended(boundary: Dictionary)

var tick := 0
var clock: MwPassClock
var fader: MwScreenFader
var input: MwInputSource = MwInputSource.new()
## Where screen scenes are added (the scene tree root in the game).
var host: Node
## Screens, bottom to top; the top one is active.
var stack: Array[MwScreen] = []
## Screen IDs in the order they were entered (pushes included).
var history: Array[int] = []
var fade_ticks := MwScreenFader.DEFAULT_TICKS
## The game session handed to every screen.
var session := MwSession.new()
## Makes the screen for an ID or extra key; default: instantiate its scene
## (MwScreens.scene_path). Tests swap in stand-ins.
var factory: Callable = MwRouter.instantiate_scene

var _pending := {}          # {"op": "go"/"push"/"pop", "id", "data", "fade"}
var _frame := MwInputFrame.new()
var _last_held := {}
var _visits := {}


func _init(host_node: Node, screen_fader: MwScreenFader, pass_clock: MwPassClock = null) -> void:
	host = host_node
	fader = screen_fader
	clock = pass_clock if pass_clock else MwPassClock.realtime()


func current() -> MwScreen:
	return stack.back() if not stack.is_empty() else null


func current_id() -> int:
	var s := current()
	return s.screen_id if s else MwScreens.BOOT


## Take an existing scene as the first screen (the project's main scene, or a
## screen run on its own from the editor).
func adopt(screen: MwScreen, data := {}) -> void:
	_enter(screen, screen.screen_id, data, -1)


## Leave the current screen(s) for [param id]; the fade-out takes
## [param ticks] (-1: [member fade_ticks]).
func go(id: int, data := {}, fade := true, ticks := -1) -> void:
	_request({"op": "go", "id": id, "data": data, "fade": fade, "ticks": ticks})


## Show [param id] (an ID or an MwScreens.EXTRA key) over the current screen.
func push(id: Variant, data := {}, fade := true) -> void:
	_request({"op": "push", "id": id, "data": data, "fade": fade})


## Close the top screen and resume the one underneath.
func pop(fade := true) -> void:
	_request({"op": "pop", "fade": fade})


func busy() -> bool:
	return not _pending.is_empty()


## One 60 Hz tick.
func step() -> void:
	tick += 1
	tick_started.emit(tick)
	input.tick()
	fader.step()
	# a change with a fade-out waits for it; one without happens now (a
	# fade-in still running carries on into the next screen)
	if not _pending.is_empty() and (not _pending.fade or not fader.busy()):
		_apply(_pending)
		_pending = {}
	if not _pending.is_empty():
		return                    # fading out: the leaving screen gets no passes
	var top := current()
	if top == null:
		return
	for b in clock.due(tick):
		top._screen_pass(int(b.elapsed), _frame)
		pass_ended.emit(b)
		_sample()
		if not _pending.is_empty() or current() != top:
			break


func _request(req: Dictionary) -> void:
	if not _pending.is_empty():
		return                    # one change at a time; the first request wins
	_pending = req
	if req.fade and current() != null:
		var t := int(req.get("ticks", -1))
		fader.fade_out(t if t > 0 else fade_ticks)


func _apply(req: Dictionary) -> void:
	var prev := current_id()
	match req.op:
		"go":
			for s in stack:
				s.queue_free()
				if s.get_parent():
					s.get_parent().remove_child(s)
			stack.clear()
			_enter(_instantiate(req.id), req.id, req.data, prev)
		"push":
			var under := current()
			if under:
				under.visible = false
			_enter(_instantiate(req.id), req.id, req.data, prev)
		"pop":
			var top: MwScreen = stack.pop_back()
			top.get_parent().remove_child(top)
			top.queue_free()
			var under := current()
			if under:
				under.visible = true      # keeps its own previous screen (D7)
				clock.resume(under.screen_id, under.visit)
				screen_resumed.emit(under.screen_id, under.visit, tick)
				_sample()
				under._resume_screen()
	var entered := current()
	if fader.coverage() > 0.0 and not (entered and entered.fades_in_itself and req.op != "pop"):
		fader.fade_in(fade_ticks)    # the new screen fades in from the cover


func _instantiate(id: Variant) -> MwScreen:
	var s: MwScreen = factory.call(id)
	if id is int:
		s.screen_id = id
	return s


## The scene of screen [param id], instantiated.
static func instantiate_scene(id: Variant) -> MwScreen:
	var path := MwScreens.scene_path(id)
	var packed := load(path) as PackedScene
	assert(packed != null, "no scene for screen %s at %s" % [str(id), path])
	var s := packed.instantiate() as MwScreen
	assert(s != null, "%s: root must extend MwScreen" % path)
	return s


func _enter(screen: MwScreen, id: Variant, data: Dictionary, prev: int) -> void:
	var sid: int = id if id is int else (stack.back().screen_id if not stack.is_empty() else -1)
	screen.session = session
	screen.fader = fader
	if screen.get_parent() == null:
		host.add_child(screen)
	stack.append(screen)
	if not screen.exit_requested.is_connected(go):
		screen.exit_requested.connect(go)
		screen.push_requested.connect(func(what: Variant, d: Dictionary) -> void: push(what, d))
		screen.pop_requested.connect(func() -> void: pop())
	screen.entry = MwScreens.entry(id)
	screen.previous = prev
	if id is int:
		_visits[sid] = int(_visits.get(sid, 0)) + 1
		screen.visit = _visits[sid]
		history.append(sid)
		clock.screen_entered(sid, tick)
		screen_entered.emit(sid, screen.visit, tick, prev)
	else:
		# an extra scene (password) runs under its host's ID and pass clock
		screen.screen_id = sid
		screen.visit = int(_visits.get(sid, 0))
	if stack.size() == 1 and host.is_inside_tree() and host == host.get_tree().root:
		host.get_tree().current_scene = screen
	_sample()
	screen._enter_screen(data)


## Input for the pass that starts now.
func _sample() -> void:
	var held := input.sample(MwScreens.contexts(current_id()) if current() else [])
	_frame = MwInputFrame.make(held, _last_held)
	_frame.pressed.merge(input.taps())
	_last_held = held
