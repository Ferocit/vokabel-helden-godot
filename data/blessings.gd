class_name Blessings
extends RefCounted
## Segnungen: Nach jedem Sieg über einen Elite-Gegner wählt man eine von drei zufälligen Segnungen.
## Sie gelten nur für das laufende Abenteuer (profile.blessings) und nutzen dieselben Effekt-Schlüssel
## wie die Skillbäume. Wie dort gilt: keine Vokabelhilfen.

const ALL: Array[Dictionary] = [
	{"id": "b_oak", "name": "Segen der Eiche", "icon": "🌳", "effect": {"maxHp": 8}},
	{"id": "b_jaguar", "name": "Segen des Jaguars", "icon": "🐆", "effect": {"moveSpeed": 0.15}},
	{"id": "b_blade", "name": "Segen der Klinge", "icon": "⚔", "effect": {"attack": 2}},
	{"id": "b_falcon", "name": "Falkenauge", "icon": "🦅", "effect": {"critChance": 0.1}},
	{"id": "b_stone", "name": "Steinhaut", "icon": "🪨", "effect": {"armor": 1}},
	{"id": "b_sun", "name": "Sonnenfeuer", "icon": "☀", "effect": {"skillPower": 0.3}},
	{"id": "b_spring", "name": "Lebensquell", "icon": "💧", "effect": {"lifeOnWin": 4}},
	{"id": "b_gold", "name": "Goldregen", "icon": "💰", "effect": {"goldFind": 0.5}},
	{"id": "b_crystal", "name": "Kristallglanz", "icon": "🔷", "effect": {"shardBonus": 0.2}},
	{"id": "b_prayer", "name": "Schildgebet", "icon": "🛡", "effect": {"defend": 0.1}},
	{"id": "b_alchemy", "name": "Alchemistenglück", "icon": "🧪", "effect": {"potionHeal": 6}},
	{"id": "b_fury", "name": "Kampfrausch", "icon": "🔥", "effect": {"critMult": 0.3}},
]


static func get_blessing(id: String) -> Dictionary:
	for b in ALL:
		if b.id == id:
			return b
	return {}


static func text(b: Dictionary) -> String:
	return SkillTrees.effect_text({"effect": b.effect}, 1)


## Zufällige Auswahl ohne bereits erhaltene Segnungen.
static func roll(rng: Callable, owned: Array, count: int) -> Array:
	var pool := ALL.filter(func(b: Dictionary) -> bool: return not owned.has(b.id))
	return Rng.shuffle(rng, pool).slice(0, count)
