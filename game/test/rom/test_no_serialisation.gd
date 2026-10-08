extends GutTest
## No ROM-derived data in the project's committed resources: scans every
## .tscn/.tres under res:// for embedded images, textures, tile cells, sprite
## frames or byte arrays (docs/architecture.md, Assets).

const FORBIDDEN := ["tile_map_data", "PackedByteArray(", "Image\"", "type=\"Image\"",
		"ImageTexture", "SpriteFrames", "[sub_resource type=\"TileSet\"", "TileSetAtlasSource"]
const SKIP := ["res://addons", "res://.godot", "res://reports"]


func _files(dir: String, out: Array) -> void:
	if dir in SKIP:
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tscn") or f.ends_with(".tres"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_files(dir.path_join(sub), out)


func test_no_embedded_rom_data() -> void:
	var files := []
	_files("res://", files)
	var bad := []
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for f in FORBIDDEN:
			if text.contains(f):
				bad.append("%s: %s" % [path, f])
	assert_eq(bad, [], "resources with embedded data")
	gut.p("scanned %d resource files" % files.size())
