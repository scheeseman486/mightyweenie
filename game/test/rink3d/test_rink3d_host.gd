extends "res://test/rom/rom_test_base.gd"
## The 3D view's host (plan 20, MwRink3DHost): the view built off the scene
## tree (on a worker thread at launch, or on the spot), the warm-up render
## waiting for a covered screen, screens borrowing and releasing the view,
## the window's scaling following it.
## Short names: h the MwRink3DHost under test, v the MwRinkView3D under test.

const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")


func _host() -> MwRink3DHost:
	var h := MwRink3DHost.new()
	h.name = "TestHost"
	add_child_autofree(h)
	return h


func test_the_router_owns_one_host() -> void:
	var router := get_tree().root.get_node_or_null("Router")
	assert_not_null(router, "Router autoload")
	var h := MwRink3DHost.existing(get_tree())
	assert_not_null(h)
	assert_eq(h, router.rink_3d)
	assert_eq(h.layer, -1, "behind the screens")
	assert_lt(h.layer, router.fader.layer, "under the fader")


func test_view_builds_off_the_tree() -> void:
	if not need_rom():
		return
	var v := VIEW.instantiate() as MwRinkView3D
	v.build()
	assert_false(v.is_inside_tree())
	assert_not_null(v.stands)
	assert_not_null(v.stands.crowd, "the crowd cut from the ROM")
	assert_gt(v.stands.seats.size(), 100)
	assert_not_null(v.nets)
	var model := v.get_node("World/Model") as MwRinkModel
	assert_false(model.meshes().is_empty(), "the rink model loaded")
	var stands := v.stands
	v.build()                                   # once only
	assert_eq(v.stands, stands)
	add_child_autofree(v)                       # _ready keeps what was built
	assert_eq(v.stands, stands)
	assert_eq(v.get_node("World").get_children().filter(func(n): return n is MwStands3D).size(), 1)


func test_host_builds_on_a_worker() -> void:
	if not need_rom():
		return
	var h := _host()
	assert_eq(h.stage, MwRink3DHost.Stage.IDLE)
	h.covered = func() -> bool: return false
	h.prepare()
	assert_eq(h.stage, MwRink3DHost.Stage.BUILDING)
	assert_false(h.is_built())
	await wait_for_signal(h.built, 20.0, "the worker's build")
	assert_true(h.is_built())
	var v := h.view()
	assert_not_null(v)
	assert_true(v.is_inside_tree())
	assert_eq(v.get_parent(), h.viewport)
	assert_false(h.visible, "built hidden")
	assert_eq(h.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	h.prepare()                                 # once only
	assert_eq(h.view(), v)


func test_view_builds_on_demand() -> void:
	if not need_rom():
		return
	var h := _host()
	h.covered = func() -> bool: return false
	var v := h.view()
	assert_not_null(v)
	assert_true(h.is_built())
	assert_eq(h.view(), v)


func test_warm_up_waits_for_a_covered_screen() -> void:
	if not need_rom():
		return
	var h := _host()
	h.can_render = true                         # as with a display
	var cover := [false]
	h.covered = func() -> bool: return cover[0]
	var v := h.view()
	await wait_physics_frames(5)
	assert_eq(h.stage, MwRink3DHost.Stage.BUILT, "not while the screen shows")
	cover[0] = true
	await wait_physics_frames(2)
	assert_eq(h.stage, MwRink3DHost.Stage.WARMING, "warms once covered")
	assert_false(h.visible, "unseen")
	assert_eq(h.viewport.render_target_update_mode, SubViewport.UPDATE_ONCE)
	assert_eq(v.camera.mode, MwRinkCamera3D.Mode.OVERVIEW, "everything in sight")
	assert_eq(v.nets.get_children().size(), MwNet3D.MODELS.size())
	# headless draws no frame: a screen using the view ends the warm-up at once
	h.borrow(self, null)
	assert_eq(h.stage, MwRink3DHost.Stage.WARM)
	assert_eq(v.camera.mode, MwRinkCamera3D.Mode.FOLLOW, "the camera mode back")
	await wait_process_frames(1)
	assert_eq(v.nets.get_children().size(), 0, "the warm-up nets gone")
	for mi: MeshInstance3D in v.sprites.get_children():
		assert_false(mi.visible, "the warm-up frames hidden")


func test_no_warm_up_without_a_display() -> void:
	if not need_rom():
		return
	var h := _host()
	h.can_render = false
	h.view()
	await wait_physics_frames(2)
	assert_eq(h.stage, MwRink3DHost.Stage.WARM)


func test_warm_up_shows_every_kind() -> void:
	if not need_rom():
		return
	var h := _host()
	h.covered = func() -> bool: return false
	var v := h.view()
	v.nets.warm_up(true)
	assert_eq(v.nets.get_children().size(), MwNet3D.MODELS.size(), "a net of every style")
	v.sprites.warm_up(true)
	var shown := v.sprites.get_children().filter(func(mi): return mi.visible)
	assert_eq(shown.size(), 5, "standing (with a stick shadow), its flat shadow, its reflection, flat card, on the ice")
	var shaders := {}
	for mi: MeshInstance3D in shown:
		var m: Material = mi.material_override
		while m:
			shaders[(m as ShaderMaterial).shader.resource_path] = true
			m = m.next_pass
	for s in [MwSprites3D.SPRITE, MwSprites3D.SPRITE_DEPTH, MwSprites3D.SPRITE_OPS, MwSprites3D.SPRITE_BLEND,
			MwSprites3D.SPRITE_SHADOW, MwSprites3D.SPRITE_STICK, MwSprites3D.SPRITE_REFLECT]:
		assert_true(shaders.has(s.resource_path), s.resource_path)
	v.sprites.warm_up(false)
	v.nets.warm_up(false)
	await wait_process_frames(1)
	assert_eq(v.sprites.get_children().filter(func(mi): return mi.visible).size(), 0)
	assert_eq(v.nets.get_children().size(), 0)


func test_screens_borrow_show_and_release() -> void:
	if not need_rom():
		return
	var h := _host()
	h.covered = func() -> bool: return false
	var root := get_tree().root
	var mode := root.content_scale_mode
	var a := RefCounted.new()
	var b := RefCounted.new()
	var pal := RomPalette.make(4, PackedStringArray(MwScreenPalettes.RINK), 0, 0)
	var v := h.borrow(a, pal)
	assert_eq(v.palette, pal)
	assert_false(h.visible, "borrowed, not shown")
	h.show_for(a, true)
	assert_true(h.shown_for(a))
	assert_false(h.shown_for(b))
	assert_eq(h.viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	assert_eq(root.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "2D content as canvas items")
	h.show_for(b, false)                        # another screen's 2D leaves it be
	assert_true(h.shown_for(a))
	h.release(b)
	assert_true(h.shown_for(a))
	v.auto_blend = true
	h.release(a)
	assert_false(h.visible)
	assert_null(h.user)
	assert_false(v.auto_blend)
	assert_eq(h.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_eq(root.content_scale_mode, mode, "the project's scaling back")


## Plan 25: WIDE - a wide screen's picture is the window at its whole
## scale, in 2D and in 3D (whole steps either way); the screens' 2D layers
## centred; back as before after.
func test_wide_scaling() -> void:
	if not need_rom():
		return
	var h := _host()
	h.covered = func() -> bool: return false
	var root := get_tree().root
	var size := root.content_scale_size
	var mode := root.content_scale_mode
	var stretch := root.content_scale_stretch
	var a := RefCounted.new()
	var v := h.borrow(a, RomPalette.make(4, PackedStringArray(MwScreenPalettes.RINK), 0, 0))
	h.wide_for(a, true)
	assert_eq(h.wide_user, a)
	var want := MwRink3DHost.wide_shape(root.size)
	assert_eq(h.view_size, Vector2(want))
	assert_eq(root.content_scale_size, want, "the window's content: the wide picture")
	assert_eq(root.canvas_transform.origin, Vector2(h.column_origin()), "the original's 320 x 224 centred")
	h.show_for(a, true)
	assert_eq(root.content_scale_stretch, stretch, "3D wide: whole steps, as the 2D (owner)")
	assert_almost_eq(h.box.size * h.box.scale, h.view_size, Vector2(0.01, 0.01), "the view fills it")
	assert_eq(v.camera.view, h.view_size, "the camera told")
	h.release(a)
	assert_null(h.wide_user)
	assert_eq(root.content_scale_size, size, "the project's back")
	assert_eq(root.content_scale_mode, mode)
	assert_eq(h.view_size, Vector2(MwRink3D.SCREEN))
	assert_eq(root.canvas_transform.origin, Vector2.ZERO)
	h.show_for(a, true)
	assert_eq(root.content_scale_stretch, Window.CONTENT_SCALE_STRETCH_FRACTIONAL, "ORIGINAL 3D: as before")
	h.release(a)
	assert_eq(root.content_scale_stretch, stretch)
	assert_eq(MwRink3DHost.wide_shape(Vector2i(1920, 1080)), Vector2i(480, 270), "4x, the whole screen (owner)")
	assert_eq(MwRink3DHost.wide_shape(Vector2i(1280, 720)), Vector2i(426, 240))
	assert_eq(MwRink3DHost.wide_shape(Vector2i(1024, 768)), Vector2i(341, 256))
	assert_eq(MwRink3DHost.wide_shape(Vector2i(2560, 1080)), Vector2i(640, 270))
	assert_eq(MwRink3DHost.wide_shape(Vector2i(1280, 896)), Vector2i(320, 224), "the original's shape")
	assert_eq(MwRink3DHost.wide_shape(Vector2i(300, 200)), Vector2i(320, 224), "never narrower")


## Plan 33: a screen passing the view on (the match's opening to the rink)
## leaves it shown and shaped; the next screen claims it as it is, or hides
## it if it shows 2D.
func test_a_screen_passes_the_view_on() -> void:
	if not need_rom():
		return
	var h := _host()
	h.covered = func() -> bool: return false
	var root := get_tree().root
	var size := root.content_scale_size
	var pal := RomPalette.make(4, PackedStringArray(MwScreenPalettes.RINK), 0, 0)
	var a := RefCounted.new()
	var b := RefCounted.new()
	h.borrow(a, pal)
	h.wide_for(a, true)
	h.show_for(a, true)
	var shape := h.view_size
	var vp_size := h.viewport.size
	h.pass_on(a)
	assert_true(h.visible, "still shown")
	assert_eq(h.viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	h.wide_for(b, true)
	assert_eq(h.wide_user, b)
	assert_eq(h.view_size, shape, "the same picture")
	assert_eq(h.viewport.size, vp_size, "nothing resized")
	h.borrow(b, pal)
	h.show_for(b, true)
	assert_true(h.shown_for(b), "claimed")
	h.release(b)
	assert_false(h.visible)
	assert_eq(root.content_scale_size, size)
	# passed on to a screen in 2D: hidden when it says so
	h.borrow(a, pal)
	h.show_for(a, true)
	h.pass_on(a)
	h.wide_for(b, false)
	h.show_for(b, false)
	assert_false(h.visible, "hidden by the next screen's 2D")
	assert_null(h.user)


func test_prime_renders_once_unseen() -> void:
	if not need_rom():
		return
	var h := _host()
	h.covered = func() -> bool: return false
	h.view()
	h.prime()
	assert_true(h.primed)
	assert_false(h.visible)
	assert_eq(h.viewport.render_target_update_mode, SubViewport.UPDATE_ONCE)
	await wait_physics_frames(2)
	assert_eq(h.stage, MwRink3DHost.Stage.WARM, "a primed view needs no warm-up")
	var a := RefCounted.new()
	h.show_for(a, true)
	h.primed = false
	h.prime()
	assert_false(h.primed, "nothing while it shows")
	h.release(a)


func test_every_shader_is_compiled_at_launch() -> void:
	var listed := {}
	for sh in MwRink3DHost.shaders():
		listed[sh.resource_path] = true
	var missing := []
	for f in DirAccess.get_files_at("res://src/rink3d"):
		if f.ends_with(".gdshader") and not listed.has("res://src/rink3d/" + f):
			missing.append(f)
	assert_eq(missing, [], "shaders the launch's compile render leaves out")
	var h := _host()
	h._compile_shaders()
	var vp := h.get_node("Shaders") as SubViewport
	assert_not_null(vp)
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_ONCE)
	var drawn := vp.get_children().filter(func(n): return n is GeometryInstance3D)
	assert_eq(drawn.size(), listed.size(), "a quad per shader")
