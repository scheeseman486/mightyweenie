extends "res://test/rom/rom_test_base.gd"
## The ice as a mirror (plan 37, owner: a planar reflection, the on-ice
## sprites' from 25 % opaque at their base to none over 12 px, the rink's
## geometry the same; then the opacity and the fade's length doubled): the
## rule, the rink's mirrored meshes, the nets', the sprites' flipped frames,
## and the view showing them (not from the original's angle).

## A skater's frame (team A's attr), as test_flat_shadows.
const SKATER := 0x45252
const TEAM_A := 0x20
const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")

var _was := true


func before_each() -> void:
	_was = MwSettings.reflections
	MwSettings.reflections = true


func after_each() -> void:
	MwSettings.reflections = _was


## Row n above the ice: 50 % at the ice, 1/24 less each row, none from 24
## (owner: 25 % over 12, then the opacity and the fade's length doubled).
func test_the_rule_50_percent_at_the_ice_gone_24_rows_up() -> void:
	assert_almost_eq(MwRink3D.reflect_alpha(0), 0.5, 1e-6, "the row standing on the ice")
	assert_almost_eq(MwRink3D.reflect_alpha(12), 0.25, 1e-6, "half way")
	assert_almost_eq(MwRink3D.reflect_alpha(23), 0.5 / 24.0, 1e-6, "the last row")
	assert_eq(MwRink3D.reflect_alpha(24), 0.0, "24 rows up: gone")
	assert_eq(MwRink3D.reflect_alpha(-1), 0.0, "below the ice: nothing")
	for n in 24:
		assert_gt(MwRink3D.reflect_alpha(n), MwRink3D.reflect_alpha(n + 1), "fading")


## The padding, the signs and the fence are mirrored under the ice (the same
## meshes, the world's y turned round), drawn with the reflection shader in
## the reflections' place in the order, with the stadium's colours and the
## paint; the switch hides them.
func test_the_rinks_boards_are_mirrored_under_the_ice() -> void:
	if not need_rom():
		return
	var model := MwRinkModel.new()
	add_child_autofree(model)
	var found := model.meshes()
	var refl := model.reflections()
	assert_eq(refl.keys().size(), MwRinkModel.REFLECTED.size())
	for object_name: String in MwRinkModel.REFLECTED:
		var r: MeshInstance3D = refl[object_name]
		var mi: MeshInstance3D = found[object_name]
		assert_eq(r.mesh, mi.mesh, "%s: the same mesh" % object_name)
		assert_lt(r.global_transform.basis.determinant(), 0.0, "%s: mirrored" % object_name)
		assert_almost_eq(r.global_transform * Vector3(0.3, 0.4, 0.5), Vector3(0.3, -0.4, 0.5), Vector3.ONE * 1e-6,
				"%s: under the ice" % object_name)
		var m := r.material_override as ShaderMaterial
		var spec: Array = MwRinkModel.REFLECTED[object_name]
		assert_eq(m.shader, MwRinkModel.REFLECT_MESH_2S if spec[0] else MwRinkModel.REFLECT_MESH)
		assert_eq(m.render_priority, MwRinkModel.REFLECT_PRIORITY)
		assert_eq(int(m.get_shader_parameter("mode")), spec[1], "a picture, or the glass")
		assert_eq(m.get_shader_parameter("picture"), MwRinkModel.picture_texture(MwRinkModel.OBJECTS[object_name][0]))
		assert_eq(m.get_shader_parameter("reflect_ice"), MwRinkModel.ice_mask())
		assert_almost_eq(float(m.get_shader_parameter("reflect_alpha")), 0.5, 1e-6)
		assert_almost_eq(float(m.get_shader_parameter("reflect_fade")), 24.0, 1e-6)
		assert_true(r.visible)
	var glass := refl["glass"].material_override as ShaderMaterial
	var main := found["glass"].material_override as ShaderMaterial
	for p in ["glass_rows", "clear_rows", "post_cols", "post_rows"]:
		assert_eq(glass.get_shader_parameter(p), main.get_shader_parameter(p), "the glass's own " + p)
	assert_eq(int(glass.get_shader_parameter("mode")), 3, "the glass's lowest rows (from 19 px), by its own alpha")
	assert_false(refl.has("near_wall"), "the near end's outer wall stands off the ice")
	var pal := RomPalette.make(4, PackedStringArray(["screen_palette"]), 18, 3)
	model.palette = pal
	assert_eq((refl["wall"].material_override as ShaderMaterial).get_shader_parameter("palette"), pal.texture())
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_R8))
	model.set_paint(tex, true)
	assert_eq((refl["fence"].material_override as ShaderMaterial).get_shader_parameter("paint"), tex,
			"blood on the boards reflected too")
	model.set_reflections(false)
	for r: MeshInstance3D in refl.values():
		assert_false(r.visible)


## The ice under the reflections is the floor's: inside the boards.
func test_the_reflections_ice_is_inside_the_boards() -> void:
	if not need_rom():
		return
	var img := MwRinkModel.ice_mask().get_image()
	var o := MwRink3D.MAP_ORIGIN
	assert_eq(img.get_pixel(o.x, o.y).r8, 255, "centre ice")
	assert_eq(img.get_pixel(o.x + 184, o.y).r8, 255, "by the side boards")
	assert_eq(img.get_pixel(o.x + 185, o.y).r8, 0, "the boards")
	assert_eq(img.get_pixel(o.x + 200, o.y).r8, 0, "the bench area")


## A net with a model has its mirror image under it: the frame in its
## colour, the netting's stipple; its ground shadow lies on the ice (not
## reflected).
func test_a_net_is_mirrored_under_the_ice() -> void:
	if not need_rom():
		return
	var nets := MwNets3D.new()
	add_child_autofree(nets)
	nets.warm_up(true)
	var net_3d := nets.get_child(0) as MwNet3D
	var mirror := net_3d.get_node("Reflection") as Node3D
	assert_lt(mirror.transform.basis.determinant(), 0.0, "mirrored")
	var shaders := {}
	for mi: MeshInstance3D in mirror.find_children("*", "MeshInstance3D", true, false):
		for surface in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(surface) as ShaderMaterial
			assert_not_null(m)
			shaders[m.shader] = true
			if m.shader != MwNet3D.HIDDEN:
				assert_eq(m.render_priority, MwRinkModel.REFLECT_PRIORITY)
	assert_true(shaders.has(MwRinkModel.REFLECT_MESH), "the frame")
	assert_true(shaders.has(MwRinkModel.REFLECT_MESH_2S), "the netting")
	assert_eq(int(MwNet3D.reflect_material_for("net_0_1_8").get_shader_parameter("mode")), 2)
	assert_eq(int(MwNet3D.reflect_material_for("bar_0_5").get_shader_parameter("index")), 5)
	assert_eq(MwNet3D.reflect_material_for("shadow_0_6").shader, MwNet3D.HIDDEN, "the ground shadow: not reflected")
	assert_true(mirror.visible)
	nets.reflections = false
	assert_false(mirror.visible)
	nets.warm_up(false)


## A skater standing on the ice gets his reflection - the same frame and
## rectangle, drawn flipped by rink3d_sprite_reflect in the reflections'
## place; not in the bench area, not high in the air, not with the switch
## off or from the original's angle.
func test_a_standing_sprite_is_reflected_on_the_ice_only() -> void:
	if not need_rom():
		return
	var spr := MwSprites3D.new()
	add_child_autofree(spr)
	spr.flat_shadows = false
	spr.show_items([_item(Vector3(40, 100, 0))])
	var shown := _visible(spr)
	assert_eq(shown.size(), 2, "the skater and his reflection")
	var m := shown[1].material_override as ShaderMaterial
	assert_eq(m.shader, MwSprites3D.SPRITE_REFLECT)
	assert_eq(m.render_priority, MwRinkModel.REFLECT_PRIORITY)
	assert_eq(m.get_shader_parameter("frame"),
			(shown[0].material_override as ShaderMaterial).next_pass.get_shader_parameter("frame"))
	assert_eq(shown[1].get_instance_shader_parameter("px_rect"), shown[0].get_instance_shader_parameter("px_rect"),
			"its rectangle, flipped by the shader")
	assert_eq(m.get_shader_parameter("reflect_ice"), MwRinkModel.ice_mask())
	spr.show_items([_item(Vector3(MwBench3D.PEN_X[0], 100, 0))])
	assert_eq(_visible(spr).size(), 1, "the bench area: no ice")
	spr.show_items([_item(Vector3(40, 100, 120))])
	assert_eq(_visible(spr).size(), 1, "120 px up: past the fade")
	spr.reflections = false
	spr.show_items([_item(Vector3(40, 100, 0))])
	assert_eq(_visible(spr).size(), 1, "off")
	spr.reflections = true
	spr.original_order = true
	spr.show_items([_item(Vector3(40, 100, 0))])
	assert_eq(_visible(spr).size(), 1, "the calibration camera: the original's picture")


## Which frames are reflected: on the ice, some rows above it within the fade.
func test_which_frames_are_reflected() -> void:
	assert_true(MwSprites3D.reflected(Vector3(0, 0, 0), -30.0, 32), "standing on the ice")
	assert_true(MwSprites3D.reflected(Vector3(0, 0, 0), -40.0, 17), "its last row 23 up")
	assert_false(MwSprites3D.reflected(Vector3(0, 0, 0), -40.0, 16), "its last row 24 up")
	assert_false(MwSprites3D.reflected(Vector3(0, 0, 0), 0.0, 8), "all below the ice (lying on it)")
	assert_false(MwSprites3D.reflected(Vector3(186, 0, 0), -30.0, 32), "outside the side boards")
	assert_false(MwSprites3D.reflected(Vector3(0, 373, 0), -30.0, 32), "beyond the end boards")


## The reflections lie over the under-ice frames and under the hazards,
## shadows and markers on the ice; the standing frames after them all.
func test_the_reflections_draw_order() -> void:
	if not need_rom():
		return
	var spr := MwSprites3D.new()
	add_child_autofree(spr)
	var f := spr.frame_texture(rom, SKATER, TEAM_A)
	var under := spr._material(f, 0).render_priority
	var hazards := spr._material(f, 1).render_priority
	assert_lt(MwSprites3D.SHADOW_PRIORITY, under)
	assert_lt(under, MwRinkModel.REFLECT_PRIORITY)
	assert_lt(MwRinkModel.REFLECT_PRIORITY, hazards)
	assert_lt(spr._material(f, 3).render_priority, 0, "the standing frames last")


## The view shows them in the game's cameras, not the calibration camera's.
func test_the_view_shows_them_but_not_from_the_originals_angle() -> void:
	if not need_rom():
		return
	var view := VIEW.instantiate() as MwRinkView3D
	add_child_autofree(view)
	var f := {"items": [_item(Vector3(40, 100, 0))], "shot": null, "shown": Vector2.ZERO}
	view.present_frame(f, {}, false)
	assert_true(view.sprites.reflections)
	assert_true((view.model.reflections()["wall"] as MeshInstance3D).visible)
	assert_true(view.nets.reflections)
	view.set_camera_mode(MwRinkCamera3D.Mode.CALIBRATION)
	view.blend_to(1.0)
	assert_false(view.sprites.reflections)
	assert_false((view.model.reflections()["wall"] as MeshInstance3D).visible)
	assert_false(view.nets.reflections)
	view.set_camera_mode(MwRinkCamera3D.Mode.FOLLOW)
	MwSettings.reflections = false
	view.blend_to(1.0)
	assert_false(view.sprites.reflections, "the switch")
	MwSettings.reflections = true
	view.blend_to(1.0)
	assert_true((view.model.reflections()["wall"] as MeshInstance3D).visible)


func _item(at: Vector3) -> Dictionary:
	return {"frame": SKATER, "attr": TEAM_A, "depth": 0x100, "place": MwRinkDraw3D.UPRIGHT, "at": at,
			"offset": Vector2i.ZERO, "order": 0, "key": "t0.p0/body"}


func _visible(spr: MwSprites3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in spr.get_children():
		if c is MeshInstance3D and c.visible:
			out.append(c)
	return out
