extends "res://test/rom/rom_test_base.gd"
## The team description against the original (compare/fixtures/
## team_description.json, recorded with compare/scripts/td_*.mwi):
## * every page move shows the same vscroll at the same tick of the move
##   (the original's motion physics, bounces included);
## * the team, cursor and line change in the same order, close in time: our
##   pages read the pads every tick, the original's every 5-10 ticks while it
##   redraws the page (owner: menus run every tick);
## * the screens visited.
## Plus the ports underneath: the motion object, the text box, the quotes.

## Our change may come this much earlier / later than the original's.
const SELECT_EARLY := 12
const SELECT_LATE := 2
## A move starts this close to the original's.
const MOVE_SHIFT := 12
## vscroll changes further apart than this belong to different moves.
const MOVE_GAP := 20

var host: Node
var _fixture: Dictionary


func before_all() -> void:
	super.before_all()
	_fixture = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/team_description.json")))


func after_each() -> void:
	if host:
		host.free()
		host = null
		await wait_process_frames(1)      # screens the router left are queue_free()d


## Plays compare/scripts/<name>.mwi from the main menu; returns
## {"history": screens entered, "visits": per visit of screen 2, the state of
## every tick [tick from entry, vscroll, side, cursor, line]}.
func _play(case_name: String) -> Dictionary:
	host = Node.new()
	add_child(host)
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = MwSession.new(0x61F2415D, 0x1234567)
	var script := MwInputScript.parse(FileAccess.get_file_as_string(repo_path("compare/scripts/%s.mwi" % case_name)),
			case_name)
	assert_eq(script.error, "")
	var player := MwScriptPlayer.new(script)
	var source := MwScriptedInput.new(player)
	source.attach(router)
	router.input = source
	var history := []
	var visits := []
	var entry := [0]
	router.screen_entered.connect(func(id: int, _visit: int, tick: int, _p: int) -> void:
		history.append(id)
		entry[0] = tick
		if id == 2:
			visits.append([]))
	router.pass_ended.connect(func(_b: Dictionary) -> void:
		var td := router.current() as MwTeamDescription
		if td and not visits.is_empty():
			visits.back().append([router.tick - int(entry[0]), td.vscroll, td.side, td.cursor, td.line]))
	var menu := (load(MwScreens.scene_path(1)) as PackedScene).instantiate() as MwScreen
	menu.screen_id = 1
	router.adopt(menu)
	var n := 0
	while not player.ended() and n < 20000:
		router.step()
		n += 1
	assert_true(player.ended(), "%s reached END" % case_name)
	return {"history": history, "visits": visits}


## Runs of vscroll changes: [[[tick, vscroll], ...], ...].
static func _moves(states: Array) -> Array:
	var moves := []
	var prev := -1
	var last := -1000
	for s in states:
		var v := int(s[1])
		if prev >= 0 and v != prev:
			if int(s[0]) - last > MOVE_GAP:
				moves.append([])
			moves.back().append([int(s[0]), v])
			last = int(s[0])
		prev = v
	return moves


## Changes of (side, cursor, line): [[tick, side, cursor, line], ...].
static func _selections(states: Array) -> Array:
	var out := []
	for s in states:
		var sel := [int(s[2]), int(s[3]), int(s[4])]
		if out.is_empty() or out.back().slice(1) != sel:
			out.append([int(s[0])] + sel)
	return out


func _check(case_name: String) -> void:
	if not need_rom():
		return
	var want: Dictionary = _fixture["cases"][case_name]
	var got := _play(case_name)
	var history: Array = want["history"].filter(func(id: Variant) -> bool: return int(id) != 0)
	assert_eq(got["history"], history.map(func(id: Variant) -> int: return int(id)), "%s: screens" % case_name)
	var wv: Array = want["visits"]
	var gv: Array = got["visits"]
	assert_eq(gv.size(), wv.size(), "%s: visits of screen 2" % case_name)
	for i in mini(gv.size(), wv.size()):
		var ws: Array = wv[i]["states"]
		var gs: Array = gv[i]
		var tag := "%s visit %d" % [case_name, i + 1]
		# selections: same order, close in time
		var wsel := _selections(ws)
		var gsel := _selections(gs)
		assert_eq(gsel.map(func(selection: Array) -> Array: return selection.slice(1)), \
				wsel.map(func(selection: Array) -> Array: return selection.slice(1)), \
				tag + ": team / cursor / line changes")
		for k in range(1, mini(wsel.size(), gsel.size())):
			var d := int(gsel[k][0]) - int(wsel[k][0])
			assert_true(d >= -SELECT_EARLY and d <= SELECT_LATE,
					"%s: change %d at %+d ticks from the original's" % [tag, k, d])
		# moves: same vscroll at the same tick of the move
		var wm := _moves(ws)
		var gm := _moves(gs)
		assert_eq(gm.size(), wm.size(), tag + ": page moves")
		var at := {}
		for s in gs:
			at[int(s[0])] = int(s[1])
		for k in mini(wm.size(), gm.size()):
			var first: Array = wm[k][0]
			var start := -1
			for g in gm[k]:
				if int(g[1]) == int(first[1]):
					start = int(g[0])
					break
			assert_true(start >= 0, "%s move %d: reaches vscroll %d" % [tag, k, int(first[1])])
			if start < 0:
				continue
			var shift := start - int(first[0])
			assert_true(absi(shift) <= MOVE_SHIFT, "%s move %d starts %+d ticks from the original's" % [tag, k, shift])
			var bad := []
			for w in wm[k]:
				var t := int(w[0]) + shift
				if at.get(t, -1) != int(w[1]):
					bad.append([int(w[0]) - int(first[0]), int(w[1]), at.get(t, -1)])
			assert_eq(bad, [], "%s move %d: [tick of move, original, ours] that differ" % [tag, k])
		assert_eq(gs.back().slice(1), ws.back().slice(1).map(func(x: Variant) -> int: return int(x)), \
				tag + ": last state")


func test_pages_like_the_original() -> void:
	_check("td_pages")


func test_teams_and_pads_like_the_original() -> void:
	_check("td_teams")


# --- the ports underneath ------------------------------------------------------------------------
## The coach page's drop as the original moved it (BlastEm / GPGX traces):
## z (1/256 px) and z speed after so many ticks from (0, 0, 160) at -200.
## Plan 34: the pages read every pad (`$C28E`) - in an extended set-up
## every player's, so players 5-12 (over a match one of them paused) turn
## the pages and leave too; in the original's set-ups pads 1-4.
func test_players_5_to_12_count_in_an_extended_set_up() -> void:
	if not need_rom():
		return
	var td := (load(MwScreens.scene_path(2)) as PackedScene).instantiate() as MwTeamDescription
	td.session = MwSession.new(1, 1)
	var press := MwInputFrame.make({MwVerbs.menu_action(9, "ui_info_return"): true}, {})
	assert_eq(td._pads(press), 0, "the original's set-up: player 9 on no pad")
	for p in [1, 2, 3]:
		td.session.humans.set_team(p, 0)
	td.session.humans.set_team(9, 1)
	td.session.pad_map = td.session.humans.pad_players(rom)
	assert_eq(td._pads(press), 0x80, "an extended set-up: player 9's Start")
	td.free()


func test_motion_drop_and_bounces() -> void:
	var params := MwMotion.Params.new(-32, 0x60, 0, 0)
	var motion := MwMotion.new()
	motion.init(0, 0, 160)
	motion.vel[2] = -200
	var want := {2: [40528, -264], 45: [280, -1640], 46: [0, 627], 66: [6460, -13], 86: [0, 244], 93: [0, 20]}
	var t := 0
	for k in [2, 45, 46, 66, 86, 93]:
		motion.step(params, k - t)
		t = k
		assert_eq([motion.pos[2], motion.vel[2]], want[k], "after %d ticks" % k)


func test_motion_rise_and_chunks() -> void:
	var params := MwMotion.Params.new(-32, 0x60, 0, 0)
	var per_tick := MwMotion.new()
	var motion := MwMotion.new()
	per_tick.vel[2] = 0x708
	motion.vel[2] = 0x708
	for i in 31:
		per_tick.step(params, 1)
	motion.step(params, 31)                       # in chunks of 8: the same z
	assert_eq([per_tick.pos[2], per_tick.vel[2]], [40920, 808])
	assert_eq([motion.pos[2], motion.vel[2]], [40920, 808])


func test_motion_friction_matches_the_68000_arithmetic() -> void:
	# x with friction 16/256: the speed decays by the factor table (mulu,
	# lsr 8), the position moves by the lost speed / friction (divs)
	var params := MwMotion.Params.new(0, 0, 16, 16)
	assert_eq(params.ground.slice(0, 3), PackedInt32Array([240, 225, 210]))
	var motion := MwMotion.new()
	motion.vel[0] = 1000
	motion.step(params, 1)
	assert_eq([motion.pos[0], motion.vel[0]], [1008, 937])
	motion.vel[0] = -1000
	motion.pos[0] = 0
	motion.step(params, 2)
	assert_eq([motion.pos[0], motion.vel[0]], [-1952, -878])


func test_text_box_wraps_words() -> void:
	if not need_rom():
		return
	var plane := RomPlane.new()
	add_child_autofree(plane)
	var font := MwPlanePainter.FONT_MENU
	var space := MwGfx.u16(rom, font + 2)
	var a := MwGfx.char_width(rom, font, 0x41)
	var box := MwTextBox.new(plane, font, Rect2i(2, 3, 6 * a + space, 10))
	box.write(rom, "AAA AAA".to_ascii_buffer(), 0x60)
	assert_eq([box.cursor_x, box.cursor_y], [6 * a + space, 0], "two words fit")
	box.write(rom, " A".to_ascii_buffer(), 0x60)
	var line_h := MwGfx.u16(rom, font)
	assert_eq([box.cursor_x, box.cursor_y], [a, line_h], "the next word wraps")
	box.write(rom, "\nA".to_ascii_buffer(), 0x60)
	assert_eq([box.cursor_x, box.cursor_y], [a, 2 * line_h], "newline")
	box.home()
	assert_eq([box.cursor_x, box.cursor_y], [0, 0])


func test_star_quotes() -> void:
	if not need_rom():
		return
	var e := MwPortrait.star_entry(rom, MwTeams.player(rom, 22, 0))
	assert_ne(e, 0, "team 22's first player is a star")
	var quote := MwQuotes.pick(rom, MwTeamDescription.STAR_QUOTES, 2, MwGfx.u16(rom, e + 8), MlhRng.new(1))
	assert_gt(quote["template"].size(), 20)
	assert_eq(MwQuotes.expand("A @ B {".to_ascii_buffer(), {"@": "x".to_ascii_buffer(), "{": "yz".to_ascii_buffer()}),
			"A x B yz".to_ascii_buffer())
