extends SceneTree
## Plan 15 review renders (desktop, needs a renderer): the 3D rink with its
## stands and crowd, from the game's follow camera at points round the rink
## and from a few overviews, at 960 x 672. Writes PNGs to the output folder.
##
##   godot --path game -s res://test/rink3d/crowd_shots.gd -- OUT_DIR [STADIUM]

const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")
## The follow camera looking at these ice points (rink px).
const FOLLOW := {
	"follow_far": Vector2(0, -250),
	"follow_far_left": Vector2(-120, -260),
	"follow_centre": Vector2(0, 0),
	"follow_left": Vector2(-120, -40),
	"follow_near_right": Vector2(120, 250),
	"follow_near": Vector2(0, 270),
}
## Free shots: name -> [look at (rink px), pitch deg, yaw deg (0 = looking
## north from the south, 90 = looking west), distance px, fov deg (vertical)]
const SHOTS := {
	"overview": [Vector3(0, 40, 0), 55.0, 0.0, 1300.0, 50.0],
	"far_stands": [Vector3(0, -420, 60), 20.0, 0.0, 420.0, 55.0],
	"left_stands": [Vector3(-260, -120, 60), 18.0, 90.0, 380.0, 60.0],
	"near_stands_from_ice": [Vector3(0, 440, 60), 10.0, 180.0, 400.0, 60.0],
	"corner_far_left": [Vector3(-200, -360, 60), 20.0, 45.0, 360.0, 60.0],
	"ref_pen": [Vector3(235, 0, 25), 15.0, -90.0, 200.0, 55.0],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(180.0).timeout.connect(quit.bind(2))
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var stadium := int(args[1]) if args.size() > 1 else 0
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := SubViewport.new()
	vp.size = Vector2i(960, 672)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var view: MwRinkView3D = VIEW.instantiate()
	view.palette = RomPalette.make(4, PackedStringArray(["screen_palette", "rom 1BD8A 3"]), stadium, stadium)
	vp.add_child(view)
	await process_frame
	var cam := view.camera
	for name: String in FOLLOW:
		var look: Vector2 = FOLLOW[name]
		cam.mode = MwRinkCamera3D.Mode.FOLLOW
		var shown := MwRink3D.map_point(look.x, look.y, 0) - Vector2(MwRink3D.SCREEN) / 2.0
		cam.follow(shown)
		await _save(vp, out_dir, name)
	for name: String in SHOTS:
		var s: Array = SHOTS[name]
		var look: Vector3 = s[0]
		var p := deg_to_rad(s[1])
		var y := deg_to_rad(s[2])
		var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = s[4]
		cam.near = 0.05
		cam.far = 400.0
		cam.transform = Transform3D(Basis.from_euler(Vector3(-p, y, 0)),
				MwRink3D.world(look.x, look.y, look.z) + back * (float(s[3]) * MwRink3D.METRES_PER_PX))
		await _save(vp, out_dir, name)
	quit()


func _save(vp: SubViewport, out_dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print(name)
