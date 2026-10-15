@tool
class_name RomTileSet
extends Resource
## The VRAM tile space of a screen: catalogue tile banks (pictures,
## tilebanks) at their VRAM bases, plus tiles that stay in the ROM (font
## glyphs) under their ROM tile number (address / 32, always >= $800 - the
## original's own convention for ROM tiles). Stores only the keys; [method build]
## decodes the tiles from the ROM into an indexed (R8) atlas with one copy per
## palette line (value = line * 16 + index), so a cell's palette line is part
## of its atlas coordinates and flips are tile transforms. The port's input
## glyphs (MwGlyphs, plan 23: indexed tiles of port art, under keys from
## [constant MwGlyphs.KEY_BASE]) are in every tile set, so any plane can
## draw them.
##
## The atlas image holds every tile in every line, but the TileSet's tiles
## are made only as planes first draw them ([method atlas_coords]; plan 27):
## making all of them - 4 x (the screen's tiles + 1,925 glyph tiles), about
## 0.1 ms each in Godot - held a screen's first visit for 1-3.5 s.
##
## The atlas itself is drawn once per run at most: the start prepares every
## screen's on workers ([method prepare], MwPreloader), and it is kept in the
## disk cache ([method atlas_cached], MwCache) for the next run.

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
var _src: TileSetAtlasSource       # the built atlas (its tiles made on first use)

## Built tile sets by their banks and fonts, shared by every screen that
## asks for the same tiles (building the rink's picture takes ~0.1 s).
static var _built := {}
## Tiles in their four palette lines ([method _line_tiles]): hex of the tile -> Image.
static var _lines_cache := {}


## VRAM tile -> ROM address of its 32 bytes, for all banks (later banks win).
func vram_tiles() -> Dictionary:
	return vram_tiles_of(banks, fonts)


## [method vram_tiles] of [param banks_] and [param fonts_] (safe on a
## worker once the ROM and its catalogue are loaded).
static func vram_tiles_of(banks_: PackedStringArray, fonts_: PackedStringArray) -> Dictionary:
	var out := {}
	for key in banks_:
		var catalogue_entry := MwRom.entry(key)
		if catalogue_entry.is_empty():
			push_warning("RomTileSet: no catalogue entry '%s'" % key)
			continue
		var base := int(catalogue_entry["vram_base"])
		var src := int(catalogue_entry["tiles"])
		for i in int(catalogue_entry["count"]):
			out[base + i] = src + 32 * i
	if MwRom.available():
		var rom := MwRom.data()
		for key in fonts_:
			var f := MwRom.entry(key)
			var fa := int(f["address"]) if not f.is_empty() else key.hex_to_int()
			for g in MwGfx.font_glyphs(rom, fa):
				var glyph_piece := MwGfx.piece(rom, g)
				for i in int(glyph_piece["w"]) * int(glyph_piece["h"]):
					out[int(glyph_piece["tile"]) + i] = (int(glyph_piece["tile"]) + i) * 32
	return out


## Builds the TileSet (atlas source 0, 8x8 tiles; the tiles themselves are
## made as they are drawn, [method atlas_coords]). Empty without the ROM.
## The atlas comes from a worker that prepared it ([method prepare]), else
## from the disk cache, else is drawn here; the input glyphs' live cells are
## brought up to date either way.
func build() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(8, 8)
	if not MwRom.available():
		return ts
	var key := key_of(banks, fonts)
	if _built.has(key):
		var hit: Array = _built[key]
		_slots = hit[1]
		_keys = PackedInt32Array()
		_src = (hit[0] as TileSet).get_source(0) as TileSetAtlasSource
		return hit[0]
	var a := _take(key)
	if a.is_empty():
		a = atlas_cached(banks, fonts, MwGlyphs.tiles(), MwGlyphs.fixed_hash())
	_finish(a, MwGlyphs.tiles(), MwGlyphs.live_hash())
	_slots = a["slots"] if a.has("slots") else _slots_of(a["order"])
	_keys = PackedInt32Array()
	var img := Image.create_from_data(int(a["w"]), int(a["h"]), false, Image.FORMAT_R8, a["data"])
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(8, 8)
	ts.add_source(src, 0)
	_src = src
	_built[key] = [ts, _slots, img, src.texture]
	return ts


# --- the atlas, off the main thread and on disk (plan 27) ----------------------------------------

## What an atlas is drawn from besides the ROM and the glyphs: editing one
## draws the cached atlases again (runs from the project's sources).
const SOURCES := ["res://src/rom/rom_tile_set.gd", "res://src/rom/gfx.gd", "res://data/rom_catalogue.json"]

## Workers' atlases by key until a screen builds them ([method prepare]).
static var _prepared := {}
static var _lock := Mutex.new()
## Workers still drawing or reading an atlas: key -> task (main thread only).
static var _tasks := {}
## The glyphs the workers draw from (a copy per MwGlyphs.generation).
static var _snapshot := {}
static var _snapshot_gen := -1


## The key of the tile set of [param banks_] and [param fonts_].
static func key_of(banks_: PackedStringArray, fonts_: PackedStringArray) -> String:
	return "%s|%s|%d" % [",".join(banks_), ",".join(fonts_), MwRom.data().size()]


## The atlas of [param banks_], [param fonts_] and the glyph tiles
## [param glyphs] (key -> 64 indices): {order (slot -> tile key, sorted),
## w, h, data (R8 pixels, a copy of every tile per palette line), live
## (MwGlyphs.live_hash_of the cells drawn)}. Safe on a worker.
static func atlas_of(banks_: PackedStringArray, fonts_: PackedStringArray, glyphs: Dictionary) -> Dictionary:
	var rom := MwRom.data()
	var tiles := vram_tiles_of(banks_, fonts_)
	tiles.merge(glyphs)
	var keys := tiles.keys()
	keys.sort()
	var order := PackedInt32Array(keys)
	var n := order.size()
	var w := COLUMNS * 8
	var h := maxi(ceili(4.0 * n / COLUMNS), 1) * 8
	var data := PackedByteArray()
	data.resize(w * h)
	for i in n:
		var src_tile: Variant = tiles[order[i]]
		var t: PackedByteArray = src_tile if src_tile is PackedByteArray else MwGfx.tile_indices(rom, src_tile)
		if t.size() != 64:
			continue
		for line in 4:
			var slot := line * n + i
			MwGfx.blit_tile(data, w, (slot % COLUMNS) * 8, (slot / COLUMNS) * 8, t, line, false, false)
	return {"order": order, "w": w, "h": h, "data": data, "live": MwGlyphs.live_hash_of(glyphs)}


## [method atlas_of] read from the disk cache (MwCache), or drawn and kept
## there; [param fixed] is MwGlyphs.fixed_hash (other glyph art draws it
## again). Safe on a worker.
static func atlas_cached(banks_: PackedStringArray, fonts_: PackedStringArray, glyphs: Dictionary,
		fixed: String) -> Dictionary:
	var name := "atlas-" + key_of(banks_, fonts_).sha1_text().substr(0, 12)
	var got: Variant = MwCache.read(name, SOURCES)
	if got is Dictionary and _whole(got) and got.get("fixed", "") == fixed:
		return got
	var a := atlas_of(banks_, fonts_, glyphs)
	a["fixed"] = fixed
	MwCache.write(name, SOURCES, a)
	return a


## Starts preparing the atlas of [param banks_] and [param fonts_] on a
## worker (once per key; nothing without the ROM), for [method build] to
## take. Main thread: the ROM, its catalogue, the glyphs and the cache's
## identity are read here first, and the worker gets a copy of the glyphs.
static func prepare(banks_: PackedStringArray, fonts_: PackedStringArray) -> void:
	if not MwRom.available():
		return
	var key := key_of(banks_, fonts_)
	if _built.has(key) or _tasks.has(key):
		return
	MwRom.catalogue()
	MwCache.prepare()
	var glyphs := MwGlyphs.tiles()
	if _snapshot_gen != MwGlyphs.generation or _snapshot.size() != glyphs.size():
		_snapshot = glyphs.duplicate()      # the workers' copy, never changed after
		_snapshot_gen = MwGlyphs.generation
	var task := Callable(RomTileSet, "_prepare_task").bind(key, banks_, fonts_, _snapshot,
			MwGlyphs.fixed_hash(), MwGlyphs.live_hash())
	_tasks[key] = WorkerThreadPool.add_task(task, false, "mightyweenie: a tile set's atlas")


## The atlases still being prepared (and the finished workers let go).
static func preparing() -> int:
	for key in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[key]):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
	return _tasks.size()


## Forgets every built and prepared tile set (tests; after waiting for the workers).
static func forget() -> void:
	for key in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
	_tasks = {}
	_prepared = {}
	_built = {}


static func _prepare_task(key: String, banks_: PackedStringArray, fonts_: PackedStringArray,
		glyphs: Dictionary, fixed: String, live: String) -> void:
	var a := atlas_cached(banks_, fonts_, glyphs, fixed)
	_finish(a, glyphs, live)
	a["slots"] = _slots_of(a["order"])
	_lock.lock()
	_prepared[key] = a
	_lock.unlock()


## The prepared atlas of [param key] ({} if none), waiting for its worker.
static func _take(key: String) -> Dictionary:
	if _tasks.has(key):
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
		_tasks.erase(key)
	_lock.lock()
	var a: Dictionary = _prepared.get(key, {})
	_prepared.erase(key)
	_lock.unlock()
	return a


## Draws the glyphs' live cells into atlas [param a] from [param glyphs]
## unless it already has the cells of hash [param live].
static func _finish(a: Dictionary, glyphs: Dictionary, live: String) -> void:
	if a.get("live", "") == live:
		return
	var order: PackedInt32Array = a["order"]
	var data: PackedByteArray = a["data"]
	var w: int = a["w"]
	var n := order.size()
	var i := order.bsearch(MwGlyphs.LIVE_BASE)
	while i < n and MwGlyphs.is_live(order[i]):
		var t: PackedByteArray = glyphs.get(order[i], PackedByteArray())
		if t.size() == 64:
			for line in 4:
				var slot := line * n + i
				MwGfx.blit_tile(data, w, (slot % COLUMNS) * 8, (slot / COLUMNS) * 8, t, line, false, false, false)
		i += 1
	a["data"] = data
	a["live"] = live


static func _slots_of(order: PackedInt32Array) -> Dictionary:
	var out := {}
	for i in order.size():
		out[order[i]] = i
	return out


## Whether [param a] (read from disk) is a whole atlas.
static func _whole(a: Dictionary) -> bool:
	if not (a.get("order") is PackedInt32Array and a.get("data") is PackedByteArray
			and a.get("w") is int and a.get("h") is int):
		return false
	var n := (a["order"] as PackedInt32Array).size()
	return int(a["w"]) == COLUMNS * 8 and int(a["h"]) >= ceili(4.0 * n / COLUMNS) * 8 \
			and (a["data"] as PackedByteArray).size() == int(a["w"]) * int(a["h"])


## Redraws tiles [param changed_tiles] (key -> 64 indices: the glyphs' live
## cells, MwGlyphs.refresh_live) in every built tile set that has them.
static func update_tiles(changed_tiles: Dictionary) -> void:
	if changed_tiles.is_empty():
		return
	for k in _built:
		var built_set: Array = _built[k]
		var slots: Dictionary = built_set[1]
		var img: Image = built_set[2]
		var n := slots.size()
		var any := false
		for key in changed_tiles:
			if not slots.has(key):
				continue
			any = true
			var lines := _line_tiles(changed_tiles[key])
			for line in 4:
				var slot: int = line * n + slots[key]
				img.blit_rect(lines, Rect2i(0, 8 * line, 8, 8), Vector2i((slot % COLUMNS) * 8, (slot / COLUMNS) * 8))
		if any:
			(built_set[3] as ImageTexture).update(img)


## Tile [param t] (64 colour indices) in palette lines 0-3, one under the
## other (8 x 32, R8: index + 16 x line, 0 stays 0 - MwGfx.blit_tile's
## opaque rule), made once per tile: [method update_tiles] copies them with
## the image's own blit (owner, 2026-10-12: the per-pixel copy into every
## atlas was the bigger half of a device switch's hitch).
static func _line_tiles(t: PackedByteArray) -> Image:
	var k := t.hex_encode()
	var img: Image = _lines_cache.get(k)
	if img != null:
		return img
	var b := PackedByteArray()
	b.resize(256)
	for line in 4:
		var base := 16 * line
		for i in mini(t.size(), 64):
			b[64 * line + i] = 0 if t[i] == 0 else base + t[i]
	img = Image.create_from_data(8, 32, false, Image.FORMAT_R8, b)
	_lines_cache[k] = img
	return img


## Atlas coordinates of VRAM tile [param tile] in palette [param line], or
## (-1, -1) when no bank covers it, its Godot tile made if it wasn't yet.
## Valid after [method build].
func atlas_coords(tile: int, line: int) -> Vector2i:
	if not _slots.has(tile):
		return Vector2i(-1, -1)
	var slot: int = line * _slots.size() + _slots[tile]
	var c := Vector2i(slot % COLUMNS, slot / COLUMNS)
	if _src != null and not _src.has_tile(c):
		_src.create_tile(c)
	return c


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
