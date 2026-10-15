class_name MwPassLoad
extends RefCounted
## The original's 68000 load in the rink loop, pass by pass (plan 36,
## docs/re/timing.md "Pass load"): what a pass made the CPU do, read from
## our simulation, so the pass's length in ticks can follow the original's
## (TICK RATE ORIGINAL, [MwSettings]).
##
## The rink pass `$F962` (docs/re/rink-pass.md 1) costs the 68000 roughly
## * a fixed part (the pads with the 4-Way Play, `$95C8`, the loop);
## * the team updates (`$3836`): per present player its dispatcher `$86A` -
##   far more when the player is on the previous pass's screen (`$5C3C`:
##   only those collide), when its AI thinks (`$3BFE`, `$8820`, the
##   avoidance `$2050`), by state and control;
## * the rink update `$56EA` (plane B rows streamed as the camera moves);
## * the phase handler `$FC58` (its window texts and sprites);
## * the draws (`$38E0` per team, the puck, `$591E`): per sprite piece and
##   frame, and per tile run the sprite tile cache `$150CE` had to upload;
## * the VBlank handler (the DMA queue drained: words queued since the last
##   VBlank; the sound driver; palette steps).
## [method features] reads all of it after a pass; [MwPassCost] turns it
## into the 68000's cycles and [MwPassPacer] into ticks (TICK RATE
## ORIGINAL; APPROXIMATED reads the same load without the dictionaries:
## [MwPassApprox]). The sprite tile cache's model is [MwTileLru] (an LRU of
## 672 tiles keyed by a run's first tile, emptied at each rink visit): it
## agrees with the original's misses on 99.2 % of its calls.

var rom: PackedByteArray
## The CPU with its thinks counted per player (the AI's cost: `$86A`'s
## think, `$8820`, the avoidance) - APPROXIMATED's counter (plan 40, S8).
var ai := MwPassApprox.Thinks.new()
var cache := MwTileLru.new()
var _start: Array = []               # the players at the segment's start ([method begin])
var _e := 0
var _phase0 := 0
var _row0 := 0
var _cam0 := Vector2i.ZERO
var _puck0 := []
## Live play ([method clock_now] at the pass start): the pass's own clock
## texts are its "clock"; else (the recordings' replays) the next pass's
## start is run with this pass's features ("clock_next").
var live := false
var _clock: Variant = null


func _init(rom_: PackedByteArray) -> void:
	rom = rom_


## A new rink visit: the sprite tile cache starts empty (`rink_load`).
func reset_visit() -> void:
	cache.reset()


## [param cpu] with its thinks counted ([member ai]); set it as the sim's CPU.
func wrap(cpu: Object) -> MwPassApprox.Thinks:
	ai.inner = cpu
	return ai


## Before the segment of a pass with [param e] elapsed ticks: who is on the
## ice, on the previous pass's screen, carrying the puck, thinking soon.
func begin(sim: MwRinkSim, e: int) -> void:
	var s := sim.s
	_e = e
	_phase0 = s.phase
	_row0 = s.plane_b_cell.y
	_cam0 = s.camera.shown
	var pk := s.puck
	_puck0 = [pk.flags, absi(pk.motion.vel[0]) + absi(pk.motion.vel[1]), pk.motion.pos[2], absi(pk.motion.vel[2])]
	ai.clear()
	_start = []
	for ti in 2:
		var players := s.teams[ti].players
		for i in players.size():
			var p := players[i]
			if not p.present:
				continue
			ai.place[p] = ti * 8 + i
			_start.append([p, ti, 1 if MwRinkSim.on_screen(s, p) else 0,
					1 if s.puck.flags & MwRinkState.Puck.CARRIED and s.puck.carrier == p else 0,
					p.state, 1 if p.flags & MwRinkState.Player.HUMAN else 0, 1 if p.think <= 0 else 0, p.position,
					p.original, p.weapon, p.anim_id])


## After the pass (the segment, the rink update, the phase handler, the
## draws of [param up]'s drawer, and the next pass's start - its clock - in
## [param up]): the pass's features. [param ph]: the phase handler (its
## window texts). The sprite tile cache sees them in the original's order:
## the phase handler's texts, the draws, the next pass's clock texts
## ("clock_next": the next pass's cost).
func features(up: MwRinkUpdate, ph: MwRinkPhases) -> Dictionary:
	var s := up.sim.s
	var f := {"e": _e, "phase": _phase0, "phase_end": s.phase}
	# players
	var on := [0, 0]
	for st in _start:
		on[int(st[1])] += int(st[2])
	var players := []
	for st in _start:
		var p: MwRinkState.Player = st[0]
		players.append([int(st[1]), int(st[2]), on[int(st[1])], on[1 - int(st[1])], 1 if int(st[7]) == 5 else 0,
				int(st[3]), int(st[4]), int(st[5]), int(st[6]), ai.count_of(p), int(st[8]), int(st[9]),
				int(st[10])])
	f["players"] = players
	# the phase handler's window texts (their glyphs cached at once, `$150C6`)
	f["window"] = _window(ph.window_ops if ph != null else [])
	# the draws, part by part
	var drawer := up.drawer
	var prev := [0, 0, 0, 0]
	for part in ["phase", "team_a", "team_b", "puck", "rink", "portrait"]:
		var m: Array = drawer.marks.get(part, prev)
		var runs := 0
		var tiles := 0
		for i in range(int(prev[2]), int(m[2])):
			var up_tiles := MwPassApprox.piece_tiles(rom, cache, int(drawer.inserted[i]))
			if up_tiles > 0:
				runs += 1
				tiles += up_tiles
		f["draw_" + part] = [int(m[0]) - int(prev[0]), int(m[1]) - int(prev[1]), int(m[2]) - int(prev[2]), runs, tiles,
				int(m[3]) - int(prev[3])]
		prev = m
	# the next pass's start: its clock texts (`$261C`)
	if live:
		f["clock"] = _clock
	else:
		f["clock_next"] = _window(up.window_ops)
	# plane B rows streamed by the rink update (each a 64-word DMA)
	f["rows"] = absi(s.plane_b_cell.y - _row0)
	var objs := 0
	for object_slot in s.objects:
		if object_slot.kind != 0:
			objs += 1
	f["objects"] = objs
	# candidates (plan 36's fit): the rink's hazards, teams, nets, objects'
	# kinds, the camera's move, the puck at the segment's start
	var hz := []
	for hazard in s.hazards:
		hz.append(hazard.kind)
	f["hazards"] = hz
	f["teams"] = [s.teams[0].record, s.teams[1].record]
	var nets := []
	for net in s.nets:
		nets.append(net.style)
	f["nets"] = nets
	var kinds := []
	for rink_object in s.objects:
		kinds.append(rink_object.kind)
	f["kinds"] = kinds
	f["cam"] = [absi(s.camera.shown.x - _cam0.x), absi(s.camera.shown.y - _cam0.y)]
	f["puck0"] = _puck0
	f["replay"] = s.replay_on
	f["crowd"] = s.crowd
	return f


## Live play: the pass start's clock texts [param ops]
## ([member MwRinkUpdate.window_ops]), through the cache as the original
## draws them first thing in the pass.
func clock_now(ops: Array) -> void:
	_clock = _window(ops)


## A window op list's load: [ops, text characters, glyph runs the cache
## missed, their tiles, fill cells] (MwPassApprox.window_counts: plan 40, S8).
func _window(ops: Array) -> Array:
	return Array(MwPassApprox.window_counts(rom, cache, ops))


## Plan 40 (S8): the pass's work for [MwPassPacer] in master clocks
## ([method features] through [method MwPassCost.work_mclk]) - live play's,
## as APPROXIMATED's [method MwPassApprox.work].
func work(up: MwRinkUpdate, ph: MwRinkPhases) -> Dictionary:
	var f := features(up, ph)
	return MwPassCost.work_mclk(f, f["clock"])
