extends TestCase
## Melden: Kontext, lokale Ablage, Issue-Text (GitHub abgeschaltet).


static func tmp_dir() -> String:
	var d := OS.get_temp_dir().path_join("vq-test-reports-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(d)
	return d


func test_repo_aus_remote_url() -> void:
	expect_eq(Reporter.parse_repo("https://github.com/Ferocit/vokabel-helden-godot.git\n"), "Ferocit/vokabel-helden-godot")
	expect_eq(Reporter.parse_repo("git@github.com:Ferocit/vokabel-helden-godot"), "Ferocit/vokabel-helden-godot")
	expect_eq(Reporter.parse_repo("https://example.com/x/y"), "")


func test_issue_titel_und_text() -> void:
	expect_eq(Reporter.issue_title("vokabel", "Haus ist falsch\nmehr Text"), "[Vokabel falsch] Haus ist falsch")
	var long := "x".repeat(90)
	expect_eq(Reporter.issue_title("unbekannt", long).length(), "[Sonstiges] ".length() + 68)
	var ctx := {
		"scene": "Combat", "godot": "4.7", "os": "Linux", "renderer": "forward_plus", "window": "1280×720",
		"vocabPrompt": {"question": "Haus", "typed": "hause", "correction": true, "matchingEntries": [{"en": "house", "alternatives": ["home"], "set": "Unit 1"}]},
		"battleMessage": "Treffer!", "profile": {"level": 3},
		"run": {"seed": 7, "sets": ["Unit 1"], "hp": 10, "runes": 2, "questions": 5},
	}
	var summary := Reporter.context_summary(ctx)
	expect_true(summary.contains("- **Vokabel:** Haus → house (auch: home) – Set „Unit 1“"), summary)
	expect_true(summary.contains("`hause` (in der Fehlerkorrektur)"))
	expect_true(summary.contains("Seed 7"))
	var body := Reporter.issue_body({"category": "vokabel", "description": "Text", "createdLocal": "01.01.2026 10:00", "context": ctx}, "_Kein Screenshot._", "ordner")
	expect_true(body.contains("### Beschreibung\nText"))
	expect_true(body.contains("**Szene:** Combat"))


func test_kontext_mit_abenteuer() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 5)
	var ctx := Reporter.collect_context()
	expect_true(ctx.run is Dictionary, "Abenteuer im Kontext")
	expect_eq(int(ctx.run.seed), 5)
	expect_eq(ctx.selectedSets, [], "Keine Auswahl gespeichert")
	expect_true(ctx.has("recentLog"))


func test_lokal_speichern() -> void:
	var r: Node = Reporter
	r.reports_dir = tmp_dir()
	r.github_enabled = false
	var img := Image.create(32, 18, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	var folder: String = r.submit({"category": "idee", "description": "Mehr Drachen | bitte", "context": {"scene": "Title"}}, img)
	var dir: String = r.reports_dir.path_join(folder)
	expect_true(folder.ends_with("_idee"), folder)
	expect_true(FileAccess.file_exists(dir.path_join("screenshot.png")), "Screenshot gespeichert")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("report.json")))
	expect_eq(report.description, "Mehr Drachen | bitte")
	expect_eq(report.screenshot, "screenshot.png")
	var index := FileAccess.get_file_as_string(r.reports_dir.path_join("index.md"))
	expect_true(index.contains("Mehr Drachen / bitte"), "Index-Zeile ohne Tabellen-Trenner")
	var second: String = r.submit({"category": "idee", "description": "Noch was", "context": {}}, null)
	expect_ne(second, folder, "Eigener Ordner pro Meldung")
	expect_false(FileAccess.file_exists(r.reports_dir.path_join(second).path_join("screenshot.png")), "Ohne Screenshot")
