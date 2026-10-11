extends TestCase
## Auswertung nach dem Abenteuer und Vollständigkeit der Sounds.

const SUMMARY := preload("res://scenes/summary.tscn")
const EXPLORATION := preload("res://scenes/exploration.tscn")


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func play_some(n: int) -> void:
	VocabPrompt.instant = true
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 99)
	for i in n:
		var item: Dictionary = (Ctx.run.learning as LearningSession).next_word("normal")
		Ctx.submit_answer(item, Vocab.result("wrongCorrected" if i % 3 == 2 else "correct", 0))


static func texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


func test_auswertung_zeigt_zahlen_und_woerter() -> void:
	play_some(12)
	Ctx.end_run()
	var s: Control = SUMMARY.instantiate()
	s.victory = true
	root().add_child(s)
	var t := texts(s)
	expect_true(t.has("🏆 Abenteuer bestanden!"), "Siegtitel")
	expect_true(t.has("12"), "Anzahl Abfragen")
	expect_true(t.any(func(x: String) -> bool: return x.contains("→") and x.contains("×)")), "Fehlerwörter mit Anzahl")
	expect_true(t.any(func(x: String) -> bool: return x.begins_with("⭐ +")), "XP-Zeile")
	root().remove_child(s)
	s.free()


func test_auswertung_ohne_fehler() -> void:
	VocabPrompt.instant = true
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 99)
	var item: Dictionary = (Ctx.run.learning as LearningSession).next_word("normal")
	Ctx.submit_answer(item, Vocab.result("correct", 0))
	var s: Control = SUMMARY.instantiate()
	root().add_child(s)
	var t := texts(s)
	expect_true(t.has("Abenteuer beendet"))
	expect_true(t.has("Kein einziger Fehler – großartig!"))
	root().remove_child(s)
	s.free()


func test_abenteuer_beenden_fuehrt_zur_auswertung() -> void:
	play_some(3)
	var e: Node3D = EXPLORATION.instantiate()
	root().add_child(e)
	e.finish_run(true)
	var s: Node = root().get_child(root().get_child_count() - 1)
	expect_eq(String(s.name), "Summary", "Auswertung geöffnet")
	expect_true(s.victory)
	expect_true(Ctx.run.completed, "Run abgeschlossen")
	expect_false(Ctx.can_resume(), "Kein Fortsetzen mehr")
	(Engine.get_main_loop() as SceneTree).current_scene = null
	root().remove_child(s)
	s.free()


func test_alle_sounds_vorhanden() -> void:
	var ids := {}
	var re := RegEx.create_from_string("Sound\\.play\\(\"([a-z_]+)\"")
	for dir in ["res://scenes", "res://ui", "res://world"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				for m in re.search_all(FileAccess.get_file_as_string(dir.path_join(f))):
					ids[m.get_string(1)] = true
	for c: Dictionary in GameData.HERO_CLASSES:
		ids[c.steps.sound] = true
		if c.steps.has("extra"):
			ids[c.steps.extra] = true
	expect_gt(ids.size(), 12, "Sound-IDs im Code gefunden")
	for id: String in ids:
		expect_true(ResourceLoader.exists("res://assets/audio/%s.ogg" % id), "Sounddatei fehlt: %s" % id)


func test_letzte_pruefung_zahlt_einmal_aus() -> void:
	play_some(12)
	Ctx.end_run()
	var shards_before := int(Ctx.profile.shards)
	var wrong: Array = (Ctx.run.learning as LearningSession).run.summary().wrongWords
	expect_gt(wrong.size(), 0)
	var s: Control = SUMMARY.instantiate()
	root().add_child(s)
	var btn: Button = s.find_child("FinalExam", true, false)
	expect_true(btn != null, "Letzte Prüfung wird angeboten")
	btn.pressed.emit()
	var answered := 0
	while answered < 20:
		var prompts := s.find_children("*", "VocabPrompt", true, false).filter(func(p: Node) -> bool: return not p.is_queued_for_deletion())
		if prompts.is_empty():
			break
		var p: VocabPrompt = prompts[0]
		p.input.text = p.entry.en
		p._submit()
		answered += 1
	expect_eq(answered, wrong.size(), "Jedes Fehlerwort einmal")
	expect_eq(int(Ctx.profile.shards), shards_before + Meta.final_exam_reward(wrong.size()))
	expect_true(Ctx.run.finalExamDone)
	expect_eq(Meta.apply_final_exam(Ctx.profile, Ctx.run, 5), 0, "Nur einmal")
	expect_true(s.find_child("FinalExam", true, false) == null, "Kein zweites Angebot")
	expect_true(texts(s).any(func(x: String) -> bool: return x.begins_with("📝 Letzte Prüfung:")), "Ergebnis wird gezeigt")
	root().remove_child(s)
	s.free()


func test_letzte_pruefung_belohnung() -> void:
	expect_eq(Meta.final_exam_reward(0), 0)
	expect_eq(Meta.final_exam_reward(1), 1)
	expect_eq(Meta.final_exam_reward(6), 6 / int(Meta.cfg().shards.finalExamPer))
