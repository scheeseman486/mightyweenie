class_name MwRinkDraw3D
extends MwRinkDraw
## The rink's draw pass (MwRinkDraw) that also says where each drawn frame
## is in the world (plan 14). The original's sprite list ([method sprites])
## comes out exactly as before; next to it [member items] holds one entry per
## `draw_frame` call, taken before the 2D window's clipping and the 79-piece
## cap (the 3D view sees more of the rink):
##
## [codeblock]
## {frame, attr, depth, place, at: Vector3 (rink px), offset: Vector2i (px), order, key[, pin]}
## [/codeblock]
##
## [member key]: what the frame belongs to, the same from pass to pass, so
## the 3D view can interpolate between passes (MwRinkBlend3D):
## "subject/role", with "#n" for the n-th repeat in a pass. The subject is the
## last actor drawn (a player "t0.p3.<record>", "puck", "net1", "obj4",
## "lamp1", "ref"), so its shadow, weapon, markers and plate follow it; the
## role is "body" for an actor's own frame, the name of an animation that is
## no actor's ("t0.arrow1", "impale", "faceoff", ...), else the animation's or
## the frame's address.
##
## [member place]: UPRIGHT (standing at a rink point: players, puck, nets,
## objects, lamps), GROUND (flat on the ice: shadows, markers, plates, in-ice
## hazards - the original's depths 1-3), UNDER_ICE (object kinds 8-10, depth
## 0), MAP (a map point drawn with the camera but not projected from the rink:
## the faceoff portrait in phase 1, put at height [constant MAP_HEIGHT] above
## the ice under it so it stays on the same spot of the screen), SCREEN
## (screen space: ref icons, off-screen arrows, the phase handler's pieces).
## [member offset] is a frame's shift on the screen from its point (weapon
## overlays at a hotspot). [method screen_sprites] lists the SCREEN pieces in
## the original's order, for a 2D layer over the 3D view.
##
## How a call is placed: the draw routines turn rink points into map points
## with [method project] and those into sprite coordinates with
## [method to_sprite]; this class remembers both and matches them up.
##
## Presentation only, both along the original's line of sight (y - z kept,
## so they stay on their 2D spot): an upright frame beyond the near boards
## (the near lamp stand and its lamp, at y 386, which the original's near
## boards plane covers) slides in until it stands on the ice inside them; one
## behind the far boards (the far lamp stand: the wings, and its lamp: the
## skull) comes forward until it stands in front of the far glass, and is
## pinned to it: [member pin] (rink px) is the height of the point on the glass
## its billboard hangs from ([constant FAR_PIN_Z], MwSprites3D), so the skull
## covers the middle post's top bulb from any camera, as in the original.
##
## For the 3D view's own rules (plan 16, MwRinkFacing3D) some items carry
## more: [code]dir[/code] {anim, variant, aframe, attr0[, hot]} on frames
## with a direction in the world (players' bodies and weapons, the shark,
## corpses; animations with 8 variants: variant k = k x 45 deg clockwise from
## north), so the view can show the variant the camera sees, the weapon's
## [code]hot[/code] = [anim, frame, n] being the body's hotspot it is drawn
## at; [code]net[/code] {anim, aframe, attr0, mouth} on the nets (front view:
## variant 1, mouth +1 = facing south, -1 north); [code]carrier[/code] on a
## carried puck (the carrier's body key); [code]flat[/code] on the lamp
## stands (the wings) and on the lamps (the skulls) while they rest on them;
## [code]wall[/code] on the spikes (object kind 6, on a side board pointing
## into the ice: MwRinkFacing3D mirrors them for a camera looking south).

enum { UPRIGHT, GROUND, UNDER_ICE, MAP, SCREEN }

## Height (px) given to MAP points: the faceoff portrait is set up at the
## projection of (spot x - 28, spot y - 64, z 96) (docs/re: plan 09 notes).
const MAP_HEIGHT := 96
## The near and far boards (rink y): upright frames beyond them are moved inside.
const NEAR_BOARDS_Y := MwSimCollide.BOARD_Y
const FAR_BOARDS_Y := -MwSimCollide.BOARD_Y
## Pin height (rink px) of the frames in front of the far glass: the middle
## post's top bulb (rink picture rows 41-48, z 48-41 on the far boards).
const FAR_PIN_Z := 45

var items: Array = []
## Every piece the pass put to the list, in order (clipped or not, the
## recorded phase pieces too): [x, y, depth, attr, piece, kind] - kind
## [constant PIECE_WORLD], [constant PIECE_SCREEN] or [constant PIECE_ARROW]
## (an off-screen arrow's) - and, for the FACE OFF letters, a seventh:
## Vector2i(side, height) (FACE -1, OFF! +1; the drop's height, [method
## drop_shift]). The wide 2D picture's list is built from them (plan 25,
## [method wide_list]), the wide 3D's letters too ([method wide_drop]).
var pieces: Array = []
const PIECE_WORLD := 0
const PIECE_SCREEN := 1
const PIECE_ARROW := 2
## The FACE OFF letters (`$ADDC`): "FACE" at x 64 - height, "OFF!" at
## 160 + height (screen px), the drop falling from height 180.
const DROP_FACE_X := 0x40
const DROP_OFF_X := 0xA0
const DROP_FROM := 0xB4


## Plan 40 (S10): the subject of team [param ti]'s player [param pi] (his
## slot in the team's players) with record [param record] - "t0.p3.<record>",
## the keys' (saved replays keep them: never changed).
static func subject_key(ti: int, pi: int, record: int) -> String:
	return "%s.%X" % [actor_key(ti, pi), record]


## The slot part of [method subject_key] ("t0.p3"): the client's dead
## reckoning's keys (MwNetReckoning), the record left out.
static func actor_key(ti: int, pi: int) -> String:
	if ti >= 0 and ti < 2 and pi >= 0 and pi < 16:
		if _actor_keys.is_empty():
			for t in 2:
				for i in 16:
					_actor_keys.append("t%d.p%d" % [t, i])
		return _actor_keys[ti * 16 + pi]           # (plan 42: spelled once)
	return "t%d.p%d" % [ti, pi]


static var _actor_keys := PackedStringArray()

var _drop := Vector2i.ZERO        # the FACE OFF letters being drawn: (side, height)
var _proj_in := Vector3i.ZERO
var _proj_out := Vector3i(0x7FFFFFFF, 0, 0)
var _sprite_in := Vector3i.ZERO
var _sprite_out := Vector3i.ZERO
var _sprite_cam := false
var _in_frame := false
var _entry_screen := PackedByteArray([1])   # per sprite-list entry: 1 = from a SCREEN call
var _entry_key := PackedStringArray([""])    # per sprite-list entry: its frame's key ("" none)
var _variants := {}
var _actors := {}      # MwAnimState -> subject name (keys)
var _parts := {}       # MwAnimState -> role name
var _subject := ""
var _role := ""
var _key_count := {}   # key -> frames with it so far this pass
var _kinds := {}       # object subject -> kind
var _dir := {}         # the frame being drawn: its direction (see above)
var _net := {}
var _hot := []         # the last hotspot read ([anim, frame, n]): a weapon's
var _weapons := {}     # weapon animation records
var _key_names := {}       # subject -> {role or frame: "subject/role"} (plan 42: spelled once)
var _frame_key := ""       # the frame being drawn: its key, whether on the screen, its pieces' kind (plan 42)
var _frame_screen := true
var _frame_kind := 0
var _names := {}       # stem -> ["net0", "net1", ...] (plan 42: spelled once)
var _subject_names := {}   # (team, slot, record) -> subject_key (plan 42)


## The draw pass for [param s] as [method MwRinkDraw.build] (the other arguments as there),
## with [member items] and [member pieces] made afresh beside the sprite list; returns
## [method sprites].
func build(s: MwRinkState, phase_adds: Array = [], rules_phase := -1, phase_overlays: Array = [],
		phase_sprites: Array = []) -> Array:
	items = []
	pieces = []
	_entry_screen = PackedByteArray([1])
	_entry_key = PackedStringArray([""])
	_proj_out = Vector3i(0x7FFFFFFF, 0, 0)
	_name_subjects(s)
	_subject = ""
	_role = ""
	_key_count = {}
	_dir = {}
	_net = {}
	_hot = []
	if _weapons.is_empty():
		for i in 5:
			_weapons[MwGfx.u32(rom, WEAPON_ANIMS + 4 * i)] = true
	return super.build(s, phase_adds, rules_phase, phase_overlays, phase_sprites)


## `$5AC2` as [method MwRinkDraw.project], the rink point and its map point remembered for
## [method draw_frame] to place the frame.
func project(x: int, y: int, z: int) -> Vector3i:
	var point := super.project(x, y, z)
	_proj_in = Vector3i(x, y, z)
	_proj_out = point
	return point


## `$14712` as [method MwRinkDraw.to_sprite], [param point], [param with_camera] and the
## result remembered for [method draw_frame] to place the frame.
func to_sprite(point: Vector3i, with_camera := true) -> Vector3i:
	var sprite_point := super.to_sprite(point, with_camera)
	_sprite_in = point
	_sprite_out = sprite_point
	_sprite_cam = with_camera
	return sprite_point


## `draw_frame` (`$A07E`) as [method MwRinkDraw.draw_frame], [param frame] first recorded in
## [member items]: its key, place and point in the world (see the class notes).
func draw_frame(x: int, y: int, depth: int, attr: int, frame: int) -> void:
	var it := {"frame": frame, "attr": attr, "depth": depth & 0xFFFF, "order": items.size(),
			"offset": Vector2i(x - _sprite_out.x, y - _sprite_out.y), "key": _next_key(frame)}
	if not _sprite_cam:
		it["place"] = SCREEN
		it["at"] = Vector3(x, y, 0)
	elif _sprite_in.x == _proj_out.x and _sprite_in.y == _proj_out.y:
		it["at"] = Vector3(_proj_in)
		var d := depth & 0xFFFF
		it["place"] = UNDER_ICE if d == 0 else (GROUND if d <= DEPTH_MARKER else UPRIGHT)
		var at: Vector3 = it["at"]
		if it["place"] == UPRIGHT and at.y > NEAR_BOARDS_Y and at.z > 0:
			var k := minf(at.z, at.y - (NEAR_BOARDS_Y + 1))
			it["at"] = Vector3(at.x, at.y - k, at.z - k)
		elif it["place"] == UPRIGHT and at.y <= FAR_BOARDS_Y:
			var k := (FAR_BOARDS_Y + 1) - at.y
			it["at"] = Vector3(at.x, at.y + k, at.z + k)
			it["pin"] = FAR_PIN_Z
	else:
		var g := MwRink3D.ice_under_map(Vector2(_sprite_in.x, _sprite_in.y))
		it["place"] = MAP
		it["at"] = Vector3(g.x, g.y + MAP_HEIGHT, MAP_HEIGHT)
	if it["place"] == UPRIGHT:
		_extras(it, frame)
	_dir = {}
	_net = {}
	items.append(it)
	# (plan 42: what each of the frame's pieces needs of it, worked out once)
	_frame_key = it["key"]
	_frame_screen = it["place"] == SCREEN
	_frame_kind = (PIECE_ARROW if _frame_key.contains(".arrow") else PIECE_SCREEN) if _frame_screen else PIECE_WORLD
	_in_frame = true
	super.draw_frame(x, y, depth, attr, frame)
	_in_frame = false


## Keys: an actor's animation makes it the subject.
func draw_anim(anim: MwAnimState, point: Vector3i, attr: int) -> void:
	if _actors.has(anim):
		_subject = _actors[anim]
		_role = "body"
	elif _parts.has(anim):
		_role = _parts[anim]
	super.draw_anim(anim, point, attr)


## Animation frames: what the 3D view needs to turn them (see above).
func draw_anim_frame(anim: int, variant: int, frame: int, x: int, y: int, depth: int, attr: int) -> void:
	var body := _role == "body"
	if _role == "":
		_role = "a%X" % anim
	if _sprite_cam:
		var weapon := _weapons.has(anim) and not _hot.is_empty()
		if (weapon or (body and _turns(_subject))) and _variant_count(anim) >= 8 and variant < 8:
			_dir = {"anim": anim, "variant": variant, "aframe": frame, "attr0": attr}
			if weapon:
				_dir["hot"] = _hot
		elif body and _subject.begins_with("net"):
			_net = {"anim": anim, "aframe": frame, "attr0": attr, "mouth": 1 if variant == 1 else -1}
	_hot = []
	super.draw_anim_frame(anim, variant, frame, x, y, depth, attr)


## The body's hotspot a weapon is drawn at: remembered for its frame.
func hotspot(anim: MwAnimState, n: int) -> Vector2i:
	_hot = [anim.address, anim.frame, n]
	return super.hotspot(anim, n)


## Whether an actor's own frames face a direction in the world: players,
## the referee, the shark (its variant is its heading) and corpses (a
## player's animation, kept).
func _turns(subject: String) -> bool:
	if subject.begins_with("t") or subject == "ref":
		return true
	var k: int = _kinds.get(subject, 0)
	return k == MwRinkState.KIND_SHARK or k == MwRinkState.KIND_CORPSE


## The 3D view's extras on an upright item (see the class notes).
func _extras(it: Dictionary, frame: int) -> void:
	if not _dir.is_empty():
		it["dir"] = _dir
	if not _net.is_empty():
		it["net"] = _net
	var key: String = it["key"]
	if _kinds.get(_subject, 0) == MwRinkState.KIND_SPIKES and key.begins_with(_subject + "/body"):
		it["wall"] = true                  # on a side board, pointing into the ice (MwRinkFacing3D)
	if frame == STAND_FRAME:
		it["flat"] = true
	elif key.begins_with("lamp") and key.contains("/body"):
		var i := int(key.substr(4, 1))
		var rest := float(LAMP_RAISE[i] >> 8)
		if _proj_in.z <= rest:
			it["flat"] = true          # resting on its stand; flies as a billboard
	elif key == "puck/body" and state.puck.carried_by() != null:
		var player := state.puck.carried_by()
		for ti in state.teams.size():
			var pi := state.teams[ti].players.find(player)
			if pi >= 0:
				it["carrier"] = subject_key(ti, pi, player.record) + "/body"


func _insert(x: int, y: int, depth: int, attr: int, piece: int) -> void:
	var before := _entries.size()
	# (a frame's pieces: its own key and place, draw_frame's; others: none, the screen's)
	var screen := _frame_screen if _in_frame else true
	var key := _frame_key if _in_frame else ""
	pieces.append([x, y, depth & 0xFFFF, attr, piece, _frame_kind if _in_frame else PIECE_SCREEN])
	if _drop != Vector2i.ZERO:
		pieces[-1].append(_drop)
	super._insert(x, y, depth, attr, piece)
	if _entries.size() > before:
		_entry_screen.append(1 if screen else 0)
		_entry_key.append(key)


## The sprite list for a 2D picture of [param size] pixels whose original
## 320 x 224 starts at [param off] in it, the rink drawn [param slide]
## pixels from where the original puts it (inside its picture; plan 25):
## the pass's [member pieces] - the rink's moved by the slide, the
## screen-space ones (the phase's, the ref icons) where and as far as the
## original shows them, but the FACE OFF letters, which fly in from beyond
## the bigger picture's edges ([method drop_shift]), the off-screen arrows
## drawn again for the bigger picture from [param arrow_list] ([method
## MwRinkDraw.wide_arrows]) - clipped to the bigger picture, no cap.
## Presentation only.
func wide_list(size: Vector2i, off: Vector2i, slide: Vector2i, arrow_list: Array) -> Array:
	var ps := []
	for piece: Array in pieces:
		match int(piece[5]):
			PIECE_WORLD:
				ps.append([int(piece[0]) + slide.x, int(piece[1]) + slide.y, piece[2], piece[3], piece[4]])
			PIECE_SCREEN:
				if piece.size() > 6:
					ps.append(_drop_moved(piece, size, off))
					continue
				var entry := piece_entry(rom, int(piece[0]), int(piece[1]), int(piece[2]), int(piece[3]), int(piece[4]))
				if int(entry[0]) >= CLIP_MIN and int(entry[0]) < CLIP_X and int(entry[1]) >= CLIP_MIN \
						and int(entry[1]) < CLIP_Y:
					ps.append(piece.slice(0, 5))
	var lo := off + slide
	var hi := size - MwRink3D.SCREEN - off - slide
	ps.append_array(wide_arrows(rom, arrow_list, lo, hi, slide))
	var o := Vector2i(SPRITE_ORIGIN, SPRITE_ORIGIN)
	return list_of(rom, ps, Vector2i(CLIP_MIN - off.x, o.x + size.x - off.x), 0x7FFFFFFF,
			Vector2i(CLIP_MIN - off.y, o.y + size.y - off.y))


## How much further out a FACE OFF letter is drawn in a picture
## [param margin] px wider on its side than the original's (owner,
## 2026-10-09: aware of ultrawide pictures, the faster the further the text
## has to move, the sequence taking as long as before): at the drop's height
## [param height] the original puts it [param height] px out from where it
## lands; here margin x (height / 180)^2 more, so it starts as far beyond
## the bigger picture's edge as the original's beyond its own, lands at the
## same tick, and bounces as the original's (the extra fades with the
## height squared: the extra distance is made while the letters are high).
static func drop_shift(height: int, margin: int) -> int:
	if height <= 0 or margin <= 0:
		return 0
	var h := float(height) / DROP_FROM
	return roundi(margin * h * h)


## FACE OFF piece [param piece] (with its seventh element) moved for a picture
## [param size] whose original 320 x 224 starts at [param off].
static func _drop_moved(piece: Array, size: Vector2i, off: Vector2i) -> Array:
	var d: Vector2i = piece[6]
	var margin := off.x if d.x < 0 else size.x - MwRink3D.SCREEN.x - off.x
	return [int(piece[0]) + d.x * drop_shift(d.y, margin), piece[1], piece[2], piece[3], piece[4]]


## The FACE OFF letters among [param pieces] (MwRinkDraw3D.pieces, live or
## a replay's) as a wide picture [param size] (its original's 320 x 224 at
## [param off]) shows them: moved out ([method drop_shift]), clipped to the
## bigger picture. Sprite list entries, front first.
static func wide_drop(rom_: PackedByteArray, pieces_: Array, size: Vector2i, off: Vector2i) -> Array:
	var ps := []
	for piece: Array in pieces_:
		if piece.size() > 6:
			ps.append(_drop_moved(piece, size, off))
	if ps.is_empty():
		return []
	var o := SPRITE_ORIGIN
	return list_of(rom_, ps, Vector2i(CLIP_MIN - off.x, o + size.x - off.x), 0x7FFFFFFF,
			Vector2i(CLIP_MIN - off.y, o + size.y - off.y))


## [param entries] (a sprite list) without the FACE OFF letters of
## [param pieces_] as the original placed them.
static func without_drop(rom_: PackedByteArray, entries: Array, pieces_: Array) -> Array:
	var drop := []
	for piece: Array in pieces_:
		if piece.size() > 6:
			drop.append(piece_entry(rom_, int(piece[0]), int(piece[1]), int(piece[2]), int(piece[3]), int(piece[4])))
	if drop.is_empty():
		return entries
	return entries.filter(func(e: Array) -> bool: return not e in drop)


## The phase handler's sprite [param op]; the FACE OFF letters' pieces
## marked with their side and the drop's height ([member pieces]).
func phase_sprite(op: Array) -> void:
	_drop = Vector2i.ZERO
	if str(op[0]) == "sprite_text" and op[6] is int:
		if int(op[6]) == MwRinkPhases.T_FACE:
			_drop = Vector2i(-1, DROP_FACE_X - int(op[2]))
		elif int(op[6]) == MwRinkPhases.T_OFF:
			_drop = Vector2i(1, int(op[2]) - DROP_OFF_X)
		if _drop.y <= 0:
			_drop = Vector2i.ZERO
	super.phase_sprite(op)
	_drop = Vector2i.ZERO


## The sprite list's SCREEN pieces in link order (front first), as
## [method sprites] gives them; [param no_arrows]: without the arrows that
## point at players off the 2D screen (plan 20: the views that frame
## otherwise, MwRinkViews.shows_arrows).
func screen_sprites(no_arrows := false) -> Array:
	var out := []
	var i := _links[0]
	while i != 0:
		if _entry_screen[i] == 1 and not (no_arrows and _entry_key[i].contains(".arrow")):
			out.append(_entries[i])
		i = _links[i]
	return out


## The key of the frame being drawn ([member items]).
func _next_key(frame: int) -> String:
	# (plan 42: "subject/role" spelled once per pair; a frame drawn without a
	# role is its frame's "f<hex>")
	var by_role: Dictionary = _key_names.get(_subject, {})
	if by_role.is_empty():
		_key_names[_subject] = by_role
	var role: Variant = _role if _role != "" else frame
	var key: String = by_role.get(role, "")
	if key == "":
		key = "%s/%s" % [_subject, _role if _role != "" else "f%X" % frame]
		by_role[role] = key
	_role = ""
	var n: int = _key_count.get(key, 0)
	_key_count[key] = n + 1
	return key if n == 0 else "%s#%d" % [key, n]


## The subjects and parts of [param s]'s animations, for the keys.
## Plan 42 (speed): the names spelled once ([method _name]).
func _name_subjects(s: MwRinkState) -> void:
	_actors = {s.puck.anim: "puck", s.referee.anim: "ref"}
	_parts = {s.impale: "impale", s.faceoff.anim: "faceoff", s.penalty.anim: "penalty",
			s.stoppage.anim: "stoppage"}
	for ti in s.teams.size():
		var team := s.teams[ti]
		for pi in team.players.size():
			var rec := team.players[pi].record
			var key: Variant = _subject_names.get(((ti * 64 + pi) << 32) | (rec & 0xFFFFFFFF))
			if key == null:
				key = subject_key(ti, pi, rec)
				_subject_names[((ti * 64 + pi) << 32) | (rec & 0xFFFFFFFF)] = key
			_actors[team.players[pi].anim] = key
		for k in team.arrows.size():
			_parts[team.arrows[k]] = _name("t%d.arrow" % ti, k)
	for i in s.nets.size():
		_actors[s.nets[i].anim] = _name("net", i)
	for i in s.lamps.size():
		_actors[s.lamps[i].anim] = _name("lamp", i)
	_kinds = {}
	for i in s.objects.size():
		var name := _name("obj", i)
		_actors[s.objects[i].anim] = name
		_kinds[name] = s.objects[i].kind


## [param stem] and [param i] as one name ("net1"), spelled once.
func _name(stem: String, i: int) -> String:
	var names: Array = _names.get(stem, [])
	while names.size() <= i:
		names.append("%s%d" % [stem, names.size()])
	_names[stem] = names
	return names[i]


## Number of variants of an animation record (its variant table).
func _variant_count(anim: int) -> int:
	if not _variants.has(anim):
		_variants[anim] = (MwGfx.animation(rom, anim)["variants"] as Array).size()
	return _variants[anim]
