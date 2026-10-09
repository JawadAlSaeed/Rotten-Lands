extends GutTest
## Determinism (DESIGN 4.4): the same seed and the same commands give the same events and the
## same final state, and event logs survive var_to_bytes / var_to_str unchanged.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const Bot := preload("res://tests/helpers/combat_bot.gd")

const SEEDS: Array[int] = [1, 7, 42, 2026, -99]
const MODES: Array[int] = [Bot.Defence.PERFECT, Bot.Defence.MISS, Bot.Defence.MIXED]


func _fight(seed_value: int, defence: int, chunk: int = 0, practice: bool = false, tuning: Tuning = null) -> Dictionary:
	var engine := CombatEngine.new(Fx.shipped_setup(seed_value, tuning, practice))
	var run: Dictionary = Bot.new(defence as Bot.Defence, chunk, practice).play(engine)
	run["snapshot"] = engine.snapshot()
	run["engine"] = engine
	return run


func _check_twice(seed_value: int, defence: int, chunk: int, practice: bool, tuning_a: Tuning = null, tuning_b: Tuning = null) -> void:
	var a := _fight(seed_value, defence, chunk, practice, tuning_a)
	var b := _fight(seed_value, defence, chunk, practice, tuning_b)
	var label := "seed %d defence %d chunk %d practice %s" % [seed_value, defence, chunk, practice]
	var engine: CombatEngine = a.engine
	assert_eq(engine.phase, CombatEngine.Phase.ENDED, "fight finished: " + label)
	assert_eq((a.rejected as Array).size(), 0, "the bot never sends a bad command: " + label)
	assert_eq((a.events as Array).size(), (b.events as Array).size(), "same event count: " + label)
	assert_true(a.events == b.events, "identical event logs: " + label)
	assert_true(a.snapshot == b.snapshot, "identical final snapshots: " + label)


func test_same_seed_same_events() -> void:
	for seed_value: int in SEEDS:
		for defence: int in MODES:
			_check_twice(seed_value, defence, 0, false)


func test_same_seed_same_events_with_one_prompt_per_command_and_practice() -> void:
	for seed_value: int in [3, 99]:
		for defence: int in MODES:
			_check_twice(seed_value, defence, 1, true)


func test_same_seed_same_events_with_damage_variance() -> void:
	var tuning_a := Tuning.new()
	tuning_a.damage_variance_percent = 20
	var tuning_b := Tuning.new()
	tuning_b.damage_variance_percent = 20
	for seed_value: int in [5, 6]:
		_check_twice(seed_value, Bot.Defence.MIXED, 0, false, tuning_a, tuning_b)


func test_variance_changes_damage_between_seeds() -> void:
	var tuning := Tuning.new()
	tuning.damage_variance_percent = 20
	var amounts := {}
	for seed_value: int in 6:
		var run := _fight(seed_value, Bot.Defence.MISS, 0, false, tuning)
		for e: Dictionary in Fx.of_type(run.events as Array, "timed_sequence_declared"):
			for p: Dictionary in e.prompts:
				amounts[int(p.damage)] = true
	assert_gt(amounts.size(), 3, "variance produces a spread of pre-rolled damage values")


func test_different_seeds_play_differently() -> void:
	var a := _fight(1, Bot.Defence.MIXED)
	var b := _fight(2, Bot.Defence.MIXED)
	assert_false(a.events == b.events, "the seed matters")


func test_bot_results_match_expectations() -> void:
	# Smoke check of the fight balance with Tuning.new(): perfect defence wins, no defence loses.
	for seed_value: int in SEEDS:
		var perfect := _fight(seed_value, Bot.Defence.PERFECT)
		assert_eq((perfect.engine as CombatEngine).result, "victory", "perfect defence wins (seed %d)" % seed_value)
		var miss := _fight(seed_value, Bot.Defence.MISS)
		assert_eq((miss.engine as CombatEngine).result, "defeat", "no defence loses (seed %d)" % seed_value)


func test_event_log_survives_serialisation() -> void:
	var checked := 0
	for defence: int in MODES:
		var run := _fight(11, defence, 0, true)
		var events: Array = run.events
		for e: Dictionary in events:
			var copy: Variant = bytes_to_var(var_to_bytes(e))
			if not (copy == e):
				fail_test("var_to_bytes changed %s" % str(e))
				return
			var text_copy: Variant = str_to_var(var_to_str(e))
			if not (text_copy == e):
				fail_test("var_to_str changed %s" % str(e))
				return
			checked += 1
		assert_true(bytes_to_var(var_to_bytes(events)) == events, "the whole log round-trips")
		var snap: Dictionary = run.snapshot
		assert_true(bytes_to_var(var_to_bytes(snap)) == snap, "the snapshot round-trips")
	assert_gt(checked, 100)
