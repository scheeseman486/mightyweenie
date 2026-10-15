class_name MwSplatterReplay
extends RefCounted
## The arena's paint in a recorded match's playback (plan 37, docs/rink3d.md,
## Splatter; owner: the recordings' playbacks had shown none of the new
## blood, oil and ice detail, which should be made again procedurally from a
## seed). A recording keeps no texels: its store has the paint's seed
## ([member MwFullReplay.splat_seed]) and each 3D frame the inputs of the
## passes since the frame before ("splat" "in", MwSplatter.inputs). This
## makes the paint again - [code]MwSplatter.new(seed)[/code] and the frames'
## inputs applied in order, as far as the frame shown - and gives each frame
## its paint as it was ([method dress]: the atlas, seeked by the view to the
## operations it had then; back and forth alike). The same seed and inputs
## give the same operations, so the same texels as the match.
##
## The match's own replay while it goes on (screen 7's FULL GAME replay of
## the rink's state) shows the match's atlas itself: its frames' operation
## counts are that atlas's.
##
## An older file (plan 34's, before the seed was kept): no seed and no
## inputs - the seed is derived ([method derived_seed]: the crowd's, which
## those builds painted from), so the ice's detail is the match's, and there
## is no blood ([member derived]; MwReplayFile.open says so).
##
## **Made on a worker thread** (owner, 2026-10-15: replays still juddered and
## ran slow; [method of], the playbacks'): making a frame's paint takes
## ~0.6 ms on the desktop - a fast forward's 32 frames a tick were ~20 ms of
## every 16.7 ms tick, and the ticks piled up behind them. A
## [MwSplatterReplay.Maker] makes the frames' paint in order from the start
## on a worker thread, with its own MwSplatter and atlas and its own reader
## of the frames, and hands each frame's operations, its checkpoints and the
## frame's operation count over; the frames shown take them ([method dress])
## into an atlas of their own that [member MwSplatterAtlas.follows] (the 3D
## view seeks it a share at a time). A frame the maker has not reached yet
## shows the paint as far as it has made it (a fast forward ahead of it: it
## makes ~1600 frames a second, a fast forward shows 1920 at the most; the
## first frames, until it has made them) and then its own: the frame's
## "ops_made" asks for its count as it is made (the view, each rendered
## frame - a replay paused there too). Nothing waits for it but
## [method finish] (tests); [method stop] ends it (the playback dropped, the
## screen left).

## The recording played.
var store: MwFullReplay
## The match's own paint (its live replay), else null.
var live: MwSplatter = null
## The paint made again (a recording of a match that is over) on this
## thread, else null.
var splat: MwSplatter = null
## The seed it paints from.
@warning_ignore("shadowed_global_identifier")   # a frozen name (docs/style.md N9): read by name elsewhere
var seed := 0
## True when the recording kept no seed (an older file): [member seed] is
## [method derived_seed]'s.
var derived := false
var _done := 0                       # frames whose inputs are applied
var _ops := PackedInt32Array()       # the operations after each of them
var _maker: Maker = null             # the paint made on a worker thread, else null
var _shown: MwSplatterAtlas = null   # its frames' atlas, fed by it
var _thread: Thread = null           # its thread (null: none, or waited for)


## Makes a recording's paint on a worker thread ([method run]): the frames'
## inputs in order into its own MwSplatter, each frame's new operations,
## the atlas's new checkpoints and its operation count handed over under
## [member lock] ([method take]).
class Maker:
	extends RefCounted
	var reader: MwFullReplay
	@warning_ignore("shadowed_global_identifier")   # as MwSplatter's
	var seed := 0
	var lock := Mutex.new()
	var _stop := false
	var _finished := false
	var _ops: Array[PackedFloat32Array] = []
	var _checkpoints: Array = []
	var _counts := PackedInt32Array()

	func _init(reader_: MwFullReplay, seed_: int) -> void:
		reader = reader_
		seed = seed_

	## The worker thread's task: every frame, or until [method stop_soon].
	func run() -> void:
		var made := MwSplatter.new(seed)
		var atlas := made.atlas
		atlas.copies = false                      # (it never seeks)
		var sent := 0
		var checks := 1                           # (both atlases start with the one at 0)
		for i in reader.size():
			lock.lock()
			var stopping := _stop
			lock.unlock()
			if stopping:
				break
			var sp: Variant = reader.side(i).get("splat")
			if sp is Dictionary:
				for rec: Variant in (sp as Dictionary).get("in", []):
					if rec is PackedInt32Array:
						made.apply(rec)
			var n := atlas.count()
			var ops: Array[PackedFloat32Array] = []
			for k in range(sent, n):
				ops.append(atlas.operation(k))
			sent = n
			var new_checks := atlas.checkpoints_from(checks)
			checks += new_checks.size()
			lock.lock()
			_ops.append_array(ops)
			_checkpoints.append_array(new_checks)
			_counts.append(n)
			lock.unlock()
		lock.lock()
		_finished = true
		lock.unlock()

	## Asks [method run] to end after the frame it is on.
	func stop_soon() -> void:
		lock.lock()
		_stop = true
		lock.unlock()

	## What was made since the last call: [operations, checkpoints, each
	## frame's operation count, whether it is done (every frame, or stopped)].
	func take() -> Array:
		lock.lock()
		var out := [_ops, _checkpoints, _counts, _finished]
		_ops = []
		_checkpoints = []
		_counts = PackedInt32Array()
		lock.unlock()
		return out


## The paint of [param store]'s frames: [param live_]'s (the match going
## on) or made again from the store's seed - on a worker thread with
## [param background] (see the class description), else here as the frames
## are shown.
func _init(store_: MwFullReplay, live_: MwSplatter = null, background := false) -> void:
	store = store_
	if live_ != null:
		live = live_
		seed = live_.seed
		return
	seed = store.splat_seed
	if seed < 0:
		seed = derived_seed(store)
		derived = true
	if not background:
		splat = MwSplatter.new(seed)
		return
	MwSplatterAtlas.layout()                     # read here once: the thread only reads it
	_shown = MwSplatterAtlas.new()
	_shown.follows = true
	_maker = Maker.new(store.reader(), seed)
	_thread = Thread.new()                       # (its own: seconds long, it would hold a pool's thread)
	_thread.start(_maker.run, Thread.PRIORITY_LOW)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _thread != null:
		_maker.stop_soon()                       # ([method stop]; no method of its own is called now)
		_thread.wait_to_finish()


## The paint for playing [param recording] of [param state]'s match: the
## match's own when it is the rink's recording with its paint, else made
## again (on a worker thread: the playbacks'); null when the replays show
## none ([method shown]).
static func of(state: MwRinkState, recording: MwFullReplay) -> MwSplatterReplay:
	if not shown() or recording == null:
		return null
	if state != null and state.splatter != null and state.full_replay == recording:
		return MwSplatterReplay.new(recording, state.splatter)
	return MwSplatterReplay.new(recording, null, true)


## Whether the replays show the arena's paint: the paint's model on
## (MwSettings.splatter) and GAMEPLAY MODIFIERS' REPLAY BLOOD
## (MwSettings.replay_paint; owner, 2026-10-15: off by default).
static func shown() -> bool:
	return MwSettings.splatter and MwSettings.replay_paint


## Waits until the worker thread has made every frame's paint, and takes it
## (made on this thread: nothing to wait for).
func finish() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if _maker != null:
		_take()


## Ends the worker thread's making (after the frame it is on) and waits for
## it; what it made stays. Safe to call again.
func stop() -> void:
	if _thread == null:
		return
	_maker.stop_soon()
	_thread.wait_to_finish()
	_thread = null


## The frames whose paint is made (on the worker thread: those taken so far).
func made() -> int:
	return _done


## Whether the worker thread is still making the paint.
func making() -> bool:
	return _thread != null and _thread.is_alive()


## A seed for a recording that kept none (an older file): the crowd's seed of
## its first 3D frame (MwCrowdLife.snapshot "seed": the builds before kept
## the paint's seed equal to it), else one from its first frame's bytes (the
## engine's hash() of them as it has always been, MwSeed: plan 40, B5).
static func derived_seed(recording: MwFullReplay) -> int:
	for i in mini(recording.size(), 8):
		var crowd: Variant = recording.side(i).get("crowd")
		if crowd is Dictionary and (crowd as Dictionary).has("seed"):
			return int(crowd["seed"])
	if recording.size() > 0:
		return MwSeed.engine_hash_bytes(recording.frames[0]) & 0x7FFFFFFF
	return 1


## Whether [param recording]'s 3D frames carry the paint (its first frames
## looked at: a match played with the paint off has none).
static func painted(recording: MwFullReplay) -> bool:
	if recording.splat_seed >= 0:
		return true
	for i in mini(recording.size(), 8):
		if recording.side(i).has("splat"):
			return true
	return false


## Frame [param i]'s 3D frame [param f] (MwFullReplay.side) with its paint:
## its "splat" given the atlas and the operations it had at that frame
## (MwRinkView3D.present_frame seeks to them). Returns [param f].
func dress(f: Dictionary, i: int) -> Dictionary:
	var sp: Variant = f.get("splat")
	if not sp is Dictionary:
		return f
	var d := (sp as Dictionary).duplicate()
	if live != null:
		d["atlas"] = live.atlas                 # (its "ops" are that atlas's)
	elif _maker != null:
		d["atlas"] = _shown                      # (as far as the worker thread has made it ...
		d["ops"] = ops_at(i)
		d["ops_made"] = ops_at.bind(i)           # ... and as it makes it)
	else:
		run_to(i, f)
		d["atlas"] = splat.atlas
		d["ops"] = ops_at(i)
	f["splat"] = d
	return f


## Applies the frames' inputs up to frame [param i] (inclusive) if not yet
## ([param f]: frame [param i]'s 3D frame, already read); made on the
## worker thread, takes what it has made.
func run_to(i: int, f := {}) -> void:
	if _maker != null:
		_take()                                  # (made on the worker thread: what it has)
		return
	i = mini(i, store.size() - 1)
	while _done <= i:
		var side := f if _done == i and not f.is_empty() else store.side(_done)
		var sp: Variant = side.get("splat")
		if sp is Dictionary:
			for rec: Variant in (sp as Dictionary).get("in", []):
				if rec is PackedInt32Array:
					splat.apply(rec)
		_ops.append(splat.atlas.count())
		_done += 1


## The operations the paint had at frame [param i] (applied as far as it).
func ops_at(i: int) -> int:
	if live != null:
		var sp: Variant = store.side(i).get("splat")
		return int((sp as Dictionary).get("ops", 0)) if sp is Dictionary else 0
	run_to(i)
	return _ops[clampi(i, 0, _ops.size() - 1)] if not _ops.is_empty() else 0


## The atlas painted (the match's own, or the one made again).
func atlas() -> MwSplatterAtlas:
	if live != null:
		return live.atlas
	return _shown if _maker != null else splat.atlas


## The worker thread's frames made since the last call into the shown
## atlas and the operation counts.
func _take() -> void:
	var got := _maker.take()
	for op: PackedFloat32Array in got[0]:
		_shown.append(op)
	for c: Array in got[1]:
		_shown.take_checkpoint(c)
	_ops.append_array(got[2])
	_done = _ops.size()
