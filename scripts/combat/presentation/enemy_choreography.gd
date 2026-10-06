class_name EnemyChoreography
extends RefCounted
## The enemy's attack animation as a pure function of attack time (DESIGN.md 3.3 and 3.7).
## Because it only depends on the AttackClock, hit-stop freezes it exactly and what you see always
## matches what is judged: every normal lunge lasts approach_ms and reaches the contact point
## exactly at impact; a ground hit launches its wave approach_ms before impact.
##
## `hits` are the hit dictionaries of a timed_sequence_declared event (at_ms, kind, approach_ms,
## feint). `approach` in the result is 0 at the enemy's home and 1 at the contact point.

## Frames of an enemy sheet (DESIGN.md 5.3).
enum Pose {
	IDLE,
	WINDUP,
	LUNGE,
	CONTACT,
	HURT,
	SLAM,
}

const CUE_LUNGE := "lunge"
const CUE_FEINT := "feint"
const CUE_SLAM := "slam"


## {pose: Pose, approach: float, glow: float (0..1 wind-up glow)} at attack time `t_ms`.
static func sample(hits: Array, t_ms: float, v: CombatVisuals) -> Dictionary:
	if hits.is_empty() or t_ms < 0.0:
		return _pose(Pose.IDLE, 0.0, 0.0)
	var rest := 0.0
	var hold_from := 0.0
	for i: int in hits.size():
		var hit: Dictionary = hits[i]
		var impact := float(hit.at_ms)
		var approach_ms := maxf(1.0, float(hit.approach_ms))
		var start := _motion_start(hits, i, v)
		var lunge_start := maxf(impact - approach_ms, hold_from)
		var is_last := i == hits.size() - 1
		if t_ms < start:
			return _pose(Pose.WINDUP, rest, _ramp(t_ms, hold_from, start))

		if int(hit.kind) == AttackHitData.Kind.GROUND:
			var slam_end := start + float(v.slam_hold_ms)
			if not is_last:
				slam_end = minf(slam_end, _motion_start(hits, i + 1, v))
			if t_ms < slam_end:
				return _pose(Pose.SLAM, rest, 1.0 - _ramp(t_ms, start, slam_end))
			if is_last:
				var back_from := maxf(slam_end, impact)
				if t_ms < back_from:
					return _pose(Pose.IDLE, rest, 0.0)
				return _pose(Pose.IDLE, lerpf(rest, 0.0, _smooth(_ramp(t_ms, back_from, back_from + float(v.return_ms)))), 0.0)
			hold_from = slam_end
			continue

		var from := rest
		if bool(hit.feint):
			var portion := float(v.feint_portion_percent) / 100.0
			var feint_end := start + approach_ms * portion
			if t_ms < feint_end:
				var u := (t_ms - start) / approach_ms
				return _pose(Pose.LUNGE, rest + (1.0 - rest) * u * u, 1.0 - u)
			from = rest + (1.0 - rest) * portion * portion
			if t_ms < lunge_start:
				return _pose(Pose.WINDUP, from, _ramp(t_ms, feint_end, lunge_start))
		if t_ms < impact:
			var u := clampf((t_ms - lunge_start) / maxf(1.0, impact - lunge_start), 0.0, 1.0)
			return _pose(Pose.LUNGE, from + (1.0 - from) * u * u, 1.0 - u)

		if is_last:
			var hold_end := impact + float(v.contact_hold_ms)
			if t_ms < hold_end:
				return _pose(Pose.CONTACT, 1.0, 0.0)
			var back := _smooth(_ramp(t_ms, hold_end, hold_end + float(v.return_ms)))
			return _pose(Pose.IDLE, 1.0 - back, 0.0)

		var available := maxf(0.0, _motion_start(hits, i + 1, v) - impact)
		var hold := minf(float(v.contact_hold_ms), available * 0.5)
		var recoil := minf(float(v.recoil_ms), available - hold)
		var recoiled := 1.0 - float(v.recoil_percent) / 100.0
		if t_ms < impact + hold:
			return _pose(Pose.CONTACT, 1.0, 0.0)
		if t_ms < impact + hold + recoil:
			var r := _ramp(t_ms, impact + hold, impact + hold + recoil)
			return _pose(Pose.IDLE, lerpf(1.0, recoiled, 1.0 - (1.0 - r) * (1.0 - r)), 0.0)
		rest = recoiled
		hold_from = impact + hold + recoil
	return _pose(Pose.IDLE, 0.0, 0.0)


## Moments where something starts, in attack time: [{at_ms, type, hit}], type is CUE_LUNGE,
## CUE_FEINT or CUE_SLAM. Used for the telegraph flash, the lunge and slam sounds and the wave.
static func cues(hits: Array, v: CombatVisuals) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for i: int in hits.size():
		var hit: Dictionary = hits[i]
		var lunge_start := float(hit.at_ms) - float(hit.approach_ms)
		if i > 0:
			lunge_start = maxf(lunge_start, float((hits[i - 1] as Dictionary).at_ms))
		lunge_start = maxf(lunge_start, 0.0)
		if int(hit.kind) == AttackHitData.Kind.GROUND:
			list.append({"at_ms": lunge_start, "type": CUE_SLAM, "hit": i})
			continue
		if bool(hit.feint):
			list.append({"at_ms": _motion_start(hits, i, v), "type": CUE_FEINT, "hit": i})
		list.append({"at_ms": lunge_start, "type": CUE_LUNGE, "hit": i})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.at_ms) < float(b.at_ms))
	return list


## When the visible motion for hit `i` starts (feint false start, lunge or slam).
static func _motion_start(hits: Array, i: int, v: CombatVisuals) -> float:
	var hit: Dictionary = hits[i]
	var start := float(hit.at_ms) - float(hit.approach_ms)
	if int(hit.kind) == AttackHitData.Kind.NORMAL and bool(hit.feint):
		start -= float(v.feint_lead_ms)
	if i > 0:
		start = maxf(start, float((hits[i - 1] as Dictionary).at_ms))
	return maxf(start, 0.0)


static func _ramp(t: float, from: float, to: float) -> float:
	if to <= from:
		return 1.0
	return clampf((t - from) / (to - from), 0.0, 1.0)


static func _smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


static func _pose(pose: Pose, approach: float, glow: float) -> Dictionary:
	return {"pose": pose, "approach": clampf(approach, 0.0, 1.0), "glow": clampf(glow, 0.0, 1.0)}
