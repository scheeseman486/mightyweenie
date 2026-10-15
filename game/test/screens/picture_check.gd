extends SceneTree
## The picture's transitions, checked (owner, 2026-10-09: aspect-ratio
## glitches between screens - other such cases looked for systematically
## and removed). Headless, at full speed: a whole match
## through the router and the real scenes with live_match.gd's menu bot on
## the pads (every screen between plays, its detours to the stats, the
## replay and special plays) and, at the rink, the pause menu's items now
## and then - TEAM INFO, REPLAY, TIMEOUT (when offered), FORFEIT (the last:
## it ends the match); or (--attract 1) from the title with no input,
## through the front menu's idle into the attract demo and back.
##
## After every tick the picture's signature - the window's content scaling
## (mode, stretch, size), the default canvas's offset, the 3D view shown and
## for which screen, the screen the picture is wide for - is compared with
## the tick before. A change is fine under a full cover (the fader's black
## on both ticks: the player sees neither), with the screen swapped under
## the cover (the tick its fade-out ends: the new screen's first frame is
## black), or at a hard cut (a screen change without a fade: the old
## picture's last frame, the new one's first).
## Any other change happens in front of the player: the picture switching
## its shape, scale or view while a screen shows - a glitch. And while the
## picture shows (the cover not full), the 3D view and the wide picture may
## only be the screen's on top: a claim left by a screen underneath or gone
## gives the screen shown another screen's scaling (a stale claim).
##
##   tools/bin/godot-headless -s res://test/screens/picture_check.gd -- [options]
##     --view N      the rink's view (MwRinkViews; default 7, the 3D follow camera)
##     --aspect A    ORIGINAL or WIDE (default WIDE)
##     --window WxH  the window's size (default 1920x1080: a wide picture of
##                   480 x 270; headless windows are otherwise 64 x 64)
##     --pause N     pause menu visits, this many (default 4: each item once; 0 none)
##     --attract N   1: the attract run instead of a match (default 0)
##     --inject N    1: the check's own check - on each push from the rink, the
##                   3D view and the wide picture given back at once, as TEAM
##                   INFO did before 2026-10-09: must be reported
##     --pads N, --minutes N, --teams A,B, --seed N, --ticks N, --detours N: as live_match.gd
##                   (pads default 0: player 1 against the CPU - the pause menu
##                   needs a player; the bot leaves the rink to the CPU)
##
## Prints each glitch (tick, screens, the fader's coverage, the fields that
## changed) and a summary; exits 0 when there were none, 1 otherwise (2: the
## run did not finish).

const Bots := preload("res://test/support/bots.gd")
const RINK := [4, 5, 6]
const RESUME := {"p1_ui_resume": true, "ui_resume": true}
const ACCEPT := {"p1_ui_accept": true, "ui_accept": true}
const UP := {"p1_ui_up": true, "ui_up": true}
const DOWN := {"p1_ui_down": true, "ui_down": true}
## The pause menu's items in the order the bot visits them, and the presses
## from REPLAY (selected when it opens) that pick each.
const ITEMS := ["TEAM INFO", "REPLAY", "TIMEOUT", "FORFEIT"]
const PICKS := {"TEAM INFO": [UP, UP, ACCEPT], "REPLAY": [ACCEPT], "TIMEOUT": [DOWN, ACCEPT],
		"FORFEIT": [UP, ACCEPT, DOWN, ACCEPT]}


## live_match's bot, plus the pause menu at the rink: once a visit (up to
## [member pauses] times in all), in live play, the next of [constant
## ITEMS] (TIMEOUT when not offered picks TEAM INFO); Start on the team
## description pops it, Start on the pause menu after it resumes play.
class Bot extends Bots.MenuBot:
	var pauses := 4
	var done := 0
	var used := false
	var held := {}
	var steps: Array = []          ## [tick, actions] still to hold, in order

	func on_entered(id: int, visit: int, t: int, prev: int) -> void:
		super.on_entered(id, visit, t, prev)
		used = false
		steps = []

	func on_resumed(id: int, _visit: int, t: int) -> void:
		screen = id
		entered_at = t
		plan = []
		mask = 0
		next_at = t + 1000000
		steps = [[t + 40, RESUME], [t + 44, {}]] if id in RINK else []

	func _plan(id: int, visit: int) -> Array:
		if id == 2:
			return ["START", "START", "START"]     # over the pause menu: the bio's Start pops it
		return super._plan(id, visit)

	func _wait(id: int) -> int:
		return 700 if id == 2 else super._wait(id)

	func tick() -> void:
		super.tick()
		var t := router.tick
		if screen in RINK and steps.is_empty() and not used and done < pauses:
			var rk := router.current() as MwRink
			if rk != null and rk.state != null and rk.phases != null and not rk.phases.paused \
					and rk.state.phase == MwRinkState.PHASE_PLAY and t - entered_at > 400:
				used = true
				var item: String = ITEMS[done % ITEMS.size()]
				done += 1
				steps = [[t, {"p1_pause": true}], [t + 3, {}]]
				var at := t + 20
				for press in PICKS[item]:
					steps += [[at, press], [at + 3, {}]]
					at += 20
				log.append([t, screen, item])
		while not steps.is_empty() and t >= int(steps[0][0]):
			held = steps.pop_front()[1]

	func sample(contexts: Array) -> Dictionary:
		var out := super.sample(contexts)
		out.merge(held)
		return out


var router: MwRouter
var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	var a := _args()
	MwSettings.aspect = str(a.get("aspect", "WIDE"))
	MwSettings.start_view = int(a.get("view", str(MwRinkViews.FOLLOW)))
	var attract := int(a.get("attract", "0")) != 0
	var win := str(a.get("window", "1920x1080")).split("x")
	root.size = Vector2i(int(win[0]), int(win[1]))
	var host := Node.new()
	root.add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	router = MwRouter.new(host, fader)
	router.session = MwSession.new(int(a.get("seed", "1")), 1)
	router.session.view = MwSettings.start_view
	var su := router.session.setup
	su.pads = int(a.get("pads", "0"))
	su.period_minutes = int(a.get("minutes", "1"))
	var teams := str(a.get("teams", "0,5")).split(",")
	su.team_a = int(teams[0])
	su.team_b = int(teams[1])
	var bot: Bot = null
	if attract:
		router.input = MwInputSource.new()
	else:
		bot = Bot.new()
		bot.router = router
		bot.detours = int(a.get("detours", "6"))
		bot.cpu = su.pads == 5
		bot.pauses = int(a.get("pause", "4"))
		router.screen_entered.connect(bot.on_entered)
		router.screen_resumed.connect(bot.on_resumed)
		router.input = bot
	var entries := []
	router.screen_entered.connect(func(id: int, _v: int, t: int, _p: int) -> void: entries.append([t, id]))
	var first := (load(MwScreens.scene_path(0 if attract else 1)) as PackedScene).instantiate() as MwScreen
	first.screen_id = 0 if attract else 1
	fader.cover()
	router.adopt(first)
	var limit := int(a.get("ticks", "60000" if attract else "200000"))
	var glitches := []
	var changes := {"covered": 0, "swap": 0, "cut": 0}
	var was := _signature()
	var was_cov := fader.coverage()
	var was_top := router.current()
	var inject := int(a.get("inject", "0")) != 0
	var injected := false
	var game_over := false
	var finished := false
	var n := 0
	while n < limit:
		router.step()
		n += 1
		if inject and router.busy() and str(router.get("_pending").get("op", "")) == "push" \
				and router.current() is MwRink:
			if not injected:
				var h := MwRink3DHost.of(self)
				h.show_for(router.current(), false)
				h.wide_for(router.current(), false)
				print("injected: the picture given back with the request, tick %d" % router.tick)
			injected = true
		else:
			injected = false
		var sig := _signature()
		var cov := fader.coverage()
		var top := router.current()
		if sig != was:
			if top != was_top:
				changes["swap" if cov >= 1.0 else "cut"] += 1
			elif was_cov >= 1.0 and cov >= 1.0:
				changes["covered"] += 1
			else:
				var diff := []
				for k in sig:
					if sig[k] != was.get(k):
						diff.append("%s %s -> %s" % [k, str(was.get(k)), str(sig[k])])
				glitches.append("tick %d screen %d (stack %s), coverage %.2f -> %.2f: %s" % [router.tick,
						router.current_id(), str(router.stack.map(func(item: MwScreen) -> int: return item.screen_id)),
						was_cov, cov, "; ".join(diff)])
				print("GLITCH ", glitches[-1])
		if cov < 1.0:
			var h := MwRink3DHost.existing(self)
			for claim in ([["3D view", h.user], ["wide picture", h.wide_user]] if h != null else []):
				if claim[1] != null and claim[1] != top:
					var g := "tick %d screen %d (stack %s), coverage %.2f: the %s is %s's, not the screen shown's" % [
							router.tick, router.current_id(),
							str(router.stack.map(func(entry: MwScreen) -> int: return entry.screen_id)), cov, claim[0],
							_screen_of(claim[1])]
					if glitches.is_empty() or not str(glitches[-1]).ends_with(g.get_slice(": ", 1)):
						glitches.append(g)
						print("STALE ", g)
		was = sig
		was_cov = cov
		was_top = top
		var id := router.current_id()
		if attract:
			if n > 3000 and id == MwScreens.FRONT_MENU \
					and entries.any(func(e: Array) -> bool: return int(e[1]) in RINK) \
					and not router.busy():
				finished = true
				break
		else:
			if id in [15, 16]:
				game_over = true
			if game_over and id in [1, 11] and n > 1000:
				finished = true
				break
	var seen := {}
	for e in entries:
		seen[int(e[1])] = int(seen.get(int(e[1]), 0)) + 1
	print("picture_check: view %d, %s, window %s, %s: %d ticks, screens %s" % [MwSettings.start_view, MwSettings.aspect,
			str(root.size), "attract" if attract else "match", n, str(seen)])
	if bot != null:
		print("pause menu visits: %s" % str(bot.log.filter(func(l: Array) -> bool: return l.size() == 3 \
				and str(l[2]) in ITEMS)))
	print("picture changes: %d under the cover, %d with the screen swapped under it, %d at hard cuts, %d in sight" % [
			changes["covered"], changes["swap"], changes["cut"], glitches.size()])
	print("RESULT %s" % ("unfinished, on screen %d" % router.current_id() if not finished
			else ("ok" if glitches.is_empty() else "%d glitches" % glitches.size())))
	quit(2 if not finished else (0 if glitches.is_empty() else 1))
	return true


## The picture as the window shows it: its content scaling, the default
## canvas's offset (the wide picture's centred column), the 3D view shown
## and for which screen, the screen the picture is wide for.
func _signature() -> Dictionary:
	var h := MwRink3DHost.existing(self)
	return {"scale_mode": root.content_scale_mode, "stretch": root.content_scale_stretch,
			"size": root.content_scale_size, "origin": root.canvas_transform.origin,
			"view_3d": h != null and h.visible,
			"3d_for": _screen_of(h.user if h != null else null),
			"wide_for": _screen_of(h.wide_user if h != null else null)}


static func _screen_of(o: Object) -> String:
	if o == null:
		return "-"
	var screen := o as MwScreen
	return "%d#%d" % [screen.screen_id, screen.get_instance_id()] if screen != null else str(o)


func _args() -> Dictionary:
	return preload("res://test/support/cli.gd").args()      # (plan 40: one copy)
