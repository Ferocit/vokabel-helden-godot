extends TestCase
## Balancing-Eckwerte, gemessen mit dem Simulator (logic/sim/balance_sim.gd).
## Tabellen zum Nachschauen: `start.bat sim` bzw. `godot --headless --path . -s res://tools/sim.gd -- …`


static func simulate_run(seed: int, accuracy: float, hero_class: String = "warrior", vocabulary: Array = [], skills: Variant = {}, heat: int = 0) -> Dictionary:
	return BalanceSim.run({"seed": seed, "accuracy": accuracy, "heroClass": hero_class, "vocabulary": vocabulary, "skills": skills, "heat": heat})


static func batch(opts: Dictionary, n: int) -> Dictionary:
	return BalanceSim.batch(opts, n)


func test_balance_abfragen_pro_run() -> void:
	var min_q := int(GameConfig.section("run").minVocabularyInteractions)
	var total := 0
	for seed in range(1, 31):
		var r := simulate_run(seed * 31, 0.8)
		expect_ge(r.questions, min_q * 0.7, "seed %d" % seed)
		expect_le(r.questions, 65, "seed %d" % seed)
		expect_ge(r.words, 12, "seed %d" % seed)
		total += int(r.questions)
	expect_ge(total / 30.0, min_q, "im Schnitt mindestens minVocabularyInteractions")


func test_balance_boss_schaffbar() -> void:
	var s := batch({"seed": 1000, "accuracy": 0.8}, 40)
	expect_gt(s.bossFirstTry, 0.5)
	expect_gt(s.winRate, 0.95)


func test_balance_60_prozent() -> void:
	expect_gt(batch({"seed": 5000, "accuracy": 0.6}, 30).winRate, 0.9)


func test_balance_klassen() -> void:
	for cls in ["warrior", "rogue", "mage"]:
		expect_gt(batch({"seed": 9000, "accuracy": 0.8, "heroClass": cls}, 40).winRate, 0.9, cls)


func test_balance_grosse_sets_issue16() -> void:
	var big: Array = []
	for i in 95:
		big.append(Vocab.entry("b%d" % i, "de%d" % i, "en%d" % i))
	var total := 0
	for i in 15:
		var r := simulate_run(7000 + i * 11, 0.8, "warrior", big)
		expect_ge(r.words, 33)
		expect_le(r.questions, 150)
		total += int(r.words)
	expect_ge(total / 15.0, 38)


# ---------- Lerner-Modell ----------

func test_balance_anfaenger_schafft_stufe_0() -> void:
	var s := batch({"seed": 3000, "learner": "beginner"}, 20)
	expect_gt(s.winRate, 0.85, "Auch Anfänger gewinnen auf Stufe 0 meistens")
	expect_gt(s.knowledgeGain, 0.1, "Anfänger lernen im Lauf messbar dazu")


func test_balance_abenteuer_dauer() -> void:
	var s := batch({"seed": 3100, "learner": "average"}, 20)
	expect_ge(s.minutes, 6.0)
	expect_le(s.minutes, 25.0)


# ---------- Rogue-lite ----------

func test_balance_talente_und_segnungen_werden_genutzt() -> void:
	var s := batch({"seed": 3200, "accuracy": 0.8}, 20)
	expect_ge(s.talents, 1.5)
	expect_ge(s.blessings, 1.0)


func test_balance_splitter_pro_sieg() -> void:
	var avg: float = batch({"seed": 2000, "accuracy": 0.8}, 30).shards
	expect_ge(avg, 30.0, "Schurke (25) nach dem ersten Sieg freischaltbar")
	expect_le(avg, 60.0, "Skillbaum (198) nicht nach 2–3 Läufen fertig")


func test_balance_leben_reichen_auf_stufe_0() -> void:
	expect_le(batch({"seed": 9000, "accuracy": 0.6}, 30).lost, 1, "Auch mit 60 % Treffern endet der Lauf praktisch nie vorzeitig")


func test_balance_tempelstufen_brauchen_skills() -> void:
	# Gemessen mit dem durchschnittlichen Lerner (Wissen pro Wort, lernt im Lauf dazu).
	var o := {"seed": 9000, "learner": "average", "heat": 3}
	var without: int = batch(o, 40).lost
	o.skills = "full"
	var with_tree: int = batch(o, 40).lost
	expect_ge(without, 10, "Stufe 3 ohne Skills ist schwer (gemessen ≈ 45 % verloren)")
	expect_le(with_tree, 3, "Stufe 3 mit vollem Baum ist machbar")
	o.heat = 5
	expect_le(batch(o, 40).lost, 14, "Höchste Stufe bleibt mit vollem Baum schaffbar (gemessen ≈ 20 % verloren)")


func test_balance_kampagne_fortschritt() -> void:
	var runs := BalanceSim.campaign({"seed": 4000, "learner": "average"}, 6)
	expect_eq(runs.size(), 6)
	expect_gt(float(runs[5].invested), 60.0, "Nach 6 Läufen ist ein Teil des Baums gekauft")


func test_balance_verteidigen_umgeht_keine_schweren_woerter() -> void:
	# Issue #19: Wörter beim Verteidigen sind im Schnitt nicht leichter als bei anderen Befehlen.
	var s := batch({"seed": 6100, "learner": "beginner"}, 30)
	expect_gt(s.defendShare, 0.0, "Der Bot verteidigt überhaupt")
	expect_lt(absf(float(s.defendKnowledge) - float(s.otherKnowledge)), 0.08)


func test_balance_abfragen_pro_minute() -> void:
	# Issue #16: Schreine und Runenplatten bringen mehr Abfragen, ohne das Abenteuer zu verlängern.
	var s := batch({"seed": 6200, "learner": "average"}, 20)
	expect_ge(s.perMinute, 4.0)
	expect_ge(s.questions, 42.0)
	expect_le(s.minutes, 16.0)  # Ziel: etwa 15 Minuten (run.targetMinutes)


func test_balance_ebenen() -> void:
	# Issue #27: Drei Ebenen sind für Durchschnitts-Lerner meist, aber nicht immer schaffbar.
	var s := batch({"seed": 6300, "learner": "average", "floors": 3}, 20)
	expect_ge(s.floorsCleared, 2.2)
	expect_gt(s.defeats, 0.0, "tiefe Ebenen sind gefährlich")
	expect_gt(s.shards, 100.0)


func test_balance_nemesis_ruestung_brechbar() -> void:
	# Issue #24: Die Rüstungswörter werden im Bosskampf abgefragt und meist gebrochen; der Boss bleibt schaffbar.
	var s := batch({"seed": 6400, "learner": "beginner"}, 20)
	expect_gt(s.nemesisArmor, 0.0)
	expect_ge(s.nemesisBroken, s.nemesisArmor * 0.6)
	expect_gt(s.winRate, 0.9)


func test_balance_kampagne_schaltet_inhalte_frei() -> void:
	# Issue #23: Nach dem Skillbaum fließen Splitter in neue Inhalte.
	var runs := BalanceSim.campaign({"seed": 4100, "learner": "average"}, 8)
	expect_gt(int(runs[7].unlocks), 3)
	expect_lt(int(runs[2].unlocks), Unlocks.ALL.size(), "nicht alles nach drei Läufen")


func test_balance_gruppen() -> void:
	# Issue #30: Gruppen kommen vor, Stufe 0 bleibt sicher schaffbar.
	var s := batch({"seed": 6500, "learner": "average"}, 20)
	expect_gt(s.groups, 0.5, "im Schnitt mindestens eine Gruppe pro Lauf")
	expect_gt(s.winRate, 0.95)
