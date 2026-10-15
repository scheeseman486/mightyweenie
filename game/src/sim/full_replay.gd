class_name MwFullReplay
extends RefCounted
## The whole match's replay (plan 28, owner: recordings the whole game long;
## REPLAY LENGTH: FULL GAME). The original's replay ring
## (MwRinkState.ReplayRing, `docs/re/replay.md`) holds the last play only:
## it is emptied at every faceoff and drops its oldest frames when its 32 KB
## are full. It stays exactly as it is; beside it this keeps every frame
## the ring closes, for the whole match (MwRinkUpdate.draws): the frame as
## the ring holds it (header, camera point, hazards, markers, sprite
## records, trailer: big-endian words) and its 3D frame (MwReplay3D),
## compressed. MwFullReplayPlayback plays it on screen 7. Presentation
## only: outside the comparisons (MwSimDict.skipped).

## Each frame's bytes, oldest first.
var frames: Array[PackedByteArray] = []
## The 3D frames (plan 34: kept in chunks, as saved replays store them -
## consecutive frames are much alike, so a chunk compressed whole is a
## fifth of its frames compressed one by one): each frame's var_to_bytes,
## joined in frame order. [member chunks] holds the closed chunks (zstd),
## [member chunk_sizes] their raw sizes and [member chunk_first] the index
## of each one's first frame; the frames since go to an open chunk, closed
## every [constant CHUNK] frames.
const CHUNK := 256
var chunks: Array[PackedByteArray] = []
var chunk_sizes := PackedInt32Array()
var chunk_first := PackedInt32Array()
## Each frame's 3D frame: where it starts in its chunk's raw bytes, its
## length (0: none was kept).
var side_at := PackedInt32Array()
var side_len := PackedInt32Array()
var _open := PackedByteArray()
var _open_first := 0
var _cached := -1                    # the chunk decompressed last, and its bytes
var _cache := PackedByteArray()
## The arena's paint's seed (plan 37, MwSplatter.seed, from the first 3D
## frame with the paint; -1: none - no paint, or an older file): with the
## inputs each 3D frame keeps ("splat" "in") a playback makes the paint
## again (MwSplatterReplay); the texels are never kept.
var splat_seed := -1
## Plan 35 work item 6: frames the match had recorded before this machine's
## recording began - a machine that rejoined an online match keeps the
## match from its return on (its FULL GAME replay starts there), but the
## game's flow asks how much the match recorded ([method recorded]), the
## same on every machine.
var before := 0


## Frames kept.
func size() -> int:
	return frames.size()


## Frames the match has recorded: those kept and those from before this
## machine's recording began ([member before]).
func recorded() -> int:
	return before + frames.size()


## Keeps the frame [param ring] has just closed, which started at
## [param start] (its header), with its 3D frame [param frame_3d] (MwReplay3D;
## {} none).
func add(ring: MwRinkState.ReplayRing, start: int, frame_3d: Dictionary) -> void:
	var ring_size := MwRinkState.ReplayRing.SIZE
	var n := (ring.write - start + ring_size) % ring_size
	var b := ring.ring_bytes.slice(start, mini(start + n, ring_size))
	if start + n > ring_size:
		b.append_array(ring.ring_bytes.slice(0, start + n - ring_size))       # the frame wrapped round the ring
	add_frame(b, frame_3d)


## Keeps a frame's bytes [param b] and its 3D frame [param frame_3d] ({} none).
func add_frame(b: PackedByteArray, frame_3d: Dictionary) -> void:
	frames.append(b)
	var splat: Variant = frame_3d.get("splat")
	if splat_seed < 0 and splat is Dictionary:
		splat_seed = int((splat as Dictionary).get("seed", -1))
	side_at.append(_open.size())
	if frame_3d.is_empty():
		side_len.append(0)
	else:
		var raw := var_to_bytes(side_to_data(frame_3d))
		side_len.append(raw.size())
		_open.append_array(raw)
	if frames.size() - _open_first >= CHUNK:
		seal()


## Closes the open chunk (a saved replay closes it to write it).
func seal() -> void:
	if frames.size() == _open_first:
		return
	chunks.append(_open.compress(FileAccess.COMPRESSION_ZSTD))
	chunk_sizes.append(_open.size())
	chunk_first.append(_open_first)
	_open = PackedByteArray()
	_open_first = frames.size()


## Frame [param i]'s words (header first, trailer last).
func words(i: int) -> PackedInt32Array:
	var b := frames[i]
	var out := PackedInt32Array()
	out.resize(b.size() / 2)
	for k in out.size():
		out[k] = (b[2 * k] << 8) | b[2 * k + 1]
	return out


## Frame [param i]'s recorded pass length (its header's e: ticks).
func ticks(i: int) -> int:
	return frames[i][1] & 0xF if frames[i].size() >= 2 else 0


## Frame [param i]'s 3D frame ({} none, or unreadable).
func side(i: int) -> Dictionary:
	if i < 0 or i >= frames.size() or side_len[i] == 0:
		return {}
	var raw := _open
	if i < _open_first:
		var c := chunk_first.bsearch(i, false) - 1         # the chunk whose first frame is at or before i
		if c != _cached:
			_cache = chunks[c].decompress(chunk_sizes[c], FileAccess.COMPRESSION_ZSTD)
			_cached = c
		raw = _cache
	if side_at[i] + side_len[i] > raw.size():
		return {}
	var d: Variant = bytes_to_var(raw.slice(side_at[i], side_at[i] + side_len[i]))
	return side_from_data(d) if d is Dictionary else {}


## A reader of the frames kept now for another thread (MwSplatterReplay's
## maker): its own decompressed chunk, the arrays copied (the frames' and
## chunks' bytes shared, unchanged), so neither store's later use touches
## the other's.
func reader() -> MwFullReplay:
	var copy := MwFullReplay.new()
	copy.frames = frames.duplicate()
	copy.chunks = chunks.duplicate()
	copy.chunk_sizes = chunk_sizes.duplicate()
	copy.chunk_first = chunk_first.duplicate()
	copy.side_at = side_at.duplicate()
	copy.side_len = side_len.duplicate()
	copy._open = _open.duplicate()
	copy._open_first = _open_first
	copy.splat_seed = splat_seed
	copy.before = before
	return copy


## The store as plain data (a saved replay's body; [method seal] first).
func to_data() -> Dictionary:
	seal()
	return {"frames": frames, "chunks": chunks, "chunk_sizes": chunk_sizes, "chunk_first": chunk_first,
			"side_at": side_at, "side_len": side_len, "splat_seed": splat_seed}


## A store from [method to_data]'s; [param sides]: false drops the 3D frames
## (a file whose 3D frames this build can't read plays in 2D).
static func from_data(d: Dictionary, sides := true) -> MwFullReplay:
	var full_replay := MwFullReplay.new()
	full_replay.splat_seed = int(d.get("splat_seed", -1))         # (-1: an older file - MwSplatterReplay derives one)
	for f in d.get("frames", []):
		full_replay.frames.append(f)
	var n := full_replay.frames.size()
	full_replay.side_at = d.get("side_at", PackedInt32Array()) if sides else PackedInt32Array()
	full_replay.side_len = d.get("side_len", PackedInt32Array()) if sides else PackedInt32Array()
	if full_replay.side_at.size() != n or full_replay.side_len.size() != n:
		full_replay.side_at.resize(n)
		full_replay.side_len.resize(n)
		full_replay.side_at.fill(0)
		full_replay.side_len.fill(0)                   # no 3D frames: 2D
	else:
		for c in d.get("chunks", []):
			full_replay.chunks.append(c)
		full_replay.chunk_sizes = d.get("chunk_sizes", PackedInt32Array())
		full_replay.chunk_first = d.get("chunk_first", PackedInt32Array())
	full_replay._open_first = n
	return full_replay


## A 3D frame as plain data (its shot an object: as a dictionary). Plan 34
## added the drivers (3D EXTENDED's targets) as two more keys: a file
## without them still reads (the shot keeps its empty defaults) and an older
## build skips them, so [constant MwReplayFile.SIDE_FORMAT] stays. The
## paint's ("splat", plan 37) atlas is the match's object, not data: left
## out (and its seed, [member splat_seed]) - the playback makes it again
## from the frames' inputs (MwSplatterReplay); an older build reads the
## frame as before (its atlas missing: no paint).
static func side_to_data(frame_3d: Dictionary) -> Dictionary:
	var d := frame_3d.duplicate()
	var splat: Variant = frame_3d.get("splat")
	if splat is Dictionary:
		var sp := (splat as Dictionary).duplicate()
		sp.erase("atlas")
		sp.erase("seed")
		d["splat"] = sp
	var shot: MwRinkShot3D = frame_3d.get("shot")
	if shot != null:
		d["shot"] = shot.to_data()
	return d


## [method side_to_data] undone.
static func side_from_data(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	var shot: Variant = d.get("shot")
	if shot is Dictionary:
		out["shot"] = MwRinkShot3D.from_data(shot)
	return out
