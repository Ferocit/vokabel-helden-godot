class_name Nemesis
extends RefCounted
## Der Boss als persönliche Nemesis (Issue #24): Er „kennt deine Schwachstellen“ – seine Rüstungsteile sind die
## schwierigsten Wörter des Spielers (über alle Abenteuer). Solange er Rüstung trägt, richten Angriffe nur einen Teil
## des Schadens an; ein Rüstungsteil zerbricht, wenn sein Wort richtig beantwortet wird. Wörter, die man inzwischen
## beherrscht (Mastery ≥ masteredAt), verschwinden aus seiner Rüstung – sichtbarer Fortschritt von Lauf zu Lauf.
## Werte: config/game.json → nemesis { armorPieces, armorDamageFactor, masteredAt }.


static func cfg() -> Dictionary:
	return GameConfig.section("nemesis")


## Wie schwierig ein Wort für diesen Spieler ist (höher = schwerer).
static func difficulty(stats: Variant) -> float:
	if not stats is Dictionary:
		return 0.5  # noch nie gesehen: mittelschwer
	var s: Dictionary = stats
	var score := 1.0 - float(s.get("mastery", 0.0))
	score += 1.5 * Vocab.error_rate(s)
	if int(s.get("wrong", 0)) > 0 and int(s.get("streak", 0)) == 0:
		score += 0.5  # zuletzt falsch
	return score


## Die Nemesis-Wörter: höchstens armorPieces Stück, schwerste zuerst, ohne beherrschte Wörter.
## Ohne bisherige Fehler zählen nur Wörter, die schon einmal falsch waren oder wenig Mastery haben.
static func pick(items: Array, progress: Dictionary) -> Array:
	var c := cfg()
	var candidates: Array = items.filter(func(item: Dictionary) -> bool:
		var s: Variant = progress.get(item.key)
		return not (s is Dictionary and float(s.mastery) >= float(c.masteredAt)))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := difficulty(progress.get(a.key))
		var db := difficulty(progress.get(b.key))
		return da > db if da != db else String(a.key) < String(b.key))
	return candidates.slice(0, int(c.armorPieces))


## Der Satz, mit dem der Boss den Kampf eröffnet.
static func taunt(boss_name: String, words: Array) -> String:
	if words.is_empty():
		return "%s: „Du kennst jedes Wort … diesmal kann ich mich hinter nichts verstecken!“" % boss_name
	var de: PackedStringArray = []
	for w: Dictionary in words:
		de.append("„%s“" % w.entry.de)
	return "%s: „Ich kenne deine Schwachstellen: %s. Meine Rüstung hält, bis du sie bezwingst!“" % [boss_name, ", ".join(de)]
