class_name CombatMath
extends RefCounted
## Integer maths used by combat rules. Percentages are ints (100 = x1). No floats, so results are
## identical on every machine and do not depend on the order multipliers are applied.
## Fixed modifier order for damage: base power -> move percent -> (phase 4: equipment by slot,
## then statuses) -> variance.


## value x percent / 100, rounded half up. Only for non-negative values.
@warning_ignore("integer_division")
static func percent(value: int, pct: int) -> int:
	return (value * pct + 50) / 100


## Like percent() but never below 1.
static func percent_min1(value: int, pct: int) -> int:
	return maxi(1, percent(value, pct))
