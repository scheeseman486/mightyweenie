extends GutTest
## The frame rate is free (plan 14; owner: an unlocked frame rate must not
## change the game's behaviour or timing): all game logic runs on the fixed
## 60 Hz physics tick (Router, screens' passes), nothing reads the rendered
## frame's time, and the frame rate is not capped by the project.

## Scripts allowed a per-frame callback: presentation only (interpolation),
## and the start's background loading (plan 27: it polls its threads and
## notes how long its steps take; nothing in the game waits on its timing).
## Plan 34's saves and saved replays read the clock once to date a file
## (no game logic; plan 40: through MwFileStamp). Plan 35: the Router autoload hands the online pages'
## service and an online match the time once a physics tick (the network's
## pings, resends, timeouts, a refusal's wait; the game's ticks come from the
## input stream, never from the clock - the net code itself reads none).
## Plan 41: a client's run-ahead times itself against its budget - how
## many passes ahead it draws (presentation; the game's state, hashes and
## sound calls are the same with it, without it, at any speed). Owner,
## 2026-10-13 (music dropouts): an online client's heard sound driver keeps
## the wall clock (MwAudioPump) - only what is heard; the game's own driver
## is stepped by the ticks.
const PER_FRAME_OK := ["res://scenes/_proof/rink3d_proof.gd", "res://src/rink3d/rink_view_3d.gd",
		"res://src/flow/preloader.gd", "res://src/data/file_stamp.gd",
		"res://src/flow/router_service.gd",
		"res://scenes/rink_editor/rink_editor.gd",   # (plan 38: its camera, presentation)
		"res://src/net/net_run_ahead.gd",
		"res://src/audio/audio_pump.gd"]
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
