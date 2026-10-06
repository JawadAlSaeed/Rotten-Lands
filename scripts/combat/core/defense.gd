class_name Defense
extends RefCounted
## Defence outcomes and the one place that decides which defence works against which hit.
## The engine builds each prompt's windows here and validates results here, so what a client's
## judge accepts and what the host accepts can never drift apart.
## The same enum is used for the three defence buttons (DODGE, PARRY, JUMP).

enum Outcome {
	## No (successful) defence: the hit connects.
	NONE,
	DODGE,
	PARRY,
	JUMP,
}


## Actions that work against a hit kind, each with its window edges in microseconds relative to
## impact: {Outcome: [early_us (negative), late_us]}. Plain arrays so events stay serialisable.
## Phase 4 passives that change windows per character plug in here.
static func build_windows(kind: int, tuning: Tuning) -> Dictionary:
	var windows: Dictionary = {}
	if kind == AttackHitData.Kind.NORMAL:
		var dodge: Vector2i = tuning.window_edges_us(tuning.dodge_window_ms)
		var parry: Vector2i = tuning.window_edges_us(tuning.parry_window_ms)
		windows[Outcome.DODGE] = [dodge.x, dodge.y]
		windows[Outcome.PARRY] = [parry.x, parry.y]
	elif kind == AttackHitData.Kind.GROUND:
		var jump: Vector2i = tuning.window_edges_us(tuning.jump_window_ms)
		windows[Outcome.JUMP] = [jump.x, jump.y]
	return windows


## Outcomes that count toward a counterattack for this hit kind.
static func perfect_outcomes(kind: int) -> Array[int]:
	var list: Array[int] = []
	if kind == AttackHitData.Kind.NORMAL:
		list.append(Outcome.PARRY)
	elif kind == AttackHitData.Kind.GROUND:
		list.append(Outcome.JUMP)
	return list


## The outcome if the prompt allows it, otherwise NONE.
static func sanitize(outcome: int, windows: Dictionary) -> int:
	if outcome != Outcome.NONE and windows.has(outcome):
		return outcome
	return Outcome.NONE


## AP earned for a successful defence.
static func ap_reward(outcome: int, tuning: Tuning) -> int:
	match outcome:
		Outcome.PARRY:
			return tuning.ap_per_parry
		Outcome.JUMP:
			return tuning.ap_per_jump
	return 0


static func outcome_name(outcome: int) -> String:
	match outcome:
		Outcome.DODGE:
			return "dodge"
		Outcome.PARRY:
			return "parry"
		Outcome.JUMP:
			return "jump"
	return "none"
