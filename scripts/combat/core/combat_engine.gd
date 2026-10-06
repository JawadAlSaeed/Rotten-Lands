class_name CombatEngine
extends RefCounted
## Deterministic combat state machine. The only way to change a fight is submit(command), which
## returns the events that happened. Same setup + same seed + same commands = same events.
##
## Rules for this file and everything in scripts/combat/core/:
## no Nodes, no Input, no Time, no randi()/randf(), no floats in rules. Randomness comes from
## `rng` only. Events and commands hold only ints, bools, Strings and arrays/dictionaries of
## those, built fresh (never shared with internal state).
##
## Timed sequences: anything resolved in real time is a "timed sequence" made of prompts. A prompt
## is one (moment, character) pair with the actions it accepts and their windows. In phase 1 the
## only sequence kind is "enemy_attack" (one prompt per hit per target). Phase 2 adds skill presses
## and follow-up strikes as more kinds. Prompts name characters, never players; deciding which
## player answers which prompt is the controller's job.
##
## Commands (build them with CombatCommands):
##   use_ability      {turn, actor, ability, targets}            phase AWAITING_ACTION
##   resolve_prompts  {seq, results:[{prompt, outcome, offset_us}]}  phase AWAITING_TIMING
##                    partial is fine; per character, prompts must resolve in order
##   practice         {invulnerable_party?, immortal_enemies?, force_attack?}  if setup allows
##
## Events (Dictionary with "type"):
##   combat_started          {seed, fighters:[Combatant.to_dict()], practice_allowed}
##   turn_started            {turn, actor, team, time}
##   turn_order              {order:[id]}      current actor first, then upcoming turns
##   ability_used            {turn, actor, ability, targets:[id]}
##   damage                  {source, target, amount, hp, max_hp, cause}
##                           cause: "ability" | "counter" | "team_counter"
##   downed                  {target}
##   ap_changed              {character, delta, ap, reason}    reason: "spend" | "ability"
##   timed_sequence_declared {seq, kind, source, action, name, mode, targets:[id],
##                            alert_cue, allow_timing_ring, hits:[hit], prompts:[prompt]}
##       hit    = {index, at_ms, kind, approach_ms, feint, damage_percent, impact_sfx}
##       prompt = {idx, hit, character, at_ms, kind, windows:{Outcome:[early_us, late_us]},
##                 perfect:[Outcome], damage}
##       at_ms already includes tuning attack_tempo_percent; damage is pre-rolled.
##   prompt_resolved         {seq, prompt, hit, character, outcome, perfect, offset_us,
##                            damage, hp, max_hp, ap, ap_delta, downed}
##                           damage is what the hit would deal (0 if avoided); hp/ap are after.
##   prompts_voided          {seq, prompts:[idx], reason}      reason: "downed" | "attacker_down"
##   sequence_resolved       {seq, reason}   boundary: every prompt is done. Counters follow.
##                           reason: "completed" | "targets_down" | "attacker_down"
##   counter                 {seq, actors:[id], target, team}  followed by a damage event
##   turn_ended              {turn, actor}
##   practice_changed        {invulnerable_party, immortal_enemies, force_attack}
##                           also emitted (before timed_sequence_declared) when a forced
##                           attack is used and force_attack clears
##   combat_ended            {result}        "victory" | "defeat"
##   command_rejected        {reason, command}   private to the sender; never broadcast/replayed

enum Phase {
	NOT_STARTED,
	## A party member (active_actor) must choose an action.
	AWAITING_ACTION,
	## The current timed sequence (`sequence`) has prompts waiting for results.
	AWAITING_TIMING,
	ENDED,
}

enum PromptState {
	PENDING,
	RESOLVED,
	## Cancelled (its character went down). Counts as not perfect.
	VOID,
}

const SEQUENCE_ENEMY_ATTACK := "enemy_attack"
const MAX_AUTO_TURNS: int = 1000

var phase: Phase = Phase.NOT_STARTED
var tuning: Tuning
var rng: CombatRng
var combatants: Array[Combatant] = []
## Id of the combatant whose turn it is, or -1.
var active_actor: int = -1
## Timeline position of the current turn (used for revives and speed changes later).
var time_now: int = 0
## Increases by one every turn; use_ability must quote it.
var turn_number: int = 0
## Last timed sequence number handed out.
var sequence_counter: int = 0
## The timed sequence being resolved (empty when none). Keys: seq, kind, source, action, mode,
## targets, hits, prompts, states (Array of PromptState), outcomes (Array of Defense.Outcome).
var sequence: Dictionary = {}
## "victory" or "defeat" once the fight is over.
var result: String = ""
## Practice options (only changeable when the setup allows practice).
var practice: Dictionary = {"invulnerable_party": false, "immortal_enemies": false, "force_attack": ""}

var _setup: CombatSetup
var _abilities: Dictionary = {}
var _attacks: Dictionary = {}


func _init(setup: CombatSetup) -> void:
	_setup = setup
	tuning = setup.tuning
	rng = CombatRng.new(setup.rng_seed)


## Builds the fighters and runs until the first decision is needed.
func start() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if phase != Phase.NOT_STARTED:
		events.append(_reject("already_started", {}))
		return events
	var problems := _setup.validate()
	if not problems.is_empty():
		events.append(_reject("invalid_setup: " + ", ".join(problems), {}))
		return events
	_build_lookups()
	_build_combatants()
	var fighters: Array[Dictionary] = []
	for c: Combatant in combatants:
		fighters.append(c.to_dict())
	events.append({
		"type": "combat_started",
		"seed": _setup.rng_seed,
		"fighters": fighters,
		"practice_allowed": _setup.allow_practice,
	})
	_advance_turn(events)
	return events


## Applies one command. Invalid commands change nothing and return one command_rejected event.
func submit(command: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match String(command.get("type", "")):
		CombatCommands.USE_ABILITY:
			_cmd_use_ability(command, events)
		CombatCommands.RESOLVE_PROMPTS:
			_cmd_resolve_prompts(command, events)
		CombatCommands.PRACTICE:
			_cmd_practice(command, events)
		_:
			events.append(_reject("unknown_command", command))
	return events


## Rebuilds an engine from snapshot() output (reconnects, late join, desync debugging).
static func restore(setup: CombatSetup, snap: Dictionary) -> CombatEngine:
	var engine := CombatEngine.new(setup)
	engine._build_lookups()
	for d: Dictionary in snap.combatants:
		engine.combatants.append(Combatant.from_dict(d))
	engine.phase = int(snap.phase) as Phase
	engine.active_actor = int(snap.active_actor)
	engine.time_now = int(snap.time_now)
	engine.turn_number = int(snap.turn_number)
	engine.sequence_counter = int(snap.sequence_counter)
	engine.sequence = (snap.sequence as Dictionary).duplicate(true)
	engine.result = String(snap.result)
	engine.practice = (snap.practice as Dictionary).duplicate(true)
	engine.rng.state = int(snap.rng_state)
	return engine


# --- queries ----------------------------------------------------------------------------------

func get_combatant(id: int) -> Combatant:
	if id < 0 or id >= combatants.size():
		return null
	return combatants[id]


func party_ids() -> Array[int]:
	return _ids_of_team(Combatant.Team.PARTY, false)


func enemy_ids() -> Array[int]:
	return _ids_of_team(Combatant.Team.ENEMY, false)


func living_party_ids() -> Array[int]:
	return _ids_of_team(Combatant.Team.PARTY, true)


func living_enemy_ids() -> Array[int]:
	return _ids_of_team(Combatant.Team.ENEMY, true)


func get_ability(ability_id: String) -> AbilityData:
	return _abilities.get(ability_id) as AbilityData


func get_attack(attack_id: String) -> EnemyAttackData:
	return _attacks.get(attack_id) as EnemyAttackData


## True if the actor has enough AP for this ability (ignores whose turn it is).
func can_afford(actor_id: int, ability_id: String) -> bool:
	var actor := get_combatant(actor_id)
	var ability := get_ability(ability_id)
	return actor != null and ability != null and actor.ap >= ability.ap_cost


## Indices of prompts still waiting for a result.
func pending_prompts() -> Array[int]:
	var list: Array[int] = []
	if sequence.is_empty():
		return list
	var states: Array = sequence.states
	for i: int in states.size():
		if int(states[i]) == PromptState.PENDING:
			list.append(i)
	return list


## Current actor first, then the next turns.
func preview_turn_order(count: int) -> Array[int]:
	var order: Array[int] = []
	var current := get_combatant(active_actor)
	if current != null and current.is_alive():
		order.append(active_actor)
	order.append_array(Timeline.preview(combatants, maxi(0, count - order.size()), tuning.timeline_base))
	return order


## Full state as plain data (deep copy), for determinism checks, restore and network sync.
func snapshot() -> Dictionary:
	var fighters: Array[Dictionary] = []
	for c: Combatant in combatants:
		fighters.append(c.to_dict())
	return {
		"phase": phase,
		"combatants": fighters,
		"active_actor": active_actor,
		"time_now": time_now,
		"turn_number": turn_number,
		"sequence_counter": sequence_counter,
		"sequence": sequence.duplicate(true),
		"result": result,
		"practice": practice.duplicate(true),
		"rng_state": rng.state,
	}


# --- building ---------------------------------------------------------------------------------

func _build_lookups() -> void:
	_abilities.clear()
	_attacks.clear()
	for data: CharacterData in _setup.party:
		for ability: AbilityData in data.all_abilities():
			_abilities[ability.id] = ability
	for data: EnemyData in _setup.enemies:
		for attack: EnemyAttackData in data.attacks:
			_attacks[attack.id] = attack


func _build_combatants() -> void:
	combatants.clear()
	var slot := 0
	for data: CharacterData in _setup.party:
		var c := Combatant.new()
		c.id = combatants.size()
		c.team = Combatant.Team.PARTY
		c.slot = slot
		c.data_id = data.id
		c.display_name = data.display_name
		c.max_hp = CombatMath.percent_min1(tuning.base_character_hp, data.hp_percent)
		c.hp = c.max_hp
		c.ap = clampi(tuning.start_ap, 0, tuning.max_ap)
		c.power = CombatMath.percent_min1(tuning.base_party_damage, data.power_percent)
		c.speed = maxi(1, data.speed)
		for ability: AbilityData in data.all_abilities():
			c.ability_ids.append(ability.id)
		c.next_turn_at = Timeline.turn_cost(c.speed, tuning.timeline_base)
		combatants.append(c)
		slot += 1
	slot = 0
	for data: EnemyData in _setup.enemies:
		var c := Combatant.new()
		c.id = combatants.size()
		c.team = Combatant.Team.ENEMY
		c.slot = slot
		c.data_id = data.id
		c.display_name = data.display_name
		c.max_hp = CombatMath.percent_min1(tuning.base_enemy_hp, data.hp_percent)
		c.hp = c.max_hp
		c.power = CombatMath.percent_min1(tuning.base_enemy_hit_damage, data.power_percent)
		c.speed = maxi(1, data.speed)
		for attack: EnemyAttackData in data.attacks:
			c.attack_ids.append(attack.id)
		c.next_turn_at = Timeline.turn_cost(c.speed, tuning.timeline_base)
		combatants.append(c)
		slot += 1


# --- turn flow --------------------------------------------------------------------------------

## Moves the timeline forward until a decision is needed or the fight ends.
func _advance_turn(events: Array[Dictionary]) -> void:
	for _guard: int in MAX_AUTO_TURNS:
		if _check_end(events):
			return
		var actor := Timeline.next_actor(combatants)
		time_now = actor.next_turn_at
		actor.next_turn_at += Timeline.turn_cost(actor.speed, tuning.timeline_base)
		turn_number += 1
		active_actor = actor.id
		events.append({"type": "turn_started", "turn": turn_number, "actor": actor.id, "team": actor.team, "time": time_now})
		events.append({"type": "turn_order", "order": preview_turn_order(tuning.turn_order_preview)})
		if actor.is_party():
			phase = Phase.AWAITING_ACTION
			return
		if _begin_enemy_attack(actor, events):
			return
		# The enemy had nothing it could do; its turn passes.
		events.append({"type": "turn_ended", "turn": turn_number, "actor": actor.id})
	push_warning("CombatEngine: turn guard reached; nobody can act")


## Declares the enemy's attack as a timed sequence. Returns false if it has no usable attack.
func _begin_enemy_attack(actor: Combatant, events: Array[Dictionary]) -> bool:
	var attack: EnemyAttackData = null
	var forced := String(practice.force_attack)
	if not forced.is_empty() and actor.attack_ids.has(forced):
		attack = get_attack(forced)
		practice.force_attack = ""
		# Announce the clear, or mirrors (HUD practice status) would keep showing the forced attack.
		events.append(_practice_changed_event())
	else:
		var choices: Array[EnemyAttackData] = []
		var weights: Array[int] = []
		for attack_id: String in actor.attack_ids:
			var candidate := get_attack(attack_id)
			if candidate != null and not candidate.hits.is_empty() and candidate.weight > 0:
				choices.append(candidate)
				weights.append(candidate.weight)
		var pick := rng.pick_weighted(weights)
		if pick >= 0:
			attack = choices[pick]
	if attack == null:
		return false

	var living := living_party_ids()
	var targets: Array[int] = []
	if attack.target_mode == EnemyAttackData.TargetMode.PARTY:
		targets = living
	else:
		targets.append(living[rng.range_int(0, living.size() - 1)])

	var hits: Array[Dictionary] = []
	var prompts: Array[Dictionary] = []
	for hit_index: int in attack.hits.size():
		var hit: AttackHitData = attack.hits[hit_index]
		var at_ms := CombatMath.percent(hit.impact_ms, tuning.attack_tempo_percent)
		hits.append({
			"index": hit_index,
			"at_ms": at_ms,
			"kind": hit.kind,
			"approach_ms": CombatMath.percent(hit.approach_ms, tuning.attack_tempo_percent),
			"feint": hit.feint,
			"damage_percent": hit.damage_percent,
			"impact_sfx": hit.impact_sfx,
		})
		for target_id: int in targets:
			prompts.append({
				"idx": prompts.size(),
				"hit": hit_index,
				"character": target_id,
				"at_ms": at_ms,
				"kind": hit.kind,
				"windows": Defense.build_windows(hit.kind, tuning),
				"perfect": Defense.perfect_outcomes(hit.kind),
				"damage": _roll_damage(actor.power, hit.damage_percent),
			})
	var states: Array[int] = []
	var outcomes: Array[int] = []
	for i: int in prompts.size():
		states.append(PromptState.PENDING)
		outcomes.append(Defense.Outcome.NONE)

	sequence_counter += 1
	sequence = {
		"seq": sequence_counter,
		"kind": SEQUENCE_ENEMY_ATTACK,
		"source": actor.id,
		"action": attack.id,
		"mode": attack.target_mode,
		"targets": targets.duplicate(),
		"hits": hits.duplicate(true),
		"prompts": prompts.duplicate(true),
		"states": states,
		"outcomes": outcomes,
	}
	phase = Phase.AWAITING_TIMING
	events.append({
		"type": "timed_sequence_declared",
		"seq": sequence_counter,
		"kind": SEQUENCE_ENEMY_ATTACK,
		"source": actor.id,
		"action": attack.id,
		"name": attack.display_name,
		"mode": attack.target_mode,
		"targets": targets.duplicate(),
		"alert_cue": attack.alert_cue,
		"allow_timing_ring": attack.allow_timing_ring,
		"hits": hits.duplicate(true),
		"prompts": prompts.duplicate(true),
	})
	return true


## Emits combat_ended and returns true if one side is wiped out.
func _check_end(events: Array[Dictionary]) -> bool:
	if phase == Phase.ENDED:
		return true
	var outcome := ""
	if living_enemy_ids().is_empty():
		outcome = "victory"
	elif living_party_ids().is_empty():
		outcome = "defeat"
	if outcome.is_empty():
		return false
	result = outcome
	phase = Phase.ENDED
	active_actor = -1
	sequence = {}
	events.append({"type": "combat_ended", "result": outcome})
	return true


# --- commands ---------------------------------------------------------------------------------

func _cmd_use_ability(command: Dictionary, events: Array[Dictionary]) -> void:
	if phase != Phase.AWAITING_ACTION:
		events.append(_reject("not_awaiting_action", command))
		return
	if int(command.get("turn", -1)) != turn_number:
		events.append(_reject("wrong_turn", command))
		return
	var actor_id := int(command.get("actor", -1))
	if actor_id != active_actor:
		events.append(_reject("not_this_actors_turn", command))
		return
	var actor := get_combatant(actor_id)
	var ability_id := String(command.get("ability", ""))
	if not actor.ability_ids.has(ability_id):
		events.append(_reject("unknown_ability", command))
		return
	var ability := get_ability(ability_id)
	if actor.ap < ability.ap_cost:
		events.append(_reject("not_enough_ap", command))
		return
	var targets: Array[int] = []
	match ability.target:
		AbilityData.Target.ALL_ENEMIES:
			targets = living_enemy_ids()
		_:
			var requested: Variant = command.get("targets", [])
			if typeof(requested) != TYPE_ARRAY or (requested as Array).size() != 1:
				events.append(_reject("needs_one_target", command))
				return
			var target := get_combatant(int((requested as Array)[0]))
			if target == null or target.is_party() or not target.is_alive():
				events.append(_reject("invalid_target", command))
				return
			targets.append(target.id)

	if ability.ap_cost > 0:
		_change_ap(actor, -ability.ap_cost, "spend", events)
	events.append({"type": "ability_used", "turn": turn_number, "actor": actor.id, "ability": ability.id, "targets": targets.duplicate()})
	for target_id: int in targets:
		var target := get_combatant(target_id)
		if target.is_alive():
			_deal_damage(actor, target, _roll_damage(actor.power, ability.damage_percent), "ability", events)
	if ability.ap_gain > 0:
		_change_ap(actor, ability.ap_gain, "ability", events)
	events.append({"type": "turn_ended", "turn": turn_number, "actor": actor.id})
	_advance_turn(events)


func _cmd_resolve_prompts(command: Dictionary, events: Array[Dictionary]) -> void:
	if phase != Phase.AWAITING_TIMING:
		events.append(_reject("not_awaiting_timing", command))
		return
	if int(command.get("seq", -1)) != int(sequence.seq):
		events.append(_reject("stale_sequence", command))
		return
	var raw: Variant = command.get("results", [])
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		events.append(_reject("no_results", command))
		return
	var prompts: Array = sequence.prompts
	var states: Array = sequence.states

	# Validate everything before changing anything.
	var items: Array[Dictionary] = []
	var included: Dictionary = {}
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			events.append(_reject("bad_result", command))
			return
		var idx := int((entry as Dictionary).get("prompt", -1))
		if idx < 0 or idx >= prompts.size():
			events.append(_reject("unknown_prompt", command))
			return
		if included.has(idx):
			events.append(_reject("duplicate_prompt", command))
			return
		if int(states[idx]) != PromptState.PENDING:
			events.append(_reject("stale_prompt", command))
			return
		included[idx] = true
		items.append({
			"idx": idx,
			"outcome": int((entry as Dictionary).get("outcome", Defense.Outcome.NONE)),
			"offset_us": int((entry as Dictionary).get("offset_us", 0)),
		})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.idx) < int(b.idx))
	for item: Dictionary in items:
		var character := int((prompts[item.idx] as Dictionary).character)
		for j: int in int(item.idx):
			if int((prompts[j] as Dictionary).character) == character \
					and int(states[j]) == PromptState.PENDING and not included.has(j):
				events.append(_reject("out_of_order", command))
				return

	for item: Dictionary in items:
		if int(states[item.idx]) != PromptState.PENDING:
			continue # voided earlier in this batch because its character went down
		_apply_prompt(item, events)
		_void_dead_prompts(events)
	_finish_sequence_if_done(events)


func _cmd_practice(command: Dictionary, events: Array[Dictionary]) -> void:
	if not _setup.allow_practice:
		events.append(_reject("practice_disabled", command))
		return
	if phase == Phase.NOT_STARTED or phase == Phase.ENDED:
		events.append(_reject("not_in_combat", command))
		return
	if command.has("force_attack"):
		var attack_id := String(command.force_attack)
		if not attack_id.is_empty() and not _attacks.has(attack_id):
			events.append(_reject("unknown_attack", command))
			return
	if command.has("invulnerable_party"):
		practice.invulnerable_party = bool(command.invulnerable_party)
	if command.has("immortal_enemies"):
		practice.immortal_enemies = bool(command.immortal_enemies)
	if command.has("force_attack"):
		practice.force_attack = String(command.force_attack)
	events.append(_practice_changed_event())


func _practice_changed_event() -> Dictionary:
	return {
		"type": "practice_changed",
		"invulnerable_party": practice.invulnerable_party,
		"immortal_enemies": practice.immortal_enemies,
		"force_attack": practice.force_attack,
	}


# --- timed sequence resolution ----------------------------------------------------------------

func _apply_prompt(item: Dictionary, events: Array[Dictionary]) -> void:
	var idx: int = item.idx
	var prompt: Dictionary = sequence.prompts[idx]
	var target := get_combatant(int(prompt.character))
	var outcome := Defense.sanitize(int(item.outcome), prompt.windows)
	sequence.states[idx] = PromptState.RESOLVED
	sequence.outcomes[idx] = outcome
	var damage := 0
	var ap_delta := 0
	if outcome != Defense.Outcome.NONE:
		ap_delta = _change_ap_silent(target, Defense.ap_reward(outcome, tuning))
	else:
		damage = int(prompt.damage)
		_lose_hp(target, damage)
	var downed := not target.is_alive()
	events.append({
		"type": "prompt_resolved",
		"seq": sequence.seq,
		"prompt": idx,
		"hit": prompt.hit,
		"character": target.id,
		"outcome": outcome,
		"perfect": (prompt.perfect as Array).has(outcome),
		"offset_us": int(item.offset_us),
		"damage": damage,
		"hp": target.hp,
		"max_hp": target.max_hp,
		"ap": target.ap,
		"ap_delta": ap_delta,
		"downed": downed,
	})
	if downed:
		events.append({"type": "downed", "target": target.id})


## Cancels pending prompts whose character is down, or all of them if the attacker is down.
func _void_dead_prompts(events: Array[Dictionary]) -> void:
	var attacker := get_combatant(int(sequence.source))
	var attacker_down := not attacker.is_alive()
	var voided: Array[int] = []
	var prompts: Array = sequence.prompts
	for i: int in prompts.size():
		if int(sequence.states[i]) != PromptState.PENDING:
			continue
		var character := get_combatant(int((prompts[i] as Dictionary).character))
		if attacker_down or not character.is_alive():
			sequence.states[i] = PromptState.VOID
			voided.append(i)
	if not voided.is_empty():
		events.append({
			"type": "prompts_voided",
			"seq": sequence.seq,
			"prompts": voided,
			"reason": "attacker_down" if attacker_down else "downed",
		})


func _finish_sequence_if_done(events: Array[Dictionary]) -> void:
	if not pending_prompts().is_empty():
		return
	var attacker := get_combatant(int(sequence.source))
	var any_standing := false
	for target_id: int in sequence.targets:
		if get_combatant(target_id).is_alive():
			any_standing = true
			break
	var reason := "completed"
	if not attacker.is_alive():
		reason = "attacker_down"
	elif not any_standing:
		reason = "targets_down"
	events.append({"type": "sequence_resolved", "seq": sequence.seq, "reason": reason})
	if reason == "completed":
		_resolve_counters(attacker, events)
	sequence = {}
	events.append({"type": "turn_ended", "turn": turn_number, "actor": attacker.id})
	_advance_turn(events)


## Counter for every target who perfectly defended all of their prompts. If the attack was
## party-wide and every target did, they strike together as one team counter instead.
func _resolve_counters(attacker: Combatant, events: Array[Dictionary]) -> void:
	if not attacker.is_alive():
		return
	var targets: Array = sequence.targets
	var counterers: Array[int] = []
	for target_id: int in targets:
		if get_combatant(target_id).is_alive() and _all_perfect(target_id):
			counterers.append(target_id)
	if counterers.is_empty():
		return
	var team := (
		int(sequence.mode) == EnemyAttackData.TargetMode.PARTY
		and targets.size() >= 2
		and counterers.size() == targets.size()
	)
	if team:
		var total := 0
		for actor_id: int in counterers:
			total += CombatMath.percent(get_combatant(actor_id).power, tuning.team_counter_percent)
		events.append({"type": "counter", "seq": sequence.seq, "actors": counterers.duplicate(), "target": attacker.id, "team": true})
		_deal_damage(get_combatant(counterers[0]), attacker, _apply_variance(maxi(1, total)), "team_counter", events)
		return
	for actor_id: int in counterers:
		if not attacker.is_alive():
			break
		var actor := get_combatant(actor_id)
		events.append({"type": "counter", "seq": sequence.seq, "actors": [actor_id], "target": attacker.id, "team": false})
		_deal_damage(actor, attacker, _roll_damage(actor.power, tuning.counter_percent), "counter", events)


func _all_perfect(character_id: int) -> bool:
	var prompts: Array = sequence.prompts
	var found := false
	for i: int in prompts.size():
		var prompt: Dictionary = prompts[i]
		if int(prompt.character) != character_id:
			continue
		found = true
		if int(sequence.states[i]) != PromptState.RESOLVED:
			return false
		if not (prompt.perfect as Array).has(int(sequence.outcomes[i])):
			return false
	return found


# --- helpers ----------------------------------------------------------------------------------

func _roll_damage(power: int, pct: int) -> int:
	return _apply_variance(CombatMath.percent_min1(power, pct))


func _apply_variance(amount: int) -> int:
	if tuning.damage_variance_percent <= 0:
		return maxi(1, amount)
	var spread := rng.range_int(-tuning.damage_variance_percent, tuning.damage_variance_percent)
	return CombatMath.percent_min1(amount, 100 + spread)


## Lowers HP, respecting practice floors. Returns the HP actually lost.
func _lose_hp(target: Combatant, amount: int) -> int:
	var floor_hp := 0
	if target.is_party() and practice.invulnerable_party:
		floor_hp = 1
	elif not target.is_party() and practice.immortal_enemies:
		floor_hp = 1
	var before := target.hp
	target.hp = maxi(mini(floor_hp, before), before - amount)
	return before - target.hp


func _deal_damage(source: Combatant, target: Combatant, amount: int, cause: String, events: Array[Dictionary]) -> void:
	_lose_hp(target, amount)
	events.append({
		"type": "damage",
		"source": source.id,
		"target": target.id,
		"amount": amount,
		"hp": target.hp,
		"max_hp": target.max_hp,
		"cause": cause,
	})
	if not target.is_alive():
		events.append({"type": "downed", "target": target.id})


func _change_ap(target: Combatant, delta: int, reason: String, events: Array[Dictionary]) -> void:
	var applied := _change_ap_silent(target, delta)
	if applied != 0:
		events.append({"type": "ap_changed", "character": target.id, "delta": applied, "ap": target.ap, "reason": reason})


## Changes AP within [0, max_ap] and returns the change actually applied.
func _change_ap_silent(target: Combatant, delta: int) -> int:
	var before := target.ap
	target.ap = clampi(target.ap + delta, 0, tuning.max_ap)
	return target.ap - before


func _ids_of_team(team: Combatant.Team, living_only: bool) -> Array[int]:
	var ids: Array[int] = []
	for c: Combatant in combatants:
		if c.team == team and (not living_only or c.is_alive()):
			ids.append(c.id)
	return ids


func _reject(reason: String, command: Dictionary) -> Dictionary:
	return {"type": "command_rejected", "reason": reason, "command": command.duplicate(true)}
