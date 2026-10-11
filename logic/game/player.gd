class_name Player
extends RefCounted
## Dauerhafter Spielerfortschritt zwischen Runs (PlayerProfile als Dictionary):
##   { heroClass, level, xp, gold, equipment: {weapon, helmet, ring}, bag: Array[String], potions,
##     unlockedWorlds, lastLearnedAt }
## Alle Funktionen liefern neue Profile zurück, das übergebene bleibt unverändert.


static func new_profile(cfg: Dictionary) -> Dictionary:
	return {
		"heroClass": "warrior",
		"level": 1,
		"xp": 0,
		"gold": 0,
		"equipment": {"weapon": "wooden_sword", "helmet": null, "ring": null},
		"bag": [],
		"potions": int(cfg.startPotions),
		"unlockedWorlds": ["jungle"],
		"lastLearnedAt": null,
	}


## Gespeicherte Profile kommen aus JSON (Zahlen als float) – hier wieder in saubere Typen bringen.
static func normalize(p: Dictionary, cfg: Dictionary) -> Dictionary:
	var base := new_profile(cfg)
	base.merge(p, true)
	for k in ["level", "xp", "gold", "potions"]:
		base[k] = int(base[k])
	var eq: Dictionary = {"weapon": null, "helmet": null, "ring": null}
	if base.equipment is Dictionary:
		eq.merge(base.equipment, true)
	base.equipment = eq
	return base


## { maxHp, maxFocus, attack, freeHints: {length?, firstLetter?}, repeatGapReduction }
static func compute_stats(profile: Dictionary, cfg: Dictionary) -> Dictionary:
	var lv: int = int(profile.level) - 1
	var cls := GameData.get_class_def(profile.heroClass)
	var stats := {
		"maxHp": int(cfg.baseHp) + lv * int(cfg.hpPerLevel) + int(cls.hpBonus),
		"maxFocus": int(cfg.baseFocus) + lv * int(cfg.focusPerLevel) + int(cls.focusBonus),
		"attack": int(cfg.baseAttack) + lv * int(cfg.attackPerLevel) + int(cls.attackBonus),
		"freeHints": (cls.freeHints as Dictionary).duplicate(),
		"repeatGapReduction": 0,
	}
	for id: Variant in profile.equipment.values():
		if id == null or not GameData.has_item(id):
			continue
		var fx: Dictionary = GameData.get_item(id).effects
		stats.maxHp += int(fx.get("maxHp", 0))
		stats.maxFocus += int(fx.get("maxFocus", 0))
		stats.attack += int(fx.get("attack", 0))
		stats.repeatGapReduction += int(fx.get("repeatGapReduction", 0))
		var hints: Dictionary = fx.get("freeHints", {})
		for type: String in hints:
			stats.freeHints[type] = int(stats.freeHints.get(type, 0)) + int(hints[type])
	return stats


## XP-Schwelle für das nächste Level oder -1, wenn das Maximum erreicht ist.
static func xp_for_next_level(level: int, cfg: Dictionary) -> int:
	var table: Array = cfg.xpPerLevel
	return int(table[level]) if level < table.size() else -1


## { profile, levelsGained }
static func add_xp(profile: Dictionary, amount: int, cfg: Dictionary) -> Dictionary:
	var next := profile.duplicate(true)
	next.xp = int(profile.xp) + amount
	var gained := 0
	while true:
		var needed := xp_for_next_level(int(next.level), cfg)
		if needed < 0 or int(next.xp) < needed:
			break
		next.level = int(next.level) + 1
		gained += 1
	return {"profile": next, "levelsGained": gained}


static func owns_item(profile: Dictionary, id: String) -> bool:
	return (profile.bag as Array).has(id) or (profile.equipment as Dictionary).values().has(id)


static func equip(profile: Dictionary, id: String) -> Dictionary:
	if not (profile.bag as Array).has(id):
		return profile
	var item := GameData.get_item(id)
	var next := profile.duplicate(true)
	var current: Variant = next.equipment[item.slot]
	(next.bag as Array).erase(id)
	if current != null:
		(next.bag as Array).append(current)
	next.equipment[item.slot] = id
	return next


static func unequip(profile: Dictionary, slot: String) -> Dictionary:
	var current: Variant = profile.equipment.get(slot)
	if current == null:
		return profile
	var next := profile.duplicate(true)
	(next.bag as Array).append(current)
	next.equipment[slot] = null
	return next


## Verkauft einen Gegenstand aus der Tasche (angelegte Ausrüstung muss erst abgelegt werden).
static func sell_item(profile: Dictionary, id: String) -> Dictionary:
	if not (profile.bag as Array).has(id):
		return profile
	var next := profile.duplicate(true)
	(next.bag as Array).erase(id)
	next.gold = int(profile.gold) + int(GameData.SELL_PRICE[GameData.get_item(id).rarity])
	return next


static func can_buy_potion(profile: Dictionary) -> bool:
	return int(profile.gold) >= GameData.POTION_PRICE and int(profile.potions) < GameData.MAX_POTIONS


static func buy_potion(profile: Dictionary) -> Dictionary:
	if not can_buy_potion(profile):
		return profile
	var next := profile.duplicate(true)
	next.gold = int(profile.gold) - GameData.POTION_PRICE
	next.potions = int(profile.potions) + 1
	return next
