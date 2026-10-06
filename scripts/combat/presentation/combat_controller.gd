class_name CombatController
extends Node
## Runs one fight (DESIGN.md 4). Owns the CombatEngine, keeps an event queue and plays the events
## one by one through the view and HUD, applying each to the CombatMirror at the moment it is
## played (so bars change with the animation). Enemy attacks are handed to the
## TimedSequenceRunner. Everything shown is read from the mirror and static data, never from the
## engine; the only way presentation changes the fight is submit() here.
## No SceneTree.paused and no Engine.time_scale anywhere: waits use Timers, hit-stop is the
## AttackClock.

signal restart_requested
## Every event as it is played (and the prompt events the runner applies at once).
signal event_played(event: Dictionary)
## The action menu opened for this party member.
signal menu_opened(actor_id: int)
signal combat_finished(result: String)

const QUIT_DELAY_S: float = 1.0
const PRACTICE_ATTACK_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
const PRACTICE_KEYS_PER_LINE: int = 3
## Party members dashing together (team counter) stand this far apart (world units).
const TEAM_SPREAD: float = 0.9
const TEAM_BANNER_MS: int = 1100

var mirror := CombatMirror.new()
var engine: CombatEngine
var view: CombatView
var hud: CombatHud
var runner: TimedSequenceRunner
var defense_input: DefenseInput
var autoplay: Autoplay

var _encounter: EncounterData
var _tuning: Tuning
var _visuals: CombatVisuals
var _options: CombatOptions
var _queue: Array[Dictionary] = []
var _playing: bool = false
var _waiting_runner: bool = false
var _ended: bool = false
var _menu_turn: int = -1
## Combatant id -> CharacterData or EnemyData.
var _data_by_id: Dictionary = {}
## Ability id -> AbilityData.
var _abilities: Dictionary = {}


## Call before adding the node to the tree.
func configure(encounter: EncounterData, tuning: Tuning, visuals: CombatVisuals, options: CombatOptions) -> void:
	_encounter = encounter
	_tuning = tuning
	_visuals = visuals
	_options = options


func _ready() -> void:
	defense_input = DefenseInput.new()
	defense_input.name = "DefenseInput"
	add_child(defense_input)

	view = CombatView.new()
	view.name = "View"
	add_child(view)
	view.build(_visuals)

	hud = CombatHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(view, _visuals, _tuning)
	hud.action_menu.chosen.connect(_on_ability_chosen)
	hud.action_menu.target_changed.connect(_on_target_changed)
	hud.calibration.setup(_visuals, defense_input)

	runner = TimedSequenceRunner.new()
	runner.name = "SequenceRunner"
	add_child(runner)
	runner.setup(_submit, _apply_now, mirror, view, hud, _tuning, _visuals, _options, defense_input)
	runner.finished.connect(_on_runner_finished)

	if _options.is_autoplay():
		autoplay = Autoplay.new()
		autoplay.name = "Autoplay"
		autoplay.setup(_options.autoplay_mode, mirror, runner, defense_input, hud.action_menu, _tuning)
		add_child(autoplay)
		runner.press_judged.connect(autoplay.on_press_judged)
		event_played.connect(autoplay.on_event)
		menu_opened.connect(autoplay.on_menu_opened)
		combat_finished.connect(autoplay.on_combat_finished)

	var setup := CombatSetup.from_encounter(_encounter, _tuning, _pick_seed())
	setup.allow_practice = _tuning.practice_tools_enabled or _options.is_autoplay()
	print("Combat seed: %d" % setup.rng_seed)
	for data: CharacterData in setup.party:
		for ability: AbilityData in data.all_abilities():
			_abilities[ability.id] = ability
	engine = CombatEngine.new(setup)
	_warm_up_assets(setup)
	_enqueue(_submit_start())


func _process(_delta: float) -> void:
	hud.overlay.update_text(_options.stats, _tuning, _options, runner.longest_frame_ms())


func _unhandled_input(event: InputEvent) -> void:
	if hud.calibration.is_running():
		hud.calibration.handle_input(event)
		get_viewport().set_input_as_handled()
		return
	var key := _pressed_key(event)
	if _ended:
		if event.is_action_pressed("menu_confirm", false, true) or key == KEY_R:
			get_viewport().set_input_as_handled()
			restart_requested.emit()
		return
	if _tuning.practice_tools_enabled and _handle_practice(event, key):
		get_viewport().set_input_as_handled()
		return
	if hud.action_menu.handle_input(event):
		get_viewport().set_input_as_handled()


# --- engine access ----------------------------------------------------------------------------

## Submits a command and returns its events. A rejection must never happen: it is reported and
## dropped (never played).
func submit(command: Dictionary) -> Array[Dictionary]:
	return _submit(command)


func _submit(command: Dictionary) -> Array[Dictionary]:
	return _keep_valid(engine.submit(command))


func _submit_start() -> Array[Dictionary]:
	return _keep_valid(engine.start())


func _keep_valid(events: Array[Dictionary]) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for ev: Dictionary in events:
		if String(ev.get("type", "")) == "command_rejected":
			var details := "reason=%s command=%s" % [String(ev.get("reason", "?")), var_to_str(ev.get("command", {})).replace("\n", " ")]
			push_error("CombatController: command rejected: " + details)
			if _options.is_autoplay():
				print("AUTOPLAY_ERROR command_rejected " + details)
			continue
		kept.append(ev)
	return kept


# --- event playback ---------------------------------------------------------------------------

func _enqueue(events: Array[Dictionary]) -> void:
	for ev: Dictionary in events:
		# Practice toggles are not part of any animation; show them at once.
		if String(ev.get("type", "")) == "practice_changed":
			_apply_now(ev)
		else:
			_queue.append(ev)
	_pump()


func _pump() -> void:
	if _playing or _waiting_runner:
		return
	_playing = true
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		await _play(ev)
		if _waiting_runner:
			break
	_playing = false
	if _queue.is_empty() and not _waiting_runner:
		_maybe_open_menu()


## Applies an event to the mirror right now (runner prompt events, practice changes).
func _apply_now(ev: Dictionary) -> void:
	mirror.apply(ev)
	if String(ev.get("type", "")) == "downed":
		_show_downed(int(ev.target))
	_refresh()
	event_played.emit(ev)


func _play(ev: Dictionary) -> void:
	var type := String(ev.get("type", ""))
	match type:
		"combat_started":
			mirror.apply(ev)
			await _build_fighters()
		"turn_started":
			mirror.apply(ev)
			if int(ev.team) == Combatant.Team.PARTY:
				Sfx.play("turn_start")
		"ability_used":
			mirror.apply(ev)
			_refresh()
			await _play_party_action(ev)
		"counter":
			mirror.apply(ev)
			await _play_counter(ev)
		"damage":
			mirror.apply(ev)
			_show_damage(ev)
		"downed":
			mirror.apply(ev)
			_show_downed(int(ev.target))
		"ap_changed":
			mirror.apply(ev)
			if int(ev.delta) > 0:
				Sfx.play("ap_gain")
		"timed_sequence_declared":
			mirror.apply(ev)
			hud.action_menu.close()
			get_viewport().gui_release_focus()
			_menu_turn = -1
			_waiting_runner = true
			_set_active_pose(-1)
			runner.start(ev)
		"turn_ended":
			mirror.apply(ev)
			_refresh()
			event_played.emit(ev)
			await _wait_ms(_tuning.turn_gap_ms)
			return
		"combat_ended":
			mirror.apply(ev)
			_on_combat_ended(String(ev.result))
		_:
			mirror.apply(ev)
	_refresh()
	event_played.emit(ev)


func _on_runner_finished(tail: Array[Dictionary]) -> void:
	_waiting_runner = false
	view.sync_alive(mirror)
	_queue.append_array(tail)
	_pump()


func _maybe_open_menu() -> void:
	if _ended or runner.is_active() or engine.phase != CombatEngine.Phase.AWAITING_ACTION:
		return
	var actor := mirror.active_actor
	if actor < 0 or not mirror.party_ids.has(actor):
		return
	if hud.action_menu.is_open() and _menu_turn == mirror.turn:
		return
	_menu_turn = mirror.turn
	var data := _data_by_id.get(actor) as CharacterData
	if data == null:
		push_error("CombatController: no character data for fighter %d" % actor)
		return
	var names: Dictionary = {}
	for id: int in mirror.enemy_ids:
		names[id] = String(mirror.fighter(id).display_name)
	hud.action_menu.open(String(mirror.fighter(actor).display_name), data.color, data.all_abilities(),
			int(mirror.fighter(actor).ap), mirror.living_enemy_ids(), names)
	_set_active_pose(actor)
	menu_opened.emit(actor)


func _on_ability_chosen(ability_id: String, target_id: int) -> void:
	if _ended or engine.phase != CombatEngine.Phase.AWAITING_ACTION:
		return
	var targets: Array[int] = []
	if target_id >= 0:
		targets.append(target_id)
	_menu_turn = -1
	_enqueue(_submit(CombatCommands.use_ability(mirror.turn, mirror.active_actor, ability_id, targets)))


func _on_target_changed(target_id: int) -> void:
	var v := view.fighter(target_id)
	if v == null:
		hud.set_target_marker(Vector3.ZERO, false)
	else:
		hud.set_target_marker(v.head_position(), true)


func _on_combat_ended(result: String) -> void:
	_ended = true
	hud.action_menu.close()
	_set_active_pose(-1)
	Sfx.play("victory" if result == "victory" else "defeat")
	hud.show_end(result)
	combat_finished.emit(result)
	if _options.quit_on_end:
		get_tree().create_timer(QUIT_DELAY_S).timeout.connect(_quit)


func _quit() -> void:
	get_tree().quit(0)


# --- animations -------------------------------------------------------------------------------

func _build_fighters() -> void:
	for id: int in mirror.fighters:
		var f := mirror.fighter(id)
		var is_party := int(f.team) == Combatant.Team.PARTY
		var data := _find_data(String(f.data_id), is_party)
		if data == null:
			push_error("CombatController: no data resource for '%s'" % String(f.data_id))
			continue
		_data_by_id[id] = data
		view.add_fighter(id, is_party, int(f.slot), data)
	hud.build_fighters(mirror, _data_by_id)
	view.sync_alive(mirror)
	_refresh()
	# Warm-up: draw every effect once so the first parry has no shader-compile hitch.
	view.warm_up()
	hud.warm_up()
	await get_tree().process_frame
	await get_tree().process_frame
	view.finish_warm_up()
	hud.finish_warm_up()


## Dash, strike, damage, hold, return (DESIGN.md 2.2, about 0.55 s).
func _play_party_action(ev: Dictionary) -> void:
	var actor := int(ev.actor)
	var ability := _abilities.get(String(ev.ability)) as AbilityData
	var targets: Array = ev.targets
	var target := int(targets[0]) if not targets.is_empty() else -1
	if target < 0 and not mirror.enemy_ids.is_empty():
		target = mirror.enemy_ids[0]
	var actors: Array[int] = [actor]
	var sfx := ability.impact_sfx if ability != null else "strike"
	await _strike(actors, target, sfx, _take_following(), false)
	_set_active_pose(-1)


func _play_counter(ev: Dictionary) -> void:
	var actors: Array[int] = []
	actors.assign(ev.actors)
	var team := bool(ev.team)
	if team:
		hud.show_center_banner("TEAM COUNTER!", HudStyle.GOLD, TEAM_BANNER_MS)
	await _strike(actors, int(ev.target), "team_counter" if team else "counter", _take_following(), true)


## Pops the damage/downed events that belong to the strike now being played.
func _take_following() -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	while not _queue.is_empty() and String(_queue[0].get("type", "")) in ["damage", "downed"]:
		taken.append(_queue.pop_front())
	return taken


func _strike(actors: Array[int], target: int, sfx: String, results: Array[Dictionary], is_counter: bool) -> void:
	var enemy := view.fighter(target)
	var dash_s := float(_tuning.action_dash_ms) / 1000.0
	var return_s := float(_tuning.action_return_ms) / 1000.0
	var strike_at := view.strike_point(target)
	for i: int in actors.size():
		var v := view.fighter(actors[i])
		if v == null:
			continue
		var spread := Vector3(0.0, 0.0, (float(i) - float(actors.size() - 1) * 0.5) * TEAM_SPREAD)
		v.set_pose(FighterView.CharPose.READY)
		var tween := v.create_tween()
		tween.tween_property(v, "body_offset", strike_at + spread - v.position, dash_s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait_ms(_tuning.action_dash_ms)

	for id: int in actors:
		var v := view.fighter(id)
		if v != null:
			v.set_pose(FighterView.CharPose.STRIKE)
	if enemy != null:
		view.spawn_slash(enemy.centre_position(), true)
	Sfx.play(sfx)
	if is_counter:
		view.camera.shake(_visuals.shake_counter, _visuals.shake_counter_ms)
		view.camera.punch(_visuals.punch_counter, _visuals.punch_ms)
	else:
		view.camera.shake(_visuals.shake_strike, _visuals.shake_strike_ms)
	for ev: Dictionary in results:
		mirror.apply(ev)
		if String(ev.type) == "damage":
			_show_damage(ev)
		elif String(ev.type) == "downed":
			_show_downed(int(ev.target))
		event_played.emit(ev)
	_refresh()
	await _wait_ms(_tuning.action_hold_ms + (_tuning.hitstop_counter_ms if is_counter else 0))

	for id: int in actors:
		var v := view.fighter(id)
		if v == null:
			continue
		v.set_pose(FighterView.CharPose.IDLE if mirror.is_alive(id) else FighterView.CharPose.DOWN)
		var tween := v.create_tween()
		tween.tween_property(v, "body_offset", Vector3.ZERO, return_s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _wait_ms(_tuning.action_return_ms)


func _show_damage(ev: Dictionary) -> void:
	var v := view.fighter(int(ev.target))
	if v == null:
		return
	var to_enemy := not mirror.party_ids.has(int(ev.target))
	hud.damage_number(int(ev.amount), v.head_position(), HudStyle.DAMAGE_DEALT if to_enemy else HudStyle.DAMAGE_TAKEN)
	v.flash(_visuals.flash_ms)
	if mirror.is_alive(int(ev.target)):
		v.play_pose(EnemyChoreography.Pose.HURT if to_enemy else FighterView.CharPose.HURT, _visuals.hurt_pose_ms)


func _show_downed(id: int) -> void:
	var v := view.fighter(id)
	if v == null:
		return
	Sfx.play("downed")
	v.clear_timed_pose()
	v.set_grey(1.0)
	v.set_glow(0.0)
	if mirror.party_ids.has(id):
		v.set_pose(FighterView.CharPose.DOWN)
	else:
		v.set_pose(EnemyChoreography.Pose.HURT)


## Ready pose for the party member whose turn it is (-1: nobody).
func _set_active_pose(actor: int) -> void:
	for id: int in mirror.party_ids:
		var v := view.fighter(id)
		if v == null or not mirror.is_alive(id):
			continue
		v.set_pose(FighterView.CharPose.READY if id == actor else FighterView.CharPose.IDLE)


func _refresh() -> void:
	hud.refresh(mirror, _practice_text())


# --- practice tools ---------------------------------------------------------------------------

func _handle_practice(event: InputEvent, key: Key) -> bool:
	if event.is_action_pressed("debug_overlay", false, true):
		hud.overlay.toggle()
		return true
	if key == KEY_NONE:
		return false
	if hud.overlay.visible:
		match key:
			KEY_R:
				PlayerSettings.set_show_timing_ring(not PlayerSettings.show_timing_ring(_tuning))
				return true
			KEY_F:
				_options.telegraph_flash = not _options.telegraph_flash
				return true
			KEY_T:
				_options.timing_readout = not _options.timing_readout
				return true
	match key:
		KEY_F2:
			# Only while the game waits for a menu choice, never during an enemy attack.
			if hud.action_menu.is_open() and not runner.is_active():
				hud.calibration.open()
			return true
		KEY_I:
			_enqueue(_submit(CombatCommands.practice({"invulnerable_party": not bool(mirror.practice.invulnerable_party)})))
			return true
		KEY_O:
			_enqueue(_submit(CombatCommands.practice({"immortal_enemies": not bool(mirror.practice.immortal_enemies)})))
			return true
		KEY_R:
			restart_requested.emit()
			return true
	var index := PRACTICE_ATTACK_KEYS.find(key)
	if index >= 0:
		var attacks := _practice_attacks()
		if index < attacks.size():
			_enqueue(_submit(CombatCommands.practice({"force_attack": attacks[index].id})))
		return true
	return false


## The attacks of the first living enemy (what 1-5 force).
func _practice_attacks() -> Array[EnemyAttackData]:
	var list: Array[EnemyAttackData] = []
	for id: int in mirror.living_enemy_ids():
		var data := _data_by_id.get(id) as EnemyData
		if data != null:
			for attack: EnemyAttackData in data.attacks:
				if attack != null:
					list.append(attack)
			break
	return list


func _practice_text() -> String:
	if not _tuning.practice_tools_enabled:
		return ""
	var forced := String(mirror.practice.get("force_attack", ""))
	var attacks := _practice_attacks()
	var lines := PackedStringArray()
	lines.append("PRACTICE   next attack: " + ("random" if forced.is_empty() else _attack_name(forced)))
	var keys := PackedStringArray()
	for i: int in mini(attacks.size(), PRACTICE_ATTACK_KEYS.size()):
		keys.append("%d %s" % [i + 1, attacks[i].display_name])
		if keys.size() == PRACTICE_KEYS_PER_LINE:
			lines.append("   ".join(keys))
			keys.clear()
	if not keys.is_empty():
		lines.append("   ".join(keys))
	lines.append("I party invulnerable: " + _on_off(bool(mirror.practice.get("invulnerable_party", false))))
	lines.append("O enemy immortal: " + _on_off(bool(mirror.practice.get("immortal_enemies", false))))
	lines.append("R restart   F1 stats   F2 calibrate")
	return "\n".join(lines)


func _attack_name(attack_id: String) -> String:
	for attack: EnemyAttackData in _practice_attacks():
		if attack.id == attack_id:
			return attack.display_name
	return attack_id


static func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


# --- helpers ----------------------------------------------------------------------------------

## A real-time wait owned by this node: if the fight is freed (restart) the wait simply never
## resumes, so no coroutine wakes up on a freed controller.
func _wait_ms(ms: int) -> void:
	if ms <= 0:
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = float(ms) / 1000.0
	add_child(timer)
	timer.start()
	await timer.timeout
	timer.queue_free()


func _pick_seed() -> int:
	if _options.seed_override >= 0:
		return _options.seed_override
	if _tuning.fixed_seed != 0:
		return _tuning.fixed_seed
	return randi_range(1, 2147483646)


func _find_data(data_id: String, is_party: bool) -> Resource:
	if is_party:
		for c: CharacterData in _encounter.party:
			if c != null and c.id == data_id:
				return c
	else:
		for e: EnemyData in _encounter.enemies:
			if e != null and e.id == data_id:
				return e
	return null


## Loads every sound and texture now so nothing loads in the middle of an attack.
func _warm_up_assets(setup: CombatSetup) -> void:
	Sfx.preload_all()
	for c: CharacterData in setup.party:
		AssetLoader.texture(c.sprite_path, Vector2i(256, 48))
		AssetLoader.texture(c.portrait_path, Vector2i(24, 24))
	for e: EnemyData in setup.enemies:
		AssetLoader.texture(e.sprite_path, Vector2i(384, 64))
		AssetLoader.texture(e.portrait_path, Vector2i(24, 24))
	for path: String in [_visuals.spark_path, _visuals.shockwave_path, _visuals.shadow_path,
			_visuals.slash_path, _visuals.floor_tile_path, _visuals.backdrop_path,
			_visuals.lock_icon_path, _visuals.ap_pip_path, _visuals.ap_pip_empty_path]:
		AssetLoader.texture(path)


static func _pressed_key(event: InputEvent) -> Key:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return KEY_NONE
	return key.physical_keycode
