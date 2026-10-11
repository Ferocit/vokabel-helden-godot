class_name Blessings
extends RefCounted
## Segnungen: Nach jedem Sieg über einen Elite-Gegner wählt man eine von drei zufälligen Segnungen.
## Sie gelten nur für das laufende Abenteuer (profile.blessings) und nutzen dieselben Effekt-Schlüssel
## wie die Skillbäume. Wie dort gilt: keine Vokabelhilfen.
##
## Seltenheit (Issue #20): gewöhnlich = Werte, selten/legendär = Regeln, die richtiges Erinnern belohnen
## (Kettenblitz, Rache des Gelehrten …). `classes` beschränkt eine Segnung auf bestimmte Klassen.
## Duo-Segnungen wirken von selbst, sobald man beide Segnungen eines Paars besitzt.

const RARITY_WEIGHT := {"common": 6.0, "rare": 3.0, "legendary": 1.2}
const RARITY_LABEL := {"common": "gewöhnlich", "rare": "selten", "legendary": "legendär"}

const ALL: Array[Dictionary] = [
	{"id": "b_oak", "name": "Segen der Eiche", "icon": "🌳", "rarity": "common", "effect": {"maxHp": 8}},
	{"id": "b_jaguar", "name": "Segen des Jaguars", "icon": "🐆", "rarity": "common", "effect": {"moveSpeed": 0.15}},
	{"id": "b_blade", "name": "Segen der Klinge", "icon": "⚔", "rarity": "common", "effect": {"attack": 2}},
	{"id": "b_falcon", "name": "Falkenauge", "icon": "🦅", "rarity": "common", "effect": {"critChance": 0.1}},
	{"id": "b_stone", "name": "Steinhaut", "icon": "🪨", "rarity": "common", "effect": {"armor": 1}},
	{"id": "b_sun", "name": "Sonnenfeuer", "icon": "☀", "rarity": "common", "effect": {"skillPower": 0.3}},
	{"id": "b_spring", "name": "Lebensquell", "icon": "💧", "rarity": "common", "effect": {"lifeOnWin": 4}},
	{"id": "b_gold", "name": "Goldregen", "icon": "💰", "rarity": "common", "effect": {"goldFind": 0.5}},
	{"id": "b_crystal", "name": "Kristallglanz", "icon": "🔷", "rarity": "common", "effect": {"shardBonus": 0.2}},
	{"id": "b_prayer", "name": "Schildgebet", "icon": "🛡", "rarity": "common", "effect": {"defend": 0.1}},
	{"id": "b_alchemy", "name": "Alchemistenglück", "icon": "🧪", "rarity": "common", "effect": {"potionHeal": 6}},
	{"id": "b_fury", "name": "Kampfrausch", "icon": "🔥", "rarity": "common", "effect": {"critMult": 0.3}},
	{"id": "b_chain", "name": "Kettenblitz", "icon": "⚡", "rarity": "legendary", "effect": {"chainStrike": 1}},
	{"id": "b_revenge", "name": "Rache des Gelehrten", "icon": "📜", "rarity": "rare", "effect": {"revenge": 1.0}},
	{"id": "b_hunter", "name": "Jagdinstinkt", "icon": "🎯", "rarity": "rare", "effect": {"firstStrike": 1, "critChance": 0.05}},
	{"id": "b_vampire", "name": "Lebensdurst", "icon": "🩸", "rarity": "rare", "effect": {"critHeal": 4}},
	{"id": "b_venom", "name": "Schlangenbiss", "icon": "🐍", "rarity": "rare", "classes": ["rogue"], "effect": {"poisonStack": 1, "poisonTurns": 1}},
	{"id": "b_spark", "name": "Funkenflug", "icon": "✨", "rarity": "rare", "classes": ["mage"], "effect": {"critFocus": 1, "critChance": 0.05}},
]

## Duo-Segnungen: wirken automatisch, wenn beide Segnungen gewählt wurden.
const DUOS: Array[Dictionary] = [
	{"id": "duo_storm", "name": "Gewittersturm", "icon": "🌩", "requires": ["b_chain", "b_falcon"], "effect": {"critChance": 0.15}},
	{"id": "duo_fortress", "name": "Festung", "icon": "🏰", "requires": ["b_stone", "b_prayer"], "effect": {"armor": 1, "defend": 0.1}},
	{"id": "duo_sage", "name": "Flammende Weisheit", "icon": "📖", "requires": ["b_revenge", "b_sun"], "effect": {"skillPower": 0.5}},
	{"id": "duo_bloodmoon", "name": "Blutmond", "icon": "🌕", "requires": ["b_vampire", "b_fury"], "effect": {"critHeal": 4}},
	{"id": "duo_hunt", "name": "Treibjagd", "icon": "🐾", "requires": ["b_hunter", "b_jaguar"], "effect": {"critMult": 0.4}},
]


static func get_blessing(id: String) -> Dictionary:
	for b in ALL:
		if b.id == id:
			return b
	for d in DUOS:
		if d.id == id:
			return d
	return {}


static func text(b: Dictionary) -> String:
	return SkillTrees.effect_text({"effect": b.effect}, 1)


## Alle Duos, deren beide Segnungen vorhanden sind.
static func active_duos(owned: Array) -> Array:
	return DUOS.filter(func(d: Dictionary) -> bool: return owned.has(d.requires[0]) and owned.has(d.requires[1]))


## Duos, die diese Segnung zusammen mit einer schon gewählten vervollständigen würde.
static func duos_completed_by(owned: Array, id: String) -> Array:
	return DUOS.filter(func(d: Dictionary) -> bool:
		return (d.requires as Array).has(id) and owned.has(d.requires[0] if d.requires[1] == id else d.requires[1]))


## Zufällige Auswahl ohne bereits erhaltene Segnungen, gewichtet nach Seltenheit, passend zur Klasse.
static func roll(rng: Callable, owned: Array, count: int, class_id: String = "") -> Array:
	var pool: Array = ALL.filter(func(b: Dictionary) -> bool:
		return not owned.has(b.id) and (class_id == "" or not b.has("classes") or (b.classes as Array).has(class_id)))
	var picks: Array = []
	while picks.size() < count and not pool.is_empty():
		var b: Dictionary = Rng.weighted_pick(rng, pool, func(x: Dictionary) -> float: return RARITY_WEIGHT[x.rarity])
		picks.append(b)
		pool.erase(b)
	return picks
