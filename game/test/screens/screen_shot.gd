extends SceneTree
## Plan 40 (T8): any screen's picture after N ticks, through the router and
## the real scene - the review shots every session used to write its own
## capture script for (tools/bin/screen-shot runs it on a virtual display).
##
##   godot --path game --rendering-driver opengl3 --resolution 320x224 \
##     -s res://test/screens/screen_shot.gd -- ID TICKS OUT.png [options]
##     --press T:VERB[,T:VERB...]   VERB held 3 ticks from tick T, as player 1
##                                  presses it (the bare menu action and its
##                                  p1_ twin); VERB@P for player P
##     --session K=V[,K=V...]       local_mode, run_started (0 / 1), run_games,
##                                  team_a, team_b, stadium, play_mode, humans
##                                  (A.B: "+" between player numbers)
##     --settings K=V[,K=V...]      MwSettings switches by name (booleans 0 / 1,
##                                  numbers, words as they are)
##     --frames A;B;C               also OUT_A.png ... at those ticks
##     --hide NODE[+NODE...]        nodes of the screen hidden for the last shot
## Prints the screen it saved on; exits 0, or 1 when screen ID has no scene.

const Pad := preload("res://test/support/pad.gd")
const ScreenRig := preload("res://test/support/screen_rig.gd")

var _rig := ScreenRig.new()
var _presses := {}            # tick -> [action names]
var _frames: Array[int] = []
var _hide: PackedStringArray = []
var _at := 0
var _out := ""
var _n := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(600.0).timeout.connect(quit.bind(2))
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		push_error("screen_shot: ID TICKS OUT.png [options]")
		quit(1)
		return
	var id := int(a[0])
	_at = int(a[1])
	_out = a[2]
	if MwScreens.scene_path(id) == "":
		push_error("screen_shot: no scene for screen %d" % id)
		quit(1)
		return
	var session := MwSession.new(1, 1)
	var i := 3
	while i + 1 < a.size():
		var v: String = a[i + 1]
		match a[i]:
			"--press":
				for text in v.split(","):
					var parts := text.split(":")
					var verb := parts[1].get_slice("@", 0)
					var player := int(parts[1].get_slice("@", 1)) if parts[1].contains("@") else 1
					var list: Array = _presses.get(int(parts[0]), [])
					list.append_array([verb, "p%d_%s" % [player, verb]])
					_presses[int(parts[0])] = list
			"--session":
				for kv in v.split(","):
					_session_value(session, kv.get_slice("=", 0), kv.get_slice("=", 1))
			"--settings":
				for kv in v.split(","):
					_setting(kv.get_slice("=", 0), kv.get_slice("=", 1))
			"--frames":
				for f in v.split(";"):
					_frames.append(int(f))
			"--hide":
				_hide = v.split("+")
		i += 2
	MwInputMap.install()
	_rig.make(root, session)
	_rig.open(id)
	process_frame.connect(_tick)


func _tick() -> void:
	var held := {}
	for t: int in _presses:
		if _n >= t and _n < t + 3:
			for action: String in _presses[t]:
				held[action] = true
	_rig.pad.held = held
	_rig.router.step()
	_n += 1
	if _n in _frames:
		_save(_out.get_basename() + "_%d.png" % _n)
	if _n == _at:
		for h in _hide:
			var node := _rig.current().find_child(h, true, false)
			if node is CanvasItem:
				(node as CanvasItem).visible = false
		_save(_out)
		print("saved %s on screen %d" % [_out, _rig.router.current_id()])
		process_frame.disconnect(_tick)
		_quit.call_deferred()


## Quits once the game's own background loading is over (the router
## service's preloader: quitting mid-load hangs the process).
func _quit() -> void:
	for n in root.get_children():
		for c in n.get_children():
			if c is MwPreloader:
				while not (c as MwPreloader).done():
					await process_frame
	quit()


func _save(path: String) -> void:
	RenderingServer.force_draw()
	var img := root.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(path)


static func _session_value(session: MwSession, k: String, v: String) -> void:
	match k:
		"local_mode":
			session.local_mode = v
		"run_started":
			session.run_started = v == "1"
		"run_games":
			session.run_games = int(v)
		"team_a", "team_b", "stadium", "play_mode":
			session.setup.set(k, int(v))
		"humans":
			session.humans = preload("res://test/support/bots.gd").humans_of(v)
		_:
			push_warning("screen_shot: no session key %s" % k)


static func _setting(k: String, v: String) -> void:
	var sc: GDScript = MwSettings                 # (its static variables, by name)
	if not k in sc:
		push_warning("screen_shot: no setting %s" % k)
		return
	var now: Variant = sc.get(k)
	if now is bool:
		sc.set(k, v == "1" or v == "true")
	elif now is int:
		sc.set(k, int(v))
	elif now is float:
		sc.set(k, float(v))
	else:
		sc.set(k, v)
