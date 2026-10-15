class_name MwPassClock
extends RefCounted
## Decides when each screen's loop ends a pass ("boundary") and how many ticks
## the pass took (docs/compare.md, docs/re/timing.md).
##
## REALTIME: one pass every N ticks of the global 60 Hz tick, N per screen
## (approved model: menus 1, gameplay 2 - "for now"), unless the screen
## paces its own passes: a screen whose `pass_pacer()` returns an
## [MwPassPacer] (the rink with TICK RATE ORIGINAL, plan 36) gets its next
## pass when the pacer's [method MwPassPacer.tick] says the original's
## would start.
## REPLAY: the boundaries recorded from the original, per screen visit and
## relative to the visit's entry, so our logic sees exactly the original's
## passes and elapsed ticks.
##
## STREAM (plan 35, docs/net.md): REALTIME's passes, but a tick runs only
## once the input stream has it ([method ready]: [member stream]'s last
## confirmed tick) - the router holds (no tick, no pass, no sound driver
## tick, no fade step) until it comes. A replay of a recorded stream holds
## at its end; online the network feeds it (work item 4) and a client
## behind runs ticks back to back. (A recording itself runs REALTIME: its
## stream is filled by the capture inside each tick, MwStreamInput.)
##
## Usage per tick: [method screen_entered] / [method resume] when the screen
## changes, then [method due] returns the boundaries that fall on this tick.
## Short names: c a pass clock.

enum Mode { REALTIME, REPLAY, STREAM }

## The rink's pass in ticks (screens 4-6 in REALTIME; OVERCLOCKED's
## passes): plan 40, S12 - every "2" that means it.
const RINK_PASS_TICKS := 2
## Ticks per pass in REALTIME, by screen ID; others use [member default_pass_ticks].
const DEFAULT_PASS_TICKS := {4: RINK_PASS_TICKS, 5: RINK_PASS_TICKS, 6: RINK_PASS_TICKS}

var mode: Mode = Mode.REALTIME
var pass_ticks: Dictionary = DEFAULT_PASS_TICKS.duplicate()
var default_pass_ticks := 1
var screen := -1
var visit := 0

## STREAM: the input stream whose confirmed ticks may run.
var stream: MwInputStream = null

var _visits := {}            # screen -> visits so far
var _state := {}             # Vector2i(screen, visit) -> {"entry", "next", "queue"}
var _replay := {}            # Vector2i(screen, visit) -> Array of [relative tick, elapsed]


## A REALTIME clock: [param table] the ticks per pass by screen ID, [param default_ticks]
## those of every other screen.
static func realtime(table: Dictionary = DEFAULT_PASS_TICKS, default_ticks := 1) -> MwPassClock:
	var c := MwPassClock.new()
	c.mode = Mode.REALTIME
	c.pass_ticks = table.duplicate()
	c.default_pass_ticks = default_ticks
	return c


## Plan 35: REALTIME's passes, each tick waiting for [param input_stream]
## to confirm it.
static func streamed(input_stream: MwInputStream, table: Dictionary = DEFAULT_PASS_TICKS,
		default_ticks := 1) -> MwPassClock:
	var c := realtime(table, default_ticks)
	c.mode = Mode.STREAM
	c.stream = input_stream
	return c


## Whether tick [param tick] may run: always, but in STREAM mode only once
## the stream holds it.
func ready(tick: int) -> bool:
	return mode != Mode.STREAM or (stream != null and tick <= stream.last_tick())


## [param records]: the lines of an mw-pass/1 record (parsed JSON).
static func replay(records: Array) -> MwPassClock:
	var c := MwPassClock.new()
	c.mode = Mode.REPLAY
	var entry := {}
	for r in records:
		if r.get("event", "") == "screen":
			var key := Vector2i(int(r.screen), int(r.visit))
			entry[key] = int(r.tick)
			c._replay[key] = []
		elif not r.has("event") and r.has("pass"):
			var key := Vector2i(int(r.screen), int(r.visit))
			if c._replay.has(key):
				c._replay[key].append([int(r.tick) - int(entry[key]), int(r.elapsed)])
	return c


## Plan 35 work item 6: what a resync snapshot carries of the clock - the
## visits counted per screen (the next screen's visit number; its passes
## start afresh at its entry).
func snapshot_state() -> Dictionary:
	return {"visits": _visits.duplicate()}


## [method snapshot_state]'s [param d] back: the visits counted per screen.
func restore_state(d: Dictionary) -> void:
	_visits = {}
	var v: Variant = d.get("visits", {})
	if v is Dictionary:
		for k in v:
			_visits[k] = int(v[k])


## The ticks per pass of screen [param screen_id] in REALTIME ([member pass_ticks], else
## [member default_pass_ticks]).
func pass_length(screen_id: int) -> int:
	return int(pass_ticks.get(screen_id, default_pass_ticks))


## Screen [param screen_id] entered at [param tick]: its visit counted, its passes counted
## from there (REPLAY: that visit's recorded boundaries queued).
func screen_entered(screen_id: int, tick: int) -> void:
	var v := int(_visits.get(screen_id, 0)) + 1
	_visits[screen_id] = v
	screen = screen_id
	visit = v
	var key := Vector2i(screen_id, v)
	var queue: Array = []
	if mode == Mode.REPLAY:
		for b in _replay.get(key, []):
			queue.append([tick + int(b[0]), int(b[1])])
	_state[key] = {"entry": tick, "next": 0, "queue": queue, "last": tick}


## The screen [param screen_id]'s visit [param visit_no] resumed (a pushed
## screen popped); [param from] >= 0: its passes count afresh from that tick
## (MwScreen.resume_fresh), else they go on from its last pass.
func resume(screen_id: int, visit_no: int, from := -1) -> void:
	screen = screen_id
	visit = visit_no
	var st: Dictionary = _state.get(Vector2i(screen_id, visit_no), {})
	if from >= 0 and not st.is_empty():
		st.last = from


## Plan 41 (the run-ahead): the tick the current visit's last pass ran at
## (-1: none yet).
func last_pass_tick() -> int:
	return int(_state.get(Vector2i(screen, visit), {}).get("last", -1))


## Boundaries of the current visit that fall on [param tick] (at most one per
## tick in practice), each {"screen", "visit", "pass", "tick", "elapsed"}.
## [param top]: the screen (REALTIME: its `pass_pacer()`, when it has one).
func due(tick: int, top: Object = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st: Dictionary = _state.get(Vector2i(screen, visit), {})
	if st.is_empty():
		return out
	if mode == Mode.REPLAY:
		while not st.queue.is_empty() and int(st.queue[0][0]) <= tick:
			var b: Array = st.queue.pop_front()
			out.append({"screen": screen, "visit": visit, "pass": st.next, "tick": tick, "elapsed": int(b[1])})
			st.next += 1
	else:
		var pacer: MwPassPacer = top.pass_pacer() if top != null and top.has_method("pass_pacer") else null
		if pacer != null:
			if pacer.tick():
				out.append({"screen": screen, "visit": visit, "pass": st.next, "tick": tick,
						"elapsed": tick - int(st.last)})
				st.next += 1
				st.last = tick
			return out
		var n := pass_length(screen)
		if tick - int(st.last) >= n:
			out.append({"screen": screen, "visit": visit, "pass": st.next, "tick": tick,
					"elapsed": tick - int(st.last)})
			st.next += 1
			st.last = tick
	return out
