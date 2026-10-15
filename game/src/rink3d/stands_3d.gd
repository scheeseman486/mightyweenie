class_name MwStands3D
extends Node3D
## The stands and their crowd in 3D (plan 15, docs/rink3d.md, Crowd): tiers,
## seat bars and the figures (MwStands' layout), the figures cut from the ROM
## at load (MwCrowd) into one indexed atlas. Static: built once, drawn as
## three meshes (tiers, seats, a MultiMesh of figure billboards,
## rink3d_crowd.gdshader; screen billboards as the players' since plan 32,
## [member billboards]). The stadium's colours come from [member palette];
## each fan wears his team's (MwCrowdMix, [member variety]). Presentation
## only.
##
## The crowd's life (plans 30-31, [method show_life]): the figures sway, hop
## and turn in the crowd shader as MwCrowdLife's snapshot of the pass says
## (livelier with the game's crowd level, the leading team's fans more, a
## wave round the stands in a quiet spell): repeatable from its seed, kept
## with the replay's frames. Its seed also deals who sits where ([method
## deal], MwStands.deal; owner, 2026-10-09): a new crowd every match, the
## same in its replays.
##
## The crowd makes way ([method make_way], owner, 2026-10-09): the fans
## between the camera and a thing on the ice that they hide sink behind
## their seats, those near it side to side less and less (MwCrowdDuck).

const S := MwRink3D.METRES_PER_PX
const CROWD_SHADER := preload("res://src/rink3d/rink3d_crowd.gdshader")
const STANDS_SHADER := preload("res://src/rink3d/rink3d_stands.gdshader")
const ATLAS_W := 512
const PATH_STEP := 4.0          # px between path samples of the tiers and bars
## Where Satan stands (rink px: x, y of his feet: the picture's spot) and
## faces (the rink): the winged devil the rink picture paints in the right
## pen, between the penalty boxes (owner's name, 2026-10-11; not the
## referee).
const SATAN_AT := Vector2(235, 7)
const SATAN_FACING := Vector2(-1, 0)
## Satan turns (mirrors) to face the play once it is this far (rink px,
## across the screen) to his other side (owner: a mirror is all he needs).
const SATAN_TURN_PX := 24.0
## Satan makes way (owner, 2026-10-11: players went through him - he slides
## aside as they come out, maybe with a subtle walking hop): the picture's
## spot is in the lane the game's players come on along (from the bench door,
## 265, 10, straight west) and go off by. While a figure (a player, a bench or
## box figure, the opening's players) stands within SATAN_CLEAR px of his
## spot in the east hallway, he walks to SATAN_ASIDE - its north side, away
## from the follow camera, so they pass in front of him; his drawing, at most
## 20 px either side of his feet, clear of the hallway's walls (|y| 40) and
## the pens' corners from any side - and once his spot has been clear for
## SATAN_WAIT s he walks back, at SATAN_SPEED px/s, a little hop to each
## step (SATAN_HOP px, SATAN_STEP px a step). If something comes near the
## side too, he keeps to whichever of the two is clearer ([method
## satan_next]).
const SATAN_ASIDE := Vector2(235, -18)
const SATAN_CLEAR := 44.0
const SATAN_WAIT := 0.6
const SATAN_SPEED := 90.0
const SATAN_HOP := 2.0
const SATAN_STEP := 12.5
## Figures deeper in the hallway than this (x) don't count: a player coming
## on at the bench door (265) does - he is aside by the time the player
## reaches his spot -, the figures waiting at the exits (270), in the dark,
## don't.
const SATAN_SEES_TO := 267.0
## The top rows fade to black (owner, plan 16; 2026-10-11: more obvious - from
## twice the rows, a sharper ramp): from just above row 5's tread (of 10: rows
## 5-10 fade, were 8-10) to the top of the back wall (rink px above the ice),
## the smoothstep's brightness squared (FADE_POWER): row 6's heads at half,
## rows 9 and 10 nearly black.
const FADE_FROM := MwStands.H0 + 4 * MwStands.RISE + 8
const FADE_TO := MwStands.H0 + (MwStands.ROWS - 1) * MwStands.RISE + 3 * MwStands.RISE
const FADE_POWER := 2.0
## The boards' top (the far glass's, rink px): the edge the game's cameras
## look over ([method cutaway]).
const BOARDS_TOP := MwRinkShape.BOARDS_TOP
## A fan's team rides on his rects' x (atlas px): x + TEAM_STRIDE * (team + 1);
## 0 (Satan, or no [member variety]): the palette as it is.
const TEAM_STRIDE := 1024.0

## The stadium's palette (the rink's). Its teams and stadium also pick the
## crowd's mix; changes are followed.
var palette: RomPalette:
	set(v):
		if palette and palette.changed.is_connected(_palette_changed):
			palette.changed.disconnect(_palette_changed)
		palette = v
		if palette:
			palette.changed.connect(_palette_changed)
		_update_palette()

## Whose fans the crowd are (plan 16 amendment, owner): each fan wears the
## colours of the team he supports (MwCrowdMix: the home team's groups, the
## away teams', anyone else's). Off: every fan in team A's, as the original.
var variety := true:
	set(v):
		variety = v
		_update_teams()

## The team each seat supports (MwCrowdMix.assign; empty with
## [member variety] off).
var fan_teams := PackedInt32Array()
## Line 1 of the palette as each team would have it: 16 x 23 colours, row t
## built with team t as team A. What a fan of team t wears.
var team_lines: Image

## The share of seats taken (0 empty .. 1 full house). Seats fill in a fixed
## random order, so any share spreads evenly over the stands; Satan is
## always there.
var occupancy := 1.0:
	set(v):
		occupancy = clampf(v, 0.0, 1.0)
		_update_occupancy()

## How the figures (and Satan) stand (plan 32, owner: the crowd and the
## referee drawn as billboards, as the players are): on, each is a quad in
## the screen's plane at his feet, his pixels square on screen at any
## distance as the rink's sprites are, his depth that of the drawing
## standing upright there facing the camera (rink3d_crowd); off, a card
## standing upright on his tread turned to the camera (plans 15-31), which
## the high cameras see squashed.
var billboards := true:
	set(v):
		billboards = v
		if _crowd_material:
			_crowd_material.set_shader_parameter("screen_billboards", v)

## Figures nearer the camera than this (rink px, to their middle) are not
## drawn: for cameras among the crowd (0: all drawn).
var near_hide_px := 0.0:
	set(v):
		near_hide_px = maxf(v, 0.0)
		if _crowd_material:
			_crowd_material.set_shader_parameter("near_hide", near_hide_px * S)

var crowd: MwCrowd
var seats: Array = []
var atlas: Image
var rects := {}                 # variant key -> Rect2i in the atlas
var _materials: Array[ShaderMaterial] = []
var _figures: MultiMesh
var _crowd_material: ShaderMaterial
var _satan_looks_right := false    # his drawing looks left (at the rink, from his pen)
## Where Satan is and where he goes ([method satan_next]: at, goal,
## clear, hop).
var satan := {"at": SATAN_AT, "goal": SATAN_AT, "clear": SATAN_WAIT, "hop": 0.0, "walked": 0.0}
var _order := PackedInt32Array()  # instance n + 1 shows seat _order[n]
var _teams_for := []             # what fan_teams were made for
var _refresh_queued := false

## The crowd's life shown last (MwCrowdLife.snapshot; {} none yet).
var life_shown := {}
## The things the crowd makes way for, and their wakes ([method make_way]).
var duck := MwCrowdDuck.new()
## The seed the seats were dealt with ([method deal]).
var dealt := 0


func _ready() -> void:
	build()


## Cuts the crowd from the ROM and makes the stands' meshes (once). Safe off
## the scene tree and on a worker thread (plan 20, MwRink3DHost); [method
## _ready] does it if nobody did.
func build() -> void:
	if crowd != null or not MwRom.available():
		return
	crowd = MwCrowd.new()
	crowd.build(MwRom.data())
	seats = MwStands.seats(crowd.data, dealt)
	_build_atlas()
	_build_tiers()
	_build_figures()
	_update_palette()


# --- atlas ---------------------------------------------------------------------------

func _key(figure: String, team: bool, swap: Array) -> String:
	return "%s|%d|%s" % [figure, int(team), str(swap)]


## Packs every view a seat can show (figure x team brown x colour swap,
## MwStands.variants: any deal) into one R8 atlas, shelf by shelf.
func _build_atlas() -> void:
	var wanted := {}
	for v: Array in MwStands.variants(crowd.data):
		wanted[_key(v[0], v[1], v[2])] = v
	wanted[_key("satan", false, [])] = ["satan", false, []]
	var keys := wanted.keys()
	keys.sort()
	var x := 0
	var y := 0
	var shelf := 0
	var images := {}
	for key: String in keys:
		var v: Array = wanted[key]
		var t: Dictionary = crowd.template(v[0])
		var w: int = t["w"]
		var h: int = t["h"]
		if x + w > ATLAS_W:
			x = 0
			y += shelf + 1
			shelf = 0
		rects[key] = Rect2i(x, y, w, h)
		images[key] = _pixels(t, v[1], v[2])
		x += w + 1
		shelf = maxi(shelf, h)
	var ah := y + shelf
	var px := PackedByteArray()
	px.resize(ATLAS_W * ah)
	for key: String in keys:
		var r: Rect2i = rects[key]
		var src: PackedByteArray = images[key]
		for row in r.size.y:
			for col in r.size.x:
				px[(r.position.y + row) * ATLAS_W + r.position.x + col] = src[row * r.size.x + col]
	atlas = Image.create_from_data(ATLAS_W, ah, false, Image.FORMAT_R8, px)


## A template as atlas pixels: its colours (team brown, swaps), 0 elsewhere.
func _pixels(t: Dictionary, team: bool, swap: Array) -> PackedByteArray:
	var src: PackedInt32Array = MwCrowd.recolour(t["t"], swap)
	var out := PackedByteArray()
	out.resize(src.size())
	for i in src.size():
		var v := src[i]
		if v < 0:
			continue
		if team and v == MwCrowd.BROWN:
			v = MwCrowd.TEAM_BROWN
		out[i] = v
	return out


# --- the stands ----------------------------------------------------------------------

func _world(point: Vector2, z: float) -> Vector3:
	return MwRink3D.world(point.x, point.y, z)


## Points along a row's path [param d] px outside the boards: the left half,
## then its mirror, as two polylines [{p, n}].
func _paths(d: float) -> Array:
	var left: Array = []
	for u in MwStands.path_us(PATH_STEP):
		left.append(MwStands.point_at_u(d, u))
	var right: Array = []
	for at: Dictionary in left:
		right.append({"p": Vector2(-at["p"].x, at["p"].y), "n": Vector2(-at["n"].x, at["n"].y), "seg": at["seg"]})
	return [left, right]


## Why row [param k] stops at a path point (MwStands.Cut: not, the pens, a
## hallway).
func _cut(k: int, at: Dictionary) -> int:
	return MwStands.cut(k, at["seg"], at["p"])


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, kind: int) -> void:
	var col := Color(kind / 4.0, 0, 0)
	for v in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
		st.set_color(col)
		st.set_uv(v[1])
		st.add_vertex(v[0])


func _build_tiers() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in MwStands.ROWS:
		var d0 := MwStands.offset(k)
		var d1 := d0 + MwStands.DEPTH
		var h := MwStands.height(k)
		var below := MwStands.height(k - 1) if k > 0 else 0.0
		var ds := d0 + MwStands.SEAT_AT * MwStands.DEPTH
		var front := _paths(d0)
		var back := _paths(d1)
		var seat := _paths(ds)
		var seat_back := _paths(ds + MwStands.SEAT_T)
		for half in 2:
			var f: Array = front[half]
			var b: Array = back[half]
			var sf: Array = seat[half]
			var sb: Array = seat_back[half]
			var u := 0.0
			for i in f.size() - 1:
				var step: float = (f[i + 1]["p"] - f[i]["p"]).length()
				var cut_a := _cut(k, f[i])
				var cut_b := _cut(k, f[i + 1])
				if cut_a != MwStands.Cut.NONE or cut_b != MwStands.Cut.NONE:
					# where the row stops (for the pens or a hallway): its end closed, a black
					# face from the floor to the tread (the rows behind step up)
					if (cut_a == MwStands.Cut.NONE) != (cut_b == MwStands.Cut.NONE):
						var j := i if cut_a == MwStands.Cut.NONE else i + 1
						var front_end: Vector2 = f[j]["p"]
						var eb: Vector2 = b[j]["p"]
						_quad(st, _world(front_end, 0.0), _world(eb, 0.0), _world(eb, h), _world(front_end, h),
								Vector2(0, h), Vector2(MwStands.DEPTH, h), Vector2(MwStands.DEPTH, 0), Vector2(0, 0), 1)
					u += step
					continue
				var fa: Vector2 = f[i]["p"]
				var fb: Vector2 = f[i + 1]["p"]
				var ba: Vector2 = b[i]["p"]
				var bb: Vector2 = b[i + 1]["p"]
				# tread
				_quad(st, _world(fa, h), _world(fb, h), _world(bb, h), _world(ba, h),
						Vector2(u, 0), Vector2(u + step, 0), Vector2(u + step, MwStands.DEPTH),
						Vector2(u, MwStands.DEPTH), 0)
				# riser up to it: from the row in front's tread, or from the floor where that row
				# stops at the pens (over a hallway it stays: the hallway's roof)
				var from := below
				if k > 0 and _cut(k - 1, f[i]) == MwStands.Cut.PEN:
					from = 0.0
				_quad(st, _world(fa, from), _world(fb, from), _world(fb, h), _world(fa, h),
						Vector2(u, h - from), Vector2(u + step, h - from), Vector2(u + step, 0), Vector2(u, 0), 1)
				# the seat bar: faces towards the rink and away, and its top
				var z0 := h + MwStands.SEAT_Z
				var z1 := z0 + MwStands.SEAT_H
				var sa: Vector2 = sf[i]["p"]
				var sbb: Vector2 = sf[i + 1]["p"]
				var ta: Vector2 = sb[i]["p"]
				var tb: Vector2 = sb[i + 1]["p"]
				for face: Array in [[sa, sbb], [ta, tb]]:
					_quad(st, _world(face[0], z1), _world(face[1], z1), _world(face[1], z0), _world(face[0], z0),
							Vector2(u, 0), Vector2(u + step, 0), Vector2(u + step, MwStands.SEAT_H),
							Vector2(u, MwStands.SEAT_H), 2)
				_quad(st, _world(sa, z1), _world(sbb, z1), _world(tb, z1), _world(ta, z1),
						Vector2(u, 0), Vector2(u + step, 0), Vector2(u + step, MwStands.SEAT_T),
						Vector2(u, MwStands.SEAT_T), 3)
				u += step
		# the last row's back wall
		if k == MwStands.ROWS - 1:
			for half in 2:
				var b: Array = back[half]
				var u2 := 0.0
				for i in b.size() - 1:
					var step2: float = (b[i + 1]["p"] - b[i]["p"]).length()
					_quad(st, _world(b[i]["p"], h), _world(b[i + 1]["p"], h),
							_world(b[i + 1]["p"], h + 3 * MwStands.RISE),
							_world(b[i]["p"], h + 3 * MwStands.RISE), Vector2(u2, 0), Vector2(u2 + step2, 0),
							Vector2(u2 + step2, 0), Vector2(u2, 0), 1)
					u2 += step2
	var mi := MeshInstance3D.new()
	mi.name = "Tiers"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = STANDS_SHADER
	m.set_shader_parameter("fade_from", FADE_FROM)
	m.set_shader_parameter("fade_to", FADE_TO)
	m.set_shader_parameter("fade_power", FADE_POWER)
	_materials.append(m)
	mi.material_override = m
	add_child(mi)


# --- the figures ---------------------------------------------------------------------

func _quad_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0),
			Vector3(-0.5, 1, 0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# the quads move in the vertex shader: give culling a box the size of a figure
	mesh.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	return mesh


## A view's rect in the atlas as the shader takes it (rink3d_crowd); a fan's
## [param team] (-1: none) rides on its x.
func _rect(key: String, mirrored: bool, team := -1) -> Color:
	var r: Rect2i = rects[key]
	return Color(r.position.x + TEAM_STRIDE * (team + 1), r.position.y,
			-r.size.x if mirrored else r.size.x, r.size.y)


func _place(mm: MultiMesh, i: int, at: Vector2, z: float, facing: Vector2, front: Color, back: Color) -> void:
	var zf := Vector3(facing.x, 0, facing.y).normalized()
	var facing_basis := Basis(Vector3.UP.cross(zf), Vector3.UP, zf)
	mm.set_instance_transform(i, Transform3D(facing_basis, MwRink3D.world(at.x, at.y, z)))
	mm.set_instance_custom_data(i, front)
	mm.set_instance_color(i, back)


func _build_figures() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _quad_mesh()
	mm.instance_count = seats.size() + 1
	# Satan first, then the seats in their filling order (occupancy)
	var r := _rect(_key("satan", false, []), false)
	_place(mm, 0, satan["at"], satan["hop"], SATAN_FACING, r, r)
	_satan_looks_right = false
	var order := range(seats.size())
	var keys := []
	for seat: Dictionary in seats:
		keys.append(_fill_key(seat))
	order.sort_custom(func(a, b): return keys[a] < keys[b])
	_order = PackedInt32Array(order)
	for n in order.size():
		var seat: Dictionary = seats[order[n]]
		var pos: Vector3 = seat["stand"]      # (stepped across the tread: no two neighbours in one plane)
		_place(mm, n + 1, Vector2(pos.x, pos.y), pos.z, seat["facing"],
				_rect(_key(seat["front"], seat["team"], seat["swap"]), seat["mirrored"]),
				_rect(_key(seat["back"], seat["team"], seat["swap"]), seat["mirrored"]))
	_figures = mm
	_update_occupancy()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Figures"
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = CROWD_SHADER
	m.set_shader_parameter("atlas", ImageTexture.create_from_image(atlas))
	m.set_shader_parameter("near_hide", near_hide_px * S)
	m.set_shader_parameter("screen_billboards", billboards)
	m.set_shader_parameter("chant_beats", Vector3(MwChant.STOMPS[0], MwChant.STOMPS[1], MwChant.CLAP))
	_crowd_material = m
	m.set_shader_parameter("fade_from", FADE_FROM)
	m.set_shader_parameter("fade_to", FADE_TO)
	m.set_shader_parameter("fade_power", FADE_POWER)
	_materials.append(m)
	mmi.material_override = m
	add_child(mmi)


## Shows the crowd as [param snap] says (MwCrowdLife.snapshot, blended
## between passes; plans 30-31): who sits where (dealt from its seed,
## [method deal]), the crowd shader's uniforms - the seed, the clock, the
## liveliness, the lead's teams (from [member palette]) and lift, the wave.
## The same snapshot draws the same crowd.
func show_life(snap: Dictionary) -> void:
	life_shown = snap
	if _crowd_material == null or snap.is_empty():
		return
	deal(int(snap.get("seed", 0)))
	var m := _crowd_material
	m.set_shader_parameter("crowd_seed", float(int(snap.get("seed", 0)) % 9973) * 0.731)
	m.set_shader_parameter("crowd_time", float(snap.get("ticks", 0)) / MwCrowdLife.TICKS_PER_S)
	m.set_shader_parameter("liveliness", float(snap.get("life", MwCrowdLife.LIFE_CALM)))
	var lead := int(snap.get("lead", 0))
	var teams := [palette.team_a, palette.team_b] if palette else [0, 1]
	m.set_shader_parameter("lead_team", int(teams[0 if lead > 0 else 1]) + 1 if lead != 0 and variety else 0)
	m.set_shader_parameter("trail_team", int(teams[1 if lead > 0 else 0]) + 1 if lead != 0 and variety else 0)
	m.set_shader_parameter("lead_lift", float(snap.get("lift", 0.0)))
	m.set_shader_parameter("wave_angle", float(snap.get("wave_angle", 0.0)))
	m.set_shader_parameter("wave_amp", float(snap.get("wave_amp", 0.0)))


## The match's opening's chant (plan 33, MwChant): [param time] s since its
## sample last started (< 0: no chant), [param period] s from one start to
## the next, [param first]: its first bar (no fan jumps before the sound).
## About 80% of the fans jump on the two stomps, landing on their peaks, and
## shake on the clap (rink3d_crowd); the rest go on as they were.
func chant(time: float, period := 1.55, first := false) -> void:
	if _crowd_material == null:
		return
	_crowd_material.set_shader_parameter("chant_time", time)
	_crowd_material.set_shader_parameter("chant_period", period)
	_crowd_material.set_shader_parameter("chant_first", first)


## The crowd makes way for [param things] (MwCrowdDuck.things: the players,
## the puck, the referee, the nets, the standing objects and, during a goal,
## the lamps' skulls as this frame shows them), stepped by [param dt] s (the rendered frame's
## time): the fans who hide the rink in front of them on the screen sink
## behind their seats as far as they must, those near them side to side
## less, and rise again when they have gone by; [param scoring] (a goal):
## a wider, gentler curve (MwCrowdDuck, rink3d_crowd's duck_px).
func make_way(things: Array, dt: float, scoring := false) -> void:
	duck.update(things, dt, scoring)
	_write_duck(duck.points())


## Every fan stands up again at once, the things forgotten (the switch off,
## the calibration camera).
func clear_way() -> void:
	if duck.tracks.is_empty() and duck.ghosts.is_empty():
		return
	duck.clear()
	_write_duck([])


## Hands MwCrowdDuck's points to the crowd shader: their ice points in the
## world (the world may be scaled: the ortho camera's), weights, drawings.
func _write_duck(points: Array) -> void:
	if _crowd_material == null:
		return
	var at := PackedVector4Array()
	var rect := PackedVector4Array()
	at.resize(MwCrowdDuck.MAX_POINTS)
	rect.resize(MwCrowdDuck.MAX_POINTS)
	var n := mini(points.size(), MwCrowdDuck.MAX_POINTS)
	var xf := global_transform if is_inside_tree() else transform
	for i in n:
		var point: Vector2 = points[i][0]
		var w := xf * MwRink3D.world(point.x, point.y, 0)
		at[i] = Vector4(w.x, w.y, w.z, points[i][2])
		rect[i] = points[i][1]
	_crowd_material.set_shader_parameter("duck_at", at)
	_crowd_material.set_shader_parameter("duck_rect", rect)
	_crowd_material.set_shader_parameter("duck_count", n)
	_crowd_material.set_shader_parameter("duck_goal", duck.goal_share())
	_crowd_material.set_shader_parameter("duck_scale", xf.basis.get_scale())


## Deals the seats their fans from [param seed_] (MwStands.deal) unless
## they were dealt from it; the figures follow.
func deal(seed_: int) -> void:
	if seed_ == dealt or crowd == null:
		return
	dealt = seed_
	MwStands.deal(seats, crowd.data, seed_)
	_write_rects()


## A seat's place in the filling order: a fixed hash of where it is (the
## engine's hash() of its point and row as it has always been, MwSeed: the
## same order whatever a later engine's hash() does - plan 40, B5).
static func _fill_key(seat: Dictionary) -> int:
	var point: Vector3 = seat["pos"]
	var h := MwSeed.engine_hash_ints(roundi(point.x * 4.0), roundi(point.y * 4.0), int(seat["row"]))
	return MwSeed.knuth(h) & 0x7FFFFFFF


## The seats drawn at this [member occupancy] (indices into [member
## seats]), in their filling order: a fuller house adds seats, never moves
## any.
func shown_seats() -> PackedInt32Array:
	return _order.slice(0, roundi(occupancy * seats.size()))


func _update_occupancy() -> void:
	if _figures:
		_figures.visible_instance_count = 1 + roundi(occupancy * seats.size())


## Whether a fan shows his drawing mirrored (as rink3d_crowd does it): four
## views, Doom's rule (owner). His true front is his row's facing
## ([param facing], rink x, y). The ROM has no straight-on views: its front
## drawings face front-right, its back drawings back-right (owner); mirrored,
## front-left and back-left. Front or back by the camera's side of him (the
## shader's); left or right by which way his true front points across his
## line of sight ([param sight]: from the camera to him, rink x, y), the same
## for both: mirrored when it points to the screen's left.
static func shown_mirrored(facing: Vector2, sight: Vector2) -> bool:
	var across := facing.dot(Vector2(-sight.y, sight.x))      # > 0: towards the screen's right
	return across < 0.0


## Whether Satan is mirrored to look right ([method watch]).
func satan_looks_right() -> bool:
	return _satan_looks_right


## Satan in his pen watches the play (plan 16): his one drawing looks
## left from the original's camera; seen from [param cam], he is mirrored to
## look right once the puck at [param puck] (rink px) is more than
## [constant SATAN_TURN_PX] to his right on the screen, and back once it is as
## far to his left.
func watch(puck: Vector3, cam: Camera3D) -> void:
	if _figures == null or cam == null:
		return
	var b := cam.global_transform.basis if cam.is_inside_tree() else cam.transform.basis
	var right := Vector3(b.x.x, 0, b.x.z).normalized()
	var at: Vector2 = satan["at"]
	var d := MwRink3D.world(puck.x, puck.y, 0) - MwRink3D.world(at.x, at.y, 0)
	var across := d.dot(right) / S
	var looks_right := _satan_looks_right
	if across > SATAN_TURN_PX:
		looks_right = true
	elif across < -SATAN_TURN_PX:
		looks_right = false
	if looks_right != _satan_looks_right:
		_satan_looks_right = looks_right
		var r := _rect(_key("satan", false, []), looks_right)
		_figures.set_instance_custom_data(0, r)
		_figures.set_instance_color(0, r)


## The figures Satan makes way for (rink px, x y): of [param items]
## (MwRinkDraw3D's, as a frame shows them) the standing bodies - players,
## bench and box figures, the opening's players - in the east hallway and
## round its mouth, short of its dark (SATAN_SEES_TO).
static func satan_figures(items: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for it: Dictionary in items:
		var key: String = it.get("key", "")
		if not key.ends_with("/body") or key == "puck/body" or int(it.get("place", -1)) != MwRinkDraw3D.UPRIGHT:
			continue
		var at: Vector3 = it["at"]
		if at.x > MwStands.BOARD.x and at.x < SATAN_SEES_TO and absf(at.y) < 60.0:
			out.append(Vector2(at.x, at.y))
	return out


## Satan's next state ([member satan]: at, goal, clear - s his spot has
## been clear -, hop - px up -, walked - px, the steps' phase) [param dt] s on,
## the [param figures] (rink px) about: his goal is his spot, or the side
## while something is within SATAN_CLEAR of his spot (the clearer of the two
## if something is near both), back to his spot once it has been clear for
## SATAN_WAIT; he walks towards his goal at SATAN_SPEED, hopping SATAN_HOP px
## a step.
static func satan_next(state: Dictionary, figures: PackedVector2Array, dt: float) -> Dictionary:
	var out := state.duplicate()
	var near_home := INF
	var near_aside := INF
	for f in figures:
		near_home = minf(near_home, f.distance_to(SATAN_AT))
		near_aside = minf(near_aside, f.distance_to(SATAN_ASIDE))
	var goal: Vector2 = state["goal"]
	var clear: float = state["clear"]
	if near_home < SATAN_CLEAR:
		clear = 0.0
		goal = SATAN_ASIDE if near_aside > near_home else SATAN_AT
	else:
		clear += dt
		if clear >= SATAN_WAIT:
			goal = SATAN_AT
	var at: Vector2 = state["at"]
	var step := SATAN_SPEED * dt
	var to := goal - at
	var walked: float = state["walked"]
	if to.length() <= step:
		at = goal
		walked = 0.0
	else:
		at += to.normalized() * step
		walked += step
	out["at"] = at
	out["goal"] = goal
	out["clear"] = clear
	out["walked"] = walked
	out["hop"] = absf(sin(PI * walked / SATAN_STEP)) * SATAN_HOP if walked > 0.0 else 0.0
	return out


## Satan makes way for [param figures] (rink px, [method satan_figures])
## this rendered frame, [param dt] s after the last (0: no time, he stays).
func satan_make_way(figures: PackedVector2Array, dt: float) -> void:
	if dt <= 0.0:
		return
	var was: Vector2 = satan["at"]
	var hop_was: float = satan["hop"]
	satan = satan_next(satan, figures, dt)
	if _figures != null and (satan["at"] != was or satan["hop"] != hop_was):
		var zf := Vector3(SATAN_FACING.x, 0, SATAN_FACING.y).normalized()
		var at: Vector2 = satan["at"]
		_figures.set_instance_transform(0, Transform3D(Basis(Vector3.UP.cross(zf), Vector3.UP, zf),
				MwRink3D.world(at.x, at.y, satan["hop"])))


## Cutaway for the game's cameras (plan 16): with [param cam] beyond the
## boards at [param boards_y] (rink px: 372 near, -372 far), the stands
## between it and the rink that rise above its line of sight over those
## boards' top would hide the play, and are not drawn
## (rink3d_stands_common). A null camera, or one not beyond them: all drawn.
func cutaway(cam: Camera3D, boards_y := 0.0) -> void:
	var c := Vector3.ZERO
	if cam != null:
		c = cam.global_position if cam.is_inside_tree() else cam.position
		if is_inside_tree() and cam.is_inside_tree():
			c = to_local(c)                 # the world may be scaled (the ortho camera)
	var plane := cut_plane(c, boards_y if cam != null else 0.0)
	for m in _materials:
		m.set_shader_parameter("cut_enabled", plane["on"])
		m.set_shader_parameter("cut_origin", plane["origin"])
		m.set_shader_parameter("cut_normal", plane["normal"])
		m.set_shader_parameter("cut_side", plane["side"])


## The cut for a camera at world point [param c] over the boards at
## [param boards_y] (see [method cutaway]): {on, origin, normal, side}.
static func cut_plane(c: Vector3, boards_y: float) -> Dictionary:
	var origin := MwRink3D.world(0, boards_y, BOARDS_TOP)
	var side := signf(boards_y)
	var out := {"on": false, "origin": origin, "normal": Vector3.UP, "side": side}
	if boards_y != 0.0 and (c.z - origin.z) * side > 0.0:
		var n := Vector3(0, -(c.z - origin.z), c.y - origin.y).normalized()
		out["on"] = true
		out["normal"] = -n if n.y < 0.0 else n
	return out


## Whether world point [param w] is cut away by [param plane] (cut_plane;
## as rink3d_stands_common does it).
static func is_cut(plane: Dictionary, w: Vector3) -> bool:
	var o: Vector3 = plane["origin"]
	return plane["on"] and (w.z - o.z) * float(plane["side"]) > 0.0 and (plane["normal"] as Vector3).dot(w - o) > 0.0


## The brightness of the stands at height [param z] (rink px; as
## rink3d_stands_common does it): the top rows fade to black.
static func fade(z: float) -> float:
	return pow(1.0 - smoothstep(FADE_FROM, FADE_TO, z), FADE_POWER)


func _update_palette() -> void:
	var tex: Texture2D = palette.texture() if palette else null
	for m in _materials:
		m.set_shader_parameter("palette", tex)
	_update_teams()


## The palette's colours, teams or stadium changed (one refresh for a batch
## of changes).
func _palette_changed() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		refresh.call_deferred()


## Follows the palette now (normally deferred after its changes).
func refresh() -> void:
	_refresh_queued = false
	_update_palette()


## Picks who each fan supports for the palette's match (MwCrowdMix) and
## dresses the figures in their teams' colours.
func _update_teams() -> void:
	if _figures == null:
		return
	var on := variety and palette != null and MwRom.available()
	# a custom team's working copy gone (the editor left) before a deferred
	# refresh: no teams to dress the fans in until the palette names others
	if on and maxi(maxi(palette.team_a, palette.team_b), palette.stadium) >= MwCustomTeams.readable():
		on = false
	var made_for := [palette.team_a, palette.team_b, palette.stadium, palette.screen, palette.steps,
			MwCustomTeams.version] if on else []
	if made_for == _teams_for:
		return
	_teams_for = made_for
	fan_teams = PackedInt32Array()
	if on:
		fan_teams = MwCrowdMix.assign(seats, palette.team_a, palette.team_b, palette.stadium,
				MwCrowdMix.skulls(MwRom.data()))
		team_lines = lines_by_team(palette)
		_crowd_material.set_shader_parameter("team_lines", ImageTexture.create_from_image(team_lines))
	_write_rects()


## Every fan's views (front, back) in the figures' instances, as dealt and
## in the colours of the team he supports.
func _write_rects() -> void:
	if _figures == null:
		return
	for n in _order.size():
		var i := _order[n]
		var seat: Dictionary = seats[i]
		var team := fan_teams[i] if fan_teams.size() == seats.size() else -1
		_figures.set_instance_custom_data(n + 1, _rect(_key(seat["front"], seat["team"], seat["swap"]),
				seat["mirrored"], team))
		_figures.set_instance_color(n + 1, _rect(_key(seat["back"], seat["team"], seat["swap"]), seat["mirrored"],
				team))


## Line 1 of [param base] as each team would have it (16 x every team's
## colours - the custom teams' after the original's 23 - row t with team t
## as team A): the crowd's colours by the team a fan supports.
static func lines_by_team(base: RomPalette) -> Image:
	var img := Image.create_empty(16, MwCustomTeams.readable(), false, Image.FORMAT_RGBA8)
	for t in MwCustomTeams.readable():
		var words := RomPalette.derived(base, PackedStringArray(), t).colours()
		for i in 16:
			var c := MwGfx.color(words[16 + i])
			c.a = 0.0 if i == 0 else 1.0
			img.set_pixel(i, t, c)
	return img
