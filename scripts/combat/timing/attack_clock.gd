class_name AttackClock
extends RefCounted
## Converts real time (Time.get_ticks_usec()) into "attack time": microseconds since the attack
## started, not counting hit-stop pauses. Hit times, enemy animation and the defence judge all use
## attack time, so a pause shifts every later hit by exactly the pause and nothing drifts.
## Pure: the caller passes every real timestamp in.

var _start_us: int = 0
## Pause intervals in real time, in order: _pause_from[i] .. _pause_to[i]. 64-bit arrays on
## purpose: Time.get_ticks_usec() passes the int32 range after about 36 minutes of uptime.
var _pause_from := PackedInt64Array()
var _pause_to := PackedInt64Array()
var _started: bool = false


func start(real_now_us: int) -> void:
	_start_us = real_now_us
	_pause_from.clear()
	_pause_to.clear()
	_started = true


func is_started() -> bool:
	return _started


## Freezes attack time for `duration_us` from `real_now_us`. Overlapping pauses merge.
func pause_for(real_now_us: int, duration_us: int) -> void:
	if duration_us <= 0:
		return
	var end_us := real_now_us + duration_us
	var last := _pause_from.size() - 1
	if last >= 0 and real_now_us <= _pause_to[last]:
		_pause_from[last] = mini(_pause_from[last], real_now_us)
		_pause_to[last] = maxi(_pause_to[last], end_us)
		return
	_pause_from.append(real_now_us)
	_pause_to.append(end_us)


func is_paused(real_now_us: int) -> bool:
	for i: int in _pause_from.size():
		if real_now_us >= _pause_from[i] and real_now_us < _pause_to[i]:
			return true
	return false


## Real time at which the latest pause ends, or -1 if there was none.
func last_pause_end_us() -> int:
	return -1 if _pause_to.is_empty() else _pause_to[_pause_to.size() - 1]


## Attack time (microseconds) at the given real time. Works for past timestamps too, so a press
## stamped slightly before the current frame converts correctly.
func attack_time_us(real_us: int) -> int:
	var paused := 0
	for i: int in _pause_from.size():
		var a := maxi(_pause_from[i], _start_us)
		var b := mini(_pause_to[i], real_us)
		if b > a:
			paused += b - a
	return real_us - _start_us - paused
