class_name TimedSequenceRunner
extends Node
## Plays one enemy attack on this machine (DESIGN.md 3 and 4.5).
##
## On timed_sequence_declared the controller calls start(). After attack_lead_in_ms (banner up)
## the AttackClock starts. Presses arrive from DefenseInput and are judged at once by this
## machine's DefenseJudge (phase 1: the one local player answers every prompt), converted to
## attack time. Every frame, after input: scheduled contact effects fire, judge.advance() expires
## missed prompts (the hit lands), and released results go to the engine as resolve_prompts. The
## prompt events that come back are applied to the mirror at once; everything from
## sequence_resolved on is handed back (finished) only when the local animation is over.
##
## Feedback comes from the judge at press time, never from engine events: decide early, show at
## contact (attack time max(press, impact)). Enemy motion, the ground wave and the training ring
## are pure functions of attack time, so hit-stop (AttackClock.pause_for) freezes them exactly.

## Everything from sequence_resolved on, to be played by the controller.
signal finished(tail: Array[Dictionary])
## Every judged press (a DefenseJudge.press() report), for statistics and the autoplay bot.
signal press_judged(action: int, report: Dictionary)

enum Anim {
	NONE,
	PARRY,
	DODGE,
	JUMP,
	WHIFF,
	HURT,
}

## Share of a dodge pose spent sliding out and coming back.
const DODGE_OUT_SHARE: float = 0.25
const DODGE_BACK_SHARE: float = 0.3
## A jumping body counts as clear of a ground wave at this share of the jump height.
const JUMP_CLEAR_HEIGHT: float = 0.6
## A wave front reaching beyond the outer party slots needs at least two crests.
const MIN_WAVE_CRESTS: int = 2

var _submit: Callable
var _apply_now: Callable
var _mirror: CombatMirror
var _view: CombatView
var _hud: CombatHud
var _tuning: Tuning
var _visuals: CombatVisuals
var _options: CombatOptions
var _input: DefenseInput

var _active: bool = false
var _animating: bool = false
var _event: Dictionary = {}
var _seq: int = -1
var _source: int = -1
var _hits: Array = []
var _prompts: Array = []
var _targets: Array[int] = []
var _clock := AttackClock.new()
var _judge: DefenseJudge
var _latency_ms: int = 0
var _lead_in_end_us: int = 0
var _cues: Array[Dictionary] = []
var _next_cue: int = 0
## Contact effects waiting for their attack time: [{at_us, call: Callable}], in order.
var _scheduled: Array[Dictionary] = []
## Party member id -> {kind: Anim, frame, from_us, until_us, apex_us, land_us} (attack time).
var _anims: Dictionary = {}
## Attack times of every press (any result), for the MISS label.
var _press_times: Array[int] = []
## Hits a whiff was judged against (they never show MISS: the player did press).
var _whiffed_hits: Dictionary = {}
## Real time span of the hurt freeze on the last hit; presses inside it are still judged.
var _hurt_pause_from_us: int = -1
var _hurt_pause_to_us: int = -1
var _contact: Vector3 = Vector3.ZERO
var _tail: Array[Dictionary] = []
var _tail_received: bool = false
var _tail_t_us: int = 0
var _end_reason: String = ""
var _has_counter: bool = false
var _counter_ready_us: int = 0
var _wave_hit: int = -1
var _wave_dist: float = -1.0
## Real time start() ran (bystanders step aside from then).
var _started_us: int = 0
## Attack time of the first enemy motion (target arrows hide then).
var _first_motion_us: int = 0
var _last_frame_us: int = 0
var _longest_frame_us: int = 0
var _last_attack_longest_us: int = 0


func setup(submit: Callable, apply_now: Callable, mirror: CombatMirror, view: CombatView, hud: CombatHud,
		tuning: Tuning, visuals: CombatVisuals, options: CombatOptions, input: DefenseInput) -> void:
	_submit = submit
	_apply_now = apply_now
	_mirror = mirror
	_view = view
	_hud = hud
	_tuning = tuning
	_visuals = visuals
	_options = options
	_input = input
	_input.pressed.connect(_on_pressed)


## Starts playing a timed_sequence_declared event (already applied to the mirror).
func start(event: Dictionary) -> void:
	_event = event
	_seq = int(event.seq)
	_source = int(event.source)
	_prompts = event.prompts
	_targets.assign(event.targets)
	_latency_ms = PlayerSettings.latency_compensation_ms(_tuning)
	# Each hit carries its close time on this machine, so the enemy holds contact until then.
	_hits = EnemyChoreography.with_close_times(event.hits, _prompts, _latency_ms)
	_judge = DefenseJudge.new(_tuning.whiff_lockout_ms, _latency_ms, _tuning.press_reach_back_max_ms,
			_tuning.late_press_report_ms)
	_judge.set_prompts(_prompts)
	_clock = AttackClock.new()
	_started_us = Time.get_ticks_usec()
	_lead_in_end_us = _started_us + _tuning.attack_lead_in_ms * 1000
	_cues = EnemyChoreography.cues(_hits, _visuals)
	_first_motion_us = roundi(float(_cues[0].at_ms) * 1000.0) if not _cues.is_empty() else 0
	_next_cue = 0
	_scheduled.clear()
	_anims.clear()
	_press_times.clear()
	_whiffed_hits.clear()
	_hurt_pause_from_us = -1
	_hurt_pause_to_us = -1
	_tail.clear()
	_tail_received = false
	_has_counter = false
	_counter_ready_us = 0
	_end_reason = ""
	_wave_hit = -1
	_wave_dist = -1.0
	_longest_frame_us = 0
	_last_frame_us = Time.get_ticks_usec()
	_contact = _view.contact_point(_targets)
	# The runner moves the party every frame from here on: stop any leftover tweened movement.
	for id: int in _mirror.party_ids:
		var view := _view.fighter(id)
		if view != null:
			view.move_body(view.body_offset, 0.0)
	_active = true
	_animating = true
	_input.arm_all()
	_hud.show_banner(_banner_text())
	_hud.set_targeted(_targets)
	var enemy := _view.fighter(_source)
	if enemy != null:
		enemy.body_offset = Vector3.ZERO
		enemy.set_pose(EnemyChoreography.Pose.IDLE)


## True between start() and the hand-back.
func is_active() -> bool:
	return _active


## True while presses are being judged (the attack clock is running).
func is_defending() -> bool:
	return _active and _clock.is_started()


## Current attack time in microseconds (0 before the clock starts).
func attack_time_us() -> int:
	if not _clock.is_started():
		return 0
	return _clock.attack_time_us(Time.get_ticks_usec())


func is_clock_paused() -> bool:
	return _clock.is_started() and _clock.is_paused(Time.get_ticks_usec())


## The lag compensation the current judge uses.
func latency_us() -> int:
	return _latency_ms * 1000


## Longest frame (ms) during the current attack, or the last one if none is running.
func longest_frame_ms() -> float:
	return float(_longest_frame_us if _active else _last_attack_longest_us) / 1000.0


func _process(_delta: float) -> void:
	if not _animating:
		return
	var now := Time.get_ticks_usec()
	if _active:
		_longest_frame_us = maxi(_longest_frame_us, now - _last_frame_us)
		_last_frame_us = now
	if not _clock.is_started():
		if now < _lead_in_end_us:
			_update_party(0)
			_update_target_arrows(0)
			return
		_clock.start(_lead_in_end_us)
		if bool(_event.get("alert_cue", false)):
			Sfx.play("alert")
	var t := _clock.attack_time_us(now)
	if _active:
		_fire_scheduled(t)
		_expire(t)
		_release(t)
		_fire_cues(t)
	_update_enemy(t)
	if _active:
		_update_party(t)
		_update_wave(t)
		_update_rings(t)
		_update_lock(t)
		_update_target_arrows(t)
		# Read the time again: a contact effect above may have just started a hit-stop.
		_check_finish(Time.get_ticks_usec(), t)
	elif _enemy_settled(t):
		_animating = false


# --- presses ----------------------------------------------------------------------------------

func _on_pressed(action: int, stamp_us: int, previous_pump_us: int, _device: int) -> void:
	if not _active or not _clock.is_started():
		return
	# Every target went down: what is left of the attack is only animation.
	if _tail_received and _end_reason != "completed":
		return
	var t := _clock.attack_time_us(stamp_us)
	var earliest := -1
	if _clock.is_paused(stamp_us):
		# Presses during a success freeze are ignored: no judgement, no lockout (DESIGN.md 3.3).
		# The hurt freeze on a last hit is the exception: every prompt is resolved by then, so the
		# press can only be a LATE report, judged at the time it would have had without the freeze.
		if stamp_us < _hurt_pause_from_us or stamp_us >= _hurt_pause_to_us:
			return
		t += stamp_us - _hurt_pause_from_us
	elif previous_pump_us > 0 and previous_pump_us < stamp_us:
		var e := _clock.attack_time_us(previous_pump_us)
		if e >= 0:
			earliest = e
	var report := _judge.press(action, t, earliest)
	if int(report.result) == DefenseJudge.Result.SUCCESS and not _any_pending(report.prompts):
		report.result = DefenseJudge.Result.DONE
	_press_times.append(t)
	# Hits this press expired (after a long frame) land now, while still pending, so they get
	# their hit feedback before the results go to the engine.
	_expire(t)
	_options.stats.record(action, report)
	press_judged.emit(action, report)
	match int(report.result):
		DefenseJudge.Result.SUCCESS:
			_on_success(action, report, t)
		DefenseJudge.Result.WHIFF:
			_on_whiff(action, report, t)
		DefenseJudge.Result.LOCKED:
			Sfx.play("locked", _visuals.locked_click_volume_db)
	_release(t)


func _on_success(action: int, report: Dictionary, t: int) -> void:
	var hit_index := int(report.hit)
	var hit: Dictionary = _hits[hit_index]
	var impact_us := int(hit.at_ms) * 1000
	var characters: Array[int] = []
	var contact_us := maxi(t, impact_us)
	for idx: int in report.prompts:
		if not _is_pending(idx):
			continue
		var prompt: Dictionary = _prompts[idx]
		var id := int(prompt.character)
		characters.append(id)
		var late_us := int((prompt.windows[action] as Array)[1])
		contact_us = maxi(contact_us, _start_defence_anim(id, action, t, impact_us, late_us))
	if characters.is_empty():
		return
	_schedule(contact_us, _on_contact.bind(action, hit_index, characters, int(report.offset_us)))


func _on_whiff(action: int, report: Dictionary, t: int) -> void:
	Sfx.play("whiff")
	var reason := int(report.reason)
	var offset_ms := roundi(float(report.offset_us) / 1000.0)
	var text := "LATE"
	var color := HudStyle.LATE
	match reason:
		DefenseJudge.Reason.EARLY:
			text = "EARLY"
			color = HudStyle.EARLY
		DefenseJudge.Reason.WRONG_ACTION:
			color = HudStyle.WRONG
			text = "PARRY!"
			var hit_index := int(report.hit)
			if hit_index >= 0 and int((_hits[hit_index] as Dictionary).kind) == AttackHitData.Kind.GROUND:
				text = "JUMP!"
	if reason != DefenseJudge.Reason.WRONG_ACTION and _options.timing_readout and int(report.hit) >= 0:
		text += " " + HudStyle.signed_ms(offset_ms)
	if int(report.hit) >= 0:
		_whiffed_hits[int(report.hit)] = true
	var defenders := _living_targets()
	for id: int in defenders:
		var current: Dictionary = _anims.get(id, {})
		# Keep a flinch (the hit is what happened) and a successful defence still playing (a
		# double tap must not drop a jumper to the ground); flash, sound and readout still show.
		if not current.is_empty() and int(current.kind) != Anim.WHIFF and t < int(current.until_us):
			_view.fighter(id).flash(_visuals.flash_ms, color, _visuals.whiff_flash_strength)
			continue
		_anims[id] = {"kind": Anim.WHIFF, "frame": _pose_for_action(action), "from_us": t,
				"until_us": t + _visuals.whiff_pose_ms * 1000}
		_view.fighter(id).flash(_visuals.flash_ms, color, _visuals.whiff_flash_strength)
	_hud.popup(text, _focus_head(defenders), color)


## Contact moment of a successful defence: sound, flash, sparks, hit-stop, popup.
func _on_contact(action: int, hit_index: int, characters: Array[int], offset_us: int) -> void:
	var now := Time.get_ticks_usec()
	var final := hit_index == _hits.size() - 1
	var text := ""
	var color := HudStyle.PARRY
	match action:
		Defense.Outcome.PARRY:
			text = "PARRY"
			Sfx.play("parry_final" if final else "parry")
			_clock.pause_for(now, (_tuning.hitstop_parry_final_ms if final else _tuning.hitstop_parry_ms) * 1000)
			_view.camera.shake(_visuals.shake_parry_final if final else _visuals.shake_parry, _visuals.shake_parry_ms)
			_view.camera.punch(_visuals.punch_parry_final if final else _visuals.punch_parry, _visuals.punch_ms)
			var enemy := _view.fighter(_source)
			if enemy != null:
				enemy.flash(_visuals.flash_ms, Color.WHITE, _visuals.parry_enemy_flash_strength)
		Defense.Outcome.DODGE:
			text = "DODGE"
			color = HudStyle.DODGE
			Sfx.play("dodge")
		Defense.Outcome.JUMP:
			text = "JUMP"
			color = HudStyle.JUMP
			Sfx.play("jump")
			_clock.pause_for(now, _tuning.hitstop_jump_ms * 1000)
	if _options.timing_readout:
		text += " " + HudStyle.signed_ms(roundi(float(offset_us) / 1000.0))
	var shown: Array[int] = []
	var enemy_view := _view.fighter(_source)
	for id: int in characters:
		if not _mirror.is_alive(id):
			continue
		shown.append(id)
		var view := _view.fighter(id)
		if action == Defense.Outcome.PARRY:
			view.flash(_visuals.flash_ms)
			var at := view.centre_position()
			if enemy_view != null:
				at = at.lerp(enemy_view.centre_position(), _visuals.spark_toward_enemy)
			_view.spawn_sparks(at, _visuals.sparks_per_parry)
		elif action == Defense.Outcome.JUMP:
			view.flash(_visuals.flash_ms, HudStyle.JUMP, _visuals.jump_flash_strength)
	# One readout per press, even when it answered several characters at once.
	if not shown.is_empty():
		_hud.popup(text, _focus_head(shown), color)


# --- per-frame steps --------------------------------------------------------------------------

func _schedule(at_us: int, call: Callable) -> void:
	var entry := {"at_us": at_us, "call": call}
	var i := _scheduled.size()
	while i > 0 and int(_scheduled[i - 1].at_us) > at_us:
		i -= 1
	_scheduled.insert(i, entry)


func _fire_scheduled(t: int) -> void:
	while not _scheduled.is_empty() and int(_scheduled[0].at_us) <= t:
		var entry: Dictionary = _scheduled.pop_front()
		(entry.call as Callable).call()


## Prompts whose windows all closed: the hit lands now (damage, flinch, sound, hit-stop).
func _expire(t: int) -> void:
	var expired := _judge.advance(t)
	if expired.is_empty():
		return
	var now := Time.get_ticks_usec()
	var sounded: Dictionary = {}
	for idx: int in expired:
		if not _is_pending(idx):
			continue
		var prompt: Dictionary = _prompts[idx]
		var id := int(prompt.character)
		if not _mirror.is_alive(id):
			continue
		var hit_index := int(prompt.hit)
		if not sounded.has(hit_index):
			sounded[hit_index] = true
			Sfx.play(String((_hits[hit_index] as Dictionary).get("impact_sfx", "hurt")))
			# Only the last hit freezes: in a string the next lunge has often started by now.
			if hit_index == _hits.size() - 1 and _tuning.hitstop_hurt_ms > 0:
				_clock.pause_for(now, _tuning.hitstop_hurt_ms * 1000)
				_hurt_pause_from_us = now
				_hurt_pause_to_us = now + _tuning.hitstop_hurt_ms * 1000
			_view.camera.shake(_visuals.shake_hurt, _visuals.shake_hurt_ms)
		var view := _view.fighter(id)
		view.flash(_visuals.flash_ms, HudStyle.DAMAGE_TAKEN, _visuals.hurt_flash_strength)
		_anims[id] = {"kind": Anim.HURT, "frame": FighterView.CharPose.HURT, "from_us": t,
				"until_us": t + _visuals.hurt_pose_ms * 1000}
		# MISS first: popups in a column stack oldest on top, so the damage number (newest) stays
		# at the head and MISS sits just above it.
		if not _whiffed_hits.has(hit_index) and not _pressed_near(prompt):
			var rise := view.visible_height() * _visuals.miss_label_rise_factor
			_hud.popup("MISS", view.head_position() + Vector3(0.0, rise, 0.0), HudStyle.MISS)
		_hud.damage_number(int(prompt.damage), view.head_position(), HudStyle.DAMAGE_TAKEN)


## Sends the judge's released results to the engine and applies what comes back.
func _release(t: int) -> void:
	if _judge == null:
		return
	var ready := _judge.pop_ready()
	if ready.is_empty():
		return
	var results: Array[Dictionary] = []
	for r: Dictionary in ready:
		var idx := int(r.prompt)
		# Prompts the engine voided (their character went down) are no longer accepted.
		if _is_pending(idx):
			results.append(CombatCommands.prompt_result(idx, int(r.outcome), int(r.offset_us)))
	if results.is_empty():
		return
	var events: Array[Dictionary] = _submit.call(CombatCommands.resolve_prompts(_seq, results))
	var in_tail := _tail_received
	for ev: Dictionary in events:
		var type := String(ev.get("type", ""))
		if type == "sequence_resolved":
			in_tail = true
			_tail_received = true
			_tail_t_us = t
			_end_reason = String(ev.get("reason", ""))
		if type == "prompts_voided":
			_judge.void_prompts(ev.get("prompts", []) as Array)
		# Practice toggles are not part of any animation: apply them at once even in the tail,
		# so a newer toggle can never be overwritten by this older snapshot later.
		if in_tail and type != "practice_changed":
			_tail.append(ev)
			if type == "counter":
				_has_counter = true
		else:
			_apply_now.call(ev)


func _fire_cues(t: int) -> void:
	var t_ms := float(t) / 1000.0
	while _next_cue < _cues.size() and t_ms >= float(_cues[_next_cue].at_ms):
		var cue: Dictionary = _cues[_next_cue]
		_next_cue += 1
		var enemy := _view.fighter(_source)
		if _options.telegraph_flash and enemy != null:
			enemy.flash(_visuals.telegraph_flash_ms, _visuals.telegraph_flash_color, _visuals.telegraph_flash_strength)
		match String(cue.type):
			EnemyChoreography.CUE_SLAM:
				if _options.motion_sounds:
					Sfx.play("slam")
				_wave_hit = int(cue.hit)
				_wave_dist = -1.0
			_:
				if _options.motion_sounds:
					Sfx.play("lunge")


func _update_enemy(t: int) -> void:
	var enemy := _view.fighter(_source)
	if enemy == null:
		return
	var s := EnemyChoreography.sample(_hits, float(t) / 1000.0, _visuals)
	enemy.set_pose(int(s.pose))
	enemy.set_glow(float(s.glow))
	var travel := _contact - enemy.position
	travel.y = 0.0
	enemy.body_offset = travel * float(s.approach)


func _enemy_settled(t: int) -> bool:
	var s := EnemyChoreography.sample(_hits, float(t) / 1000.0, _visuals)
	if float(s.approach) > 0.0 or int(s.pose) != EnemyChoreography.Pose.IDLE:
		return false
	if t < _last_impact_us():
		return false
	var enemy := _view.fighter(_source)
	if enemy != null:
		enemy.body_offset = Vector3.ZERO
		enemy.set_glow(0.0)
	return true


func _update_party(t: int) -> void:
	# During a single-target attack the others step back and dim, so the lunge lane and the
	# target read clearly (they ease aside at the speed party members return to their spots).
	var single := int(_event.get("mode", 0)) != EnemyAttackData.TargetMode.PARTY
	var step := clampf(float(Time.get_ticks_usec() - _started_us) / float(maxi(1, _tuning.action_return_ms * 1000)), 0.0, 1.0)
	for id: int in _mirror.party_ids:
		var view := _view.fighter(id)
		if view == null:
			continue
		if not _mirror.is_alive(id):
			view.set_pose(FighterView.CharPose.DOWN)
			view.set_grey(1.0)
			view.body_offset = Vector3.ZERO
			continue
		var pose := FighterView.CharPose.READY if _targets.has(id) else FighterView.CharPose.IDLE
		var offset := Vector3.ZERO
		var bystander := single and not _targets.has(id)
		if bystander:
			offset = _away_from_contact(id) * _visuals.bystander_step_back * (1.0 - (1.0 - step) * (1.0 - step))
		view.set_tint(Color.WHITE.lerp(_visuals.bystander_tint, step) if bystander else Color.WHITE)
		var anim: Dictionary = _anims.get(id, {})
		if not anim.is_empty() and t < int(anim.until_us):
			pose = int(anim.frame)
			offset += _anim_offset(id, anim, t)
		view.set_pose(pose)
		view.body_offset = offset


## Flat direction from the contact point to this party member's home.
func _away_from_contact(id: int) -> Vector3:
	var away := _view.home_of(id) - _contact
	away.y = 0.0
	return away.normalized() if away.length() > 0.0 else Vector3.LEFT


func _anim_offset(id: int, anim: Dictionary, t: int) -> Vector3:
	var from := float(anim.from_us)
	var until := float(anim.until_us)
	var away := _away_from_contact(id)
	match int(anim.kind):
		Anim.DODGE:
			var length := maxf(1.0, until - from)
			var s := (float(t) - from) / length
			var k := 1.0
			if s < DODGE_OUT_SHARE:
				k = 1.0 - pow(1.0 - s / DODGE_OUT_SHARE, 2.0)
			elif s > 1.0 - DODGE_BACK_SHARE:
				k = 1.0 - (s - (1.0 - DODGE_BACK_SHARE)) / DODGE_BACK_SHARE
			return away * _visuals.dodge_slide_distance * clampf(k, 0.0, 1.0)
		Anim.JUMP:
			var apex := float(anim.apex_us)
			var land := float(anim.land_us)
			var y := 0.0
			if float(t) < apex:
				var u := clampf((float(t) - from) / maxf(1.0, apex - from), 0.0, 1.0)
				y = 1.0 - (1.0 - u) * (1.0 - u)
			else:
				var u := clampf((float(t) - apex) / maxf(1.0, land - apex), 0.0, 1.0)
				y = 1.0 - u * u
			return Vector3(0.0, _visuals.jump_height * y, 0.0)
		Anim.HURT:
			var s := clampf((float(t) - from) / maxf(1.0, until - from), 0.0, 1.0)
			return away * _visuals.hurt_knockback * (1.0 - s) * (1.0 - s)
	return Vector3.ZERO


## Places the ground-wave crests: a front parallel to the party line that reaches it at impact.
func _update_wave(t: int) -> void:
	if _wave_hit < 0:
		return
	var hit: Dictionary = _hits[_wave_hit]
	var approach := maxf(1.0, float(hit.approach_ms))
	var u := (float(t) / 1000.0 - (float(hit.at_ms) - approach)) / approach
	# Fully visible until the hit can no longer be jumped (a missed jump's damage lands on it),
	# then it fades out while travelling on past the party.
	var close_u := 1.0 + float(hit.get("close_ms", 0.0)) / approach
	var gone_u := close_u + float(_visuals.wave_fade_ms) / approach
	if u > gone_u:
		_wave_hit = -1
		_view.hide_wave()
		return
	var line := _party_line()
	var a: Vector3 = line[0]
	var b: Vector3 = line[1]
	var along := b - a
	along.y = 0.0
	along = along.normalized() if along.length() > 0.0 else Vector3.BACK
	var normal := Vector3(along.z, 0.0, -along.x)
	var enemy := _view.fighter(_source)
	var enemy_pos := enemy.body_position() if enemy != null else _contact
	if normal.dot(enemy_pos - a) < 0.0:
		normal = -normal
	if _wave_dist < 0.0:
		_wave_dist = maxf(normal.dot(enemy_pos - a), _visuals.wave_min_travel)
	var front := normal * _wave_dist * (1.0 - u)
	var margin := along * _visuals.wave_line_margin
	var count := maxi(MIN_WAVE_CRESTS, _visuals.wave_crest_count)
	var points: Array[Vector3] = []
	for i: int in count:
		var p := (a - margin).lerp(b + margin, float(i) / float(count - 1)) + front
		p.y = 0.0
		points.append(p)
	var alpha := 1.0 if u <= close_u else 1.0 - (u - close_u) / maxf(0.001, gone_u - close_u)
	_view.set_wave(points, clampf(minf(alpha, u * 4.0 + 0.2), 0.0, 1.0))


func _update_rings(t: int) -> void:
	if not bool(_event.get("allow_timing_ring", true)) or not PlayerSettings.show_timing_ring(_tuning):
		_hud.set_rings([])
		return
	var rings: Array[Dictionary] = []
	var lead := _tuning.ring_lead_ms * 1000
	for prompt: Dictionary in _prompts:
		var at := int(prompt.at_ms) * 1000
		if t < at - lead or t > at:
			continue
		var id := int(prompt.character)
		if not _mirror.is_alive(id):
			continue
		var u := float(t - (at - lead)) / float(maxi(1, lead))
		var ground := int(prompt.kind) == AttackHitData.Kind.GROUND
		rings.append({
			"pos": _view.screen_position(_view.fighter(id).centre_position()),
			"radius": lerpf(_visuals.ring_start_radius_px, _visuals.ring_end_radius_px, u),
			"color": HudStyle.RING_GROUND if ground else HudStyle.RING_NORMAL,
			"label": "JUMP" if ground else "",
		})
	_hud.set_rings(rings)


func _update_lock(t: int) -> void:
	if _judge.is_locked_out(t):
		var defenders := _living_targets()
		_hud.set_lock(true, _focus_feet(defenders))
	else:
		_hud.set_lock(false)


## Hands the tail back once the local animation is over (DESIGN.md 4.5).
func _check_finish(now: int, t: int) -> void:
	# Wait for every contact effect of this attack (a jump's contact comes after impact).
	if not _tail_received or _clock.is_paused(now) or not _scheduled.is_empty():
		return
	if _has_counter:
		# The counter follows the final hit-stop after counter_delay_ms.
		if t < _last_impact_us():
			return
		if _counter_ready_us == 0:
			_counter_ready_us = maxi(now, _clock.last_pause_end_us()) + _tuning.counter_delay_ms * 1000
		if now >= _counter_ready_us:
			_hand_back()
		return
	var end_at := _last_impact_us() if _end_reason == "completed" else _tail_t_us
	if t >= end_at + _tuning.attack_recover_ms * 1000:
		_hand_back()


func _hand_back() -> void:
	_active = false
	_last_attack_longest_us = _longest_frame_us
	_input.disarm()
	_hud.hide_banner()
	_hud.set_rings([])
	_hud.set_lock(false)
	_hud.set_targeted([])
	_hud.set_target_arrows([])
	_view.hide_wave()
	_wave_hit = -1
	var return_s := float(_tuning.action_return_ms) / 1000.0
	for id: int in _mirror.party_ids:
		var view := _view.fighter(id)
		if view == null:
			continue
		view.set_tint(Color.WHITE)
		if view.body_offset == Vector3.ZERO or not _mirror.is_alive(id):
			view.move_body(Vector3.ZERO, 0.0)
		else:
			# Bystanders walk back and jumpers come down; a counter dash replaces this movement.
			view.move_body(Vector3.ZERO, return_s, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var tail: Array[Dictionary] = _tail.duplicate()
	_tail.clear()
	finished.emit(tail)


# --- helpers ----------------------------------------------------------------------------------

## Starts the defence pose and returns the attack time of its contact moment (sound, popup,
## hit-stop): the impact, or the press if later; for a jump also not before the body is clear
## of the wave, so the freeze never shows a successful jump standing in it.
func _start_defence_anim(id: int, action: int, t: int, impact_us: int, late_us: int) -> int:
	var hold_until := impact_us + late_us
	var contact := maxi(t, impact_us)
	match action:
		Defense.Outcome.PARRY:
			_anims[id] = {"kind": Anim.PARRY, "frame": FighterView.CharPose.PARRY, "from_us": t,
					"until_us": maxi(hold_until, t + _visuals.parry_pose_min_ms * 1000)}
		Defense.Outcome.DODGE:
			_anims[id] = {"kind": Anim.DODGE, "frame": FighterView.CharPose.DODGE, "from_us": t,
					"until_us": maxi(hold_until, t + _visuals.dodge_pose_min_ms * 1000)}
		Defense.Outcome.JUMP:
			# Apex at impact when the press leaves time for it (up to half the airtime), else the
			# fastest rise; the whole jump lasts about jump_airtime_ms.
			var fast := _visuals.jump_rise_fast_ms * 1000
			var rise := clampi(impact_us - t, fast, maxi(fast, _visuals.jump_airtime_ms * 500))
			var apex := t + rise
			var fall := maxi(_visuals.jump_airtime_ms * 1000 - rise, fast)
			_anims[id] = {"kind": Anim.JUMP, "frame": FighterView.CharPose.JUMP, "from_us": t,
					"until_us": apex + fall, "apex_us": apex, "land_us": apex + fall}
			# The rise y = 1 - (1 - u)^2 reaches JUMP_CLEAR_HEIGHT at u = 1 - sqrt(1 - JUMP_CLEAR_HEIGHT).
			contact = maxi(contact, t + roundi(float(rise) * (1.0 - sqrt(1.0 - JUMP_CLEAR_HEIGHT))))
	return contact


## Arrows over the targets from the banner until the enemy starts moving.
func _update_target_arrows(t: int) -> void:
	var heads: Array[Vector3] = []
	if t < _first_motion_us:
		for id: int in _living_targets():
			heads.append(_view.fighter(id).head_position())
	_hud.set_target_arrows(heads)


func _pose_for_action(action: int) -> int:
	match action:
		Defense.Outcome.PARRY:
			return FighterView.CharPose.PARRY
		Defense.Outcome.DODGE:
			return FighterView.CharPose.DODGE
		Defense.Outcome.JUMP:
			return FighterView.CharPose.JUMP
	return FighterView.CharPose.READY


## True if any press happened between the earliest window edge of this prompt and now (press
## times compensated the way the judge compensates them).
func _pressed_near(prompt: Dictionary) -> bool:
	var earliest := 0
	for action: int in (prompt.windows as Dictionary):
		earliest = mini(earliest, int((prompt.windows[action] as Array)[0]))
	var from := int(prompt.at_ms) * 1000 + earliest
	for pressed_at: int in _press_times:
		if pressed_at - latency_us() >= from:
			return true
	return false


func _any_pending(idxs: Array) -> bool:
	for idx: int in idxs:
		if _is_pending(idx):
			return true
	return false


func _is_pending(idx: int) -> bool:
	if _mirror.sequence.is_empty() or int(_mirror.sequence.seq) != _seq:
		return false
	var states: Array = _mirror.sequence.states
	return idx >= 0 and idx < states.size() and int(states[idx]) == CombatEngine.PromptState.PENDING


func _living_targets() -> Array[int]:
	var list: Array[int] = []
	for id: int in _targets:
		if _mirror.is_alive(id):
			list.append(id)
	return list


## The middle of these fighters' feet (standing, ignoring jumps), for the lock icon.
func _focus_feet(ids: Array[int]) -> Vector3:
	var list := ids if not ids.is_empty() else _mirror.party_ids
	var sum := Vector3.ZERO
	var count := 0
	for id: int in list:
		var view := _view.fighter(id)
		if view != null:
			var feet := view.body_position()
			feet.y = 0.0
			sum += feet
			count += 1
	return sum / float(maxi(1, count))


## Above the middle of these fighters' standing heads (the party centre if the list is empty).
## Ignores a jump's lift, so a jump readout starts where a parry readout does.
func _focus_head(ids: Array[int]) -> Vector3:
	var list := ids if not ids.is_empty() else _mirror.party_ids
	var sum := Vector3.ZERO
	var count := 0
	for id: int in list:
		var view := _view.fighter(id)
		if view != null:
			sum += view.head_position() - Vector3(0.0, view.body_offset.y, 0.0)
			count += 1
	return sum / float(maxi(1, count))


## The first and last party slots' homes: the line ground waves travel toward.
func _party_line() -> Array[Vector3]:
	var ids := _mirror.party_ids
	var line: Array[Vector3] = [_contact, _contact]
	if ids.is_empty():
		return line
	line[0] = _view.home_of(ids[0])
	line[1] = _view.home_of(ids[ids.size() - 1])
	return line


func _last_impact_us() -> int:
	if _hits.is_empty():
		return 0
	return int((_hits[_hits.size() - 1] as Dictionary).at_ms) * 1000


func _banner_text() -> String:
	var enemy_name := String(_mirror.fighter(_source).get("display_name", "?"))
	var target_text := "WHOLE PARTY"
	if int(_event.get("mode", 0)) != EnemyAttackData.TargetMode.PARTY and _targets.size() == 1:
		target_text = String(_mirror.fighter(_targets[0]).get("display_name", "?")).to_upper()
	return "%s: %s -> %s" % [enemy_name.to_upper(), String(_event.get("name", "?")), target_text]
