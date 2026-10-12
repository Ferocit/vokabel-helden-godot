class_name SetBonus
extends RefCounted
## Super-Bonus (Issue #29): Wer in einem Abenteuer jede Vokabel eines Sets mindestens einmal richtig schreibt,
## wird „Set-Meister“ – sofort volle Heilung und voller Fokus, am Ende Bonus-Splitter und ein Stern am Set.
## Golden 🌟: jede Vokabel mindestens einmal ohne Hilfe richtig (größere Belohnung, ersetzt den normalen Bonus).
## „Fast richtig“ zählt nicht – das Wort muss einmal korrekt geschrieben sein. Das Training zählt nicht.
##
## Im Lauf: run.setWords {unitId: Anzahl Wörter}, run.setHits {key: true}, run.setClean {key: true},
##          run.setBonus {unitId: "normal" | "golden"}
## Dauerhaft: profile.setStars {unitId: 1 (Set-Meister) | 2 (golden)}
## Werte: config/game.json → setBonus { shards, goldenShards }


static func cfg() -> Dictionary:
	return GameConfig.section("setBonus")


static func unit_of(item: Dictionary) -> String:
	return String(item.get("unitId", ""))


## Lauf-Felder anlegen (Wörter je Set aus den Lernkarten des Abenteuers).
static func init_run(run: Dictionary, items: Array) -> void:
	var words := {}
	for item: Dictionary in items:
		var u := unit_of(item)
		words[u] = int(words.get(u, 0)) + 1
	run.setWords = words
	run.setHits = {}
	run.setClean = {}
	run.setBonus = {}


## Fortschritt je Set: { unitId: {hits, clean, total} }
static func progress(run: Dictionary, items: Array) -> Dictionary:
	var out := {}
	for u: String in run.get("setWords", {}):
		out[u] = {"hits": 0, "clean": 0, "total": int(run.setWords[u])}
	for item: Dictionary in items:
		var u := unit_of(item)
		if not out.has(u):
			continue
		if run.setHits.has(item.key):
			out[u].hits += 1
		if run.setClean.has(item.key):
			out[u].clean += 1
	return out


## Eine Antwort eintragen. Liefert die dadurch neu erreichten Boni: [{unitId, level: "normal"|"golden"}].
static func record(run: Dictionary, items: Array, item: Dictionary, res: Dictionary) -> Array:
	if not run.has("setWords") or res.outcome != "correct":
		return []
	run.setHits[item.key] = true
	if Vocab.unaided(res):
		run.setClean[item.key] = true
	var u := unit_of(item)
	var p: Dictionary = progress(run, items).get(u, {})
	if p.is_empty():
		return []
	var have: String = run.setBonus.get(u, "")
	var level := ""
	if int(p.clean) >= int(p.total) and have != "golden":
		level = "golden"
	elif int(p.hits) >= int(p.total) and have == "":
		level = "normal"
	if level == "":
		return []
	run.setBonus[u] = level
	return [{"unitId": u, "level": level}]


static func shards_for(level: String) -> int:
	return int(cfg().goldenShards) if level == "golden" else int(cfg().shards)


## Stern am Set dauerhaft merken (der bessere bleibt).
static func award_star(profile: Dictionary, unit_id: String, level: String) -> void:
	if not profile.get("setStars") is Dictionary:
		profile.setStars = {}
	var stars := 2 if level == "golden" else 1
	profile.setStars[unit_id] = maxi(int(profile.setStars.get(unit_id, 0)), stars)


static func star_text(stars: int) -> String:
	return "🌟" if stars >= 2 else ("⭐" if stars == 1 else "")
