class_name ImportDialog
extends RefCounted
## Import-Workflow: JSON einfügen oder laden → prüfen → editierbare Tabelle → speichern.
## Mit `existing` wird ein vorhandenes Set bearbeitet und erweitert (Lernfortschritt bleibt erhalten).

const AI_PROMPT := """Lies die Vokabeln auf dem Foto aus. Gib ausschließlich JSON in genau diesem Format zurück:
{
  "version": 1,
  "title": "Unit 3",
  "sourceLanguage": "de",
  "targetLanguage": "en",
  "vocabulary": [
    { "id": "u3_001", "de": "Haus", "en": "house", "alternatives": [], "caseSensitive": true }
  ]
}
Regeln: "de" = deutsches Wort, "en" = englische Hauptlösung, weitere gültige Übersetzungen in "alternatives".
Übernimm die Schreibweise exakt wie auf der Seite. Großbuchstaben nur dort, wo sie im Englischen immer stehen
(z. B. "I", "Monday", "London") – sonst alles klein."""

## Das gerade offene Dialogfenster (für Drag & Drop aus der Titelszene), als WeakRef,
## damit die statische Variable den Dialog nicht über das Spielende hinaus festhält.
static var _current: WeakRef


static func current() -> ImportDialog:
	return _current.get_ref() if _current != null else null

var modal: UI.Modal
var existing: Dictionary
var on_done: Callable
var _saved: Dictionary = {}

# Vorschau-Zustand
var entries: Array = []
var parse_issues: Array = []
var row_parse_issues: Array = []
var dirty := false
var _in_preview := false
var _title_input: LineEdit
var _search: LineEdit
var _counter: Label
var _issue_box: VBoxContainer
var _rows: VBoxContainer
var _save_btn: Button
var _append_box: VBoxContainer
var _append_text: TextEdit
var _append_error: Label


## opts: { existing: VocabUnit, initial_text: String, on_done: Callable(saved: Dictionary) }
static func open(parent: Node, opts: Dictionary) -> ImportDialog:
	var d := ImportDialog.new()
	d.existing = opts.get("existing", {})
	d.on_done = opts.get("on_done", Callable())
	d.modal = UI.modal(parent, "", 1140, false)
	d.modal.set_meta("dialog", d)
	d.modal.closed.connect(d._on_closed)
	_current = weakref(d)
	if not d.existing.is_empty():
		var copy: Array = []
		for v: Dictionary in d.existing.vocabulary:
			copy.append(v.duplicate(true))
		d.show_preview(d.existing.title, copy, [])
	elif opts.get("initial_text", "") != "":
		var res := ImportValidator.parse_import(opts.initial_text)
		if res.ok:
			d.show_preview(res.title, res.entries, res.issues)
		else:
			d.show_input(opts.initial_text, res.message)
	else:
		d.show_input()
	return d


func _on_closed() -> void:
	if current() == self:
		_current = null
	if on_done.is_valid():
		on_done.call(_saved)


func close(saved: Dictionary = {}) -> void:
	_saved = saved
	modal.close()


## Datei wurde ins Fenster gezogen: in der Tabelle anhängen, sonst in das Eingabefeld übernehmen.
func handle_drop(text: String) -> void:
	if _in_preview:
		append_entries(text)
	else:
		var res := ImportValidator.parse_import(text)
		if res.ok:
			show_preview(res.title, res.entries, res.issues)
		else:
			show_input(text, res.message)


func _set_header(title: String) -> void:
	UI.clear(modal.header)
	modal.header.add_child(UI.label(title, "H2"))


# ---------- Schritt 1: JSON einfügen ----------

func show_input(prefill: String = "", initial_error: String = "") -> void:
	_in_preview = false
	_set_header("Vokabel-Set importieren")
	var body := modal.body
	UI.clear(body)
	var copy := UI.button("KI-Anweisung kopieren", Callable(), "SmallButton")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(AI_PROMPT)
		copy.text = "Kopiert ✓")
	body.add_child(UI.hbox([
		UI.para("1. Vokabelseite fotografieren · 2. Foto mit der KI-Anweisung an eine KI geben · 3. Das erzeugte JSON hier einfügen, als Datei laden oder ins Fenster ziehen.", "Dim", 16),
		copy,
	]))
	var text := TextEdit.new()
	text.placeholder_text = "JSON hier einfügen …"
	text.text = prefill
	text.custom_minimum_size = Vector2(0, 380)
	text.add_theme_font_size_override("font_size", 15)
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.add_child(text)
	var error := UI.para(initial_error, "Bad", 16)
	error.custom_minimum_size.y = 24
	body.add_child(error)
	var load_btn := UI.button("📂 Datei laden …", func() -> void:
		_pick_file(func(content: String) -> void: text.text = content), "SmallButton")
	var cancel := UI.button("Abbrechen", func() -> void: close())
	var check := UI.button("Prüfen & Vorschau", func() -> void:
		var res := ImportValidator.parse_import(text.text)
		if not res.ok:
			error.text = res.message
			return
		show_preview(res.title, res.entries, res.issues))
	body.add_child(UI.hbox([load_btn, UI.spacer(), cancel, check]))
	UI.focus_later(text)


func _pick_file(on_text: Callable) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json ; JSON-Dateien", "*.txt ; Text"])
	fd.use_native_dialog = true
	fd.title = "Vokabel-Datei öffnen"
	fd.file_selected.connect(func(path: String) -> void:
		on_text.call(FileAccess.get_file_as_string(path))
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	modal.add_child(fd)
	fd.popup_centered(Vector2i(900, 560))


# ---------- Schritt 2: Vorschau / Editor ----------

func show_preview(initial_title: String, list: Array, issues: Array) -> void:
	_in_preview = true
	entries = list
	parse_issues = issues
	row_parse_issues = issues.filter(func(i: Dictionary) -> bool: return int(i.row) >= 0)
	dirty = false
	_set_header("Vokabel-Set bearbeiten" if not existing.is_empty() else "Vorschau prüfen")
	var body := modal.body
	UI.clear(body)

	_title_input = LineEdit.new()
	_title_input.text = initial_title
	_title_input.custom_minimum_size.x = 360
	_title_input.add_theme_font_size_override("font_size", 20)
	_title_input.text_changed.connect(func(_t: String) -> void:
		dirty = true
		refresh())
	_search = LineEdit.new()
	_search.placeholder_text = "🔍 Suchen …"
	_search.custom_minimum_size.x = 200
	_search.text_changed.connect(func(_t: String) -> void: _apply_filter())
	_counter = UI.label("", "Dim", 16)
	body.add_child(UI.hbox([UI.label("Titel:"), _title_input, UI.spacer(), _search, _counter]))
	body.add_child(UI.para(
		"Ändere Einträge direkt in der Tabelle, füge Zeilen hinzu oder hänge weitere Vokabeln per JSON an. Der Lernfortschritt bestehender Wörter bleibt erhalten." if not existing.is_empty()
		else "Bitte vergleiche jede Zeile mit der Vokabelseite und korrigiere Erkennungsfehler direkt in der Tabelle.", "Dim", 15))
	_issue_box = UI.vbox([], 2)
	body.add_child(_issue_box)

	# Weitere Vokabeln per JSON anhängen (z. B. die nächste Buchseite).
	_append_text = TextEdit.new()
	_append_text.placeholder_text = "JSON mit weiteren Vokabeln hier einfügen …"
	_append_text.custom_minimum_size.y = 110
	_append_text.add_theme_font_size_override("font_size", 14)
	_append_error = UI.para("", "Bad", 15)
	var append_file := UI.button("📂 Datei anhängen …", func() -> void: _pick_file(append_entries), "SmallButton")
	var append_go := UI.button("Anhängen", func() -> void: append_entries(_append_text.text), "SmallButton")
	_append_box = UI.vbox([_append_text, _append_error, UI.hbox([append_file, UI.spacer(), append_go])])
	_append_box.visible = false
	body.add_child(_append_box)

	var head := UI.hbox([
		_col(UI.label("#", "Accent", 14), 34),
		_col(UI.label("Deutsch", "Accent", 14), 260),
		_col(UI.label("Englisch", "Accent", 14), 230),
		_col(UI.label("Alternativen (mit ; trennen)", "Accent", 14), 230),
		_col(UI.label("Aa", "Accent", 14), 34),
		_col(UI.label("Hinweis", "Accent", 14), 190),
	])
	body.add_child(head)
	_rows = UI.vbox([], 3)
	body.add_child(UI.scroll(_rows, 330))

	var add := UI.button("+ Zeile", func() -> void:
		_search.text = ""
		entries.append({"id": "", "de": "", "en": "", "alternatives": [], "caseSensitive": true})
		dirty = true
		render_rows()
		var last := _rows.get_child(_rows.get_child_count() - 1)
		UI.focus_later(last.find_children("*", "LineEdit", true, false)[0] as LineEdit), "SmallButton")
	var toggle := UI.button("📥 Vokabeln aus JSON anhängen", func() -> void:
		_append_box.visible = not _append_box.visible
		if _append_box.visible:
			_append_text.grab_focus(), "SmallButton")
	var back := UI.button("Abbrechen" if not existing.is_empty() else "Zurück", func() -> void:
		var leave := func() -> void:
			if existing.is_empty():
				show_input()
			else:
				close()
		if dirty:
			UI.confirm(modal, "Ungespeicherte Änderungen verwerfen?", leave, "Verwerfen")
		else:
			leave.call())
	_save_btn = UI.button("Änderungen speichern" if not existing.is_empty() else "Set speichern", _save)
	body.add_child(UI.hbox([add, toggle, UI.spacer(), back, _save_btn]))
	render_rows()


static func _col(c: Control, width: int) -> Control:
	c.custom_minimum_size.x = width
	return c


func render_rows() -> void:
	UI.clear(_rows)
	for row in entries.size():
		_rows.add_child(_make_row(row))
	refresh()
	_apply_filter()


func _make_row(row: int) -> PanelContainer:
	var entry: Dictionary = entries[row]
	var panel := PanelContainer.new()
	panel.theme_type_variation = "RowPlain"
	var field := func(key: String, width: int, placeholder: String = "") -> LineEdit:
		var input := LineEdit.new()
		input.text = entry[key]
		input.placeholder_text = placeholder
		input.custom_minimum_size.x = width
		input.text_changed.connect(func(t: String) -> void:
			entry[key] = t
			dirty = true
			refresh())
		return input
	var alt := LineEdit.new()
	alt.text = ImportValidator.format_alternatives(entry.alternatives)
	alt.placeholder_text = "mit ; trennen"
	alt.custom_minimum_size.x = 230
	alt.text_changed.connect(func(t: String) -> void:
		entry.alternatives = ImportValidator.parse_alternatives(t)
		dirty = true
		refresh())
	var cs := CheckBox.new()
	cs.button_pressed = entry.caseSensitive
	cs.tooltip_text = "Großbuchstaben der Lösung prüfen (z. B. „Monday“). Kleingeschriebene Lösungen sind immer egal."
	cs.custom_minimum_size.x = 34
	cs.toggled.connect(func(on: bool) -> void:
		entry.caseSensitive = on
		dirty = true)
	var issue := UI.label("", "Dim", 13)
	issue.name = "Issue"
	issue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	issue.custom_minimum_size.x = 190
	issue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var del := UI.button("✕", func() -> void:
		entries.remove_at(row)
		row_parse_issues = []
		dirty = true
		render_rows(), "DangerButton")
	del.tooltip_text = "Zeile löschen"
	panel.add_child(UI.hbox([
		_col(UI.label(str(row + 1), "Dim", 14), 34),
		field.call("de", 260),
		field.call("en", 230),
		alt, cs, issue, del,
	], 6))
	return panel


## Hinweise neu berechnen und an den Zeilen anzeigen, ohne die Eingabefelder neu aufzubauen.
func refresh() -> void:
	var row_issues: Array = ImportValidator.validate_entries(entries) + row_parse_issues
	var all: Array = parse_issues.filter(func(i: Dictionary) -> bool: return int(i.row) < 0) + row_issues
	var by_row := {}
	for issue: Dictionary in row_issues:
		if int(issue.row) >= 0:
			if not by_row.has(int(issue.row)):
				by_row[int(issue.row)] = []
			by_row[int(issue.row)].append(issue)
	for row in _rows.get_child_count():
		var panel := _rows.get_child(row) as PanelContainer
		var list: Array = by_row.get(row, [])
		var has_error := list.any(func(i: Dictionary) -> bool: return i.severity == "error")
		panel.theme_type_variation = "RowError" if has_error else ("RowWarning" if not list.is_empty() else "RowPlain")
		var lbl := panel.find_child("Issue", true, false) as Label
		lbl.text = " ".join(PackedStringArray(list.map(func(i: Dictionary) -> String: return i.message)))
		lbl.theme_type_variation = "Bad" if has_error else "Accent"
	UI.clear(_issue_box)
	for issue: Dictionary in all:
		if int(issue.row) < 0:
			_issue_box.add_child(UI.para(("✖ " if issue.severity == "error" else "⚠ ") + issue.message, "Bad" if issue.severity == "error" else "Accent", 15))
	var errors := all.filter(func(i: Dictionary) -> bool: return i.severity == "error").size()
	_counter.text = "%d Vokabeln%s" % [entries.size(), " · %d Fehler zu korrigieren" % errors if errors > 0 else ""]
	_save_btn.disabled = ImportValidator.has_errors(all) or _title_input.text.strip_edges() == ""


func _apply_filter() -> void:
	var q := _search.text.strip_edges().to_lower()
	for row in _rows.get_child_count():
		var e: Dictionary = entries[row]
		var hay := ("%s %s %s" % [e.de, e.en, " ".join(PackedStringArray(e.alternatives))]).to_lower()
		(_rows.get_child(row) as Control).visible = q == "" or hay.contains(q)


func append_entries(text: String) -> void:
	var res := ImportValidator.parse_import(text)
	if not res.ok:
		_append_box.visible = true
		_append_error.text = res.message
		return
	var offset := entries.size()
	entries.append_array(res.entries)
	for i: Dictionary in res.issues:
		if int(i.row) >= 0:
			var shifted := i.duplicate()
			shifted.row = int(i.row) + offset
			row_parse_issues.append(shifted)
	_append_text.text = ""
	_append_error.text = ""
	_append_box.visible = false
	_search.text = ""
	dirty = true
	render_rows()
	Sound.play("select")
	UI.toast(modal, "%d Vokabeln angehängt" % (res.entries as Array).size())


func _save() -> void:
	var id: String = existing.id if not existing.is_empty() else Ctx.repo.new_unit_id()
	var unit := {
		"id": id,
		"title": _title_input.text.strip_edges(),
		"createdAt": int(existing.createdAt) if not existing.is_empty() else Vocab.now_ms(),
		"vocabulary": ImportValidator.finalize_entries(entries, id),
	}
	Ctx.repo.upsert(unit)
	Sound.play("correct")
	close(unit)
