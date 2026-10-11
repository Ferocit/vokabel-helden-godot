extends TestCase
## Titelbildschirm, Import-Editor und Klassenwahl – ohne Rendern, mit Speicher im Arbeitsspeicher.

const TITLE := preload("res://scenes/title.tscn")


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func fresh_ctx() -> void:
	Ctx.setup(KeyValueStore.new())


static func unit(id: String, title: String, created: int, words: int) -> Dictionary:
	var vocab: Array = []
	for i in words:
		vocab.append(Vocab.entry("w%d" % i, "de%d" % i, "en%d" % i))
	return {"id": id, "title": title, "createdAt": created, "vocabulary": vocab}


static func open_title() -> Control:
	var t: Control = TITLE.instantiate()
	root().add_child(t)
	return t


static func close(node: Node) -> void:
	root().remove_child(node)
	node.free()


func test_titel_zeigt_beispielset_und_zusammenfassung() -> void:
	fresh_ctx()
	var t := open_title()
	expect_eq(t._list_body.get_child_count(), 1, "Ein Set in der Liste")
	expect_eq(t._summary.text, "1 Set ausgewählt · 27 Wörter")
	expect_false(t._start_btn.disabled, "Start möglich")
	expect_eq(Ctx.settings.selectedUnits, ["sample"])
	close(t)


func test_titel_filter_und_sortierung() -> void:
	fresh_ctx()
	Ctx.repo.upsert(unit("u_a", "Zoo-Tiere", 2000, 3))
	Ctx.repo.upsert(unit("u_b", "Alltag", 1000, 4))
	Ctx.progress[Vocab.item_key("u_a", "w0")] = {"mastery": 0.9}
	var t := open_title()
	var ids := func() -> Array: return t.visible_units().map(func(u: Dictionary) -> String: return u.id)
	expect_eq(ids.call(), ["u_a", "u_b", "sample"], "Neueste zuerst")
	t.set_sort = "name"
	expect_eq(ids.call(), ["u_b", "sample", "u_a"], "Name A–Z")
	t.set_sort = "weakest"
	expect_eq((ids.call() as Array).back(), "u_a", "Am meisten geübt zuletzt")
	t.set_filter = "zoo"
	t._render_list()
	expect_eq(ids.call(), ["u_a"], "Filter")
	expect_eq(t._list_body.get_child_count(), 1)
	t.set_filter = "gibtsnicht"
	t._render_list()
	expect_eq(t._list_body.get_child_count(), 1, "Hinweis bei leerem Filter")
	close(t)


func test_titel_alle_und_keine() -> void:
	fresh_ctx()
	Ctx.repo.upsert(unit("u_a", "A", 2000, 3))
	var t := open_title()
	t._toggle_all_visible()
	expect_eq(t._selected.size(), 2, "Alle gewählt")
	expect_eq(t._toggle_all.text, "Keine")
	expect_eq(t._summary.text, "2 Sets ausgewählt · 30 Wörter")
	t._toggle_all_visible()
	expect_eq(t._selected.size(), 0, "Keine gewählt")
	expect_true(t._start_btn.disabled, "Ohne Set kein Start")
	expect_eq(t._summary.text, "Kein Set ausgewählt.")
	close(t)


func test_klassenwahl_per_taste() -> void:
	fresh_ctx()
	var t := open_title()
	var chosen := []
	var m: UI.Modal = t.choose_class(func(id: String) -> void: chosen.append(id))
	var keys: Node = m.get_child(m.get_child_count() - 1)
	expect_true(keys.on_key.call(KEY_2), "Taste 2 erkannt")
	expect_eq(chosen, [], "Schurke ist anfangs gesperrt")
	Ctx.profile.unlockedClasses = ["warrior", "rogue"]
	expect_true(keys.on_key.call(KEY_2))
	expect_eq(chosen, ["rogue"])
	expect_false(keys.on_key.call(KEY_A), "Andere Tasten ignoriert")
	close(t)


func test_import_dialog_pruefen_bearbeiten_speichern() -> void:
	fresh_ctx()
	var t := open_title()
	var text := FileAccess.get_file_as_string("res://vokabeln/welcome.json")
	var d: ImportDialog = t.open_import(text)
	expect_true(d._in_preview, "Gültiges JSON öffnet direkt die Vorschau")
	expect_eq(ImportDialog.current(), d)
	var n := d.entries.size()
	expect_eq(d._rows.get_child_count(), n)
	expect_false(d._save_btn.disabled, "Speichern möglich")
	d.entries[0].de = ""
	d.refresh()
	expect_true(d._save_btn.disabled, "Fehler blockiert Speichern")
	expect_eq(String((d._rows.get_child(0) as Control).theme_type_variation), "RowError")
	d.entries[0].de = "Willkommen"
	d.refresh()
	expect_false(d._save_btn.disabled)
	d.append_entries('{"vocabulary":[{"de":"Hund","en":"dog"}]}')
	expect_eq(d.entries.size(), n + 1, "Angehängt")
	d.append_entries("kein json")
	expect_true(d._append_box.visible, "Fehler beim Anhängen sichtbar")
	expect_eq(d.entries.size(), n + 1)
	d._save()
	expect_eq(Ctx.repo.all().size(), 2, "Gespeichert")
	var u: Dictionary = Ctx.repo.all()[1]
	expect_eq(Ctx.repo.get_unit(u.id).vocabulary.size(), n + 1, "Im Repo gespeichert")
	expect_true((Ctx.settings.selectedUnits as Array).has(u.id), "Neues Set ausgewählt")
	expect_false((Ctx.settings.selectedUnits as Array).has("sample"), "Beispiel ersetzt")
	close(t)


func test_import_dialog_ungueltig_bleibt_bei_eingabe() -> void:
	fresh_ctx()
	var t := open_title()
	var d := ImportDialog.open(t._ui, {"initial_text": "{ kaputt"})
	expect_false(d._in_preview, "Ungültiges JSON bleibt im Eingabeschritt")
	d.handle_drop('{"title":"Neu","vocabulary":[{"de":"Katze","en":"cat"}]}')
	expect_true(d._in_preview, "Abgelegte Datei öffnet die Vorschau")
	expect_eq(d._title_input.text, "Neu")
	close(t)


func test_beispielset_wird_als_kopie_bearbeitet() -> void:
	fresh_ctx()
	var t := open_title()
	t.edit_set("sample")
	var d := ImportDialog.current()
	expect_true(d != null and d.existing.is_empty(), "Kopie statt Bearbeitung")
	expect_eq(d._title_input.text, "Beispiel: Abenteuer (Kopie)")
	close(t)


func test_ausruestung_verkaufen_und_trank_kaufen() -> void:
	fresh_ctx()
	Ctx.profile.gold = 30
	(Ctx.profile.bag as Array).append("copper_ring")
	var box := VBoxContainer.new()
	root().add_child(box)
	EquipmentView.render(box)
	var buttons := box.find_children("*", "Button", true, false)
	var sell: Button = buttons.filter(func(b: Button) -> bool: return b.text.begins_with("Verkaufen"))[0]
	sell.pressed.emit()
	expect_eq(int(Ctx.profile.gold), 40, "Gewöhnlich: +10 Gold")
	expect_false((Ctx.profile.bag as Array).has("copper_ring"))
	buttons = box.find_children("*", "Button", true, false)
	var buy: Button = buttons.filter(func(b: Button) -> bool: return b.text.begins_with("Kaufen"))[0]
	buy.pressed.emit()
	expect_eq(int(Ctx.profile.gold), 20)
	expect_eq(int(Ctx.profile.potions), 3)
	close(box)


func test_einstellungen_anwenden() -> void:
	fresh_ctx()
	Ctx.settings.volume = 0.5
	Ctx.settings.sound = false
	SettingsView.apply()
	expect_false(Sound.enabled)
	expect_near(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.5, 0.01)
	var box := VBoxContainer.new()
	root().add_child(box)
	SettingsView.render(box)
	var slider: HSlider = box.find_children("*", "HSlider", true, false)[0]
	slider.value = 0.25
	expect_near(float(Ctx.settings.volume), 0.25, 0.001, "Regler speichert")
	Ctx.settings.sound = true
	Ctx.settings.volume = 0.8
	SettingsView.apply()
	close(box)


func test_controller_belegung() -> void:
	Controls.ensure()
	for action in ["move_up", "move_left", "interact", "menu"]:
		expect_true(InputMap.action_get_events(action).any(func(e: InputEvent) -> bool: return e is InputEventJoypadButton), action)
	expect_true(InputMap.action_get_events("move_right").any(func(e: InputEvent) -> bool: return e is InputEventJoypadMotion), "Stick")
	var before := InputMap.action_get_events("interact").size()
	Controls.ensure()
	expect_eq(InputMap.action_get_events("interact").size(), before, "Kein doppeltes Anlegen")


func test_einstieg_beim_ersten_start() -> void:
	fresh_ctx()
	var t := open_title()
	expect_false(bool(Ctx.settings.seenIntro))
	t._show_intro()
	expect_true(bool(Ctx.settings.seenIntro), "Nur einmal")
	var modals: Array = t._ui.get_children().filter(func(c: Node) -> bool: return c is UI.Modal)
	expect_eq(modals.size(), 1, "Hilfe geöffnet")
	close(t)
