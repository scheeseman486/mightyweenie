extends SceneTree
## Plan 15 review renders (desktop, needs a renderer): the 3D rink with its
## stands and crowd, from the game's follow camera at points round the rink
## and from a few overviews, at 960 x 672. Writes PNGs to the output folder.
##
##   godot --path game -s res://test/rink3d/crowd_shots.gd -- OUT_DIR [STADIUM]

const ShotRig := preload("res://test/support/shot_rig.gd")
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
	"satan": [Vector3(235, 0, 25), 15.0, -90.0, 200.0, 55.0],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(180.0).timeout.connect(quit.bind(2))
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var stadium := int(args[1]) if args.size() > 1 else 0
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rig := ShotRig.new()
	rig.make(root, Vector2i(960, 672), stadium)
	await process_frame
	for name: String in FOLLOW:
		rig.follow(FOLLOW[name])
		await rig.save(out_dir.path_join(name + ".png"))
		print(name)
	for name: String in SHOTS:
		var shot: Array = SHOTS[name]
		rig.orbit(shot[0], shot[1], shot[2], shot[3], shot[4])
		await rig.save(out_dir.path_join(name + ".png"))
		print(name)
	quit()
