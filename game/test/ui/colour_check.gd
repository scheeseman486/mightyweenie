extends SceneTree
## Plan 34's colour check (tools/bin/colour-check): the twelve players'
## colours (MwPlayerColours) against each other, the CPU carrier's grey,
## the ice and the crossbones' own colours - printed, exit 1 on a failure.
## With [code]--sheet PATH[/code] also a contact sheet (PNG, 3x): each ice's
## bare surface with the CPU's and the twelve players' crossbones on it and
## their numbers, then the players' numbers on the menus' black. The sheet
## is made from the ROM at run time: it stays out of the repository.
##   godot --headless -s res://test/ui/colour_check.gd -- [--sheet PATH]

const SCALE := 3
const CELL := 40          # pixels per crossbones column
const ROW := 44           # pixels per ice row


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	MwRom.use(null)
	if not MwRom.available():
		print("colour-check: the ROM isn't installed (tools/bin/setup-rom)")
		quit(2)
		return
	var rom := MwRom.data()
	for p in range(1, MwPlayerColours.PLAYERS + 1):
		var nearest := INF
		for q in range(1, MwPlayerColours.PLAYERS + 1):
			if q != p:
				nearest = minf(nearest, MwPlayerColours.ciede2000(MwPlayerColours.colour(rom, p),
						MwPlayerColours.colour(rom, q)))
		var ice := INF
		for w in MwPlayerColours.ice(rom):
			ice = minf(ice, MwPlayerColours.ciede2000(MwPlayerColours.colour(rom, p), MwGfx.color(w)))
		print("P%-2d %s  nearest player %5.1f  ice %5.1f  CPU %5.1f%s"
				% [p, "rom" if p <= 4 else "%03X" % MwPlayerColours.face(rom, p),
				nearest, ice, MwPlayerColours.ciede2000(MwPlayerColours.colour(rom, p),
				MwGfx.color(MwPlayerColours.cpu_face(rom))),
				"" if p > 4 else "  (the original's)"])
	var fails := MwPlayerColours.check(rom)
	for f in fails:
		print("FAIL ", f)
	print("closest two players: %.1f; %s" % [MwPlayerColours.closest(rom),
			"pass" if fails.is_empty() else "%d failures" % fails.size()])
	var at := args.find("--sheet")
	if at >= 0 and at + 1 < args.size():
		var img := sheet(rom)
		img.save_png(args[at + 1])
		print("sheet: ", args[at + 1])
	quit(0 if fails.is_empty() else 1)


## The contact sheet (see the script's description).
static func sheet(rom: PackedByteArray) -> Image:
	var ices := MwPlayerColours.ice(rom)
	var w := CELL * (MwPlayerColours.PLAYERS + 1) + 8
	var h := ROW * (ices.size() + 1)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var line := MwPlayerColours._line3(rom)
	for r in ices.size():
		img.fill_rect(Rect2i(0, r * ROW, w, ROW), MwGfx.color(ices[r]))
		for k in MwPlayerColours.PLAYERS + 1:
			var x := 4 + CELL * k + CELL / 2
			var y := r * ROW + 16
			_crossbones(img, rom, line, k, x, y)
			_label(img, rom, "CPU" if k == 0 else "P%d" % k, x, y + 14, Color.BLACK)
	img.fill_rect(Rect2i(0, ices.size() * ROW, w, ROW), Color.BLACK)
	for p in range(1, MwPlayerColours.PLAYERS + 1):
		_label(img, rom, "P%d" % p, 4 + CELL * p + CELL / 2, ices.size() * ROW + 20, MwPlayerColours.colour(rom, p))
	img.resize(w * SCALE, h * SCALE, Image.INTERPOLATE_NEAREST)
	return img


## Crossbones [param k] (0 the CPU's, then players 1-12: 5-12 the first
## pad's shape in their colour) centred on (x, y).
static func _crossbones(img: Image, rom: PackedByteArray, line: PackedInt32Array, k: int, x: int, y: int) -> void:
	var frame := mini(k, 4) if k <= 4 else 1
	var cols := line.duplicate()
	if k > 4:
		cols[MwPlayerColours.face_index(rom, 1)] = MwPlayerColours.face(rom, k)
	for p in MwGfx.frame_pieces(rom, MwGfx.u32(rom, MwPlayerColours.CROSSBONES + 4 * frame)):
		var t: int = p["tile"]
		if t < 0x800:
			continue
		var px := MwGfx.tiles(rom, t * 32, p["w"] * p["h"])
		for cx in p["w"]:
			for cy in p["h"]:
				var tile: int = cx * p["h"] + cy
				for i in 64:
					var v := px[64 * tile + i]
					if v == 0:
						continue
					var tx := i % 8
					var ty := i / 8
					var fx: int = 8 * cx + tx
					var fy: int = 8 * cy + ty
					if p["attr"] & 0x08:
						fx = 8 * p["w"] - 1 - fx
					if p["attr"] & 0x10:
						fy = 8 * p["h"] - 1 - fy
					var ix: int = x + p["x"] + fx
					var iy: int = y + p["y"] + fy
					if ix >= 0 and iy >= 0 and ix < img.get_width() and iy < img.get_height():
						img.set_pixel(ix, iy, MwGfx.color(cols[v]))


## [param text] in the menus' font, centred on [param x], its top at [param y], in [param c].
static func _label(img: Image, rom: PackedByteArray, text: String, x: int, y: int, c: Color) -> void:
	var font := MwPlanePainter.FONT_MENU
	var glyphs := []
	var width := 0
	for ch in text.to_ascii_buffer():
		var g := MwGfx.font_glyph(rom, font, ch)
		if g < 0:
			continue
		var glyph_piece := MwGfx.piece(rom, font + 8 + 6 * g)
		glyphs.append(glyph_piece)
		width += 8 * int(glyph_piece["w"])
	var at := x - width / 2
	for p in glyphs:
		var t: int = p["tile"]
		var px := MwGfx.tiles(rom, t * 32, p["w"] * p["h"])
		var counts := {}
		for v in px:
			counts[v] = counts.get(v, 0) + 1
		var paper: int = counts.keys().reduce(func(a, b): return a if counts[a] >= counts[b] else b)
		for cx in p["w"]:
			for cy in p["h"]:
				for i in 64:
					var v := px[64 * (cx * p["h"] + cy) + i]
					if v != 0 and v != paper:      # the ink, not the glyph's paper
						img.set_pixel(at + 8 * cx + i % 8, y + 8 * cy + i / 8, c)
		at += 8 * int(p["w"])
