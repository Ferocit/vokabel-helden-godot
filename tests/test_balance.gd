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
		expect_ge(r.questions, min_q * 0.8, "seed %d" % seed)
		expect_le(r.questions, 65, "seed %d" % seed)
		expect_ge(r.words, 15, "seed %d" % seed)
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
		expect_ge(r.words, 40)
		expect_le(r.questions, 150)
		total += int(r.words)
	expect_ge(total / 15.0, 45)


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
