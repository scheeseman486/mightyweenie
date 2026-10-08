class_name MwTeamPanel
extends Node2D
## One of the main menu's two team panels (`$1315A`; docs/re/menus.md, Team
## panels). A cycle: the team's logo (drawn for 174 ticks; after 180 the
## next player), then a player - a star's talking portrait for 180 ticks, or
## a skater's little routine of four steps - then the logo again; five
## players, then from the first again. Below the panel, one icon per
## featured player (team record +$0B).
##
## Configured from the original's panel records (`$1F2A2` team A, `$1F2EA`
## team B; 72 bytes):
## [codeblock]
## +4 logo x, +6 y, +8 depth, +A attr   +E icon column offset
## +16/+18/+1A skater start x, y, z     +1C sprite attr (palette line)
## +1E skater direction (angle)         +20..+26 portrait x, y, depth, attr
## +30..+3C the skater's four steps (anim ID, variant, speed, distance)
## [/codeblock]

const CONFIGS := [0x1F2A2, 0x1F2EA]
const LOGO_RING := 0x249C8
const LOGO_TICKS := 0xAE
const PHASE_TICKS := 0xB4
const PORTRAIT_TICKS := 0xB4
const PLAYERS := 5
const ICON_POS := 0x13152            ## x, y, depth, attr (x + 12 * i + column * 8)
const ICON_ANIM := 0x3EA6E
const STEP_RANDOM := 0x1F296         ## the third step's template; anim ID from:
const STEP_RANDOM_IDS := 0x1F29E     ## [aux rng & 2]
const MOTION_ARRIVED := 4            ## a step ends this close to its target x
const PORTRAIT_SIZE := 2
## The panels' windows (screen pixels, inside their black outlines: x
## 33-110 / 209-286, y 8-98). The skater shows only inside its panel's
## window: the original hides it outside by running into the VDP's per-line
## sprite limit; here a clip rectangle does it (owner: not the quirk).
const WINDOWS := [Rect2i(33, 8, 78, 91), Rect2i(209, 8, 78, 91)]

var menu: MwMainMenu
var index := 0
var config := 0
var rom: PackedByteArray
var team := 0
## The original's (a3): -1 restart, 0 logo, 4..16 skater step, 100 portrait.
var state := -1
var slot := 0                 ## +2 / 4: the player shown (0-4)
var icon := 0                 ## +$42
var icon_elapsed := 0         ## +$48
var portrait_elapsed := 0     ## +$4A
var started := 0              ## +$66
var target_x := 0             ## +$4C
var team_colours := false     ## lines 1/2: panel colours (false) or team line
## The skater's motion (24.8 fixed point, 1/256 px per tick).
var pos := Vector2i.ZERO
var vel := Vector2i.ZERO
var steps: Array[PackedInt32Array] = []

@onready var logo: RomSprite = $Logo
@onready var ring: RomSprite = $Ring
var icons: Array[RomSprite] = []
var skater := RomSprite.new()
## The skater's clip: its panel's window ([constant WINDOWS]).
var skater_clip := Control.new()
var portrait := MwPortrait.new()


func _init() -> void:
	skater_clip.name = "SkaterClip"
	skater_clip.clip_contents = true
	skater_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skater_clip.add_child(skater)
	add_child(skater_clip)
	add_child(portrait)


func setup_panel(main_menu: MwMainMenu, which: int) -> void:
	menu = main_menu
	index = which
	config = CONFIGS[which]
	rom = menu.rom
	var pal := menu.palette
	if icons.is_empty():
		for i in 6:
			var s := RomSprite.new()
			s.tick_driven = true
			s.palette = pal
			s.anim = "%x" % ICON_ANIM
			add_child(s)
			icons.append(s)
		skater.tick_driven = true
		skater.only_variant = true
		skater.palette = pal
		portrait.set_palette(pal)
		move_child(skater_clip, -1)          # drawn over the logo and icons
		move_child(portrait, -1)
	var window: Rect2i = WINDOWS[which]
	skater_clip.position = Vector2(window.position)
	skater_clip.size = Vector2(window.size)
	skater.visible = false
	portrait.attr = cfg(0x1C)
	portrait.rng = menu.session.rng
	logo.attr_xor = cfg(0xA)
	ring.attr_xor = cfg(0xA)
	ring.frame_addresses = PackedInt32Array([LOGO_RING])
	logo.position = Vector2(cfg(4), cfg(6))
	ring.position = Vector2(cfg(4) - 16, cfg(6) - 7)
	skater.attr_xor = cfg(0x1C)
	steps.clear()
	for k in 4:
		var a := MwGfx.u32(rom, config + 0x30 + 4 * k)
		var st := PackedInt32Array()
		if a < 0xFF0000:
			for w in 4:
				st.append(MwGfx.s16(rom, a + 2 * w))
		steps.append(st)


func cfg(off: int) -> int:
	return MwGfx.s16(rom, config + off)


## Lines 1 / 2 of the palette: the panel colours (`$23B0`) or, while a
## player is shown, the team line (`$2272` team A in colours, `$2284` team B
## plain).
func palette_steps() -> PackedStringArray:
	if menu == null:
		return PackedStringArray()
	var line := (cfg(0x1C) & 0x60) >> 5
	var who := "a" if index == 0 else "b"
	if team_colours:
		return PackedStringArray(["team_line %s %d %d" % [who, line, 1 if index == 0 else 2]])
	return PackedStringArray(["panel_line %s %d" % [who, line]])


## `$13072`: start over with [param t] (its featured players' icons). A
## player being shown goes: the original draws its portrait or skater from
## the panel's state each pass, so neither stays on screen (nor the
## portrait's voice).
func reset(t: int) -> void:
	team = t
	state = -1
	portrait.hide_now()                 # no `$B656` here: its voice plays on
	skater.visible = false
	logo.frame_addresses = PackedInt32Array([MwTeams.logo_frame(rom, t)])
	for i in icons.size():
		icons[i].visible = i < count()


func count() -> int:
	return MwTeams.featured(rom, team)


func _player_record(s: int) -> int:
	return MwTeams.player(rom, team, s)


func step(elapsed: int) -> void:
	if menu == null:
		return
	var now := menu.idle_clock()
	for i in mini(count(), icons.size()):        # the icons
		icons[i].position = Vector2(MwGfx.u16(rom, ICON_POS) + 12 * i + cfg(0xE) * 8, MwGfx.u16(rom, ICON_POS + 2))
		icons[i].attr_xor = MwGfx.u16(rom, ICON_POS + 6)
	if state < 0:
		slot = 0
		icon = 0
		_logo_phase(now)
	if state == 0:
		_logo_step(now)
	elif state > 0x14:
		_portrait_step(now)
	else:
		_skater_step(now)
	var _e := elapsed


## `$131A0`: the logo again (panel colours, timer, the team's name).
func _logo_phase(now: int) -> void:
	state = 0
	team_colours = false
	menu._update_palette()
	started = now
	menu._draw_row(index)
	icon_elapsed = 0
	if icon < icons.size():
		icons[icon].state = null
		icons[icon].rebuild()
	skater.visible = false


func _logo_step(now: int) -> void:
	var d := now - started
	logo.visible = d < LOGO_TICKS
	ring.visible = d < LOGO_TICKS
	if count() > 0 and icon < icons.size():
		icons[icon].advance(d - icon_elapsed)
		icon_elapsed = d
	if d <= PHASE_TICKS:
		return
	team_colours = true
	menu._update_palette()
	icon = (icon + 1) % count() if count() > 0 else 0
	state = 4
	logo.visible = false
	ring.visible = false
	var record := _player_record(slot)
	if MwPortrait.star_entry(rom, record) != 0:
		portrait.set_player(rom, record, PORTRAIT_SIZE)
		var r := menu.session.rng_aux.next_state() & 0xF
		portrait.start(r & (r >> 2))
		portrait.place(Vector2(cfg(0x20), cfg(0x22)))
		menu.rows.draw_name(menu.plane, index, MwGfx.rom_string(rom, MwGfx.u32(rom, record)), menu.current == index)
		state = 100
		started = now
		portrait_elapsed = 0
		_portrait_step(now)
		return
	pos = Vector2i(cfg(0x16) << 8, cfg(0x18) << 8)
	vel = Vector2i.ZERO
	var tmpl := PackedInt32Array()
	for w in 4:
		tmpl.append(MwGfx.s16(rom, STEP_RANDOM + 2 * w))
	tmpl[0] = MwGfx.u16(rom, STEP_RANDOM_IDS + (menu.session.rng_aux.next_state() & 2))
	steps[2] = tmpl
	_skater_setup(now)


func _portrait_step(now: int) -> void:
	var d := now - started
	if d >= PORTRAIT_TICKS:
		_end_player(now)
		return
	portrait.advance(d - portrait_elapsed)
	portrait_elapsed = d


## `$13332`: set up the skater's step for the current state.
func _skater_setup(now: int) -> void:
	while true:
		var record := _player_record(slot)
		if state == 8:
			menu.rows.draw_name(menu.plane, index, MwGfx.rom_string(rom, MwGfx.u32(rom, record)), menu.current == index)
		if state == 0x10:
			menu._draw_row(index)
		var st: PackedInt32Array = steps[(state >> 2) - 1]
		if not st.is_empty():
			skater.anim = "%x" % MwPlayerAnims.anim(rom, record, st[0])
			skater.variant = st[1]
			skater.rebuild()
			skater.restart()
			vel = MwTrig.polar(rom, cfg(0x1E) & 0xFF, st[2])
			target_x = RomStarfield.asr8(pos.x) + (st[3] if cfg(0x1E) == 0 else -st[3])
			started = now
			_skater_step(now)               # drawn in the same pass
			return
		state += 4
		if state >= 0x14:
			_end_player(now)
			return


func _skater_step(now: int) -> void:
	var x := RomStarfield.asr8(pos.x)
	if skater.is_running() and absi(x - target_x) > MOTION_ARRIVED:
		var e := now - started
		started = now
		pos += vel * e
		skater.advance(e)
		skater.position = Vector2(RomStarfield.asr8(pos.x), RomStarfield.asr8(pos.y)) - skater_clip.position
		skater.visible = true
		return
	state += 4
	if state < 0x14:
		_skater_setup(now)
	else:
		_end_player(now)


## `$133E8`: the next player (after the fifth, the first).
func _end_player(now: int) -> void:
	portrait.stop()
	skater.visible = false
	slot += 1
	if slot >= PLAYERS:
		slot = 0
		icon = 0
	_logo_phase(now)
	_logo_step(now)
