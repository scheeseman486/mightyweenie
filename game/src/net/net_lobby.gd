class_name MwNetLobby
extends RefCounted
## The lobby (plan 35 section 2): the machines in the game and their
## players. The host's is the real one ([MwNetHost] changes it and sends it
## whenever it changes); each client keeps a copy ([method load_wire] from
## the host's LOBBY messages). The lobby page (122, work item 3) draws the
## rows from [member players] and [member machines] and listens to the
## signals. Node-free.
##
## * A machine: its id (0 is the host's), its address, whether it is still
##   connected (a machine that drops while a match runs keeps its players
##   for a rejoin, section 5), its ping.
## * A player: their number (1-12, the colour, MwPlayerColours), their
##   machine, which of that machine's local players they are (local 1, 2
##   ... - which bindings they use), and the device kind the page draws a
##   glyph for (a byte the pages define).
## * Numbers [proposed]: the lowest free number, so in join order and a
##   freed number goes to the next joiner; nobody is renumbered. The host's
##   first player is P1. Twelve at most.
## * A machine's first player (local 1) can't leave on their own - their
##   Back is EXIT LOBBY / CLOSE LOBBY (section 2) - so [method leave]
##   refuses them; removing the machine frees all its numbers.

## Something in the lobby changed (after the specific signals); [method set_ping] doesn't emit it.
signal changed
## Player [param number] joined.
signal player_joined(number: int)
## Player [param number] left (or their machine was removed).
signal player_left(number: int)
## Machine [param id] joined.
signal machine_joined(id: int)
## Machine [param id] left (after its players' [signal player_left]).
signal machine_left(id: int)
## The lobby's [member state] became [param state] (a [enum State]).
signal state_changed(state: int)

enum State { OPEN, RUNNING, CLOSED }
const MAX_PLAYERS := MwVerbs.PLAYERS
const HOST_MACHINE := 0

var state := State.OPEN
var match_id := 0
## id -> {id, address, host, connected, ping}
var machines := {}
## number -> {number, machine, local, device}
var players := {}


## Adds a machine at [param address]; its id (the lowest free; 0 for the
## host), or -1 when every id is taken.
func add_machine(address: String, host := false) -> int:
	for id in range(0 if host else 1, MwNetProtocol.MAX_MACHINE + 1):
		if not machines.has(id):
			machines[id] = {"id": id, "address": address, "host": host, "connected": true, "ping": 0}
			machine_joined.emit(id)
			changed.emit()
			return id
	return -1


## Removes machine [param id] and its players; the numbers freed.
func remove_machine(id: int) -> Array[int]:
	var freed: Array[int] = []
	if not machines.has(id):
		return freed
	for n in numbers_of(id):
		players.erase(n)
		freed.append(n)
		player_left.emit(n)
	machines.erase(id)
	machine_left.emit(id)
	changed.emit()
	return freed


## Marks machine [param id] as connected or dropped ([param on]); its players stay either way.
func set_connected(id: int, on: bool) -> void:
	if machines.has(id) and bool(machines[id]["connected"]) != on:
		machines[id]["connected"] = on
		changed.emit()


## Sets a machine's ping; true when it changed by [param threshold] ms or
## more (worth sending).
func set_ping(id: int, ms: int, threshold := 0) -> bool:
	if not machines.has(id):
		return false
	var was := int(machines[id]["ping"])
	if absi(was - ms) <= threshold and threshold > 0:
		return false
	machines[id]["ping"] = ms
	return was != ms


## Moves the lobby to another [enum State], signalling [signal state_changed] and [signal changed]
## when it is a change.
func set_state(new_state: int) -> void:
	if state != new_state:
		state = new_state
		state_changed.emit(new_state)
		changed.emit()


## Players still free.
func free_slots() -> int:
	return MAX_PLAYERS - players.size()


## The lowest free player number (0: full).
func next_number() -> int:
	for n in range(1, MAX_PLAYERS + 1):
		if not players.has(n):
			return n
	return 0


## Machine [param machine]'s local player [param local] (1-12) joins with a
## [param device]; their number, or 0 (full, no such machine, or that local
## player already in).
func join(machine: int, local: int, device := 0) -> int:
	if not machines.has(machine) or local < 1 or local > MAX_PLAYERS or player_of(machine, local) != 0:
		return 0
	var n := next_number()
	if n == 0:
		return 0
	players[n] = {"number": n, "machine": machine, "local": local, "device": device}
	player_joined.emit(n)
	changed.emit()
	return n


## Player [param number] leaves (not a machine's first player); false when
## they can't.
func leave(number: int) -> bool:
	if not players.has(number) or int(players[number]["local"]) == 1:
		return false
	players.erase(number)
	player_left.emit(number)
	changed.emit()
	return true


## Machine [param machine]'s player numbers, ascending.
func numbers_of(machine: int) -> Array[int]:
	var out: Array[int] = []
	for n in range(1, MAX_PLAYERS + 1):
		if players.has(n) and int(players[n]["machine"]) == machine:
			out.append(n)
	return out


## The player who is machine [param machine]'s local [param local] (0: none).
func player_of(machine: int, local: int) -> int:
	for n in players:
		if int(players[n]["machine"]) == machine and int(players[n]["local"]) == local:
			return n
	return 0


## The machine player [param number] plays on (-1: nobody has that number).
func machine_of(number: int) -> int:
	return int(players[number]["machine"]) if players.has(number) else -1


## Machine [param machine]'s players as a player mask (number n: bit n - 1).
func mask_of(machine: int) -> int:
	var m := 0
	for n in numbers_of(machine):
		m |= 1 << (n - 1)
	return m


## Every player number, ascending.
func numbers() -> Array[int]:
	var out: Array[int] = []
	for n in range(1, MAX_PLAYERS + 1):
		if players.has(n):
			out.append(n)
	return out


## The lobby as MwNetProtocol.write_lobby takes it.
func to_wire() -> Dictionary:
	var ms := []
	var ids := machines.keys()
	ids.sort()
	for id in ids:
		ms.append((machines[id] as Dictionary).duplicate())
	var ps := []
	for n in numbers():
		ps.append((players[n] as Dictionary).duplicate())
	return {"state": MwNetProtocol.Lobby.RUNNING if state == State.RUNNING else MwNetProtocol.Lobby.OPEN,
			"match": match_id, "machines": ms, "players": ps}


## Takes the host's lobby (a decoded LOBBY), signalling what changed.
func load_wire(d: Dictionary) -> void:
	var new_machines := {}
	for m: Dictionary in d.get("machines", []):
		new_machines[int(m["id"])] = m.duplicate()
	var new_players := {}
	for player: Dictionary in d.get("players", []):
		new_players[int(player["number"])] = player.duplicate()
	var left := []
	for n in players:
		if not new_players.has(n) or int(new_players[n]["machine"]) != int(players[n]["machine"]):
			left.append(n)
	var joined := []
	for n in new_players:
		if not players.has(n) or n in left:
			joined.append(n)
	var gone := []
	for id in machines:
		if not new_machines.has(id):
			gone.append(id)
	var came := []
	for id in new_machines:
		if not machines.has(id):
			came.append(id)
	var was_state := state
	var was := to_wire()
	machines = new_machines
	players = new_players
	match_id = int(d.get("match", 0))
	state = State.RUNNING if int(d.get("state", 0)) == MwNetProtocol.Lobby.RUNNING else State.OPEN
	for n in left:
		player_left.emit(n)
	for id in gone:
		machine_left.emit(id)
	for id in came:
		machine_joined.emit(id)
	for n in joined:
		player_joined.emit(n)
	if state != was_state:
		state_changed.emit(state)
	if to_wire() != was:
		changed.emit()
