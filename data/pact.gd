class_name Pact
extends RefCounted
## Pakt (Issue #22): frei wählbare Erschwernisse statt fester Tempelstufen. Jeder Rang kostet Punkte, jeder Punkt
## bringt +shardBonusPerPoint Tempelsplitter. Ein Teil sind lernförderliche Erschwernisse (ohne Hilfen, umgekehrte
## Richtung, mehr neue Wörter) – sinnvolle Schwierigkeiten als freiwillige Herausforderung.
## Ein Pakt ist ein Dictionary {id: rang}. Die alten Tempelstufen entsprechen {p_hp: n, p_atk: n} (from_heat).
## Freigeschaltete Punkte: pointsPerLevel × records.heatUnlocked; ein Sieg mit voll ausgeschöpftem Pakt schaltet
## die nächste Stufe frei. Werte: config/game.json → meta.pact.

const ALL: Array[Dictionary] = [
	{"id": "p_hp", "name": "Zähe Gegner", "icon": "🛡", "max": 5, "points": 1, "learning": false},
	{"id": "p_atk", "name": "Wilde Gegner", "icon": "⚔", "max": 5, "points": 1, "learning": false},
	{"id": "p_elite", "name": "Elite-Horden", "icon": "👹", "max": 2, "points": 1, "learning": false},
	{"id": "p_supplies", "name": "Karge Vorräte", "icon": "🧪", "max": 2, "points": 1, "learning": false},
	{"id": "p_lives", "name": "Zerbrechlich", "icon": "💔", "max": 2, "points": 2, "learning": false},
	{"id": "p_greed", "name": "Gierige Händler", "icon": "💰", "max": 2, "points": 1, "learning": false},
	{"id": "p_nohints", "name": "Ohne Hilfen", "icon": "🚫", "max": 1, "points": 2, "learning": true},
	{"id": "p_reverse", "name": "Umgekehrte Richtung", "icon": "🔁", "max": 2, "points": 1, "learning": true},
	{"id": "p_new", "name": "Neue Wörter", "icon": "🆕", "max": 1, "points": 1, "learning": true},
]


static func cfg() -> Dictionary:
	return GameConfig.section("meta").pact


static func get_mod(id: String) -> Dictionary:
	for m in ALL:
		if m.id == id:
			return m
	return {}


## Text für einen Rang, z. B. „Gegner +70 % HP“.
static func describe(id: String, r: int) -> String:
	var c := cfg()
	match id:
		"p_hp":
			return "Gegner +%d %% HP" % roundi(float(c.hpPerRank) * r * 100.0)
		"p_atk":
			return "Gegner +%d %% Angriff" % roundi(float(c.attackPerRank) * r * 100.0)
		"p_elite":
			return "+%d Elite-Gegner pro Ebene" % r
		"p_supplies":
			return "−%d Heiltrank zu Beginn" % r
		"p_lives":
			return "−%d Leben" % r
		"p_greed":
			return "Händler +%d %% teurer" % roundi(float(c.greedPerRank) * r * 100.0)
		"p_nohints":
			return "Keine Hilfen (Wortlänge, erster Buchstabe)"
		"p_reverse":
			return "Jede 3. Abfrage Englisch → Deutsch" if r <= 1 else "Alle Abfragen Englisch → Deutsch"
		"p_new":
			return "Noch nie geübte Wörter kommen deutlich öfter"
	return ""


## Alte Tempelstufe als Pakt (für Spielstände, Tests und den Simulator).
static func from_heat(heat: int) -> Dictionary:
	return {} if heat <= 0 else {"p_hp": heat, "p_atk": heat}


## Pakt aus int (alte Tempelstufe) oder Dictionary, mit gültigen Rängen.
static func normalize(v: Variant) -> Dictionary:
	if v is int or v is float:
		return from_heat(int(v))
	var out := {}
	if v is Dictionary:
		for id: String in v:
			var m := get_mod(id)
			var r := clampi(int(v[id]), 0, int(m.get("max", 0)))
			if r > 0:
				out[id] = r
	return out


static func rank(pact: Dictionary, id: String) -> int:
	return int(pact.get(id, 0))


static func points(pact: Dictionary) -> int:
	var total := 0
	for id: String in pact:
		total += int(get_mod(id).get("points", 0)) * int(pact[id])
	return total


## Wie viele Punkte das Profil schon einsetzen darf.
static func cap(profile: Dictionary) -> int:
	return int(cfg().pointsPerLevel) * Meta.heat_max_unlocked(profile)


## Auf die freigeschalteten Punkte begrenzen: Ränge werden von hinten abgebaut, bis es passt.
static func sanitize(pact: Dictionary, profile: Dictionary) -> Dictionary:
	var out := normalize(pact)
	var limit := cap(profile)
	var ids := out.keys()
	ids.reverse()
	for id: String in ids:
		while points(out) > limit and int(out.get(id, 0)) > 0:
			out[id] = int(out[id]) - 1
			if int(out[id]) == 0:
				out.erase(id)
	return out


static func hp_factor(pact: Dictionary) -> float:
	return 1.0 + float(cfg().hpPerRank) * rank(pact, "p_hp")


static func attack_factor(pact: Dictionary) -> float:
	return 1.0 + float(cfg().attackPerRank) * rank(pact, "p_atk")


static func shard_bonus(pact: Dictionary) -> float:
	return float(cfg().shardBonusPerPoint) * points(pact)


static func price_factor(pact: Dictionary) -> float:
	return 1.0 + float(cfg().greedPerRank) * rank(pact, "p_greed")


static func hints_allowed(pact: Dictionary) -> bool:
	return rank(pact, "p_nohints") == 0


## Wahrscheinlichkeit, dass eine Abfrage Englisch → Deutsch läuft.
static func reverse_chance(pact: Dictionary) -> float:
	var r := rank(pact, "p_reverse")
	return 0.0 if r == 0 else (1.0 / 3.0 if r == 1 else 1.0)


## Lernkarte für die umgekehrte Richtung: Englisch wird gezeigt, Deutsch ist die Lösung.
## Schlüssel bleibt gleich, damit Statistik und Scheduler dasselbe Wort meinen.
static func reversed_item(item: Dictionary) -> Dictionary:
	var e: Dictionary = item.entry
	var swapped := {"id": e.id, "de": e.en, "en": e.de, "alternatives": [], "caseSensitive": true, "reversed": true}
	var out := item.duplicate()
	out.entry = swapped
	return out


## Kurzbeschreibung des gewählten Pakts für Tooltips.
static func summary(pact: Dictionary) -> String:
	if pact.is_empty():
		return "Kein Pakt"
	var parts: PackedStringArray = []
	for m: Dictionary in ALL:
		var r := rank(pact, m.id)
		if r > 0:
			parts.append("%s %s: %s" % [m.icon, m.name, describe(m.id, r)])
	return "\n".join(parts)
