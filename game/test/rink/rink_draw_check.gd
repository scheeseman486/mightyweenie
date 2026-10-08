class_name MwRinkDrawCheck
extends RefCounted
## Compares our draw pass with a pass recorded from the original
## (harness/mw_harness/rink_fixtures.py): draw_frame calls, add_sprite_piece
## calls, the sprite list and the info plates. Used by the GUT test on the
## committed sample and, locally, on whole recordings.


## Mismatch descriptions for pass [param p] (empty: identical).
## [param rules_phase]: the phase before the pass, for passes whose phase
## handler changed it (the recording has the phase after the pass).
static func compare(rom: PackedByteArray, p: Dictionary, rules_phase := -1) -> PackedStringArray:
	var out := PackedStringArray()
	var s := MwRinkState.from_dict(rom, p["state"])
	var d := MwRinkDraw.new(rom)
	var list := d.build(s, p["phase_adds"], rules_phase)
	var want_calls: Array = p["calls"]
	_diff(out, "calls", d.calls, want_calls)
	_diff(out, "adds", d.adds, p["adds"])
	var got_sprites := []
	for e in list:
		got_sprites.append([e[0], e[1], e[2], e[3], e[5]])
	_diff(out, "sprites", got_sprites, p["sprites"])
	# the plates drawn this pass, as the state says they show, vs the RAM tiles' hash
	for i in 4:
		var frame := MwRinkDraw.PLATES + 8 * i
		if not want_calls.any(func(c: Array) -> bool: return int(c[4]) == frame):
			continue
		var v: Array = s.plates[i]
		var h := MwGfx.sha1(MwPlate.tiles(rom, v[0], v[1], v[2])).substr(0, 16)
		if h != String(p["plates"][i]):
			out.append("plate %d (%s): %s != %s" % [i, v, h, p["plates"][i]])
	return out


static func _diff(out: PackedStringArray, what: String, got: Array, want: Array) -> void:
	var n := maxi(got.size(), want.size())
	for i in n:
		var g: Variant = _ints(got[i]) if i < got.size() else null
		var w: Variant = _ints(want[i]) if i < want.size() else null
		if g != w:
			out.append("%s[%d]: got %s want %s (%d vs %d entries)" % [what, i, _hex(g), _hex(w), got.size(), want.size()])
			return


static func _ints(a: Array) -> Array:
	return a.map(func(v: Variant) -> int: return int(v))


static func _hex(a: Variant) -> String:
	if a == null:
		return "-"
	return "[" + ", ".join((a as Array).map(func(v: int) -> String: return "%X" % v if v > 255 or v < 0 else str(v))) + "]"
