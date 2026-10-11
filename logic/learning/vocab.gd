class_name Vocab
extends RefCounted
## Datentypen der Lernlogik als Dictionaries (bleiben JSON-kompatibel zum Spielstand):
##   VocabEntry  { id, de, en, alternatives: Array[String], caseSensitive: bool }
##   VocabStats  { seen, correct, wrong, streak, mastery, lastSeen (ms oder null), hintsUsed,
##                 firstTry (auf Anhieb richtig), firstTryStreak (so oft in Folge auf Anhieb richtig) }
##               Global über alle Abenteuer und Trainings (Ctx.progress), Schlüssel „Set/Vokabel“.
##   VocabUnit   { id, title, createdAt (ms), vocabulary: Array[VocabEntry] }
##   LearningItem{ key, entry }
##   AnswerResult{ outcome: "correct" | "almostCorrect" | "wrongCorrected", hintsUsed, firstTry (optional: richtig
##                 ohne Hilfe und ohne vorherigen Fehler in dieser Sitzung) }
##   „almostCorrect“: ein Tippfehler (ein Buchstabe falsch, zu viel, zu wenig oder zwei vertauscht) oder nur die
##   Großschreibung falsch – zählt halb (Issue #17).


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


## Stimmt die Groß-/Kleinschreibung? Lösungen ganz in Kleinbuchstaben dürfen beliebig geschrieben werden
## („House“ für „house“ am Satzanfang). Enthält die Lösung Großbuchstaben („I“, „Monday“), müssen sie stimmen –
## außer der Eintrag ist ausdrücklich `caseSensitive: false`.
static func _matches(expected: String, answer: String, case_sensitive: bool) -> bool:
	if not case_sensitive or expected == expected.to_lower():
		return expected.to_lower() == answer.to_lower()
	return expected == answer


static func is_correct_answer(e: Dictionary, input: String) -> bool:
	return check_answer(e, input) == "correct"


## "correct" | "almostCorrect" | "wrong" für die erste Eingabe (Issue #17).
static func check_answer(e: Dictionary, input: String) -> String:
	var answer := normalize_answer(input)
	if answer.is_empty():
		return "wrong"
	for expected: String in accepted_answers(e):
		if _matches(expected, answer, e.caseSensitive):
			return "correct"
	var min_len := int(GameConfig.section("learning").get("almostMinLength", 4))
	for expected: String in accepted_answers(e):
		if expected.to_lower() == answer.to_lower():
			return "almostCorrect"  # nur die Großschreibung
		if expected.length() >= min_len and one_typo(expected.to_lower(), answer.to_lower()):
			return "almostCorrect"
	return "wrong"


## Genau ein Tippfehler: ein Zeichen ersetzt, eingefügt, ausgelassen oder zwei Nachbarn vertauscht.
static func one_typo(a: String, b: String) -> bool:
	if a == b:
		return false
	var la := a.length()
	var lb := b.length()
	if absi(la - lb) > 1:
		return false
	var i := 0
	while i < mini(la, lb) and a[i] == b[i]:
		i += 1
	if la == lb:
		if a.substr(i + 1) == b.substr(i + 1):
			return true  # ersetzt
		return i + 1 < la and a[i] == b[i + 1] and a[i + 1] == b[i] and a.substr(i + 2) == b.substr(i + 2)  # vertauscht
	if la > lb:
		return a.substr(i + 1) == b.substr(i)  # ausgelassen
	return a.substr(i) == b.substr(i + 1)  # eingefügt


## Bei der Fehlerkorrektur muss die angezeigte Lösung exakt abgetippt werden.
static func is_correct_copy(expected: String, input: String) -> bool:
	return normalize_answer(input) == expected


# ---------- Mastery ----------

static func clamp_mastery(value: float) -> float:
	return clampf(roundf(value * 1000.0) / 1000.0, 0.0, 1.0)


## Richtig: +gain, ohne Hilfe zusätzlich +bonus. Fast richtig: +almostGain. Falsch (auch wenn korrekt
## abgeschrieben): -loss.
static func next_mastery(current: float, res: Dictionary, cfg: Dictionary) -> float:
	if res.outcome == "wrongCorrected":
		return clamp_mastery(current - cfg.masteryWrongLoss)
	if res.outcome == "almostCorrect":
		return clamp_mastery(current + float(cfg.get("masteryAlmostGain", 0.0)))
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
	var almost: bool = res.outcome == "almostCorrect"
	var first_try: bool = correct and bool(res.get("firstTry", false))
	# Fast richtig zählt nicht als Fehler, hält die Serie an und ist nie „auf Anhieb“.
	return {
		"seen": int(s.seen) + 1,
		"correct": int(s.correct) + (1 if correct else 0),
		"wrong": int(s.wrong) + (1 if res.outcome == "wrongCorrected" else 0),
		"almost": int(s.get("almost", 0)) + (1 if almost else 0),
		"streak": int(s.streak) + 1 if correct else (int(s.streak) if almost else 0),
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
