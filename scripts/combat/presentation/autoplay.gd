class_name Autoplay
extends Node
## Test bot for `-- --autoplay[=perfect|miss|mash]` (DESIGN.md 10). It plays through the same
## paths as a person: menu choices go through the ActionMenu, defence presses are injected into
## DefenseInput and judged like real ones.
## - perfect: the correct press for every hit (parry for normal, jump for ground) at window centre;
## - miss: never presses;
## - mash: random defence presses about every MASH_INTERVAL_MS.
## At the end it prints exactly one "AUTOPLAY_RESULT victory|defeat" line and one
## "AUTOPLAY_STATS ..." line.

## Pause before picking an action, so the menu is visible for a moment.
const CHOOSE_DELAY_MS: int = 250
const MASH_INTERVAL_MS: int = 70
const MASH_JITTER_MS: int = 20
const DEFENCE_ACTIONS: Array[int] = [Defense.Outcome.PARRY, Defense.Outcome.DODGE, Defense.Outcome.JUMP]

var _mode: String = CombatOptions.AUTOPLAY_PERFECT
var _mirror: CombatMirror
var _runner: TimedSequenceRunner
var _input: DefenseInput
var _menu: ActionMenu
var _tuning: Tuning
var _rng := RandomNumberGenerator.new()
var _seq: int = -1
var _pressed_hits: Dictionary = {}
var _next_mash_us: int = 0
var _last_frame_us: int = 0
var _frame_us: int = 0
var _reported: bool = false
var _stats: Dictionary = {
	"parries": 0, "dodges": 0, "jumps": 0, "whiffs": 0,
	"hits_taken": 0, "counters": 0, "team_counters": 0,
}


func setup(mode: String, mirror: CombatMirror, runner: TimedSequenceRunner, input: DefenseInput,
		menu: ActionMenu, tuning: Tuning) -> void:
	_mode = mode
	_mirror = mirror
	_runner = runner
	_input = input
	_menu = menu
	_tuning = tuning
	_rng.randomize()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_frame_us = now - _last_frame_us if _last_frame_us > 0 else 0
	_last_frame_us = now
	if not _runner.is_defending():
		return
	match _mode:
		CombatOptions.AUTOPLAY_PERFECT:
			_defend_perfectly()
		CombatOptions.AUTOPLAY_MASH:
			_mash()


## The controller opened the menu for this party member: pick Heavy Strike if affordable.
func on_menu_opened(actor_id: int) -> void:
	var turn := _mirror.turn
	# A Timer child: if the fight is freed the wait never resumes on a freed bot.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = float(CHOOSE_DELAY_MS) / 1000.0
	add_child(timer)
	timer.start()
	await timer.timeout
	timer.queue_free()
	if not _menu.is_open() or _mirror.turn != turn or _mirror.active_actor != actor_id:
		return
	var ap := int(_mirror.fighter(actor_id).get("ap", 0))
	var best := ""
	var best_cost := -1
	var basic := ""
	for ability: AbilityData in _menu_abilities():
		if ability.ap_cost == 0 and basic.is_empty():
			basic = ability.id
		elif ability.ap_cost > best_cost and ability.ap_cost <= ap:
			best = ability.id
			best_cost = ability.ap_cost
	var choice := best if not best.is_empty() else basic
	if choice.is_empty() or not _menu.choose(choice):
		print("AUTOPLAY_ERROR could not choose an ability for fighter %d" % actor_id)


func on_press_judged(action: int, report: Dictionary) -> void:
	match int(report.get("result", DefenseJudge.Result.DONE)):
		DefenseJudge.Result.SUCCESS:
			match action:
				Defense.Outcome.PARRY:
					_stats.parries += 1
				Defense.Outcome.DODGE:
					_stats.dodges += 1
				Defense.Outcome.JUMP:
					_stats.jumps += 1
		DefenseJudge.Result.WHIFF:
			_stats.whiffs += 1


func on_event(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"prompt_resolved":
			if int(event.outcome) == Defense.Outcome.NONE:
				_stats.hits_taken += 1
		"counter":
			if bool(event.team):
				_stats.team_counters += 1
			else:
				_stats.counters += 1


func on_combat_finished(result: String) -> void:
	if _reported:
		return
	_reported = true
	print("AUTOPLAY_RESULT %s" % result)
	print("AUTOPLAY_STATS parries=%d dodges=%d jumps=%d whiffs=%d hits_taken=%d counters=%d team_counters=%d" % [
			_stats.parries, _stats.dodges, _stats.jumps, _stats.whiffs,
			_stats.hits_taken, _stats.counters, _stats.team_counters])


## Presses the perfect action for the next hit when attack time reaches its window centre
## (plus the lag compensation the judge will subtract).
func _defend_perfectly() -> void:
	var sequence := _mirror.sequence
	if sequence.is_empty() or _runner.is_clock_paused():
		return
	if int(sequence.seq) != _seq:
		_seq = int(sequence.seq)
		_pressed_hits.clear()
	var t := _runner.attack_time_us()
	for hit: Dictionary in sequence.hits:
		var hit_index := int(hit.index)
		if _pressed_hits.has(hit_index):
			continue
		var prompt := _open_prompt(sequence, hit_index)
		if prompt.is_empty():
			_pressed_hits[hit_index] = true
			continue
		var action := int((prompt.perfect as Array)[0])
		var edges: Array = prompt.windows[action]
		@warning_ignore("integer_division")
		var centre := int(prompt.at_ms) * 1000 + (int(edges[0]) + int(edges[1])) / 2
		# Half a frame early: the press lands on average at the centre even when frames are slow.
		@warning_ignore("integer_division")
		var lead_us := _frame_us / 2
		if t + lead_us >= centre + _runner.latency_us():
			_pressed_hits[hit_index] = true
			_input.inject_press(action)
		return


func _mash() -> void:
	var now := Time.get_ticks_usec()
	if now < _next_mash_us:
		return
	_next_mash_us = now + (MASH_INTERVAL_MS + _rng.randi_range(-MASH_JITTER_MS, MASH_JITTER_MS)) * 1000
	_input.inject_press(DEFENCE_ACTIONS[_rng.randi_range(0, DEFENCE_ACTIONS.size() - 1)])


## The first still-pending prompt of a hit whose character is standing, or {}.
func _open_prompt(sequence: Dictionary, hit_index: int) -> Dictionary:
	var prompts: Array = sequence.prompts
	var states: Array = sequence.states
	for i: int in prompts.size():
		var prompt: Dictionary = prompts[i]
		if int(prompt.hit) != hit_index:
			continue
		if int(states[i]) == CombatEngine.PromptState.PENDING and _mirror.is_alive(int(prompt.character)):
			return prompt
	return {}


func _menu_abilities() -> Array[AbilityData]:
	return _menu.abilities()
