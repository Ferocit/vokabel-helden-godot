class_name TrainingScreen
extends Control
## Trainingsmodus für ein Set – ganz ohne Spiel: Karte mit dem deutschen Wort, englisch eintippen.
## Falsche Karten kommen am Ende der Runde noch einmal, bis alle sitzen. Wer alle schafft, bekommt
## Tempelsplitter. Jede Antwort zählt wie im Abenteuer für Statistik und Mastery.
## Vor dem Szenenwechsel `unit_id` setzen (siehe Titel).

const TITLE := "res://scenes/title.tscn"
const SCENE := "res://scenes/training.tscn"

static var unit_id := ""

var unit: Dictionary
var session: TrainingSession
var reward := 0

var _title: Label
var _progress: Label
var _bar: ProgressBar
var _result: PanelContainer


static func start(tree: SceneTree, id: String) -> void:
	unit_id = id
	tree.change_scene_to_file(SCENE)


func _ready() -> void:
	name = "Training"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	unit = Ctx.repo.get_unit(unit_id)
	var items := Ctx.repo.learning_items([unit_id])
	if items.is_empty():
		get_tree().change_scene_to_file.call_deferred(TITLE)
		return
	var bg := ColorRect.new()
	bg.color = Color("#120e1e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_header()
	session = TrainingSession.new(items, Rng.create(Rng.random_seed()))
	next_card()


func _build_header() -> void:
	_title = UI.label("🎯 Training: %s" % unit.title, "H3")
	_progress = UI.label("", "Dim", 16)
	_bar = Hud.bar(0, 1, UI.GOOD, 220)
	var quit := UI.button("Beenden", ask_quit, "SmallButton")
	quit.focus_mode = Control.FOCUS_NONE
	var header := PanelContainer.new()
	header.custom_minimum_size.x = 900
	header.add_child(UI.hbox([_title, UI.spacer(), _progress, _bar, quit], 14))
	UI.pin(self, header, Control.PRESET_CENTER_TOP, Vector2(0, 10))


func _refresh_header() -> void:
	var total := session.items.size()
	var done := total - session.remaining()
	_progress.text = "%d von %d geschafft%s" % [done, total, " · Runde %d" % session.round if session.round > 1 else ""]
	_bar.max_value = total
	_bar.value = done


func next_card() -> void:
	_refresh_header()
	if session.is_finished():
		_finish()
		return
	var item := session.current()
	var prompt := VocabPrompt.create({
		"item": item,
		"wallet": {"freeCharges": {}, "focus": 0, "costs": GameConfig.section("combat").hintFocusCost.duplicate()},
		"label": "Wiederholung" if session.round > 1 else "Karte",
		"hints": false,
	})
	prompt.finished.connect(_on_answer.bind(item), CONNECT_ONE_SHOT)
	add_child(prompt)


func _on_answer(out: Dictionary, item: Dictionary) -> void:
	if out.get("cancelled", false):
		return
	# Wie im Abenteuer: Statistik und Mastery fortschreiben und sofort speichern.
	var res: Dictionary = out.result.duplicate()
	res.firstTry = res.outcome == "correct" and int(res.hintsUsed) == 0 and not session.was_missed(item.key)
	Ctx.progress[item.key] = Vocab.record_answer(Ctx.progress.get(item.key), res, GameConfig.section("learning"), Vocab.now_ms())
	Ctx.profile.lastLearnedAt = Vocab.now_ms()
	Ctx.save_persistent()
	session.submit(out.result)
	next_card.call_deferred()


## Alle Karten geschafft: Tempelsplitter gutschreiben und Ergebnis zeigen.
func _finish() -> void:
	reward = TrainingSession.reward_for(session.items.size())
	Ctx.profile.shards = int(Ctx.profile.shards) + reward
	Ctx.profile.records.shardsTotal = int(Ctx.profile.records.get("shardsTotal", 0)) + reward
	Ctx.save_persistent()
	Ctx.profile_changed.emit()
	Sound.play("victory")
	var win := UI.window(640)
	var body: VBoxContainer = win.get_node("Body")
	var t := UI.label("🎉 Alle Vokabeln geschafft!", "H1")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(t)
	var lines := [
		["%d Wörter geübt" % session.items.size(), ""],
		["%d beim ersten Versuch richtig" % session.first_try, "Good"],
		["%d Fehler, alle nachgeholt" % session.wrong if session.wrong > 0 else "Kein einziger Fehler – großartig!", "Bad" if session.wrong > 0 else "Good"],
		["%s +%d %s" % [Meta.ICON, reward, Meta.CURRENCY], "Accent"],
	]
	for l: Array in lines:
		var lab := UI.label(l[0], l[1], 22)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(lab)
	body.add_child(UI.gap(8))
	var again := UI.button("Nochmal üben", func() -> void: TrainingScreen.start(get_tree(), unit_id))
	var back := UI.button("Zurück zum Titel", back_to_title)
	body.add_child(UI.hbox([UI.spacer(), again, back, UI.spacer()]))
	_result = win
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(win)
	add_child(center)
	UI.focus_later(back)


func ask_quit() -> void:
	if session.is_finished():
		back_to_title()
		return
	UI.confirm(self, "Training beenden? Dein Lernstand ist gespeichert, Tempelsplitter gibt es aber nur, wenn du alle Vokabeln schaffst.", back_to_title, "Beenden")


func back_to_title() -> void:
	Sound.play("select")
	get_tree().change_scene_to_file(TITLE)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k.pressed and not k.echo and k.keycode == KEY_ESCAPE and _result == null:
		get_viewport().set_input_as_handled()
		ask_quit()
