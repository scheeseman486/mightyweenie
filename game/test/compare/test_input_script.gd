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
		var s := MwInputScript.parse(case.text)
		assert_eq(s.error, "", case.text)
		assert_eq(s.events.size(), 1, case.text)
		if s.events.size() != 1:
			continue
		var e: Dictionary = s.events[0]
		for k in case.event:
			var want: Variant = case.event[k]
			if want is float:
				want = int(want)
			assert_eq(e[k], want, "%s: %s" % [case.text, k])
		assert_eq(MwInputScript.event_to_text(e), case.canonical)


func test_invalid_lines() -> void:
	for text in _fix.invalid:
		var s := MwInputScript.parse(text)
		assert_true(s.error.begins_with("line 1:"), "%s -> '%s'" % [text, s.error])


func test_shipped_scripts_round_trip() -> void:
	var dir := DirAccess.open(_repo("compare/scripts"))
	assert_not_null(dir)
	for f in dir.get_files():
		if not f.ends_with(".mwi"):
			continue
		var s := MwInputScript.load_file(_repo("compare/scripts").path_join(f))
		assert_eq(s.error, "", f)
		assert_gt(s.events.size(), 0, f)
		assert_eq(MwInputScript.parse(s.to_text()).to_text(), s.to_text(), f)
