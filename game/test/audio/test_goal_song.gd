extends "res://test/rom/rom_test_base.gd"
## The goal song carried over into the goal scoreboard (owner, 2026-10-09;
## [member MwSettings.goal_song_carries]): the rink's exit to a scoreboard
## while sound 9 plays lets it play on, every other sound stopped; the
## scoreboard holds its crowd and its music until the song ends, then fades
## the first of them in over a second; off, and in the attract demo, the
## original's `$13C04`.

const SONG := 9            ## the goal song (`$9332`)
const OTHER := 4           ## another sequence (the goal horn)
const VOICE := 0x26        ## a sample voice

var calls: Array = []
var audio: MwAudio
var _carries := true
var _pool := true


func before_each() -> void:
	_carries = MwSettings.goal_song_carries
	_pool = MwAudio.organ_pool
	MwAudio.organ_pool = false        # sound 9 itself (plan 39's pool has its own test below)
	calls = []
	MwSound.trace = func(what: String, args: Array, _result: Variant) -> void: calls.append([what, args])


func after_each() -> void:
	MwSound.trace = Callable()
	MwSound.driver = null
	MwSound.carried = MwSound.NONE
	MwSound.take_fade_in()
	MwSettings.goal_song_carries = _carries
	MwAudio.organ_pool = _pool
	if audio:
		audio.free()
		audio = null


func _audio() -> MwAudio:
	audio = MwAudio.new()
	audio.setup(rom, false)
	MwSound.driver = audio
	return audio


## Ticks until [param handle] has stopped (at most [param limit]); how many.
func _until_quiet(handle: int, limit := 600) -> int:
	var n := 0
	while audio.s68k.sound_busy(handle) and n < limit:
		audio.step_driver()
		n += 1
	return n


func _names() -> Array:
	return calls.map(func(c: Array) -> String: return c[0])


## The 68000 side: one sequence kept, the rest stopped, no reset.
func test_leave_keeping_stops_all_but_the_song() -> void:
	if not need_rom():
		return
	var driver := MwSound68k.new(rom)
	driver.reset()
	var song := driver.sound_play(SONG)
	var other := driver.sound_play(OTHER)
	var voice := driver.sound_play(VOICE)
	driver.crowd_level(500)
	for i in 5:
		driver.channels_tick()
		driver.seq_tick()
	assert_true(driver.sound_busy(song) and driver.sound_busy(other) and driver.sound_busy(voice))
	assert_ne(driver.r32(MwSound68k.CROWD_HANDLE), 0xFFFFFFFF, "the crowd on")
	driver.leave_keeping(song)
	assert_true(driver.sound_busy(song), "the song plays on")
	assert_false(driver.sound_busy(other), "the other sequence stopped")
	assert_false(driver.sound_busy(voice), "the voice stopped")
	assert_eq(driver.r32(MwSound68k.CROWD_HANDLE), 0xFFFFFFFF, "the crowd off")
	assert_eq(driver.r16(MwSound68k.CROWD_ON), 0)
	assert_eq(driver.r32(MwSound68k.POSITIONAL), 0xFFFFFFFF)
	var n := 0
	while driver.sound_busy(song) and n < 1000:
		driver.channels_tick()
		driver.seq_tick()
		n += 1
	assert_between(n, 300, 400, "then it plays to its end (about 6.6 s from its start)")


## The facade: carried while it plays; when it has ended, one fade-in.
func test_carry_over_then_one_fade_in() -> void:
	if not need_rom():
		return
	_audio()
	var song := MwSound.play(SONG)
	MwSound.crowd_level(500)
	for i in 100:
		audio.step_driver()
	MwSound.carry_over(song)
	assert_eq(MwSound.carried, song & 0xFFFFFFFF)
	assert_eq(audio.s68k.r32(MwSound68k.CROWD_HANDLE), 0xFFFFFFFF, "the crowd off")
	assert_true(MwSound.carrying())
	assert_eq(MwSound.take_fade_in(), 0, "no fade-in while it plays")
	var n := _until_quiet(song)
	assert_between(n, 200, 300, "the rest of the song")
	assert_false(MwSound.carrying(), "ended")
	assert_eq(MwSound.carried, MwSound.NONE)
	assert_eq(MwSound.take_fade_in(), MwSound.FADE_IN_TICKS, "a second's fade-in, once")
	assert_eq(MwSound.take_fade_in(), 0)
	song = MwSound.play(SONG)
	MwSound.carry_over(song)
	MwSound.enter_match(1)
	assert_eq(MwSound.carried, MwSound.NONE, "a driver reset ends it")
	assert_false(audio.s68k.sound_busy(song))
	song = MwSound.play(SONG)
	MwSound.carry_over(song)
	MwSound.end_carry()
	assert_false(audio.s68k.sound_busy(song), "the scoreboard left: stopped")
	assert_eq(MwSound.take_fade_in(), 0)


class LevelOut extends MwAudioOut:
	var levels := {}       ## channel -> the volumes the mixer was given, in order
	func pcm_volume(ch: int, volume: int) -> void:
		if not levels.has(ch):
			levels[ch] = []
		levels[ch].append(volume)
		super.pcm_volume(ch, volume)


## A sample voice rising from silence over the ticks given, in the mix only.
func test_a_voice_fades_in() -> void:
	if not need_rom():
		return
	_audio()
	var out := LevelOut.new(audio.chips)
	audio.out = out
	audio.z80.out = out
	var h := MwSound.play(MwScoreboardSim.MUSIC)
	MwSound.fade_in(h, 60)
	var k := audio.s68k.voice_channel(h)
	assert_true(k >= 0, "a voice")
	for i in 30:
		audio.step_driver()
	var mid: int = out.levels[k][-1]
	assert_between(mid, 0x30, 0x50, "half way: about half")
	for i in 40:
		audio.step_driver()
	assert_eq(out.levels[k][-1], audio.z80.effective_volume(k), "then its own volume")
	assert_true(audio._fade_ins.is_empty())
	var rising: Array = out.levels[k].slice(1, 60)
	var sorted := rising.duplicate()
	sorted.sort()
	assert_eq(rising, sorted, "rising")


## The rink's exit: carried to a scoreboard while the song plays; otherwise,
## switched off or in the attract demo, `$13C04`.
func test_the_rink_exit_carries_the_song() -> void:
	if not need_rom():
		return
	_audio()
	for case: Array in [[12, true, 0, "carry_over"], [15, true, 0, "carry_over"], [5, true, 0, "enter_match"],
			[12, false, 0, "enter_match"], [12, true, 1, "enter_match"]]:
		MwSettings.goal_song_carries = case[1]
		var state := MwRinkState.new()
		var rink_sim := MwRinkSim.new(rom, state)
		MwRinkMatch.start(rink_sim, 0, 0, 5, 0, false, 2)
		state.fight_block = case[2]
		var phases := MwRinkPhases.new(MwRinkUpdate.new(rink_sim))
		rink_sim.live = true
		phases.goal_song = MwSound.play(SONG)
		calls.clear()
		phases.exit(case[0])
		assert_has(_names(), case[3], str(case))
		assert_eq(phases.goal_song, MwSound.NONE)
		MwSound.enter_match(1)
	MwSettings.goal_song_carries = true
	var s := MwRinkState.new()
	var sim := MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim, 0, 0, 5, 0, false, 2)
	var ph := MwRinkPhases.new(MwRinkUpdate.new(sim))
	sim.live = true
	ph.goal_song = MwSound.play(SONG)
	_until_quiet(ph.goal_song)
	calls.clear()
	ph.exit(12)
	assert_has(_names(), "enter_match", "the song over: the original's exit")


## The scoreboard: nothing of its own while the song plays; then the crowd
## (no menu yet) or the music (the menu asked for meanwhile) fading in.
func test_the_scoreboard_waits_for_the_song() -> void:
	if not need_rom():
		return
	_audio()
	for menu in [false, true]:
		var song := MwSound.play(SONG)
		MwSound.carry_over(song)
		var sb := MwScoreboardSim.new(rom)
		sb.screen = 12
		calls.clear()
		sb._music_pass()
		if menu:
			sb._music_on()
			assert_eq(sb.music, -1, "the menu's music waits")
		sb._music_pass()
		assert_false(_names().has("crowd_level") or _names().has("play"), "nothing while the song plays")
		_until_quiet(song)
		calls.clear()
		sb._music_pass()
		if menu:
			assert_ne(sb.music, -1, "then the music")
			assert_eq(_names().slice(0, 2), ["crowd_off", "play"])
			var fades := calls.filter(func(c: Array) -> bool: return c[0] == "fade_in")
			assert_eq(fades.size(), 1)
			assert_eq(fades[0][1][1], MwSound.FADE_IN_TICKS, "fading in over a second")
		else:
			assert_has(calls, ["crowd_level", [MwScoreboardSim.CROWD, MwSound.FADE_IN_TICKS]],
					"then the crowd, fading in")
		calls.clear()
		sb._music_pass()
		assert_false(calls.any(func(c: Array) -> bool: return c[0] == "fade_in" \
				or (c[0] == "crowd_level" and c[1].size() > 1)),
				"once")
		MwSound.enter_match(1)


## Not carried (the original's flow): the scoreboard as before.
func test_the_scoreboard_unchanged_without_a_song() -> void:
	if not need_rom():
		return
	_audio()
	var sb := MwScoreboardSim.new(rom)
	sb.screen = 12
	sb._music_pass()
	assert_eq(calls, [["crowd_level", [MwScoreboardSim.CROWD]]])
	calls.clear()
	sb._music_on()
	assert_eq(_names(), ["crowd_off", "play"], "no fade-in")


## Plan 39: with the organ pool, the goal song may be a longer tune of the
## pool - carried all the same, the fade-in after its end.
func test_a_pool_tune_is_carried() -> void:
	if not need_rom():
		return
	_audio()
	MwAudio.organ_pool = true
	MwOrganPool.rng.seed = 7
	for k in MwOrganPool.size():
		var song := audio.play_pool_tune(k)
		for i in 60:
			audio.step_driver()
		MwSound.carry_over(song)
		assert_true(MwSound.carrying(), "tune %d carried" % k)
		_until_quiet(song, 1000)
		assert_false(MwSound.carrying(), "tune %d over" % k)
		assert_eq(MwSound.take_fade_in(), MwSound.FADE_IN_TICKS)
		MwSound.enter_match(1)
