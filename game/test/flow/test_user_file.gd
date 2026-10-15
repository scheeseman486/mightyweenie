extends GutTest
## Plan 40 (S6): the player's files are written whole - a ".part" moved
## over the file - with the same bytes the engine's own writers made.

const DIR := "user://test/user_file"


func after_each() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))


func test_written_whole_and_replaced() -> void:
	var text := DIR.path_join("a.txt")
	assert_true(MwUserFile.write_text(text, "one\n"))
	assert_true(MwUserFile.write_text(text, "two\n"), "over the old one")
	assert_eq(FileAccess.get_file_as_string(text), "two\n")
	assert_false(FileAccess.file_exists(text + ".part"), "no .part left")


func test_a_config_as_the_engine_writes_it() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "version", 3)
	cfg.set_value("save", "humans", {"a": [1, 2], "b": []})
	cfg.set_value("net", "address", "host:1")
	var mine := DIR.path_join("mine.cfg")
	var engine := DIR.path_join("engine.cfg")
	assert_true(MwUserFile.write_config(cfg, mine))
	cfg.save(engine)
	assert_eq(FileAccess.get_file_as_bytes(mine), FileAccess.get_file_as_bytes(engine))
	var back := ConfigFile.new()
	assert_eq(back.load(mine), OK)
	assert_eq(back.get_value("save", "humans"), {"a": [1, 2], "b": []})


func test_packed_vars_and_their_bounds() -> void:
	var v := {"a": [1, 2, 3], "b": "text".repeat(50)}
	for mode in [FileAccess.COMPRESSION_DEFLATE, FileAccess.COMPRESSION_ZSTD]:
		var b := MwNetBytes.pack_var(v, mode)
		assert_eq(MwNetBytes.packed_raw_size(b), var_to_bytes(v).size())
		assert_eq(MwNetBytes.unpack_var(b, 1 << 20, mode), v)
		assert_null(MwNetBytes.unpack_var(b, 16, mode), "over the bound: nothing")
