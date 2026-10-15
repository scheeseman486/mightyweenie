extends "res://test/net/net_test_base.gd"
## Plan 45 (the audit's M2): a client's game shows only the screens an
## online match shows (MwNetMatch.ONLINE_SCREENS) - not as the start
## record's first screen, a resync snapshot's or one the host's stream
## steers its game to (the port's own pages: REPLAYS, SAVED GAMES and their
## files, the options and their settings): the host is dropped there and the
## match ends with THE HOST SENT SOMETHING WRONG, the screen never entered.

const Machines := preload("res://test/net/net_machines.gd")


## Every test plays a game: pending without the ROM. Untyped like GutTest's.
func should_skip_script():
	return rom_or_skip()


func after_all() -> void:
	MwSettings.own_match_rules()
	super.after_all()


## A host and one client on the game options (screen 1, the host's record),
## [param entered] noting every screen the client's game enters.
func _on_the_game_options(seed_value: int, entered: Array[int]) -> Machines:
	var w := Machines.new(self, seed_value, {}, [1])
	var client := w.machines[1]
	client.router.screen_entered.connect(func(id: int, _visit: int, _tick: int, _prev: int) -> void:
		entered.append(id))
	w.start()
	var there := func() -> bool:
		return client.net_match != null and client.net_match.phase == MwNetMatch.Phase.PLAYING \
				and client.router.current_id() == 1 and not client.router.busy()
	assert_true(w.run_until(there, 900), "the client on the game options")
	w.run(30)
	return w


## The client's match over as a hostile host's should end: its host dropped,
## its key let go, ONLINE MULTIPLAYER next with the reason.
func _ended_on_the_host(w: Machines, what: String) -> void:
	var client := w.machines[1]
	assert_true(w.run_until(func() -> bool: return client.ended >= 0, 300), "%s: the match ended" % what)
	assert_eq(client.ended, MwNetMatch.End.PROTOCOL, "%s: THE HOST SENT SOMETHING WRONG" % what)
	assert_eq([client.service.client.state, client.service.client.fail],
			[MwNetClient.State.DONE, MwNetClient.Fail.PROTOCOL], "%s: the host dropped" % what)
	assert_eq(MwNetRejoin.read(), {}, "%s: its rejoin key let go" % what)
	assert_eq(client.router.pending_id(), MwFlow.ONLINE_MENU, "%s: on to ONLINE MULTIPLAYER" % what)


func test_a_start_record_begins_on_a_screen_an_online_match_shows() -> void:
	for screen in [1, 3]:
		var record := MwSession.new(3, 4).to_record(screen, 0)
		assert_false(MwNetMatch.decode_record(MwNetMatch.encode_record(record)).is_empty(), "screen %d" % screen)
	for screen in [0, 7, 11, MwScreens.FRONT_MENU, MwScreens.OPTIONS, MwScreens.VISUALS, MwScreens.SAVED_GAMES,
			MwScreens.REPLAYS, MwFlow.ONLINE_MENU, MwFlow.ONLINE_LOBBY, MwScreens.HOST_GAME,
			MwScreens.CREATE_A_TEAM, MwScreens.HOME_RINK, -1, 999]:
		var record := MwSession.new(3, 4).to_record(screen, 0)
		assert_eq(MwNetMatch.decode_record(MwNetMatch.encode_record(record)), {}, "screen %d: refused" % screen)
	for odd: Variant in ["1", 1.0, [1], null]:
		var record := MwSession.new(3, 4).to_record(1, 0)
		record["screen"] = odd
		assert_eq(MwNetMatch.decode_record(MwNetMatch.encode_record(record)), {}, "screen %s: refused" % str(odd))


func test_a_client_never_enters_a_screen_the_stream_strays_to() -> void:
	var entered: Array[int] = []
	var w := _on_the_game_options(51, entered)
	# what the host's P1 driving a port page would make the game ask for (no fade: at once)
	w.machines[1].router.go(MwScreens.REPLAYS, {}, false)
	_ended_on_the_host(w, "the stream")
	assert_false(MwScreens.REPLAYS in entered, "REPLAYS never entered")
	w.free_all()


func test_a_client_never_enters_a_snapshots_local_screen() -> void:
	var entered: Array[int] = []
	var w := _on_the_game_options(52, entered)
	var hosting := w.machines[0]
	hosting.enter()
	var d := MwNetSnapshot.capture(hosting.router, {"op": "go", "id": MwScreens.SAVED_GAMES, "data": {}},
			hosting.router.current_id(), hosting.net_match.base, hosting.net_match.input)
	hosting.leave()
	var n := hosting.net_match.stream_tick(hosting.router.tick)
	assert_ne(w.host.send_snapshot(1, n, MwNetSnapshot.to_bytes(d)), 0, "a snapshot entering SAVED GAMES sent")
	_ended_on_the_host(w, "the snapshot")
	assert_false(MwScreens.SAVED_GAMES in entered, "SAVED GAMES never entered")
	assert_eq(int(w.machines[1].net_match.stats["loaded"]), 0, "nothing taken up")
	w.free_all()
