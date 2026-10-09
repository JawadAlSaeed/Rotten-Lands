extends GutTest
## EnemyChoreography (DESIGN 3.3, 3.6, 3.7): what you see is what is judged. For every shipped
## attack, as the engine declares it: a normal lunge reaches the contact point exactly at impact,
## the contact pose holds until the hit can no longer be defended (where the string leaves room),
## a ground wave launches approach_ms before impact and a feint's false start comes feint_lead_ms
## earlier. Uses the default Tuning and CombatVisuals so edits to the .tres files never break it.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const ATTACK_DIR := "res://data/enemy_attacks"
const LATENCY_MS: int = 30
## Close enough for float milliseconds.
const EPS: float = 0.001

var _visuals := CombatVisuals.new()


## {name, hits (with close times), prompts} for every shipped attack, declared by the engine.
func _declared_attacks() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for file: String in DirAccess.get_files_at(ATTACK_DIR):
		if not file.ends_with(".tres"):
			continue
		var attack := load(ATTACK_DIR.path_join(file)) as EnemyAttackData
		var engine := CombatEngine.new(Fx.setup([attack]))
		var declared := Fx.first_of(engine.start(), "timed_sequence_declared")
		var prompts: Array = declared.prompts
		list.append({
			"name": attack.id,
			"hits": EnemyChoreography.with_close_times(declared.hits as Array, prompts, LATENCY_MS),
			"prompts": prompts,
		})
	return list


func test_shipped_attacks_are_found() -> void:
	assert_eq(_declared_attacks().size(), 5)


func test_close_times_are_late_edge_plus_latency() -> void:
	var tuning := Tuning.new()
	for a: Dictionary in _declared_attacks():
		for hit: Dictionary in a.hits:
			var late_ms := float(tuning.window_edges_us(tuning.dodge_window_ms).y) / 1000.0
			if int(hit.kind) == AttackHitData.Kind.GROUND:
				late_ms = float(tuning.window_edges_us(tuning.jump_window_ms).y) / 1000.0
			assert_almost_eq(float(hit.close_ms), late_ms + LATENCY_MS, EPS, a.name)


func test_normal_lunges_reach_contact_exactly_at_impact() -> void:
	for a: Dictionary in _declared_attacks():
		for i: int in (a.hits as Array).size():
			var hit: Dictionary = a.hits[i]
			if int(hit.kind) != AttackHitData.Kind.NORMAL:
				continue
			var at := float(hit.at_ms)
			var label := "%s hit %d" % [a.name, i]
			var before := EnemyChoreography.sample(a.hits, at - 1.0, _visuals)
			assert_eq(int(before.pose), EnemyChoreography.Pose.LUNGE, label + ": still lunging 1 ms before impact")
			assert_lt(float(before.approach), 1.0, label)
			var contact := EnemyChoreography.sample(a.hits, at, _visuals)
			assert_eq(int(contact.pose), EnemyChoreography.Pose.CONTACT, label + ": contact at impact")
			assert_almost_eq(float(contact.approach), 1.0, EPS, label)


func test_contact_holds_until_the_hit_closes_where_the_string_allows() -> void:
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		for i: int in hits.size():
			var hit: Dictionary = hits[i]
			if int(hit.kind) != AttackHitData.Kind.NORMAL:
				continue
			var at := float(hit.at_ms)
			var hold := maxf(float(_visuals.contact_hold_ms), float(hit.close_ms))
			if i == hits.size() - 1:
				hold = maxf(float(_visuals.contact_hold_ms), float(hit.close_ms) + float(_visuals.contact_after_close_ms))
			else:
				var next_motion := float(EnemyChoreography.cues(hits, _visuals).filter(
						func(c: Dictionary) -> bool: return int(c.hit) == i + 1)[0].at_ms)
				hold = minf(hold, next_motion - at - float(_visuals.recoil_min_ms))
			var label := "%s hit %d" % [a.name, i]
			var held := EnemyChoreography.sample(hits, at + hold - 1.0, _visuals)
			assert_eq(int(held.pose), EnemyChoreography.Pose.CONTACT, label + ": still in contact")
			if i == hits.size() - 1:
				assert_gt(hold, float(hit.close_ms), label + ": the last hit holds past its close (it lands after it)")


func test_cues_match_the_motion() -> void:
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		var cues := EnemyChoreography.cues(hits, _visuals)
		for i: int in hits.size():
			var hit: Dictionary = hits[i]
			var mine := cues.filter(func(c: Dictionary) -> bool: return int(c.hit) == i)
			var label := "%s hit %d" % [a.name, i]
			var earliest := float(hits[i - 1].at_ms) if i > 0 else 0.0
			var launch := maxf(float(hit.at_ms) - float(hit.approach_ms), earliest)
			if int(hit.kind) == AttackHitData.Kind.GROUND:
				assert_eq(mine.size(), 1, label)
				assert_eq(String(mine[0].type), EnemyChoreography.CUE_SLAM, label)
				assert_almost_eq(float(mine[0].at_ms), launch, EPS, label + ": the wave launches approach_ms before impact")
			elif bool(hit.feint):
				assert_eq(mine.size(), 2, label)
				assert_eq(String(mine[0].type), EnemyChoreography.CUE_FEINT, label)
				assert_almost_eq(float(mine[0].at_ms), maxf(launch - float(_visuals.feint_lead_ms), earliest), EPS, label)
				assert_almost_eq(float(mine[1].at_ms), launch, EPS, label + ": the real lunge")
			else:
				assert_eq(mine.size(), 1, label)
				assert_almost_eq(float(mine[0].at_ms), launch, EPS, label)


func test_nothing_moves_before_the_clock_or_after_the_attack() -> void:
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		var start := EnemyChoreography.sample(hits, -1.0, _visuals)
		assert_eq([int(start.pose), float(start.approach)], [EnemyChoreography.Pose.IDLE, 0.0], a.name)
		var last: Dictionary = hits[hits.size() - 1]
		var settled := float(last.at_ms) + float(last.close_ms) + float(_visuals.contact_after_close_ms) 				+ float(_visuals.slam_hold_ms) + float(_visuals.return_ms) + 1.0
		var end := EnemyChoreography.sample(hits, settled, _visuals)
		assert_eq(int(end.pose), EnemyChoreography.Pose.IDLE, a.name)
		assert_almost_eq(float(end.approach), 0.0, EPS, a.name + ": back home")
