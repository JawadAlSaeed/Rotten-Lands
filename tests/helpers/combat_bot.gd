extends RefCounted
## Scripted player for tests. Every decision depends only on the engine's state and the settings
## below, so two bots on two engines with the same setup send identical commands.
## Party turns: Heavy Strike when affordable, otherwise the basic attack, on the first living
## enemy. Enemy attacks: the prompts of the next hit, answered according to `defence`.

enum Defence {
	## Parry normal hits, jump ground hits.
	PERFECT,
	## Never defend.
	MISS,
	## A fixed mix of perfect, missed and dodged prompts.
	MIXED,
	## Always dodge (fails against ground hits).
	DODGE,
}

const MAX_STEPS: int = 5000

var defence: Defence = Defence.PERFECT
## Prompts per resolve_prompts command. 0 = every pending prompt of the next hit at once.
var chunk: int = 0
## Send a practice command every few party turns (the setup must allow practice).
var use_practice: bool = false

var _practiced_turn: int = -1


func _init(p_defence: Defence = Defence.PERFECT, p_chunk: int = 0, p_practice: bool = false) -> void:
	defence = p_defence
	chunk = p_chunk
	use_practice = p_practice


## Starts the fight and plays it to the end (at most MAX_STEPS commands).
## Returns {events: Array[Dictionary], commands: Array[Dictionary], rejected: Array[Dictionary]}.
## `events` holds every event in order, starting with the ones from start().
func play(engine: CombatEngine) -> Dictionary:
	var events: Array[Dictionary] = []
	events.append_array(engine.start())
	var commands: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	for _step: int in MAX_STEPS:
		if engine.phase == CombatEngine.Phase.ENDED:
			break
		var command := next_command(engine)
		if command.is_empty():
			break
		commands.append(command)
		var out := engine.submit(command)
		for e: Dictionary in out:
			if String(e.type) == "command_rejected":
				rejected.append(e)
		events.append_array(out)
	return {"events": events, "commands": commands, "rejected": rejected}


## The command this bot sends in the engine's current state ({} if it has nothing to do).
func next_command(engine: CombatEngine) -> Dictionary:
	match engine.phase:
		CombatEngine.Phase.AWAITING_ACTION:
			if use_practice and _practiced_turn != engine.turn_number and engine.turn_number % 4 == 0:
				_practiced_turn = engine.turn_number
				return _practice_command(engine)
			return _action_command(engine)
		CombatEngine.Phase.AWAITING_TIMING:
			return _resolve_command(engine)
	return {}


func _action_command(engine: CombatEngine) -> Dictionary:
	var actor := engine.get_combatant(engine.active_actor)
	var ability_id := "basic_attack"
	if actor.ability_ids.has("heavy_strike") and engine.can_afford(actor.id, "heavy_strike"):
		ability_id = "heavy_strike"
	elif not actor.ability_ids.has(ability_id):
		ability_id = actor.ability_ids[0]
	var targets: Array[int] = [engine.living_enemy_ids()[0]]
	return CombatCommands.use_ability(engine.turn_number, actor.id, ability_id, targets)


## Answers the pending prompts of the earliest unresolved hit (or the first `chunk` of them).
## Taking the lowest pending prompts keeps every character's prompts in order.
func _resolve_command(engine: CombatEngine) -> Dictionary:
	var pending := engine.pending_prompts()
	if pending.is_empty():
		return {}
	var prompts: Array = engine.sequence.prompts
	var seq := int(engine.sequence.seq)
	var hit := int((prompts[pending[0]] as Dictionary).hit)
	var results: Array[Dictionary] = []
	for idx: int in pending:
		var prompt: Dictionary = prompts[idx]
		if int(prompt.hit) != hit:
			break
		results.append(CombatCommands.prompt_result(idx, _outcome_for(seq, prompt), _offset_for(seq, idx)))
		if chunk > 0 and results.size() >= chunk:
			break
	return CombatCommands.resolve_prompts(seq, results)


func _outcome_for(seq: int, prompt: Dictionary) -> int:
	var perfect: Array = prompt.perfect
	var best: int = Defense.Outcome.NONE if perfect.is_empty() else int(perfect[0])
	match defence:
		Defence.PERFECT:
			return best
		Defence.MISS:
			return Defense.Outcome.NONE
		Defence.DODGE:
			return Defense.Outcome.DODGE
	var roll := (seq * 7 + int(prompt.idx) * 3 + int(prompt.character)) % 5
	if roll <= 2:
		return best
	if roll == 3:
		return Defense.Outcome.NONE
	return Defense.Outcome.DODGE


## A made-up but deterministic press offset, so offsets travel through the events.
func _offset_for(seq: int, idx: int) -> int:
	return ((seq * 31 + idx * 17) % 101 - 50) * 1000


func _practice_command(engine: CombatEngine) -> Dictionary:
	var foe := engine.get_combatant(engine.living_enemy_ids()[0])
	@warning_ignore("integer_division")
	var cycle := engine.turn_number / 4
	return CombatCommands.practice({
		"force_attack": foe.attack_ids[cycle % foe.attack_ids.size()],
		"invulnerable_party": cycle % 3 == 1,
		"immortal_enemies": cycle % 5 == 2,
	})
