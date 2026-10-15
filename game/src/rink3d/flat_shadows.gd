class_name MwFlatShadows
extends RefCounted
## Port only, 3D only ([member MwSettings.flat_shadows], owner, 2026-10-09):
## the shadows drawn into the rink's sprites, taken out of the standing
## frames and laid flat on the ice beneath them - the original's dither kept
## (owner: the dither stays). The 2D view is the original's (owner: no change
## to 2D at all).
##
## The original draws a figure's shadow on the ice as part of its frame: a
## dither of colour 11 of the team lines (1 and 2), which `screen_palette`
## sets to the stadium's ice colour 5 (docs/re/graphics.md, Palettes) - the
## shade of the ice. So every colour-11 pixel of a team-line frame is ice in
## shadow: under the skates and the body, along a stick, at the puck's edge.
## Here those pixels are:
##
## * left out of the standing billboard (rink3d_sprite_body's strip_shadow);
## * laid on the ice under the figure ([method mask]: pixel for pixel as the
##   frame has them, its dither too, and the holes its feet leave in it
##   dithered over), turned to face the camera as the billboard above it does
##   (MwSprites3D, rink3d_sprite_shadow);
## * but for the stick's shadow (the pixels beside its colour 4, owner):
##   those stay on the billboard, drawn in a pass of their own
##   (rink3d_sprite_stick) so they follow the same colour rule.
##
## The colour rule: the shade colour but never lighter than what the opaque
## pass drew below: min(below, colour 11) per channel. On the ice that is
## colour 11 itself, as in the original; over black (the floor beyond the
## ice, the dark behind the boards) it is black (owner: not seen on black);
## over the rink's markings, the darker of the two. Overlapping
## shadows give the same, so they do not stack.
##
## A figure outside the side boards ([method in_bench_area]: the benches, the
## penalty boxes, the ways to the arches, plan 32) has no shadow at all.
## Off: the original's dithered shadows inside the frames.
##
## **The fires' scorch marks** (plan 37, owner: the players' shadow code
## extended to them): a fire (rink object kind 4, drawn with attr `$60`:
## line 3) has round its base, in its loop frames
## (`$22B2A`, MwRinkUpdate.FIRE_LOOP), a dithered ring of line 3's colour 11
## - the ice scorched under it ([method scorch_index]). Those pixels go the
## shadows' way (the same [method mask], dither and gaps under the flame
## included), the flat drawn in their own colour with the same rule
## (rink3d_sprite_shadow's shade_index). Line 3's colour 11 elsewhere (the
## lamps) is left alone.

## Colour 11 of palette lines 1 and 2 (the team lines): the ice's colour 5.
const SHADOW_INDICES := [27, 43]
## The colour the flat is drawn in (palette index; line 2's is the same).
const SHADE_INDEX := 27
## Colour 4 of lines 1 and 2: the sticks (the default palette's brown).
const STICK_INDICES := [20, 36]
## The fires' scorch: line 3's colour 11 in the fire's loop frames.
const SCORCH_INDEX := 59
static var _scorch_frames := {}

## [method mask]'s values: a pixel of the flat on the ice, a shadow pixel
## that stays on the billboard beside the stick.
const FLAT := 255
const ON_STICK := 128
## A frame's rows from this one down (from its point: 0 = the ice under it)
## are its feet's: a patch of shadow reaching them lies on the ice.
const GROUND_ROW := -3
## Gaps the figure's own pixels leave in a row of its shadow, filled up to
## this many pixels (its legs and skates standing on it).
const BODY_GAP := 12
## The side boards (rink |x|: the physics boundary, MwRinkShape.BOARD):
## beyond them are the benches and the boxes.
const BOARD_X := MwRinkShape.BOARD.x


## Whether indexed pixel [param v] (line * 16 + colour) is a shadow pixel.
static func is_shadow(v: int) -> bool:
	return v == 27 or v == 43


## Whether [param px] has any shadow pixel ([param extra]: one more index
## that counts, the scorch's; -1 none).
static func has_shadow(px: PackedByteArray, extra := -1) -> bool:
	for v in px:
		if v == 27 or v == 43 or v == extra:
			return true
	return false


## The palette index of ROM frame [param frame]'s scorch mark drawn with
## [param attr] ([constant SCORCH_INDEX] for a fire's loop frame on line 3),
## or -1.
static func scorch_index(frame: int, attr: int) -> int:
	if (attr >> 5) & 3 != 3:
		return -1
	if _scorch_frames.is_empty() and MwRom.available():
		var rom := MwRom.data()
		var a := MwGfx.animation(rom, MwRinkUpdate.FIRE_LOOP)
		for o in MwGfx.anim_offsets(rom, a, 0):
			_scorch_frames[int(a["frames"]) + o] = true
	return SCORCH_INDEX if _scorch_frames.has(frame) else -1


## [param px] without its shadow pixels (a copy; they become 0, transparent).
static func strip(px: PackedByteArray) -> PackedByteArray:
	var out := px.duplicate()
	for i in out.size():
		var v := out[i]
		if v == 27 or v == 43:
			out[i] = 0
	return out


## Whether indexed pixel [param v] is a stick's (colour 4 of a team line).
static func is_stick(v: int) -> bool:
	return v == 20 or v == 36


## A whole frame's shadow ([param px], [param w] wide, its top row
## [param top] rows from the frame's point) sorted for 3D, one value a pixel
## (empty when the frame has no shadow pixel):
## * [constant ON_STICK]: the stick's shadow, which stays on the billboard -
##   a shadow pixel beside a stick pixel (its 8 neighbours); one two pixels
##   from the stick touching such a pixel (lines two pixels thick); and every
##   pixel of a patch of shadow (8-connected) that touches the stick but not
##   the ground (no pixel from [constant GROUND_ROW] down: the lines along a
##   raised stick, to their ends);
## * [constant FLAT]: the rest of the shadow pixels as they are (the dither
##   too), and in each row the gaps between two of them that the frame's own
##   pixels fill (at most [constant BODY_GAP] long, no two transparent pixels
##   in a row in them: where the figure stands on its shadow) dithered over -
##   every other pixel from the one before the gap: the flat on the ice;
## * 0 elsewhere.
## [param extra]: one more index sorted as a shadow (a fire's scorch,
## [method scorch_index]; -1 none).
static func mask(px: PackedByteArray, w: int, top := 0, extra := -1) -> PackedByteArray:
	var m := PackedByteArray()
	if w <= 0 or not has_shadow(px, extra):
		return m
	m.resize(px.size())
	var h := px.size() / w
	for i in px.size():
		if px[i] == 27 or px[i] == 43 or px[i] == extra:
			m[i] = ON_STICK if _stick_within(px, w, h, i, 1) else FLAT
	# patches of shadow up in the air that touch the stick: all of them on it
	var patch := PackedInt32Array()
	patch.resize(px.size())
	patch.fill(-1)
	for i in px.size():
		if m[i] == 0 or patch[i] >= 0:
			continue
		var members := PackedInt32Array([i])
		patch[i] = i
		var grounded := false
		var touches := false
		var k := 0
		while k < members.size():
			var j := members[k]
			k += 1
			grounded = grounded or j / w + top >= GROUND_ROW
			touches = touches or m[j] == ON_STICK
			for yy in range(maxi(j / w - 1, 0), mini(j / w + 1, h - 1) + 1):
				for xx in range(maxi(j % w - 1, 0), mini(j % w + 1, w - 1) + 1):
					var n := yy * w + xx
					if m[n] != 0 and patch[n] < 0:
						patch[n] = i
						members.append(n)
		if touches and not grounded:
			for j in members:
				m[j] = ON_STICK
	var thick := PackedInt32Array()
	for i in px.size():
		if m[i] == FLAT and _stick_within(px, w, h, i, 2) and _next_to(m, w, h, i, ON_STICK):
			thick.append(i)
	for i in thick:
		m[i] = ON_STICK
	var shadow := PackedByteArray()
	shadow.resize(px.size())
	for i in px.size():
		if m[i] == FLAT:
			shadow[i] = 1
	for y in h:
		var row := y * w
		var last := -1
		var zrun := 0
		var zmax := 0
		for x in w:
			var i := row + x
			if shadow[i] != 0:
				if last >= 0 and x - last > 1 and x - last - 1 <= BODY_GAP and zmax <= 1:
					for k in range(last + 2, x, 2):
						if m[row + k] == 0 and px[row + k] != 0:     # the figure's pixels only
							m[row + k] = FLAT
				last = x
				zrun = 0
				zmax = 0
			elif px[i] == 0:
				zrun += 1
				zmax = maxi(zmax, zrun)
			else:
				zrun = 0
	return m


## Whether a stick pixel lies within [param d] pixels (rows and columns) of
## pixel [param i].
static func _stick_within(px: PackedByteArray, w: int, h: int, i: int, d: int) -> bool:
	var x := i % w
	var y := i / w
	for yy in range(maxi(y - d, 0), mini(y + d, h - 1) + 1):
		for xx in range(maxi(x - d, 0), mini(x + d, w - 1) + 1):
			var v := px[yy * w + xx]
			if v == 20 or v == 36:
				return true
	return false


## Whether one of pixel [param i]'s 8 neighbours in [param m] is [param v].
static func _next_to(m: PackedByteArray, w: int, h: int, i: int, v: int) -> bool:
	var x := i % w
	var y := i / w
	for yy in range(maxi(y - 1, 0), mini(y + 1, h - 1) + 1):
		for xx in range(maxi(x - 1, 0), mini(x + 1, w - 1) + 1):
			if m[yy * w + xx] == v:
				return true
	return false


## Whether a figure standing at [param at] (rink px) is in the bench area:
## outside the side boards - the benches, the penalty boxes and the ways
## between them and the arches (plan 32, MwBench3D), where the floor is not
## ice. No shadow there.
static func in_bench_area(at: Vector3) -> bool:
	return absf(at.x) > BOARD_X
