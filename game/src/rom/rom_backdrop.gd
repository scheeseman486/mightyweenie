@tool
class_name RomBackdrop
extends ColorRect
## The VDP backdrop: a full-screen rectangle in the palette's colour 0 (what
## shows through transparent pixels, e.g. the rink's ice). The colour is
## taken from the ROM when the scene loads and never saved.

@export var palette: RomPalette:
	set(v):
		if palette and palette.changed.is_connected(_update):
			palette.changed.disconnect(_update)
		palette = v
		if palette:
			palette.changed.connect(_update)
		_update()


func _ready() -> void:
	_update()


func _validate_property(property: Dictionary) -> void:
	if property.name == "color":
		property.usage &= ~PROPERTY_USAGE_STORAGE


func _update() -> void:
	color = palette.backdrop() if palette else Color.BLACK
