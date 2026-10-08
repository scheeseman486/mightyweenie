extends GutTest
## Exported builds carry no ROM: MwRom.find_rom() looks for the player's file
## (here: files put in the user data folder, one of the places it looks).

const NOT_MLH := "user://test_not_mlh.bin"
const COPY := "user://test_rom_copy.gen"


func after_each() -> void:
	for p in [NOT_MLH, COPY]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_a_file_of_the_right_size_but_wrong_contents_is_skipped() -> void:
	var f := FileAccess.open(NOT_MLH, FileAccess.WRITE)
	var zeros := PackedByteArray()
	zeros.resize(RomArchive.MLH_SIZE)
	f.store_buffer(zeros)
	f.close()
	var path := ProjectSettings.globalize_path(NOT_MLH)
	assert_has(MwRom.rom_candidates(), path, "the user data folder is searched")
	var found := MwRom.find_rom()
	assert_true(found == null or found.source_path != path)


func test_the_rom_is_found_by_its_contents() -> void:
	if not MwRom.available():
		pending("no ROM")
		return
	var f := FileAccess.open(COPY, FileAccess.WRITE)
	f.store_buffer(MwRom.data())
	f.close()
	var found := MwRom.find_rom()
	assert_not_null(found)
	assert_true(found.is_mlh())
	assert_eq(found.bytes(), MwRom.data())
