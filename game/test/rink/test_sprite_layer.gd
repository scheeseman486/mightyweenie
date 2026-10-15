extends "res://test/rom/rom_test_base.gd"
## MwSpriteLayer's pieces and what hides them (plan 42, second round: whether
## a piece hides worked out once a list - MwSpriteLayer.mine_and_covers - is
## the pair-by-pair rule it replaced).


## The rule pair by pair: a piece of [param entries] in [param layer] loses pixels to an
## earlier (front) piece that overlaps it and has operator pixels
## or, on the high layer, is low.
static func _pairwise(layer: MwSpriteLayer, entries: Array) -> Array:
	var mine := []
	var covers := []
	for index in entries.size():
		var piece: Array = entries[index]
		var is_high := (int(piece[3]) & 0x80) != 0
		if is_high != layer.high:
			continue
		mine.append(piece)
		var cover := []
		for j in index:
			var f: Array = entries[j]
			if ((is_high and (int(f[3]) & 0x80) == 0) or layer._has_operators(f)) and MwSpriteLayer._overlap(f, piece):
				cover.append(f)
		covers.append(cover)
	return [mine, covers]


func test_what_hides_a_piece_is_the_pairwise_rule() -> void:
	if not need_rom():
		return
	var rig := preload("res://test/support/rink_rig.gd").new()
	var s: MwRinkState = rig.make(rom, 3, 3, 7, 0, false, null, true)
	MwRinkMatch.boot_icons(rig.sim)
	rig.phases.enter(5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var low := MwSpriteLayer.new()
	var high := MwSpriteLayer.new()
	high.high = true
	add_child_autofree(low)
	add_child_autofree(high)
	var lists := 0
	var covered := {false: 0, true: 0}      # pieces with something in front hiding pixels, by layer
	var by_ops := 0                          # front pieces hiding by their operator pixels
	for i in 60:
		rig.run(5)
		var list: Array = rig.update.drawer.build(s)
		# some pieces moved onto each other, given the priority bit or line 3 (the
		# operator colours' line) at random
		var entries := []
		for piece: Array in list:
			var c := piece.duplicate()
			if rng.randf() < 0.3:
				c[0] = int(c[0]) + rng.randi_range(-24, 24)
				c[1] = int(c[1]) + rng.randi_range(-24, 24)
			if rng.randf() < 0.3:
				c[3] = int(c[3]) ^ 0x80
			if rng.randf() < 0.3:
				c[3] = (int(c[3]) & ~0x60) | 0x60
			entries.append(c)
		for layer: MwSpriteLayer in [low, high]:
			var got := layer.mine_and_covers(entries)
			var want := _pairwise(layer, entries)
			if str(got) != str(want):
				assert_eq(str(got), str(want), "list %d, %s layer" % [i, "high" if layer.high else "low"])
				return
			for cv: Array in got[1]:
				if not cv.is_empty():
					covered[layer.high] += 1
				for f: Array in cv:
					if layer._has_operators(f):
						by_ops += 1
		lists += 1
	assert_eq(lists, 60)
	assert_gt(covered[false], 0, "low pieces hidden in part")
	assert_gt(covered[true], 0, "high pieces hidden in part")
	assert_gt(by_ops, 0, "by operator pixels")
