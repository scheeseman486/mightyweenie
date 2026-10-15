extends "res://test/rom/rom_test_base.gd"
## The playoffs with a custom team (plan 38, owner's option 2): it plays a
## run in its playoff place's stead - places, bracket and draws the
## original's; plan 34's saves keep its run and the team's file name.

const TEST_DIR := "user://test_custom_playoffs"
const ScreenRig := preload("res://test/support/screen_rig.gd")

var _teams_dir := ""
var _saves_dir := ""


func before_all() -> void:
	super.before_all()
	_teams_dir = MwCustomTeams.dir                # (the run's test folders, pre_run.gd: put back after)
	_saves_dir = MwPlayoffSave.dir


func after_each() -> void:
	MwCustomTeams.clear()
	MwCustomTeams.dir = _teams_dir
	MwPlayoffSave.dir = _saves_dir
	var d := DirAccess.open(TEST_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(TEST_DIR)


func _custom(place: int) -> int:
	MwCustomTeams.dir = TEST_DIR
	var team := MwCustomTeam.from_original(MwRom.archive().bytes(), 2)
	team.city = "Play"
	team.name = "Offs"
	team.playoff_place = place
	return MwCustomTeams.save(team)


func _setup(a: int, b: int, mode := 1) -> MwMatchSetup:
	var su := MwMatchSetup.new()
	su.team_a = a
	su.team_b = b
	su.play_mode = mode
	return su


func test_a_run_in_the_place_s_stead() -> void:
	if not need_rom():
		return
	var id := _custom(14)
	var run := MwPlayoffs.new()
	run.start(_setup(id, 11), MlhRng.new(77))
	var orig := MwPlayoffs.new()
	orig.start(_setup(14, 11), MlhRng.new(77))
	assert_eq(run.custom, id)
	assert_eq(run.pair, orig.pair, "the place's pair")
	assert_eq(run.conference, 1)
	assert_eq(run.seed, orig.seed, "the same draw")
	run.build_bracket(MwRom.data(), MwPlayoffs.place(id), 11)
	orig.build_bracket(MwRom.data(), 14, 11)
	assert_eq(run.sides, orig.sides, "the original's bracket and results")
	var g := run.game_teams()
	assert_eq(run.shown(g.x), id)
	assert_eq(run.shown(g.y), g.y)
	assert_eq(run.shown(3), 3)


func test_a_saved_run_comes_back_under_the_team_s_id_now() -> void:
	if not need_rom():
		return
	var id := _custom(4)
	var session := MwSession.new(1, 1)
	session.setup = _setup(id, 7)
	session.playoffs.start(session.setup, MlhRng.new(5))
	session.playoffs.build_bracket(MwRom.data(), 4, 7)
	session.playoffs.flags &= ~MwPlayoffs.NEW
	session.playoffs.game_over(true)
	session.run_checkpoint = session.setup.to_bytes() + session.playoffs.to_bytes()
	MwPlayoffSave.dir = TEST_DIR.path_join("saves")
	assert_true(MwPlayoffSave.save(session, 1))
	var run := session.playoffs.to_bytes()
	# another custom team first in the bank: this one's id moves on
	var other := MwCustomTeam.from_original(MwRom.archive().bytes(), 1)
	other.city = "Aaa"
	other.name = "Firsts"
	MwCustomTeams.save(other)
	MwCustomTeams.clear()
	MwCustomTeams.load_bank()
	var now := MwCustomTeams.id_of_team(MwCustomTeams.teams[1])
	assert_eq(MwCustomTeams.teams[1].name, "Offs")
	assert_ne(now, id)
	var info := MwPlayoffSave.info(1)
	assert_true(info["ok"])
	assert_eq(info["team_a"], now, "the list names the custom team")
	var again := MwSession.new(1, 1)
	assert_true(MwPlayoffSave.load_into(again, 1))
	assert_eq(again.setup.team_a, now)
	assert_eq(again.playoffs.custom, now)
	assert_eq(again.playoffs.to_bytes(), run, "the run as it was")
	assert_eq(again.playoffs.shown(again.playoffs.teams().x), now)
	# the team deleted: the save can't be loaded
	MwCustomTeams.delete(MwCustomTeams.teams[1])
	assert_false(MwPlayoffSave.info(1)["ok"])
	assert_false(MwPlayoffSave.load_into(MwSession.new(1, 1), 1))
	MwPlayoffSave.delete(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MwPlayoffSave.dir))


func test_a_password_names_the_originals() -> void:
	if not need_rom():
		return
	var id := _custom(4)
	var run := MwPlayoffs.new()
	run.start(_setup(id, 7), MlhRng.new(5))
	run.build_bracket(MwRom.data(), 4, 7)
	run.game_over(true)
	var pw := run.make_password(MwRom.data(), 0, 0, 0)
	var back := MwPlayoffs.new()
	back.custom = id
	assert_true(back.enter_password(MwRom.data(), pw))
	assert_eq(back.custom, -1)
	assert_eq(back.teams(), Vector2i(4, 7))


## Plan 40 (D3): the game reads a custom team's place from its record in
## the view (+$A1) - the editor's working copy as shown, a team the view
## doesn't hold is no custom team.
func test_the_place_is_the_record_s() -> void:
	if not need_rom():
		return
	var id := _custom(14)
	assert_true(MwTeams.is_custom(id))
	assert_eq(MwTeams.playoff_place(MwRom.data(), id), 14)
	assert_eq(MwPlayoffs.place(id), 14)
	assert_eq(MwPlayoffs.place(5), 5, "an original team: its own place")
	assert_false(MwTeams.is_custom(5))
	assert_false(MwTeams.is_custom(id + 1), "not in the view")
	var copy := MwCustomTeam.from_dict(MwRom.archive().bytes(), MwCustomTeams.team(id).to_dict())
	copy.playoff_place = 3
	MwCustomTeams.edit(copy, MwCustomTeams.team(id))
	assert_eq(MwPlayoffs.place(id), 3, "the working copy as the view shows it")
	MwCustomTeams.stop_editing()
	assert_eq(MwPlayoffs.place(id), 14, "the bank's again")
	var fresh := MwCustomTeam.from_original(MwRom.archive().bytes(), 4)
	fresh.playoff_place = 8
	MwCustomTeams.edit(fresh)
	var at := MwCustomTeams.editing_id()
	assert_true(MwTeams.is_custom(at), "a new team's working copy is read")
	assert_eq(MwTeams.playoff_place(MwRom.data(), at), 8)
	assert_eq(MwTeams.count(), MwTeams.COUNT + 1, "and never offered")
	MwCustomTeams.stop_editing()


## A custom team's run goes on past its first game: the bracket after the
## game shows the password (the place's original team's, as the original
## shows it) and the run is still the custom team's - its next game, its
## autosave (owner, 2026-10-15: asked whether loading and saving a playoff
## run keeps a custom team's set-up).
func test_a_custom_run_stays_custom_past_its_password() -> void:
	if not need_rom():
		return
	var front := MwSettings.front_menu
	MwSettings.front_menu = true
	MwPlayoffSave.dir = TEST_DIR.path_join("saves")
	var id := _custom(4)
	var session := MwSession.new(1, 1)
	session.local_mode = "playoffs"
	session.setup = _setup(id, 7)
	session.setup.stadium = id
	session.playoffs.start(session.setup, session.rng)                  # PLAY GAME: the new run
	session.run_started = true
	session.playoffs.build_bracket(MwRom.data(), MwPlayoffs.place(id), 7)
	var g := session.playoffs.game_teams()
	session.setup.team_a = session.playoffs.shown(g.x)
	session.setup.team_b = g.y
	session.playoffs.flags &= ~MwPlayoffs.NEW               # the bracket's Start
	session.playoffs.game_over(true)                        # the game, won
	var rig := ScreenRig.new()
	var router := rig.make(self, session)
	var stand_in := MwScreen.new()
	stand_in.screen_id = 16                                # the playoff game's last scoreboard
	router.adopt(stand_in)
	router.fader.uncover()
	router.go(11)
	rig.run(200)
	assert_true(router.current() is MwPasswordScreen, "the new password, as the original")
	rig.hold({"ui_password_done": true, "p1_ui_password_done": true}, 3, 0)
	rig.run(200)
	assert_eq(router.current_id(), 11, "the bracket")
	assert_eq(session.playoffs.custom, id, "still the custom team's run")
	assert_eq(session.setup.team_a, id, "its next game")
	assert_eq(MwPlayoffSave.info(MwPlayoffSave.AUTOSAVE).get("team_a"), id, "the autosave names it")
	rig.free_host()
	MwSettings.front_menu = front


## A saved custom run loads as the run it was, whatever was done to the
## bank and the team since: its place in the bracket (an edited PLAYOFF
## PLACE moves nothing: the run's place), its rink under the team's id now;
## a team switched off or deleted is named on the list, not loaded (owner,
## 2026-10-15).
func test_a_saved_custom_run_keeps_its_place_and_rink() -> void:
	if not need_rom():
		return
	var id := _custom(4)
	var session := MwSession.new(1, 1)
	session.setup = _setup(id, 7)
	session.setup.stadium = id
	session.playoffs.start(session.setup, MlhRng.new(5))
	session.run_checkpoint = session.setup.to_bytes() + session.playoffs.to_bytes()
	MwPlayoffSave.dir = TEST_DIR.path_join("saves")
	assert_true(MwPlayoffSave.save(session, 2))
	var saved := session.playoffs.to_bytes()
	session.playoffs.build_bracket(MwRom.data(), session.playoffs.run_place(id), 7)
	var want: Array = [session.playoffs.sides[0], session.playoffs.sides[1], session.playoffs.game_teams()]
	# another custom team first in the bank (this one's id moves on), its place edited
	var other := MwCustomTeam.from_original(MwRom.archive().bytes(), 1)
	other.city = "Aaa"
	other.name = "Firsts"
	MwCustomTeams.save(other)
	var team := MwCustomTeams.teams[1]
	assert_eq(team.name, "Offs")
	team.playoff_place = 12
	var now := MwCustomTeams.save(team)
	assert_ne(now, id)
	assert_eq(MwPlayoffs.place(now), 12)
	var again := MwSession.new(1, 1)
	assert_true(MwPlayoffSave.load_into(again, 2))
	assert_eq(again.setup.team_a, now)
	assert_eq(again.setup.stadium, now, "its rink, under its id now")
	assert_eq(again.playoffs.to_bytes(), saved)
	assert_eq(again.playoffs.run_place(now), 4, "the run's place, not the edited one")
	again.playoffs.build_bracket(MwRom.data(), again.playoffs.run_place(again.setup.team_a), again.setup.team_b)
	assert_eq([again.playoffs.sides[0], again.playoffs.sides[1], again.playoffs.game_teams()], want,
			"the same bracket")
	assert_eq(again.playoffs.shown(again.playoffs.game_teams().x), now, "the custom team plays it")
	# switched off: named, not loaded; on again: loaded
	MwCustomTeams.set_enabled(team, false)
	var info := MwPlayoffSave.info(2)
	assert_false(info["ok"])
	assert_eq(info["why"], "TEAM IS OFF")
	assert_false(MwPlayoffSave.load_into(MwSession.new(1, 1), 2))
	MwCustomTeams.set_enabled(team, true)
	assert_true(MwPlayoffSave.info(2)["ok"])
	MwCustomTeams.delete(team)
	assert_eq(MwPlayoffSave.info(2)["why"], "TEAM DELETED")
	MwPlayoffSave.delete(2)
