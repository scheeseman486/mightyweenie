class_name MwPlayerColours
extends RefCounted
## The twelve players' colours (plan 34, section 4): what tells the players
## apart wherever they show - the rink's crossbones under their skaters, the
## off-screen arrows, the cursors and highlights of the controller and
## character selection, the vote. Players 1-4 keep the original's: each
## pad's crossbones frame (`$1C5C2`: the CPU carrier's grey, then pads 1-4)
## differs from the others in one colour of the rink's line 3, read from the
## ROM at run time ([method rom_face]). Players 5-12 have the port's own
## colours ([constant PORT], Genesis colour words at the console's levels),
## chosen by [method check]: CIEDE2000 at least [constant APART] from every
## other player's and the CPU carrier's grey, and at least
## [constant FROM_ICE] from every ice colour (the four ice palettes' surface)
## and the crossbones' own outline, shade and highlight. Wherever there is
## room the player's number goes with the colour (P7), so colour is never
## the only cue. A crossbones or an arrow in a player's colour is the
## original's player-1 shape with that colour in its face index
## ([method face_index]).

## Players 5-12: orange, purple, sky, pink, olive, brown, teal, maroon
## (Genesis words: 0000BBB0GGG0RRR0). The port's own.
const PORT := [0x0AE, 0xE68, 0xEA0, 0x88E, 0x066, 0x028, 0x8A0, 0x608]
const PLAYERS := MwVerbs.PLAYERS
## The check's limits (CIEDE2000).
const APART := 20.0
const FROM_ICE := 15.0
## The crossbones' frames: the CPU carrier's, then pads 1-4's.
const CROSSBONES := MwRinkDraw.CROSSBONES
## The rink's line 3 (MwScreenPalettes: screens 4-7).
const RINK_SCREEN := 4


## Player [param player]'s colour (1-12) as a Genesis word.
static func face(rom: PackedByteArray, player: int) -> int:
	if player >= 1 and player <= 4:
		return rom_face(rom, player - 1)
	return PORT[clampi(player - 5, 0, PORT.size() - 1)]


## Player [param player]'s colour as the port shows it.
static func colour(rom: PackedByteArray, player: int) -> Color:
	return MwGfx.color(face(rom, player))


## The line-3 index of the crossbones frame [param k] (0 the CPU carrier's,
## 1-4 pads 1-4) that no other of the five frames uses: its face.
static func face_index(rom: PackedByteArray, k: int) -> int:
	var own := _indices(rom, k)
	for j in 5:
		if j != k:
			for i in _indices(rom, j):
				own.erase(i)
	return own.keys()[0] if own.size() == 1 else -1


## The crossbones' indices every frame shares (outline, shade, highlight).
static func shared_indices(rom: PackedByteArray) -> Array:
	var all := _indices(rom, 0)
	for k in range(1, 5):
		var other := _indices(rom, k)
		for i in all.keys():
			if not other.has(i):
				all.erase(i)
	all.erase(0)
	return all.keys()


## The crossbones' outline: the darkest of the indices every frame shares
## in the rink's line 3 (plan 34: the owners' hollow mark's outline, MwPlate).
static func outline_index(rom: PackedByteArray) -> int:
	var l3 := _line3(rom)
	var best := -1
	var dark := 1e9
	for i: int in shared_indices(rom):
		var c := MwGfx.color(l3[i])
		var lum := c.r + c.g + c.b
		if lum < dark:
			dark = lum
			best = i
	return best


## Pad [param pad]'s (0-3) crossbones colour: its face index in the rink's line 3.
static func rom_face(rom: PackedByteArray, pad: int) -> int:
	return _line3(rom)[face_index(rom, pad + 1)]


## The CPU carrier's crossbones colour (the grey).
static func cpu_face(rom: PackedByteArray) -> int:
	return _line3(rom)[face_index(rom, 0)]


## The ice surface colours: each ice palette's backdrop (its colour 0, the
## colour of the bare ice), each once.
static func ice(rom: PackedByteArray) -> Array[int]:
	var out: Array[int] = []
	for st in MwTeams.COUNT:
		var w := MwGfx.u16(rom, MwPalettes.ice_palette(rom, st))
		if not w in out:
			out.append(w)
	return out


## What breaks the rules ([constant APART], [constant FROM_ICE]): one line
## per failure, empty when the colours pass.
static func check(rom: PackedByteArray) -> Array[String]:
	var out: Array[String] = []
	var faces: Array[Color] = []
	for p in range(1, PLAYERS + 1):
		faces.append(colour(rom, p))
	var line := _line3(rom)
	for p in range(4, PLAYERS):
		for q in p:
			var d := ciede2000(faces[p], faces[q])
			if d < APART:
				out.append("P%d and P%d: %.1f" % [p + 1, q + 1, d])
		var dc := ciede2000(faces[p], MwGfx.color(cpu_face(rom)))
		if dc < APART:
			out.append("P%d and the CPU's grey: %.1f" % [p + 1, dc])
		for w in ice(rom):
			var di := ciede2000(faces[p], MwGfx.color(w))
			if di < FROM_ICE:
				out.append("P%d and an ice: %.1f" % [p + 1, di])
		for i in shared_indices(rom):
			var ds := ciede2000(faces[p], MwGfx.color(line[i]))
			if ds < FROM_ICE:
				out.append("P%d and the crossbones' colour %d: %.1f" % [p + 1, i, ds])
	return out


## The smallest distance between any two players' colours.
static func closest(rom: PackedByteArray) -> float:
	var m := INF
	for p in range(1, PLAYERS + 1):
		for q in range(1, p):
			m = minf(m, ciede2000(colour(rom, p), colour(rom, q)))
	return m


## CIEDE2000 colour difference of two sRGB colours (CIE Lab, D65).
static func ciede2000(c1: Color, c2: Color) -> float:
	return ciede2000_lab(lab(c1), lab(c2))


## CIEDE2000 of two CIE Lab colours (Vector3(L, a, b); Sharma, Wu and
## Dalal's formulation).
static func ciede2000_lab(l1: Vector3, l2: Vector3) -> float:
	var cb := (Vector2(l1.y, l1.z).length() + Vector2(l2.y, l2.z).length()) / 2.0
	var g := 0.5 * (1.0 - sqrt(pow(cb, 7) / (pow(cb, 7) + pow(25.0, 7))))
	var a1 := (1.0 + g) * l1.y
	var a2 := (1.0 + g) * l2.y
	var c1p := Vector2(a1, l1.z).length()
	var c2p := Vector2(a2, l2.z).length()
	var h1 := fposmod(rad_to_deg(atan2(l1.z, a1)), 360.0)
	var h2 := fposmod(rad_to_deg(atan2(l2.z, a2)), 360.0)
	var dl := l2.x - l1.x
	var dc := c2p - c1p
	var dh := 0.0
	if c1p * c2p != 0.0:
		dh = h2 - h1
		if dh > 180.0:
			dh -= 360.0
		elif dh < -180.0:
			dh += 360.0
	var dhh := 2.0 * sqrt(c1p * c2p) * sin(deg_to_rad(dh / 2.0))
	var lb := (l1.x + l2.x) / 2.0
	var cbp := (c1p + c2p) / 2.0
	var hb := h1 + h2
	if c1p * c2p != 0.0:
		if absf(h1 - h2) <= 180.0:
			hb = (h1 + h2) / 2.0
		else:
			hb = (h1 + h2 + 360.0) / 2.0 if h1 + h2 < 360.0 else (h1 + h2 - 360.0) / 2.0
	var t := 1.0 - 0.17 * cos(deg_to_rad(hb - 30.0)) + 0.24 * cos(deg_to_rad(2.0 * hb)) \
			+ 0.32 * cos(deg_to_rad(3.0 * hb + 6.0)) - 0.20 * cos(deg_to_rad(4.0 * hb - 63.0))
	var dth := 30.0 * exp(-pow((hb - 275.0) / 25.0, 2))
	var rc := 2.0 * sqrt(pow(cbp, 7) / (pow(cbp, 7) + pow(25.0, 7)))
	var sl := 1.0 + 0.015 * pow(lb - 50.0, 2) / sqrt(20.0 + pow(lb - 50.0, 2))
	var sc := 1.0 + 0.045 * cbp
	var sh := 1.0 + 0.015 * cbp * t
	var rt := -sin(deg_to_rad(2.0 * dth)) * rc
	return sqrt(pow(dl / sl, 2) + pow(dc / sc, 2) + pow(dhh / sh, 2) + rt * (dc / sc) * (dhh / sh))


## An sRGB colour in CIE Lab (D65): Vector3(L, a, b).
static func lab(c: Color) -> Vector3:
	var lin := func(u: float) -> float: return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)
	var r: float = lin.call(c.r)
	var g: float = lin.call(c.g)
	var b: float = lin.call(c.b)
	var x := (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	var y := 0.2126 * r + 0.7152 * g + 0.0722 * b
	var z := (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	var f := func(v: float) -> float: return pow(v, 1.0 / 3.0) if v > 0.008856 else 7.787 * v + 16.0 / 116.0
	var fx: float = f.call(x)
	var fy: float = f.call(y)
	var fz: float = f.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _indices(rom: PackedByteArray, k: int) -> Dictionary:
	var out := {}
	for p in MwGfx.frame_pieces(rom, MwGfx.u32(rom, CROSSBONES + 4 * k)):
		var t: int = p["tile"]
		if t < 0x800:
			continue
		for v in MwGfx.tiles(rom, t * 32, p["w"] * p["h"]):
			out[v] = true
	return out


static func _line3(rom: PackedByteArray) -> PackedInt32Array:
	var c := MwScreenPalettes.palette(RINK_SCREEN).build(rom)
	return c.slice(48, 64)
