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


## Recordings somewhere else than out/sim (plan 36: the load recordings in
## out/load), absolute or relative to the repository; "" = out/sim.
static var dir_override := ""


## The folder the recordings are in: [member dir_override] when set (absolute, or relative to
## the repository), else out/sim ([method local_out]).
static func folder() -> String:
	if dir_override != "":
		return dir_override if dir_override.is_absolute_path() else local_out(dir_override)
	return local_out("out/sim")


## [param rel] (a folder of the repository's out/, local: never committed)
## as an absolute path: this checkout's, or - in a plan's worktree
## (`.worktrees/NAME`) that has none - the main checkout's (plan 40: the
## recordings live there; no symlink needed).
static func local_out(rel: String) -> String:
	var repo := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var here := repo.path_join(rel).simplify_path()
	if not DirAccess.dir_exists_absolute(here) and repo.contains("/.worktrees/"):
		return repo.get_slice("/.worktrees/", 0).path_join(rel).simplify_path()
	return here


## Recording [param name_] (its folder in [method folder]) read in; null without its meta.json.
static func open(name_: String) -> MwSimRecording:
	var dir := folder().path_join(name_)
	if not FileAccess.file_exists(dir.path_join("meta.json")):
		return null
	var recording := MwSimRecording.new()
	recording.name = name_
	recording.meta = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("meta.json")))
	recording.passes = recording.meta["passes"]
	recording._start = _gunzip(dir.path_join("start.bin.gz"))
	recording._mid = _gunzip(dir.path_join("mid.bin.gz"))
	recording._end = _gunzip(dir.path_join("end.bin.gz"))
	recording._ai = _gunzip(dir.path_join("ai.bin.gz"))
	if FileAccess.file_exists(dir.path_join("ring.bin.gz")):
		recording.ring0 = _gunzip(dir.path_join("ring.bin.gz"))
	recording.screen_passes = recording.meta.get("screen_passes", [])
	if FileAccess.file_exists(dir.path_join("screens.bin.gz")):
		recording._screens = _gunzip(dir.path_join("screens.bin.gz"))
	return recording


static func _gunzip(path: String) -> PackedByteArray:
	var data := FileAccess.get_file_as_bytes(path)
	return data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)


## How many rink passes were recorded.
func count() -> int:
	return passes.size()


## The replay ring's data before the first recorded pass: [member ring0],
## else an empty ring (recordings from power-on).
func ring_start() -> PackedByteArray:
	if not ring0.is_empty():
		return ring0.duplicate()
	return MwRinkState.ReplayRing.new().ring_bytes


## The RAM at the start of pass [param i]'s segment (an [MwRinkRam] image).
func start(i: int) -> PackedByteArray:
	return _start.slice(i * MwRinkRam.SIZE, (i + 1) * MwRinkRam.SIZE)


## The RAM at the end of pass [param i]'s segment (an [MwRinkRam] image).
func end(i: int) -> PackedByteArray:
	return _end.slice(i * MwRinkRam.SIZE, (i + 1) * MwRinkRam.SIZE)


## The RAM after both team updates of pass [param i] (mid; the AI snapshots' range, to
## `$FFBDC1`).
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


## The byte at [param addr] of the stack page at screen record [param i].
func stack_u8(i: int, addr: int) -> int:
	return screen_stack(i)[(addr & 0xFFFFFF) - STACK]


## Recorder v5: the visits of the screens between plays: [[first record,
## last record, screen], ...] (a visit starts at the screen's entry record).
func screen_visits() -> Array:
	var out := []
	for i in screen_passes.size():
		var record: Array = screen_passes[i]
		if int(record[3]) == SCREEN_ENTRY or out.is_empty():
			out.append([i, i, int(record[1])])
		else:
			out[out.size() - 1][1] = i
	return out


## Recorder v5: log [param kind]'s entries during screen record [param i].
func screen_log(kind: String, i: int) -> Array:
	var d: Dictionary = meta.get("screen_log_data", {}).get(kind, {})
	var entry: Variant = d.get(str(i))
	return entry if entry != null else []


## Log [param kind]'s entries of pass [param i] ([param after]: the entries
## after the segment instead): arrays of 32-bit values.
func log_entries(kind: String, i: int, after := false) -> Array:
	var d: Dictionary = meta["log_data"].get(kind, {})
	var entry: Variant = d.get(str(i))
	if entry == null:
		return []
	return entry[1 if after else 0]
