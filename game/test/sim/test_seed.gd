extends GutTest
## Plan 40 (S9, the survey's B5): MwSeed's reproductions of the engine's
## hash() give what this engine's hash() gives - the stands' filling order
## and an old replay's paint seed stay what they were, whatever a later
## engine's hash() does - and the session's stream seeds are its.


func test_the_engines_hash_of_three_ints() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 40
	for i in 500:
		var v := Vector3i(rng.randi_range(-4000, 4000), rng.randi_range(-4000, 4000), rng.randi_range(0, 40))
		assert_eq(MwSeed.engine_hash_ints(v.x, v.y, v.z), hash(v), str(v))
	assert_eq(MwSeed.engine_hash_ints(0, 0, 0), hash(Vector3i.ZERO))


func test_the_engines_hash_of_bytes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for n in [1, 2, 3, 4, 5, 7, 8, 13, 64, 301]:
		var b := PackedByteArray()
		for i in n:
			b.append(rng.randi() & 0xFF)
		assert_eq(MwSeed.engine_hash_bytes(b), hash(b), "%d bytes" % n)


func test_the_sessions_streams_mix_as_before() -> void:
	assert_eq(MwSeed.mix32(0), 0)
	assert_ne(MwSeed.mix([1, 2]), MwSeed.mix([2, 1]), "order matters")
	var u := MwSeed.unit(7, 3)
	assert_true(u >= 0.0 and u < 1.0)
