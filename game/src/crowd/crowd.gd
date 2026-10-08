class_name MwCrowd
extends RefCounted
## The rink picture's crowd as separate figures (plan 15, docs/rink3d.md,
## Crowd). The picture (`$24CFC`, palette line 1 outside the boards) is a few
## figure drawings stamped many times over each other and the seats; this cuts
## every figure out of the ROM's picture at load from the numbers in
## [constant DATA] (written by tools/crowd/crowd_build.py). It follows the
## tool's crowd_lib.py rule for rule; test_crowd.gd checks every template
## against the tool's checksum. Nothing decoded is saved.
##
## A figure's **template** (box-sized, palette indices line * 16 + colour) is
## per pixel the colour most of its instances show there ([constant EMPTY]:
## see-through, [constant INFILL]: the owner's paint goes there, [constant
## UNSURE]: the instances tie). Each instance is cut in its own surroundings
## the figure's way: seeds flooded through the figure colours, or a lasso
## taking the parts mostly inside it, plus their dark outline, plus the
## owner's marks (runs of picture pixels added, removed or to paint). Views
## the picture never shows ("from") are another figure's template with
## colours swapped, marks and rects of other figures ("graft", the owner's
## combinations); ("size") a canvas the owner draws on. Last
## comes the owner's own art ("paint": runs of palette indices from the
## template's top-left, an erase being EMPTY), which may grow the canvas
## ([method paint_canvas]).

const DATA := "res://assets/crowd/crowd.json"
const PICTURE := 0x24CFC
const LINE := 16             # crowd colours: line 1, 16..31
const HALF := 256            # the crowd is mirrored about x = 256: the left half holds it
const EMPTY := -2            # template: see-through (or a gap the picture never shows)
const UNSURE := -4           # template: instances tie
const INFILL := -5           # template: to paint (the owner's art)
const NOT_CROWD := -1        # picture: rink, boards, left out, off the picture
const BROWN := 20            # the fixed brown ...
const TEAM_BROWN := 25       # ... and team A's skin shade: one colour with team 0
const DARK_GREY := 30
const BLACK := 31
const TOP_CENTRE := Rect2i(208, 0, 48, 48)   # the left half's part of the block left out (owner)

var data: Dictionary = {}           # crowd.json
var pic_w := 0
var pic_h := 0
var picture := PackedInt32Array()   # the whole picture (pic_w x pic_h)
var crowd := PackedInt32Array()     # the left half's crowd (HALF x pic_h), NOT_CROWD elsewhere
var templates := {}                 # figure name -> {w, h, t: PackedInt32Array, source, ox, oy (the box's top-left in t)}
var figures := {}                   # figure name -> its crowd.json entry


## Reads crowd.json.
static func load_data() -> Dictionary:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())


## Cuts every figure of [param data_] (crowd.json) from the ROM [param rom].
func build(rom: PackedByteArray, data_: Dictionary = {}) -> void:
	data = data_ if not data_.is_empty() else load_data()
	var img := MwGfx.picture_image(rom, MwGfx.picture(rom, PICTURE))
	pic_w = img["w"]
	pic_h = img["h"]
	var px: PackedByteArray = img["px"]
	picture.resize(pic_w * pic_h)
	for i in px.size():
		picture[i] = px[i]
	crowd = crowd_area(picture, pic_w, pic_h)
	templates.clear()
	figures.clear()
	for f: Dictionary in data.get("figures", []):
		figures[f["name"]] = f
	for f: Dictionary in data.get("figures", []):
		if not f.has("from") and not f.has("size"):
			templates[f["name"]] = _template(f)
	for f: Dictionary in data.get("figures", []):    # in order: a made view may start from one made before it
		if f.has("from"):
			templates[f["name"]] = _derive(f)
		elif f.has("size"):
			templates[f["name"]] = _drawn(f)


## A figure's template: {w, h, t}.
func template(name: String) -> Dictionary:
	return templates.get(name, {})


# --- the picture ---------------------------------------------------------------------

## The left half's crowd: line-1 pixels reached from the picture's edge
## through line-1 pixels (so not the pens' floors), without the top centre.
static func crowd_area(pic: PackedInt32Array, w: int, h: int) -> PackedInt32Array:
	var reach := PackedByteArray()
	reach.resize(HALF * h)
	var stack: Array[Vector2i] = []
	for y in h:
		stack.append(Vector2i(0, y))
	for x in HALF:
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		var i := p.y * HALF + p.x
		if reach[i] or pic[p.y * w + p.x] < LINE:
			continue
		reach[i] = 1
		for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var q := p + d
			if q.x >= 0 and q.x < HALF and q.y >= 0 and q.y < h and not reach[q.y * HALF + q.x]:
				stack.append(q)
	var out := PackedInt32Array()
	out.resize(HALF * h)
	for y in h:
		for x in HALF:
			var inside := reach[y * HALF + x] and not TOP_CENTRE.has_point(Vector2i(x, y))
			out[y * HALF + x] = pic[y * w + x] if inside else NOT_CROWD
	return out


## a[y:y+h, x:x+w] (a is aw x ah) padded with NOT_CROWD, mirrored if asked.
static func window(a: PackedInt32Array, aw: int, ah: int, x: int, y: int, w: int, h: int,
		mirrored := false) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(w * h)
	out.fill(NOT_CROWD)
	for r in h:
		var sy := y + r
		if sy < 0 or sy >= ah:
			continue
		for c in w:
			var sx := x + c
			if sx < 0 or sx >= aw:
				continue
			var dc := w - 1 - c if mirrored else c
			out[r * w + dc] = a[sy * aw + sx]
	return out


# --- colours -------------------------------------------------------------------------

## [param a] with TEAM_BROWN as BROWN (crowd_lib.canonical).
static func canonical(a: PackedInt32Array) -> PackedInt32Array:
	var out := a.duplicate()
	for i in out.size():
		if out[i] == TEAM_BROWN:
			out[i] = BROWN
	return out


## [param a] with colours swapped: [param swap] = [[from, to], ...].
static func recolour(a: PackedInt32Array, swap: Array) -> PackedInt32Array:
	var out := a.duplicate()
	for pair: Array in swap:
		var k := int(pair[0])
		var v := int(pair[1])
		for i in a.size():
			if a[i] == k:
				out[i] = v
	return out


static func _dark(v: int) -> bool:
	return v == DARK_GREY or v == BLACK


## Pixels that can belong to a figure's parts: crowd colours but black, dark
## grey only next to another dark grey or a lighter colour.
static func figure_colours(a: PackedInt32Array, w: int, h: int) -> PackedByteArray:
	var light := PackedByteArray()
	light.resize(w * h)
	for i in a.size():
		light[i] = 1 if a[i] >= LINE and not _dark(a[i]) else 0
	var out := light.duplicate()
	for y in h:
		for x in w:
			var i := y * w + x
			if a[i] != DARK_GREY:
				continue
			for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var q := Vector2i(x, y) + d
				if q.x < 0 or q.x >= w or q.y < 0 or q.y >= h:
					continue
				var j := q.y * w + q.x
				if light[j] or a[j] == DARK_GREY:
					out[i] = 1
					break
	return out


# --- cutting a figure ------------------------------------------------------------------

## The 4-connected region of [param allowed] reached from [param seeds] (x, y).
static func flood(allowed: PackedByteArray, w: int, h: int, seeds: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	var stack: Array[Vector2i] = []
	for s: Vector2i in seeds:
		if s.x >= 0 and s.x < w and s.y >= 0 and s.y < h and allowed[s.y * w + s.x]:
			out[s.y * w + s.x] = 1
			stack.append(s)
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var q := p + d
			if q.x >= 0 and q.x < w and q.y >= 0 and q.y < h:
				var j := q.y * w + q.x
				if allowed[j] and not out[j]:
					out[j] = 1
					stack.append(q)
	return out


## Pixels 8-next to [param parts] (and parts).
static func ring(parts: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			if not parts[y * w + x]:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var qx := x + dx
					var qy := y + dy
					if qx >= 0 and qx < w and qy >= 0 and qy < h:
						out[qy * w + qx] = 1
	return out


## Black / dark grey pixels 8-next to [param parts], and dark pixels the
## outside can't reach without crossing parts or that outline (inside).
static func outline(parts: PackedByteArray, a: PackedInt32Array, w: int, h: int) -> PackedByteArray:
	var near := ring(parts, w, h)
	var free := PackedByteArray()
	free.resize(w * h)
	for i in a.size():
		var keep := parts[i] or (_dark(a[i]) and near[i])
		free[i] = 0 if keep else 1
	var edge: Array = []
	for y in h:
		edge.append(Vector2i(0, y))
		edge.append(Vector2i(w - 1, y))
	for x in w:
		edge.append(Vector2i(x, 0))
		edge.append(Vector2i(x, h - 1))
	var outside := flood(free, w, h, edge)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in a.size():
		if _dark(a[i]) and (near[i] or (not outside[i] and not parts[i])):
			out[i] = 1
	return out


## A figure's mask by seeds (crowd_lib.rule_mask): its parts (seeds, not
## through walls) with their outline, plus dark patches [x, y, radius].
static func rule_mask(view: PackedInt32Array, w: int, h: int, seeds: Array, walls: Array,
		patches: Array) -> PackedByteArray:
	var allowed := figure_colours(view, w, h)
	for p: Vector2i in walls:
		if p.x >= 0 and p.x < w and p.y >= 0 and p.y < h:
			allowed[p.y * w + p.x] = 0
	var parts := flood(allowed, w, h, seeds)
	var mask := _or(parts, outline(parts, view, w, h))
	for pt: Vector3i in patches:
		var x := pt.x
		var y := pt.y
		var r := pt.z
		if x < 0 or x >= w or y < 0 or y >= h or view[y * w + x] < LINE:
			continue
		var area := PackedByteArray()
		area.resize(w * h)
		for yy in h:
			for xx in w:
				var near: bool = absi(yy - y) <= r and absi(xx - x) <= r
				if (near and _dark(view[yy * w + xx])) or (yy == y and xx == x):
					area[yy * w + xx] = 1
		mask = _or(mask, flood(area, w, h, [Vector2i(x, y)]))
	return mask


## Pixels (top-left x0, y0) whose centres are inside [param poly] [[x, y], ...]
## (even-odd rule).
static func inside(poly: Array, w: int, h: int, x0: int, y0: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	var n := poly.size()
	for r in h:
		var py := float(y0 + r) + 0.5
		for c in w:
			var px := float(x0 + c) + 0.5
			var odd := false
			for i in n:
				var a: Array = poly[i]
				var b: Array = poly[(i + 1) % n]
				var xa := float(a[0])
				var ya := float(a[1])
				var xb := float(b[0])
				var yb := float(b[1])
				if ya == yb:
					continue
				if (ya > py) != (yb > py):
					var xi := xa + (py - ya) * (xb - xa) / (yb - ya)
					if px < xi:
						odd = not odd
			out[r * w + c] = 1 if odd else 0
	return out


## A figure's mask by a lasso (crowd_lib.lasso_mask): its parts (4-connected
## figure colours) mostly inside the lasso whole, those partly inside cut at
## it, plus their outline.
static func lasso_mask(view: PackedInt32Array, w: int, h: int, region: PackedByteArray,
		whole := 0.7, none := 0.3) -> PackedByteArray:
	var col := figure_colours(view, w, h)
	var parts := PackedByteArray()
	parts.resize(w * h)
	var seen := PackedByteArray()
	seen.resize(w * h)
	for i in w * h:
		if not (col[i] and region[i]) or seen[i]:
			continue
		var part := flood(col, w, h, [Vector2i(i % w, i / w)])
		var total := 0
		var within := 0
		for j in w * h:
			if part[j]:
				seen[j] = 1
				total += 1
				if region[j]:
					within += 1
		var frac := float(within) / float(total)
		for j in w * h:
			if part[j] and (frac >= whole or (frac >= none and region[j])):
				parts[j] = 1
	return _or(parts, outline(parts, view, w, h))


static func _or(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var out := a.duplicate()
	for i in b.size():
		if b[i]:
			out[i] = 1
	return out


## The owner's marks [param which] ("add", "remove", "infill") of figure
## [param f] as a box-sized mask.
static func runs(f: Dictionary, box: Array, which: String) -> PackedByteArray:
	var x: int = box[0]
	var y: int = box[1]
	var w: int = box[2]
	var h: int = box[3]
	var out := PackedByteArray()
	out.resize(w * h)
	for run: Array in f.get(which, []):
		var r := int(run[1]) - y
		if r < 0 or r >= h:
			continue
		var c0 := maxi(int(run[0]) - x, 0)
		var c1 := mini(maxi(int(run[0]) - x + int(run[2]), 0), w)
		for c in range(c0, c1):
			out[r * w + c] = 1
	return out


## [param mask] with the owner's marks: plus add, minus remove and infill.
static func marked(f: Dictionary, box: Array, mask: PackedByteArray) -> PackedByteArray:
	var add := runs(f, box, "add")
	var rem := runs(f, box, "remove")
	var inf := runs(f, box, "infill")
	var out := mask.duplicate()
	for i in out.size():
		out[i] = 1 if (mask[i] or add[i]) and not rem[i] and not inf[i] else 0
	return out


## The figure's mask in [param view] (box-sized). For an instance,
## [param like] is the source's figure as the instance colours it: the hand
## seeds it shows and every figure pixel it shows as the source does seed
## the flood.
func cut(f: Dictionary, view: PackedInt32Array, like := PackedInt32Array()) -> PackedByteArray:
	var box: Array = f["box"]
	var bx: int = box[0]
	var by: int = box[1]
	var w: int = box[2]
	var h: int = box[3]
	if int(f.get("line", 1)) != 1:      # outlined in its first background colour
		var bg := PackedInt32Array()
		for v in f.get("background", []):
			bg.append(int(v))
		var allowed := PackedByteArray()
		allowed.resize(w * h)
		var region := inside(f["lasso"], w, h, bx, by) if f.has("lasso") else PackedByteArray()
		for i in w * h:
			allowed[i] = 1 if view[i] >= 0 and not bg.has(view[i]) and (region.is_empty() or region[i]) else 0
		var parts := flood(allowed, w, h, _points(f.get("seeds", []), bx, by))
		var near := ring(parts, w, h)
		for i in w * h:
			if near[i] and view[i] == int(bg[0]):
				parts[i] = 1
		return marked(f, box, parts)
	if f.has("lasso"):
		return marked(f, box, lasso_mask(view, w, h, inside(f["lasso"], w, h, bx, by)))
	var seeds := _points(f.get("seeds", []), bx, by)
	var pads: Array = []
	for p: Array in f.get("patches", []):
		pads.append(Vector3i(int(p[0]) - bx, int(p[1]) - by, int(p[2])))
	if not like.is_empty():
		var kept: Array = []
		for s: Vector2i in seeds:
			if _at(view, w, h, s) == _at(like, w, h, s):
				kept.append(s)
		seeds = kept
		var kept_pads: Array = []
		for p: Vector3i in pads:
			var s := Vector2i(p.x, p.y)
			if _at(view, w, h, s) == _at(like, w, h, s):
				kept_pads.append(p)
		pads = kept_pads
		for i in w * h:
			if like[i] >= LINE and not _dark(like[i]) and view[i] == like[i]:
				seeds.append(Vector2i(i % w, i / w))
	return marked(f, box, rule_mask(view, w, h, seeds, _points(f.get("walls", []), bx, by), pads))


## A box value at s, NumPy-style (negative indices count from the end).
static func _at(a: PackedInt32Array, w: int, h: int, s: Vector2i) -> int:
	return a[posmod(s.y, h) * w + posmod(s.x, w)]


static func _points(pts: Array, bx: int, by: int) -> Array:
	var out: Array = []
	for p: Array in pts:
		out.append(Vector2i(int(p[0]) - bx, int(p[1]) - by))
	return out


# --- templates -----------------------------------------------------------------------

func _template(f: Dictionary) -> Dictionary:
	var box: Array = f["box"]
	var x: int = box[0]
	var y: int = box[1]
	var w: int = box[2]
	var h: int = box[3]
	var line1 := int(f.get("line", 1)) == 1
	var source: PackedInt32Array
	var masks: Array = []      # per unswapped instance: [view, mask]
	if not line1:
		source = window(picture, pic_w, pic_h, x, y, w, h)
		for inst: Array in f["instances"]:
			var v := window(picture, pic_w, pic_h, int(inst[0]), int(inst[1]), w, h, bool(inst[2]))
			masks.append([v, cut(f, v)])
	else:
		var src := canonical(window(crowd, HALF, pic_h, x, y, w, h))
		var mask := cut(f, src)
		source = PackedInt32Array()
		source.resize(w * h)
		for i in w * h:
			source[i] = src[i] if mask[i] else EMPTY
		var swaps: Array = [[]]
		swaps.append_array(f.get("swaps", []))
		for inst: Array in f["instances"]:
			if int(inst[4]) != 0:
				continue        # recoloured instances only use the figure
			var view := canonical(window(crowd, HALF, pic_h, int(inst[0]), int(inst[1]), w, h, bool(inst[2])))
			masks.append([view, cut(f, view, recolour(source, swaps[int(inst[4])]))])
	var t := majority(masks, source, w, h)
	var sp := specks(t, w, h)
	for i in w * h:
		if sp[i]:
			t[i] = EMPTY
	var inf := runs(f, box, "infill")
	for i in w * h:
		if inf[i]:
			t[i] = INFILL
	var out := apply_paint(t, w, h, f.get("paint", []))
	out["source"] = source
	return out


## Per pixel the colour most of [param masks]' views show (ties: the source's
## colour if it is one of them, else UNSURE; nothing: EMPTY).
static func majority(masks: Array, source: PackedInt32Array, w: int, h: int) -> PackedInt32Array:
	var t := PackedInt32Array()
	t.resize(w * h)
	t.fill(EMPTY)
	for i in w * h:
		var counts := {}
		for m: Array in masks:
			var mask: PackedByteArray = m[1]
			if mask[i]:
				var v: int = (m[0] as PackedInt32Array)[i]
				if v >= 0 and v < 64:
					counts[v] = counts.get(v, 0) + 1
		if counts.is_empty():
			continue
		var top := 0
		for v in counts:
			top = maxi(top, counts[v])
		var best := 64
		var n := 0
		for v in counts:
			if counts[v] == top:
				n += 1
				best = mini(best, v)
		if n == 1:
			t[i] = best
		elif source[i] >= 0 and counts.get(source[i], 0) == top:
			t[i] = source[i]
		else:
			t[i] = UNSURE
	return t


## Pixels of a template in 8-connected bits smaller than [param smallest]
## (what one instance's cut took from a neighbour).
static func specks(t: PackedInt32Array, w: int, h: int, smallest := 8) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	var seen := PackedByteArray()
	seen.resize(w * h)
	for i in w * h:
		if t[i] == EMPTY or seen[i]:
			continue
		var part: Array[int] = [i]
		var stack: Array[int] = [i]
		seen[i] = 1
		while not stack.is_empty():
			var j: int = stack.pop_back()
			var cx := j % w
			var cy := j / w
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := cx + dx
					var ny := cy + dy
					if nx >= 0 and nx < w and ny >= 0 and ny < h:
						var k := ny * w + nx
						if t[k] != EMPTY and not seen[k]:
							seen[k] = 1
							part.append(k)
							stack.append(k)
		if part.size() < smallest:
			for k in part:
				out[k] = 1
	return out


## A view made from another figure (its view as shown): colours swapped, the
## marks (remove: see-through, infill: to paint, add: the base source's pixel;
## in the base's box) and the owner's paint.
func _derive(f: Dictionary) -> Dictionary:
	var base: Dictionary = templates[f["from"]]
	var box: Array = figures[f["from"]]["box"]
	var w: int = base["w"]
	var h: int = base["h"]
	var bw: int = box[2]
	var bh: int = box[3]
	var ox: int = base["ox"]
	var oy: int = base["oy"]
	var swap: Array = f.get("swap", [])
	var t := recolour(base["t"], swap)
	var base_src: PackedInt32Array = base["source"]
	var src := recolour(base_src, swap)
	var add := runs(f, box, "add")
	var rem := runs(f, box, "remove")
	var inf := runs(f, box, "infill")
	for i in bw * bh:
		var k := (i / bw + oy) * w + i % bw + ox
		if add[i] and base_src[i] >= 0:
			t[k] = src[i]
		if rem[i]:
			t[k] = EMPTY
		if inf[i]:
			t[k] = INFILL
	for g: Array in f.get("graft", []):
		_graft(t, w, templates[g[0]], int(g[1]), int(g[2]), int(g[3]), int(g[4]), int(g[5]), int(g[6]))
	var out := apply_paint(t, w, h, f.get("paint", []))
	out["ox"] = int(out["ox"]) + ox
	out["oy"] = int(out["oy"]) + oy
	out["source"] = base_src
	return out


## The owner's combination: [param src]'s view as shown, the rect (x, y, gw,
## gh) from its box's top-left (EMPTY outside it), replaces [param t]'s
## (w wide) rect at (ax, ay), see-through included.
static func _graft(t: PackedInt32Array, w: int, src: Dictionary, x: int, y: int, gw: int, gh: int,
		ax: int, ay: int) -> void:
	var sw: int = src["w"]
	var sh: int = src["h"]
	var st: PackedInt32Array = src["t"]
	for r in gh:
		for q in gw:
			var sy := int(src["oy"]) + y + r
			var sx := int(src["ox"]) + x + q
			t[(ay + r) * w + ax + q] = st[sy * sw + sx] if sy >= 0 and sy < sh and sx >= 0 and sx < sw else EMPTY


## A view drawn from nothing: the owner's paint on an empty canvas [code]size[/code].
func _drawn(f: Dictionary) -> Dictionary:
	var size: Array = f["size"]
	var w := int(size[0])
	var h := int(size[1])
	var t := PackedInt32Array()
	t.resize(w * h)
	t.fill(EMPTY)
	var out := apply_paint(t, w, h, f.get("paint", []))
	out["source"] = t
	return out


## Where a [param w] x [param h] template lies once [param paint]ed:
## [left, top, w', h']. The canvas grows to take paint outside it: as much
## on both sides (a figure stands on its bottom centre), up, and down.
static func paint_canvas(w: int, h: int, paint: Array) -> Array:
	if paint.is_empty():
		return [0, 0, w, h]
	var x0 := 1 << 30
	var x1 := -(1 << 30)
	var y0 := 1 << 30
	var y1 := -(1 << 30)
	for run: Array in paint:
		x0 = mini(x0, int(run[0]))
		x1 = maxi(x1, int(run[0]) + int(run[2]) - 1)
		y0 = mini(y0, int(run[1]))
		y1 = maxi(y1, int(run[1]))
	var side := maxi(0, maxi(-x0, x1 - (w - 1)))
	var top := maxi(0, -y0)
	var bottom := maxi(0, y1 - (h - 1))
	return [side, top, w + 2 * side, h + top + bottom]


## [param t] (w x h) with the owner's [param paint] runs [x, y, length,
## colour] on its grown canvas: {w, h, t, ox, oy} (ox, oy: where [param t]'s
## top-left lies).
static func apply_paint(t: PackedInt32Array, w: int, h: int, paint: Array) -> Dictionary:
	var c := paint_canvas(w, h, paint)
	var left: int = c[0]
	var top: int = c[1]
	var nw: int = c[2]
	var nh: int = c[3]
	var out := t.duplicate()
	if nw != w or nh != h:
		out = PackedInt32Array()
		out.resize(nw * nh)
		out.fill(EMPTY)
		for r in h:
			for q in w:
				out[(r + top) * nw + q + left] = t[r * w + q]
	for run: Array in paint:
		var at := (int(run[1]) + top) * nw + int(run[0]) + left
		for k in int(run[2]):
			out[at + k] = int(run[3])
	return {"w": nw, "h": nh, "t": out, "ox": left, "oy": top}


## A template's checksum (crowd_lib.template_hash): row-major,
## h = h * 31 + value + 8, 32 bits.
static func template_hash(t: PackedInt32Array) -> int:
	var hv := 0
	for v in t:
		hv = (hv * 31 + v + 8) & 0xFFFFFFFF
	return hv
