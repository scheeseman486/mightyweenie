extends GutTest
## Plan 40 (R2): the 3D view's layers decided once a frame (MwViewLayers) -
## the settings in the game's cameras, none of the port's layers from the
## calibration camera, the crowd's duck in the main cameras only.

const SETTINGS := ["reflections", "flat_shadows", "blood", "ice_detail", "crowd_duck"]
var _was := {}


func before_each() -> void:
	var sc: GDScript = MwSettings
	for k in SETTINGS:
		_was[k] = sc.get(k)


func after_each() -> void:
	var sc: GDScript = MwSettings
	for k in SETTINGS:
		sc.set(k, _was[k])


func _all(on: bool) -> void:
	var sc: GDScript = MwSettings
	for k in SETTINGS:
		sc.set(k, on)


func test_the_game_s_cameras_show_the_settings() -> void:
	_all(true)
	var layers := MwViewLayers.of(MwRinkCamera3D.Mode.FOLLOW, true, true)
	assert_false(layers.original)
	assert_true(layers.reflections and layers.flat_shadows and layers.paint and layers.blood and layers.ice_detail)
	assert_true(layers.benches and layers.particles and layers.crowd_duck)
	_all(false)
	layers = MwViewLayers.of(MwRinkCamera3D.Mode.FOLLOW, true, true)
	assert_false(layers.reflections or layers.flat_shadows or layers.blood or layers.ice_detail or layers.particles
			or layers.crowd_duck)
	assert_true(layers.paint and layers.benches, "not VISUALS switches")
	assert_false(MwViewLayers.of(MwRinkCamera3D.Mode.FOLLOW, false, false).paint, "no paint model")
	assert_false(MwViewLayers.of(MwRinkCamera3D.Mode.FOLLOW, false, false).benches)


func test_the_calibration_camera_shows_the_original() -> void:
	_all(true)
	var layers := MwViewLayers.of(MwRinkCamera3D.Mode.CALIBRATION, true, true)
	assert_true(layers.original)
	assert_false(layers.reflections or layers.flat_shadows or layers.paint or layers.benches or layers.particles
			or layers.crowd_duck)


func test_the_crowd_ducks_in_the_main_cameras_only() -> void:
	_all(true)
	for m in [MwRinkCamera3D.Mode.FOLLOW, MwRinkCamera3D.Mode.EXTENDED]:
		assert_true(MwViewLayers.of(m, false, true).crowd_duck)
	for m in [MwRinkCamera3D.Mode.TV, MwRinkCamera3D.Mode.ORTHO, MwRinkCamera3D.Mode.CINEMATIC]:
		assert_false(MwViewLayers.of(m, false, true).crowd_duck, str(m))
