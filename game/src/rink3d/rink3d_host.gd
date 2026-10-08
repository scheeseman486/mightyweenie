class_name MwRink3DHost
extends CanvasLayer
## The 3D view's home (plan 20, docs/rink3d.md, The 3D host): one
## MwRinkView3D for the whole run, in a SubViewport on this canvas layer
## behind the screens (the fader covers it), owned by the Router autoload.
##
## Built at launch whether or not 3D is ever shown, without a pause: the
## heavy part (the crowd cut from the ROM, the stands' meshes, the rink
## model's textures: about 0.6 s) runs on a worker thread, off the scene
## tree ([method MwRinkView3D.build]); the built view then joins the tree
## in one cheap step. The first time the screen is fully covered after that
## (the black between two screens, [member covered]) it renders once,
## hidden, with everything it has in sight (the nets' models and a frame of
## each sprite kind too), so the shaders are compiled before anyone looks:
## on a cold shader cache that is 0.2-0.35 s the player would otherwise
## see. A screen that shows the rink borrows the view ([method borrow],
## [method show_for], [method release]); in 2D it can [method prime] it,
## presenting its first pass unseen so the sprites' textures exist before
## the first switch.
##
## Without a display (tests, harness runs) nothing starts at launch: the
## first [method view] builds it on the spot. Presentation only: nothing
## here touches the game's state.

## The view joined the tree (built).
signal built

const VIEW_SCENE := preload("res://src/rink3d/rink_view_3d.tscn")

enum Stage { IDLE, BUILDING, BUILT, WARMING, WARM }

## Where the build is.
var stage := Stage.IDLE
## The screen showing the view (null: hidden).
var user: Object = null
## True once a screen primed the view with a pass ([method prime]).
var primed := false
## Whether the screen is fully covered now (the moment to warm up unseen);
## the Router gives its fader's. Default: always (warm at once).
var covered: Callable = func() -> bool: return true
## False without a display (nothing renders: no warm-up).
var can_render := DisplayServer.get_name() != "headless"

var box: SubViewportContainer
var viewport: SubViewport
var _view: MwRinkView3D            # in the tree once built
var _pending: MwRinkView3D         # built off the tree by the task
var _task := -1
var _palette: RomPalette
var _warm_mode := MwRinkCamera3D.Mode.FOLLOW
## The window's own content scaling (the project's), restored when hidden.
var _scale_mode := -1
var _scale_stretch := -1


func _init() -> void:
	name = "Rink3D"
	layer = -1                          # behind the screens; the fader covers it
	visible = false
	box = SubViewportContainer.new()
	box.name = "View3D"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.size = MwRink3D.SCREEN
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	box.add_child(viewport)
	add_child(box)
	set_physics_process(false)


func _ready() -> void:
	var root := get_tree().root
	_scale_mode = root.content_scale_mode
	_scale_stretch = root.content_scale_stretch
	root.size_changed.connect(_fit)


## The host the game uses: the Router's, or (a scene run without it) one
## made under the root.
static func of(tree: SceneTree) -> MwRink3DHost:
	var h := existing(tree)
	if h == null:
		h = MwRink3DHost.new()
		tree.root.add_child(h)
	return h


## The host if there is one (null: none made yet).
static func existing(tree: SceneTree) -> MwRink3DHost:
	var h := tree.root.get_node_or_null("Router/Rink3D") as MwRink3DHost
	if h == null:
		h = tree.root.get_node_or_null("Rink3D") as MwRink3DHost
	return h


## Starts building the view on a worker thread (once; nothing without the
## ROM). The view joins the tree on the first physics tick after it is done.
func prepare() -> void:
	if stage != Stage.IDLE or not MwRom.available():
		return
	MwRom.data()                    # the ROM read on this thread before the worker shares it
	stage = Stage.BUILDING
	_task = WorkerThreadPool.add_task(_build_off_tree, false, "mightyweenie: the 3D rink")
	set_physics_process(true)
	if can_render:
		_compile_shaders()


## Every shader the view draws with.
static func shaders() -> Array[Shader]:
	var out: Array[Shader] = []
	for sh: Shader in MwRinkModel.SHADERS.values():
		out.append(sh)
	out.append_array([MwStands3D.STANDS_SHADER, MwStands3D.CROWD_SHADER,
			MwNet3D.FLAT, MwNet3D.NETTING, MwNet3D.SHADOW, MwNet3D.HIDDEN,
			MwSprites3D.SPRITE, MwSprites3D.SPRITE_2D, MwSprites3D.SPRITE_DEPTH,
			MwSprites3D.SPRITE_OPS, MwSprites3D.SPRITE_BLEND])
	return out


## The shaders compiled at once, while the view is still being built: one
## small hidden render of a quad with each (the crowd's as a MultiMesh), in
## the first frames, which the boot screen covers. The warm-up render later
## then only has the pipelines of the real meshes left.
func _compile_shaders() -> void:
	var vp := SubViewport.new()
	vp.name = "Shaders"
	vp.size = Vector2i(16, 16)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 2)
	vp.add_child(cam)
	var quad := QuadMesh.new()
	for sh in shaders():
		var m := ShaderMaterial.new()
		m.shader = sh
		if sh == MwStands3D.CROWD_SHADER:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = quad
			mm.instance_count = 1
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = m
			vp.add_child(mmi)
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = m
			vp.add_child(mi)
	add_child(vp)
	cam.current = true
	RenderingServer.frame_post_draw.connect(vp.queue_free, CONNECT_ONE_SHOT)


func _build_off_tree() -> void:
	var v := VIEW_SCENE.instantiate() as MwRinkView3D
	v.name = "RinkView3D"
	v.build()
	_pending = v


## True once the view is in the tree.
func is_built() -> bool:
	return stage >= Stage.BUILT


## The view, built on the spot if it is not yet (finishing the worker's
## build, or the whole build without one); null without the ROM.
func view() -> MwRinkView3D:
	if stage == Stage.IDLE:
		if not MwRom.available():
			return null
		stage = Stage.BUILDING
		_build_off_tree()
	_attach()
	_end_warm_up()
	return _view


func _attach() -> void:
	if stage != Stage.BUILDING:
		return
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	viewport.add_child(_pending)
	_view = _pending
	_pending = null
	if _palette:
		_view.palette = _palette
	stage = Stage.BUILT
	set_physics_process(true)
	_fit()
	built.emit()


func _physics_process(_delta: float) -> void:
	if stage == Stage.BUILDING:
		if WorkerThreadPool.is_task_completed(_task):
			_attach()
	elif stage == Stage.BUILT:
		if user != null or primed or not can_render:
			stage = Stage.WARM          # already seen, or nothing renders: nothing to warm
		elif covered.call():
			_warm_up()
	elif stage != Stage.WARMING:
		set_physics_process(false)


## One hidden render with everything in sight: the whole rink from above,
## the nets' models of every style, a frame of every sprite kind. Ends after
## that frame is drawn, or as soon as a screen uses the view.
func _warm_up() -> void:
	stage = Stage.WARMING
	_warm_mode = _view.camera.mode
	_view.camera.mode = MwRinkCamera3D.Mode.OVERVIEW
	_view.camera.follow(Vector2.ZERO)
	_view.stands.cutaway(null)
	_view.nets.warm_up(true)
	_view.sprites.warm_up(true)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.frame_post_draw.connect(_end_warm_up, CONNECT_ONE_SHOT)


func _end_warm_up() -> void:
	if stage != Stage.WARMING:
		return
	stage = Stage.WARM
	if RenderingServer.frame_post_draw.is_connected(_end_warm_up):
		RenderingServer.frame_post_draw.disconnect(_end_warm_up)
	_view.nets.warm_up(false)
	_view.sprites.warm_up(false)
	_view.camera.mode = _warm_mode


## The view for screen [param u] with its [param palette], not shown yet
## (null without the ROM).
func borrow(u: Object, palette: RomPalette) -> MwRinkView3D:
	var v := view()
	if v == null:
		return null
	if palette != _palette:
		_palette = palette
		v.palette = palette
	return v


## Shows the view for screen [param u] (true), or hides it if [param u]
## shows it (false).
func show_for(u: Object, three: bool) -> void:
	if three:
		if view() == null:
			return
		var was := user
		user = u
		visible = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if was == null:
			_scaling(true)
	elif user == u:
		_hide()


## True when screen [param u] shows the view.
func shown_for(u: Object) -> bool:
	return user == u and visible


## Screen [param u] is leaving: hidden if it showed the view.
func release(u: Object) -> void:
	if user == u:
		_hide()


func _hide() -> void:
	user = null
	visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _view:
		_view.auto_blend = false
	_scaling(false)


## Renders the view once unseen (the caller presented a pass first): that
## pass's sprite textures and materials made before the first switch.
## Nothing while it shows.
func prime() -> void:
	_end_warm_up()
	if user != null or _view == null:
		return
	primed = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The viewport's size: every window pixel of the 320 x 224 screen (shown
## or not, so showing it allocates nothing new).
func _fit() -> void:
	if not is_inside_tree():
		return
	var root := get_tree().root
	var screen := Vector2(MwRink3D.SCREEN)
	var k := maxf(minf(root.size.x / screen.x, root.size.y / screen.y), 1.0)
	box.stretch = false
	viewport.size = Vector2i((screen * k).round())
	box.size = Vector2(viewport.size)
	box.scale = screen / Vector2(viewport.size)


## The window's scaling while the view shows (true): its 2D content scales
## as canvas items (fractional, aspect kept) over the 3D view; hidden: the
## project's pixel-exact viewport scaling.
func _scaling(shown: bool) -> void:
	if not is_inside_tree():
		return
	var root := get_tree().root
	if shown:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	elif _scale_mode >= 0:
		root.content_scale_mode = _scale_mode as Window.ContentScaleMode
		root.content_scale_stretch = _scale_stretch as Window.ContentScaleStretch
	_fit()


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_end_warm_up):
		RenderingServer.frame_post_draw.disconnect(_end_warm_up)
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _pending != null:
		_pending.free()
		_pending = null
