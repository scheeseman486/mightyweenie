extends GutTest
## MwInputScript must read scripts exactly like the Python parser. Fixture
## shared with harness/tests/test_script.py.

var _fix: Dictionary


func before_all() -> void:
	_fix = JSON.parse_string(FileAccess.get_file_as_string(_repo("compare/fixtures/scripts_parse.json")))


static func _repo(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel).simplify_path()


func test_valid_lines() -> void:
	for case in _fix.valid:
		var input_script := MwInputScript.parse(case.text)
		assert_eq(input_script.error, "", case.text)
		assert_eq(input_script.events.size(), 1, case.text)
		if input_script.events.size() != 1:
			continue
		var parsed: Dictionary = input_script.events[0]
		for k in case.event:
			var want: Variant = case.event[k]
			if want is float:
				want = int(want)
			assert_eq(parsed[k], want, "%s: %s" % [case.text, k])
		assert_eq(MwInputScript.event_to_text(parsed), case.canonical)


func test_invalid_lines() -> void:
	for text in _fix.invalid:
		var input_script := MwInputScript.parse(text)
		assert_true(input_script.error.begins_with("line 1:"), "%s -> '%s'" % [text, input_script.error])


func test_shipped_scripts_round_trip() -> void:
	var dir := DirAccess.open(_repo("compare/scripts"))
	assert_not_null(dir)
	for f in dir.get_files():
		if not f.ends_with(".mwi"):
			continue
		var input_script := MwInputScript.load_file(_repo("compare/scripts").path_join(f))
		assert_eq(input_script.error, "", f)
		assert_gt(input_script.events.size(), 0, f)
		assert_eq(MwInputScript.parse(input_script.to_text()).to_text(), input_script.to_text(), f)
