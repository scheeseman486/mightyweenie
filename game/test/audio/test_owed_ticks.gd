extends "res://test/rom/rom_test_base.gd"
## Plan 42 (speed): a sound driver's model that owes its ticks (the
## run-ahead's own, MwAudio.owed) - run when the game asks it something,
## the calls with no answer made among them later (MwAudio.call_later) -
## answers as one ticked every tick and called at once, and is the same
## driver once settled.
## Short names: a the MwAudio under test.

const MOVE := 0x25
const CROWD := 0x1B

var _made: Array[MwAudio] = []
var _was_driver: MwAudio
var _was_pool := true


func before_each() -> void:
	_was_driver = MwSound.driver
	_was_pool = MwAudio.organ_pool
	MwAudio.organ_pool = false        # (its pick draws from a stream the two drivers would share)


func after_each() -> void:
	MwSound.driver = _was_driver
	MwAudio.organ_pool = _was_pool
	for a in _made:
		a.free()
	_made.clear()


func _model() -> MwAudio:
	var a := MwAudio.new()
	a.setup(rom, false, false)
	_made.append(a)
	return a


static func _state(a: MwAudio) -> String:
	return var_to_bytes(MwNetSnapshot.audio_state(MwNetGraph.new(), a)).hex_encode().sha256_text()


func test_an_owing_model_answers_and_ends_as_one_ticked() -> void:
	if not need_rom():
		return
	var eager := _model()
	var lazy := _model()
	for a in [eager, lazy]:
		MwSound.driver = a
		MwSound.music_game()
		MwSound.crowd_level(600)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var handles := {eager: [], lazy: []}
	var asked := 0
	var later := 0
	for t in 3000:
		eager.tick()
		lazy.owed += 1
		if rng.randf() < 0.25:
			var what := rng.randi() % 9
			var arg := rng.randi_range(0x12, 0x3A)
			var on := rng.randf() < 0.5
			var level := rng.randi_range(0, 1000)
			for a: MwAudio in [eager, lazy]:
				MwSound.driver = a
				var hs: Array = handles[a]
				match what:
					0:
						hs.append(MwSound.play(arg))
					1:
						MwSound.positional(arg, on)
					2:
						MwSound.crowd_level(level)
					3:
						MwSound.crowd_off()
					4:
						MwSound.crowd_restart()
					5:
						if not hs.is_empty():
							MwSound.stop(int(hs[-1]))
					6:
						MwSound.random_sound(arg)
					7:
						MwSound.crowd_fade()
					8:
						MwSound.fade_out(int(hs[-1]) if not hs.is_empty() else 0, 30)
			if what in [1, 2, 3, 4, 5, 7, 8]:
				later += 1
		if rng.randf() < 0.1:
			MwSound.driver = eager
			var b1 := MwSound.busy(int(handles[eager][-1])) if not handles[eager].is_empty() else false
			var s1 := MwSound.sounding(CROWD)
			MwSound.driver = lazy
			var b2 := MwSound.busy(int(handles[lazy][-1])) if not handles[lazy].is_empty() else false
			var s2 := MwSound.sounding(CROWD)
			assert_eq([b2, s2], [b1, s1], "tick %d: the same answers" % t)
			if [b2, s2] != [b1, s1]:
				return
			asked += 1
	lazy.settle()
	assert_eq(handles[lazy], handles[eager], "the same handles")
	assert_eq(_state(lazy), _state(eager), "the same driver, settled")
	assert_gt(asked, 100, "questions asked")
	assert_gt(later, 100, "calls made later")
