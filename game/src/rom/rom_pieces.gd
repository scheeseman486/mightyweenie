class_name RomPieces
extends Sprite2D
## A sprite made of ROM pieces placed by code (the original's `$156C6`
## calls outside frames: big-font letters, single glyphs, badges): pieces
## are dictionaries as MwGfx.piece returns, x/y relative to this node's
## origin. Palette-swapped like the other ROM sprites; nothing is saved.

@export var palette: RomPalette:
	set(v):
		palette = v
		material = palette.material() if palette and palette.texture() else null
		if palette and not palette.changed.is_connected(_on_palette):
			palette.changed.connect(_on_palette)

const GENERATED := ["texture", "material", "offset", "centered"]


func _validate_property(property: Dictionary) -> void:
	if property.name in GENERATED:
		property.usage &= ~PROPERTY_USAGE_STORAGE


func _on_palette() -> void:
	material = palette.material() if palette and palette.texture() else null


## Shows [param pieces] (empty: nothing).
func set_pieces(pieces: Array) -> void:
	if pieces.is_empty() or not MwRom.available():
		texture = null
		return
	var img := MwGfx.frame_image(MwRom.data(), pieces)
	if int(img["w"]) <= 0 or int(img["h"]) <= 0:
		texture = null
		return
	texture = ImageTexture.create_from_image(Image.create_from_data(img["w"], img["h"], false, Image.FORMAT_R8, img["px"]))
	centered = false
	offset = Vector2(-int(img["ox"]), -int(img["oy"]))
