extends "res://test/rom/rom_test_base.gd"
## The instant replay (MwReplaySim, screen 7, around MwInstantReplay) on a
## set-up match whose replay ring holds synthetic frames written by the
## rink's own recording code (MwRinkUpdate.replay_head / replay_sprite, the
## ring's close_frame) (plan 11; docs/re/replay.md): the set-up (the oldest
## frame, the controlling pad), the speeds of play, slow motion and rewind
## and their ends, the controls' priorities, the exit (the ring put back,
## the screen returned), what the last frame shown leaves (plane B, its
## scroll, the markers, the plates), the draws, no RNG. The original tick
## for tick: `tools/bin/screen-check NAME --only 7` (out/sim/scr_*).

const NONE := [0, 0, 0, 0]
const A := MwInstantReplay.NEW_A
const B := MwInstantReplay.NEW_B
const C := MwInstantReplay.NEW_C
const START := MwInstantReplay.START
## The frames' recorded pass lengths e (oldest first).
const ES := [3, 4, 2, 5, 1]
const HAZARD_KIND := 2               ## shown in every frame in slot 0

var sim: MwRinkSim
var s: MwRinkState
var up: MwRinkUpdate
## The ring object and data as the rink left them.
var ring_before: Array = []
## The ROM frame the sprite records draw (a hazard's: any ROM frame does).
var record_frame := 0


class Idle:
	func think(_sim: MwRinkSim, _p: MwRinkState.Player, _team: MwRinkState.Team, _other: MwRinkState.Team) -> void:
		pass


func before_each() -> void:
	if rom.is_empty():
		return
	s = MwRinkState.new()
	s.rng = MlhRng.new(1234)
	sim = MwRinkSim.new(rom, s)
	sim.cpu = Idle.new()
	MwRinkMatch.start(sim, 4, 9, 4, 0, false, 2)
	up = MwRinkUpdate.new(sim)
	MwRinkPhases.new(up).enter(5)
	s.tick = 1000
	record_frame = MwGfx.u32(rom, MwReplaySim.HAZARD_FRAMES)
	s.replay.reset()
	for k in ES.size():
		_record_frame(k)
	ring_before = _ring_state()
	# the live state differs from every frame
	s.camera.shown = Vector2i(7, 9)
	s.scroll_b = Vector2i(1, 2)
	s.hazards[0].kind = 0
	for t in s.teams:
		for m in t.markers:
			m.x = 999
			m.y = 999


## Frame [param k] as a rink pass records it: the head (camera point,
## hazards, markers), k + 1 sprite records, the trailer.
func _record_frame(k: int) -> void:
	s.camera.x = _cam(k).x << 8
	s.camera.y = _cam(k).y << 8
	s.camera.amp = 0
	for h in s.hazards:
		h.kind = 0
	s.hazards[0].kind = HAZARD_KIND
	s.hazards[0].flags = 0x80
	for t in 2:
		var m := s.teams[t].markers[0]
		m.x = 10 * k + t
		m.y = 5 * k
		m.number = 10 + k
		m.position = k % 6
		m.health = 20 + k
	up.replay_head(ES[k])
	for i in k + 1:
		up.replay_sprite(0x80 + 8 * i, 0x90 + 2 * k, 0x100 + i, 0x08, record_frame)
	s.replay.close_frame()


static func _cam(k: int) -> Vector2i:
	return Vector2i(40 + 10 * k, 200 + 30 * k)


func _ring_state() -> Array:
	var r := s.replay
	return [r.write, r.read, r.used, r.frames, r.open, r.pan, r.ring_bytes.duplicate()]


## A pass of [param e] ticks with [param held] / [param new] on pad [param pad].
func _step(rp: MwReplaySim, held := 0, new := 0, pad := 0, e := 1) -> int:
	s.tick += e
	var h := NONE.duplicate()
	var n := NONE.duplicate()
	h[pad] = held
	n[pad] = new
	rp.begin_pass()
	return rp.step(e, h, n)


func _enter(from := 4, pads_new := [A, 0, 0, 0]) -> MwReplaySim:
	for p in 4:
		s.pads_new[p] = pads_new[p]
	var rp := MwReplaySim.new(rom)
	rp.enter(s, 7, from)
	return rp


## The index of the frame on screen (by its camera point).
func _shown(rp: MwReplaySim) -> int:
	var cam: Vector2i = rp.replay.shown["camera"]
	return (cam.x - 40) / 10


## Passes (with the given pad bytes) until the shown frame changes or
## [param limit] passes: the passes taken.
func _until_next(rp: MwReplaySim, held: int, limit := 40) -> int:
	var drawn := rp.replay.drawn
	for i in limit:
		_step(rp, held)
		if rp.replay.drawn != drawn:
			return i + 1
	return -1


# --- set-up --------------------------------------------------------------------------------------

func test_setup_shows_the_oldest_frame_frozen() -> void:
	if not need_rom():
		return
	var rng := s.rng.state
	var rp := _enter(4, [0, A, 0, 0])
	assert_eq(rp.replay.pad, 1, "the pad that pressed A in the pause menu")
	assert_eq(rp.replay.cursor, 1)
	assert_false(rp.replay.play, "frozen")
	assert_eq(rp.replay.wait, ES[1], "the next frame's e")
	assert_eq(_shown(rp), 0, "the oldest frame")
	assert_eq(s.camera.shown, _cam(0), "plane B at its camera point")
	assert_eq(s.scroll_b, Vector2i((-_cam(0).x) & 0x1FF, _cam(0).y & 0xFF), "the scroll buffers")
	for t in 2:
		var m := s.teams[t].markers[0]
		assert_eq([m.x, m.y, m.number, m.position, m.health], [t, 0, 10, 0, 20], "the frame's marker")
		assert_eq(s.plates[m.plate], [10, 0, 0xFF], "the plate (no health bar without Reserves)")
	assert_eq(s.hazards[0].kind, 0, "the live hazard left alone")
	assert_eq(s.rng.state, rng, "no random number")
	assert_true(["crowd", MwReplaySim.CROWD] in rp.events, "the crowd loop")
	assert_eq(rp.replay.saved_read, ring_before[1])
	assert_eq(rp.replay.saved_used, ring_before[2])


func test_setup_draws() -> void:
	if not need_rom():
		return
	var rp := _enter()
	assert_eq(rp.plane_ops, [["rink"], ["scroll", _cam(0).x, _cam(0).y]])
	assert_eq(rp.window_ops[0], ["fill", 0, 0, 40, 28, 0x8000], "rink_load's window clear")
	assert_eq(rp.window_ops[1], ["map", MwReplaySim.WIDGET_MAP, 9, 9, 5, 2, 2], "the A/B/C widget")
	assert_eq(rp.window_ops.slice(2), [
			["text", MwReplaySim.TEXT_FONT, 4, 4, 0xE0, MwReplaySim.TEXTS[0]],
			["text", MwReplaySim.TEXT_FONT, 4, 5, 0xE0, MwReplaySim.TEXTS[1]]], "the widget's texts")
	# the hazard (its frame at the live slot's point, depth 1), then the one record's pieces
	var hz := MwGfx.u32(rom, MwReplaySim.HAZARD_FRAMES + 8 * (HAZARD_KIND - 1))
	var h := s.hazards[0]
	var p := MwScoreboardSim.project(s, h.x, h.y, 0)
	var n_hz := MwGfx.u16(rom, hz)
	var n_rec := MwGfx.u16(rom, record_frame)
	assert_eq(rp.sprite_ops.size(), n_hz + n_rec)
	assert_eq(rp.sprite_ops[0], ["piece", hz + 2, p.x - _cam(0).x, p.y - _cam(0).y, 0, 1])
	assert_eq(rp.sprite_ops[n_hz], ["piece", record_frame + 2, 0, 0x10, 0x08, 0x100], "the record: screen pixels")


func test_control_pad_from_a_scoreboard() -> void:
	if not need_rom():
		return
	var rp := _enter(12, [A, 0, C, 0])
	assert_eq(rp.replay.pad, 2, "C on the scoreboard (A does not count)")
	_step(rp, C, C, 0)
	assert_false(rp.replay.play, "another pad's C is ignored")
	_step(rp, C, C, 2)
	assert_true(rp.replay.play)
	assert_eq(MwInstantReplay.control_pad(4, NONE), 0, "pad 1 when none pressed")


# --- speeds --------------------------------------------------------------------------------------

func test_play_at_the_recorded_speed_to_the_newest_frame() -> void:
	if not need_rom():
		return
	var rp := _enter()
	_step(rp, C, C)
	assert_true(rp.replay.play)
	assert_eq(1 + _until_next(rp, 0), ES[1], "frame 1 e[1] ticks after the press (its pass counts)")
	for k in range(2, ES.size()):
		assert_eq(_until_next(rp, 0), ES[k], "frame %d e[%d] ticks after frame %d" % [k, k, k - 1])
	assert_eq(_shown(rp), ES.size() - 1, "the newest frame")
	assert_eq(rp.replay.cursor, ES.size())
	assert_eq(_until_next(rp, 0, 20), -1, "stays on the newest frame")
	assert_true(rp.replay.play, "the play flag stays set")
	assert_eq(_until_next(rp, B, 20), -1, "slow motion has nowhere to go")
	assert_false(rp.replay.play, "B clears it")


func test_slow_motion() -> void:
	if not need_rom():
		return
	var rp := _enter()
	assert_eq(_until_next(rp, B), ES[1], "the first step after the wait already running")
	assert_eq(_shown(rp), 1)
	for k in range(2, ES.size()):
		assert_eq(_until_next(rp, B), 2 * ES[k], "frame %d: 2e" % k)
	assert_eq(_shown(rp), ES.size() - 1)
	assert_eq(_until_next(rp, 0, 20), -1, "frozen when B is released")


func test_rewind() -> void:
	if not need_rom():
		return
	var rp := _enter()
	_step(rp, C, C)
	for i in 40:
		if _shown(rp) >= 3:
			break
		_step(rp)
	assert_eq(rp.replay.cursor, 4)
	# a new A: a step at once, showing the current frame again
	var drawn := rp.replay.drawn
	_step(rp, A, A)
	assert_eq(rp.replay.drawn, drawn + 1, "drawn at once")
	assert_eq(_shown(rp), 3, "the frame shown again")
	assert_eq(rp.replay.cursor, 3)
	assert_false(rp.replay.play)
	assert_eq(_until_next(rp, A), maxi(ES[3] >> 1, 1))
	assert_eq(_shown(rp), 2)
	assert_eq(_until_next(rp, A), maxi(ES[2] >> 1, 1))
	assert_eq(_shown(rp), 1)
	assert_eq(_until_next(rp, A), maxi(ES[1] >> 1, 1))
	assert_eq(_shown(rp), 0, "the oldest frame")
	assert_eq(rp.replay.cursor, 0)
	assert_eq(_until_next(rp, A, 20), -1, "rewinding stops at the oldest")
	# forward again: the first step shows the current frame again (the
	# rewind's wait, 1 here, runs out at once), then frame 1 after e[1]
	drawn = rp.replay.drawn
	_step(rp, C, C)
	assert_eq(rp.replay.drawn, drawn + 1)
	assert_eq(_shown(rp), 0, "the oldest frame again")
	assert_eq(rp.replay.cursor, 1)
	assert_eq(_until_next(rp, 0), ES[1])
	assert_eq(_shown(rp), 1)


# --- priorities ----------------------------------------------------------------------------------

func test_start_ignored_while_a_or_b_is_held_or_c_is_new() -> void:
	if not need_rom():
		return
	var rp := _enter()
	assert_eq(_step(rp, B | START, START), -1, "B held")
	assert_eq(_step(rp, A | START, START), -1, "A held")
	assert_eq(_step(rp, C | START, C | START), -1, "C new")
	assert_true(rp.replay.play, "C played")
	assert_eq(_step(rp, 0x0F, 0x0F), -1, "the D-pad does nothing")
	assert_eq(_step(rp, START, START, 1), -1, "another pad's Start")
	assert_eq(_step(rp, START, START), 6, "Start leaves")


# --- exit ----------------------------------------------------------------------------------------

func test_exit_puts_the_ring_back_and_keeps_the_last_frame() -> void:
	if not need_rom():
		return
	var rng := s.rng.state
	var rp := _enter()
	_step(rp, C, C)
	for i in 40:
		if _shown(rp) >= 2:
			break
		_step(rp)
	var to := _step(rp, START, START)
	assert_eq(to, 6, "back to the rink (entry 6)")
	assert_eq(_ring_state(), ring_before, "the ring as the rink left it")
	assert_true(["crowd_off"] in rp.events)
	assert_true(["fade_out", MwScreenSim.FADE_OUT] in rp.events)
	assert_eq(s.camera.shown, _cam(2), "plane B at the last frame shown")
	assert_eq(s.scroll_b, Vector2i((-_cam(2).x) & 0x1FF, _cam(2).y & 0xFF))
	var m := s.teams[0].markers[0]
	assert_eq([m.x, m.y, m.number, m.position, m.health], [20, 10, 12, 2, 22])
	assert_eq(s.plates[m.plate], [12, 2, 0xFF])
	assert_eq(s.rng.state, rng, "no random number")


func test_exit_to_the_scoreboard() -> void:
	if not need_rom():
		return
	var rp := _enter(14, [C, 0, 0, 0])
	assert_eq(_step(rp, START, START), 14, "back to the scoreboard it came from")


func test_health_bar_with_reserves() -> void:
	if not need_rom():
		return
	s.reserves = true
	var rp := _enter()
	var m := s.teams[0].markers[0]
	assert_eq(s.plates[m.plate], [10, 0, 20], "the frame's health on the plate")
	assert_eq(rp.replay.cursor, 1)


func test_unused_marker_plate() -> void:
	if not need_rom():
		return
	# an unused marker (number 127, position 7): the font lacks "<" and char 3,
	# so `$63A2` copies the "tile" a null glyph piece points at
	var t := MwPlate.tiles(rom, 127, 7, MwPlate.NONE)
	var src := MwGfx.u16(rom, 4) << 5
	assert_eq(t.slice(0, 32), rom.slice(src, src + 32), "tens digit")
	assert_eq(t.slice(32 * 6, 32 * 7), rom.slice(src, src + 32), "position letter")
	assert_eq(MwPlate.tiles(rom, 7, 0, MwPlate.NONE).slice(32 * 2, 32 * 3), t.slice(32 * 2, 32 * 3), "units digit 7")
