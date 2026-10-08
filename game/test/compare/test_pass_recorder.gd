extends GutTest
## MwPassRecorder writes mw-pass/1 lines the Python diff tool reads.


func test_lines_follow_the_format() -> void:
	var rec := MwPassRecorder.new()
	rec.header("t", ["time", "input"])
	rec.screen(1, 1, 50, -1)
	rec.pass_line({"screen": 1, "visit": 1, "pass": 0, "tick": 51, "elapsed": 1}, [0x8080, 0, 0, 0], {"rng": 12})
	rec.end(52)
	assert_eq(rec.lines.size(), 4)
	var head: Dictionary = JSON.parse_string(rec.lines[0])
	assert_eq(head.format, "mw-pass/1")
	assert_eq(head.side, "godot")
	var p: Dictionary = JSON.parse_string(rec.lines[2])
	for k in ["screen", "visit", "pass", "tick", "elapsed", "pads", "rng"]:
		assert_true(p.has(k), k)
	assert_eq(int(p.pads[0]), 0x8080)
	# integers stay integers in the text (the diff compares exact values)
	assert_false(rec.lines[2].contains(".0"))


func test_save(params = use_parameters([["user://compare_test/x.jsonl"]])) -> void:
	var rec := MwPassRecorder.new()
	rec.header("t", [])
	rec.end(1)
	var path := ProjectSettings.globalize_path(params[0])
	assert_eq(rec.save(path), OK)
	assert_eq(FileAccess.get_file_as_string(path).split("\n", false).size(), 2)
