extends "res://test/rom/rom_test_base.gd"
## Plan 45 (M2, L3, L4): the player's files are committed only once they
## read back whole (a full disk refuses buffered writes at the close and
## says nothing), a write that fails says so to its caller, a secret's
## ".part" is its owner's alone before the secret goes in, and a ".part" a
## crash left is taken up (or cleared) by the next read.

const DIR := "user://test/checked_writes"

var _was := {}


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_was = {"settings": MwSettings.path, "rejoin": MwNetRejoin.path, "identity": MwNetIdentity.dir,
			"teams": MwCustomTeams.dir}


func after_each() -> void:
	MwSettings.path = _was["settings"]
	MwNetRejoin.path = _was["rejoin"]
	MwNetIdentity.dir = _was["identity"]
	MwCustomTeams.dir = _was["teams"]
	MwCustomTeams.clear()
	_remove_tree(DIR)


static func _remove_tree(path: String) -> void:
	var at := ProjectSettings.globalize_path(path)
	for d in DirAccess.get_directories_at(at):
		_remove_tree(path.path_join(d))
	for f in DirAccess.get_files_at(at):
		DirAccess.remove_absolute(at.path_join(f))
	DirAccess.remove_absolute(at)


static func _put(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func test_a_part_that_doesnt_read_back_whole_is_never_committed() -> void:
	var path := DIR.path_join("file.cfg")
	assert_true(MwUserFile.write_text(path, "old\n"))
	var meant := "new text\n".repeat(300).to_utf8_buffer()
	_put(path + ".part", meant.slice(0, 2048))           # what a full disk leaves: the first blocks
	assert_false(MwUserFile.commit_checked(path + ".part", path, meant), "refused")
	assert_eq(FileAccess.get_file_as_string(path), "old\n", "the old file kept")
	assert_false(FileAccess.file_exists(path + ".part"), "the short .part gone")
	assert_true(MwUserFile.write_atomic(path, meant), "a write that reads back whole")
	assert_eq(FileAccess.get_file_as_bytes(path), meant)
	assert_false(FileAccess.file_exists(path + ".part"))


func test_a_write_that_cant_be_made_tells_its_caller() -> void:
	var blocker := DIR.path_join("blocker")
	_put(blocker, "a file where a folder should be".to_utf8_buffer())
	assert_false(MwUserFile.write_text(blocker.path_join("file.cfg"), "x"))
	MwSettings.path = blocker.path_join("settings.cfg")
	assert_false(MwSettings.save(), "the settings")
	if need_rom():
		MwCustomTeams.dir = blocker
		var team := MwCustomTeam.from_original(MwRom.archive().bytes(), 2)
		team.id = "team"
		assert_false(MwCustomTeams.write(team), "a custom team")
	for e in get_errors():
		e.handled = true     # (the engine may report the folder it couldn't make)


func test_a_secrets_part_is_its_owners_before_the_secret_goes_in() -> void:
	if OS.get_name() != "Linux":
		pending("Unix permissions")
		return
	var net := DIR.path_join("net")
	MwNetRejoin.path = net.path_join("rejoin.cfg")
	# a folder in the file's place: the rename fails and leaves the written .part to be looked at
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MwNetRejoin.path))
	assert_false(MwNetRejoin.save("host.example", 42032, 7, MwNetProtocol.random_bytes(32)), "not put in place")
	var part := MwNetRejoin.path + ".part"
	assert_true(FileAccess.file_exists(part))
	assert_eq(FileAccess.get_unix_permissions(part) & 63, 0, "the rejoin key's .part: its owner's alone")
	assert_eq(FileAccess.get_unix_permissions(ProjectSettings.globalize_path(net)) & 63, 0,
			"and its folder: nobody else opens anything in it")
	MwNetIdentity.dir = DIR.path_join("identity")
	var key_path := MwNetIdentity.dir.path_join(MwNetIdentity.KEY_FILE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(key_path))
	assert_null(MwNetIdentity.load_or_create(), "the host's key: not put in place")
	assert_eq(FileAccess.get_unix_permissions(key_path + ".part") & 63, 0, "the host key's .part: its owner's alone")
	assert_eq(FileAccess.get_unix_permissions(ProjectSettings.globalize_path(MwNetIdentity.dir)) & 63, 0)
	assert_true("PRIVATE KEY" in FileAccess.get_file_as_string(key_path + ".part"), "CryptoKey.save's text")


func test_a_part_a_crash_left_is_taken_up_or_cleared() -> void:
	var path := DIR.path_join("settings.cfg")
	var cfg := ConfigFile.new()
	cfg.set_value("game", "camera", "2D")
	_put(path + ".part", cfg.encode_to_text().to_utf8_buffer())     # renamed away, never back (no file)
	var back := MwUserFile.read_config(path)
	assert_not_null(back, "the whole .part taken up")
	if back != null:
		assert_eq(back.get_value("game", "camera"), "2D")
	assert_true(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + ".part"))
	_put(path + ".part", "[game]\ncamera=\"3D\"\n".to_utf8_buffer())   # a write that never got put in place
	back = MwUserFile.read_config(path)
	assert_eq(back.get_value("game", "camera") if back != null else null, "2D", "the whole file kept")
	assert_false(FileAccess.file_exists(path + ".part"), "the .part cleared")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_put(path + ".part", "[game]\ncamera=Object(RefCounted)\n".to_utf8_buffer())
	assert_null(MwUserFile.read_config(path), "a .part that isn't plain settings: not taken")
	assert_false(FileAccess.file_exists(path + ".part"))
	assert_false(FileAccess.file_exists(path))


func test_a_custom_teams_part_is_taken_up_by_the_bank() -> void:
	if not need_rom():
		return
	MwCustomTeams.dir = DIR.path_join("teams")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MwCustomTeams.dir))
	var team := MwCustomTeam.from_original(MwRom.archive().bytes(), 2)
	team.city = "Crashville"
	var file := MwCustomTeams.dir.path_join("crashville.json")
	_put(file + ".part", JSON.stringify(team.to_dict()).to_utf8_buffer())
	_put(MwCustomTeams.dir.path_join("broken.json.part"), "{\"city\": ".to_utf8_buffer())
	MwCustomTeams.load_bank()
	assert_eq(MwCustomTeams.count(), 1, "the whole one taken up")
	assert_true(FileAccess.file_exists(file))
	assert_false(FileAccess.file_exists(file + ".part"))
	assert_false(FileAccess.file_exists(MwCustomTeams.dir.path_join("broken.json.part")), "the broken one cleared")
	assert_false(FileAccess.file_exists(MwCustomTeams.dir.path_join("broken.json")))
