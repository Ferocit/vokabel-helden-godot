class_name Talents
extends RefCounted
## Talente: Bei jedem Level-up innerhalb eines Abenteuers wählt man eins von drei zufälligen Talenten.
## Talente lassen sich mehrfach nehmen (bis `max`), gelten nur im laufenden Abenteuer (profile.talents)
## und nutzen dieselben Effekt-Schlüssel wie Skillbäume und Segnungen. Wie dort: keine Vokabelhilfen.
## Sie sind bewusst kleiner als Segnungen – dafür gibt es sie bei jedem Aufstieg.

const ALL: Array[Dictionary] = [
	{"id": "t_vigor", "name": "Zähigkeit", "icon": "❤", "max": 5, "effect": {"maxHp": 8}},
	{"id": "t_might", "name": "Kraft", "icon": "⚔", "max": 5, "effect": {"attack": 1}},
	{"id": "t_focus", "name": "Konzentration", "icon": "✦", "max": 3, "effect": {"maxFocus": 1}},
	{"id": "t_eye", "name": "Scharfer Blick", "icon": "✸", "max": 4, "effect": {"critChance": 0.05}},
	{"id": "t_guard", "name": "Standhaft", "icon": "🛡", "max": 3, "effect": {"defend": 0.05}},
	{"id": "t_hide", "name": "Dickes Fell", "icon": "⛨", "max": 2, "effect": {"armor": 1}},
	{"id": "t_herbs", "name": "Kräuterkunde", "icon": "🌿", "max": 3, "effect": {"potionHeal": 5}},
	{"id": "t_will", "name": "Siegeswille", "icon": "✚", "max": 3, "effect": {"lifeOnWin": 3}},
	{"id": "t_stride", "name": "Leichtfuß", "icon": "👟", "max": 3, "effect": {"moveSpeed": 0.08}},
	{"id": "t_mastery", "name": "Klassenmeister", "icon": "★", "max": 3, "effect": {"skillPower": 0.15}},
	{"id": "t_luck", "name": "Glückspilz", "icon": "💰", "max": 3, "effect": {"goldFind": 0.2}},
	# Regel-Talente (Issue #20): verändern Kämpfe, belohnen Treffer – nie Hilfen beim Antworten.
	{"id": "t_ambush", "name": "Überraschungsangriff", "icon": "🗡", "max": 1, "effect": {"firstStrike": 1}},
	{"id": "t_thirst", "name": "Kampfeslust", "icon": "🩸", "max": 2, "effect": {"critHeal": 2}},
	{"id": "t_clarity", "name": "Geistesblitz", "icon": "💫", "max": 2, "effect": {"critFocus": 1}},
]


static func get_talent(id: String) -> Dictionary:
	for t in ALL:
		if t.id == id:
			return t
	return {}


static func text(t: Dictionary) -> String:
	var fx: Dictionary = t.effect
	if fx.has("maxFocus"):
		return "+%d max. Fokus" % int(fx.maxFocus)
	return SkillTrees.effect_text({"effect": fx}, 1)


## Wie oft ein Talent schon gewählt wurde.
static func rank(owned: Array, id: String) -> int:
	return owned.count(id)


## Zufällige Auswahl ohne voll ausgebaute Talente.
static func roll(rng: Callable, owned: Array, count: int = 3, profile: Dictionary = {}) -> Array:
	var pool := ALL.filter(func(t: Dictionary) -> bool: return rank(owned, t.id) < int(t.max) and Unlocks.available(profile, "talent", t.id))
	return Rng.shuffle(rng, pool).slice(0, count)
