extends TestCase
## Portierung von AnswerValidator-, Mastery-, Hint-, RunSession-, Scheduler- und LearningSession-Tests.

const NOW := 1000000000000


func cfg() -> Dictionary:
	return GameConfig.section("learning")


static func entry(id: String, en: String, extra: Dictionary = {}) -> Dictionary:
	var e := Vocab.entry(id, "de_" + id, en)
	e.merge(extra, true)
	return e


static func items(count: int) -> Array:
	var list: Array = []
	for i in count:
		var e := entry("w%d" % i, "word%d" % i)
		list.append({"key": "u/" + e.id, "entry": e})
	return list


func scheduler(count: int, seed: int = 1, stats: Dictionary = {}, reduction: int = 0) -> LearningScheduler:
	return LearningScheduler.new(items(count), func(k: String) -> Variant: return stats.get(k), cfg(), Rng.create(seed), func() -> int: return NOW, {"repeatGapReduction": reduction})


## Zieht so lange (alles korrekt beantwortet), bis `key` wieder dran ist; liefert die Anzahl Wörter dazwischen.
func gap_until(s: LearningScheduler, key: String, limit: int = 50) -> int:
	var gap := 0
	var item := s.next()
	while item.key != key:
		s.report(item.key, "correct")
		gap += 1
		if gap > limit:
			fail("Wort kam nicht wieder")
			return gap
		item = s.next()
	return gap


static func stats_of(seen: int, correct: int, wrong: int, streak: int, mastery: float) -> Dictionary:
	return {"seen": seen, "correct": correct, "wrong": wrong, "streak": streak, "mastery": mastery, "lastSeen": NOW, "hintsUsed": 0}


# ---------- AnswerValidator ----------

func test_validator_exakt_und_trim() -> void:
	var d := entry("1", "dangerous")
	expect_true(Vocab.is_correct_answer(d, "dangerous"))
	expect_true(Vocab.is_correct_answer(d, "  dangerous \t"))
	for wrong in ["dangerus", "dnagerous", "dangerou", "dangerouss", "dan gerous", "   "]:
		expect_false(Vocab.is_correct_answer(d, wrong), wrong)


func test_validator_gross_klein_und_alternativen() -> void:
	var monday := entry("2", "Monday")
	expect_true(Vocab.is_correct_answer(monday, "Monday"))
	expect_false(Vocab.is_correct_answer(monday, "monday"))
	expect_eq(Vocab.check_answer(monday, "monday"), "almostCorrect", "nur Großschreibung falsch")
	# Kleingeschriebene Lösung: Großschreibung ist egal (Issue #17).
	expect_true(Vocab.is_correct_answer(entry("1", "dangerous"), "Dangerous"))
	expect_true(Vocab.is_correct_answer(entry("3", "house", {"caseSensitive": false}), "HOUSE"))
	var fast := entry("4", "fast", {"alternatives": ["quick"]})
	expect_true(Vocab.is_correct_answer(fast, "quick"))
	expect_false(Vocab.is_correct_answer(fast, "rapid"))
	expect_true(Vocab.is_correct_copy("dangerous", " dangerous "))
	expect_false(Vocab.is_correct_copy("dangerous", "Dangerous"))


func test_fast_richtig_ein_tippfehler() -> void:
	var d := entry("1", "dangerous")
	for typo in ["dangerus", "dnagerous", "dangerou", "dangerouss", "dangerois", "Dangerus"]:
		expect_eq(Vocab.check_answer(d, typo), "almostCorrect", typo)
	for wrong in ["dangrus", "danger", "safe", "dan gerous x", "   "]:
		expect_eq(Vocab.check_answer(d, wrong), "wrong", wrong)
	# Kurze Wörter: kein Tippfehler-Bonus („cat“ vs. „car“ sind verschiedene Wörter).
	expect_eq(Vocab.check_answer(entry("2", "cat"), "car"), "wrong")
	# Alternativen zählen auch.
	expect_eq(Vocab.check_answer(entry("3", "fast", {"alternatives": ["quickly"]}), "quickyl"), "almostCorrect")
	expect_true(Vocab.one_typo("house", "hosue"))
	expect_false(Vocab.one_typo("house", "house"))


func test_fast_richtig_lernlogik() -> void:
	expect_near(Vocab.next_mastery(0.5, Vocab.result("almostCorrect"), cfg()), 0.55)
	var s := Vocab.record_answer(null, Vocab.result("correct"), cfg(), 100)
	s = Vocab.record_answer(s, Vocab.result("almostCorrect"), cfg(), 200)
	expect_match(s, {"seen": 2, "correct": 1, "wrong": 0, "almost": 1, "streak": 1, "firstTryStreak": 0})
	# Scheduler: kommt bald wieder, aber ohne Fehler-Gewicht.
	var items := [{"key": "a", "entry": entry("a", "alpha")}, {"key": "b", "entry": entry("b", "beta")}, {"key": "c", "entry": entry("c", "gamma")}]
	var sched := LearningScheduler.new(items, func(_k: String) -> Variant: return null, cfg(), Rng.create(3))
	sched.next()
	sched.report("a", "almostCorrect")
	expect_true(sched.pending.has("a"))
	expect_false(sched.wrong_in_run.has("a"))
	var run := RunSession.new()
	run.record(items[0], Vocab.result("almostCorrect"), 0.0, 0.05)
	var sum := run.summary()
	expect_eq((sum.almostWords as Array).size(), 1)
	expect_eq((sum.wrongWords as Array).size(), 0)


# ---------- Mastery & Statistik ----------

func test_mastery() -> void:
	expect_near(Vocab.next_mastery(0, Vocab.result("correct", 0), cfg()), 0.15)
	expect_near(Vocab.next_mastery(0, Vocab.result("correct", 1), cfg()), 0.1)
	expect_near(Vocab.next_mastery(0.5, Vocab.result("wrongCorrected"), cfg()), 0.35)
	expect_eq(Vocab.next_mastery(0.05, Vocab.result("wrongCorrected"), cfg()), 0.0)
	expect_eq(Vocab.next_mastery(0.98, Vocab.result("correct"), cfg()), 1.0)
	expect_lt(Vocab.next_mastery(0, Vocab.result("correct"), cfg()), 0.25)


func test_statistik() -> void:
	var s := Vocab.record_answer(null, Vocab.result("correct", 1), cfg(), 100)
	s = Vocab.record_answer(s, Vocab.result("correct", 0), cfg(), 200)
	expect_match(s, {"seen": 2, "correct": 2, "wrong": 0, "streak": 2, "hintsUsed": 1, "lastSeen": 200})
	s = Vocab.record_answer(s, Vocab.result("wrongCorrected"), cfg(), 300)
	expect_match(s, {"seen": 3, "wrong": 1, "streak": 0})


# ---------- Hilfen ----------

func test_hilfen_masken() -> void:
	var d := entry("1", "dangerous")
	var st := HintService.apply(d, HintService.create_state(), "length")
	expect_eq(HintService.render_mask(d, st), "_ _ _ _ _ _ _ _ _")
	expect_eq(HintService.describe_length(d), "9 Buchstaben")
	st = HintService.apply(d, HintService.create_state(), "firstLetter")
	expect_eq(HintService.render_mask(d, st), "d _ _ _ _ _ _ _ _")
	var phrase := entry("2", "How are you?")
	st = HintService.apply(phrase, HintService.create_state(), "firstLetter")
	expect_eq(HintService.render_mask(phrase, st), "H _ _   _ _ _   _ _ _ ?")
	expect_eq(HintService.describe_length(phrase), "3 Wörter: 3 + 3 + 3 Buchstaben")


func test_hilfen_bezahlen() -> void:
	var wallet := HintService.pay({"freeCharges": {"length": 1}, "focus": 1, "costs": {"length": 1, "firstLetter": 2}}, "length")
	expect_match(wallet, {"focus": 1})
	expect_eq(wallet.freeCharges.length, 0)
	wallet = HintService.pay(wallet, "length")
	expect_eq(wallet.focus, 0)
	expect_true(HintService.pay(wallet, "length").is_empty())


# ---------- RunSession ----------

func test_run_session_zusammenfassung() -> void:
	var run := RunSession.new()
	var a := {"key": "u/a", "entry": entry("a", "apple")}
	var b := {"key": "u/b", "entry": entry("b", "banana")}
	run.record(a, Vocab.result("correct", 0), 0, 0.15)
	run.record(b, Vocab.result("wrongCorrected", 0), 0.3, 0.15)
	run.record(b, Vocab.result("correct", 1), 0.15, 0.25)
	var s := run.summary()
	var keys := func(list: Array) -> Array: return list.map(func(w: Dictionary) -> String: return w.item.key)
	expect_eq(s.totalQuestions, 3)
	expect_eq(keys.call(s.firstTryCorrect), ["u/a"])
	expect_eq(keys.call(s.wrongWords), ["u/b"])
	expect_eq(keys.call(s.withHints), ["u/b"])
	expect_near(s.masteryDelta, 0.1)


# ---------- LearningScheduler ----------

func test_scheduler_nie_direkt_doppelt() -> void:
	var s := scheduler(5)
	var last := ""
	for i in 200:
		var item := s.next()
		expect_ne(item.key, last)
		last = item.key
		s.report(item.key, "correct")


func test_scheduler_wiederholungsabstand() -> void:
	for seed in range(1, 101):
		var s := scheduler(20, seed)
		var wrong := s.next()
		s.report(wrong.key, "wrongCorrected")
		var gap := gap_until(s, wrong.key)
		expect_ge(gap, cfg().minRepeatGap, "seed %d" % seed)
		expect_le(gap, cfg().maxRepeatGap, "seed %d" % seed)


func test_scheduler_offene_wiederholungen() -> void:
	var s := scheduler(10)
	var wrong := s.next()
	s.report(wrong.key, "wrongCorrected")
	expect_eq(s.owed_repeats().map(func(i: Dictionary) -> String: return i.key), [wrong.key])
	gap_until(s, wrong.key)
	s.report(wrong.key, "wrongCorrected")
	expect_eq(s.owed_repeats().size(), 1)
	gap_until(s, wrong.key)
	s.report(wrong.key, "correct")
	expect_eq(s.owed_repeats().size(), 0)


func test_scheduler_ausruestung_verkuerzt_abstand() -> void:
	for seed in range(1, 31):
		var s := scheduler(20, seed, {}, 1)
		var wrong := s.next()
		s.report(wrong.key, "wrongCorrected")
		expect_le(gap_until(s, wrong.key), cfg().maxRepeatGap - 1)


func test_scheduler_sichere_woerter_seltener() -> void:
	var all := items(10)
	var stats := {}
	for i in all.size():
		var known := i < 5
		stats[all[i].key] = stats_of(10, 10 if known else 4, 0 if known else 6, 6 if known else 0, 1.0 if known else 0.2)
	var s := LearningScheduler.new(all, func(k: String) -> Variant: return stats.get(k), cfg(), Rng.create(42), func() -> int: return NOW)
	var known_picks := 0
	for i in 2000:
		var item := s.next()
		if int((item.entry.id as String).substr(1)) < 5:
			known_picks += 1
		s.report(item.key, "correct")
	expect_lt(known_picks / 2000.0, 0.35)


func test_scheduler_modi() -> void:
	var all := items(10)
	var stats := {}
	for i in all.size():
		var hard := i == 0
		stats[all[i].key] = stats_of(5, 1 if hard else 5, 4 if hard else 0, 0, 0.0 if hard else 0.8)
	var s := LearningScheduler.new(all, func(k: String) -> Variant: return stats.get(k), cfg(), Rng.create(7), func() -> int: return NOW)
	expect_gt(s.weight(all[0], "preferHard"), s.weight(all[1], "preferHard") * 2)
	expect_gt(s.weight(all[1], "preferKnown"), s.weight(all[0], "preferKnown"))


func test_scheduler_issue7_keine_wiederholung_richtiger() -> void:
	for mode in ["normal", "preferHard", "preferKnown"]:
		for seed in range(1, 21):
			var all := items(97)
			var stats := {}
			for i in all.size():
				if i % 3 == 0:
					stats[all[i].key] = stats_of(3, 3, 0, 3, 0.5)
			var s := LearningScheduler.new(all, func(k: String) -> Variant: return stats.get(k), cfg(), Rng.create(seed), func() -> int: return NOW)
			var seen := {}
			var repeats := 0
			for i in 30:
				var item := s.next(mode)
				if seen.has(item.key):
					repeats += 1
				seen[item.key] = true
				s.report(item.key, "correct")
			expect_eq(repeats, 0, "%s seed %d" % [mode, seed])


func test_scheduler_eine_vokabel() -> void:
	var s := scheduler(1)
	expect_eq(s.next().key, "u/w0")
	expect_eq(s.next().key, "u/w0")


# ---------- LearningSession ----------

func test_session_traegt_ergebnisse_ein() -> void:
	var progress := {}
	var session := LearningSession.new(items(8), progress, cfg(), Rng.create(1), func() -> int: return 1000)
	var first := session.next_word()
	session.submit(first, Vocab.result("wrongCorrected"))
	expect_match(progress[first.key], {"seen": 1, "wrong": 1, "mastery": 0})
	expect_eq(session.scheduler.owed_repeats().map(func(i: Dictionary) -> String: return i.key), [first.key])
	expect_eq(session.run.questions, 1)


func test_session_wiederholt_schwache_woerter() -> void:
	var progress := {}
	var session := LearningSession.new(items(20), progress, cfg(), Rng.create(5), func() -> int: return 1000)
	var seen := {}
	for i in 35:
		var item := session.next_word()
		seen[item.key] = int(seen.get(item.key, 0)) + 1
		var wrong: bool = seen[item.key] == 1 and i % 3 == 0 and i < 25
		session.submit(item, Vocab.result("wrongCorrected" if wrong else "correct"))
	var summary := session.run.summary()
	expect_eq(summary.totalQuestions, 35)
	for w: Dictionary in summary.wrongWords:
		expect_ge(w.asked, 2)


func test_session_speichern_und_laden() -> void:
	var progress := {}
	var a := LearningSession.new(items(10), progress, cfg(), Rng.create(2), func() -> int: return 1000)
	var w := a.next_word()
	a.submit(w, Vocab.result("wrongCorrected", 1))
	var snap: Dictionary = JSON.parse_string(JSON.stringify(a.snapshot()))
	var b := LearningSession.new(items(10), progress, cfg(), Rng.create(3), func() -> int: return 1000)
	b.restore(snap)
	expect_eq(b.scheduler.owed_repeats().map(func(i: Dictionary) -> String: return i.key), [w.key])
	expect_eq(b.run.summary().withHints.size(), 1)


func test_training_falsche_karten_kommen_wieder() -> void:
	var t := TrainingSession.new(items(4), Rng.create(7))
	var wrong_key: String = t.current().key
	t.submit(Vocab.result("wrongCorrected"))
	for i in 3:
		t.submit(Vocab.result("correct"))
	expect_false(t.is_finished(), "Falsche Karte steht noch aus")
	expect_eq(t.round, 2)
	expect_eq(t.current().key, wrong_key, "Falsche Karte kommt am Ende wieder")
	t.submit(Vocab.result("wrongCorrected"))
	expect_eq(t.current().key, wrong_key, "… so lange, bis sie sitzt")
	t.submit(Vocab.result("correct"))
	expect_true(t.is_finished())
	expect_eq(t.first_try, 3)
	expect_eq(t.wrong, 2)
	expect_eq(t.answered, 6)
	expect_eq(TrainingSession.reward_for(27), 5)
	expect_eq(TrainingSession.reward_for(3), 1, "Mindestens ein Splitter")


# ---------- Über mehrere Abenteuer ----------

func test_statistik_auf_anhieb_richtig() -> void:
	var s := Vocab.record_answer(null, {"outcome": "correct", "hintsUsed": 0, "firstTry": true}, cfg(), 1)
	s = Vocab.record_answer(s, {"outcome": "correct", "hintsUsed": 0, "firstTry": true}, cfg(), 2)
	expect_match(s, {"firstTry": 2, "firstTryStreak": 2})
	s = Vocab.record_answer(s, Vocab.result("correct", 1), cfg(), 3)
	expect_match(s, {"firstTry": 2, "firstTryStreak": 0}, "Mit Hilfe zählt nicht als auf Anhieb")
	var old := Vocab.record_answer({"seen": 3, "correct": 3, "wrong": 0, "streak": 3, "mastery": 0.5, "lastSeen": 1, "hintsUsed": 0}, {"outcome": "correct", "hintsUsed": 0, "firstTry": true}, cfg(), 4)
	expect_match(old, {"seen": 4, "firstTry": 1, "firstTryStreak": 1}, "Alter Spielstand ohne neue Felder")


func test_session_erkennt_auf_anhieb() -> void:
	var progress := {}
	var session := LearningSession.new(items(8), progress, cfg(), Rng.create(1), func() -> int: return 1000)
	var a := session.next_word()
	session.submit(a, Vocab.result("correct"))
	expect_match(progress[a.key], {"firstTry": 1, "firstTryStreak": 1})
	var b := session.next_word()
	session.submit(b, Vocab.result("wrongCorrected"))
	session.submit(b, Vocab.result("correct"))
	expect_match(progress[b.key], {"seen": 2, "firstTry": 0, "firstTryStreak": 0}, "Nach Fehler im selben Abenteuer nicht auf Anhieb")


func test_scheduler_gewichte_ueber_abenteuer() -> void:
	var all := items(5)
	var stats := {
		all[0].key: stats_of(6, 6, 0, 6, 0.8),  # oft dran, sicher
		all[1].key: stats_of(1, 1, 0, 1, 0.15),  # selten dran
		all[2].key: stats_of(6, 5, 1, 0, 0.5),  # zuletzt falsch
	}
	stats[all[0].key].firstTryStreak = 4
	var s := LearningScheduler.new(all, func(k: String) -> Variant: return stats.get(k), cfg(), Rng.create(1), func() -> int: return NOW)
	s.refresh_average_seen()
	var w := func(i: int) -> float: return s.weight(all[i], "normal")
	expect_gt(w.call(3), w.call(1), "Noch nie dran vor selten dran")
	expect_gt(w.call(1), w.call(0), "Selten dran vor oft dran")
	expect_gt(w.call(2), w.call(0), "Zuletzt falsch vor sicher")
	var plain: Dictionary = (stats[all[0].key] as Dictionary).duplicate()
	plain.firstTryStreak = 0
	stats[all[4].key] = plain
	expect_lt(w.call(0), w.call(4) * 0.5, "Mehrfach auf Anhieb richtig kommt deutlich seltener")


## Mehrere Abenteuer hintereinander mit einem großen Set: Die Lernstatistik bleibt erhalten, und neue
## Wörter kommen dran, bevor sichere Wörter wiederholt werden.
func test_mehrere_abenteuer_decken_das_set_ab() -> void:
	var covered := 0
	for seed in 5:
		var progress := {}
		var all := items(60)
		for run in 3:
			var session := LearningSession.new(all, progress, cfg(), Rng.create(100 * seed + run), func() -> int: return NOW + run * 1000)
			for i in 20:
				var item := session.next_word()
				session.submit(item, Vocab.result("correct"))
		covered += progress.size()
	expect_ge(covered / 5.0, 55.0, "Nach 3 × 20 Abfragen im Schnitt fast alle 60 Wörter mindestens einmal dran")
