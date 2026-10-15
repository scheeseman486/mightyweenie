extends "res://test/rom/rom_test_base.gd"
## Plan 45: the determinism lint (docs/net.md, "The determinism rules";
## docs/style.md D1-D8). The code every machine of an online match runs in
## lockstep - or carries in a snapshot or the run-ahead's copy - reads
## nothing that can differ between machines, platforms (Linux, Windows),
## builds (debug, release) or runs. Comments and strings are stripped; each
## reviewed exception names the line it allows (a piece of its code) and why
## it is safe. A new breach fails here with the rule it breaks.
## Short names: rx a rule's compiled RegEx.

const RinkRig := preload("res://test/support/rink_rig.gd")

## Every script under these folders is lockstep code.
const DIRS := ["res://src/sim"]
## ... and these scripts.
const FILES := [
	"res://src/screens/screen_sim.gd", "res://src/screens/screen_sims.gd", "res://src/screens/fight_sim.gd",
	"res://src/screens/message_scoreboard_sim.gd", "res://src/screens/referee_sim.gd",
	"res://src/screens/replay_sim.gd", "res://src/screens/scoreboard_sim.gd",
	"res://src/screens/special_plays_sim.gd", "res://src/screens/stats_sim.gd",
	"res://src/compare/sim_dict.gd", "res://src/compare/pass_clock.gd",
	"res://src/flow/session.gd", "res://src/flow/selection.gd", "res://src/flow/lineup.gd",
	"res://src/flow/captain_vote.gd", "res://src/flow/humans.gd", "res://src/flow/match_setup.gd",
	"res://src/crowd/crowd_life.gd", "res://src/rink3d/match_models.gd",
	"res://src/intro/intro_cast.gd", "res://src/intro/match_rehearsal.gd",
	"res://src/audio/sound.gd", "res://src/audio/sound_68k.gd", "res://src/audio/sound_z80.gd",
	"res://src/audio/fm_sfx.gd", "res://src/audio/organ_pool.gd", "res://src/audio/organ_tunes.gd",
	"res://src/net/net_hash.gd", "res://src/net/net_snapshot.gd", "res://src/net/net_graph.gd",
	"res://src/net/rink_copy.gd", "res://src/net/audio_copy.gd", "res://src/net/game_start.gd",
	"res://src/input/stick.gd", "res://src/input/gameplay_pads.gd", "res://src/input/tick_input.gd",
	"res://src/input/input_stream.gd", "res://src/input/input_frame.gd",
]

## rule -> [regex, what can differ]. (own_settings is checked by name:
## [method _own_setting].)
const RULES := {
	"global_rng": ["(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize|seed)\\s*\\(",
			"Godot's global generator: seeded from the clock, per process"],
	"rng": ["RandomNumberGenerator\\.new\\s*\\(|\\.randomize\\s*\\(",
			"a Godot generator: only seeded from the session's streams"],
	"clock": ["\\bTime\\.|\\bOS\\.(get_ticks|get_unix|get_system_time|delay)|\\bEngine\\.get_|\\bPerformance\\.",
			"the wall clock, frame counters"],
	"machine": ["\\bOS\\.(get_name|get_locale|get_environment|has_environment|get_process_id|get_cmdline"
			+ "|get_executable|is_debug_build|has_feature|get_processor)|\\bEngine\\.is_editor_hint"
			+ "|\\bDisplayServer\\.|(?<![\\w.])Input\\.|\\bInputMap\\.",
			"this machine, this build, its window and devices"],
	"libm": ["(?<![\\w.])(sin|cos|tan|asin|acos|atan|atan2|pow|exp|log|sinh|cosh|tanh|fmod|fposmod|deg_to_rad"
			+ "|rad_to_deg|lerp_angle|angle_difference|ease|smoothstep|snapped|snappedf|snappedi|is_equal_approx"
			+ "|is_zero_approx)\\s*\\(|\\.(angle|angle_to|angle_to_point|rotated|slerp|cubic_interpolate"
			+ "|bezier_interpolate|is_equal_approx|snapped)\\s*\\(",
			"the C maths library (its last bit differs between glibc and Windows' CRT), approximate comparisons"],
	"engine_hash": ["(?<![\\w.])hash\\s*\\(|\\.hash\\s*\\(\\s*\\)|get_instance_id\\s*\\(|get_property_list\\s*\\(",
			"engine hashes, object ids, reflection order"],
	"own_session": ["\\bsession_?\\.(view|birds_eye_across|extended_views|reckoning|net|machine)\\b",
			"a machine's own session fields (MwSession.OWN_FIELDS)"],
	"files": ["user://|\\bFileAccess\\.(?!COMPRESSION_)|\\bDirAccess\\.|\\bConfigFile\\b", "this machine's files"],
	"assert": ["(?<![\\w.])assert\\s*\\(", "stripped from release exports"],
	"timing": ["func _process\\s*\\(|func _physics_process\\s*\\(|create_timer\\s*\\(|create_tween\\s*\\("
			+ "|\\bawait\\b|call_deferred|set_deferred|\\bThread\\b|WorkerThreadPool",
			"frame time, wall-clock timers, deferred or threaded work"],
}
## The settings lockstep code may read besides [constant MwSettings.MATCH_RULES]:
## the rules' own functions (every machine's: the match's rules in force).
const RULE_FUNCTIONS := ["opening_view", "extended_play", "full_replays", "rink_tick_rate", "use_match_rules",
		"own_match_rules", "match_rules", "match_rules_in_force"]

## path -> rule -> [[a piece of the allowed line's code ("": any line of
## the file), why it is safe], ...]
const ALLOWED := {
	"res://src/flow/session.gd": {
		"global_rng": [["randi()", "the one draw for a session nobody gave a seed (online: the record's seed)"]],
		"own_settings": [["MwSettings.layout(player)",
				"offline only: an online start record holds every player's layout (MwNetMatch)"]],
	},
	"res://src/crowd/crowd_life.gd": {
		"rng": [["RandomNumberGenerator.new()",
				"seeded from the session's crowd stream; PCG integers (randf: an int scaled exactly)"]],
	},
	"res://src/intro/intro_cast.gd": {
		"rng": [["RandomNumberGenerator.new()", "seeded from the session's opening stream"]],
	},
	"res://src/audio/organ_pool.gd": {
		"rng": [["RandomNumberGenerator.new()", "the pick without a stream (offline renders, tests, the "
				+ "run-ahead's own model) - never a game's"], ["r.randomize()", "(the same generator)"]],
		"assert": [["assert(key >= 24", "a tune's data check, no side effect"]],
	},
	"res://src/input/stick.gd": {
		"libm": [["atan2(", "encode(): the source machine only (its code is the stream's); decode() is integers"]],
	},
	"res://src/input/tick_input.gd": {
		"libm": [["MwStick.angle(", "the stick code's angle byte (an integer), no maths library"]],
	},
	"res://src/compare/sim_dict.gd": {
		"engine_hash": [["", "ids key paths within one call; property lists in declaration order"]],
	},
	"res://src/net/net_graph.gd": {
		"engine_hash": [["", "as MwSimDict: ids within one call, declaration order"]],
		"rng": [["", "a decoded generator gets its seed and state"]],
	},
	"res://src/net/rink_copy.gd": {
		"engine_hash": [["", "the copy's pool is keyed by ids within this process"]],
		"rng": [["", "a copy gets its seed and state"]],
	},
	"res://src/net/audio_copy.gd": {
		"engine_hash": [["", "the copy's pool is keyed by ids within this process"]],
	},
	"res://src/rink3d/match_models.gd": {
		"own_settings": [["MwSettings.splatter",
				"the paint is local presentation (MwRinkState.PORT_FIELDS); the game never reads it"]],
	},
}


func test_lockstep_code_reads_nothing_a_machine_owns() -> void:
	var rules := {}
	for rule: String in RULES:
		var rx := RegEx.new()
		assert_eq(rx.compile(RULES[rule][0]), OK, rule)
		rules[rule] = rx
	var setting_rx := RegEx.create_from_string("\\bMwSettings\\.([A-Za-z_]\\w*)")
	var found: Array[String] = []
	var scope := _scope()
	assert_gt(scope.size(), 40, "the lockstep scope found")
	for path in scope:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		assert_gt(lines.size(), 1, path)
		for i in lines.size():
			var code := _code_of(lines[i])
			if code.strip_edges().is_empty():
				continue
			for rule: String in rules:
				if (rules[rule] as RegEx).search(code) != null and not _allowed(path, rule, code):
					found.append("%s:%d [%s] %s - %s" % [path, i + 1, rule, code.strip_edges(), RULES[rule][1]])
			for m in setting_rx.search_all(code):
				if _own_setting(m.get_string(1)) and not _allowed(path, "own_settings", code):
					found.append("%s:%d [own_settings] %s - a machine's own setting (only MwSettings.MATCH_RULES "
							% [path, i + 1, code.strip_edges()] + "are every machine's)")
	for f in found:
		gut.p(f)
	assert_eq(found, [] as Array[String], "lockstep code outside the determinism rules (docs/net.md)")


## The lint itself: comments and strings never count, a rule finds what it names.
func test_the_lint_reads_code_only() -> void:
	assert_eq(_code_of("x = randi() # randf()"), "x = randi() ")
	assert_eq(_code_of("s = \"Time.now # x\" + 'a\\'b'"), "s = \"\" + ''")
	var rx := RegEx.create_from_string(RULES["global_rng"][0])
	assert_not_null(rx.search("var r := randi() & 1"))
	assert_null(rx.search("var r := s.rng.randi() & 1"), "a generator of the state's is no global")
	assert_true(_own_setting("splatter"))
	assert_false(_own_setting("extended_cpu"), "a match rule")
	assert_false(_own_setting("MATCH_RULES"), "a constant")
	assert_false(_own_setting("extended_play"), "a rule's function")


## Floats in the state the hash, the snapshot and the run-ahead's copy
## carry: none but the reviewed ones ([constant FLOAT_FIELDS]), whatever is
## added later.
const FLOAT_TYPES := [TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_RECT2, TYPE_TRANSFORM2D,
		TYPE_TRANSFORM3D, TYPE_BASIS, TYPE_QUATERNION, TYPE_PLANE, TYPE_AABB, TYPE_PROJECTION, TYPE_COLOR,
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY,
		TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY]
## class key ([method MwNetGraph.key_of]) -> its reviewed float fields.
## The crowd's life is hashed (its noise level reaches the sound driver):
## IEEE-exact operations only (MwCrowdLife.det_exp, no maths library), the
## same bits on every machine. The benches' is carried, never read by the game.
const FLOAT_FIELDS := {
	"MwCrowdLife": ["life", "lift", "wave_t", "wave_from", "wave_dir", "_quiet", "_wave_end"],
	"MwBenchLife": ["life"],
}


func test_carried_state_has_no_unreviewed_float_fields() -> void:
	var s := _played()
	var found: Array[String] = []
	var seen := {}
	_walk(s, found, seen)
	_walk(MwSession.new(1, 1), found, seen)
	assert_gt(seen.size(), 5, "the state's parts walked (%d)" % seen.size())
	for f in found:
		gut.p(f)
	assert_eq(found, [] as Array[String], "float fields in lockstep state (review, then list in FLOAT_FIELDS)")


## The rink hash's form holds no float but the reviewed fields'.
func test_the_rink_hash_holds_no_unreviewed_float() -> void:
	if not need_rom():
		return
	var out: Array[String] = []
	_floats(MwNetHash.rink_dict(_played()), "", out)
	var unreviewed: Array[String] = []
	for path in out:
		var field := path.get_file()
		var reviewed := false
		for key: String in FLOAT_FIELDS:
			reviewed = reviewed or field in (FLOAT_FIELDS[key] as Array)
		if not reviewed:
			unreviewed.append(path)
	assert_eq(unreviewed, [] as Array[String], "floats in the hashed form")


## A match state as an online match carries it: played 150 passes with its
## models (without the ROM: a bare state with them).
func _played() -> MwRinkState:
	var s: MwRinkState
	if rom.is_empty():
		s = MwRinkState.new()
	else:
		var rig := RinkRig.new()
		s = rig.make(rom, 3, 3, 7, 0, false, MwRinkAI.new())
		rig.enter(5)
		for i in 150:
			if rig.step() >= 0:
				break
	MwMatchModels.make(s, MwSession.new(1, 1))
	if rom.is_empty():
		s.control = MwRinkControl.new()
	return s


## The paths in [param v] (dictionaries and arrays all the way down) that
## hold a float-typed value, into [param out].
static func _floats(v: Variant, path: String, out: Array[String]) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			for k: Variant in v:
				_floats(v[k], "%s/%s" % [path, k], out)
		TYPE_ARRAY:
			for i in (v as Array).size():
				_floats(v[i], "%s/%d" % [path, i], out)
		_:
			if typeof(v) in FLOAT_TYPES:
				out.append(path)


## [param o]'s script variables (and the objects they hold, once each):
## the float-typed ones not reviewed into [param found]. A state's LOCAL
## fields (MwRinkState.PORT_FIELDS: a machine's own presentation, neither
## hashed nor carried) are left out.
func _walk(o: Object, found: Array[String], seen: Dictionary) -> void:
	if o == null or not o is RefCounted or o.get_script() == null or seen.has(o.get_instance_id()):
		return
	seen[o.get_instance_id()] = true
	var key := MwNetGraph.key_of(o.get_script())
	var local := MwRinkState.port_fields(MwRinkState.Port.LOCAL) if o is MwRinkState else PackedStringArray()
	for p in o.get_property_list():
		if not int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE or str(p["name"]) in local:
			continue
		var field := str(p["name"])
		var v: Variant = o.get(field)
		if (int(p["type"]) in FLOAT_TYPES or typeof(v) in FLOAT_TYPES) \
				and not field in (FLOAT_FIELDS.get(key, []) as Array):
			found.append("%s.%s" % [key, field])
		if v is Object:
			_walk(v, found, seen)
		elif v is Array:
			for x: Variant in v:
				if x is Object:
					_walk(x, found, seen)
		elif v is Dictionary:
			for x: Variant in (v as Dictionary).values():
				if x is Object:
					_walk(x, found, seen)


## True when [param setting] (read as [code]MwSettings.<setting>[/code]) is a
## machine's own setting: not a match rule, not a rule's function, not a
## constant.
static func _own_setting(setting: String) -> bool:
	if setting == setting.to_upper():
		return false
	return not setting in MwSettings.MATCH_RULES and not setting in RULE_FUNCTIONS and not setting.ends_with("_rule")


## True when [param code] of [param path] is a reviewed exception to [param rule].
static func _allowed(path: String, rule: String, code: String) -> bool:
	for a: Array in (ALLOWED.get(path, {}) as Dictionary).get(rule, []):
		if str(a[0]).is_empty() or code.contains(str(a[0])):
			return true
	return false


## A line's code: its comment cut, its strings emptied.
static func _code_of(line: String) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				i += 2
				continue
			if c == quote:
				quote = ""
				out += c
		elif c == "\"" or c == "'":
			quote = c
			out += c
		elif c == "#":
			break
		else:
			out += c
		i += 1
	return out


func _scope() -> PackedStringArray:
	var out := PackedStringArray(FILES)
	for d: String in DIRS:
		out.append_array(_scripts(d))
	return out


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
