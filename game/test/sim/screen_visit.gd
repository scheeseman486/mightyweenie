extends RefCounted
## A recorded screen visit (recorder v5's screen records) run through its
## ported sim ([MwScreenSims]): each pass with the original's elapsed
## ticks (d0 at the pass boundary, else the tick difference) and the pads
## its `read_joypads` saw (the RAM at the next record), the sound driver's
## answers and the tick reads from the recording ([Hooks]). Shared by
## screen-check (`screen_check.gd`: the visit from the RAM at the screen's
## call, compared pass by pass) and pass-check (`pass_check.gd`: the visits
## between two rink visits on our own state, so what the screens leave in
## the rink is ours).

## Pass boundaries without a tick wait (elapsed = the tick difference).
## (The replay's `$9E70` has d0 = the elapsed ticks: the loop's own
## difference, also for its first pass, which counts from the set-up's last
## tick read rather than from the screen's entry.)
const NO_WAIT := [0xCC02, 0x1098E]
const PADS := 0xFFCA5A


## The recording's answers to what a screen asks outside the CPU: the
## sound driver's "still playing?" (the "vc" log of the pass, in order),
## the tick reads.
class Hooks extends RefCounted:
	## `screen-check --deaf`: every voice poll answered "ended", as live
	## play's [method MwSound.busy] does until the sound driver (plan 12).
	static var deaf := false
	var vc: Array = []
	var at := 0
	var now := 0

	func voice_poll(_sim: MwScreenSim, _handle: int) -> int:
		var v := int(vc[at][1]) if at < vc.size() else 0
		at += 1
		if deaf:
			return 0
		return 1 if v != 0 else 0

	func tick(_sim: MwScreenSim) -> int:
		return now

	## The tick the first pass's elapsed counts from - what the set-up's
	## last tick read saw (the loop's snapshot): the first pass boundary's
	## tick minus its elapsed (the entry's tick when there is none). Screens
	## that stamp the tick at the end of their set-up ask for it.
	var loop_start := 0

	func setup_end(_sim: MwScreenSim) -> int:
		return loop_start

	## The pass's boundary tick (what a read early in the pass sees) and the
	## next boundary's (what a read after the pass's `dma_queue_wait` sees:
	## the queued sprite upload waits for a VBlank, and the loop's tick wait
	## then ends at once; the last pass: its tick + 1).
	var pass_start_tick := 0
	var pass_end_tick := 0

	func pass_start(_sim: MwScreenSim) -> int:
		return pass_start_tick

	func pass_end(_sim: MwScreenSim) -> int:
		return pass_end_tick

	## The RAM at the pass's end (the next boundary). Screen 10's passes are
	## CPU-bound (no tick wait), so a tick read inside a handler sees a VBlank
	## count no boundary tells: the check answers it with what the original
	## stored from it - the long at [param address] then.
	var next_ram := PackedByteArray()

	func stored_long(_sim: MwScreenSim, address: int) -> int:
		if next_ram.is_empty():
			return now
		return MwRinkRam.u32(next_ram, address)


## [Hooks] that also log their answers by kind (the screen fixture keeps
## them: compare/fixtures/screen_visits.json).
class Logged extends Hooks:
	var answers := {}

	func _log(kind: String, v: int) -> int:
		if not answers.has(kind):
			answers[kind] = []
		answers[kind].append(v)
		return v

	func voice_poll(sim: MwScreenSim, handle: int) -> int:
		return _log("voice_poll", super.voice_poll(sim, handle))

	func tick(sim: MwScreenSim) -> int:
		return _log("tick", super.tick(sim))

	func setup_end(sim: MwScreenSim) -> int:
		return _log("setup_end", super.setup_end(sim))

	func pass_start(sim: MwScreenSim) -> int:
		return _log("pass_start", super.pass_start(sim))

	func pass_end(sim: MwScreenSim) -> int:
		return _log("pass_end", super.pass_end(sim))

	func stored_long(sim: MwScreenSim, address: int) -> int:
		return _log("stored_long", super.stored_long(sim, address))


## The answers of a [Logged] run given back in the same order (a sim is
## deterministic: it asks the same questions again).
class Replayed extends RefCounted:
	var answers := {}
	var at := {}
	## The stats' set-up looks for this (`_setup_vblanks`); a fixture
	## without stored longs answers nothing.
	var next_ram := PackedByteArray([0])

	func _init(a: Dictionary) -> void:
		answers = a

	func _next(kind: String) -> int:
		var i := int(at.get(kind, 0))
		at[kind] = i + 1
		var list: Array = answers.get(kind, [])
		return int(list[i]) if i < list.size() else 0

	func voice_poll(_sim: MwScreenSim, _handle: int) -> int:
		return _next("voice_poll")

	func tick(_sim: MwScreenSim) -> int:
		return _next("tick")

	func setup_end(_sim: MwScreenSim) -> int:
		return _next("setup_end")

	func pass_start(_sim: MwScreenSim) -> int:
		return _next("pass_start")

	func pass_end(_sim: MwScreenSim) -> int:
		return _next("pass_end")

	func stored_long(_sim: MwScreenSim, _address: int) -> int:
		return _next("stored_long")


## Whether [param sim] is a port (the stubs keep MwScreenSim's step).
static func ported(sim: MwScreenSim) -> bool:
	return sim != null and sim.has_method("ported") and bool(sim.call("ported"))


## `screen-check --fresh`: a sim's own RAM from earlier visits is not
## given ([method MwStatsSim.enter_ram]): the visit starts as the live
## game's new sims do.
static var fresh := false


## Runs visit [param v] ([first record, last record, screen]) on [param s]
## through [param sim] (entered here, from the screen the recording says).
## [param each] (optional) is called after the set-up with (first, -1) and
## after each pass with (record, the screen it chose or -1). Returns the
## screen the sim left for (-1: none by the visit's last record).
## [param hooks] (optional): the [Hooks] to use (a [Logged] one for the
## fixture); [param trace] (optional) gets [entry tick, entry pads (8)]
## then per pass [tick, elapsed, held (4), new (4)].
static func run(rec: MwSimRecording, v: Array, s: MwRinkState, sim: MwScreenSim, each := Callable(),
		hooks: Hooks = null, trace: Variant = null) -> int:
	var first: int = v[0]
	var last: int = v[1]
	var scr: int = v[2]
	var from := from_screen(rec, first)
	s.tick = int(rec.screen_passes[first][2])
	# the pads as the screen's call finds them (input, not state)
	var at_entry := rec.screen_ram(first)
	for pad in 4:
		s.pads_held[pad] = MwRinkRam.u8(at_entry, PADS + 2 * pad)
		s.pads_new[pad] = MwRinkRam.u8(at_entry, PADS + 2 * pad + 1)
	if trace is Array:
		var pads := []
		for pad in 4:
			pads.append_array([s.pads_held[pad], s.pads_new[pad]])
		(trace as Array).append([s.tick, pads])
	if hooks == null:
		hooks = Hooks.new()
	sim.hooks = hooks
	hooks.now = s.tick
	hooks.vc = rec.screen_log("vc", first)
	hooks.loop_start = s.tick
	if first + 1 <= last and not int(rec.screen_passes[first + 1][3]) in NO_WAIT:
		hooks.loop_start = int(rec.screen_passes[first + 1][2]) - int(rec.screen_passes[first + 1][4])
	hooks.next_ram = rec.screen_ram(first + 1) if first + 1 <= last else PackedByteArray()
	if fresh and sim is MwStatsSim:
		# the live game's visit (`screen-check --fresh`): a new sim with the
		# session's second stream, nothing else from earlier visits
		(sim as MwStatsSim).aux.state = MwRinkRam.u32(rec.screen_ram(first), MwStatsSim.AUX)
	elif sim.has_method("enter_ram"):
		# the RAM the state does not hold (MwStatsSim: the aux stream, its scratch)
		sim.call("enter_ram", rec.screen_ram(first))
	sim.enter(s, scr, from)
	if each.is_valid():
		each.call(first, -1)
	for j in range(first + 1, last + 1):
		var e: Array = rec.screen_passes[j]
		var el := int(e[4])
		if int(e[3]) in NO_WAIT:
			el = (int(e[2]) - int(rec.screen_passes[j - 1][2])) & 0xFFFF
		var after_ := after(rec, j)
		var held := []
		var new := []
		for p in 4:
			held.append(MwRinkRam.u8(after_, PADS + 2 * p) if not after_.is_empty() else 0)
			new.append(MwRinkRam.u8(after_, PADS + 2 * p + 1) if not after_.is_empty() else 0)
		if j == last and not contiguous(rec, j):
			# the rink ran next: no snapshot holds what this pass's read_joypads saw
			# (on pad 1, or the pad a one-pad screen names: `control_pad()`)
			var b := tour_press(rec, int(e[2]), scr, int(rec.screen_passes[j - 1][2]))
			var at := int(sim.call("control_pad")) & 3 if sim.has_method("control_pad") else 0
			held = [0, 0, 0, 0]
			new = [0, 0, 0, 0]
			held[at] = b
			new[at] = b
		s.tick = int(e[2])
		hooks.now = int(rec.screen_passes[j + 1][2]) - 1 if j + 1 <= last else s.tick
		hooks.pass_start_tick = s.tick
		# the last pass: as long as its own elapsed (the screen left, no next boundary)
		hooks.pass_end_tick = int(rec.screen_passes[j + 1][2]) if j + 1 <= last else s.tick + maxi(el, 1)
		hooks.vc = rec.screen_log("vc", j)
		hooks.at = 0
		hooks.next_ram = rec.screen_ram(j + 1) if j + 1 <= last else PackedByteArray()
		if trace is Array:
			(trace as Array).append([s.tick, el, held.duplicate(), new.duplicate()])
		sim.begin_pass()
		var to := sim.step(el, held, new)
		if each.is_valid():
			each.call(j, to)
		if to >= 0 or j == last:
			return to
	return -1


## The screen's call before record [param i]: the screen it came from.
static func from_screen(rec: MwSimRecording, i: int) -> int:
	var e: Array = rec.screen_passes[i]
	var prev := -1
	for x in rec.meta["screens"]:
		if int(x[2]) == int(e[2]) and int(x[1]) == int(e[1]):
			return prev
		prev = int(x[1])
	return prev


## The RAM after record [param j]'s pass: the next record's, else the next
## rink pass's start.
static func after(rec: MwSimRecording, j: int) -> PackedByteArray:
	if j + 1 < rec.screen_passes.size():
		return rec.screen_ram(j + 1)
	var n := int(rec.screen_passes[j][0])
	return rec.start(n) if n < rec.count() else PackedByteArray()


## Whether record [param j + 1] follows record [param j] directly (the
## same screen's next pass, or the next screen entered without rink passes
## between): its RAM holds what record [param j]'s pass left.
static func contiguous(rec: MwSimRecording, j: int) -> bool:
	if j + 1 >= rec.screen_passes.size():
		return false
	var nx: Array = rec.screen_passes[j + 1]
	return int(nx[3]) != MwSimRecording.SCREEN_ENTRY or int(nx[0]) == int(rec.screen_passes[j][0])


## The button the recording's tour pressed during the pass from [param
## tick] on screen [param scr] (meta "tour" log [tick, screen, state,
## button]: the first press within 16 ticks; failing that, the last one
## logged from [param since], the previous pass boundary, on - a press
## logged at tick t reaches the pads from t + 1, and the replay's loop
## reads them right after its boundary) as a pad byte, 0 if none: a
## visit's last pass before the rink has no snapshot of its read_joypads.
static func tour_press(rec: MwSimRecording, tick: int, scr: int, since := -1) -> int:
	const BITS := {"START": 0x80, "A": 0x40, "C": 0x20, "B": 0x10, "right": 0x08, "left": 0x04,
			"down": 0x02, "up": 0x01}
	var tour: Variant = rec.meta.get("tour")
	if not tour is Dictionary:
		return 0
	var earlier := 0
	for x in (tour as Dictionary).get("log", []):
		if int(x[1]) != scr or not BITS.has(str(x[3])):
			continue
		if int(x[0]) >= tick and int(x[0]) < tick + 16:
			return int(BITS.get(str(x[3]), 0))
		if since >= 0 and int(x[0]) >= since and int(x[0]) < tick:
			earlier = int(BITS.get(str(x[3]), 0))
	return earlier


## The screen the original went to after record [param j] (-1: the recording ended).
static func next_screen(rec: MwSimRecording, j: int) -> int:
	var tick := int(rec.screen_passes[j][2])
	for x in rec.meta["screens"]:
		if int(x[2]) > tick:
			return int(x[1])
	return -1


## The visits between rink passes [param n] - 1 and [param n] (the screens
## after the rink's pass n - 1, in order): [[first, last, screen], ...].
static func visits_after(rec: MwSimRecording, n: int) -> Array:
	var out := []
	for v in rec.screen_visits():
		if int(rec.screen_passes[v[0]][0]) == n:
			out.append(v)
	return out
