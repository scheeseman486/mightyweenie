extends "res://test/rom/rom_test_base.gd"
## Plan 35 work item 1, the offline proof in one process (docs/net.md; the
## two-process run is `tools/bin/net-determinism`): a short local match with
## bots on the pads recorded - start record, input stream, a hash every
## pass - and replayed from the record and the stream alone gives the same
## hashes; the stream changed gives others.

const Proof := preload("res://test/screens/net_proof.gd")
const TICKS := 2400


func test_a_recorded_match_replays_the_same() -> void:
	if not need_rom():
		return
	var rec := Proof.record(self, {"seed": 7, "humans": "1.2", "teams": "3,8"}, TICKS)
	assert_eq(rec.stream.ticks.size(), TICKS, "a tick of input each tick")
	var passes := 0
	var distinct := {}
	for h in rec.hashes:
		if int(h[1]) == MwNetRecording.PASS:
			passes += 1
			distinct[h[3]] = true
	assert_gt(passes, 600, "the rink's passes hashed")
	assert_gt(distinct.size(), passes / 2, "and they change as the game goes")
	# through the file's bytes, into a fresh session
	var path := "user://test_net_proof.mwnet"
	assert_eq(rec.save(path), OK)
	var back := MwNetRecording.open(path)
	assert_not_null(back)
	var mine := Proof.replay(self, back)
	assert_eq(back.first_difference(mine), "", "every hash equal")
	# player 1 holding up from early in the match on: the game goes otherwise
	var t := _a_rink_tick(back)
	assert_gt(t, 0)
	for k in range(t, back.stream.last_tick() + 1):
		back.stream.at(k).set_held(MwTickInput.index_of("p1_move_up"), true)
		back.stream.at(k).set_held(MwTickInput.index_of("p1_move_down"), false)
	var other := Proof.replay(self, back)
	assert_ne(back.first_difference(other), "", "another stream, another game")


## The shot heights (MwSettings.shot_heights) recorded with the bots'
## heights changing every 13 ticks (players 1, 5 and 2: an extended set-up)
## replay the same from the stream; one tick's heights changed on the rink
## gives another game (the pads' heights are hashed).
func test_shot_heights_replay_the_same() -> void:
	if not need_rom():
		return
	var rec := Proof.record(self, {"seed": 9, "humans": "1+5.2", "teams": "2,6", "heights": 13}, 1800)
	var with := 0
	for ti in rec.stream.ticks:
		if ti.heights.count(0) != ti.heights.size():
			with += 1
	assert_gt(with, 200, "ticks carrying heights (%d)" % with)
	var path := "user://test_net_proof_heights.mwnet"
	assert_eq(rec.save(path), OK)
	var back := MwNetRecording.open(path)
	assert_not_null(back)
	var mine := Proof.replay(self, back)
	assert_eq(back.first_difference(mine), "", "every hash equal")
	var t := _a_rink_tick(back)
	assert_gt(t, 0)
	var ti := back.stream.at(t)
	ti.heights[0] = (ti.heights[0] + 1) & 3
	var other := Proof.replay(self, back)
	assert_ne(back.first_difference(other), "", "another height, another game")


## Plan 38 with plan 35: the custom teams are part of what the game's
## course depends on, so the start record carries them ("custom_teams":
## their JSON) and a replay takes them from it - the same game on a machine
## without custom teams and on one whose bank holds another team under the
## same id (its own bank back after); another team in the record, another
## game.
func test_a_custom_teams_match_replays_from_its_record() -> void:
	if not need_rom():
		return
	var rom_alone := MwRom.archive().bytes()
	var team := MwCustomTeam.from_original(rom_alone, 9)
	team.rink.gravity = -16
	for slot in [0, 3, 7]:
		var player := MwCustomPlayer.from_record(rom_alone, MwTeams.player(rom_alone, 9, slot))
		player.ratings["speed"] = 10
		team.players.append(player)
		team.roster[slot] = {"player": team.players.size() - 1}
	team.validate(rom_alone)
	MwCustomTeams.teams.append(team)
	MwCustomTeams.rebuild()
	var rec := Proof.record(self, {"seed": 9, "humans": "1.2", "teams": "23,8"}, TICKS)
	assert_true(rec.record.has("custom_teams"), "the record carries the custom teams")
	assert_eq(((rec.record["custom_teams"] as Dictionary)["teams"] as Array).size(), 1)
	var json: Variant = JSON.parse_string(JSON.stringify(rec.record))
	assert_eq(MwNetHash.digest(json), MwNetHash.digest(rec.record), "the same record through JSON")
	var path := "user://test_net_proof_custom.mwnet"
	assert_eq(rec.save(path), OK)
	var back := MwNetRecording.open(path)
	# a machine without custom teams
	MwCustomTeams.clear()
	var bare := Proof.replay(self, back)
	assert_eq(back.first_difference(bare), "", "every hash equal on a machine without the team")
	assert_eq(MwCustomTeams.count(), 0, "still none after")
	assert_eq(MwRom.data().size(), rom_alone.size(), "the ROM alone again")
	# another machine: another team under id 23 in its bank
	var other := MwCustomTeam.from_original(rom_alone, 2)
	MwCustomTeams.teams.append(other)
	MwCustomTeams.rebuild()
	var mine := Proof.replay(self, back)
	assert_eq(back.first_difference(mine), "", "every hash equal: the record's team played")
	assert_eq(MwCustomTeams.teams, [other] as Array[MwCustomTeam], "the machine's own bank back after")
	assert_false(MwCustomTeams.teams_in_use())
	var carried: Dictionary = ((back.record["custom_teams"] as Dictionary)["teams"] as Array)[0]
	(carried["rink"] as Dictionary)["gravity"] = -40
	var theirs := Proof.replay(self, back)
	assert_ne(back.first_difference(theirs), "", "another team in the record: another game")
	MwCustomTeams.clear()


## A tick of the recording's first rink pass hash.
static func _a_rink_tick(rec: MwNetRecording) -> int:
	for h in rec.hashes:
		if int(h[1]) == MwNetRecording.PASS:
			return int(h[0]) + 20
	return -1
