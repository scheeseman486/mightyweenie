extends RefCounted
## Plan 40 (T6): the scripted drivers the checks share - moved here verbatim
## from live_match.gd (its command line stays there), so a test or a tool
## preloads the bots without a SceneTree script: [MenuBot] (the menus'
## presses, a spectator leaving), [GameBot] (a human's gameplay pad from its
## own random stream: every check that plays a match depends on its draws -
## never change them), [method humans_of].

## The rink's screens (the menus' bot presses nothing there).
const RINK := [4, 5, 6]


## The pads: a press of [member button] for a few ticks some time after
## each screen entry, again while the screen stays (screens 7 / 8 / 10 /
## scoreboards / menus); nothing on the rink, the fight or the cutscene.
class MenuBot extends MwInputSource:
	var router: MwRouter
	## Plan 34: the playing humans' gameplay bots ([GameBot]; none: the menus only).
	var game_bots: Array = []
	var mask := 0
	var entered_at := 0
	var screen := -1
	var visits := {}
	var detours := 6
	var cpu := false
	var captains := false
	## Plan 34: who presses the menus past the game setup (--menus).
	var menu_players: Array = [1]
	## The shot heights (MwSettings.shot_heights' form, MwInputSource.heights):
	## every [member height_every] ticks on the rink each gameplay bot's
	## player holds the next height (-1 the D-pad's, 0 none, 1 high, 2 low);
	## 0: none (the option off).
	var height_every := 0
	var plan: Array = []          ## buttons still to press on this visit
	## --leave: the spectator who leaves (0 none), from which tick, the
	## presses still to make (verb, per-player), the press held now and when
	## it is let go, and whether QUIT GAME was picked.
	var leave_player := 0
	var leave_at := 0
	var leave_plan: Array = ["pause", "ui_down", "ui_down", "ui_accept", "ui_up", "ui_accept"]
	var leave_press := ""
	var leave_release := 0
	var left := false
	var next_at := 0
	var release_at := 0
	@warning_ignore("shadowed_global_identifier")   # a frozen name (docs/style.md N9): read by name elsewhere
	var log: Array = []

	func on_entered(id: int, _visit: int, router_tick: int, _prev: int) -> void:
		screen = id
		entered_at = router_tick
		visits[id] = int(visits.get(id, 0)) + 1
		plan = _plan(id, int(visits[id]))
		next_at = router_tick + _wait(id)
		mask = 0

	func on_resumed(id: int, _visit: int, router_tick: int) -> void:
		on_entered(id, 0, router_tick, -1)

	func _plan(id: int, visit: int) -> Array:
		match id:
			0, 1, 3, 11, 16, MwScreens.FRONT_MENU, MwScreens.PLAY_MODE, MwScreens.LOCAL_PLAY:
				return ["START"]
			12, 14, 17:
				if detours > 0 and visit % 2 == 1:
					detours -= 1
					# no special plays in CPU vs CPU: the screen's page B
					# has no pad then and never finishes (as on the original)
					var pick: Array = ["A", "C"] if cpu else ["A", "C", "B"]
					return [pick[(visit / 2) % pick.size()]]
				return ["START"]
			15:
				if detours > 0:
					detours -= 1
					return ["A"]
				return ["START"]
			7, 8, 10:
				return ["START"]
		return []

	func _wait(id: int) -> int:
		match id:
			12, 14, 15, 16, 17:
				return 700          # past the comment / the message and the menu's opening
			7, 8, 10:
				return 300
		return 120

	func tick() -> void:
		var t := router.tick
		_leave_tick(t)
		if mask != 0 and t >= release_at:
			mask = 0
			next_at = t + 240       # pressed again if the screen stays
		if mask == 0 and t >= next_at and screen not in RINK:
			var b: String = plan.pop_front() if not plan.is_empty() \
					else ("START" if screen in [0, 1, 3, 7, 8, 10, 11, 12, 14, 15, 16, 17, MwScreens.FRONT_MENU,
					MwScreens.PLAY_MODE, MwScreens.LOCAL_PLAY] else "")
			if b != "":
				mask = MwInputScript.PAD_BITS[b]
				release_at = t + 6
				log.append([t, screen, b])

	## --leave: the spectator's presses on the rink - Start in open play, then
	## the pause menu's Down, Down (QUIT GAME), accept, Up (YES), accept -
	## each held 4 ticks, 8 apart.
	func _leave_tick(t: int) -> void:
		if leave_player == 0 or left or screen not in RINK or t < leave_at:
			return
		if leave_press != "":
			if t >= leave_release:
				leave_press = ""
				leave_release = t + 8
			return
		if t < leave_release:
			return
		var rk := router.current() as MwRink
		if rk == null or rk.state == null or rk.phases == null:
			return
		var paused := rk.phases.paused
		if leave_plan[0] == "pause" and (paused or rk.state.phase != 0):
			return
		if leave_plan[0] != "pause" and not paused:
			return
		leave_press = leave_plan.pop_front()
		leave_release = t + 4
		log.append([t, screen, "P%d %s" % [leave_player, leave_press]])
		if leave_plan.is_empty():
			left = true

	func heights() -> Array:
		if height_every <= 0 or screen not in RINK or game_bots.is_empty():
			return []
		var out := []
		out.resize(MwVerbs.PLAYERS)
		out.fill(-1)
		@warning_ignore("integer_division")
		var step := router.tick / height_every
		for bot: GameBot in game_bots:
			out[bot.player - 1] = posmod(step + bot.player, 4) - 1
		return out

	func sample(contexts: Array) -> Dictionary:
		var out := {}
		if screen in RINK or screen == 18:
			for bot: GameBot in game_bots:
				out.merge(MwVerbs.pad_actions(bot.player, bot.mask(router.tick), contexts))
		if leave_press != "" and screen in RINK:
			out[MwVerbs.action(leave_player, "pause") if leave_press == "pause"
					else MwVerbs.menu_action(leave_player, leave_press)] = true
		if mask == 0:
			return out
		# special plays: every pad (a second page waits for its own player's Start);
		# plan 34, captains: every pad between plays too (only theirs count, and the
		# replay then answers the captain who asked for it)
		var all := screen == 10 or (captains and screen in [7, 8, 12, 13, 14, 15, 16, 17])
		var players := range(1, MwVerbs.PLAYERS + 1) if all else menu_players
		if screen in [0, 1] or screen >= MwScreens.FRONT_MENU:
			players = [1]                     # the host's screens (the game setup: P1's Start alone)
		elif screen in [15, 16] and not 1 in players:
			players = players + [1]           # SAVE REPLAY? is the host's question
		for p in players:
			out.merge(MwVerbs.pad_actions(p, mask, contexts))
		return out


## Plan 34: a human's gameplay pad - a direction held for a while, now and
## then B, C or A pressed for a few ticks (never Start), from its own
## random stream.
class GameBot:
	var player := 1
	var rng := RandomNumberGenerator.new()
	var dir := 0
	var turn_at := 0
	var button := 0
	var release_at := 0

	func _init(p: int, seed_value: int) -> void:
		player = p
		rng.seed = seed_value * 7919 + p

	## The pad bits held at [param t].
	func mask(t: int) -> int:
		if t >= turn_at:
			dir = [0, 0x01, 0x02, 0x04, 0x08, 0x05, 0x09, 0x06, 0x0A][rng.randi_range(0, 8)]
			turn_at = t + rng.randi_range(10, 90)
		if button != 0 and t >= release_at:
			button = 0
			release_at = t + rng.randi_range(8, 60)
		elif button == 0 and t >= release_at:
			button = [0x10, 0x20, 0x40][rng.randi_range(0, 2)]
			release_at = t + rng.randi_range(2, 24)
		return dir | button


## The players of [param spec] (--humans: "A.B", "+" between numbers).
static func humans_of(spec: String) -> MwHumans:
	var humans := MwHumans.new()
	var sides := spec.split(".")
	for t in mini(sides.size(), 2):
		for x in sides[t].split("+", false):
			humans.set_team(int(x), t)
	return humans
