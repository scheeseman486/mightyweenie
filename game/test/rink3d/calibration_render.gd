extends SceneTree
## Plan 14 desktop check (needs a renderer, not headless): recorded passes
## drawn by the 2D rink and by the 3D rink through the calibration camera
## (the original's projection), plus the default 3D camera for review.
## Writes PNGs and summary.json (pixels differing between 2D and the
## calibration view, and how many are outside the deviations the plan lists:
## expected 0 but for a few edge pixels) to the output folder.
## tools/bin/rink3d-calibration runs it.
##
##   godot --path game -s res://test/rink3d/calibration_render.gd -- OUT_DIR demo_s3:400,1500 human_s9:800

const PROOF := preload("res://scenes/_proof/rink3d.tscn")
const LABEL_ROWS := 14     # the proof scene's info line

## The deviations the plan lists (map points of the 2D screen): the near
## boards and the ice behind the near goal line (the owner's board layout),
## the far end's boards (translucent glass, the thick glass on the curves),
## the sides' boards and pens (the benches, the referee's box: their walls,
## their black floor); and (plan 16) the black floor outside the ice.
static func _listed(mx: int, my: int) -> bool:
	return my >= 760 or my < 90 or (my < 160 and (mx < 140 or mx > 372)) or mx < 72 or mx > 440



## Plan 16: the floor is black outside the ice (the 2D picture draws the
## flat surroundings there).
static func _off_ice(rom: PackedByteArray, mx: int, my: int) -> bool:
	var p := MwRink3D.ice_under_map(Vector2(mx, my))
	return absf(p.x) >= MwRinkModel.ice_half_width(rom, int(p.y))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(180.0).timeout.connect(quit.bind(2))    # never leave a window open
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var proof: Node2D = PROOF.instantiate()
	if not proof.has_method("_present"):
		push_error("the proof scene's script did not load")
		quit(1)
		return
	proof.start_3d = false
	root.add_child(proof)
	await process_frame
	proof.paused = true
	var summary := []
	var rom := MwRom.data()
	for spec: String in args.slice(1):
		var parts := spec.split(":")
		var idx: int = Array(proof.files).map(func(f: String) -> String: return f.get_file().get_basename()).find(parts[0])
		if idx < 0:
			push_error("no recording " + parts[0])
			continue
		proof._load(idx)
		for n in parts[1].split(","):
			proof.at = int(n)
			var name := "%s_%05d" % [parts[0], int(n)]
			var a := await _shot(proof, false, MwRinkCamera3D.Mode.CALIBRATION)
			var b := await _shot(proof, true, MwRinkCamera3D.Mode.CALIBRATION)
			var c := await _shot(proof, true, MwRinkCamera3D.Mode.FOLLOW)
			a.save_png(out_dir.path_join(name + "_2d.png"))
			b.save_png(out_dir.path_join(name + "_calib.png"))
			c.save_png(out_dir.path_join(name + "_follow.png"))
			var shown: Array = proof.passes[proof.at]["state"]["camera"]["shown"]
			var differ := 0
			var outside := 0
			for y in range(LABEL_ROWS, a.get_height()):
				for x in a.get_width():
					var p := a.get_pixel(x, y)
					var q := b.get_pixel(x, y)
					if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.06:
						differ += 1
						var mx := x + int(shown[0])
						var my := y + int(shown[1])
						if not _listed(mx, my) and not (q.r + q.g + q.b < 0.01 and _off_ice(rom, mx, my)):
							outside += 1
			summary.append({"pass": name, "differ": differ, "outside_listed": outside})
			print("%s: %d pixels differ, %d outside the listed deviations" % [name, differ, outside])
	var f := FileAccess.open(out_dir.path_join("summary.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "  "))
	f.close()
	quit()


func _shot(proof: Node2D, three_d: bool, mode: int) -> Image:
	proof.show_3d = three_d
	proof.view.set_camera_mode(mode)
	proof._present()
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
