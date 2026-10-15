extends "res://test/rom/rom_test_base.gd"
## Plan 40 (D4): the team and player records' layouts named once
## ([MwTeams], [MwPlayerRecord]) - the team description's Player page reads
## the bytes it read before, the custom player round-trips through them.


func test_the_player_page_s_nibbles() -> void:
	# the team description's columns as `$C278` reads them: [byte, high nibble]
	var want := [
		[[0x9, false], [0xA, false], [0x8, true], [0xC, true], [0xC, false], [0xE, true]],
		[[0xB, true], [0xB, false], [0xA, true], [0xD, false], [0x9, true], [0xF, true]]]
	for col in 2:
		for i in 6:
			assert_eq(MwPlayerRecord.NIBBLES[MwPlayerRecord.COLUMNS[col][i]], want[col][i], "%d %d" % [col, i])
	var flat := []
	for col in 2:
		flat.append_array(MwPlayerRecord.COLUMNS[col].slice(0, 5))
	assert_eq(flat, MwPlayerRecord.RATINGS, "the ten ratings, column by column")


func test_a_record_s_ratings_read_back() -> void:
	if not need_rom():
		return
	var rec := MwTeams.player(rom, 4, 2)
	var player := MwCustomPlayer.from_record(rom, rec)
	var b := player.record_bytes(0)
	for r in MwPlayerRecord.RATINGS:
		assert_eq(MwPlayerRecord.nibble(b, 0, r), MwPlayerRecord.nibble(rom, rec, r), r)
	assert_eq(MwPlayerRecord.enforcer(b, 0), MwPlayerRecord.enforcer(rom, rec))


func test_the_team_record_s_fields() -> void:
	if not need_rom():
		return
	for t in MwTeams.COUNT:
		var rec := MwTeams.record(t)
		assert_eq(MwTeams.name(rom, t), MwGfx.u32(rom, rec + MwTeams.NAME))
		assert_eq(MwTeams.name_text(rom, t), MwGfx.rom_string(rom, MwGfx.u32(rom, rec + 4)).get_string_from_ascii())
		assert_eq(MwTeams.skulls(rom, t), rom[rec + 0x0B])
		assert_eq(MwTeams.player(rom, t, 7), MwGfx.u32(rom, rec + 0x18 + 0x18 + 4))


## Plan 40 (D5): a face and its quote set from one place - a star's entry,
## else his species'; a listed coach's entry, else the default and ROM 4's
## word.
func test_faces() -> void:
	if not need_rom():
		return
	var star := MwGfx.u32(rom, MwPortrait.STARS)               # the first star's record
	assert_eq(MwPortrait.player_face(rom, star),
			PackedInt32Array([MwGfx.u32(rom, MwPortrait.STARS + 4), MwGfx.u16(rom, MwPortrait.STARS + 8)]))
	var plain := 0
	for slot in 24:
		var r := MwTeams.player(rom, 0, slot)
		if r != 0 and MwPortrait.star_entry(rom, r) == 0:
			plain = r
			break
	var k := MwPortrait.BY_SPECIES + 6 * (rom[plain + 7] & 0x0F)
	assert_eq(MwPortrait.player_face(rom, plain), PackedInt32Array([MwGfx.u32(rom, k), MwGfx.u16(rom, k + 4)]))
	assert_eq(MwPortrait.player_face(rom, 0), PackedInt32Array([MwPortrait.DEFAULT, 0]), "no record")
	var coach := MwGfx.u32(rom, MwPortrait.COACHES)
	assert_eq(MwPortrait.coach_face(rom, coach),
			PackedInt32Array([MwGfx.u32(rom, MwPortrait.COACHES + 4), MwGfx.u16(rom, MwPortrait.COACHES + 8)]))
	assert_eq(MwPortrait.coach_face(rom, 0x123456), PackedInt32Array([MwPortrait.COACH_DEFAULT, MwGfx.u16(rom, 4)]),
			"a coach not listed")
