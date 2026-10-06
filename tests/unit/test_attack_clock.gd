extends GutTest
## AttackClock (DESIGN 3.3): attack time = real time since start minus hit-stop pauses.

const START: int = 1000000


func _clock() -> AttackClock:
	var clock := AttackClock.new()
	clock.start(START)
	return clock


func test_progression_without_pauses() -> void:
	var clock := AttackClock.new()
	assert_false(clock.is_started())
	clock.start(START)
	assert_true(clock.is_started())
	assert_eq(clock.attack_time_us(START), 0)
	assert_eq(clock.attack_time_us(START + 500), 500)
	assert_eq(clock.attack_time_us(START + 2500000), 2500000)


func test_pause_shifts_every_later_time_by_its_length() -> void:
	var clock := _clock()
	clock.pause_for(START + 1000, 100)
	assert_eq(clock.attack_time_us(START + 1000), 1000)
	assert_eq(clock.attack_time_us(START + 1050), 1000, "attack time stands still during the pause")
	assert_eq(clock.attack_time_us(START + 1100), 1000)
	assert_eq(clock.attack_time_us(START + 2000), 1900, "later times shift by exactly the pause")


func test_overlapping_pauses_merge() -> void:
	var clock := _clock()
	clock.pause_for(START + 1000, 100)
	clock.pause_for(START + 1050, 100)
	assert_eq(clock.attack_time_us(START + 1150), 1000, "[1000, 1150] frozen once, not twice")
	assert_eq(clock.attack_time_us(START + 2000), 1850)
	var nested := _clock()
	nested.pause_for(START + 1000, 300)
	nested.pause_for(START + 1100, 50)
	assert_eq(nested.attack_time_us(START + 2000), 1700, "a pause inside another adds nothing")


func test_separate_pauses_add_up() -> void:
	var clock := _clock()
	clock.pause_for(START + 1000, 100)
	clock.pause_for(START + 1500, 50)
	assert_eq(clock.attack_time_us(START + 1400), 1300)
	assert_eq(clock.attack_time_us(START + 2000), 1850)


func test_past_timestamps_convert_correctly() -> void:
	var clock := _clock()
	clock.pause_for(START + 1000, 100)
	clock.pause_for(START + 1500, 50)
	# A press stamped before the later pauses were recorded still converts with only the
	# pauses before it.
	assert_eq(clock.attack_time_us(START + 900), 900)
	assert_eq(clock.attack_time_us(START + 1060), 1000)
	assert_eq(clock.attack_time_us(START + 1300), 1200)
	assert_eq(clock.attack_time_us(START + 1525), 1400)


func test_is_paused() -> void:
	var clock := _clock()
	clock.pause_for(START + 1000, 100)
	assert_false(clock.is_paused(START + 999))
	assert_true(clock.is_paused(START + 1000))
	assert_true(clock.is_paused(START + 1099))
	assert_false(clock.is_paused(START + 1100), "the end is exclusive")


func test_zero_pause_and_restart() -> void:
	var clock := _clock()
	clock.pause_for(START + 1000, 0)
	assert_false(clock.is_paused(START + 1000))
	assert_eq(clock.attack_time_us(START + 2000), 2000)
	clock.pause_for(START + 1000, 100)
	clock.start(START + 5000)
	assert_eq(clock.attack_time_us(START + 6000), 1000, "start() clears old pauses")
