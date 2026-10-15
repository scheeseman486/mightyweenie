class_name MwRouter
extends RefCounted
## Moves between screens by the original's screen IDs and drives them on the
## 60 Hz tick (docs/scenes.md, docs/re/timing.md).
##
## [method step] is one tick: the sound driver's VBlank work ([member
## audio]), the fader advances, a pending screen change happens once its
## fade-out has finished (at once without one), and the top screen gets a
## pass whenever its pass clock says so (menus every tick, gameplay every 2
## ticks; or the original's recorded passes in replay mode). A pass sees the
## input sampled when it started. The `Router` autoload steps it from
## _physics_process; tests step it by hand.
##
## Plan 35 (docs/net.md): a screen change happens on its tick however long
## the next screen takes to load (the load holds the picture, never the
## timeline: the tick is counted, not timed); with the pass clock in stream
## mode a tick runs only when the input stream has it ([method step] returns
## false and nothing moves); the sound driver steps with the ticks, so its
## "still playing?" answers are the same on every machine, headless or not
## ([method use_driver_model]).
##
## A push whose data says [code]"over": true[/code] (owner, 2026-10-12: the
## line-up panels crash in over the last menu screen, no fade;
## backing out, they pull back off it) leaves the screen under in sight - it
## takes no passes, as under any push - and hands it to the new one as data
## "under" ([constant UNDER]; not in the request itself).
##
## Plan 35 work item 6: a screen change ("go") is a safe point for a resync
## snapshot - [signal entering] fires once the screens left are gone and
## before the next is made, and [method resume_entry] goes on from that very
## point on a machine that took the game up from the snapshot
## ([method snapshot_state], [method restore_state]: what of the router it
## carries).

## [method step] began tick [param tick] (the count just went up, the sound driver
## stepped); the input, the fader, a pending change and the passes follow.
signal tick_started(tick: int)
## Screen [param id] (an ID, not an extra scene) entered: its [param visit]th visit, at
## [param tick], from screen [param previous] ([constant MwScreens.BOOT]: none). Fires
## before the screen's own [code]_enter_screen[/code].
signal screen_entered(id: int, visit: int, tick: int, previous: int)
## Screen [param id] (visit [param visit]) is on top again at [param tick]: the one
## above it was popped.
signal screen_resumed(id: int, visit: int, tick: int)
## After a screen's pass: {"screen", "visit", "pass", "tick", "elapsed"}.
signal pass_ended(boundary: Dictionary)
## Plan 35 work item 6: a screen change happening - the screens left are
## gone (their exits done), the next one not made yet: [param request]
## ({"op": "go", "id", "data", "fade", "ticks"}) is about to be entered
## from [param previous]. A safe point for a resync snapshot (MwNetMatch).
signal entering(request: Dictionary, previous: int)

## Plan 40 (S12): the ticks a second (the original's NTSC VBlank) - every
## "60" the port's timing means.
const TICK_HZ := 60
## The data key a screen pushed "over" another finds that screen under.
const UNDER := "under"

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
## The sound driver stepped at the start of every tick (the original's
## VBlank work comes first): the audio service with a display, the driver
## model alone otherwise ([method use_driver_model], adopted with the first
## screen: plan 40, D6); null: none (no ROM).
var audio: MwAudio = null
## Plan 41 work item 3: an online client's driver model apart from
## [member audio] ([method split_audio]): the game's calls and questions go
## to it, [member audio] is what is heard (MwSound.heard); null: [member
## audio] is both.
var model: MwAudio = null
## Plan 35 work item 4: what drives this router's ticks instead of the
## `Router` autoload's one step a physics frame (an online match,
## MwNetMatch): the autoload calls its [code]frame(now_ms) -> bool[/code]
## once a physics frame, and drops it when that returns false. Null: the
## autoload steps the router itself.
var driver: RefCounted = null

var _pending := {}          # {"op": "go"/"push"/"pop", "id", "data", "fade"}
var _frame := MwInputFrame.new()
var _last_held := {}
var _sampled := -1               # the tick [method _sample] last ran at (plan 41)
var _visits := {}


func _init(host_node: Node, screen_fader: MwScreenFader, pass_clock: MwPassClock = null) -> void:
	host = host_node
	fader = screen_fader
	clock = pass_clock if pass_clock else MwPassClock.realtime()


## Plan 41 (the run-ahead): the input the next pass will see (sampled after
## the last), the actions held then, and whether the screen's pads are
## remapped ([method _remaps]) - what a client's prediction needs to make
## the passes after it.
func pending_frame() -> MwInputFrame:
	return _frame


## The tick the next pass's input was sampled at (after the pass before;
## -1 none since the game began): a screen's pass draws before it - inside
## the pass, [method pending_frame] is still the pass's own.
func sampled_tick() -> int:
	return _sampled


## The actions held at the last input sample (the next sample's presses are measured
## from them).
func last_held() -> Dictionary:
	return _last_held


## Whether the screen on top reads its pads remapped to their players' inputs (plan 34;
## the rule is [method _remaps]'s).
func remaps() -> bool:
	return _remaps()


## Plan 34: the original's screens (the game setup to the scoreboards) read
## pads 1-4; in a match the controller selection chose, each pad gets its
## player's inputs (MwSession.pad_map). Not in the attract demo, nor on the
## port's own screens (their players are themselves). The analogue sticks
## go with the buttons. An extended set-up remaps nothing (its pad map is
## the identity: every player their own pad, MwHumans.pad_index).
func _remaps() -> bool:
	var id := current_id()
	return session != null and not session.attract and id >= 1 and id < MwScreens.FRONT_MENU \
			and not MwHumans.identity(session.pad_map)


## The screen on top (the active one); null with none.
func current() -> MwScreen:
	return stack.back() if not stack.is_empty() else null


## The ID of the screen on top; [constant MwScreens.BOOT] with none.
func current_id() -> int:
	var screen := current()
	return screen.screen_id if screen else MwScreens.BOOT


## Take an existing scene as the first screen (the project's main scene, or a
## screen run on its own from the editor).
func adopt(screen: MwScreen, data := {}) -> void:
	_default_driver()
	_enter(screen, screen.screen_id, data, -1)


## Plan 40 (D6, owner: one "still playing?" answer): a router with no sound
## driver of its own hears the driver's model ([method use_driver_model]) -
## unless a driver someone else holds is running (in the tree: a test's or
## a tool's own) - so every screen, a test's too, gets the answers the game
## gets. The model is the host's (it goes with it, and stops answering
## then). Without the ROM there is none.
func _default_driver() -> void:
	if audio != null or not MwRom.available():
		return
	if MwSound.driver != null and is_instance_valid(MwSound.driver) and MwSound.driver.is_inside_tree():
		return
	var driver_model := use_driver_model(MwRom.data())
	driver_model.tree_exiting.connect(func() -> void:
		if MwSound.driver == driver_model:
			MwSound.driver = null)
	if host != null:
		host.add_child(driver_model)


## Leave the current screen(s) for [param id]; the fade-out takes
## [param ticks] (-1: [member fade_ticks]).
func go(id: int, data := {}, fade := true, ticks := -1) -> void:
	_request({"op": "go", "id": id, "data": data, "fade": fade, "ticks": ticks})


## Show [param id] (an ID or an MwScreens.EXTRA key) over the current screen.
func push(id: Variant, data := {}, fade := true) -> void:
	_request({"op": "push", "id": id, "data": data, "fade": fade})


## Close the top screen and resume the one underneath, handing it
## [param result] (MwScreen._resume_screen's).
func pop(fade := true, result := {}) -> void:
	_request({"op": "pop", "fade": fade, "result": result})


## Whether a screen change is pending: asked for and not carried out yet (its fade-out
## runs; one change at a time).
func busy() -> bool:
	return not _pending.is_empty()


## The screen a pending change goes to (an ID or an EXTRA key; null: none,
## or a pop).
func pending_id() -> Variant:
	return _pending.get("id") if not _pending.is_empty() else null


## Plan 35 work item 4: leave for [param id] whatever was pending (an
## online match ended under the game: the host gone, a kick).
func force_go(id: int, data := {}) -> void:
	_pending = {}
	go(id, data)


## Plan 35 work item 4: a game afresh on this router, as every machine of an
## online match starts it from the start record - the screens gone (freed),
## nothing pending, no visits counted, the input's last sample forgotten;
## [param session_] the game's session, [param pass_clock] its clock (the
## stream mode's), the tick counter at [param tick_] (the record's). The
## caller then adopts the first screen ([method adopt]) under a covered
## fader.
func reset_game(session_: MwSession, pass_clock: MwPassClock, tick_: int) -> void:
	for screen in stack:
		if screen.get_parent():
			screen.get_parent().remove_child(screen)
		screen.queue_free()
	stack.clear()
	history.clear()
	_pending = {}
	_visits = {}
	_frame = MwInputFrame.new()
	_last_held = {}
	_sampled = -1
	session = session_
	clock = pass_clock
	tick = tick_


## The driver the game calls and asks: [member model] when split, else
## [member audio].
func game_audio() -> MwAudio:
	return model if model != null else audio


## Plan 41 work item 3 (an online client's match): [param on], the game's
## sound driver becomes a model of its own ([member model], from
## [member audio]'s state - both at power-on at a match's start) and
## [member audio] only what is heard ([MwHeard] as MwSound.heard) - played
## on the wall clock when it is heard at all ([method MwAudio.start_pump]:
## not stepped by this router, whose ticks hold for a late stream); off, one
## driver again, stepped by the ticks. Nothing without [member audio].
func split_audio(on: bool) -> void:
	if on and model == null and audio != null and not audio.rom.is_empty():
		model = MwAudio.new()
		model.name = "GameSound"
		model.setup(MwRom.data() if MwRom.available() else audio.rom, false, false)
		if host != null:
			host.add_child(model)
		model.reset()
		MwSound.driver = model
		MwSound.heard = MwHeard.new(audio, self)
		if audio.audible():
			audio.start_pump()             # heard on the wall clock (owner, 2026-10-13: the dropouts)
	elif not on and model != null:
		if audio != null:
			audio.stop_pump()              # (stepped by the ticks again)
		if MwSound.driver == model:
			MwSound.driver = audio
		MwSound.heard = null
		if audio != null:
			audio.session = session
		if model.is_inside_tree():
			model.queue_free()
		else:
			model.free()
		model = null


## Plan 35: the sound driver as a model only (no chips, no sound: the
## 68000 and Z80 sides and the enhancement voices' bookkeeping), stepped
## by this router's ticks and answering the game's "still playing?"
## ([member MwSound.driver]) - headless games, recordings and replays.
func use_driver_model(rom: PackedByteArray) -> MwAudio:
	if audio == null:
		audio = MwAudio.new()
		audio.name = "DriverModel"
		audio.setup(rom, false, false)
	MwSound.driver = audio
	return audio


## One physics frame of [member driver] (an online match) at [param
## now_ms]; it is dropped once its [code]frame[/code] returns false. Plan 45
## (stability M4): a script error in [code]frame[/code]'s own body ends it
## with false (a typed function's default) while the match goes on - its
## [code]over[/code] says so - and the match is left ([code]abandon[/code]:
## the router, its clock and its input handed back, the online pages shown)
## instead of the router keeping a stream nobody feeds and the game standing
## still. False when there is no driver now.
func drive(now_ms: int) -> bool:
	if driver == null:
		return false
	if not bool(driver.call("frame", now_ms)):
		if driver.has_method("over") and not driver.call("over"):
			push_error("MwRouter: the online match's frame stopped on an error - the match left")
			driver.call("abandon")
		driver = null
	return driver != null


## One 60 Hz tick; false when the pass clock holds it (stream mode: the
## input stream hasn't confirmed it yet).
func step() -> bool:
	if not clock.ready(tick + 1):
		return false
	if audio != null and not audio.pumping():
		audio.tick()              # the VBlank's sound driver work comes first (a pumped one keeps its own clock)
	if model != null:
		model.tick()              # (plan 41: an online client's game's own, beside what is heard)
	tick += 1
	tick_started.emit(tick)
	input.tick()
	fader.step()
	# a change with a fade-out waits for it; one without happens now (a
	# fade-in still running carries on into the next screen)
	if not _pending.is_empty() and (not _pending.fade or not fader.busy()):
		# taken off before it is carried out: a screen that asks to leave as
		# it enters (the rink's line-up forfeit - `rink_exit` in `$F8A4` -
		# or its period end with the clock at 0:00) asks for the next change,
		# which used to be dropped as "one change at a time" (owner's bug,
		# 2026-10-10: a freeze on the faceoff)
		var req := _pending
		_pending = {}
		_apply(req)
	return _passes()


## The rest of a tick: the top screen's passes due now.
func _passes() -> bool:
	var sound := game_audio()
	if sound != null:
		sound.session = session       # plan 39: the organ pool picks from this game's stream
	if model != null and audio != null:
		audio.session = null      # (plan 41: what is heard plays the model's pick, MwHeard)
	if not _pending.is_empty():
		return true               # fading out: the leaving screen gets no passes
	var top := current()
	if top == null:
		return true
	for b in clock.due(tick, top):
		top._screen_pass(int(b.elapsed), _frame)
		pass_ended.emit(b)
		_sample()
		if not _pending.is_empty() or current() != top:
			break
	return true


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
			for screen in stack:
				screen.queue_free()
				if screen.get_parent():
					screen.get_parent().remove_child(screen)
			stack.clear()
			entering.emit(req, prev)          # plan 35: a safe point for a resync snapshot
			_enter(_instantiate(req.id), req.id, req.data, prev)
		"push":
			var under := current()
			var data: Dictionary = req.data
			if under:
				if bool(data.get("over", false)):
					data = data.duplicate()
					data[UNDER] = under       # still in sight, under the new one
				else:
					under.visible = false
				under.pushed_at = tick
				under._cover_screen()
			_enter(_instantiate(req.id), req.id, data, prev)
		"pop":
			var top: MwScreen = stack.pop_back()
			top.get_parent().remove_child(top)
			top.queue_free()
			var under := current()
			if under:
				under.visible = true      # keeps its own previous screen (D7)
				under.away = tick - under.pushed_at
				clock.resume(under.screen_id, under.visit, tick if under.resume_fresh else -1)
				screen_resumed.emit(under.screen_id, under.visit, tick)
				_sample()
				under._resume_screen(req.get("result", {}))
	if _pending.is_empty():
		_fade_in_entered(req)
	# else the screen entered asked to leave at once: it stays covered while
	# that change's fade-out runs (from the cover to the cover), then goes


## After a change: the new screen fades in from the cover (unless it fades
## itself in).
func _fade_in_entered(req: Dictionary) -> void:
	var entered := current()
	if fader.coverage() > 0.0 and not (entered and entered.fades_in_itself and req.op != "pop"):
		fader.fade_in(fade_ticks)    # the new screen fades in from the cover


# --- plan 35 work item 6: resync snapshots ------------------------------------------------------

## A game taken up from a resync snapshot at its safe point ([signal
## entering]): the router's tick, visits, input and fade are the
## snapshot's already ([method reset_game], [method restore_state]); this
## does what that tick did from there on - the screen [param request] asks
## for entered from [param previous] (nothing pending meanwhile, as in
## [method step]: a change it asks for as it enters is the next), faded in,
## then the passes due this tick.
func resume_entry(request: Dictionary, previous: int) -> void:
	_pending = {}                 # as [method step] takes it off before entering
	_enter(_instantiate(request.id), request.id, request.data, previous)
	if _pending.is_empty():
		_fade_in_entered(request)
	_passes()


## What of the router a resync snapshot carries (its tick aside): the
## visits counted, the screens' history, the last sample's held actions
## (the next sample's presses are measured from them), the fade's length,
## the pass clock's visits and the fader's state.
func snapshot_state() -> Dictionary:
	return {"visits": _visits.duplicate(), "history": Array(history), "last_held": _last_held.duplicate(),
			"fade_ticks": fade_ticks, "clock": clock.snapshot_state(), "fader": fader.snapshot_state()}


## [method snapshot_state]'s [param d] back (after [method reset_game]).
func restore_state(d: Dictionary) -> void:
	_visits = {}
	var v: Variant = d.get("visits", {})
	if v is Dictionary:
		for k in v:
			_visits[k] = int(v[k])
	history.clear()
	var h: Variant = d.get("history", [])
	if h is Array:
		for id in h:
			history.append(int(id))
	var l: Variant = d.get("last_held", {})
	_last_held = (l as Dictionary).duplicate() if l is Dictionary else {}
	fade_ticks = int(d.get("fade_ticks", fade_ticks))
	var c: Variant = d.get("clock", {})
	clock.restore_state(c if c is Dictionary else {})
	var f: Variant = d.get("fader", {})
	fader.restore_state(f if f is Dictionary else {})


func _instantiate(id: Variant) -> MwScreen:
	var screen: MwScreen = factory.call(id)
	if id is int:
		screen.screen_id = id
	return screen


## The scene of screen [param id], instantiated. Plan 45 (stability L5): a
## scene that doesn't load (a damaged pack, a missing path) or whose root
## is no MwScreen gives a stand-in (MwPlaceholderScreen) that leaves for the
## main menu (screen 1) at once - release builds strip [code]assert[/code],
## and a null screen stopped the game.
static func instantiate_scene(id: Variant) -> MwScreen:
	var path := MwScreens.scene_path(id)
	var packed: PackedScene = load(path) as PackedScene if path != "" else null
	var node: Node = packed.instantiate() if packed != null else null
	var screen := node as MwScreen
	if screen != null:
		return screen
	if node != null:
		node.free()
	push_error("MwRouter: no screen scene for %s at %s - a stand-in leaves for the main menu" % [str(id), path])
	var stand_in := MwPlaceholderScreen.new()
	stand_in.auto_exit_ticks = 1
	stand_in.auto_exit = 1
	return stand_in


func _enter(screen: MwScreen, id: Variant, data: Dictionary, prev: int) -> void:
	var sid: int = id if id is int else (stack.back().screen_id if not stack.is_empty() else -1)
	screen.session = session
	screen.fader = fader
	if screen.get_parent() == null:
		host.add_child(screen)
	stack.append(screen)
	if not screen.exit_requested.is_connected(go):
		screen.exit_requested.connect(go)
		screen.push_requested.connect(func(what: Variant, d: Dictionary, f: bool) -> void: push(what, d, f))
		screen.pop_requested.connect(func(result: Dictionary, f: bool) -> void: pop(f, result))
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


## Plan 40 (I2): the input contexts of the screen on top (MwScreens.contexts;
## none without one) - the router's, the stream's and an online machine's
## sampling read them.
func contexts() -> Array:
	return MwScreens.contexts(current_id()) if current() else []


## Input for the pass that starts now.
func _sample() -> void:
	var held := input.sample(contexts())
	var taps := input.taps()
	var sticks := input.sticks()
	var heights := input.heights()
	if _remaps():
		var r := MwHumans.remapped(session.pad_map, held, taps, sticks, heights)
		held = r[0]
		taps = r[1]
		sticks = r[2]
		heights = r[3]
	_frame = MwInputFrame.make(held, _last_held)
	_frame.pressed.merge(taps)
	_frame.sticks = sticks
	_frame.heights = heights
	_frame.away = input.away()
	_frame.tick = input.tick_input()            # plan 40 (S7): every player's state as the wire has it
	if _remaps():
		_frame.pad_map = session.pad_map
	_last_held = held
	_sampled = tick
