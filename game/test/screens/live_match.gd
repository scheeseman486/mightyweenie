extends SceneTree
## Plan 11's live flow check, headless: a whole match through the router
## and the real scenes (the main menu, the matchup, the rink, every screen
## between plays) with a menu bot on the pads, at full speed.
##
##   tools/bin/godot-headless -s res://test/screens/live_match.gd -- [options]
##     --pads N       pad mode (5: CPU vs CPU, default; 0: P1 vs CPU ...)
##     --minutes N    period length in minutes (default 1)
##     --penalties N  0 / 1 (default 1)
##     --teams A,B    (default 0,5)
##     --seed N       the session's RNG seed (default 1)
##     --ticks N      give up after N ticks (default 200000)
##     --detours N    scoreboard visits that take a detour first (8 / 7 / 10; default 6)
##     --view3d N     1: the rink in its 3D follow view (plan 14 phase B; default 0) -
##                    the flow and the result must be the 2D run's
##     --view N       the rink's view (MwRinkViews, 0-7; overrides --view3d)
##
## Start goes to every pad on the special plays screen (its second page
## waits for its own player). Prints each screen entry (tick, screen, entry) and a summary; exits 0
## when the match got back to the main menu (or the playoffs) through a
## game-over scoreboard with no script error, else 1.

const RINK := [4, 5, 6]


## The pads: a press of [member button] for a few ticks some time after
## each screen entry, again while the screen stays (screens 7 / 8 / 10 /
## scoreboards / menus); nothing on the rink, the fight or the cutscene.
class MenuBot extends MwInputSource:
	var router: MwRouter
	var mask := 0
	var entered_at := 0
	var screen := -1
	var visits := {}
	var detours := 6
	var cpu := false
	var plan: Array = []          ## buttons still to press on this visit
	var next_at := 0
	var release_at := 0
	var log: Array = []

	func on_entered(id: int, _visit: int, tick: int, _prev: int) -> void:
		screen = id
		entered_at = tick
		visits[id] = int(visits.get(id, 0)) + 1
		plan = _plan(id, int(visits[id]))
		next_at = tick + _wait(id)
		mask = 0

	func on_resumed(id: int, _visit: int, tick: int) -> void:
		on_entered(id, 0, tick, -1)

	func _plan(id: int, visit: int) -> Array:
		match id:
			0, 1, 3, 11, 16, MwScreens.FRONT_MENU:
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
		if mask != 0 and t >= release_at:
			mask = 0
			next_at = t + 240       # pressed again if the screen stays
		if mask == 0 and t >= next_at and screen not in RINK:
			var b: String = plan.pop_front() if not plan.is_empty() else ("START" if screen in [0, 1, 3, 7, 8, 10, 11, 12, 14, 15, 16, 17, MwScreens.FRONT_MENU] else "")
			if b != "":
				mask = MwInputScript.PAD_BITS[b]
				release_at = t + 6
				log.append([t, screen, b])

	func sample(contexts: Array) -> Dictionary:
		var out := {}
		if mask == 0:
			return out
		# special plays: every pad (a second page waits for its own player's Start)
		var players := range(1, MwVerbs.PLAYERS + 1) if screen == 10 else [1]
		for button in MwInputScript.PAD_BITS:
			if mask & MwInputScript.PAD_BITS[button]:
				for ctx in contexts:
					for verb in MwVerbs.verbs_of(ctx, button):
						for p in players:
							out[MwVerbs.action(p, verb)] = true
							if ctx == MwVerbs.Context.MENU:
								out[MwVerbs.menu_action(p, verb)] = true
		return out


var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	var args := _args()
	var host := Node.new()
	root.add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(int(args.get("seed", "1")), 1)
	var su := router.session.setup
	su.pads = int(args.get("pads", "5"))
	su.period_minutes = int(args.get("minutes", "1"))
	su.penalties = int(args.get("penalties", "1"))
	var teams := str(args.get("teams", "0,5")).split(",")
	su.team_a = int(teams[0])
	su.team_b = int(teams[1])
	# every match starts in the options' view (the matchup sets it): override that
	MwSettings.start_view = MwRinkViews.FOLLOW if int(args.get("view3d", "0")) != 0 else MwRinkViews.FLAT
	if args.has("view"):
		MwSettings.start_view = int(args["view"])
	router.session.view = MwSettings.start_view
	var bot := MenuBot.new()
	bot.router = router
	bot.detours = int(args.get("detours", "6"))
	bot.cpu = su.pads == 5
	router.screen_entered.connect(bot.on_entered)
	router.screen_resumed.connect(bot.on_resumed)
	router.input = bot
	var entries: Array = []
	router.screen_entered.connect(func(id: int, visit: int, tick: int, prev: int) -> void:
		var e := router.current().entry if router.current() else ""
		entries.append([tick, id, prev, e])
		print("%7d  %2d <- %2d  %s" % [tick, id, prev, e]))
	router.screen_resumed.connect(func(id: int, _visit: int, tick: int) -> void:
		print("%7d  %2d (resumed)" % [tick, id]))
	var menu := (load(MwScreens.scene_path(1)) as PackedScene).instantiate() as MwScreen
	fader.cover()
	router.adopt(menu)
	var limit := int(args.get("ticks", "200000"))
	var started := Time.get_ticks_msec()
	var game_over := false
	var done := false
	var n := 0
	while n < limit:
		router.step()
		n += 1
		var id := router.current_id()
		if id in [15, 16]:
			game_over = true
		if game_over and id in [1, 11] and n > 1000:
			done = true
			break
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	var seen := {}
	for e in entries:
		seen[int(e[1])] = int(seen.get(int(e[1]), 0)) + 1
	var st: MwRinkState = router.session.screens.get("rink") as MwRinkState
	print("ticks %d in %.1f s (%.0f ticks/s); screens %s" % [n, secs, n / maxf(secs, 0.001), str(seen)])
	if st:
		print("score %d-%d, period %d" % [st.teams[0].score if "score" in st.teams[0] else -1,
			st.teams[1].score if "score" in st.teams[1] else -1, st.period])
	print("presses: %d" % bot.log.size())
	print("RESULT %s" % ("ok" if done else "tick limit, on screen %d" % router.current_id()))
	quit(0 if done else 1)
	return true


func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	return out
