class_name CombatRng
extends RefCounted
## Deterministic random numbers for combat (xorshift32).
## The whole state is one int, so it can be snapshotted, sent over the network and compared in
## tests. All values stay inside 32 bits, so 64-bit int overflow can never happen.
## Combat logic must never call randi() or randf(); it uses this instead.

const MASK_32: int = 0xFFFFFFFF

var state: int = 1


func _init(seed_value: int = 1) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	# Mix the seed so nearby seeds give unrelated sequences. Each product stays below 2^59.
	var s: int = seed_value & MASK_32
	s = ((s ^ (s >> 16)) * 0x45d9f3b) & MASK_32
	s = ((s ^ (s >> 16)) * 0x45d9f3b) & MASK_32
	s = s ^ (s >> 16)
	state = s if s != 0 else 0x9E3779B9


## Next raw value in [0, 2^32 - 1].
func next_u32() -> int:
	var x: int = state
	x ^= (x << 13) & MASK_32
	x ^= x >> 17
	x ^= (x << 5) & MASK_32
	state = x
	return x


## Random int in [lo, hi], both inclusive.
func range_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + next_u32() % (hi - lo + 1)


## Picks an index with probability proportional to its weight. Returns -1 if all weights are 0.
func pick_weighted(weights: Array[int]) -> int:
	var total: int = 0
	for w: int in weights:
		total += maxi(w, 0)
	if total <= 0:
		return -1
	var roll: int = next_u32() % total
	for i: int in weights.size():
		var w: int = maxi(weights[i], 0)
		if roll < w:
			return i
		roll -= w
	return weights.size() - 1
