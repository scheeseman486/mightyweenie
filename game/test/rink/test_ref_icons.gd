extends "res://test/rom/rom_test_base.gd"
## The ref icons (penalty `$C2DC`, stoppage `$C3C8`): set up once at
## power-on (`boot_init` `$20C0`: `$A27C`, `$C7F8`), kept from then on. A
## live match without them drew the stoppage icon's animation from ROM
## address 0 when icing was pending: a runaway frame of garbage pieces.

var host: Node


func after_each() -> void:
	if host:
		host.free()
		host = null


func _icon_ok(o: MwRinkState.Overlay, what: String) -> void:
	assert_eq(o.anim.address, MwGfx.u32(rom, MwRinkMatch.PORTRAITS + 8 * 4), what + ": the ref's animation")
	assert_eq([o.x, o.y, o.depth, o.attr, o.flags], [240, 16, 0xFFFF, 0xA0, 1], what + ": screen (240, 16), small border, hidden")


func test_boot_set_ups() -> void:
	if not need_rom():
		return
	var s := MwRinkState.new()
	var sim := MwRinkSim.new(rom, s)
	MwRinkMatch.boot_icons(sim)
	_icon_ok(s.penalty, "penalty")
	_icon_ok(s.stoppage, "stoppage")
	assert_ne(s.penalty.anim.flags & MwAnimState.PLAYING, 0, "`$A290`: the penalty icon's animation plays")


func test_a_pending_icing_draws_the_icon() -> void:
	if not need_rom():
		return
	var s := MwRinkState.new()
	var sim := MwRinkSim.new(rom, s)
	MwRinkMatch.start(sim, 3, 3, 7, 0, false, 2)
	MwRinkMatch.boot_icons(sim)
	s.phase = MwRinkState.PHASE_PLAY
	s.puck_rule = 1
	s.stoppage.flags |= 0x80
	var d := MwRinkDraw.new(rom)
	d.build(s)
	assert_between(d.head.size(), 2, 20, "the small border and the ref (%d pieces)" % d.head.size())
	for h: Array in d.head:
		assert_between(int(h[0]) - MwRinkDraw.SPRITE_ORIGIN, 200, 300, "near x 240")
		assert_between(int(h[1]) - MwRinkDraw.SPRITE_ORIGIN, -20, 60, "near y 16")


func _rink(session: MwSession) -> MwRink:
	var fader := MwScreenFader.new()
	host.add_child(fader)
	var router := MwRouter.new(host, fader)
	router.session = session
	router.input = MwLiveInput.new()
	var rink := (load(MwScreens.scene_path(4)) as PackedScene).instantiate() as MwRink
	rink.screen_id = 4
	router.adopt(rink, {"new_match": true})
	return rink


func test_the_live_game_sets_them_up_and_keeps_them() -> void:
	if not need_rom():
		return
	host = Node.new()
	add_child(host)
	var session := MwSession.new(0x61F2415D, 0x1234567)
	var first := _rink(session)
	_icon_ok(first.state.stoppage, "a session's first match")
	var first_state := first.state
	var penalty := first_state.penalty
	var stoppage := first_state.stoppage
	host.free()
	host = Node.new()
	add_child(host)
	var second := _rink(session)
	assert_ne(second.state, first_state, "a new match")
	assert_same(second.state.penalty, penalty, "the icons carried on, as from power-on")
	assert_same(second.state.stoppage, stoppage)
