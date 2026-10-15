extends "res://test/rom/rom_test_base.gd"
## Plan 45 (L5): the ROM's SHA-1 is that of the bytes the game uses - the
## bytes RomArchive.describe hashed are the ones kept, and an imported
## archive (its SHA-1 the import's) hashes the bytes it reads once - so a
## file changed after the check is never taken for the ROM; and the ROM is
## only available at its size.

const COPY := "user://test/rom_hash.gen"


func after_each() -> void:
	if FileAccess.file_exists(COPY):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY))
	MwRom.use(null)


static func _put(bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(COPY.get_base_dir()))
	var f := FileAccess.open(COPY, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


static func _zeros(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	return b


func test_the_bytes_described_are_the_bytes_hashed() -> void:
	if not need_rom():
		return
	_put(rom.slice(0, RomArchive.MLH_SIZE))
	var archive := RomArchive.describe(COPY)
	assert_true(archive.is_mlh())
	_put(_zeros(RomArchive.MLH_SIZE))                      # the file changed after the check
	assert_eq(archive.bytes(), rom.slice(0, RomArchive.MLH_SIZE), "the bytes that were hashed, not the file's now")


func test_an_import_older_than_its_file_is_not_the_rom() -> void:
	_put(_zeros(RomArchive.MLH_SIZE))
	var imported := RomArchive.new()                     # as the import left it: metadata from another day
	imported.source_path = COPY
	imported.size = RomArchive.MLH_SIZE
	imported.sha1 = RomArchive.MLH_SHA1
	assert_eq(imported.bytes().size(), RomArchive.MLH_SIZE)
	assert_false(imported.is_mlh(), "its SHA-1 is now the bytes'")
	MwRom.use(imported)
	assert_false(MwRom.available())


func test_the_rom_is_available_at_its_size_only() -> void:
	_put(PackedByteArray([1, 2, 3]))
	var short := RomArchive.new()
	short.source_path = COPY
	short.sha1 = RomArchive.MLH_SHA1
	MwRom.use(short)
	assert_false(MwRom.available(), "three bytes: not the ROM, whatever the metadata says")


func test_a_file_of_another_size_is_hashed_in_pieces() -> void:
	var bytes := PackedByteArray()
	for i in 251:
		bytes.append(i * 7 & 0xFF)
	while bytes.size() < RomArchive.HASH_CHUNK * 2:
		bytes.append_array(bytes)
	bytes.resize(RomArchive.HASH_CHUNK * 2 + 5)
	_put(bytes)
	var archive := RomArchive.describe(COPY)
	assert_eq(archive.size, bytes.size())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(bytes)
	assert_eq(archive.sha1, ctx.finish().hex_encode(), "the whole file's SHA-1")
