extends SceneTree
## Plan 16 review renders (desktop): recorded passes in the 3D view from the
## game's cameras and from free ones round the players, the nets and the
## winged skulls, 960 x 540. Writes PASS_CAMERA.png to the output folder.
##
##   godot --path game -s res://test/rink3d/sprite_shots.gd -- OUT_DIR [SET [RECORDING]]
##
## SET: facing (players, nets, winged skulls; default), order (players at
## the boards, in the corners and at the ends, from inside and outside the
## rink), crowd (the side stands and corners from either end) or mix (the
## crowd's colours for a few matchups, MwCrowdMix; full stands), nets (the
## 3D nets close up, plan 17, in stadium 1's colours: the cyan rinks'; the
## close-ups without the players, who stand in the way) or battle (the same
## with Battle Nets).

const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")
## pass -> what it shows
const PASSES := {120: "lineup", 245: "carried", 402: "far_goal", 1500: "play", 3541: "near_goal"}
## (crowd) name -> [camera at, looking at, vertical fov]
const CROWD := {
	"left_from_south": [Vector3(-60, 330, 110), Vector3(-280, -40, 90), 50.0],
	"left_from_north": [Vector3(-60, -330, 110), Vector3(-280, 40, 90), 50.0],
	"right_from_south": [Vector3(60, 330, 110), Vector3(280, -40, 90), 50.0],
	"right_from_north": [Vector3(60, -330, 110), Vector3(280, 40, 90), 50.0],
	"far_left_corner": [Vector3(60, -150, 100), Vector3(-260, -420, 90), 50.0],
	"near_right_corner": [Vector3(-60, 150, 100), Vector3(260, 420, 90), 50.0],
}
## (mix) [team A, team B, stadium, label]; "original": every fan in team A's
## colours, as the original
const MIX := [[0, 7, 0, "original"], [0, 7, 0, "hearts_v_monsters_at_hearts"],
		[5, 22, 5, "weenies_v_aces_at_weenies"], [22, 5, 22, "aces_v_weenies_at_aces"],
		[1, 2, 7, "bots_v_liars_at_monsters"]]
const MIX_SHOTS := {
	"follow": MwRinkCamera3D.Mode.FOLLOW,
	"left_from_south": [Vector3(-60, 330, 110), Vector3(-280, -40, 90), 50.0],
	"far_end": [Vector3(0, -120, 120), Vector3(0, -470, 95), 60.0],
}
## (nets) the nets close up, the far net's then the near net's: name -> [camera at, looking at, fov]
const NET_SHOTS := {
	"far_front_low": [Vector3(26, -255, 28), Vector3(0, -336, 6), 40.0],
	"far_front_high": [Vector3(0, -250, 95), Vector3(0, -336, 6), 36.0],
	"far_side": [Vector3(80, -330, 30), Vector3(0, -336, 8), 36.0],
	"far_behind": [Vector3(-34, -368, 34), Vector3(0, -333, 8), 50.0],
	"far_corner_front": [Vector3(-36, -296, 36), Vector3(-21, -330, 19), 24.0],
	"far_corner_back": [Vector3(-44, -362, 42), Vector3(-21, -331, 19), 24.0],
	"near_front_low": [Vector3(-26, 255, 28), Vector3(0, 336, 6), 40.0],
	"near_behind_high": [Vector3(30, 430, 90), Vector3(0, 333, 6), 36.0],
	"follow": MwRinkCamera3D.Mode.FOLLOW,
	"calibration": MwRinkCamera3D.Mode.CALIBRATION,
}
## (order) pass -> [what it shows, the player's point (rink px)]
const ORDER := {3128: ["right_side", Vector3(176, 5, 0)], 270: ["left_side", Vector3(-170, -126, 0)],
		996: ["far_right_corner", Vector3(156, -322, 0)], 3059: ["near_left_corner", Vector3(-137, 362, 0)],
		3071: ["near_boards", Vector3(68, 362, 0)], 2028: ["far_boards", Vector3(-20, -354, 0)]}
## name -> [camera at, looking at (rink px; null = the play), vertical fov],
## or a camera mode (follow, calibration).
const SHOTS := {
	"follow": MwRinkCamera3D.Mode.FOLLOW,
	"calibration": MwRinkCamera3D.Mode.CALIBRATION,
	"reverse_high": [Vector3(0, -620, 300), null, 46.0],
	"side_low": [Vector3(170, 0, 60), null, 55.0],
	"far_corner_low": [Vector3(-150, -350, 50), null, 52.0],
	"outside_far_top": [Vector3(0, -610, 270), null, 48.0],
	"far_net_behind": [Vector3(30, -365, 45), Vector3(0, -250, 10), 55.0],
	"near_net_from_north": [Vector3(0, 180, 80), Vector3(0, 340, 15), 50.0],
	"far_skull_side": [Vector3(-130, -260, 90), Vector3(0, -372, 47), 45.0],
	"near_skull_inside": [Vector3(70, 250, 70), Vector3(0, 374, 12), 45.0],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(600.0).timeout.connect(quit.bind(2))
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var set: String = args[1] if args.size() > 1 else "facing"
	var name: String = args[2] if args.size() > 2 else "demo_s3"
	var nets_set := set in ["nets", "battle"]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rom := MwRom.data()
	var path := ProjectSettings.globalize_path("res://").path_join("../out/rink/dec").path_join(name + ".json").simplify_path()
	var passes: Array = (JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary)["passes"]
	var first: Dictionary = passes[0]["state"]
	var vp := SubViewport.new()
	vp.size = Vector2i(960, 540)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var view: MwRinkView3D = VIEW.instantiate()
	var palette := RomPalette.make(4, PackedStringArray(["screen_palette", "rom 1BD8A 3"]),
			int(first.get("team_a", 0)), 1 if nets_set else int(first.get("stadium", 0)))
	palette.team_b = int(first.get("team_b", 5))
	view.palette = palette
	vp.add_child(view)
	view.stands.occupancy = 1.0 if set == "mix" else 0.5
	await process_frame
	var drawer := MwRinkDraw3D.new(rom)
	var cam := view.camera
	var list: Dictionary = PASSES if set == "facing" else ({1500: "crowd"} if set in ["crowd", "mix"] else ({402: "far_goal", 3541: "near_goal"} if nets_set else ORDER))
	for at: int in list:
		for mix: Variant in (MIX if set == "mix" else [null]):
			var p: Dictionary = passes[at]
			var label: String = PASSES[at] if set == "facing" or nets_set else ("crowd" if set == "crowd" else ("" if set == "mix" else ORDER[at][0]))
			if mix != null:
				palette.team_a = mix[0]
				palette.team_b = mix[1]
				palette.stadium = mix[2]
				view.stands.variety = mix[3] != "original"
				view.stands.refresh()
				label = mix[3]
			var state := MwRinkState.from_dict(rom, p["state"])
			if set == "battle":
				for n in state.nets:
					n.style = 2
					n.anim = MwAnimState.from_record(rom, MwGfx.u32(rom, MwRinkState.NET_ANIMS + 8), 0 if n.bottom else 1)
			drawer.build(state, p.get("phase_adds", []))
			var tiles := {}
			for slot in 4:
				var v: Array = state.plates[slot]
				var b := MwPlate.tiles(rom, v[0], v[1], v[2])
				for n in 8:
					tiles[MwRinkDraw.PLATE_TILES + 8 * slot + n] = b.slice(32 * n, 32 * n + 32)
			cam.mode = MwRinkCamera3D.Mode.FOLLOW
			view.present(state, drawer, tiles, false)
			var focus := MwRinkCamera3D.look_point(Vector2(state.camera.shown))
			var shots: Dictionary = SHOTS if set == "facing" else (CROWD if set == "crowd" else (MIX_SHOTS if set == "mix" else (NET_SHOTS if nets_set else _order_shots(ORDER[at][1]))))
			for shot: String in shots:
				var s = shots[shot]
				if s is int:
					cam.mode = s
					view.world.scale = cam.world_scale()
				else:
					cam.mode = MwRinkCamera3D.Mode.FREE
					view.world.scale = Vector3.ONE
					var from: Vector3 = s[0]
					if shot == "side_low":
						from.y = focus.y
					var to: Vector3 = s[1] if s[1] != null else focus
					cam.projection = Camera3D.PROJECTION_PERSPECTIVE
					cam.keep_aspect = Camera3D.KEEP_HEIGHT
					cam.fov = s[2]
					cam.near = 0.05
					cam.far = 400.0
					var a := MwRink3D.world(from.x, from.y, from.z)
					cam.transform = Transform3D(Basis.looking_at(MwRink3D.world(to.x, to.y, to.z) - a, Vector3.UP), a)
				view.blend_to(1.0)
				view.sprites.visible = not (nets_set and not s is int)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				vp.get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [label, shot]))
				print(label, " ", shot)
	quit()


## Cameras round a player at the boards [param p]: the game's, from across
## the rink low, along the boards, and from outside over the stands.
static func _order_shots(p: Vector3) -> Dictionary:
	var sx := signf(p.x) if absf(p.x) > 1.0 else 1.0
	var sy := signf(p.y) if absf(p.y) > 1.0 else 1.0
	var end := absf(p.y) > 300.0
	var outside := Vector3(p.x, sy * 600, 280) if end else Vector3(sx * 420, p.y, 260)
	var across := Vector3(p.x, p.y - sy * 160, 45) if end else Vector3(p.x - sx * 150, p.y + 40, 45)
	var along := Vector3(p.x - sx * 12, p.y - sy * 150, 40) if not end else Vector3(p.x - sx * 150, p.y - sy * 15, 40)
	return {
		"follow": MwRinkCamera3D.Mode.FOLLOW,
		"calibration": MwRinkCamera3D.Mode.CALIBRATION,
		"reverse_high": [Vector3(0, -620, 300), p, 46.0],
		"across_low": [across, p + Vector3(0, 0, 15), 50.0],
		"along_boards": [along, p + Vector3(0, 0, 15), 50.0],
		"outside_top": [outside, p, 40.0],
	}
