extends Node3D
## Rundenbasierter Kampf im Stil klassischer JRPGs, in HD-2D-Optik und ohne Zeitdruck pro Zug
## (nur in der Zeit-Challenge läuft eine Uhr für das ganze Abenteuer).
## Jede Aktion verlangt eine richtig erinnerte Vokabel. Gegner kündigen ihre nächste Aktion an.
## Wird von der Erkundung erzeugt: `object_id` setzen, Signal `finished(data)` abwarten.

signal finished(data: Dictionary)
signal command_chosen(action: String)
signal result_closed
signal blessing_chosen(id: String)

const COMMANDS: Array[String] = ["attack", "defend", "skill", "item"]
const HERO_POS := Vector3(7.2, 0, 6.6)
const ENEMY_POS := Vector3(14.8, 0, 6.6)
## Richtung vom Helden zum Gegner auf der x-Achse (Held links, Gegner rechts).
const TOWARD_ENEMY := 1.0 if ENEMY_POS.x > HERO_POS.x else -1.0
const ARENA_W := 22
const ARENA_H := 12

## Für Tests: keine Wartezeiten, Ablauf läuft synchron bis zur nächsten Eingabe.
static var fast := false

var object_id := ""
var run: Dictionary
var obj: Dictionary
var def: Dictionary
var cls: Dictionary
var state: Dictionary
var wallet: Dictionary
var rng: Callable

var fx: WorldFx
var arena: LevelBuilder
var hero: Sprite3D
var enemy: Sprite3D
var enemy_root: Node3D
var enemy_height := 2.0
var weapon: HeldWeapon
var _shield: MeshInstance3D

var ui: CanvasLayer
var _msg: Label
var _enemy_panel: VBoxContainer
var _command_panel: VBoxContainer
var _party_panel: VBoxContainer
var _intent: PanelContainer
var _intent_label: Label
var _flash_rect: ColorRect
var _menu_active := false
var _command_buttons: Array[Button] = []
## Erklärt den gerade gewählten Befehl (Issue #7).
var _command_info: Label


func _ready() -> void:
	name = "Combat"
	run = Ctx.run
	for o: Dictionary in run.map.objects:
		if o.id == object_id:
			obj = o
	def = GameData.get_enemy(obj.enemyId)
	cls = Ctx.hero_class()
	rng = run.rng
	state = CombatService.create_combat(Ctx.combat_player(), CombatService.create_enemy(def, int(Ctx.profile.level), rng, int(run.get("heat", 0))))
	wallet = Ctx.hint_wallet(int(state.player.focus))
	Ctx.set_bonus_reached.connect(_on_set_bonus)
	_build_arena()
	_build_combatants()
	_build_ui()
	refresh_panels()
	_fade(1.0, 0.0, 0.3)
	battle_loop()


func _sleep(seconds: float) -> void:
	if fast or not is_inside_tree():
		return
	await get_tree().create_timer(seconds).timeout


# ---------- Darstellung ----------

## Tempelhalle aus denselben Pixel-Kacheln wie die Erkundung, mit warmem Licht.
func _build_arena() -> void:
	var tiles := PackedInt32Array()
	tiles.resize(ARENA_W * ARENA_H)
	var room := {"id": 0, "x": 1, "y": 4, "w": ARENA_W - 2, "h": 5}
	for y in range(room.y, room.y + room.h):
		for x in range(room.x, room.x + room.w):
			tiles[y * ARENA_W + x] = MapModel.FLOOR
	var map := {
		"seed": int(run.seed) + int(obj.x) * 31 + int(obj.y), "width": ARENA_W, "height": ARENA_H, "tiles": tiles,
		"rooms": [room], "startRoomId": 0, "bossRoomId": 0, "start": Vector2i(-50, -50), "objects": [],
	}
	arena = LevelBuilder.build(map)
	add_child(arena.root)
	# Die Fackeln stehen in der Halle dicht beieinander – etwas gedämpfter als in der Erkundung.
	for l in arena.root.find_children("*", "OmniLight3D", true, false):
		if l is Fx.Flicker:
			(l as Fx.Flicker).base_energy *= 0.55
	fx = WorldFx.new(0.8)
	fx.pitch = 24.0
	fx.distance = 12.5
	fx.look_height = 1.1
	fx.target = Vector3(11.0, 0, 6.6)
	add_child(fx)
	# Fülllicht von vorn, damit die Kämpfer nicht nur von den Fackeln im Rücken beleuchtet werden.
	var fill := OmniLight3D.new()
	fill.light_color = Color("#fff0d8")
	fill.light_energy = 1.1
	fill.omni_range = 12.0
	fill.position = Vector3(11.0, 3.5, 11.0)
	add_child(fill)
	fx.snap()


func _build_combatants() -> void:
	var scale := 3.0 if def.tier == "boss" else (2.5 if def.tier == "elite" else 2.0)
	enemy_height = scale
	enemy_root = Node3D.new()
	enemy_root.position = ENEMY_POS
	enemy_root.add_child(Fx.shadow_quad(scale * 0.8))
	enemy = Fx.sprite(Assets.frame(int(def.frame)), 16.0 / scale)
	# Die Pixel-Art schaut nach rechts; der Gegner soll den Helden ansehen.
	enemy.flip_h = TOWARD_ENEMY > 0.0
	var bob := Fx.Bob.new()
	bob.amplitude = 0.1
	bob.period = 1.8
	enemy.add_child(bob)
	enemy_root.add_child(enemy)
	if def.tier != "normal":
		enemy_root.add_child(LevelBuilder._light(Color("#ff5040") if def.tier == "boss" else Color("#ffb030"), 0.7, scale * 1.6, Vector3(0, 0.3, -0.6)))
	add_child(enemy_root)
	if def.tier == "boss":
		_shake(0.3, 0.1)

	var hero_root := Node3D.new()
	hero_root.position = HERO_POS
	hero_root.add_child(Fx.shadow_quad(1.6))
	hero = Fx.sprite(Assets.frame(int(cls.frame)), 8.0)
	hero.flip_h = TOWARD_ENEMY < 0.0
	hero_root.add_child(hero)
	weapon = HeldWeapon.equip(hero, Ctx.profile.equipment.get("weapon"))
	var light := OmniLight3D.new()
	light.light_color = Color("#ffe2a8")
	light.light_energy = 0.8
	light.omni_range = 4.5
	light.position = Vector3(0, 2.2, 1.2)
	hero_root.add_child(light)
	add_child(hero_root)


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var top := PanelContainer.new()
	top.custom_minimum_size = Vector2(900, 56)
	_msg = UI.label("", "", 22)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_msg)
	UI.pin(ui, top, Control.PRESET_CENTER_TOP, Vector2(0, 14))
	if run.get("timeChallenge", false):
		var clock := PanelContainer.new()
		clock.add_child(Hud.Clock.new())
		UI.pin(ui, clock, Control.PRESET_TOP_LEFT, Vector2(14, 14))

	_intent = PanelContainer.new()
	_intent_label = UI.label("", "Bold", 18)
	_intent.add_child(_intent_label)
	_intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_intent)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -54
	bottom.offset_top = -262
	bottom.offset_bottom = -14
	ui.add_child(bottom)
	# Wie in der Arena: Held und seine Anzeige links, Gegner rechts.
	_party_panel = _panel(bottom, 0)
	_command_panel = _panel(bottom, 330)
	_enemy_panel = _panel(bottom, 330)

	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(0, 0, 0, 0)
	ui.add_child(_flash_rect)


static func _panel(parent: Control, width: int) -> VBoxContainer:
	var p := PanelContainer.new()
	if width > 0:
		p.custom_minimum_size.x = width
	else:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UI.vbox([], 4)
	p.add_child(box)
	parent.add_child(p)
	return box


func _process(_delta: float) -> void:
	# Absichtsanzeige schwebt über dem Gegner.
	if _intent and fx and fx.camera.is_inside_tree():
		var top := enemy_root.global_position + Vector3(0, enemy_height + 0.45, 0)
		var p := fx.camera.unproject_position(top)
		_intent.reset_size()
		_intent.position = p - Vector2(_intent.size.x / 2.0, _intent.size.y) + Vector2(0, sin(Time.get_ticks_msec() / 400.0) * 3.0)


func refresh_panels() -> void:
	var e: Dictionary = state.enemy
	var p: Dictionary = state.player
	var tier_label := "Boss" if def.tier == "boss" else ("Elite" if def.tier == "elite" else "")
	var intent: Dictionary = GameData.ENEMY_MOVES[e.intent]
	var status: Array[String] = []
	if e.poison != null:
		status.append("☠️ Gift (%d)" % int(e.poison.turns))
	if e.guarding:
		status.append("🛡️ gepanzert")
	if int(e.phase) == 2:
		status.append("🔥 wütend")
	UI.clear(_enemy_panel)
	var title := UI.hbox([UI.label(def.name, "Bold", 24)])
	if tier_label != "":
		title.add_child(UI.label(tier_label, "Accent", 16))
	_enemy_panel.add_child(title)
	_enemy_panel.add_child(UI.label("HP %d/%d" % [int(e.hp), int(e.maxHp)], "Bold", 18))
	var bar := Hud.bar(e.hp, e.maxHp, Color("#e8785a"), 300, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_panel.add_child(bar)
	_enemy_panel.add_child(UI.hbox([UI.label("Als Nächstes:", "Dim", 17), UI.label("%s %s" % [intent.icon, intent.name], "Bold", 17)], 6))
	_enemy_panel.add_child(UI.para(intent.hint, "Dim", 14))
	if not status.is_empty():
		_enemy_panel.add_child(UI.label(" · ".join(status), "", 15))

	_intent_label.text = "%s %s" % [intent.icon, intent.name]
	var border := {"heavy": Color("#ff6a4a"), "charge": Color("#ffb04a"), "guard": Color("#8ac8ff"), "regenerate": Color("#7dffa1")}
	var text_c := {"heavy": Color("#ffb39a"), "charge": Color("#ffd79a"), "guard": Color("#c8e6ff"), "regenerate": Color("#c8ffd6")}
	var sb := UiTheme.box(Color(0.055, 0.047, 0.04, 0.85), border.get(intent.id, UI.GOLD), 1, 14, Vector4(12, 4, 12, 4))
	if intent.id == "heavy":
		sb.shadow_color = Color(1, 0.35, 0.24, 0.6)
		sb.shadow_size = 10
	_intent.add_theme_stylebox_override("panel", sb)
	_intent_label.add_theme_color_override("font_color", text_c.get(intent.id, UI.TEXT))

	UI.clear(_party_panel)
	var hp_low := float(p.hp) / float(p.maxHp) < 0.3
	var hp_box := UI.vbox([UI.label("HP %d/%d" % [int(p.hp), int(p.maxHp)], "Bold", 20), Hud.bar(p.hp, p.maxHp, UI.HP_LOW if hp_low else UI.HP, 180)], 2)
	var fp_box := UI.vbox([UI.label("FP %d/%d" % [int(p.focus), int(p.maxFocus)], "Bold", 20), Hud.bar(p.focus, p.maxFocus, UI.FP, 180)], 2)
	var name_l := UI.label(cls.name, "Bold", 22)
	name_l.custom_minimum_size.x = 110
	_party_panel.add_child(UI.hbox([name_l, hp_box, fp_box], 14))
	var potions := UI.hbox([UI.label("🧪 Heiltränke: %d" % int(p.potions), "Dim", 16)])
	if state.defending:
		potions.add_child(UI.label("· 🛡 verteidigt", "Accent", 16))
	var combo := int(run.get("combo", 0))
	p.comboMult = Combo.multiplier(combo)
	if combo > 0:
		var cl := UI.label("· %s Kombo %d" % [Combo.text(combo), combo], "Accent", 16)
		cl.tooltip_text = "Richtige Antworten in Folge (ohne Hilfe) machen Angriffe stärker. Ein Fehler setzt die Kombo zurück."
		cl.mouse_filter = Control.MOUSE_FILTER_PASS
		potions.add_child(cl)
	_party_panel.add_child(UI.gap(6))
	_party_panel.add_child(potions)
	_party_panel.add_child(UI.para("%s: %s" % [cls.passiveName, cls.passiveDescription], "Dim", 14))


func say(text: String) -> void:
	_msg.text = text


# ---------- Ablauf ----------

func battle_loop() -> void:
	await _sleep(0.3)
	say("Boss: %s versperrt dir den Weg!" % def.name if def.tier == "boss" else "%s taucht auf!" % def.name)
	await _sleep(0.9)
	var learning: LearningSession = run.learning
	while state.outcome == "ongoing":
		if Ctx.time_up():
			break
		var action: String = await choose_command()
		var label := CombatService.action_label(action, state.player)
		var mode: String = def.selection
		say("%s: Erinnere dich an das englische Wort!" % label)
		_intent.visible = false
		var item := learning.next_word(mode)
		var prompt := VocabPrompt.create({"item": item, "wallet": wallet, "label": label})
		prompt.wallet_changed.connect(func(w: Dictionary) -> void:
			state.player.focus = int(w.focus)
			refresh_panels())
		ui.add_child(prompt)
		var out: Dictionary = await prompt.finished
		_intent.visible = true
		wallet = out.wallet
		state.player.focus = int(wallet.focus)
		# Rache des Gelehrten: War das Wort in diesem Abenteuer schon einmal falsch?
		var was_missed: bool = learning.scheduler.wrong_in_run.has(item.key)
		var levels := Ctx.submit_answer(item, out.result)
		if levels > 0:
			_on_level_up()
		var outcome: String = out.result.outcome
		state.player.combo = int(run.get("combo", 0))
		state.player.revengeWord = was_missed and outcome == "correct"
		var power := float(GameConfig.section("combat").almostPower) if outcome == "almostCorrect" else 1.0
		state.player.comboMult = Combo.multiplier(int(run.get("combo", 0)))
		var events := CombatService.resolve_player_action(state, action, outcome != "wrongCorrected", GameConfig.section("combat"), rng, power)
		wallet.focus = int(state.player.focus)
		await play_events(events, action)
		if state.outcome != "ongoing":
			break
		await _sleep(0.35)
		await play_events(CombatService.resolve_enemy_turn(state, rng), "")
		_clear_shield()
		refresh_panels()
	_intent.visible = false
	if state.outcome == "won":
		await victory()
	elif state.outcome == "ongoing":
		await time_over()
	else:
		await defeat()


func choose_command() -> String:
	var intent: Dictionary = GameData.ENEMY_MOVES[state.enemy.intent]
	say("Was tust du? %s plant: %s %s" % [def.name, intent.icon, intent.name])
	UI.clear(_command_panel)
	_command_buttons.clear()
	for i in COMMANDS.size():
		var action := COMMANDS[i]
		var meta := ""
		if action == "skill":
			meta = "   %d FP" % int(state.player.skill.focusCost)
		elif action == "item":
			meta = "   ×%d" % int(state.player.potions)
		var b := Button.new()
		b.theme_type_variation = "SmallButton"
		b.custom_minimum_size.y = 38
		var name := UI.label(CombatService.action_label(action, state.player), "Bold", 19)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.fill_button(b, UI.hbox([UI.keycap(str(i + 1)), name, UI.label(meta.strip_edges(), "Dim", 17)], 10), Vector4(8, 3, 12, 3))
		b.modulate = Color.WHITE if CombatService.can_use_action(state, action) else Color(1, 1, 1, 0.45)
		var effect := CombatService.action_effect(action, state, GameConfig.section("combat"))
		b.tooltip_text = effect
		b.focus_entered.connect(func() -> void: _command_info.text = effect)
		b.pressed.connect(choose.bind(i))
		b.mouse_entered.connect(b.grab_focus)
		_command_buttons.append(b)
		_command_panel.add_child(b)
	_command_info = UI.para("", "", 14)
	_command_info.custom_minimum_size = Vector2(300, 40)
	_command_panel.add_child(_command_info)
	_command_panel.add_child(UI.label("Tasten 1–4 · ↑↓ + Enter · falsche Vokabel: Aktion verpufft", "Dim", 13))
	_menu_active = false
	# Verzögert aktivieren, damit das Enter der vorherigen Eingabe nicht sofort einen Befehl auslöst.
	if fast:
		_menu_active = true
	else:
		_later(0.12, func() -> void: _menu_active = true)
	UI.focus_later(_command_buttons[0])
	return await command_chosen


func choose(i: int) -> void:
	if not _menu_active or i < 0 or i >= COMMANDS.size():
		return
	var action := COMMANDS[i]
	if not CombatService.can_use_action(state, action):
		Sound.play("wrong")
		say("Dafür hast du nicht genug Fokus." if action == "skill" else "Du hast keinen Heiltrank oder volle HP.")
		return
	_menu_active = false
	Sound.play("select")
	UI.clear(_command_panel)
	_command_buttons.clear()
	_command_panel.add_child(UI.label("▶ %s" % CombatService.action_label(action, state.player), "Dim", 18))
	command_chosen.emit(action)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if _menu_active:
		var idx := [KEY_1, KEY_2, KEY_3, KEY_4].find(k.keycode)
		if idx < 0:
			idx = [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4].find(k.keycode)
		if idx >= 0:
			get_viewport().set_input_as_handled()
			choose(idx)
			return
		# W/S wie ↑/↓
		var focus := get_viewport().gui_get_focus_owner()
		var cur := _command_buttons.find(focus)
		if k.physical_keycode in [KEY_W, KEY_S] and not _command_buttons.is_empty():
			var n := _command_buttons.size()
			var next := (maxi(cur, 0) + (1 if k.physical_keycode == KEY_S else n - 1)) % n
			_command_buttons[next].grab_focus()
			Sound.play("select", 0.3)
			get_viewport().set_input_as_handled()
	elif _blessing_modal != null and k.keycode in [KEY_1, KEY_2, KEY_3]:
		get_viewport().set_input_as_handled()
		choose_blessing([KEY_1, KEY_2, KEY_3].find(k.keycode))
	elif _result_open and k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E]:
		get_viewport().set_input_as_handled()
		close_result()


func play_events(events: Array, action: String) -> void:
	for ev: Dictionary in events:
		match ev.type:
			"fizzle":
				say("„%s“ verpufft – das Wort kommt bald noch einmal." % CombatService.action_label(ev.action, state.player))
				_burst(hero_pos(1.4), Color("#bfc4d8"), 10, 1.2, false)
				await _sleep(1.1)
			"weak":
				say("Fast richtig – „%s“ wirkt nur halb so stark." % CombatService.action_label(ev.action, state.player))
				await _sleep(0.8)
			"chain":
				say("⚡ Kettenblitz! Kombo %d – doppelter Schaden!" % int(run.get("combo", 0)))
				_burst(hero_pos(1.4), Color("#ffe066"), 14, 1.4, true)
				await _sleep(0.7)
			"revenge":
				say("📜 Rache des Gelehrten! Das Wort sitzt jetzt – mehr Schaden!")
				await _sleep(0.7)
			"damage":
				if ev.target == "enemy":
					var skill := action == "skill"
					var nm: String = state.player.skill.name if skill else "Treffer"
					var mult := float(state.player.get("comboMult", 1.0))
					var combo_txt := " %s Kombo!" % Combo.text(int(run.get("combo", 0))) if mult > 1.0 else ""
					say("%s! %d Schaden%s%s%s" % [nm, int(ev.amount), " – kritischer Treffer!" if ev.crit else ".", " (halbiert durch Panzer)" if ev.guarded else "", combo_txt])
					await hero_attack(skill, ev.crit)
					Sound.play("hit")
					_flash_sprite(enemy)
					if skill or ev.crit:
						_shake(0.22, 0.12)
					_damage_number(enemy_pos(enemy_height), str(int(ev.amount)) + ("!" if ev.crit else ""), Color("#ff9cff") if ev.crit else (Color("#ffd75e") if skill else Color.WHITE))
				else:
					Sound.play("hurt")
					_flash_sprite(hero)
					_shake(0.16, 0.06)
					_damage_number(hero_pos(2.2) + Vector3(randf_range(-0.3, 0.3), 0, 0), str(int(ev.amount)), Color("#ff9a8a"))
					say("Geblockt! Nur %d Schaden." % int(ev.amount) if ev.blocked else "Du erleidest %d Schaden." % int(ev.amount))
				refresh_panels()
				await _sleep(0.65)
			"poisoned":
				say("Gift wirkt! Der Gegner verliert %d Runden lang Lebenspunkte." % int(ev.turns))
				_burst(enemy_pos(1.0), Color("#8aff6a"), 14, 1.5, true)
				refresh_panels()
				await _sleep(0.7)
			"poisonTick":
				say("Das Gift wirkt: %d Schaden." % int(ev.amount))
				_damage_number(enemy_pos(enemy_height), str(int(ev.amount)), Color("#8aff6a"))
				enemy.modulate = Color("#9aff8a")
				_later(0.25, _restore_enemy_tint)
				refresh_panels()
				await _sleep(0.65)
			"focus":
				_damage_number(hero_pos(1.9) + Vector3(0.8, 0, 0), "+%d FP" % int(ev.amount), Color("#7fc8ff"))
				refresh_panels()
			"defend":
				say("Du gehst in Verteidigung – der nächste Angriff wird stark abgeschwächt.")
				_show_shield()
				refresh_panels()
				await _sleep(0.8)
			"heal":
				Sound.play("heal")
				say("Heiltrank! +%d HP." % int(ev.amount))
				_damage_number(hero_pos(2.2), "+%d" % int(ev.amount), Color("#7dffa1"))
				_burst(hero_pos(1.0), Color("#7dffa1"), 14, 1.5, true)
				refresh_panels()
				await _sleep(0.9)
			"enemyMove":
				var move: Dictionary = GameData.ENEMY_MOVES[ev.move]
				_intent.visible = false
				say("%s: %s %s!" % [def.name, move.icon, move.name])
				if int(move.hits) > 0:
					await _lunge(enemy, -1.4 * TOWARD_ENEMY)
				elif move.id == "charge":
					var tw := create_tween()
					tw.tween_property(enemy, "scale", Vector3(1.12, 1, 1), 0.25)
					tw.tween_property(enemy, "scale", Vector3.ONE, 0.25)
					tw.set_loops(2)
					_glow_flash(enemy_pos(1.0), Color("#ff6040"), 0.9)
					await _sleep(0.9)
				elif move.id == "guard":
					_burst(enemy_pos(1.0), Color("#aee0ff"), 12, 1.4, true)
					await _sleep(0.8)
				else:
					await _sleep(0.5)
			"enemyHeal":
				_damage_number(enemy_pos(enemy_height), "+%d" % int(ev.amount), Color("#7dffa1"))
				_burst(enemy_pos(1.0), Color("#7dffa1"), 12, 1.4, true)
				refresh_panels()
				await _sleep(0.7)
			"intent":
				_intent.visible = true
				refresh_panels()
			"phase":
				say(ev.text)
				_shake(0.5, 0.15)
				_restore_enemy_tint()
				refresh_panels()
				await _sleep(1.4)
			"enemyDefeated":
				var tw := create_tween().set_parallel()
				tw.tween_property(enemy, "modulate:a", 0.0, 0.6)
				tw.tween_property(enemy, "scale", Vector3(1.3, 0.0, 1.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				_burst(enemy_pos(1.0), Color.WHITE, 20, 2.0, true)
				await _sleep(0.7)
			"playerDefeated":
				create_tween().tween_property(hero, "rotation:z", -PI / 2.0, 0.5)
				hero.modulate.a = 0.5
				await _sleep(0.7)


# ---------- Ergebnis ----------

func victory() -> void:
	Sound.play("victory")
	run.defeated[obj.id] = true
	# Skill „HP nach jedem Sieg“ (lifeOnWin).
	var life := mini(int(state.player.get("lifeOnWin", 0)), int(state.player.maxHp) - int(state.player.hp))
	run.hp = int(state.player.hp) + life
	run.focus = mini(int(state.player.maxFocus), int(state.player.focus) + 1)
	Ctx.profile.potions = int(state.player.potions)
	var xp_cfg := GameConfig.section("xp")
	var xp := int(xp_cfg.boss) if def.tier == "boss" else (int(xp_cfg.eliteEnemy) if def.tier == "elite" else int(xp_cfg.normalEnemy))
	var levels := Ctx.gain_xp(xp)
	var loot := LootService.roll_loot(def.tier, rng, Ctx.owns)
	Ctx.apply_loot(loot)
	var got_rune: bool = def.tier != "boss"
	if got_rune:
		run.runes = int(run.runes) + 1
	var found := LootView.entries(loot, xp)
	if got_rune:
		found.append({"icon": "◆", "title": "Rune", "detail": "%d von %d für das Siegeltor" % [mini(int(run.runes), int(run.bossRunes)), int(run.bossRunes)], "amount": "+1", "color": UI.ACCENT})
	if life > 0:
		found.append({"icon": "❤", "title": "Lebenskraft", "detail": "Nach dem Sieg geheilt", "amount": "+%d HP" % life, "color": UI.GOOD})
	if levels > 0:
		Sound.play("levelup")
		found.push_front({"icon": "⭐", "title": "Level up!", "detail": "Jetzt Level %d – HP und Fokus aufgefüllt" % int(Ctx.profile.level), "amount": "Lv %d" % int(Ctx.profile.level), "color": UI.GOOD, "highlight": true})
	say("%s wurde besiegt!" % def.name)
	_victory_hop()
	var sub := UI.label("%s besiegt – deine Beute:" % def.name, "Dim", 17)
	await result_window("Sieg!", [sub, LootView.list(found)])
	var messages: Array[String] = ["%s besiegt: %s%s" % [def.name, describe_loot(loot), ", +1 Rune" if got_rune else ""]]
	if def.tier == "elite":
		await choose_blessing_window()
	if def.tier != "boss":
		Ctx.autosave()
	_finish({"objectId": obj.id, "outcome": "won", "messages": messages, "victory": def.tier == "boss"})


func defeat() -> void:
	var s := Ctx.stats()
	run.hp = int(s.maxHp)
	run.focus = int(s.maxFocus)
	Ctx.profile.potions = int(state.player.potions)
	say("Du wurdest besiegt …")
	# Rogue-lite: Jede Niederlage kostet ein Leben; ohne Leben endet das Abenteuer.
	var alive := Meta.lose_life(Ctx.profile)
	if alive:
		var lives := int(Ctx.profile.lives)
		await result_window("Besiegt …", [
			UI.label("Du erwachst am letzten Kristallaltar.", "", 20),
			UI.label("Noch %d Leben ❤" % lives, "Accent" if lives > 1 else "Bad", 22),
			UI.label("Alles, was du gelernt hast, bleibt erhalten.", "Good", 20),
		])
		Ctx.autosave()
		_finish({"objectId": obj.id, "outcome": "lost", "messages": ["Du bist am Kristallaltar erwacht (noch %d Leben). Tipp: Achte auf die Ankündigung des Gegners und verteidige dich vor schweren Schlägen!" % lives]})
	else:
		await result_window("Abenteuer vorbei", [
			UI.label("Deine Kräfte sind erschöpft.", "", 20),
			UI.label("Für alles Erreichte bekommst du trotzdem %s." % Meta.CURRENCY, "Accent", 20),
			UI.label("Alles, was du gelernt hast, bleibt erhalten.", "Good", 20),
		])
		_finish({"objectId": obj.id, "outcome": "lost", "messages": [], "gameOver": true})


## Zeit-Challenge: Die Uhr ist während des Kampfes abgelaufen.
func time_over() -> void:
	Ctx.profile.potions = int(state.player.potions)
	say("Die Zeit ist abgelaufen!")
	await result_window("⏱ Zeit abgelaufen", [
		UI.label("Der Tempel hat dich diesmal noch nicht ganz durchgelassen.", "", 20),
		UI.label("Für alles Erreichte bekommst du trotzdem %s." % Meta.CURRENCY, "Accent", 20),
		UI.label("Alles, was du gelernt hast, bleibt erhalten.", "Good", 20),
	])
	_finish({"objectId": obj.id, "outcome": "lost", "messages": [], "gameOver": true})


static func describe_loot(loot: Dictionary) -> String:
	var parts: Array[String] = ["%d Gold" % int(loot.gold)]
	if int(loot.potions) > 0:
		parts.append("Heiltrank")
	if loot.itemId != null:
		parts.append("✨ %s" % GameData.get_item(loot.itemId).name)
	return ", ".join(parts)


var _result_open := false
var _blessing_modal: UI.Modal
var _blessing_options: Array = []
var _result_modal: UI.Modal


func result_window(title: String, lines: Array) -> void:
	var m := UI.modal(ui, "", 560, false)
	_result_modal = m
	var t := UI.label(title, "H1")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.body.add_child(t)
	for c: Control in lines:
		if c is Label:
			(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.body.add_child(c)
	m.body.add_child(UI.gap(8))
	var btn := UI.button("Weiter", close_result)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.body.add_child(btn)
	var hint := UI.label("Enter", "Dim", 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.body.add_child(hint)
	if fast:
		_result_open = true
	else:
		_later(0.5, func() -> void: _result_open = true)
	await result_closed


## Nach einem Elite-Sieg: eine von mehreren Segnungen wählen (gilt nur in diesem Abenteuer).
func choose_blessing_window() -> void:
	var options := Blessings.roll(rng, Ctx.profile.blessings, int(Meta.cfg().blessingChoices), String(Ctx.profile.heroClass))
	if options.is_empty():
		return
	var m := UI.modal(ui, "Wähle eine Segnung", 900, false)
	_blessing_modal = m
	_blessing_options = options
	m.body.add_child(UI.label("Der Tempel belohnt deinen Mut. Die Segnung wirkt bis zum Ende dieses Abenteuers.", "Dim", 16))
	var row := UI.hbox([], 12)
	for i in options.size():
		var b: Dictionary = options[i]
		var extra: String = Blessings.RARITY_LABEL[b.rarity].capitalize()
		for duo: Dictionary in Blessings.duos_completed_by(Ctx.profile.blessings, b.id):
			extra += " · Duo: %s %s" % [duo.icon, duo.name]
		var btn := UI.choice_card(i + 1, b.icon, b.name, Blessings.text(b), extra)
		btn.pressed.connect(choose_blessing.bind(i))
		row.add_child(btn)
	m.body.add_child(row)
	var hint := UI.label("Taste 1–3 oder klicken", "Dim", 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.body.add_child(hint)
	UI.focus_later(row.get_child(0) as Control)
	await blessing_chosen


func choose_blessing(i: int) -> void:
	if _blessing_modal == null or i < 0 or i >= _blessing_options.size():
		return
	var b: Dictionary = _blessing_options[i]
	var duos := Blessings.duos_completed_by(Ctx.profile.blessings, b.id)
	Meta.add_blessing(Ctx.profile, run, b.id)
	Sound.play("levelup")
	for duo: Dictionary in duos:
		say("Duo-Segnung erwacht: %s %s – %s" % [duo.icon, duo.name, Blessings.text(duo)])
	var m := _blessing_modal
	_blessing_modal = null
	m.close()
	blessing_chosen.emit(b.id)


func close_result() -> void:
	if _result_modal == null:
		return
	_result_open = false
	var m := _result_modal
	_result_modal = null
	m.close()
	result_closed.emit()


func _finish(data: Dictionary) -> void:
	_fade(0.0, 1.0, 0.25)
	await _sleep(0.26)
	finished.emit(data)
	queue_free()


## Super-Bonus mitten im Kampf (Issue #29): volle Heilung und voller Fokus.
func _on_set_bonus(bonus: Dictionary) -> void:
	var p: Dictionary = state.player
	p.hp = int(p.maxHp)
	p.focus = int(p.maxFocus)
	wallet.focus = int(p.maxFocus)
	say("%s Set-Meister! Jede Vokabel %s richtig – volle Heilung!" % ["🌟 Goldener" if bonus.level == "golden" else "⭐", "ohne Hilfe" if bonus.level == "golden" else "einmal"])
	_burst(hero_pos(1.6), Color("#ffd75e"), 24, 2.0, true)
	refresh_panels()


func _on_level_up() -> void:
	Sound.play("levelup")
	var s := Ctx.stats()
	var p: Dictionary = state.player
	p.maxHp = int(s.maxHp)
	p.maxFocus = int(s.maxFocus)
	p.attack = int(s.attack)
	p.hp = int(s.maxHp)
	p.focus = int(s.maxFocus)
	wallet.focus = int(s.maxFocus)
	say("⭐ Level up! Du bist jetzt Level %d." % int(Ctx.profile.level))
	_burst(hero_pos(1.6), Color("#ffd75e"), 18, 1.8, true)
	refresh_panels()


# ---------- Positionen & kleine Effekte ----------

func hero_pos(h: float) -> Vector3:
	return HERO_POS + Vector3(0, h, 0.2)


func enemy_pos(h: float) -> Vector3:
	return ENEMY_POS + Vector3(0, h, 0.2)


## Verzögerter Aufruf, der mit dem Kampf endet: Ein Tween gehört zum Knoten und verfällt mit ihm.
## (Ein SceneTree-Timer würde nach dem Kampfende noch ein Lambda auf den freigegebenen Kampf aufrufen.)
func _later(seconds: float, cb: Callable) -> void:
	if fast:
		cb.call()
	else:
		create_tween().tween_callback(cb).set_delay(seconds)


func _restore_enemy_tint() -> void:
	if not is_instance_valid(enemy):
		return
	enemy.modulate = Color("#ffa0a0") if int(state.enemy.phase) == 2 else Color.WHITE


func _flash_sprite(s: Sprite3D) -> void:
	var tw := create_tween()
	for i in 2:
		tw.tween_callback(func() -> void: s.modulate = Color(4, 4, 4))
		tw.tween_interval(0.09)
		tw.tween_callback(func() -> void:
			if s == enemy:
				_restore_enemy_tint()
			else:
				s.modulate = Color.WHITE)
		tw.tween_interval(0.09)


func _fade(from: float, to: float, seconds: float) -> void:
	_flash_rect.color = Color(0, 0, 0, from)
	create_tween().tween_property(_flash_rect, "color:a", to, seconds)


func _shake(seconds: float, strength: float) -> void:
	var cam := fx.camera
	var tw := create_tween()
	var n := maxi(1, int(seconds / 0.04))
	for i in n:
		var k := 1.0 - float(i) / n
		tw.tween_property(cam, "h_offset", randf_range(-strength, strength) * k, 0.04)
		tw.parallel().tween_property(cam, "v_offset", randf_range(-strength, strength) * k, 0.04)
	tw.tween_property(cam, "h_offset", 0.0, 0.04)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.04)


func _lunge(s: Sprite3D, dist: float) -> void:
	var start := s.position.x
	var tw := create_tween()
	tw.tween_property(s, "position:x", start + dist, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "position:x", start, 0.14)
	await _sleep(0.14)


func _damage_number(pos: Vector3, text: String, c: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font_bold
	l.font_size = 96
	l.pixel_size = 0.006
	l.modulate = c
	l.outline_modulate = Color("#1a1030")
	l.outline_size = 22
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 20
	l.position = pos
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", pos.y + 0.45, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", pos.y + 0.3, 0.22)
	tw.tween_interval(0.35)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


## Kurzer Funken- oder Glitzerausbruch.
func _burst(pos: Vector3, c: Color, amount: int, speed: float, upward: bool) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.8
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0) if upward else Vector3(0, 0, 1)
	pm.spread = 70.0 if upward else 180.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed * 1.5
	pm.gravity = Vector3(0, -1.5 if upward else -3.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * 2.5
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	p.position = pos
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _glow_flash(pos: Vector3, c: Color, seconds: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 3.0
	l.omni_range = 3.5
	l.position = pos + Vector3(0, 0, 0.8)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, seconds)
	tw.tween_callback(l.queue_free)


func _additive_quad(size: Vector2, c: Color, tex: Texture2D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := Fx.additive(tex if tex else Fx.glow(), c)
	m.no_depth_test = true
	m.render_priority = 5
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Leuchtende Linie (Schwerthieb, Kreuzschnitt), blendet schnell aus.
func _slash(center: Vector3, angle_deg: float, length: float, c: Color, width := 0.14) -> void:
	var mi := _additive_quad(Vector2(length, width), c, Fx.shaft())
	mi.position = center
	mi.rotation = Vector3(0, 0, deg_to_rad(angle_deg))
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, 0.26)
	tw.tween_callback(mi.queue_free)


## Flacher Ring am Boden, der sich ausbreitet (Schockwelle, Zauberkreis).
func _ring(pos: Vector3, c: Color, to_scale: float, seconds: float) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.42
	t.outer_radius = 0.5
	t.rings = 32
	t.ring_segments = 6
	mi.mesh = t
	var m := Fx.additive(null, c * 2.0)
	mi.material_override = m
	mi.position = pos + Vector3(0, 0.05, 0)
	mi.scale = Vector3(0.4, 0.1, 0.4)
	add_child(mi)
	var tw := create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(to_scale, 0.1, to_scale), seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, seconds)
	tw.chain().tween_callback(mi.queue_free)


func _show_shield() -> void:
	_clear_shield()
	_shield = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.1
	sp.height = 2.4
	_shield.mesh = sp
	var m := Fx.additive(null, Color(0.43, 0.78, 1.0, 0.18))
	_shield.material_override = m
	_shield.position = hero_pos(1.0)
	add_child(_shield)
	var tw := _shield.create_tween().set_loops()
	tw.tween_property(m, "albedo_color:a", 0.4, 0.6)
	tw.tween_property(m, "albedo_color:a", 0.15, 0.6)


func _clear_shield() -> void:
	if _shield:
		_shield.queue_free()
		_shield = null


func _victory_hop() -> void:
	_clear_shield()
	var tw := create_tween().set_loops(3)
	tw.tween_property(hero, "position:y", 0.45, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(hero, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ---------- Klassen-Angriffe (Issue #11) ----------

## Jede Klasse greift anders an; die Fähigkeit ist jeweils eine größere Variante.
func hero_attack(skill: bool, crit: bool) -> void:
	match cls.id:
		"mage":
			await _mage_attack(skill)
		"rogue":
			await _rogue_attack(skill, crit)
		_:
			await _warrior_attack(skill, crit)


func _move_hero(x: float, seconds: float, ease_in := true) -> void:
	var tw := create_tween()
	tw.tween_property(hero, "position:x", x, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN if ease_in else Tween.EASE_OUT)
	await _sleep(seconds)


## Krieger: stürmt vor und führt einen weiten Schwertbogen; Wuchtschlag mit Sprung und Schockwelle.
func _warrior_attack(skill: bool, crit: bool) -> void:
	var to := ENEMY_POS.x - HERO_POS.x - 2.6 * TOWARD_ENEMY
	await _move_hero(to, 0.24)
	if skill:
		var tw := create_tween()
		tw.tween_property(hero, "position:y", 1.6, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(hero, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await _sleep(0.36)
		_ring(ENEMY_POS, Color("#ffd75e"), 6.0, 0.5)
		_burst(ENEMY_POS + Vector3(0, 0.2, 0.3), Color("#c89a6a"), 14, 2.5, true)
		_shake(0.3, 0.2)
	if weapon:
		weapon.swing(0.3 if skill else 0.24)
	var c := Color("#ffd75e") if skill or crit else Color.WHITE
	var center := enemy_pos(enemy_height * 0.55) + Vector3(-0.3 * TOWARD_ENEMY, 0, 0.3)
	var sweep := 1.4 if skill else 1.0
	for i in 4:
		_later(0.045 * i, _slash.bind(center + Vector3(-0.1 * i * TOWARD_ENEMY, 0.15 - 0.12 * i, 0), -(60 - 40 * i) * TOWARD_ENEMY, 2.0 * sweep, c, 0.18 * sweep))
	_burst(center, Color("#ffe08a"), 18 if skill else 10, 2.5, false)
	if crit:
		_shake(0.18, 0.12)
	var back := create_tween()
	back.tween_interval(0.12)
	back.tween_property(hero, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _sleep(0.12)


## Schurke: blitzschneller Sprint mit Nachbildern und Kreuzhieben; Giftklinge hinterlässt eine Giftwolke.
func _rogue_attack(skill: bool, crit: bool) -> void:
	var to := ENEMY_POS.x - HERO_POS.x - 2.0 * TOWARD_ENEMY
	for i in range(1, 5):
		var ghost := Fx.sprite(hero.texture, 8.0)
		ghost.flip_h = hero.flip_h
		ghost.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		ghost.modulate = Color("#8aff6a", 0.45) if skill else Color("#b8c8ff", 0.45)
		ghost.position = HERO_POS + Vector3(to * i / 5.0, 0, -0.05)
		add_child(ghost)
		var tw := ghost.create_tween()
		tw.tween_interval(i * 0.025)
		tw.tween_property(ghost, "modulate:a", 0.0, 0.38)
		tw.tween_callback(ghost.queue_free)
	await _move_hero(to, 0.11)
	var c := Color("#8aff6a") if skill else (Color("#ffb0ff") if crit else Color.WHITE)
	var center := enemy_pos(enemy_height * 0.55) + Vector3(0, 0, 0.3)
	if weapon:
		weapon.swing(0.14)
	_slash(center, 45, 2.0, c)
	await _sleep(0.11)
	if weapon:
		weapon.swing(0.14)
	_slash(center + Vector3(0.2 * TOWARD_ENEMY, 0, 0), -45, 2.0, c)
	if skill:
		_burst(center, Color("#6adf4a"), 24, 1.0, true)
	if crit:
		_shake(0.18, 0.12)
	var back := create_tween()
	back.tween_interval(0.06)
	back.tween_property(hero, "position:x", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _sleep(0.08)


## Magier: Zauberkreis, dann ein Feuerball mit Funkenspur; die Fähigkeit ist ein großer Feuerball.
func _mage_attack(skill: bool) -> void:
	_ring(HERO_POS, Color("#ff9040") if skill else Color("#ffd080"), 3.0, 0.42)
	if weapon:
		var raise := create_tween()
		raise.tween_property(weapon, "swing_deg", 35.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		raise.tween_property(weapon, "swing_deg", -30.0, 0.16)
		raise.tween_property(weapon, "swing_deg", 0.0, 0.3)
	var hop := create_tween()
	hop.tween_property(hero, "position:y", 0.25, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hop.tween_property(hero, "position:y", 0.0, 0.18)
	await _sleep(0.36)
	var size := 0.55 if skill else 0.3
	var ball := Node3D.new()
	var core := _additive_quad(Vector2(size, size) * 2.0, Color(1.0, 0.75, 0.38) * 2.5)
	(core.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ball.add_child(core)
	var light := OmniLight3D.new()
	light.light_color = Color("#ff7030")
	light.light_energy = 3.0
	light.omni_range = 4.0
	ball.add_child(light)
	var trail := GPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.4
	trail.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3.ZERO
	pm.color = Color(1.0, 0.55, 0.2)
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	trail.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(2.5, 2.5, 2.5)
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = qm
	trail.draw_pass_1 = q
	ball.add_child(trail)
	ball.position = hero_pos(1.3) + Vector3(0.6 * TOWARD_ENEMY, 0, 0.2)
	add_child(ball)
	var to := enemy_pos(enemy_height * 0.5) + Vector3(0, 0, 0.3)
	var flight := 0.52 if skill else 0.38
	var tw := create_tween()
	tw.tween_property(ball, "position", to, flight).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _sleep(flight)
	ball.queue_free()
	_glow_flash(to, Color("#ff7030"), 0.45)
	_burst(to, Color("#ffa040"), 24 if skill else 12, 2.5, false)
	if skill:
		var flash := create_tween()
		_flash_rect.color = Color(1.0, 0.63, 0.31, 0.35)
		flash.tween_property(_flash_rect, "color:a", 0.0, 0.18)
		_shake(0.26, 0.16)
		_ring(ENEMY_POS, Color("#ff9040"), 6.0, 0.5)


## Nur für Screenshots/Debugging: aktuelle Abfrage mit einem Text beantworten.
func debug_answer(text: String) -> void:
	for n in ui.get_children():
		if n is VocabPrompt:
			(n as VocabPrompt).input.text = text
			(n as VocabPrompt)._submit()


## Nur für Screenshots/Debugging: aktuelle Abfrage richtig beantworten.
func debug_answer_correct() -> void:
	for n in ui.get_children():
		if n is VocabPrompt:
			debug_answer((n as VocabPrompt).entry.en)
