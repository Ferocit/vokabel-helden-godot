class_name LootService
extends RefCounted
## Quellen: normal | elite | boss | chestNormal | chestRare | chestSpecial
## Loot: { gold, potions, itemId (String oder null) }

const TABLES := {
	"normal": {"gold": [2, 6], "potionChance": 0.15, "itemChance": 0.12, "rarity": {"common": 80, "uncommon": 18, "rare": 2}},
	"elite": {"gold": [10, 18], "potionChance": 0.5, "itemChance": 0.8, "rarity": {"common": 25, "uncommon": 55, "rare": 20}},
	"boss": {"gold": [30, 50], "potionChance": 1.0, "itemChance": 1.0, "rarity": {"common": 0, "uncommon": 40, "rare": 60}},
	"chestNormal": {"gold": [4, 10], "potionChance": 0.35, "itemChance": 0.35, "rarity": {"common": 70, "uncommon": 27, "rare": 3}},
	"chestRare": {"gold": [8, 16], "potionChance": 0.4, "itemChance": 0.75, "rarity": {"common": 30, "uncommon": 50, "rare": 20}},
	"chestSpecial": {"gold": [12, 20], "potionChance": 0.5, "itemChance": 0.9, "rarity": {"common": 10, "uncommon": 50, "rare": 40}},
}


static func _roll_rarity(rng: Callable, weights: Dictionary) -> String:
	var total: float = weights.common + weights.uncommon + weights.rare
	var roll: float = rng.call() * total
	for rarity in ["common", "uncommon", "rare"]:
		roll -= weights[rarity]
		if roll < 0.0:
			return rarity
	return "common"


## Würfelt Beute aus. Bereits besessene Gegenstände werden nicht doppelt vergeben; gibt es in der
## Seltenheit nichts Neues, wird auf die anderen Stufen ausgewichen, sonst gibt es Gold.
static func roll_loot(source: String, rng: Callable, owns: Callable) -> Dictionary:
	var table: Dictionary = TABLES[source]
	var loot := {
		"gold": Rng.rand_int(rng, table.gold[0], table.gold[1]),
		"potions": 1 if rng.call() < table.potionChance else 0,
		"itemId": null,
	}
	if rng.call() >= table.itemChance:
		return loot
	var rarity := _roll_rarity(rng, table.rarity)
	var order: Array = [rarity]
	for r in ["rare", "uncommon", "common"]:
		if r != rarity:
			order.append(r)
	for r: String in order:
		var candidates: Array = GameData.ITEMS.filter(func(item: Dictionary) -> bool:
			return item.rarity == r and not owns.call(item.id))
		if not candidates.is_empty():
			loot.itemId = (Rng.pick(rng, candidates) as Dictionary).id
			return loot
	loot.gold += 15
	return loot
