extends GutTest
## Timeline (DESIGN 2.1): integer turn cost, lowest next_turn_at acts, ties to the lower id,
## preview without side effects, downed fighters skipped.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const BASE: int = 10000


func _fighter(id: int, speed: int, hp: int = 10) -> Combatant:
	var c := Combatant.new()
	c.id = id
	c.speed = speed
	c.hp = hp
	c.max_hp = maxi(1, hp)
	c.next_turn_at = Timeline.turn_cost(speed, BASE)
	return c


func test_turn_cost_is_integer_division() -> void:
	assert_eq(Timeline.turn_cost(100, BASE), 100)
	assert_eq(Timeline.turn_cost(90, BASE), 111, "10000 / 90 = 111.1 truncates")
	assert_eq(Timeline.turn_cost(110, BASE), 90, "10000 / 110 = 90.9 truncates")
	assert_eq(Timeline.turn_cost(200, BASE), 50)
	assert_eq(Timeline.turn_cost(0, BASE), BASE, "speed is clamped to at least 1")
	assert_eq(Timeline.turn_cost(20000, BASE), 1, "a turn always costs at least 1 tick")


func test_next_actor_is_the_lowest_next_turn_at() -> void:
	var fighters: Array[Combatant] = [_fighter(0, 90), _fighter(1, 110), _fighter(2, 100), _fighter(3, 200)]
	assert_eq(Timeline.next_actor(fighters).id, 3, "speed 200 has the lowest turn cost")
	fighters[3].hp = 0
	assert_eq(Timeline.next_actor(fighters).id, 1, "then speed 110")


func test_ties_go_to_the_lower_id() -> void:
	var a := _fighter(0, 100)
	var b := _fighter(1, 100)
	var c := _fighter(2, 100)
	var fighters: Array[Combatant] = [c, b, a]
	assert_eq(Timeline.next_actor(fighters).id, 0, "array order does not matter, the id does")
	assert_true(Timeline.comes_before(a, b))
	assert_false(Timeline.comes_before(b, a))


func test_preview_order_by_speed() -> void:
	var slow := _fighter(0, 100)
	var fast := _fighter(1, 200)
	var fighters: Array[Combatant] = [slow, fast]
	# fast at 50, then 100 (tie with slow: slow has the lower id), 150, 200 (tie again)...
	assert_eq(Timeline.preview(fighters, 8, BASE), [1, 0, 1, 1, 0, 1, 1, 0])
	assert_eq(Timeline.preview(fighters, 0, BASE), [])


func test_preview_does_not_mutate_state() -> void:
	var fighters: Array[Combatant] = [_fighter(0, 90), _fighter(1, 110), _fighter(2, 100), _fighter(3, 200)]
	var before: Array[int] = []
	for c: Combatant in fighters:
		before.append(c.next_turn_at)
	var first := Timeline.preview(fighters, 12, BASE)
	var after: Array[int] = []
	for c: Combatant in fighters:
		after.append(c.next_turn_at)
	assert_eq(after, before, "next_turn_at untouched")
	assert_eq(Timeline.preview(fighters, 12, BASE), first, "a second preview gives the same order")


func test_downed_fighters_are_skipped() -> void:
	var fighters: Array[Combatant] = [_fighter(0, 100), _fighter(1, 300, 0), _fighter(2, 100)]
	assert_eq(Timeline.next_actor(fighters).id, 0)
	assert_does_not_have(Timeline.preview(fighters, 10, BASE), 1)
	for c: Combatant in fighters:
		c.hp = 0
	assert_null(Timeline.next_actor(fighters))
	assert_eq(Timeline.preview(fighters, 5, BASE), [])


func test_engine_turn_order_from_speeds() -> void:
	# Fixture party speeds 90 / 110 / 100 (costs 111 / 90 / 100); enemy speed 200 (cost 50).
	var engine := CombatEngine.new(Fx.setup([Fx.attack("swipe", [Fx.hit(900)])]))
	var events := engine.start()
	var turn := Fx.first_of(events, "turn_started")
	assert_eq(turn.actor, Fx.ENEMY_ID, "the speed 200 enemy acts first")
	assert_eq(turn.time, 50)
	assert_eq(engine.time_now, 50)
	assert_eq(engine.get_combatant(Fx.ENEMY_ID).next_turn_at, 100, "next_turn_at += turn cost")
	# Upcoming: c1@90, c2@100 (ties the enemy, lower id), enemy@100, c0@111, enemy@150, c1@180,
	# c2@200 (tie), enemy@200.
	var expected: Array[int] = [3, 1, 2, 3, 0, 3, 1, 2]
	assert_eq(Fx.first_of(events, "turn_order").order, expected)
	var before := engine.snapshot()
	assert_eq(engine.preview_turn_order(8), expected)
	assert_eq(engine.snapshot(), before, "preview_turn_order does not change the engine")


func test_engine_skips_downed_party_member() -> void:
	# c0 has 10 HP; one undefended 50% hit (14 damage) downs it.
	var slam := Fx.attack("slam", [Fx.hit(900, Fx.NORMAL, 50)], Fx.PARTY)
	var engine := Fx.started([slam], {"hp_percents": [10, 100, 100]})
	var events := engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.NONE], [1, Defense.Outcome.PARRY], [2, Defense.Outcome.PARRY]]))
	assert_false(engine.get_combatant(0).is_alive())
	assert_does_not_have(Fx.first_of(events, "turn_order").order as Array, 0)
	# Play many more turns: c0 never gets one.
	for i: int in 40:
		if engine.phase == CombatEngine.Phase.ENDED:
			break
		if engine.phase == CombatEngine.Phase.AWAITING_ACTION:
			assert_ne(engine.active_actor, 0, "a downed character never acts")
			events = engine.submit(Fx.use(engine, "basic_attack"))
		else:
			var pairs: Array = []
			for idx: int in engine.pending_prompts():
				pairs.append([idx, Defense.Outcome.PARRY])
			events = engine.submit(Fx.resolve_now(engine, pairs))
		for e: Dictionary in Fx.of_type(events, "turn_started"):
			assert_ne(e.actor, 0)
