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
