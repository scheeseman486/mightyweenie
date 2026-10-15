class_name MwPassRecorder
extends RefCounted
## Writes a pass record (mw-pass/1, docs/compare.md) from our side: one JSON
## line per completed pass, plus screen events. Probe fields beyond the
## always-present ones come from the caller (the simulation's observe()).

var lines: PackedStringArray = []


## The record's first line: format and side, the input script [param script_name], the probe
## sets [param probes] and the [param tool] that wrote it.
func header(script_name: String, probes: Array, tool := "godot") -> void:
	_add({"format": "mw-pass/1", "side": "godot", "script": script_name, "probes": probes, "tool": tool})


## A screen event: visit [param visit] of screen [param screen_id] entered at [param tick], from
## screen [param prev].
func screen(screen_id: int, visit: int, tick: int, prev: int) -> void:
	_add({"event": "screen", "screen": screen_id, "visit": visit, "tick": tick, "prev": prev})


## A resume event: screen [param screen_id]'s visit [param visit] going on at [param tick]
## (screen 8 after the player stats).
func resume(screen_id: int, visit: int, tick: int) -> void:
	_add({"event": "resume", "screen": screen_id, "visit": visit, "tick": tick})


## [param pads]: the four pad words as the pass read them (high byte held,
## low byte newly pressed). [param fields]: extra probe fields.
func pass_line(b: Dictionary, pads: Array, fields: Dictionary = {}) -> void:
	var d := {"screen": int(b.screen), "visit": int(b.visit), "pass": int(b.pass), "tick": int(b.tick),
		"elapsed": int(b.elapsed), "pads": pads}
	d.merge(fields)
	_add(d)


## The end event, at [param tick].
func end(tick: int) -> void:
	_add({"event": "end", "tick": tick})


## Writes the lines to [param path] (its folder made first): OK, or the error opening it.
func save(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	for l in lines:
		f.store_line(l)
	return OK


func _add(d: Dictionary) -> void:
	lines.append(JSON.stringify(d, "", false))
