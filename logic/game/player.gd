class_name Player
extends RefCounted
## Spielerprofil (Dictionary):
##   Dauerhaft:  heroClass, shards, unlockedClasses, skills, records, unlockedWorlds, lastLearnedAt
##   Pro Abenteuer (siehe Meta.reset_run_fields): level, xp, gold, equipment: {weapon, helmet, ring},
##               bag: Array[String], potions, blessings: Array[String]
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
		"shards": 0,
		"unlockedClasses": ["warrior"],
		"skills": {},
		"records": {"runs": 0, "victories": 0, "shardsTotal": 0},
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
	return Meta.ensure(base)


## { maxHp, maxFocus, attack, freeHints: {length?, firstLetter?}, repeatGapReduction, mods }
## `mods` sind die Effekte des Skillbaums der aktuellen Klasse (siehe Meta.mods).
static func compute_stats(profile: Dictionary, cfg: Dictionary) -> Dictionary:
	var lv: int = int(profile.level) - 1
	var cls := GameData.get_class_def(profile.heroClass)
	var m := Meta.mods(profile, cls.id)
	var stats := {
		"maxHp": int(cfg.baseHp) + lv * int(cfg.hpPerLevel) + int(cls.hpBonus) + int(Meta.mod(m, "maxHp")),
		"maxFocus": int(cfg.baseFocus) + lv * int(cfg.focusPerLevel) + int(cls.focusBonus),
		"attack": int(cfg.baseAttack) + lv * int(cfg.attackPerLevel) + int(cls.attackBonus) + int(Meta.mod(m, "attack")),
		"freeHints": (cls.freeHints as Dictionary).duplicate(),
		"repeatGapReduction": 0,
		"mods": m,
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
		_add_mods(m, fx)
	# Talente aus Level-ups und Segnungen gelten nur im laufenden Abenteuer (Meta.reset_run_fields leert sie).
	for id: String in profile.get("talents", []):
		var t := Talents.get_talent(id)
		if not t.is_empty():
			stats.maxHp += int(t.effect.get("maxHp", 0))
			stats.attack += int(t.effect.get("attack", 0))
			stats.maxFocus += int(t.effect.get("maxFocus", 0))
			_add_mods(m, t.effect)
	var blessing_list: Array = profile.get("blessings", [])
	# Duo-Segnungen (Issue #20) wirken automatisch, sobald beide Segnungen eines Paars gewählt sind.
	for duo: Dictionary in Blessings.active_duos(blessing_list):
		_add_mods(m, duo.effect)
	for id: String in blessing_list:
		var b := Blessings.get_blessing(id)
		if not b.is_empty():
			stats.maxHp += int(b.effect.get("maxHp", 0))
			stats.attack += int(b.effect.get("attack", 0))
			_add_mods(m, b.effect)
	return stats


const BASE_KEYS := ["attack", "maxHp", "maxFocus", "repeatGapReduction", "freeHints"]


## Weitere Effekte (Skill-Schlüssel wie moveSpeed, armor …) zu den Skill-Effekten addieren.
static func _add_mods(m: Dictionary, fx: Dictionary) -> void:
	for key: String in fx:
		if key not in BASE_KEYS:
			m[key] = float(m.get(key, 0.0)) + float(fx[key])


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
