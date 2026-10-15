extends "res://test/net/net_test_base.gd"
## Plan 41 work item 2: run-ahead on the rink (MwNetRunAhead, MwRinkCopy).
## The copy is the state (its hash) and the shadow's passes leave the
## confirmed state alone; online, a client drawing through it plays the
## same game - every hash the host's, the same sound calls and screens at
## the same ticks as a client without it; and what it draws is measured
## against the host's own picture of the tick it shows (the plan 35 table's
## way, with dead reckoning alone beside it).

const Machines := preload("res://test/net/net_machines.gd")
const Bots := preload("res://test/support/bots.gd")
const ReckoningTest := preload("res://test/net/test_net_reckoning.gd")


func should_skip_script():
	return rom_or_skip()


func after_each() -> void:
	MwNetRunAhead.enabled = true
	MwNetMatch.input_stamps = true
	MwSound.trace = Callable()


## A match played offline for [param passes] passes from a faceoff, the
## pads pressed at random: [state, sim, update, phases].
static func _played(passes: int) -> Array:
	var rom_bytes := MwRom.data()
	var s := MwRinkState.new()
	s.rng = MlhRng.new(7)
	var sim := MwRinkSim.new(rom_bytes, s)
	sim.cpu = MwRinkAI.new()
	var up := MwRinkUpdate.new(sim)
	var ph := MwRinkPhases.new(up)
	MwRinkMatch.start(sim, 3, 3, 7, 4, false, 2)
	s.period = 1
	s.period_minutes = 5
	s.clock = 300
	ph.enter(5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in passes:
		for pad in 4:
			s.pads_held[pad] = [0x01, 0x02, 0x04, 0x08, 0x05, 0x0A,
					0][rng.randi() % 7] | (0x10 if rng.randf() < 0.05 else 0)
		var to := up.run_pass(2, ph)
		if to >= 0:
			MwRinkMatch.rink_exit(sim, to)
			ph.enter(5)
	return [s, sim, up, ph]


func test_a_copy_is_the_state_and_its_passes_leave_the_state_alone() -> void:
	var g := _played(300)
	var s: MwRinkState = g[0]
	var copier := MwRinkCopy.new()
	var shadow := MwRinkState.new()
	copier.copy_into(shadow, s)
	assert_eq(MwNetHash.rink(shadow), MwNetHash.rink(s), "the copy's hash is the state's")
	assert_gt(int(copier.stats["objects"]), 50, "objects copied")
	assert_ne(shadow.teams[0].players[0], s.teams[0].players[0], "objects of its own")
	assert_null(shadow.full_replay, "no full replay of its own")
	var before := MwNetHash.rink(s)
	var ssim := MwRinkSim.new(MwRom.data(), shadow)
	ssim.cpu = MwRinkAI.new()
	var sup := MwRinkUpdate.new(ssim)
	var sph := MwRinkPhases.new(sup)
	for i in 10:
		shadow.pads_held[0] = 0x08
		sup.run_pass(2, sph)
	assert_ne(MwNetHash.rink(shadow), before, "the shadow played on")
	assert_eq(MwNetHash.rink(s), before, "the state untouched")
	# copied again: the shadow's objects reused, the state again
	var player := shadow.teams[0].players[0]
	copier.copy_into(shadow, s)
	assert_eq(shadow.teams[0].players[0], player, "the same objects copied into")
	assert_eq(MwNetHash.rink(shadow), before, "the state again")


## Plan 42 (speed, second round): the copy by each class's compiled fill
## function (MwRinkCopy.generated) is the copy by the plan walked - the
## same hash, the same objects shared (the camera's target is one of the
## players), objects kept from copy to copy - match after match; and the
## sound driver's model's copy (MwAudioCopy) the same both ways.
func test_the_compiled_copy_is_the_walked_copy() -> void:
	for passes in [50, 300, 900]:
		var g := _played(passes)
		var s: MwRinkState = g[0]
		var walked := MwRinkState.new()
		var compiled := MwRinkState.new()
		var cw := MwRinkCopy.new()
		var cc := MwRinkCopy.new()
		MwRinkCopy.generated = false
		cw.copy_into(walked, s)
		MwRinkCopy.generated = true
		cc.copy_into(compiled, s)
		assert_eq(MwNetHash.rink(compiled), MwNetHash.rink(walked), "%d passes: the same copy" % passes)
		assert_eq(MwNetHash.rink(compiled), MwNetHash.rink(s), "%d passes: the state's" % passes)
		assert_eq(cc.stats["objects"], cw.stats["objects"], "the same objects met")
		if s.camera_target != null:
			var t := s.teams[0].players.find(s.camera_target)
			if t >= 0:
				assert_eq(compiled.camera_target, compiled.teams[0].players[t], "a shared object copied once")
		var p := compiled.teams[1].players[2]
		(g[2] as MwRinkUpdate).run_pass(2, g[3])
		cc.copy_into(compiled, s)
		cw.copy_into(walked, s)
		assert_eq(compiled.teams[1].players[2], p, "copied into the same objects")
		assert_eq(MwNetHash.rink(compiled), MwNetHash.rink(walked), "%d passes: copied again the same" % passes)
	if MwRom.available():
		var audio := MwAudio.new()
		audio.setup(MwRom.data(), false, false)
		audio.s68k.music_game()
		audio.s68k.crowd_level(600)
		for i in 200:
			if i % 30 == 0:
				audio.play_sound(0x25)
			audio.tick()
		var bw := MwAudio.new()
		bw.setup(MwRom.data(), false, false)
		MwRinkCopy.generated = false
		MwAudioCopy.new().copy_into(bw, audio)
		var bc := MwAudio.new()
		bc.setup(MwRom.data(), false, false)
		MwRinkCopy.generated = true
		MwAudioCopy.new().copy_into(bc, audio)
		var sw := MwNetSnapshot.audio_state(MwNetGraph.new(), bw)
		var sc := MwNetSnapshot.audio_state(MwNetGraph.new(), bc)
		if var_to_bytes(sc) != var_to_bytes(sw):
			var diffs := []
			_diff(MwNetHash.plain(sc), MwNetHash.plain(sw), "", diffs)
			gut.p("audio copies differ: %s" % str(diffs.slice(0, 6)))
		assert_true(var_to_bytes(sc) == var_to_bytes(sw), "the driver's model the same")
		for x in [audio, bw, bc]:
			x.free()


## A host (P1) and clients under [param conditions], gameplay bots on
## everyone, from the matchup onto the rink.
func _world(seed_value: int, conditions: Dictionary, client_locals: Array, teams: Dictionary) -> Machines:
	var w := Machines.new(self, seed_value, conditions, client_locals)
	for machine in w.machines:
		machine.bot.expected = teams.size()
		for p in machine.bot.players:
			machine.bot.teams[p] = teams[p]
			machine.bot.game_bots[p] = Bots.GameBot.new(p, seed_value)
	w.start(ReckoningTest._record(w, teams, seed_value))
	assert_true(w.run_until(func() -> bool:
		return w.machines.all(func(m: Machines.Machine) -> bool: return m.router.current_id() in [4, 5, 6]),
		6000), "every machine on the rink")
	return w


## Plan 43: a client's own stick moving every tick (an analogue stick in
## use; owner, 2026-10-13: to find out whether stamps help) at a 250 ms
## round trip: with input stamps the host takes each of
## its states at the tick its run-ahead played it at - its own input never
## the reason for a rollback, every state on time, the lead where the round
## trip puts it; with plan 41's merge (each state as it comes) its own input
## is mispredicted on most pictures and the merge bias runs to its bound.
## Every hash the host's either way.
func test_stamped_input_lands_where_the_run_ahead_played_it() -> void:
	var out := {}
	for stamps: bool in [true, false]:
		MwNetMatch.input_stamps = stamps
		var w := _world(43, {"delay": 125, "jitter": 10}, [1, 1], {1: 0, 2: 1, 3: 1})
		var machine := w.machines[1]
		var p: int = machine.bot.players[0]
		var bot := machine.bot
		bot.stick_fn = func(t: int) -> PackedInt32Array:
			var codes := PackedInt32Array()
			codes.resize(MwVerbs.PLAYERS)
			if bot.screen in [4, 5, 6]:
				codes[p - 1] = MwStick.encode(Vector2i(roundi(256.0 * sin(t * 0.5)), roundi(90.0 * cos(t * 0.3))))
			return codes
		var ra := machine.net_match.reckoning.run_ahead
		var before := ra.stats.duplicate()
		w.run(900)
		var ms: Dictionary = w.host.merge.stats.get(p, {})
		out[stamps] = {"runs": int(ra.stats["runs"]) - int(before["runs"]),
				"own": int(ra.stats["mis_own"]) - int(before["mis_own"]), "bias": machine.net_match.merge_bias,
				"on_time": int(ms.get("on_time", 0)), "late": int(ms.get("late", 0))}
		var h := w.compare_hashes()
		assert_true(h["ok"], "stamps %s: every hash the host's - %s" % [stamps, h["why"]])
		w.free_all()
	gut.p("a client's own stick moving every tick: %s" % str(out))
	var on: Dictionary = out[true]
	var off: Dictionary = out[false]
	assert_gt(int(on["runs"]), 200, "drawn through the run-ahead")
	assert_lt(int(on["own"]), int(on["runs"]) / 20, "stamped: its own input (all but) never mispredicted")
	assert_gt(int(on["on_time"]), 1000, "its states stamped")
	assert_lt(int(on["late"]), int(on["on_time"]) / 20, "on time")
	assert_lt(absf(float(on["bias"])), 3.0, "the lead where the round trip puts it")
	assert_gt(int(off["own"]), int(off["runs"]) / 2, "as they come: its own input mispredicted on most pictures")
	assert_eq(int(off["on_time"]) + int(off["late"]), 0, "as they come: nothing waits")


func test_online_the_game_is_untouched() -> void:
	var w := _world(41, {"delay": 125, "jitter": 10, "loss": 0.05}, [1, 1], {1: 0, 2: 1, 3: 1})
	var on := w.machines[1]
	var off := w.machines[2]
	off.net_match.reckoning.run_ahead.on = false
	var by_driver := {}
	var sounds := {on.id: [], off.id: []}
	var screens := {on.id: [], off.id: []}
	for m in [on, off]:
		by_driver[m._statics["driver"]] = m
		var mm: Machines.Machine = m
		m.router.screen_entered.connect(func(id: int, _v: int, tick: int, _p: int) -> void:
			(screens[mm.id] as Array).append([mm.net_match.stream_tick(tick), id]))
	MwSound.trace = func(fn: String, args: Array, result: Variant) -> void:
		var m: Machines.Machine = by_driver.get(MwSound.driver)
		if m != null and m.net_match != null:
			(sounds[m.id] as Array).append([m.net_match.stream_tick(m.router.tick), fn, str(args), str(result)])
	w.run(900)
	MwSound.trace = Callable()
	var c := w.compare_hashes()
	assert_true(c["ok"], "every client's hash the host's - %s" % c["why"])
	assert_gt(int(c["compared"]), 400, "hashes compared")
	var upto := mini(on.net_match.stream_tick(on.router.tick), off.net_match.stream_tick(off.router.tick))
	var cut := func(a: Array) -> Array: return a.filter(func(x: Array) -> bool: return int(x[0]) <= upto)
	var sa: Array = cut.call(sounds[on.id])
	assert_gt(sa.size(), 50, "sound calls made")
	assert_eq(sa, cut.call(sounds[off.id]), "the same sound calls at the same ticks, with it and without")
	assert_eq(cut.call(screens[on.id]), cut.call(screens[off.id]), "the same screens at the same ticks")
	var ra := on.net_match.reckoning.run_ahead
	assert_gt(int(ra.stats["runs"]), 200, "the client with it drew through it")
	assert_gt(int(ra.stats["carried"]), int(ra.stats["runs"]) / 4, "pictures carried on from the last")
	assert_gt(int(ra.stats["rollbacks"]), 0, "pictures started again")
	assert_eq(int(off.net_match.reckoning.run_ahead.stats["runs"]), 0, "the one without it didn't")
	# work item 3: the shadow's sounds heard at once, the game's own calls of them not again
	var heard: MwHeard = on._statics["heard"]
	gut.p("heard: %s" % str(heard.stats))
	assert_gt(int(heard.stats["predicted"]), 10, "the run-ahead's sounds heard as predicted")
	assert_gt(int(heard.stats["skipped"]), int(heard.stats["predicted"]) / 2, "most made by the game in time")
	assert_eq(int((off._statics["heard"] as MwHeard).stats["predicted"]), 0, "none without it")
	gut.p("run-ahead: %s; %.2f ms a picture" % [str(ra.stats),
			ra.stats["us"] / 1000.0 / maxi(int(ra.stats["runs"]), 1)])
	w.free_all()


## Work item 4: a client fallen behind its stream (frozen a second, then
## its packets at once) runs no run-ahead while far behind and a cut one
## while behind - what it draws never keeps it there: it catches up as fast
## as a client without it.
func test_a_client_behind_its_stream_draws_less_until_caught_up() -> void:
	var w := _world(44, {"delay": 50, "jitter": 0}, [1, 1], {1: 0, 2: 1, 3: 1})
	var on := w.machines[1]
	var off := w.machines[2]
	off.net_match.reckoning.run_ahead.on = false
	w.run(60)
	var ra := on.net_match.reckoning.run_ahead
	assert_gt(int(ra.stats["runs"]), 10, "drawing through it")
	for m in [on, off]:
		m.frozen = true
	w.run(60)
	for m in [on, off]:
		m.frozen = false
	var caught := {}
	for i in 240:
		w.frame()
		for m in [on, off]:
			if not caught.has(m.id) and m.net_match.lead() <= m.net_match.buffer_target() + MwNetRunAhead.BEHIND_TICKS:
				caught[m.id] = i
	gut.p("caught up after %s frames; %s" % [str(caught), str(ra.stats)])
	assert_gt(int(ra.stats["behind"]), 0, "far behind: none run")
	assert_eq(caught.size(), 2, "both caught up")
	assert_lte(int(caught.get(on.id, 999)), int(caught.get(off.id, 0)) + 2, "as fast as without it")
	assert_almost_eq(ra.budget_now, ra.budget_ms, 0.01, "its budget back once caught up")
	assert_true(w.compare_hashes()["ok"], "every hash the host's")
	w.free_all()


## The 3D views draw the shadow too (the presenter, the camera, the items
## from the shadow's draw pass): a client in FOLLOW 3D and then EXTENDED
## through a minute of play, the run-ahead drawing, every hash the host's.
func test_the_3d_views_draw_it() -> void:
	var w := _world(45, {"delay": 100, "jitter": 10}, [1, 1], {1: 0, 2: 1, 3: 1})
	var client := w.machines[1]
	# (plan 44: an online match is an EXTENDED one, every machine in 2D EXTENDED
	# - drawn by the 3D view; in one process the machines share it: the others
	# shown in the flat 2D, the view is this client's alone)
	for machine in w.machines:
		if machine != client:
			machine.enter()
			(machine.router.current() as MwRink).select_view(MwRinkViews.FLAT)
			machine.leave()
	for v: int in [MwRinkViews.FOLLOW, MwRinkViews.EXTENDED]:
		client.enter()
		var rk := client.router.current() as MwRink
		rk.select_view(v)
		client.leave()
		var runs := int(client.net_match.reckoning.run_ahead.stats["runs"])
		w.run(300)
		rk = client.router.current() as MwRink
		assert_true(rk != null and rk.view_3d(), "%s: in 3D" % MwRinkViews.NAMES[v])
		assert_gt(int(client.net_match.reckoning.run_ahead.stats["runs"]), runs + 50,
				"%s: drawn through the run-ahead" % MwRinkViews.NAMES[v])
		if v == MwRinkViews.EXTENDED:
			# (owner, 2026-10-13: 3D EXTENDED extends out for the local players
			# only) - the client's player alone, not the host's nor the other
			# client's
			var view := MwRink3DHost.existing(rk.get_tree()).view()
			assert_eq(view.local_pads, PackedInt32Array([client.service.client.numbers[0] - 1]), "its machine's pad")
			assert_eq(view.camera.shot.drivers.size(), 1, "3D EXTENDED frames its own player and the puck")
			assert_eq(MwRinkShot3D.drivers_of(rk.state).size(), 3, "(three driven in the game)")
	assert_true(w.compare_hashes()["ok"], "every hash the host's")
	w.free_all()


## The shadow carried on from picture to picture is the shadow started
## again from a copy of the confirmed state at the same moment: every
## picture both reach the same tick, the same game (its hash's form but
## the replay ring: [method _played_part]).
func test_a_carried_on_shadow_is_one_started_again() -> void:
	var w := _world(43, {"delay": 100, "jitter": 10}, [1, 1], {1: 0, 2: 1, 3: 1})
	var machine := w.machines[1]
	machine.net_match.reckoning.run_ahead.on = false
	var ra := MwNetRunAhead.new(machine.net_match)
	ra.budget_ms = 1.0e9
	var again := MwNetRunAhead.new(machine.net_match)
	again.carry_on = false
	again.budget_ms = 1.0e9
	var compared := 0
	var unlike := []
	for i in 600:
		w.frame()
		var scene := machine.router.current() as MwRink
		if scene == null or scene.state == null:
			continue
		machine.enter()
		var ctx := MwScreens.contexts(scene.screen_id)
		var a := ra.run(scene, ctx)
		var carried := not bool(ra.last["fresh"])
		var b := again.run(scene, ctx)
		if a >= 0 and a == b and carried:
			compared += 1
			var x := _played_part(ra.shadow)
			var y := _played_part(again.shadow)
			if MwNetHash.digest(x, false) != MwNetHash.digest(y, false):
				unlike.append(machine.net_match.stream_tick(a))
				if unlike.size() <= 3:
					var diffs := []
					_diff(MwNetHash.plain(x), MwNetHash.plain(y), "", diffs)
					gut.p("at %d (from %d): %s" % [a, machine.router.clock.last_pass_tick(), str(diffs.slice(0, 12))])
		machine.leave()
	gut.p("compared %d, unlike at %s; %s" % [compared, str(unlike.slice(0, 10)), str(ra.stats)])
	assert_gt(compared, 100, "carried-on pictures compared")
	assert_eq(unlike.size(), 0, "each the same as started again")
	w.free_all()


## What of a shadow its passes play from: its hash's form but the replay
## ring (each picture's draw closes the frame its last pass opened - a
## shadow drawn once after many passes abandons the frames before; the
## shadow plays no replay) and what only the draw pass writes - the arrows'
## variants and the impale record's animation (plan 42: the scene draws the
## shadow, MwRinkUpdate.defer_draws; nothing a pass plays reads them).
static func _played_part(s: MwRinkState) -> Dictionary:
	var d := MwNetHash.rink_dict(s)
	d.erase("replay")
	for t: Variant in d.get("teams", []):
		if t is Dictionary:
			for a: Variant in (t as Dictionary).get("arrows", []):
				if a is Dictionary:
					(a as Dictionary).erase("variant")
	var imp: Variant = d.get("impale")
	if imp is Dictionary:
		(imp as Dictionary).erase("address")
	return d


## The paths where [param x] and [param y] differ (into [param out]).
static func _diff(x: Variant, y: Variant, path: String, out: Array) -> void:
	if out.size() > 40:
		return
	if x is Dictionary and y is Dictionary:
		for k in x:
			_diff(x[k], (y as Dictionary).get(k), path + "." + str(k), out)
	elif x is Array and y is Array and (x as Array).size() == (y as Array).size():
		for i in (x as Array).size():
			_diff(x[i], y[i], path + "[%d]" % i, out)
	elif typeof(x) != typeof(y) or x != y:
		out.append("%s: %s | %s" % [path, str(x).left(60), str(y).left(60)])


## What a client drew against the host's own picture of the same tick (px):
## [param delay] ms each way, 10 ms jitter, [param frames] frames on the
## rink; the client with run-ahead (machine 1) and one with dead reckoning
## alone (machine 2) - each picture's tick: the run-ahead's aim, dead
## reckoning's lead's end; the host's picture of a tick between its passes
## the two passes' blended (the 3D view's frames between passes are). Its
## own skater apart from everyone else's, and
## its own skater's animation (what it is doing: skating, shooting,
## checking) against the host's at that tick - the run-ahead's from its
## shadow, dead reckoning's the confirmed state's (it moves things, it
## doesn't play them).
func _measure(delay: int, frames: int, seed_value := 42) -> Dictionary:
	var w := _world(seed_value, {"delay": delay, "jitter": 10}, [1, 1], {1: 0, 2: 1, 3: 1})
	var host_machine := w.machines[0]
	w.machines[2].net_match.reckoning.run_ahead.on = false
	# (what it draws given the time: the test's machine's speed aside)
	w.machines[1].net_match.reckoning.run_ahead.budget_ms = 1.0e9
	var host_at := {}                          # host router tick -> {actor key: pixels}
	var host_anim := {}                        # host router tick -> {actor key: animation}
	# per client: [picture tick, {actor key: drawn}, own keys, {own key: anim}]
	var drawn := [[], []]
	var seen := [-1, -1]
	for i in frames:
		w.frame()
		var hs := host_machine.rink()
		# (the host's at its passes: what the game is between them is the pass before)
		if host_machine.router.current_id() in [4, 5, 6] and hs != null and hs.phase == MwRinkState.PHASE_PLAY \
				and host_machine.router.clock.last_pass_tick() == host_machine.router.tick:
			host_at[host_machine.router.tick] = _pixels(hs)
			host_anim[host_machine.router.tick] = _anims(hs)
		for j in 2:
			var machine := w.machines[j + 1]
			var rk := machine.net_match.reckoning
			var tick := rk.last_tick + rk.last_lead
			if rk.last_tick == seen[j] or machine.rink() == null or machine.rink().phase != MwRinkState.PHASE_PLAY:
				continue
			seen[j] = rk.last_tick
			var d := {}
			for key: String in rk.last:
				if key != "camera":
					d[key] = Vector3(rk.last[key]["drawn"])
			var ra := rk.run_ahead
			var shown: MwRinkState = ra.shadow if j == 0 and int(ra.last["at"]) >= 0 else machine.rink()
			var own := _own(machine.rink(), MwNetReckoning.steering(machine.rink(),
					machine.net_match.local_states()).keys())
			var anims := _anims(shown)
			var mine := {}
			for key: String in own:
				mine[key] = anims.get(key)
			(drawn[j] as Array).append([machine.net_match.stream_tick(tick), d, own, mine])
	var out := {}
	for predictor in ["ahead", "dr"]:
		out[predictor] = {"own": [], "players": [], "puck": [], "acting": [0, 0]}
	var base := host_machine.net_match.base
	for j in 2:
		var predicted_by := "ahead" if j == 0 else "dr"
		for picture: Array in drawn[j]:
			var tick := int(picture[0]) + base
			var b0 := tick
			while b0 > tick - 4 and not host_at.has(b0):
				b0 -= 1
			var b1 := tick + 1
			while b1 < tick + 4 and not host_at.has(b1):
				b1 += 1
			if not host_at.has(b0) or (b0 != tick and not host_at.has(b1)):
				continue
			var own: Array = picture[2]
			var p0: Dictionary = host_at[b0]
			for key: String in picture[1]:
				if not p0.has(key):
					continue
				var at := Vector3(p0[key])
				if b0 != tick:
					var p1: Dictionary = host_at[b1]
					if not p1.has(key):
						continue
					at = at.lerp(Vector3(p1[key]), float(tick - b0) / (b1 - b0))
				var which := "puck" if key == "puck" else ("own" if key in own else "players")
				(out[predicted_by][which] as Array).append(((picture[1] as Dictionary)[key] - at).length())
			var ha: Dictionary = host_anim[b0]
			for key: String in picture[3]:
				if ha.has(key):
					out[predicted_by]["acting"][1] += 1
					if ha[key] == picture[3][key]:
						out[predicted_by]["acting"][0] += 1
	assert_true(w.compare_hashes()["ok"], "%d ms: every hash the host's" % delay)
	out["stats"] = w.machines[1].net_match.reckoning.run_ahead.stats.duplicate()
	out["stats"]["bias"] = "%.2f (%d seen)" % [w.machines[1].net_match.merge_bias,
			int(w.machines[1].net_match.stats.get("merge_seen", 0))]
	w.free_all()
	return out


## The skaters of [param s] driven by pads [param pads] (MwNetReckoning.steering's keys).
static func _own(s: MwRinkState, pads: Array) -> Array:
	var out := []
	for ti in s.teams.size():
		var team := s.teams[ti]
		for pi in team.players.size():
			var p := team.players[pi]
			if not p.present or not p.flags & MwRinkState.Player.HUMAN:
				continue
			var pad: int = (p.pad if p.pad >= 0 else -1) if s.extended \
					else team.pads[1 if p.flags & MwRinkState.Player.SECOND_PAD else 0] & 3
			if pad in pads:
				out.append(MwRinkDraw3D.actor_key(ti, pi))
	return out


## Each present skater's animation (its script: skating, shooting,
## checking, falling).
static func _anims(s: MwRinkState) -> Dictionary:
	var out := {}
	for ti in s.teams.size():
		for pi in s.teams[ti].players.size():
			var p := s.teams[ti].players[pi]
			if p.present:
				out[MwRinkDraw3D.actor_key(ti, pi)] = p.anim.address
	return out


static func _pixels(s: MwRinkState) -> Dictionary:
	var out := {}
	for ti in s.teams.size():
		for pi in s.teams[ti].players.size():
			var p := s.teams[ti].players[pi]
			if p.present:
				out[MwRinkDraw3D.actor_key(ti, pi)] = Vector3(p.motion.pixels())
	if not s.puck.flags & MwRinkState.Puck.HIDDEN:
		out["puck"] = Vector3(s.puck.motion.pixels())
	return out


func test_drawn_error_against_the_hosts_picture_of_its_tick() -> void:
	gut.p("drawn against the host's picture of the tick shown (px): mean / 95th percentile - run-ahead | dead "
			+ "reckoning;"
			+ " its own skater doing what the host's is")
	for delay: int in [50, 125]:
		var r := _measure(delay, 600)
		var line := "%3d ms one-way:" % delay
		for which: String in ["own", "players", "puck"]:
			var a: Array = r["ahead"][which]
			var d: Array = r["dr"][which]
			line += "  %s %.1f / %.1f | %.1f / %.1f" % [which, ReckoningTest._mean(a), ReckoningTest._p95(a),
					ReckoningTest._mean(d), ReckoningTest._p95(d)]
		var acting := []
		for predictor in ["ahead", "dr"]:
			var n: Array = r[predictor]["acting"]
			acting.append(100.0 * n[0] / maxi(n[1], 1))
		line += "  acting %.0f%% | %.0f%%" % acting
		gut.p(line)
		gut.p("    run-ahead: %s" % str(r["stats"]))
		assert_gt((r["ahead"]["own"] as Array).size(), 60, "%d ms: pictures measured" % delay)
		assert_lte(ReckoningTest._p95(r["ahead"]["own"]), ReckoningTest._p95(r["dr"]["own"]),
				"%d ms: its own skater nearer the host's with it" % delay)
		if delay > 100:
			assert_lt(ReckoningTest._mean(r["ahead"]["own"]), ReckoningTest._mean(r["dr"]["own"]),
					"%d ms: its own skater nearer the host's with it (mean)" % delay)
		assert_gt(acting[0], acting[1], "%d ms: its own skater doing what the host's is, more often with it" % delay)
