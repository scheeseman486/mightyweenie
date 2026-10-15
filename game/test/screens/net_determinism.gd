extends SceneTree
## Plan 35's offline proof, one side per process (docs/net.md;
## `tools/bin/net-determinism` runs both and compares):
##
##   godot --headless -s res://test/screens/net_determinism.gd -- --record FILE [options]
##   godot --headless -s res://test/screens/net_determinism.gd -- --replay FILE
##
## --record plays a local match from the game setup with live_match.gd's
## bots (its options: --seed, --pads, --minutes, --penalties, --teams,
## --humans, --owners, --captains, --bots, --view, --tick-rate; --ticks N,
## default 20000) and writes its start record, input stream and hashes to FILE.
## Plan 38: --custom T puts a changed copy of original team T (players of its
## own, its rink's gravity and a pit) in the recording process's bank as
## team 23 (e.g. with --teams 23,8): the record carries it, and the replay -
## a process without custom teams - plays it from the record.
## --replay plays FILE's record and stream in this fresh process and
## compares its hashes with the file's: exits 0 when every one is equal.

const Proof := preload("res://test/screens/net_proof.gd")

var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	var a := _args()
	var t0 := Time.get_ticks_msec()
	if a.has("record"):
		var opts := a.duplicate()
		for k in ["pads", "minutes", "penalties", "seed", "owners", "bots", "view", "heights"]:
			if opts.has(k):
				opts[k] = int(opts[k])
		if a.has("custom"):
			_custom_team(int(a["custom"]))
		var rec := Proof.record(root, opts, int(a.get("ticks", "20000")))
		var err := rec.save(str(a["record"]))
		print("recorded %d ticks, %d hashes (%d of the rink's passes) in %.1f s -> %s (%s)" % [
				rec.stream.ticks.size(), rec.hashes.size(), _passes(rec.hashes),
				(Time.get_ticks_msec() - t0) / 1000.0, a["record"], error_string(err)])
		quit(0 if err == OK else 1)
	elif a.has("replay"):
		var rec := MwNetRecording.open(str(a["replay"]))
		if rec == null:
			print("RESULT not a recording: %s" % a["replay"])
			quit(2)
			return true
		var mine := Proof.replay(root, rec)
		var diff := rec.first_difference(mine)
		print("replayed %d ticks, %d hashes in %.1f s" % [rec.stream.ticks.size(), mine.size(),
				(Time.get_ticks_msec() - t0) / 1000.0])
		print("RESULT %s" % ("equal" if diff == "" else "DIFFERENT - " + diff))
		quit(0 if diff == "" else 1)
	else:
		print("usage: -- --record FILE [options] | --replay FILE")
		quit(2)
	return true


## Plan 38: a changed copy of original team [param team] as custom team 23.
static func _custom_team(team: int) -> void:
	var rom := MwRom.archive().bytes()
	var custom := MwCustomTeam.from_original(rom, team)
	custom.name = "CUSTOMS"
	custom.rink.gravity = -16
	custom.rink.hazards.append({"kind": "pit", "x": -120, "y": 180, "mirror": false})
	for s in [0, 3, 7]:
		var player := MwCustomPlayer.from_record(rom, MwTeams.player(rom, team, s))
		player.ratings["speed"] = 10
		custom.players.append(player)
		custom.roster[s] = {"player": custom.players.size() - 1}
	custom.validate(rom)
	MwCustomTeams.clear()
	MwCustomTeams.teams.append(custom)
	MwCustomTeams.rebuild()


static func _passes(hashes: Array) -> int:
	var n := 0
	for h in hashes:
		if int(h[1]) == MwNetRecording.PASS:
			n += 1
	return n


func _args() -> Dictionary:
	return preload("res://test/support/cli.gd").args()      # (plan 40: one copy)
