class_name AttackClock
extends RefCounted
## Converts real time (Time.get_ticks_usec()) into "attack time": microseconds since the attack
## started, not counting hit-stop pauses. Hit times, enemy animation and the defence judge all use
## attack time, so a pause shifts every later hit by exactly the pause and nothing drifts.
## Pure: the caller passes every real timestamp in.

var _start_us: int = 0
## Pause intervals in real time, as [start_us, end_us] pairs, in order.
var _pauses: Array[Vector2i] = []
var _started: bool = false


func start(real_now_us: int) -> void:
	_start_us = real_now_us
	_pauses.clear()
	_started = true


func is_started() -> bool:
	return _started


## Freezes attack time for `duration_us` from `real_now_us`. Overlapping pauses merge.
func pause_for(real_now_us: int, duration_us: int) -> void:
	if duration_us <= 0:
		return
	var end_us := real_now_us + duration_us
	if not _pauses.is_empty():
		var last: Vector2i = _pauses[_pauses.size() - 1]
		if real_now_us <= last.y:
			_pauses[_pauses.size() - 1] = Vector2i(mini(last.x, real_now_us), maxi(last.y, end_us))
			return
	_pauses.append(Vector2i(real_now_us, end_us))


func is_paused(real_now_us: int) -> bool:
	for p: Vector2i in _pauses:
		if real_now_us >= p.x and real_now_us < p.y:
			return true
	return false


## Attack time (microseconds) at the given real time. Works for past timestamps too, so a press
## stamped slightly before the current frame converts correctly.
func attack_time_us(real_us: int) -> int:
	var paused := 0
	for p: Vector2i in _pauses:
		var a := maxi(p.x, _start_us)
		var b := mini(p.y, real_us)
		if b > a:
			paused += b - a
	return real_us - _start_us - paused
