class_name Timeline
extends RefCounted
## Speed-based (charge time) turn order. Integer maths only.


## Timeline ticks one turn costs at the given speed.
@warning_ignore("integer_division")
static func turn_cost(speed: int, base: int) -> int:
	return maxi(1, base / maxi(1, speed))


## True if a acts before b. Ties go to the lower id (party members have the lowest ids).
static func comes_before(a: Combatant, b: Combatant) -> bool:
	if a.next_turn_at != b.next_turn_at:
		return a.next_turn_at < b.next_turn_at
	return a.id < b.id


## The living fighter who acts next, or null if nobody is alive.
static func next_actor(combatants: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	for c: Combatant in combatants:
		if not c.is_alive():
			continue
		if best == null or comes_before(c, best):
			best = c
	return best


## Ids of the next `count` turns, simulated without changing anyone's state.
static func preview(combatants: Array[Combatant], count: int, base: int) -> Array[int]:
	var times: Dictionary = {}
	var living: Array[Combatant] = []
	for c: Combatant in combatants:
		if c.is_alive():
			living.append(c)
			times[c.id] = c.next_turn_at
	var order: Array[int] = []
	if living.is_empty():
		return order
	for i: int in count:
		var best: Combatant = null
		for c: Combatant in living:
			if best == null:
				best = c
				continue
			var tc: int = times[c.id]
			var tb: int = times[best.id]
			if tc < tb or (tc == tb and c.id < best.id):
				best = c
		order.append(best.id)
		times[best.id] = int(times[best.id]) + turn_cost(best.speed, base)
	return order
