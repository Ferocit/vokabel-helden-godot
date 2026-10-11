extends CanvasLayer
## Autoload „Reporter“: 🐞-Knopf unten rechts in jedem Bildschirm. Nimmt einen Screenshot auf, fragt nach
## Kategorie und Beschreibung und legt die Meldung ab:
## 1. Lokale Sicherung unter reports/<Zeitstempel>_<kategorie>/ (screenshot.png, report.json, index.md)
## 2. GitHub-Issue im Repository des Projekts über die angemeldete GitHub-CLI `gh`. Der Screenshot wird
##    dafür auf den Branch `report-screenshots` hochgeladen und im Issue eingebettet.
## Mit der Umgebungsvariable VQ_REPORT_GITHUB=0 wird nur lokal gespeichert.

const SCREENSHOT_BRANCH := "report-screenshots"
const CATEGORIES := [
	{"id": "fehler", "label": "🐞 Fehler / Bug", "title": "Fehler", "gh": ["meldung", "bug"]},
	{"id": "vokabel", "label": "📖 Vokabel falsch", "title": "Vokabel falsch", "gh": ["meldung", "vokabel"]},
	{"id": "idee", "label": "💡 Idee / Wunsch", "title": "Idee / Wunsch", "gh": ["meldung", "enhancement"]},
	{"id": "grafik", "label": "🎨 Grafik / Darstellung", "title": "Grafik / Darstellung", "gh": ["meldung", "grafik"]},
	{"id": "sonstiges", "label": "💬 Sonstiges", "title": "Sonstiges", "gh": ["meldung"]},
]

## Für Tests: GitHub abschalten und Zielordner umlenken.
var github_enabled := OS.get_environment("VQ_REPORT_GITHUB") != "0"
var reports_dir := ""

var _button: Button
var _dialog: Control
var _notify: PanelContainer
var _thread: Thread
var _was_paused := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	if reports_dir == "":
		reports_dir = default_reports_dir()
	_button = Button.new()
	_button.text = "🐞"
	_button.theme_type_variation = "SmallButton"
	_button.tooltip_text = "Etwas melden (Fehler, Idee, falsche Vokabel …)"
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_font_size_override("font_size", 18)
	_button.pressed.connect(open_report)
	UI.pin(self, _button, Control.PRESET_BOTTOM_RIGHT, Vector2(-12, -10))


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


## Im Projektordner (beim Start aus dem Quelltext), sonst im Benutzerordner.
static func default_reports_dir() -> String:
	if OS.has_feature("template"):
		return ProjectSettings.globalize_path("user://reports")
	return ProjectSettings.globalize_path("res://").path_join("reports")


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k.pressed and not k.echo and k.keycode == KEY_F8:
		get_viewport().set_input_as_handled()
		open_report()


# ---------- Kontext ----------

## Alles, was beim Nachvollziehen einer Meldung hilft.
func collect_context() -> Dictionary:
	var tree := get_tree()
	var scene := tree.current_scene
	var scenes: Array[String] = []
	if scene:
		scenes.append(scene.name)
	for c in tree.root.get_children():
		if c.name in ["Combat", "Summary"] and c != scene:
			scenes.append(c.name)
	var dialogs: Array = []
	for m in tree.root.find_children("*", "Control", true, false):
		if m is UI.Modal and m.is_visible_in_tree():
			for l in (m as UI.Modal).header.get_children():
				if l is Label:
					dialogs.append(l.text)
	var ctx := {
		"scene": ", ".join(scenes),
		"godot": Engine.get_version_info().string,
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"renderer": RenderingServer.get_current_rendering_method(),
		"window": "%d×%d" % [get_window().size.x, get_window().size.y],
		"openDialogs": dialogs,
		"battleMessage": null,
		"vocabPrompt": null,
		"profile": {"level": Ctx.profile.level, "xp": Ctx.profile.xp, "gold": Ctx.profile.gold, "potions": Ctx.profile.potions, "equipment": Ctx.profile.equipment, "bag": Ctx.profile.bag, "heroClass": Ctx.profile.heroClass},
		"selectedSets": (Ctx.settings.get("selectedUnits", []) as Array).map(func(id: String) -> String: return Ctx.repo.get_unit(id).get("title", id)),
		"run": null,
		"recentLog": recent_log(30),
	}
	var combat := tree.root.get_node_or_null("Combat")
	if combat and combat.get("_msg") is Label:
		ctx.battleMessage = (combat.get("_msg") as Label).text
	for p in tree.root.find_children("*", "PanelContainer", true, false):
		var vp := p as VocabPrompt
		if vp == null or vp.is_queued_for_deletion():
			continue
		var matching: Array = []
		for u: Dictionary in Ctx.repo.all():
			for v: Dictionary in u.vocabulary:
				if v.de == vp.entry.de:
					var m := v.duplicate()
					m.set = u.title
					matching.append(m)
		ctx.vocabPrompt = {"question": vp.entry.de, "typed": vp.input.text, "correction": vp.phase == "correction", "matchingEntries": matching}
	if Ctx.has_run():
		var run: Dictionary = Ctx.run
		var learning: LearningSession = run.learning
		ctx.run = {
			"seed": run.seed, "world": run.worldId,
			"sets": (run.unitIds as Array).map(func(id: String) -> String: return Ctx.repo.get_unit(id).get("title", id)),
			"hp": run.hp, "focus": run.focus, "runes": run.runes,
			"player": {"x": snappedf(run.player.x, 0.01), "y": snappedf(run.player.y, 0.01)},
			"defeated": (run.defeated as Dictionary).keys(), "opened": (run.opened as Dictionary).keys(),
			"questions": learning.run.questions,
			"owedRepeats": learning.scheduler.owed_repeats().map(func(i: Dictionary) -> String: return i.entry.de),
		}
	return ctx


## Letzte Zeilen der Godot-Logdatei (Fehler und Warnungen der laufenden Sitzung).
static func recent_log(lines: int) -> Array:
	var path := "user://logs/godot.log"
	if not FileAccess.file_exists(path):
		return []
	var all := FileAccess.get_file_as_string(path).split("\n", false)
	return Array(all.slice(maxi(0, all.size() - lines)))


static func context_summary(ctx: Dictionary) -> String:
	var lines: Array[String] = []
	var vocab: Variant = ctx.get("vocabPrompt")
	if vocab is Dictionary:
		var expected := (vocab.matchingEntries as Array).map(func(e: Dictionary) -> String:
			var alts: Array = e.get("alternatives", [])
			return "%s%s – Set „%s“" % [e.en, " (auch: %s)" % ", ".join(PackedStringArray(alts)) if not alts.is_empty() else "", e.get("set", "")])
		lines.append("- **Vokabel:** %s → %s" % [vocab.question, "; ".join(PackedStringArray(expected)) if not expected.is_empty() else "unbekannt"])
		if str(vocab.typed) != "":
			lines.append("- **Eingabe:** `%s`%s" % [vocab.typed, " (in der Fehlerkorrektur)" if vocab.correction else ""])
	if ctx.get("battleMessage") != null:
		lines.append("- **Kampfmeldung:** %s" % ctx.battleMessage)
	var run: Variant = ctx.get("run")
	if run is Dictionary:
		lines.append("- **Abenteuer:** Seed %s, Sets: %s, HP %s, Runen %s, %s Abfragen" % [run.seed, ", ".join(PackedStringArray(run.sets)), run.hp, run.runes, run.questions])
	if ctx.get("profile") is Dictionary:
		lines.append("- **Held:** Level %s" % ctx.profile.level)
	lines.append("- **System:** Godot %s · %s · %s · %s" % [ctx.get("godot", ""), ctx.get("os", ""), ctx.get("renderer", ""), ctx.get("window", "")])
	return "\n".join(lines)


static func category_info(id: String) -> Dictionary:
	for c: Dictionary in CATEGORIES:
		if c.id == id:
			return c
	return CATEGORIES[CATEGORIES.size() - 1]


static func issue_title(category: String, description: String) -> String:
	var first := description.split("\n")[0].strip_edges()
	if first.length() > 70:
		first = first.substr(0, 67) + "…"
	return "[%s] %s" % [category_info(category).title, first]


static func issue_body(report: Dictionary, image_markdown: String, folder: String) -> String:
	return "\n".join(PackedStringArray([
		"**Kategorie:** %s · **Szene:** %s · **Gemeldet:** %s" % [category_info(report.category).title, report.context.get("scene", "–"), report.createdLocal],
		"",
		"### Beschreibung",
		report.description,
		"",
		"### Screenshot",
		image_markdown,
		"",
		"### Kontext",
		context_summary(report.context),
		"",
		"<details><summary>Vollständiger Kontext (JSON)</summary>",
		"",
		"```json",
		JSON.stringify(report.context, "  "),
		"```",
		"</details>",
		"",
		"_Automatisch aus dem Spiel gemeldet (lokale Kopie: `reports/%s/`)._" % folder,
	]))


# ---------- Dialog ----------

func open_report() -> void:
	if is_instance_valid(_dialog):
		return
	var context := collect_context()
	# Screenshot vor dem Öffnen des Dialogs; der Knopf selbst wird dafür kurz ausgeblendet.
	_button.visible = false
	await RenderingServer.frame_post_draw
	var shot: Image = get_viewport().get_texture().get_image() if is_inside_tree() else null
	_button.visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_build_dialog(context, shot)


func _build_dialog(context: Dictionary, shot: Image) -> void:
	_dialog = Control.new()
	_dialog.name = "ReportDialog"
	add_child(_dialog)
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bd := Panel.new()
	bd.theme_type_variation = "Backdrop"
	_dialog.add_child(bd)
	bd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_dialog.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var win := UI.window(780)
	center.add_child(win)
	var body: VBoxContainer = win.get_node("Body")
	body.add_child(UI.label("Etwas melden", "H2"))

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(300, 169)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if shot:
		preview.texture = ImageTexture.create_from_image(shot)
	var include := CheckBox.new()
	include.text = "Screenshot mitschicken"
	include.button_pressed = shot != null
	include.disabled = shot == null
	include.toggled.connect(func(on: bool) -> void: preview.modulate.a = 1.0 if on else 0.3)
	var info := UI.para("Spielstand und aktuelle Vokabel werden immer mitgeschickt. Daraus entsteht automatisch ein GitHub-Issue.", "Dim", 15)
	var side := UI.vbox([include, info])
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(UI.hbox([preview, side], 16))

	var category := [CATEGORIES[0].id]
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	var group := ButtonGroup.new()
	for i in CATEGORIES.size():
		var c: Dictionary = CATEGORIES[i]
		var b := Button.new()
		b.text = c.label
		b.theme_type_variation = "SmallButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.pressed.connect(func() -> void: category[0] = c.id)
		chips.add_child(b)
	body.add_child(chips)

	var text := TextEdit.new()
	text.placeholder_text = "Was ist passiert oder was wünschst du dir? Je genauer, desto besser."
	text.custom_minimum_size.y = 130
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.add_child(text)
	var status := UI.label("", "Bad", 15)
	body.add_child(status)
	var cancel := UI.button("Abbrechen", close_dialog)
	var send := UI.button("Meldung senden", func() -> void:
		var description := text.text.strip_edges()
		if description == "":
			status.text = "Bitte beschreibe kurz, worum es geht."
			text.grab_focus()
			return
		close_dialog()
		submit({"category": category[0], "description": description, "context": context}, shot if include.button_pressed else null))
	body.add_child(UI.hbox([UI.spacer(), cancel, send]))
	text.grab_focus()


func close_dialog() -> void:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null
	get_tree().paused = _was_paused


# ---------- Speichern & Senden ----------

## Speichert lokal und erstellt (im Hintergrund) das GitHub-Issue. Liefert den Ordnernamen.
func submit(base: Dictionary, shot: Image) -> String:
	var saved := save_local(base, shot)
	if not github_enabled:
		notify("Danke! Lokal gespeichert (reports/%s)." % saved.folder)
		return saved.folder
	notify("Meldung wird im Hintergrund gesendet …")
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread.start(_github_worker.bind(saved))
	return saved.folder


func save_local(base: Dictionary, shot: Image) -> Dictionary:
	var now := Time.get_datetime_dict_from_system()
	var stamp := "%04d-%02d-%02d_%02d-%02d-%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second]
	var category := String(base.get("category", "sonstiges")).to_lower()
	var folder := "%s_%s" % [stamp, category]
	var i := 2
	while DirAccess.dir_exists_absolute(reports_dir.path_join(folder)):
		folder = "%s_%s_%d" % [stamp, category, i]
		i += 1
	var dir := reports_dir.path_join(folder)
	DirAccess.make_dir_recursive_absolute(dir)
	var png_path := ""
	if shot:
		png_path = dir.path_join("screenshot.png")
		shot.save_png(png_path)
	var report := {
		"createdAt": Time.get_datetime_string_from_system(true),
		"createdLocal": "%02d.%02d.%04d %02d:%02d" % [now.day, now.month, now.year, now.hour, now.minute],
		"category": category,
		"description": String(base.get("description", "")).strip_edges(),
		"screenshot": "screenshot.png" if shot else null,
		"context": base.get("context", {}),
		"issue": null,
		"githubError": null,
	}
	_write_json(dir.path_join("report.json"), report)
	var index := reports_dir.path_join("index.md")
	var f: FileAccess
	if FileAccess.file_exists(index):
		f = FileAccess.open(index, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(index, FileAccess.WRITE)
		f.store_string("# Meldungen aus dem Spiel\n\n| Zeit | Kategorie | Szene | Beschreibung | Ordner |\n| --- | --- | --- | --- | --- |\n")
	var one_line: String = String(report.description).replace("\n", " ").replace("|", "/").substr(0, 140)
	f.store_string("| %s | %s | %s | %s | [%s](%s/report.json) |\n" % [report.createdLocal, category, report.context.get("scene", ""), one_line, folder, folder])
	f.close()
	return {"folder": folder, "dir": dir, "report": report, "png": png_path}


static func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()


## Läuft im Hintergrund-Thread: Screenshot hochladen, Issue anlegen, Ergebnis in report.json vermerken.
func _github_worker(saved: Dictionary) -> void:
	var report: Dictionary = saved.report
	var result := {"issue": null, "error": null}
	var repo := git_remote_repo()
	if repo == "":
		result.error = "Kein GitHub-Remote (origin) gefunden."
	else:
		var image_md := "_Kein Screenshot._"
		if saved.png != "":
			var up := _gh_upload_screenshot(repo, saved.png, saved.folder)
			image_md = up.markdown
		var created := _gh(["api", "-X", "POST", "repos/%s/issues" % repo], {
			"title": issue_title(report.category, report.description),
			"body": issue_body(report, image_md, saved.folder),
			"labels": category_info(report.category).gh,
		})
		if created.ok:
			var data: Variant = JSON.parse_string(created.out)
			if data is Dictionary:
				result.issue = {"number": int(data.number), "url": data.html_url}
		else:
			result.error = created.out
	report.issue = result.issue
	report.githubError = result.error
	_write_json(String(saved.dir).path_join("report.json"), report)
	_on_github_done.call_deferred(result, saved.folder)


func _on_github_done(result: Dictionary, folder: String) -> void:
	if result.issue != null:
		notify("Danke! Issue #%d wurde auf GitHub erstellt." % int(result.issue.number), result.issue.url)
	else:
		notify("Danke! Lokal gespeichert (reports/%s). GitHub-Issue nicht möglich – Details in report.json." % folder)


func _gh_upload_screenshot(repo: String, png_path: String, folder: String) -> Dictionary:
	# Branch für Screenshots bei Bedarf anlegen.
	if not _gh(["api", "repos/%s/git/ref/heads/%s" % [repo, SCREENSHOT_BRANCH]]).ok:
		var info: Variant = JSON.parse_string(_gh(["api", "repos/%s" % repo]).out)
		var default_branch: String = info.default_branch if info is Dictionary else "main"
		var base: Variant = JSON.parse_string(_gh(["api", "repos/%s/git/ref/heads/%s" % [repo, default_branch]]).out)
		if base is Dictionary:
			_gh(["api", "-X", "POST", "repos/%s/git/refs" % repo], {"ref": "refs/heads/" + SCREENSHOT_BRANCH, "sha": base.object.sha})
	var path := "screenshots/%s.png" % folder
	var content := Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(png_path))
	var put := _gh(["api", "-X", "PUT", "repos/%s/contents/%s" % [repo, path]], {"message": "Screenshot für Meldung %s" % folder, "content": content, "branch": SCREENSHOT_BRANCH})
	if put.ok:
		return {"markdown": "![Screenshot](https://github.com/%s/blob/%s/%s?raw=true)" % [repo, SCREENSHOT_BRANCH, path]}
	return {"markdown": "_Screenshot konnte nicht hochgeladen werden: %s (lokal unter `reports/%s/`)._" % [put.out.strip_edges(), folder]}


## Ruft die GitHub-CLI auf. Große Eingaben (Base64-Screenshot) gehen über eine Datei.
func _gh(args: Array, input: Variant = null) -> Dictionary:
	var input_file := ""
	if input != null:
		input_file = OS.get_temp_dir().path_join("vq-gh-%d-%d.json" % [Time.get_ticks_usec(), randi()])
		_write_json(input_file, input)
		args = args + ["--input", input_file]
	var out: Array = []
	var code := OS.execute("gh", PackedStringArray(args), out, true)
	if input_file != "":
		DirAccess.remove_absolute(input_file)
	return {"ok": code == 0, "out": "".join(PackedStringArray(out))}


## „owner/repo“ aus dem origin-Remote des Projektordners.
static func git_remote_repo() -> String:
	var out: Array = []
	var code := OS.execute("git", PackedStringArray(["-C", ProjectSettings.globalize_path("res://"), "remote", "get-url", "origin"]), out, true)
	if code != 0 or out.is_empty():
		return ""
	return parse_repo(String(out[0]))


static func parse_repo(url: String) -> String:
	var re := RegEx.create_from_string("github\\.com[:/]([^/]+/[^/.\\s]+?)(?:\\.git)?\\s*$")
	var m := re.search(url.strip_edges())
	return m.get_string(1) if m else ""


func notify(text: String, link: String = "") -> void:
	if is_instance_valid(_notify):
		_notify.queue_free()
	_notify = PanelContainer.new()
	var row := UI.hbox([UI.label(text, "", 18)])
	if link != "":
		row.add_child(UI.button("Öffnen", func() -> void: OS.shell_open(link), "SmallButton"))
	_notify.add_child(row)
	UI.pin(self, _notify, Control.PRESET_CENTER_BOTTOM, Vector2(0, -60))
	var n := _notify
	get_tree().create_timer(7.0, true).timeout.connect(func() -> void:
		if is_instance_valid(n):
			n.queue_free())
