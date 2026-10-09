extends GutTest
## CombatMath (DESIGN 2.7): integer percentages, rounded half up, optional minimum of 1.


func test_percent_exact_values() -> void:
	assert_eq(CombatMath.percent(100, 100), 100)
	assert_eq(CombatMath.percent(40, 220), 88)
	assert_eq(CombatMath.percent(28, 130), 36, "36.4 rounds down")
	assert_eq(CombatMath.percent(28, 45), 13, "12.6 rounds up")
	assert_eq(CombatMath.percent(28, 35), 10, "9.8 rounds up")
	assert_eq(CombatMath.percent(0, 150), 0)
	assert_eq(CombatMath.percent(1500, 0), 0)


func test_percent_rounds_half_up() -> void:
	assert_eq(CombatMath.percent(5, 50), 3, "2.5 -> 3")
	assert_eq(CombatMath.percent(3, 50), 2, "1.5 -> 2")
	assert_eq(CombatMath.percent(1, 50), 1, "0.5 -> 1")
	assert_eq(CombatMath.percent(7, 150), 11, "10.5 -> 11")
	assert_eq(CombatMath.percent(48, 120), 58, "57.6 -> 58")
	assert_eq(CombatMath.percent(1, 49), 0, "0.49 -> 0")
	assert_eq(CombatMath.percent(1, 149), 1, "1.49 -> 1")


func test_percent_min1() -> void:
	assert_eq(CombatMath.percent_min1(1, 49), 1, "would round to 0")
	assert_eq(CombatMath.percent_min1(0, 100), 1)
	assert_eq(CombatMath.percent_min1(28, 45), 13, "above 1 it equals percent()")
	assert_eq(CombatMath.percent_min1(40, 90), 36)
