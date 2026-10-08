extends "res://test/rom/rom_test_base.gd"
## The crowd's figures (plan 15, docs/rink3d.md, Crowd): MwCrowd cuts them
## from the ROM rule for rule as tools/crowd/crowd_build.py does (it writes a
## checksum of every template into crowd.json), and crowd.json holds numbers
## only (positions, runs, polygons; no pixels).

var crowd: MwCrowd


func before_all() -> void:
	super.before_all()
	if not rom.is_empty():
		crowd = MwCrowd.new()
		crowd.build(rom)


func test_templates_match_the_tool() -> void:
	if not need_rom():
		return
	var figs: Array = crowd.data.get("figures", [])
	assert_gt(figs.size(), 10, "figures")
	for f: Dictionary in figs:
		var t: Dictionary = crowd.template(f["name"])
		assert_false(t.is_empty(), f["name"])
		assert_eq(MwCrowd.template_hash(t["t"]), int(f["template_hash"]), f["name"])


func test_crowd_area_is_the_left_half() -> void:
	if not need_rom():
		return
	assert_eq(crowd.crowd.size(), MwCrowd.HALF * crowd.pic_h)
	var on := 0
	for v in crowd.crowd:
		if v >= MwCrowd.LINE:
			on += 1
	assert_eq(on, int(crowd.data["inventory"]["crowd"]), "crowd pixels as the tool counts them")


## No list of more than 8 numbers: pixel rows would be longer.
func _short_lists(v: Variant, path: String) -> void:
	if v is Array:
		var numbers := 0
		for e in v:
			if e is float or e is int:
				numbers += 1
			_short_lists(e, path)
		assert_true(numbers <= 8, "%s: a list of %d numbers" % [path, numbers])
	elif v is Dictionary:
		for k in v:
			_short_lists(v[k], path + "." + str(k))


func test_numbers_only() -> void:
	_short_lists(MwCrowd.load_data(), "crowd.json")


func test_paint_grows_the_canvas_round_the_figure() -> void:
	# the owner's paint (crowd_build.py paint): runs [x, y, length, colour]
	# from the template's top-left; outside it the canvas grows, as much on
	# both sides (figures stand on their bottom centre), and up
	var t := PackedInt32Array([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	var out := MwCrowd.apply_paint(t, 4, 3, [[-1, 0, 1, 31], [2, -1, 2, 28], [0, 2, 1, MwCrowd.EMPTY]])
	assert_eq([out["w"], out["h"], out["ox"], out["oy"]], [6, 4, 1, 1])
	var o: PackedInt32Array = out["t"]
	assert_eq(o[1 * 6 + 0], 31, "left of it")
	assert_eq([o[0 * 6 + 3], o[0 * 6 + 4]], [28, 28], "above it")
	assert_eq(o[3 * 6 + 1], MwCrowd.EMPTY, "an erase")
	assert_eq(o[0], MwCrowd.EMPTY, "the rest of the new canvas")
	assert_eq(o[1 * 6 + 1], 1, "the template, moved by the growth")
	assert_eq(MwCrowd.paint_canvas(4, 3, []), [0, 0, 4, 3], "no paint, no growth")


func test_every_character_view_is_a_figure() -> void:
	# a character shows both views once both exist (the owner's paint makes
	# the missing ones); until then it borrows a stand-in's
	if not need_rom():
		return
	for c: Dictionary in crowd.data.get("characters", []):
		for side in ["front", "back"]:
			if c.get(side) is String:
				assert_false(crowd.template(c[side]).is_empty(), "%s: %s" % [c["name"], side])
		if not MwStands.complete(c) and c.get("back") != null:
			assert_true(c.has("standin"), "%s: a stand-in until its view is drawn" % c["name"])
