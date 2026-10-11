extends Control
## Titelbildschirm: Set-Auswahl (Filter, Sortierung, Datum, Mastery, ✎, Alle/Keine), Import und
## Drag & Drop, Klassenwahl (Tasten 1–3), Sets & Statistik, Fortsetzen, Training,
## Zeit-Challenge und Spiel verlassen.

const EXPLORATION := "res://scenes/exploration.tscn"

var set_filter := ""
var set_sort := "newest"  # newest | name | weakest

var _ui: Control
var _selected := {}
var _list_body: VBoxContainer
var _summary: Label
var _toggle_all: Button
var _start_btn: Button
var _fx: WorldFx
var _pan_points: Array[Vector3] = []
var _pan_i := 0
var _pan_t := 0.0


func _ready() -> void:
	SettingsView.apply()
	_build_backdrop()
	_ui = Control.new()
	_ui.name = "UI"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	get_window().files_dropped.connect(_on_files_dropped)
	render_menu()


func _exit_tree() -> void:
	if get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)


## Ein zufälliges Level als langsam schwenkende 3D-Kulisse.
func _build_backdrop() -> void:
	var theme := GameData.get_theme("jungle")
	var cfg := GameConfig.section("level")
	var map := LevelGenerator.generate(Rng.random_seed(), cfg, {"bossRunesRequired": 3, "enemies": theme.enemies})
	var world := Node3D.new()
	world.name = "Backdrop"
	add_child(world)
	world.add_child(LevelBuilder.build(map).root)
	_fx = WorldFx.new(1.2)
	_fx.zoom = 0.8
	_fx.follow_speed = 0.0
	world.add_child(_fx)
	for room: Dictionary in map.rooms:
		var c := MapModel.room_center(room)
		_pan_points.append(Vector3(c.x + 0.5, 0, c.y + 0.5))
	_fx.target = _pan_points[0]
	_fx.snap()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.024, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


func _process(delta: float) -> void:
	if _fx == null or _pan_points.size() < 2:
		return
	# Gleichmäßig von Raum zu Raum schwenken (etwa 9 s pro Abschnitt, sanft ein- und ausblenden).
	_pan_t += delta / 9.0
	if _pan_t >= 1.0:
		_pan_t = 0.0
		_pan_i = (_pan_i + 1) % _pan_points.size()
	var a: Vector3 = _pan_points[_pan_i]
	var b: Vector3 = _pan_points[(_pan_i + 1) % _pan_points.size()]
	_fx.target = a.lerp(b, smoothstep(0.0, 1.0, _pan_t))
	_fx.snap()


# ---------- Hauptmenü ----------

func render_menu() -> void:
	UI.clear(_ui)
	var units := Ctx.repo.all()
	_selected = {}
	for id: String in Ctx.settings.get("selectedUnits", []):
		if not Ctx.repo.get_unit(id).is_empty():
			_selected[id] = true
	if _selected.is_empty():
		_selected[units[0].id] = true

	var logo := UI.label("Vokabel-Helden", "TitleLogo")
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := UI.label("Das Geheimnis des Dschungeltempels · Deutsch → Englisch", "Dim", 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var p: Dictionary = Ctx.profile
	var settings_btn := UI.button("⚙", open_settings, "SmallButton")
	settings_btn.tooltip_text = "Einstellungen"
	var help_btn := UI.button("❔", open_help, "SmallButton")
	help_btn.tooltip_text = "So geht's"

	# Set-Auswahl mit Filter, Sortierung und Datum (Issue #8).
	var filter := LineEdit.new()
	filter.placeholder_text = "🔍 Sets filtern …"
	filter.text = set_filter
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter.text_changed.connect(func(t: String) -> void:
		set_filter = t
		_render_list())
	var sort := OptionButton.new()
	for o: Array in [["newest", "Neueste zuerst"], ["name", "Name A–Z"], ["weakest", "Am wenigsten geübt"]]:
		sort.add_item(o[1])
		sort.set_item_metadata(sort.item_count - 1, o[0])
		if o[0] == set_sort:
			sort.select(sort.item_count - 1)
	sort.item_selected.connect(func(i: int) -> void:
		set_sort = sort.get_item_metadata(i)
		_render_list())
	_toggle_all = UI.button("Alle", _toggle_all_visible, "SmallButton")
	_list_body = UI.vbox([], 3)
	_summary = UI.label("", "Dim", 15)

	var import_btn := UI.button("📥 Vokabel-Set importieren", func() -> void: open_import(), "SmallButton")
	_start_btn = UI.button("⚔ Neues Abenteuer", _on_start, "BigButton")
	var start_row := UI.hbox([UI.spacer(), _start_btn])
	if Ctx.can_resume():
		start_row.add_child(UI.button("⟲ Abenteuer fortsetzen", _on_resume))
	start_row.add_child(UI.spacer())
	var heat_row := UI.hbox([UI.spacer(), _heat_selector(), _time_challenge_toggle(), UI.spacer()], 16)
	var manage_btn := UI.button("📚 Sets & Statistik", open_unit_manager)
	var skills_btn := UI.button("🌳 Fertigkeiten", open_skills)
	var bottom_row := UI.hbox([UI.spacer(), manage_btn, skills_btn])
	# Im Browser lässt sich das Spiel nicht beenden – dort schließt man einfach den Tab.
	if not OS.has_feature("web"):
		bottom_row.add_child(UI.button("🚪 Spiel verlassen", quit_game))
	bottom_row.add_child(UI.spacer())

	var win := UI.window(640, [
		UI.hbox([
			UI.label("%s %d %s" % [Meta.ICON, int(p.shards), Meta.CURRENCY], "Accent", 18),
			UI.label("Abenteuer: %d · Siege: %d" % [int(p.records.runs), int(p.records.victories)], "Dim", 15),
			UI.spacer(), help_btn, settings_btn,
		], 14),
		UI.label("Welche Vokabel-Sets willst du üben?", "H3"),
		UI.hbox([filter, sort, _toggle_all]),
		UI.scroll(_list_body, 168 if Meta.heat_max_unlocked(Ctx.profile) <= 0 else 128),
		_summary,
		UI.hbox([import_btn, UI.label("oder JSON-Datei ins Fenster ziehen", "Dim", 14)]),
		UI.gap(4),
		start_row,
		heat_row,
		bottom_row,
	])

	var column := UI.vbox([logo, sub, UI.gap(10), _center(win)], 2)
	column.set_anchors_preset(Control.PRESET_CENTER_TOP)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.position.y = 26
	_ui.add_child(column)

	var help := RichTextLabel.new()
	help.bbcode_enabled = true
	help.fit_content = true
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	help.add_theme_font_size_override("normal_font_size", 14)
	help.add_theme_color_override("default_color", UI.DIM)
	help.text = "[center]Steuerung: [color=#f1c96b]WASD[/color]/[color=#f1c96b]Pfeiltasten[/color] bewegen · [color=#f1c96b]E[/color]/[color=#f1c96b]Enter[/color] interagieren · [color=#f1c96b]I[/color] Inventar · [color=#f1c96b]Esc[/color] Menü · Grafik & Sound: Kenney.nl (CC0)[/center]"
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.custom_minimum_size.x = 1000
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.position.y -= 10
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(help)

	_render_list()
	_update_start()
	UI.focus_later(_start_btn)
	# Beim allerersten Start erklärt ein kurzes Fenster das Spiel.
	if not bool(Ctx.settings.get("seenIntro", false)):
		_show_intro.call_deferred()


func quit_game() -> void:
	Ctx.save_persistent()
	get_tree().quit()


func _show_intro() -> void:
	if not is_inside_tree() or bool(Ctx.settings.get("seenIntro", false)):
		return
	Ctx.settings.seenIntro = true
	Ctx.save_persistent()
	open_help()


func open_settings() -> UI.Modal:
	var m := UI.modal(_ui, "Einstellungen", 640)
	var box := UI.vbox()
	m.body.add_child(box)
	SettingsView.render(box)
	return m


const HELP := [
	["⚔ Ziel", "Erkunde den Dschungeltempel, sammle Runen ◆ (besiegte Gegner, geöffnete Türen) und öffne damit das Siegeltor zum Boss."],
	["📖 Lernen", "Jede Aktion im Kampf, jede Truhe und jede Tür verlangt ein englisches Wort. Falsch ist nicht schlimm: Du siehst die Lösung, tippst sie einmal ab und das Wort kommt bald wieder. Es gibt kein Zeitlimit – außer du wählst die ⏱ Zeit-Challenge."],
	["🎯 Training", "Mit 🎯 neben einem Set übst du ohne Spiel: Du siehst das deutsche Wort und tippst das englische ein. Falsche Wörter kommen am Ende noch einmal, bis alle sitzen. Schaffst du alle, gibt es Tempelsplitter."],
	["⏱ Zeit-Challenge", "Wer mag, schaltet sie vor dem Start ein: Dann muss das ganze Abenteuer in einer festen Zeit geschafft werden. Je mehr Vokabeln du übst, desto mehr Zeit gibt es. Im Menü (Esc) und im Inventar (I) steht die Uhr still. Ein Sieg bringt extra Tempelsplitter."],
	["💡 Hilfen", "Alt+1 zeigt die Wortlänge, Alt+2 den ersten Buchstaben. Hilfen kosten Fokus (FP)."],
	["❤ Leben", "Jedes Abenteuer hat 3 Leben. Bei einer Niederlage erwachst du am Kristallaltar; ist das letzte Leben weg, endet das Abenteuer."],
	["🔷 Tempelsplitter", "Jedes Abenteuer beginnt auf Level 1 mit Holzschwert – Ausrüstung, Gold und Level verfallen am Ende. Dafür bekommst du Tempelsplitter für alles Erreichte. Damit schaltest du unter „🌳 Fertigkeiten“ neue Klassen frei und baust Skillbäume aus."],
	["✨ Unterwegs", "Am Kristallaltar ruhst du dich aus und kaufst beim Händler mit Gold ein. Nach jedem Sieg über einen Elite-Gegner wählst du eine Segnung für den Rest des Abenteuers."],
	["🎮 Steuerung", "WASD/Pfeiltasten oder Controller bewegen · E/Enter/Leertaste (A) interagieren · I (Y) Charakter & Inventar · Esc (Start) Menü · F8 oder 🐞 etwas melden."],
]


func open_help() -> UI.Modal:
	var m := UI.modal(_ui, "So geht's", 860)
	for h: Array in HELP:
		var title := UI.label(h[0], "H3")
		title.custom_minimum_size.x = 210
		title.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var text := UI.para(h[1], "", 16)
		m.body.add_child(UI.hbox([title, text], 12))
	return m


static func _center(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.add_child(c)
	return cc


func visible_units() -> Array:
	var q := set_filter.strip_edges().to_lower()
	var list := Ctx.repo.all().filter(func(u: Dictionary) -> bool: return q == "" or (u.title as String).to_lower().contains(q))
	match set_sort:
		"name":
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.title as String).naturalnocasecmp_to(b.title) < 0)
		"weakest":
			var m := {}
			for u: Dictionary in list:
				m[u.id] = StatsView.average_mastery(u.id)
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return m[a.id] < m[b.id])
		_:
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.createdAt) > int(b.createdAt))
	return list


func _render_list() -> void:
	UI.clear(_list_body)
	var list := visible_units()
	for unit: Dictionary in list:
		var row := PanelContainer.new()
		row.theme_type_variation = "RowChecked" if _selected.has(unit.id) else "RowUnchecked"
		var cb := CheckBox.new()
		cb.button_pressed = _selected.has(unit.id)
		cb.text = unit.title
		cb.add_theme_font_size_override("font_size", 17)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.clip_text = true
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				_selected[unit.id] = true
			else:
				_selected.erase(unit.id)
			row.theme_type_variation = "RowChecked" if on else "RowUnchecked"
			_update_start())
		var built_in := Ctx.repo.is_built_in(unit.id)
		var date := UI.label("Beispiel" if built_in else UI.format_date(int(unit.createdAt)), "Dim", 14)
		date.custom_minimum_size.x = 84
		var count := UI.label("%d W." % (unit.vocabulary as Array).size(), "Dim", 14)
		count.custom_minimum_size.x = 48
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var train := UI.button("🎯", func() -> void: start_training(unit.id), "SmallButton")
		train.tooltip_text = "Training: Vokabeln als Karten üben, ohne Spiel"
		var edit := UI.button("✎", func() -> void: edit_set(unit.id), "SmallButton")
		edit.tooltip_text = "Als eigene Kopie bearbeiten" if built_in else "Set bearbeiten und erweitern"
		row.add_child(UI.hbox([cb, date, count, UI.mastery_bar(StatsView.average_mastery(unit.id), 70), train, edit], 10))
		_list_body.add_child(row)
	if list.is_empty():
		_list_body.add_child(UI.label("Kein Set passt zum Filter.", "Dim", 16))
	_toggle_all.text = "Keine" if not list.is_empty() and list.all(func(u: Dictionary) -> bool: return _selected.has(u.id)) else "Alle"


## Gewählte Tempelstufe (gespeichert, auf die freigeschaltete Stufe begrenzt).
func selected_heat() -> int:
	return clampi(int(Ctx.settings.get("heat", 0)), 0, Meta.heat_max_unlocked(Ctx.profile))


## Auswahl der Tempelstufe; erst sichtbar, wenn nach einem Sieg Stufe 1 freigeschaltet ist.
func _heat_selector() -> OptionButton:
	var max_heat := Meta.heat_max_unlocked(Ctx.profile)
	if max_heat <= 0:
		return null
	var opt := OptionButton.new()
	for h in max_heat + 1:
		opt.add_item(("🔥 " if h > 0 else "") + Meta.heat_text(h))
	opt.select(selected_heat())
	opt.item_selected.connect(func(i: int) -> void:
		Ctx.settings.heat = i
		Ctx.save_persistent())
	return opt


var _time_toggle: CheckBox


## Zeit-Challenge an/aus; die angezeigte Zeit richtet sich nach den gewählten Vokabeln.
func _time_challenge_toggle() -> CheckBox:
	_time_toggle = CheckBox.new()
	_time_toggle.button_pressed = bool(Ctx.settings.get("timeChallenge", false))
	_time_toggle.add_theme_font_size_override("font_size", 17)
	_time_toggle.tooltip_text = "Das ganze Abenteuer muss in der angezeigten Zeit geschafft werden.
Mehr Vokabeln = mehr Zeit. Ein Sieg bringt +%d %% %s." % [roundi(float(GameConfig.section("timeChallenge").shardBonus) * 100.0), Meta.CURRENCY]
	_time_toggle.toggled.connect(func(on: bool) -> void:
		Ctx.settings.timeChallenge = on
		Ctx.save_persistent())
	return _time_toggle


func time_limit() -> int:
	return RunScaling.time_limit_for(Ctx.repo.learning_items(_selected.keys()).size())


func _toggle_all_visible() -> void:
	var list := visible_units()
	var all_selected := list.all(func(u: Dictionary) -> bool: return _selected.has(u.id))
	for u: Dictionary in list:
		if all_selected:
			_selected.erase(u.id)
		else:
			_selected[u.id] = true
	_update_start()
	_render_list()


func _update_start() -> void:
	_start_btn.disabled = _selected.is_empty()
	Ctx.settings.selectedUnits = _selected.keys()
	Ctx.save_persistent()
	var words := 0
	for id: String in _selected:
		words += (Ctx.repo.get_unit(id).get("vocabulary", []) as Array).size()
	var n := _selected.size()
	_summary.text = "Kein Set ausgewählt." if n == 0 else "%d %s ausgewählt · %d Wörter" % [n, "Set" if n == 1 else "Sets", words]
	if _time_toggle:
		_time_toggle.text = "⏱ Zeit-Challenge (%s Min.)" % Hud.format_time(time_limit())


# ---------- Abenteuer ----------

func _on_start() -> void:
	var go := func() -> void:
		choose_class(func(hero_class: String) -> void:
			Ctx.profile.heroClass = hero_class
			Ctx.save_persistent()
			Ctx.save.clear_run()
			Sound.play("encounter")
			Ctx.start_run(_selected.keys(), "jungle", -1, selected_heat(), bool(Ctx.settings.get("timeChallenge", false)))
			_enter_world())
	if Ctx.can_resume():
		UI.confirm(_ui, "Ein laufendes Abenteuer wird dabei beendet. Trotzdem neu starten?", go, "Neu starten")
	else:
		go.call()


func _on_resume() -> void:
	if not Ctx.resume_run().is_empty():
		Sound.play("select")
		_enter_world()


## Trainingsmodus für ein Set: Karten üben ohne Spiel.
func start_training(unit_id: String) -> void:
	Sound.play("select")
	TrainingScreen.start(get_tree(), unit_id)


func _enter_world() -> void:
	if ResourceLoader.exists(EXPLORATION):
		get_tree().change_scene_to_file(EXPLORATION)
	else:
		UI.toast(_ui, "Die Erkundung wird gerade gebaut.")
		render_menu()


## Klassenwahl vor jedem Abenteuer. Gesperrte Klassen werden unter „Fertigkeiten“ freigeschaltet.
func choose_class(on_choose: Callable = Callable()) -> UI.Modal:
	var m := UI.modal(_ui, "Wähle deine Klasse", 1100)
	m.name = "ClassSelect"
	var sub := UI.label("Jedes Abenteuer beginnt auf Level 1 mit Holzschwert. Gesperrte Klassen schaltest du unter „Fertigkeiten“ frei.", "Dim", 16)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.body.add_child(sub)
	m.body.add_child(UI.gap(6))
	var pick := func(id: String) -> void:
		if not Meta.is_class_unlocked(Ctx.profile, id):
			Sound.play("wrong")
			UI.toast(m, "%s ist noch gesperrt (%d %s unter „Fertigkeiten“)." % [GameData.get_class_def(id).name, Meta.unlock_cost(id), Meta.ICON])
			return
		m.close()
		if on_choose.is_valid():
			on_choose.call(id)
	var row := UI.hbox([], 14)
	var focus_btn: Button
	for i in GameData.HERO_CLASSES.size():
		var cls: Dictionary = GameData.HERO_CLASSES[i]
		var card := _class_card(cls, i + 1)
		card.pressed.connect(pick.bind(cls.id))
		row.add_child(card)
		if Meta.is_class_unlocked(Ctx.profile, cls.id) and (cls.id == Ctx.profile.heroClass or focus_btn == null):
			focus_btn = card
	m.body.add_child(row)
	# Tasten 1–3 wählen direkt.
	var keys := KeyCatcher.new()
	keys.on_key = func(code: Key) -> bool:
		var idx := [KEY_1, KEY_2, KEY_3].find(code)
		if idx < 0:
			idx = [KEY_KP_1, KEY_KP_2, KEY_KP_3].find(code)
		if idx >= 0 and m.is_top():
			pick.call(GameData.HERO_CLASSES[idx].id)
			return true
		return false
	m.add_child(keys)
	UI.focus_later(focus_btn)
	return m


func _class_card(cls: Dictionary, key: int) -> Button:
	var card := Button.new()
	card.theme_type_variation = "CardButton"
	card.custom_minimum_size = Vector2(340, 440)
	var box := UI.vbox([], 6)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	box.offset_top = 12
	box.offset_bottom = -12
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sprite := UI.sprite(int(cls.frame), 96)
	sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(sprite)
	var name := UI.label(cls.name, "H2")
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	var tag := UI.label(cls.tagline, "Dim", 14)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)
	box.add_child(UI.para(cls.description, "", 15))
	var stats := UI.hbox([
		UI.label("❤ %s" % UI.signed(int(cls.hpBonus)), "Good", 15),
		UI.label("✦ FP %s" % UI.signed(int(cls.focusBonus)), "", 15),
		UI.label("⚔ %s" % UI.signed(int(cls.attackBonus)), "Accent", 15),
	], 16)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(stats)
	box.add_child(_rich("[b][color=#f1c96b]%s (%d FP)[/color][/b] – %s" % [cls.skill.name, int(cls.skill.focusCost), cls.skill.description]))
	box.add_child(_rich("[b][color=#f1c96b]%s[/color][/b] – %s" % [cls.passiveName, cls.passiveDescription]))
	var ranks := 0
	for node: Dictionary in SkillTrees.tree(cls.id).nodes:
		ranks += Meta.rank(Ctx.profile, cls.id, node.id)
	var status := UI.label("🌳 %d Fertigkeitsränge" % ranks, "Dim", 14) if Meta.is_class_unlocked(Ctx.profile, cls.id) \
		else UI.label("🔒 Gesperrt – %d %s" % [Meta.unlock_cost(cls.id), Meta.ICON], "Bad", 16)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	if not Meta.is_class_unlocked(Ctx.profile, cls.id):
		card.modulate = Color(1, 1, 1, 0.55)
	for c in box.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	# Tastenkappe oben links in der Ecke, außerhalb des Textflusses.
	var cap := UI.keycap(str(key), 18)
	cap.position = Vector2(12, 12)
	card.add_child(cap)
	return card


static func _rich(bb: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bb
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 14)
	r.add_theme_font_override("bold_font", UiTheme.font_bold)
	r.add_theme_color_override("default_color", UI.TEXT)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


# ---------- Sets: Import, Bearbeiten, Statistik ----------

func _on_files_dropped(files: PackedStringArray) -> void:
	if files.is_empty():
		return
	var text := FileAccess.get_file_as_string(files[0])
	var dialog := ImportDialog.current()
	if dialog != null:
		dialog.handle_drop(text)
	else:
		open_import(text)


## Import direkt vom Titelbildschirm; ein neues Set wird gleich für das nächste Abenteuer ausgewählt.
func open_import(initial_text: String = "", on_done: Callable = Callable()) -> ImportDialog:
	return ImportDialog.open(_ui, {
		"initial_text": initial_text,
		"on_done": func(saved: Dictionary) -> void:
			if not saved.is_empty() and not (Ctx.settings.selectedUnits as Array).has(saved.id):
				# Ist bisher nur das Beispiel-Set gewählt, wird es durch das neue ersetzt.
				var current := (Ctx.settings.selectedUnits as Array).filter(func(id: String) -> bool:
					return not Ctx.repo.get_unit(id).is_empty() and not Ctx.repo.is_built_in(id))
				current.append(saved.id)
				Ctx.settings.selectedUnits = current
				Ctx.save_persistent()
			if on_done.is_valid():
				on_done.call()
			else:
				render_menu(),
	})


## Set bearbeiten und erweitern. Das Beispiel-Set ist fest eingebaut und wird als eigene Kopie angelegt.
func edit_set(unit_id: String, on_done: Callable = Callable()) -> void:
	var unit := Ctx.repo.get_unit(unit_id)
	if unit.is_empty():
		return
	if Ctx.repo.is_built_in(unit.id):
		var copy := JSON.stringify({"version": 1, "title": "%s (Kopie)" % unit.title, "vocabulary": unit.vocabulary})
		open_import(copy, on_done)
		return
	ImportDialog.open(_ui, {
		"existing": unit,
		"on_done": func(_saved: Dictionary) -> void:
			if on_done.is_valid():
				on_done.call()
			else:
				render_menu(),
	})


func open_skills(class_id: String = "") -> UI.Modal:
	var m := UI.modal(_ui, "Fertigkeiten", 1140)
	m.closed.connect(render_menu)
	var body := UI.vbox()
	m.body.add_child(body)
	SkillTreeView.render(body, class_id)
	return m


func open_unit_manager() -> UI.Modal:
	var m := UI.modal(_ui, "Vokabel-Sets", 1080)
	m.closed.connect(render_menu)
	_render_units(m)
	return m


func _render_units(m: UI.Modal) -> void:
	var body := m.body
	UI.clear(body)
	var rerender := func() -> void: _render_units(m)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	for h: String in ["Einheit", "Wörter", "Mastery", ""]:
		grid.add_child(UI.label(h, "Accent", 15))
	for unit: Dictionary in Ctx.repo.all():
		var built_in := Ctx.repo.is_built_in(unit.id)
		var title := UI.label(unit.title + ("  (Beispiel)" if built_in else ""), "", 17)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		title.custom_minimum_size.x = 420
		grid.add_child(title)
		grid.add_child(UI.label(str((unit.vocabulary as Array).size()), "", 17))
		grid.add_child(UI.mastery_bar(StatsView.average_mastery(unit.id), 120))
		var actions := UI.hbox([
			UI.button("🎯 Training", func() -> void: start_training(unit.id), "SmallButton"),
			UI.button("Statistik", func() -> void: _open_stats(m, unit.id), "SmallButton"),
			UI.button("Als Kopie bearbeiten" if built_in else "Bearbeiten", func() -> void: edit_set(unit.id, rerender), "SmallButton"),
		])
		if not built_in:
			actions.add_child(UI.button("Löschen", func() -> void:
				UI.confirm(_ui, "Einheit „%s“ wirklich löschen?" % unit.title, func() -> void:
					Ctx.repo.remove(unit.id)
					rerender.call(), "Löschen"), "DangerButton"))
		actions.alignment = BoxContainer.ALIGNMENT_END
		grid.add_child(actions)
	body.add_child(UI.scroll(grid, 470))
	body.add_child(UI.hbox([UI.spacer(), UI.button("＋ Neues Set importieren", func() -> void: open_import("", rerender))]))


func _open_stats(m: UI.Modal, unit_id: String) -> void:
	var body := m.body
	UI.clear(body)
	var back := UI.button("← Zurück", func() -> void: _render_units(m), "SmallButton")
	body.add_child(UI.hbox([back, UI.label(Ctx.repo.get_unit(unit_id).get("title", ""), "H3")]))
	var stats := UI.vbox()
	body.add_child(stats)
	StatsView.render(stats, unit_id)


## Fängt Tastendrücke für ein Modal ab (z. B. Klassenwahl mit 1–3).
class KeyCatcher extends Node:
	var on_key: Callable

	func _unhandled_key_input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k.pressed and not k.echo and on_key.call(k.keycode):
			get_viewport().set_input_as_handled()
