extends GutTest
## MlhRng must reproduce the original's RNG exactly. The fixture is a BlastEm
## trace of the original ROM (numbers only), shared with the Python harness.

var _fixture: Dictionary


func before_all() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(
		"../harness/tests/fixtures/rng_trace.json").simplify_path()
	_fixture = JSON.parse_string(FileAccess.get_file_as_string(path))


func test_fixture_loaded() -> void:
	assert_not_null(_fixture)
	assert_eq(_fixture.next_states.size(), 256)


func test_next_state_matches_original() -> void:
	var rng := MlhRng.new(int(_fixture.start_state))
	for want in _fixture.next_states:
		assert_eq(rng.next_state(), int(want))


func test_range_value_matches_original() -> void:
	for range_call in _fixture.range_calls:
		var rng := MlhRng.new(int(range_call.state_before))
		assert_eq(rng.range_value(int(range_call.lo), int(range_call.hi)), int(range_call.value),
			"range %d..%d" % [int(range_call.lo), int(range_call.hi)])


func test_state_stays_32_bit() -> void:
	var rng := MlhRng.new(0xFFFFFFFF)
	for i in 1000:
		rng.next_state()
		assert_between(rng.state, 0, 0xFFFFFFFF)
