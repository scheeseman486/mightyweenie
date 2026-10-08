class_name MwSimRecording
extends RefCounted
## A simulation recording of the original (`mw_harness sim-record` ->
## out/sim/NAME/; docs/compare.md, Simulation recordings): per rink pass the
## RAM at the segment's start, after both team updates (mid) and at its end,
## the RAM before / after every CPU think, and the call logs. Snapshots are
## [MwRinkRam] byte images.

var name := ""
var meta := {}
var passes: Array = []
var _start := PackedByteArray()
var _mid := PackedByteArray()
var _end := PackedByteArray()
var _ai := PackedByteArray()
## The replay ring's data (`$FF0000`, 32 KB) when the recording started in
## the middle of a match (a soak run recorded from a later visit; plan 10):
## the ring keeps frames over faceoffs and the instant replay.
var ring0 := PackedByteArray()
## Recorder v5 (plan 11): the screens between plays, per screen entry / pass
## ([member screen_passes] [rink passes so far, screen, tick, site (`$20AC`:
## the entry), d0]): the RAM (an [MwRinkRam] image, then the stack page
## `$FFFE00`-`$FFFFFF` where the handlers' locals are).
var screen_passes: Array = []
var _screens := PackedByteArray()
const SCREEN_ENTRY := 0x20AC
const STACK := 0xFFFE00
const STACK_SIZE := 0x200


static func folder() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../out/sim").simplify_path()


static func open(name_: String) -> MwSimRecording:
	var dir := folder().path_join(name_)
	if not FileAccess.file_exists(dir.path_join("meta.json")):
		return null
	var r := MwSimRecording.new()
	r.name = name_
	r.meta = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("meta.json")))
	r.passes = r.meta["passes"]
	r._start = _gunzip(dir.path_join("start.bin.gz"))
	r._mid = _gunzip(dir.path_join("mid.bin.gz"))
	r._end = _gunzip(dir.path_join("end.bin.gz"))
	r._ai = _gunzip(dir.path_join("ai.bin.gz"))
	if FileAccess.file_exists(dir.path_join("ring.bin.gz")):
		r.ring0 = _gunzip(dir.path_join("ring.bin.gz"))
	r.screen_passes = r.meta.get("screen_passes", [])
	if FileAccess.file_exists(dir.path_join("screens.bin.gz")):
		r._screens = _gunzip(dir.path_join("screens.bin.gz"))
	return r


static func _gunzip(path: String) -> PackedByteArray:
	var data := FileAccess.get_file_as_bytes(path)
	return data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)


func count() -> int:
	return passes.size()


## The replay ring's data before the first recorded pass: [member ring0],
## else an empty ring (recordings from power-on).
func ring_start() -> PackedByteArray:
	if not ring0.is_empty():
		return ring0.duplicate()
	return MwRinkState.ReplayRing.new().ring_bytes


func start(i: int) -> PackedByteArray:
	return _start.slice(i * MwRinkRam.SIZE, (i + 1) * MwRinkRam.SIZE)


func end(i: int) -> PackedByteArray:
	return _end.slice(i * MwRinkRam.SIZE, (i + 1) * MwRinkRam.SIZE)


func mid(i: int) -> PackedByteArray:
	return _mid.slice(i * MwRinkRam.AI_SIZE, (i + 1) * MwRinkRam.AI_SIZE)


## The AI snapshot number [param k] (indices in the pass's "ai" list).
func ai(k: int) -> PackedByteArray:
	return _ai.slice(k * MwRinkRam.AI_SIZE, (k + 1) * MwRinkRam.AI_SIZE)


## Elapsed ticks of pass [param i].
func elapsed(i: int) -> int:
	return int(passes[i]["e"])


## Recorder v5: the RAM image ([MwRinkRam]) at screen record [param i].
func screen_ram(i: int) -> PackedByteArray:
	var n := MwRinkRam.SIZE + STACK_SIZE
	return _screens.slice(i * n, i * n + MwRinkRam.SIZE)


## Recorder v5: the stack page at screen record [param i].
func screen_stack(i: int) -> PackedByteArray:
	var n := MwRinkRam.SIZE + STACK_SIZE
	return _screens.slice(i * n + MwRinkRam.SIZE, (i + 1) * n)


## A word / byte of the stack page at screen record [param i] (`$FFFE00`-`$FFFFFF`).
func stack_u16(i: int, addr: int) -> int:
	var b := screen_stack(i)
	var o := (addr & 0xFFFFFF) - STACK
	return (b[o] << 8) | b[o + 1]


func stack_u8(i: int, addr: int) -> int:
	return screen_stack(i)[(addr & 0xFFFFFF) - STACK]


## Recorder v5: the visits of the screens between plays: [[first record,
## last record, screen], ...] (a visit starts at the screen's entry record).
func screen_visits() -> Array:
	var out := []
	for i in screen_passes.size():
		var e: Array = screen_passes[i]
		if int(e[3]) == SCREEN_ENTRY or out.is_empty():
			out.append([i, i, int(e[1])])
		else:
			out[out.size() - 1][1] = i
	return out


## Recorder v5: log [param kind]'s entries during screen record [param i].
func screen_log(kind: String, i: int) -> Array:
	var d: Dictionary = meta.get("screen_log_data", {}).get(kind, {})
	var e: Variant = d.get(str(i))
	return e if e != null else []


## Log [param kind]'s entries of pass [param i] ([param after]: the entries
## after the segment instead): arrays of 32-bit values.
func log_entries(kind: String, i: int, after := false) -> Array:
	var d: Dictionary = meta["log_data"].get(kind, {})
	var e: Variant = d.get(str(i))
	if e == null:
		return []
	return e[1 if after else 0]
