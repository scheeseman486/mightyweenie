extends "res://test/rom/rom_test_base.gd"
## RomArchive: metadata only, bytes read from the file and never saved.


func test_describe_reads_metadata() -> void:
	if not need_rom():
		return
	var a := RomArchive.describe(MwRom.ROM_PATH)
	assert_eq(a.size, RomArchive.MLH_SIZE)
	assert_true(a.is_mlh(), "SHA-1 of the project ROM")
	assert_eq(a.bytes().size(), RomArchive.MLH_SIZE)


func test_imported_archive_is_metadata_only() -> void:
	if not need_rom():
		return
	if not ResourceLoader.exists(MwRom.ROM_PATH, "Resource"):
		pending("ROM not imported yet (open the project in the editor once)")
		return
	var a := load(MwRom.ROM_PATH) as RomArchive
	assert_not_null(a, "imported as RomArchive")
	assert_eq(a.sha1, RomArchive.MLH_SHA1)
	assert_eq(a.source_path, MwRom.ROM_PATH)


func test_saved_archive_holds_no_bytes() -> void:
	if not need_rom():
		return
	var a := RomArchive.describe(MwRom.ROM_PATH)
	a.bytes()                                   # loaded in memory...
	var path := "user://test_rom_archive.tres"
	assert_eq(ResourceSaver.save(a, path), OK)
	var text := FileAccess.get_file_as_string(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_string_contains(text, RomArchive.MLH_SHA1)
	assert_false(text.contains("PackedByteArray"), "...but not saved")
	assert_lt(text.length(), 1000)


func test_missing_file() -> void:
	var a := RomArchive.describe("res://rom/does_not_exist.gen")
	assert_eq(a.size, 0)
	assert_false(a.is_mlh())
	assert_true(a.bytes().is_empty())
