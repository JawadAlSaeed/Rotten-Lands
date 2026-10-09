extends GutTest
## CombatMirror (DESIGN 4.5): built only from events, it ends every fight agreeing with the
## engine's snapshot, and its copy of the current sequence follows prompt_resolved and
## prompts_voided.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const Bot := preload("res://tests/helpers/combat_bot.gd")

const PENDING: int = CombatEngine.PromptState.PENDING
const RESOLVED: int = CombatEngine.PromptState.RESOLVED
const VOID: int = CombatEngine.PromptState.VOID


func _apply_all(mirror: CombatMirror, events: Array) -> String:
	for e: Dictionary in events:
		if String(e.type) == "command_rejected":
			continue
		mirror.apply(e)
		if String(e.type) == "sequence_resolved" and (mirror.sequence.states as Array).has(PENDING):
			return "sequence %d resolved while the mirror still had pending prompts" % int(e.seq)
	return ""


## Plays a whole fight, feeding a mirror. Returns a description of the first disagreement
## between the mirror's sequence and the engine's, or "" if there was none.
func _play(engine: CombatEngine, bot: Bot, mirror: CombatMirror) -> String:
	var problem := _apply_all(mirror, engine.start())
	if not problem.is_empty():
		return problem
	for step: int in Bot.MAX_STEPS:
		if engine.phase == CombatEngine.Phase.ENDED:
			return ""
		var command := bot.next_command(engine)
		problem = _apply_all(mirror, engine.submit(command))
		if not problem.is_empty():
			return problem
		if engine.phase == CombatEngine.Phase.AWAITING_TIMING:
			if int(mirror.sequence.get("seq", -1)) != int(engine.sequence.seq):
				return "step %d: mirror on sequence %s, engine on %d" % [step, str(mirror.sequence.get("seq")), int(engine.sequence.seq)]
			if not (mirror.sequence.states == engine.sequence.states):
				return "step %d: states %s vs engine %s" % [step, str(mirror.sequence.states), str(engine.sequence.states)]
			if not (mirror.sequence.outcomes == engine.sequence.outcomes):
				return "step %d: outcomes %s vs engine %s" % [step, str(mirror.sequence.outcomes), str(engine.sequence.outcomes)]
		if mirror.turn != engine.turn_number:
			return "step %d: mirror turn %d, engine turn %d" % [step, mirror.turn, engine.turn_number]
	return "fight did not end"


func test_projection_matches_engine_after_full_fights() -> void:
	var fights := 0
	for seed_value: int in [1, 8, 33]:
		for defence: int in [Bot.Defence.PERFECT, Bot.Defence.MISS, Bot.Defence.MIXED, Bot.Defence.DODGE]:
			for chunk: int in [0, 1]:
				var practice := chunk == 1 and defence != Bot.Defence.PERFECT
				var label := "seed %d defence %d chunk %d practice %s" % [seed_value, defence, chunk, practice]
				var engine := CombatEngine.new(Fx.shipped_setup(seed_value, null, practice))
				var mirror := CombatMirror.new()
				var problem := _play(engine, Bot.new(defence as Bot.Defence, chunk, practice), mirror)
				assert_eq(problem, "", label)
				assert_eq(engine.phase, CombatEngine.Phase.ENDED, label)
				assert_eq(mirror.projection(), CombatMirror.project_snapshot(engine.snapshot()), label)
				assert_eq(mirror.result, engine.result, label)
				assert_eq(mirror.living_party_ids(), engine.living_party_ids(), label)
				assert_eq(mirror.living_enemy_ids(), engine.living_enemy_ids(), label)
				assert_eq(mirror.active_actor, -1, "nobody is active after the end: " + label)
				fights += 1
	assert_eq(fights, 24)


func test_projection_matches_engine_on_every_step() -> void:
	var engine := CombatEngine.new(Fx.shipped_setup(5, null, true))
	var bot := Bot.new(Bot.Defence.MIXED, 1, true)
	var mirror := CombatMirror.new()
	_apply_all(mirror, engine.start())
	var mismatches := 0
	while engine.phase != CombatEngine.Phase.ENDED:
		_apply_all(mirror, engine.submit(bot.next_command(engine)))
		if not (mirror.projection() == CombatMirror.project_snapshot(engine.snapshot())):
			mismatches += 1
	assert_eq(mismatches, 0, "after every command the mirror agrees with the engine")


func test_sequence_states_follow_resolved_and_voided_prompts() -> void:
	# c0 has 10 HP and drops on the first hit; its later prompts (3 and 6) are voided.
	var attack := Fx.attack("triple", [Fx.hit(900, Fx.NORMAL, 50), Fx.hit(1200, Fx.NORMAL, 50), Fx.hit(1500, Fx.NORMAL, 50)], Fx.PARTY)
	var engine := CombatEngine.new(Fx.setup([attack], {"hp_percents": [10, 100, 100]}))
	var mirror := CombatMirror.new()
	_apply_all(mirror, engine.start())
	assert_eq(mirror.sequence.states, [PENDING, PENDING, PENDING, PENDING, PENDING, PENDING, PENDING, PENDING, PENDING])
	_apply_all(mirror, engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.NONE], [1, Defense.Outcome.PARRY], [2, Defense.Outcome.DODGE]])))
	assert_eq(mirror.sequence.states, [RESOLVED, RESOLVED, RESOLVED, VOID, PENDING, PENDING, VOID, PENDING, PENDING])
	assert_eq((mirror.sequence.outcomes as Array).slice(0, 3), [Defense.Outcome.NONE, Defense.Outcome.PARRY, Defense.Outcome.DODGE])
	assert_eq(mirror.sequence.states, engine.sequence.states)
	assert_false(mirror.is_alive(0))
	assert_eq(mirror.fighter(0).hp, 0)
	assert_eq(mirror.fighter(1).ap, 2, "the parry's AP arrives through prompt_resolved")
	_apply_all(mirror, engine.submit(Fx.resolve_now(engine, [[4, Defense.Outcome.PARRY], [5, Defense.Outcome.PARRY]])))
	assert_eq(mirror.sequence.states, [RESOLVED, RESOLVED, RESOLVED, VOID, RESOLVED, RESOLVED, VOID, PENDING, PENDING])
	_apply_all(mirror, engine.submit(Fx.resolve_now(engine, [[7, Defense.Outcome.PARRY], [8, Defense.Outcome.NONE]])))
	assert_false((mirror.sequence.states as Array).has(PENDING), "the finished sequence has nothing pending")
	assert_eq(mirror.projection(), CombatMirror.project_snapshot(engine.snapshot()))


func test_events_of_another_sequence_do_not_touch_the_current_one() -> void:
	var engine := CombatEngine.new(Fx.setup([Fx.attack("swipe", [Fx.hit(900)])]))
	var mirror := CombatMirror.new()
	_apply_all(mirror, engine.start())
	var target := int((engine.sequence.targets as Array)[0])
	mirror.apply({"type": "prompts_voided", "seq": 99, "prompts": [0], "reason": "downed"})
	assert_eq(mirror.sequence.states, [PENDING])
	mirror.apply({"type": "prompt_resolved", "seq": 99, "prompt": 0, "hit": 0, "character": target,
			"outcome": Defense.Outcome.PARRY, "perfect": true, "offset_us": 0, "damage": 0, "hp": 100,
			"max_hp": 100, "ap": 1, "ap_delta": 0, "downed": false})
	assert_eq(mirror.sequence.states, [PENDING], "a stale sequence's results are not applied to this one")
