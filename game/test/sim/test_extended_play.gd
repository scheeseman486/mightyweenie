extends "res://test/rom/rom_test_base.gd"
## Plan 44: an EXTENDED match (the options' 2D EXTENDED / 3D EXTENDED,
## online always). The original's `$6D02` meets the rink only for players
## on its 320x240 screen round the camera; in an EXTENDED match the players
## humans drive count as on it wherever they are (owner: not the CPU's,
## which keep the original's behaviour), a CPU's player off it still meets
## the opponents humans drive (the owner's exception: CPU v human combat),
## EXTENDED CPU puts the CPU's players on it too, and EXTENDED PENALTIES
## lets the referee stop play for an offender anywhere. 2D and 3D matches:
## the original's.

var host: Node
var _saved := []


func before_each() -> void:
	_saved = [MwSettings.camera, MwSettings.start_view, MwSettings.extended_penalties, MwSettings.extended_cpu]
	MwSettings.start_view = -1


func after_each() -> void:
	MwSettings.own_match_rules()
	MwSettings.camera = _saved[0]
	MwSettings.start_view = _saved[1]
	MwSettings.extended_penalties = _saved[2]
	MwSettings.extended_cpu = _saved[3]
	if host != null and is_instance_valid(host):
		host.free()
	host = null


## A match in play (P1 v the CPU at team 22's home rink, Death Index 0) and its
## sim: [state, sim].
func _match(extended := false, cpu := false, penalties := false) -> Array:
	var s := MwRinkState.new()
	s.rng = MlhRng.new(7)
	var sim := MwRinkSim.new(rom, s)
	sim.cpu = MwRinkAI.new()
	var up := MwRinkUpdate.new(sim)
	var ph := MwRinkPhases.new(up)
	var su := MwMatchSetup.new()
	su.team_a = 22
	su.team_b = 5
	su.stadium = 22
	su.period_minutes = 5
	su.extended_play = extended
	su.extended_cpu = cpu
	su.extended_penalties = penalties
	MwRinkMatch.matchup_setup(sim, su, 0)
	ph.enter(5)
	for i in 600:                             # into open play (phase 0: past the faceoff)
		var to := up.run_pass(2, ph)
		if to >= 0:
			MwRinkMatch.rink_exit(sim, to)
			ph.enter(5)
		if i >= 60 and s.phase == 0:
			break
	assert_eq(s.phase, 0, "in open play")
	return [s, sim]


## A point on the ice 300 px from the middle of the original's screen (off it).
static func _off(s: MwRinkState) -> Vector2i:
	var cam := s.camera.shown
	var cx := cam.x + 160 - 256
	var cy := cam.y + 112 - 461
	return Vector2i(cx, cy + (300 if cy < 0 else -300))


static func _human(p: MwRinkState.Player, on: bool) -> void:
	if on:
		p.flags |= MwRinkState.Player.HUMAN
	else:
		p.flags &= ~MwRinkState.Player.HUMAN


## Team B's left wing standing in a fire off the screen for one collision
## pass: the health it lost.
func _burnt(extended: bool, cpu: bool, human: bool) -> int:
	var m := _match(extended, cpu)
	var s: MwRinkState = m[0]
	var sim: MwRinkSim = m[1]
	var p := s.teams[1].players[1]
	_human(p, human)
	p.state = 0
	var at := _off(s)
	var rink_object := sim.free_object()
	rink_object.kind = MwRinkState.KIND_FIRE
	rink_object.motion.init(at.x, at.y, 0)
	p.motion.init(at.x, at.y, 0)
	assert_false(MwRinkSim.on_screen(s, p), "off the original's screen")
	var h0 := s.teams[1].health[p.slot] & 0x7FFFFFFF
	sim.collide.player(p, 2)
	return h0 - (s.teams[1].health[p.slot] & 0x7FFFFFFF)


func test_a_fire_off_the_screen_burns_a_humans_player_in_an_extended_match() -> void:
	if not need_rom():
		return
	assert_eq(_burnt(false, false, true), 0, "a 2D / 3D match: the original's - off its screen, nothing")
	assert_eq(_burnt(false, false, false), 0)
	assert_gt(_burnt(true, false, true), 0, "an EXTENDED match: the human's player burns wherever he is")
	assert_eq(_burnt(true, false, false), 0, "the CPU's keeps the original's rule (owner)")
	assert_gt(_burnt(true, true, false), 0, "EXTENDED CPU: the CPU's too")
	assert_eq(_burnt(false, true, false), 0, "EXTENDED CPU outside an EXTENDED match: nothing")


## Team A's centre and team B's left wing overlapping off the screen, A
## skating into B, for one collision pass of A's: B's velocity after it.
func _bumped(extended: bool, cpu: bool, a_human: bool, b_human: bool) -> Vector2i:
	var m := _match(extended, cpu)
	var s: MwRinkState = m[0]
	var sim: MwRinkSim = m[1]
	var bumper := s.teams[0].players[0]
	var player := s.teams[1].players[1]
	_human(bumper, a_human)
	_human(player, b_human)
	for p in [bumper, player]:
		p.state = 0
	var at := _off(s)
	bumper.motion.init(at.x, at.y, 0)
	player.motion.init(at.x + 6, at.y, 0)
	bumper.motion.vel[0] = 0x400
	player.motion.vel[0] = 0
	sim.geometry()
	assert_false(MwRinkSim.on_screen(s, bumper) or MwRinkSim.on_screen(s, player), "both off the original's screen")
	s.fight_block = 1                         # (no fight's chance: the bump alone)
	sim.collide.player(bumper, 2)
	return Vector2i(player.motion.vel[0], player.motion.vel[1])


func test_cpu_and_human_players_meet_off_the_screen_in_an_extended_match() -> void:
	if not need_rom():
		return
	var still := Vector2i.ZERO
	assert_eq(_bumped(false, false, false, true), still, "a 2D / 3D match: off the screen, no bump")
	assert_ne(_bumped(true, false, false, true), still,
			"EXTENDED: a CPU's player off the screen hits a human's (owner: the combat exception)")
	assert_ne(_bumped(true, false, true, false), still, "and a human's hits a CPU's")
	assert_ne(_bumped(true, false, true, true), still, "two humans' players")
	assert_eq(_bumped(true, false, false, false), still, "two CPU players off the screen: the original's")
	assert_ne(_bumped(true, true, false, false), still, "EXTENDED CPU: they meet too")


## A minor penalty (code 2) called on team B's left wing off the screen in
## open play: whether it counted.
func _called(extended: bool, penalties: bool) -> bool:
	var m := _match(extended, false, penalties)
	var s: MwRinkState = m[0]
	var sim: MwRinkSim = m[1]
	var p := s.teams[1].players[1]
	var at := _off(s)
	p.motion.init(at.x, at.y, 0)
	s.penalties = 1
	s.phase = 0
	assert_false(MwRinkSim.on_screen(s, p))
	return sim.penalties.rule(2, p)


func test_extended_penalties_call_an_offender_off_the_screen() -> void:
	if not need_rom():
		return
	assert_false(_called(false, false), "the original's: the referee only sees its screen")
	assert_false(_called(true, false), "an EXTENDED match without EXTENDED PENALTIES: the same")
	assert_true(_called(true, true), "EXTENDED PENALTIES: anywhere")


func test_the_rules_go_from_the_options_into_the_match() -> void:
	var su := MwMatchSetup.new()
	MwSettings.extended_penalties = true
	MwSettings.extended_cpu = true
	MwSettings.camera = MwSettings.CAMERAS.find("3D")
	su.take_extended_rules()
	assert_eq([su.extended_play, su.extended_penalties, su.extended_cpu], [false, false, false],
			"a 3D match: the options' EXTENDED ones do nothing")
	MwSettings.camera = MwSettings.CAMERAS.find("2D EXTENDED")
	su.take_extended_rules()
	assert_eq([su.extended_play, su.extended_penalties, su.extended_cpu], [true, true, true])
	var copied := su.copy()
	assert_eq([copied.extended_play, copied.extended_penalties, copied.extended_cpu], [true, true, true], "copied")
	var rules := MwSettings.match_rules()
	assert_eq([rules["extended_play"], rules["extended_penalties"], rules["extended_cpu"]], [true, true, true],
			"match rules: in the start record, online the host's")
	MwSettings.camera = MwSettings.CAMERAS.find("2D")
	var online := MwNetMatch.online_rules()
	assert_true(online["extended_play"], "online: forced EXTENDED (owner)")
	assert_eq(online["opening_view"], MwRinkViews.EXTENDED_2D, "the host's 2D in that group")
	MwSettings.use_match_rules(online)
	assert_true(MwSettings.extended_play())
	assert_eq(MwSettings.view(), MwRinkViews.EXTENDED_2D)
	su.take_extended_rules()
	assert_true(su.extended_play)
	MwSettings.own_match_rules()
	assert_false(MwSettings.extended_play(), "this machine's own again")
	if not need_rom():
		return
	var m := _match(true, true, true)
	var s: MwRinkState = m[0]
	assert_eq([s.extended_play, s.extended_cpu, s.extended_penalties], [true, true, true], "into the state")
	var d := MwSimDict.to_dict(s)
	assert_eq([d.get("extended_play"), d.get("extended_cpu"), d.get("extended_penalties")], [true, true, true],
			"in the state's fields (snapshots, copies, hashes)")
	var back := MwSimDict.from_dict(d)
	assert_true(back.extended_play and back.extended_cpu and back.extended_penalties, "and back")


func test_the_rinks_entry_takes_the_match_rule() -> void:
	if not need_rom():
		return
	for cam in ["3D", "3D EXTENDED"]:
		MwSettings.camera = MwSettings.CAMERAS.find(cam)
		host = Node.new()
		add_child(host)
		var fader := MwScreenFader.new()
		host.add_child(fader)
		var router := MwRouter.new(host, fader)
		router.session = MwSession.new(0x61F2415D, 0x1234567)
		router.input = MwLiveInput.new()
		var rink := (load(MwScreens.scene_path(4)) as PackedScene).instantiate() as MwRink
		rink.screen_id = 4
		router.adopt(rink, {"new_match": true})
		assert_eq(rink.state.extended_play, cam == "3D EXTENDED", "%s: the match's rule" % cam)
		host.free()
		host = null
