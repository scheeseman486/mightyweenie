extends "res://test/rom/rom_test_base.gd"
## The GDScript decoders and palette builders reproduce the Python reference
## decoders exactly: same SHA-1 for every catalogue entry and builder case
## (compare/fixtures/gfx_hashes.json - hashes only, no ROM content).

var _fixture: Dictionary


func before_all() -> void:
	super.before_all()
	_fixture = JSON.parse_string(FileAccess.get_file_as_string(repo_path("compare/fixtures/gfx_hashes.json")))


func test_fixture_is_for_this_rom() -> void:
	assert_eq(_fixture["format"], "mw-gfx-hashes/1")
	assert_eq(_fixture["rom_sha1"], MwRom.catalogue()["rom_sha1"])


func test_catalogue_entries_decode_like_python() -> void:
	if not need_rom():
		return
	var got := MwGfx.catalogue_hashes(rom, MwRom.catalogue())
	var want: Dictionary = _fixture["entries"]
	assert_eq(got.size(), want.size(), "same entries")
	var bad := []
	for k in want:
		if got.get(k, "") != want[k]:
			bad.append(k)
	assert_eq(bad, [], "entries decoding differently")


func test_palette_builders_like_python() -> void:
	if not need_rom():
		return
	var want: Dictionary = _fixture["palette_builders"]
	var bad := []
	for c in MwPalettes.builder_cases():
		var words := MwPalettes.run_case(rom, c[0], c[1])
		var data := PackedByteArray()
		for w in words:
			data.append_array(PackedByteArray([(w >> 8) & 0xFF, w & 0xFF]))
		var key: String = "/".join([c[0]] + c[1].map(func(x): return str(x)))
		if want.get(key, "") != MwGfx.sha1(data):
			bad.append(key)
	assert_eq(bad, [])
	assert_eq(MwPalettes.builder_cases().size(), want.size())


func test_formats_on_synthetic_data() -> void:
	var t := PackedByteArray([0x12, 0x34])
	t.resize(32)
	assert_eq(MwGfx.tile_indices(t, 0).slice(0, 4), PackedByteArray([1, 2, 3, 4]), "left pixel in the high nibble")
	assert_eq(MwGfx.color_rgb8(0x000E), PackedByteArray([255, 0, 0]), "red in the low nibble")
	assert_eq(MwGfx.color_rgb8(0x0E00), PackedByteArray([0, 0, 255]))
	var c := MwGfx.cell(0xF9FF)
	assert_eq([c.priority, c.line, c.vflip, c.hflip, c.tile], [true, 3, true, true, 0x1FF])
	var p := MwGfx.piece(PackedByteArray([0xF8, 5, (1 << 2) | 2, 0x08 | 0x10 | (2 << 5), 0x12, 0x34]), 0)
	assert_eq([p.x, p.y, p.w, p.h, p.tile], [-8, 5, 2, 3, 0x1234])
	var f: Dictionary = MwGfx.flip_pieces([{"x": -8, "y": 4, "w": 2, "h": 1, "attr": 0, "tile": 0x800}], 1)[0]
	assert_eq([f.x, f.y, f.attr & 0x08], [-8, 4, 0x08])
