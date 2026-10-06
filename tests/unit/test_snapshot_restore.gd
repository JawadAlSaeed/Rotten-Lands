extends GutTest
## CombatEngine.snapshot() / restore() (DESIGN 4.2, 4.4): a fight restored from a snapshot taken
## mid-attack, after a partial resolve, continues exactly like the uninterrupted fight.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const Bot := preload("res://tests/helpers/combat_bot.gd")


## Indices of commands after which the engine was waiting on a partially resolved sequence.
func _partial_points(seed_value: int, commands: Array, practice: bool) -> Array[int]:
	var engine := CombatEngine.new(Fx.shipped_setup(seed_value, null, practice))
	engine.start()
	var points: Array[int] = []
	for i: int in commands.size():
		var command: Dictionary = commands[i]
		engine.submit(command)
		if String(command.type) == CombatCommands.RESOLVE_PROMPTS \
				and engine.phase == CombatEngine.Phase.AWAITING_TIMING \
				and int(engine.sequence.seq) == int(command.seq):
			points.append(i)
	return points


## Replays commands[0..cut], snapshots (through var_to_bytes, as if sent over the network),
## restores into a new engine and replays the rest. Checks the tail and the final state.
func _check_restore_at(seed_value: int, practice: bool, reference: Dictionary, final_snapshot: Dictionary, cut: int) -> void:
	var commands: Array = reference.commands
	var label := "seed %d, restored after command %d" % [seed_value, cut]
	var engine := CombatEngine.new(Fx.shipped_setup(seed_value, null, practice))
	var head: Array[Dictionary] = []
	head.append_array(engine.start())
	for i: int in cut + 1:
		head.append_array(engine.submit(commands[i]))
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_TIMING, label)
	assert_false(engine.pending_prompts().is_empty(), "some prompts still pending: " + label)
	var snap: Dictionary = bytes_to_var(var_to_bytes(engine.snapshot()))
	var restored := CombatEngine.restore(Fx.shipped_setup(seed_value, null, practice), snap)
	assert_true(restored.snapshot() == engine.snapshot(), "restored state equals the original: " + label)
	assert_eq(restored.pending_prompts(), engine.pending_prompts())
	var tail: Array[Dictionary] = []
	for i: int in range(cut + 1, commands.size()):
		tail.append_array(restored.submit(commands[i]))
	var reference_events: Array = reference.events
	var expected_tail := reference_events.slice(head.size())
	assert_eq(tail.size(), expected_tail.size(), "same number of tail events: " + label)
	assert_true(tail == expected_tail, "identical event tail: " + label)
	assert_true(restored.snapshot() == final_snapshot, "identical final snapshot: " + label)


func test_restore_mid_attack_continues_identically() -> void:
	var cases := 0
	for seed_value: int in [3, 11, 77]:
		for defence: int in [Bot.Defence.MIXED, Bot.Defence.PERFECT, Bot.Defence.MISS]:
			var practice := defence == Bot.Defence.MIXED
			# One prompt per command, so multi-prompt attacks pass through partial states.
			var engine := CombatEngine.new(Fx.shipped_setup(seed_value, null, practice))
			var reference: Dictionary = Bot.new(defence as Bot.Defence, 1, practice).play(engine)
			assert_eq(engine.phase, CombatEngine.Phase.ENDED)
			var points := _partial_points(seed_value, reference.commands as Array, practice)
			assert_gt(points.size(), 0, "the fight had partial resolves (seed %d)" % seed_value)
			if points.is_empty():
				continue
			@warning_ignore("integer_division")
			var middle: int = points[points.size() / 2]
			var picks: Array[int] = [points[0], middle, points[points.size() - 1]]
			for cut: int in picks:
				_check_restore_at(seed_value, practice, reference, engine.snapshot(), cut)
				cases += 1
	assert_gt(cases, 0)


func test_restore_between_turns() -> void:
	var engine := CombatEngine.new(Fx.shipped_setup(21))
	var reference: Dictionary = Bot.new(Bot.Defence.MIXED).play(engine)
	var commands: Array = reference.commands
	var replay := CombatEngine.new(Fx.shipped_setup(21))
	var head: Array[Dictionary] = []
	head.append_array(replay.start())
	var cut := -1
	for i: int in commands.size():
		head.append_array(replay.submit(commands[i]))
		if replay.phase == CombatEngine.Phase.AWAITING_ACTION and replay.turn_number > 6:
			cut = i
			break
	assert_gt(cut, -1, "reached a party turn")
	var restored := CombatEngine.restore(Fx.shipped_setup(21), replay.snapshot())
	var tail: Array[Dictionary] = []
	for i: int in range(cut + 1, commands.size()):
		tail.append_array(restored.submit(commands[i]))
	assert_true(tail == (reference.events as Array).slice(head.size()))
	assert_true(restored.snapshot() == engine.snapshot())


func test_restore_keeps_practice_options() -> void:
	var engine := Fx.started([Fx.attack("a", [Fx.hit(900)]), Fx.attack("b", [Fx.hit(900)])], {"practice": true})
	engine.submit(CombatCommands.practice({"invulnerable_party": true, "force_attack": "b"}))
	var restored := CombatEngine.restore(Fx.setup([Fx.attack("a", [Fx.hit(900)]), Fx.attack("b", [Fx.hit(900)])], {"practice": true}), engine.snapshot())
	assert_eq(restored.practice, {"invulnerable_party": true, "immortal_enemies": false, "force_attack": "b"})
	assert_eq(restored.snapshot(), engine.snapshot())


func test_snapshot_is_a_deep_copy() -> void:
	var attacks := [Fx.attack("party", [Fx.hit(900), Fx.hit(1500, Fx.GROUND)], Fx.PARTY)]
	var engine := Fx.started(attacks)
	var before := engine.snapshot()
	var snap := engine.snapshot()
	Fx.scramble(snap)
	assert_eq(engine.snapshot(), before, "changing a snapshot never changes the engine")
	var restored := CombatEngine.restore(Fx.setup(attacks), before)
	Fx.scramble(before)
	assert_eq(restored.snapshot(), engine.snapshot(), "restore copies the snapshot instead of keeping it")
