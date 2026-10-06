class_name DefenseJudge
extends RefCounted
## Judges one player's defence presses against the prompts of one timed sequence.
## Pure: every time is passed in, in microseconds of attack time (see AttackClock).
## Windows, accepted actions and impact times come from the prompts the engine declared; only
## the whiff lockout and the player's lag compensation are local.
##
## Rules (DESIGN.md 3.4):
## 1. advance() every frame: prompts whose windows have all closed resolve as NONE (hit taken).
## 2. A press while locked out is ignored AND restarts the lockout (mashing never pays).
## 3. For each character this player controls, the press resolves that character's earliest
##    unresolved prompt whose window for that button contains the press time.
## 4. If no prompt matched: whiff, with a reason (EARLY, LATE or WRONG_ACTION); lockout starts.
## Results are released strictly in prompt order (pop_ready), which keeps every character's
## prompts in hit order as the engine requires.

enum Result {
	## The press defended at least one prompt.
	SUCCESS,
	## The press matched nothing; lockout started.
	WHIFF,
	## Ignored because of an earlier whiff; lockout restarted.
	LOCKED,
	## Ignored because every prompt is already resolved.
	DONE,
}

enum Reason {
	NONE,
	EARLY,
	LATE,
	## Wrong button for the hit (for example parry on a ground wave).
	WRONG_ACTION,
}

const NEVER: int = -9223372036854775807
## Most a press interval may reach back in time (see press()).
const MAX_STAMP_SLACK_US: int = 100000

var _lockout_us: int = 0
var _latency_us: int = 0
## Sorted by idx. Each: {idx, hit, character, at_us, windows {Outcome: Vector2i}, resolved,
## outcome, offset_us, pressed}
var _prompts: Array[Dictionary] = []
var _next_release: int = 0
var _lockout_until: int = NEVER


## `latency_compensation_ms` is subtracted from every time passed in (press and advance alike).
func _init(whiff_lockout_ms: int, latency_compensation_ms: int) -> void:
	_lockout_us = whiff_lockout_ms * 1000
	_latency_us = latency_compensation_ms * 1000


## Loads the prompts this player answers (from a timed_sequence_declared event).
func set_prompts(prompts: Array) -> void:
	_prompts.clear()
	_next_release = 0
	_lockout_until = NEVER
	for p: Dictionary in prompts:
		var windows: Dictionary = {}
		for action: int in (p.windows as Dictionary):
			var edges: Array = p.windows[action]
			windows[action] = Vector2i(int(edges[0]), int(edges[1]))
		_prompts.append({
			"idx": int(p.idx),
			"hit": int(p.hit),
			"character": int(p.character),
			"at_us": int(p.at_ms) * 1000,
			"windows": windows,
			"resolved": false,
			"outcome": Defense.Outcome.NONE,
			"offset_us": 0,
			"pressed": false,
		})
	_prompts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.idx) < int(b.idx))


func prompt_count() -> int:
	return _prompts.size()


## True once every prompt is resolved and released.
func is_complete() -> bool:
	return _next_release >= _prompts.size()


func is_locked_out(t_us: int) -> bool:
	return _compensate(t_us) < _lockout_until


## Attack time (uncompensated) of the next unresolved prompt's impact, or -1 if none.
func next_impact_us() -> int:
	for p: Dictionary in _prompts:
		if not p.resolved:
			return int(p.at_us)
	return -1


## Judges a press of `action` (Defense.Outcome.DODGE / PARRY / JUMP).
## `t_us` is when Godot delivered the press (attack time). `earliest_us` is the earliest moment
## the physical press could have happened (the previous input pump, attack time); a press counts
## if any part of [earliest_us, t_us] is inside a window. This removes the half-frame bias of
## once-per-frame input and turns a frame hitch into leniency instead of an unfair miss. The
## extension is capped at MAX_STAMP_SLACK_US. Pass -1 (default) to judge the single moment t_us.
## Returns {result: Result, reason: Reason, prompts: Array[int] (idx resolved), outcome,
## offset_us (press midpoint minus impact of the matched or nearest prompt), hit (or -1)}.
func press(action: int, t_us: int, earliest_us: int = -1) -> Dictionary:
	var latest := _compensate(t_us)
	var earliest := latest
	if earliest_us >= 0 and earliest_us < t_us:
		earliest = maxi(_compensate(earliest_us), latest - MAX_STAMP_SLACK_US)
	@warning_ignore("integer_division")
	var t := earliest + (latest - earliest) / 2
	_expire(earliest)
	if _all_resolved():
		return _report(Result.DONE, Reason.NONE, [], Defense.Outcome.NONE, 0, -1)
	if latest < _lockout_until:
		_lockout_until = latest + _lockout_us
		return _report(Result.LOCKED, Reason.NONE, [], Defense.Outcome.NONE, _nearest_offset(t), -1)

	var matched: Array[int] = []
	var claimed: Dictionary = {}
	var offset := 0
	var hit := -1
	for p: Dictionary in _prompts:
		if p.resolved or claimed.has(p.character) or not (p.windows as Dictionary).has(action):
			continue
		var edges: Vector2i = p.windows[action]
		var at := int(p.at_us)
		var off := t - at
		if latest >= at + edges.x and earliest <= at + edges.y:
			p.resolved = true
			p.outcome = action
			p.offset_us = off
			p.pressed = true
			claimed[p.character] = true
			matched.append(int(p.idx))
			if hit < 0:
				hit = int(p.hit)
				offset = off
	if not matched.is_empty():
		return _report(Result.SUCCESS, Reason.NONE, matched, action, offset, hit)

	_lockout_until = latest + _lockout_us
	var nearest := _nearest_prompt(t)
	var reason := Reason.LATE
	var nearest_offset := 0
	if not nearest.is_empty():
		nearest_offset = t - int(nearest.at_us)
		var windows: Dictionary = nearest.windows
		if not windows.has(action):
			reason = Reason.WRONG_ACTION
		elif nearest_offset < (windows[action] as Vector2i).x:
			reason = Reason.EARLY
	return _report(Result.WHIFF, reason, [], Defense.Outcome.NONE, nearest_offset, int(nearest.get("hit", -1)))


## Call every frame with the current attack time. Resolves overdue prompts as NONE and returns
## their idx.
func advance(t_us: int) -> Array[int]:
	return _expire(_compensate(t_us))


## Resolves every remaining prompt as NONE (for example when the sequence is cut short).
func resolve_all_remaining() -> void:
	for p: Dictionary in _prompts:
		if not p.resolved:
			p.resolved = true
			p.outcome = Defense.Outcome.NONE


## Resolved prompts that can be sent to the engine now, in order:
## [{prompt, outcome, offset_us, pressed}].
func pop_ready() -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	while _next_release < _prompts.size() and bool(_prompts[_next_release].resolved):
		var p: Dictionary = _prompts[_next_release]
		ready.append({
			"prompt": int(p.idx),
			"outcome": int(p.outcome),
			"offset_us": int(p.offset_us),
			"pressed": bool(p.pressed),
		})
		_next_release += 1
	return ready


## Latest attack time (compensated) at which this prompt can still be defended.
static func close_time_us(prompt: Dictionary) -> int:
	var latest := 0
	var first := true
	for action: int in (prompt.windows as Dictionary):
		var edges: Vector2i = prompt.windows[action]
		if first or edges.y > latest:
			latest = edges.y
			first = false
	return int(prompt.at_us) + latest


func _compensate(t_us: int) -> int:
	return t_us - _latency_us


func _expire(t: int) -> Array[int]:
	var expired: Array[int] = []
	for p: Dictionary in _prompts:
		if not p.resolved and t > close_time_us(p):
			p.resolved = true
			p.outcome = Defense.Outcome.NONE
			expired.append(int(p.idx))
	return expired


func _all_resolved() -> bool:
	for p: Dictionary in _prompts:
		if not p.resolved:
			return false
	return true


func _nearest_prompt(t: int) -> Dictionary:
	var best: Dictionary = {}
	var best_abs := -1
	for p: Dictionary in _prompts:
		if p.resolved:
			continue
		var d := absi(t - int(p.at_us))
		if best_abs < 0 or d < best_abs:
			best_abs = d
			best = p
	return best


func _nearest_offset(t: int) -> int:
	var p := _nearest_prompt(t)
	return 0 if p.is_empty() else t - int(p.at_us)


func _report(result: Result, reason: Reason, prompts: Array[int], outcome: int, offset_us: int, hit: int) -> Dictionary:
	return {"result": result, "reason": reason, "prompts": prompts, "outcome": outcome, "offset_us": offset_us, "hit": hit}
