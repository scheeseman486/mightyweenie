extends "res://test/net/net_test_base.gd"
## Plan 38 with plan 35: custom teams online. The host's custom teams travel
## in the start record (each team's JSON, MwCustomTeams.record_teams; START
## in chunks when the record outgrows one message - protocol version 4) and
## in every resync snapshot (the session's custom_teams); every machine
## plays the match with them in use (MwCustomTeams.use_teams: its own bank
## put aside, never written) and gets its own bank back when the match is
## over for it. Here: the carried form's round trip, its limits and
## fuzzing (the teams come from another machine); START's chunks over the
## loopback, a record whose teams aren't teams refused; a match of three
## machines through the menus where only the host has the teams (a client
## has another team of its own under the same id) - every hash the host's,
## every machine's bank its own again afterwards, no file written; a fresh
## process rejoining a match of a custom team. (A replay of a record with
## custom teams on a machine without them: test/screens/test_net_proof.gd.)
## Short names: r the MwSession under test.

const Machines := preload("res://test/net/net_machines.gd")
const Bots := preload("res://test/support/bots.gd")
const TEAMS_DIR := "user://test_net_custom/teams"

var _teams_dir := ""
var _rom := PackedByteArray()


func before_all() -> void:
	super.before_all()
	_teams_dir = MwCustomTeams.dir
	MwCustomTeams.dir = TEAMS_DIR                  # the bank's files: none may appear but the test's own
	MwRom.use(null)
	if MwRom.available():
		_rom = MwRom.archive().bytes()


func after_all() -> void:
	MwCustomTeams.clear()
	_clear_teams_dir()
	MwCustomTeams.dir = _teams_dir
	MwSettings.own_match_rules()
	super.after_all()


func after_each() -> void:
	MwCustomTeams.clear()
	_clear_teams_dir()


func _clear_teams_dir() -> void:
	for f in _team_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEAMS_DIR.path_join(f)))


func _team_files() -> PackedStringArray:
	var d := DirAccess.open(TEAMS_DIR)
	return d.get_files() if d != null else PackedStringArray()


## A changed copy of original team [param team]: its name, [param players]
## players of its own (faster), its rink's gravity and a pit.
func _team(team: int, name_: String, players := 3, gravity := -16) -> MwCustomTeam:
	var custom := MwCustomTeam.from_original(_rom, team)
	custom.city = "TESTVILLE"
	custom.name = name_
	custom.rink.gravity = gravity
	custom.rink.hazards.append({"kind": "pit", "x": -120, "y": 180, "mirror": false})
	for slot in players:
		var player := MwCustomPlayer.from_record(_rom, MwTeams.player(_rom, team, slot))
		player.ratings["speed"] = 10
		player.name = "SPEEDY NO%d" % slot
		custom.players.append(player)
		custom.roster[slot] = {"player": custom.players.size() - 1}
	custom.validate(_rom)
	return custom


static func _bank(list: Array) -> void:
	MwCustomTeams.clear()
	for team: MwCustomTeam in list:
		MwCustomTeams.teams.append(team)
	MwCustomTeams.rebuild()


# --- the carried form ---------------------------------------------------------------------------------

## Every original team's copy and a team with 24 players of its own come
## back from their carried form (through the record's bytes) as they went:
## the same JSON, the same bytes past the ROM.
func test_carried_teams_round_trip() -> void:
	if not need_rom():
		return
	for t in MwTeams.COUNT:
		var team := MwCustomTeam.from_original(_rom, t)
		_bank([team])
		var carried := MwCustomTeams.record_teams(null)
		var back: Variant = MwCustomTeams.parse_carried(bytes_to_var(var_to_bytes(carried)))
		assert_true(back is Array and (back as Array).size() == 1, "team %d's copy read back" % t)
		var want := team.to_dict()
		want["stats"] = null
		assert_eq((back[0] as MwCustomTeam).to_dict(), want, "team %d's copy: the same JSON" % t)
		assert_eq(MwCustomOverlay.build(_rom, back)["bytes"],
				MwCustomOverlay.build(_rom, [team] as Array[MwCustomTeam])["bytes"],
				"team %d's copy: the same bytes past the ROM" % t)
	var heavy := _team(14, "HEAVIES", 24, -30)
	heavy.stats = {"games": 12}
	_bank([_team(9, "TESTERS"), heavy])
	var c2 := MwCustomTeams.record_teams(null)
	assert_eq((c2["teams"] as Array).size(), 2)
	assert_eq(c2["teams"][1]["stats"], null, "stats stay home (the game never reads them)")
	assert_eq(MwCustomTeams.record_teams(null, 1)["teams"].size(), 1, "a limit")
	assert_eq(MwCustomTeams.record_teams(null, 0), {}, "none")
	var back2: Array = MwCustomTeams.parse_carried(c2)
	assert_eq(MwCustomOverlay.build(_rom, back2)["bytes"], MwRom.overlay(), "the whole view as the bank's")
	# in the start record, through START's bytes
	var world := World.new(5)
	var r := MwNetMatch.host_record(MwSession.new(5, 6), world.host.lobby)
	assert_eq((r["custom_teams"]["teams"] as Array).size(), 2, "the host's teams in its record")
	var b := MwNetMatch.encode_record(r)
	gut.p("a record with 2 custom teams (one of 24 players): %d bytes (%d START chunks), %d raw" % [b.size(),
			MwNetProtocol.start_messages(1, 0, b).size(), var_to_bytes(r).size()])
	assert_gt(b.size(), MwNetProtocol.RECORD_CHUNK, "more than one START")
	var d := MwNetMatch.decode_record(b)
	assert_eq(MwNetHash.digest(d), MwNetHash.digest(r), "the same record")
	assert_eq(MwSession.from_record(d).custom_teams["teams"], r["custom_teams"]["teams"], "the session holds them")


## The bank put aside while a game's teams are in use, and back after: the
## editor's working copy too; nothing written, saved or deleted meanwhile; a
## bank loaded meanwhile is the one put aside.
func test_use_teams_puts_the_bank_aside() -> void:
	if not need_rom():
		return
	var mine := _team(9, "MINE")
	var other := _team(2, "THEIRS", 0, -40)
	_bank([mine])
	var team := MwCustomTeam.from_original(_rom, 5)
	MwCustomTeams.edit(team)
	var own_view := MwRom.overlay()
	_bank([other])
	var carried := MwCustomTeams.record_teams(null)
	var their_view := MwRom.overlay()
	_bank([mine])
	MwCustomTeams.edit(team)
	assert_true(MwCustomTeams.use_teams(carried))
	assert_true(MwCustomTeams.teams_in_use())
	assert_eq(MwCustomTeams.count(), 1)
	assert_eq(MwCustomTeams.teams[0].name, "THEIRS", "the game's team under id 23")
	assert_ne(MwCustomTeams.teams[0], other, "made from the carried JSON")
	assert_eq(MwCustomTeams.editing, null, "no working copy in the game")
	assert_eq(MwRom.overlay(), their_view, "the game reads the carried team")
	# nothing of it is written
	assert_eq(MwCustomTeams.save(MwCustomTeams.teams[0]), -1, "no SAVE TEAM")
	MwCustomTeams.write(MwCustomTeams.teams[0])
	MwCustomTeams.delete(MwCustomTeams.teams[0])
	assert_eq(MwCustomTeams.count(), 1, "no delete")
	assert_eq(_team_files().size(), 0, "no file written")
	assert_true(MwCustomTeams.use_teams(carried), "in use again: the bank stays put aside")
	assert_false(MwCustomTeams.use_teams({"teams": "nonsense"}), "garbage isn't taken")
	assert_eq(MwCustomTeams.teams[0].name, "THEIRS", "nothing changed")
	MwCustomTeams.own_teams()
	assert_false(MwCustomTeams.teams_in_use())
	assert_eq(MwCustomTeams.teams, [mine] as Array[MwCustomTeam], "the machine's own bank back")
	assert_eq(MwCustomTeams.editing, team, "and the working copy")
	assert_eq(MwRom.overlay(), own_view)
	MwCustomTeams.own_teams()
	assert_eq(MwCustomTeams.teams, [mine] as Array[MwCustomTeam], "twice: nothing more")
	# none: the ROM alone
	MwCustomTeams.stop_editing()
	assert_true(MwCustomTeams.use_teams({}))
	assert_eq(MwRom.data().size(), _rom.size(), "no team: the ROM alone")
	assert_eq(MwTeams.count(), MwTeams.COUNT)
	MwCustomTeams.own_teams()
	assert_gt(MwRom.data().size(), _rom.size())
	# a bank loaded while a game's teams are in use is the one put aside
	assert_eq(MwCustomTeams.save(mine), 23)
	assert_eq(_team_files().size(), 1)
	assert_true(MwCustomTeams.use_teams(carried))
	MwCustomTeams.load_bank()
	assert_eq(MwCustomTeams.teams[0].name, "THEIRS", "still the game's")
	MwCustomTeams.own_teams()
	assert_eq(MwCustomTeams.count(), 1)
	assert_eq(MwCustomTeams.teams[0].name, "MINE", "the bank loaded meanwhile")


## Carried teams come from another machine: anything but plain data within
## the bounds is refused before anything reads it.
func test_carried_teams_limits() -> void:
	for bad: Variant in [null, [], "teams", 7, {"teams": "x"}, {"teams": [1]}, {"teams": [[]]},
			{"teams": [{}], "playoff": "a"}, {"teams": [{}], "playoff": []}]:
		assert_eq(MwCustomTeams.parse_carried(bad), null, "refused: %s" % str(bad))
	assert_eq(MwCustomTeams.parse_carried({}), [] as Array[MwCustomTeam], "{}: no teams")
	var many := []
	for i in MwCustomTeams.CARRY_MAX + 1:
		many.append({})
	assert_eq(MwCustomTeams.parse_carried({"teams": many}), null, "more teams than ids")
	var nest: Variant = 1
	for i in MwPlain.DEPTH + 1:
		nest = [nest]
	var wide := []
	wide.resize(MwPlain.ITEMS + 1)
	var keys := {}
	for i in MwPlain.KEYS + 1:
		keys["k%d" % i] = i
	var budget := []
	for i in 100:
		var player := {}
		for k in 60:
			player["f%d" % k] = [k, k]
		budget.append(player)
	var typed: Array[int] = [1, 2]
	for v: Variant in ["x".repeat(MwPlain.STRING + 1), nest, wide, keys, {"players": budget},
			{3: 1}, PackedByteArray([1]), PackedInt32Array([1]), Vector2(1, 2), Color.RED, NAN, INF, -INF,
			typed, RefCounted.new(), Callable(), StringName("x"), NodePath("x")]:
		var team := {"city": "X"}
		team["name"] = v
		assert_false(MwPlain.plain_ok(team), "not plain or past the bounds: %s" % type_string(typeof(v)))
		assert_eq(MwCustomTeams.parse_carried({"teams": [team]}), null)
	assert_true(MwPlain.plain_ok({"a": [1, 2.5, "x", null, true, {"b": []}]}), "plain data")
	if not need_rom():
		return
	var plain: Variant = MwCustomTeams.parse_carried({"teams": [{}], "playoff": 0})
	assert_eq((plain as Array).size(), 1, "an empty team: a valid default one")
	# a record whose teams aren't teams isn't a record
	var r := MwSession.new(3, 4).to_record()
	r["custom_teams"] = {"teams": [{"name": PackedByteArray([1])}], "playoff": -1}
	assert_eq(MwNetMatch.decode_record(MwNetMatch.encode_record(r)), {}, "refused with its teams")
	r["custom_teams"] = {"teams": [{"name": "OK"}], "playoff": -1}
	assert_false(MwNetMatch.decode_record(MwNetMatch.encode_record(r)).is_empty(), "plain teams: a record")


## Mutated carried teams - any value swapped for any other kind, at any
## depth - never crash the reader: refused, or read as valid teams (the
## same team again through its own JSON). Random and mutated records never
## crash decode_record.
func test_fuzzed_carried_teams_never_crash() -> void:
	if not need_rom():
		return
	_bank([_team(9, "TESTERS", 6, -20)])
	var base := MwCustomTeams.record_teams(null)
	var rng := RandomNumberGenerator.new()
	rng.seed = 38
	var junk: Array = [null, true, false, 0, -1, 1 << 40, -(1 << 62), 3.75, -2.5, NAN, INF, "", "ZZZZ", "0E64",
			"auto", "x".repeat(2000), [], [1, 2, 3], [[[]]], {}, {"player": 3}, {"team": 99, "slot": -4},
			PackedByteArray([1, 2]), Vector2i(3, 4), "pit", "battle", "waste_ref", 1e30]
	var accepted := 0
	for i in 600:
		var d: Dictionary = base.duplicate(true)
		for k in rng.randi_range(1, 6):
			_mutate(d["teams"][0], rng, junk, 0)
		var got: Variant = MwCustomTeams.parse_carried(d)
		if got == null:
			continue
		accepted += 1
		for team: MwCustomTeam in got:
			var j := team.to_dict()
			assert_true(MwPlain.plain_ok(j), "a read team's JSON is plain")
			if MwCustomTeam.from_dict(_rom, j).to_dict() != j:
				fail_test("mutation %d: a read team isn't stable through its JSON" % i)
				return
	gut.p("fuzz: %d of 600 mutated carried teams read as valid teams, the rest refused" % accepted)
	assert_gt(accepted, 100, "mutations reach the team reader")
	assert_eq(get_errors().size(), 0, "not even an engine complaint reading them")
	var rec := MwNetMatch.encode_record(MwNetMatch.host_record(MwSession.new(7, 8), World.new(9).host.lobby))
	for i in 120:
		var b := PackedByteArray()
		if i % 6 != 0:
			for j in rng.randi_range(0, 64):
				b.append(rng.randi_range(0, 255))
		else:
			b = rec.duplicate()
			for j in rng.randi_range(1, 6):
				b[rng.randi_range(0, b.size() - 1)] = rng.randi_range(0, 255)
		MwNetMatch.decode_record(b)
	for e in get_errors():
		e.handled = true                       # the engine reports the deflate streams it couldn't unpack
	pass_test("random and mutated records decoded without a crash")


## One random change somewhere in [param v] (a dictionary or an array).
static func _mutate(v: Variant, rng: RandomNumberGenerator, junk: Array, depth: int) -> void:
	var keys: Array = (v as Dictionary).keys() if v is Dictionary else range((v as Array).size())
	if keys.is_empty():
		return
	var k: Variant = keys[rng.randi_range(0, keys.size() - 1)]
	var child: Variant = v[k]
	if (child is Dictionary or child is Array) and depth < 5 and rng.randf() < 0.6:
		_mutate(child, rng, junk, depth + 1)
		return
	if rng.randf() < 0.1 and v is Dictionary:
		(v as Dictionary).erase(k)
		return
	v[k] = junk[rng.randi_range(0, junk.size() - 1)]


# --- START in chunks -------------------------------------------------------------------------------

## A start record of several chunks over the loopback at 20 % loss: the
## client's START is the record whole, once; one over the cap isn't sent.
## A record whose custom teams aren't teams drops the host (as garbage).
func test_start_record_in_chunks() -> void:
	var world := World.new(11, "", {"loss": 0.2, "delay": 60, "jitter": 20, "duplicate": 0.05, "reorder": 0.1})
	var client := world.join("")
	assert_true(world.run_until(func() -> bool: return client.state == MwNetClient.State.LOBBY))
	var got := []
	client.started.connect(func(id: int, first: int, rec: PackedByteArray) -> void: got.append([id, first, rec]))
	assert_eq(world.host.start_match(MwNetProtocol.random_bytes(MwNetProtocol.MAX_RECORD + 1)), 0, "over the cap")
	var record := MwNetProtocol.random_bytes(MwNetProtocol.RECORD_CHUNK * 6 + 77)
	var match_id := world.host.start_match(record)
	assert_ne(match_id, 0)
	for i in 120:
		world.host.step()
		world.run(17)
	assert_eq(got, [[match_id, 0, record]], "the record whole, once")
	assert_eq(client.state, MwNetClient.State.RUNNING)
	assert_true(client.stream.confirmed > 60, "the stream taken meanwhile (%d)" % client.stream.confirmed)
	world.host.end_match()
	assert_true(world.run_until(func() -> bool: return client.state == MwNetClient.State.LOBBY))
	# garbage teams in the next record: the client drops the host
	var r := MwSession.new(3, 4).to_record()
	r["custom_teams"] = {"teams": [{"name": Vector2(1, 2)}], "playoff": -1}
	var svc := Machines.Service.new()
	svc.client = client
	var made := []
	client.started.connect(func(mid: int, first: int, rec: PackedByteArray) -> void:
		made.append(MwNetMatch.start_client(MwSession.new(1, 1), null, svc, mid, first, rec)))
	assert_ne(world.host.start_match(MwNetMatch.encode_record(r)), 0)
	assert_true(world.run_until(func() -> bool: return client.state == MwNetClient.State.DONE), "the host dropped")
	assert_eq(made, [null], "no match from it")
	assert_eq(client.fail, MwNetClient.Fail.PROTOCOL, "as for any garbage")
	assert_true(MwNetRejoin.read().is_empty(), "its key let go")


# --- matches ------------------------------------------------------------------------------------------

## Three machines - the host P1 (three custom teams in its bank), a client P2
## with another team of its own under id 23, a client P3 with none - through
## the menus: the game options show the host's teams on every machine (the
## host's setup: team A its first, at its rink), the controller selection,
## character selection with the vote, the matchup, the rink. Every hash the host's; the match over (the host leaves),
## every machine's own bank is back, nothing written.
func test_the_hosts_teams_through_the_menus() -> void:
	if not need_rom():
		return
	var mine: Array = [_team(9, "TESTERS", 3, -40), MwCustomTeam.from_original(_rom, 2), _team(14, "HEAVIES", 24, -30)]
	var theirs := _team(4, "OTHERS", 0, -6)
	MwCustomTeams.clear()
	var w := Machines.new(self, 38, {}, [1, 1])
	var h := w.machines[0]
	h.set_bank(mine)
	w.machines[1].set_bank([theirs])
	var teams := {1: 0, 2: 1, 3: 1}
	for m in w.machines:
		m.bot.expected = teams.size()
		for p in m.bot.players:
			m.bot.teams[p] = teams[p]
			m.bot.game_bots[p] = Bots.GameBot.new(p, 38)
	h.session.setup.team_a = 23
	h.session.setup.team_b = 7
	h.session.setup.stadium = 23
	h.bot.quiet = true                             # the host's P1 waits on the game options a moment
	w.start()
	assert_not_null(h.net_match, "START GAME")
	w.run(30)
	var host_view := h.bank()["overlay"] as PackedByteArray
	for m in w.machines:
		assert_not_null(m.net_match, "%s: its match" % m.name)
		assert_eq(m.router.current_id(), 1, "%s: the game options" % m.name)
		m.enter()
		assert_eq(MwTeams.count(), MwTeams.COUNT + 3, "%s: the host's three teams in the rows" % m.name)
		assert_true(MwCustomTeams.teams_in_use())
		assert_eq(MwCustomTeams.teams[0].name, "TESTERS", "%s: the host's team 23" % m.name)
		assert_eq(MwRom.overlay(), host_view, "%s: the bytes the host reads" % m.name)
		assert_eq(m.session.setup.team_a, 23, "%s: the host's pick" % m.name)
		m.leave()
	gut.p("START: %s" % str(w.host.log_lines.slice(-3)))
	h.bot.quiet = false
	var on_rink := func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool: return m.router.current_id() in [4, 5, 6])
	assert_true(w.run_until(on_rink, 6000), "every machine on the rink (%s)" % str(w.machines.map(
			func(m: Machines.Machine) -> int: return m.router.current_id())))
	w.run(400)
	var c := w.compare_hashes()
	assert_true(c["ok"], "every hash the host's - %s" % c["why"])
	assert_gt(int(c["compared"]), 200, "hashes compared (%d)" % c["compared"])
	for m in w.machines:
		var state := m.rink()
		m.enter()
		assert_eq(MwTeams.id_of(state.teams[0].record), 23, "%s: team A the host's custom team" % m.name)
		var nm := MwGfx.rom_string(MwRom.data(), MwTeams.name(MwRom.data(), 23)).get_string_from_ascii()
		assert_eq(nm, "TESTERS", "%s: its name read from the view" % m.name)
		assert_eq(state.stadium, 23, "%s: the host's custom rink" % m.name)
		m.leave()
		if m.id != 0:
			assert_eq(m.net_match.mismatches.size(), 0, "%s: no mismatch" % m.name)
	gut.p("custom teams online: %d hashes compared" % c["compared"])
	# the host leaves: every machine's match over, its own bank back
	h.enter()
	h.net_match.leave()
	h.leave()
	assert_true(w.run_until(func() -> bool: return w.machines.slice(1).all(func(m: Machines.Machine) -> bool:
			return m.ended >= 0), 600), "the clients' matches end")
	assert_eq(w.machines[1].ended, MwNetMatch.End.HOST_LEFT)
	var hb := h.bank()
	assert_false(bool(hb["in_use"]))
	assert_eq(hb["teams"], mine, "the host's own bank")
	var b1 := w.machines[1].bank()
	assert_false(bool(b1["in_use"]))
	assert_eq(b1["teams"], [theirs], "client 1's own team back")
	var b2 := w.machines[2].bank()
	assert_eq(b2["teams"], [], "client 2: none")
	assert_eq((b2["overlay"] as PackedByteArray).size(), 0, "the ROM alone again")
	assert_eq(_team_files().size(), 0, "no team file written anywhere")
	w.free_all()


## A start record from the matchup: the host's session [param from]'s
## setup (its custom teams carried), [param teams] (number -> team) on the
## teams, [param captains].
static func _matchup_record(w: Machines, from: MwSession, teams: Dictionary, captains: Array) -> Dictionary:
	var h := w.machines[0]
	h.enter()
	var session := MwSession.from_record(MwNetMatch.host_record(from, w.host.lobby))
	for p: int in teams:
		session.humans.set_team(p, int(teams[p]))
	session.humans.captains = captains.duplicate()
	session.humans.apply_to(session.setup)
	session.pad_map = session.humans.pad_players(MwRom.data())
	var r := session.to_record(3, 0)
	h.leave()
	return r


## A match of the host's custom team at its rink (5 % loss): the client's
## process dies on the matchup and a fresh one - its own bank, another team
## under id 23 - rejoins with its key, waits, and is taken up from the
## host's snapshot at the faceoff: the host's teams in use (they came with
## the snapshot), every hash the host's. The host leaving gives it its own
## bank back.
func test_a_rejoin_takes_the_hosts_teams_from_the_snapshot() -> void:
	if not need_rom():
		return
	var mine := _team(9, "TESTERS", 3, -40)
	var theirs := _team(4, "OTHERS", 0, -6)
	MwCustomTeams.clear()
	var w := Machines.new(self, 39, {"loss": 0.05, "delay": 40, "jitter": 20, "duplicate": 0.02, "reorder": 0.05}, [1])
	var h := w.machines[0]
	h.set_bank([mine])
	w.machines[1].set_bank([theirs])
	for m in w.machines:
		for p in m.bot.players:
			m.bot.game_bots[p] = Bots.GameBot.new(p, 39)
	var from := MwSession.new(11, 12)
	from.setup.team_a = 23
	from.setup.team_b = 6
	from.setup.stadium = 23
	w.start(_matchup_record(w, from, {1: 0, 2: 1}, [1, 2]))
	var on_matchup := func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool:
			return m.net_match != null and m.router.current_id() == 3)
	assert_true(w.run_until(on_matchup, 600), "on the matchup")
	assert_true(w.machines[1].bank()["in_use"], "the client plays the host's teams")
	h.bot.quiet = true
	w.drop(1)
	w.machines[1].frozen = true                # the process is gone
	w.run(20)
	var back := w.rejoin(1, true)
	back.set_bank([theirs])                    # a fresh process: its own bank from its files
	for p in back.bot.players:
		back.bot.game_bots[p] = Bots.GameBot.new(p, 39)
	assert_true(w.run_until(func() -> bool: return back.net_match != null, 600), "back in with the key")
	assert_eq(back.net_match.phase, MwNetMatch.Phase.WAITING)
	var waiting := back.bank()
	assert_false(bool(waiting["in_use"]), "its own bank while it waits")
	h.bot.quiet = false
	assert_true(w.run_until(func() -> bool: return back.net_match.synced_at >= 0, 3000), "taken up from a snapshot")
	gut.p("rejoined with a custom team: taken up at tick %d (screen %d), %d bytes" % [back.net_match.synced_at,
			back.net_match.synced_screen, back.net_match.stats["snapshot_bytes"]])
	var bb := back.bank()
	assert_true(bool(bb["in_use"]), "the host's teams in use")
	assert_eq(bb["overlay"], h.bank()["overlay"], "the bytes the host reads")
	assert_eq((bb["teams"] as Array)[0].name, "TESTERS")
	var on_rink := func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool:
			return m.net_match != null and m.net_match.phase == MwNetMatch.Phase.PLAYING \
					and m.router.current_id() in [4, 5, 6])
	assert_true(w.run_until(on_rink, 900), "both on the rink")
	w.run(400)
	var c := w.compare_hashes()
	assert_true(c["ok"], "every hash the host's - %s" % c["why"])
	assert_gt(back.net_match.hashes.size(), 100, "hashes since its return")
	assert_eq(back.net_match.mismatches.size(), 0, "no mismatch")
	assert_eq(back.rink().stadium, 23, "at the host's custom rink")
	h.enter()
	h.net_match.leave()
	h.leave()
	assert_true(w.run_until(func() -> bool: return back.ended >= 0, 600), "its match ends")
	var after := back.bank()
	assert_false(bool(after["in_use"]))
	assert_eq(after["teams"], [theirs], "its own bank back")
	assert_eq(h.bank()["teams"], [mine])
	assert_eq(_team_files().size(), 0, "no team file written")
	w.free_all()
