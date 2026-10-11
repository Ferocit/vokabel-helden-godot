class_name Encounters
extends RefCounted
## Kleine Lernbegegnungen in der Erkundung (Issue #16: mehr Abfragen pro Spielminute):
##   Wissensschrein – fragt `shrine.words` Vokabeln nacheinander ab (jede einmal), Belohnung nach Treffern.
##   Runenplatte    – liegt im Gang und löst beim Drüberlaufen eine Vokabel aus: richtig → Gold, falsch → etwas Schaden.
## Werte: config/game.json → shrine, plate.


## Belohnung eines Schreins für `hits` richtige (oder fast richtige) Antworten.
## { gold, heal, focus, perfect }
static func shrine_reward(hits: int, max_hp: int) -> Dictionary:
	var c := GameConfig.section("shrine")
	var perfect := hits >= int(c.words)
	return {
		"gold": hits * int(c.goldPerCorrect),
		"heal": CombatService.js_round(max_hp * float(c.perfectHealShare)) if perfect else 0,
		"focus": int(c.perfectFocus) if perfect else 0,
		"perfect": perfect,
	}


## Ergebnis einer Runenplatte: { gold, damage }. Schaden bringt niemanden unter 1 HP.
static func plate_result(outcome: String, hp: int) -> Dictionary:
	var c := GameConfig.section("plate")
	if outcome == "wrongCorrected":
		return {"gold": 0, "damage": mini(int(c.damage), maxi(0, hp - 1))}
	return {"gold": int(c.gold), "damage": 0}


## Runenplatte an dieser Kachel, die noch nicht ausgelöst wurde (oder ein leeres Dictionary).
static func plate_at(run: Dictionary, tile: Vector2i) -> Dictionary:
	for obj: Dictionary in run.map.objects:
		if obj.kind == "plate" and int(obj.x) == tile.x and int(obj.y) == tile.y and not run.opened.has(obj.id):
			return obj
	return {}
