extends GutTest
## Environment smoke tests.
##
## These pin the project settings the reimplementation depends on, so an
## accidental change in the editor (or by an editor tool) fails loudly instead of
## silently altering timing or pixel output. They also prove the ROM can be
## read from disk, since every non-code asset is loaded from it at runtime.

const ROM_FILE := "Mutant League Hockey (USA, Europe).md"
## No-Intro SHA-1 of the only known dump (T-50766-00, 2 MiB).
const ROM_SHA1 := "84e203c5226bc1913a485804e59c6418e939bd3d"


## One physics tick = one tick of the original's 60 Hz tick_counter. Screen
## loops run a pass when their pass length has elapsed (docs/re/timing.md).
func test_tick_is_60hz() -> void:
	assert_eq(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"), 60,
		"Mirrors the original's 60 Hz tick_counter (docs/architecture.md, Timing)")


## Rendering is not capped (Stage 2, plan 14): the display's rate with vsync.
## Logic stays on the tick (test/rink3d/test_frame_rate.gd).
func test_render_rate_is_free() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/max_fps"), 0)


func test_native_resolution_is_h40() -> void:
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 320)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 224)


func test_pixel_grid_settings() -> void:
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "viewport")
	assert_eq(ProjectSettings.get_setting("display/window/stretch/scale_mode"), "integer")
	assert_true(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel"))
	assert_eq(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"), 0,
		"Textures must use nearest filtering")


func test_private_user_dir() -> void:
	assert_true(ProjectSettings.get_setting("application/config/use_custom_user_dir"))
	assert_eq(ProjectSettings.get_setting("application/config/custom_user_dir_name"), "mightyweenie")


func test_rom_present_and_verified() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../rom").path_join(ROM_FILE).simplify_path()
	if not FileAccess.file_exists(path):
		pending("ROM not installed at %s (see rom/README.md)" % path)
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	assert_eq(bytes.size(), 2 * 1024 * 1024, "ROM should be 2 MiB")
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(bytes)
	assert_eq(ctx.finish().hex_encode(), ROM_SHA1, "ROM must be the No-Intro dump")
	# Cartridge header sanity: system type and product code.
	assert_eq(bytes.slice(0x100, 0x10C).get_string_from_ascii(), "SEGA GENESIS")
	assert_eq(bytes.slice(0x180, 0x18E).get_string_from_ascii(), "GM T-50766 -00")
