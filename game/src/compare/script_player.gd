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
	for e in input_script.events:
		if e.anchor == "tick":
			_tick_due.append([int(e.start), e])


func held(player: int) -> int:
	var m := 0
	for p in _active:
		if p.player == player:
			m |= p.mask
	return m


func held_all() -> Array[int]:
	var out: Array[int] = []
	for p in range(1, PLAYERS + 1):
		out.append(held(p))
	return out


func ended() -> bool:
	return ended_at >= 0


func screen_entered(screen: int, at_tick: int) -> void:
	tick = at_tick
	var visit := int(visits.get(screen, 0)) + 1
	visits[screen] = visit
	entries[Vector2i(screen, visit)] = at_tick
	var moment := "screen %d" % screen
	if current.x >= 0:  # pass-anchored holds end with their visit
		var old := current
		_release(func(p): return p.release_after != null and Vector2i(p.release_after.x, p.release_after.y) == old, moment)
	current = Vector2i(screen, visit)
	for e in input_script.events:
		if e.anchor == "screen" and e.screen == screen and e.visit == visit:
			if e.unit == "tick":
				_tick_due.append([at_tick + int(e.start), e])
			else:
				_pass_due.append([Vector3i(screen, visit, int(e.start)), e])
	_apply_tick_due(at_tick, moment)


func resume(screen: int, visit: int) -> void:
	current = Vector2i(screen, visit)


func tick_start(at_tick: int) -> void:
	tick = at_tick
	var moment := "tick %d" % at_tick
	_release(func(p): return p.release_tick >= 0 and p.release_tick <= at_tick, moment)
	_release(func(p): return p.event.mode == "tap" and at_tick - p.press_tick >= TAP_CAP_TICKS, moment)
	_apply_tick_due(at_tick, moment)


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


func _start(e: Dictionary, at_tick: int, moment: String) -> void:
	if e.mode == "end":
		if ended_at < 0:
			ended_at = at_tick
			change_log.append([moment, 0, 0, "end"])
		return
	_press(e, at_tick, moment, int(e.repeat) - 1)


func _press(e: Dictionary, at_tick: int, moment: String, taps_left: int) -> void:
	var p := {"event": e, "player": int(e.player), "mask": int(e.buttons), "press_tick": at_tick,
		"release_tick": -1, "release_after": null, "read": false, "taps_left": taps_left}
	if e.mode == "hold":
		if e.unit == "pass":
			p.release_after = Vector3i(e.screen, e.visit, int(e.end))
		elif e.anchor == "tick":
			p.release_tick = int(e.end)
		else:
			p.release_tick = int(entries[Vector2i(e.screen, e.visit)]) + int(e.end)
	var before := held(p.player)
	_active.append(p)
	if held(p.player) != before:
		change_log.append([moment, p.player, held(p.player), "down"])


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
