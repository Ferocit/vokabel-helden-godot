class_name SettingsView
extends RefCounted
## Einstellungen: Ton an/aus, Lautstärke, Vollbild. Werden in Ctx.settings gespeichert und beim Start angewendet.


## Gespeicherte Einstellungen auf Audio und Fenster anwenden.
static func apply() -> void:
	var s: Dictionary = Ctx.settings
	Sound.enabled = bool(s.get("sound", true))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(s.get("volume", 0.8)))))
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(s.get("fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)


static func _changed() -> void:
	apply()
	Ctx.save_persistent()


static func render(container: Control) -> void:
	UI.clear(container)
	var s: Dictionary = Ctx.settings
	var sound := CheckBox.new()
	sound.text = "Ton an"
	sound.button_pressed = bool(s.get("sound", true))
	sound.toggled.connect(func(on: bool) -> void:
		Ctx.settings.sound = on
		_changed())
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(s.get("volume", 0.8))
	vol.custom_minimum_size.x = 260
	vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vol_label := UI.label("%d %%" % roundi(vol.value * 100.0), "", 17)
	vol.value_changed.connect(func(v: float) -> void:
		Ctx.settings.volume = v
		vol_label.text = "%d %%" % roundi(v * 100.0)
		_changed())
	vol.drag_ended.connect(func(_c: bool) -> void: Sound.play("select"))
	var full := CheckBox.new()
	full.text = "Vollbild"
	full.button_pressed = bool(s.get("fullscreen", false))
	full.toggled.connect(func(on: bool) -> void:
		Ctx.settings.fullscreen = on
		_changed())
	container.add_child(sound)
	container.add_child(UI.hbox([UI.label("Lautstärke", "", 17), vol, vol_label], 12))
	container.add_child(full)
	container.add_child(UI.gap(6))
	container.add_child(UI.para("Steuerung: WASD/Pfeiltasten oder Controller (Stick/Steuerkreuz) · E/Enter/Leertaste bzw. A-Knopf interagieren · Esc bzw. Start öffnet das Menü · Alt+1/Alt+2 Hilfen · F8 etwas melden.", "Dim", 15))
