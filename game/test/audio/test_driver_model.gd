extends "res://test/rom/rom_test_base.gd"
## Plan 35 work item 1 (docs/net.md): the answers the game waits on - a
## handle still playing, a sound heard (MwSound.sounding: the matchup's
## chant, plan 33), with ENHANCE AUDIO's extra voices - come from the sound
## driver's model, stepped by the ticks: the same with no chips at all
## (headless, muted) as with the chips rendering however many frames the
## sound card wants each tick.
## Short names: a the MwAudio under test.

const SOUND_CROWD := 0x1B        # the matchup's chant (a sample)
const SOUND_MOVE := 0x25         # the menus' cursor sound
const SOUND_DPCM := 0x15
const SOUND_A := 0x20
const SOUND_B := 0x26

var _defaults := []
var _made: Array[MwAudio] = []


func before_all() -> void:
	super.before_all()
	_defaults = [MwAudio.free_music_samples, MwAudio.free_effects]


func after_each() -> void:
	MwAudio.free_music_samples = _defaults[0]
	MwAudio.free_effects = _defaults[1]
	for a in _made:
		a.free()
	_made.clear()


func _driver(chips: bool) -> MwAudio:
	var a := MwAudio.new()
	a.setup(rom, false, chips)
	_made.append(a)
	return a


## What the game would ask each tick, for a busy minute of the menus' music,
## the matchup's chant asked for whenever it isn't heard (as screen 3 does),
## and effects in other banks cutting in; [param jitter] renders the chips
## a random number of frames more or less each tick (a sound card's pull).
func _answers(a: MwAudio, jitter: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var out := []
	var chant := MwSound.NONE
	a.s68k.music_game()
	for i in 1200:
		if not a.s68k.sound_busy(chant) and not a.sounding(SOUND_CROWD):
			chant = a.s68k.sound_play(SOUND_CROWD)
		if i % 37 == 0:
			a.s68k.sound_play(SOUND_MOVE)
		if i % 90 == 45:
			a.s68k.positional(SOUND_A if i % 180 == 45 else SOUND_B, true)
		if i % 300 == 150:
			a.s68k.sound_play(SOUND_DPCM)
		a.step_driver()
		if a.chips != null:
			a.chips.call("render", maxi(a.frames_this_tick() + (rng.randi_range(-8, 8) if jitter else 0), 0))
		out.append([chant, a.s68k.sound_busy(chant), a.sounding(SOUND_CROWD), a.sounding(0x12)])
	return out


func test_answers_never_depend_on_the_chips() -> void:
	if not need_rom():
		return
	for enhanced in [true, false]:
		MwAudio.free_music_samples = enhanced
		MwAudio.free_effects = enhanced
		var model := _answers(_driver(false), false)
		if ClassDB.class_exists("MwChips"):
			var heard := _answers(_driver(true), true)
			assert_eq(heard, model, "with the chips rendering (a sound card's pull) as with none (ENHANCE AUDIO %s)"
					% enhanced)
		var again := _answers(_driver(false), false)
		assert_eq(again, model, "the model again: the same")
		var sounded := 0
		for row in model:
			if row[2]:
				sounded += 1
		assert_gt(sounded, 100, "the chant is heard (ENHANCE AUDIO %s)" % enhanced)


func test_extras_end_in_the_model() -> void:
	if not need_rom():
		return
	MwAudio.free_effects = true
	var a := _driver(false)
	a.s68k.positional(SOUND_A, true)
	for i in 10:
		a.step_driver()
	a.s68k.positional(SOUND_B, true)
	a.step_driver()
	var sa := a.z80.samples.by_instrument(MwGfx.u16(rom, 0x1F5C6 + 2 * (SOUND_A - 0x12)))
	var on := 0
	for i in 600:
		var playing := false
		for extra: MwAudio.Extra in a._extras:
			if extra.sample == sa:
				playing = true
				assert_eq(extra.voice, -1, "no chips: the model's own")
				assert_between(extra.slot, MwAudio.EXTRA_FIRST, MwAudio.EXTRA_END - 1)
		if playing:
			on += 1
		a.step_driver()
	assert_gt(on, 0, "A cut by B plays on an extra voice in the model")
	assert_lt(on, 600, "and ends there by its length")
