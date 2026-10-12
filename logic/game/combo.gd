class_name Combo
extends RefCounted
## Kombo-Zähler (Issue #21): Richtige Antworten in Folge machen Angriffe und Fähigkeiten stärker.
## Auf Anhieb richtig (ohne Hilfe) → +1; mit Hilfe, im zweiten Versuch oder „fast richtig“ bleibt die Kombo stehen;
## falsch → 0.
## Die Kombo gilt für das ganze Abenteuer (Kämpfe, Truhen, Türen) und steht in run.combo.
## Werte: config/game.json → combat.combo { step, max }.


static func cfg() -> Dictionary:
	return GameConfig.section("combat").combo


static func next(combo: int, res: Dictionary) -> int:
	match res.outcome:
		"correct":
			return combo + 1 if Vocab.unaided(res) else combo
		"almostCorrect":
			return combo
	return 0


## Schadensfaktor, z. B. 1.3 bei Kombo 3 (gedeckelt bei combo.max Stufen).
static func multiplier(combo: int) -> float:
	var c := cfg()
	return 1.0 + float(c.step) * mini(combo, int(c.max))


static func text(combo: int) -> String:
	return "⚡ ×%s" % String.num(multiplier(combo), 1)
