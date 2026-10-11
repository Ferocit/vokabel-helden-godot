extends TestCase
## Portierung von ImportValidator- und Save-Tests.

const VALID := """{
	"version": 1, "title": "Unit 3", "sourceLanguage": "de", "targetLanguage": "en",
	"vocabulary": [
		{ "id": "u3_001", "de": "Haus", "en": "house", "alternatives": [], "caseSensitive": true },
		{ "id": "u3_002", "de": "Straße", "en": "street", "alternatives": ["road"], "caseSensitive": true }
	]
}"""


func test_import_dokumentiertes_format() -> void:
	var r := ImportValidator.parse_import(VALID)
	expect_true(r.ok)
	expect_eq(r.title, "Unit 3")
	expect_eq(r.entries.size(), 2)
	expect_eq(r.issues.size(), 0)
	expect_false(ImportValidator.has_errors(ImportValidator.validate_entries(r.entries)))


func test_import_fehlermeldungen() -> void:
	var r := ImportValidator.parse_import("{ \"vocabulary\": [ }")
	expect_false(r.ok)
	expect_true((r.message as String).contains("kein gültiges JSON"))
	expect_false(ImportValidator.parse_import("{\"title\": \"x\"}").ok)


func test_import_leere_felder() -> void:
	var r := ImportValidator.parse_import(JSON.stringify({"vocabulary": [{"de": "Haus"}, {"de": "", "en": "x"}]}))
	expect_true(r.ok)
	var rows: Array = ImportValidator.validate_entries(r.entries).filter(func(i: Dictionary) -> bool: return i.severity == "error").map(func(i: Dictionary) -> int: return i.row)
	expect_eq(rows, [0, 1])


func test_import_alternativen_umwandeln() -> void:
	var r := ImportValidator.parse_import(JSON.stringify({"vocabulary": [{"de": "schnell", "en": "fast", "alternatives": "quick; rapid"}, {"de": "a", "en": "b", "alternatives": 5}]}))
	expect_eq(r.entries[0].alternatives, ["quick", "rapid"])
	expect_eq(r.entries[1].alternatives, [])
	expect_eq(r.issues.filter(func(i: Dictionary) -> bool: return i.severity == "warning").size(), 2)


func test_import_dubletten() -> void:
	var r := ImportValidator.parse_import(JSON.stringify({"vocabulary": [
		{"id": "a", "de": "Haus", "en": "house"},
		{"id": "a", "de": "Haus", "en": "House"},
		{"id": "b", "de": "Haus", "en": "home"},
	]}))
	expect_true(r.issues.any(func(i: Dictionary) -> bool: return (i.message as String).contains("Doppelte IDs")))
	var issues := ImportValidator.validate_entries(r.entries)
	var first_of := func(row: int) -> String:
		for i: Dictionary in issues:
			if i.row == row:
				return i.severity
		return ""
	expect_eq(first_of.call(1), "error")
	expect_eq(first_of.call(2), "warning")


func test_import_ids_neu_vergeben() -> void:
	var entries := ImportValidator.finalize_entries([
		{"id": "x", "de": "a", "en": "b", "alternatives": [" c ", "b", ""], "caseSensitive": true},
		{"id": "x", "de": "c", "en": "d", "alternatives": [], "caseSensitive": false},
		{"id": "", "de": "e", "en": "f", "alternatives": [], "caseSensitive": true},
	], "u")
	var ids := {}
	for e: Dictionary in entries:
		ids[e.id] = true
	expect_eq(ids.size(), 3)
	expect_eq(entries[0].id, "x")
	expect_eq(entries[0].alternatives, ["c"])
	expect_eq(ImportValidator.parse_alternatives("quick;  rapid ;"), ["quick", "rapid"])


func test_save_speichert_und_laedt() -> void:
	var save := SaveService.new(KeyValueStore.new())
	var profile := Player.new_profile(GameConfig.section("player"))
	profile.gold = 42
	save.save_player(profile)
	save.save_progress({"u/1": {"seen": 1, "correct": 1, "wrong": 0, "streak": 1, "mastery": 0.15, "lastSeen": 5, "hintsUsed": 0}})
	save.save_settings({"sound": false, "selectedUnits": []})
	expect_eq(save.load_player(), profile)
	expect_eq(save.load_progress()["u/1"].mastery, 0.15)
	expect_eq(save.load_settings().sound, false)


func test_save_kaputte_daten() -> void:
	var store := KeyValueStore.new()
	store.set_item("vq.player", "{kaputt")
	var save := SaveService.new(store)
	expect_eq(save.load_player(), null)
	expect_eq(save.load_progress(), {})


func test_repository() -> void:
	var save := SaveService.new(KeyValueStore.new())
	var repo := VocabularyRepository.new(save)
	expect_ge(repo.get_unit(VocabularyRepository.SAMPLE_UNIT_ID).vocabulary.size(), 25)
	repo.upsert({"id": "u1", "title": "Test", "createdAt": 1, "vocabulary": [Vocab.entry("a", "Haus", "house")]})
	expect_eq(VocabularyRepository.new(save).all().size(), 2)
	expect_eq(repo.learning_items(["u1"])[0].key, "u1/a")
	expect_false(repo.upsert({"id": VocabularyRepository.SAMPLE_UNIT_ID, "title": "", "createdAt": 0, "vocabulary": []}))
