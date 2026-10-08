@tool
class_name RomTileSet
extends Resource
## The VRAM tile space of a screen: catalogue tile banks (pictures,
## tilebanks) at their VRAM bases, plus tiles that stay in the ROM (font
## glyphs) under their ROM tile number (address / 32, always >= $800 - the
## original's own convention for ROM tiles). Stores only the keys; [method build]
## decodes the tiles from the ROM into an indexed (R8) atlas with one copy per
## palette line (value = line * 16 + index), so a cell's palette line is part
## of its atlas coordinates and flips are tile transforms.

const COLUMNS := 32

@export var banks := PackedStringArray():
	set(v):
		banks = v
		_slots = {}
		_keys = PackedInt32Array()
		emit_changed()

## Catalogue keys of fonts whose glyph tiles are added (for [RomPlane] text).
@export var fonts := PackedStringArray():
	set(v):
		fonts = v
		_slots = {}
		_keys = PackedInt32Array()
		emit_changed()

var _slots := {}          # tile key -> slot index in the atlas
var _keys := PackedInt32Array()   # slot index -> tile key

## Built tile sets by their banks and fonts, shared by every screen that
## asks for the same tiles (building the rink's picture takes ~0.1 s).
static var _built := {}


## VRAM tile -> ROM address of its 32 bytes, for all banks (later banks win).
func vram_tiles() -> Dictionary:
	var out := {}
	for key in banks:
		var e := MwRom.entry(key)
		if e.is_empty():
			push_warning("RomTileSet: no catalogue entry '%s'" % key)
			continue
		var base := int(e["vram_base"])
		var src := int(e["tiles"])
		for i in int(e["count"]):
			out[base + i] = src + 32 * i
	if MwRom.available():
		var rom := MwRom.data()
		for key in fonts:
			var f := MwRom.entry(key)
			var fa := int(f["address"]) if not f.is_empty() else key.hex_to_int()
			for g in MwGfx.font_glyphs(rom, fa):
				var p := MwGfx.piece(rom, g)
				for i in int(p["w"]) * int(p["h"]):
					out[int(p["tile"]) + i] = (int(p["tile"]) + i) * 32
	return out


## Builds the TileSet (atlas source 0, 8x8 tiles). Empty without the ROM.
func build() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(8, 8)
	if not MwRom.available():
		return ts
	var cache_key := "%s|%s|%d" % [",".join(banks), ",".join(fonts), MwRom.data().size()]
	if _built.has(cache_key):
		var hit: Array = _built[cache_key]
		_slots = hit[1]
		_keys = PackedInt32Array()
		return hit[0]
	var rom := MwRom.data()
	var tiles := vram_tiles()
	var order := tiles.keys()
	order.sort()
	_slots = {}
	_keys = PackedInt32Array()
	for i in order.size():
		_slots[order[i]] = i
	var n := order.size()
	var rows := ceili(4.0 * n / COLUMNS)
	var img := Image.create_empty(COLUMNS * 8, maxi(rows, 1) * 8, false, Image.FORMAT_R8)
	var data := img.get_data()
	var stride := COLUMNS * 8
	for line in 4:
		for i in n:
			var t := MwGfx.tile_indices(rom, tiles[order[i]])
			var slot := line * n + i
			MwGfx.blit_tile(data, stride, (slot % COLUMNS) * 8, (slot / COLUMNS) * 8, t, line, false, false)
	img.set_data(COLUMNS * 8, maxi(rows, 1) * 8, false, Image.FORMAT_R8, data)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(8, 8)
	for slot in 4 * n:
		src.create_tile(Vector2i(slot % COLUMNS, slot / COLUMNS))
	ts.add_source(src, 0)
	_built[cache_key] = [ts, _slots]
	return ts


## Atlas coordinates of VRAM tile [param tile] in palette [param line], or
## (-1, -1) when no bank covers it. Valid after [method build].
func atlas_coords(tile: int, line: int) -> Vector2i:
	if not _slots.has(tile):
		return Vector2i(-1, -1)
	var slot: int = line * _slots.size() + _slots[tile]
	return Vector2i(slot % COLUMNS, slot / COLUMNS)


## The tile key and palette line at atlas coordinates [param coords]
## (Vector2i(key, line)); (-1, -1) for none. Valid after [method build].
func key_at(coords: Vector2i) -> Vector2i:
	var n := _slots.size()
	if n == 0:
		return Vector2i(-1, -1)
	var slot := coords.y * COLUMNS + coords.x
	var line := slot / n
	var index := slot % n
	if _keys.is_empty():
		_keys.resize(n)
		for k in _slots:
			_keys[_slots[k]] = k
	return Vector2i(_keys[index], line)
