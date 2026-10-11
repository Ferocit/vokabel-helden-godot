class_name UI
extends RefCounted
## UI-Helfer: Farben und kleine Bausteine (Label, Button, Fenster, Modal, Bestätigung,
## Mastery-Balken, Toast), damit Szenen ihre Oberflächen kompakt im Code aufbauen können.

const TEXT := Color("#f6eedb")
const DIM := Color("#b9b29c")
const ACCENT := Color("#f1c96b")
const HEADING := Color("#f3dfb0")
const GOOD := Color("#7dffa1")
const BAD := Color("#ffb38a")
const HP := Color("#6ee07a")
const HP_LOW := Color("#ff7a6a")
const FP := Color("#6ec8ff")
const GOLD := Color("#c9a96a")
const GOLD_DARK := Color(0.788, 0.663, 0.416, 0.35)
const WIN_BG := Color(0.071, 0.086, 0.094, 0.97)
const RARITY := {"common": Color("#e8e2cf"), "uncommon": Color("#7dd8ff"), "rare": Color("#e3a8ff")}


static func label(text: String, variation: String = "", size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


## Mehrzeiliger Text mit Zeilenumbruch.
static func para(text: String, variation: String = "Dim", size: int = 16) -> Label:
	var l := label(text, variation, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, on_press: Callable = Callable(), variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if on_press.is_valid():
		b.pressed.connect(on_press)
	b.pressed.connect(func() -> void: _click())
	return b


static func _click() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var snd := tree.root.get_node_or_null("Sound") if tree else null
	if snd:
		snd.play("select", 0.35)


static func hbox(children: Array = [], separation: int = -1) -> HBoxContainer:
	var b := HBoxContainer.new()
	if separation >= 0:
		b.add_theme_constant_override("separation", separation)
	b.alignment = BoxContainer.ALIGNMENT_BEGIN
	for c: Variant in children:
		if c is Node:
			b.add_child(c)
	return b


static func vbox(children: Array = [], separation: int = -1) -> VBoxContainer:
	var b := VBoxContainer.new()
	if separation >= 0:
		b.add_theme_constant_override("separation", separation)
	for c: Variant in children:
		if c is Node:
			b.add_child(c)
	return b


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


## Fenster im JRPG-Stil mit fester Breite.
static func window(width: int = 0, children: Array = []) -> PanelContainer:
	var p := PanelContainer.new()
	if width > 0:
		p.custom_minimum_size.x = width
	var box := vbox(children)
	box.name = "Body"
	p.add_child(box)
	return p


## Vertikaler Scrollbereich mit fester Höhe.
static func scroll(child: Control, height: int) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.custom_minimum_size.y = height
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## Hängt `c` an `parent` und verankert es (z. B. PRESET_CENTER_BOTTOM) mit Versatz in Pixeln.
## Wachstumsrichtungen passend zum Anker, damit spätere Größenänderungen am Rand bleiben.
static func pin(parent: Node, c: Control, preset: Control.LayoutPreset, offset := Vector2.ZERO) -> Control:
	if c.get_parent() == null:
		parent.add_child(c)
	var right := preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_CENTER_RIGHT, Control.PRESET_BOTTOM_RIGHT]
	var center_x := preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER, Control.PRESET_CENTER_BOTTOM]
	var bottom := preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_CENTER_BOTTOM, Control.PRESET_BOTTOM_RIGHT]
	var center_y := preset in [Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER, Control.PRESET_CENTER_RIGHT]
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH if center_x else (Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BOTH if center_y else (Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.offset_left += offset.x
	c.offset_right += offset.x
	c.offset_top += offset.y
	c.offset_bottom += offset.y
	return c


## Fokus im nächsten Frame setzen (erst dann sind neu gebaute Controls im Baum).
static func focus_later(c: Control) -> void:
	var id := c.get_instance_id()
	(func() -> void:
		var node := instance_from_id(id) as Control
		if node != null and node.is_inside_tree() and node.is_visible_in_tree():
			node.grab_focus()).call_deferred()


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Tastenkappe, z. B. für Kurzbefehle 1–4: sieht wie eine Taste aus, damit man sie nicht für Text hält.
static func keycap(text: String, size: int = 16) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.name = "Keycap"
	var sb := UiTheme.box(Color("#2b2620"), GOLD, 1, 4, Vector4(7, 0, 7, 1))
	sb.border_width_bottom = 3
	cap.add_theme_stylebox_override("panel", sb)
	var l := label(text, "Bold", size)
	l.add_theme_color_override("font_color", ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(l)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cap


## Inhalt (Box) auf einen Knopf legen: füllt ihn mit Rand und lässt Klicks zum Knopf durch.
static func fill_button(b: Button, content: Control, margin := Vector4(10, 4, 10, 4)) -> void:
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = margin.x
	content.offset_top = margin.y
	content.offset_right = -margin.z
	content.offset_bottom = -margin.w
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in content.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(content)


## Auswahlkarte mit Tastenkappe (Segnungen, Talente): Symbol, Name, Wirkung, optional eine Zusatzzeile.
static func choice_card(key: int, icon_text: String, title: String, text: String, extra: String = "") -> Button:
	var btn := Button.new()
	btn.theme_type_variation = "CardButton"
	# Der Inhalt liegt über dem Knopf und lässt ihn nicht mitwachsen: Höhe reicht für zwei Zeilen Wirkung.
	btn.custom_minimum_size = Vector2(270, 210 if extra != "" else 190)
	var icon_l := label(icon_text, "", 34)
	icon_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_l := label(title, "Bold", 20)
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var text_l := para(text, "", 16)
	text_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var box := vbox([keycap(str(key), 18), icon_l, title_l, text_l], 6)
	if extra != "":
		var extra_l := label(extra, "Dim", 14)
		extra_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(extra_l)
	fill_button(btn, box, Vector4(12, 10, 12, 10))
	return btn


## Kenney-Sprite als skalierte Pixelgrafik.
static func sprite(frame_no: int, px: int = 40) -> TextureRect:
	return icon(Assets.frame(frame_no), px)


## Beliebige Pixelgrafik (z. B. Assets.item_icon) als skaliertes, scharfes Symbol.
static func icon(tex: Texture2D, px: int = 40) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## Mastery als kleiner Balken (0..1), Farbe von rot nach grün; Tooltip mit Prozent und Einstufung.
static func mastery_bar(value: float, width: int = 90) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.tooltip_text = "%d %% – %s" % [roundi(value * 100.0), Vocab.mastery_label(value)]
	var fill := StyleBoxFlat.new()
	fill.bg_color = HP_LOW.lerp(Color("#f1c96b"), clampf(value * 2.0, 0.0, 1.0)).lerp(HP, clampf(value * 2.0 - 1.0, 0.0, 1.0))
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


static func format_date(ms: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(ms / 1000.0) + _tz_offset_s())
	return "%02d.%02d.%04d" % [d.day, d.month, d.year]


static func format_date_time(ms: Variant) -> String:
	if ms == null or int(ms) <= 0:
		return "–"
	var d := Time.get_datetime_dict_from_unix_time(int(int(ms) / 1000.0) + _tz_offset_s())
	return "%02d.%02d. %02d:%02d" % [d.day, d.month, d.hour, d.minute]


static func _tz_offset_s() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


static func signed(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)


## Kurze Meldung am unteren Bildschirmrand.
static func toast(parent: Node, text: String, seconds: float = 2.4) -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = "Toast"
	p.add_child(label(text, "", 18))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pin(parent, p, Control.PRESET_CENTER_BOTTOM, Vector2(0, -70))
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(seconds)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


## Modales Fenster: halbtransparenter Hintergrund, mittiges Fenster mit Titelzeile.
## Esc oder Klick auf den Hintergrund schließt es (nur das oberste Modal reagiert).
static func modal(parent: Node, title: String, width: int = 900, closable: bool = true) -> Modal:
	var m := Modal.new()
	m.setup(title, width, closable)
	parent.add_child(m)
	return m


## Ja/Nein-Abfrage im Spielstil (ersetzt window.confirm).
static func confirm(parent: Node, text: String, on_yes: Callable, yes_text: String = "Ja", no_text: String = "Abbrechen") -> Modal:
	var m := modal(parent, "Bitte bestätigen", 520, true)
	m.body.add_child(para(text, "", 18))
	m.body.add_child(gap(8))
	var yes := button(yes_text, func() -> void:
		m.close()
		on_yes.call())
	var no := button(no_text, m.close)
	var row := hbox([spacer(), no, yes])
	m.body.add_child(row)
	UI.focus_later(yes)
	return m


class Modal extends Control:
	signal closed

	static var _stack: Array[Modal] = []

	var body: VBoxContainer
	var header: HBoxContainer
	var win: PanelContainer
	var closable := true

	func setup(title: String, width: int, can_close: bool) -> void:
		closable = can_close
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var bd := Panel.new()
		bd.theme_type_variation = "Backdrop"
		bd.set_anchors_preset(Control.PRESET_FULL_RECT)
		bd.gui_input.connect(func(e: InputEvent) -> void:
			if closable and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				close())
		add_child(bd)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		win = PanelContainer.new()
		win.custom_minimum_size.x = width
		center.add_child(win)
		var outer := VBoxContainer.new()
		win.add_child(outer)
		header = HBoxContainer.new()
		if title != "":
			header.add_child(UI.label(title, "H2"))
		header.add_child(UI.spacer())
		if can_close:
			header.add_child(UI.button("Schließen", close))
		outer.add_child(header)
		body = VBoxContainer.new()
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(body)

	func _enter_tree() -> void:
		_stack.append(self)

	func _exit_tree() -> void:
		_stack.erase(self)

	func is_top() -> bool:
		return not _stack.is_empty() and _stack.back() == self

	func _unhandled_key_input(event: InputEvent) -> void:
		if closable and is_top() and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()

	func close() -> void:
		if is_queued_for_deletion():
			return
		closed.emit()
		queue_free()
