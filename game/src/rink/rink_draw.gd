class_name MwRinkDraw
extends RefCounted
## The rink's draw pass (`$FA54`-`$FB16`; docs/re/rink.md, Draw pass),
## node-free: from an [MwRinkState] it makes the original's sprite list.
##
## The original draws by calling `draw_frame` ($A07E: a ROM frame at a
## point, with a depth and an attr XOR) for everything on the ice, each
## frame adding its pieces with `add_sprite_piece` ($156C6). Pieces are kept
## in a list sorted by depth (unsigned, higher in front; at equal depth the
## later piece goes in front), which becomes the VDP's sprite link order.
## Pieces whose top-left corner is more than 32 px off the top or left, or
## off the right or bottom, are dropped, and at most 79 are kept.
##
## Order of the draws: the ref icons (screen space), the phase handler's
## overlays and sprites (plan 09: [member MwRinkPhases.sprite_ops] - the
## FACE OFF! letters, the coach portrait, the speech bubble's tail - or
## recorded pieces), team A then team B (per player:
## body, airborne shadow, weapon or impale overlay, then the off-screen
## arrow and the marker), the puck, the rink (nets, in-ice hazards, rink
## objects, lamp stands, lamps), the faceoff portrait.
##
## Plan 34, extended set-ups (MwRinkState.extended): every player's marker,
## info plate and off-screen arrow - players 5-12's in their colours
## (MwPlayerColours: pad 1's crossbones and arrow on a palette line of their
## own, [constant PORT_LINE]) and plates past the original's four
## ([constant PORT_BANK]) - drawn where the original draws its pads' ([method
## _port_marks]); kept apart in [member port_calls], not the replay ring's
## records (the ring keeps a team's two markers; MwRinkUpdate keeps these
## in the frame's port side-record).
## Short names: t a team (MwRinkState.Team).

const MAX_COUNT := 0x50              ## the list's count stops here (entry 0 is the head)
## Plan 34: an extended set-up's list holds more (up to twelve players'
## markers, plates and tags beside the original's two a team): the port's,
## no VDP behind it.
const MAX_COUNT_EXTENDED := 0x100
const SPRITE_ORIGIN := 0x80          ## VDP sprite coordinates of screen (0, 0)
const CLIP_MIN := 0x60
const CLIP_X := 0x1C0
const CLIP_Y := 0x160

const SHADOW := 0x3C8A4              ## player shadow (airborne only)
const PUCK_SHADOW := 0x3C8CC
const POSSESSION := 0x3C25C          ## arcs under the puck carrier
const CROSSBONES := 0x1C5C2          ## frames: CPU carrier, pads 1-4
const PLATES := 0x1C59C              ## one-piece frames on the RAM plate tiles, 8 bytes per slot
const PLATE_TILES := 0x5F4           ## VRAM tile of plate 0 (8 tiles per plate)
const WEAPON_ANIMS := 0x1BAA6        ## by weapon 0-4
const IMPALE_ANIM := 0x3C042
const IMPALE_ANIM_2 := 0x3C058       ## species 2
const HAZARD_FRAMES := 0x1C88E       ## by kind - 1: frame.l, half width.w, half height.w
const OBJECT_KINDS := 0x1C626        ## by kind - 1: animation.l, attr.w
const STANDS := [0x1C524, 0x1C52C]   ## x, y, z, attr of the lamp stands (top, bottom)
const STAND_FRAME := 0x3DC6C
const LAMP_RAISE := [0xC00, 0x2D00]  ## lamp z offsets while drawn (bottom, top)
const BORDER := 0x20370
const SMALL_BORDER := 0x3C88A
const ARROW_DIRECTIONS := 0x1F618    ## outcode -> direction
const ARROW_POINTS := 0x1C4A8        ## by direction: x.w, y.w (-1 = the player's)
const PUCK_ANIM := 0x3C8D4
const DEPTH_SHADOW := 2
const DEPTH_MARKER := 3
const DEPTH_ARROW := 0x7FFF
const DEPTH_TOP := 0xFFFF
const PORTRAIT_BORDERS := 0x1CDF6    ## the coach portrait's border frames, by size - 1
## Plan 34: the port's bits above the original's attrs (words, which never
## reach them): a palette line beyond the four (bits 16-19: players 5-12's
## crossbones and arrows on lines 4-11 - the rink palette's "player_lines",
## RomPalette) and a bank of RAM tiles (bits 20-23: + 32 tiles a bank, the
## info plates past the original's four slots, the players' number tags, the
## owners' hollow marks and the captains' C, MwPlate.ram_tiles).
const PORT_LINE := 0x10000
const PORT_BANK := 0x100000
const PORT_BITS := 0xFF0000
## Plan 34: where a player's number tag goes from their marker's point (the
## plate's frame drawn there: the tag's digits right of the plate's number).
const TAG_AT := Vector2i(37, 0)
## Plan 34: where the owners' hollow mark's plate frame goes from a player's
## ground point (the ring, MwPlate.RING, centred where the crossbones are).
const RING_AT := Vector2i(-1, -13)
## Plan 38: the port line of team A's coach in colours of his own (team B's
## the next), after plan 34's players' lines 4-11 ([member portrait_lines]).
const COACH_LINE := 12

## The list's cap ([constant MAX_COUNT]; an extended set-up's
## [constant MAX_COUNT_EXTENDED]).
var cap := MAX_COUNT
## The penalty icon at `$A5EC`'s draw (`$AFBC`): 1 shown, 0 hidden, -1 as the
## state has it at the draw pass ([method MwRinkUpdate.penalties] sets it).
var penalty_shown := -1
## Port only (plan 38): the palette lines the coach portrait's pieces go
## to, by the line their attr names ({1: 12}): a custom coach with colours of
## his own drawn on a port line ([constant PORT_LINE]) that has them (the
## screen's palette carries it, RomPalette "coach_line"); empty: none.
var portrait_lines := {}
var rom: PackedByteArray
var state: MwRinkState
## `draw_frame` calls in order: [x, y, depth, attr, frame] (sprite coordinates).
var calls: Array = []
## Plan 34: an extended set-up's marker, plate and arrow draws (the same
## form; [method _port_marks]): not the original's, so not [member calls].
var port_calls: Array = []
var _port := false
## Plan 36 (the load model, MwPassLoad): the pieces that made it into the
## list (past the clip and the list's size: the ones the original hands the
## sprite tile cache), in order, and where each part of the pass ended -
## part name -> [adds, calls, inserted] counts at its end.
var inserted: Array = []
## Plan 36: entries passed over by the depth-sorted inserts (`$156C6`'s list walk).
var steps := 0
var marks := {}
var _port_adds := 0                      # plan 34's marks among [member adds] (not the original's)
## `add_sprite_piece` calls in order: [x, y, depth, attr, piece address]
## (the phase handler's pieces passed in as pieces are not repeated here).
var adds: Array = []
## The pieces added before the teams' (the ref icons, the phase handler's
## overlays, sprites and pieces), in order: [x, y, depth, attr, piece] -
## what the original adds from `$A5EC` to the phase handler's return.
var head: Array = []
## Called before the pass reads the tick counter (a human goalie's arrow
## blinks with tick bit 4): comparisons set the tick the original read.
var on_tick := Callable()

# the list: entry 0 is the head; each entry [x, y, size, attr byte, tile word, depth]
var _entries: Array = []
var _links := PackedInt32Array()
var _depths := PackedInt32Array()     # each entry's depth (plan 42: the insertion's walk reads these)


func _init(rom_: PackedByteArray) -> void:
	rom = rom_


## An empty sprite list: the head entry alone (the list, its links and its
## depths kept in step - plan 42: the insertion's walk reads the depths).
func start_list() -> void:
	_entries = [[0, 0, 0, 0, 0, 0]]
	_links = PackedInt32Array([0])
	_depths = PackedInt32Array([0])


## Runs the draw pass for [param s]. [param phase_adds] are recorded
## `add_sprite_piece` calls of the phase handler ([x, y, depth, attr,
## piece]; playback). [param rules_phase]: the phase when the puck rules
## ran, if the phase handler changed it afterwards in this pass (-1: the
## state's). [param phase_overlays]: overlays the phase handler draws
## ([overlay, with camera]; e.g. the stoppage icon in phase 8), drawn
## before its sprites [param phase_sprites] ([member
## MwRinkPhases.sprite_ops]). Returns [method sprites].
func build(s: MwRinkState, phase_adds: Array = [], rules_phase := -1, phase_overlays: Array = [],
		phase_sprites: Array = []) -> Array:
	_head(s, rules_phase, phase_overlays, phase_sprites)
	head = adds.duplicate()
	for a in phase_adds:
		_insert(int(a[0]), int(a[1]), int(a[2]), int(a[3]), int(a[4]))
		head.append([int(a[0]), int(a[1]), int(a[2]) & 0xFFFF, int(a[3]), int(a[4])])
	_part_end("phase")
	for i in s.teams.size():
		_team(s.teams[i])
		_part_end("team_a" if i == 0 else "team_b")
	_puck()
	_part_end("puck")
	_rink()
	_part_end("rink")
	_overlay(s.faceoff, s.phase == MwRinkState.PHASE_FACEOFF)
	_part_end("portrait")
	return sprites()


## Plan 36: where part [param part] of the draw pass ends ([member marks]).
func _part_end(part: String) -> void:
	marks[part] = [adds.size() - _port_adds, calls.size(), inserted.size(), steps]


## The pieces the draw pass adds before the teams' ([member head] without
## recorded pieces) for [param s] - the rest of the pass not run (a pass
## the phase handler leaves the rink in draws nothing).
func head_pieces(s: MwRinkState, rules_phase := -1, phase_overlays: Array = [], phase_sprites: Array = []) -> Array:
	_head(s, rules_phase, phase_overlays, phase_sprites)
	return adds.duplicate()


## A new list; the ref icons (`$A5EC`, `$C84A`), the phase handler's
## overlays and sprites.
func _head(s: MwRinkState, rules_phase: int, phase_overlays: Array, phase_sprites: Array) -> void:
	state = s
	cap = MAX_COUNT_EXTENDED if s.extended else MAX_COUNT
	calls = []
	port_calls = []
	adds = []
	inserted = []
	steps = 0
	_port_adds = 0
	marks = {}
	start_list()
	# the penalty icon as `$A5EC` saw it (the phase handler shows and hides it later in the pass)
	var keep := s.penalty.flags
	if penalty_shown >= 0:
		s.penalty.flags = (keep | 0x80) if penalty_shown else (keep & ~0x80)
	_overlay(s.penalty, false)
	s.penalty.flags = keep
	var ph := s.phase if rules_phase < 0 else rules_phase
	if ph == MwRinkState.PHASE_PLAY and s.puck_rule != 0:     # `$C84A` (states 0-1 draw it)
		_overlay(s.stoppage, false)
	for o in phase_overlays:
		_overlay(o[0], o[1])
	for op in phase_sprites:
		phase_sprite(op)


## The list in link order (front first): [x, y, size, attr byte, tile word,
## depth], sprite coordinates.
func sprites() -> Array:
	var out := []
	var i := _links[0]
	while i != 0:
		out.append(_entries[i])
		i = _links[i]
	return out


# --- the original's primitives ----------------------------------------------------------

## `$5AC2`: rink point -> map point and depth (words).
func project(x: int, y: int, z: int) -> Vector3i:
	return project_on(state, x, y, z)


## [method project] for state [param s] (presentation helpers).
static func project_on(s: MwRinkState, x: int, y: int, z: int) -> Vector3i:
	if s.projection != 0:
		var ax := -absi(x)
		var my := MwRinkSim.s16(ax + 0x179 - z)
		return Vector3i(MwRinkSim.s16(y + 0xA0), my, MwRinkSim.s16(my + z))
	var my2 := MwRinkSim.s16(y + 0x1CD - z)
	return Vector3i(MwRinkSim.s16(x + 0x100), my2, MwRinkSim.s16(my2 + z))


## `$14712`: map point -> sprite coordinates (camera = plane B's, or none).
func to_sprite(point: Vector3i, with_camera := true) -> Vector3i:
	var c := state.camera.shown if with_camera else Vector2i.ZERO
	return Vector3i(MwRinkSim.s16(point.x - c.x + SPRITE_ORIGIN), MwRinkSim.s16(point.y - c.y + SPRITE_ORIGIN), point.z)


## `draw_frame` ($A07E).
func draw_frame(x: int, y: int, depth: int, attr: int, frame: int) -> void:
	(port_calls if _port else calls).append([x, y, depth & 0xFFFF, attr, frame])
	for i in MwGfx.u16(rom, frame):
		add_piece(x, y, depth, attr, frame + 2 + 6 * i)


## `$15666`: frame [param frame] of [param variant] of animation [param anim]
## (the variant's flips XORed into the attr).
func draw_anim_frame(anim: int, variant: int, frame: int, x: int, y: int, depth: int, attr: int) -> void:
	var f := MwAnimState.frame_address_of(rom, anim, variant, frame)
	draw_frame(x, y, depth, attr ^ (f.y << 3), f.x)


## `$14444`: an animation object at a sprite point.
func draw_anim(anim: MwAnimState, point: Vector3i, attr: int) -> void:
	draw_anim_frame(anim.address, anim.variant, anim.frame, point.x, point.y, point.z, attr)


## `$141C8`: an actor at its position through a projection, with the camera.
func draw_actor(actor: MwRinkState.Actor, attr: int, top_above := -1) -> void:
	var px := actor.motion.pixels()
	var point := project(px.x, px.y, px.z)
	if top_above >= 0 and px.z > top_above:      # `$60C4`
		point.z = DEPTH_TOP
	draw_anim(actor.anim, to_sprite(point), attr)


## `add_sprite_piece` ($156C6).
func add_piece(x: int, y: int, depth: int, attr: int, piece: int) -> void:
	adds.append([x, y, depth & 0xFFFF, attr, piece])
	if _port:
		_port_adds += 1                  # plan 36: not the original's work
	_insert(x, y, depth, attr, piece)


## The port's input glyph [param cells] (MwGlyphs: one row of tiles, up to
## 4) as one sprite centred on where [param piece] would be drawn at (x, y)
## (plan 23: the special plays' A / B / C buttons), on the glyphs' line.
func add_glyph(x: int, y: int, depth: int, attr: int, piece: int, cells: PackedInt32Array) -> void:
	if cells.is_empty():
		return
	var size := rom[piece + 2]
	var cx := x + MwGfx.s8(rom, piece) + 4 * (((size >> 2) & 3) + 1)
	var cy := y + MwGfx.s8(rom, piece + 1) + 4 * ((size & 3) + 1)
	var n := mini(cells.size(), 4)
	if _entries.size() >= cap:
		return
	var d := depth & 0xFFFF
	var at := _entries.size()
	_entries.append([cx - 4 * n, cy - 4, (n - 1) << 2, (attr & 0x80) | (MwGlyphs.LINE << 5), cells[0], d])
	_links.append(0)
	_depths.append(d)
	var prev := 0
	var i := _links[0]
	while i != 0 and d < _depths[i]:
		prev = i
		i = _links[i]
	_links[at] = i
	_links[prev] = at


## A sprite list entry ([x, y, size, attr, tile, depth], sprite coordinates)
## for the port's glyph [param cells] centred on screen pixel (cx, cy), high
## priority, on the glyphs' line (plan 23; the list's front).
static func glyph_entry(cells: PackedInt32Array, cx: int, cy: int) -> Array:
	var n := mini(cells.size(), 4)
	return [cx - 4 * n + SPRITE_ORIGIN, cy - 4 + SPRITE_ORIGIN, (n - 1) << 2, 0x80 | (MwGlyphs.LINE << 5), cells[0], 0]


func _insert(x: int, y: int, depth: int, attr: int, piece: int) -> void:
	var entry := piece_entry(rom, x, y, depth, attr, piece)
	var ex: int = entry[0]
	var ey: int = entry[1]
	if ex < CLIP_MIN or ex >= CLIP_X:
		return
	if ey < CLIP_MIN or ey >= CLIP_Y:
		return
	if _entries.size() >= cap:
		return
	var d: int = entry[5]
	var n := _entries.size()
	_entries.append(entry)
	_links.append(0)
	_depths.append(d)
	if not _port:
		inserted.append(piece)           # plan 36: the original's pieces only
	# insert before the first entry whose depth <= ours
	var prev := 0
	var i := _links[0]
	while i != 0 and d < _depths[i]:
		prev = i
		i = _links[i]
		if not _port:
			steps += 1
	_links[n] = i
	_links[prev] = n


# --- the phase handler's sprites ---------------------------------------------------------

## One of the phase handler's sprites ([member MwRinkPhases.sprite_ops],
## screen pixels: the window plane's, whose scroll is 0).
func phase_sprite(op: Array) -> void:
	match str(op[0]):
		"sprite_text":
			text_sprites(int(op[1]), int(op[2]), int(op[3]), int(op[4]), int(op[5]), op[6])
		"portrait":
			portrait(int(op[1]), int(op[2]), int(op[3]), int(op[4]), int(op[5]), int(op[6]), int(op[7]), int(op[8]))
		"piece":
			var piece_point := to_sprite(Vector3i(int(op[2]), int(op[3]), 0), false)
			add_piece(piece_point.x, piece_point.y, int(op[5]), int(op[4]), int(op[1]))
		"glyph":
			# ["glyph", piece, x, y, attr, depth, cells]: the port's input glyph
			# (plan 23) centred where piece would have been
			var point := to_sprite(Vector3i(int(op[2]), int(op[3]), 0), false)
			add_glyph(point.x, point.y, int(op[5]), int(op[4]), int(op[1]), op[6])
		"referee":
			draw_actor(state.referee, int(op[1]))      # `$EFB4`
		_:
			push_warning("MwRinkDraw: unknown phase sprite %s" % str(op[0]))


## `draw_text_sprites` ($F3CC) with no plane (screen pixels): each glyph
## of [param text] (a ROM address or bytes) in [param font] a sprite piece
## at ([param x], [param y]), x moving on by the glyph's width (a space by
## the font's). Quirk (kept): the glyph lookup `$14BA0` leaves Z set for
## glyph 0 (its last `add.w d0,d0`), which `$F3CC` takes for "no glyph":
## that character is neither drawn nor advanced over ("OFF!"'s `!` in font
## `$246FA`).
func text_sprites(font: int, x: int, y: int, attr: int, depth: int, text: Variant) -> void:
	var b: PackedByteArray = MwGfx.rom_string(rom, int(text)) if text is int else text
	var point := to_sprite(Vector3i(x, y, depth), false)
	var px := point.x
	for c in b:
		var advance := 8 * MwGfx.char_width(rom, font, c)
		if c != 0x20:
			var g := MwGfx.font_glyph(rom, font, c)
			if g <= 0:
				continue                         # glyph 0 (or none: never in the ROM's strings)
			add_piece(px, point.y, depth, attr, font + 8 + 6 * g)
		px = MwRinkSim.s16(px + advance)


## `$B70C` on the window plane: the coach portrait object (as drawn:
## [param anim], [param variant], [param frame], [param size]) at screen
## ([param x], [param y]) - its border (`$1CDF6` by size, none for size 0)
## one pixel right with the attr's line 3, then the animation's frame.
func portrait(x: int, y: int, depth: int, attr: int, anim: int, variant: int, frame: int, size: int) -> void:
	var point := to_sprite(Vector3i(x, y, depth), false)
	if size != 0:
		draw_frame(MwRinkSim.s16(point.x + 1), point.y, depth, attr | 0x60,
				MwGfx.u32(rom, PORTRAIT_BORDERS + 4 * (size - 1)))
	var a := attr
	if portrait_lines.has((attr >> 5) & 3):
		a |= PORT_LINE * int(portrait_lines[(attr >> 5) & 3])
	draw_anim_frame(anim, variant, frame, point.x, point.y, depth, a)


# --- what the rink draws -----------------------------------------------------------------

## `$AFBC`: an overlay's border, then its animation.
func _overlay(overlay: MwRinkState.Overlay, with_camera: bool) -> void:
	if not overlay.shown():
		return
	var bx := overlay.x
	var by := overlay.y - 2
	var border := BORDER
	if overlay.flags & 1:
		border = SMALL_BORDER
		by += 3
		bx += 1
	var b := to_sprite(Vector3i(bx, by, overlay.depth), with_camera)
	draw_frame(b.x, b.y, overlay.depth, overlay.attr | 0x60, border)
	draw_anim(overlay.anim, to_sprite(Vector3i(overlay.x, overlay.y, overlay.depth), with_camera), overlay.attr)


## `$38E0`: a team's players with their arrows and markers (plan 34, an
## extended set-up: [method _port_marks]; owners and captains: [method
## _control_marks]).
func _team(t: MwRinkState.Team) -> void:
	for p in t.players:
		if not p.present:
			continue
		_player(p, t.attr)
		if state.phase == MwRinkState.PHASE_REF:
			continue
		if state.control != null:
			_control_marks(p, t)
		if state.extended:
			_port_marks(p, t)
			continue
		if p.flags & MwRinkState.Player.HUMAN:
			var k := 1 if p.flags & MwRinkState.Player.SECOND_PAD else 0
			_arrow(p, t.arrows[k])
			_marker(p, t.markers[k])
		elif state.puck.carried_by() == p:
			_marker(p, t.markers[0])


## Plan 34 (section 7), into [member port_calls]: an owned player driven by
## someone else or the CPU gets the owner's hollow mark (MwPlate.RING: a ring
## on the ice round his feet in the owner's colour, under the crossbones of
## whoever drives him), and the captain's info plate a C beside their number
## (beside the plate, where the original's set-ups have no number tag) - in
## their crossbones' colour: an extended set-up's player's ([method
## player_attr]), the original's pad's otherwise.
func _control_marks(p: MwRinkState.Player, t: MwRinkState.Team) -> void:
	var control := state.control
	var ti := state.teams.find(t)
	var owner := control.owner_of(ti, p.position)
	var driver := control.driver_of(p)
	_port = true
	if owner != null and driver != owner:
		var px := p.motion.pixels()
		var g := to_sprite(project(px.x, px.y, 0))
		_mark(Vector2i(g.x, g.y) + RING_AT, MwPlate.RING_SLOT, owner.pad)
	if driver != null and control.captain_mode and control.captains[ti] == driver.player:
		var marker: MwRinkState.Marker = t.markers[t.marker_of(p)]
		var g := to_sprite(project(marker.x, marker.y, 0))
		var at := TAG_AT + (Vector2i(8 * str(driver.player).length(), 0) if state.extended else Vector2i.ZERO)
		_mark(Vector2i(g.x, g.y) + at, MwPlate.CAPTAIN_SLOT, driver.pad)
	_port = false


## One of the port's marks (variant slot [param base] + the crossbones
## variant of match pad [param pad], MwPlate) at sprite point [param at].
func _mark(at: Vector2i, base: int, pad: int) -> void:
	var slot := base + (pad if state.extended and pad < 4 else (0 if state.extended else pad & 3))
	var attr := (player_attr(pad) if state.extended else 0x60) | (slot >> 2) * PORT_BANK
	draw_frame(at.x, at.y, DEPTH_MARKER, attr, PLATES + 8 * (slot & 3))


## `$9DC`: body, airborne shadow, weapon swing, impaled overlay.
func _player(p: MwRinkState.Player, team_attr: int) -> void:
	var attr := team_attr
	var px := p.motion.pixels()
	if state.projection != 0 and absi(px.x) <= 0xB9:
		attr |= 0x80
	draw_actor(p, attr)
	if px.z != 0:
		var shadow_point := to_sprite(project(px.x, px.y, 0))
		draw_frame(shadow_point.x, shadow_point.y, DEPTH_SHADOW, 0x60, SHADOW)
	if p.state == MwRinkState.Player.STATE_WEAPON and p.weapon >= 0 \
			and not (p.weapon == 3 and p.anim.position >= 0x200):
		var hot := hotspot(p.anim, 1)
		var point_2 := to_sprite(project(px.x, px.y, px.z))
		var anim := MwGfx.u32(rom, WEAPON_ANIMS + 4 * p.weapon)
		draw_anim_frame(anim, p.anim.variant, mini(p.anim.frame, 3), point_2.x + hot.x, point_2.y + hot.y, point_2.z,
				attr)
	if p.state == MwRinkState.Player.STATE_IMPALED:
		var a := attr | 0x08 if px.x < 0 else attr
		var species := rom[p.record + 7] & 0x0F
		if species != 1:
			var imp := state.impale
			imp.address = IMPALE_ANIM_2 if species == 2 else IMPALE_ANIM
			draw_anim(imp, to_sprite(project(px.x, px.y, px.z)), a)


## `$1567C` + `$A142`: hotspot [param n] of an animation object's current
## frame, negated by the variant's flips.
func hotspot(anim: MwAnimState, n: int) -> Vector2i:
	var f := anim.frame_address(rom)
	var at := f.x + 2 + 6 * MwGfx.u16(rom, f.x) + 2 * n
	var hx := MwGfx.s8(rom, at)
	var hy := MwGfx.s8(rom, at + 1)
	return Vector2i(-hx if f.y & 1 else hx, -hy if f.y & 2 else hy)


## Plan 34, an extended set-up: what `$38E0` draws for [param p]'s pad -
## the off-screen arrow and the marker of the player driving him
## (MwRinkState.Team.marker_of: players 1-4 the original's pads' frames,
## 5-12 pad 1's in their colour, [method player_attr]), or the CPU
## carrier's grey marker on its own plate; into [member port_calls].
func _port_marks(p: MwRinkState.Player, t: MwRinkState.Team) -> void:
	var human := p.flags & MwRinkState.Player.HUMAN != 0
	if not human and state.puck.carried_by() != p:
		return
	var k := t.marker_of(p)
	_port = true
	if human:
		_arrow(p, t.arrows[k], player_attr(p.pad))
	_port_marker(p, t.markers[k], p.pad if human else -1)
	_port = false


## The attr a match pad [param pad]'s crossbones and arrow are drawn with
## (plan 34): line 3, as the original's pads' (pads 0-3); players 5-12 (pads
## 4-11) on their own line, [constant PORT_LINE] (line = pad: 4-11).
static func player_attr(pad: int) -> int:
	return 0x60 | (pad * PORT_LINE if pad >= 4 else 0)


## The palette line a sprite piece's [param attr] draws with: the port's
## ([constant PORT_LINE]) or the original's bits 5-6.
static func line_of(attr: int) -> int:
	var l := (attr >> 16) & 0xF
	return l if l != 0 else (attr >> 5) & 3


## The RAM tile [param tile] of a piece drawn with [param attr] (its bank,
## [constant PORT_BANK]: + 32 tiles each); other tiles as they are.
static func tile_of(tile: int, attr: int) -> int:
	return tile + 32 * ((attr >> 20) & 15) if tile < 0x800 else tile


## `$4B14`: the off-screen arrow of a human player (a goalie's blinks at
## the top or bottom while he is on screen). Plan 34: [param attr] (a
## player's colour, [method player_attr]).
func _arrow(p: MwRinkState.Player, arrow: MwAnimState, attr := 0x60) -> void:
	var px := p.motion.pixels()
	var m := project(px.x, px.y, px.z)
	var screen_pos := Vector2i(MwRinkSim.s16(m.x - state.camera.shown.x), MwRinkSim.s16(m.y - state.camera.shown.y))
	var code := _outcode(screen_pos.x - 8, screen_pos.y - 8, 0x130, 0xD0)
	var dir := -1
	if p.position == 5:
		if on_tick.is_valid():
			on_tick.call()
		if state.tick & 0x10 == 0:
			return
		if code == 0:
			dir = 8 if MwMotion.asr(p.motion.pos[1], 16) >= 0 else 9
	elif code == 0:
		return
	if dir < 0:
		dir = MwGfx.s8(rom, ARROW_DIRECTIONS + (code & 0xF))
	arrow.variant = dir & 0xFF
	var ax := MwGfx.s16(rom, ARROW_POINTS + 4 * dir)
	var ay := MwGfx.s16(rom, ARROW_POINTS + 4 * dir + 2)
	if ax < 0:
		ax = screen_pos.x
	if ay < 0:
		ay = screen_pos.y
	draw_anim(arrow, to_sprite(Vector3i(ax, ay, DEPTH_ARROW), false), attr)


## The sprite list entry ([x, y, size, attr, tile, depth], sprite
## coordinates) of [param piece] drawn at sprite point (x, y) with
## [param attr] (its flips mirror the piece's offset), unclipped.
static func piece_entry(rom_: PackedByteArray, x: int, y: int, depth: int, attr: int, piece: int) -> Array:
	# (plan 42: the bytes and words inline - MwGfx.s8, MwGfx.mirror_offset,
	# MwRinkSim.s16, MwGfx.u16, [method tile_of] - ~60 pieces a draw pass)
	var size := rom_[piece + 2]
	var px := ((rom_[piece] ^ 0x80) - 0x80)
	var py := ((rom_[piece + 1] ^ 0x80) - 0x80)
	if attr & 0x08:
		px = -px - 8 * (((size >> 2) & 3) + 1)
	if attr & 0x10:
		py = -py - 8 * ((size & 3) + 1)
	var sx := ((x + px + 0x8000) & 0xFFFF) - 0x8000
	var sy := ((y + py + 0x8000) & 0xFFFF) - 0x8000
	var a := ((rom_[piece + 3] ^ attr) & 0xF8) | (attr & (PORT_LINE * 0xF))
	var tile := (rom_[piece + 4] << 8) | rom_[piece + 5]
	if tile < 0x800:
		tile += 32 * ((attr >> 20) & 15)
	return [sx, sy, size, a, tile, depth & 0xFFFF]


# --- widescreen (plan 25): the off-screen arrows for a wider picture, presentation only -----

## What [method _arrow] needs of each human player of [param s], kept so a
## wider picture can draw the arrows again ([method wide_arrows]; the
## replay keeps them with its 3D frames): {at: the player's screen point
## (the original's screen, the sim camera's), goalie, south (a goalie's
## half), blink (the goalie's arrow shows this tick), anim, frame (the
## arrow's animation object)}. Reads only.
static func arrow_marks(s: MwRinkState) -> Array:
	var out := []
	if s.phase == MwRinkState.PHASE_REF:
		return out
	for t in s.teams:
		for p in t.players:
			if not p.present or not (p.flags & MwRinkState.Player.HUMAN):
				continue
			var anim: MwAnimState = t.arrows[t.control_slot(p)]
			var px := p.motion.pixels()
			var m := project_on(s, px.x, px.y, px.z)
			var mk := {"at": Vector2i(MwRinkSim.s16(m.x - s.camera.shown.x), MwRinkSim.s16(m.y - s.camera.shown.y)),
					"goalie": p.position == 5, "south": MwMotion.asr(p.motion.pos[1], 16) >= 0,
					"blink": (s.tick & 0x10) != 0, "anim": anim.address, "frame": anim.frame}
			if s.extended:
				mk["attr"] = player_attr(p.pad)          # plan 34: the player's colour
			out.append(mk)
	return out


## The arrows of [param player_marks] ([method arrow_marks]) for a picture that
## shows [param lo] more pixels than the original's screen on its left / top
## and [param hi] more on its right / bottom (in the sim camera's screen
## coordinates), the rink drawn [param shift] from where the original puts
## it (the 2D rink sliding inside its picture): `$4B14`'s test against that
## rectangle (a player inside it gets none), the ROM's direction table, the
## edge points moved out to its edges - as pieces to draw ([x, y, depth,
## attr, piece], sprite coordinates; [method list_of]). Presentation only.
static func wide_arrows(rom_: PackedByteArray, player_marks: Array, lo: Vector2i, hi: Vector2i,
		shift := Vector2i.ZERO) -> Array:
	var out := []
	var screen := Vector2i(MwRink3D.SCREEN)
	for mk: Dictionary in player_marks:
		var at: Vector2i = mk["at"]
		var code := _outcode(at.x - 8 + lo.x, at.y - 8 + lo.y, 0x130 + lo.x + hi.x, 0xD0 + lo.y + hi.y)
		var dir := -1
		if mk["goalie"]:
			if not mk["blink"]:
				continue
			if code == 0:
				dir = 8 if mk["south"] else 9
		elif code == 0:
			continue
		if dir < 0:
			dir = MwGfx.s8(rom_, ARROW_DIRECTIONS + (code & 0xF))
		var ax := MwGfx.s16(rom_, ARROW_POINTS + 4 * dir)
		var ay := MwGfx.s16(rom_, ARROW_POINTS + 4 * dir + 2)
		ax = (at.x if ax < 0 else _moved(ax, screen.x, lo.x, hi.x)) + shift.x
		ay = (at.y if ay < 0 else _moved(ay, screen.y, lo.y, hi.y)) + shift.y
		var anim := MwAnimState.new()
		anim.address = mk["anim"]
		anim.variant = dir
		anim.frame = mk["frame"]
		var f := anim.frame_address(rom_)
		var attr := int(mk.get("attr", 0x60)) ^ (f.y << 3)
		for i in MwGfx.u16(rom_, f.x):
			out.append([ax + SPRITE_ORIGIN, ay + SPRITE_ORIGIN, DEPTH_ARROW, attr, f.x + 2 + 6 * i])
	return out


## An edge point [param v] of a [param size] screen moved out with its edge
## (within 16 px of the low edge: by [param lo], of the high one: by
## [param hi]); others (a goalie's) stay.
static func _moved(v: int, size: int, lo: int, hi: int) -> int:
	if v < 16:
		return v - lo
	if v >= size - 16:
		return v + hi
	return v


## The sprite list of [param pieces] ([x, y, depth, attr, piece], sprite
## coordinates, in drawing order) built as the draw pass builds it
## ([method _insert]: by depth, a later piece of equal depth in front),
## clipped to sprite x [code]clip_x.x .. clip_x.y - 1[/code] and y
## [code]clip_y.x .. clip_y.y - 1[/code] (default: the original's), at most
## [param limit] entries; front first. The original's list for the original's
## clip and cap; bigger for a wide picture (presentation only).
static func list_of(rom_: PackedByteArray, pieces: Array, clip_x: Vector2i, limit := 0x7FFFFFFF,
		clip_y := Vector2i(CLIP_MIN, CLIP_Y)) -> Array:
	var entries: Array = [[0, 0, 0, 0, 0, 0]]
	var links := PackedInt32Array([0])
	for pc: Array in pieces:
		var entry := piece_entry(rom_, int(pc[0]), int(pc[1]), int(pc[2]), int(pc[3]), int(pc[4]))
		if int(entry[0]) < clip_x.x or int(entry[0]) >= clip_x.y or int(entry[1]) < clip_y.x \
				or int(entry[1]) >= clip_y.y:
			continue
		if entries.size() >= limit:
			continue
		var d: int = entry[5]
		var n := entries.size()
		entries.append(entry)
		links.append(0)
		var prev := 0
		var i := links[0]
		while i != 0 and d < int(entries[i][5]):
			prev = i
			i = links[i]
		links[n] = i
		links[prev] = n
	var out := []
	var j := links[0]
	while j != 0:
		out.append(entries[j])
		j = links[j]
	return out


## `$155A2`: bit 2 left of 0, 3 right of [param w], 0 above, 1 below [param h].
static func _outcode(x: int, y: int, w: int, h: int) -> int:
	var c := 0
	if x < 0:
		c |= 4
	elif x >= w:
		c |= 8
	if y < 0:
		c |= 1
	elif y >= h:
		c |= 2
	return c


## `$61CA`: possession arcs (the carrier), crossbones, info plate.
func _marker(p: MwRinkState.Player, marker: MwRinkState.Marker) -> void:
	var point := to_sprite(project(marker.x, marker.y, 0))
	if state.puck.carried_by() == p:
		draw_frame(point.x, point.y, DEPTH_MARKER, 0x60, POSSESSION)
	var k := marker.plate + 1 if p.flags & MwRinkState.Player.HUMAN else 0
	draw_frame(point.x, point.y, DEPTH_MARKER, 0x60, MwGfx.u32(rom, CROSSBONES + 4 * k))
	draw_frame(point.x, point.y, DEPTH_MARKER, 0x60, PLATES + 8 * marker.plate)


## [method _marker] for an extended set-up (plan 34): the possession arcs,
## match pad [param pad]'s crossbones (-1: the CPU carrier's grey; pads 0-3
## the original's pads' frames, 4-11 pad 1's in the player's colour,
## [method player_attr]), the info plate of the marker's slot (past the
## original's four: a bank further, [constant PORT_BANK]) and, for a
## player, their number in their colour beside it (the plates show the
## skater's number and position: MwPlate.tag_tiles; the plate's frame on
## the tag's tiles, [constant TAG_AT] along) - so colour is never the only
## cue.
func _port_marker(p: MwRinkState.Player, marker: MwRinkState.Marker, pad: int) -> void:
	var point := to_sprite(project(marker.x, marker.y, 0))
	if state.puck.carried_by() == p:
		draw_frame(point.x, point.y, DEPTH_MARKER, 0x60, POSSESSION)
	var k := 0 if pad < 0 else (pad + 1 if pad < 4 else 1)
	draw_frame(point.x, point.y, DEPTH_MARKER, player_attr(pad) if pad >= 0 else 0x60,
			MwGfx.u32(rom, CROSSBONES + 4 * k))
	draw_frame(point.x, point.y, DEPTH_MARKER, 0x60 | (marker.plate >> 2) * PORT_BANK, PLATES + 8 * (marker.plate & 3))
	if pad >= 0:
		var tag := MwPlate.TAG_SLOT + pad
		draw_frame(point.x + TAG_AT.x, point.y + TAG_AT.y, DEPTH_MARKER, player_attr(pad) | (tag >> 2) * PORT_BANK,
				PLATES + 8 * (tag & 3))


## `$605A`: the puck (the faceoff drop in front of everything above z 50)
## and its shadow.
func _puck() -> void:
	var pk := state.puck
	if state.phase == MwRinkState.PHASE_FACEOFF_BANNER or pk.flags & MwRinkState.Puck.HIDDEN:
		return
	if pk.anim.address == PUCK_ANIM:
		draw_actor(pk, 0x20)
	else:
		draw_actor(pk, 0xE0, 50)
	var px := pk.motion.pixels()
	if px.z != 0:
		var shadow_point := to_sprite(project(px.x, px.y, 0))
		draw_frame(shadow_point.x, shadow_point.y, DEPTH_SHADOW, 0x60, PUCK_SHADOW)


## `$591E`: nets, in-ice hazards, rink objects, lamp stands and lamps.
func _rink() -> void:
	for net in state.nets:
		draw_actor(net, 0 if net.style != 0 else 0x20)
	for hazard in state.hazards:
		if hazard.kind == 0:
			continue
		var e := HAZARD_FRAMES + 8 * (hazard.kind - 1)
		var hazard_point := to_sprite(project(hazard.x, hazard.y, 0))
		draw_frame(hazard_point.x, hazard_point.y, 1, 0, MwGfx.u32(rom, e))
	var setup := state.phase == MwRinkState.PHASE_FACEOFF or state.phase == MwRinkState.PHASE_START
	for rink_object in state.objects:
		if rink_object.kind == 0 or (setup and rink_object.kind != MwRinkState.KIND_CORPSE):
			continue
		var attr := MwGfx.u16(rom, OBJECT_KINDS + 6 * (rink_object.kind - 1) + 4) | rink_object.flags
		var px := rink_object.motion.pixels()
		var point := project(px.x, px.y, px.z)
		if rink_object.kind >= 8 and rink_object.kind <= 10:          # `$67A8`: under the ice
			point.z = 0
		draw_anim(rink_object.anim, to_sprite(point), attr)
	for a in STANDS:
		var stand_point := to_sprite(project(MwGfx.s16(rom, a), MwGfx.s16(rom, a + 2), MwGfx.s16(rom, a + 4)))
		draw_frame(stand_point.x, stand_point.y, stand_point.z, MwGfx.s16(rom, a + 6), STAND_FRAME)
	for i in 2:
		var actor := state.lamps[i]
		var z := actor.motion.pos[2]
		actor.motion.pos[2] = z + LAMP_RAISE[i]
		draw_actor(actor, 0x60)
		actor.motion.pos[2] = z
