extends "res://test/rom/rom_test_base.gd"
## Plan 42 (speed): MwTrig.angle_of answers from a table of the original's
## `$14290` walk worked out once per ROM (MwTrig._table, by halving each
## step of the walk's answer) - here the walk itself for every ratio, and
## angle_of against the walk for directions all round.


func test_the_table_is_the_walk_for_every_ratio() -> void:
	if not need_rom():
		return
	MwTrig._table(rom)
	var off := []
	for q in MwTrig.RATIOS:
		if MwTrig._atan[q] != MwTrig._search(rom, q):
			off.append(q)
			if off.size() > 5:
				break
	assert_eq(off, [], "every ratio's angle the walk's")


func test_angles_all_round_are_the_walks() -> void:
	if not need_rom():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 20000:
		var dx := rng.randi_range(-0x7FFF, 0x7FFF) >> rng.randi_range(0, 14)
		var dy := rng.randi_range(-0x7FFF, 0x7FFF) >> rng.randi_range(0, 14)
		if dx == 0 and dy == 0:
			continue
		var want := _walked(dx, dy)
		var got := MwTrig.angle_of(rom, dx, dy)
		if got != want:
			assert_eq(got, want, "(%d, %d)" % [dx, dy])
			return
	assert_true(true)


## `$14290` with the walk, as MwTrig.angle_of was before the table.
func _walked(dx: int, dy: int) -> int:
	var octant := 0
	if dx < 0:
		dx = -dx
		octant += 4
	if dy < 0:
		dy = -dy
		octant += 8
	var a := 0
	if dx == dy:
		a = 0x20
	else:
		if dx < dy:
			var t := dx
			dx = dy
			dy = t
			octant += 2
		var q := ((dy << 16) >> 1) / dx
		a = 0x20 if q >= 0x7FFE else MwTrig._search(rom, q)
	match octant:
		2: a = 0x40 - a
		4: a = 0x80 - a
		6: a = 0x40 + a
		8: a = 0x100 - a
		10: a = 0xC0 + a
		12: a = 0x80 + a
		14: a = 0xC0 - a
	return a & 0xFF
