extends RefCounted
## Builders for test fights: hand-made data with exact numbers, or copies of the shipped data.
## Tests preload this file (it has no class_name, so nothing leaks into the game's classes).
## Hand-made fights always use Tuning.new() unless a test passes its own tuning, so the user's
## edits to data/tuning/tuning.tres never change an exact-number test.

const ENCOUNTER_PATH := "res://data/encounters/phase1_test.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"

const NORMAL: int = AttackHitData.Kind.NORMAL
const GROUND: int = AttackHitData.Kind.GROUND
const SINGLE: int = EnemyAttackData.TargetMode.SINGLE
const PARTY: int = EnemyAttackData.TargetMode.PARTY

## Fixture party: the same power and speed percentages as the phase 1 party.
const PARTY_POWER_PERCENTS: Array[int] = [90, 120, 100]
const PARTY_SPEEDS: Array[int] = [90, 110, 100]
## Enemy id in a fixture fight (after the three party members).
const ENEMY_ID: int = 3


static func hit(impact_ms: int, kind: int = NORMAL, damage_percent: int = 100, approach_ms: int = 200) -> AttackHitData:
	var h := AttackHitData.new()
	h.impact_ms = impact_ms
	h.kind = kind as AttackHitData.Kind
	h.damage_percent = damage_percent
	h.approach_ms = approach_ms
	return h


## An enemy attack. `hits` is an Array of AttackHitData.
static func attack(id: String, hits: Array, mode: int = SINGLE, weight: int = 1) -> EnemyAttackData:
	var a := EnemyAttackData.new()
	a.id = id
	a.display_name = "Attack " + id
	a.target_mode = mode as EnemyAttackData.TargetMode
	a.weight = weight
	a.hits.assign(hits)
	return a


static func ability(id: String, ap_cost: int, ap_gain: int, damage_percent: int) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.display_name = id
	a.ap_cost = ap_cost
	a.ap_gain = ap_gain
	a.damage_percent = damage_percent
	return a


## A character with the phase 1 ability ids: basic_attack (0 AP, +1 AP, 100%) and
## heavy_strike (2 AP, 220%).
static func character(id: String, hp_percent: int, power_percent: int, speed: int) -> CharacterData:
	var c := CharacterData.new()
	c.id = id
	c.display_name = id
	c.hp_percent = hp_percent
	c.power_percent = power_percent
	c.speed = speed
	c.basic_attack = ability("basic_attack", 0, 1, 100)
	c.skills.append(ability("heavy_strike", 2, 0, 220))
	return c


static func party(hp_percents: Array = [100, 100, 100]) -> Array[CharacterData]:
	var list: Array[CharacterData] = []
	for i: int in hp_percents.size():
		list.append(character("c%d" % i, int(hp_percents[i]), PARTY_POWER_PERCENTS[i], PARTY_SPEEDS[i]))
	return list


static func enemy(id: String, attacks: Array, speed: int = 200, hp_percent: int = 100, power_percent: int = 100) -> EnemyData:
	var e := EnemyData.new()
	e.id = id
	e.display_name = id
	e.speed = speed
	e.hp_percent = hp_percent
	e.power_percent = power_percent
	e.attacks.assign(attacks)
	return e


## Hand-made fight: the fixture party against one enemy that uses `attacks`.
## options: tuning (Tuning, default Tuning.new()), seed (int, 1), practice (bool, false),
## enemy_speed (int, 200: the enemy acts first; 10: the party gets many turns first),
## enemy_hp_percent (100), enemy_power_percent (100), hp_percents (Array, [100, 100, 100]).
static func setup(attacks: Array, options: Dictionary = {}) -> CombatSetup:
	var s := CombatSetup.new()
	s.party = party(options.get("hp_percents", [100, 100, 100]) as Array)
	s.enemies.append(enemy("foe", attacks, int(options.get("enemy_speed", 200)),
			int(options.get("enemy_hp_percent", 100)), int(options.get("enemy_power_percent", 100))))
	s.tuning = options.get("tuning", Tuning.new()) as Tuning
	s.rng_seed = int(options.get("seed", 1))
	s.allow_practice = bool(options.get("practice", false))
	return s


## A started engine for setup(attacks, options).
static func started(attacks: Array, options: Dictionary = {}) -> CombatEngine:
	var engine := CombatEngine.new(setup(attacks, options))
	engine.start()
	return engine


## The shipped phase 1 fight (a deep copy of the encounter). Uses Tuning.new() unless given one.
static func shipped_setup(rng_seed: int, p_tuning: Tuning = null, practice: bool = false) -> CombatSetup:
	var encounter := (load(ENCOUNTER_PATH) as EncounterData).duplicate(true) as EncounterData
	var s := CombatSetup.from_encounter(encounter, p_tuning if p_tuning != null else Tuning.new(), rng_seed)
	s.allow_practice = practice
	return s


## A copy of the shipped tuning file (only for tests that validate the data itself).
static func shipped_tuning() -> Tuning:
	return (load(TUNING_PATH) as Tuning).duplicate(true) as Tuning


## resolve_prompts command from [[prompt_idx, outcome], ...] or [[prompt_idx, outcome, offset_us], ...].
static func resolve(seq: int, pairs: Array) -> Dictionary:
	var results: Array[Dictionary] = []
	for pair: Array in pairs:
		var offset := int(pair[2]) if pair.size() > 2 else 0
		results.append(CombatCommands.prompt_result(int(pair[0]), int(pair[1]), offset))
	return CombatCommands.resolve_prompts(seq, results)


## resolve_prompts for the engine's current sequence.
static func resolve_now(engine: CombatEngine, pairs: Array) -> Dictionary:
	return resolve(int(engine.sequence.get("seq", -1)), pairs)


## use_ability command for the engine's current turn and actor.
static func use(engine: CombatEngine, ability_id: String, target: int = ENEMY_ID) -> Dictionary:
	var targets: Array[int] = [target]
	return CombatCommands.use_ability(engine.turn_number, engine.active_actor, ability_id, targets)


static func of_type(events: Array, type: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for e: Dictionary in events:
		if String(e.type) == type:
			list.append(e)
	return list


static func first_of(events: Array, type: String) -> Dictionary:
	for e: Dictionary in events:
		if String(e.type) == type:
			return e
	return {}


static func index_of(events: Array, type: String) -> int:
	for i: int in events.size():
		if String((events[i] as Dictionary).type) == type:
			return i
	return -1


static func types(events: Array) -> Array[String]:
	var list: Array[String] = []
	for e: Dictionary in events:
		list.append(String(e.type))
	return list


## Path to the first value that is not an int, bool, String, Array or Dictionary (DESIGN 4.3
## payload rule), or "" if there is none. Objects (Resources, nodes) are reported too.
static func find_illegal_value(value: Variant, path: String = "") -> String:
	match typeof(value):
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return ""
		TYPE_ARRAY:
			var arr: Array = value
			for i: int in arr.size():
				var bad := find_illegal_value(arr[i], "%s[%d]" % [path, i])
				if not bad.is_empty():
					return bad
			return ""
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			for key: Variant in dict:
				var bad_key := find_illegal_value(key, "%s<key %s>" % [path, str(key)])
				if not bad_key.is_empty():
					return bad_key
				var bad := find_illegal_value(dict[key], "%s.%s" % [path, str(key)])
				if not bad.is_empty():
					return bad
			return ""
	return "%s is %s" % [path, type_string(typeof(value))]


## Changes every container inside `value` in place (values replaced, extra items added), to prove
## that nobody else holds a reference to them.
static func scramble(value: Variant) -> void:
	if value is Array:
		var arr: Array = value
		for i: int in arr.size():
			if arr[i] is Array or arr[i] is Dictionary:
				scramble(arr[i])
			elif not arr.is_read_only():
				arr[i] = _junk_like(arr[i])
		if arr.is_read_only():
			return
		if not arr.is_typed():
			arr.append("junk")
		elif arr.get_typed_builtin() == TYPE_INT:
			arr.append(-424242)
		elif arr.get_typed_builtin() == TYPE_STRING:
			arr.append("junk")
		elif arr.get_typed_builtin() == TYPE_DICTIONARY:
			arr.append({"junk_key": "junk"})
	elif value is Dictionary:
		var dict: Dictionary = value
		for key: Variant in dict.keys():
			if dict[key] is Array or dict[key] is Dictionary:
				scramble(dict[key])
			else:
				dict[key] = _junk_like(dict[key])
		dict["junk_key"] = "junk"


static func _junk_like(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT:
			return -424242
		TYPE_BOOL:
			return not bool(v)
		TYPE_STRING:
			return "junk"
	return v
