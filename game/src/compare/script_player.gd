class_name MwScriptPlayer
extends RefCounted
## Applies an input script as things happen: the GDScript twin of
## harness/mw_harness/script.py (ScriptPlayer).
##
## The rules (docs/compare.md): presses change only at a screen entry, at a
## tick start, or at a pass boundary. A tap is read by exactly one pass: it is
## released at the boundary after the pass that read it (or 16 ticks after the
## press when no pass ends, e.g. the pause menu's polling loop). Call
## [method screen_entered], [method tick_start] and [method boundary] in the
## order they happen; [method held] gives a player's pad bits.

const TAP_CAP_TICKS := 16
const PLAYERS := 4

var input_script: MwInputScript
var visits := {}            # screen -> visits so far
var entries := {}           # Vector2i(screen, visit) -> entry tick
var current := Vector2i(-1, -1)
var tick := 0
var ended_at := -1
## Every change as [moment, player, held bits after, "down"/"up"/"end"].
var change_log: Array = []

var _tick_due: Array = []   # [due tick, event]
var _pass_due: Array = []   # [Vector3i(screen, visit, pass), event]
var _next_taps: Array = []  # [due tick, press]
var _active: Array = []     # presses (Dictionary)


func _init(script_in: MwInputScript) -> void:
	input_script = script_in
	for event in input_script.events:
		if event.anchor == "tick":
			_tick_due.append([int(event.start), event])


## The pad bits player [param player] (1-4) holds now: the masks of his presses down, ORed.
func held(player: int) -> int:
	var m := 0
	for p in _active:
		if p.player == player:
			m |= p.mask
	return m


## [method held] for players 1 to 4, in order.
func held_all() -> Array[int]:
	var out: Array[int] = []
	for p in range(1, PLAYERS + 1):
		out.append(held(p))
	return out


## Whether the script has reached its end ([member ended_at]: the tick).
func ended() -> bool:
	return ended_at >= 0


## A screen entry at [param at_tick]: [param screen]'s visit counted, the holds anchored to
## the visit before released, this visit's events queued and those due started.
func screen_entered(screen: int, at_tick: int) -> void:
	tick = at_tick
	var visit := int(visits.get(screen, 0)) + 1
	visits[screen] = visit
	entries[Vector2i(screen, visit)] = at_tick
	var moment := "screen %d" % screen
	if current.x >= 0:  # pass-anchored holds end with their visit
		var old := current
		_release(func(p): return p.release_after != null and Vector2i(p.release_after.x, p.release_after.y) == old, \
				moment)
	current = Vector2i(screen, visit)
	for event in input_script.events:
		if event.anchor == "screen" and event.screen == screen and event.visit == visit:
			if event.unit == "tick":
				_tick_due.append([at_tick + int(event.start), event])
			else:
				_pass_due.append([Vector3i(screen, visit, int(event.start)), event])
	_apply_tick_due(at_tick, moment)


## A visit going on after a sub-screen (player stats -> game stats): [param screen]'s visit
## [param visit] is current again, without an entry.
func resume(screen: int, visit: int) -> void:
	current = Vector2i(screen, visit)


## A tick starts at [param at_tick]: the holds that end by then and the taps down
## [constant TAP_CAP_TICKS] ticks are released, then the events due start.
func tick_start(at_tick: int) -> void:
	tick = at_tick
	var moment := "tick %d" % at_tick
	_release(func(p): return p.release_tick >= 0 and p.release_tick <= at_tick, moment)
	_release(func(p): return p.event.mode == "tap" and at_tick - p.press_tick >= TAP_CAP_TICKS, moment)
	_apply_tick_due(at_tick, moment)


## A pass boundary at [param at_tick] (pass [param pass_index] of [param screen]'s visit
## [param visit]): the taps read and the pass-anchored holds past their end released, the
## events anchored here started, the taps still down marked read (released at the next).
func boundary(screen: int, visit: int, pass_index: int, at_tick: int) -> void:
	tick = at_tick
	var moment := "pass %d/%d/%d" % [screen, visit, pass_index]
	_release(func(p): return p.event.mode == "tap" and p.read, moment)
	_release(func(p): return p.release_after != null and p.release_after.x == screen \
			and p.release_after.y == visit and pass_index > p.release_after.z, moment)
	var key := Vector3i(screen, visit, pass_index)
	for item in _pass_due.duplicate():
		if item[0] == key:
			_pass_due.erase(item)
			_start(item[1], at_tick, moment)
	for p in _active:
		if p.event.mode == "tap":
			p.read = true


func _apply_tick_due(at_tick: int, moment: String) -> void:
	var due := _tick_due.duplicate()
	due.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1].line < b[1].line))
	for item in due:
		if item[0] <= at_tick:
			_tick_due.erase(item)
			_start(item[1], at_tick, moment)
	for item in _next_taps.duplicate():
		if item[0] <= at_tick:
			_next_taps.erase(item)
			_press(item[1].event, at_tick, moment, item[1].taps_left)


func _start(event: Dictionary, at_tick: int, moment: String) -> void:
	if event.mode == "end":
		if ended_at < 0:
			ended_at = at_tick
			change_log.append([moment, 0, 0, "end"])
		return
	_press(event, at_tick, moment, int(event.repeat) - 1)


func _press(event: Dictionary, at_tick: int, moment: String, taps_left: int) -> void:
	var press := {"event": event, "player": int(event.player), "mask": int(event.buttons), "press_tick": at_tick,
		"release_tick": -1, "release_after": null, "read": false, "taps_left": taps_left}
	if event.mode == "hold":
		if event.unit == "pass":
			press.release_after = Vector3i(event.screen, event.visit, int(event.end))
		elif event.anchor == "tick":
			press.release_tick = int(event.end)
		else:
			press.release_tick = int(entries[Vector2i(event.screen, event.visit)]) + int(event.end)
	var before := held(press.player)
	_active.append(press)
	if held(press.player) != before:
		change_log.append([moment, press.player, held(press.player), "down"])


func _release(pred: Callable, moment: String) -> void:
	for p in _active.duplicate():
		if not pred.call(p):
			continue
		var before := held(p.player)
		_active.erase(p)
		if held(p.player) != before:
			change_log.append([moment, p.player, held(p.player), "up"])
		if p.event.mode == "tap" and p.taps_left > 0:
			var nxt := {"event": p.event, "taps_left": p.taps_left - 1}
			_next_taps.append([tick + 1, nxt])
