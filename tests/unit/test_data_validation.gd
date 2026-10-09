extends GutTest
## Data files (DESIGN 2.9, 5, 10): everything under res://data loads, ids are unique per type,
## the phase 1 encounter is a valid setup, attacks follow the timing rules and weights and damage
## percents are positive. Asset paths and import settings are checked in test_asset_files.gd.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const DATA_DIR := "res://data"
## DESIGN 2.9 spacing rules, in ms at tempo 100%.
const MIN_NORMAL_GAP_MS: int = 250
const MIN_GROUND_GAP_MS: int = 450
## DESIGN 2.9: mid-string parry hit-stop at least this much under the parry window's early part.
const PARRY_HITSTOP_MARGIN_MS: int = 30


func _tres_files(dir_path: String) -> PackedStringArray:
	var files := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	for file: String in dir.get_files():
		if file.ends_with(".tres"):
			files.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		files.append_array(_tres_files(dir_path.path_join(sub)))
	return files


func _load_all() -> Array[Resource]:
	var list: Array[Resource] = []
	for path: String in _tres_files(DATA_DIR):
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res != null:
			list.append(res)
	return list


## Every enemy attack in the data: standalone files plus the ones listed by enemies.
func _all_attacks() -> Array[EnemyAttackData]:
	var by_id := {}
	for res: Resource in _load_all():
		if res is EnemyAttackData:
			by_id[(res as EnemyAttackData).id] = res
		elif res is EnemyData:
			for a: EnemyAttackData in (res as EnemyData).attacks:
				if a != null and not by_id.has(a.id):
					by_id[a.id] = a
	var list: Array[EnemyAttackData] = []
	for id: String in by_id:
		list.append(by_id[id])
	return list


## Problems with one attack's hit timing (DESIGN 2.9). Empty means it follows the rules.
func _timing_problems(attack: EnemyAttackData) -> PackedStringArray:
	var problems := PackedStringArray()
	if attack.hits.is_empty():
		problems.append("%s has no hits" % attack.id)
		return problems
	for i: int in range(1, attack.hits.size()):
		var prev: AttackHitData = attack.hits[i - 1]
		var hit: AttackHitData = attack.hits[i]
		if prev == null or hit == null:
			problems.append("%s has an empty hit slot" % attack.id)
			continue
		var gap := hit.impact_ms - prev.impact_ms
		if gap <= 0:
			problems.append("%s: hit %d (%d ms) is not after hit %d (%d ms)" % [attack.id, i, hit.impact_ms, i - 1, prev.impact_ms])
		elif prev.kind == AttackHitData.Kind.GROUND or hit.kind == AttackHitData.Kind.GROUND:
			if gap < MIN_GROUND_GAP_MS:
				problems.append("%s: only %d ms between hits %d and %d around a ground hit (need %d)" % [attack.id, gap, i - 1, i, MIN_GROUND_GAP_MS])
		elif gap < MIN_NORMAL_GAP_MS:
			problems.append("%s: only %d ms between normal hits %d and %d (need %d)" % [attack.id, gap, i - 1, i, MIN_NORMAL_GAP_MS])
	return problems


func _hitstop_problem(tuning: Tuning) -> String:
	var early_part_us := -tuning.window_edges_us(tuning.parry_window_ms).x
	var limit_us := early_part_us - PARRY_HITSTOP_MARGIN_MS * 1000
	if tuning.hitstop_parry_ms * 1000 > limit_us:
		return "hitstop_parry_ms %d is above %.1f ms (parry window early part %.1f ms minus %d ms)" % [
				tuning.hitstop_parry_ms, limit_us / 1000.0, early_part_us / 1000.0, PARRY_HITSTOP_MARGIN_MS]
	return ""


func test_every_data_file_loads() -> void:
	var paths := _tres_files(DATA_DIR)
	assert_gt(paths.size(), 10, "found the data files")
	for path: String in paths:
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert_not_null(res, "%s loads" % path)


func test_ids_are_unique_per_type() -> void:
	var seen := {}
	var checked := 0
	for path: String in _tres_files(DATA_DIR):
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var type := ""
		if res is AbilityData:
			type = "ability"
		elif res is CharacterData:
			type = "character"
		elif res is EnemyData:
			type = "enemy"
		elif res is EnemyAttackData:
			type = "enemy attack"
		elif res is EncounterData:
			type = "encounter"
		if type.is_empty():
			continue
		var id := String(res.get("id"))
		assert_false(id.is_empty(), "%s has an id" % path)
		var key := type + ":" + id
		assert_false(seen.has(key), "%s id '%s' is used by %s and %s" % [type, id, seen.get(key, ""), path])
		seen[key] = path
		checked += 1
	assert_gt(checked, 8)


func test_sound_cue_names_are_unique() -> void:
	var library := ResourceLoader.load("res://data/audio/sfx_library.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as SfxLibrary
	assert_not_null(library)
	var names := {}
	for cue: SfxCue in library.cues:
		assert_not_null(cue, "no empty cue slot")
		if cue == null:
			continue
		assert_false(names.has(cue.name), "cue '%s' is defined once" % cue.name)
		names[cue.name] = true


func test_sound_cues_used_by_the_data_exist() -> void:
	var library := ResourceLoader.load("res://data/audio/sfx_library.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as SfxLibrary
	var used := {}
	for res: Resource in _load_all():
		if res is AbilityData:
			used[(res as AbilityData).impact_sfx] = (res as AbilityData).id
	for attack: EnemyAttackData in _all_attacks():
		for i: int in attack.hits.size():
			var hit: AttackHitData = attack.hits[i]
			if hit != null:
				used[hit.impact_sfx] = "%s hit %d" % [attack.id, i]
	assert_gt(used.size(), 0)
	for cue_name: String in used:
		if cue_name.is_empty():
			continue
		assert_not_null(library.find(cue_name), "%s plays cue '%s', which sfx_library.tres defines" % [used[cue_name], cue_name])


func test_phase1_encounter_is_a_valid_setup() -> void:
	var encounter := (load(Fx.ENCOUNTER_PATH) as EncounterData).duplicate(true) as EncounterData
	var setup := CombatSetup.from_encounter(encounter, Fx.shipped_tuning(), 1)
	assert_eq(setup.validate(), PackedStringArray())
	assert_eq(encounter.party.size(), 3, "phase 1 party is three characters")
	var engine := CombatEngine.new(setup)
	var events := engine.start()
	assert_eq(Fx.of_type(events, "command_rejected").size(), 0, "the engine starts the shipped fight")


func test_attack_timing_rules() -> void:
	var attacks := _all_attacks()
	assert_gt(attacks.size(), 0)
	for attack: EnemyAttackData in attacks:
		assert_eq(_timing_problems(attack), PackedStringArray(), "timing rules for %s" % attack.id)


func test_timing_rule_check_catches_bad_data() -> void:
	var tight := Fx.attack("tight", [Fx.hit(900), Fx.hit(1100)])
	var ground := Fx.attack("ground", [Fx.hit(900), Fx.hit(1300, Fx.GROUND), Fx.hit(1800)])
	var backwards := Fx.attack("backwards", [Fx.hit(900), Fx.hit(900)])
	var fine := Fx.attack("fine", [Fx.hit(900), Fx.hit(1150), Fx.hit(1600, Fx.GROUND), Fx.hit(2050)])
	assert_eq(_timing_problems(tight).size(), 1, "normal hits 200 ms apart")
	assert_eq(_timing_problems(ground).size(), 1, "400 ms before a ground hit")
	assert_eq(_timing_problems(backwards).size(), 1, "times must increase")
	assert_eq(_timing_problems(fine).size(), 0, "250 ms and 450 ms gaps are allowed")
	var tuning := Tuning.new()
	tuning.hitstop_parry_ms = 68
	assert_ne(_hitstop_problem(tuning), "", "68 ms is above 97.5 - 30 ms")
	tuning.hitstop_parry_ms = 67
	assert_eq(_hitstop_problem(tuning), "")


func test_parry_hitstop_stays_under_the_parry_window() -> void:
	assert_eq(_hitstop_problem(Fx.shipped_tuning()), "", "data/tuning/tuning.tres")
	assert_eq(_hitstop_problem(Tuning.new()), "", "defaults in tuning.gd")


func test_weights_and_percents_are_positive() -> void:
	for attack: EnemyAttackData in _all_attacks():
		assert_gt(attack.weight, 0, "%s weight" % attack.id)
		for i: int in attack.hits.size():
			var hit: AttackHitData = attack.hits[i]
			assert_gt(hit.damage_percent, 0, "%s hit %d damage percent" % [attack.id, i])
			assert_gt(hit.approach_ms, 0, "%s hit %d approach" % [attack.id, i])
	for res: Resource in _load_all():
		if res is AbilityData:
			assert_gt((res as AbilityData).damage_percent, 0, "%s damage percent" % (res as AbilityData).id)
		elif res is CharacterData:
			var c := res as CharacterData
			assert_gt(c.hp_percent, 0, "%s hp percent" % c.id)
			assert_gt(c.power_percent, 0, "%s power percent" % c.id)
			assert_gt(c.speed, 0, "%s speed" % c.id)
			assert_not_null(c.basic_attack, "%s has a basic attack" % c.id)
		elif res is EnemyData:
			var e := res as EnemyData
			assert_gt(e.hp_percent, 0, "%s hp percent" % e.id)
			assert_gt(e.power_percent, 0, "%s power percent" % e.id)
			assert_gt(e.speed, 0, "%s speed" % e.id)
			assert_gt(e.attacks.size(), 0, "%s has attacks" % e.id)
