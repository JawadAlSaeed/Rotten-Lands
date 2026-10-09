class_name DefenseStats
extends RefCounted
## Defence statistics for the F1 overlay: presses and successes per action, the mean and spread
## of the timing offsets of successful presses, the rolling median of recent parry offsets, and
## whiffs split by reason with the median offset of every timed press (hits and misses), which
## shows a player who is consistently late or early better than the successes alone.
## Offsets are what the judge reports: press time (after lag compensation) minus impact.

const RECENT_PARRY_COUNT: int = 20

## Defense.Outcome -> int
var presses: Dictionary = {}
var successes: Dictionary = {}
## Defense.Outcome -> Array of offsets (microseconds) of successful presses.
var offsets_us: Dictionary = {}
var recent_parry_us: Array[int] = []
var whiffs: int = 0
## DefenseJudge.Reason -> int
var whiff_reasons: Dictionary = {}
var locked_presses: int = 0
## Offsets of every press judged against a hit (successes and early/late whiffs), recent ones.
var recent_all_us: Array[int] = []


## Records one judged press (a DefenseJudge.press() report).
func record(action: int, report: Dictionary) -> void:
	var result := int(report.get("result", DefenseJudge.Result.DONE))
	if result == DefenseJudge.Result.DONE:
		return
	presses[action] = int(presses.get(action, 0)) + 1
	match result:
		DefenseJudge.Result.SUCCESS:
			successes[action] = int(successes.get(action, 0)) + 1
			var offset := int(report.get("offset_us", 0))
			if not offsets_us.has(action):
				offsets_us[action] = []
			(offsets_us[action] as Array).append(offset)
			if action == Defense.Outcome.PARRY:
				recent_parry_us.append(offset)
				if recent_parry_us.size() > RECENT_PARRY_COUNT:
					recent_parry_us.remove_at(0)
			_add_recent(int(report.get("offset_us", 0)))
		DefenseJudge.Result.WHIFF:
			whiffs += 1
			var reason := int(report.get("reason", DefenseJudge.Reason.NONE))
			whiff_reasons[reason] = int(whiff_reasons.get(reason, 0)) + 1
			if reason != DefenseJudge.Reason.WRONG_ACTION and int(report.get("hit", -1)) >= 0:
				_add_recent(int(report.get("offset_us", 0)))
		DefenseJudge.Result.LOCKED:
			locked_presses += 1


func whiff_count(reason: int) -> int:
	return int(whiff_reasons.get(reason, 0))


## Median offset (ms) of the recent timed presses, hits and misses alike.
func recent_all_median_ms() -> float:
	return median_us(recent_all_us) / 1000.0


func _add_recent(offset_us: int) -> void:
	recent_all_us.append(offset_us)
	if recent_all_us.size() > RECENT_PARRY_COUNT:
		recent_all_us.remove_at(0)


func press_count(action: int) -> int:
	return int(presses.get(action, 0))


func success_count(action: int) -> int:
	return int(successes.get(action, 0))


func success_percent(action: int) -> float:
	var n := press_count(action)
	return 0.0 if n == 0 else 100.0 * float(success_count(action)) / float(n)


func mean_ms(action: int) -> float:
	var values: Array = offsets_us.get(action, [])
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v: int in values:
		total += float(v)
	return total / float(values.size()) / 1000.0


## Population standard deviation of successful offsets, in ms.
func stddev_ms(action: int) -> float:
	var values: Array = offsets_us.get(action, [])
	if values.size() < 2:
		return 0.0
	var mean := mean_ms(action) * 1000.0
	var total := 0.0
	for v: int in values:
		total += (float(v) - mean) * (float(v) - mean)
	return sqrt(total / float(values.size())) / 1000.0


func recent_parry_median_ms() -> float:
	return median_us(recent_parry_us) / 1000.0


## Spread of the middle half of a list of microsecond values (the interquartile range).
static func spread_us(values: Array[int]) -> float:
	if values.size() < 2:
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var half := sorted.size() >> 1
	var lower: Array[int] = []
	lower.assign(sorted.slice(0, half))
	var upper: Array[int] = []
	upper.assign(sorted.slice(sorted.size() - half))
	return median_us(upper) - median_us(lower)


## Median of a list of microsecond values (0 for an empty list).
static func median_us(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() >> 1
	if sorted.size() % 2 == 1:
		return float(sorted[mid])
	return (float(sorted[mid - 1]) + float(sorted[mid])) * 0.5
