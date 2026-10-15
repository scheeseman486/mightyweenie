extends "res://test/net/net_test_base.gd"
## Plan 41 work item 1: client-side menus (MwLocalEcho, MwScreen.predict_local,
## MwNetMatch.unconfirmed). A host and a client in one process on the
## loopback at 250 ms round trip, the client's player pressing by a script:
## the client's own picture shows each press the frame it is made - long
## before its game runs it - and the game, its hashes and the host's
## picture are as they would be without it; a press the game refuses is
## shown, then taken back.

const Machines := preload("res://test/net/net_machines.gd")
const Bots := preload("res://test/support/bots.gd")

## The loopback each way (ms): a 250 ms round trip.
const ONE_WAY := 125


func should_skip_script():
	return rom_or_skip()


func after_each() -> void:
	MwLocalEcho.enabled = true


## A host (P1) and a client (P2) at [param one_way] ms each way, START
## GAME, both on the controller selection; P2's bot quiet (the test
## presses), P1's on team A, never going on (it waits for a third player).
func _two(one_way := ONE_WAY) -> Machines:
	var w := Machines.new(self, 41, {"delay": one_way}, [1])
	for m in w.machines:
		m.bot.expected = 3
		m.bot.teams[1] = 0
	w.machine(1).bot.quiet = true
	w.start()
	assert_true(w.run_until(func() -> bool:
		for m in w.machines:
			if m.router.current_id() != MwScreens.CONTROLLER_SELECT or m.router.busy():
				return false
		return true, 6000), "both on the controller selection")
	w.run(30)
	return w


## [param m]'s player [param p] presses [param verb] now (held 4 ticks).
static func _press(m: Machines.Machine, p: int, verb: String) -> void:
	m.bot.presses.append([m.router.tick + 1, p, MwVerbs.menu_action(p, verb), 4])


static func _select(m: Machines.Machine) -> MwControllerSelect:
	return (m.router.current() as MwMainMenu).select if m.router.current() is MwMainMenu else null


func test_unconfirmed_presses_are_this_machines_until_run() -> void:
	assert_eq(MwNetMatch.MENU_VERB, MwNetInput.index_of("ui_up"), "the menu verbs' first")
	var w := _two()
	var c := w.machine(1)
	_press(c, 2, "ui_right")
	w.run(3)
	assert_eq(c.net_match.unconfirmed(), {2: ["ui_right"]}, "pressed, not yet run")
	assert_eq(w.machines[0].net_match.unconfirmed(), {}, "the host has none")
	assert_true(w.run_until(func() -> bool: return c.session.humans.team_of(2) == 1, 600), "run: team B")
	assert_eq(c.net_match.unconfirmed(), {}, "let go once run")
	w.free_all()


func test_a_side_shows_at_once_and_the_game_is_unchanged() -> void:
	var w := _two()
	var machine := w.machines[0]
	var c := w.machine(1)
	_press(c, 2, "ui_right")
	var frames := 0
	while frames < 60 and int(_select(c).drawn.get(2, -1)) != 1:
		w.run(1)
		frames += 1
	assert_lte(frames, 3, "the client draws its player on team B within a frame or two")
	assert_eq(c.session.humans.team_of(2), MwHumans.MIDDLE, "while its game still has P2 in the middle")
	assert_eq(int(_select(machine).drawn[2]), MwHumans.MIDDLE, "and the host hasn't had the press yet")
	var run_at := -1
	for i in 120:
		w.run(1)
		if run_at < 0 and c.session.humans.team_of(2) == 1:
			run_at = frames + i + 1
		assert_eq(int(_select(c).drawn[2]), 1, "drawn on team B throughout (frame %d)" % (frames + i + 1))
	assert_between(run_at, 15, 40, "the client's game runs it a round trip and the buffer later")
	assert_eq(int(_select(machine).drawn[2]), 1, "the host's too")
	var hashes := w.compare_hashes()
	assert_true(hashes["ok"], "every hash the host's: " + str(hashes["why"]))
	assert_gt(int(hashes["compared"]), 0)
	w.free_all()


## Work item 3: the move's sound is heard on the client the frame the press
## shows, once (the frames after predict it again: the same press), and not
## again when the game runs it - the game's own driver got the call then, as
## the host's did (every hash the host's).
func test_a_press_is_heard_at_once_and_once_only() -> void:
	var w := _two()
	var c := w.machine(1)
	var heard: MwHeard = c._statics["heard"]
	assert_not_null(heard, "a client hears apart from its game's driver")
	assert_null(w.machines[0]._statics["heard"], "the host doesn't")
	var moves := func() -> Array:
		return heard.log.filter(func(e: Array) -> bool: return e[2] == "play" and e[3] == [MwSoundIds.MOVE])
	heard.log.clear()
	_press(c, 2, "ui_right")
	var frames := 0
	while frames < 60 and moves.call().is_empty():
		w.run(1)
		frames += 1
	assert_lte(frames, 3, "heard within a frame or two")
	assert_eq((moves.call()[0] as Array)[1], "predicted")
	assert_true(w.run_until(func() -> bool: return c.session.humans.team_of(2) == 1, 600), "the game runs it")
	w.run(5)
	var whys: Array = moves.call().map(func(e: Array) -> String: return e[1])
	assert_eq(whys.count("predicted"), 1, "predicted once: %s" % str(heard.log))
	assert_eq(whys.count("skipped"), 1, "the game's call not heard again")
	var hashes := w.compare_hashes()
	assert_true(hashes["ok"], "every hash the host's: " + str(hashes["why"]))
	w.free_all()


func test_off_it_waits_for_the_game() -> void:
	MwLocalEcho.enabled = false
	var w := _two()
	var c := w.machine(1)
	_press(c, 2, "ui_right")
	w.run(8)
	assert_eq(int(_select(c).drawn.get(2, -1)), MwHumans.MIDDLE, "off: the press waits for the round trip")
	w.free_all()


func test_a_refused_move_and_back() -> void:
	var w := _two()
	var c := w.machine(1)
	_press(c, 2, "ui_right")
	assert_true(w.run_until(func() -> bool: return c.session.humans.team_of(2) == 1, 600))
	w.run(10)
	_press(c, 2, "ui_right")                 # past team B: refused by the screen's own rule
	w.run(3)
	assert_eq(int(_select(c).drawn[2]), 1, "nothing to show past team B")
	_press(c, 2, "ui_back")
	w.run(3)
	assert_eq(int(_select(c).drawn[2]), MwHumans.MIDDLE, "Back shows the middle at once")
	assert_eq(c.session.humans.team_of(2), 1, "the game not yet")
	w.free_all()


## Character selection (111): five players, the host's P1 and the client's
## P3 on team A. P3 is moved onto P1's card; then P1 picks it and, a frame
## later - before the host's pick can reach the client - so does P3.
func test_a_pick_shows_at_once_and_a_lost_one_is_taken_back() -> void:
	var w := Machines.new(self, 43, {"delay": ONE_WAY}, [3], 2)
	var sides := {1: 0, 3: 0, 2: 1, 4: 1, 5: 1}
	for m in w.machines:
		m.bot.expected = sides.size()
		for p in m.bot.players:
			m.bot.teams[p] = sides[p]
		m.bot.hook = func(b: Machines.NetBot) -> void:
			if b.screen == MwScreens.CHARACTER_SELECT:
				b.quiet = true                   # the test picks
	w.start()
	var machine := w.machines[0]
	var c := w.machine(1)
	assert_true(w.run_until(func() -> bool:
		for m in w.machines:
			if m.router.current_id() != MwScreens.CHARACTER_SELECT or m.router.busy():
				return false
		return true, 9000), "both on character selection")
	w.run(10)
	var cs := c.router.current() as MwCharacterSelect
	var hs := machine.router.current() as MwCharacterSelect
	if int(hs.picks[1]) != MwCharacterSelect.Pick.MOVING:
		_press(machine, 1, "ui_back")              # (P1's presses going on from 110 picked as 111 came)
		assert_true(w.run_until(func() -> bool:
			return int(cs.picks[1]) == MwCharacterSelect.Pick.MOVING, 600), "P1 choosing again")
	var target := int(cs.cursor[1])
	# P3 onto P1's card, one press at a time, each run before the next
	for i in 6:
		var at := int(cs.cursor[3])
		if at == target:
			break
		_press(c, 3, "ui_down" if at / 3 != target / 3 else "ui_right")
		assert_true(w.run_until(func() -> bool: return int(cs.cursor[3]) != at, 600), "P3 moved")
	assert_eq(int(cs.cursor[3]), target, "P3 on P1's card")
	w.run(10)
	_press(machine, 1, "ui_accept")
	w.run(1)
	_press(c, 3, "ui_accept")
	w.run(3)
	assert_eq(cs.drawn[3], [Vector2i(0, target), MwCharacterSelect.Pick.LOCKED],
			"the client shows P3's pick at once (no line-ups: locked)")
	assert_false((cs.taken[0] as Dictionary).has(target), "its game hasn't run either pick yet")
	assert_true(w.run_until(func() -> bool: return cs.taken[0].get(target, 0) == 1, 600), "P1's pick came first")
	assert_true(w.run_until(func() -> bool: return c.net_match.unconfirmed().is_empty(), 600), "P3's run")
	w.run(2)
	assert_eq(cs.drawn[3], [Vector2i(0, target), MwCharacterSelect.Pick.MOVING],
			"refused by the game: P3 shown still choosing, on P1's card")
	assert_eq(int(cs.picks[3]), MwCharacterSelect.Pick.MOVING)
	var hashes := w.compare_hashes()
	assert_true(hashes["ok"], str(hashes["why"]))
	w.free_all()


## Plan 45 (determinism L1): a predicted Back on a locked pick shows the
## player choosing again, but its card's face - the game's portrait and
## voices - goes on pulling until the game runs the Back.
func test_a_predicted_back_leaves_the_face_to_the_game() -> void:
	var w := Machines.new(self, 45, {"delay": ONE_WAY}, [3], 2)
	var sides := {1: 0, 3: 0, 2: 1, 4: 1, 5: 1}
	for m in w.machines:
		m.bot.expected = sides.size()
		for p in m.bot.players:
			m.bot.teams[p] = sides[p]
		m.bot.hook = func(b: Machines.NetBot) -> void:
			if b.screen == MwScreens.CHARACTER_SELECT:
				b.quiet = true                   # the test picks
	w.start()
	var c := w.machine(1)
	assert_true(w.run_until(func() -> bool:
		for m in w.machines:
			if m.router.current_id() != MwScreens.CHARACTER_SELECT or m.router.busy():
				return false
		return true, 9000), "both on character selection")
	w.run(10)
	var cs := c.router.current() as MwCharacterSelect
	var pos := int(cs.cursor[3])
	if (cs.taken[0] as Dictionary).has(pos):
		_press(c, 3, "ui_right")
		assert_true(w.run_until(func() -> bool: return int(cs.cursor[3]) != pos, 600), "P3 moved")
		pos = int(cs.cursor[3])
	_press(c, 3, "ui_accept")
	assert_true(w.run_until(func() -> bool: return cs.taken[0].get(pos, 0) == 3, 600), "P3's pick run")
	var card: MwCharacterCard = cs.cards[0][pos]
	assert_true(w.run_until(func() -> bool: return card.pulling(), 600), "its face pulling")
	_press(c, 3, "ui_back")
	w.run(3)
	assert_eq(cs.drawn[3][1], MwCharacterSelect.Pick.MOVING, "the Back shown at once")
	assert_false(c.net_match.unconfirmed().is_empty(), "not run yet")
	assert_ne(card.portrait.which, 0, "the face still the game's: pulling")
	assert_true(w.run_until(func() -> bool: return c.net_match.unconfirmed().is_empty(), 600), "the Back run")
	w.run(2)
	assert_eq(card.portrait.which, 0, "the game's Back rested it")
	var hashes := w.compare_hashes()
	assert_true(hashes["ok"], str(hashes["why"]))
	w.free_all()


## The line-up panels (113): two players, a team each (each their team's
## captain), Reserves on - the client's P2 drives team B's panel: its
## highlight and the browsed candidate show at once, the game's later.
func test_the_panels_show_the_clients_presses_at_once() -> void:
	var w := Machines.new(self, 44, {"delay": ONE_WAY}, [1])
	w.machines[0].session.setup.reserves = 1
	for m in w.machines:
		m.bot.expected = 2
		m.bot.teams[1] = 0
		m.bot.teams[2] = 1
		m.bot.hook = func(b: Machines.NetBot) -> void:
			if b.screen == MwScreens.LINEUPS:
				b.quiet = true                   # the test presses
	w.start()
	var c := w.machine(1)
	var panels_in := func() -> bool:
		for m in w.machines:
			var cs := m.router.current() as MwCharacterSelect
			if cs == null or cs.panels.size() != 2 or m.router.busy() \
					or not cs.panels.all(func(panel: MwLineupPanel) -> bool: return panel.landed()):
				return false
		return true
	assert_true(w.run_until(panels_in, 9000), "both machines' panels landed")
	w.run(10)
	var pn: MwLineupPanel = (c.router.current() as MwCharacterSelect).panels[1]
	assert_eq(pn.drivers, [2] as Array[int], "team B's panel: the client's P2")
	var was := pn.cursor
	_press(c, 2, "ui_right")
	w.run(3)
	assert_eq(int(pn.drawn[0]), was + 1, "the highlight moved at once")
	assert_eq(pn.cursor, was, "the game's still where it was")
	assert_true(w.run_until(func() -> bool: return pn.cursor == was + 1, 600), "the game's too, later")
	w.run(3)
	_press(c, 2, "ui_down")
	w.run(3)
	assert_gte(int(pn.drawn[1]), 0, "a candidate browsed at once")
	assert_eq(pn.preview, -1, "the game hasn't browsed yet")
	assert_true(w.run_until(func() -> bool: return pn.preview == int(pn.drawn[1]), 600), "the same one, later")
	var hashes := w.compare_hashes()
	assert_true(hashes["ok"], str(hashes["why"]))
	w.free_all()


## The rink's pause menu: the client's P2 pauses; its moves on the menu
## show at once, the game's later.
func test_the_pause_menu_shows_the_clients_moves_at_once() -> void:
	var net_match_test: Variant = load("res://test/net/test_net_match.gd")
	var w := Machines.new(self, 45, {"delay": ONE_WAY}, [1])
	for m in w.machines:
		for p in m.bot.players:
			m.bot.game_bots[p] = Bots.GameBot.new(p, 45)     # (the period's start waits for play)
	w.start(net_match_test.matchup_record(w, {1: 0, 2: 1}, [1, 2]))
	var c := w.machine(1)
	assert_true(w.run_until(func() -> bool:
		for m in w.machines:
			if not m.router.current_id() in [4, 5, 6] or m.router.busy():
				return false
		return true, 9000), "both on the rink")
	w.run(120)
	var rink := func() -> MwRink: return c.router.current() as MwRink    # (each rink entry a scene of its own)
	var paused := func() -> bool:
		var latest: MwRink = rink.call()
		return latest != null and latest.phases != null and latest.phases.paused and not latest.phases.menu.is_empty()
	for i in 15:                              # (a press each second until the game pauses)
		if paused.call():
			break
		c.bot.presses.append([c.router.tick + 1, 2, "p2_pause", 4])
		w.run(60)
	assert_true(w.run_until(paused, 300), "P2 paused (the game's)")
	w.run(5)
	var scene: MwRink = rink.call()
	assert_eq(int(scene.phases.menu["player"]), 2, "P2's pause menu")
	var sel := int(scene.phases.menu["sel"])
	_press(c, 2, "ui_down")
	w.run(3)
	assert_eq(int(scene.pause_menu.shown["sel"]), sel + 1, "the highlight moved at once")
	assert_eq(int(scene.phases.menu["sel"]), sel, "the game's menu not yet")
	assert_true(w.run_until(func() -> bool: return int(scene.phases.menu["sel"]) == sel + 1, 600), "the game's, later")
	w.run(3)
	assert_eq(int(scene.pause_menu.shown["sel"]), sel + 1, "and still shown there")
	var hashes := w.compare_hashes()
	assert_true(hashes["ok"], str(hashes["why"]))
	w.free_all()
