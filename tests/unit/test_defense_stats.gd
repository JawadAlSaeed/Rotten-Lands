extends GutTest
## DefenseStats (F1 overlay and calibration maths) and the calibration clamp (DESIGN 3.2).

const SUCCESS: int = DefenseJudge.Result.SUCCESS
const WHIFF: int = DefenseJudge.Result.WHIFF
const PARRY: int = Defense.Outcome.PARRY


func _report(result: int, reason: int, offset_us: int, hit: int = 0) -> Dictionary:
	return {"result": result, "reason": reason, "prompts": [], "outcome": PARRY, "offset_us": offset_us, "hit": hit}


func test_median() -> void:
	var odd: Array[int] = [30000, -10000, 20000]
	assert_eq(DefenseStats.median_us(odd), 20000.0)
	var even: Array[int] = [40000, 10000, 30000, 20000]
	assert_eq(DefenseStats.median_us(even), 25000.0)
	var empty: Array[int] = []
	assert_eq(DefenseStats.median_us(empty), 0.0)


func test_spread_is_the_interquartile_range() -> void:
	var steady: Array[int] = [28000, 30000, 31000, 29000, 33000, 27000, 30000, 32000]
	assert_eq(DefenseStats.spread_us(steady), 3000.0, "sorted 27 28 29 30 | 30 31 32 33: 31.5 - 28.5")
	var reactive: Array[int] = [150000, 260000, 210000, 330000, 180000, 290000, 240000, 200000]
	assert_gt(DefenseStats.spread_us(reactive), 60000.0, "reaction presses spread far wider")
	var one: Array[int] = [5000]
	assert_eq(DefenseStats.spread_us(one), 0.0)


func test_whiffs_are_split_by_reason_and_feed_the_all_presses_median() -> void:
	var stats := DefenseStats.new()
	stats.record(PARRY, _report(SUCCESS, DefenseJudge.Reason.NONE, 10000))
	stats.record(PARRY, _report(WHIFF, DefenseJudge.Reason.LATE, 150000))
	stats.record(PARRY, _report(WHIFF, DefenseJudge.Reason.LATE, 90000))
	stats.record(PARRY, _report(WHIFF, DefenseJudge.Reason.EARLY, -120000))
	stats.record(PARRY, _report(WHIFF, DefenseJudge.Reason.WRONG_ACTION, 0))
	assert_eq(stats.whiffs, 4)
	assert_eq([stats.whiff_count(DefenseJudge.Reason.EARLY), stats.whiff_count(DefenseJudge.Reason.LATE),
			stats.whiff_count(DefenseJudge.Reason.WRONG_ACTION)], [1, 2, 1])
	assert_eq(stats.recent_all_us.size(), 4, "wrong-button presses carry no timing")
	assert_eq(stats.recent_all_median_ms(), 50.0)
	assert_eq(stats.success_count(PARRY), 1)
	assert_eq(stats.press_count(PARRY), 5)


func test_calibration_is_clamped_to_tuning_bounds() -> void:
	var tuning := Tuning.new()
	assert_eq(PlayerSettings.clamp_latency(45, tuning), 45)
	assert_eq(PlayerSettings.clamp_latency(250, tuning), tuning.calibration_max_ms)
	assert_eq(PlayerSettings.clamp_latency(-120, tuning), tuning.calibration_min_ms)
	assert_eq(PlayerSettings.clamp_latency(250, null), 250, "no tuning: unchanged")
