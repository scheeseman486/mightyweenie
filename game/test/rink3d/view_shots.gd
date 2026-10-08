extends SceneTree
## Plan 20 review renders (desktop, needs a renderer): the game's 3D views
## (MwRinkViews) on passes of a recorded match, each view's camera run over
## the 45 passes before the shot as in play (its smoothing settled), one
## contact sheet per pass: calibration (= the 2D), ortho, TV, dolly,
## birds-eye, birds-eye across, first person, cinematic, follow; and each
## view alone.
##
##   godot --path game -s res://test/rink3d/view_shots.gd -- OUT_DIR REC.json PASS[,PASS...] [MODES]
##
## MODES: comma-separated MwRinkCamera3D.Mode names (default: the eight above).

const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")
const W := 640
const H := 448
const LEAD := 45
const DEFAULT_MODES := ["CALIBRATION", "ORTHO", "TV", "DOLLY", "BIRDS_EYE", "BIRDS_EYE_ACROSS", "FIRST_PERSON", "CINEMATIC", "FOLLOW"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(600.0).timeout.connect(quit.bind(2))
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var passes: Array = (JSON.parse_string(FileAccess.get_file_as_string(args[1])) as Dictionary)["passes"]
	var at_list := Array(args[2].split(",")).map(func(a): return int(a))
	var modes: Array = Array(args[3].split(",")) if args.size() > 3 else DEFAULT_MODES
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rom := MwRom.data()
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var view: MwRinkView3D = VIEW.instantiate()
	var first: Dictionary = passes[0]["state"]
	var pal := RomPalette.make(4, PackedStringArray(["screen_palette", "rom 1BD8A 3"]), int(first.get("team_a", 0)), int(first.get("stadium", 0)))
	pal.team_b = int(first.get("team_b", 1))
	view.palette = pal
	vp.add_child(view)
	await process_frame
	for at: int in at_list:
		var sheet := Image.create_empty(W * 4, H * ((modes.size() + 3) / 4), false, Image.FORMAT_RGBA8)
		for mi in modes.size():
			var mode: int = MwRinkCamera3D.Mode.keys().find(modes[mi])
			view.set_camera_mode(mode)
			for k in range(maxi(at - LEAD, 0), at + 1):
				_present(view, rom, passes, k, k > at - LEAD)
				view.blend_to(1.0, 1.0 / 30.0)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.save_png(out_dir.path_join("pass%d_%d_%s.png" % [at, mi, String(modes[mi]).to_lower()]))
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((mi % 4) * W, (mi / 4) * H))
			print("pass %d %s" % [at, modes[mi]])
		sheet.save_png(out_dir.path_join("pass%d_sheet.png" % at))
	quit()


func _present(view: MwRinkView3D, rom: PackedByteArray, passes: Array, k: int, continuous: bool) -> void:
	var p: Dictionary = passes[k]
	var state := MwRinkState.from_dict(rom, p["state"])
	var drawer := MwRinkDraw3D.new(rom)
	drawer.build(state, p.get("phase_adds", []))
	var tiles := {}
	for slot in 4:
		var pv: Array = state.plates[slot]
		var b := MwPlate.tiles(rom, pv[0], pv[1], pv[2])
		for n in 8:
			tiles[MwRinkDraw.PLATE_TILES + 8 * slot + n] = b.slice(32 * n, 32 * n + 32)
	view.present(state, drawer, tiles, continuous)
