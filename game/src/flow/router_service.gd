extends Node
## Autoload "Router": installs the default input bindings, owns the screen
## fader and the 3D view's host and steps an [MwRouter] once per physics
## tick (60 Hz). The project's main scene (boot) - or whichever screen scene
## is run on its own from the editor - becomes the first screen. With a
## display the 3D view starts building at once, in the background, warming
## up the first time the fader covers the screen (MwRink3DHost).
## Every screen's scene and tile set atlases load in the background from
## the start too (MwPreloader, plan 27). Plan 35: the session's online game
## ([member MwSession.net]) is polled before each tick with the clock - the
## one place the net code's time comes from.
##
## Started with [code]-- --join ADDRESS [--password P][/code] (tools/bin/net-mock
## starts the game so: docs/net.md "The mock session") the boot goes to
## JOIN GAME instead of the title, and it connects at once ([method
## join_request]).

var router: MwRouter
var fader := MwScreenFader.new()
var rink_3d := MwRink3DHost.new()
## The start's background loading (plan 27): every screen's scene and atlases.
var preloader := MwPreloader.new()
## The sound driver and its output (plan 12); in a headless game the
## driver's model (plan 35, MwRouter.use_driver_model) so the game hears the
## same answers.
var audio: MwAudio = null


func _ready() -> void:
	if not _headless():
		MwSettings.load_file()      # the player's options (plan 21); headless runs keep the defaults
		MwCustomTeams.load_bank()   # CREATE-A-TEAM's teams (plan 38); headless runs have none
	MwSettings.apply()              # the audio switches and the input map
	fader.name = "ScreenFader"
	add_child(fader)
	rink_3d.covered = func() -> bool: return fader.coverage() >= 1.0
	add_child(rink_3d)
	if DisplayServer.get_name() != "headless":
		rink_3d.prepare()
	preloader.name = "Preloader"
	add_child(preloader)
	if not _headless():
		var order := MwPreloader.screen_order(0)     # the title first, alone
		preloader.start(order.slice(0, 1), order.slice(1))
	router = MwRouter.new(get_tree().root, fader)
	MwStreamInput.live(MwLiveInput.new()).attach(router)   # plan 40 (S7): one input tick, offline too
	_start_audio()
	_adopt.call_deferred()


## The audio service, when the game runs with a display and the ROM is there.
func _start_audio() -> void:
	if _headless():
		return
	var rom := MwRom.data()
	if rom.is_empty():
		return
	audio = MwAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(rom)
	MwSound.driver = audio
	router.audio = audio                # stepped with the router's ticks (plan 35)


## Every input event: the device used last, for the screens' glyphs (plan
## 23: MwGlyphs.note_input redraws the prompts' live cells when it changes).
## Alt+Enter switches between full screen and windowed (plan 28) and is
## nothing else: the actions Enter drives (Start, the menus' select) don't
## see it - they are read by polling, so they are let go here, before the
## tick reads them.
func _input(event: InputEvent) -> void:
	if MwSettings.is_display_toggle(event):
		MwSettings.toggle_fullscreen()
		for a in InputMap.get_actions():
			if event.is_action(a):
				Input.action_release(a)
		get_viewport().set_input_as_handled()
		return
	MwGlyphs.note_input(event)


## The online game the command line asks to join ([param args]: the
## user arguments, "--join ADDRESS" and "--password P"): JOIN GAME's entry
## data ({"join": address, "password": password}), or {} without --join.
static func join_request(args: PackedStringArray) -> Dictionary:
	var i := args.find("--join")
	if i < 0 or i + 1 >= args.size():
		return {}
	var j := args.find("--password")
	return {"join": args[i + 1], "password": args[j + 1] if j >= 0 and j + 1 < args.size() else ""}


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("headless")


func _adopt() -> void:
	var node := get_tree().current_scene
	if node is MwScreen:
		if node.screen_id == MwScreens.BOOT:
			fader.cover()
			var join := join_request(OS.get_cmdline_user_args())
			if not join.is_empty() and node is MwPlaceholderScreen:
				(node as MwPlaceholderScreen).auto_exit = MwScreens.JOIN_GAME
				(node as MwPlaceholderScreen).auto_exit_data = join
		if router.audio == null and MwRom.available():
			audio = router.use_driver_model(MwRom.data())   # plan 35: a headless game hears the model
			add_child(audio)
		router.adopt(node)


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var net: MwNetService = router.session.net if router.session != null else null
	if net != null:
		net.router = router
		net.poll(now)                # plan 35: the online pages' service (the net code reads no clock)
	MwNetService.background()     # ENet's goodbyes and UPnP's removals after a service is gone
	if router.driver != null:
		# plan 35: an online match runs the ticks (as many as its stream allows
		# this frame); the clock is read here, never by the net code
		router.drive(now)        # (plan 45: a frame that fails leaves the match)
		return
	router.step()                 # the sound driver's tick first (MwRouter.audio)


## The game quitting: UPnP's threads waited for.
func _exit_tree() -> void:
	MwNetUpnp.finish_all()


## Shortcut for game code: go to screen [param id].
func go(id: int, data := {}, fade := true, ticks := -1) -> void:
	router.go(id, data, fade, ticks)
