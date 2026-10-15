extends GutTest
## Exported builds carry no ROM: MwRom.find_rom() looks for the player's file
## (here: files put in the user data folder, one of the places it looks).

const NOT_MLH := "user://test_not_mlh.bin"
const COPY := "user://test_rom_copy.gen"
## Where the tests' chosen ROM is copied (the game: the user data folder itself).
const TAKEN := "user://test_rom_taken"
const RomService := preload("res://src/rom/rom_service.gd")


func after_each() -> void:
	for p in [NOT_MLH, COPY, TAKEN.path_join(RomService.COPY_NAME)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TAKEN))


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


## Run from an AppImage (owner's request, 2026-10-15): the game's folder is the
## AppImage file's (its runtime's APPIMAGE variable), not the executable's
## read-only mount - a ROM put next to the AppImage is found there; outside
## one, the executable's.
func test_an_appimage_s_folder_is_the_game_s() -> void:
	var was := OS.get_environment("APPIMAGE")
	var folder := ProjectSettings.globalize_path(TAKEN)
	DirAccess.make_dir_recursive_absolute(folder)
	var beside := folder.path_join("beside.gen")
	var f := FileAccess.open(beside, FileAccess.WRITE)
	f.store_8(0)
	f.close()
	OS.set_environment("APPIMAGE", folder.path_join("mightyweenie-v0.2-x86_64.AppImage"))
	assert_eq(MwRom.game_dir(), folder, "the AppImage's folder")
	assert_has(MwRom.rom_candidates(), beside, "a ROM next to the AppImage is looked at")
	OS.unset_environment("APPIMAGE")
	assert_eq(MwRom.game_dir(), OS.get_executable_path().get_base_dir(), "else the executable's")
	if was != "":
		OS.set_environment("APPIMAGE", was)
	DirAccess.remove_absolute(beside)


## No ROM where an exported build looks: the file the player chooses in the
## dialog (owner, 2026-10-15) is checked - its size, then its SHA-1 - and
## copied into the user data folder, where the next start finds it; a file
## that isn't the ROM is refused with the reason and nothing is copied.
func test_a_chosen_rom_is_copied_into_the_user_folder() -> void:
	if not MwRom.available():
		pending("no ROM")
		return
	var f := FileAccess.open(COPY, FileAccess.WRITE)
	f.store_buffer(MwRom.archive().bytes())
	f.close()
	var folder := ProjectSettings.globalize_path(TAKEN)
	assert_eq(RomService.take_rom(ProjectSettings.globalize_path(COPY), folder), "")
	var copied := folder.path_join(RomService.COPY_NAME)
	assert_true(RomArchive.describe(copied).is_mlh(), "the copy is the ROM")
	assert_eq(RomService.take_rom(copied, folder), "", "the copy itself chosen: nothing more to copy")
	assert_eq(RomService.COPY_NAME.get_extension(), "gen", "an extension the start looks for (MwRom.ROM_EXTENSIONS)")
	assert_has(MwRom.ROM_EXTENSIONS, RomService.COPY_NAME.get_extension())


func test_a_file_that_is_not_the_rom_is_refused() -> void:
	var folder := ProjectSettings.globalize_path(TAKEN)
	var f := FileAccess.open(NOT_MLH, FileAccess.WRITE)
	var zeros := PackedByteArray()
	zeros.resize(RomArchive.MLH_SIZE)
	f.store_buffer(zeros)
	f.close()
	var why := RomService.take_rom(ProjectSettings.globalize_path(NOT_MLH), folder)
	assert_string_contains(why, "SHA-1", "the ROM's size, not its contents")
	f = FileAccess.open(NOT_MLH, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3]))
	f.close()
	assert_string_contains(RomService.take_rom(ProjectSettings.globalize_path(NOT_MLH), folder), "3 bytes")
	assert_string_contains(RomService.take_rom(folder.path_join("nothing_here.gen"), folder), "can't be read")
	assert_false(FileAccess.file_exists(folder.path_join(RomService.COPY_NAME)), "nothing copied")


func test_the_dialog_asks_for_a_file_of_the_file_system() -> void:
	var start := OS.get_user_data_dir()
	var d := RomService.rom_dialog(start)
	assert_true(d.use_native_dialog, "the system's own dialog where it has one")
	assert_true(d.force_native, "else the engine's in a window of its own (not in the 320 x 224 picture)")
	assert_eq(d.file_mode, FileDialog.FILE_MODE_OPEN_FILE)
	assert_eq(d.access, FileDialog.ACCESS_FILESYSTEM)
	assert_eq(d.process_mode, Node.PROCESS_MODE_ALWAYS, "it answers with the game paused under it")
	assert_eq(d.filters, PackedStringArray(RomService.FILTERS))
	assert_eq(d.current_dir.simplify_path(), start.simplify_path(), "where it is told (the executable's folder)")
	d.free()
