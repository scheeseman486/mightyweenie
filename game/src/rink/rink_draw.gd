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

const MAX_COUNT := 0x50              ## the list's count stops here (entry 0 is the head)
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

## The penalty icon at `$A5EC`'s draw (`$AFBC`): 1 shown, 0 hidden, -1 as the
## state has it at the draw pass ([method MwRinkUpdate.penalties] sets it).
var penalty_shown := -1
var rom: PackedByteArray
var state: MwRinkState
## `draw_frame` calls in order: [x, y, depth, attr, frame] (sprite coordinates).
var calls: Array = []
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


func _init(rom_: PackedByteArray) -> void:
	rom = rom_


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
	for t in s.teams:
		_team(t)
	_puck()
	_rink()
	_overlay(s.faceoff, s.phase == MwRinkState.PHASE_FACEOFF)
	return sprites()


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
	calls = []
	adds = []
	_entries = [[0, 0, 0, 0, 0, 0]]
	_links = PackedInt32Array([0])
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
	if state.projection != 0:
		var ax := -absi(x)
		var my := MwMotion.s16(ax + 0x179 - z)
		return Vector3i(MwMotion.s16(y + 0xA0), my, MwMotion.s16(my + z))
	var my2 := MwMotion.s16(y + 0x1CD - z)
	return Vector3i(MwMotion.s16(x + 0x100), my2, MwMotion.s16(my2 + z))


## `$14712`: map point -> sprite coordinates (camera = plane B's, or none).
func to_sprite(p: Vector3i, with_camera := true) -> Vector3i:
	var c := state.camera.shown if with_camera else Vector2i.ZERO
	return Vector3i(MwMotion.s16(p.x - c.x + SPRITE_ORIGIN), MwMotion.s16(p.y - c.y + SPRITE_ORIGIN), p.z)


## `draw_frame` ($A07E).
func draw_frame(x: int, y: int, depth: int, attr: int, frame: int) -> void:
	calls.append([x, y, depth & 0xFFFF, attr, frame])
	for i in MwGfx.u16(rom, frame):
		add_piece(x, y, depth, attr, frame + 2 + 6 * i)


## `$15666`: frame [param frame] of [param variant] of animation [param anim]
## (the variant's flips XORed into the attr).
func draw_anim_frame(anim: int, variant: int, frame: int, x: int, y: int, depth: int, attr: int) -> void:
	var a := MwAnimState.new()
	a.address = anim
	a.variant = variant
	a.frame = frame
	var f := a.frame_address(rom)
	draw_frame(x, y, depth, attr ^ (f.y << 3), f.x)


## `$14444`: an animation object at a sprite point.
func draw_anim(a: MwAnimState, p: Vector3i, attr: int) -> void:
	draw_anim_frame(a.address, a.variant, a.frame, p.x, p.y, p.z, attr)


## `$141C8`: an actor at its position through a projection, with the camera.
func draw_actor(o: MwRinkState.Actor, attr: int, top_above := -1) -> void:
	var px := o.motion.pixels()
	var p := project(px.x, px.y, px.z)
	if top_above >= 0 and px.z > top_above:      # `$60C4`
		p.z = DEPTH_TOP
	draw_anim(o.anim, to_sprite(p), attr)


## `add_sprite_piece` ($156C6).
func add_piece(x: int, y: int, depth: int, attr: int, piece: int) -> void:
	adds.append([x, y, depth & 0xFFFF, attr, piece])
	_insert(x, y, depth, attr, piece)


func _insert(x: int, y: int, depth: int, attr: int, piece: int) -> void:
	var size := rom[piece + 2]
	var w := 8 * (((size >> 2) & 3) + 1)
	var h := 8 * ((size & 3) + 1)
	var px := MwGfx.s8(rom, piece)
	var py := MwGfx.s8(rom, piece + 1)
	var sx := MwMotion.s16(x - px - w) if attr & 0x08 else MwMotion.s16(x + px)
	if sx < CLIP_MIN or sx >= CLIP_X:
		return
	var sy := MwMotion.s16(y - py - h) if attr & 0x10 else MwMotion.s16(y + py)
	if sy < CLIP_MIN or sy >= CLIP_Y:
		return
	if _entries.size() >= MAX_COUNT:
		return
	var d := depth & 0xFFFF
	var n := _entries.size()
	_entries.append([sx, sy, size, (rom[piece + 3] ^ attr) & 0xF8, MwGfx.u16(rom, piece + 4), d])
	_links.append(0)
	# insert before the first entry whose depth <= ours
	var prev := 0
	var i := _links[0]
	while i != 0 and d < int(_entries[i][5]):
		prev = i
		i = _links[i]
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
			var p := to_sprite(Vector3i(int(op[2]), int(op[3]), 0), false)
			add_piece(p.x, p.y, int(op[5]), int(op[4]), int(op[1]))
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
	var p := to_sprite(Vector3i(x, y, depth), false)
	var px := p.x
	for c in b:
		var advance := 8 * MwGfx.char_width(rom, font, c)
		if c != 0x20:
			var g := MwGfx.font_glyph(rom, font, c)
			if g <= 0:
				continue                         # glyph 0 (or none: never in the ROM's strings)
			add_piece(px, p.y, depth, attr, font + 8 + 6 * g)
		px = MwMotion.s16(px + advance)


## `$B70C` on the window plane: the coach portrait object (as drawn:
## [param anim], [param variant], [param frame], [param size]) at screen
## ([param x], [param y]) - its border (`$1CDF6` by size, none for size 0)
## one pixel right with the attr's line 3, then the animation's frame.
func portrait(x: int, y: int, depth: int, attr: int, anim: int, variant: int, frame: int, size: int) -> void:
	var p := to_sprite(Vector3i(x, y, depth), false)
	if size != 0:
		draw_frame(MwMotion.s16(p.x + 1), p.y, depth, attr | 0x60, MwGfx.u32(rom, PORTRAIT_BORDERS + 4 * (size - 1)))
	draw_anim_frame(anim, variant, frame, p.x, p.y, depth, attr)


# --- what the rink draws -----------------------------------------------------------------

## `$AFBC`: an overlay's border, then its animation.
func _overlay(o: MwRinkState.Overlay, with_camera: bool) -> void:
	if not o.shown():
		return
	var bx := o.x
	var by := o.y - 2
	var border := BORDER
	if o.flags & 1:
		border = SMALL_BORDER
		by += 3
		bx += 1
	var b := to_sprite(Vector3i(bx, by, o.depth), with_camera)
	draw_frame(b.x, b.y, o.depth, o.attr | 0x60, border)
	draw_anim(o.anim, to_sprite(Vector3i(o.x, o.y, o.depth), with_camera), o.attr)


## `$38E0`: a team's players with their arrows and markers.
func _team(t: MwRinkState.Team) -> void:
	for p in t.players:
		if not p.present:
			continue
		_player(p, t.attr)
		if state.phase == MwRinkState.PHASE_REF:
			continue
		if p.flags & MwRinkState.Player.HUMAN:
			var k := 1 if p.flags & MwRinkState.Player.SECOND_PAD else 0
			_arrow(p, t.arrows[k])
			_marker(p, t.markers[k])
		elif state.puck.carried_by() == p:
			_marker(p, t.markers[0])


## `$9DC`: body, airborne shadow, weapon swing, impaled overlay.
func _player(p: MwRinkState.Player, team_attr: int) -> void:
	var attr := team_attr
	var px := p.motion.pixels()
	if state.projection != 0 and absi(px.x) <= 0xB9:
		attr |= 0x80
	draw_actor(p, attr)
	if px.z != 0:
		var s := to_sprite(project(px.x, px.y, 0))
		draw_frame(s.x, s.y, DEPTH_SHADOW, 0x60, SHADOW)
	if p.state == MwRinkState.Player.STATE_WEAPON and p.weapon >= 0 \
			and not (p.weapon == 3 and p.anim.position >= 0x200):
		var hot := hotspot(p.anim, 1)
		var q := to_sprite(project(px.x, px.y, px.z))
		var anim := MwGfx.u32(rom, WEAPON_ANIMS + 4 * p.weapon)
		draw_anim_frame(anim, p.anim.variant, mini(p.anim.frame, 3), q.x + hot.x, q.y + hot.y, q.z, attr)
	if p.state == MwRinkState.Player.STATE_IMPALED:
		var a := attr | 0x08 if px.x < 0 else attr
		var species := rom[p.record + 7] & 0x0F
		if species != 1:
			var imp := state.impale
			imp.address = IMPALE_ANIM_2 if species == 2 else IMPALE_ANIM
			draw_anim(imp, to_sprite(project(px.x, px.y, px.z)), a)


## `$1567C` + `$A142`: hotspot [param n] of an animation object's current
## frame, negated by the variant's flips.
func hotspot(a: MwAnimState, n: int) -> Vector2i:
	var f := a.frame_address(rom)
	var at := f.x + 2 + 6 * MwGfx.u16(rom, f.x) + 2 * n
	var hx := MwGfx.s8(rom, at)
	var hy := MwGfx.s8(rom, at + 1)
	return Vector2i(-hx if f.y & 1 else hx, -hy if f.y & 2 else hy)


## `$4B14`: the off-screen arrow of a human player (a goalie's blinks at
## the top or bottom while he is on screen).
func _arrow(p: MwRinkState.Player, arrow: MwAnimState) -> void:
	var px := p.motion.pixels()
	var m := project(px.x, px.y, px.z)
	var s := Vector2i(MwMotion.s16(m.x - state.camera.shown.x), MwMotion.s16(m.y - state.camera.shown.y))
	var code := _outcode(s.x - 8, s.y - 8, 0x130, 0xD0)
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
		ax = s.x
	if ay < 0:
		ay = s.y
	draw_anim(arrow, to_sprite(Vector3i(ax, ay, DEPTH_ARROW), false), 0x60)


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
func _marker(p: MwRinkState.Player, m: MwRinkState.Marker) -> void:
	var s := to_sprite(project(m.x, m.y, 0))
	if state.puck.carried_by() == p:
		draw_frame(s.x, s.y, DEPTH_MARKER, 0x60, POSSESSION)
	var k := m.plate + 1 if p.flags & MwRinkState.Player.HUMAN else 0
	draw_frame(s.x, s.y, DEPTH_MARKER, 0x60, MwGfx.u32(rom, CROSSBONES + 4 * k))
	draw_frame(s.x, s.y, DEPTH_MARKER, 0x60, PLATES + 8 * m.plate)


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
		var s := to_sprite(project(px.x, px.y, 0))
		draw_frame(s.x, s.y, DEPTH_SHADOW, 0x60, PUCK_SHADOW)


## `$591E`: nets, in-ice hazards, rink objects, lamp stands and lamps.
func _rink() -> void:
	for n in state.nets:
		draw_actor(n, 0 if n.style != 0 else 0x20)
	for h in state.hazards:
		if h.kind == 0:
			continue
		var e := HAZARD_FRAMES + 8 * (h.kind - 1)
		var s := to_sprite(project(h.x, h.y, 0))
		draw_frame(s.x, s.y, 1, 0, MwGfx.u32(rom, e))
	var setup := state.phase == MwRinkState.PHASE_FACEOFF or state.phase == MwRinkState.PHASE_START
	for o in state.objects:
		if o.kind == 0 or (setup and o.kind != MwRinkState.KIND_CORPSE):
			continue
		var attr := MwGfx.u16(rom, OBJECT_KINDS + 6 * (o.kind - 1) + 4) | o.flags
		var px := o.motion.pixels()
		var p := project(px.x, px.y, px.z)
		if o.kind >= 8 and o.kind <= 10:          # `$67A8`: under the ice
			p.z = 0
		draw_anim(o.anim, to_sprite(p), attr)
	for a in STANDS:
		var s := to_sprite(project(MwGfx.s16(rom, a), MwGfx.s16(rom, a + 2), MwGfx.s16(rom, a + 4)))
		draw_frame(s.x, s.y, s.z, MwGfx.s16(rom, a + 6), STAND_FRAME)
	for i in 2:
		var l := state.lamps[i]
		var z := l.motion.pos[2]
		l.motion.pos[2] = z + LAMP_RAISE[i]
		draw_actor(l, 0x60)
		l.motion.pos[2] = z
