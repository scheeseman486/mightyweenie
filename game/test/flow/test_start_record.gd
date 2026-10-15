extends "res://test/rom/rom_test_base.gd"
## Plan 35 work item 1 (docs/net.md): the start record - everything the
## game's course depends on besides the inputs - and the port's random
## streams, all derived from one session seed; the match rules and the
## player table it carries.
## Short names: a the MwSession under test, b the MwSession under test, t the MwSession under test.

var _rules := {}


func before_each() -> void:
	_rules = MwSettings.match_rules()


func after_each() -> void:
	MwSettings.own_match_rules()
	MwSettings.use_match_rules(_rules)
	MwSettings.own_match_rules()


## A session with a bit of everything: an extended set-up's players, owners,
## captains, line-ups, someone out, a playoff run, port streams used.
func _busy_session() -> MwSession:
	var session := MwSession.new(0x1234, 0x5678)
	var humans := MwHumans.new()
	for p in [1, 3, 5]:
		humans.set_team(p, 0)
	for p in [2, 4]:
		humans.set_team(p, 1)
	humans.positions = {5: 0, 1: 2, 3: 1}
	humans.captains = [3, 2]
	humans.lineups = [PackedInt32Array([0, 1, 2, 3, 4, 5]), PackedInt32Array()]
	humans.out = {4: true}
	session.humans = humans
	humans.apply_to(session.setup)
	session.setup.play_mode = 1
	session.playoffs.start(session.setup, session.rng)
	session.local_mode = "playoffs"
	session.run_started = true
	session.run_games = 2
	session.port_stream(MwSession.STREAM_CROWD).next_state()
	session.port_seed(MwSession.STREAM_OPENING)
	session.layouts = {3: "GENESIS"}
	return session


func test_one_seed_makes_every_stream() -> void:
	var a := MwSession.new(0, 0, 0xCAFE)
	var b := MwSession.new(0, 0, 0xCAFE)
	assert_eq(a.rng.state, b.rng.state, "the original's main stream: the session's hardware seed")
	assert_eq(a.rng_aux.state, b.rng_aux.state, "and its second")
	for stream_name in [MwSession.STREAM_CROWD, MwSession.STREAM_OPENING, MwSession.STREAM_CAPTAINS]:
		assert_eq(a.port_seed(stream_name), b.port_seed(stream_name), stream_name + ": the same from the same seed")
	assert_ne(a.port_seed(MwSession.STREAM_CROWD), a.port_seed(MwSession.STREAM_CROWD), "a new seed each match")
	assert_ne(MwSession.stream_seed(1, "crowd"), MwSession.stream_seed(1, "opening"), "each name its own stream")
	assert_ne(MwSession.stream_seed(1, "crowd"), MwSession.stream_seed(2, "crowd"), "each seed its own")
	var session := MwSession.new(0, 0, 0xBEEF)
	assert_ne(a.rng.state, session.rng.state, "another seed, another game")


func test_given_seeds_stay_the_originals() -> void:
	var session := MwSession.new(77, 88)
	assert_eq(session.rng.state, 77, "a test's seed is the main stream's (no warm-up), as before")
	assert_eq(session.rng_aux.state, 88)
	assert_eq(MwSession.new(77, 88).seed, session.seed, "and the session seed follows from them")
	session.reseed_aux()
	assert_eq(session.rng_aux.state, 88, "fixed seeds: the main menu doesn't reseed")


func test_the_hardware_seeds_come_from_the_session() -> void:
	var a := MwSession.new(0, 0, 99)
	var b := MwSession.new(0, 0, 99)
	a.reseed_aux()
	b.reseed_aux()
	assert_eq(a.rng_aux.state, b.rng_aux.state, "the main menu's reseed: the same 'HV counter'")
	assert_eq(a.playoffs.check(0, 0), b.playoffs.check(0, 0), "a password whose check seed is 0")


func test_the_record_round_trips() -> void:
	if not need_rom():
		return
	var session := _busy_session()
	var r := session.to_record(1, 500)
	var t := MwSession.from_record(r)
	assert_eq(t.to_record(1, 500), r, "the record of the session made from it")
	assert_eq(MwNetHash.session(t), MwNetHash.session(session), "the same session hash")
	assert_eq(MwSession.record_screen(r), 1)
	assert_eq(MwSession.record_tick(r), 500)
	assert_eq(t.rng.state, session.rng.state)
	assert_eq(t.playoffs.to_bytes(), session.playoffs.to_bytes(), "the playoffs' 21 bytes")
	assert_eq(t.setup.to_bytes(), session.setup.to_bytes(), "the setup's 10 bytes")
	assert_false(r.has("extended") or r.has("lineups"), "the players carry them (plan 40, S13)")
	assert_eq(MwSelection.for_the_rink(t, t.setup.copy()).extended, session.humans.match_pads(),
			"the extended pads, from the players")
	assert_eq(MwSelection.chosen_lineups(t), MwSelection.chosen_lineups(session), "the line-ups, from the players")
	assert_eq(t.humans.captains, [3, 2])
	assert_eq(t.humans.positions, {1: 2, 3: 1, 5: 0})
	assert_true(t.humans.out.has(4), "who is out")
	assert_eq(t.layout_of(3), "GENESIS", "the player table's layouts")
	# the streams go on as they would have
	for stream_name in [MwSession.STREAM_CROWD, MwSession.STREAM_OPENING, MwSession.STREAM_CAPTAINS,
			MwSession.STREAM_HARDWARE]:
		assert_eq(t.port_seed(stream_name), session.port_seed(stream_name), stream_name + " goes on the same")
	assert_eq(t.rng.range_value(0, 99), session.rng.range_value(0, 99))


## Plan 40 (S4): every field of the session is in one of MwSession's lists -
## the record's, a machine's own, the screens' keepsakes - and a reset from
## a record sets the record's, keeps a machine's own and clears the
## keepsakes; the resync snapshot leaves a machine's own alone.
func test_every_session_field_is_decided() -> void:
	var have := []
	for property in MwSession.new(1, 1).get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			have.append(property["name"])
	var lists := MwSession.RECORD_FIELDS + MwSession.OWN_FIELDS + MwSession.KEEPSAKES
	for f: String in have:
		assert_eq(lists.count(f), 1, "%s: in one list" % f)
	for f: String in lists:
		assert_true(f in have, "%s is a field" % f)
	assert_eq(MwNetSnapshot.SESSION_OWN, MwSession.OWN_FIELDS)
	if not need_rom():
		return
	var session := _busy_session()
	var r := session.to_record(1, 500)
	var t := MwSession.new(9, 9)
	t.view = MwRinkViews.FOLLOW
	t.machine = 2
	t.screens["x"] = 1
	t.reset_from_record(r)
	assert_eq(t.to_record(1, 500), r, "the record's fields")
	assert_eq([t.view, t.machine], [MwRinkViews.FOLLOW, 2], "a machine's own kept")
	assert_eq(t.screens, {}, "the keepsakes cleared")


## Plan 40 (S6, the survey's B7): a host's start record of the wrong shape
## reads as defaults, never a script error (GUT fails a test on any): every
## key, and the players' and online table's, given each kind of junk.
func test_a_malformed_record_reads_without_errors() -> void:
	var good := MwSession.new(3, 4).to_record(1, 0)
	good["players"]["humans"] = {"a": [1], "b": [2], "positions": {"1": 0}, "captains": [1, 2],
			"lineups": [[0, 1, 2, 3, 4, 5], []]}
	good["online"] = {"players": [1, 2], "machines": {"1": 0, "2": 1}}
	var junk := [null, "x", 1.5, [], {}, [1, "a", null, [2]], {"k": [], "1": "y"}, -7, true]
	var paths := []
	for k in good:
		paths.append([k])
	for k in good["players"]:
		paths.append(["players", k])
	for k in good["players"]["humans"]:
		paths.append(["players", "humans", k])
	for k in good["online"]:
		paths.append(["online", k])
	var read := 0
	for path: Array in paths:
		for j in junk:
			var r: Dictionary = good.duplicate(true)
			var at: Dictionary = r
			for i in path.size() - 1:
				at = at[path[i]]
			at[path[-1]] = j
			if MwSession.from_record(r) != null:
				read += 1
	assert_eq(read, paths.size() * junk.size(), "every one read")


func test_the_record_survives_json() -> void:
	if not need_rom():
		return
	var session := _busy_session()
	var r := session.to_record(3, 7)
	var back: Variant = JSON.parse_string(JSON.stringify(r))
	assert_true(back is Dictionary)
	var t := MwSession.from_record(back)
	assert_eq(MwNetHash.session(t), MwNetHash.session(session), "numbers as JSON's floats: the same session")
	assert_eq(MwSession.record_screen(back), 3)


func test_match_rules_and_local_settings() -> void:
	for k in MwSettings.MATCH_RULES:
		assert_false(k in MwSettings.LOCAL, k + ": one class")
	assert_eq(MwSettings.match_rules().keys(), Array(MwSettings.MATCH_RULES), "every rule in the record")
	var own := MwSettings.match_rules()
	var host := own.duplicate()
	host["enhance_audio"] = not own["enhance_audio"]
	host["replay_length"] = MwSettings.REPLAYS[1]
	host["opening_view"] = MwRinkViews.FOLLOW
	host["idle_attract"] = false
	MwSettings.use_match_rules(host)
	assert_eq(MwSettings.match_rules(), host, "the host's rules in force")
	assert_eq(MwAudio.free_effects, host["enhance_audio"], "ENHANCE AUDIO reaches the driver's switches")
	assert_eq(MwCrowdLife.drives_sound, host["enhance_audio"])
	assert_eq(MwAudio.organ_pool, host["enhance_audio"], "and the organ pool (plan 39: its tunes' lengths)")
	assert_false(MwAttract.idle_out(MwAttract.IDLE_TICKS * 10), "no idle timeout online")
	assert_eq(MwSettings.opening_view(), MwRinkViews.FOLLOW, "the opening's flow: the host's camera")
	assert_true(MwSettings.match_rules_in_force())
	MwSettings.own_match_rules()
	assert_eq(MwSettings.match_rules(), own, "this machine's own back")
	assert_true(MwAttract.idle_out(MwAttract.IDLE_TICKS))
	assert_false(MwSettings.match_rules_in_force())


func test_saving_keeps_the_players_own_settings() -> void:
	var was := MwSettings.path
	MwSettings.path = "user://test_settings_rules.cfg"
	var own := MwSettings.replay_length
	var host := MwSettings.match_rules()
	host["replay_length"] = MwSettings.REPLAYS[1] if own == MwSettings.REPLAYS[0] else MwSettings.REPLAYS[0]
	MwSettings.use_match_rules(host)
	MwSettings.save()
	var cfg := ConfigFile.new()
	cfg.load(MwSettings.path)
	assert_eq(str(cfg.get_value("game", "replay_length", "")), own, "the host's rule isn't saved as the player's")
	MwSettings.own_match_rules()
	MwSettings.path = was


func test_a_records_rules_are_the_hosts() -> void:
	var session := MwSession.new(1, 1)
	var r := session.to_record()
	assert_eq(r["rules"], MwSettings.match_rules(), "a local session: this machine's rules")
	r["rules"]["front_menu"] = false
	var t := MwSession.from_record(r)
	assert_eq(t.rules["front_menu"], false, "a record's rules kept in its session")
	assert_true(MwSettings.front_menu, "reading a record doesn't touch this machine's settings")
	assert_eq(t.to_record()["rules"], r["rules"], "and passed on")


func test_the_captain_votes_draw_from_the_session_seed() -> void:
	var draws := []
	for k in 3:
		var session := MwSession.new(0, 0, 0xD1CE if k < 2 else 0xD1CF)
		var picks := []
		for i in 8:
			var vote := MwCaptainVote.new(0, [1, 2], [1, 2])
			for round_number in 2:
				vote.vote(1, 1)
				vote.vote(2, 2)
				vote.count(MwCaptainVote.stream(session))
			assert_true(vote.drawn, "a second tie: drawn")
			picks.append(vote.winner)
		draws.append(picks)
	assert_eq(draws[0], draws[1], "the same session seed: the same captains on every machine")
	assert_ne(draws[0], draws[2], "another seed draws otherwise")
	# a session made from a record mid-way draws on as the first would
	var a := MwSession.new(0, 0, 0xD1CE)
	MwCaptainVote.stream(a).next_state()
	var b := MwSession.from_record(a.to_record())
	assert_eq(MwCaptainVote.stream(b).next_state(), MwCaptainVote.stream(a).next_state(),
			"the draw's stream is in the record")
	assert_eq(a.rng.state, b.rng.state, "and never the original's streams")
