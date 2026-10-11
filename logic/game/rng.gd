class_name Rng
extends RefCounted
## Seedbarer Zufallsgenerator (mulberry32, identisch zur Phaser-Version). Ein Rng ist ein Callable,
## das Werte in [0, 1) liefert – so lassen sich in Tests auch feste Folgen einsetzen.

const MASK := 0xFFFFFFFF


## 32-Bit-Multiplikation wie Math.imul, ohne 64-Bit-Überlauf.
static func imul(a: int, b: int) -> int:
	a &= MASK
	b &= MASK
	var a_hi := (a >> 16) & 0xFFFF
	var a_lo := a & 0xFFFF
	var b_hi := (b >> 16) & 0xFFFF
	var b_lo := b & 0xFFFF
	return ((a_lo * b_lo) + ((((a_hi * b_lo) + (a_lo * b_hi)) << 16) & MASK)) & MASK


static func create(seed: int) -> Callable:
	var state := [seed & MASK]
	return func() -> float:
		state[0] = (state[0] + 0x6D2B79F5) & MASK
		var t: int = state[0]
		t = imul(t ^ (t >> 15), t | 1)
		t ^= (t + imul(t ^ (t >> 7), t | 61)) & MASK
		return float((t ^ (t >> 14)) & MASK) / 4294967296.0


static func random_seed() -> int:
	return randi() & MASK


## Ganzzahl in [min_v, max_v] (beide inklusive).
static func rand_int(rng: Callable, min_v: int, max_v: int) -> int:
	return min_v + int(floor(rng.call() * (max_v - min_v + 1)))


static func pick(rng: Callable, items: Array) -> Variant:
	assert(not items.is_empty(), "pick() auf leerer Liste")
	return items[int(floor(rng.call() * items.size()))]


static func shuffle(rng: Callable, items: Array) -> Array:
	var result := items.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j := int(floor(rng.call() * (i + 1)))
		var tmp: Variant = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result


static func weighted_pick(rng: Callable, items: Array, weight: Callable) -> Variant:
	var weights: Array[float] = []
	var total := 0.0
	for item: Variant in items:
		var w: float = weight.call(item)
		weights.append(w)
		total += w
	var roll: float = rng.call() * total
	for i in items.size():
		roll -= weights[i]
		if roll < 0.0:
			return items[i]
	return items[items.size() - 1]
