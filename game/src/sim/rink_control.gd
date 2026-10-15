class_name MwRinkControl
extends RefCounted
## Plan 34 (section 7): who drives which skater beyond the original's rules -
## the players' owned positions (ownership), RECLAIM, the captains' powers,
## everyone else's own menu, QUIT GAME and REJOIN. A port layer of the rink's
## simulation, node-free, kept in the match's state ([member
## MwRinkState.control]) and run at the start of every rink pass ([method
## pass_start], from MwRinkSim.run) in player-number order, so it is
## deterministic (plan 35 runs it over the network): the menus are inputs
## only; QUIT GAME and REJOIN are events here.
##
## The original's control: each team's pads drive one skater each (+$74 bit
## 2; which pad: bit 3 and the team's two slot bytes +$66 / +$67 - plan 34's
## extended set-ups: the player object's [member MwRinkState.Player.pad]);
## control moves by the switch (`$1856`, B without the puck), when the game
## takes it (`$D1C`: killed, impaled, penalty, taken off), on a pass to a
## CPU-driven team-mate (`$53F0`: the passer follows the puck), when a
## CPU-driven team-mate picks up a loose puck (`$53F0`: one of the team's two
## pads in turn) and by Waste the Goalie (`$1DEC`). This layer adds:
##
## * **Seats** ([Seat]): every playing human (MwHumans: a team's players in
##   number order) with the pad the simulation reads for them - the
##   original's pad the router gives them (MwSession.pad_map) in the set-ups
##   the original could have had, their match pad in an extended one
##   (MwHumans.pad_index).
## * **Ownership** ([member owned]: positions picked on character selection,
##   which only an extended set-up has): each player owns a position (C, LW,
##   RW, LD, RD, G), whoever plays there. The faceoff line-up ([method
##   lineup]) puts everyone on their own position when it is on the ice,
##   else the original's choice (`$1856`'s best-placed CPU-driven team-mate),
##   else nobody. RECLAIM ([method reclaim]: the verb, or B tapped twice
##   within [constant TAP_TICKS] ticks without the puck with the GENESIS
##   layout) takes the own player back at any time: whoever drives it is
##   bumped to their own player if free, else the original's choice, else
##   they wait with nobody. When the game takes control from an owner on
##   their own player they get the original's choice, and return to their
##   own when it can be driven again ([method taken], [member Seat.back]) -
##   not when they had left it themselves. SWITCH and the pass are the
##   original's (owned or not); a loose puck picked up by a CPU-driven
##   team-mate moves nobody (MwHumanControl.pickup_switch: the original's
##   alternation would yank a player off their own); Waste the Goalie gives
##   the goalie as the original does, and its owner can reclaim him.
## * **Away** ([method away]): a player who left with QUIT GAME ([member
##   Seat.out]) or has their own menu open drives nobody - the CPU drives
##   their skater (the AI thinks for every skater without +$74 bit 2) - and
##   their pad's bytes reach nothing in the game. A faceoff line-up leaves
##   them out ([method after_lineup]). Coming back ([method _come_back]: the
##   menu closed, REJOIN): an owner as a RECLAIM; without owners the skater
##   they left if the CPU still drives him, else the original's choice, else
##   nobody until the next line-up. Their position stays theirs, open to
##   switches like any CPU-driven player's.
## * **Captains** ([member captain_mode]: MwHumans.captains non-zero, voted
##   before the match - local playoff games from CAPTAIN MODE's number of
##   players, online games): only the captain's Start pauses (the port's
##   pause menu and everything behind it); another player's Start opens
##   their own menu ([method open_menu]: RESUME, QUIT GAME - ARE YOU SURE? -
##   and after QUIT GAME, REJOIN), which never pauses. A captain leaving
##   passes the captaincy to the team's lowest-numbered player still in, and
##   it comes back when they rejoin ([method _recaptain]). Only captains'
##   presses count on the special plays screen and the scoreboards' menus
##   ([method screen_pads]). Without captains Start pauses for anyone (the
##   original). The pause menu has no QUIT GAME (owner, 2026-10-10: only a
##   spectated CPU v CPU match's, which stops the match - MwRinkPhases.QUIT;
##   plan 34 had it hand the pausing player's spot to the CPU), so leaving
##   is the own menus' alone: a captain doesn't leave (online their machine
##   going away passes the captaincy on all the same) and without captains
##   nobody does; a player out (a [method request]) gets their own menu
##   with REJOIN.
## * **A team with nobody left in** ([method anyone_in]): the CPU team's
##   decisions (MwRinkState.has_players: line changes and special plays at
##   the line-up, the coach's speeches, the special plays page, the fight)
##   until someone rejoins - the team's +4 bit 2 itself stays (the replay
##   ring's frames read it). Nothing waits on it: its coach's speech (team
##   A's always speaks) is the other team's players' to skip
##   (MwRinkPhases.speech), whoever answers for the match where the
##   original reads pad 1 alone is someone still in ([method first_seat]),
##   and with everyone out the screens between plays read every pad as in
##   the original's CPU v CPU match ([method screen_pads]).
##
## * **Online** (plan 35 work item 4, [method go_online]): a player whose
##   machine is away ([member Seat.net]: LAGGING, DISCONNECTED, KICKED - the
##   host's word, in the input stream: [method set_net]) is away like a
##   player who left: the CPU drives their skater, a captain's captaincy
##   passes on, and when their machine is back they come back as from their
##   menu. They count as gone wherever plan 34 tests who is still in
##   ([method anyone_in], [method lead_seat], [method reshaped], [method
##   everyone_out], [method first_seat], [method screen_pads]): the status
##   comes in the stream, so every machine decides alike at the same tick.
##   The host's players have PLAYERS in their menus (the pause menu,
##   their own): the remote machines ([method kick_list]), each KICKed
##   after ARE YOU SURE? ([member kicks]: the host's network carries it
##   out). A machine whose players have all left can DISCONNECT from their
##   own menu ([member leaving]: that machine leaves the match, its key kept).
##
## Without owners, captains or anyone away nothing here changes a thing: the
## set-ups the original could have had run the original's code exactly.

## How close (ticks) two B taps without the puck reclaim (the GENESIS
## layout, owner: a 3-button pad has no spare button).
const TAP_TICKS := 10
## The own menu's items.
const RESUME := "RESUME"
const QUIT := "QUIT GAME"
const REJOIN := "REJOIN"
## Plan 35 (online): the host's players' list of the remote machines, a
## machine's leaving, the list's way back and its question.
const PLAYERS := "PLAYERS"
const DISCONNECT := "DISCONNECT"
const BACK := "BACK"
const KICK := "KICK"
## The screens whose decisions are the captains' (with captains): the
## special plays / Reserves page and the scoreboards' menus.
const CAPTAIN_SCREENS: Array[int] = [10, 12, 13, 14, 15, 16, 17]
## A skater the return rule takes back ([member Seat.back]) is in play:
## below the injured state (`$D1C`'s injured, impaled, killed, fallen,
## entering from the bench).
const BACK_STATE := 0xF
## A skater a player can be given at all (`$1856`'s test: below impaled).
const DRIVABLE_STATE := 0x11
const START := 0x80
const B := 0x10

## One playing human.
class Seat:
	var player := 0          ## the port's player number (1-12)
	var team := 0            ## 0 team A, 1 team B
	## The pad the simulation reads for them: the original's pad 0-3 (the
	## router's pad map) or an extended set-up's match pad 0-11.
	var pad := -1
	## The original's control slot of [member pad] in the team's two slot
	## bytes (+$66 / +$67: +$74 bit 3), -1 in an extended set-up.
	var slot := -1
	var own := -1            ## the owned position (0-5, MwHumans.POSITIONS), -1 none
	var out := false         ## left with QUIT GAME (until REJOIN)
	## Their own menu while it is open: {"items", "sel", "confirm", "sure"}
	## (MwRinkPhases.menu's form); empty: closed.
	var menu := {}
	## The game took their own player from them (`$D1C`): they return to it
	## when it can be driven again.
	var back := false
	var last := -1           ## the team slot (players index) they left when they went away
	var taps := false        ## B tapped twice reclaims (the GENESIS layout)
	var tap := -1            ## the tick of the last B tap without the puck (-1 none)
	## Plan 35: their machine's network status (MwTickInput.HERE, LAGGING,
	## DISCONNECTED, KICKED): not here, the CPU drives their skater.
	var net := 0

	func away() -> bool:
		return out or net != 0 or not menu.is_empty()

	## Out of the game: left with QUIT GAME or their machine away (a
	## captaincy passes on, the team's decisions go to who is in).
	func gone() -> bool:
		return out or net != 0

## The seats in player-number order.
var seats: Array[Seat] = []
## Players own positions (an extended set-up with character selection).
var owned := false
## An extended set-up (MwRinkState.extended: who drives a skater is his
## [member MwRinkState.Player.pad]; else +$74 bit 3 and the slot bytes).
var extended := false
## Teams have captains (MwHumans.captains non-zero).
var captain_mode := false
## The captains as voted, and as they are now (a captain who left: the
## team's lowest-numbered player still in; 0: nobody).
var voted := [0, 0]
var captains := [0, 0]
## This pass's menu verbs, given by the scene before the pass: player ->
## {"up", "down", "select", "resume", "back": bool} for the players whose
## own menu is open (MwRink reads them as the pause menu's).
var verbs := {}
## Requests for the next pass (in the order asked): [player, kind] with kind
## "quit", "rejoin", "open", "close" (tests, live_match's --quit).
var requests: Array = []
## Plan 35 (online, [method go_online]): an online match's player table
## (player -> their machine, 0 the host's), every player's network status
## as the stream last said (player -> MwTickInput status), the machines
## the host's PLAYERS menu asked to kick this pass, and the machines whose
## DISCONNECT was picked this pass (the network acts on them; the lists
## start empty every pass).
var online := false
var machines := {}
var net_status := {}
var kicks: Array[int] = []
var leaving: Array[int] = []
var _s: MwRinkState


## The seats of [param humans] for a match: the pads as [param pad_map]
## (MwSession.pad_map: pads 1-4's players) gives them in the original's
## set-ups, the match pads in an extended one; [param rom] for the pad
## modes' slot bytes. Ownership needs an extended set-up (the original's two
## slots a team cannot carry owners; character selection never happens
## without one).
static func make(humans: MwHumans, pad_map: PackedInt32Array, rom: PackedByteArray) -> MwRinkControl:
	var control := MwRinkControl.new()
	var extended_setup := not humans.original()
	control.extended = extended_setup
	var mode := humans.pad_mode()
	var players := []
	for t in 2:
		for p: int in humans.teams[t]:
			players.append(p)
	players.sort()
	for p: int in players:
		var seat := Seat.new()
		seat.player = p
		seat.team = humans.team_of(p)
		if extended_setup:
			seat.pad = humans.pad_index(p)
		else:
			seat.pad = pad_map.find(p)
			for k in 2:
				var b: int = rom[MwRinkMatch.PAD_MODES + 4 * mode + 2 * seat.team + k]
				if b != 0xFF and b & 3 == seat.pad:
					seat.slot = k
		seat.own = int(humans.positions.get(p, -1)) if extended_setup else -1
		control.seats.append(seat)
	control.owned = extended_setup and humans.owners()
	for t in 2:
		control.voted[t] = humans.captain_of(t)
	control.captain_mode = control.voted[0] != 0 or control.voted[1] != 0
	control.captains = control.voted.duplicate()
	for p in humans.out:
		var seat := control.seat_of(int(p))
		if seat != null:
			seat.out = true
	for t in 2:
		control._recaptain(t)
	return control


## Plan 35: an online match ([param table]: MwSession.online - "machines":
## player (as a string) -> machine).
func go_online(table: Dictionary) -> void:
	online = not table.is_empty()
	machines = {}
	var ms: Dictionary = table.get("machines", {})
	for k in ms:
		machines[int(str(k))] = int(ms[k])


## The machine [param player] plays on online (-1: none).
func machine_of(player: int) -> int:
	return int(machines.get(player, -1))


## Plan 35: the players' network statuses as this pass's input says them
## ([param away]: player -> status, the others here; MwInputFrame.away).
## A seat going away drops their menu (the CPU drives their skater from
## their next pass, [method _step]); one coming back comes back at the next
## pass (as from their menu); captains follow.
func set_net(away: Dictionary) -> void:
	for p: int in machines:
		var code := int(away.get(p, 0))
		if int(net_status.get(p, 0)) == code:
			continue
		if code == 0:
			net_status.erase(p)
		else:
			net_status[p] = code
		var seat := seat_of(p)
		if seat == null:
			continue
		var was := seat.net
		seat.net = code
		if code != 0:
			seat.menu = {}
			seat.back = false
			seat.tap = -1
		elif was != 0 and not seat.out:
			requests.append([p, "back"])
		_recaptain(seat.team)


## Plan 35: the remote machines the host's PLAYERS list offers to kick
## (those with a player not kicked yet), ascending: [{machine, label}] -
## the label its players' numbers ("P2+P3").
func kick_list() -> Array:
	var by := {}
	for p: int in machines:
		var m := int(machines[p])
		if m <= 0:
			continue
		if not by.has(m):
			by[m] = []
		by[m].append(p)
	var ids := by.keys()
	ids.sort()
	var out := []
	for m: int in ids:
		var ps: Array = by[m]
		ps.sort()
		var all_kicked := true
		var names := PackedStringArray()
		for p: int in ps:
			names.append("P%d" % p)
			all_kicked = all_kicked and int(net_status.get(p, 0)) == MwTickInput.KICKED
		if not all_kicked and not m in kicks:
			out.append({"machine": m, "label": "+".join(names)})
	return out


## Plan 35: menu [param m] (the pause menu's or an own menu's form) shows
## the PLAYERS list: the remote machines, then BACK.
func open_players(m: Dictionary) -> void:
	var list := kick_list()
	m["main"] = (m["items"] as Array).duplicate()
	m["main_sel"] = int(m["sel"])
	var items := []
	var targets := []
	for entry: Dictionary in list:
		items.append(entry["label"])
		targets.append(int(entry["machine"]))
	items.append(BACK)
	m["items"] = items
	m["targets"] = targets
	m["sel"] = 0
	m["players"] = true


## Back from the PLAYERS list to [param m]'s own items.
func close_players(m: Dictionary) -> void:
	if not m.get("players", false):
		return
	m["items"] = m["main"]
	m["sel"] = m["main_sel"]
	for k in ["main", "main_sel", "targets", "players", "ask", "target"]:
		m.erase(k)
	m["confirm"] = false


## The PLAYERS list's select on [param m]: BACK closes it; a machine asks
## ARE YOU SURE? (NO first) before [method kick].
func players_select(m: Dictionary) -> void:
	var i := int(m["sel"])
	var targets: Array = m.get("targets", [])
	if i >= targets.size():
		close_players(m)
		return
	m["confirm"] = true
	m["ask"] = KICK
	m["target"] = int(targets[i])
	m["sure"] = 1


## KICK machine [param machine] (the host's network carries it out).
func kick(machine: int) -> void:
	if not machine in kicks:
		kicks.append(machine)


## The items of [param seat]'s own menu: RESUME and QUIT GAME, or for a
## player who left REJOIN and RESUME; online the host's players' PLAYERS,
## and DISCONNECT once every player of the seat's machine has left.
func own_items(seat: Seat) -> Array:
	var items := [REJOIN, RESUME] if seat.out else [RESUME, QUIT]
	if online and machine_of(seat.player) == 0:
		items.append(PLAYERS)
	elif online and seat.out and machine_of(seat.player) > 0:
		var all_out := true
		for other in seats:
			if machine_of(other.player) == machine_of(seat.player) and not other.out:
				all_out = false
		if all_out:
			items.append(DISCONNECT)
	return items


## Players still out (QUIT GAME) when a game ended ([member MwHumans.out])
## start the next controller selection in the middle (MwFlow.before_match).
static func out_to_middle(humans: MwHumans) -> void:
	for p in humans.out.keys():
		humans.set_team(int(p), MwHumans.MIDDLE)
	humans.out = {}


## The pad (1-12, as the screens read them: the router's pad map in the
## set-ups the original could have had, else the player's own) of team
## [param t]'s captain in [param humans] - 0: no captain. Between playoff
## games the run's screens answer team A's captain as well as P1.
static func captain_screen_pad(humans: MwHumans, pad_map: PackedInt32Array, t := 0) -> int:
	var c := humans.captain_of(t)
	if c == 0:
		return 0
	if not humans.original():
		return c
	var k := pad_map.find(c)
	return k + 1 if k >= 0 else 0


## The seat of player [param player] (null: not playing).
func seat_of(player: int) -> Seat:
	for seat in seats:
		if seat.player == player:
			return seat
	return null


## The seat the simulation reads on pad [param pad] (null: none).
func seat_on_pad(pad: int) -> Seat:
	for seat in seats:
		if seat.pad == pad:
			return seat
	return null


## The players who left with QUIT GAME (MwHumans.out's form).
func out_players() -> Dictionary:
	var out := {}
	for seat in seats:
		if seat.out:
			out[seat.player] = true
	return out


## Whether team [param t] has a player still in (a team without seats:
## true - the original's own test, the team's +4 bit 2, decides).
func anyone_in(t: int) -> bool:
	var any := false
	for seat in seats:
		if seat.team == t:
			if not seat.gone():
				return true
			any = true
	return not any


## Player [param player] (in or out) asks for [param kind] at the next pass:
## "quit", "rejoin", "open" (their own menu), "close".
func request(player: int, kind: String) -> void:
	requests.append([player, kind])


## The open own menus, in player-number order: [{player, team, menu, pad}].
func menus() -> Array:
	var out := []
	for seat in seats:
		if not seat.menu.is_empty():
			out.append({"player": seat.player, "team": seat.team, "menu": seat.menu, "pad": seat.pad})
		elif seat.net != 0:
			# plan 35: a player whose machine is away - P7 LAGGING (no items)
			out.append({"player": seat.player, "team": seat.team, "pad": seat.pad,
					"menu": {"items": [], "note": MwTickInput.STATUS_TEXT[clampi(seat.net, 0, 3)]}})
	return out


# --- the pass ------------------------------------------------------------------------------------

## The start of a rink pass (MwRinkSim.run, after the pads are read into the
## state): each seat in player-number order - its requests, its own menu's
## verbs ([member verbs]), Start (the own menu's, where it doesn't pause),
## the pads of the away kept from the game, RECLAIM, a waiting player's
## switch, the return to an own player.
func pass_start(sim: MwRinkSim) -> void:
	_s = sim.s
	var asked := requests
	requests = []
	kicks = []
	leaving = []
	for seat in seats:
		for r: Array in asked:
			if int(r[0]) == seat.player:
				_requested(sim, seat, str(r[1]))
		_step(sim, seat)
	verbs = {}


func _requested(sim: MwRinkSim, seat: Seat, kind: String) -> void:
	match kind:
		"quit":
			if not seat.out:
				_quit(sim, seat)
		"rejoin":
			if seat.out:
				_rejoin(sim, seat)
		"open":
			if seat.menu.is_empty():
				open_menu(sim, seat)
		"close":
			if not seat.menu.is_empty():
				close_menu(sim, seat)
		"back":
			if not seat.away():
				_come_back(sim, seat)                  # plan 35: their machine is back


func _step(sim: MwRinkSim, seat: Seat) -> void:
	var s := _s
	var pad := seat.pad
	if pad < 0 or pad >= s.pads_new.size():
		return
	if seat.net != 0:
		_keep_out(sim, seat)                           # plan 35: their machine is away
		return
	var was_open := not seat.menu.is_empty()
	var handled := false
	if was_open and verbs.has(seat.player):
		handled = _menu_verbs(sim, seat, verbs[seat.player])
	var start := s.pads_new[pad] & START != 0
	if start and not handled and (seat.out or (captain_mode and captains[seat.team] != seat.player)):
		if was_open:
			if not seat.menu.is_empty():
				close_menu(sim, seat)                  # Start resumes
		else:
			open_menu(sim, seat)
	if seat.away():
		_keep_out(sim, seat)
		return
	if captain_mode and captains[seat.team] != seat.player:
		s.pads_held[pad] &= ~START                     # their Start is their own menu's
		s.pads_new[pad] &= ~START
	var direct: Array = sim.human.direct[pad] if pad < sim.human.direct.size() else []
	var reclaim := direct.has(MwVerbs.RECLAIM)
	direct.erase(MwVerbs.RECLAIM)
	var tapped := s.pads_new[pad] & B != 0 or direct.has("change_player")
	var driven := driven_by(seat)
	if owned:
		var carrier := driven != null and s.puck.flags & MwRinkState.Puck.CARRIED and s.puck.carrier == driven
		if seat.taps and tapped and not carrier:
			if seat.tap >= 0 and (s.tick - seat.tap) & 0xFFFFFFFF <= TAP_TICKS:
				reclaim = true
				_consume_b(sim, seat)                  # the second tap reclaims, it doesn't switch again
				tapped = false
				seat.tap = -1
			else:
				seat.tap = s.tick & 0xFFFFFFFF
		if reclaim:
			reclaim_seat(sim, seat)
			driven = driven_by(seat)
	if driven == null and tapped:
		# B (or CHANGE PLAYER) with nobody to drive: the original's choice, as a switch would
		var p := sim.human.best_mate(s.teams[seat.team], null)
		if p != null:
			_drive(sim, seat, p)
		_consume_b(sim, seat)
	if owned and seat.back:
		var own := own_player(seat)
		if own != null and own.state < BACK_STATE and not own.flags & MwRinkState.Player.HUMAN:
			_drive(sim, seat, own)
			seat.back = false


## A B press of [param seat]'s pad taken out of this pass (the pad byte and
## a CHANGE PLAYER bound alone).
func _consume_b(sim: MwRinkSim, seat: Seat) -> void:
	_s.pads_new[seat.pad] &= ~B
	if seat.pad < sim.human.direct.size():
		(sim.human.direct[seat.pad] as Array).erase("change_player")


## An away player's pad reaches nothing in the game (its bytes, stick,
## meanings and tap / hold timer), and they drive nobody.
func _keep_out(sim: MwRinkSim, seat: Seat) -> void:
	var s := _s
	var pad := seat.pad
	s.pads_held[pad] = 0
	s.pads_new[pad] = 0
	if pad < s.pad_sticks.size():
		s.pad_sticks[pad] = Vector2i.ZERO
	if pad < s.pad_heights.size():
		s.pad_heights[pad] = -1
	if pad < sim.human.direct.size():
		sim.human.direct[pad] = []
	if pad < s.hold_left.size():
		s.hold_left[pad] = 0
	_free(seat)


# --- the own menus -------------------------------------------------------------------------------

## Opens [param seat]'s own menu: RESUME and QUIT GAME, or for a player
## who left REJOIN and RESUME; the CPU drives their skater while it is open.
func open_menu(sim: MwRinkSim, seat: Seat) -> void:
	var items := own_items(seat)
	seat.menu = {"items": items, "sel": 0, "confirm": false, "sure": 1, "player": seat.player}
	if not seat.out:
		_free(seat)
	if sim != null:
		sim.sound(MwRinkPhases.MENU_MOVE)


## Closes [param seat]'s own menu; a player still in comes back.
func close_menu(sim: MwRinkSim, seat: Seat) -> void:
	seat.menu = {}
	if not seat.out:
		_come_back(sim, seat)


## [param seat]'s own menu's verbs [param v] ("up", "down", "select",
## "resume", "back"): as the pause menu's (MwRinkPhases.menu_press) - Up /
## Down move (wrapping), select picks: RESUME closes the menu, QUIT GAME
## asks ARE YOU SURE? (NO first; YES quits), REJOIN rejoins; Start and Back
## close it (on ARE YOU SURE?: back to the menu). Returns whether a verb
## acted.
func _menu_verbs(sim: MwRinkSim, seat: Seat, v: Dictionary) -> bool:
	var m := seat.menu
	var items: Array = m["items"]
	if m["confirm"]:
		match MwMenuDict.confirm_verbs(m, v):                 # plan 40 (M4)
			MwMenuDict.MOVED:
				sim.sound(MwRinkPhases.MENU_MOVE)
			MwMenuDict.YES:
				if m.get("ask", "") == KICK:
					kick(int(m["target"]))
					close_players(m)
				else:
					_quit(sim, seat)
			MwMenuDict.NO:
				m["confirm"] = false
			MwMenuDict.NONE:
				return false
		return true
	if m.get("players", false) and (v.get("resume", false) or v.get("back", false)):
		close_players(m)                               # back from the list to the menu
		sim.sound(MwRinkPhases.MENU_MOVE)
		return true
	if v.get("resume", false) or v.get("back", false):
		close_menu(sim, seat)
	elif MwMenuDict.move(m, v):
		sim.sound(MwRinkPhases.MENU_MOVE)
	elif v.get("select", false):
		if m.get("players", false):
			players_select(m)
			sim.sound(MwRinkPhases.MENU_MOVE)
			return true
		match str(items[int(m["sel"])]):
			RESUME:
				close_menu(sim, seat)
			QUIT:
				m["confirm"] = true
				m["ask"] = QUIT
				m["sure"] = 1
			REJOIN:
				_rejoin(sim, seat)
			PLAYERS:
				open_players(m)
				sim.sound(MwRinkPhases.MENU_MOVE)
			DISCONNECT:
				var mach := machine_of(seat.player)
				if not mach in leaving:
					leaving.append(mach)
				close_menu(sim, seat)
	else:
		return false
	return true


# --- QUIT GAME and REJOIN ---------------------------------------------------------------------------

## QUIT GAME: the CPU drives their skater until they rejoin; their position
## stays theirs; a captain's captaincy passes on.
func _quit(_sim: MwRinkSim, seat: Seat) -> void:
	seat.menu = {}
	seat.out = true
	seat.back = false
	seat.tap = -1
	_free(seat)
	_recaptain(seat.team)


## REJOIN: in again - an owner on their own position (as a RECLAIM), else
## as from their menu - and a voted captain captain again.
func _rejoin(sim: MwRinkSim, seat: Seat) -> void:
	seat.menu = {}
	seat.out = false
	_recaptain(seat.team)
	_come_back(sim, seat)


## Team [param t]'s captain now: the voted one while in, else the team's
## lowest-numbered player still in, else nobody (0).
func _recaptain(t: int) -> void:
	if not captain_mode:
		return
	var v: int = voted[t]
	var vs := seat_of(v)
	if vs != null and not vs.gone():
		captains[t] = v
		return
	captains[t] = 0
	for seat in seats:
		if seat.team == t and not seat.gone():
			captains[t] = seat.player
			return


## A player back in play (their menu closed, REJOIN): an owner on their own
## player as a RECLAIM when it is on the ice (else they return to it when it
## is: [member Seat.back]); otherwise the skater they left if the CPU still
## drives him, else the original's choice (`$1856`), else nobody.
func _come_back(sim: MwRinkSim, seat: Seat) -> void:
	if driven_by(seat) != null:
		return
	if owned and seat.own >= 0:
		if reclaim_seat(sim, seat):
			return
		seat.back = true
	var team := _s.teams[seat.team]
	var p: MwRinkState.Player = null
	if seat.last >= 0 and seat.last < team.players.size():
		var q := team.players[seat.last]
		if q.present and q.state < DRIVABLE_STATE and not q.flags & MwRinkState.Player.HUMAN:
			p = q
	if p == null:
		p = sim.human.best_mate(team, null)
	if p != null:
		_drive(sim, seat, p)


# --- ownership ----------------------------------------------------------------------------------------

## [param seat]'s own player: the team's skater on the ice at their
## position (null: none there, or no position).
func own_player(seat: Seat) -> MwRinkState.Player:
	if seat.own < 0:
		return null
	for q in _s.teams[seat.team].players:
		if q.present and q.position == seat.own:
			return q
	return null


## The seat owning team [param t]'s position [param pos] (null: nobody).
func owner_of(t: int, pos: int) -> Seat:
	if not owned:
		return null
	for seat in seats:
		if seat.team == t and seat.own == pos:
			return seat
	return null


## RECLAIM: [param seat] back on their own player (on the ice, below the
## impaled state); whoever drove it is bumped ([method _bump]). False when
## the own player can't be had.
func reclaim_seat(sim: MwRinkSim, seat: Seat) -> bool:
	if seat.away():
		return false
	var own := own_player(seat)
	if own == null or own.state >= DRIVABLE_STATE:
		return false
	seat.back = false
	if driven_by(seat) == own:
		return true
	var other := driver_of(own)
	_drive(sim, seat, own)
	if other != null and other != seat:
		_bump(sim, other)
	return true


## [param seat], bumped off a skater: to their own player if no-one drives
## it, else the original's choice (`$1856`), else they wait with nobody.
func _bump(sim: MwRinkSim, seat: Seat) -> void:
	var mine := own_player(seat)
	if mine != null and mine.state < DRIVABLE_STATE and not mine.flags & MwRinkState.Player.HUMAN:
		_drive(sim, seat, mine)
		seat.back = false
		return
	var p := sim.human.best_mate(_s.teams[seat.team], null)
	if p != null:
		_drive(sim, seat, p)


## `$D1C` (MwHumanControl.lose_control) is about to hand [param p]'s control
## on: an owner losing their own player returns to it later.
func taken(p: MwRinkState.Player) -> void:
	if not owned or not p.flags & MwRinkState.Player.HUMAN:
		return
	var seat := driver_of(p)
	if seat != null and seat.own == p.position:
		seat.back = true


## The faceoff line-up of [param team] with owners (`$3A28`'s pad part, the
## players placed and nobody driving): everyone in on their own position
## if it is on the ice, in player-number order; then the rest the
## original's choice (`$1856`), in player-number order; else nobody. No
## random draw.
func lineup(sim: MwRinkSim, team: MwRinkState.Team) -> void:
	_s = sim.s
	var t := _s.teams.find(team)
	var rest: Array[Seat] = []
	for seat in seats:
		if seat.team != t:
			continue
		seat.tap = -1
		if seat.away():
			seat.back = false
			continue
		_drop_stale(seat)
		var own := own_player(seat)
		if own != null and own.state < DRIVABLE_STATE and not own.flags & MwRinkState.Player.HUMAN:
			_drive(sim, seat, own)
			seat.back = false
		else:
			seat.back = seat.own >= 0
			rest.append(seat)
	for seat in rest:
		var p := sim.human.best_mate(team, null)
		if p != null:
			_drive(sim, seat, p)


## After `$3A28` lined [param team] up: the away drive nobody (the CPU
## drives the skaters the line-up gave them).
func after_lineup(sim: MwRinkSim, team: MwRinkState.Team) -> void:
	_s = sim.s
	var t := _s.teams.find(team)
	for seat in seats:
		if seat.team == t and seat.away():
			_free(seat)
			seat.tap = -1


# --- who drives whom -------------------------------------------------------------------------------

## The skater on the ice [param seat] drives (null: nobody).
func driven_by(seat: Seat) -> MwRinkState.Player:
	for q in _s.teams[seat.team].players:
		if q.present and _drives(seat, q):
			return q
	return null


## The seat driving [param p] (null: the CPU).
func driver_of(p: MwRinkState.Player) -> Seat:
	if not p.flags & MwRinkState.Player.HUMAN:
		return null
	for seat in seats:
		if seat.team == p.team and _drives(seat, p):
			return seat
	return null


func _drives(seat: Seat, q: MwRinkState.Player) -> bool:
	if not q.flags & MwRinkState.Player.HUMAN:
		return false
	if extended:
		return q.pad == seat.pad
	return seat.slot == (1 if q.flags & MwRinkState.Player.SECOND_PAD else 0)


## [param seat] drives [param to] (`$1856`'s hand-over when they drove
## someone: the Player Blast goes along; else control alone).
func _drive(sim: MwRinkSim, seat: Seat, to: MwRinkState.Player) -> void:
	var from := driven_by(seat)
	if from == to:
		return
	_drop_stale(seat)
	if from != null:
		sim.human._switch(from, to)
		return
	to.flags |= MwRinkState.Player.HUMAN
	to.flags &= ~MwRinkState.Player.SECOND_PAD
	to.flags2 &= ~8
	if extended:
		to.pad = seat.pad
	elif seat.slot == 1:
		to.flags |= MwRinkState.Player.SECOND_PAD


## The CPU drives [param seat]'s skater (remembered for their return).
func _free(seat: Seat) -> void:
	var p := driven_by(seat)
	if p != null:
		seat.last = p.index
		p.flags &= ~MwRinkState.Player.HUMAN
	_drop_stale(seat)


## Control flags [param seat]'s pad left on players off the ice (the
## original keeps a human on a player leaving with nobody to hand over to):
## gone, so a substitute coming on can't bring a second driver.
func _drop_stale(seat: Seat) -> void:
	for q in _s.teams[seat.team].players:
		if not q.present and _drives(seat, q):
			q.flags &= ~MwRinkState.Player.HUMAN


# --- the screens between plays, the fight, the draws --------------------------------------------

## The pads screen [param screen] reads ([param held] / [param new], pad
## bytes by pad) as the players count there: a player who left presses
## nothing; with captains, only the captains on the special plays screen
## and the scoreboards' menus ([constant CAPTAIN_SCREENS]). With everyone
## out ([method everyone_out]) both teams are the CPU's, as in the
## original's CPU v CPU match, whose screens between plays read every pad
## as it is - so do these then, and a menu waiting for a press never waits
## for nobody (the special plays pages idle and the fights are the CPU's
## by themselves: MwRinkState.has_players, [method fight_pad]).
func screen_pads(screen: int, held: Array, new: Array) -> void:
	if everyone_out():
		return
	var keep := {}
	var only_captains := captain_mode and screen in CAPTAIN_SCREENS
	for seat in seats:
		if seat.pad < 0:
			continue
		if seat.gone() or (only_captains and captains[seat.team] != seat.player):
			keep[seat.pad] = false
		elif only_captains:
			keep[seat.pad] = true
	for pad in held.size():
		if keep.get(pad, not only_captains) == false:
			held[pad] = 0
			if pad < new.size():
				new[pad] = 0


## The pad (x 2, MwFightSim's form) that fights for team [param t]'s
## fighter [param p], given the original's choice [param pad2]: with
## captains or someone away, a fighter's driver when in, else the team's
## captain, else its lowest-numbered player still in; nobody in: the CPU
## (-1). Otherwise [param pad2] as it is.
func fight_pad(t: int, p: MwRinkState.Player, pad2: int) -> int:
	var any_away := false
	var any := false
	for seat in seats:
		if seat.team == t:
			any = true
			any_away = any_away or seat.away()
	if not any or not (captain_mode or any_away):
		return pad2
	var driver := driver_of(p)
	if driver != null and not driver.away():
		return driver.pad * 2
	var lead := lead_seat(t)
	return lead.pad * 2 if lead != null else -1


## Team [param t]'s deciding player: its captain, else (no captains) its
## lowest-numbered player still in; null: nobody in.
func lead_seat(t: int) -> Seat:
	if captain_mode and captains[t] != 0:
		return seat_of(captains[t])
	for seat in seats:
		if seat.team == t and not seat.gone():
			return seat
	return null


## Whether who answers for the teams between plays differs from the
## original's pads: teams with captains, or a player gone (left with QUIT
## GAME, or their machine away: [method Seat.gone]).
func reshaped() -> bool:
	if captain_mode:
		return true
	for seat in seats:
		if seat.gone():
			return true
	return false


## Whether every player is gone (false without seats): left with QUIT GAME
## or their machine away - LAGGING too, as nobody can answer for them
## ([method Seat.gone], as [method screen_pads] counts them). Both teams are
## the CPU's then, as in the original's CPU v CPU match.
func everyone_out() -> bool:
	for seat in seats:
		if not seat.gone():
			return false
	return not seats.is_empty()


## The seat answering where the original reads its pad 1 alone (team A's
## first pad in every pad mode with a human: the message scoreboard's
## referee message): team A's deciding player ([method lead_seat]), else
## team B's. With nobody in at all, the first player whose machine is here
## (team A's, else team B's): one who left, whose pad counts again then
## ([method screen_pads]); else team A's first player, else team B's. Null:
## no seats.
func first_seat() -> Seat:
	for t in 2:
		var lead := lead_seat(t)
		if lead != null:
			return lead
	var first: Seat = null
	for t in 2:
		for seat in seats:
			if seat.team != t:
				continue
			if seat.net == 0:
				return seat
			if first == null:
				first = seat
	return first


## The pad of team [param t]'s captain now (-1: none).
func captain_pad(t: int) -> int:
	if not captain_mode or captains[t] == 0:
		return -1
	var seat := seat_of(captains[t])
	return seat.pad if seat != null else -1


## Plan 45: lets go of the state the passes worked on (it keeps this
## control layer: a reference cycle). For a match's state the game is done
## with ([method MwRinkState.retire]).
func release() -> void:
	_s = null


# --- the invariants (tests) ---------------------------------------------------------------------------

## The invariants of [param s] (tests): a player drives at most one skater,
## a skater has at most one driver - and is a seat's of his team - and the
## away drive nobody. "" when they hold, else what broke.
func check(s: MwRinkState) -> String:
	_s = s
	for seat in seats:
		var n := 0
		for q in s.teams[seat.team].players:
			if q.present and _drives(seat, q):
				n += 1
		if n > 1:
			return "player %d drives %d skaters" % [seat.player, n]
		if n > 0 and seat.away():
			return "player %d drives a skater while away" % seat.player
	for t in 2:
		for q in s.teams[t].players:
			if not q.present or not q.flags & MwRinkState.Player.HUMAN:
				continue
			var drivers := 0
			for seat in seats:
				if seat.team == t and _drives(seat, q):
					drivers += 1
			if drivers != 1:
				return "team %d's skater %d (position %d) has %d drivers" % [t, q.index, q.position, drivers]
	return ""
