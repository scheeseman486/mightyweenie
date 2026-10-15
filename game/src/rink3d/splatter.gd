class_name MwSplatter
extends RefCounted
## Blood and oil on the 3D arena (plan 37, docs/rink3d.md, Splatter; owner:
## painted on it, building up through the whole match). A small model
## stepped with the game's passes ([method step], MwRinkUpdate: live play
## only, beside the benches' life) that reads the game's state and never
## writes it; it paints into its MwSplatterAtlas and keeps the particles in
## flight, and what it is at a pass ([method snapshot]: the atlas, its
## number of operations, the particles) is all the 3D view needs, so a
## replay frame keeping it shows the arena as it was.
## Repeatable: the same seed and the same passes give the same paint.
##
## **Replays** (owner: made again procedurally from a seed): a pass's step
## is two halves - what it reads of the game ([method inputs]: a few
## numbers a player, the corpses, the puck) and what it does with them
## ([method apply]), which needs nothing else. The replay frames keep the
## inputs since the frame before ([method take_inputs], MwReplay3D.frame)
## and the store the seed (MwFullReplay.splat_seed), so a replay makes the
## paint again from them (MwSplatterReplay) - no texels kept. The attract
## demo paints from its own seed, the same every time it runs
## ([constant DEMO_SEED], [method seed_for]).
##
## * **Hits** (a drop in an on-ice player's health, `$BC8`): particles fly
##   off him away from the hitter - the fight's spray `$2154A` for punches
##   and checks, the impale overlay's drops `$3C042` (its pool rows cut off)
##   for weapons, spikes and hazards - more and bigger by the damage; where
##   one lands on the ice it lays one of `$20BD2`'s frames 1-3 flat (1:3 to
##   1:2 by the hit), where it reaches the boards below their top frame 5, 0
##   or 4 upright on them, its bottom on their foot; over the glass it is
##   gone (into the crowd).
## * **Deaths** (state 18): a 1:1 splat under him, four particles, the boards
##   painted when he is near them; then a pool grows from under his corpse
##   (rink object kind 11) to [constant POOL_MAX] px, following it, until the
##   corpse goes.
## * **Streaks:** each skater's feet (two, across his facing - all 256
##   steps; a robot's one wheel) carry paint out of a patch along their own
##   sub-pixel path ([method MwSplatterAtlas.streak]).
## * **The puck** on the ice drags paint out of a patch the same way, one
##   line, no scratches ([method _puck]; owner).
## * Robots (species 2) leave oil (`$3C058`, the fight's grey); skeletons
##   (species 1, and 0's skeleton art) nothing, as in the original; the rest
##   blood.
## * **The ice's detail** (owner: dark and light splotches of ~10% opacity
##   before any paint, from a random seed kept for the replays): at the
##   match's start [constant SPLOTCHES] of the blood art's frames, dark and
##   light, anywhere on the ice, from the seed - those with a straight cut
##   (the geyser's wall frames) with the cut against the rim, on it or under
##   the boards ([constant RIM_OUT]); and the skates scratch it light
##   (owner): sparse going straight, solid in a turn, every other texel when
##   slow.
## Presentation only: nothing of the game's state or random numbers.

## The original's blood art (docs/rink3d.md, Splatter).
const SPRAY := 0x2154A            ## the fight's hit spurt: 3 frames, colour 10
const DROPS := 0x3C042            ## the impale overlay: drops over a pool (colours 1 and 10)
const DROPS_OIL := 0x3C058        ## the robots' (colours 13 and 14)
const GEYSER := 0x20BD2           ## the fight's blood from the ice: 6 frames, colour 10
## The impale drops' rows from here down (frame y) are its pool: cut off.
const DROPS_CLIP := 20
## `$20BD2`'s frames by use (owner): flat on the ice; upright on the boards by
## the hit's size (small, medium, big).
const ICE_FRAMES := [1, 2, 3]
const WALL_FRAMES := [5, 0, 4]
## Ice splats' scale by the hit's tier (rink px a sprite pixel); deaths 1:1.
const ICE_SCALE := [1.0 / 3.0, 0.4, 0.5]
## A hit's tier by its share of full health (`$800000`): small, medium, big.
const TIER_AT := [0.08, 0.25]
const FULL_HEALTH := 0x800000
## Particles: gravity (px a tick^2), launch height above the player's z (his
## chest), the most in flight, the longest one flies (ticks).
const GRAVITY := 0.15
const CHEST := 14.0
const MAX_PARTICLES := 48
const MAX_AGE := 150
## A pool: start and largest radius (rink px), ticks to grow.
const POOL_START := 3.0
const POOL_MAX := 14.0
const POOL_TICKS := 360
## Feet: either side of the foot point across the facing (rink px).
const FOOT := 2.0
## The player states that leave no streaks: killed, fallen through the ice.
const NO_FEET := [0x12, 0x13]
## Players' species (player record +7, low nibble).
const ROBOT := 2
## The ice's detail: splotches laid at the start, their scale range; the
## skates' scratches: density going straight, the turn (radians a pass) that
## makes it solid, the speed (px a tick) under which it is dithered.
const SPLOTCHES := 160
const SPLOTCH_SCALE := Vector2(0.5, 1.5)
const SCRATCH_STRAIGHT := 0.06
const SCRATCH_TURN := 0.35
const SCRATCH_SLOW := 1.0
## Splotches with a straight cut (MwSplatterAtlas.cut_side: the geyser's
## wall frames) go against the ice's rim, the cut on it or up to this many
## px under the boards (owner: the flat side always against the rim or
## hidden beyond it, outside the arena).
const RIM_OUT := 2.0
## The puck's streak (MwSplatterAtlas.streak, as a foot's): its key among the
## feet, and the most it moves in a pass before it counts as a jump (a shot
## is fast).
const PUCK_KEY := "puck"
const PUCK_JUMP := 48.0
## Oil in flight a shade darker than the art's greys (owner): by this many
## of each channel's 8 levels (RomPalette.darker; MwSprites3D, the items'
## "darker").
const OIL_DARKER := 1
## The attract demo's seed (owner: one fixed seed of its own): its paint and
## the ice's detail the same every time it runs ([method seed_for]); any
## other match paints from the crowd's seed.
const DEMO_SEED := 1994
## A pass's inputs ([method inputs]): its head (ticks, a rink entry, the
## players listed), the numbers a player.
const IN_HEAD := 3
const IN_PLAYER := 13

@warning_ignore("shadowed_global_identifier")   # a frozen name (docs/style.md N9): read by name elsewhere
var seed := 0
var ticks := 0
var atlas := MwSplatterAtlas.new()
var _rng := 0
var _next_id := 0
var _parts: Array[Dictionary] = []      # in flight
var _seen := {}                          # "t:slot" -> [record, health, state]
var _feet := {}                          # "t:slot" -> [[last pos, load, kind, phase], ...]
var _pools := {}                         # object slot -> {at, kind, age, r}
var _deaths: Array = []                  # [x, y, kind, tick] waiting for their corpse
var _started := false
var _frames := {}                        # animation -> PackedInt32Array of frame addresses
var _scratches := PackedFloat32Array()   # this pass's skate scratches (MwSplatterAtlas.skates)
var _pending: Array[PackedInt32Array] = []   # the passes' inputs since the last replay frame took them


func _init(seed_ := 0) -> void:
	seed = seed_
	_rng = MwSeed.knuth(seed_, 0x9E3779B9) & 0x7FFFFFFF
	if _rng == 0:
		_rng = 1
	_splotches()


## The ice's detail at the match's start: [constant SPLOTCHES] frames of the
## original's blood art (the fight's spray and blood from the ice, the impale
## drops), half dark, half light, turned, mirrored and sized at random from
## the seed, laid anywhere on the ice (the atlas's first operations, so a
## replay has them too).
func _splotches() -> void:
	var frames := PackedInt32Array()
	for anim in [GEYSER, SPRAY, DROPS]:
		frames.append_array(_frames_of(anim))
	if frames.is_empty():
		return
	var total := float(MwSplatterAtlas.layout().get("total", 0.0))
	var n := 0
	var tries := 0
	while n < SPLOTCHES and tries < SPLOTCHES * 4:
		tries += 1
		var frame := frames[_below(frames.size())]
		var kind := MwSplatterAtlas.DARK if n % 2 == 0 else MwSplatterAtlas.LIGHT
		var scale := lerpf(SPLOTCH_SCALE.x, SPLOTCH_SCALE.y, _unit())
		var flip := _below(2) == 0
		if not MwSplatterAtlas.cut_side(frame).is_empty():
			# its straight cut against the rim, on it or under the boards (owner)
			var at := MwSplatterAtlas.against_rim(frame, _unit() * total, _unit() * RIM_OUT, scale, flip)
			var point: Vector2 = at[0]
			atlas.ice_stamp(kind, frame, point.x, point.y, at[1], scale, flip, MwSplatterAtlas.DETAIL)
			n += 1
			continue
		var x := -MwRinkShape.BOARD.x + _unit() * (2.0 * MwRinkShape.BOARD.x)    # inside the straight boards
		var y := -MwRinkShape.BOARD.y + _unit() * (2.0 * MwRinkShape.BOARD.y)
		if not MwSplatterAtlas.on_ice(x, y):
			continue
		atlas.ice_stamp(kind, frame, x, y, _unit() * TAU, scale, flip, MwSplatterAtlas.DETAIL)
		n += 1


## The seed of a match's paint: the attract demo's own ([constant
## DEMO_SEED]: the same every time it runs), else the match's crowd's
## ([param crowd_seed], MwCrowdLife.crowd_seed - the same on every machine
## online).
static func seed_for(attract: bool, crowd_seed: int) -> int:
	return DEMO_SEED if attract else crowd_seed


## A pass of [param e] ticks of [param sim]'s match (its state read only):
## its inputs read ([method inputs]), kept for the replay frames ([method
## take_inputs]) and applied.
func step(e: int, sim: MwRinkSim) -> void:
	var rec := inputs(e, sim.s, sim.rom)
	_pending.append(rec)
	apply(rec)


## The inputs of the passes stepped since the last call (MwReplay3D.frame:
## each replay frame keeps those since the frame before), oldest first.
func take_inputs() -> Array[PackedInt32Array]:
	var out := _pending
	_pending = []
	return out


## What a pass of [param e] ticks reads of match [param s] ([param rom]: the
## players' species), as numbers: [e, a rink entry (1), the players listed
## (both teams' lists in order)], then each player ([constant IN_PLAYER]):
## [team * 256 + slot, on the ice (1), record, paint (CLEAR / BLOOD / OIL)
## + 16 for a robot, health (bit 31 masked), state, x, y, z (24.8), knock-back
## x, y, facing, his `+$3A` victim (the index of a player listed; -1 none)];
## then the corpses (rink objects kind 11): their number and each one's
## [object slot, x, y]; then the puck: [hidden (1), x, y, z].
static func inputs(e: int, s: MwRinkState, rom: PackedByteArray) -> PackedInt32Array:
	var players: Array[MwRinkState.Player] = []
	var team_of := PackedInt32Array()
	for t in 2:
		for p: MwRinkState.Player in s.teams[t].players:
			players.append(p)
			team_of.append(t)
	var out := PackedInt32Array([e, 1 if s.first_pass != 0 else 0, players.size()])
	for k in players.size():
		var p := players[k]
		var t := team_of[k]
		if not p.present:
			out.append_array(PackedInt32Array([t * 256 + p.slot, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1]))
			continue
		var team := s.teams[t]
		var health := int(team.health[p.slot]) & 0x7FFFFFFF if p.slot < team.health.size() else 0
		var paint := _kind(rom, p) | (16 if _species(rom, p) == ROBOT else 0)
		out.append_array(PackedInt32Array([t * 256 + p.slot, 1, p.record, paint, health, p.state,
				p.motion.pos[0], p.motion.pos[1], p.motion.pos[2], p.motion.vel[0], p.motion.vel[1], p.angle,
				players.find(p.victim) if p.victim is MwRinkState.Player else -1]))
	var corpses := PackedInt32Array()
	for i in s.objects.size():
		var rink_object := s.objects[i]
		if rink_object.kind == MwRinkState.KIND_CORPSE:
			corpses.append_array(PackedInt32Array([i, rink_object.motion.pos[0], rink_object.motion.pos[1]]))
	out.append(corpses.size() / 3)
	out.append_array(corpses)
	var pk := s.puck
	out.append_array(PackedInt32Array([1 if pk.flags & MwRinkState.Puck.HIDDEN else 0,
			pk.motion.pos[0], pk.motion.pos[1], pk.motion.pos[2]]))
	return out


## A pass from its inputs [param rec] ([method inputs]): live and in a
## replay alike, so both paint the same.
func apply(rec: PackedInt32Array) -> void:
	atlas.seek(atlas.count())           # every operation shown (a replay may have rewound it)
	var e := rec[0]
	ticks += e
	var entry := rec[1] != 0 or not _started
	_started = true
	if entry:
		# a rink entry (a faceoff, a period, back from a screen between plays):
		# positions jump and health may have changed off the rink - only look
		_parts.clear()
		_feet.clear()
	_scratches = PackedFloat32Array()
	var n := rec[2]
	for i in n:
		_player(rec, i, e, entry)
	var at := IN_HEAD + n * IN_PLAYER       # the corpses
	_puck(rec, at + 1 + rec[at] * 3)       # (paint only: no scratches)
	atlas.skates(_scratches)                # the pass's skate scratches, one operation
	_corpses(rec, at, e)
	_fly(e)


## What the 3D view needs at this pass: {atlas, ops (its operations so far),
## parts (the particles: [key, frame, attr, x, y, z, ox, oy, clip, oil]
## each), seed}.
func snapshot() -> Dictionary:
	var parts := []
	for particle in _parts:
		var f := _particle_frame(particle)
		parts.append([int(particle["id"]), f[0], f[1], particle["x"], particle["y"], particle["z"], f[2], f[3], f[4],
				1 if int(particle["kind"]) == MwSplatterAtlas.OIL else 0])
	return {"atlas": atlas, "ops": atlas.count(), "parts": parts, "seed": seed}


## The particles of [param snap] as 3D items (MwRinkDraw3D.items: standing
## billboards at their points, keyed so the view moves them between passes).
static func items(snap: Dictionary) -> Array:
	var out := []
	for part: Array in snap.get("parts", []):
		var it := {"frame": int(part[1]), "attr": int(part[2]), "depth": 0, "place": MwRinkDraw3D.UPRIGHT,
				"at": Vector3(part[3], part[4], part[5]), "offset": Vector2i(int(part[6]), int(part[7])), "order": 0,
				"key": "splat/%d" % int(part[0])}
		if int(part[8]) < 0x7FFF:
			it["clip"] = int(part[8])
		if part.size() > 9 and int(part[9]) != 0:
			it["darker"] = OIL_DARKER        # oil: a shade darker in flight (owner)
		out.append(it)
	return out


# --- players ------------------------------------------------------------------------------

## Player [param i] of the pass's inputs [param rec] ([method inputs]).
func _player(rec: PackedInt32Array, i: int, e: int, entry: bool) -> void:
	var o := IN_HEAD + i * IN_PLAYER
	var key := "%d:%d" % [rec[o] >> 8, rec[o] & 0xFF]
	if rec[o + 1] == 0:
		_seen.erase(key)
		_feet.erase(key)
		return
	var record := rec[o + 2]
	var kind := rec[o + 3] & 0x0F
	var health := rec[o + 4]
	var state := rec[o + 5]
	var was: Array = _seen.get(key, [])
	_seen[key] = [record, health, state]
	var at := Vector3(rec[o + 6] / 256.0, rec[o + 7] / 256.0, rec[o + 8] / 256.0)
	if not entry and not was.is_empty() and int(was[0]) == record and kind != MwSplatterAtlas.CLEAR:
		if state == 0x12 and int(was[2]) != 0x12:
			_death(rec, i, at, kind)
		elif health < int(was[1]):
			_hit(rec, i, at, kind, float(int(was[1]) - health) / FULL_HEALTH)
	elif state == 0x12 and (was.is_empty() or int(was[2]) != 0x12):
		_deaths.append([at.x, at.y, kind, ticks])   # (a skeleton's: no pool either)
	_streaks(rec, i, key, at, e)


## Player [param p]'s species (player record +7, low nibble; the record
## his animations come from), -1 none.
static func _species(rom: PackedByteArray, p: MwRinkState.Player) -> int:
	var rec := p.original if p.original != 0 else p.record
	if rec <= 0 or rec + 7 >= rom.size():
		return -1
	return rom[rec + 7] & 0x0F


## The paint player [param p] leaves: CLEAR (skeletons), OIL (robots), BLOOD.
static func _kind(rom: PackedByteArray, p: MwRinkState.Player) -> int:
	var species := _species(rom, p)
	if species < 0:
		return MwSplatterAtlas.BLOOD
	if species == 0 or species == 1:
		return MwSplatterAtlas.CLEAR
	return MwSplatterAtlas.OIL if species == ROBOT else MwSplatterAtlas.BLOOD


## The way the blood flies from player [param i] of the inputs [param rec]:
## away from the player hitting him (whose victim he is), else along his
## knock-back, else anywhere.
func _away(rec: PackedInt32Array, i: int, at: Vector3) -> Dictionary:
	for j in rec[2]:
		var q := IN_HEAD + j * IN_PLAYER
		if j != i and rec[q + 1] != 0 and rec[q + 12] == i:
			var d := Vector2(at.x - rec[q + 6] / 256.0, at.y - rec[q + 7] / 256.0)
			var weapon := rec[q + 5] == MwRinkState.Player.STATE_WEAPON
			if d.length() > 0.5:
				return {"dir": d.normalized(), "weapon": weapon}
			return {"dir": _random_dir(), "weapon": weapon}
	var o := IN_HEAD + i * IN_PLAYER
	var v := Vector2(rec[o + 9], rec[o + 10])
	var hazard := true      # no hitter: a weapon, spikes, a mine, the puck... the drops
	if v.length() > 1.0:
		return {"dir": v.normalized(), "weapon": hazard}
	return {"dir": _random_dir(), "weapon": hazard}


func _hit(rec: PackedInt32Array, i: int, at: Vector3, kind: int, share: float) -> void:
	var tier := 0 if share < TIER_AT[0] else (1 if share < TIER_AT[1] else 2)
	var way := _away(rec, i, at)
	var impaled := rec[IN_HEAD + i * IN_PLAYER + 5] == MwRinkState.Player.STATE_IMPALED
	var style := 1 if bool(way["weapon"]) or impaled else 0
	for n in tier + 1:
		_launch(at, way["dir"].rotated(_spread(0.5)), kind, style, tier, 1.0 + 0.25 * tier)


func _death(rec: PackedInt32Array, i: int, at: Vector3, kind: int) -> void:
	var way := _away(rec, i, at)
	var dir: Vector2 = way["dir"]
	atlas.ice_stamp(kind, _frame(GEYSER, ICE_FRAMES[1 + _below(2)]), at.x, at.y, dir.angle(), 1.0, _below(2) == 0)
	for n in 4:
		_launch(at, dir.rotated(_spread(1.1)), kind, n % 2, 2, 0.9)
	var w := MwSplatterAtlas.wall_s(Vector2(at.x, at.y))
	if -w.y < 30.0:
		atlas.wall_stamp(kind, _frame(GEYSER, WALL_FRAMES[2]), w.x, 1.0, _below(2) == 0)
	_deaths.append([at.x, at.y, kind, ticks])


# --- particles ---------------------------------------------------------------------------

## A particle from [param at] along [param dir]: [param style] 0 the spray,
## 1 the drops; [param tier] its splats' size; [param speed] a factor.
func _launch(at: Vector3, dir: Vector2, kind: int, style: int, tier: int, speed: float) -> void:
	if _parts.size() >= MAX_PARTICLES:
		return
	var h := (1.6 + _unit() * 1.2) * speed if style == 0 else (0.8 + _unit() * 1.2) * speed
	var vz := 1.2 + _unit() * 1.2 if style == 0 else 0.8 + _unit() * 1.2
	_parts.append({"id": _next_id, "x": at.x, "y": at.y, "z": at.z + CHEST, "vx": dir.x * h, "vy": dir.y * h,
			"vz": vz, "kind": kind, "style": style, "tier": tier, "age": 0, "flip": dir.x < 0.0})
	_next_id += 1


## Moves the particles [param e] ticks: landing on the ice lays a splat,
## reaching the boards below their top paints them; over them, gone.
func _fly(e: int) -> void:
	var keep: Array[Dictionary] = []
	for particle in _parts:
		var x0: float = particle["x"]
		var y0: float = particle["y"]
		particle["x"] = x0 + particle["vx"] * e
		particle["y"] = y0 + particle["vy"] * e
		particle["z"] = particle["z"] + particle["vz"] * e - 0.5 * GRAVITY * e * e
		particle["vz"] = particle["vz"] - GRAVITY * e
		particle["age"] = int(particle["age"]) + e
		var x: float = particle["x"]
		var y: float = particle["y"]
		var z: float = particle["z"]
		var kind: int = particle["kind"]
		var tier: int = particle["tier"]
		if not MwSplatterAtlas.on_ice(x, y):
			var w := MwSplatterAtlas.wall_s(Vector2(x, y))
			if MwSplatterAtlas.on_ice(x0, y0) and z < MwSplatterAtlas.wall_top(w.x):
				atlas.wall_stamp(kind, _frame(GEYSER, WALL_FRAMES[tier]), w.x, 1.0, _below(2) == 0)
				continue
			if w.y > 24.0 or z <= 0.0:
				continue                    # over the boards, into the crowd
			keep.append(particle)
			continue
		if z <= 0.0:
			var d := Vector2(particle["vx"], particle["vy"])
			var f := _frame(GEYSER, ICE_FRAMES[_below(3)] if tier > 0 else ICE_FRAMES[0])
			atlas.ice_stamp(kind, f, x, y, d.angle() if d.length() > 0.01 else 0.0, ICE_SCALE[tier], _below(2) == 0)
			continue
		if int(particle["age"]) < MAX_AGE:
			keep.append(particle)
	_parts = keep


## A particle's frame now: [frame, attr, offset x, offset y, clip] - centred
## on its point (the drawings' own travel taken out: it flies itself).
func _particle_frame(particle: Dictionary) -> Array:
	var oil := int(particle["kind"]) == MwSplatterAtlas.OIL
	var flip := bool(particle["flip"])
	var age: int = particle["age"]
	var frame: int
	var attr := 0x20
	var clip := 0x7FFF
	if int(particle["style"]) == 0:
		var fs := _frames_of(SPRAY)
		frame = fs[mini(fs.size() - 1, int(age * 51 / 256.0))]   # the record's speed
		if oil:
			attr = 0x60                 # line 3: its colour 10 is grey (`$888`), the oil
	else:
		var fs := _frames_of(DROPS_OIL if oil else DROPS)
		frame = fs[int(age * 43 / 256.0) % fs.size()]
		clip = DROPS_CLIP
	var c := _centre(frame, clip)
	if flip:
		attr |= 0x08
		c.x = -c.x
	return [frame, attr, int(round(-c.x)), int(round(-c.y)), clip]


## The middle of a frame's pixels (above [param clip]) from its point (cached).
static var _centres := {}


func _centre(frame: int, clip: int) -> Vector2:
	var ck := Vector2i(frame, clip)
	MwSplatterAtlas.cache_lock.lock()             # (a recording's paint is made on a worker thread)
	if not _centres.has(ck):
		_centres[ck] = _find_centre(frame, clip)
	var c: Vector2 = _centres[ck]
	MwSplatterAtlas.cache_lock.unlock()
	return c


static func _find_centre(frame: int, clip: int) -> Vector2:
	var m := MwSplatterAtlas.mask(frame)
	if m.is_empty():
		return Vector2.ZERO
	var w: int = m["w"]
	var h: int = m["h"]
	var px: PackedByteArray = m["px"]
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	for y in h:
		if y - int(m["oy"]) >= clip:
			break
		for x in w:
			if px[y * w + x] != 0:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return Vector2.ZERO
	return Vector2((lo.x + hi.x + 1) / 2.0 - int(m["ox"]), (lo.y + hi.y + 1) / 2.0 - int(m["oy"]))


# --- pools ---------------------------------------------------------------------------------

## Corpses (rink objects kind 11; the inputs [param rec] list them from
## [param from]): a pool grows from under each, of its player's paint,
## following it, until it goes.
func _corpses(rec: PackedInt32Array, from: int, e: int) -> void:
	var here := {}
	for c in rec[from]:
		here[rec[from + 1 + 3 * c]] = true
	for slot: int in _pools.keys():
		if not here.has(slot):
			_pools.erase(slot)              # (gone: no corpse there now)
	for c in rec[from]:
		var o := from + 1 + 3 * c
		var i := rec[o]
		var at := Vector2(rec[o + 1] / 256.0, rec[o + 2] / 256.0)
		if not _pools.has(i):
			_pools[i] = {"at": at, "kind": _death_kind(at), "age": 0, "r": 0.0,
					"shape": _below(0x1000000)}
		var pl: Dictionary = _pools[i]
		if int(pl["kind"]) == MwSplatterAtlas.CLEAR:
			continue
		pl["age"] = int(pl["age"]) + e
		var r := minf(POOL_MAX, POOL_START + (POOL_MAX - POOL_START) * float(pl["age"]) / POOL_TICKS)
		var moved: bool = (pl["at"] as Vector2).distance_to(at) >= 1.0
		if floor(r) > floor(float(pl["r"])) or moved:
			atlas.pool(pl["kind"], at.x, at.y, floor(r), pl["shape"])
			pl["r"] = r
			pl["at"] = at


## The paint of the death nearest to a new corpse at [param at] (taken).
func _death_kind(at: Vector2) -> int:
	var best := -1
	var dist := 48.0
	for i in _deaths.size():
		var d := at.distance_to(Vector2(_deaths[i][0], _deaths[i][1]))
		if d < dist:
			dist = d
			best = i
	if best < 0:
		return MwSplatterAtlas.CLEAR
	var kind: int = _deaths[best][2]
	_deaths.remove_at(best)
	# deaths waiting too long (no corpse came: a full object list) are dropped
	_deaths = _deaths.filter(func(d: Array) -> bool: return ticks - int(d[3]) < 600)
	return kind


# --- streaks -------------------------------------------------------------------------------

## The feet of player [param who] of the inputs [param rec] on the ice
## carry paint along their paths: two across his facing (`+$73`, 256 steps),
## or a robot's one wheel.
func _streaks(rec: PackedInt32Array, who: int, key: String, at: Vector3, e: int) -> void:
	var o := IN_HEAD + who * IN_PLAYER
	if at.z > 0.0 or rec[o + 5] in NO_FEET or not MwSplatterAtlas.on_ice(at.x, at.y):
		_feet.erase(key)
		return
	var c := Vector2(at.x, at.y)
	var points: Array[Vector2] = []
	if rec[o + 3] & 16:                     # a robot
		points.append(c)
	else:
		var a := rec[o + 11] * TAU / 256.0
		var across := Vector2(-sin(a), cos(a)) * FOOT
		points.append(c + across)
		points.append(c - across)
	var was: Array = _feet.get(key, [])
	var now: Array = []
	for i in points.size():
		# a foot: [last point, load, kind, phase, wet, last way (a unit vector or zero)]
		var f: Array = was[i] if i < was.size() else [points[i], 0, MwSplatterAtlas.CLEAR, 0, 0, Vector2.ZERO]
		var last: Vector2 = f[0]
		if last.distance_to(points[i]) > 24.0:      # a jump (a reset): no mark across it
			f = [points[i], 0, MwSplatterAtlas.CLEAR, 0, 0, Vector2.ZERO]
			last = points[i]
		var r := atlas.streak(int(f[2]), int(f[1]), int(f[3]), int(f[4]), last, points[i])
		var way := _scratch(last, points[i], f[5], e, i)
		now.append([points[i], r[0], r[1], r[2], r[3], way])
	_feet[key] = now


## The puck on the ice drags paint out of a patch along its way, as a foot
## does (owner: the blood and oil only, no scratches); not while it is in
## the air or hidden. Its inputs from [param from] of [param rec].
func _puck(rec: PackedInt32Array, from: int) -> void:
	var at := Vector3(rec[from + 1] / 256.0, rec[from + 2] / 256.0, rec[from + 3] / 256.0)
	if rec[from] != 0 or at.z > 0.0 or not MwSplatterAtlas.on_ice(at.x, at.y):
		_feet.erase(PUCK_KEY)
		return
	var point := Vector2(at.x, at.y)
	var was: Array = _feet.get(PUCK_KEY, [])
	var f: Array = was[0] if not was.is_empty() else [point, 0, MwSplatterAtlas.CLEAR, 0, 0, Vector2.ZERO]
	var last: Vector2 = f[0]
	if last.distance_to(point) > PUCK_JUMP:            # a jump (a faceoff, a reset): no mark across it
		f = [point, 0, MwSplatterAtlas.CLEAR, 0, 0, Vector2.ZERO]
		last = point
	var r := atlas.streak(int(f[2]), int(f[1]), int(f[3]), int(f[4]), last, point)
	_feet[PUCK_KEY] = [[point, r[0], r[1], r[2], r[3], Vector2.ZERO]]


## A foot's scratch from [param a] to [param b] this pass ([param e] ticks;
## [param was] the way it went last pass): the density by how much it turned,
## dithered when slow. Returns the way it went (zero: standing).
func _scratch(a: Vector2, b: Vector2, was: Vector2, e: int, foot: int) -> Vector2:
	var d := b - a
	var length := d.length()
	if length < 0.05:
		return Vector2.ZERO
	var way := d / length
	var turn := absf(was.angle_to(way)) if was != Vector2.ZERO else 0.0
	var density := clampf(SCRATCH_STRAIGHT + turn / SCRATCH_TURN, 0.0, 1.0)
	var slow := length / maxi(e, 1) < SCRATCH_SLOW
	_scratches.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, density, 1.0 if slow else 0.0,
			float((ticks * 32 + _scratches.size() / 7 + foot) & 0xFFFFFF)]))
	return way


# --- helpers -------------------------------------------------------------------------------

## The frame addresses of animation [param anim], in order.
func _frames_of(anim: int) -> PackedInt32Array:
	if not _frames.has(anim):
		var out := PackedInt32Array()
		if MwRom.available():
			var rom := MwRom.data()
			var a := MwGfx.animation(rom, anim)
			for o in MwGfx.anim_offsets(rom, a, 0):
				out.append(int(a["frames"]) + o)
		_frames[anim] = out
	return _frames[anim]


func _frame(anim: int, n: int) -> int:
	var fs := _frames_of(anim)
	return fs[clampi(n, 0, fs.size() - 1)] if not fs.is_empty() else 0


func _next() -> int:
	_rng = (_rng * 1103515245 + 12345) & 0x7FFFFFFF
	return _rng >> 8


func _below(n: int) -> int:
	return _next() % maxi(n, 1)


func _unit() -> float:
	return float(_next() & 0xFFFF) / 65536.0


func _spread(width: float) -> float:
	return (_unit() - 0.5) * width


func _random_dir() -> Vector2:
	return Vector2.RIGHT.rotated(_unit() * TAU)
