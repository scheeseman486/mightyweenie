@tool
class_name RomTileMapLayer
extends TileMapLayer
## A plane of the original, filled from the ROM when the scene loads - in the
## editor and in the game. It stores only references: the tile space
## ([RomTileSet]), the palette ([RomPalette]) and which map to place (a
## catalogue picture or map key, a region of it, where it goes). The
## generated tile set, cells and material are never saved
## ([method _validate_property] drops them from storage).

@export var tiles: RomTileSet:
	set(v):
		if tiles and tiles.changed.is_connected(_queue):
			tiles.changed.disconnect(_queue)
		tiles = v
		if tiles:
			tiles.changed.connect(_queue)
		_queue()
@export var palette: RomPalette:
	set(v):
		if palette and palette.changed.is_connected(_update_material):
			palette.changed.disconnect(_update_material)
		palette = v
		if palette:
			palette.changed.connect(_update_material)
		_update_material()
## Catalogue key of the map: a picture ("picture_024cfc") or a map ("map_049136").
@export var map := "":
	set(v):
		map = v
		_queue()
## Map cells to place (x, y, columns, rows); a zero size means the whole map.
@export var region := Rect2i():
	set(v):
		region = v
		_queue()
## Cell of this layer where the region's top-left goes.
@export var at := Vector2i.ZERO:
	set(v):
		at = v
		_queue()
## Place the region this many times across and down (a plane repeating a
## picture, like the starfield's 64x32 plane holding two copies).
@export var repeat := Vector2i.ONE:
	set(v):
		repeat = v
		_queue()
## Which cells to place by their priority bit (the VDP draws high-priority
## cells above sprites; split a plane into two layers for that).
@export_enum("All", "Low only", "High only") var priority := 0:
	set(v):
		priority = v
		_queue()

const GENERATED := ["tile_map_data", "tile_set", "material"]

var _queued := false


func _ready() -> void:
	rebuild()


## Rebuild once at the end of the frame (several properties change together
## when a scene loads or the inspector edits); before _ready, _ready builds.
func _queue() -> void:
	if is_inside_tree() and not _queued:
		_queued = true
		_rebuild_deferred.call_deferred()


func _rebuild_deferred() -> void:
	_queued = false
	rebuild()


func _validate_property(property: Dictionary) -> void:
	if property.name in GENERATED:
		property.usage &= ~PROPERTY_USAGE_STORAGE


## Map words and size: {cols, rows, word(x, y)} for the map key.
func _map_source() -> Dictionary:
	var e := MwRom.entry(map)
	if e.is_empty():
		return {}
	var rom := MwRom.data()
	if e["kind"] == "picture":
		var w := int(e["width"])
		var base := int(e["map"])
		return {"cols": w, "rows": int(e["height"]), "addr": func(x: int, y: int) -> int: return base + 2 * (y * w + x)}
	if e["kind"] == "map":
		var base := int(e["address"])
		var stride := int(e["src_stride"])
		return {"cols": int(e["cols"]), "rows": int(e["rows"]), "addr": func(x: int, y: int) -> int: return base + y * stride + 2 * x}
	return {}


## Rebuilds the tile set and cells from the ROM.
func rebuild() -> void:
	clear()
	if tiles == null or map == "" or not MwRom.available():
		tile_set = null
		return
	tile_set = tiles.build()
	_update_material()
	var src := _map_source()
	if src.is_empty():
		return
	var rom := MwRom.data()
	var r := region
	if r.size.x <= 0 or r.size.y <= 0:
		r = Rect2i(0, 0, src["cols"], src["rows"])
	var addr: Callable = src["addr"]
	for y in r.size.y:
		for x in r.size.x:
			var word := MwGfx.u16(rom, addr.call(r.position.x + x, r.position.y + y))
			var high := (word & 0x8000) != 0
			if (priority == 1 and high) or (priority == 2 and not high):
				continue
			var coords := tiles.atlas_coords(word & 0x7FF, (word >> 13) & 3)
			if coords.x < 0:
				continue
			var alt := 0
			if word & 0x800:
				alt |= TileSetAtlasSource.TRANSFORM_FLIP_H
			if word & 0x1000:
				alt |= TileSetAtlasSource.TRANSFORM_FLIP_V
			for ry in maxi(repeat.y, 1):
				for rx in maxi(repeat.x, 1):
					set_cell(at + Vector2i(x + rx * r.size.x, y + ry * r.size.y), 0, coords, alt)


func _update_material() -> void:
	material = palette.material() if palette and palette.texture() else null
