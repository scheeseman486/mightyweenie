extends GutTest
## MwScriptPlayer must apply scripts with exactly the timing rules of the
## Python ScriptPlayer (docs/compare.md). Hand-checked fixture shared with
## harness/tests/test_script.py.

var _fix: Dictionary


func before_all() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(
		"../compare/fixtures/player_timeline.json").simplify_path()
	_fix = JSON.parse_string(FileAccess.get_file_as_string(path))


func _play(case: Dictionary) -> MwScriptPlayer:
	var player := MwScriptPlayer.new(MwInputScript.parse(case.script))
	for step in case.timeline:
		match step[0]:
			"screen":
				player.screen_entered(int(step[1]), int(step[2]))
			"tick":
				player.tick_start(int(step[1]))
			"pass":
				player.boundary(int(step[1]), int(step[2]), int(step[3]), int(step[4]))
			"resume":
				player.resume(int(step[1]), int(step[2]))
	return player


func test_timing_rules() -> void:
	for case in _fix.cases:
		var got: Array = []
		for entry in _play(case).change_log:
			got.append([entry[0], int(entry[1]), int(entry[2]), entry[3]])
		var want: Array = []
		for entry in case.log:
			want.append([entry[0], int(entry[1]), int(entry[2]), entry[3]])
		assert_eq(got, want, case.name)


func test_tap_is_read_by_exactly_one_pass() -> void:
	for length in range(1, 8):
		var player := MwScriptPlayer.new(MwInputScript.parse("@screen 5 +3 P1 A"))
		player.screen_entered(5, 0)
		var reads := 0
		var n := 0
		for t in range(1, 60):
			player.tick_start(t)
			if t % length == 0:
				player.boundary(5, 1, n, t)
				n += 1
				if player.held(1) != 0:
					reads += 1
		assert_eq(reads, 1, "pass length %d" % length)
