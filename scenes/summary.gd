extends Control
## Auswertung nach einem Abenteuer – ohne jede Bewertung nach Geschwindigkeit.
## `victory` wird vor dem Einhängen gesetzt (Boss besiegt oder Abenteuer beendet).

const TITLE := "res://scenes/title.tscn"

var victory := false
var _stars: Array = []  # [Vector2 Position, Radius, Phase, Tempo]
var _t := 0.0


func _ready() -> void:
	name = "Summary"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not Ctx.has_run():
		get_tree().change_scene_to_file.call_deferred(TITLE)
		return
	for i in 60:
		_stars.append([Vector2(randf() * 1280.0, randf() * 720.0), randf_range(1.0, 2.5), randf() * TAU, randf_range(1.5, 4.0)])
	Sound.play("victory" if victory else "select")
	_build()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Sternenhimmel mit sanft funkelnden Punkten.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#120e1e"))
	var k := size / Vector2(1280, 720)
	for s: Array in _stars:
		var a := 0.2 + 0.6 * (0.5 + 0.5 * sin(_t * s[3] + s[2]))
		draw_circle(s[0] * k, s[1], Color(1.0, 0.95, 0.77, a))


func _build() -> void:
	var run: Dictionary = Ctx.run
	var learning: LearningSession = run.learning
	var s := learning.run.summary()
	var minutes := maxi(1, roundi((Vocab.now_ms() - int(run.startedAt)) / 60000.0))
	var words: Array = s.words
	var avg_delta := (float(s.masteryDelta) / words.size()) * 100.0 if not words.is_empty() else 0.0

	var win := UI.window(1080)
	var body: VBoxContainer = win.get_node("Body")
	var title := UI.label("🏆 Abenteuer bestanden!" if victory else "Abenteuer beendet", "H1")
	title.add_theme_color_override("font_color", UI.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var sub := UI.label("Der Boss ist besiegt. Hier ist, was du gelernt hast:" if victory else "Dein Lernfortschritt wurde gespeichert. Hier ist deine Auswertung:", "Dim", 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(sub)
	body.add_child(UI.gap(4))

	var grid := UI.hbox([], 10)
	grid.add_child(_stat(str(int(s.totalQuestions)), "Abfragen", "Accent"))
	grid.add_child(_stat(str(words.size()), "verschiedene Wörter", "Accent"))
	grid.add_child(_stat(str((s.firstTryCorrect as Array).size()), "beim ersten Versuch richtig", "Good"))
	grid.add_child(_stat("%s%d %%" % ["+" if avg_delta >= 0 else "", roundi(avg_delta)], "Ø Mastery-Zuwachs pro Wort", "Accent"))
	body.add_child(grid)
	body.add_child(UI.gap(6))

	var left := UI.vbox([UI.label("✔ Beim ersten Versuch gewusst", "H3")])
	left.add_child(_chips(s.firstTryCorrect, false, "–"))
	left.add_child(UI.gap(8))
	left.add_child(UI.label("💡 Mit Hilfe gelöst", "H3"))
	left.add_child(_chips(s.withHints, false, "Keine Hilfen gebraucht."))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var right := UI.vbox([UI.label("✎ Diese Wörter üben wir weiter", "H3")])
	if (s.wrongWords as Array).is_empty():
		right.add_child(UI.label("Kein einziger Fehler – großartig!", "Good", 17))
	else:
		right.add_child(_chips(s.wrongWords, true, ""))
	if not (s.hardest as Array).is_empty():
		right.add_child(UI.gap(8))
		right.add_child(UI.label("Schwierigste Wörter", "H3"))
		var table := GridContainer.new()
		table.columns = 3
		table.add_theme_constant_override("h_separation", 16)
		for w: Dictionary in s.hardest:
			table.add_child(UI.label(w.item.entry.de, "", 16))
			table.add_child(UI.label(w.item.entry.en, "", 16))
			table.add_child(UI.mastery_bar(float(w.masteryAfter)))
		right.add_child(table)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cols := UI.hbox([left, right], 16)
	body.add_child(UI.scroll(cols, 320))

	var back := UI.button("Zurück zum Titel", back_to_title)
	back.add_theme_font_size_override("font_size", 22)
	var footer := UI.hbox([
		UI.label("⏱ ca. %d min" % minutes, "", 17),
		UI.label("⭐ +%d XP (Level %d)" % [int(run.xpGained), int(Ctx.profile.level)], "", 17),
		UI.label("💰 +%d Gold" % int(run.goldGained), "", 17),
	], 18)
	if not (run.lootGained as Array).is_empty():
		var names := (run.lootGained as Array).map(func(id: String) -> String: return GameData.get_item(id).name)
		footer.add_child(UI.label("✨ " + ", ".join(PackedStringArray(names)), "", 17))
	footer.add_child(UI.spacer())
	footer.add_child(back)
	body.add_child(UI.gap(6))
	body.add_child(footer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(win)
	add_child(center)
	UI.focus_later(back)


func _stat(big: String, label: String, variation: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Card"
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := UI.label(big, variation, 34)
	b.add_theme_font_override("font", UiTheme.font_bold)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var l := UI.label(label, "", 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(UI.vbox([b, l], 0))
	return p


static func _chips(records: Array, with_count: bool, empty_text: String) -> Control:
	if records.is_empty():
		return UI.label(empty_text, "Dim", 16)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for w: Dictionary in records:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.3), Color(0.79, 0.82, 1.0, 0.35), 1, 12, Vector4(9, 3, 9, 3)))
		var e: Dictionary = w.item.entry
		chip.add_child(UI.label("%s → %s%s" % [e.de, e.en, " (%d×)" % int(w.wrong) if with_count else ""], "", 15))
		chip.tooltip_text = "%s → %s" % [e.de, e.en]
		flow.add_child(chip)
	return flow


func back_to_title() -> void:
	Sound.play("select")
	Ctx.run = {}
	get_tree().change_scene_to_file(TITLE)
