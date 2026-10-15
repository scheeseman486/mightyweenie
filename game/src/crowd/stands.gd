class_name MwStands
extends RefCounted
## The 3D crowd's stands (plan 15, docs/rink3d.md, Crowd): where the tiers,
## seats and figures go round the rink, as numbers (rink px). Rows of tiers
## follow the boards out from them, a steeper bowl than the picture's (owner);
## the seats of the right half mirror the left's places. Who sits where is
## dealt at random ([method deal]; owner, 2026-10-09: the 3D spectators
## random, not guessed from the tilemap): any of the characters with both
## views, a colour swap of theirs, the team brown skin as often as the
## picture's figures have it - a new crowd for every match (MwStands3D deals
## from the crowd's seed).

const ROWS := 10
const D0 := 16.0             # the first tread's front edge outside the boards (px)
const DEPTH := 18.0          # a tread's depth
const RISE := 16.0           # a tier's rise
const H0 := 20.0             # the first tread's height
const SPACING := 15.0        # seats along a row
const FIGURE_AT := 0.35      # where a figure stands across its tread (0 front edge, 1 back)
const SEAT_AT := 0.75        # where its seat is
const SEAT_Z := 5.0          # the seat bar's bottom above the tread
const SEAT_H := 6.0          # its height (the picture's: 2 rows checker, 3 dark grey, 1 rim)
const SEAT_T := 3.0          # its thickness
## Owner, 2026-10-14 (z-fighting in the stands, mostly low down, where
## neighbours stood at nearly one depth): a figure's depth is that of an
## upright plane at his feet facing the camera's heading, and the game's
## cameras look straight along the rink (FOLLOW, REVERSE, the ortho views; the
## TV views across it) - so every fan of an end's row stood in one plane with
## his neighbours, and where their drawings overlap the depth test fought. Each
## fan now stands a little in front of or behind his row's line, and if need be
## a little along it ([method stagger_steps]), so that no two whose drawings
## can meet stand at one depth seen along the rink or across it (the rows above
## him included: the far end's rows have their seats at the same x, seen
## side-on).
const STAGGER := 1.0         # px a step
## The steps a fan may take (STAGGER: across the tread, forward towards the
## rink; along the row): the first four in turn along a row, then the rest
## in order.
const STAGGER_STEPS: Array[Vector2] = [Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(1.5, 0), Vector2(-1.5, 0),
		Vector2(2.5, 0), Vector2(-2.5, 0), Vector2(0.5, 1), Vector2(-0.5, -1), Vector2(1.5, -1), Vector2(-1.5, 1),
		Vector2(0.5, -2), Vector2(-0.5, 2), Vector2(1.5, 2), Vector2(-1.5, -2), Vector2(2.5, 1), Vector2(-2.5, -1)]
const STAGGER_REACH := 44.0  # px apart side to side: drawings that can overlap (the widest view, 42)
const STAGGER_TALL := 70.0   # px apart in height: the same (the tallest view, 66)
const STAGGER_MIN := 0.25    # px: the least depth between two such figures (5 mm: well inside the depth buffer)
const BOARD := MwRinkShape.BOARD                # the straight boards (physics boundary)
# the boards' corners: rows the x-limit tables cover ($1C77E from |y| 298)
const CORNER_FAR := MwRinkShape.CORNER_FAR
const CORNER_NEAR := MwRinkShape.CORNER_NEAR    # ... ($1C81E from y 324)
const PEN_Y := 172.0         # the pens along the sides (|y| < PEN_Y) ...
const PEN_CLEAR := 34.0      # ... reach this far out: the rows in front of it stop there (row 0; owner,
                             # 2026-10-11: the seating comes in right behind the pens, was 75: rows 0-3)
const HALL_Y := 46.0         # the hallways between the pens (|y| < HALL_Y; their walls at 40) run out under
const HALL_CLEAR := 75.0     # the stands: the rows in front of HALL_CLEAR stop for them (0-3), row 4 roofs them

enum Region { FAR, SIDE_FRONT, SIDE_BACK, NEAR }
enum Seg { FAR_STRAIGHT, FAR_CORNER, SIDE, NEAR_CORNER, NEAR_STRAIGHT }
## Why a row stops at a point ([method cut]): not, for the pens, for a hallway.
enum Cut { NONE, PEN, HALL }


## Row [param k]'s tread: its front edge outside the boards ...
static func offset(k: int) -> float:
	return D0 + k * DEPTH


## ... and its height.
static func height(k: int) -> float:
	return H0 + k * RISE


## Whether row [param k] stops at path point [param point] (of segment [param seg],
## [method point_at]) and why ([enum Cut]): the rows in front of
## [constant PEN_CLEAR] stop at the pens, those in front of [constant
## HALL_CLEAR] for the hallways between them, which run on under the stands
## (the rink model's, tools/blender/rink_build.py HALL_X).
static func cut(k: int, seg: int, point: Vector2) -> int:
	if seg != Seg.SIDE:
		return Cut.NONE
	if absf(point.y) < HALL_Y and offset(k) < HALL_CLEAR:
		return Cut.HALL
	if absf(point.y) < PEN_Y and offset(k) < PEN_CLEAR:
		return Cut.PEN
	return Cut.NONE


## The length of the left half of the path [param d] px outside the boards
## (from the far centre west round to the near centre).
static func half_length(d: float) -> float:
	var a := BOARD.x + d
	var b := BOARD.y + d
	var rf := CORNER_FAR + d
	var rn := CORNER_NEAR + d
	return (a - rf) + rf * PI / 2.0 + (b - rf) + (b - rn) + rn * PI / 2.0 + (a - rn)


## The point [param distance] px along the left half of the path [param d] px outside
## the boards: {p: Vector2 (x, y), n: inward normal, seg: Seg}.
static func point_at(d: float, distance: float) -> Dictionary:
	var a := BOARD.x + d
	var b := BOARD.y + d
	var rf := CORNER_FAR + d
	var rn := CORNER_NEAR + d
	var lens := [a - rf, rf * PI / 2.0, (b - rf) + (b - rn), rn * PI / 2.0, a - rn]
	var seg := 0
	while seg < 4 and distance > lens[seg]:
		distance -= lens[seg]
		seg += 1
	distance = minf(distance, lens[seg])
	match seg:
		Seg.FAR_STRAIGHT:
			return {"p": Vector2(-distance, -b), "n": Vector2(0, 1), "seg": seg}
		Seg.FAR_CORNER:
			var t: float = distance / lens[1] * PI / 2.0
			var dir := Vector2(-sin(t), -cos(t))
			return {"p": Vector2(-(a - rf), -(b - rf)) + dir * rf, "n": -dir, "seg": seg}
		Seg.SIDE:
			return {"p": Vector2(-a, -(b - rf) + distance), "n": Vector2(1, 0), "seg": seg}
		Seg.NEAR_CORNER:
			var t: float = distance / lens[3] * PI / 2.0
			var dir := Vector2(-cos(t), sin(t))
			return {"p": Vector2(-(a - rn), b - rn) + dir * rn, "n": -dir, "seg": seg}
		_:
			return {"p": Vector2(-(a - rn) + distance, b), "n": Vector2(0, -1), "seg": seg}


## The point at [param u] (0..5: segment Seg + the fraction along it) of the
## left half of the path [param d] px outside the boards, as point_at: the
## same u is the same place along the stands at any offset.
static func point_at_u(d: float, u: float) -> Dictionary:
	var a := BOARD.x + d
	var b := BOARD.y + d
	var rf := CORNER_FAR + d
	var rn := CORNER_NEAR + d
	var lens := [a - rf, rf * PI / 2.0, (b - rf) + (b - rn), rn * PI / 2.0, a - rn]
	var seg := clampi(int(floor(u)), 0, 4)
	var segment_start := 0.0
	for i in seg:
		segment_start += lens[i]
	return point_at(d, segment_start + (u - seg) * lens[seg])


## The u (point_at_u) of samples about [param step] px apart at the
## outermost row, the same for every row.
static func path_us(step: float) -> PackedFloat32Array:
	var d := offset(ROWS) + DEPTH
	var a := BOARD.x + d
	var b := BOARD.y + d
	var rf := CORNER_FAR + d
	var rn := CORNER_NEAR + d
	var lens := [a - rf, rf * PI / 2.0, (b - rf) + (b - rn), rn * PI / 2.0, a - rn]
	var out := PackedFloat32Array()
	for seg in 5:
		var n := maxi(int(ceil(lens[seg] / step)), 1)
		for i in n:
			out.append(seg + float(i) / n)
	out.append(5.0)
	return out


## The [enum Region] of [param point] on path segment [param seg] ([enum Seg]): FAR on the
## far straight and corner, SIDE_FRONT / SIDE_BACK on the side (y < 0 / y >= 0), else NEAR.
static func region_of(seg: int, point: Vector2) -> int:
	match seg:
		Seg.FAR_STRAIGHT, Seg.FAR_CORNER:
			return Region.FAR
		Seg.SIDE:
			return Region.SIDE_FRONT if point.y < 0 else Region.SIDE_BACK
		_:
			return Region.NEAR


## The characters of crowd.json by figure name (a figure's character) and by
## name.
static func characters(data: Dictionary) -> Dictionary:
	var by_figure := {}
	var by_name := {}
	for c: Dictionary in data.get("characters", []):
		by_name[c["name"]] = c
		for side in ["front", "back"]:
			if c.get(side) is String:
				by_figure[c[side]] = c
	return {"figure": by_figure, "name": by_name}


## Whether a character has both views.
static func complete(c: Dictionary) -> bool:
	return c.get("front") is String and c.get("back") is String


## Every seat of the stands: {pos: Vector3 (rink px: x, y, z of the tread
## on the row's line under the seat), stand: Vector3 (where its figure
## stands: [member pos] stepped across the tread, [method stagger_steps]),
## facing: Vector2 (towards the rink), row, region, front, back (the figures
## of its character), mirrored, team, swap} - who sits there dealt by
## [method deal] with [param seed_]. Who sits where, the filling order and
## the fans' teams go by [member pos]; the drawing by [member stand].
static func seats(data: Dictionary, seed_ := 0) -> Array:
	var rows: Array[Array] = []        # each row's left half's places (point_at's), in order
	for k in ROWS:
		var d := offset(k) + FIGURE_AT * DEPTH
		var length := half_length(d)
		var places: Array[Dictionary] = []
		var j := 0
		while SPACING * (j + 0.5) < length:
			var at := point_at(d, SPACING * (j + 0.5))
			j += 1
			if cut(k, at["seg"], at["p"]) != Cut.NONE:
				continue
			places.append(at)
		rows.append(places)
	var steps := stagger_steps(rows)
	var out: Array = []
	for k in ROWS:
		var places: Array = rows[k]
		for i in places.size():
			var at: Dictionary = places[i]
			var point: Vector2 = at["p"]
			var normal: Vector2 = at["n"]
			var r := region_of(at["seg"], point)
			for half in 2:                 # the left half, then its mirror
				var side := 1.0 if half == 0 else -1.0
				var step := STAGGER_STEPS[(steps[k] as PackedInt32Array)[i + half * places.size()]]
				var stand := _stepped(Vector2(point.x * side, point.y), Vector2(normal.x * side, normal.y), step)
				out.append({"pos": Vector3(point.x * side, point.y, height(k)),
						"stand": Vector3(stand.x, stand.y, height(k)),
						"facing": Vector2(normal.x * side, normal.y),
						"row": k, "region": r})
	deal(out, data, seed_)
	return out


## Each row's fans' steps across their tread (indices into [constant
## STAGGER_STEPS]; [param rows]: each row's left half's places, point_at's,
## in order): per row the left half's, then their mirrors'. A row is a loop
## - the left half out from the far end's middle round to the near end's,
## its mirror back - and each fan, going round it row by row, takes the
## first step in his turn (the loop's position, mod 4) that leaves him at
## least [constant STAGGER_MIN] apart in depth, seen along the rink and
## across it, from every fan already placed whose drawing can overlap his
## (within [constant STAGGER_REACH] side to side and [constant STAGGER_TALL]
## in height: his own row's neighbours, round the loop's ends too, and the
## rows above and below); none does: the one that leaves the most.
static func stagger_steps(rows: Array[Array]) -> Array[PackedInt32Array]:
	var placed := {}                   # grid cell (STAGGER_REACH px) -> the stand points placed in it
	var out: Array[PackedInt32Array] = []
	for k in rows.size():
		var places: Array = rows[k]
		var n := places.size()
		var loop: Array[Array] = []    # [point, normal, index in the row's steps], in the loop's order
		for i in n:
			loop.append([places[i]["p"], places[i]["n"], i])
		for i in range(n - 1, -1, -1):
			var point: Vector2 = places[i]["p"]
			var normal: Vector2 = places[i]["n"]
			loop.append([Vector2(-point.x, point.y), Vector2(-normal.x, normal.y), n + i])
		var row_steps := PackedInt32Array()
		row_steps.resize(2 * n)
		var z := height(k)
		for i in loop.size():
			var point: Vector2 = loop[i][0]
			var normal: Vector2 = loop[i][1]
			var pick := 0
			var most := -1.0
			for t in STAGGER_STEPS.size():
				var candidate := (i + t) % 4 if t < 4 else t
				var stand := _stepped(point, normal, STAGGER_STEPS[candidate])
				var gap := _depth_gap(placed, Vector3(stand.x, stand.y, z))
				if gap > most:
					most = gap
					pick = candidate
				if gap >= STAGGER_MIN:
					break
			row_steps[loop[i][2]] = pick
			var stood := _stepped(point, normal, STAGGER_STEPS[pick])
			var cell := Vector2i(floori(stood.x / STAGGER_REACH), floori(stood.y / STAGGER_REACH))
			if not placed.has(cell):
				placed[cell] = []
			(placed[cell] as Array).append(Vector3(stood.x, stood.y, z))
		out.append(row_steps)
	return out


## [param point] (a row's, its inward [param normal]) moved by [param step]
## (STAGGER_STEPS': across the tread towards the rink, along the row - the
## left half's way round; its mirror's too, the normal mirrored).
static func _stepped(point: Vector2, normal: Vector2, step: Vector2) -> Vector2:
	return point + (normal * step.x + Vector2(-normal.y, normal.x) * step.y) * STAGGER


## The least depth (px) between a figure standing at [param stand] and the
## figures already [param placed] ([method stagger_steps]' grid) whose
## drawings can overlap his, seen along the rink (depth y, side to side x)
## and across it (depth x, side to side y); INF when none can.
static func _depth_gap(placed: Dictionary, stand: Vector3) -> float:
	var least := INF
	var cell := Vector2i(floori(stand.x / STAGGER_REACH), floori(stand.y / STAGGER_REACH))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for other: Vector3 in placed.get(cell + Vector2i(dx, dy), []):
				if absf(other.z - stand.z) >= STAGGER_TALL:
					continue
				var along := absf(other.x - stand.x)
				var across := absf(other.y - stand.y)
				if along < STAGGER_REACH:
					least = minf(least, across)
				if across < STAGGER_REACH:
					least = minf(least, along)
	return least


## The characters a seat can get: those with both views (Satan
## has one).
static func fans(data: Dictionary) -> Array:
	var out := []
	for c: Dictionary in data.get("characters", []):
		if complete(c):
			out.append(c)
	return out


## A character's colour swaps (its views' together; none is also a choice).
static func swaps_of(data: Dictionary, c: Dictionary) -> Array:
	var out := []
	for f: Dictionary in data.get("figures", []):
		if f["name"] == c["front"] or f["name"] == c["back"]:
			for swap: Array in f.get("swaps", []):
				if not swap in out:
					out.append(swap)
	return out


## How often the picture's figures have the team brown skin (their share).
static func team_share(data: Dictionary) -> float:
	var n := 0
	var team := 0
	for f: Dictionary in data.get("figures", []):
		if int(f.get("line", 1)) != 1:
			continue
		for inst: Array in f.get("instances", []):
			n += 1
			team += 1 if bool(inst[3]) else 0
	return float(team) / n if n > 0 else 0.5


## Deals [param seat_list] their fans from [param seed_] (the same seed, the
## same crowd): a character with both views ([method fans]), each as likely;
## one of its colour swaps or none, each as likely; the team brown skin as
## often as in the picture ([method team_share]); drawn mirrored or not.
static func deal(seat_list: Array, data: Dictionary, seed_: int) -> void:
	var cast := fans(data)
	if cast.is_empty():
		return
	var swaps := []
	for c: Dictionary in cast:
		swaps.append(swaps_of(data, c))
	var share := team_share(data)
	var rng := RandomNumberGenerator.new()
	rng.seed = MwSeed.knuth(seed_, 0x4D57534E)
	for seat: Dictionary in seat_list:
		var i := rng.randi() % cast.size()
		var options: Array = swaps[i]
		var w := rng.randi() % (options.size() + 1)
		seat["front"] = cast[i]["front"]
		seat["back"] = cast[i]["back"]
		seat["swap"] = options[w - 1] if w > 0 else []
		seat["team"] = rng.randf() < share
		seat["mirrored"] = rng.randf() < 0.5


## Every view a deal can show: [figure, team, swap] ([method deal]).
static func variants(data: Dictionary) -> Array:
	var out := []
	for c: Dictionary in fans(data):
		var options := [[]] + swaps_of(data, c)
		for side in ["front", "back"]:
			for team in [false, true]:
				for sw: Array in options:
					out.append([c[side], team, sw])
	return out
