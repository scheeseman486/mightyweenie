@tool
class_name RomText
extends Sprite2D
## A line of text in one of the original's fonts, drawn the way `draw_text`
## ($14CAE) puts it into a plane: glyphs on the font's baseline from cell
## [member cell], palette line [member line], palette-swapped like the other
## ROM nodes. Stores references only (font key, ROM string address or a
## string typed in code, cell); the texture and material are generated.
## The node's position is the plane's origin (normally 0, 0).

## Catalogue key of the font ("font_022ee0") or its address in hex.
@export var font := "":
	set(v):
		font = v
		_queue()
## ROM address of a 0-terminated string (-1: use [member text]).
@export var string_address := -1:
	set(v):
		string_address = v
		_queue()
## Text not from the ROM (numbers, names built by code); ASCII.
@export var text := "":
	set(v):
		text = v
		_queue()
## Cell (column, row) the text starts at, as `draw_text`'s D1/D2.
@export var cell := Vector2i.ZERO:
	set(v):
		cell = v
		_queue()
## When > 0: centre in this many columns (x = (columns - width) / 2), as the
## credit pages do with 40.
@export var center_in := 0:
	set(v):
		center_in = v
		_queue()
## Palette line of the cells (draw_text's D3).
@export_range(0, 3) var line := 0:
	set(v):
		line = v
		_queue()
@export var palette: RomPalette:
	set(v):
		if palette and palette.changed.is_connected(_update_material):
			palette.changed.disconnect(_update_material)
		palette = v
		if palette:
			palette.changed.connect(_update_material)
		_update_material()

const GENERATED := ["texture", "material", "offset", "centered"]

## Width of the text in cells (after a build).
var width := 0
var _queued := false


func _ready() -> void:
	rebuild()


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


## Font record address.
func font_address() -> int:
	var e := MwRom.entry(font)
	return int(e["address"]) if not e.is_empty() else font.hex_to_int()


## The string's bytes.
func bytes() -> PackedByteArray:
	if string_address >= 0 and MwRom.available():
		return MwGfx.rom_string(MwRom.data(), string_address)
	return text.to_ascii_buffer()


## The cell the text starts at after centring.
@warning_ignore("integer_division")
func start_cell() -> Vector2i:
	if center_in > 0:
		return Vector2i((center_in - width) / 2, cell.y)
	return cell


func rebuild() -> void:
	texture = null
	width = 0
	if font == "" or not MwRom.available():
		return
	var rom := MwRom.data()
	var f := font_address()
	var b := bytes()
	width = MwGfx.text_width(rom, f, b)
	var img := MwGfx.text_image(rom, f, b, line)
	centered = false
	var at := start_cell()
	offset = Vector2(8 * at.x, 8 * (at.y + int(img["top"])))
	if int(img["h"]) > 0:
		texture = ImageTexture.create_from_image(
				Image.create_from_data(img["w"], img["h"], false, Image.FORMAT_R8, img["px"]))
	_update_material()


func _update_material() -> void:
	material = palette.material() if palette and palette.texture() else null
