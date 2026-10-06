extends GutTest
## CombatEngine rules (DESIGN 2, 4.2, 4.3): start state, abilities and AP, atomic rejections,
## declared sequences, defence outcomes, partial and invalid results, counters and team counters,
## downed and voided prompts, victory/defeat mid-attack, kill thresholds, practice commands,
## payload hygiene and the documented event fields. Exact numbers come from Tuning.new() (never
## the user's tuning.tres).

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const Bot := preload("res://tests/helpers/combat_bot.gd")

const NONE: int = Defense.Outcome.NONE
const DODGE: int = Defense.Outcome.DODGE
const PARRY: int = Defense.Outcome.PARRY
const JUMP: int = Defense.Outcome.JUMP
const FOE: int = Fx.ENEMY_ID
## Fixture party power with Tuning.new(): 40 x 90%, 40 x 120%, 40 x 100%.
const POWERS: Array[int] = [36, 48, 40]
## Enemy speed that lets the party act first (turn cost 1000 against 90 to 111).
const SLOW_ENEMY: int = 10
## Field lists from the header of combat_engine.gd (the contract presentation and the network
## code rely on), plus the allowed values of the string enums.
const EVENT_KEYS: Dictionary = {
	"combat_started": ["seed", "fighters", "practice_allowed"],
	"turn_started": ["turn", "actor", "team", "time"],
	"turn_order": ["order"],
	"ability_used": ["turn", "actor", "ability", "targets"],
	"damage": ["source", "target", "amount", "hp", "max_hp", "cause"],
	"downed": ["target"],
	"ap_changed": ["character", "delta", "ap", "reason"],
	"timed_sequence_declared": ["seq", "kind", "source", "action", "name", "mode", "targets", "alert_cue",
			"allow_timing_ring", "hits", "prompts"],
	"prompt_resolved": ["seq", "prompt", "hit", "character", "outcome", "perfect", "offset_us", "damage", "hp",
			"max_hp", "ap", "ap_delta", "downed"],
	"prompts_voided": ["seq", "prompts", "reason"],
	"sequence_resolved": ["seq", "reason"],
	"counter": ["seq", "actors", "target", "team"],
	"turn_ended": ["turn", "actor"],
	"practice_changed": ["invulnerable_party", "immortal_enemies", "force_attack"],
	"combat_ended": ["result"],
	"command_rejected": ["reason", "command"],
}
const HIT_KEYS: Array[String] = ["index", "at_ms", "kind", "approach_ms", "feint", "damage_percent", "impact_sfx"]
const PROMPT_KEYS: Array[String] = ["idx", "hit", "character", "at_ms", "kind", "windows", "perfect", "damage"]
const STRING_VALUES: Dictionary = {
	"damage.cause": ["ability", "counter", "team_counter"],
	"ap_changed.reason": ["spend", "ability"],
	"prompts_voided.reason": ["downed", "attacker_down"],
	"sequence_resolved.reason": ["completed", "targets_down", "attacker_down"],
	"combat_ended.result": ["victory", "defeat"],
}


func _swipe() -> EnemyAttackData:
	return Fx.attack("swipe", [Fx.hit(900)])


func _flurry(pct: int = 45) -> EnemyAttackData:
	return Fx.attack("flurry", [Fx.hit(900, Fx.NORMAL, pct), Fx.hit(1200, Fx.NORMAL, pct), Fx.hit(1500, Fx.NORMAL, pct)])


## Party-wide: normal 900 (50%), ground 1500 (80%). Prompts 0-2 hit 0, prompts 3-5 hit 1.
func _mixed_party_attack() -> EnemyAttackData:
	return Fx.attack("combo", [Fx.hit(900, Fx.NORMAL, 50), Fx.hit(1500, Fx.GROUND, 80)], Fx.PARTY)


## A started engine where the party acts first (c1 at time 90 is the first actor).
func _party_first(options: Dictionary = {}) -> CombatEngine:
	var opts := options.duplicate()
	opts["enemy_speed"] = SLOW_ENEMY
	return Fx.started([_swipe()], opts)


func _prompts(engine: CombatEngine) -> Array:
	return engine.sequence.prompts


func _target(engine: CombatEngine) -> int:
	return int((engine.sequence.targets as Array)[0])


func _assert_rejected_atomically(engine: CombatEngine, command: Dictionary, reason: String) -> void:
	var before := engine.snapshot()
	var events := engine.submit(command)
	assert_eq(events.size(), 1, "rejection is a single event (%s)" % reason)
	if events.is_empty():
		return
	assert_eq(events[0].type, "command_rejected")
	assert_eq(events[0].reason, reason)
	assert_eq(events[0].command, command, "the rejected command is echoed back")
	assert_eq(engine.snapshot(), before, "a rejected command (%s) changes nothing" % reason)


# --- start ------------------------------------------------------------------------------------

func test_start_events_and_initial_stats() -> void:
	var engine := CombatEngine.new(Fx.setup([_swipe()], {"seed": 5}))
	var events := engine.start()
	assert_eq(Fx.types(events), ["combat_started", "turn_started", "turn_order", "timed_sequence_declared"],
			"the enemy is fastest, so start() runs straight into its attack")
	var started: Dictionary = events[0]
	assert_eq(started.seed, 5)
	assert_eq(started.practice_allowed, false)
	var fighters: Array = started.fighters
	assert_eq(fighters.size(), 4)
	for i: int in 3:
		var f: Dictionary = fighters[i]
		assert_eq(f.id, i)
		assert_eq(f.team, Combatant.Team.PARTY)
		assert_eq(f.slot, i)
		assert_eq(f.max_hp, 100)
		assert_eq(f.hp, 100)
		assert_eq(f.ap, 1, "start_ap")
		assert_eq(f.power, POWERS[i], "base_party_damage x power_percent")
	var foe: Dictionary = fighters[3]
	assert_eq(foe.team, Combatant.Team.ENEMY)
	assert_eq(foe.slot, 0)
	assert_eq(foe.max_hp, 1500)
	assert_eq(foe.hp, 1500)
	assert_eq(foe.power, 28)
	assert_eq(foe.ap, 0)
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_TIMING)
	assert_eq(engine.turn_number, 1)


func test_initial_stats_follow_tuning_and_data_percents() -> void:
	var tuning := Tuning.new()
	tuning.base_character_hp = 200
	tuning.base_party_damage = 50
	tuning.base_enemy_hp = 1000
	tuning.base_enemy_hit_damage = 30
	tuning.start_ap = 5
	tuning.max_ap = 3
	var engine := Fx.started([_swipe()], {"tuning": tuning, "hp_percents": [150, 100, 55],
			"enemy_hp_percent": 250, "enemy_power_percent": 130})
	assert_eq(engine.get_combatant(0).max_hp, 300)
	assert_eq(engine.get_combatant(1).max_hp, 200)
	assert_eq(engine.get_combatant(2).max_hp, 110)
	assert_eq(engine.get_combatant(0).power, 45)
	assert_eq(engine.get_combatant(1).power, 60)
	assert_eq(engine.get_combatant(2).power, 50)
	assert_eq(engine.get_combatant(0).ap, 3, "start_ap is capped at max_ap")
	assert_eq(engine.get_combatant(FOE).max_hp, 2500)
	assert_eq(engine.get_combatant(FOE).power, 39)


func test_start_twice_is_rejected() -> void:
	var engine := Fx.started([_swipe()])
	var before := engine.snapshot()
	var events := engine.start()
	assert_eq(Fx.types(events), ["command_rejected"])
	assert_eq(engine.snapshot(), before)


func test_invalid_setup_is_rejected_at_start() -> void:
	var setup := Fx.setup([Fx.attack("bad", [Fx.hit(900), Fx.hit(800)])])
	var engine := CombatEngine.new(setup)
	var events := engine.start()
	assert_eq(Fx.types(events), ["command_rejected"])
	assert_eq(engine.phase, CombatEngine.Phase.NOT_STARTED)


# --- abilities and AP -------------------------------------------------------------------------

func test_basic_attack_damage_and_ap_gain() -> void:
	var engine := _party_first()
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_ACTION)
	assert_eq(engine.active_actor, 1, "speed 110 acts first")
	var events := engine.submit(Fx.use(engine, "basic_attack"))
	assert_eq(Fx.types(events), ["ability_used", "damage", "ap_changed", "turn_ended", "turn_started", "turn_order"])
	assert_eq(events[0], {"type": "ability_used", "turn": 1, "actor": 1, "ability": "basic_attack", "targets": [FOE]})
	assert_eq(events[1], {"type": "damage", "source": 1, "target": FOE, "amount": 48, "hp": 1452, "max_hp": 1500, "cause": "ability"})
	assert_eq(events[2], {"type": "ap_changed", "character": 1, "delta": 1, "ap": 2, "reason": "ability"})
	assert_eq(events[3], {"type": "turn_ended", "turn": 1, "actor": 1})
	assert_eq(events[4].actor, 2, "then speed 100")
	assert_eq(engine.get_combatant(FOE).hp, 1452)
	assert_eq(engine.get_combatant(1).ap, 2)


func test_heavy_strike_costs_two_ap() -> void:
	var tuning := Tuning.new()
	tuning.start_ap = 2
	var engine := _party_first({"tuning": tuning})
	var events := engine.submit(Fx.use(engine, "heavy_strike"))
	assert_eq(Fx.types(events), ["ap_changed", "ability_used", "damage", "turn_ended", "turn_started", "turn_order"])
	assert_eq(events[0], {"type": "ap_changed", "character": 1, "delta": -2, "ap": 0, "reason": "spend"})
	assert_eq(events[2].amount, 106, "48 x 220% = 105.6 rounds to 106")
	assert_eq(engine.get_combatant(1).ap, 0)
	assert_eq(engine.get_combatant(FOE).hp, 1500 - 106)


func test_ap_gain_is_capped_at_max_ap() -> void:
	var tuning := Tuning.new()
	tuning.start_ap = 9
	var engine := _party_first({"tuning": tuning})
	var events := engine.submit(Fx.use(engine, "basic_attack"))
	assert_eq(Fx.of_type(events, "ap_changed").size(), 0, "no AP change at the cap, so no event")
	assert_eq(engine.get_combatant(1).ap, 9)


func test_invalid_use_ability_commands_are_rejected_atomically() -> void:
	var engine := _party_first()
	var turn := engine.turn_number
	var actor := engine.active_actor
	var foe_only: Array[int] = [FOE]
	_assert_rejected_atomically(engine, Fx.use(engine, "heavy_strike"), "not_enough_ap")
	_assert_rejected_atomically(engine, CombatCommands.use_ability(turn + 1, actor, "basic_attack", foe_only), "wrong_turn")
	_assert_rejected_atomically(engine, CombatCommands.use_ability(turn - 1, actor, "basic_attack", foe_only), "wrong_turn")
	_assert_rejected_atomically(engine, CombatCommands.use_ability(turn, 0, "basic_attack", foe_only), "not_this_actors_turn")
	_assert_rejected_atomically(engine, CombatCommands.use_ability(turn, FOE, "basic_attack", foe_only), "not_this_actors_turn")
	_assert_rejected_atomically(engine, Fx.use(engine, "basic_attack", 0), "invalid_target")
	_assert_rejected_atomically(engine, Fx.use(engine, "basic_attack", 99), "invalid_target")
	_assert_rejected_atomically(engine, Fx.use(engine, "basic_attack", -1), "invalid_target")
	var none: Array[int] = []
	var two: Array[int] = [FOE, FOE]
	_assert_rejected_atomically(engine, CombatCommands.use_ability(turn, actor, "basic_attack", none), "needs_one_target")
	_assert_rejected_atomically(engine, CombatCommands.use_ability(turn, actor, "basic_attack", two), "needs_one_target")
	_assert_rejected_atomically(engine, Fx.use(engine, "fireball"), "unknown_ability")
	_assert_rejected_atomically(engine, Fx.resolve(1, [[0, PARRY]]), "not_awaiting_timing")
	_assert_rejected_atomically(engine, {"type": "dance"}, "unknown_command")
	_assert_rejected_atomically(engine, {}, "unknown_command")
	# Nothing moved, so the original command still works.
	var events := engine.submit(Fx.use(engine, "basic_attack"))
	assert_eq(Fx.of_type(events, "command_rejected").size(), 0)
	assert_eq(engine.get_combatant(FOE).hp, 1452)


func test_use_ability_rejected_while_awaiting_timing() -> void:
	var engine := Fx.started([_swipe()])
	var targets: Array[int] = [FOE]
	_assert_rejected_atomically(engine, CombatCommands.use_ability(engine.turn_number, 0, "basic_attack", targets), "not_awaiting_action")


# --- declared sequences -----------------------------------------------------------------------

func test_declared_party_wide_sequence() -> void:
	var tuning := Tuning.new()
	tuning.attack_tempo_percent = 150
	var hits := [Fx.hit(900, Fx.NORMAL, 50), Fx.hit(1200, Fx.NORMAL, 100, 180), Fx.hit(1700, Fx.GROUND, 80, 400)]
	var attack := Fx.attack("combo", hits, Fx.PARTY)
	attack.alert_cue = false
	attack.allow_timing_ring = false
	var engine := CombatEngine.new(Fx.setup([attack], {"tuning": tuning}))
	var declared := Fx.first_of(engine.start(), "timed_sequence_declared")
	assert_eq(declared.seq, 1)
	assert_eq(declared.kind, "enemy_attack")
	assert_eq(declared.source, FOE)
	assert_eq(declared.action, "combo")
	assert_eq(declared.name, "Attack combo")
	assert_eq(declared.mode, Fx.PARTY)
	assert_eq(declared.targets, [0, 1, 2])
	assert_eq(declared.alert_cue, false)
	assert_eq(declared.allow_timing_ring, false)
	var expected_at: Array[int] = [1350, 1800, 2550]
	var expected_damage: Array[int] = [14, 28, 22]
	var declared_hits: Array = declared.hits
	assert_eq(declared_hits.size(), 3)
	for h: int in 3:
		var hd: Dictionary = declared_hits[h]
		assert_eq(hd.index, h)
		assert_eq(hd.at_ms, expected_at[h], "impact scaled by attack_tempo_percent")
		assert_eq(hd.approach_ms, CombatMath.percent((hits[h] as AttackHitData).approach_ms, 150))
		assert_eq(hd.kind, (hits[h] as AttackHitData).kind)
		assert_eq(hd.damage_percent, (hits[h] as AttackHitData).damage_percent)
	var prompts: Array = declared.prompts
	assert_eq(prompts.size(), 9, "one prompt per hit per target")
	for i: int in prompts.size():
		var p: Dictionary = prompts[i]
		@warning_ignore("integer_division")
		var h := i / 3
		var kind := (hits[h] as AttackHitData).kind
		assert_eq(p.idx, i)
		assert_eq(p.hit, h, "hit order first")
		assert_eq(p.character, i % 3, "then targets in slot order")
		assert_eq(p.at_ms, expected_at[h])
		assert_eq(p.kind, kind)
		assert_eq(p.windows, Defense.build_windows(kind, tuning), "windows come from Defense.build_windows")
		assert_eq(p.perfect, Defense.perfect_outcomes(kind))
		assert_eq(p.damage, expected_damage[h], "damage pre-rolled: 28 x hit percent")
	assert_eq(engine.pending_prompts(), [0, 1, 2, 3, 4, 5, 6, 7, 8])
	assert_eq(engine.sequence.prompts, prompts, "the engine keeps the same prompts it declared")


func test_declared_single_target_sequence() -> void:
	for seed_value: int in [1, 2, 3, 4, 5, 6]:
		var engine := CombatEngine.new(Fx.setup([_flurry()], {"seed": seed_value}))
		var declared := Fx.first_of(engine.start(), "timed_sequence_declared")
		var targets: Array = declared.targets
		assert_eq(targets.size(), 1)
		assert_between(int(targets[0]), 0, 2, "the target is a living party member")
		var prompts: Array = declared.prompts
		assert_eq(prompts.size(), 3)
		for i: int in 3:
			assert_eq(prompts[i].idx, i)
			assert_eq(prompts[i].hit, i)
			assert_eq(prompts[i].character, targets[0])
			assert_eq(prompts[i].damage, 13, "28 x 45% = 12.6 rounds to 13")


func test_single_target_attacks_spread_over_the_party() -> void:
	var seen := {}
	for seed_value: int in 30:
		var engine := Fx.started([_swipe()], {"seed": seed_value})
		seen[_target(engine)] = true
	assert_eq(seen.size(), 3, "every party member gets targeted for some seed")


# --- defence outcomes -------------------------------------------------------------------------

func test_none_applies_prompt_damage() -> void:
	var engine := Fx.started([_swipe()])
	var t := _target(engine)
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE, 1234]]))
	assert_eq(events[0], {
		"type": "prompt_resolved", "seq": 1, "prompt": 0, "hit": 0, "character": t, "outcome": NONE,
		"perfect": false, "offset_us": 1234, "damage": 28, "hp": 72, "max_hp": 100, "ap": 1,
		"ap_delta": 0, "downed": false,
	})
	assert_eq(events[1], {"type": "sequence_resolved", "seq": 1, "reason": "completed"})
	assert_eq(events[2], {"type": "turn_ended", "turn": 1, "actor": FOE})
	assert_eq(Fx.of_type(events, "counter").size(), 0)
	assert_eq(engine.get_combatant(t).hp, 72)


func test_parry_gives_ap_per_parry_and_no_damage() -> void:
	var tuning := Tuning.new()
	tuning.ap_per_parry = 2
	var engine := Fx.started([_swipe()], {"tuning": tuning})
	var t := _target(engine)
	var resolved := Fx.first_of(engine.submit(Fx.resolve_now(engine, [[0, PARRY, -5000]])), "prompt_resolved")
	assert_eq(resolved.outcome, PARRY)
	assert_eq(resolved.perfect, true)
	assert_eq(resolved.damage, 0)
	assert_eq(resolved.hp, 100)
	assert_eq(resolved.ap, 3)
	assert_eq(resolved.ap_delta, 2)
	assert_eq(resolved.offset_us, -5000)
	assert_eq(engine.get_combatant(t).ap, 3)


func test_parry_ap_is_capped_at_max_ap() -> void:
	var tuning := Tuning.new()
	tuning.start_ap = 9
	var engine := Fx.started([_swipe()], {"tuning": tuning})
	var resolved := Fx.first_of(engine.submit(Fx.resolve_now(engine, [[0, PARRY]])), "prompt_resolved")
	assert_eq(resolved.ap, 9)
	assert_eq(resolved.ap_delta, 0)


func test_dodge_gives_no_ap_and_no_damage() -> void:
	var engine := Fx.started([_swipe()])
	var events := engine.submit(Fx.resolve_now(engine, [[0, DODGE]]))
	var resolved := Fx.first_of(events, "prompt_resolved")
	assert_eq(resolved.outcome, DODGE)
	assert_eq(resolved.perfect, false)
	assert_eq(resolved.damage, 0)
	assert_eq(resolved.hp, 100)
	assert_eq(resolved.ap, 1)
	assert_eq(resolved.ap_delta, 0)
	assert_eq(Fx.of_type(events, "counter").size(), 0, "a dodge is not perfect: no counter")


func test_jump_on_ground_hit_works() -> void:
	var tuning := Tuning.new()
	tuning.ap_per_jump = 1
	var engine := Fx.started([Fx.attack("wave", [Fx.hit(1100, Fx.GROUND, 80, 450)])], {"tuning": tuning})
	var events := engine.submit(Fx.resolve_now(engine, [[0, JUMP]]))
	var resolved := Fx.first_of(events, "prompt_resolved")
	assert_eq(resolved.outcome, JUMP)
	assert_eq(resolved.perfect, true)
	assert_eq(resolved.damage, 0)
	assert_eq(resolved.ap_delta, 1, "ap_per_jump")
	assert_eq(Fx.of_type(events, "counter").size(), 1, "a jump counts as perfect")


func test_parry_or_dodge_on_ground_hit_is_sanitized_to_none() -> void:
	var waves := Fx.attack("waves", [Fx.hit(900, Fx.GROUND, 80), Fx.hit(1500, Fx.GROUND, 80)])
	var engine := Fx.started([waves])
	var t := _target(engine)
	var first := Fx.first_of(engine.submit(Fx.resolve_now(engine, [[0, PARRY]])), "prompt_resolved")
	assert_eq(first.outcome, NONE)
	assert_eq(first.perfect, false)
	assert_eq(first.damage, 22)
	assert_eq(first.hp, 78)
	assert_eq(first.ap_delta, 0, "no AP for a parry that did not happen")
	var second := Fx.first_of(engine.submit(Fx.resolve_now(engine, [[1, DODGE]])), "prompt_resolved")
	assert_eq(second.outcome, NONE)
	assert_eq(second.damage, 22)
	assert_eq(engine.get_combatant(t).hp, 56)


func test_jump_on_normal_hit_is_none() -> void:
	var engine := Fx.started([_swipe()])
	var resolved := Fx.first_of(engine.submit(Fx.resolve_now(engine, [[0, JUMP]])), "prompt_resolved")
	assert_eq(resolved.outcome, NONE)
	assert_eq(resolved.damage, 28)
	assert_eq(resolved.hp, 72)


func test_unknown_outcome_value_is_none() -> void:
	var engine := Fx.started([_swipe()])
	var resolved := Fx.first_of(engine.submit(Fx.resolve_now(engine, [[0, 99]])), "prompt_resolved")
	assert_eq(resolved.outcome, NONE)
	assert_eq(resolved.damage, 28)


# --- partial and invalid results --------------------------------------------------------------

func test_partial_results_keep_awaiting_timing() -> void:
	var engine := Fx.started([_flurry()])
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
	assert_eq(Fx.types(events), ["prompt_resolved"])
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_TIMING)
	assert_eq(engine.pending_prompts(), [1, 2])
	events = engine.submit(Fx.resolve_now(engine, [[2, PARRY], [1, PARRY]]))
	assert_eq(Fx.types(events).slice(0, 3), ["prompt_resolved", "prompt_resolved", "sequence_resolved"])
	assert_eq(events[0].prompt, 1, "a batch is applied in prompt order, whatever the list order")
	assert_eq(events[1].prompt, 2)


func test_invalid_resolve_commands_are_rejected_atomically() -> void:
	var engine := Fx.started([_flurry()])
	var seq := int(engine.sequence.seq)
	_assert_rejected_atomically(engine, Fx.resolve(seq, [[1, PARRY]]), "out_of_order")
	_assert_rejected_atomically(engine, Fx.resolve(seq, [[2, PARRY], [0, PARRY]]), "out_of_order")
	_assert_rejected_atomically(engine, Fx.resolve(seq, [[0, PARRY], [0, PARRY]]), "duplicate_prompt")
	_assert_rejected_atomically(engine, Fx.resolve(seq, [[3, PARRY]]), "unknown_prompt")
	_assert_rejected_atomically(engine, Fx.resolve(seq, [[-1, PARRY]]), "unknown_prompt")
	_assert_rejected_atomically(engine, Fx.resolve(seq + 1, [[0, PARRY]]), "stale_sequence")
	_assert_rejected_atomically(engine, Fx.resolve(seq - 1, [[0, PARRY]]), "stale_sequence")
	_assert_rejected_atomically(engine, Fx.resolve(seq, []), "no_results")
	_assert_rejected_atomically(engine, {"type": CombatCommands.RESOLVE_PROMPTS, "seq": seq}, "no_results")
	_assert_rejected_atomically(engine, {"type": CombatCommands.RESOLVE_PROMPTS, "seq": seq, "results": "all"}, "no_results")
	_assert_rejected_atomically(engine, {"type": CombatCommands.RESOLVE_PROMPTS, "seq": seq, "results": [0]}, "bad_result")
	# A bad entry anywhere rejects the whole batch, including the valid entries before it.
	_assert_rejected_atomically(engine, Fx.resolve(seq, [[0, PARRY], [1, PARRY], [7, PARRY]]), "unknown_prompt")
	engine.submit(Fx.resolve(seq, [[0, PARRY]]))
	_assert_rejected_atomically(engine, Fx.resolve(seq, [[0, PARRY]]), "stale_prompt")
	_assert_rejected_atomically(engine, Fx.resolve(seq, [[1, PARRY], [0, PARRY]]), "stale_prompt")
	assert_eq(engine.pending_prompts(), [1, 2])


func test_characters_resolve_independently() -> void:
	var engine := Fx.started([_mixed_party_attack()])
	var seq := int(engine.sequence.seq)
	assert_eq(Fx.of_type(engine.submit(Fx.resolve(seq, [[1, PARRY]])), "prompt_resolved").size(), 1,
			"c1 may answer before c0")
	assert_eq(Fx.of_type(engine.submit(Fx.resolve(seq, [[4, JUMP]])), "prompt_resolved").size(), 1,
			"c1's second hit while c0's first is still pending")
	_assert_rejected_atomically(engine, Fx.resolve(seq, [[3, JUMP]]), "out_of_order")
	var events := engine.submit(Fx.resolve(seq, [[5, JUMP], [3, JUMP], [0, PARRY], [2, PARRY]]))
	assert_eq(Fx.of_type(events, "prompt_resolved").size(), 4)
	assert_eq(Fx.first_of(events, "sequence_resolved").reason, "completed")


# --- counters ---------------------------------------------------------------------------------

func test_single_target_all_parried_counter() -> void:
	var engine := Fx.started([_flurry()])
	var t := _target(engine)
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, PARRY], [2, PARRY]]))
	var start := Fx.index_of(events, "sequence_resolved")
	assert_eq(events[start], {"type": "sequence_resolved", "seq": 1, "reason": "completed"})
	assert_eq(Fx.of_type(events, "counter").size(), 1)
	var amount := CombatMath.percent(POWERS[t], 150)
	assert_eq(events[start + 1], {"type": "counter", "seq": 1, "actors": [t], "target": FOE, "team": false})
	assert_eq(events[start + 2], {"type": "damage", "source": t, "target": FOE, "amount": amount,
			"hp": 1500 - amount, "max_hp": 1500, "cause": "counter"})
	assert_eq(events[start + 3].type, "turn_ended")


func test_counter_needs_every_hit_perfect() -> void:
	var engine := Fx.started([_flurry()])
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, PARRY], [2, DODGE]]))
	assert_eq(Fx.of_type(events, "counter").size(), 0)
	engine = Fx.started([_flurry()])
	events = engine.submit(Fx.resolve_now(engine, [[0, NONE], [1, PARRY], [2, PARRY]]))
	assert_eq(Fx.of_type(events, "counter").size(), 0)


func test_counter_uses_counter_percent_from_tuning() -> void:
	var tuning := Tuning.new()
	tuning.counter_percent = 300
	var engine := Fx.started([_swipe()], {"tuning": tuning})
	var t := _target(engine)
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
	var damage := Fx.of_type(events, "damage")[0]
	assert_eq(damage.amount, CombatMath.percent(POWERS[t], 300))
	assert_eq(damage.cause, "counter")


func test_party_wide_all_perfect_gives_one_team_counter() -> void:
	var engine := Fx.started([_mixed_party_attack()])
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, PARRY], [2, PARRY], [3, JUMP], [4, JUMP], [5, JUMP]]))
	var counters := Fx.of_type(events, "counter")
	assert_eq(counters.size(), 1, "exactly one counter event")
	assert_eq(counters[0], {"type": "counter", "seq": 1, "actors": [0, 1, 2], "target": FOE, "team": true})
	var expected := 0
	for i: int in 3:
		expected += CombatMath.percent(engine.get_combatant(i).power, Tuning.new().team_counter_percent)
	assert_eq(expected, 149, "43 + 58 + 48 with the default 120%")
	var damages := Fx.of_type(events, "damage")
	assert_eq(damages.size(), 1, "one combined hit")
	assert_eq(damages[0].amount, expected)
	assert_eq(damages[0].cause, "team_counter")
	assert_eq(damages[0].target, FOE)
	assert_eq(engine.get_combatant(FOE).hp, 1500 - expected)


func test_party_wide_partially_perfect_gives_solo_counters() -> void:
	var engine := Fx.started([_mixed_party_attack()])
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, DODGE], [2, PARRY], [3, JUMP], [4, JUMP], [5, JUMP]]))
	var counters := Fx.of_type(events, "counter")
	assert_eq(counters.size(), 2)
	assert_eq(counters[0], {"type": "counter", "seq": 1, "actors": [0], "target": FOE, "team": false})
	assert_eq(counters[1], {"type": "counter", "seq": 1, "actors": [2], "target": FOE, "team": false})
	var damages := Fx.of_type(events, "damage")
	assert_eq(damages.size(), 2)
	assert_eq(damages[0].amount, CombatMath.percent(POWERS[0], 150))
	assert_eq(damages[0].source, 0)
	assert_eq(damages[1].amount, CombatMath.percent(POWERS[2], 150))
	assert_eq(damages[1].source, 2)
	assert_eq(damages[1].hp, 1500 - damages[0].amount - damages[1].amount)


func test_downed_mid_attack_voids_prompts_and_blocks_team_counter() -> void:
	# c0 has 10 HP; each hit deals 14, so c0 drops on the first hit it takes.
	var attack := Fx.attack("triple", [Fx.hit(900, Fx.NORMAL, 50), Fx.hit(1200, Fx.NORMAL, 50), Fx.hit(1500, Fx.NORMAL, 50)], Fx.PARTY)
	var engine := Fx.started([attack], {"hp_percents": [10, 100, 100]})
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE], [1, PARRY], [2, PARRY]]))
	assert_eq(Fx.types(events), ["prompt_resolved", "downed", "prompts_voided", "prompt_resolved", "prompt_resolved"])
	assert_eq(events[0].downed, true)
	assert_eq(events[0].hp, 0)
	assert_eq(events[1], {"type": "downed", "target": 0})
	assert_eq(events[2], {"type": "prompts_voided", "seq": 1, "prompts": [3, 6], "reason": "downed"})
	assert_eq(engine.pending_prompts(), [4, 5, 7, 8])
	_assert_rejected_atomically(engine, Fx.resolve_now(engine, [[3, PARRY]]), "stale_prompt")
	events = engine.submit(Fx.resolve_now(engine, [[4, PARRY], [5, PARRY], [7, PARRY], [8, PARRY]]))
	assert_eq(Fx.first_of(events, "sequence_resolved").reason, "completed", "the others still stand")
	var counters := Fx.of_type(events, "counter")
	assert_eq(counters.size(), 2, "the survivors counter on their own")
	for c: Dictionary in counters:
		assert_eq(c.team, false, "no team counter when someone went down")
	assert_eq(counters[0].actors, [1])
	assert_eq(counters[1].actors, [2])


func test_downed_characters_are_not_targeted_and_a_lone_target_counters_alone() -> void:
	# c0 and c1 have 10 HP and drop on the first undefended hit (14 damage); c2 parries.
	var slam := Fx.attack("slam", [Fx.hit(900, Fx.NORMAL, 50)], Fx.PARTY)
	var poke := Fx.attack("poke", [Fx.hit(900, Fx.NORMAL, 50)], Fx.SINGLE)
	var engine := Fx.started([slam, poke], {"hp_percents": [10, 10, 100], "seed": 3})
	for attempt: int in 50:
		if String(engine.sequence.action) == "slam":
			break
		engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
		while engine.phase == CombatEngine.Phase.AWAITING_ACTION:
			engine.submit(Fx.use(engine, "basic_attack"))
	assert_eq(engine.sequence.action, "slam", "the party-wide attack came up")
	engine.submit(Fx.resolve_now(engine, [[0, NONE], [1, NONE], [2, PARRY]]))
	assert_eq(engine.living_party_ids(), [2])
	var bot := Bot.new(Bot.Defence.PERFECT)
	var declared: Array[Dictionary] = []
	var lone_counters: Array[Dictionary] = []
	for step: int in 60:
		if engine.phase == CombatEngine.Phase.ENDED:
			break
		var events := engine.submit(bot.next_command(engine))
		declared.append_array(Fx.of_type(events, "timed_sequence_declared"))
		lone_counters.append_array(Fx.of_type(events, "counter"))
	assert_gt(declared.size(), 3, "the enemy attacked again several times")
	for e: Dictionary in declared:
		assert_eq(e.targets, [2], "only the living character is targeted (%s)" % e.action)
		for p: Dictionary in e.prompts:
			assert_eq(p.character, 2)
	assert_gt(lone_counters.size(), 0)
	for c: Dictionary in lone_counters:
		# DESIGN 2.5 does not cover a party-wide attack with one living target: the engine treats
		# it as a solo counter (team needs at least two targets).
		assert_eq(c.team, false, "a single target never makes a team counter")
		assert_eq(c.actors, [2])


func test_whole_party_downed_mid_attack_is_defeat() -> void:
	var attack := Fx.attack("crush", [Fx.hit(900, Fx.NORMAL, 400), Fx.hit(1500, Fx.NORMAL, 400)], Fx.PARTY)
	var engine := Fx.started([attack])
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE], [1, NONE], [2, NONE]]))
	assert_eq(Fx.of_type(events, "downed").size(), 3)
	var voided: Array = []
	for e: Dictionary in Fx.of_type(events, "prompts_voided"):
		voided.append_array(e.prompts)
		assert_eq(e.reason, "downed")
	assert_eq(voided, [3, 4, 5], "every remaining prompt is voided")
	var resolved_at := Fx.index_of(events, "sequence_resolved")
	var ended_at := Fx.index_of(events, "combat_ended")
	assert_eq(events[resolved_at], {"type": "sequence_resolved", "seq": 1, "reason": "targets_down"})
	assert_gt(ended_at, resolved_at, "sequence_resolved comes before combat_ended")
	assert_eq(events[ended_at], {"type": "combat_ended", "result": "defeat"})
	assert_eq(ended_at, events.size() - 1, "nothing after the end")
	assert_eq(Fx.of_type(events, "counter").size(), 0)
	assert_eq(engine.phase, CombatEngine.Phase.ENDED)
	assert_eq(engine.result, "defeat")
	assert_eq(engine.active_actor, -1)
	assert_true(engine.sequence.is_empty())
	_assert_rejected_atomically(engine, Fx.resolve(1, [[3, NONE]]), "not_awaiting_timing")
	var targets: Array[int] = [FOE]
	_assert_rejected_atomically(engine, CombatCommands.use_ability(engine.turn_number, 0, "basic_attack", targets), "not_awaiting_action")


func test_single_target_downed_moves_to_the_next_turn() -> void:
	var attack := Fx.attack("crush", [Fx.hit(900, Fx.NORMAL, 400), Fx.hit(1500, Fx.NORMAL, 400)])
	var engine := Fx.started([attack])
	var t := _target(engine)
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	assert_eq(Fx.first_of(events, "prompts_voided").prompts, [1])
	assert_eq(Fx.first_of(events, "sequence_resolved").reason, "targets_down")
	assert_eq(Fx.of_type(events, "combat_ended").size(), 0, "two characters still stand")
	assert_ne(Fx.first_of(events, "turn_started").actor, t)
	assert_ne(engine.phase, CombatEngine.Phase.ENDED)


func test_results_for_prompts_voided_mid_batch_are_skipped() -> void:
	var attack := Fx.attack("crush", [Fx.hit(900, Fx.NORMAL, 400), Fx.hit(1500, Fx.NORMAL, 400)])
	var engine := Fx.started([attack])
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE], [1, PARRY]]))
	assert_eq(Fx.types(events).slice(0, 4), ["prompt_resolved", "downed", "prompts_voided", "sequence_resolved"],
			"prompt 1 is voided by the first result, so its own result is dropped, not rejected")
	assert_eq(Fx.of_type(events, "prompt_resolved").size(), 1)
	assert_eq(Fx.first_of(events, "prompts_voided").prompts, [1])
	assert_eq(Fx.first_of(events, "sequence_resolved").reason, "targets_down")


func test_victory_by_counter_kill() -> void:
	var tuning := Tuning.new()
	tuning.base_enemy_hp = 50
	var engine := Fx.started([_swipe()], {"tuning": tuning})
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
	var counter_at := Fx.index_of(events, "counter")
	var damage := Fx.first_of(events, "damage")
	assert_gt(counter_at, -1)
	assert_eq(damage.hp, 0)
	var downed := Fx.of_type(events, "downed")
	assert_eq(downed.size(), 1)
	assert_eq(downed[0].target, FOE)
	assert_eq(events[events.size() - 1], {"type": "combat_ended", "result": "victory"})
	assert_gt(Fx.index_of(events, "combat_ended"), Fx.index_of(events, "downed"))
	assert_eq(engine.phase, CombatEngine.Phase.ENDED)
	assert_eq(engine.result, "victory")


func test_victory_by_ability() -> void:
	var tuning := Tuning.new()
	tuning.base_enemy_hp = 40
	var engine := _party_first({"tuning": tuning})
	var events := engine.submit(Fx.use(engine, "basic_attack"))
	assert_eq(Fx.types(events), ["ability_used", "damage", "downed", "ap_changed", "turn_ended", "combat_ended"])
	assert_eq(events[5].result, "victory")


# --- kill thresholds (DESIGN 2.7) -------------------------------------------------------------

func _undefended_hp_trail(attack: EnemyAttackData) -> Array[int]:
	var engine := Fx.started([attack])
	var trail: Array[int] = []
	for idx: int in (engine.sequence.prompts as Array).size():
		var resolved := Fx.first_of(engine.submit(Fx.resolve_now(engine, [[idx, NONE]])), "prompt_resolved")
		trail.append(int(resolved.hp))
		assert_eq(resolved.downed, int(resolved.hp) == 0)
	return trail


func test_four_normal_hits_kill_three_do_not() -> void:
	var four := Fx.attack("four", [Fx.hit(900), Fx.hit(1200), Fx.hit(1500), Fx.hit(1800)])
	assert_eq(_undefended_hp_trail(four), [100 - 28, 100 - 56, 100 - 84, 0])


func test_three_heavy_hits_kill_two_do_not() -> void:
	var heavy := Fx.attack("heavy", [Fx.hit(900, Fx.NORMAL, 130), Fx.hit(1200, Fx.NORMAL, 130), Fx.hit(1500, Fx.NORMAL, 130)])
	assert_eq(_undefended_hp_trail(heavy), [100 - 36, 100 - 72, 0])


## Damage each shipped husk attack deals to one target when nothing is defended, read from the
## prompts the engine declares (Tuning.new() numbers, shipped party and attacks).
func _shipped_attack_damage() -> Dictionary:
	var encounter := (load(Fx.ENCOUNTER_PATH) as EncounterData).duplicate(true) as EncounterData
	var husk: EnemyData = encounter.enemies[0]
	var damage := {}
	for attack: EnemyAttackData in husk.attacks:
		var solo := husk.duplicate() as EnemyData
		var only: Array[EnemyAttackData] = [attack]
		solo.attacks = only
		var setup := CombatSetup.new()
		setup.party = encounter.party.duplicate()
		var foes: Array[EnemyData] = [solo]
		setup.enemies = foes
		setup.tuning = Tuning.new()
		var engine := CombatEngine.new(setup)
		var declared := Fx.first_of(engine.start(), "timed_sequence_declared")
		assert_eq(declared.action, attack.id)
		var per_target := {}
		for p: Dictionary in declared.prompts:
			per_target[p.character] = int(per_target.get(p.character, 0)) + int(p.damage)
		var values := per_target.values()
		for v: Variant in values:
			assert_eq(int(v), int(values[0]), "every target of %s takes the same damage" % attack.id)
		damage[attack.id] = int(values[0])
	return damage


func test_shipped_husk_two_attacks_never_kill_and_three_or_four_can() -> void:
	var damage := _shipped_attack_damage()
	assert_eq(damage.size(), 5, "five husk attacks")
	var values: Array[int] = []
	for v: Variant in damage.values():
		values.append(int(v))
	values.sort()
	var top: int = values[values.size() - 1]
	# Attacks are drawn with replacement, so the worst pair is the strongest attack twice.
	var max_two: int = top * 2
	var engine := CombatEngine.new(Fx.shipped_setup(1))
	engine.start()
	for id: int in engine.party_ids():
		var hp := engine.get_combatant(id).max_hp
		assert_lt(max_two, hp, "any 2 undefended attacks leave %s alive (worst pair %d)" % [engine.get_combatant(id).data_id, max_two])
		assert_gte(top * 4, hp, "some 3 or 4 attack sequence downs %s" % engine.get_combatant(id).data_id)
	gut.p("Undefended damage per husk attack: %s" % str(damage))


func test_shipped_rot_combo_downs_the_party_on_the_third_attack() -> void:
	var encounter := (load(Fx.ENCOUNTER_PATH) as EncounterData).duplicate(true) as EncounterData
	var husk: EnemyData = encounter.enemies[0]
	var solo := husk.duplicate() as EnemyData
	var only: Array[EnemyAttackData] = []
	for attack: EnemyAttackData in husk.attacks:
		if attack.id == "husk_rot_combo":
			only.append(attack)
	assert_eq(only.size(), 1, "the shipped husk has a Rot Combo")
	solo.attacks = only
	var setup := CombatSetup.new()
	setup.party = encounter.party.duplicate()
	var foes: Array[EnemyData] = [solo]
	setup.enemies = foes
	setup.tuning = Tuning.new()
	var engine := CombatEngine.new(setup)
	var run: Dictionary = Bot.new(Bot.Defence.MISS).play(engine)
	var events: Array = run.events
	assert_eq(engine.result, "defeat")
	assert_eq(Fx.of_type(events, "timed_sequence_declared").size(), 3, "party-wide combos: alive after 2, down on the 3rd")


# --- practice ---------------------------------------------------------------------------------

func test_practice_rejected_when_the_setup_does_not_allow_it() -> void:
	var engine := Fx.started([_swipe()])
	_assert_rejected_atomically(engine, CombatCommands.practice({"invulnerable_party": true}), "practice_disabled")
	_assert_rejected_atomically(engine, CombatCommands.practice({"force_attack": "swipe"}), "practice_disabled")


func test_practice_rejected_outside_combat() -> void:
	var engine := CombatEngine.new(Fx.setup([_swipe()], {"practice": true}))
	_assert_rejected_atomically(engine, CombatCommands.practice({"invulnerable_party": true}), "not_in_combat")


func test_invulnerable_party_floors_party_hp_at_one() -> void:
	var attack := Fx.attack("crush", [Fx.hit(900, Fx.NORMAL, 400), Fx.hit(1200, Fx.NORMAL, 400), Fx.hit(1500, Fx.NORMAL, 400)])
	var engine := Fx.started([attack], {"practice": true})
	var events := engine.submit(CombatCommands.practice({"invulnerable_party": true}))
	assert_eq(events, [{"type": "practice_changed", "invulnerable_party": true, "immortal_enemies": false, "force_attack": ""}])
	var t := _target(engine)
	for idx: int in 3:
		events = engine.submit(Fx.resolve_now(engine, [[idx, NONE]]))
		var resolved := Fx.first_of(events, "prompt_resolved")
		assert_eq(resolved.hp, 1, "HP stops at 1")
		assert_eq(resolved.downed, false)
		assert_eq(Fx.of_type(events, "downed").size(), 0)
	assert_true(engine.get_combatant(t).is_alive())
	assert_eq(Fx.first_of(events, "sequence_resolved").reason, "completed")


func test_immortal_enemies_floors_enemy_hp_at_one() -> void:
	var tuning := Tuning.new()
	tuning.base_enemy_hp = 30
	var engine := _party_first({"tuning": tuning, "practice": true})
	engine.submit(CombatCommands.practice({"immortal_enemies": true}))
	var events := engine.submit(Fx.use(engine, "basic_attack"))
	assert_eq(Fx.first_of(events, "damage").hp, 1)
	events = engine.submit(Fx.use(engine, "basic_attack"))
	assert_eq(Fx.first_of(events, "damage").hp, 1, "still 1 after another hit")
	assert_eq(Fx.of_type(events, "downed").size(), 0)
	assert_ne(engine.phase, CombatEngine.Phase.ENDED)
	engine.submit(CombatCommands.practice({"immortal_enemies": false}))
	events = engine.submit(Fx.use(engine, "basic_attack"))
	assert_eq(Fx.first_of(events, "combat_ended").result, "victory", "turning it off lets the next hit kill")


func test_force_attack_picks_the_next_attack_then_clears() -> void:
	var common := Fx.attack("common", [Fx.hit(900)], Fx.SINGLE, 1)
	# Weight 0: never chosen at random, so only forcing can select it.
	var rare := Fx.attack("rare", [Fx.hit(1100, Fx.GROUND, 80)], Fx.PARTY, 0)
	var engine := CombatEngine.new(Fx.setup([common, rare], {"practice": true}))
	var bot := Bot.new(Bot.Defence.PERFECT)
	assert_eq(Fx.first_of(engine.start(), "timed_sequence_declared").action, "common")
	var events := engine.submit(CombatCommands.practice({"force_attack": "rare"}))
	assert_eq(events[0], {"type": "practice_changed", "invulnerable_party": false, "immortal_enemies": false, "force_attack": "rare"})
	assert_eq(engine.practice.force_attack, "rare")
	var declared: Array[String] = []
	for i: int in 200:
		if declared.size() >= 3 or engine.phase == CombatEngine.Phase.ENDED:
			break
		events = engine.submit(bot.next_command(engine))
		for e: Dictionary in Fx.of_type(events, "timed_sequence_declared"):
			declared.append(String(e.action))
			if e.action == "rare":
				assert_eq(engine.practice.force_attack, "", "cleared once used")
				var changed := Fx.first_of(events, "practice_changed")
				assert_eq(changed.get("force_attack", "missing"), "", "the clear is announced so mirrors stay in sync")
	assert_eq(declared, ["rare", "common", "common"])


func test_unknown_force_attack_is_rejected() -> void:
	var engine := Fx.started([_swipe()], {"practice": true})
	_assert_rejected_atomically(engine, CombatCommands.practice({"force_attack": "nope"}), "unknown_attack")
	_assert_rejected_atomically(engine, CombatCommands.practice({"force_attack": "nope", "invulnerable_party": true}), "unknown_attack")
	var events := engine.submit(CombatCommands.practice({"force_attack": ""}))
	assert_eq(events[0].type, "practice_changed", "an empty id clears the forced attack")


# --- payload hygiene (DESIGN 4.3) -------------------------------------------------------------

func test_mutating_returned_events_does_not_change_the_engine() -> void:
	var options := {"seed": 9, "practice": true}
	var attacks := [_mixed_party_attack(), _flurry()]
	var touched := CombatEngine.new(Fx.setup(attacks, options))
	var clean := CombatEngine.new(Fx.setup(attacks, options))
	var bot := Bot.new(Bot.Defence.MIXED, 0, true)
	var shadow := Bot.new(Bot.Defence.MIXED, 0, true)
	var got := touched.start()
	var want := clean.start()
	assert_eq(got, want)
	var steps := 0
	while touched.phase != CombatEngine.Phase.ENDED and steps < 2000:
		var before := touched.snapshot()
		Fx.scramble(got)
		assert_true(touched.snapshot() == before, "scrambling events at step %d left the engine alone" % steps)
		var command := bot.next_command(touched)
		var command_copy := shadow.next_command(clean)
		got = touched.submit(command)
		Fx.scramble(command)
		want = clean.submit(command_copy)
		if not (got == want):
			fail_test("events diverged at step %d" % steps)
			return
		steps += 1
	assert_eq(touched.phase, CombatEngine.Phase.ENDED, "the fight finished")
	assert_true(touched.snapshot() == clean.snapshot())


func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


func _expected_keys(list: Array, with_type: bool) -> Array:
	var keys := list.duplicate()
	if with_type:
		keys.append("type")
	keys.sort()
	return keys


func test_events_have_exactly_the_documented_fields() -> void:
	var events: Array[Dictionary] = []
	for defence: int in [Bot.Defence.PERFECT, Bot.Defence.MISS, Bot.Defence.MIXED]:
		for seed_value: int in [2, 13]:
			var run: Dictionary = Bot.new(defence as Bot.Defence, 1, true).play(CombatEngine.new(Fx.shipped_setup(seed_value, null, true)))
			events.append_array(run.events)
	events.append_array(Fx.started([_swipe()]).submit({"type": "dance"}))
	var seen := {}
	for i: int in events.size():
		var e: Dictionary = events[i]
		var type := String(e.type)
		seen[type] = true
		if not EVENT_KEYS.has(type):
			fail_test("undocumented event type '%s'" % type)
			return
		if _sorted_keys(e) != _expected_keys(EVENT_KEYS[type], true):
			fail_test("%s has fields %s, documented %s" % [type, str(_sorted_keys(e)), str(_expected_keys(EVENT_KEYS[type], true))])
			return
		for field: String in e:
			var allowed: Array = STRING_VALUES.get(type + "." + field, [])
			if not allowed.is_empty() and not allowed.has(e[field]):
				fail_test("%s.%s = '%s' is not one of %s" % [type, field, str(e[field]), str(allowed)])
				return
		if type == "counter":
			var next: Dictionary = events[i + 1]
			assert_eq(next.type, "damage", "a counter is followed by its damage event")
			assert_eq(next.cause, "team_counter" if bool(e.team) else "counter")
		if type == "timed_sequence_declared":
			for h: Dictionary in e.hits:
				assert_eq(_sorted_keys(h), _expected_keys(HIT_KEYS, false), "hit fields")
			for p: Dictionary in e.prompts:
				assert_eq(_sorted_keys(p), _expected_keys(PROMPT_KEYS, false), "prompt fields")
	for type: String in EVENT_KEYS:
		assert_true(seen.has(type), "the fights produced a %s event" % type)


func test_mutating_a_snapshot_does_not_change_the_engine() -> void:
	var engine := Fx.started([_mixed_party_attack()])
	var before := engine.snapshot()
	var snap := engine.snapshot()
	Fx.scramble(snap)
	assert_eq(engine.snapshot(), before)


func test_events_hold_only_plain_values() -> void:
	var runs: Array[Dictionary] = []
	for defence: int in [Bot.Defence.PERFECT, Bot.Defence.MISS, Bot.Defence.MIXED]:
		runs.append(Bot.new(defence as Bot.Defence, 0, true).play(CombatEngine.new(Fx.shipped_setup(4, null, true))))
	var engine := Fx.started([_swipe()])
	var rejected: Array[Dictionary] = []
	rejected.append_array(engine.submit({"type": "dance", "payload": [1, {"a": "b"}]}))
	rejected.append_array(engine.submit(Fx.resolve(9, [[0, PARRY]])))
	runs.append({"events": rejected})
	var checked := 0
	for run: Dictionary in runs:
		for e: Dictionary in run.events:
			var bad := Fx.find_illegal_value(e, String(e.type))
			if not bad.is_empty():
				fail_test("illegal payload value: " + bad)
				return
			checked += 1
	assert_gt(checked, 100, "checked a meaningful number of events")
