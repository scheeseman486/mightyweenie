class_name MwStands
extends RefCounted
## The 3D crowd's stands (plan 15, docs/rink3d.md, Crowd): where the tiers,
## seats and figures go round the rink, as numbers (rink px). Rows of tiers
## follow the boards out from them, a steeper bowl than the picture's (owner);
## each seat gets a figure from the picture's crowd in the same part of the
## stadium (far end, the sides' north and south halves, near end), in the
## picture's order along the stands and by its depth bands, so the crowd keeps
## the picture's mix. A seat whose character lacks a view gets its stand-in
## (owner: "matched stand-ins" until the artwork exists). The right half
## mirrors the left, as the picture does.

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
const BOARD := Vector2(185.0, 372.0)    # the straight boards (physics boundary)
const CORNER_FAR := 74.0     # the boards' corners: rows the x-limit tables cover ($1C77E from |y| 298)
const CORNER_NEAR := 48.0    # ... ($1C81E from y 324)
const PEN_Y := 172.0         # the pens along the sides (|y| < PEN_Y) ...
const PEN_CLEAR := 75.0      # ... reach this far out: lower rows stop there
const BANDS := 3             # depth bands of the picture's crowd per part
const ROW_SHIFTS := [0, 7, 3, 12, 5, 9, 1, 14, 6, 11]   # where each row starts in its band's list (no diagonals)

enum Region { FAR, SIDE_FRONT, SIDE_BACK, NEAR }
enum Seg { FAR_STRAIGHT, FAR_CORNER, SIDE, NEAR_CORNER, NEAR_STRAIGHT }


## Row [param k]'s tread: its front edge outside the boards ...
static func offset(k: int) -> float:
	return D0 + k * DEPTH


## ... and its height.
static func height(k: int) -> float:
	return H0 + k * RISE


## The length of the left half of the path [param d] px outside the boards
## (from the far centre west round to the near centre).
static func half_length(d: float) -> float:
	var a := BOARD.x + d
	var b := BOARD.y + d
	var rf := CORNER_FAR + d
	var rn := CORNER_NEAR + d
	return (a - rf) + rf * PI / 2.0 + (b - rf) + (b - rn) + rn * PI / 2.0 + (a - rn)


## The point [param s] px along the left half of the path [param d] px outside
## the boards: {p: Vector2 (x, y), n: inward normal, seg: Seg}.
static func point_at(d: float, s: float) -> Dictionary:
	var a := BOARD.x + d
	var b := BOARD.y + d
	var rf := CORNER_FAR + d
	var rn := CORNER_NEAR + d
	var lens := [a - rf, rf * PI / 2.0, (b - rf) + (b - rn), rn * PI / 2.0, a - rn]
	var seg := 0
	while seg < 4 and s > lens[seg]:
		s -= lens[seg]
		seg += 1
	s = minf(s, lens[seg])
	match seg:
		Seg.FAR_STRAIGHT:
			return {"p": Vector2(-s, -b), "n": Vector2(0, 1), "seg": seg}
		Seg.FAR_CORNER:
			var t: float = s / lens[1] * PI / 2.0
			var dir := Vector2(-sin(t), -cos(t))
			return {"p": Vector2(-(a - rf), -(b - rf)) + dir * rf, "n": -dir, "seg": seg}
		Seg.SIDE:
			return {"p": Vector2(-a, -(b - rf) + s), "n": Vector2(1, 0), "seg": seg}
		Seg.NEAR_CORNER:
			var t: float = s / lens[3] * PI / 2.0
			var dir := Vector2(-cos(t), sin(t))
			return {"p": Vector2(-(a - rn), b - rn) + dir * rn, "n": -dir, "seg": seg}
		_:
			return {"p": Vector2(-(a - rn) + s, b), "n": Vector2(0, -1), "seg": seg}


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
	var s := 0.0
	for i in seg:
		s += lens[i]
	return point_at(d, s + (u - seg) * lens[seg])


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


static func region_of(seg: int, p: Vector2) -> int:
	match seg:
		Seg.FAR_STRAIGHT, Seg.FAR_CORNER:
			return Region.FAR
		Seg.SIDE:
			return Region.SIDE_FRONT if p.y < 0 else Region.SIDE_BACK
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


## The picture's crowd instances by region, each split into [constant BANDS]
## depth bands (front band first) sorted along the region as its seats run
## (the far end from the centre west, the sides north to south, the near end
## west to the centre): {Region: [band: [{figure, mirrored, team, swap}]]}.
static func picture_regions(data: Dictionary) -> Dictionary:
	var lists := {}
	for r in Region.values():
		lists[r] = []
	for f: Dictionary in data.get("figures", []):
		if f.has("from") or int(f.get("line", 1)) != 1:
			continue
		var box: Array = f["box"]
		for inst: Array in f["instances"]:
			var cx := float(inst[0]) + float(box[2]) / 2.0
			var cy := float(inst[1]) + float(box[3]) / 2.0
			var r: int
			var along: float
			var depth: float           # from the boards out
			if f["view"] == "front":
				if cy < 60.0 or (cy < 100.0 and cx >= 64.0):
					r = Region.FAR
					along = -cx
					depth = -cy
				else:
					r = Region.SIDE_FRONT
					along = cy
					depth = -cx
			else:
				if cy >= 828.0:
					r = Region.NEAR
					along = cx
					depth = cy
				else:
					r = Region.SIDE_BACK
					along = cy
					depth = -cx
			lists[r].append({"figure": f["name"], "mirrored": bool(inst[2]), "team": bool(inst[3]),
					"swap": f.get("swaps", [])[int(inst[4]) - 1] if int(inst[4]) > 0 else [],
					"along": along, "depth": depth})
	var out := {}
	for r in lists:
		var l: Array = lists[r]
		# depth bands, the nearest the boards first, each sorted along
		l.sort_custom(func(p, q): return p["depth"] < q["depth"] if p["depth"] != q["depth"] else p["along"] < q["along"])
		var bands: Array = []
		var n := l.size()
		for bi in BANDS:
			var band := l.slice(bi * n / BANDS, (bi + 1) * n / BANDS)
			band.sort_custom(func(p, q): return p["along"] < q["along"] if p["along"] != q["along"] else p["depth"] > q["depth"])
			bands.append(band)
		out[r] = bands
	return out


## Every seat of the stands: {pos: Vector3 (rink px: x, y, z of the tread
## under the figure), facing: Vector2 (towards the rink), row, region, front,
## back (the figures of its character or stand-in), mirrored, team, swap}.
static func seats(data: Dictionary) -> Array:
	var chars := characters(data)
	var regions := picture_regions(data)
	var out: Array = []
	for k in ROWS:
		var d := offset(k) + FIGURE_AT * DEPTH
		var length := half_length(d)
		var count := {}            # seats so far per region on this row
		var j := 0
		while SPACING * (j + 0.5) < length:
			var at := point_at(d, SPACING * (j + 0.5))
			j += 1
			var p: Vector2 = at["p"]
			if at["seg"] == Seg.SIDE and absf(p.y) < PEN_Y and offset(k) < PEN_CLEAR:
				continue
			var r := region_of(at["seg"], p)
			var bands: Array = regions[r]
			var band: Array = bands[mini(k * BANDS / ROWS, BANDS - 1)]
			if band.is_empty():
				continue
			var i: int = count.get(r, 0)
			count[r] = i + 1
			var inst: Dictionary = band[(i + ROW_SHIFTS[k % ROW_SHIFTS.size()] * (k / ROW_SHIFTS.size() + 1)) % band.size()]
			var c: Dictionary = chars["figure"][inst["figure"]]
			if not complete(c):
				c = chars["name"][c["standin"]]
			for side in [1.0, -1.0]:       # the left half, then its mirror
				out.append({"pos": Vector3(p.x * side, p.y, height(k)), "facing": Vector2(at["n"].x * side, at["n"].y),
						"row": k, "region": r, "front": c["front"], "back": c["back"],
						"mirrored": inst["mirrored"] != (side < 0.0), "team": inst["team"], "swap": inst["swap"]})
	return out
