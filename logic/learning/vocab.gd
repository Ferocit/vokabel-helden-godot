class_name Vocab
extends RefCounted
## Datentypen der Lernlogik als Dictionaries (bleiben JSON-kompatibel zum Spielstand):
##   VocabEntry  { id, de, en, alternatives: Array[String], caseSensitive: bool }
##   VocabStats  { seen, correct, wrong, streak, mastery, lastSeen (ms oder null), hintsUsed,
##                 firstTry (auf Anhieb richtig), firstTryStreak (so oft in Folge auf Anhieb richtig) }
##               Global über alle Abenteuer und Trainings (Ctx.progress), Schlüssel „Set/Vokabel“.
##   VocabUnit   { id, title, createdAt (ms), vocabulary: Array[VocabEntry] }
##   LearningItem{ key, entry }
##   AnswerResult{ outcome: "correct" | "wrongCorrected", hintsUsed, firstTry (optional: richtig ohne Hilfe
##                 und ohne vorherigen Fehler in dieser Sitzung) }


static func item_key(unit_id: String, vocab_id: String) -> String:
	return "%s/%s" % [unit_id, vocab_id]


static func empty_stats() -> Dictionary:
	return {"seen": 0, "correct": 0, "wrong": 0, "streak": 0, "mastery": 0.0, "lastSeen": null, "hintsUsed": 0, "firstTry": 0, "firstTryStreak": 0}


static func entry(id: String, de: String, en: String, alternatives: Array = [], case_sensitive: bool = true) -> Dictionary:
	return {"id": id, "de": de, "en": en, "alternatives": alternatives, "caseSensitive": case_sensitive}


static func result(outcome: String, hints_used: int = 0) -> Dictionary:
	return {"outcome": outcome, "hintsUsed": hints_used}


static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


# ---------- Antwortprüfung ----------

## Erlaubt ist nur das Entfernen von führendem und nachgestelltem Whitespace.
static func normalize_answer(input: String) -> String:
	return input.strip_edges()


static func accepted_answers(e: Dictionary) -> Array:
	var list: Array = [e.en]
	list.append_array(e.alternatives)
	return list


static func is_correct_answer(e: Dictionary, input: String) -> bool:
	var answer := normalize_answer(input)
	if answer.is_empty():
		return false
	for expected: String in accepted_answers(e):
		if e.caseSensitive:
			if expected == answer:
				return true
		elif expected.to_lower() == answer.to_lower():
			return true
	return false


## Bei der Fehlerkorrektur muss die angezeigte Lösung exakt abgetippt werden.
static func is_correct_copy(expected: String, input: String) -> bool:
	return normalize_answer(input) == expected


# ---------- Mastery ----------

static func clamp_mastery(value: float) -> float:
	return clampf(roundf(value * 1000.0) / 1000.0, 0.0, 1.0)


## Richtig: +gain, ohne Hilfe zusätzlich +bonus. Falsch (auch wenn korrekt abgeschrieben): -loss.
static func next_mastery(current: float, res: Dictionary, cfg: Dictionary) -> float:
	if res.outcome == "wrongCorrected":
		return clamp_mastery(current - cfg.masteryWrongLoss)
	var bonus: float = cfg.masteryNoHintBonus if res.hintsUsed == 0 else 0.0
	return clamp_mastery(current + cfg.masteryCorrectGain + bonus)


static func mastery_label(mastery: float) -> String:
	if mastery >= 0.9:
		return "sehr sicher"
	if mastery >= 0.7:
		return "meist korrekt"
	if mastery >= 0.45:
		return "teilweise sicher"
	if mastery > 0.0:
		return "erste Begegnungen"
	return "unbekannt"


# ---------- Statistik ----------

static func record_answer(stats: Variant, res: Dictionary, cfg: Dictionary, now: int) -> Dictionary:
	var s: Dictionary = stats if stats is Dictionary else empty_stats()
	var correct: bool = res.outcome == "correct"
	var first_try: bool = correct and bool(res.get("firstTry", false))
	return {
		"seen": int(s.seen) + 1,
		"correct": int(s.correct) + (1 if correct else 0),
		"wrong": int(s.wrong) + (0 if correct else 1),
		"streak": int(s.streak) + 1 if correct else 0,
		"mastery": next_mastery(float(s.mastery), res, cfg),
		"lastSeen": now,
		"hintsUsed": int(s.hintsUsed) + int(res.hintsUsed),
		"firstTry": int(s.get("firstTry", 0)) + (1 if first_try else 0),
		"firstTryStreak": int(s.get("firstTryStreak", 0)) + 1 if first_try else 0,
	}


static func error_rate(stats: Dictionary) -> float:
	return 0.0 if int(stats.seen) == 0 else float(stats.wrong) / float(stats.seen)


static func success_rate(stats: Dictionary) -> float:
	return 0.0 if int(stats.seen) == 0 else float(stats.correct) / float(stats.seen)
