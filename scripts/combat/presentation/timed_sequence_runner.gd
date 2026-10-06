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
## Sparks appear this far from the defender toward the attacker, as a share of the gap.
const SPARK_TOWARD_ENEMY: float = 0.35
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
var _contact: Vector3 = Vector3.ZERO
var _tail: Array[Dictionary] = []
var _tail_received: bool = false
var _tail_t_us: int = 0
var _end_reason: String = ""
var _has_counter: bool = false
var _counter_ready_us: int = 0
var _wave_hit: int = -1
var _wave_dist: float = -1.0
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
	_hits = event.hits
	_prompts = event.prompts
	_targets.assign(event.targets)
	_latency_ms = PlayerSettings.latency_compensation_ms(_tuning)
	_judge = DefenseJudge.new(_tuning.whiff_lockout_ms, _latency_ms)
	_judge.set_prompts(_prompts)
	_clock = AttackClock.new()
	_lead_in_end_us = Time.get_ticks_usec() + _tuning.attack_lead_in_ms * 1000
	_cues = EnemyChoreography.cues(_hits, _visuals)
	_next_cue = 0
	_scheduled.clear()
	_anims.clear()
	_press_times.clear()
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
	_active = true
	_animating = true
	_input.arm_all()
	_hud.show_banner(_banner_text())
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
		_check_finish(now, t)
	elif _enemy_settled(t):
		_animating = false


# --- presses ----------------------------------------------------------------------------------

func _on_pressed(action: int, stamp_us: int, previous_pump_us: int, _device: int) -> void:
	if not _active or not _clock.is_started():
		return
	# Presses during a freeze are ignored: no judgement, no lockout (DESIGN.md 3.3).
	if _clock.is_paused(stamp_us):
		return
	var t := _clock.attack_time_us(stamp_us)
	var earliest := -1
	if previous_pump_us > 0 and previous_pump_us < stamp_us:
		var e := _clock.attack_time_us(previous_pump_us)
		if e >= 0:
			earliest = e
	var report := _judge.press(action, t, earliest)
	_press_times.append(t)
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
	for idx: int in report.prompts:
		if not _is_pending(idx):
			continue
		var prompt: Dictionary = _prompts[idx]
		var id := int(prompt.character)
		characters.append(id)
		var late_us := int((prompt.windows[action] as Array)[1])
		_start_defence_anim(id, action, t, impact_us, late_us)
	if characters.is_empty():
		return
	_schedule(maxi(t, impact_us), _on_contact.bind(action, hit_index, characters, int(report.offset_us)))


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
	var defenders := _living_targets()
	for id: int in defenders:
		_anims[id] = {"kind": Anim.WHIFF, "frame": _pose_for_action(action), "from_us": t,
				"until_us": t + _visuals.whiff_pose_ms * 1000}
		_view.fighter(id).flash(_visuals.flash_ms, color, 0.35)
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
			_view.camera.shake(_visuals.shake_parry, _visuals.shake_parry_ms)
			_view.camera.punch(_visuals.punch_parry_final if final else _visuals.punch_parry, _visuals.punch_ms)
			var enemy := _view.fighter(_source)
			if enemy != null:
				enemy.flash(_visuals.flash_ms, Color.WHITE, 0.6)
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
	for id: int in characters:
		if not _mirror.is_alive(id):
			continue
		var view := _view.fighter(id)
		if action == Defense.Outcome.PARRY:
			view.flash(_visuals.flash_ms)
			var at := view.centre_position().lerp(_view.fighter(_source).centre_position(), SPARK_TOWARD_ENEMY) \
					if _view.fighter(_source) != null else view.centre_position()
			_view.spawn_sparks(at, _visuals.sparks_per_parry)
		elif action == Defense.Outcome.JUMP:
			view.flash(_visuals.flash_ms, HudStyle.JUMP, 0.5)
		_hud.popup(text, view.head_position(), color)


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
			_clock.pause_for(now, _tuning.hitstop_hurt_ms * 1000)
			_view.camera.shake(_visuals.shake_hurt, _visuals.shake_hurt_ms)
		var view := _view.fighter(id)
		view.flash(_visuals.flash_ms, HudStyle.DAMAGE_TAKEN, 0.8)
		_anims[id] = {"kind": Anim.HURT, "frame": FighterView.CharPose.HURT, "from_us": t,
				"until_us": t + _visuals.hurt_pose_ms * 1000}
		_hud.damage_number(int(prompt.damage), view.head_position(), HudStyle.DAMAGE_TAKEN)
		if not _pressed_near(prompt):
			_hud.popup("MISS", view.head_position() + Vector3(0.0, view.sprite_height() * 0.3, 0.0), HudStyle.MISS)


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
		if in_tail:
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
			enemy.flash(_visuals.telegraph_flash_ms, Color.WHITE, _visuals.telegraph_flash_strength)
		match String(cue.type):
			EnemyChoreography.CUE_SLAM:
				Sfx.play("slam")
				_wave_hit = int(cue.hit)
				_wave_dist = -1.0
			_:
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
		var anim: Dictionary = _anims.get(id, {})
		if not anim.is_empty() and t < int(anim.until_us):
			pose = int(anim.frame)
			offset = _anim_offset(id, anim, t)
		view.set_pose(pose)
		view.body_offset = offset


func _anim_offset(id: int, anim: Dictionary, t: int) -> Vector3:
	var from := float(anim.from_us)
	var until := float(anim.until_us)
	var away := _view.home_of(id) - _contact
	away.y = 0.0
	away = away.normalized() if away.length() > 0.0 else Vector3.LEFT
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
	var overshoot := float(_visuals.wave_overshoot_percent) / 100.0
	if u > 1.0 + overshoot:
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
	var alpha := 1.0 if u <= 1.0 else 1.0 - (u - 1.0) / maxf(0.001, overshoot)
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
		_hud.set_lock(true, _focus_head(defenders) + Vector3(0.0, 0.6, 0.0))
	else:
		_hud.set_lock(false)


## Hands the tail back once the local animation is over (DESIGN.md 4.5).
func _check_finish(now: int, t: int) -> void:
	if not _tail_received or _clock.is_paused(now):
		return
	if _has_counter:
		# The counter follows the final hit-stop after counter_delay_ms.
		if t < _last_impact_us():
			return
		if _counter_ready_us == 0:
			_counter_ready_us = now + _tuning.counter_delay_ms * 1000
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
	_view.hide_wave()
	_wave_hit = -1
	for id: int in _mirror.party_ids:
		var view := _view.fighter(id)
		if view != null:
			view.body_offset = Vector3.ZERO
	var tail: Array[Dictionary] = _tail.duplicate()
	_tail.clear()
	finished.emit(tail)


# --- helpers ----------------------------------------------------------------------------------

func _start_defence_anim(id: int, action: int, t: int, impact_us: int, late_us: int) -> void:
	var hold_until := impact_us + late_us
	match action:
		Defense.Outcome.PARRY:
			_anims[id] = {"kind": Anim.PARRY, "frame": FighterView.CharPose.PARRY, "from_us": t,
					"until_us": maxi(hold_until, t + _visuals.parry_pose_min_ms * 1000)}
		Defense.Outcome.DODGE:
			_anims[id] = {"kind": Anim.DODGE, "frame": FighterView.CharPose.DODGE, "from_us": t,
					"until_us": maxi(hold_until, t + _visuals.dodge_pose_min_ms * 1000)}
		Defense.Outcome.JUMP:
			# Apex at impact when the press is early enough; airtime about jump_airtime_ms.
			var rise_min := _visuals.jump_rise_min_ms * 1000
			var apex := maxi(impact_us, t + rise_min)
			var fall := maxi(_visuals.jump_airtime_ms * 1000 - (apex - t), rise_min)
			_anims[id] = {"kind": Anim.JUMP, "frame": FighterView.CharPose.JUMP, "from_us": t,
					"until_us": apex + fall, "apex_us": apex, "land_us": apex + fall}


func _pose_for_action(action: int) -> int:
	match action:
		Defense.Outcome.PARRY:
			return FighterView.CharPose.PARRY
		Defense.Outcome.DODGE:
			return FighterView.CharPose.DODGE
		Defense.Outcome.JUMP:
			return FighterView.CharPose.JUMP
	return FighterView.CharPose.READY


## True if any press happened between the earliest window edge of this prompt and now.
func _pressed_near(prompt: Dictionary) -> bool:
	var earliest := 0
	for action: int in (prompt.windows as Dictionary):
		earliest = mini(earliest, int((prompt.windows[action] as Array)[0]))
	var from := int(prompt.at_ms) * 1000 + earliest
	for pressed_at: int in _press_times:
		if pressed_at >= from:
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


## Above the middle of these fighters' heads (the party centre if the list is empty).
func _focus_head(ids: Array[int]) -> Vector3:
	var list := ids if not ids.is_empty() else _mirror.party_ids
	var sum := Vector3.ZERO
	var count := 0
	for id: int in list:
		var view := _view.fighter(id)
		if view != null:
			sum += view.head_position()
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
