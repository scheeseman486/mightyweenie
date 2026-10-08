extends Node
## Autoload "Router": installs the default input bindings, owns the screen
## fader and the 3D view's host and steps an [MwRouter] once per physics
## tick (60 Hz). The project's main scene (boot) - or whichever screen scene
## is run on its own from the editor - becomes the first screen. With a
## display the 3D view starts building at once, in the background, warming
## up the first time the fader covers the screen (MwRink3DHost).

var router: MwRouter
var fader := MwScreenFader.new()
var rink_3d := MwRink3DHost.new()
## The sound driver and its output (plan 12); null in headless runs (tests,
## checks), where [MwSound] keeps its silent stand-in.
var audio: MwAudio = null


func _ready() -> void:
	if not _headless():
		MwSettings.load_file()      # the player's options (plan 21); headless runs keep the defaults
	MwSettings.apply()              # the audio switches and the input map
	fader.name = "ScreenFader"
	add_child(fader)
	rink_3d.covered = func() -> bool: return fader.coverage() >= 1.0
	add_child(rink_3d)
	if DisplayServer.get_name() != "headless":
		rink_3d.prepare()
	router = MwRouter.new(get_tree().root, fader)
	router.input = MwLiveInput.new()
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


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("headless")


func _adopt() -> void:
	var s := get_tree().current_scene
	if s is MwScreen:
		if s.screen_id == MwScreens.BOOT:
			fader.cover()
		router.adopt(s)


func _physics_process(_delta: float) -> void:
	if audio:
		audio.tick()              # the VBlank's sound driver work comes first
	router.step()


## Shortcut for game code: go to screen [param id].
func go(id: int, data := {}, fade := true, ticks := -1) -> void:
	router.go(id, data, fade, ticks)
