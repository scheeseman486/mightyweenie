extends RefCounted
## Plan 40 (T8): the 3D review renders' set-up (test/rink3d/*_shots.gd,
## desktop, a renderer needed): the rink's 3D view in a viewport of its own
## world, its palette, the camera's free shots (an orbit round a rink point)
## and the follow camera, the picture saved. The scripts keep only their
## shot tables.
##
##   var rig := ShotRig.new()
##   rig.make(root, Vector2i(960, 672), stadium)
##   await process_frame
##   rig.orbit(Vector3(0, 40, 0), 55.0, 0.0, 1000.0, 50.0)
##   await rig.save(out_dir.path_join("overview.png"))

const VIEW := preload("res://src/rink3d/rink_view_3d.tscn")
## The rink's palette as the review renders draw it (the rink's recipe
## without the players' port lines).
const PALETTE_STEPS := MwScreenPalettes.RINK

var viewport: SubViewport
var view: MwRinkView3D


## The 3D view, [param size] big, in a viewport of its own world under
## [param root] (the SceneTree's), with team [param team_a]'s and stadium
## [param stadium]'s colours ([param team_b] -1: team A's). Shoot after the
## next frame.
func make(root: Node, size: Vector2i, stadium := 0, team_a := -1, team_b := -1) -> MwRinkView3D:
	viewport = SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	view = VIEW.instantiate()
	var pal := RomPalette.make(4, PackedStringArray(PALETTE_STEPS), team_a if team_a >= 0 else stadium, stadium)
	if team_b >= 0:
		pal.team_b = team_b
	view.palette = pal
	viewport.add_child(view)
	return view


## A free shot: the camera [param dist_px] rink pixels from [param look]
## (rink px, z up), [param pitch_deg] above the ice, turned [param yaw_deg]
## (0: looking north from the south, 90: looking west), [param fov_deg]
## (vertical).
func orbit(look: Vector3, pitch_deg: float, yaw_deg: float, dist_px: float, fov_deg: float) -> void:
	var cam := view.camera
	var pitch := deg_to_rad(pitch_deg)
	var y := deg_to_rad(yaw_deg)
	var back := Vector3(sin(y) * cos(pitch), sin(pitch), cos(y) * cos(pitch))
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = fov_deg
	cam.near = 0.05
	cam.far = 400.0
	cam.transform = Transform3D(Basis.from_euler(Vector3(-pitch, y, 0)),
			MwRink3D.world(look.x, look.y, look.z) + back * (dist_px * MwRink3D.METRES_PER_PX))


## The game's follow camera looking at ice point [param at] (rink px).
func follow(at: Vector2) -> void:
	var cam := view.camera
	cam.mode = MwRinkCamera3D.Mode.FOLLOW
	cam.follow(MwRink3D.map_point(at.x, at.y, 0) - Vector2(MwRink3D.SCREEN) / 2.0)


## The picture after two drawn frames.
func image() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


## The picture saved at [param path]; returned too.
func save(path: String) -> Image:
	var img: Image = await image()
	img.save_png(path)
	return img
