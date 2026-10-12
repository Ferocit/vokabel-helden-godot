class_name LearningScheduler
extends RefCounted
## Gewichtete Vokabelauswahl mit Wiederholungs-Warteschlange.
## Modi: "normal" | "preferHard" (Elite, Boss, besondere Truhen). Verteidigen nutzt die normale Auswahl –
## kein Kampfbefehl darf schwierige Wörter umgehen (Issue #19).
## Über alle Abenteuer hinweg (VocabStats): Noch nie oder selten abgefragte und zuletzt falsche Wörter
## haben Vorrang; wer ein Wort mehrmals in Folge auf Anhieb richtig weiß, bekommt es seltener.

const HOUR_MS := 60 * 60 * 1000

var picks := 0
var history: Array[String] = []
var wrong_in_run := {}  # key → misses
var pending := {}  # key → {dueAt, misses}
## Im Run bereits richtig beantwortet – erst wieder dran, wenn die anderen Wörter durch sind.
var correct_in_run := {}  # key → true
var options := {}  # repeatGapReduction
## Durchschnittliche Abfragen pro Wort im Set (für „selten dran“), wird vor jeder Auswahl aktualisiert.
var average_seen := 0.0

var _items: Array
var _by_key := {}
var _get_stats: Callable
var _cfg: Dictionary
var _rng: Callable
var _now: Callable


func _init(items: Array, get_stats: Callable, cfg: Dictionary, rng: Callable, now: Callable = Vocab.now_ms, opts: Dictionary = {}) -> void:
	assert(not items.is_empty(), "Keine Vokabeln für den Run vorhanden.")
	_items = items
	_get_stats = get_stats
	_cfg = cfg
	_rng = rng
	_now = now
	options = opts.duplicate()
	for item: Dictionary in items:
		_by_key[item.key] = item


func snapshot() -> Dictionary:
	var wrong: Array = []
	for k: String in wrong_in_run:
		wrong.append([k, wrong_in_run[k]])
	var pend: Array = []
	for k: String in pending:
		pend.append([k, pending[k].duplicate()])
	return {
		"picks": picks,
		"history": history.slice(-10),
		"wrongInRun": wrong,
		"pending": pend,
		"correctInRun": correct_in_run.keys(),
	}


func restore(snap: Dictionary) -> void:
	picks = int(snap.picks)
	history.clear()
	for k: String in snap.history:
		history.append(k)
	wrong_in_run.clear()
	for pair: Array in snap.wrongInRun:
		if _by_key.has(pair[0]):
			wrong_in_run[pair[0]] = int(pair[1])
	pending.clear()
	for pair: Array in snap.pending:
		if _by_key.has(pair[0]):
			pending[pair[0]] = {"dueAt": int(pair[1].dueAt), "misses": int(pair[1].misses)}
	correct_in_run.clear()
	for k: String in snap.get("correctInRun", []):
		if _by_key.has(k):
			correct_in_run[k] = true


func set_options(opts: Dictionary) -> void:
	options.merge(opts, true)


## Wörter, die im Run falsch waren und noch einmal richtig beantwortet werden müssen.
func owed_repeats() -> Array:
	var list: Array = []
	for k: String in pending:
		list.append(_by_key[k])
	return list


func next(mode: String = "normal") -> Dictionary:
	refresh_average_seen()
	var candidates := _without_recent(_items)

	# 1. Fällige Wiederholungen haben Vorrang.
	var due: Array = candidates.filter(func(item: Dictionary) -> bool:
		return pending.has(item.key) and int(pending[item.key].dueAt) <= picks)
	if not due.is_empty():
		due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(pending[a.key].dueAt) < int(pending[b.key].dueAt))
		return _take(due[0])

	# 2. Noch nicht fällige Wiederholungen nicht zu früh zeigen.
	var not_early: Array = candidates.filter(func(item: Dictionary) -> bool: return not pending.has(item.key))
	var pool: Array = not_early if not not_early.is_empty() else candidates
	# 3. Abwechslung: Im Run schon Richtiges kommt erst wieder, wenn alle anderen dran waren.
	var fresh: Array = pool.filter(func(item: Dictionary) -> bool: return not correct_in_run.has(item.key))
	if not fresh.is_empty():
		pool = fresh

	return _take(Rng.weighted_pick(_rng, pool, func(item: Dictionary) -> float: return weight(item, mode)))


## Ergebnis der zuletzt gezogenen Vokabel melden.
func report(key: String, outcome: String) -> void:
	if outcome == "correct":
		pending.erase(key)
		correct_in_run[key] = true
		return
	correct_in_run.erase(key)
	if outcome == "almostCorrect":
		# Fast richtig: bald noch einmal, aber ohne Fehler-Gewicht.
		pending[key] = {"dueAt": picks + Rng.rand_int(_rng, int(_cfg.minRepeatGap), int(_cfg.maxRepeatGap)), "misses": int(wrong_in_run.get(key, 0))}
		return
	var misses: int = int(wrong_in_run.get(key, 0)) + 1
	wrong_in_run[key] = misses
	var reduction: int = int(options.get("repeatGapReduction", 0))
	var min_gap: int = maxi(1, int(_cfg.minRepeatGap) - reduction)
	var max_gap: int = maxi(min_gap, int(_cfg.maxRepeatGap) - reduction)
	pending[key] = {"dueAt": picks + Rng.rand_int(_rng, min_gap, max_gap), "misses": misses}


func refresh_average_seen() -> void:
	var total := 0
	for item: Dictionary in _items:
		var s: Variant = _get_stats.call(item.key)
		total += int(s.seen) if s is Dictionary else 0
	average_seen = float(total) / _items.size()


func weight(item: Dictionary, mode: String) -> float:
	var s: Variant = _get_stats.call(item.key)
	var stats: Dictionary = s if s is Dictionary else Vocab.empty_stats()
	var w := 1.0

	# Über alle Abenteuer: noch nie oder seltener als der Durchschnitt dran → Vorrang.
	var seen: int = int(stats.seen)
	if seen == 0:
		# Pakt „Neue Wörter“ (Issue #22): noch nie Geübtes kommt deutlich öfter.
		w += float(_cfg.unseenWeight) * (3.0 if options.get("unseenBoost", false) else 1.0)
	elif average_seen > 0.0 and seen < average_seen:
		w += float(_cfg.rarelySeenWeight) * (1.0 - seen / average_seen)
	# Zuletzt falsch beantwortet (die Serie ist seitdem nicht wieder angelaufen).
	if int(stats.wrong) > 0 and int(stats.streak) == 0:
		w += float(_cfg.lastWrongWeight)

	var misses: int = int(wrong_in_run.get(item.key, 0))
	if misses > 0:
		w += float(_cfg.wrongAnswerWeight) * misses
	if int(stats.seen) >= 2 and Vocab.error_rate(stats) > float(_cfg.highErrorRateThreshold):
		w += float(_cfg.highErrorRateWeight)
	if stats.lastSeen == null or int(_now.call()) - int(stats.lastSeen) > float(_cfg.notSeenRecentlyHours) * HOUR_MS:
		w += float(_cfg.notSeenRecentlyWeight)
	w = maxf(1.0, w)
	# Mehrmals in Folge auf Anhieb richtig → deutlich seltener (aber nie ganz weg).
	var known: int = int(stats.get("firstTryStreak", 0))
	if known > 0:
		w *= maxf(float(_cfg.minKnownFactor), pow(float(_cfg.firstTryDecay), known))

	var mastery: float = float(stats.mastery)
	if mode == "preferHard":
		w *= 1.0 + 3.0 * (1.0 - mastery)
		w += 2.0 * mini(int(stats.wrong), 3)
	return w


func _without_recent(items: Array) -> Array:
	var window: int = mini(int(_cfg.recentHistorySize), items.size() - 1)
	if window <= 0:
		return items
	var recent := {}
	for k in history.slice(-window):
		recent[k] = true
	return items.filter(func(item: Dictionary) -> bool: return not recent.has(item.key))


## Ein bestimmtes Wort abfragen (z. B. ein Nemesis-Wort des Bosses); zählt wie eine normale Auswahl.
func take(key: String) -> Dictionary:
	return _take(_by_key[key]) if _by_key.has(key) else next()


func _take(item: Dictionary) -> Dictionary:
	picks += 1
	history.append(item.key)
	return item
