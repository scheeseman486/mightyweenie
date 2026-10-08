extends GutTest
## The frame rate is free (plan 14; owner: an unlocked frame rate must not
## change the game's behaviour or timing): all game logic runs on the fixed
## 60 Hz physics tick (Router, screens' passes), nothing reads the rendered
## frame's time, and the frame rate is not capped by the project.

## Scripts allowed a per-frame callback: presentation only (interpolation).
const PER_FRAME_OK := ["res://scenes/_proof/rink3d_proof.gd", "res://src/rink3d/rink_view_3d.gd"]
const PER_FRAME := ["func _process(", "get_frames_drawn(", "get_process_frames(", "Time.get_ticks", "get_unix_time"]


func test_game_logic_does_not_run_per_rendered_frame() -> void:
	var found := []
	for dir in ["res://src", "res://scenes"]:
		for path in _scripts(dir):
			if path in PER_FRAME_OK:
				continue
			var text := FileAccess.get_file_as_string(path)
			for needle in PER_FRAME:
				if text.contains(needle):
					found.append("%s: %s" % [path, needle])
	assert_eq(found, [], "per-frame code outside the presentation allow-list")


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
