class_name MwPassClock
extends RefCounted
## Decides when each screen's loop ends a pass ("boundary") and how many ticks
## the pass took (docs/compare.md, docs/re/timing.md).
##
## REALTIME: one pass every N ticks of the global 60 Hz tick, N per screen
## (approved model: menus 1, gameplay 2 - "for now").
## REPLAY: the boundaries recorded from the original, per screen visit and
## relative to the visit's entry, so our logic sees exactly the original's
## passes and elapsed ticks.
##
## Usage per tick: [method screen_entered] / [method resume] when the screen
## changes, then [method due] returns the boundaries that fall on this tick.

enum Mode { REALTIME, REPLAY }

## Ticks per pass in REALTIME, by screen ID; others use [member default_pass_ticks].
const DEFAULT_PASS_TICKS := {4: 2, 5: 2, 6: 2}

var mode: Mode = Mode.REALTIME
var pass_ticks: Dictionary = DEFAULT_PASS_TICKS.duplicate()
var default_pass_ticks := 1
var screen := -1
var visit := 0

var _visits := {}            # screen -> visits so far
var _state := {}             # Vector2i(screen, visit) -> {"entry", "next", "queue"}
var _replay := {}            # Vector2i(screen, visit) -> Array of [relative tick, elapsed]


static func realtime(table: Dictionary = DEFAULT_PASS_TICKS, default_ticks := 1) -> MwPassClock:
	var c := MwPassClock.new()
	c.mode = Mode.REALTIME
	c.pass_ticks = table.duplicate()
	c.default_pass_ticks = default_ticks
	return c


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


func pass_length(screen_id: int) -> int:
	return int(pass_ticks.get(screen_id, default_pass_ticks))


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


func resume(screen_id: int, visit_no: int) -> void:
	screen = screen_id
	visit = visit_no


## Boundaries of the current visit that fall on [param tick] (at most one per
## tick in practice), each {"screen", "visit", "pass", "tick", "elapsed"}.
func due(tick: int) -> Array[Dictionary]:
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
		var n := pass_length(screen)
		if tick - int(st.last) >= n:
			out.append({"screen": screen, "visit": visit, "pass": st.next, "tick": tick, "elapsed": tick - int(st.last)})
			st.next += 1
			st.last = tick
	return out
