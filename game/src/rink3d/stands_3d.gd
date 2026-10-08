class_name MwStands3D
extends Node3D
## The stands and their crowd in 3D (plan 15, docs/rink3d.md, Crowd): tiers,
## seat bars and the figures (MwStands' layout), the figures cut from the ROM
## at load (MwCrowd) into one indexed atlas. Static: built once, drawn as
## three meshes (tiers, seats, a MultiMesh of figure billboards,
## rink3d_crowd.gdshader). The stadium's colours come from [member palette];
## each fan wears his team's (MwCrowdMix, [member variety]). Presentation
## only.

const S := MwRink3D.METRES_PER_PX
const CROWD_SHADER := preload("res://src/rink3d/rink3d_crowd.gdshader")
const STANDS_SHADER := preload("res://src/rink3d/rink3d_stands.gdshader")
const ATLAS_W := 512
const PATH_STEP := 4.0          # px between path samples of the tiers and bars
## Where the pen's referee stands (rink px: x, y of its feet) and faces (the rink).
const REF_AT := Vector2(235, 7)
const REF_FACING := Vector2(-1, 0)
## The referee turns (mirrors) to face the play once it is this far (rink px,
## across the screen) to his other side (owner: a mirror is all he needs).
const REF_TURN_PX := 24.0
## The top rows fade to black (owner, plan 16): from just above row 8's
## tread (of 10; row 7's heads stay bright) to the top of the back wall
## (rink px above the ice).
const FADE_FROM := MwStands.H0 + 7 * MwStands.RISE + 8
const FADE_TO := MwStands.H0 + (MwStands.ROWS - 1) * MwStands.RISE + 3 * MwStands.RISE
## The boards' top (the far glass's, rink px): the edge the game's cameras
## look over ([method cutaway]).
const BOARDS_TOP := 48.0
## A fan's team rides on his rects' x (atlas px): x + TEAM_STRIDE * (team + 1);
## 0 (the referee, or no [member variety]): the palette as it is.
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
## random order, so any share spreads evenly over the stands; the pen's
## referee is always there.
var occupancy := 1.0:
	set(v):
		occupancy = clampf(v, 0.0, 1.0)
		_update_occupancy()

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
var _ref_looks_right := false    # his drawing looks left (at the rink, from his pen)
var _order := PackedInt32Array()  # instance n + 1 shows seat _order[n]
var _teams_for := []             # what fan_teams were made for
var _refresh_queued := false


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
	seats = MwStands.seats(crowd.data)
	_build_atlas()
	_build_tiers()
	_build_figures()
	_update_palette()


# --- atlas ---------------------------------------------------------------------------

func _key(figure: String, team: bool, swap: Array) -> String:
	return "%s|%d|%s" % [figure, int(team), str(swap)]


## Packs every view a seat shows (figure x team brown x colour swap) into one
## R8 atlas, shelf by shelf.
func _build_atlas() -> void:
	var wanted := {}
	for s: Dictionary in seats:
		for side in ["front", "back"]:
			wanted[_key(s[side], s["team"], s["swap"])] = [s[side], s["team"], s["swap"]]
	wanted[_key("pen_ref", false, [])] = ["pen_ref", false, []]
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

func _world(p: Vector2, z: float) -> Vector3:
	return MwRink3D.world(p.x, p.y, z)


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


## Whether a row [param k]'s path point is cut by the pens.
func _in_pens(k: int, at: Dictionary) -> bool:
	return at["seg"] == MwStands.Seg.SIDE and absf(at["p"].y) < MwStands.PEN_Y and MwStands.offset(k) < MwStands.PEN_CLEAR


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
				if _in_pens(k, f[i]) or _in_pens(k, f[i + 1]):
					u += step
					continue
				var fa: Vector2 = f[i]["p"]
				var fb: Vector2 = f[i + 1]["p"]
				var ba: Vector2 = b[i]["p"]
				var bb: Vector2 = b[i + 1]["p"]
				# tread
				_quad(st, _world(fa, h), _world(fb, h), _world(bb, h), _world(ba, h),
						Vector2(u, 0), Vector2(u + step, 0), Vector2(u + step, MwStands.DEPTH), Vector2(u, MwStands.DEPTH), 0)
				# riser up to it
				_quad(st, _world(fa, below), _world(fb, below), _world(fb, h), _world(fa, h),
						Vector2(u, h - below), Vector2(u + step, h - below), Vector2(u + step, 0), Vector2(u, 0), 1)
				# the seat bar: faces towards the rink and away, and its top
				var z0 := h + MwStands.SEAT_Z
				var z1 := z0 + MwStands.SEAT_H
				var sa: Vector2 = sf[i]["p"]
				var sbb: Vector2 = sf[i + 1]["p"]
				var ta: Vector2 = sb[i]["p"]
				var tb: Vector2 = sb[i + 1]["p"]
				for face: Array in [[sa, sbb], [ta, tb]]:
					_quad(st, _world(face[0], z1), _world(face[1], z1), _world(face[1], z0), _world(face[0], z0),
							Vector2(u, 0), Vector2(u + step, 0), Vector2(u + step, MwStands.SEAT_H), Vector2(u, MwStands.SEAT_H), 2)
				_quad(st, _world(sa, z1), _world(sbb, z1), _world(tb, z1), _world(ta, z1),
						Vector2(u, 0), Vector2(u + step, 0), Vector2(u + step, MwStands.SEAT_T), Vector2(u, MwStands.SEAT_T), 3)
				u += step
		# the last row's back wall
		if k == MwStands.ROWS - 1:
			for half in 2:
				var b: Array = back[half]
				var u2 := 0.0
				for i in b.size() - 1:
					var step2: float = (b[i + 1]["p"] - b[i]["p"]).length()
					_quad(st, _world(b[i]["p"], h), _world(b[i + 1]["p"], h), _world(b[i + 1]["p"], h + 3 * MwStands.RISE),
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
	_materials.append(m)
	mi.material_override = m
	add_child(mi)


# --- the figures ---------------------------------------------------------------------

func _quad_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
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
	var basis := Basis(Vector3.UP.cross(zf), Vector3.UP, zf)
	mm.set_instance_transform(i, Transform3D(basis, MwRink3D.world(at.x, at.y, z)))
	mm.set_instance_custom_data(i, front)
	mm.set_instance_color(i, back)


func _build_figures() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _quad_mesh()
	mm.instance_count = seats.size() + 1
	# the referee first, then the seats in their filling order (occupancy)
	var ref := _rect(_key("pen_ref", false, []), false)
	_place(mm, 0, REF_AT, 0.0, REF_FACING, ref, ref)
	_ref_looks_right = false
	var order := range(seats.size())
	var keys := []
	for s: Dictionary in seats:
		keys.append(_fill_key(s))
	order.sort_custom(func(a, b): return keys[a] < keys[b])
	_order = PackedInt32Array(order)
	for n in order.size():
		var s: Dictionary = seats[order[n]]
		var pos: Vector3 = s["pos"]
		_place(mm, n + 1, Vector2(pos.x, pos.y), pos.z, s["facing"],
				_rect(_key(s["front"], s["team"], s["swap"]), s["mirrored"]),
				_rect(_key(s["back"], s["team"], s["swap"]), s["mirrored"]))
	_figures = mm
	_update_occupancy()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Figures"
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = CROWD_SHADER
	m.set_shader_parameter("atlas", ImageTexture.create_from_image(atlas))
	m.set_shader_parameter("near_hide", near_hide_px * S)
	_crowd_material = m
	m.set_shader_parameter("fade_from", FADE_FROM)
	m.set_shader_parameter("fade_to", FADE_TO)
	_materials.append(m)
	mmi.material_override = m
	add_child(mmi)


## A seat's place in the filling order: a fixed hash of where it is.
static func _fill_key(s: Dictionary) -> int:
	var p: Vector3 = s["pos"]
	var h := hash(Vector3i(roundi(p.x * 4.0), roundi(p.y * 4.0), int(s["row"])))
	return (h * 2654435761) & 0x7FFFFFFF


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


## Whether the referee is mirrored to look right ([method watch]).
func ref_looks_right() -> bool:
	return _ref_looks_right


## The referee in his pen watches the play (plan 16): his one drawing looks
## left from the original's camera; seen from [param cam], he is mirrored to
## look right once the puck at [param puck] (rink px) is more than
## [constant REF_TURN_PX] to his right on the screen, and back once it is as
## far to his left.
func watch(puck: Vector3, cam: Camera3D) -> void:
	if _figures == null or cam == null:
		return
	var b := cam.global_transform.basis if cam.is_inside_tree() else cam.transform.basis
	var right := Vector3(b.x.x, 0, b.x.z).normalized()
	var d := MwRink3D.world(puck.x, puck.y, 0) - MwRink3D.world(REF_AT.x, REF_AT.y, 0)
	var across := d.dot(right) / S
	var looks_right := _ref_looks_right
	if across > REF_TURN_PX:
		looks_right = true
	elif across < -REF_TURN_PX:
		looks_right = false
	if looks_right != _ref_looks_right:
		_ref_looks_right = looks_right
		var r := _rect(_key("pen_ref", false, []), looks_right)
		_figures.set_instance_custom_data(0, r)
		_figures.set_instance_color(0, r)


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
	var p := cut_plane(c, boards_y if cam != null else 0.0)
	for m in _materials:
		m.set_shader_parameter("cut_enabled", p["on"])
		m.set_shader_parameter("cut_origin", p["origin"])
		m.set_shader_parameter("cut_normal", p["normal"])
		m.set_shader_parameter("cut_side", p["side"])


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
	return 1.0 - smoothstep(FADE_FROM, FADE_TO, z)


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
	var made_for := [palette.team_a, palette.team_b, palette.stadium, palette.screen, palette.steps] if on else []
	if made_for == _teams_for:
		return
	_teams_for = made_for
	fan_teams = PackedInt32Array()
	if on:
		fan_teams = MwCrowdMix.assign(seats, palette.team_a, palette.team_b, palette.stadium,
				MwCrowdMix.skulls(MwRom.data()))
		team_lines = lines_by_team(palette)
		_crowd_material.set_shader_parameter("team_lines", ImageTexture.create_from_image(team_lines))
	for n in _order.size():
		var i := _order[n]
		var s: Dictionary = seats[i]
		var team := fan_teams[i] if on else -1
		_figures.set_instance_custom_data(n + 1, _rect(_key(s["front"], s["team"], s["swap"]), s["mirrored"], team))
		_figures.set_instance_color(n + 1, _rect(_key(s["back"], s["team"], s["swap"]), s["mirrored"], team))


## Line 1 of [param p] as each team would have it (16 x 23 colours, row t
## with team t as team A): the crowd's colours by the team a fan supports.
static func lines_by_team(p: RomPalette) -> Image:
	var img := Image.create_empty(16, MwCrowdMix.TEAMS, false, Image.FORMAT_RGBA8)
	for t in MwCrowdMix.TEAMS:
		var q := RomPalette.make(p.screen, p.steps, t, p.stadium)
		q.team_b = p.team_b
		var words := q.colours()
		for i in 16:
			var c := MwGfx.color(words[16 + i])
			c.a = 0.0 if i == 0 else 1.0
			img.set_pixel(i, t, c)
	return img
