class_name RunSession
extends RefCounted
## Protokolliert alle Lernabfragen eines Runs für die Auswertung.
## WordRunRecord { item, asked, correct, wrong, firstTryCorrect, hintsUsed, masteryBefore, masteryAfter }

var questions := 0
var records := {}  # key → WordRunRecord (Einfügereihenfolge bleibt erhalten)


func snapshot() -> Dictionary:
	var list: Array = []
	for r: Dictionary in records.values():
		list.append(r.duplicate(true))
	return {"questions": questions, "records": list}


static func restore(snap: Dictionary) -> RunSession:
	var run := RunSession.new()
	run.questions = int(snap.questions)
	for r: Dictionary in snap.records:
		run.records[r.item.key] = r.duplicate(true)
	return run


func record(item: Dictionary, res: Dictionary, mastery_before: float, mastery_after: float) -> void:
	questions += 1
	var correct: bool = res.outcome == "correct"
	if not records.has(item.key):
		records[item.key] = {
			"item": item,
			"asked": 1,
			"correct": 1 if correct else 0,
			"wrong": 0 if correct else 1,
			"firstTryCorrect": correct and int(res.hintsUsed) == 0,
			"hintsUsed": int(res.hintsUsed),
			"masteryBefore": mastery_before,
			"masteryAfter": mastery_after,
		}
		return
	var r: Dictionary = records[item.key]
	r.asked = int(r.asked) + 1
	r.correct = int(r.correct) + (1 if correct else 0)
	r.wrong = int(r.wrong) + (0 if correct else 1)
	r.hintsUsed = int(r.hintsUsed) + int(res.hintsUsed)
	r.masteryAfter = mastery_after


## { totalQuestions, words, firstTryCorrect, wrongWords, withHints, masteryDelta, hardest }
func summary() -> Dictionary:
	var words: Array = records.values()
	var delta := 0.0
	for w: Dictionary in words:
		delta += float(w.masteryAfter) - float(w.masteryBefore)
	var hardest: Array = words.filter(func(w: Dictionary) -> bool: return int(w.wrong) > 0)
	hardest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.wrong) != int(b.wrong):
			return int(a.wrong) > int(b.wrong)
		return float(a.masteryAfter) < float(b.masteryAfter))
	return {
		"totalQuestions": questions,
		"words": words,
		"firstTryCorrect": words.filter(func(w: Dictionary) -> bool: return w.firstTryCorrect),
		"wrongWords": words.filter(func(w: Dictionary) -> bool: return int(w.wrong) > 0),
		"withHints": words.filter(func(w: Dictionary) -> bool: return int(w.hintsUsed) > 0),
		"masteryDelta": delta,
		"hardest": hardest.slice(0, 5),
	}
