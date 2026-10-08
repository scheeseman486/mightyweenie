extends SceneTree
## Plan 14 review renders (desktop, needs a renderer): the 3D rink model alone,
## textured from the ROM for a stadium, from fixed viewpoints, at 960 x 672.
## Writes PNGs to the output folder.
##
##   godot --path game -s res://test/rink3d/review_shots.gd -- OUT_DIR [STADIUM]

const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")
## name -> [look at (rink px), pitch deg, yaw deg (0 = looking north from the
## south, 90 = looking west), distance px, fov deg (vertical)]
const SHOTS := {
	"overview": [Vector3(0, 40, 0), 55.0, 0.0, 1000.0, 50.0],
	"near_end": [Vector3(0, 330, 10), 30.0, 0.0, 300.0, 45.0],
	"near_end_inside": [Vector3(0, 372, 15), 18.0, 180.0, 300.0, 50.0],
	"left_benches": [Vector3(-200, -10, 10), 25.0, 90.0, 260.0, 60.0],
	"left_benches_high": [Vector3(-210, -10, 0), 55.0, 60.0, 420.0, 50.0],
	"left_near_corner": [Vector3(-150, 280, 12), 18.0, 140.0, 230.0, 60.0],
	"referee_side": [Vector3(185, 0, 22), 12.0, -90.0, 255.0, 55.0],
	"far_end": [Vector3(0, -330, 10), 20.0, 0.0, 330.0, 50.0],
	"left_signs_upper": [Vector3(-185, -230, 14), 10.0, 75.0, 240.0, 55.0],
	"left_signs_lower": [Vector3(-185, 250, 14), 10.0, 105.0, 240.0, 55.0],
	"pens_close": [Vector3(-216, 0, 10), 35.0, 70.0, 200.0, 60.0],
	"near_outer": [Vector3(-60, 380, 10), 12.0, 0.0, 170.0, 45.0],
	"upper_left_corner": [Vector3(-175, -300, 14), 12.0, 50.0, 230.0, 60.0],
	"lower_half": [Vector3(0, 250, 0), 50.0, 0.0, 520.0, 50.0],
	"ref_box_high": [Vector3(210, -10, 0), 55.0, -60.0, 420.0, 50.0],
	"ref_box": [Vector3(200, 0, 10), 22.0, -90.0, 260.0, 60.0],
	"signs_end_upper": [Vector3(-185, -295, 42), 8.0, 75.0, 80.0, 50.0],
	"signs_end_bench": [Vector3(-185, -160, 42), 8.0, 90.0, 80.0, 50.0],
	"signs_end_lower": [Vector3(-185, 304, 42), 8.0, 105.0, 80.0, 50.0],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(120.0).timeout.connect(quit.bind(2))
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
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
		print(name)
	quit()
