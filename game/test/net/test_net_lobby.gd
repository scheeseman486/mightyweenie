extends "res://test/net/net_test_base.gd"
## Plan 35 work item 2: the lobby's model (MwNetLobby) the pages of work
## item 3 draw - numbers lowest-free and never renumbered, a machine's first
## player staying, machines' players leaving with them, and a client's copy
## signalling exactly what changed.


func test_numbers_and_machines() -> void:
	var lobby := MwNetLobby.new()
	assert_eq(lobby.add_machine("", true), 0, "the host's machine is 0")
	assert_eq(lobby.join(0, 1), 1, "the host's first player is P1")
	var m := lobby.add_machine("10.0.0.2")
	assert_eq(m, 1)
	assert_eq(lobby.join(m, 1, 3), 2)
	assert_eq(lobby.join(m, 2), 3)
	assert_eq(lobby.join(m, 2), 0, "a local player joins once")
	assert_eq(lobby.join(9, 1), 0, "no such machine")
	assert_eq(lobby.join(0, 2), 4)
	assert_false(lobby.leave(2), "a machine's first player stays (their Back is EXIT LOBBY)")
	assert_true(lobby.leave(3))
	assert_eq(lobby.numbers(), [1, 2, 4] as Array[int])
	assert_eq(lobby.join(0, 3), 3, "the freed number, lowest first")
	assert_eq(lobby.mask_of(0), 0b1101)
	assert_eq(lobby.machine_of(2), 1)
	assert_eq(lobby.player_of(0, 3), 3)
	assert_eq(lobby.remove_machine(m), [2] as Array[int], "its players go with it")
	assert_eq(lobby.free_slots(), 9)
	for i in 9:
		assert_ne(lobby.join(0, 4 + i), 0)
	assert_eq(lobby.join(0, 12), 0, "twelve at most")
	assert_eq(lobby.next_number(), 0)


func test_copy_signals_what_changed() -> void:
	var host := MwNetLobby.new()
	host.add_machine("", true)
	host.join(0, 1)
	var a := host.add_machine("10.0.0.2")
	host.join(a, 1)
	var copy := MwNetLobby.new()
	var heard := []
	copy.player_joined.connect(func(n: int) -> void: heard.append("+P%d" % n))
	copy.player_left.connect(func(n: int) -> void: heard.append("-P%d" % n))
	copy.machine_joined.connect(func(id: int) -> void: heard.append("+M%d" % id))
	copy.machine_left.connect(func(id: int) -> void: heard.append("-M%d" % id))
	copy.state_changed.connect(func(state: int) -> void: heard.append("state %d" % state))
	var changes := [0]
	copy.changed.connect(func() -> void: changes[0] += 1)
	copy.load_wire(MwNetProtocol.decode(MwNetProtocol.lobby(host.to_wire()))["lobby"])
	assert_eq(heard, ["+M0", "+M1", "+P1", "+P2"])
	assert_eq(copy.to_wire(), host.to_wire())
	heard.clear()
	copy.load_wire(host.to_wire())
	assert_eq(heard, [], "nothing changed, nothing heard")
	assert_eq(changes[0], 1)
	var b := host.add_machine("10.0.0.3")
	host.join(b, 1)
	host.remove_machine(a)
	host.set_state(MwNetLobby.State.RUNNING)
	copy.load_wire(host.to_wire())
	assert_eq(heard, ["-P2", "-M1", "+M2", "+P3", "state %d" % MwNetLobby.State.RUNNING],
			"one machine and its player gone, another come, the match on")
	assert_true(host.set_ping(b, 80))
	assert_false(host.set_ping(b, 83, 5), "small ping changes aren't worth sending")
