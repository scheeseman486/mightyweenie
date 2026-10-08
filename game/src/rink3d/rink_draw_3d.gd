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
## stands (the wings) and on the lamps (the skulls) while they rest on them.

enum { UPRIGHT, GROUND, UNDER_ICE, MAP, SCREEN }

## Height (px) given to MAP points: the faceoff portrait is set up at the
## projection of (spot x - 28, spot y - 64, z 96) (docs/re: plan 09 notes).
const MAP_HEIGHT := 96
## The near and far boards (rink y): upright frames beyond them are moved inside.
const NEAR_BOARDS_Y := 372
const FAR_BOARDS_Y := -372
## Pin height (rink px) of the frames in front of the far glass: the middle
## post's top bulb (rink picture rows 41-48, z 48-41 on the far boards).
const FAR_PIN_Z := 45

var items: Array = []

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


func build(s: MwRinkState, phase_adds: Array = [], rules_phase := -1, phase_overlays: Array = [],
		phase_sprites: Array = []) -> Array:
	items = []
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


func project(x: int, y: int, z: int) -> Vector3i:
	var p := super.project(x, y, z)
	_proj_in = Vector3i(x, y, z)
	_proj_out = p
	return p


func to_sprite(p: Vector3i, with_camera := true) -> Vector3i:
	var s := super.to_sprite(p, with_camera)
	_sprite_in = p
	_sprite_out = s
	_sprite_cam = with_camera
	return s


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
	_in_frame = true
	super.draw_frame(x, y, depth, attr, frame)
	_in_frame = false


## Keys: an actor's animation makes it the subject.
func draw_anim(a: MwAnimState, p: Vector3i, attr: int) -> void:
	if _actors.has(a):
		_subject = _actors[a]
		_role = "body"
	elif _parts.has(a):
		_role = _parts[a]
	super.draw_anim(a, p, attr)


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
func hotspot(a: MwAnimState, n: int) -> Vector2i:
	_hot = [a.address, a.frame, n]
	return super.hotspot(a, n)


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
	if frame == STAND_FRAME:
		it["flat"] = true
	elif key.begins_with("lamp") and key.contains("/body"):
		var i := int(key.substr(4, 1))
		var rest := float(LAMP_RAISE[i] >> 8)
		if _proj_in.z <= rest:
			it["flat"] = true          # resting on its stand; flies as a billboard
	elif key == "puck/body" and state.puck.carried_by() != null:
		var c := state.puck.carried_by()
		for ti in state.teams.size():
			var pi := state.teams[ti].players.find(c)
			if pi >= 0:
				it["carrier"] = "t%d.p%d.%X/body" % [ti, pi, c.record]


func _insert(x: int, y: int, depth: int, attr: int, piece: int) -> void:
	var before := _entries.size()
	super._insert(x, y, depth, attr, piece)
	if _entries.size() > before:
		_entry_screen.append(1 if (not _in_frame or items.is_empty() or items[-1]["place"] == SCREEN) else 0)
		_entry_key.append(items[-1]["key"] if _in_frame and not items.is_empty() else "")


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
	var key := "%s/%s" % [_subject, _role if _role != "" else "f%X" % frame]
	_role = ""
	var n: int = _key_count.get(key, 0)
	_key_count[key] = n + 1
	return key if n == 0 else "%s#%d" % [key, n]


## The subjects and parts of [param s]'s animations, for the keys.
func _name_subjects(s: MwRinkState) -> void:
	_actors = {s.puck.anim: "puck", s.referee.anim: "ref"}
	_parts = {s.impale: "impale", s.faceoff.anim: "faceoff", s.penalty.anim: "penalty",
			s.stoppage.anim: "stoppage"}
	for ti in s.teams.size():
		var t := s.teams[ti]
		for pi in t.players.size():
			_actors[t.players[pi].anim] = "t%d.p%d.%X" % [ti, pi, t.players[pi].record]
		for k in t.arrows.size():
			_parts[t.arrows[k]] = "t%d.arrow%d" % [ti, k]
	for i in s.nets.size():
		_actors[s.nets[i].anim] = "net%d" % i
	for i in s.lamps.size():
		_actors[s.lamps[i].anim] = "lamp%d" % i
	_kinds = {}
	for i in s.objects.size():
		_actors[s.objects[i].anim] = "obj%d" % i
		_kinds["obj%d" % i] = s.objects[i].kind


## Number of variants of an animation record (its variant table).
func _variant_count(anim: int) -> int:
	if not _variants.has(anim):
		_variants[anim] = (MwGfx.animation(rom, anim)["variants"] as Array).size()
	return _variants[anim]
