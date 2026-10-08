class_name MwSpriteLayer
extends Node2D
## Shows a sprite list ([method MwRinkDraw.sprites]: entries in VDP link
## order, front first) as Godot sprites, one per piece: textures decoded from
## the ROM's tiles (or RAM-built tiles, [member ram_tiles]) and drawn with
## the palette-swap shader. Pieces with the priority bit go to the layer
## with [member high] set, the others to the low one, so the planes' high
## cells can sit between.
##
## The VDP first picks the frontmost sprite pixel (link order), then lets
## that pixel's priority decide against the planes; a shadow/highlight
## operator pixel is such a pixel too and darkens or lightens the planes, not
## the sprites behind it. So pieces lose the pixels where a piece in front
## of them has an operator pixel, and a high-priority piece also loses those
## a low-priority piece in front of it covers (the faceoff puck below z 50,
## the referee on the ice): it is above the planes but hidden by that piece.
##
## Nothing here is saved: the pool and the textures are made at run time.

const SPRITE_ORIGIN := 0x80

@export var palette: RomPalette:
	set(v):
		palette = v
		_material = null
## Which pieces: false = priority bit clear, true = set.
@export var high := false
## VRAM tiles the original builds in RAM (the info plates): tile index ->
## 32 bytes (4 bits per pixel, as in VRAM).
var ram_tiles := {}

var _pool: Array[Sprite2D] = []
var _cache := {}                     ## Vector3i(tile, size, line) -> ImageTexture (ROM tiles)
var _pixel_cache := {}               ## the same key -> the texture's indexed pixels (no GPU readback)
var _cut_cache := {}                 ## a covered piece and what covers it -> its cut texture
var _operators := {}
var _material: ShaderMaterial

## Cut textures kept at most (pieces move every pass; the cache is emptied
## when it grows past this).
const CUT_CACHE_MAX := 256

var _last_pixels := PackedByteArray()   ## the pixels [method _texture] made last (RAM tiles: not cached)


## Shows the pieces of [param entries] ([x, y, size, attr, tile, depth],
## sprite coordinates) that belong to this layer.
func show_list(entries: Array) -> void:
	if _material == null and palette and palette.texture():
		_material = palette.material(true)
	var mine := []
	var covers := []          # per piece: the pieces in front of it that hide some of its pixels
	for idx in entries.size():
		var e: Array = entries[idx]
		var is_high := (int(e[3]) & 0x80) != 0
		if is_high != high:
			continue
		mine.append(e)
		var cover := []
		for j in idx:
			var f: Array = entries[j]
			if ((is_high and (int(f[3]) & 0x80) == 0) or _has_operators(f)) and _overlap(f, e):
				cover.append(f)
		covers.append(cover)
	while _pool.size() < mine.size():
		var s := Sprite2D.new()
		s.centered = false
		add_child(s)
		_pool.append(s)
	var n := mine.size()
	for i in _pool.size():
		var s := _pool[i]
		if i >= n:
			s.visible = false
			continue
		var e: Array = mine[n - 1 - i]          # back to front
		var cover: Array = covers[n - 1 - i]
		var attr := int(e[3])
		if cover.is_empty() and e.size() < 7:
			s.texture = _texture(int(e[4]), int(e[2]), (attr >> 5) & 3)
			s.flip_h = (attr & 0x08) != 0
			s.flip_v = (attr & 0x10) != 0
		else:
			s.texture = _cut(e, cover)
			s.flip_h = false
			s.flip_v = false
		s.position = Vector2(int(e[0]) - SPRITE_ORIGIN, int(e[1]) - SPRITE_ORIGIN)
		s.material = _material
		s.visible = s.texture != null


## Whether a piece has shadow/highlight operator pixels (line 3, colours 14-15).
func _has_operators(e: Array) -> bool:
	if (int(e[3]) >> 5) & 3 != 3:
		return false
	var key := Vector2i(int(e[4]), int(e[2]))
	if not _operators.has(key) or int(e[4]) < 0x800:
		var px := _pixels(e)
		var found := false
		for v in px:
			if v == 62 or v == 63:
				found = true
				break
		_operators[key] = found
	return _operators[key]


## Whether two pieces' rectangles overlap.
static func _overlap(a: Array, b: Array) -> bool:
	var aw := 8 * (((int(a[2]) >> 2) & 3) + 1)
	var ah := 8 * ((int(a[2]) & 3) + 1)
	var bw := 8 * (((int(b[2]) >> 2) & 3) + 1)
	var bh := 8 * ((int(b[2]) & 3) + 1)
	return int(a[0]) < int(b[0]) + bw and int(b[0]) < int(a[0]) + aw \
			and int(a[1]) < int(b[1]) + bh and int(b[1]) < int(a[1]) + ah


## Piece [param e]'s pixels as shown (flips applied), less every pixel that
## a piece of [param cover] (in front of it) has opaque, and less its rows
## from a cut row on (a seventh value, sprite coordinates: [MwScreenDraw]).
## Cached by the pieces and their relative positions (a stoppage icon or
## portrait over standing players gives the same cut pass after pass).
func _cut(e: Array, cover: Array) -> ImageTexture:
	var key := "%d,%d,%d" % [int(e[2]), int(e[3]), int(e[4])]
	var cut_at := int(e[6]) - int(e[1]) if e.size() > 6 else 0x7FFF
	if cut_at != 0x7FFF:
		key += "|cut%d" % cut_at
	var cacheable := int(e[4]) >= 0x800          # RAM tiles (the plates) change
	for l in cover:
		key += "|%d,%d,%d,%d,%d" % [int(l[0]) - int(e[0]), int(l[1]) - int(e[1]), int(l[2]), int(l[3]), int(l[4])]
		cacheable = cacheable and int(l[4]) >= 0x800
	if cacheable and _cut_cache.has(key):
		return _cut_cache[key]
	var px := _pixels(e)
	var w := 8 * (((int(e[2]) >> 2) & 3) + 1)
	var h := px.size() / w
	for l in cover:
		var lp := _pixels(l)
		var lw := 8 * (((int(l[2]) >> 2) & 3) + 1)
		var lh := lp.size() / lw
		for y in h:
			var ly := int(e[1]) + y - int(l[1])
			if ly < 0 or ly >= lh:
				continue
			for x in w:
				var lx := int(e[0]) + x - int(l[0])
				if lx >= 0 and lx < lw and lp[ly * lw + lx] != 0:
					px[y * w + x] = 0
	for y in range(clampi(cut_at, 0, h), h):
		for x in w:
			px[y * w + x] = 0
	var tex := ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_R8, px))
	if cacheable:
		if _cut_cache.size() >= CUT_CACHE_MAX:
			_cut_cache.clear()
		_cut_cache[key] = tex
	return tex


## Piece [param e]'s indexed pixels with its flips applied (from the pixel
## cache: reading a texture back from the GPU every pass stalls the frame).
func _pixels(e: Array) -> PackedByteArray:
	var attr := int(e[3])
	var size := int(e[2])
	var line := (attr >> 5) & 3
	var key := Vector3i(int(e[4]), size, line)
	var src: PackedByteArray
	if int(e[4]) >= 0x800 and _pixel_cache.has(key):
		src = _pixel_cache[key]
	else:
		_texture(int(e[4]), size, line)
		src = _pixel_cache.get(key, _last_pixels)
	var w := 8 * (((size >> 2) & 3) + 1)
	var h := 8 * ((size & 3) + 1)
	if attr & 0x18 == 0:
		return src.duplicate()
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		var sy := h - 1 - y if attr & 0x10 else y
		for x in w:
			var sx := w - 1 - x if attr & 0x08 else x
			out[y * w + x] = src[sy * w + sx]
	return out


## A piece's tiles (column-major) as an indexed texture on palette [param line].
func _texture(tile: int, size: int, line: int) -> ImageTexture:
	var w := ((size >> 2) & 3) + 1
	var h := (size & 3) + 1
	var from_ram := tile < 0x800
	var key := Vector3i(tile, size, line)
	if not from_ram and _cache.has(key):
		return _cache[key]
	if not MwRom.available():
		return null
	var rom := MwRom.data()
	var px := PackedByteArray()
	px.resize(64 * w * h)
	for cx in w:
		for cy in h:
			var n := cx * h + cy
			var t: PackedByteArray
			if from_ram:
				var raw: PackedByteArray = ram_tiles.get(tile + n, PackedByteArray())
				t = _indices(raw) if raw.size() == 32 else PackedByteArray()
			else:
				# the original's sprite tile cache bug in three pieces (MwSpriteCacheQuirk)
				var shown := MwSpriteCacheQuirk.tile(tile, size, n)
				if shown < 0x800:
					continue
				t = MwGfx.tile_indices(rom, shown << 5)
			if t.is_empty():
				continue
			MwGfx.blit_tile(px, 8 * w, 8 * cx, 8 * cy, t, line, false, false)
	var tex := ImageTexture.create_from_image(Image.create_from_data(8 * w, 8 * h, false, Image.FORMAT_R8, px))
	_last_pixels = px
	if not from_ram:
		_cache[key] = tex
		_pixel_cache[key] = px
	return tex


## 32 bytes of 4-bit pixels -> 64 colour indices.
static func _indices(raw: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(64)
	for i in 32:
		out[2 * i] = raw[i] >> 4
		out[2 * i + 1] = raw[i] & 15
	return out
