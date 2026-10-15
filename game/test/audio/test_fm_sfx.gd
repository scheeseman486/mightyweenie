extends "res://test/rom/rom_test_base.gd"
## Plan 34 (owner): the port's FM effects ([MwFmSfx]) on the FM channel the
## music leaves free - "gate", the chain-link gate of the controller
## selection's rising wall. Its register writes (patch, strikes, key-offs
## before a pair strikes again, `$2B` after the driver's, everything given
## back at the end), the musics heard there leaving FM6 alone, and
## [MwAudio] writing the effect after each tick's driver work (a stand-in
## for the chips records the order).

## Records every chip call MwAudio and MwAudioOut make (the extension's API).
class Chips extends RefCounted:
	var writes: Array = []          ## [tick, port, register, value]
	var tick := 0
	func ym_write(port: int, reg: int, value: int) -> void:
		writes.append([tick, port, reg, value])
	func psg_write(_v: int) -> void: pass
	func pcm_load(_i: int, _d: PackedByteArray, _r: float, _l: int) -> void: pass
	func pcm_start(_c: int, _sample: int, _f: int) -> void: pass
	func pcm_stop(_v: int) -> void: pass
	func pcm_rate(_v: int, _rate: int) -> void: pass
	func pcm_volume(_v: int, _volume: int) -> void: pass
	func pcm_detach(_c: int) -> int: return -1
	func pcm_start_extra(_i: int, _sample: int, _v: int) -> int: return -1
	func pcm_sample(_v: int) -> int: return -1
	func pcm_fade(_v: int, _f: int) -> void: pass
	func render(n: int) -> PackedVector2Array:
		var a := PackedVector2Array()
		a.resize(n)
		return a
	func sample_rate() -> float: return 53267.0
	func reset() -> void: pass

## The driver's FM6 use: key-ons, and writes to its channel / operator registers.
class Fm6 extends MwSoundOut:
	var key_ons := 0
	var key_offs := 0
	var registers := 0
	func ym_write(port: int, reg: int, value: int) -> void:
		if port == 0 and reg == MwFmSfx.KEY and value & 7 == MwFmSfx.KEY_CHANNEL:
			if value & 0xF0:
				key_ons += 1
			else:
				key_offs += 1
		elif port == MwFmSfx.PORT and reg >= 0x30 and reg & 3 == MwFmSfx.CHANNEL:
			registers += 1


var calls: Array = []


func before_each() -> void:
	calls = []
	MwSound.trace = func(what: String, args: Array, _result: Variant) -> void: calls.append([what, args])


func after_each() -> void:
	MwSound.trace = Callable()


## Every tick's writes of a whole effect (the driver never wrote anything).
static func _run(sfx: MwFmSfx, driver := PackedInt32Array()) -> Array:
	var ticks: Array = []
	for i in 200:
		if not sfx.playing():
			break
		ticks.append(sfx.tick(driver))
	return ticks


static func _keys(writes: Array) -> Array:
	return writes.filter(func(w: Array) -> bool: return w[0] == 0 and w[1] == MwFmSfx.KEY)


func test_gate_writes_only_fm6() -> void:
	var sfx := MwFmSfx.new()
	assert_true(sfx.start("gate"))
	assert_false(MwFmSfx.new().start("nothing"), "an unknown effect")
	var ticks := _run(sfx)
	assert_eq(ticks.size(), sfx.ticks(), "its length, the release included")
	for t in ticks.size():
		for w: Array in ticks[t]:
			if w[0] == 0:
				assert_true(w[1] in [MwFmSfx.KEY, MwFmSfx.DAC_ENABLE],
						"part I: only the key and DAC registers (%s)" % str(w))
				if w[1] == MwFmSfx.KEY:
					assert_eq(int(w[2]) & 7, MwFmSfx.KEY_CHANNEL, "FM6's key")
			else:
				assert_eq(int(w[1]) & 3, MwFmSfx.CHANNEL, "part II: FM6's registers (%s)" % str(w))
				assert_gte(int(w[1]), 0x30)


func test_gate_patch_and_strikes() -> void:
	var sfx := MwFmSfx.new()
	sfx.start("gate")
	var ticks := _run(sfx)
	var first: Array = ticks[0]
	assert_eq(first[0], [0, MwFmSfx.KEY, MwFmSfx.KEY_CHANNEL], "keyed off before the patch")
	assert_has(first, [1, 0xB2, (MwFmSfx.GATE_PATCH["feedback"] << 3) | MwFmSfx.GATE_PATCH["algorithm"]],
			"algorithm and feedback")
	assert_has(first, [1, 0xB6, 0xC0], "both speakers")
	var op1: Array = MwFmSfx.GATE_PATCH["operators"][0]
	assert_has(first, [1, 0x32, (op1[0] << 4) | op1[1]], "operator 1's DT1 / MUL at $32")
	var op2: Array = MwFmSfx.GATE_PATCH["operators"][1]
	assert_has(first, [1, 0x3A, (op2[0] << 4) | op2[1]], "operator 2's at $3A (offset 8)")
	for strike: Array in MwFmSfx.GATE_STRIKES:
		var t: int = strike[0]
		var w: Array = ticks[t]
		var fb := MwFmSfx.fnum_block(float(strike[1]))
		var hi := w.find([1, 0xA6, (fb.y << 3) | (fb.x >> 8)])
		var lo := w.find([1, 0xA2, fb.x & 0xFF])
		assert_true(hi >= 0 and lo > hi, "tick %d: the frequency, the high byte first" % t)
		var keys := _keys(w)
		assert_false(keys.is_empty(), "tick %d: keyed" % t)
		var on: int = (int(keys.back()[2]) >> 4) & int(strike[3])
		assert_eq(on, int(strike[3]), "tick %d: the struck pairs keyed on" % t)
	assert_almost_eq(float(MwFmSfx.fnum_block(800.0).x) * (1 << MwFmSfx.fnum_block(800.0).y) * MwFmSfx.FNUM_HZ, 800.0,
			1.0,
			"the F-number and block of a frequency")


func test_a_pair_lets_go_the_tick_before_it_strikes_again() -> void:
	var sfx := MwFmSfx.new()
	sfx.start("gate")
	var ticks := _run(sfx)
	var keyed := 0
	for t in ticks.size():
		var strikes := MwFmSfx.GATE_STRIKES.filter(func(entry: Array) -> bool: return entry[0] == t)
		for strike: Array in strikes:
			assert_eq(keyed & int(strike[3]), 0, "tick %d: the pair was off before it strikes (the envelope restarts)"
					% t)
		for w: Array in _keys(ticks[t]):
			keyed = (int(w[2]) >> 4) & 0xF
	assert_eq(keyed, 0, "all off at the end")
	var last: Array = MwFmSfx.GATE_STRIKES.back()
	assert_lt(int(last[0]), MwFmSfx.GATE_LENGTH, "the strikes fit in its length")


func test_the_dac_switch_and_the_registers_go_back() -> void:
	var sfx := MwFmSfx.new()
	sfx.start("gate")
	var driver := PackedInt32Array()
	driver.resize(512)
	driver.fill(-1)
	driver[0x2B] = 0x80                     # the drums' DAC on
	driver[256 + 0x42] = 0x7F               # the driver's own TL of FM6's operator 1
	var ticks := _run(sfx, driver)
	for t in ticks.size() - 1:
		assert_has(ticks[t], [0, MwFmSfx.DAC_ENABLE, 0x00], "tick %d: FM6 heard ($2B = $00)" % t)
	var end: Array = ticks.back()
	assert_eq(end.back(), [0, MwFmSfx.DAC_ENABLE, 0x80], "the driver's $2B put back last")
	assert_has(end, [1, 0x42, 0x7F], "a register the driver wrote: its value")
	assert_has(end, [1, 0xB6, 0xC0], "one it never wrote: the reset value (stereo on)")
	assert_has(end, [1, 0x4A, 0], "TL never written by the driver: 0")
	var touched := {}
	for t in ticks.size() - 1:
		for w: Array in ticks[t]:
			if w[1] >= 0x30:
				touched[[w[0], w[1]]] = true
	for k: Array in touched:
		assert_true(end.any(func(w: Array) -> bool: return w[0] == k[0] and w[1] == k[1]), "%s given back" % str(k))
	assert_false(sfx.playing())


func test_the_driver_taking_fm6_ends_it_at_once() -> void:
	var sfx := MwFmSfx.new()
	sfx.start("gate")
	var driver := PackedInt32Array()
	driver.resize(512)
	driver.fill(-1)
	for i in 5:
		sfx.tick(driver)
	var w := sfx.tick(driver, true)
	assert_false(sfx.playing(), "over")
	assert_eq(w, [[0, MwFmSfx.DAC_ENABLE, 0]], "only $2B back: the driver's registers left alone")


func test_stop_keys_off_then_gives_back() -> void:
	var sfx := MwFmSfx.new()
	sfx.start("gate")
	for i in 10:
		sfx.tick()
	sfx.stop()
	var w := sfx.tick()
	assert_has(w, [0, MwFmSfx.KEY, MwFmSfx.KEY_CHANNEL], "keyed off at once")
	var n := 1
	while sfx.playing() and n < 20:
		sfx.tick()
		n += 1
	assert_eq(n, MwFmSfx.RELEASE_TICKS + 1, "the registers back after the release")
	var fresh := MwFmSfx.new()
	fresh.start("gate")
	fresh.stop()
	assert_false(fresh.playing(), "not started: nothing to give back")
	assert_eq(fresh.tick(), [])


## The spare channel: the menus' music (the game setup, 110 and the
## playoffs bracket) and the title music (the bracket's champion) key FM1-FM5
## at most and never write FM6's registers; their one FM6 write is a
## key-off when they start.
func test_the_musics_leave_fm6_free() -> void:
	if not need_rom():
		return
	for which in ["game", "title"]:
		var rec := Fm6.new()
		var z80 := MwSoundZ80.new(rom, rec)
		var s68k := MwSound68k.new(rom)
		z80.reset()
		s68k.reset()
		if which == "game":
			s68k.music_game()
		else:
			s68k.music_title()
		for t in 60 * 180:
			var batch := s68k.vblank(z80)
			if not batch.is_empty():
				z80.apply_batch(batch)
			z80.advance(not batch.is_empty())
		assert_eq(rec.key_ons, 0, "%s music: no FM6 key-on in 3 minutes" % which)
		assert_eq(rec.registers, 0, "%s music: no FM6 register" % which)
		assert_lte(rec.key_offs, 1, "%s music: a key-off at most (its start)" % which)


## MwAudio: the effect's writes come after the driver's in each tick - its
## `$2B` = `$00` after the drums switched the DAC on - and the driver's
## `$2B` is put back when it ends. FM6 written by the effect only. The
## effect is played again and again over the menus' music.
func test_audio_writes_the_effect_after_the_driver() -> void:
	if not need_rom():
		return
	var audio := MwAudio.new()
	audio.setup(rom, false)
	var chips := Chips.new()
	audio.chips = chips
	audio.out.chips = chips
	audio.s68k.music_game()
	var playing := {}                  # ticks the effect played in (not its last)
	var ends := {}                     # its last ticks -> the driver's $2B then
	for t in 1200:
		chips.tick = t
		if t >= 60 and not audio.fm_sfx.playing():
			MwSound.driver = audio
			MwSound.fm_effect("gate")
			MwSound.driver = null
		var was := audio.fm_sfx.playing()
		audio.step_driver()
		if was and audio.fm_sfx.playing():
			playing[t] = true
		elif was:
			ends[t] = maxi(audio.out.regs[0x2B], 0)
	var by_tick := {}
	for w: Array in chips.writes:
		if not by_tick.has(w[0]):
			by_tick[w[0]] = []
		by_tick[w[0]].append(w.slice(1))
	var dac := func(t: int) -> Array:
		return (by_tick.get(t, []) as Array).filter(func(x: Array) -> bool: return x[0] == 0 and x[1] == 0x2B)
	var after_driver := 0
	for t: int in playing:
		var d: Array = dac.call(t)
		assert_eq(d.back(), [0, 0x2B, 0], "tick %d: the effect's $2B = $00 last" % t)
		if d.size() > 1 and d[0][2] == 0x80:
			after_driver += 1
	assert_gt(after_driver, 0, "the drums switched the DAC on while it played; the effect wrote after them")
	assert_gt(ends.size(), 10)
	var dac_on_ends := 0
	for t: int in ends:
		assert_eq((dac.call(t) as Array).back()[2], ends[t], "tick %d: the driver's $2B back at the end" % t)
		if ends[t] == 0x80:
			dac_on_ends += 1
	assert_gt(dac_on_ends, 0, "ended while the drums played: the DAC back on")
	for t in range(0, 60):
		for w: Array in by_tick.get(t, []):
			assert_false(w[0] == 1 and w[1] >= 0x30 and w[1] & 3 == 2, "no FM6 register before the effect")
	assert_has(calls.map(func(c: Array) -> String: return c[0]), "fm_effect", "traced")
	audio.free()


func test_without_a_driver_the_call_is_traced() -> void:
	MwSound.fm_effect("gate")
	MwSound.fm_effect_stop()
	assert_eq(calls, [["fm_effect", ["gate"]], ["fm_effect_stop", []]])
