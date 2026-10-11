extends Node
## Autoload „UiTheme“: baut das Theme im Code (Vorlage: src/style.css der Phaser-Version)
## und setzt es auf das Hauptfenster. Dunkle JRPG-Fenster, Goldrand, Cinzel-Überschriften, Nunito-Text.

const WGHT := 2003265652  # OpenType-Tag „wght“

var theme: Theme
var font_text: FontVariation
var font_bold: FontVariation
var font_title: FontVariation


func _init() -> void:
	font_text = _variation("res://assets/fonts/Nunito.ttf", 500)
	font_bold = _variation("res://assets/fonts/Nunito.ttf", 750)
	font_title = _variation("res://assets/fonts/Cinzel.ttf", 700)
	theme = build()


func _ready() -> void:
	# In das Standard-Theme einmischen: so gilt es auch unter CanvasLayer- und 3D-Knoten,
	# wo die Theme-Vererbung vom Fenster aus endet.
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.fallback_font = font_text
	ThemeDB.fallback_font_size = 18
	get_tree().root.theme = theme


static func _variation(path: String, weight: int) -> FontVariation:
	var base: FontFile = load(path)
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {WGHT: weight}
	# Emojis (💰 🧪 ⚔) kommen aus der System-Schrift.
	var emoji := SystemFont.new()
	emoji.font_names = PackedStringArray(["Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji", "Segoe UI Symbol", "DejaVu Sans"])
	f.fallbacks = [emoji]
	return f


static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w: int = 0, radius: int = 5, pad := Vector4(10, 6, 10, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	return s


## Fenster: Verlauf ist im StyleBoxFlat nicht möglich – dunkle Mischfarbe plus Goldrand und Schatten.
static func window_box() -> StyleBoxFlat:
	var s := box(UI.WIN_BG, UI.GOLD, 1, 6, Vector4(18, 14, 18, 14))
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 6)
	s.expand_margin_left = 0
	return s


func build() -> Theme:
	var t := Theme.new()
	t.default_font = font_text
	t.default_font_size = 18

	# ---------- Label ----------
	t.set_color("font_color", "Label", UI.TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.65))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	for v: Array in [["Dim", UI.DIM], ["Accent", UI.ACCENT], ["Good", UI.GOOD], ["Bad", UI.BAD]]:
		t.add_type(v[0])
		t.set_type_variation(v[0], "Label")
		t.set_color("font_color", v[0], v[1])
	for v: Array in [["H1", 40], ["H2", 28], ["H3", 21]]:
		t.add_type(v[0])
		t.set_type_variation(v[0], "Label")
		t.set_font("font", v[0], font_title)
		t.set_font_size("font_size", v[0], v[1])
		t.set_color("font_color", v[0], UI.HEADING)
	t.add_type("TitleLogo")
	t.set_type_variation("TitleLogo", "Label")
	t.set_font("font", "TitleLogo", font_title)
	t.set_font_size("font_size", "TitleLogo", 64)
	t.set_color("font_color", "TitleLogo", UI.HEADING)
	t.set_color("font_outline_color", "TitleLogo", Color(0.12, 0.08, 0.02))
	t.set_constant("outline_size", "TitleLogo", 10)
	t.set_color("font_shadow_color", "TitleLogo", Color(0, 0, 0, 0.8))
	t.set_constant("shadow_offset_x", "TitleLogo", 0)
	t.set_constant("shadow_offset_y", "TitleLogo", 4)
	t.add_type("Bold")
	t.set_type_variation("Bold", "Label")
	t.set_font("font", "Bold", font_bold)

	# ---------- Fenster ----------
	t.set_stylebox("panel", "PanelContainer", window_box())
	t.set_stylebox("panel", "Panel", window_box())
	t.add_type("Card")
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(Color(1, 1, 1, 0.05), UI.GOLD_DARK, 1, 6, Vector4(10, 8, 10, 8)))
	t.add_type("CardSelected")
	t.set_type_variation("CardSelected", "PanelContainer")
	t.set_stylebox("panel", "CardSelected", box(Color(0.95, 0.79, 0.42, 0.12), UI.ACCENT, 1, 6, Vector4(10, 8, 10, 8)))
	t.add_type("Backdrop")
	t.set_type_variation("Backdrop", "Panel")
	t.set_stylebox("panel", "Backdrop", box(Color(0.02, 0.024, 0.05, 0.72), Color.TRANSPARENT, 0, 0, Vector4.ZERO))
	t.add_type("Toast")
	t.set_type_variation("Toast", "PanelContainer")
	t.set_stylebox("panel", "Toast", box(Color(0.06, 0.07, 0.06, 0.92), UI.GOLD, 1, 6, Vector4(16, 8, 16, 8)))

	# ---------- Buttons ----------
	_button_styles(t, "Button", Color("#3a3528").lerp(Color("#1c1a14"), 0.5), Vector4(18, 8, 18, 8), 18)
	t.set_font("font", "Button", font_bold)
	t.add_type("SmallButton")
	t.set_type_variation("SmallButton", "Button")
	_button_styles(t, "SmallButton", Color("#3a3528").lerp(Color("#1c1a14"), 0.5), Vector4(10, 4, 10, 4), 15)
	t.add_type("DangerButton")
	t.set_type_variation("DangerButton", "Button")
	_button_styles(t, "DangerButton", Color("#7a2e24").lerp(Color("#3e1410"), 0.5), Vector4(10, 4, 10, 4), 15)
	t.add_type("BigButton")
	t.set_type_variation("BigButton", "Button")
	_button_styles(t, "BigButton", Color("#3a3528").lerp(Color("#1c1a14"), 0.5), Vector4(26, 12, 26, 12), 24)
	t.add_type("CardButton")
	t.set_type_variation("CardButton", "Button")
	_button_styles(t, "CardButton", Color(1, 1, 1, 0.05), Vector4(12, 12, 12, 12), 16)

	# ---------- Eingaben ----------
	var input := box(Color(0.04, 0.05, 0.05, 0.9), UI.GOLD_DARK, 1, 5, Vector4(8, 5, 8, 5))
	var input_focus := box(Color(0.06, 0.07, 0.06, 0.95), UI.ACCENT, 1, 5, Vector4(8, 5, 8, 5))
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, input)
		t.set_stylebox("focus", type, input_focus)
		t.set_stylebox("read_only", type, input)
		t.set_color("font_color", type, UI.TEXT)
		t.set_color("font_placeholder_color", type, Color(UI.DIM, 0.6))
		t.set_color("caret_color", type, UI.ACCENT)
		t.set_color("selection_color", type, Color(UI.ACCENT, 0.35))
		t.set_font_size("font_size", type, 17)
	t.set_font("font", "TextEdit", font_text)
	t.add_type("CodeEdit")
	t.set_font_size("font_size", "CodeEdit", 15)

	for type in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", type, UI.TEXT)
		t.set_color("font_hover_color", type, UI.ACCENT)
		t.set_color("font_pressed_color", type, UI.TEXT)
		t.set_color("font_hover_pressed_color", type, UI.ACCENT)
		t.set_color("font_focus_color", type, UI.ACCENT)
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 2
		empty.content_margin_right = 2
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(st, type, empty)
		t.set_stylebox("focus", type, box(Color.TRANSPARENT, Color(UI.ACCENT, 0.5), 1, 4))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))

	_button_styles(t, "OptionButton", Color(0.04, 0.05, 0.05, 0.9), Vector4(10, 5, 30, 5), 16)
	t.set_font("font", "OptionButton", font_text)

	# ---------- Popups, Listen, Tabellen ----------
	t.set_stylebox("panel", "PopupMenu", box(Color(0.07, 0.08, 0.08, 0.98), UI.GOLD, 1, 4, Vector4(4, 4, 4, 4)))
	t.set_stylebox("hover", "PopupMenu", box(Color(UI.ACCENT, 0.2), Color.TRANSPARENT, 0, 3))
	t.set_color("font_color", "PopupMenu", UI.TEXT)
	t.set_color("font_hover_color", "PopupMenu", UI.ACCENT)
	t.set_stylebox("panel", "PopupPanel", box(Color(0.07, 0.08, 0.08, 0.98), UI.GOLD, 1, 4))
	t.set_stylebox("panel", "AcceptDialog", window_box())
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.06, 0.06, 0.96), UI.GOLD_DARK, 1, 4, Vector4(8, 4, 8, 4)))
	t.set_color("font_color", "TooltipLabel", UI.TEXT)

	var grabber := box(Color(UI.GOLD, 0.55), Color.TRANSPARENT, 0, 4, Vector4.ZERO)
	var grabber_hl := box(UI.ACCENT, Color.TRANSPARENT, 0, 4, Vector4.ZERO)
	var scroll_bg := box(Color(0, 0, 0, 0.3), Color.TRANSPARENT, 0, 4, Vector4(3, 3, 3, 3))
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, scroll_bg)
		t.set_stylebox("grabber", type, grabber)
		t.set_stylebox("grabber_highlight", type, grabber_hl)
		t.set_stylebox("grabber_pressed", type, grabber_hl)

	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.55), UI.GOLD_DARK, 1, 3, Vector4.ZERO))
	t.set_stylebox("fill", "ProgressBar", box(UI.ACCENT, Color.TRANSPARENT, 0, 3, Vector4.ZERO))

	t.add_type("RowError")
	t.set_type_variation("RowError", "PanelContainer")
	t.set_stylebox("panel", "RowError", box(Color(1.0, 0.35, 0.25, 0.14), Color.TRANSPARENT, 0, 3, Vector4(4, 2, 4, 2)))
	t.add_type("RowWarning")
	t.set_type_variation("RowWarning", "PanelContainer")
	t.set_stylebox("panel", "RowWarning", box(Color(0.95, 0.79, 0.42, 0.1), Color.TRANSPARENT, 0, 3, Vector4(4, 2, 4, 2)))
	t.add_type("RowPlain")
	t.set_type_variation("RowPlain", "PanelContainer")
	t.set_stylebox("panel", "RowPlain", box(Color(1, 1, 1, 0.02), Color.TRANSPARENT, 0, 3, Vector4(4, 2, 4, 2)))
	t.add_type("RowChecked")
	t.set_type_variation("RowChecked", "PanelContainer")
	t.set_stylebox("panel", "RowChecked", box(Color(0.95, 0.79, 0.42, 0.1), Color(UI.ACCENT, 0.4), 1, 4, Vector4(6, 3, 6, 3)))
	t.add_type("RowUnchecked")
	t.set_type_variation("RowUnchecked", "PanelContainer")
	t.set_stylebox("panel", "RowUnchecked", box(Color(1, 1, 1, 0.03), Color.TRANSPARENT, 1, 4, Vector4(6, 3, 6, 3)))

	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 6)
	return t


func _button_styles(t: Theme, type: String, base: Color, pad: Vector4, size: int) -> void:
	t.set_stylebox("normal", type, box(base, UI.GOLD, 1, 5, pad))
	var hover := box(Color("#5a4e30").lerp(Color("#2c2618"), 0.5), UI.GOLD, 1, 5, pad)
	hover.shadow_color = Color(UI.ACCENT, 0.3)
	hover.shadow_size = 8
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, box(Color("#2c2618"), UI.ACCENT, 1, 5, pad))
	t.set_stylebox("hover_pressed", type, hover)
	t.set_stylebox("disabled", type, box(Color(base, base.a * 0.45), Color(UI.GOLD, 0.35), 1, 5, pad))
	var focus := box(Color.TRANSPARENT, UI.ACCENT, 2, 6, pad)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	t.set_stylebox("focus", type, focus)
	t.set_color("font_color", type, UI.TEXT)
	t.set_color("font_hover_color", type, UI.ACCENT)
	t.set_color("font_pressed_color", type, UI.ACCENT)
	t.set_color("font_hover_pressed_color", type, UI.ACCENT)
	t.set_color("font_focus_color", type, UI.TEXT)
	t.set_color("font_disabled_color", type, Color(UI.TEXT, 0.45))
	t.set_color("font_outline_color", type, Color(0, 0, 0, 0.6))
	t.set_font_size("font_size", type, size)


## Kleine Checkbox im Goldstil, zur Laufzeit gezeichnet.
static func _check_icon(checked: bool) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var edge := x <= 1 or y <= 1 or x >= n - 2 or y >= n - 2
			if edge:
				img.set_pixel(x, y, UI.GOLD)
			elif checked and x >= 4 and y >= 4 and x <= n - 5 and y <= n - 5:
				img.set_pixel(x, y, UI.ACCENT)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0.55))
	return ImageTexture.create_from_image(img)
