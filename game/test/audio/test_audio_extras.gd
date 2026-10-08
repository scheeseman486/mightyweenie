extends "res://test/rom/rom_test_base.gd"
## The enhancement switches MwAudio.free_music_samples / free_effects (plan
## 12, owner 2026-10-08): the sounds the original drops for want of a bank or
## a channel, or by the positional rule, play on the chips' extra voices -
## and the driver itself (its RAM, the Z80's statuses: everything the game
## can observe) stays exactly the original's. Needs the ROM and the mw_audio
## extension.

const SOUND_MOVE := 0x25        # the menus' cursor sound (a sample in another bank than the drums)
const SOUND_DPCM := 0x15        # a DPCM effect above the crowd's priority (no copies: plays alone)
const SOUND_A := 0x20           # two rink effects in different banks
const SOUND_B := 0x26

var audio: MwAudio
var _defaults := []


## Untyped like GutTest's (a "-> Variant" here and in test_chips.gd made Godot
## 4.7 reject whichever of the two loaded second).
func should_skip_script():
	if not ClassDB.class_exists("MwChips"):
		return "MwChips extension not built (tools/bin/build-audio)"
	return false


func before_all() -> void:
	super.before_all()
	_defaults = [MwAudio.free_music_samples, MwAudio.free_effects]


func after_each() -> void:
	MwAudio.free_music_samples = _defaults[0]
	MwAudio.free_effects = _defaults[1]
	if audio:
		audio.free()
		audio = null


func _audio(music: bool, effects: bool) -> MwAudio:
	MwAudio.free_music_samples = music
	MwAudio.free_effects = effects
	var a := MwAudio.new()
	a.setup(rom, false)
	return a


## One tick with its audio rendered (the extra voices advance and end).
static func _tick(a: MwAudio) -> void:
	a.step_driver()
	a.chips.call("render", a.frames_this_tick())


## The samples on the extra voices.
static func _extra_samples(a: MwAudio) -> Array:
	var out := []
	for v in range(4, 16):
		var s: int = a.chips.call("pcm_sample", v)
		if s >= 0:
			out.append(s)
	return out


func _sample_of_id(id: int) -> int:
	return audio.z80.samples.by_instrument(MwGfx.u16(rom, 0x1F5C6 + 2 * (id - 0x12)))


## The menus' music with the cursor sound now and then (as Down on the main
## menu): the drums the original drops while it plays come back on extra
## voices and stop at their note-offs.
func test_menu_drums_play_through_the_cursor_sound() -> void:
	if not need_rom():
		return
	for on in [false, true]:
		audio = _audio(on, false)
		audio.s68k.music_game()
		var drums := {}
		var seen := {}
		for i in 900:
			if i >= 300 and i % 50 == 0:
				audio.s68k.sound_play(SOUND_MOVE)
			_tick(audio)
			for s in _extra_samples(audio):
				seen[s] = true
		if not on:
			assert_eq(seen, {}, "switch off: no extra voices")
		else:
			for s in seen:
				var d := audio.z80.samples.desc(s)
				drums[d.instrument] = true
				assert_eq(d.priority, 0, "only the music's drums (priority 0)")
			assert_gt(drums.size(), 0, "drums played on extra voices")
			assert_true(audio.extras_peak <= 2, "a kick and a snare at most")
		audio.free()
		audio = null


## A positional sound cut by a different one plays on; cut by itself (the
## rink's sounds repeated every pass) it stops as in the original.
func test_positional_cut_plays_on_unless_restarted() -> void:
	if not need_rom():
		return
	audio = _audio(false, true)
	var a := _sample_of_id(SOUND_A)
	var b := _sample_of_id(SOUND_B)
	audio.s68k.positional(SOUND_A, true)
	for i in 10:
		_tick(audio)
	audio.s68k.positional(SOUND_B, true)
	_tick(audio)
	assert_eq(_extra_samples(audio), [a], "A goes on beside B")
	for i in 2:
		_tick(audio)
	audio.s68k.positional(SOUND_A, true)
	_tick(audio)
	assert_eq(_extra_samples(audio), [b], "A again: its old copy stops, B goes on")
	audio.s68k.positional(SOUND_A, true)
	_tick(audio)
	assert_eq(_extra_samples(audio), [b], "A cut by A: no copy kept")
	audio.free()
	audio = _audio(false, false)
	audio.s68k.positional(SOUND_A, true)
	for i in 10:
		_tick(audio)
	audio.s68k.positional(SOUND_B, true)
	_tick(audio)
	assert_eq(_extra_samples(audio), [], "switch off: cut as the original")


## The crowd killed by a DPCM effect (no bank in common, higher priority) is
## held on an extra voice until the driver restarts it.
func test_crowd_held_until_restarted() -> void:
	if not need_rom():
		return
	audio = _audio(false, true)
	var crowd := audio.z80.samples.by_instrument(MwAudio.CROWD_INSTRUMENT)
	for i in 30:
		audio.s68k.crowd_level(600)
		_tick(audio)
	audio.s68k.sound_play(SOUND_DPCM)
	var held := 0
	var restarted_at := -1
	for i in 120:
		audio.s68k.crowd_level(600)
		_tick(audio)
		if crowd in _extra_samples(audio):
			held += 1
		elif held > 0 and restarted_at < 0:
			restarted_at = i
	assert_gt(held, 30, "held while the effect plays")
	assert_true(restarted_at > 0 and restarted_at < MwAudio.CROWD_HOLD_TICKS, "gone once the crowd restarted")
	assert_eq(audio.z80.channels[3].sample, crowd, "the driver's own crowd is back on its channel")


## Everything the game can observe is the same with the switches on: the
## sound RAM and the Z80's channel statuses, tick for tick.
func test_driver_unchanged_by_the_switches() -> void:
	if not need_rom():
		return
	var runs := []
	for on in [false, true]:
		audio = _audio(on, on)
		var trace := []
		audio.s68k.music_game()
		for i in 1500:
			if i % 50 == 20:
				audio.s68k.sound_play(SOUND_MOVE)
			if i % 37 == 5:
				audio.s68k.positional(SOUND_A if i % 2 else SOUND_B, true)
			if i == 700:
				audio.s68k.sound_play(SOUND_DPCM)
			if i >= 600:
				audio.s68k.crowd_level(400)
			_tick(audio)
			var st := []
			for k in 4:
				st.append(audio.z80.voice_status(k))
			trace.append([audio.s68k.ram_image(), st])
		runs.append(trace)
		if on:
			assert_gt(audio.extras_peak, 0, "the switches did something")
		audio.free()
		audio = null
	var same := true
	for i in runs[0].size():
		if runs[0][i] != runs[1][i]:
			same = false
			fail_test("tick %d differs" % i)
			break
	assert_true(same, "identical driver state")
