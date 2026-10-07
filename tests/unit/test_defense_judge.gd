extends GutTest
## DefenseJudge (DESIGN 3.4, 3.5): inclusive window edges, success offsets, whiff reasons,
## lockout and its restart, mashing, expiry, in-order release, one press for several characters,
## latency compensation and interval presses. Times are microseconds of attack time.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NONE: int = Defense.Outcome.NONE
const DODGE: int = Defense.Outcome.DODGE
const PARRY: int = Defense.Outcome.PARRY
const JUMP: int = Defense.Outcome.JUMP
const SUCCESS: int = DefenseJudge.Result.SUCCESS
const WHIFF: int = DefenseJudge.Result.WHIFF
const LOCKED: int = DefenseJudge.Result.LOCKED
const DONE: int = DefenseJudge.Result.DONE
const EARLY: int = DefenseJudge.Reason.EARLY
const LATE: int = DefenseJudge.Reason.LATE
const WRONG_ACTION: int = DefenseJudge.Reason.WRONG_ACTION
const LOCKOUT_MS: int = 300
## Impact time of the single-prompt tests: 1000 ms.
const AT: int = 1000000

var _tuning := Tuning.new()


## A prompt exactly as the engine declares it (windows from Defense.build_windows).
func _prompt(idx: int, hit: int, character: int, at_ms: int, kind: int) -> Dictionary:
	return {
		"idx": idx, "hit": hit, "character": character, "at_ms": at_ms, "kind": kind,
		"windows": Defense.build_windows(kind, _tuning), "perfect": Defense.perfect_outcomes(kind),
		"damage": 10,
	}


func _judge(prompts: Array, compensation_ms: int = 0) -> DefenseJudge:
	var judge := DefenseJudge.new(LOCKOUT_MS, compensation_ms, _tuning.press_reach_back_max_ms, _tuning.late_press_report_ms)
	judge.set_prompts(prompts)
	return judge


func _single(kind: int, compensation_ms: int = 0) -> DefenseJudge:
	return _judge([_prompt(0, 0, 0, 1000, kind)], compensation_ms)


func _edges(kind: int, action: int) -> Array:
	return Defense.build_windows(kind, _tuning)[action]


func test_default_windows_match_design() -> void:
	assert_eq(_tuning.window_edges_us(_tuning.parry_window_ms), Vector2i(-97500, 52500))
	assert_eq(_tuning.window_edges_us(_tuning.dodge_window_ms), Vector2i(-162500, 87500))
	assert_eq(_tuning.window_edges_us(_tuning.jump_window_ms), Vector2i(-143000, 77000))
	assert_eq(Defense.build_windows(Fx.NORMAL, _tuning), {DODGE: [-162500, 87500], PARRY: [-97500, 52500]})
	assert_eq(Defense.build_windows(Fx.GROUND, _tuning), {JUMP: [-143000, 77000]})
	assert_eq(_tuning.press_reach_back_max_ms, 100, "DESIGN 3.1: reach back at most 100 ms")


func test_window_edges_are_inclusive_to_the_microsecond() -> void:
	for case: Array in [[Fx.NORMAL, PARRY], [Fx.NORMAL, DODGE], [Fx.GROUND, JUMP]]:
		var kind: int = case[0]
		var action: int = case[1]
		var edges := _edges(kind, action)
		var early: int = edges[0]
		var late: int = edges[1]
		var label := "%s on kind %d" % [Defense.outcome_name(action), kind]
		var r := _single(kind).press(action, AT + early)
		assert_eq(r.result, SUCCESS, "early edge counts: " + label)
		assert_eq(r.offset_us, early, label)
		r = _single(kind).press(action, AT + early - 1)
		assert_eq(r.result, WHIFF, "1 us before the early edge whiffs: " + label)
		assert_eq(r.reason, EARLY, label)
		r = _single(kind).press(action, AT + late)
		assert_eq(r.result, SUCCESS, "late edge counts: " + label)
		assert_eq(r.offset_us, late, label)
		r = _single(kind).press(action, AT + late + 1)
		assert_ne(r.result, SUCCESS, "1 us after the late edge fails: " + label)
	# Parry's late edge is inside the dodge window, so the prompt is still open: a LATE whiff.
	var late_parry := _single(Fx.NORMAL).press(PARRY, AT + 52501)
	assert_eq(late_parry.result, WHIFF)
	assert_eq(late_parry.reason, LATE)


func test_success_report_and_offset_sign() -> void:
	var r := _single(Fx.NORMAL).press(PARRY, AT - 40000)
	assert_eq(r, {"result": SUCCESS, "reason": DefenseJudge.Reason.NONE, "prompts": [0], "outcome": PARRY, "offset_us": -40000, "hit": 0})
	r = _single(Fx.NORMAL).press(PARRY, AT + 20000)
	assert_eq(r.offset_us, 20000, "after impact is positive")
	r = _single(Fx.GROUND).press(JUMP, AT)
	assert_eq(r.offset_us, 0)
	assert_eq(r.outcome, JUMP)


func test_whiff_reasons() -> void:
	var r := _single(Fx.NORMAL).press(PARRY, AT - 100000)
	assert_eq([r.result, r.reason, r.offset_us, r.hit, r.prompts], [WHIFF, EARLY, -100000, 0, []])
	r = _single(Fx.NORMAL).press(PARRY, AT + 60000)
	assert_eq([r.result, r.reason, r.offset_us], [WHIFF, LATE, 60000])
	r = _single(Fx.NORMAL).press(JUMP, AT)
	assert_eq([r.result, r.reason], [WHIFF, WRONG_ACTION], "jump into a normal hit")
	r = _single(Fx.NORMAL).press(JUMP, AT - 300000)
	assert_eq(r.reason, WRONG_ACTION, "the wrong button is reported even when also early")
	r = _single(Fx.GROUND).press(PARRY, AT)
	assert_eq([r.result, r.reason], [WHIFF, WRONG_ACTION], "parry against a ground wave")
	r = _single(Fx.GROUND).press(DODGE, AT + 10000)
	assert_eq([r.result, r.reason], [WHIFF, WRONG_ACTION], "dodge against a ground wave")


func test_whiff_starts_lockout_and_locked_presses_restart_it() -> void:
	var judge := _judge([_prompt(0, 0, 0, 1000, Fx.NORMAL), _prompt(1, 1, 0, 2000, Fx.NORMAL)])
	assert_eq(judge.press(PARRY, 500000).result, WHIFF)
	assert_true(judge.is_locked_out(799999))
	assert_false(judge.is_locked_out(800000), "the lockout lasts exactly whiff_lockout_ms")
	var locked := judge.press(PARRY, 700000)
	assert_eq(locked.result, LOCKED)
	assert_eq(locked.prompts, [])
	assert_true(judge.is_locked_out(999999), "a locked press restarts the lockout")
	assert_false(judge.is_locked_out(1000000))
	# Inside hit 0's parry window, but still locked: ignored, and the lockout restarts again.
	assert_eq(judge.press(PARRY, 950000).result, LOCKED)
	assert_true(judge.is_locked_out(1249999))
	assert_eq(judge.pop_ready(), [], "the locked press defended nothing")
	assert_eq(judge.advance(1087501), [0], "hit 0 lands")
	var r := judge.press(PARRY, 1950000)
	assert_eq(r.result, SUCCESS, "presses work again once the lockout is over")
	assert_eq(r.prompts, [1])
	assert_eq(judge.pop_ready(), [
		{"prompt": 0, "outcome": NONE, "offset_us": 0, "pressed": false},
		{"prompt": 1, "outcome": PARRY, "offset_us": -50000, "pressed": true},
	])


func test_presses_are_judged_again_when_the_lockout_ends() -> void:
	var judge := _single(Fx.NORMAL)
	assert_eq(judge.press(PARRY, 500000).result, WHIFF)
	var r := judge.press(DODGE, 850000)
	assert_eq(r.result, SUCCESS, "850 ms is after the 800 ms lockout end and inside the dodge window")
	assert_eq(r.outcome, DODGE)


func test_mashing_never_pays_after_the_first_whiff() -> void:
	var starts: Array[int] = [0, 10000, 20000, 30000, 40000, 50000, 60000, 70000, 740000, 810000]
	for action: int in [PARRY, DODGE]:
		for start: int in starts:
			var judge := _judge([_prompt(0, 0, 0, 900, Fx.NORMAL), _prompt(1, 1, 0, 1200, Fx.NORMAL), _prompt(2, 2, 0, 1500, Fx.NORMAL)])
			var results: Array[int] = []
			var t := start
			while t <= 1700000:
				judge.advance(t)
				results.append(int(judge.press(action, t).result))
				t += 80000
			var first_whiff := results.find(WHIFF)
			var successes := results.count(SUCCESS)
			var label := "%s mashing every 80 ms from %d us" % [Defense.outcome_name(action), start]
			assert_gt(first_whiff, -1, "mashing whiffs at some point: " + label)
			assert_lte(successes, first_whiff, "only presses before the first whiff can succeed: " + label)
			assert_eq(results.slice(first_whiff).count(SUCCESS), 0, "nothing succeeds after the first whiff: " + label)
			judge.advance(2000000)
			assert_eq(judge.pop_ready().size(), 3, label)


func test_advance_expires_only_after_the_latest_window_closes() -> void:
	var normal := _single(Fx.NORMAL)
	assert_eq(normal.advance(AT + 52501), [], "parry closed but dodge still open")
	assert_eq(normal.advance(AT + 87500), [], "the dodge late edge is still open")
	assert_eq(normal.pop_ready(), [])
	assert_eq(normal.advance(AT + 87501), [0])
	assert_eq(normal.pop_ready(), [{"prompt": 0, "outcome": NONE, "offset_us": 0, "pressed": false}])
	var ground := _single(Fx.GROUND)
	assert_eq(ground.advance(AT + 77000), [], "the jump late edge is still open")
	assert_eq(ground.advance(AT + 77001), [0])
	assert_eq(DefenseJudge.close_time_us({"at_us": AT, "windows": {DODGE: Vector2i(-162500, 87500), PARRY: Vector2i(-97500, 52500)}}), AT + 87500)


func test_release_order_normal_then_ground() -> void:
	# DESIGN 3.5 case: normal hit at 0, ground hit at 150 ms, JUMP pressed at 30 ms.
	var judge := _judge([_prompt(0, 0, 0, 0, Fx.NORMAL), _prompt(1, 1, 0, 150, Fx.GROUND)])
	var r := judge.press(JUMP, 30000)
	assert_eq(r.result, SUCCESS)
	assert_eq(r.prompts, [1], "the jump answers the ground hit")
	assert_eq(judge.pop_ready(), [], "prompt 1 waits for prompt 0")
	assert_eq(judge.advance(87500), [])
	assert_eq(judge.pop_ready(), [], "prompt 0 is still open")
	assert_eq(judge.advance(87501), [0])
	assert_eq(judge.pop_ready(), [
		{"prompt": 0, "outcome": NONE, "offset_us": 0, "pressed": false},
		{"prompt": 1, "outcome": JUMP, "offset_us": -120000, "pressed": true},
	])
	assert_true(judge.is_complete())


func test_one_press_answers_simultaneous_prompts_of_several_characters() -> void:
	var prompts: Array = []
	for h: int in 2:
		for c: int in 3:
			prompts.append(_prompt(h * 3 + c, h, c, 900 + h * 300, Fx.NORMAL))
	var judge := _judge(prompts)
	var r := judge.press(PARRY, 900000)
	assert_eq(r.prompts, [0, 1, 2], "one press defends the same hit for every character")
	assert_eq(judge.pop_ready().size(), 3)
	r = judge.press(PARRY, 1210000)
	assert_eq(r.prompts, [3, 4, 5])
	assert_eq(r.offset_us, 10000)


func test_one_press_defends_one_hit_per_character() -> void:
	# Overlapping windows (closer than real data allows): one press takes only the earliest.
	var judge := _judge([_prompt(0, 0, 0, 900, Fx.NORMAL), _prompt(1, 1, 0, 1000, Fx.NORMAL)])
	assert_eq(judge.press(PARRY, 950000).prompts, [0])
	assert_eq(judge.press(PARRY, 960000).prompts, [1], "the next press takes the next hit")


func test_latency_compensation_shifts_acceptance() -> void:
	var r := _single(Fx.NORMAL, 30).press(PARRY, AT + 82500)
	assert_eq(r.result, SUCCESS, "30 ms late on the clock is on time after compensation")
	assert_eq(r.offset_us, 52500)
	assert_eq(_single(Fx.NORMAL, 30).press(PARRY, AT + 82501).reason, LATE)
	assert_eq(_single(Fx.NORMAL, 30).press(PARRY, AT - 67500).result, SUCCESS)
	assert_eq(_single(Fx.NORMAL, 30).press(PARRY, AT - 67501).reason, EARLY)
	assert_eq(_single(Fx.NORMAL, 0).press(PARRY, AT + 82500).reason, LATE, "without compensation it is late")
	assert_eq(_single(Fx.NORMAL, -20).press(PARRY, AT - 117500).result, SUCCESS, "negative compensation shifts the other way")
	var judge := _single(Fx.NORMAL, 30)
	assert_eq(judge.advance(AT + 117500), [], "expiry is compensated too")
	assert_eq(judge.advance(AT + 117501), [0])
	var locking := _judge([_prompt(0, 0, 0, 1000, Fx.NORMAL), _prompt(1, 1, 0, 3000, Fx.NORMAL)], 30)
	assert_eq(locking.press(PARRY, 500000).result, WHIFF)
	assert_true(locking.is_locked_out(799999))
	assert_false(locking.is_locked_out(800000))


func test_interval_presses() -> void:
	var r := _single(Fx.NORMAL).press(PARRY, 1100000, 1040000)
	assert_eq(r.result, SUCCESS, "the interval reaches back into the window")
	assert_eq(r.offset_us, 70000, "the offset uses the interval midpoint")
	r = _single(Fx.NORMAL).press(PARRY, 1152500, 900000)
	assert_eq(r.result, SUCCESS, "reach-back capped at exactly the late edge still counts")
	assert_eq(r.offset_us, 102500)
	r = _single(Fx.NORMAL).press(PARRY, 1152501, 900000)
	assert_eq(r.result, WHIFF, "a longer reach-back is capped at press_reach_back_max_ms")
	assert_eq(r.reason, LATE)
	r = _single(Fx.NORMAL).press(PARRY, 902499, 850000)
	assert_eq([r.result, r.reason], [WHIFF, EARLY], "an interval wholly before the window")
	assert_eq(_single(Fx.NORMAL).press(PARRY, 902500, 850000).result, SUCCESS)
	r = _single(Fx.NORMAL).press(PARRY, 1060000, 1070000)
	assert_eq([r.result, r.reason], [WHIFF, LATE], "earliest after t: judged at t alone")
	assert_eq(_single(Fx.NORMAL, 30).press(PARRY, 1130000, 1070000).result, SUCCESS, "both ends are compensated")


func test_done_after_everything_resolved() -> void:
	var judge := _single(Fx.NORMAL)
	assert_eq(judge.press(PARRY, AT).result, SUCCESS)
	var r := judge.press(PARRY, AT + 10000)
	assert_eq(r.result, DONE)
	assert_false(judge.is_locked_out(AT + 20000), "DONE starts no lockout")
	assert_eq(judge.pop_ready().size(), 1)
	assert_true(judge.is_complete())
	var expired := _single(Fx.GROUND)
	expired.advance(AT + 500000)
	assert_eq(expired.press(JUMP, AT + 500000).result, DONE)


func test_helpers_and_prompt_order() -> void:
	var judge := _judge([_prompt(2, 2, 0, 1500, Fx.NORMAL), _prompt(0, 0, 0, 900, Fx.NORMAL), _prompt(1, 1, 0, 1200, Fx.GROUND)])
	assert_eq(judge.prompt_count(), 3)
	assert_eq(judge.next_impact_us(), 900000, "prompts are sorted by idx")
	assert_false(judge.is_complete())
	judge.press(PARRY, 900000)
	assert_eq(judge.next_impact_us(), 1200000)
	judge.resolve_all_remaining()
	assert_eq(judge.next_impact_us(), -1)
	var ready := judge.pop_ready()
	assert_eq(ready.size(), 3)
	assert_eq([ready[0].prompt, ready[1].prompt, ready[2].prompt], [0, 1, 2])
	assert_eq([ready[0].outcome, ready[1].outcome, ready[2].outcome], [PARRY, NONE, NONE])
	assert_true(judge.is_complete())


func test_judge_results_are_accepted_by_the_engine() -> void:
	# A judge fed with the engine's own declared prompts; its released results go straight back.
	var attack := Fx.attack("combo", [Fx.hit(900, Fx.NORMAL, 50), Fx.hit(1500, Fx.GROUND, 80)], Fx.PARTY)
	var engine := CombatEngine.new(Fx.setup([attack]))
	var declared := Fx.first_of(engine.start(), "timed_sequence_declared")
	var judge := DefenseJudge.new(_tuning.whiff_lockout_ms, 0, _tuning.press_reach_back_max_ms, _tuning.late_press_report_ms)
	judge.set_prompts(declared.prompts as Array)
	var events: Array[Dictionary] = []
	assert_eq(judge.press(PARRY, 905000).prompts, [0, 1, 2])
	events.append_array(engine.submit(CombatCommands.resolve_prompts(int(declared.seq), judge.pop_ready())))
	assert_eq(judge.press(JUMP, 1490000).prompts, [3, 4, 5])
	events.append_array(engine.submit(CombatCommands.resolve_prompts(int(declared.seq), judge.pop_ready())))
	assert_eq(Fx.of_type(events, "command_rejected").size(), 0)
	var counter := Fx.first_of(events, "counter")
	assert_eq(counter.get("team"), true, "a perfect party-wide defence becomes a team counter")
	assert_eq(Fx.of_type(events, "prompt_resolved")[0].offset_us, 5000, "the judge's offset reaches the engine")


func test_late_press_after_the_hit_landed_reports_late() -> void:
	var judge := _single(Fx.NORMAL)
	assert_eq(judge.advance(AT + 100000), [0], "the hit lands")
	var r := judge.press(PARRY, AT + 150000)
	assert_eq([r.result, r.reason, r.offset_us, r.hit, r.prompts], [WHIFF, LATE, 150000, 0, []])
	r = _single(Fx.GROUND).press(DODGE, AT + 200000)
	assert_eq([r.result, r.reason], [WHIFF, WRONG_ACTION], "a late wrong button is still the wrong button")
	var old := _single(Fx.NORMAL)
	old.advance(AT + 100000)
	var limit := _tuning.late_press_report_ms * 1000
	assert_eq(old.press(PARRY, AT + limit).reason, LATE, "late_press_report_ms is inclusive")
	assert_eq(_single(Fx.NORMAL).press(PARRY, AT + limit + 1).result, DONE, "much later presses are ignored")


func test_late_press_between_hits_blames_the_nearer_hit() -> void:
	var flurry := [_prompt(0, 0, 0, 900, Fx.NORMAL), _prompt(1, 1, 0, 1200, Fx.NORMAL)]
	var judge := _judge(flurry)
	judge.advance(1000000)
	var r := judge.press(PARRY, 1050000)
	assert_eq([r.result, r.reason, r.offset_us, r.hit], [WHIFF, LATE, 150000, 0], "late on hit 0, not early on hit 1")
	judge = _judge(flurry)
	judge.advance(1000000)
	r = judge.press(PARRY, 1060000)
	assert_eq([r.result, r.reason, r.offset_us, r.hit], [WHIFF, EARLY, -140000, 1], "nearer to hit 1: early on hit 1")
	var parried := _judge(flurry)
	assert_eq(parried.press(PARRY, 900000).result, SUCCESS)
	r = parried.press(PARRY, 1040000)
	assert_eq([r.reason, r.hit], [EARLY, 1], "a parried hit is never blamed for a late press")


func test_a_prompt_expired_by_a_capped_press_is_reported_by_advance() -> void:
	# A 190 ms frame stall: the press interval is capped at 100 ms, so press() itself expires hit 0.
	var judge := _judge([_prompt(0, 0, 0, 900, Fx.NORMAL), _prompt(1, 1, 0, 1200, Fx.NORMAL)], 30)
	assert_eq(judge.advance(960000), [])
	var r := judge.press(PARRY, 1150000, 960000)
	assert_eq(r.result, SUCCESS)
	assert_eq(r.prompts, [1])
	assert_eq(judge.advance(1151000), [0], "hit 0 still gets its hit-taken feedback")
	assert_eq(judge.advance(1152000), [], "reported once")


func test_no_late_report_across_a_defended_hit() -> void:
	var flurry := [_prompt(0, 0, 0, 900, Fx.NORMAL), _prompt(1, 1, 0, 1200, Fx.NORMAL), _prompt(2, 2, 0, 1500, Fx.NORMAL)]
	var judge := _judge(flurry)
	assert_eq(judge.press(PARRY, 880000).result, SUCCESS)
	assert_eq(judge.advance(1300000), [1], "hit 1 lands")
	assert_eq(judge.press(PARRY, 1490000).result, SUCCESS, "the last hit is parried")
	assert_eq(judge.press(PARRY, 1560000).result, DONE, "a double tap after the final parry is not LATE on hit 1")
	var mid := _judge(flurry)
	mid.advance(1000000)
	assert_eq(mid.press(PARRY, 1110000).result, SUCCESS, "hit 1 parried early")
	var r := mid.press(PARRY, 1190000)
	assert_eq([r.reason, r.hit], [EARLY, 2], "judged against the next hit, not LATE on hit 0")


func test_an_honest_late_press_costs_only_its_own_hit() -> void:
	var flurry := [_prompt(0, 0, 0, 900, Fx.NORMAL), _prompt(1, 1, 0, 1200, Fx.NORMAL), _prompt(2, 2, 0, 1500, Fx.NORMAL)]
	var judge := _judge(flurry)
	var late := judge.press(PARRY, 970000)
	assert_eq([late.result, late.reason, late.hit], [WHIFF, LATE, 0])
	assert_eq(judge.press(PARRY, 1180000).result, SUCCESS, "on time for hit 1 after a late press on hit 0")
	assert_eq(judge.press(PARRY, 1480000).result, SUCCESS)
	var close := [_prompt(0, 0, 0, 900, Fx.NORMAL), _prompt(1, 1, 0, 1100, Fx.NORMAL), _prompt(2, 2, 0, 1400, Fx.NORMAL)]
	var masher := _judge(close)
	assert_eq(masher.press(PARRY, 900000).result, SUCCESS)
	assert_eq(masher.press(PARRY, 1160000).reason, LATE, "late on hit 1, but only 260 ms after the last press")
	assert_eq(masher.press(PARRY, 1380000).result, LOCKED, "not isolated: the full lockout applies")
	var honest := _judge(close)
	assert_eq(honest.press(PARRY, 1160000).reason, LATE)
	assert_eq(honest.press(PARRY, 1380000).result, SUCCESS, "isolated: locked only until hit 2's window opens")
	var early := _judge(flurry)
	assert_eq(early.press(PARRY, 1070000).reason, EARLY)
	assert_eq(early.press(PARRY, 1180000).result, LOCKED, "an early whiff keeps the full lockout")


func test_voided_prompts_never_match_or_report_late() -> void:
	var judge := _judge([_prompt(0, 0, 0, 900, Fx.NORMAL), _prompt(1, 1, 0, 1200, Fx.NORMAL)])
	judge.advance(1000000)
	judge.void_prompts([1])
	var r := judge.press(PARRY, 1200000)
	assert_ne(r.result, SUCCESS, "a voided hit cannot be parried")
	assert_ne(r.hit, 1, "and is never the hit a press is judged against")
	assert_eq(judge.pop_ready().size(), 2, "voided prompts are still released in order")
	var landed := _judge([_prompt(0, 0, 0, 900, Fx.NORMAL)])
	landed.advance(1000000)
	landed.void_prompts([0])
	assert_eq(landed.press(PARRY, 1100000).result, DONE, "a voided hit is never blamed for a late press")


func test_a_very_late_press_does_not_lock_a_hit_whose_window_is_open() -> void:
	# +140 ms after hit 0: hit 1's dodge window (from -162.5 ms) is already open.
	var judge := _judge([_prompt(0, 0, 0, 900, Fx.NORMAL), _prompt(1, 1, 0, 1200, Fx.NORMAL), _prompt(2, 2, 0, 1500, Fx.NORMAL)])
	var late := judge.press(PARRY, 1040000)
	assert_eq([late.result, late.reason, late.hit, late.offset_us], [WHIFF, LATE, 0, 140000])
	assert_eq(judge.press(PARRY, 1180000).result, SUCCESS)
