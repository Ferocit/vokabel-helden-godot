class_name VocabPrompt
extends PanelContainer
## Gemeinsame Lernabfrage für Kampf, Truhen und Türen:
## deutsche Aufgabe → englische Eingabe → strenge Prüfung → bei Fehler Lösung zeigen und abtippen lassen.
## Kein Zeitlimit. Hilfen (Alt+1/Alt+2) kosten Fokus oder eine Gratis-Ladung.
## Ergebnis (Signal `finished`): { cancelled: bool, result: AnswerResult (falls nicht abgebrochen), wallet }

signal finished(outcome: Dictionary)
signal wallet_changed(wallet: Dictionary)

const HINT_TYPES: Array[String] = ["length", "firstLetter"]
const CORRECT_DELAY := 0.65
const CORRECTION_DELAY := 0.9

## Für Tests: Ergebnis sofort melden statt nach kurzer Anzeigezeit.
static var instant := false

var item: Dictionary
var entry: Dictionary
var wallet: Dictionary
var label_text := ""
var footer_text := ""
var allow_cancel := false
## Im Training gibt es keine Hilfen (kein Fokus, kein Kampf).
var show_hints := true
var phase := "answer"  # answer | correction | done
var hints: Dictionary

var input: LineEdit
var _body: VBoxContainer
var _mask: Label
var _length: Label
var _hint_bar: HBoxContainer
var _feedback: Label


## opts: { item, wallet, label, footer, allow_cancel, hints (Standard true) }
static func ask(parent: Node, opts: Dictionary) -> Dictionary:
	var p := create(opts)
	parent.add_child(p)
	return await p.finished


static func create(opts: Dictionary) -> VocabPrompt:
	var p := VocabPrompt.new()
	p.item = opts.item
	p.entry = opts.item.entry
	p.wallet = opts.wallet
	p.label_text = opts.get("label", "")
	p.footer_text = opts.get("footer", "")
	p.allow_cancel = opts.get("allow_cancel", false)
	p.show_hints = opts.get("hints", true)
	return p


func _ready() -> void:
	name = "VocabPrompt"
	hints = HintService.create_state()
	custom_minimum_size.x = 660
	resized.connect(_layout)
	var box := UI.vbox([], 6)
	add_child(box)
	var task := UI.label(("%s · Übersetze ins Englische" % label_text) if label_text != "" else "Übersetze ins Englische", "Dim", 16)
	task.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(task)
	var q := UI.label(entry.de, "Bold", 34)
	q.add_theme_color_override("font_color", UI.HEADING)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size.x = 620
	box.add_child(q)
	_body = UI.vbox([], 6)
	box.add_child(_body)
	input = LineEdit.new()
	input.name = "Answer"
	input.add_theme_font_size_override("font_size", 26)
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.custom_minimum_size.y = 50
	input.context_menu_enabled = false
	input.virtual_keyboard_enabled = true
	# Nach Enter weiter tippen können (sonst verlässt das Feld den Bearbeitungsmodus, und beim
	# Abtippen nach einem Fehler müsste man erst hineinklicken – Issue #6).
	input.keep_editing_on_text_submit = true
	input.text_submitted.connect(func(_t: String) -> void: _submit())
	_mask = UI.label("", "Accent", 28)
	_mask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_length = UI.label("", "Dim", 15)
	_length.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_bar = UI.hbox([], 8)
	_hint_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_feedback = UI.para("", "", 18)
	_feedback.custom_minimum_size.x = 620
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_render_answer_phase()
	_shrink.call_deferred()
	UI.focus_later(input)


## Nach Inhaltswechsel auf die nötige Höhe schrumpfen.
func _shrink() -> void:
	if is_inside_tree():
		reset_size()
		_layout()


## Waagerecht zentriert, 76 px unter dem oberen Rand.
func _layout() -> void:
	position = Vector2(roundf((get_viewport_rect().size.x - size.x) / 2.0), 76)


func _render_answer_phase() -> void:
	_detach_all()
	_body.add_child(_mask)
	_body.add_child(_length)
	_body.add_child(input)
	_body.add_child(_hint_bar)
	_body.add_child(_feedback)
	var footer := RichTextLabel.new()
	footer.bbcode_enabled = true
	footer.fit_content = true
	footer.scroll_active = false
	footer.add_theme_font_size_override("normal_font_size", 14)
	footer.add_theme_color_override("default_color", UI.DIM)
	footer.autowrap_mode = TextServer.AUTOWRAP_OFF
	var parts := ""
	if footer_text != "":
		parts += "[color=#f1c96b]%s[/color] · " % footer_text
	parts += "[color=#f1c96b]Enter[/color] bestätigen"
	if allow_cancel:
		parts += " · [color=#f1c96b]Esc[/color] abbrechen"
	footer.text = "[center]%s[/center]" % parts
	_body.add_child(footer)
	_render_hints()


## Eingabe & Co. bleiben erhalten; nur die übrigen Zeilen werden verworfen.
func _detach_all() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		if c not in [_mask, _length, input, _hint_bar, _feedback]:
			c.queue_free()


func _render_hints() -> void:
	_mask.text = HintService.render_mask(entry, hints)
	_mask.visible = _mask.text != ""
	_length.text = HintService.describe_length(entry) if hints.lengthShown else ""
	_length.visible = _length.text != ""
	UI.clear(_hint_bar)
	_hint_bar.visible = show_hints
	if not show_hints:
		return
	for i in HINT_TYPES.size():
		var type := HINT_TYPES[i]
		var pay := HintService.payment(wallet, type)
		var useful := HintService.is_useful(entry, hints, type)
		var cost := "gratis ×%d" % int(wallet.freeCharges.get(type, 0)) if pay.get("source") == "free" else "%d FP" % int(wallet.costs[type])
		var b := UI.button("💡 %s (%s)  Alt+%d" % [HintService.LABELS[type], cost, i + 1], use_hint.bind(type), "SmallButton")
		b.disabled = pay.is_empty() or not useful or phase != "answer"
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Hilfe verbraucht Fokus oder eine Gratis-Ladung"
		_hint_bar.add_child(b)


func use_hint(type: String) -> void:
	if not show_hints or phase != "answer" or not HintService.is_useful(entry, hints, type):
		return
	var paid := HintService.pay(wallet, type)
	if paid.is_empty():
		return
	wallet = paid
	hints = HintService.apply(entry, hints, type)
	Sound.play("hint")
	wallet_changed.emit(wallet)
	_render_hints()
	input.grab_focus()


func _submit() -> void:
	var value := input.text
	if value.strip_edges() == "":
		return
	if phase == "answer":
		_submit_answer(value)
	elif phase == "correction":
		_submit_correction(value)


func _submit_answer(value: String) -> void:
	if Vocab.is_correct_answer(entry, value):
		phase = "done"
		input.editable = false
		_set_input_state(true)
		_feedback.theme_type_variation = "Good"
		_feedback.text = "Richtig!" if not (hints.used as Array).is_empty() else "Richtig – ganz ohne Hilfe!"
		Sound.play("correct")
		_finish_later({"cancelled": false, "result": Vocab.result("correct", (hints.used as Array).size()), "wallet": wallet}, CORRECT_DELAY)
		return
	Sound.play("wrong")
	phase = "correction"
	_show_correction(value)


func _show_correction(wrong_input: String) -> void:
	_detach_all()
	var others := Vocab.accepted_answers(entry).slice(1)
	input.text = ""
	_set_input_state(false)
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.add_theme_font_size_override("normal_font_size", 20)
	info.add_theme_font_size_override("bold_font_size", 26)
	info.add_theme_font_override("bold_font", UiTheme.font_bold)
	info.add_theme_color_override("default_color", UI.TEXT)
	var t := "[center][color=#ffb38a]Noch nicht richtig.[/color]\n"
	t += "[font_size=17][color=#b9b29c]Deine Eingabe: [s]%s[/s][/color][/font_size]\n" % _escape(wrong_input.strip_edges())
	t += "%s → [b][color=#7dffa1]%s[/color][/b]\n" % [_escape(entry.de), _escape(entry.en)]
	if not others.is_empty():
		t += "[font_size=17][color=#b9b29c]Auch richtig: %s[/color][/font_size]\n" % _escape(", ".join(PackedStringArray(others)))
	t += "Tippe „%s“ einmal korrekt ein:[/center]" % _escape(entry.en)
	info.text = t
	info.custom_minimum_size.x = 620
	_body.add_child(info)
	_body.add_child(input)
	_feedback.text = ""
	_body.add_child(_feedback)
	var footer := UI.label("Enter bestätigen", "Dim", 14)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(footer)
	_shrink.call_deferred()
	_focus_input()


## Fokus ins Eingabefeld und sofort tippbereit (auch nachdem es kurz aus dem Baum genommen wurde).
func _focus_input() -> void:
	if not input.is_inside_tree():
		return
	input.grab_focus()
	input.edit()


static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")


func _submit_correction(value: String) -> void:
	# Abtippen: jede akzeptierte Lösung zählt, wie in der Browser-Version.
	if Vocab.is_correct_answer(entry, value):
		phase = "done"
		input.editable = false
		_set_input_state(true)
		_feedback.theme_type_variation = "Good"
		_feedback.text = "Gut abgeschrieben! Das Wort kommt bald noch einmal."
		_finish_later({"cancelled": false, "result": Vocab.result("wrongCorrected", (hints.used as Array).size()), "wallet": wallet}, CORRECTION_DELAY)
	else:
		_feedback.theme_type_variation = "Bad"
		_feedback.text = "Fast – schau noch einmal genau hin und tippe es exakt ab."
		input.select_all()


func _set_input_state(right: bool) -> void:
	var sb := UiTheme.box(Color(0.04, 0.05, 0.05, 0.9), UI.GOOD if right else UI.BAD, 2, 5, Vector4(8, 5, 8, 5))
	input.add_theme_stylebox_override("normal", sb)
	input.add_theme_stylebox_override("focus", sb)
	input.add_theme_stylebox_override("read_only", sb)


func _finish_later(outcome: Dictionary, delay: float) -> void:
	if instant or delay <= 0.0 or not is_inside_tree():
		_finish(outcome)
		return
	get_tree().create_timer(delay).timeout.connect(_finish.bind(outcome))


func _finish(outcome: Dictionary) -> void:
	phase = "done"
	finished.emit(outcome)
	queue_free()


func cancel() -> void:
	if allow_cancel and phase == "answer":
		_finish({"cancelled": true, "wallet": wallet})


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	# Hilfen: Alt+1, Alt+2 (Ziffern allein würden ins Eingabefeld geschrieben).
	if k.alt_pressed and phase == "answer":
		var idx := [KEY_1, KEY_2, KEY_3, KEY_4].find(k.keycode)
		if idx >= 0 and idx < HINT_TYPES.size():
			get_viewport().set_input_as_handled()
			use_hint(HINT_TYPES[idx])
			return
	if k.keycode == KEY_ESCAPE and allow_cancel and phase == "answer":
		get_viewport().set_input_as_handled()
		cancel()


## Klicks irgendwo im Fenster nehmen den Fokus nicht aus dem Eingabefeld.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and phase != "done":
		UI.focus_later(input)
