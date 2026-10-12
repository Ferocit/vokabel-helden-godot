class_name LearningSession
extends RefCounted
## Verbindet Scheduler, Statistik, Mastery und Run-Protokoll.
## Spielcode fragt hier nach der nächsten Vokabel und meldet das Ergebnis zurück.

var scheduler: LearningScheduler
var run: RunSession

var _progress: Dictionary  # key → VocabStats (geteilte Referenz, z. B. Ctx.progress)
var _cfg: Dictionary
var _now: Callable


func _init(items: Array, progress: Dictionary, cfg: Dictionary, rng: Callable, now: Callable = Vocab.now_ms, opts: Dictionary = {}) -> void:
	_progress = progress
	_cfg = cfg
	_now = now
	scheduler = LearningScheduler.new(items, func(key: String) -> Variant: return _progress.get(key), cfg, rng, now, opts)
	run = RunSession.new()


func next_word(mode: String = "normal") -> Dictionary:
	return scheduler.next(mode)


## Ein bestimmtes Wort abfragen (Nemesis-Rüstung des Bosses, Issue #24).
func word(key: String) -> Dictionary:
	return scheduler.take(key)


func submit(item: Dictionary, res: Dictionary) -> Dictionary:
	# Auf Anhieb richtig: ohne Hilfe und ohne vorherigen Fehler mit diesem Wort im Abenteuer.
	res = res.duplicate()
	res.firstTry = res.outcome == "correct" and Vocab.unaided(res) and not scheduler.wrong_in_run.has(item.key)
	var before: Variant = _progress.get(item.key)
	var updated := Vocab.record_answer(before, res, _cfg, int(_now.call()))
	_progress[item.key] = updated
	scheduler.report(item.key, res.outcome)
	var mastery_before: float = float(before.mastery) if before is Dictionary else 0.0
	run.record(item, res, mastery_before, updated.mastery)
	return {"masteryBefore": mastery_before, "masteryAfter": updated.mastery}


func snapshot() -> Dictionary:
	return {"scheduler": scheduler.snapshot(), "run": run.snapshot()}


func restore(snap: Dictionary) -> void:
	scheduler.restore(snap.scheduler)
	run = RunSession.restore(snap.run)
