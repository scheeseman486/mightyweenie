extends GutTest
## Plan 45 (M3): MwSimDict decodes a saved replay's body - a file players
## share - so it sets only the state objects' own script variables (a
## "script" key reached the class's GDScript: its static variables and its
## engine properties), from values of types they can take, and grows an
## owned array of objects to at most MwSimDict.GROW_MAX; a form made by
## MwSimDict.to_dict reads back as before.


func test_a_form_reads_back_as_it_was_made() -> void:
	var state := MwRinkState.new()
	state.tick = 1234
	state.teams[1].score = 4
	var form := MwSimDict.to_dict(state)
	assert_eq(MwSimDict.to_dict(MwSimDict.from_dict(form)), form)


func test_a_form_cannot_reach_the_classes_scripts() -> void:
	var script: GDScript = MwRinkState
	var team_script: GDScript = MwRinkState.Team
	var was := [script.resource_name, team_script.resource_name]
	var state := MwSimDict.from_dict({"script": {"resource_name": "set by a file"},
			"teams": [{"script": {"resource_name": "set by a file"}}]})
	assert_eq([script.resource_name, team_script.resource_name], was, "the scripts untouched")
	assert_eq(state.get_script(), script)
	script.resource_name = was[0]
	team_script.resource_name = was[1]


func test_engine_properties_and_unknown_keys_are_left_alone() -> void:
	var state := MwSimDict.from_dict({"reference_count": 99, "no_such_field": 1, 7: 8})
	assert_not_null(state)
	assert_eq(state.get_reference_count(), 1, "not set from the form")


func test_values_of_the_wrong_type_leave_the_fields_as_they_are() -> void:
	var state := MwRinkState.new()
	state.tick = 77
	MwSimDict.apply(state, {"tick": "soon", "teams": "two", "stadium": [1, 2]})
	assert_eq(state.tick, 77)
	assert_eq(state.teams.size(), 2)
	MwSimDict.apply(state, {"teams": [{"score": {"goals": 3}, "markers": "none"}, 5]})
	assert_eq(state.teams[0].score, 0)


func test_an_owned_array_grows_at_most_to_the_cap() -> void:
	var state := MwRinkState.new()
	var markers := state.teams[0].markers.size()
	var many := []
	for i in MwSimDict.GROW_MAX + 1:
		many.append({"x": i})
	MwSimDict.apply(state, {"teams": [{"markers": many}]})
	assert_eq(state.teams[0].markers.size(), markers, "past the cap: refused")
	many.resize(MwSimDict.GROW_MAX)
	MwSimDict.apply(state, {"teams": [{"markers": many}]})
	assert_eq(state.teams[0].markers.size(), MwSimDict.GROW_MAX, "up to it: grown (an extended set-up's)")
	assert_eq(state.teams[0].markers[MwSimDict.GROW_MAX - 1].x, MwSimDict.GROW_MAX - 1)
