extends SceneTree
## Visual check of the screens between plays (plan 11 item 6): a visit of
## the original recorded in GPGX (`mw_harness.visual_rec`) replayed
## through our screen's scene; what the scene shows after each pass is saved
## for a pixel comparison with the original's frames at Genesis colour
## levels (`mw_harness.visual_cmp`; docs/compare.md, Screen visual check).
##
## The recording: per emulator frame of the visit (the frame before the
## screen's entry first) the RAM `$FFB050`-`$FFCA61` (an [MwRinkRam] image)
## and `$FFE000`-`$FFFFFF` (the sound driver's channels, the stack page with
## the handlers' locals), the tick, the screen id, the PC and the long on
## the stack (in a wait: its caller), the pads given, the CRAM; the whole
## RAM of the first frame.
## * Entry: the first frame's RAM decoded into an [MwRinkState] (as
##   `test/sim/screen_check.gd` does with the RAM at the screen's call; the
##   replay ring from `$FF0000`; the stats' second stream and scratch through
##   the sim's `enter_ram`), handed to the scene in a session
##   (`session.screens["rink"]`, the setup bytes) and entered
##   ([method MwBetweenPlays._enter_screen]).
## * Passes ([method loop_rule]): most loops stamp the tick into a local at
##   each pass boundary - each change of that long is a pass, elapsed = the
##   difference (the set-up's own stamp comes first; a value that is no
##   recent tick is the local's old contents); the loops synced to VBlank by
##   `dma_queue_wait` (8, 10 with two pads) have a boundary at each VBlank
##   that ends their wait, elapsed = the tick difference. A pass gets the
##   pads its `read_joypads` read (in its boundary's frame; 12-17 read them
##   at the end of the pass: the next boundary's frame) and runs as the
##   scene runs it (the sim's step, [method MwBetweenPlays._draw_pass])
##   without the router's fades. A first run of the sim alone finds the
##   passes that switch loops (8 / 9, the fight's card): their next boundary
##   is the new loop's.
## * The sims' questions outside the CPU are answered from the recording
##   ([Hooks]): the ticks a read sees, the sound driver's "still playing?"
##   (`$13D9C`'s channel tables, our handles mapped to the driver's as they
##   appear), the longs a CPU-bound pass stores; the stats' starfield is set
##   to the original's where it differs - after set-ups and 8 / 9 switches,
##   whose length in VBlanks differs between emulators ([method _resync]).
## * After each pass the sim's [method MwScreenSim.compare] and the main
##   random stream are checked against the frame where the pass ended (a
##   diagnostic: "exact" when that frame ended inside a wait, otherwise it
##   holds the start of the next pass too).
## Writes OUT/pNNNN.png (pass 0 = the set-up) and OUT/passes.json: per pass
## its boundary frame, the next boundary's, the frames that show it
## ("shows", "window"), elapsed, the pads, the differences, the exit.
##
##   source tools/bin/_common.sh; bin="$MW_CACHE/godot-headless-$GODOT_VERSION/godot"
##   xvfb-run -a -s "-screen 0 1280x1024x24" $bin --path game \
##       --rendering-driver opengl3 --rendering-method gl_compatibility --audio-driver Dummy \
##       -s res://test/screens/visual_check.gd -- REC_DIR OUT_DIR [--max N] [--dump PASS,..]
## (REC_DIR / OUT_DIR absolute or relative to the repository root;
## `tools/bin/visual-check SCENARIO[/VISIT]` runs it and the comparison.)

const IMAGE := 0xFFB050
const IMAGE_SIZE := 0xCA62 - 0xB050
const HIGH := 0xFFE000
const HIGH_SIZE := 0x2000
const PADS := 0xFFCA5A
const AUX := 0xFFCA18
## The stats' starfield motion object (MwStatsSim.STAR).
const STAR := 0xFFC7F8
## `$13D9C`'s tables: 4 effect channels of `$42` bytes (+`$20` = 1: playing,
## +`$C` handle) and 32 music entries of `$2A` (+0 = 0: in use, +`$24`
## handle; music handles carry bit 31).
const SFX := 0xFFEA22
const MUSIC_ENTRIES := 0xFFEB44
## Screens whose pass reads the pads at its end (after the sprite upload's
## VBlank, right before the next boundary): their pass's pads are in the
## next boundary's frame; the others read them right after their boundary.
const READ_AT_END := [12, 13, 14, 15, 16, 17]
## A loop's stamp is a recent tick (older values in a local are leftovers).
const STAMP_AGE := 32
## `dma_queue_wait` (`$148A8`: a loop until VBlank has sent the queue).
const DMA_WAIT := 0x148A8
## The loops' waits (PC ranges): a frame that ends there ended between passes.
const WAITS := [[0x148A8, 0x148BA], [0x8D6E, 0x8D7C], [0xE6C0, 0xE6CE], [0xD8D8, 0xD8E6],
		[0xE432, 0xE43C], [0x13AC6, 0x13AD0], [0x9E64, 0x9E70], [0xD1E4, 0xD1F0], [0xCB9E, 0xCBBA]]


## A recording of `mw_harness.visual_rec`.
class Rec extends RefCounted:
	var dir := ""
	var meta := {}
	var frames: Array = []
	var raw := PackedByteArray()
	var size := 0
	var entry_ram := PackedByteArray()

	func open(path: String) -> bool:
		dir = path
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("meta.json")))
		if not m is Dictionary:
			return false
		meta = m
		frames = meta["frames"]
		size = int(meta["record_size"])
		raw = FileAccess.get_file_as_bytes(path.path_join("ram.bin"))
		entry_ram = FileAccess.get_file_as_bytes(path.path_join("entry_ram.bin"))
		return raw.size() == size * frames.size()

	func count() -> int:
		return frames.size()

	func image(k: int) -> PackedByteArray:
		return raw.slice(k * size, k * size + IMAGE_SIZE)

	## The stack page `$FFFE00`-`$FFFFFF` of record [param k].
	func stack(k: int) -> PackedByteArray:
		var at := k * size + IMAGE_SIZE + 0x1E00
		return raw.slice(at, at + 0x200)

	func _at(k: int, a: int) -> int:
		a = a & 0xFFFFFF
		if a >= IMAGE and a < IMAGE + IMAGE_SIZE:
			return k * size + a - IMAGE
		if a >= HIGH and a < HIGH + HIGH_SIZE:
			return k * size + IMAGE_SIZE + a - HIGH
		return -1

	func u8(k: int, a: int) -> int:
		var i := _at(k, a)
		return raw[i] if i >= 0 else 0

	func u32(k: int, a: int) -> int:
		var i := _at(k, a)
		if i < 0:
			return 0
		return (raw[i] << 24) | (raw[i + 1] << 16) | (raw[i + 2] << 8) | raw[i + 3]

	func tick(k: int) -> int:
		return int(frames[k][1])

	func sid(k: int) -> int:
		return int(frames[k][2])

	func pc(k: int) -> int:
		return int(frames[k][3])

	## The long on the stack at record [param k]'s end (in a wait: who called it).
	func ret(k: int) -> int:
		return int(frames[k][7]) if frames[k].size() > 7 else -1

	## Record [param k] ended in `dma_queue_wait` called from [param from].
	func dma_waiting(k: int, from: int) -> bool:
		return pc(k) >= DMA_WAIT and pc(k) < DMA_WAIT + 8 and ret(k) == from

	## Record [param k] ended between passes (inside a loop's wait).
	func waiting(k: int) -> bool:
		var p := pc(k)
		for w in WAITS:
			if p >= int(w[0]) and p < int(w[1]):
				return true
		return false

	## The sound handles playing at record [param k] (`$13D9C`'s view).
	func handles(k: int) -> Array:
		var out := []
		for c in 4:
			var at := SFX + 0x42 * c
			if u8(k, at + 0x20) == 1:
				out.append(u32(k, at + 0xC))
		for e in 32:
			var at := MUSIC_ENTRIES + 0x2A * e
			if u8(k, at) == 0:
				out.append(u32(k, at + 0x24) | 0x80000000)
		return out


## What the sims ask outside the CPU, answered from the recording.
class Hooks extends RefCounted:
	var rec: Rec
	## The pass's boundary record and the next one's (-1: none).
	var k := 0
	var next_k := -1
	var now := 0
	## The loop's stamp is made late in its pass (the boundary record is the
	## stamp's): what a pass stores is in the records up to the next stamp.
	var mid_pass := false
	var loop_start := 0
	var pass_start_tick := 0
	var pass_end_tick := 0
	## Our sound handles -> the driver's (from the recording); unmatched
	## ones never play.
	var mapped := {}
	var _fake := 0x20000000

	func tick(_sim: MwScreenSim) -> int:
		return now

	func setup_end(_sim: MwScreenSim) -> int:
		return loop_start

	func pass_start(_sim: MwScreenSim) -> int:
		return pass_start_tick

	func pass_end(_sim: MwScreenSim) -> int:
		return pass_end_tick

	func stored_long(_sim: MwScreenSim, address: int) -> int:
		if mid_pass:
			return rec.u32(next_k - 1 if next_k > k else k, address)
		return rec.u32(next_k if next_k >= 0 else rec.count() - 1, address)

	## A new sound of this pass: the driver's first handle (an effect, or
	## music for ids below `$12`) that appears in the pass's frames.
	func voice_handle(_sim: MwScreenSim, id: int) -> int:
		var music := (id & 0xFFFF) < 0x12
		var before := rec.handles(maxi(k - 1, 0))
		var last := mini(maxi(next_k, k) + 2, rec.count() - 1)
		for j in range(k, last + 1):
			for h in rec.handles(j):
				var is_music := (int(h) & 0x80000000) != 0
				if is_music == music and not h in before and not mapped.values().has(h):
					mapped[h] = h
					return h
		_fake += 1
		return _fake

	func voice_poll(_sim: MwScreenSim, handle: int) -> int:
		if not mapped.has(handle):
			return 0
		return 1 if handle in rec.handles(k) else 0


var rec := Rec.new()
var out_dir := ""
var max_passes := 100000
## Passes whose sprite list and draw operations are printed (--dump).
var dump: Array[int] = []
var screen := -1
var scene: MwBetweenPlays
var hooks := Hooks.new()
var passes: Array = []
var _phase := 0
var _pass := 0
## The boundary scan: the record of the last boundary, the current loop's
## rule ([method loop_rule]), the last stamp (or the last boundary's tick
## for a DMA-synced loop), the loop's own stamps still to come.
var _k := 0
var _prev_k := 0
var _pads_k := 0
var _rule := {}
var _last := 0
var _stamp_pending := 0
var _next: Dictionary = {}
var _done := false
## The sim and state passes run on (the first run's, then the scene's).
var _sim: MwScreenSim
var _state: MwRinkState
var _dry := true
## Passes after which the loop changed (pass -> rule): seen in this run,
## known from the first.
var _rules_seen := {}
var _rule_after := {}
## Values taken from the recording ([method _resync]).
var resyncs := 0


func _initialize() -> void:
	MwScreenDraw.cut_rows = false          # the original's pixels, stray ones included
	var args := OS.get_cmdline_user_args()
	var pos: Array[String] = []
	var i := 0
	while i < args.size():
		if args[i] == "--max":
			i += 1
			max_passes = int(args[i])
		elif args[i] == "--dump":
			i += 1
			for x in args[i].split(","):
				dump.append(int(x))
		else:
			pos.append(args[i])
		i += 1
	if pos.size() < 2:
		push_error("usage: visual_check.gd -- REC_DIR OUT_DIR [--max N] [--dump PASS,..]")
		quit(2)
		return
	var root_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var rd := pos[0] if pos[0].is_absolute_path() else root_dir.path_join(pos[0])
	out_dir = pos[1] if pos[1].is_absolute_path() else root_dir.path_join(pos[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not rec.open(rd):
		push_error("visual_check: cannot read %s" % rd)
		quit(2)
		return
	hooks.rec = rec
	screen = int(rec.meta["screen"])
	_dry_run()


func _process(_delta: float) -> bool:
	match _phase:
		0:
			_make_scene()
			_phase = 1
		1:
			_enter()
			_phase = 2
		2:
			_phase = 3                      # one more frame: the planes' cells update
		3:
			_capture()
			if _done or _pass >= max_passes:
				_finish()
				return true
			_run_pass()
			_phase = 2
	return false


## The game's state at the entry: the first record's RAM decoded (the
## replay ring from the whole RAM), the entry's tick.
func _entry_state(rom: PackedByteArray) -> MwRinkState:
	var s := MwRinkRam.decode(rom, rec.image(0))
	s.tick = rec.tick(1) if rec.count() > 1 else rec.tick(0)
	s.replay.ring_bytes = rec.entry_ram.slice(0, 0x8000)
	return s


func _make_scene() -> void:
	var rom := MwRom.data()
	var image0 := rec.image(0)
	var s := _entry_state(rom)
	var session := MwSession.new(1, 1)
	session.setup = MwMatchSetup.from_bytes(image0.slice(MwRinkRam.SETUP - IMAGE, MwRinkRam.SETUP - IMAGE + 10))
	session.rng.state = s.rng.state
	session.rng_aux.state = MwRinkRam.u32(image0, AUX)
	session.screens["rink"] = s
	var packed: PackedScene = load(MwScreens.scene_path(screen))
	scene = packed.instantiate() as MwBetweenPlays
	scene.screen_id = screen
	scene.previous = int(rec.meta["previous"])
	scene.session = session
	scene.on_sim_made = _sim_made
	root.add_child(scene)


## The sim made, before its set-up: the hooks, the RAM its state lacks.
func _sim_made(sim: MwScreenSim) -> void:
	sim.hooks = hooks
	if sim.has_method("enter_ram"):
		sim.call("enter_ram", rec.image(0))


## A first run of the sim alone (no scene, nothing saved): which passes
## switch the screen's loop (8 / 9, the fight's card). A pass's next
## boundary is that of the loop it leaves the sim in, and its hooks must
## know it before it runs; the second run takes them from here.
func _dry_run() -> void:
	var rom := MwRom.data()
	_sim = MwScreenSims.make(screen, rom)
	_state = _entry_state(rom)
	_sim_made(_sim)
	_begin()
	_sim.begin_pass()
	_sim.enter(_state, screen, int(rec.meta["previous"]))
	while not _done and _pass < max_passes:
		_run_pass()
	_rule_after = _rules_seen.duplicate()
	# the second run starts afresh
	hooks = Hooks.new()
	hooks.rec = rec
	passes = []
	_pass = 0
	_done = false
	_dry = false
	resyncs = 0


## The boundary scan's start: the set-up's loop.
func _begin() -> void:
	_k = 0
	_rule = loop_rule(screen, null, rec, 0)
	_last = rec.u32(0, int(_rule["stamp"])) if _rule.has("stamp") else rec.tick(1)
	_stamp_pending = int(_rule.get("setup", 0))
	_next = _find_next()
	hooks.mid_pass = bool(_rule.get("mid_pass", false))
	hooks.k = 0
	hooks.next_k = int(_next.get("k", -1))
	hooks.loop_start = int(_next.get("start", rec.tick(0)))
	hooks.now = rec.tick(1) if rec.count() > 1 else rec.tick(0)


func _enter() -> void:
	_begin()
	scene._enter_screen({})
	_sim = scene.sim
	_state = scene.state
	_resync(int(_next.get("k", -1)))
	_note(0, 0, 0, [0, 0, 0, 0], [0, 0, 0, 0], -1)


## The next pass boundary after record [member _k] under the current
## loop's rule ({} at the visit's end): {k, elapsed, tick, last, start}.
func _find_next() -> Dictionary:
	return _scan(_rule, _last, _stamp_pending)


## The next boundary after record [member _k] under [param rule], from the
## last stamp (or boundary tick) [param last] with [param pending] of the
## loop's own stamps to come first.
func _scan(rule: Dictionary, last: int, pending: int) -> Dictionary:
	var k := _k
	var start := hooks.loop_start
	while k + 1 < rec.count():
		k += 1
		if rec.sid(k) != screen:
			break
		if rule.has("dma"):
			# the VBlank that ended the last frame's wait is the boundary
			if rec.dma_waiting(k - 1, int(rule["dma"])):
				return {"k": k, "elapsed": (rec.tick(k) - last) & 0xFFFF, "tick": rec.tick(k), "last": rec.tick(k),
						"start": start}
			continue
		var v := rec.u32(k, int(rule["stamp"]))
		if v == last or (rec.tick(k) - v) & 0xFFFFFFFF > STAMP_AGE:
			continue                          # unchanged, or not a tick stamp (the stack's old contents)
		var el := (v - last) & 0xFFFFFFFF
		last = v
		if pending > 0:
			pending -= 1
			start = v
			continue
		return {"k": k, "elapsed": el & 0xFFFF, "tick": v, "last": v, "start": start}
	return {}


## Switches the scan to [param rule] at the current boundary.
func _switch(rule: Dictionary, tick: int) -> void:
	_rule = rule
	_last = rec.u32(_k, int(_rule["stamp"])) if _rule.has("stamp") else tick
	_stamp_pending = int(_rule.get("switch", 0))


func _run_pass() -> void:
	if _next.is_empty():
		_done = true
		return
	var b := _next
	_prev_k = _k
	_k = int(b["k"])
	_last = int(b["last"])
	_stamp_pending = 0
	hooks.loop_start = int(b["start"])
	var el := int(b["elapsed"])
	# a pass that switches the loop (known from the first run) ends at the new loop's boundary
	var n := _pass + 1
	if _rule_after.has(n) and _rule_after[n] != _rule:
		_switch(_rule_after[n], int(b["tick"]))
	var after := _find_next()
	var end_k := int(after["k"]) - 1 if not after.is_empty() else _visit_end()
	end_k = maxi(end_k, _k)
	var pads_k := _k
	if screen in READ_AT_END:
		pads_k = int(after["k"]) if not after.is_empty() else _last_read(_k)
	elif bool(_rule.get("mid_pass", false)) and _k - 1 > _prev_k:
		pads_k = _k - 1                      # read at the pass's start, before its stamp
	hooks.mid_pass = bool(_rule.get("mid_pass", false))
	var held := []
	var new := []
	for p in 4:
		held.append(rec.u8(pads_k, PADS + 2 * p))
		new.append(rec.u8(pads_k, PADS + 2 * p + 1))
	hooks.k = _k
	hooks.next_k = int(after.get("k", -1))
	hooks.pass_start_tick = int(b["tick"])
	hooks.pass_end_tick = int(after["tick"]) if not after.is_empty() else int(b["tick"]) + maxi(el, 1)
	hooks.now = hooks.pass_end_tick - 1 if not after.is_empty() else int(b["tick"])
	_state.tick = int(b["tick"])
	_sim.begin_pass()
	var to := _sim.step(el, held, new)
	_resync(int(after.get("k", -1)))
	if not _dry:
		scene._draw_pass()
	_pass += 1
	# the loop may change with the sim's state (8 / 9, the fight's card)
	var rule := loop_rule(screen, _sim, rec, _k)
	if rule != _rule:
		_rules_seen[_pass] = rule
		_switch(rule, int(b["tick"]))
		after = _find_next()
	_next = after
	_pads_k = pads_k
	if not _dry:
		_note(_pass, el, end_k, held, new, to)
		if _pass in dump:
			_dump()
	if to >= 0:
		_done = true


## What the emulators' timing decides, taken from the recording at the
## next boundary [param k] (none: -1) whenever ours differs: the stats'
## starfield (`$FFC7F8`, moved by a VBlank task: how many VBlanks a set-up
## or a switch between 8 and 9 takes differs between BlastEm, which the
## sim's constants follow, and GPGX; between those the sim's passes keep it
## in step). Counted in [member resyncs].
func _resync(k: int) -> void:
	if k < 0 or not "star" in _sim:
		return
	var star: MwMotion = _sim.get("star")
	var changed := false
	for a in 2:
		var at := STAR + 8 * a
		var pos := rec.u32(k, at)
		pos = pos - 0x100000000 if pos >= 0x80000000 else pos
		var vel := MwRinkSim.s16((rec.u8(k, at + 4) << 8) | rec.u8(k, at + 5))
		var acc := MwRinkSim.s16((rec.u8(k, at + 6) << 8) | rec.u8(k, at + 7))
		if star.pos[a] != pos or star.vel[a] != vel or star.acc[a] != acc:
			changed = true
		star.pos[a] = pos
		star.vel[a] = vel
		star.acc[a] = acc
	if changed:
		resyncs += 1
		var px := star.pixels()
		_state.scroll_b = Vector2i(MwRinkSim.s16(px.x), MwRinkSim.s16(px.y))


## --dump: the pass's sprite list (VDP entries in link order) and operations.
func _dump() -> void:
	print("pass %d (record %d): %d sprite ops, %d window ops, %d plane ops" % [_pass, _k, _sim.sprite_ops.size(),
			_sim.window_ops.size(), _sim.plane_ops.size()])
	for op in _sim.sprite_ops:
		print("  op ", op)
	for e in MwScreenDraw.new(MwRom.data()).list(_state, _sim.sprite_ops):
		print("  spr ", e)


## A last pass of a screen reading the pads at its end: the first later
## record with a new press (the one that left), else the next one.
func _last_read(k: int) -> int:
	var end := _visit_end()
	for j in range(k + 1, end + 1):
		for p in 4:
			if rec.u8(j, PADS + 2 * p + 1) != 0:
				return j
	return mini(k + 1, end)


## The last record of the visit (the screen id still this one).
func _visit_end() -> int:
	var k := rec.count() - 1
	while k > 0 and rec.sid(k) != screen:
		k -= 1
	return k


## The sim's differences from record [param k] (its comparison, the main
## random stream).
func _differences(k: int) -> Array:
	if _sim == null:
		return []
	var d: Array = _sim.compare(rec.image(k), rec.stack(k))
	var want := MwRinkRam.u32(rec.image(k), MwRinkRam.RNG)
	if _state.rng.state != want:
		d.push_front(["rng", "%08X" % _state.rng.state, "%08X" % want])
	return d


## The pass's entry in passes.json, with the sim's comparison against the
## record where the pass ended (or the next boundary's, see below).
func _note(n: int, el: int, end_k: int, held: Array, new: Array, to: int) -> void:
	var sim := _sim
	var at := end_k
	if n == 0:
		at = maxi(int(_next.get("k", 1)) - 1, 0) if not _next.is_empty() else _visit_end()
	var d := _differences(at)
	# what a loop does after its wait (the 17's lockout, the replay's counters) is only in the
	# next boundary's frame, which also holds the next pass's start: the closer of the two
	var after := int(_next.get("k", -1))
	if not d.is_empty() and after > at:
		var d2 := _differences(after)
		if d2.size() < d.size():
			d = d2
			at = after
	var texts: Array[String] = []
	for x in d.slice(0, 6):
		texts.append("%s ours %s want %s" % [str(x[0]), str(x[1]), str(x[2])])
	# The frames that show the pass. A GPGX frame (stable-retro's step) runs from a VBlank
	# (the tick, the queued DMA: the sprite list) through the active display, its RAM is
	# taken at the end: a pass from the boundary in frame k draws its planes directly from
	# frame k on (most before the display starts) and its sprites show from the VBlank that
	# ends its wait (the next boundary's frame; a loop stamping late in the pass: the frame
	# after the stamp's). The frame showing both is the next boundary's, where the next
	# pass's early plane writes can show already: [shows] and the window [from, to].
	var from_k := _k if n > 0 else maxi(int(_next.get("k", 1)) - 1, 0)
	var shows := int(_next.get("k", -1)) if not _next.is_empty() else _k + 1
	if bool(_rule.get("mid_pass", false)):
		shows = from_k + 1
	elif _next.is_empty() and screen in READ_AT_END:
		shows = _pads_k + 1                  # the exit pass draws after its late read
	passes.append({"pass": n, "k": _k if n > 0 else 0, "at": at, "next": int(_next.get("k", -1)), "shows": shows,
			"window": [from_k, maxi(shows, from_k)],
			"elapsed": el, "held": held, "new": new, "exact": rec.waiting(at), "ndiff": d.size(),
			"diffs": texts, "to": to, "shown": int(sim.get("shown")) if sim != null and "shown" in sim else -1})


func _capture() -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("p%04d.png" % (passes.size() - 1)))


func _finish() -> void:
	var f := FileAccess.open(out_dir.path_join("passes.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"rec": rec.dir, "screen": screen, "passes": passes, "resyncs": resyncs}))
	f.close()
	var same := 0
	var exact := 0
	for p in passes:
		if int(p["ndiff"]) == 0:
			same += 1
		if bool(p["exact"]):
			exact += 1
	print("visual_check %s: screen %d, %d passes (%d without differences; %d compared at a wait; %d resyncs)" % [
			rec.dir.get_file(), screen, passes.size(), same, exact, resyncs])


## How the screen's current loop marks its pass boundaries: {"stamp":
## address} - the loop stamps the tick into that long at each boundary (its
## set-up stamps it "setup" times first, a switch to the loop "switch"
## times); {"dma": address} - the loop ends each pass in `dma_queue_wait`
## called from that address, the VBlank that ends the wait is the boundary.
## 12-17 and 19: `-4(a6)` = `$FFFFF4` (a6 = `$FFFFF8`); 18: the same in the
## fight, `$FFFEDE` in the card's loop; 7: `-4(a6)` = `$FFFFF0`; 8: its
## loop's wait (`$CC02`), 9 (inside 8): `$FFC3EE`; 10: the idle page's
## stamp (`$FFC75C`, its +`$80`: pad modes 0 / 2; made late in a pass, the
## set-up's first) - its
## CPU-bound passes (~3-4 ticks) often end their wait between two frames'
## ends - else its loop's wait (`$1098E`).
static func loop_rule(scr: int, sim: MwScreenSim, r: Rec, k: int) -> Dictionary:
	match scr:
		12, 13, 14, 15, 16, 17, 19:
			return {"stamp": 0xFFFFF4, "setup": 1}
		18:
			if sim != null and bool(sim.get("card")):
				return {"stamp": 0xFFFEDE, "setup": 1, "switch": 1}
			return {"stamp": 0xFFFFF4, "setup": 1}
		7:
			return {"stamp": 0xFFFFF0, "setup": 1}
		8:
			if sim != null and int(sim.get("shown")) == 9:
				return {"stamp": 0xFFC3EE, "setup": 0, "switch": 0}
			return {"dma": 0xCC02}
		10:
			# pad modes 0 / 2: the idle page (team B) stamps its +$80 each pass
			var mode := r.u8(k, MwRinkRam.PAD_MODE)
			if mode == 0 or mode == 2:
				return {"stamp": 0xFFC75C, "setup": 1, "mid_pass": true}
			return {"dma": 0x1098E}
	return {"dma": -1}
