class_name MwPassApprox
extends RefCounted
## TICK RATE APPROXIMATED (plan 36, docs/re/timing.md "Pass load"): the
## rink pass's 68000 work as [MwPassLoad] + [MwPassCost] read it for
## ORIGINAL, made deterministic and cheap enough for online play (plan 35:
## every machine runs the same game from the same inputs, so the pass
## lengths follow from the shared state and cost nothing on the network):
##
## * integers only: weights in 1/[constant SCALE] cycles, rounded
##   ([MwPassApproxWeights], generated with [MwPassCostWeights]), the work
##   in master clocks for [MwPassPacer]'s integer timeline;
## * the sound driver's work at its mean (ORIGINAL reads the running
##   driver's: a machine's audio never reaches the game here);
## * no dictionaries or per-feature vectors: the same linear models summed
##   straight from the rink's state, the drawer's counts and the tile cache
##   ([MwTileLru], O(1) a use).
##
## Use: [method reset_visit] at a rink entry, [method wrap] the CPU, then per
## pass [method clock_now] after the pass start, [method begin] before the
## segment, [method work] after the draws (the recordings' replays, whose
## next pass start comes before [method work]: [method clock_now] after it).
## The rink makes it anew at each rink entry, with its pacer: plan 35's
## snapshots, taken as a screen is entered, never need its state (the
## pacer's state after each pass is in the rink's hash instead,
## MwRinkState.pace). Plan 40 (S8): ORIGINAL's [MwPassLoad] counts the AI's
## thinks with [Thinks] and the tile cache's uploads with
## [method piece_tiles] / [method window_counts] too - one counting, two
## cost models.

## The team update model's player states and phases, the phase handler's
## phases (as [MwPassCost]).
const PSTATES := [0, 1, 2, 3, 4, 5, 8, 10, 14, 15, 20]
const PPHASES := [0, 1, 3, 4, 5, 8, 9, 10, 14]
const PHASES := [0, 1, 3, 5, 8, 9]
const HALF := 47                     ## a player's features: on screen 0..46, off it 47..93
const SCALE := 16                    ## [MwPassApproxWeights]' fixed point: 1/16 cycles
const OBJECT_KINDS := 23
const DRAW_PARTS := ["phase", "team_a", "team_b", "puck", "rink", "portrait"]


## The CPU with its thinks counted per player present at the segment's
## start (by its place: team x 8 + its index in the team's players; both
## TICK RATE models: [method MwPassApprox.begin], [method MwPassLoad.begin]).
class Thinks extends RefCounted:
	var inner: Object
	var counts := PackedInt32Array()
	var place := {}                  # player -> its place

	func _init() -> void:
		counts.resize(16)

	## A new segment: nobody counted, nobody placed.
	func clear() -> void:
		counts.fill(0)
		place.clear()

	## Player [param p]'s thinks this segment (0: not placed).
	func count_of(p: MwRinkState.Player) -> int:
		var k: int = place.get(p, -1)
		return counts[k] if k >= 0 else 0

	func think(sim_: MwRinkSim, p: MwRinkState.Player, team: MwRinkState.Team, other: MwRinkState.Team) -> void:
		var k: int = place.get(p, -1)
		if k >= 0:
			counts[k] += 1
		inner.think(sim_, p, team, other)


var rom: PackedByteArray
var cache := MwTileLru.new()
var thinks := Thinks.new()
var _state_ix := PackedInt32Array()    # state -> PSTATES index, -1
var _pphase_ix := PackedInt32Array()   # phase -> PPHASES index, -1
var _phase_ix := PackedInt32Array()    # phase -> PHASES index, -1
var _e := 0
var _phase0 := 0
var _row0 := 0
var _puck := PackedInt32Array([0, 0, 0, 0])
var _players := 0                      # present players
var _cost := 0                         # their updates without the thinks (1/16 cycles)
var _on := PackedInt32Array()          # place -> 0 on screen, HALF off, -1 absent
var _count := PackedInt32Array([0, 0]) # players on the previous screen, off it
## The last [method work]'s parts in 1/16 cycles: the team updates, the
## clock, the rest before the wait, the rink update, the phase handler, the
## draws, the rest after it (checks).
var parts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
## The clock texts' work of the pass to come ([method clock_now]), 1/16 cycles.
var clock_work := 0


func _init(rom_: PackedByteArray) -> void:
	rom = rom_
	clock_work = clock_cost(null)
	_state_ix = _index(PSTATES, 256)
	_pphase_ix = _index(PPHASES, 64)
	_phase_ix = _index(PHASES, 64)
	_on.resize(16)


static func _index(values: Array, n: int) -> PackedInt32Array:
	var t := PackedInt32Array()
	t.resize(n)
	t.fill(-1)
	for i in values.size():
		t[int(values[i])] = i
	return t


## A new rink visit: the tile cache empty.
func reset_visit() -> void:
	cache.reset()
	clock_work = clock_cost(null)


## [param cpu] with its thinks counted; set it as the sim's CPU.
func wrap(cpu: Object) -> Thinks:
	thinks.inner = cpu
	return thinks


## The pass start's clock texts [param ops] ([member MwRinkUpdate.window_ops]),
## first thing in the pass (live play).
func clock_now(ops: Array) -> void:
	clock_work = clock_cost(window_counts(rom, cache, ops))


## The clock model's work (1/16 cycles) for a window op list's counts (null:
## none known).
static func clock_cost(w: Variant) -> int:
	var weights := MwPassApproxWeights.CLOCK
	if w == null:
		return weights[5] + weights[6]
	var c: PackedInt32Array = w
	return weights[0] * c[0] + weights[1] * c[1] + weights[2] * c[2] + weights[3] * c[3] + weights[4] * c[4] \
			+ (weights[5] if c[0] == 0 else 0) + weights[6]


## Before the segment of a pass of [param e] ticks: each present player's
## update cost but its thinks (on or off the previous screen, state, phase,
## control, the rink's hazards).
func begin(sim: MwRinkSim, e: int) -> void:
	var s := sim.s
	_e = e
	_phase0 = s.phase
	_row0 = s.plane_b_cell.y
	var pk := s.puck
	_puck[0] = pk.flags
	_puck[1] = 1 if pk.motion.vel[0] != 0 or pk.motion.vel[1] != 0 else 0
	_puck[2] = 1 if pk.motion.pos[2] > 0 else 0
	_puck[3] = 1 if pk.motion.vel[2] != 0 else 0
	thinks.clear()
	_on.fill(-1)
	# per player: what is its own (control, the puck, its position, state)
	var weights := MwPassApproxWeights.PLAYERS
	var carrier: MwRinkState.Player = s.puck.carrier if s.puck.flags & MwRinkState.Puck.CARRIED else null
	var count := PackedInt32Array([0, 0])    # players on the previous screen, off it
	_cost = 0
	_players = 0
	for ti in 2:
		var players := s.teams[ti].players
		for i in players.size():
			var p := players[i]
			if not p.present:
				continue
			var o := 0 if MwRinkSim.on_screen(s, p) else HALF
			_on[ti * 8 + i] = o
			thinks.place[p] = ti * 8 + i
			count[0 if o == 0 else 1] += 1
			var c := 0
			if p.flags & MwRinkState.Player.HUMAN:
				c += weights[o + 1]
			if p == carrier:
				c += weights[o + 4]
			if p.position == 5:
				c += weights[o + 5]
			if ti == 0:
				c += weights[o + 6]
			if p.think <= 0:
				c += weights[o + 8]
			if p.weapon >= 0:
				c += weights[o + 9]
			var si := _state_ix[p.state & 255]
			if si >= 0:
				c += weights[o + 14 + si]
			_cost += c
	_players = count[0] + count[1]
	_count = count
	# what every player shares, by half: the base, the ticks, the phase, how
	# many were on the screen (the hazards: as the pass leaves them, [method work])
	var ph := _pphase_ix[_phase0 & 63]
	for half in 2:
		var o := half * HALF
		var shared: int = weights[o] + weights[o + 7] * e + weights[o + 34 + count[0]]
		if ph >= 0:
			shared += weights[o + 25 + ph]
		_cost += shared * count[half]


## After the draws of [param up]'s drawer and the phase handler [param ph]:
## the pass's work for [MwPassPacer] in master clocks ([method
## MwPassCost.work]'s keys), the clock's from [member clock_work].
func work(up: MwRinkUpdate, ph: MwRinkPhases) -> Dictionary:
	var s := up.sim.s
	var phase_end := s.phase
	var changed := 1 if phase_end != _phase0 else 0
	# the team updates: the players' thinks, the teams' own work
	var player_weights := MwPassApproxWeights.PLAYERS
	var teams := _cost
	for k in 16:
		var o := _on[k]
		var t := thinks.counts[k]
		if o >= 0 and t > 0:
			teams += player_weights[o + 2] + player_weights[o + 3] * t
	var hz := PackedInt32Array([0, 0, 0, 0, 0])
	for hazard in s.hazards:
		if hazard.kind >= 1 and hazard.kind <= 4:
			hz[hazard.kind] += 1
	for half in 2:
		var o := half * HALF
		teams += (player_weights[o + 10] * hz[1] + player_weights[o + 11] * hz[2] + player_weights[o + 12] * hz[3]
				+ player_weights[o + 13] * hz[4]) * _count[half]
	var team_weights := MwPassApproxWeights.TEAMS
	var pi := _pphase_ix[_phase0 & 63]
	teams += (team_weights[pi] if pi >= 0 else 0) + team_weights[9] * _players + team_weights[10]
	# the phase handler: its window texts (their glyphs cached at once) and sprites
	var win := window_counts(rom, cache, ph.window_ops if ph != null else [])
	var drawer := up.drawer
	var prev := PackedInt32Array([0, 0, 0, 0])
	var secs := []
	var tiles_all := 0
	var adds_all := 0
	for part in DRAW_PARTS:
		var end: Array = drawer.marks.get(part, prev)
		var runs := 0
		var tiles := 0
		for i in range(prev[2], int(end[2])):
			var up_tiles := piece_tiles(rom, cache, int(drawer.inserted[i]))
			if up_tiles > 0:
				runs += 1
				tiles += up_tiles
		var sec := PackedInt32Array([int(end[0]) - prev[0], int(end[1]) - prev[1], int(end[2]) - prev[2], runs, tiles,
				int(end[3]) - prev[3]])
		secs.append(sec)
		tiles_all += tiles
		adds_all += sec[0]
		prev = PackedInt32Array([int(end[0]), int(end[1]), int(end[2]), int(end[3])])
	var phase_weights := MwPassApproxWeights.PHASE_COST
	var dp: PackedInt32Array = secs[0]
	var phi := _phase_ix[_phase0 & 63]
	var handler: int = phase_weights[0] * win[0] + phase_weights[1] * win[1] + phase_weights[2] * win[2] \
			+ phase_weights[3] * win[3] + phase_weights[4] * win[4] \
			+ phase_weights[5] * dp[0] + phase_weights[6] * dp[1] + phase_weights[7] * dp[2] \
			+ phase_weights[8] * dp[3] + phase_weights[9] * dp[4] + phase_weights[10] * dp[5] \
			+ (phase_weights[11 + phi] if phi >= 0 else 0) + phase_weights[17] * changed + phase_weights[18]
	var draws := _draw(secs[1], MwPassApproxWeights.DRAW_A) + _draw(secs[2], MwPassApproxWeights.DRAW_B) \
			+ _draw(secs[3], MwPassApproxWeights.DRAW_PUCK) + _draw(secs[4], MwPassApproxWeights.DRAW_RINK) \
			+ _draw(secs[5], MwPassApproxWeights.DRAW_PORTRAIT)
	# the rink: its objects by kind, the nets, plane B's rows
	var kinds := PackedInt32Array()
	kinds.resize(OBJECT_KINDS + 1)
	var objects := 0
	for rink_object in s.objects:
		if rink_object.kind != 0:
			objects += 1
			if rink_object.kind <= OBJECT_KINDS:
				kinds[rink_object.kind] += 1
	var rows := absi(s.plane_b_cell.y - _row0)
	var full := rows > 4
	var rink_weights := MwPassApproxWeights.RINK_UPDATE
	var net := s.nets[0].style if not s.nets.is_empty() else 1
	var ru: int = rink_weights[0] * (0 if full else rows) + (rink_weights[1] if full else 0) \
			+ rink_weights[2] * objects \
			+ (rink_weights[3] * objects if _phase0 == 0 or _phase0 == 1 else 0) \
			+ (rink_weights[4] if net == 0 else 0) \
			+ (rink_weights[5] if net == 2 else 0) + rink_weights[29]
	var before_weights := MwPassApproxWeights.A_REST
	var before: int = before_weights[0] * objects + before_weights[1] * (_puck[0] & 1) \
			+ before_weights[2] * ((_puck[0] >> 1) & 1) + before_weights[3] * _puck[1] \
			+ before_weights[4] * _puck[2] + before_weights[5] * _puck[3] + before_weights[6] * _e \
			+ (before_weights[30 + pi] if pi >= 0 else 0) + before_weights[39]
	for k in range(1, OBJECT_KINDS + 1):
		if kinds[k] != 0:
			ru += rink_weights[5 + k] * kinds[k]
			before += before_weights[6 + k] * kinds[k]
	var after_weights := MwPassApproxWeights.B_REST
	var after_rest: int = (after_weights[0] if s.replay_on != 0 else 0) + (after_weights[1 + pi] if pi >= 0 else 0) \
			+ after_weights[10] * changed + after_weights[11]
	parts[0] = teams
	parts[1] = clock_work
	parts[2] = before
	parts[3] = ru
	parts[4] = handler
	parts[5] = draws
	parts[6] = after_rest
	before += teams + clock_work + int(MwPassCost.A_GLUE) * SCALE
	var after: int = handler + draws + after_rest + int(MwPassCost.B_GLUE) * SCALE
	var m := MwPassCost.MCLK
	return {"before": maxi(before, 0) * m / SCALE, "rink_update": maxi(ru, 0) * m / SCALE,
			"after": maxi(after, 0) * m / SCALE, "rows_words": 2048 if full else 64 * rows,
			"words": 16 * tiles_all + 4 * adds_all}


static func _draw(sec: PackedInt32Array, w: Array) -> int:
	return w[0] * sec[0] + w[1] * sec[1] + w[2] * sec[2] + w[3] * sec[3] + w[4] * sec[4] + w[5] * sec[5] + w[6]


## The tiles the sprite tile cache [param tile_cache] uploads for the sprite
## piece at [param piece] (its first tile word and size; 0: a hit) - both
## TICK RATE models' (plan 40, S8).
static func piece_tiles(rom_bytes: PackedByteArray, tile_cache: MwTileLru, piece: int) -> int:
	var size := rom_bytes[piece + 2]
	return tile_cache.use(MwGfx.u16(rom_bytes, piece + 4), (((size >> 2) & 3) + 1) * ((size & 3) + 1))


## A window op list's counts: [ops, text characters, glyph runs the cache
## [param tile_cache] missed, their tiles, fill cells] - both TICK RATE models'
## (plan 40, S8: [method MwPassLoad.features] too). The glyphs go through
## the cache as the original caches them at once (`$150C6`).
static func window_counts(rom_bytes: PackedByteArray, tile_cache: MwTileLru, ops: Array) -> PackedInt32Array:
	var chars := 0
	var cells := 0
	var runs := 0
	var tiles := 0
	for op in ops:
		match String(op[0]):
			"text", "quote":
				var font := int(op[1])
				var src: Variant = op[5]
				var b: PackedByteArray = MwGfx.rom_string(rom_bytes, int(src)) if src is int else src
				chars += b.size()
				for c in b:
					var g := MwGfx.font_glyph(rom_bytes, font, c)
					if g >= 0:
						var n := piece_tiles(rom_bytes, tile_cache, font + 8 + 6 * g)
						if n > 0:
							runs += 1
							tiles += n
			"text_after":
				var b2: PackedByteArray = MwGfx.rom_string(rom_bytes, int(op[4])) if op[4] is int else op[4]
				chars += b2.size()
			"glyph", "glyph_after":
				chars += 1
			"fill", "box":
				cells += int(op[3]) * int(op[4])
	return PackedInt32Array([ops.size(), chars, runs, tiles, cells])
