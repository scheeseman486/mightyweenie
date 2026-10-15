class_name MwPassPacer
extends RefCounted
## The original's rink pass lengths (TICK RATE ORIGINAL, plan 36): the 68000
## of a pass's predicted work ([MwPassCost]) laid out on the 60 Hz VBlanks,
## one VBlank at a time, as the original's rink loop `$F962` runs
## (docs/re/timing.md "Pass load"):
##
## * a pass starts where the previous one ended, mid-frame (its elapsed
##   ticks are the VBlanks between the two starts);
## * each VBlank interrupts the work for the handler `$13F96`
##   ([method MwPassCost.handler]: the DMA queue words since the last
##   VBlank, the visit's fade-in, the sound driver's work that tick);
## * the DMA queue wait `$148A8` after the rink update holds the pass until
##   the next VBlank when plane B's rows went into the queue after the last
##   one;
## * the tick wait `$F966`: a pass with no VBlank in it waits for the next.
##
## Use: [method begin] with the pass's work right after the pass ran, then
## [method vblank] each tick (after the sound driver's tick): true when the
## next pass starts in this frame. [method reset] (a new visit, the pause
## menu): the next pass comes after [constant RESYNC_TICKS] ticks.
##
## Integers throughout, in master clocks (7 a 68000 cycle, 896 040 a
## frame): the same work gives the same ticks on every machine (TICK RATE
## APPROXIMATED online, plan 35). Its whole state is [method snapshot].

## Ticks to the first pass after [method reset] (the realtime clock's length).
const RESYNC_TICKS := MwPassClock.RINK_PASS_TICKS

enum Seg { WORK, PUSH, WAIT, FADE }
var _seg := PackedInt32Array()   # the pass in flight: (Seg, amount) pairs, in order
var _at := 0                     # the next pair's index
var _pos := 0                    # master clocks since the last VBlank's handler began
var _pending := 0                # DMA queue words since the last VBlank
var _fade := 0                   # VBlanks of the fade-in still to come
var _done := true                # the pass in flight has finished (waiting for a VBlank)
var _vblanks := 0                # VBlanks since the pass in flight began
var _resync := RESYNC_TICKS      # ticks to wait when no pass ran yet
## The VBlanks the last finished pass took (its successor's elapsed ticks).
var last_elapsed := 0
## The sound driver's master clocks this tick ([method tick]); unset: its
## mean (APPROXIMATED, headless runs).
var sound := Callable()


## Starts over (a new visit, the pause menu): no pass in flight, the next one after
## [constant RESYNC_TICKS] ticks.
func reset() -> void:
	_seg.clear()
	_at = 0
	_pos = 0
	_pending = 0
	_done = true
	_vblanks = 0
	_resync = RESYNC_TICKS


## The pass that just ran: its [param work] in master clocks
## ([method MwPassCost.work_mclk], [method MwPassApprox.work]), from where
## the previous one ended; [param first]: the visit's first pass (the
## fade-in runs after it).
func begin(work: Dictionary, first := false) -> void:
	var ru := int(work["rink_update"])
	var rows := int(work["rows_words"])
	var pre := mini(ru, int(MwPassCost.RU_PRE) * MwPassCost.MCLK) if rows > 0 else ru
	_seg = PackedInt32Array([Seg.WORK, int(work["before"]), Seg.WORK, pre, Seg.PUSH, rows, Seg.WORK, ru - pre,
			Seg.WAIT, rows, Seg.WORK, int(work["after"]), Seg.PUSH, int(work["words"])])
	if first:
		_seg.append_array([Seg.FADE, MwPassCost.FADE_VBLANKS])
	_at = 0
	_done = false
	_vblanks = 0
	_resync = 0
	_run()


## One VBlank (a 60 Hz tick) with the sound driver's [param sound_clocks] master
## clocks that tick: true when the next pass starts in this frame.
func vblank(sound_clocks: int = MwPassCost.SOUND_MEAN_MCLK) -> bool:
	if _resync > 0:
		_resync -= 1
		if _resync > 0:
			return false
		_pos = MwPassCost.handler_mclk(_pending, _fade > 0, sound_clocks)
		_after_vblank()
		return true
	_pos = MwPassCost.handler_mclk(_pending, _fade > 0, sound_clocks)
	_after_vblank()
	_vblanks += 1
	if _done:                      # the tick wait, or the pass ended right at the VBlank
		last_elapsed = _vblanks
		return true
	return _run()


## [method vblank] with [member sound]'s cycles (the router's clock calls it
## once per tick, after the sound driver's tick).
func tick() -> bool:
	return vblank(int(sound.call()) if sound.is_valid() else MwPassCost.SOUND_MEAN_MCLK)


## The sound driver's master clocks for the running driver's work this tick
## ([member MwSound.driver]), its mean without one (headless runs).
static func driver_sound() -> int:
	if MwSound.driver != null and MwSound.driver.owed > 0:
		MwSound.driver.settle()                  # (plan 42: a model's owed ticks first)
	if MwSound.driver == null or MwSound.driver.s68k == null:
		return MwPassCost.SOUND_MEAN_MCLK
	return int(roundf(MwPassCost.sound_cycles(MwSound.driver.s68k.work) * MwPassCost.MCLK))


## An online match (plan 35: [method MwFlow.online]).
static func online_session(session: Object) -> bool:
	return session is MwSession and MwFlow.online(session)


## The ticks since the pass in flight started (the confirmed state's age:
## the rink's state is as that pass left it).
func since_pass() -> int:
	return RESYNC_TICKS - _resync if _resync > 0 else _vblanks


## Plan 35's dead reckoning (MwNetReckoning): the elapsed ticks of the
## passes that would start in the next [param ticks] ticks, the first
## counted from the pass in flight's start ([method since_pass] included),
## each later one after [param work] (the latest pass's, standing in for
## the passes to come; empty: [constant RESYNC_TICKS] apart), the sound
## driver at its mean - on a copy: this pacer is left as it is.
func predict(ticks: int, work: Dictionary) -> PackedInt32Array:
	var pacer := MwPassPacer.new()
	pacer.restore(snapshot())
	var out := PackedInt32Array()
	var since := since_pass()
	for i in ticks:
		since += 1
		if pacer.vblank():
			out.append(since)
			since = 0
			if work.is_empty():
				pacer.reset()
			else:
				pacer.begin(work)
	return out


## The pacer's whole state (the rink's hash: MwRinkState.pace), integers.
## The pacer is the rink scene's, made anew at each rink entry - plan 35's
## snapshots, taken as a screen is entered, never need it.
func snapshot() -> PackedInt32Array:
	var out := PackedInt32Array([_pos, _pending, _fade, 1 if _done else 0, _vblanks, _resync, last_elapsed])
	out.append_array(_seg.slice(_at))
	return out


## The pacer put back as [method snapshot] gave [param snap].
func restore(snap: PackedInt32Array) -> void:
	_pos = snap[0]
	_pending = snap[1]
	_fade = snap[2]
	_done = snap[3] != 0
	_vblanks = snap[4]
	_resync = snap[5]
	last_elapsed = snap[6]
	_seg = snap.slice(7)
	_at = 0


func _after_vblank() -> void:
	_pending = 0
	_fade = maxi(_fade - 1, 0)


## Runs the pass in flight up to the next VBlank: true when it finishes in
## this frame after at least one VBlank (the next pass starts now).
func _run() -> bool:
	while _at < _seg.size():
		var amount := _seg[_at + 1]
		match _seg[_at]:
			Seg.WORK:
				var left := MwPassCost.FRAME_MCLK - _pos
				if amount > left:
					_seg[_at + 1] = amount - left
					_pos = MwPassCost.FRAME_MCLK
					return false
				_pos += amount
			Seg.PUSH:
				_pending += amount
			Seg.WAIT:
				if amount > 0 and _pending > 0:
					_seg[_at + 1] = 0      # the next VBlank drains the queue
					return false
			Seg.FADE:
				_fade = amount
		_at += 2
	_done = true
	if _vblanks == 0:
		return false                   # no VBlank yet: the tick wait
	last_elapsed = _vblanks
	return true
