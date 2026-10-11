class_name Hud
extends PanelContainer
## Statuszeile oben links: HP, Fokus, Runen, Tränke, Gold, Level, Lernabfragen, in der Zeit-Challenge die Restzeit.


func _ready() -> void:
	name = "Hud"
	position = Vector2(12, 12)
	refresh()


static func bar(value: float, max_value: float, color: Color, width: int = 130, height: int = 14) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = maxf(1.0, max_value)
	b.value = clampf(value, 0.0, max_value)
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, height)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("background", UiTheme.box(Color("#11120e"), UI.GOLD, 1, height / 2, Vector4.ZERO))
	b.add_theme_stylebox_override("fill", UiTheme.box(color, Color.TRANSPARENT, 0, height / 2, Vector4.ZERO))
	return b


## Runen als kleine Rauten; gesammelte leuchten golden.
static func runes(have: int, total: int) -> HBoxContainer:
	var box := UI.hbox([], 2)
	box.tooltip_text = "Runen öffnen das Siegeltor zum Boss"
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in total:
		var l := UI.label("◆" if i < have else "◇", "Accent" if i < have else "Dim", 20)
		if i < have:
			l.add_theme_color_override("font_shadow_color", Color(1, 0.84, 0.37, 0.7))
		box.add_child(l)
	return box


func refresh() -> void:
	if not Ctx.has_run():
		return
	var run: Dictionary = Ctx.run
	var s := Ctx.stats()
	UI.clear(self)
	var hp_low := float(run.hp) / float(s.maxHp) < 0.3
	var learning: LearningSession = run.learning
	var q := UI.label("📖 %d" % int(learning.run.questions), "Dim", 18)
	q.tooltip_text = "Lernabfragen in diesem Abenteuer"
	q.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(UI.hbox([
		UI.label("HP", "Bold", 18), bar(run.hp, s.maxHp, UI.HP_LOW if hp_low else UI.HP), UI.label("%d/%d" % [int(run.hp), int(s.maxHp)], "Bold", 18),
		UI.gap(0), UI.label("FP", "Bold", 18), bar(run.focus, s.maxFocus, UI.FP), UI.label("%d/%d" % [int(run.focus), int(s.maxFocus)], "Bold", 18),
		UI.gap(0), runes(int(run.runes), int(run.bossRunes)),
		UI.gap(0), _lives(),
		UI.label("🔥 %d" % int(run.get("heat", 0)), "Bad", 18) if int(run.get("heat", 0)) > 0 else null,
		UI.label("🧪 %d" % int(Ctx.profile.potions), "Bold", 18),
		UI.label("💰 %d" % int(Ctx.profile.gold), "Bold", 18),
		UI.label("Lv %d" % int(Ctx.profile.level), "Accent", 18),
		xp_bar(),
		q,
		Clock.new() if run.get("timeChallenge", false) else null,
	], 10))
	reset_size()


## Fortschritt zum nächsten Level (Issue #9); auf dem Höchstlevel voll.
static func xp_bar(width: int = 80) -> ProgressBar:
	var p: Dictionary = Ctx.profile
	var cfg := GameConfig.section("player")
	var next := Player.xp_for_next_level(int(p.level), cfg)
	var prev: int = int((cfg.xpPerLevel as Array)[int(p.level) - 1])
	var b := bar(int(p.xp) - prev, maxi(1, next - prev) if next >= 0 else 1, UI.ACCENT, width, 10)
	if next < 0:
		b.value = b.max_value
	b.name = "XpBar"
	b.tooltip_text = "XP %d / %d – noch %d bis Level %d" % [int(p.xp), next, next - int(p.xp), int(p.level) + 1] if next >= 0 else "Höchstes Level erreicht"
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	return b


## Verbleibende Leben dieses Abenteuers; die letzte Niederlage beendet es.
static func _lives() -> Label:
	var n := int(Ctx.profile.get("lives", 0))
	var l := UI.label("❤ %d" % n, "Bad" if n <= 1 else "Bold", 18)
	l.tooltip_text = "Leben: Bei 0 endet das Abenteuer."
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


static func format_time(seconds: float) -> String:
	var s := ceili(maxf(0.0, seconds))
	return "%d:%02d" % [s / 60, s % 60]


## Restzeit der Zeit-Challenge; aktualisiert sich selbst und wird in der letzten Minute rot.
class Clock extends Label:
	func _init() -> void:
		theme_type_variation = "Bold"
		add_theme_font_size_override("font_size", 18)
		tooltip_text = "Zeit-Challenge: Restzeit für das ganze Abenteuer"
		mouse_filter = Control.MOUSE_FILTER_PASS
		_update()

	func _process(_delta: float) -> void:
		_update()

	func _update() -> void:
		if not Ctx.has_run():
			return
		var left := float(Ctx.run.get("timeLeft", 0.0))
		text = "⏱ " + Hud.format_time(left)
		var urgent := left < 60.0
		add_theme_color_override("font_color", UI.HP_LOW if urgent else UI.TEXT)
		modulate.a = 0.55 + 0.45 * absf(cos(Time.get_ticks_msec() / 300.0)) if urgent and left > 0.0 else 1.0
