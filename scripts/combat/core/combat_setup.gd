class_name CombatSetup
extends RefCounted
## Everything CombatEngine needs to build a fight.

var party: Array[CharacterData] = []
var enemies: Array[EnemyData] = []
var tuning: Tuning
var rng_seed: int = 1
## Accept practice commands (force an attack, invulnerability). Off for real runs.
var allow_practice: bool = false


static func from_encounter(encounter: EncounterData, p_tuning: Tuning, p_seed: int) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.party = encounter.party.duplicate()
	setup.enemies = encounter.enemies.duplicate()
	setup.tuning = p_tuning
	setup.rng_seed = p_seed
	return setup


## Human-readable problems. Empty means the setup is usable.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if tuning == null:
		problems.append("no tuning resource")
	if party.is_empty() or party.size() > 3:
		problems.append("party must have 1 to 3 characters (has %d)" % party.size())
	if enemies.is_empty():
		problems.append("no enemies")
	for c: CharacterData in party:
		if c == null:
			problems.append("empty party slot")
		elif c.basic_attack == null:
			problems.append("character %s has no basic attack" % c.id)
	for e: EnemyData in enemies:
		if e == null:
			problems.append("empty enemy slot")
			continue
		for a: EnemyAttackData in e.attacks:
			if a == null:
				problems.append("enemy %s has an empty attack slot" % e.id)
				continue
			if a.hits.is_empty():
				problems.append("attack %s has no hits" % a.id)
			var last := -1
			for h: AttackHitData in a.hits:
				if h == null:
					problems.append("attack %s has an empty hit slot" % a.id)
				elif h.impact_ms <= last:
					problems.append("attack %s: hit times must increase" % a.id)
				else:
					last = h.impact_ms
	return problems
