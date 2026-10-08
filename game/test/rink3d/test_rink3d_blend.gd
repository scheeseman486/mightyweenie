extends GutTest
## MwRinkBlend3D (plan 14): the 3D view between passes at any frame rate.


func _item(key: String, at: Vector3, place := MwRinkDraw3D.UPRIGHT) -> Dictionary:
	return {"key": key, "at": at, "place": place, "frame": 1, "attr": 0, "depth": 0, "offset": Vector2i.ZERO, "order": 0}


func test_points_move_from_the_previous_pass_to_the_latest() -> void:
	var prev := MwRinkBlend3D.by_key([_item("t0.p1.0/body", Vector3(10, 20, 0)), _item("puck/body", Vector3(0, 0, 8))])
	var cur := [_item("t0.p1.0/body", Vector3(20, 10, 4)), _item("puck/body", Vector3(8, 0, 0))]
	assert_eq(MwRinkBlend3D.items(prev, cur, 0.0)[0]["at"], Vector3(10, 20, 0))
	assert_eq(MwRinkBlend3D.items(prev, cur, 0.5)[0]["at"], Vector3(15, 15, 2))
	assert_eq(MwRinkBlend3D.items(prev, cur, 0.25)[1]["at"], Vector3(2, 0, 6))
	assert_eq(MwRinkBlend3D.items(prev, cur, 1.0), cur, "the latest pass as it is")
	assert_eq(MwRinkBlend3D.items(prev, cur, 7.0), cur, "clamped")
	assert_eq(MwRinkBlend3D.items(prev, cur, -1.0)[0]["at"], Vector3(10, 20, 0), "clamped")
	assert_eq(cur[0]["at"], Vector3(20, 10, 4), "the pass's items are not changed")


func test_new_frames_and_jumps_show_where_they_are() -> void:
	var prev := MwRinkBlend3D.by_key([_item("a/body", Vector3(0, 0, 0)), _item("b/body", Vector3(0, 0, 0)),
			_item("c/body", Vector3(0, 0, 0))])
	var far := MwRinkBlend3D.SNAP_PX + 1.0
	var cur := [_item("a/body", Vector3(far, 0, 0)), _item("b/body", Vector3(4, 0, 0), MwRinkDraw3D.MAP),
			_item("new/body", Vector3(4, 0, 0)), _item("c/body", Vector3(4, 0, 0))]
	var got := MwRinkBlend3D.items(prev, cur, 0.5)
	assert_eq(got[0]["at"], Vector3(far, 0, 0), "a jump snaps")
	assert_eq(got[1]["at"], Vector3(4, 0, 0), "another placement snaps")
	assert_eq(got[2]["at"], Vector3(4, 0, 0), "nothing to come from")
	assert_eq(got[3]["at"], Vector3(2, 0, 0))
	assert_eq(MwRinkBlend3D.items({}, cur, 0.5), cur, "after a jump (no previous pass)")


func test_camera_point_moves_and_snaps() -> void:
	assert_eq(MwRinkBlend3D.point(Vector2(96, 300), Vector2(100, 296), 0.25), Vector2(97, 299))
	assert_eq(MwRinkBlend3D.point(Vector2(96, 300), Vector2(96, 100), 0.25), Vector2(96, 100), "a cut snaps")
