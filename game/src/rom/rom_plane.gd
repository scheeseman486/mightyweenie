class_name RomPlane
extends TileMapLayer
## A plane a screen paints at run time, cell by cell, the way the original's
## UI routines write name-table words (see [MwPlanePainter]): backdrop map
## rows, text in the ROM's fonts, frames and fills. Each cell names a tile
## key of its [RomTileSet] (a VRAM bank tile < $800, or a ROM tile number
## >= $800 such as a font glyph's), a palette line and flips. Nothing is
## saved: the screen paints it every time it runs.
##
## The original's priority bit is not kept per cell; screens order their
## layers and sprites instead (docs/architecture.md, Rendering).

@export var tiles: RomTileSet
@export var palette: RomPalette:
	set(v):
		if palette and palette.changed.is_connected(_update_material):
			palette.changed.disconnect(_update_material)
		palette = v
		if palette:
			palette.changed.connect(_update_material)
		_update_material()

## Cells from this row down go to [member lower] instead: the original's
## menus draw through one plane object whose top rows are the window and
## whose lower rows land in plane A (with its own scroll). 0 = no split.
@export var split_row := 0
@export var lower: RomPlane
## The plane that takes this one's high-priority cells (the name-table
## word's bit 15, or the attr's bit 7 of a glyph), drawn above the
## low-priority sprites; none: every cell here (the original's priority is
## then the layer order's).
@export var high_cells: RomPlane
## The priority of the cells [method put] writes next ([method put_word]
## and [MwPlanePainter]'s glyphs set it).
var priority := false

const GENERATED := ["tile_map_data", "tile_set", "material"]

var _built := false


func _ready() -> void:
	build()


func _validate_property(property: Dictionary) -> void:
	if property.name in GENERATED:
		property.usage &= ~PROPERTY_USAGE_STORAGE


## Builds the tile set (once; again after the tile keys change).
func build() -> void:
	if lower:
		lower.build()
	clear()
	_built = false
	if tiles == null or not MwRom.available():
		tile_set = null
		return
	tile_set = tiles.build()
	_built = true
	_update_material()


## Shows the plane scrolled vertically by [param v] pixels (the VDP's
## vscroll: screen line y shows plane line y + v).
func scroll_to(v: int) -> void:
	position.y = -v


## Clears every cell (and the lower plane's).
func wipe() -> void:
	clear()
	if lower:
		lower.clear()
	if high_cells:
		high_cells.clear()


## Cell (x, y) = tile [param key] in palette [param line], flipped as asked.
## Key 0 (the blank tile) clears the cell; unknown keys clear it too.
func put(x: int, y: int, key: int, line: int, hflip := false, vflip := false) -> void:
	if lower and split_row > 0 and y >= split_row:
		lower.priority = priority
		lower.put(x, y, key, line, hflip, vflip)
		return
	if high_cells:
		# one of the two planes holds the cell, the other is cleared there
		var into := high_cells if priority else self
		var other := self if priority else high_cells
		other._set_cell(x, y, 0, 0, false, false)
		into._set_cell(x, y, key, line, hflip, vflip)
		return
	_set_cell(x, y, key, line, hflip, vflip)


func _set_cell(x: int, y: int, key: int, line: int, hflip: bool, vflip: bool) -> void:
	if not _built:
		return
	var at := Vector2i(x, y)
	var coords := tiles.atlas_coords(key, line) if key != 0 else Vector2i(-1, -1)
	if coords.x < 0:
		if get_cell_source_id(at) >= 0:
			erase_cell(at)
		return
	var alt := 0
	if hflip:
		alt |= TileSetAtlasSource.TRANSFORM_FLIP_H
	if vflip:
		alt |= TileSetAtlasSource.TRANSFORM_FLIP_V
	# only what changes: screens repaint texts every pass (the rink's phases),
	# and every changed cell makes the layer rebuild its rendering
	if get_cell_source_id(at) == 0 and get_cell_atlas_coords(at) == coords and get_cell_alternative_tile(at) == alt:
		return
	set_cell(at, 0, coords, alt)


## A name-table word (tile < $800, line bits 13-14, flips bits 11-12).
func put_word(x: int, y: int, word: int) -> void:
	priority = (word & 0x8000) != 0
	put(x, y, word & 0x7FF, (word >> 13) & 3, (word & 0x800) != 0, (word & 0x1000) != 0)


## The tile key, line and flips at (x, y): {key, line, hflip, vflip}; key 0 when empty.
func cell(x: int, y: int) -> Dictionary:
	if lower and split_row > 0 and y >= split_row:
		return lower.cell(x, y)
	var at := Vector2i(x, y)
	if get_cell_source_id(at) < 0:
		return {"key": 0, "line": 0, "hflip": false, "vflip": false}
	var c := get_cell_atlas_coords(at)
	var alt := get_cell_alternative_tile(at)
	var k := tiles.key_at(c)
	return {"key": k.x, "line": k.y, "hflip": (alt & TileSetAtlasSource.TRANSFORM_FLIP_H) != 0,
			"vflip": (alt & TileSetAtlasSource.TRANSFORM_FLIP_V) != 0}


func _update_material() -> void:
	material = palette.material() if palette and palette.texture() else null
