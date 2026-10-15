class_name MwCustomRink
extends RefCounted
## A custom team's home rink (plan 38): the stadium record's fields
## (docs/re/rinks.md; `$1B6B8`..) as plain values, with the port's own
## colours, gravity and any number of hazards. [MwCustomOverlay] writes it
## as a stadium record in the original's layout:
##
## [codeblock]
## +0 name  +4 ice palette (0: custom rinks use their own colours)  +5 net
## +6 0  +7 1  +8 gravity (signed)  +9 in-ice hazards  +A rink objects
## +B hazard mask (matchup text)  +C entries: x.w, y.w, kind, flags
## [/codeblock]

## Hazard kinds by name: [rink object?, kind number, half-size x, y].
## In-ice hazards (the stadium's first list) and rink objects (its second).
const KINDS := {
	"thin_ice": [false, 1, 24, 8], "pit": [false, 2, 24, 12], "hole": [false, 3, 24, 12],
	"mine": [false, 4, 16, 12], "shark": [true, 1, 16, 12], "fire": [true, 4, 12, 8],
	"spikes": [true, 6, 8, 16],
}
## The editor's order.
const KIND_ORDER := ["thin_ice", "pit", "hole", "mine", "shark", "fire", "spikes"]
## The matchup's hazard words by kind: their bits in the stadium's mask
## (`$1CB20`'s list, bit 0 thin ice .. 7 spikes; 6 has no kind).
const MASK_BITS := {"thin_ice": 0, "pit": 1, "hole": 2, "mine": 3, "fire": 4, "shark": 5, "spikes": 7}
## Net styles: 1 standard, 2 Battle Net (0, the Demon Net, is never a stadium's).
const NETS := {"standard": 1, "battle": 2}
const NAME_MAX := 18
const GRAVITY_DEFAULT := -24
const GRAVITY_MIN := -48
const GRAVITY_MAX := -6
## The most hazards a rink may hold (both lists together).
const HAZARDS_MAX := 24
## Where a hazard's point may go: inside the boards with a margin (the
## boards are at |x| 185, |y| 372 - MwRinkShape.BOARD; spikes stand on the
## side boards) - and in the corners within the boards' curve ([method
## on_ice]).
const END_MARGIN := 12
const BOUNDS := Rect2i(-MwSimCollide.BOARD_X, -(MwSimCollide.BOARD_Y - END_MARGIN),
		2 * MwSimCollide.BOARD_X, 2 * (MwSimCollide.BOARD_Y - END_MARGIN))
## Spikes stand on the side boards (owner, 2026-10-11: only at the sides):
## at either board's x (the stadiums' ±185), facing the ice - mirrored on
## the right, as the stadiums' are - and along the boards' straight part.
const SPIKES_X := 185
const SPIKES_Y := 280
## Keep-clear zones (owner, 2026-10-10): the faceoff line-ups (`$1B904`:
## centre |x| <= 60, |y| <= 42; the end circles and the neutral zone's
## spots |x| 44-164, |y| 214-298 / 48-132) and the bench door (substitutes
## come in at the right board near y 10). Nothing is placed in them.
const ZONES := [
	Rect2i(-60, -42, 120, 84), Rect2i(165, -10, 20, 40),
	Rect2i(44, 214, 120, 84), Rect2i(-164, 214, 120, 84), Rect2i(44, -298, 120, 84), Rect2i(-164, -298, 120, 84),
	Rect2i(44, 48, 120, 84), Rect2i(-164, 48, 120, 84), Rect2i(44, -132, 120, 84), Rect2i(-164, -132, 120, 84),
]

var name := "NEW RINK"
## The ice palette the colours started from (0-6, [method MwCustomTeams.ice_presets]:
## the four the stadiums use, then the three beside them that none uses).
var preset := 0
## The 16 colours of the ice line (empty: the preset's).
var colours := PackedInt32Array()
var net := 1
var gravity := GRAVITY_DEFAULT
## [{kind: String, x: int, y: int, mirror: bool}]
var hazards: Array[Dictionary] = []


## Everything into range: the name (the charset, [constant NAME_MAX]; empty: RINK), the preset,
## the colours (a line of 16 or none), net and gravity, and the hazards - known kinds, at most
## [constant HAZARDS_MAX], moved where they may go, those touching a keep-clear zone dropped.
func validate() -> void:
	name = MwCustomTeam.clean_text(name, NAME_MAX)
	if name == "":
		name = "RINK"
	preset = clampi(preset, 0, MwCustomTeams.PRESETS - 1)
	if colours.size() != 16:
		colours = PackedInt32Array()
	for i in colours.size():
		colours[i] &= 0x0EEE
	net = 2 if net == 2 else 1
	gravity = clampi(gravity, GRAVITY_MIN, GRAVITY_MAX)
	var kept: Array[Dictionary] = []
	for h in hazards:
		var k := str(h.get("kind", ""))
		if not KINDS.has(k) or kept.size() >= HAZARDS_MAX:
			continue
		var at := on_ice(int(h.get("x", 0)), int(h.get("y", 0)))
		var x := at.x
		var y := at.y
		var m := bool(h.get("mirror", false))
		if k == "spikes":
			var point := on_boards(x, y)
			x = point.x
			y = point.y
			m = x > 0
		if blocked(k, x, y):
			continue
		kept.append({"kind": k, "x": x, "y": y, "mirror": m})
	hazards = kept


## The point (x, y) kept where a hazard may go: within [constant BOUNDS]
## and, in the corners, within the boards' curve - the sim's own
## (MwRinkShape.half_width: `$8066`'s corner tables) - so nothing is
## placed off the ice (the stadiums' hazards are all inside it).
static func on_ice(x: int, y: int) -> Vector2i:
	y = clampi(y, BOUNDS.position.y, BOUNDS.end.y)
	var half := BOUNDS.end.x
	if MwRom.available():
		half = mini(half, MwRinkShape.half_width(MwRom.archive().bytes(), y))
	return Vector2i(clampi(x, -half, half), y)


## Spikes' place for a point (x, y): the nearer side board, y along its
## straight part.
static func on_boards(x: int, y: int) -> Vector2i:
	return Vector2i(SPIKES_X if x > 0 else -SPIKES_X, clampi(y, -SPIKES_Y, SPIKES_Y))


## True when a hazard of [param kind] at ([param x], [param y]) would touch a
## keep-clear zone (its box against the zones).
static func blocked(kind: String, x: int, y: int) -> bool:
	var k: Array = KINDS.get(kind, [false, 0, 8, 8])
	var box := Rect2i(x - int(k[2]), y - int(k[3]), 2 * int(k[2]), 2 * int(k[3]))
	for z: Rect2i in ZONES:
		if z.intersects(box):
			return true
	return false


## The in-ice hazards (first) or rink objects (true) in placing order.
func list(objects: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in hazards:
		if bool(KINDS[h["kind"]][0]) == objects:
			out.append(h)
	return out


## The matchup's hazard words (`$1CB20` bits), derived from the hazards.
func mask() -> int:
	var m := 0
	for h in hazards:
		m |= 1 << int(MASK_BITS[h["kind"]])
	return m


## The stadium record (name at [param name_at]).
func record_bytes(name_at: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(0xC)
	for i in 4:
		b[i] = (name_at >> (24 - 8 * i)) & 0xFF
	b[4] = 0
	b[5] = net
	b[6] = 0
	b[7] = 1
	b[8] = gravity & 0xFF
	var ice := list(false)
	var obj := list(true)
	b[9] = ice.size()
	b[0xA] = obj.size()
	b[0xB] = mask()
	for h in ice + obj:
		var bytes := PackedByteArray()
		bytes.resize(6)
		bytes[0] = (int(h["x"]) >> 8) & 0xFF
		bytes[1] = int(h["x"]) & 0xFF
		bytes[2] = (int(h["y"]) >> 8) & 0xFF
		bytes[3] = int(h["y"]) & 0xFF
		bytes[4] = int(KINDS[h["kind"]][1])
		bytes[5] = 0x08 if bool(KINDS[h["kind"]][0]) and bool(h["mirror"]) else 0
		b.append_array(bytes)
	return b


## The 16 colours used: [member colours], else the preset's.
func palette(rom: PackedByteArray) -> PackedInt32Array:
	if colours.size() == 16:
		return colours
	return MwCustomTeams.ice_preset(rom, preset)


## A copy of original stadium [param stadium] (team index).
static func from_stadium(rom: PackedByteArray, stadium: int) -> MwCustomRink:
	var custom_rink := MwCustomRink.new()
	var rec := MwRinkState.stadium_record(rom, stadium)
	custom_rink.name = MwGfx.rom_string(rom, MwGfx.u32(rom, rec)).get_string_from_ascii()
	custom_rink.preset = maxi(0, MwCustomTeams.ice_presets(rom).find(MwPalettes.ice_palette(rom, stadium)))
	custom_rink.net = rom[rec + 5]
	custom_rink.gravity = MwGfx.s8(rom, rec + 8)
	var a := rec + 0xC
	for which in 2:
		for i in rom[rec + 9 + which]:
			var kind := rom[a + 4]
			for k in KIND_ORDER:
				if bool(KINDS[k][0]) == (which == 1) and int(KINDS[k][1]) == kind:
					custom_rink.hazards.append({"kind": k, "x": MwGfx.s16(rom, a), "y": MwGfx.s16(rom, a + 2),
							"mirror": rom[a + 5] & 0x08 != 0})
			a += 6
	custom_rink.validate()
	return custom_rink


## The rink as its custom team's JSON keeps it (the colours as words or null, the net by name);
## [method from_dict] reads it back.
func to_dict() -> Dictionary:
	var hz := []
	for h in hazards:
		hz.append(h.duplicate())
	return {
		"name": name, "preset": preset,
		"colours": null if colours.is_empty() else MwCustomTeam.words_out(colours),
		"net": "battle" if net == 2 else "standard", "gravity": gravity, "hazards": hz,
	}


## A rink from [param d] ([method to_dict]'s), read through [MwPlain] - a value of the wrong type
## is its default, at most [constant MwCustomTeam.HAZARDS_READ] hazards - and validated.
static func from_dict(d: Dictionary) -> MwCustomRink:
	var custom_rink := MwCustomRink.new()
	custom_rink.name = MwPlain.text(d.get("name"), custom_rink.name)
	custom_rink.preset = MwPlain.num(d.get("preset"), 0)
	var cs: Variant = d.get("colours")
	if cs is Array:
		custom_rink.colours = MwCustomTeam.words_in(cs)
	custom_rink.net = int(NETS.get(MwPlain.text(d.get("net"), "standard"), 1))
	custom_rink.gravity = MwPlain.num(d.get("gravity"), GRAVITY_DEFAULT)
	var hz: Variant = d.get("hazards", [])
	if hz is Array:
		for h: Variant in (hz as Array).slice(0, MwCustomTeam.HAZARDS_READ):
			if h is Dictionary:
				custom_rink.hazards.append({"kind": MwPlain.text(h.get("kind")), "x": MwPlain.num(h.get("x")),
						"y": MwPlain.num(h.get("y")), "mirror": MwPlain.flag(h.get("mirror"))})
	custom_rink.validate()
	return custom_rink
