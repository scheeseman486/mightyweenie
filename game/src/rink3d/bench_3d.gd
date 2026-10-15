class_name MwBench3D
extends RefCounted
## The benches and penalty boxes in 3D (plan 32, docs/rink3d.md, Benches):
## where their places are, the ways in and out through the arches (the dark
## openings in the stands behind them), and the frames that draw what
## MwBenchLife's snapshot says, as items like the players'
## (MwRinkDraw3D.items: billboards in their team's colours turning with the
## camera, MwRinkFacing3D). Static; presentation only.
##
## As in real hockey both benches are on one side, the west (the 2D view's
## left: the rink picture's two pens, |y| 40-160, and the recess between
## them out to x -256, split by a bar at y 0), the penalty boxes on the
## other, the east, with Satan between them. Each team keeps the
## bench on the half it defends in the first period (team A south, team B
## north) all match (owner), its box on the same half.
##
## Places on a team's bench ([method place_at]): 15 in the pen, in two
## staggered rows along the boards from end to end (0-14, nearest the
## recess first), and 6 in the
## recess by the way out ([constant RECESS]-), where the players next up
## wait (MwBenchLife); the box's three seats ([constant BOX]-, the box's
## entries); the arches' far sides ([constant WEST_EXIT], [constant
## EAST_EXIT]), in the dark. A figure fades into the dark as he walks into
## an arch ([method shade_at]), and the game's own players coming on from
## the original's bench door (265, 10), in the east arch, come out of it
## ([method arch_shade]).

## Each team's side of the centre line (rink y sign): A south, B north.
const TEAM_SIGN := [1, -1]
## Place ids ([method place_at]).
const PEN := 0                 ## 0..14: the pen
const PEN_PLACES := 15
const RECESS := 20             ## 20..25: by the way out
const RECESS_PLACES := 6
const BOX := 30                ## 30..32: the box's seats (its entries 0-2)
const WEST_EXIT := 40          ## the west arch's dark (the bench's way out)
const EAST_EXIT := 41          ## the east arch's dark (the box's)
## The pen's rows (rink x): along the boards and behind; along y the
## front row's 8 from the recess end (|y| 46) to the far end (156), the back
## row's 7 between them (owner: the pens filled to their ends).
const PEN_X := [-196.0, -208.0]
const PEN_Y0 := 46.0
const PEN_STEP := 110.0 / 7.0
## The recess spots: x by column (nearest the way out first), |y| by row.
const RECESS_X := [-230.0, -214.0, -198.0]
const RECESS_Y := [12.0, 28.0]
## The box's seats (x, |y| by entry), spread over it.
const BOX_X := 201.0
const BOX_Y := [60.0, 100.0, 140.0]
## Where the ways round the pens' corners turn (|y|): the pens open into
## the recess (west) and the penalty boxes (east) at |y| 40.
const TURN_Y := 32.0
## The exits, deep in the arches' dark (x, |y|).
const WEST_OUT := Vector2(-270.0, 20.0)
const EAST_OUT := Vector2(270.0, 14.0)
## The arches' dark: a figure is lit inside these x and black beyond these
## (the west: the rink picture's edge at -256; the east: the original's
## door at 265 is black).
const WEST_LIT := -232.0
const WEST_DARK := -262.0
const EAST_LIT := 238.0
const EAST_DARK := 264.0
## The hallways' walls and glass (owner, 2026-10-11: the hallways run on under
## the stands, about twice as long - to x -344 / 344 - and fade out more
## gently; rink3d_arch, MwRinkModel.set_arch_parameters): lit to x (the
## arches' lit lines), black at y (the walls' end), smoothstep between, within
## ARCH_HALF_Y of the centre line (their walls at |y| 40). The figures in them
## keep their own, shorter fade above: the game's players come on at x 265,
## which must be dark.
const HALL_WEST := Vector2(WEST_LIT, -344.0)
const HALL_EAST := Vector2(EAST_LIT, 344.0)
const ARCH_HALF_Y := 40.5
## The game's players' animation ids the benches use (MwPlayerAnims).
const ANIM_SKATE := 0          ## frame 0 stopped: standing
const ANIM_FIDGET := 22        ## a skater's shuffle (a loop)
const ANIM_CELEBRATE := 23     ## 23-25: the celebrations (once)
const ANIM_BOX := 0x1C         ## the box's animation (the penalty scoreboard's)
const GOALIE_FIDGET := 0       ## a goalie's skate loop
const GOALIE_CHEER := 9        ## a goalie's stick raised (the slash)
## How long a team's bench celebrates its goal, sulks at the other's, cheers
## a kill (ticks).
const CELEBRATE_TICKS := 480
const KILL_TICKS := 120
## The sprite attr of each team's players (MwRinkState.Team.attr).
const TEAM_ATTR := [0x20, 0x40]
## Upright items' depth word (unused by the 3D view for standing frames).
const DEPTH := 0x80
## Each figure's depth bias towards the camera (m, a step a roster slot,
## team B's after team A's): figures side by side the same distance from
## the camera overlap at the same depth, which flickers (owner:
## z-fighting); with it the one with the higher slot is always in front.
## 48 steps stay under 2 px.
const BIAS_STEP := 0.002


## The walls round the benches and the boxes (rink px: [Vector4(x0, y0,
## x1, y1), top z]), as the rink model has them (the pens' glass included,
## to its panes' top - the tall glass's, owner 2026-10-11: the kick strip and
## tile to 18, the glass to 49, its pointed tips to 55 - not the boxes' spear
## fence: see-through; the hallways' walls out to x -344 / 344, where they
## run on under the stands): rink3d_billboard's BARRIER list, the same. A
## figure's pixels past one from his feet and below its top, or more than
## [constant OVERHANG] px past it, are not drawn ([method past_barrier]).
const BARRIERS := [
	[Vector4(-185, 160, -216, 160), 49.0],   # west: the pens' end walls
	[Vector4(-185, -160, -216, -160), 49.0],
	[Vector4(-216, 40, -216, 160), 49.0],   # their back walls
	[Vector4(-216, -40, -216, -160), 49.0],
	[Vector4(-216, 40, -344, 40), 49.0],   # the hallway's walls
	[Vector4(-216, -40, -344, -40), 49.0],
	[Vector4(-185, -160, -185, 160), 19.0],   # the low boards in front of the benches
	[Vector4(-185, 0, -344, 0), 16.0],   # the bar between the benches
	[Vector4(185, 160, 216, 160), 49.0],   # east: the boxes' end walls
	[Vector4(185, -160, 216, -160), 49.0],
	[Vector4(216, 40, 216, 160), 49.0],   # their back walls
	[Vector4(216, -40, 216, -160), 49.0],
	[Vector4(216, 40, 344, 40), 49.0],   # the hallway's walls
	[Vector4(216, -40, 344, -40), 49.0],
	[Vector4(185, 128, 185, 160), 19.0],   # the boards beyond the fence (their pad)
	[Vector4(185, -160, 185, -128), 19.0],
]
## How far (px) a figure may hang over a wall (owner: the robots hung over
## too far).
const OVERHANG := 4.0


## Rink point (px: x, y) of place [param place] of [param team]'s side.
static func place_at(team: int, place: int) -> Vector2:
	var sy: float = TEAM_SIGN[team]
	if place >= PEN and place < PEN + PEN_PLACES:
		var k := place - PEN
		var row := k % 2
		var n := k / 2
		return Vector2(PEN_X[row], sy * (PEN_Y0 + PEN_STEP * n + PEN_STEP * 0.5 * row))
	if place >= RECESS and place < RECESS + RECESS_PLACES:
		var k := place - RECESS
		return Vector2(RECESS_X[k / 2], sy * RECESS_Y[k % 2])
	if place >= BOX and place < BOX + 3:
		return Vector2(BOX_X, sy * BOX_Y[place - BOX])
	if place == EAST_EXIT:
		return Vector2(EAST_OUT.x, sy * EAST_OUT.y)
	return Vector2(WEST_OUT.x, sy * WEST_OUT.y)


## The way (rink px, a polyline) from [param from] to [param to] on
## [param team]'s side: round the corner where a pen opens into the recess
## or the penalty boxes (|y| 40), else straight.
static func route(team: int, from: Vector2, to: Vector2) -> PackedVector2Array:
	var sy: float = TEAM_SIGN[team]
	var out := PackedVector2Array([from])
	var a_in := absf(from.y) > 40.0
	var b_in := absf(to.y) > 40.0
	if a_in and not b_in:
		out.append(Vector2(from.x, sy * TURN_Y))
	elif b_in and not a_in:
		out.append(Vector2(to.x, sy * TURN_Y))
	out.append(to)
	return out


## The length of [param path] (px).
static func length(path: PackedVector2Array) -> float:
	var d := 0.0
	for i in path.size() - 1:
		d += path[i].distance_to(path[i + 1])
	return d


## The point [param fraction] (0..1) of the way along [param path], and the way's
## direction there: [point, direction].
static func along(path: PackedVector2Array, fraction: float) -> Array:
	var total := length(path)
	var want := clampf(fraction, 0.0, 1.0) * total
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if want <= seg or i == path.size() - 2:
			var d := (path[i + 1] - path[i]).normalized() if seg > 0.0 else Vector2.ZERO
			return [path[i] + d * minf(want, seg), d]
		want -= seg
	return [path[-1], Vector2.ZERO]


## How lit a figure at rink x [param x] is: 1 outside the arches, fading to
## 0 (black, in their dark) as he goes in.
static func shade_at(x: float) -> float:
	if x < WEST_LIT:
		return clampf((x - WEST_DARK) / (WEST_LIT - WEST_DARK), 0.0, 1.0)
	if x > EAST_LIT:
		return clampf((EAST_DARK - x) / (EAST_DARK - EAST_LIT), 0.0, 1.0)
	return 1.0


## [param pass_items] (the pass's, MwRinkDraw3D) with the game's players in the
## east arch shaded ([method shade_at]): a substitute or a player out of
## the box comes on from the original's bench door (265, 10), in the arch's
## dark, and comes out of it as he skates on. Items are copied when changed.
static func arch_shade(pass_items: Array) -> Array:
	var out := []
	for it: Dictionary in pass_items:
		var key: String = it.get("key", "")
		if key.begins_with("t") and int(it["place"]) != MwRinkDraw3D.SCREEN:
			var at: Vector3 = it["at"]
			var k := shade_at(at.x)
			if k < 1.0:
				it = it.duplicate()
				it["shade"] = k
		out.append(it)
	return out


## Whether a billboard pixel at rink point [param point] (on the upright plane
## at the feet, facing the camera) of a figure standing at [param feet]
## outside the boards lies past a wall from them and below its top (or more
## than [constant OVERHANG] px past it), so is not drawn (rink3d_billboard's
## past_barrier: owner, clipped at the barrier but not where they hang over).
static func past_barrier(feet: Vector2, point: Vector3) -> bool:
	for b: Array in BARRIERS:
		var w: Vector4 = b[0]
		var c := Vector2(w.x, w.y)
		var d := Vector2(w.z, w.w)
		if _crosses(feet, Vector2(point.x, point.y), c, d):
			var wall_direction := (d - c).normalized()
			var past := absf(wall_direction.x * (point.y - c.y) - wall_direction.y * (point.x - c.x))
			if point.z < float(b[1]) or past > OVERHANG:
				return true
	return false


static func _crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var r := b - a
	var barrier := d - c
	var den := r.x * barrier.y - r.y * barrier.x
	if absf(den) < 1e-6:
		return false
	var point_2 := c - a
	var t := (point_2.x * barrier.y - point_2.y * barrier.x) / den
	var u := (point_2.x * r.y - point_2.y * r.x) / den
	return t > 0.0 and t < 1.0 and u >= 0.0 and u <= 1.0


## A fixed random number in [0, 1) for a figure ([param team], roster
## [param slot]) and [param salt], in the match's [param seed].
static func rand(seed_: int, team: int, slot: int, salt: int) -> float:
	var x := (seed_ * 0x9E3779B1 + team * 0x85EBCA77 + slot * 0xC2B2AE3D + salt * 0x27D4EB2F) & 0xFFFFFFFF
	x = ((x ^ (x >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	x = ((x ^ (x >> 12)) * 0x297A2D39) & 0xFFFFFFFF
	x = x ^ (x >> 15)
	return float(x & 0xFFFFFF) / 16777216.0


## Whether player record [param record] is a goalie (his species uses the
## goalies' animations: 4, 5, 6).
static func goalie(rom: PackedByteArray, record: int) -> bool:
	return MwPlayerAnims.species(rom, record) in [4, 5, 6]


## The frame of animation [param anim] shown [param elapsed] ticks after it
## started (as anim_advance plays it: forward, reversed or ping-pong, looping
## or holding its last frame).
static func frame_at(rom: PackedByteArray, anim: int, elapsed: float) -> int:
	var speed := MwGfx.u16(rom, anim)
	var flags := rom[anim + 2]
	var count := maxi(rom[anim + 3], 1)
	var n := floori(maxf(elapsed, 0.0) * speed / 256.0)
	var mode := flags & 7
	var cycle_frames := count if mode != 3 else maxi(2 * (count - 1), 1)
	if flags & MwAnimState.LOOP:
		n = n % cycle_frames
	else:
		n = mini(n, cycle_frames - 1)
	if mode == 2:
		n = count - 1 - n
	elif mode == 3 and n >= count:
		n = cycle_frames - n
	return clampi(n, 0, count - 1)


## How long animation [param anim] plays once (ticks).
static func anim_ticks(rom: PackedByteArray, anim: int) -> float:
	var speed := maxi(MwGfx.u16(rom, anim), 1)
	return float(maxi(rom[anim + 3], 1)) * 256.0 / speed


## The variant (0-7, k x 45 deg clockwise from north) facing [param d]
## (rink x, y).
static func variant_of(d: Vector2) -> int:
	return posmod(roundi(atan2(d.x, -d.y) / (PI / 4.0)), 8)


## The frames that draw the benches and boxes as [param snap] says
## (MwBenchLife.snapshot; the 3D view makes them once a pass and blends
## their points between passes as the game's, MwRinkBlend3D): one upright
## item per figure (MwRinkDraw3D.items' form, keyed
## "bench.t<team>.s<slot>/body", with a [code]dir[/code] so it turns with
## the camera, a [code]shade[/code] in the arches' dark and a depth
## [code]bias[/code], [constant BIAS_STEP]).
## What each does is a function of the snapshot alone - the match's seed
## gives each his own moments - so a replay shows them as they were:
##
## * walking (a move, or on his way out): skating along his way, facing
##   it, fading into the arch's dark;
## * his team's goal: facing the ice, after a moment of his own most
##   skaters play one of their celebrations (23-25, the ones the game plays),
##   the rest cheer and hop (a skater of species 1 with his arms-up
##   animation, a goalie with his stick raised); in the box he hops;
## * the other team's goal: still, facing the ice;
## * his team killed one of the other's: a short cheer;
## * else watching the puck ([code]look[/code], MwBenchLife), now and then
##   a shuffle of his own, hopping a little when the crowd is lively; in the
##   box the box's animation (the penalty scoreboard's).
static func items(snap: Dictionary, rom: PackedByteArray) -> Array:
	var out := []
	if snap.is_empty() or rom.is_empty():
		return out
	var figs: PackedFloat32Array = snap.get("figs", PackedFloat32Array())
	var n := 0
	for i in range(0, figs.size() - MwBenchLife.FIG + 1, MwBenchLife.FIG):
		var it := _figure(snap, figs, i, rom)
		if not it.is_empty():
			it["order"] = 1000 + n
			n += 1
			out.append(it)
	return out


static func _figure(snap: Dictionary, f: PackedFloat32Array, i: int, rom: PackedByteArray) -> Dictionary:
	var team := int(f[i])
	var slot := int(f[i + 1])
	var rec := int(f[i + 2])
	var place := int(f[i + 3])
	var progress := f[i + 6]
	var look := int(f[i + 7])
	var since := f[i + 8]
	var kind := int(f[i + 9])
	if rec <= 0 or rec + 8 >= rom.size() or team < 0 or team > 1:
		return {}
	var snap_seed := int(snap.get("seed", 0))
	var t := float(snap.get("ticks", 0))
	var anim_id := ANIM_SKATE
	var elapsed := -1.0               # < 0: stopped at frame 0 (standing)
	var variant := look
	var at: Vector2
	var hop := 0.0
	var key := "bench.t%d.s%d/body" % [team, slot]
	if kind != MwBenchLife.SIT and progress < 1.0:
		return walking_item(rom, key, team, slot, rec, route(team, Vector2(f[i + 4], f[i + 5]),
				place_at(team, place)), progress, t - since, look)
	elif kind == MwBenchLife.OUT:
		return {}                     # in the arch's dark
	else:
		at = place_at(team, place)
		var box := place >= BOX and place < BOX + 3
		var ice := 6 if box else 2    # the boxes look west, the benches east
		var g := goalie(rom, rec)
		var sp := MwPlayerAnims.species(rom, rec)
		var goals: Array = snap.get("goal_at", [-1, -1])
		var kills: Array = snap.get("kill_at", [-1, -1])
		var own := t - float(goals[team]) if int(goals[team]) >= 0 else -1.0
		var other := t - float(goals[1 - team]) if int(goals[1 - team]) >= 0 else -1.0
		var kill := t - float(kills[team]) if int(kills[team]) >= 0 else -1.0
		if box:
			anim_id = ANIM_BOX
			elapsed = t + rand(snap_seed, team, slot, 7) * 200.0
		if own >= 0.0 and own < CELEBRATE_TICKS:
			variant = ice
			var el := own - rand(snap_seed, team, slot, 1) * 24.0
			if el >= 0.0:
				if box:
					hop = 1.0
				else:
					var c := celebration(rom, rec, el, rand(snap_seed, team, slot, 2), rand(snap_seed, team, slot, 3))
					anim_id = c[0]
					elapsed = c[1]
					hop = c[2]
		elif other >= 0.0 and other < CELEBRATE_TICKS:
			variant = ice                  # still, looking at the ice
			elapsed = -1.0 if not box else 0.0
		elif kill >= 0.0 and kill < KILL_TICKS:
			var el := kill - rand(snap_seed, team, slot, 9) * 12.0
			if el >= 0.0:
				hop = 0.8
				if sp <= 1 and not g and not box:
					anim_id = ANIM_BOX
					elapsed = el
		elif not box:
			# watching; now and then a shuffle of his own
			var fid := GOALIE_FIDGET if g else (ANIM_BOX if sp >= 2 else ANIM_FIDGET)
			var fidget_ticks := anim_ticks(rom, MwPlayerAnims.anim(rom, rec, fid)) * (1.0 if sp >= 2 or g else 3.0)
			var period := 420.0 + rand(snap_seed, team, slot, 4) * 660.0
			var ph := fmod(t + rand(snap_seed, team, slot, 5) * period, period)
			if ph < fidget_ticks:
				anim_id = fid
				elapsed = ph
			var life := float(snap.get("life", 0.0))
			if life > 0.45 and rand(snap_seed, team, slot, 6) < (life - 0.45) * 1.6:
				hop = 0.6
	var z := hop_height(snap_seed, team, slot, t, hop)
	return figure_item(rom, key, team, slot, rec, Vector3(at.x, at.y, z), anim_id, elapsed, variant)


## What a player [param el] ticks into his celebration does (the benches at
## their team's goal, plan 32; the players showing off, plan 33): a goalie
## raises his stick (the slash) and hops; most skaters ([param whole] <
## 0.65) play one of their celebrations (23-25, by [param pick]) once, then -
## the rest from the start - hop and cheer, species 1 with his arms up:
## [animation id, ticks into it (< 0 standing), hop (0..1)].
static func celebration(rom: PackedByteArray, rec: int, el: float, pick: float, whole: float) -> Array:
	if goalie(rom, rec):
		return [GOALIE_CHEER, fmod(el, anim_ticks(rom, MwPlayerAnims.anim(rom, rec, GOALIE_CHEER))), 1.0]
	var c := ANIM_CELEBRATE + int(pick * 3.0)
	if whole < 0.65 and el < anim_ticks(rom, MwPlayerAnims.anim(rom, rec, c)):
		return [c, el, 0.0]
	if MwPlayerAnims.species(rom, rec) <= 1:
		return [ANIM_BOX, el, 1.0]                 # species 1's: arms up
	return [ANIM_SKATE, -1.0, 1.0]


## How high (px) a figure ([param team], roster [param slot], the match's
## [param seed_]) is at [param t] (ticks) hopping [param hop] (0..1): a
## pace and a height of his own.
static func hop_height(seed_: int, team: int, slot: int, t: float, hop: float) -> float:
	if hop <= 0.0:
		return 0.0
	var half := 10.0 + rand(seed_, team, slot, 10) * 6.0            # ticks up (and down again)
	return hop * (3.0 + rand(seed_, team, slot, 11) * 4.0) \
			* absf(sin((t + rand(seed_, team, slot, 8) * 60.0) * PI / half))


## A player's frame standing at rink point [param at] (px; z: how high he
## hops) as an upright item (MwRinkDraw3D.items' form, keyed [param key]):
## animation [param anim_id] of his record [param rec] (MwPlayerAnims)
## [param elapsed] ticks into it (< 0: stopped at its first frame, his
## standing frame for animation 0), facing [param variant] - turning with
## the camera ([code]dir[/code]), his team's colours, his depth bias
## ([constant BIAS_STEP] by his roster [param slot]) and the arches' dark
## ([method shade_at]). The benches' figures (plan 32) and the match's
## opening's (plan 33, MwIntroCast) are drawn by it.
static func figure_item(rom: PackedByteArray, key: String, team: int, slot: int, rec: int, at: Vector3,
		anim_id: int, elapsed: float, variant: int) -> Dictionary:
	var addr := MwPlayerAnims.anim(rom, rec, anim_id)
	var fr := frame_at(rom, addr, elapsed) if elapsed >= 0.0 else 0
	var anim := MwAnimState.new()
	anim.address = addr
	anim.variant = variant
	anim.frame = fr
	var fa := anim.frame_address(rom)
	var attr0: int = TEAM_ATTR[team]
	var it := {"frame": fa.x, "attr": attr0 ^ (fa.y << 3), "depth": DEPTH, "place": MwRinkDraw3D.UPRIGHT,
			"at": at, "offset": Vector2i.ZERO, "key": key,
			"dir": {"anim": addr, "variant": variant, "aframe": fr, "attr0": attr0},
			"bias": BIAS_STEP * (slot + 24 * team)}
	var k := shade_at(at.x)
	if k < 1.0:
		it["shade"] = k
	return it


## A player skating [param fraction] (0..1) of the way [param way] (rink px, a
## polyline), facing along it ([param look] where it has no direction), his
## skate loop [param elapsed] ticks in ([method figure_item]).
static func walking_item(rom: PackedByteArray, key: String, team: int, slot: int, rec: int,
		way: PackedVector2Array, fraction: float, elapsed: float, look: int) -> Dictionary:
	var a := along(way, fraction)
	var at: Vector2 = a[0]
	var variant := variant_of(a[1]) if a[1] != Vector2.ZERO else look
	return figure_item(rom, key, team, slot, rec, Vector3(at.x, at.y, 0.0), ANIM_SKATE, elapsed, variant)
