class_name CombatCommands
extends RefCounted
## Builders for the commands CombatEngine.submit() accepts. Commands are plain Dictionaries
## holding only ints, bools, Strings and arrays/dictionaries of those, so they can be logged,
## replayed and sent over the network unchanged.

const USE_ABILITY := "use_ability"
const RESOLVE_PROMPTS := "resolve_prompts"
const PRACTICE := "practice"


## A party member uses an ability on their turn. `turn` must match the engine's current turn
## number, so a duplicated or late command cannot act twice.
## `targets` are combatant ids (ignored for all-enemy abilities).
static func use_ability(turn: int, actor: int, ability_id: String, targets: Array[int]) -> Dictionary:
	return {
		"type": USE_ABILITY,
		"turn": turn,
		"actor": actor,
		"ability": ability_id,
		"targets": targets.duplicate(),
	}


## Results for some prompts of the current timed sequence. Each result:
## {prompt: int, outcome: Defense.Outcome, offset_us: int (press time - impact, 0 if no press)}.
## Partial is fine: prompts not listed stay pending.
static func resolve_prompts(seq: int, results: Array[Dictionary]) -> Dictionary:
	return {
		"type": RESOLVE_PROMPTS,
		"seq": seq,
		"results": results.duplicate(true),
	}


## One result entry for resolve_prompts().
static func prompt_result(prompt_idx: int, outcome: int, offset_us: int = 0) -> Dictionary:
	return {"prompt": prompt_idx, "outcome": outcome, "offset_us": offset_us}


## Practice tools (only accepted when the setup allows practice). Every key is optional:
## invulnerable_party: bool, immortal_enemies: bool, force_attack: String ("" clears it).
static func practice(options: Dictionary) -> Dictionary:
	var cmd := options.duplicate(true)
	cmd["type"] = PRACTICE
	return cmd
