extends GutTest
## Plan 40 (S1): MwRinkState.PORT_FIELDS is the one place the port's own
## fields of the rink's state are declared, and the comparison layer
## (MwSimDict), the online hash (MwNetHash) and the resync snapshot
## (MwNetSnapshot) all read it. A new script variable fails
## [method test_every_field_is_decided] until it is either listed in
## [constant ORIGINAL] (the original's RAM, or what stands for it) or
## declared in PORT_FIELDS.

## The original's fields of each class (the RAM they mirror, decoded), and
## MwSimDict.INTRINSIC's. Pinned: adding a field here is a statement that
## it is the original's.
const ORIGINAL := {
	"": ["phase", "subphase", "tick", "rng", "pads_held", "pads_new", "hold_bit", "hold_left", "pad_mode",
		"death_index", "clock", "clock_ref", "clock_rate", "clock_flags", "period", "clock_widget", "clock_text",
		"plane_b_cell", "scroll_b", "stadium_objects", "shark_osc", "replay", "replay_on", "penalty_tick",
		"box_clock", "pp_seconds", "pass_tick", "first_pass", "net_slack", "crowd_quiet", "goal_message",
		"goal_message_step", "faceoff_step", "crowd", "faceoff_spot", "ai_off", "fight_block", "crease_y",
		"scoring", "goal_points", "bribe", "special_actor", "jail_tick", "jail_count", "coop_toggle", "ref_flag",
		"pass_count", "drop_params", "be64", "player_params", "puck_params", "reserves", "penalties", "stadium",
		"projection", "camera", "camera_target", "teams", "puck", "nets", "lamps", "hazards", "objects", "faceoff",
		"penalty", "stoppage", "puck_rule", "impale", "referee", "plates", "phase_tick", "play_mode",
		"period_minutes", "period_row", "pause_pad", "pause_team", "pause_attr", "pause_offer", "goal_tick",
		"goal_net", "goal_net_frame", "faceoff_tick", "faceoff_text", "drop_plane", "drop", "speech_box",
		"text_box", "box_fill", "box_c3bc", "quote", "quote_ptr", "coach_name", "quote_value", "portrait",
		"speaker", "playoff_result", "goal_kind", "scorer", "stop_tick", "rule_team_b", "rule_clock", "rule_hold",
		"rule_spot", "penalty_step", "ref_attr", "playoffs"],
	"Actor": ["motion", "anim"],
	"Player": ["record", "present", "target_x", "target_y", "ai_x", "ai_y", "ai_zone", "bone_tick", "original",
		"victim", "init_roll", "x3d", "x3e", "x3f", "puck_dist", "puck_angle", "mate_dist", "mate_angle",
		"opp_dist", "opp_angle", "index", "slot", "position", "role", "think", "penalty", "weapon", "charges",
		"anim_id", "state", "substate", "attacker", "angle", "flags", "flags2", "team", "motion", "anim"],
	"Marker": ["x", "y", "plate", "number", "position", "health"],
	"Team": ["record", "flags4", "flags5", "health", "pads", "pad_held", "pad_new", "players", "x330", "arrows",
		"markers", "stats", "nearest", "score", "attr", "special", "x4a6", "mask", "formation", "x4a9"],
	"Puck": ["carrier", "take_tick", "owner_log", "x2e", "ring", "touches", "prev_x", "prev_y", "release_y",
		"receiver", "receiver_angle", "flags", "lock", "x3f", "motion", "anim"],
	"Net": ["style", "bottom", "motion", "anim"],
	"Hazard": ["x", "y", "x4", "kind", "flags"],
	"RinkObject": ["kind", "flags", "t24", "t26", "motion", "anim"],
	"Overlay": ["anim", "x", "y", "depth", "attr", "flags"],
	"Oscillator": ["start", "base", "amp", "rate", "phase"],
	"ReplayRing": ["base", "size", "callback", "write", "read", "used", "frames", "frame_start", "open",
		"playback", "pan", "ring_bytes", "side"],
	"TextBox": ["plane", "font", "x", "y", "w", "h", "spacing", "cursor_x", "cursor_y"],
	"Portrait": ["anim", "x0b", "data", "x10", "mode", "timer", "size", "handle", "voices", "x1e"],
}


static func _instances() -> Dictionary:
	return {"": MwRinkState.new(), "Actor": MwRinkState.Actor.new(), "Player": MwRinkState.Player.new(),
		"Marker": MwRinkState.Marker.new(), "Team": MwRinkState.Team.new(), "Puck": MwRinkState.Puck.new(),
		"Net": MwRinkState.Net.new(), "Hazard": MwRinkState.Hazard.new(),
		"RinkObject": MwRinkState.RinkObject.new(), "Overlay": MwRinkState.Overlay.new(),
		"Oscillator": MwRinkState.Oscillator.new(), "ReplayRing": MwRinkState.ReplayRing.new(),
		"TextBox": MwRinkState.TextBox.new(), "Portrait": MwRinkState.Portrait.new()}


static func _vars(o: Object) -> Array:
	var out := []
	for property in o.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(property["name"])
	return out


func test_every_field_is_decided() -> void:
	var inst := _instances()
	for cls: String in inst:
		for f: String in _vars(inst[cls]):
			var key := f if cls == "" else cls + "." + f
			var original: bool = f in ORIGINAL[cls]
			var port := MwRinkState.PORT_FIELDS.has(key)
			assert_true(original != port, "%s: the original's (ORIGINAL) or the port's (PORT_FIELDS), once" % key)
	# and nothing declared that is not there
	for key: String in MwRinkState.PORT_FIELDS:
		var parts := key.split(".")
		var cls := "" if parts.size() == 1 else parts[0]
		assert_true(inst.has(cls) and parts[-1] in _vars(inst[cls]), "%s is a field" % key)


func test_the_comparison_form_follows_the_declaration() -> void:
	var d := MwSimDict.to_dict(MwRinkState.new())
	for key: String in MwRinkState.PORT_FIELDS:
		if key.contains("."):
			continue
		var in_dict: bool = MwRinkState.PORT_FIELDS[key] == MwRinkState.Port.IN_DICT
		assert_eq(d.has(key), in_dict, key)
	for f in MwSimDict.INTRINSIC:
		assert_false(d.has(f), f)
	# the nested IN_DICT fields are in their objects' forms
	var s := MwRinkState.new()
	s.teams = [MwRinkState.Team.new()]
	s.teams[0].players = [MwRinkState.Player.new()]
	var t: Dictionary = MwSimDict.to_dict(s)["teams"][0]
	assert_true(t.has("port_pads") and t.has("port_turn"), "Team's port fields")
	assert_true(t["players"][0].has("pad"), "Player.pad")


func test_the_hash_takes_the_hashed_fields() -> void:
	var hashed := Array(MwRinkState.port_fields(MwRinkState.Port.HASHED))
	hashed.sort()
	var keyed: Array = MwNetHash.PORT_KEYS.keys()
	keyed.sort()
	assert_eq(keyed, hashed)
	var s := MwRinkState.new()
	s.control = MwRinkControl.new()
	s.crowd_life = MwCrowdLife.new(1)
	s.pace = PackedInt32Array([1, 2])
	var layers := MwNetHash.port_layers(s)
	var want: Array = MwNetHash.PORT_KEYS.values()
	want.sort()
	var got: Array = layers.keys()
	got.sort()
	assert_eq(got, want)


func test_the_snapshot_leaves_out_the_local_fields() -> void:
	var skip: Array = MwNetSnapshot.codec().skip["MwRinkState"]
	assert_eq(skip, Array(MwRinkState.port_fields(MwRinkState.Port.LOCAL)))
	assert_true("splatter" in skip)


## The control layer (a HASHED field) and its seats: what
## MwNetHash.port_layers encodes of each (by position there) and what it
## leaves out - this pass's menu verbs (given by the scene before the pass,
## each machine its own), the online table's set-up (fixed for the match:
## the START record carries it) and the state it reads. A new field fails
## until it is listed here and, if the game's course reads it, hashed.
const CONTROL_HASHED := ["seats", "owned", "extended", "captain_mode", "voted", "captains", "requests",
		"net_status", "kicks", "leaving"]
const CONTROL_UNHASHED := ["verbs", "online", "machines", "_s"]
const SEAT_HASHED := ["player", "team", "pad", "slot", "own", "out", "back", "last", "taps", "tap", "menu", "net"]


func test_the_control_layer_is_decided() -> void:
	var have := _vars(MwRinkControl.new())
	have.sort()
	var want := CONTROL_HASHED + CONTROL_UNHASHED
	want.sort()
	assert_eq(have, want, "MwRinkControl's fields: hashed (MwNetHash.port_layers) or not")
	var control := MwRinkControl.new()
	control.seats.append(MwRinkControl.Seat.new())
	var seat_vars := _vars(control.seats[0])
	seat_vars.sort()
	var seat_want := SEAT_HASHED.duplicate()
	seat_want.sort()
	assert_eq(seat_vars, seat_want, "a seat's fields are all hashed")
	var s := MwRinkState.new()
	s.control = control
	assert_eq((MwNetHash.port_layers(s)["control"] as Array).size(), CONTROL_HASHED.size(),
			"one entry each of the hashed fields")
	assert_eq((MwNetHash.port_layers(s)["control"][0][0] as Array).size(), SEAT_HASHED.size(),
			"one entry each of a seat's fields")
