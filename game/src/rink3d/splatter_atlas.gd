class_name MwSplatterAtlas
extends RefCounted
## The paint on the 3D arena (plan 37, docs/rink3d.md, Splatter): blood and
## oil kept all match in one R8 texture of [constant SIZE] x [constant SIZE]
## texels, which the rink's floor, board, glass and fence shaders read at UV2
## (rink3d_paint.gdshaderinc). Each texel holds two fields: bits 0-1 the
## paint ([constant CLEAR], [constant BLOOD], [constant OIL]), bits 2-3 the
## ice's own detail (owner: a dark bit and a light bit: [constant DARK],
## [constant LIGHT] - faint splotches laid at the match's start and the
## skates' scratches, drawn at ~10 % on the ice); each operation writes one
## field and keeps the other.
##
## **On the pixel grid.** The model's UV2 is its UV0 (a ROM picture's pixels)
## shifted by whole texels into this atlas, every paintable surface in a
## place of its own (tools/blender/rink_build.py `paint_layout`, written to
## [constant LAYOUT]): the ice in two blocks (rink px; behind the near goal
## line the far end's mirrored, scaled rows), the boards' rink side in runs
## (a strip of faces continuing one another), each with a texel of margin.
## So a paint texel has exactly the edges of the picture's texel it lies on.
##
## **Painting** is destination-driven: for every atlas texel a splat could
## cover, the texel's centre on the surface (ice: rink x, y; boards: arc
## length s along the boards' loop and height z) picks the sprite's pixel
## there, nearest, after the splat's turn and scale. Every painted texel is
## one texel of the existing grid at any angle; at quarter turns and 1:1 the
## art is untouched. New paint covers old; nothing is erased.
##
## **Operations.** The texture changes only by [method add]ed operations
## (stamps on the ice or the boards, skates' streaks, pools), kept in order
## with a compressed copy of the texels every so often, so [method seek] can
## show the paint as it was after any number of them (the replays). Each is
## applied from its stored (32-bit) numbers, live and when replayed alike, so
## both give the same texels.
##
## **Rewinding** (owner, 2026-10-15: large drops in performance while
## rewinding): a seek back started from the checkpoint before it and
## applied up to [constant CHECKPOINT_OPS] operations again - every frame of
## a rewind, at the match's start its ice splotches each time (~0.4 s a
## frame on the desktop, and the ticks that piled up behind it did it
## again). Plain copies of the texels are now kept every
## [constant COPY_STEP] operations as they are applied - live, a replay
## going forward, a seek on its way - the [constant COPY_KEEP] nearest where
## the texels are, so a rewind frame by frame starts each seek a few
## operations back; and [method seek_toward] does a seek's work a share at a
## time (the 3D view: [constant MwRinkView3D.PAINT_USEC] a rendered frame),
## so a jump far back catches up over a few frames instead of holding one.
##
## **A recording's paint made on a worker thread** (owner, 2026-10-15:
## replays were still juddery and slow; MwSplatterReplay): one atlas makes
## the operations there, [member copies] off as it never seeks; the one
## shown [member follows] it - its operations ([method append]) and
## checkpoints ([method take_checkpoint]) handed over as they are made, its
## texels only ever seeked. The sprite masks and cut sides cached for the
## run are shared by both threads ([member cache_lock]).

const SIZE := 1024
const LAYOUT := "res://assets/rink3d/rink_paint.json"
enum { CLEAR, BLOOD, OIL }
## The ice's detail (bits 2-3): none, dark, light.
enum { NO_DETAIL, DARK, LIGHT }
## Which field an ice stamp writes.
enum { PAINT, DETAIL }
enum { OP_ICE, OP_WALL, OP_STREAK, OP_POOL, OP_SKATES }
const PAINT_BITS := 3
const DETAIL_BITS := 12
## A copy of the texels at least every this many operations, or sooner after
## this much painting (texels looked at): a seek back replays few.
const CHECKPOINT_OPS := 300
const CHECKPOINT_WORK := 400000
## A plain copy of the texels every this many operations applied, at most
## [constant COPY_KEEP] kept (1 MiB each): the ones nearest the texels.
const COPY_STEP := 16
const COPY_KEEP := 16
## A streak's load (texels of track) on leaving paint; the last third broken.
const STREAK_LOAD := 40
## A foot takes paint up only after this many painted texels in a row: it
## stepped into a patch, not across another skate's line (which would
## spread the streaks from each other all over the ice).
const STREAK_WET := 3

## The layout, parsed once per run (static): see [method layout].
## Guards the sprites' caches ([method mask], [method cut_side], and
## MwSplatter's centres) - a recording's paint is made on a worker thread
## (MwSplatterReplay). The layout is read once on the main thread before.
static var cache_lock := Mutex.new()
static var _layout := {}
## Sprite masks by frame address (static): {w, h, ox, oy, px (colour indices)}.
static var _masks := {}
static var _cuts := {}
## A frame's side cut straight ([method cut_side]): bottom, top, left, right.
enum { CUT_BOTTOM, CUT_TOP, CUT_LEFT, CUT_RIGHT }

var data := PackedByteArray()          ## the texels (row-major, SIZE x SIZE)
var _texture: ImageTexture
var _dirty := true
var _log := PackedFloat32Array()       # every operation's numbers, in order
var _starts := PackedInt32Array()      # where each operation starts in _log
var _applied := 0                      # operations the texels show
var _checkpoints: Array = []           # [[operations, compressed texels], ...], ascending
var _work := 0                         # texels looked at since the last checkpoint
var _copies: Array = []                # [[operations, texels], ...], ascending (plain: no decompressing)
## Plain copies kept as operations are applied ([constant COPY_STEP]); off
## for an atlas that only makes operations (MwSplatterReplay's maker).
var copies := true
## Fed another atlas's operations and checkpoints ([method append], [method
## take_checkpoint]; MwSplatterReplay's shown atlas): never adds its own,
## and the 3D view seeks it a share at a time always (MwRinkView3D).
var follows := false


func _init() -> void:
	data.resize(SIZE * SIZE)
	_checkpoints.append([0, PackedByteArray()])


# --- the layout --------------------------------------------------------------------------

## The paint layout ([constant LAYOUT]) with tables made from it: "runs"
## (the boards' runs: [object, ax, ay, w, h, dx, dy, s0, s1, u0, u1, z0, z1,
## v0, v1]), "loop" (PackedVector2Array, the boards from the far centre
## clockwise), "cum" (arc length at each loop point), "total", "xlim" (the
## boards' |x| at each ice row, y -372..372), "top" (the boards' top z at
## each whole s), "near_k" (the near rows' scale), the ice blocks' numbers.
static func layout() -> Dictionary:
	if not _layout.is_empty():
		return _layout
	var f := FileAccess.open(LAYOUT, FileAccess.READ)
	if f == null:
		return {}
	var j: Dictionary = JSON.parse_string(f.get_as_text())
	var board_layout := {"runs": j["runs"], "total": float(j["total"]), "dead": j["dead"]}
	var ice: Dictionary = j["ice"]
	board_layout["main_d"] = Vector2i(int(ice["main"]["d"][0]), int(ice["main"]["d"][1]))
	board_layout["main_rows"] = Vector2i(int(ice["main"]["rows"][0]), int(ice["main"]["rows"][1]))
	board_layout["near_d"] = Vector2i(int(ice["near"]["d"][0]), int(ice["near"]["d"][1]))
	board_layout["near_rows"] = Vector2i(int(ice["near"]["rows"][0]), int(ice["near"]["rows"][1]))
	board_layout["near_y"] = Vector2(float(ice["near"]["y"][0]), float(ice["near"]["y"][1]))
	board_layout["cols"] = Vector2i(int(ice["cols"][0]), int(ice["cols"][1]))
	board_layout["near_k"] = PackedFloat32Array(ice["near"]["k"])
	var loop := PackedVector2Array()
	for point: Array in j["loop"]:
		loop.append(Vector2(float(point[0]), float(point[1])))
	var cum := PackedFloat32Array([0.0])
	for i in range(1, loop.size() + 1):
		cum.append(cum[i - 1] + loop[i - 1].distance_to(loop[i % loop.size()]))
	board_layout["loop"] = loop
	board_layout["cum"] = cum
	# the boards' |x| per ice row (row centre y + 0.5), from the loop's edges
	var xlim := PackedFloat32Array()
	for row in range(-372, 373):
		var y := row + 0.5
		var best := 0.0
		for i in loop.size():
			var a := loop[i]
			var b := loop[(i + 1) % loop.size()]
			if (a.y <= y) != (b.y <= y):
				best = maxf(best, absf(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y)))
		xlim.append(best)
	board_layout["xlim"] = xlim
	# the boards' top (z) at each whole s: the highest run standing there
	var top := PackedFloat32Array()
	top.resize(int(ceil(board_layout["total"])) + 1)
	for r: Array in board_layout["runs"]:
		var s0 := minf(float(r[7]), float(r[8]))
		var s1 := maxf(float(r[7]), float(r[8]))
		for arc_length in range(int(floor(s0)), int(ceil(s1)) + 1):
			if arc_length >= 0 and arc_length < top.size():
				top[arc_length] = maxf(top[arc_length], maxf(float(r[11]), float(r[12])))
	board_layout["top"] = top
	_layout = board_layout
	return board_layout


## Whether rink point ([param x], [param y]) is on the ice, inside the boards.
static func on_ice(x: float, y: float) -> bool:
	return absf(x) < MwRinkShape.mesh_half_width(y)


## The atlas texel (row * SIZE + col) under rink point ([param x], [param y])
## of the ice, -1 off the ice's blocks. The far part maps 1:1 (UV0 = (x + 256,
## y + 461)); behind the near goal line the floor shows the far end's rows
## mirrored and each row scaled by k (UV0 = (x k + 256, 461 - y)).
static func ice_texel(x: float, y: float) -> int:
	var board_layout := layout()
	var col: int
	var row: int
	if y < board_layout["near_y"].x:
		col = int(floor(x + 256.0)) + board_layout["main_d"].x
		row = int(floor(y + 461.0)) + board_layout["main_d"].y
		if row < board_layout["main_rows"].x or row >= board_layout["main_rows"].y:
			return -1
	else:
		col = int(floor(x * near_k(y) + 256.0)) + board_layout["near_d"].x
		row = int(floor(461.0 - y)) + board_layout["near_d"].y
		if row < board_layout["near_rows"].x or row >= board_layout["near_rows"].y:
			return -1
	if col < board_layout["cols"].x or col >= board_layout["cols"].y:
		return -1
	return row * SIZE + col


## The near rows' horizontal scale at rink [param y] (the far end's corner
## over the near one's), between the layout's whole rows.
static func near_k(y: float) -> float:
	var board_layout := layout()
	var k: PackedFloat32Array = board_layout["near_k"]
	var t := clampf(y - board_layout["near_y"].x, 0.0, k.size() - 1.0)
	var i := mini(int(t), k.size() - 2)
	return lerpf(k[i], k[i + 1], t - i)


## The boards' arc length (s: 0 at the far end's centre, clockwise seen from
## above) of the point on them nearest to rink point [param point], and how far
## outside them [param point] is (negative: inside): Vector2(s, distance).
static func wall_s(point: Vector2) -> Vector2:
	var board_layout := layout()
	var loop: PackedVector2Array = board_layout["loop"]
	var cum: PackedFloat32Array = board_layout["cum"]
	var best := INF
	var arc_length := 0.0
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var ab := b - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var d := (a + ab * t).distance_to(point)
		if d < best:
			best = d
			arc_length = cum[i] + t * ab.length()
	return Vector2(arc_length, best if not on_ice(point.x, point.y) else -best)


## The point on the boards at arc length [param arc_length] (wrapped) and their
## outward normal there: [Vector2 point, Vector2 normal] (rink px).
static func boards_at(arc_length: float) -> Array:
	var board_layout := layout()
	var loop: PackedVector2Array = board_layout["loop"]
	var cum: PackedFloat32Array = board_layout["cum"]
	arc_length = wrapf(arc_length, 0.0, float(board_layout["total"]))
	var i := cum.bsearch(arc_length, true) - 1
	i = clampi(i, 0, loop.size() - 1)
	var a := loop[i]
	var b := loop[(i + 1) % loop.size()]
	var d := (b - a).normalized()
	var point := a + (b - a) * clampf((arc_length - cum[i]) / maxf(cum[i + 1] - cum[i], 1e-9), 0.0, 1.0)
	var n := Vector2(d.y, -d.x)
	if on_ice(point.x + n.x * 2.0, point.y + n.y * 2.0):
		n = -n
	return [point, n]


## The boards' top (z, rink px) at arc length [param arc_length]: the padding's, the
## glass's where there is some, the gate's low rail.
static func wall_top(arc_length: float) -> float:
	var board_layout := layout()
	var top: PackedFloat32Array = board_layout["top"]
	var i := clampi(int(round(wrapf(arc_length, 0.0, board_layout["total"]))), 0, top.size() - 1)
	return top[i]


# --- sprites ------------------------------------------------------------------------------

## The ROM frame at [param frame] as a mask: {w, h, ox, oy (the frame's point
## inside it), px (colour indices, 0 = none)}; cached for the run.
static func mask(frame: int) -> Dictionary:
	cache_lock.lock()
	if not _masks.has(frame):
		var m := {}
		if MwRom.available():
			var rom := MwRom.data()
			m = MwGfx.frame_image(rom, MwGfx.frame_pieces(rom, frame))
			var px: PackedByteArray = m["px"]
			for i in px.size():
				px[i] = px[i] & 15
			m["px"] = px
		_masks[frame] = m
	var out: Dictionary = _masks[frame]
	cache_lock.unlock()
	return out


## The side of ROM frame [param frame] its art cuts off straight, if any
## (owner: the splats with a flat edge go against the ice's rim):
## [side (CUT_BOTTOM ...), the cut's middle (mask px: on the edge of the
## opaque pixels' box), the cut's half length (px)], or [] for none. A side
## is cut when its outermost line of opaque pixels covers a quarter of it or
## more and the next two lines inward are no more than 1.3 times as wide (a
## straight cut, not a rounded end): the geyser `$20BD2`'s wall frames 0, 4
## and 5 at the bottom (columns rising from the floor line); cached.
static func cut_side(frame: int) -> Array:
	cache_lock.lock()
	if not _cuts.has(frame):
		_cuts[frame] = _find_cut(frame)
	var cut: Array = _cuts[frame]
	cache_lock.unlock()
	return cut


static func _find_cut(frame: int) -> Array:
	var out := []
	var m := mask(frame)
	if not m.is_empty():
		var w: int = m["w"]
		var h: int = m["h"]
		var px: PackedByteArray = m["px"]
		var lo := Vector2i(w, h)
		var hi := Vector2i(-1, -1)
		for y in h:
			for x in w:
				if px[y * w + x] != 0:
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		if hi.x >= 0:
			for side in [CUT_BOTTOM, CUT_TOP, CUT_LEFT, CUT_RIGHT]:
				var across: bool = side == CUT_BOTTOM or side == CUT_TOP
				var n: int = (hi.x - lo.x + 1) if across else (hi.y - lo.y + 1)
				var cover := []
				for k in 3:
					var line := 0
					for j in n:
						var x: int
						var y: int
						if across:
							x = lo.x + j
							y = hi.y - k if side == CUT_BOTTOM else lo.y + k
						else:
							y = lo.y + j
							x = lo.x + k if side == CUT_LEFT else hi.x - k
						if x >= 0 and y >= 0 and x < w and y < h and px[y * w + x] != 0:
							line += 1
					cover.append(line)
				if cover[0] * 4 >= n and maxi(cover[1], cover[2]) <= cover[0] * 1.3:
					var mid: Vector2
					match side:
						CUT_BOTTOM:
							mid = Vector2((lo.x + hi.x + 1) / 2.0, hi.y + 1)
						CUT_TOP:
							mid = Vector2((lo.x + hi.x + 1) / 2.0, lo.y)
						CUT_LEFT:
							mid = Vector2(lo.x, (lo.y + hi.y + 1) / 2.0)
						_:
							mid = Vector2(hi.x + 1, (lo.y + hi.y + 1) / 2.0)
					out = [side, mid, n / 2.0]
					break
	return out


## Where a splat of [param frame] goes so that its cut side ([method
## cut_side]) lies against the boards at arc length [param arc_length], [param out]
## px beyond them (>= 0: the cut on the rim or under the boards, never on
## the ice), mirrored with [param flip], [param scale] as [method
## ice_stamp]: [Vector2 point, angle] for [method ice_stamp]; [] for a
## frame without a cut.
static func against_rim(frame: int, arc_length: float, out: float, scale: float, flip: bool) -> Array:
	var cut := cut_side(frame)
	if cut.is_empty():
		return []
	var m := mask(frame)
	var at := boards_at(arc_length)
	var b: Vector2 = at[0]
	var normal: Vector2 = at[1]
	var fs := -1.0 if flip else 1.0
	# the cut side's outward direction in frame px (x right, y down)
	var dir: Vector2 = [Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)][int(cut[0])]
	# at angle 0 (top east) a frame vector (dx, dy) lies along (-dy, dx fs);
	# turned so the cut faces out of the rink
	var v0 := Vector2(-dir.y, dir.x * fs)
	var angle := normal.angle() - v0.angle()
	var up := Vector2(cos(angle), sin(angle))
	var right := Vector2(-up.y, up.x)
	var mid: Vector2 = cut[1]
	var off := right * (mid.x - float(m["ox"])) * fs * scale - up * (mid.y - float(m["oy"])) * scale
	return [b + normal * out - off, angle]


# --- operations -------------------------------------------------------------------------

## A splat of ROM frame [param frame] laid flat on the ice, its point at rink
## ([param x], [param y]), its top towards [param angle] (radians, 0 = east,
## PI/2 = south), [param scale] rink px a sprite pixel (1 = 1:1, 0.5 = half
## size), mirrored with [param flip]; [param layer] PAINT ([param kind] blood
## or oil) or DETAIL ([param kind] DARK or LIGHT).
func ice_stamp(kind: int, frame: int, x: float, y: float, angle: float, scale: float, flip: bool,
		layer := PAINT) -> void:
	add(PackedFloat32Array([OP_ICE, kind, frame, x, y, angle, scale, 1.0 if flip else 0.0, layer]))


## The skates' scratches of one pass (owner: the skates add to the light bit,
## mostly where they turn, dithered when slow):
## [param marks] holds, per foot, [x0, y0, x1, y1, density (0-1), dither
## (1: only every other texel, checkered), seed]; each texel on a mark's way
## turns LIGHT where its hash with the seed falls under the density.
func skates(marks: PackedFloat32Array) -> void:
	if marks.is_empty():
		return
	var op := PackedFloat32Array([OP_SKATES])
	op.append_array(marks)
	add(op)


## A splat of ROM frame [param frame] upright on the boards at arc length
## [param arc_length], its bottom row on the boards' foot (z 0), [param scale] as
## [method ice_stamp], mirrored with [param flip].
func wall_stamp(kind: int, frame: int, arc_length: float, scale: float, flip: bool) -> void:
	add(PackedFloat32Array([OP_WALL, kind, frame, arc_length, scale, 1.0 if flip else 0.0]))


## A pool: a blob of radius [param r] (rink px, its edge from [param shape])
## around ([param x], [param y]) on the ice.
func pool(kind: int, x: float, y: float, r: float, shape: int) -> void:
	add(PackedFloat32Array([OP_POOL, kind, x, y, r, shape]))


## A skate's mark from [param from] to [param to] (rink px, sub-pixel) for
## one foot carrying [param paint_load] texels of [param kind] (dotted when
## [param phase] says so; [param wet] painted texels in a row so far): a
## run of [constant STREAK_WET] texels holding paint refills the load with
## their kind, each texel without paint takes one from the load. Only kept as
## an operation when it painted. Returns [load, kind, phase, wet] after it.
func streak(kind: int, paint_load: int, phase: int, wet: int, from: Vector2, to: Vector2) -> PackedInt32Array:
	var op := PackedFloat32Array([OP_STREAK, kind, paint_load, phase, wet, from.x, from.y, to.x, to.y])
	var r := _streak(op, false)
	if r[4] > 0:
		add(op)
	return PackedInt32Array([r[0], r[1], r[2], r[3]])


## Keeps operation [param op] and, when the texels show every operation so
## far, applies it.
func add(op: PackedFloat32Array) -> void:
	_starts.append(_log.size())
	_log.append_array(op)
	if _applied == _starts.size() - 1:
		_work += _apply(_starts.size() - 1)
		_applied += 1
		_checkpoint_maybe()
		_copy_maybe()


## The number of operations kept.
func count() -> int:
	return _starts.size()


## Operation [param i]'s numbers (as [method add] took them).
func operation(i: int) -> PackedFloat32Array:
	var end := _log.size() if i + 1 >= _starts.size() else _starts[i + 1]
	return _log.slice(_starts[i], end)


## Keeps operation [param op] made by another atlas ([member follows]),
## without applying it: a seek shows it.
func append(op: PackedFloat32Array) -> void:
	_starts.append(_log.size())
	_log.append_array(op)


## The checkpoints made so far from the [param from]th on ([[operations,
## compressed texels], ...]; the first, at 0, is every atlas's own).
func checkpoints_from(from: int) -> Array:
	return _checkpoints.slice(from)


## Keeps another atlas's checkpoint [param checkpoint] ([method
## checkpoints_from]; its operations [method append]ed first).
func take_checkpoint(checkpoint: Array) -> void:
	_checkpoints.append(checkpoint)


## The texels after the first [param n] operations (a replay's frame shows
## the paint as it was): forwards by applying the ones between, backwards from
## the last copy before [param n] ([method seek_toward] without a limit).
func seek(n: int) -> void:
	seek_toward(n, -1)


## Toward the texels after the first [param n] operations, applying
## operations until [param budget] texels have been looked at (-1: no limit)
## or [param more] says no (asked before each one after the first; the 3D
## view's share of a rendered frame's time) - at least one operation a call:
## from where the texels are, or - back, or far ahead - from the last copy
## (plain, else a checkpoint) before [param n]. Returns the texels looked
## at; [method shown] says how far they got.
func seek_toward(n: int, budget: int, more := Callable()) -> int:
	n = clampi(n, 0, _starts.size())
	if n == _applied:
		return 0
	var best: Array = _checkpoints[0]
	for c: Array in _checkpoints:
		if int(c[0]) <= n:
			best = c
	var copy: Array = []
	for c: Array in _copies:
		if int(c[0]) <= n:
			copy = c
	var plain := not copy.is_empty() and int(copy[0]) >= int(best[0])
	if plain:
		best = copy
	if n < _applied or int(best[0]) > _applied:     # back, or far ahead: from the copy
		var raw: PackedByteArray = best[1]
		if plain:
			data = raw.duplicate()
		elif raw.is_empty():
			data.fill(0)
		else:
			data = raw.decompress(SIZE * SIZE, FileAccess.COMPRESSION_ZSTD)
		_applied = int(best[0])
		_dirty = true
	var work := 0
	var first := true
	while _applied < n and (budget < 0 or work < budget) and (first or not more.is_valid() or more.call()):
		first = false
		work += _apply(_applied)
		_applied += 1
		_copy_maybe()
	return work


## The operations the texels show now ([method seek_toward] may still be on its way).
func shown() -> int:
	return _applied


## The texture the shaders read (made on first use), brought up to date.
func texture() -> ImageTexture:
	flush()
	return _texture


## Uploads the texels if they changed (at most once a rendered frame).
func flush() -> void:
	if not _dirty and _texture != null:
		return
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_R8, data)
	if _texture == null:
		_texture = ImageTexture.create_from_image(img)
	else:
		_texture.update(img)
	_dirty = false


## A digest of the texels (tests).
func digest() -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA1)
	h.update(data)
	return h.finish().hex_encode()


## Keeps a plain copy of the texels when they show a multiple of
## [constant COPY_STEP] operations, none kept for it yet; past
## [constant COPY_KEEP] the copy farthest from them goes.
func _copy_maybe() -> void:
	if not copies or _applied % COPY_STEP != 0:
		return
	var at := _copies.size()
	for i in _copies.size():
		var ops := int(_copies[i][0])
		if ops == _applied:
			return
		if ops > _applied:
			at = i
			break
	_copies.insert(at, [_applied, data.duplicate()])
	if _copies.size() > COPY_KEEP:
		var far := 0
		for i in _copies.size():
			if absi(int(_copies[i][0]) - _applied) > absi(int(_copies[far][0]) - _applied):
				far = i
		_copies.remove_at(far)


func _checkpoint_maybe() -> void:
	var last: int = _checkpoints[-1][0]
	if _applied != _starts.size():
		return
	if _applied - last >= CHECKPOINT_OPS or _work >= CHECKPOINT_WORK:
		_checkpoints.append([_applied, data.compress(FileAccess.COMPRESSION_ZSTD)])
		_work = 0


## Applies operation [param i]; returns the texels it looked at.
func _apply(i: int) -> int:
	var end := _log.size() if i + 1 >= _starts.size() else _starts[i + 1]
	var op := _log.slice(_starts[i], end)
	_dirty = true
	match int(op[0]):
		OP_ICE:
			return _ice(op)
		OP_WALL:
			return _wall(op)
		OP_STREAK:
			return _streak(op, true)[4]
		OP_POOL:
			return _pool(op)
		OP_SKATES:
			return _skates(op)
	return 0


## OP_ICE: [_, kind, frame, x, y, angle, scale, flip, layer].
func _ice(op: PackedFloat32Array) -> int:
	var m := mask(int(op[2]))
	if m.is_empty():
		return 0
	var kind := int(op[1])
	var c := Vector2(op[3], op[4])
	var up := Vector2(cos(op[5]), sin(op[5]))       # the sprite's top
	var right := Vector2(-up.y, up.x)               # its right (top north -> right east)
	var sc: float = op[6]
	var flip := op[7] > 0.5
	if op.size() > 8 and int(op[8]) == DETAIL:
		kind = (kind << 2) | 0x100          # the detail's field (0x100: its marker below)
	var w: int = m["w"]
	var h: int = m["h"]
	var ox: int = m["ox"]
	var oy: int = m["oy"]
	# the footprint's corners in rink px
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for corner in [Vector2(0, 0), Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
		var sx: float = (corner.x - ox) * (-1.0 if flip else 1.0) * sc
		var sy: float = (corner.y - oy) * sc
		var point := c + right * sx - up * sy
		lo = Vector2(minf(lo.x, point.x), minf(lo.y, point.y))
		hi = Vector2(maxf(hi.x, point.x), maxf(hi.y, point.y))
	# each atlas row of the ice under the footprint: the columns whose centres
	# map into the frame (an interval: the frame is a rectangle), then the
	# frame's pixel at each, stepping along the row
	var board_layout := layout()
	var fs := -1.0 if flip else 1.0
	var work := 0
	var md: Vector2i = board_layout["main_d"]
	var mr: Vector2i = board_layout["main_rows"]
	var cols: Vector2i = board_layout["cols"]
	var r0 := maxi(mr.x, int(floor(lo.y + 461.0)) + md.y - 1)
	var r1 := mini(mr.y - 1, int(floor(hi.y + 461.0)) + md.y + 1)
	for row in range(r0, r1 + 1):
		var y := row - md.y - 461.0 + 0.5
		work += _ice_row(row, y, -md.x - 256.0 + 0.5, 1.0, cols, c, up, right, sc, fs, m, kind)
	if hi.y >= board_layout["near_y"].x - 1.0:
		var nd: Vector2i = board_layout["near_d"]
		var nr: Vector2i = board_layout["near_rows"]
		var q0 := maxi(nr.x, int(floor(461.0 - hi.y)) + nd.y - 1)
		var q1 := mini(nr.y - 1, int(floor(461.0 - lo.y)) + nd.y + 1)
		for row in range(q0, q1 + 1):
			var y := 461.0 - (row - nd.y + 0.5)
			var k := near_k(y)
			work += _ice_row(row, y, (-nd.x + 0.5 - 256.0) / k, 1.0 / k, cols, c, up, right, sc, fs, m, kind)
	return work


## One atlas row of an ice splat: texel centres at x = [param xa] + [param xb]
## col on rink row [param y]; the frame [param m] laid with its point at
## [param c], its top along [param up]. Returns the texels looked at.
func _ice_row(row: int, y: float, xa: float, xb: float, cols: Vector2i, c: Vector2, up: Vector2, right: Vector2,
		sc: float, fs: float, m: Dictionary, kind: int) -> int:
	var w: int = m["w"]
	var h: int = m["h"]
	var px: PackedByteArray = m["px"]
	var vy := y - c.y
	# the frame's x and y (with its point) along the row: a + b t, t = x - c.x
	var a1 := fs * vy * right.y / sc + float(m["ox"])
	var b1 := fs * right.x / sc
	var a2 := -vy * up.y / sc + float(m["oy"])
	var b2 := -up.x / sc
	var t_lo := -INF
	var t_hi := INF
	for e in [[a1, b1, float(w)], [a2, b2, float(h)]]:
		var a: float = e[0]
		var b: float = e[1]
		if absf(b) < 1e-9:
			if a < 0.0 or a >= float(e[2]):
				return 0
			continue
		var t_zero := (0.0 - a) / b
		var t_end := (float(e[2]) - a) / b
		t_lo = maxf(t_lo, minf(t_zero, t_end))
		t_hi = minf(t_hi, maxf(t_zero, t_end))
	if t_hi < t_lo:
		return 0
	var c0 := maxi(cols.x, int(ceil((c.x + t_lo - xa) / xb)) - 1)
	var c1 := mini(cols.y - 1, int(floor((c.x + t_hi - xa) / xb)) + 1)
	var keep := PAINT_BITS if (kind & 0x100) != 0 else DETAIL_BITS     # the other field stays
	var value := kind & 0xFF
	var n := 0
	for col in range(c0, c1 + 1):
		var t := xa + xb * col - c.x
		var ix := int(floor(a1 + b1 * t))
		var iy := int(floor(a2 + b2 * t))
		n += 1
		if ix >= 0 and iy >= 0 and ix < w and iy < h and px[iy * w + ix] != 0:
			var i := row * SIZE + col
			data[i] = (data[i] & keep) | value
	return n


## The ice's atlas texels whose centres on the ice lie within [param lo]..
## [param hi] (rink px, a texel's reach added): [texels (row * SIZE + col),
## their centres]. The far part's centres are rink px centres; behind the near
## goal line each texel's centre comes through its row's scale (the floor
## shows the far end's rows there, mirrored and scaled), so a splat there is
## on that grid too.
static func ice_cells(lo: Vector2, hi: Vector2) -> Array:
	var board_layout := layout()
	var indices := PackedInt32Array()
	var xy := PackedVector2Array()
	var md: Vector2i = board_layout["main_d"]
	var mr: Vector2i = board_layout["main_rows"]
	var cols: Vector2i = board_layout["cols"]
	var r0 := maxi(mr.x, int(floor(lo.y + 461.0)) + md.y - 1)
	var r1 := mini(mr.y - 1, int(floor(hi.y + 461.0)) + md.y + 1)
	var c0 := maxi(cols.x, int(floor(lo.x + 256.0)) + md.x - 1)
	var c1 := mini(cols.y - 1, int(floor(hi.x + 256.0)) + md.x + 1)
	for row in range(r0, r1 + 1):
		var y := row - md.y - 461.0 + 0.5
		for col in range(c0, c1 + 1):
			indices.append(row * SIZE + col)
			xy.append(Vector2(col - md.x - 256.0 + 0.5, y))
	if hi.y >= board_layout["near_y"].x - 1.0:
		var nd: Vector2i = board_layout["near_d"]
		var nr: Vector2i = board_layout["near_rows"]
		var q0 := maxi(nr.x, int(floor(461.0 - hi.y)) + nd.y - 1)
		var q1 := mini(nr.y - 1, int(floor(461.0 - lo.y)) + nd.y + 1)
		for row in range(q0, q1 + 1):
			var y := 461.0 - (row - nd.y + 0.5)
			var k := near_k(y)
			for col in range(cols.x, cols.y):
				var x := (col - nd.x + 0.5 - 256.0) / k
				if x >= lo.x - 1.0 and x <= hi.x + 1.0:
					indices.append(row * SIZE + col)
					xy.append(Vector2(x, y))
	return [indices, xy]


## OP_WALL: [_, kind, frame, s, scale, flip]: the frame upright, its bottom
## row on the boards' foot, its point at arc length s.
func _wall(op: PackedFloat32Array) -> int:
	var m := mask(int(op[2]))
	if m.is_empty():
		return 0
	var kind := int(op[1])
	var sc: float = op[4]
	var flip := op[5] > 0.5
	var w: int = m["w"]
	var h: int = m["h"]
	var ox: int = m["ox"]
	var oy: int = m["oy"]
	var px: PackedByteArray = m["px"]
	var board_layout := layout()
	var total: float = board_layout["total"]
	var reach := (maxi(ox, w - ox) + 1) * sc
	var work := 0
	for r: Array in board_layout["runs"]:
		var rs0 := minf(float(r[7]), float(r[8]))
		var rs1 := maxf(float(r[7]), float(r[8]))
		for shift in [-total, 0.0, total]:          # the loop joins at the far centre
			var sc_s: float = op[3] + shift
			if rs1 < sc_s - reach - 2.0 or rs0 > sc_s + reach + 2.0:
				continue
			var ax: int = r[1]
			var ay: int = r[2]
			var rw: int = r[3]
			var rh: int = r[4]
			var dx: int = r[5]
			var dy: int = r[6]
			var ds_du := (float(r[8]) - float(r[7])) / (float(r[10]) - float(r[9]))
			var dz_dv := (float(r[12]) - float(r[11])) / (float(r[14]) - float(r[13]))
			for col in range(ax, ax + rw):
				var arc_length := float(r[7]) + (col - dx + 0.5 - float(r[9])) * ds_du
				var sx := (arc_length - sc_s) / sc
				if flip:
					sx = -sx
				var ix := int(floor(sx + ox))
				if ix < 0 or ix >= w:
					continue
				for row in range(ay, ay + rh):
					var z := float(r[11]) + (row - dy + 0.5 - float(r[13])) * dz_dv
					var iy := oy - 1 - int(floor(z / sc))
					work += 1
					if iy >= 0 and iy < h and z >= 0.0 and px[iy * w + ix] != 0:
						var i := row * SIZE + col
						data[i] = (data[i] & DETAIL_BITS) | kind
	return work


## OP_POOL: [_, kind, x, y, r, shape]: a blob, its edge wobbling (three
## waves round it from its shape) by up to a fifth of the radius.
func _pool(op: PackedFloat32Array) -> int:
	var kind := int(op[1])
	var c := Vector2(op[2], op[3])
	var r: float = op[4]
	var shape := int(op[5])
	var ph := [float(shape & 0xFF) / 40.7, float((shape >> 8) & 0xFF) / 40.7, float((shape >> 16) & 0xFF) / 40.7]
	var reach := r * 1.25 + 1.0
	var cells := ice_cells(c - Vector2(reach, reach), c + Vector2(reach, reach))
	var indices: PackedInt32Array = cells[0]
	var xy: PackedVector2Array = cells[1]
	for n in indices.size():
		var v := xy[n] - c
		var a := v.angle()
		var edge := r * (1.0 + 0.1 * sin(2.0 * a + ph[0]) + 0.06 * sin(3.0 * a + ph[1]) + 0.04 * sin(5.0 * a + ph[2]))
		if v.length() <= edge:
			data[indices[n]] = (data[indices[n]] & DETAIL_BITS) | kind
	return indices.size()


## OP_STREAK: [_, kind, load, phase, wet, x0, y0, x1, y1] - see [method
## streak]; [param paint] false only works it out. Returns [load, kind,
## phase, wet, texels painted] (texels painted: 0 when nothing would change).
func _streak(op: PackedFloat32Array, paint: bool) -> PackedInt32Array:
	var kind := int(op[1])
	var paint_load := int(op[2])
	var phase := int(op[3])
	var wet := int(op[4])
	var a := Vector2(op[5], op[6])
	var b := Vector2(op[7], op[8])
	var d := b - a
	var painted := 0
	# one sample per whole step along the longer axis, at the half-way lines
	# crossed in (a, b]: consecutive marks join without a gap or a double
	var major := 0 if absf(d.x) >= absf(d.y) else 1
	var m0: float = a[major]
	var m1: float = b[major]
	if absf(m1 - m0) < 1e-6:
		return PackedInt32Array([paint_load, kind, phase, wet, 0])
	var step := 1.0 if m1 > m0 else -1.0
	var m: float = floorf(m0 - 0.5) + 1.5 if step > 0.0 else ceilf(m0 - 0.5) - 0.5
	var n := 0
	while (step > 0.0 and m <= m1) or (step < 0.0 and m >= m1):
		var t := (m - m0) / (m1 - m0)
		var point := a + d * t
		m += step
		n += 1
		if n > 512:
			break
		if not on_ice(point.x, point.y):
			continue
		var i := ice_texel(point.x, point.y)
		if i < 0:
			continue
		var here := data[i] & PAINT_BITS
		if here != CLEAR:
			wet += 1
			if wet >= STREAK_WET:
				paint_load = STREAK_LOAD
				kind = here
			continue
		wet = 0
		if paint_load <= 0:
			continue
		paint_load -= 1
		phase += 1
		if paint_load >= STREAK_LOAD / 3 or phase % 2 == 0:     # the last third broken
			painted += 1
			if paint:
				data[i] = (data[i] & DETAIL_BITS) | kind
	return PackedInt32Array([paint_load, kind, phase, wet, painted])


## OP_SKATES: [_, then per mark x0, y0, x1, y1, density, dither, seed] - see
## [method skates]. The texels on a mark's way as a streak's (one per whole
## step along the longer axis, (a, b] joined without gaps); each decided by
## its own hash, so the same operation always marks the same texels.
func _skates(op: PackedFloat32Array) -> int:
	var work := 0
	for k in range(1, op.size() - 6, 7):
		var a := Vector2(op[k], op[k + 1])
		var b := Vector2(op[k + 2], op[k + 3])
		var density: float = op[k + 4]
		var dither := op[k + 5] > 0.5
		var op_seed := int(op[k + 6])
		var d := b - a
		var major := 0 if absf(d.x) >= absf(d.y) else 1
		var m0: float = a[major]
		var m1: float = b[major]
		if absf(m1 - m0) < 1e-6:
			continue
		var step := 1.0 if m1 > m0 else -1.0
		var m: float = floorf(m0 - 0.5) + 1.5 if step > 0.0 else ceilf(m0 - 0.5) - 0.5
		var n := 0
		while (step > 0.0 and m <= m1) or (step < 0.0 and m >= m1):
			var point := a + d * ((m - m0) / (m1 - m0))
			m += step
			n += 1
			if n > 64:
				break
			work += 1
			var i := ice_texel(point.x, point.y)
			if i < 0 or not on_ice(point.x, point.y):
				continue
			if dither and ((i % SIZE) + (i / SIZE)) % 2 == 1:
				continue
			if float((_hash(i, op_seed) >> 8) & 0xFFFF) / 65536.0 < density:
				data[i] = (data[i] & PAINT_BITS) | (LIGHT << 2)
	return work


## A texel's hash with [param seed_] (32 bits; "lowbias32", well mixed).
static func _hash(i: int, seed_: int) -> int:
	var h := (i * 0x9E3779B1 + seed_ * 0x85EBCA6B) & 0xFFFFFFFF
	h ^= h >> 16
	h = (h * 0x7FEB352D) & 0xFFFFFFFF
	h ^= h >> 15
	h = (h * 0x846CA68B) & 0xFFFFFFFF
	h ^= h >> 16
	return h
