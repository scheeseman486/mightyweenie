extends SceneTree
## Plan 15 review renders (desktop): the stands empty, a quarter full, half
## full and full, from in front of the crowd and from behind it, 960 x 672.
## Writes VIEW_PCT.png to the output folder.
##
##   godot --path game -s res://test/rink3d/crowd_variations.gd -- OUT_DIR [STADIUM]

const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")
const OCCUPANCY := [0.0, 0.25, 0.5, 1.0]
## name -> [camera at (rink px), looking at (rink px), fov deg (vertical)],
## or, for the game's follow camera, the ice point it looks at (Vector2).
const SHOTS := {
	# in front of the crowd
	"front_far_stands": [Vector3(0, -50, 140), Vector3(0, -420, 80), 55.0],
	"front_follow_far": Vector2(0, -250),
	"front_left_stands": [Vector3(120, -120, 130), Vector3(-260, -120, 70), 60.0],
	"front_follow_near": Vector2(0, 270),
	"overview": [Vector3(0, 740, 1060), Vector3(0, 40, 0), 50.0],
	# behind the crowd: from the top rows, over its backs
	"behind_near_top": [Vector3(0, 560, 250), Vector3(0, 200, 0), 60.0],
	"behind_far_top": [Vector3(0, -560, 250), Vector3(0, -200, 0), 60.0],
	"behind_left_top": [Vector3(-370, -40, 240), Vector3(-60, -40, 0), 60.0],
	"behind_near_left_corner": [Vector3(-330, 520, 240), Vector3(-80, 180, 0), 60.0],
	"behind_fan_eye_near": [Vector3(40, 494, 144), Vector3(0, 200, 20), 60.0],
	"behind_fan_eye_left": [Vector3(-327, 120, 160), Vector3(0, 60, 20), 60.0],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(600.0).timeout.connect(quit.bind(2))
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
	for occ: float in OCCUPANCY:
		view.stands.occupancy = occ
		for name: String in SHOTS:
			var s = SHOTS[name]
			if s is Vector2:
				cam.mode = MwRinkCamera3D.Mode.FOLLOW
				cam.follow(MwRink3D.map_point(s.x, s.y, 0) - Vector2(MwRink3D.SCREEN) / 2.0)
			else:
				var at: Vector3 = s[0]
				var to: Vector3 = s[1]
				cam.projection = Camera3D.PROJECTION_PERSPECTIVE
				cam.fov = s[2]
				cam.near = 0.05
				cam.far = 400.0
				var from := MwRink3D.world(at.x, at.y, at.z)
				cam.transform = Transform3D(Basis.looking_at(MwRink3D.world(to.x, to.y, to.z) - from, Vector3.UP), from)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png(out_dir.path_join("%s_%03d.png" % [name, roundi(occ * 100)]))
			print(name, " ", occ)
	quit()
