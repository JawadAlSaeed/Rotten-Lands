extends GutTest
## CombatRng (DESIGN 4.4): pinned golden values, inclusive ranges, weighted picks, state round
## trips and 32-bit safety for any seed.

const MASK_32: int = 0xFFFFFFFF
## Per seed: the state right after seeding, then the first five next_u32() values. Recorded from
## the implementation; if this test fails, every saved replay and seed-based test has changed.
const GOLDEN: Dictionary = {
	1: [824515495, 3630687087, 2772974634, 4217930956, 2514442164, 2585062432],
	42: [4147366645, 1137218979, 2129100477, 3072479877, 1394805692, 2026291286],
	0: [2654435769, 1359758873, 3761132862, 2075758394, 25405621, 3862129951],
	-1: [539527247, 353332031, 4118156907, 3235306358, 1824179178, 2889132201],
	123456789: [1952335732, 715373740, 4227093719, 1556021344, 718838041, 110041444],
}


func test_golden_values() -> void:
	for seed_value: int in GOLDEN:
		var rng := CombatRng.new(seed_value)
		var got: Array[int] = [rng.state]
		for i: int in 5:
			got.append(rng.next_u32())
		assert_eq(got, GOLDEN[seed_value] as Array, "golden values for seed %d" % seed_value)


func test_range_int_and_pick_weighted_golden_mapping() -> void:
	# Seed 1 raw values mod 10 are 7, 4, 6, 4, 2 (see GOLDEN), so both mappings are pinned too.
	var rng := CombatRng.new(1)
	var ranged: Array[int] = []
	for i: int in 5:
		ranged.append(rng.range_int(0, 9))
	assert_eq(ranged, [7, 4, 6, 4, 2])
	var weights: Array[int] = [3, 3, 2, 1, 1]
	var picker := CombatRng.new(1)
	var picks: Array[int] = []
	for i: int in 5:
		picks.append(picker.pick_weighted(weights))
	assert_eq(picks, [2, 1, 2, 1, 0])


func test_same_seed_same_sequence_and_seeds_differ() -> void:
	var a := CombatRng.new(77)
	var b := CombatRng.new(77)
	var c := CombatRng.new(78)
	var same := true
	var differs := false
	for i: int in 50:
		var va := a.next_u32()
		same = same and va == b.next_u32()
		differs = differs or va != c.next_u32()
	assert_true(same, "same seed gives the same sequence")
	assert_true(differs, "neighbouring seeds give different sequences")


func test_range_int_bounds_are_inclusive() -> void:
	var rng := CombatRng.new(99)
	var lowest := 1000
	var highest := -1000
	var outside := 0
	for i: int in 5000:
		var v := rng.range_int(-3, 4)
		lowest = mini(lowest, v)
		highest = maxi(highest, v)
		if v < -3 or v > 4:
			outside += 1
	assert_eq(outside, 0, "no value outside [-3, 4]")
	assert_eq(lowest, -3, "the low bound is reachable")
	assert_eq(highest, 4, "the high bound is reachable")


func test_range_int_degenerate_ranges_return_lo_without_drawing() -> void:
	var rng := CombatRng.new(5)
	var before := rng.state
	assert_eq(rng.range_int(5, 5), 5)
	assert_eq(rng.range_int(5, 2), 5)
	assert_eq(rng.state, before, "no state consumed for an empty range")


func test_pick_weighted_proportions() -> void:
	var rng := CombatRng.new(2024)
	var weights: Array[int] = [1, 3, 0, 6]
	var counts: Array[int] = [0, 0, 0, 0]
	var draws := 20000
	for i: int in draws:
		counts[rng.pick_weighted(weights)] += 1
	assert_eq(counts[2], 0, "a zero weight is never picked")
	assert_almost_eq(float(counts[0]) / draws, 0.1, 0.02, "weight 1 of 10")
	assert_almost_eq(float(counts[1]) / draws, 0.3, 0.02, "weight 3 of 10")
	assert_almost_eq(float(counts[3]) / draws, 0.6, 0.02, "weight 6 of 10")


func test_pick_weighted_returns_minus_one_without_positive_weights() -> void:
	var rng := CombatRng.new(3)
	var before := rng.state
	var zeros: Array[int] = [0, 0, 0]
	var empty: Array[int] = []
	var negative: Array[int] = [-5, 0]
	assert_eq(rng.pick_weighted(zeros), -1)
	assert_eq(rng.pick_weighted(empty), -1)
	assert_eq(rng.pick_weighted(negative), -1)
	assert_eq(rng.state, before, "no state consumed when nothing can be picked")
	var one_valid: Array[int] = [-5, 2, 0]
	for i: int in 50:
		assert_eq(rng.pick_weighted(one_valid), 1)


func test_state_save_and_restore_reproduces_the_sequence() -> void:
	var rng := CombatRng.new(31337)
	for i: int in 3:
		rng.next_u32()
	var saved := rng.state
	var weights: Array[int] = [2, 5, 1]
	var first: Array[int] = []
	for i: int in 20:
		first.append(rng.next_u32())
		first.append(rng.range_int(-10, 10))
		first.append(rng.pick_weighted(weights))
	rng.state = saved
	var again: Array[int] = []
	for i: int in 20:
		again.append(rng.next_u32())
		again.append(rng.range_int(-10, 10))
		again.append(rng.pick_weighted(weights))
	assert_eq(again, first, "restoring the state replays the sequence")
	var other := CombatRng.new(1)
	other.state = saved
	assert_eq(other.next_u32(), first[0], "a second generator given the state continues identically")


func test_negative_and_huge_seeds_stay_in_32_bits() -> void:
	var seeds: Array[int] = [-1, -2, -123456789, 1 << 32, (1 << 32) + 5, 1 << 62,
			9223372036854775807, -9223372036854775807 - 1, 0]
	for seed_value: int in seeds:
		var rng := CombatRng.new(seed_value)
		assert_between(rng.state, 1, MASK_32, "seeded state of %d is a non-zero 32-bit value" % seed_value)
		var bad := 0
		for i: int in 1000:
			var v := rng.next_u32()
			if v < 0 or v > MASK_32 or rng.state <= 0 or rng.state > MASK_32:
				bad += 1
		assert_eq(bad, 0, "seed %d: every value and state stays in [0, 2^32)" % seed_value)


func test_seed_uses_its_low_32_bits() -> void:
	assert_eq(CombatRng.new((1 << 32) + 5).state, CombatRng.new(5).state)
	assert_eq(CombatRng.new(0).state, 0x9E3779B9, "a zero seed never produces the stuck zero state")
