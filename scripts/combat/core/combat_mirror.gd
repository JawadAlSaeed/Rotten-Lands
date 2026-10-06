class_name CombatMirror
extends RefCounted
## What the presentation knows about a fight, built only by applying events in playback order.
## The HUD and views read this, never the engine, so:
## - bars change when the matching animation plays, not when the engine already moved on;
## - network clients (phase 5), which have no engine, use exactly the same code.
## Pure: no nodes, no time.

## id -> {id, team, slot, data_id, display_name, max_hp, hp, ap, power, speed, alive}
var fighters: Dictionary = {}
var party_ids: Array[int] = []
var enemy_ids: Array[int] = []
var turn: int = 0
var active_actor: int = -1
var turn_order: Array[int] = []
## The last declared timed sequence, with "states" and "outcomes" kept up to date.
var sequence: Dictionary = {}
var result: String = ""
var practice: Dictionary = {"invulnerable_party": false, "immortal_enemies": false, "force_attack": ""}
var practice_allowed: bool = false
var seed_value: int = 0


func apply(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"combat_started":
			fighters.clear()
			party_ids.clear()
			enemy_ids.clear()
			seed_value = int(event.seed)
			practice_allowed = bool(event.practice_allowed)
			for d: Dictionary in event.fighters:
				var f := {
					"id": int(d.id),
					"team": int(d.team),
					"slot": int(d.slot),
					"data_id": String(d.data_id),
					"display_name": String(d.display_name),
					"max_hp": int(d.max_hp),
					"hp": int(d.hp),
					"ap": int(d.ap),
					"power": int(d.power),
					"speed": int(d.speed),
					"alive": int(d.hp) > 0,
				}
				fighters[f.id] = f
				if f.team == Combatant.Team.PARTY:
					party_ids.append(f.id)
				else:
					enemy_ids.append(f.id)
		"turn_started":
			turn = int(event.turn)
			active_actor = int(event.actor)
		"turn_order":
			turn_order.assign(event.order)
		"damage":
			_set_hp(int(event.target), int(event.hp))
		"downed":
			_set_hp(int(event.target), 0)
		"ap_changed":
			fighter(int(event.character)).ap = int(event.ap)
		"timed_sequence_declared":
			sequence = event.duplicate(true)
			var states: Array[int] = []
			var outcomes: Array[int] = []
			for i: int in (event.prompts as Array).size():
				states.append(CombatEngine.PromptState.PENDING)
				outcomes.append(Defense.Outcome.NONE)
			sequence["states"] = states
			sequence["outcomes"] = outcomes
		"prompt_resolved":
			var f := fighter(int(event.character))
			f.hp = int(event.hp)
			f.alive = f.hp > 0
			f.ap = int(event.ap)
			if _is_current(event):
				sequence.states[int(event.prompt)] = CombatEngine.PromptState.RESOLVED
				sequence.outcomes[int(event.prompt)] = int(event.outcome)
		"prompts_voided":
			if _is_current(event):
				for idx: int in event.prompts:
					sequence.states[idx] = CombatEngine.PromptState.VOID
		"turn_ended":
			if active_actor == int(event.actor):
				active_actor = -1
		"practice_changed":
			practice = {
				"invulnerable_party": bool(event.invulnerable_party),
				"immortal_enemies": bool(event.immortal_enemies),
				"force_attack": String(event.force_attack),
			}
		"combat_ended":
			result = String(event.result)
			active_actor = -1


func fighter(id: int) -> Dictionary:
	return fighters.get(id, {})


func is_alive(id: int) -> bool:
	return bool(fighter(id).get("alive", false))


func living_party_ids() -> Array[int]:
	return _living(party_ids)


func living_enemy_ids() -> Array[int]:
	return _living(enemy_ids)


func _living(ids: Array[int]) -> Array[int]:
	var list: Array[int] = []
	for id: int in ids:
		if is_alive(id):
			list.append(id)
	return list


## The fields the mirror tracks, in a shape comparable with project_snapshot().
func projection() -> Dictionary:
	var hp: Dictionary = {}
	var ap: Dictionary = {}
	for id: int in fighters:
		hp[id] = int(fighters[id].hp)
		ap[id] = int(fighters[id].ap)
	return {"hp": hp, "ap": ap, "result": result, "practice": practice.duplicate()}


## The same projection taken from CombatEngine.snapshot(), for tests.
static func project_snapshot(snap: Dictionary) -> Dictionary:
	var hp: Dictionary = {}
	var ap: Dictionary = {}
	for d: Dictionary in snap.combatants:
		hp[int(d.id)] = int(d.hp)
		ap[int(d.id)] = int(d.ap)
	return {"hp": hp, "ap": ap, "result": String(snap.result), "practice": (snap.practice as Dictionary).duplicate()}


func _set_hp(id: int, hp: int) -> void:
	var f := fighter(id)
	if f.is_empty():
		return
	f.hp = hp
	f.alive = hp > 0


func _is_current(event: Dictionary) -> bool:
	return not sequence.is_empty() and int(sequence.seq) == int(event.seq)
