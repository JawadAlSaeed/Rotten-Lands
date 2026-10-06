extends SceneTree
## Creates the starting data files in data/. Only writes files that do not exist yet, so edits
## made in the editor are never overwritten. Run headless:
##   godot --headless --path . -s tools/bootstrap_data.gd
## Add "-- --force" after the script to overwrite everything (careful: loses edits).

var _force := false
var _written := 0
var _skipped := 0


func _init() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	for dir: String in ["res://data/tuning", "res://data/abilities", "res://data/characters",
			"res://data/enemies", "res://data/enemy_attacks", "res://data/encounters", "res://data/audio"]:
		DirAccess.make_dir_recursive_absolute(dir)

	_save_tuning("res://data/tuning/tuning.tres")

	var basic := _ability("basic_attack", "Attack", "A quick strike. Gains 1 AP.", 0, 1, 100, "strike")
	var heavy := _ability("heavy_strike", "Heavy Strike", "A slow, crushing blow. Costs 2 AP.", 2, 0, 220, "heavy_strike")
	basic = _save(basic, "res://data/abilities/basic_attack.tres")
	heavy = _save(heavy, "res://data/abilities/heavy_strike.tres")

	var alder := _character("alder", "Alder", Color("5b7fbf"), 100, 90, 90, basic, [heavy])
	var brin := _character("brin", "Brin", Color("c2453d"), 100, 120, 110, basic, [heavy])
	var cass := _character("cass", "Cass", Color("d8b84a"), 100, 100, 100, basic, [heavy])
	alder = _save(alder, "res://data/characters/alder.tres")
	brin = _save(brin, "res://data/characters/brin.tres")
	cass = _save(cass, "res://data/characters/cass.tres")

	# Attack set reviewed for Phase 1 (DESIGN.md 2.9). Times are ms after the attack starts.
	var swipe := _attack("husk_swipe", "Swipe", EnemyAttackData.TargetMode.SINGLE, 3, true, [
		_hit(900, AttackHitData.Kind.NORMAL, 100, 200),
	])
	var flurry := _attack("husk_flurry", "Flurry", EnemyAttackData.TargetMode.SINGLE, 3, true, [
		_hit(900, AttackHitData.Kind.NORMAL, 45, 180),
		_hit(1200, AttackHitData.Kind.NORMAL, 45, 180),
		_hit(1500, AttackHitData.Kind.NORMAL, 45, 180),
	])
	var lingering := _attack("husk_lingering_claw", "Lingering Claw", EnemyAttackData.TargetMode.SINGLE, 2, false, [
		_hit(1600, AttackHitData.Kind.NORMAL, 130, 200, true),
	])
	var slam := _attack("husk_ground_slam", "Ground Slam", EnemyAttackData.TargetMode.PARTY, 1, true, [
		_hit(1100, AttackHitData.Kind.GROUND, 80, 450),
	])
	var combo := _attack("husk_rot_combo", "Rot Combo", EnemyAttackData.TargetMode.PARTY, 1, true, [
		_hit(900, AttackHitData.Kind.NORMAL, 35, 180),
		_hit(1200, AttackHitData.Kind.NORMAL, 35, 180),
		_hit(1700, AttackHitData.Kind.GROUND, 35, 400),
		_hit(2300, AttackHitData.Kind.NORMAL, 35, 200),
	])
	swipe = _save(swipe, "res://data/enemy_attacks/husk_swipe.tres")
	flurry = _save(flurry, "res://data/enemy_attacks/husk_flurry.tres")
	lingering = _save(lingering, "res://data/enemy_attacks/husk_lingering_claw.tres")
	slam = _save(slam, "res://data/enemy_attacks/husk_ground_slam.tres")
	combo = _save(combo, "res://data/enemy_attacks/husk_rot_combo.tres")

	var husk := EnemyData.new()
	husk.id = "rotten_husk"
	husk.display_name = "Rotten Husk"
	husk.color = Color("7aa344")
	husk.sprite_path = "res://assets/sprites/enemies/rotten_husk.png"
	husk.portrait_path = "res://assets/sprites/portraits/rotten_husk.png"
	husk.sprite_pixel_size = 0.05
	husk.hp_percent = 100
	husk.power_percent = 100
	husk.speed = 200
	husk.attacks.assign([swipe, flurry, lingering, slam, combo])
	husk = _save(husk, "res://data/enemies/rotten_husk.tres")

	var encounter := EncounterData.new()
	encounter.id = "phase1_test"
	encounter.display_name = "Test Fight"
	encounter.party.assign([alder, brin, cass])
	encounter.enemies.assign([husk])
	_save(encounter, "res://data/encounters/phase1_test.tres")

	var library := SfxLibrary.new()
	var cue_names := ["parry", "parry_final", "dodge", "jump", "whiff", "locked", "hurt", "strike",
		"heavy_strike", "counter", "team_counter", "alert", "lunge", "slam", "downed", "ap_gain",
		"turn_start", "menu_move", "menu_confirm", "menu_cancel", "victory", "defeat", "metronome"]
	for cue_name: String in cue_names:
		var cue := SfxCue.new()
		cue.name = cue_name
		cue.path = "res://assets/audio/sfx/%s.wav" % cue_name
		cue.volume_db = 0.0
		cue.pitch_jitter = 0.04 if cue_name in ["hurt", "strike", "dodge", "whiff", "lunge"] else 0.0
		library.cues.append(cue)
	_save(library, "res://data/audio/sfx_library.tres")

	print("bootstrap_data: wrote %d, kept %d existing" % [_written, _skipped])
	quit()


## Saves the resource unless the file exists (then loads and returns the existing one, so other
## files reference it).
func _save(res: Resource, path: String) -> Resource:
	if FileAccess.file_exists(path) and not _force:
		_skipped += 1
		return load(path)
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("bootstrap_data: could not save %s (%d)" % [path, err])
		return res
	_written += 1
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


## Writes the tuning file with every value spelled out (Godot normally leaves defaults out,
## which would make the file look empty).
func _save_tuning(path: String) -> void:
	if FileAccess.file_exists(path) and not _force:
		_skipped += 1
		return
	var t := Tuning.new()
	var lines := PackedStringArray()
	lines.append('[gd_resource type="Resource" script_class="Tuning" format=3]')
	lines.append("")
	lines.append('[ext_resource type="Script" path="res://scripts/data/tuning.gd" id="1_tuning"]')
	lines.append("")
	lines.append("[resource]")
	lines.append('script = ExtResource("1_tuning")')
	for p: Dictionary in t.get_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and (p.usage & PROPERTY_USAGE_STORAGE):
			lines.append("%s = %s" % [p.name, var_to_str(t.get(p.name))])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	_written += 1


func _ability(id: String, title: String, desc: String, cost: int, gain: int, pct: int, sfx: String) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.display_name = title
	a.description = desc
	a.ap_cost = cost
	a.ap_gain = gain
	a.damage_percent = pct
	a.target = AbilityData.Target.SINGLE_ENEMY
	a.impact_sfx = sfx
	return a


func _character(id: String, title: String, color: Color, hp_pct: int, power_pct: int, speed: int,
		basic: AbilityData, skills: Array) -> CharacterData:
	var c := CharacterData.new()
	c.id = id
	c.display_name = title
	c.color = color
	c.sprite_path = "res://assets/sprites/characters/%s.png" % id
	c.portrait_path = "res://assets/sprites/portraits/%s.png" % id
	c.sprite_pixel_size = 0.045
	c.hp_percent = hp_pct
	c.power_percent = power_pct
	c.speed = speed
	c.basic_attack = basic
	c.skills.assign(skills)
	return c


func _attack(id: String, title: String, mode: EnemyAttackData.TargetMode, weight: int, ring: bool,
		hits: Array) -> EnemyAttackData:
	var a := EnemyAttackData.new()
	a.id = id
	a.display_name = title
	a.target_mode = mode
	a.weight = weight
	a.alert_cue = true
	a.allow_timing_ring = ring
	a.hits.assign(hits)
	return a


func _hit(impact_ms: int, kind: AttackHitData.Kind, pct: int, approach_ms: int, feint: bool = false) -> AttackHitData:
	var h := AttackHitData.new()
	h.impact_ms = impact_ms
	h.kind = kind
	h.damage_percent = pct
	h.approach_ms = approach_ms
	h.feint = feint
	h.impact_sfx = "hurt"
	return h
