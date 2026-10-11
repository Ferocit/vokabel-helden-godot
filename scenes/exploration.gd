extends Node3D
## Erkundung im HD-2D-Stil: Held läuft mit WASD/Pfeiltasten durch den Tempel, öffnet Truhen und Türen
## mit Vokabeln, berührt Gegner für Kämpfe, rastet am Kristallaltar. Esc öffnet das Menü.

const PLAYER_RADIUS := 0.24
const SPEED := 3.4  # Kacheln pro Sekunde
## Füße des Helden liegen etwas unter dem Kollisionsmittelpunkt.
const FEET_OFFSET := 0.32
const INTERACT_RANGE := 1.35
const COMBAT := "res://scenes/combat.tscn"
const SUMMARY := "res://scenes/summary.tscn"
const TITLE := "res://scenes/title.tscn"

## Für Tests: Übergänge ohne Wartezeit.
static var fast := false

var run: Dictionary
var level: LevelBuilder
var fx: WorldFx
var hero: Sprite3D
var hero_root: Node3D
var busy := false
var walk_time := 0.0
var contact_cooldown := 0.0
var step_timer := 0.0
var minimap_timer := 0.0
var current_target: Variant = null
var _target_dirty := true
var _time := 0.0
## Laufgeschwindigkeit aus Skills, Gegenständen und Segnungen; wird bei Profiländerungen neu berechnet.
var _speed_factor := 1.0
## Zeit-Challenge: Im Menü steht die Uhr still.
var _clock_paused := false
## Offene Talentwahl nach einem Level-up (Issue #14).
var _talent_modal: UI.Modal
var _talent_options: Array = []
## Bewegliche Gegner (Objekt-ID → EnemyAgent); besiegte fehlen.
var agents := {}

var ui: CanvasLayer
var hud: Hud
var minimap: Minimap
var _prompt: PanelContainer
var _prompt_text: RichTextLabel
var _toasts: VBoxContainer
var _flash: ColorRect


func _ready() -> void:
	if not Ctx.has_run():
		get_tree().change_scene_to_file.call_deferred(TITLE)
		return
	Controls.ensure()
	run = Ctx.run
	_refresh_speed()
	Ctx.profile_changed.connect(_refresh_speed)
	_create_agents()
	level = LevelBuilder.build(run.map, is_gone)
	add_child(level.root)
	fx = WorldFx.new()
	add_child(fx)
	_build_hero()
	_build_ui()
	_place_hero()
	fx.target = Vector3(run.player.x, 0, run.player.y)
	fx.snap()
	_fade_in(0.4)
	var learning: LearningSession = run.learning
	if learning.run.questions == 0 and (run.defeated as Dictionary).is_empty():
		get_tree().create_timer(0.7).timeout.connect(toast.bind("Willkommen im geheimen Dschungeltempel! Sammle %d Runen ◆, um das Siegeltor zum Boss zu öffnen." % int(run.bossRunes)))
		get_tree().create_timer(2.2).timeout.connect(toast.bind("Runen bekommst du für besiegte Gegner und geöffnete Türen. Truhen enthalten Beute."))


# ---------- Zustand ----------

func is_gone(obj: Dictionary) -> bool:
	if obj.kind == "enemy":
		return run.defeated.has(obj.id)
	if obj.kind == "heal":
		return false
	return run.opened.has(obj.id)


func is_solid_tile(x: int, y: int) -> bool:
	if not MapModel.is_floor(run.map, x, y):
		return true
	if level.solid_deco.has(Vector2i(x, y)):
		return true
	for obj: Dictionary in run.map.objects:
		if obj.x != x or obj.y != y:
			continue
		if obj.kind == "chest" or obj.kind == "heal":
			return true
		if (obj.kind == "door" or obj.kind == "bossDoor") and not run.opened.has(obj.id):
			return true
	return false


func free_at(px: float, py: float) -> bool:
	var r := PLAYER_RADIUS
	return not is_solid_tile(floori(px - r), floori(py - r)) \
		and not is_solid_tile(floori(px + r), floori(py - r)) \
		and not is_solid_tile(floori(px - r), floori(py + r)) \
		and not is_solid_tile(floori(px + r), floori(py + r))


# ---------- Held ----------

func _build_hero() -> void:
	hero_root = Node3D.new()
	hero_root.name = "Hero"
	hero_root.add_child(Fx.shadow_quad(0.8))
	hero = Fx.sprite(Assets.frame(int(Ctx.hero_class().frame)))
	hero.rotation.x = LevelBuilder.TILT
	hero_root.add_child(hero)
	HeldWeapon.equip(hero, Ctx.profile.equipment.get("weapon"))
	# Warmer Lichtschein um den Helden – der Tempel ist schummrig.
	var light := OmniLight3D.new()
	light.light_color = Color("#ffe2a8")
	light.light_energy = 1.5
	light.omni_range = 6.5
	light.omni_attenuation = 1.4
	light.position = Vector3(0, 1.6, 0.6)
	hero_root.add_child(light)
	add_child(hero_root)


## Weit weg = Bäume werden nirgends ausgeblendet (Titel, Kampf).
const NO_PLAYER := Vector3(0, -1000, 0)


func _place_hero() -> void:
	var p: Vector2 = run.player
	# Für den Urwald-Shader: Bäume zwischen Kamera und Held werden durchsichtig.
	_set_shader_player(Vector3(p.x, 0.6, p.y + FEET_OFFSET - 0.25) if hero_root.visible else NO_PLAYER)
	# Leichtes Hüpfen beim Laufen, sanftes Atmen im Stand.
	var bob := absf(sin(walk_time * 13.0)) * 0.11 if walk_time > 0.0 else sin(_time * 2.0) * 0.02
	hero_root.position = Vector3(p.x, 0, p.y + FEET_OFFSET - 0.25)
	hero.position.y = bob
	var squash := 1.0 + (sin(walk_time * 26.0) * 0.03 if walk_time > 0.0 else 0.0)
	hero.scale = Vector3(squash, 1.0, 1.0)


# ---------- Update ----------

func _process(delta: float) -> void:
	if run.is_empty():
		return
	_time += delta
	# Zeit-Challenge: Die Uhr läuft auch in Kämpfen und Abfragen; ist sie abgelaufen, wird die
	# laufende Aktion noch beendet, danach endet das Abenteuer.
	if not _clock_paused:
		Ctx.tick_time(delta)
	if Ctx.time_up() and not busy:
		time_over()
		return
	# Level-up: Talent wählen, sobald man frei ist (auch nach einem Kampf).
	if not busy and int(Ctx.profile.get("pendingTalents", 0)) > 0:
		open_talent_choice()
	if busy:
		_place_hero()
		return
	var dt := minf(delta, 0.05)
	contact_cooldown = maxf(0.0, contact_cooldown - dt)
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO and not _typing():
		move(dir, dt)
		if absf(dir.x) > 0.1:
			hero.flip_h = dir.x < 0.0
		walk_time += dt
		step_timer -= dt
		if step_timer <= 0.0:
			# Jede Klasse klingt anders: schwere Stiefel, leise Sohlen oder eine raschelnde Robe.
			var steps: Dictionary = Ctx.hero_class().steps
			Sound.play(steps.sound, float(steps.volume), float(steps.rate))
			if steps.has("extra") and randf() < 0.35:
				Sound.play(steps.extra, 0.05, 1.2)
			step_timer = float(steps.interval)
	else:
		walk_time = 0.0
	_place_hero()
	fx.target = Vector3(run.player.x, 0, run.player.y)
	update_enemies(dt)
	check_enemy_contact()
	_update_prompt()
	minimap_timer -= dt
	if minimap_timer <= 0.0:
		minimap_timer = 0.15
		minimap.reveal_around(run.player)


func _typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit


## Bewegung in Bildschirmrichtung; blockierte Achsen gleiten an Wänden entlang.
func move(input_dir: Vector2, dt: float) -> void:
	var g := input_dir.normalized()
	var step := SPEED * _speed_factor * dt
	var p: Vector2 = run.player
	var nx := p.x + g.x * step
	var ny := p.y + g.y * step
	var x_ok := absf(g.x) > 1e-6 and free_at(nx, p.y)
	var y_ok := absf(g.y) > 1e-6 and free_at(p.x, ny)
	if x_ok and y_ok and free_at(nx, ny):
		p = Vector2(nx, ny)
	elif x_ok and not y_ok:
		p.x = p.x + signf(g.x) * step
		if not free_at(p.x, p.y):
			p.x = nx
		run.player = p
		_nudge("y", g.y, step)
		return
	elif y_ok and not x_ok:
		p.y = p.y + signf(g.y) * step
		if not free_at(p.x, p.y):
			p.y = ny
		run.player = p
		_nudge("x", g.x, step)
		return
	else:
		_nudge("x", g.x, step)
		_nudge("y", g.y, step)
		return
	run.player = p


## Hilft beim Einbiegen in schmale Gänge: zur Kachelmitte schieben, wenn die Nachbarkachel frei ist.
func _nudge(blocked_axis: String, d: float, step: float) -> void:
	if absf(d) < 0.2:
		return
	var p: Vector2 = run.player
	var tx := floori(p.x)
	var ty := floori(p.y)
	var s := int(signf(d))
	var open := not is_solid_tile(tx + s, ty) if blocked_axis == "x" else not is_solid_tile(tx, ty + s)
	if not open:
		return
	if blocked_axis == "x":
		var ny := p.y + clampf(ty + 0.5 - p.y, -step, step)
		if free_at(p.x, ny):
			run.player = Vector2(p.x, ny)
	else:
		var nx := p.x + clampf(tx + 0.5 - p.x, -step, step)
		if free_at(nx, p.y):
			run.player = Vector2(nx, p.y)


func check_enemy_contact() -> void:
	if contact_cooldown > 0.0:
		return
	var p: Vector2 = run.player
	for obj: Dictionary in run.map.objects:
		if obj.kind != "enemy" or run.defeated.has(obj.id):
			continue
		var reach := 1.0 if obj.tier == "boss" else 0.75
		if p.distance_to(enemy_pos(obj)) < reach:
			start_combat(obj)
			return


# ---------- Gegnerbewegung ----------

func _create_agents() -> void:
	agents.clear()
	var ai_rng := Rng.create((int(run.seed) ^ 0x0A11CE) & Rng.MASK)
	for obj: Dictionary in run.map.objects:
		if obj.kind != "enemy" or run.defeated.has(obj.id):
			continue
		var room: Dictionary = {}
		for r: Dictionary in run.map.rooms:
			if MapModel.room_contains(r, obj.x, obj.y):
				room = r
		agents[obj.id] = EnemyAgent.new(obj, room, ai_rng)


## Aktuelle Position eines Gegners (Kachel-Einheiten).
func enemy_pos(obj: Dictionary) -> Vector2:
	if agents.has(obj.id):
		return (agents[obj.id] as EnemyAgent).pos
	return Vector2(obj.x + 0.5, obj.y + 0.5)


func update_enemies(dt: float) -> void:
	var hero_speed := SPEED * _speed_factor
	for a: EnemyAgent in agents.values():
		if not a.moves():
			continue
		a.update(dt, run.player, is_solid_tile, hero_speed)
		_sync_enemy_view(a)


func _sync_enemy_view(a: EnemyAgent) -> void:
	var view: Node3D = level.views.get(a.id)
	if view == null:
		return
	view.position = Vector3(a.pos.x, 0, a.pos.y)
	if absf(a.facing.x) > 0.1:
		for s in view.find_children("*", "Sprite3D", false, false):
			(s as Sprite3D).flip_h = a.facing.x < 0.0


## Alle Gegner zurück an ihren Platz (nach einer Niederlage des Helden).
func reset_enemies() -> void:
	for a: EnemyAgent in agents.values():
		a.reset()
		_sync_enemy_view(a)


func nearest_interactable() -> Variant:
	var p: Vector2 = run.player
	var best: Variant = null
	var best_dist := INTERACT_RANGE
	for obj: Dictionary in run.map.objects:
		if obj.kind == "enemy":
			continue
		if obj.kind != "heal" and run.opened.has(obj.id):
			continue
		var d := p.distance_to(Vector2(obj.x + 0.5, obj.y + 0.5))
		if d < best_dist:
			best = obj
			best_dist = d
	return best


func _update_prompt() -> void:
	var target: Variant = nearest_interactable()
	if not _target_dirty and target == current_target:
		return
	_target_dirty = false
	current_target = target
	_prompt.visible = target != null
	if target != null:
		_prompt_text.text = "[center][color=#f1c96b][E][/color] %s[/center]" % describe(target)


func describe(obj: Dictionary) -> String:
	match obj.kind:
		"chest":
			var detail := "2 Vokabeln" if obj.chestType == "rare" else ("1 schwere Vokabel" if obj.chestType == "special" else "1 Vokabel")
			return "%s öffnen (%s)" % [MapModel.CHEST_LABELS[obj.chestType], detail]
		"door":
			return "Verschlossene Tür öffnen (%d %s)" % [int(obj.answers), "Vokabel" if int(obj.answers) == 1 else "Vokabeln"]
		"bossDoor":
			var missing := int(obj.runes) - int(run.runes)
			return "Siegeltor – dir fehlen noch %d Runen" % missing if missing > 0 else "Siegeltor mit den Runen öffnen"
		"heal":
			return "Am Kristallaltar ausruhen"
	return ""


# ---------- Eingabe & Interaktion ----------

func _unhandled_input(event: InputEvent) -> void:
	if _talent_modal != null and event is InputEventKey and event.is_pressed() and not event.is_echo():
		var idx := [KEY_1, KEY_2, KEY_3].find((event as InputEventKey).keycode)
		if idx >= 0:
			get_viewport().set_input_as_handled()
			choose_talent(idx)
		return
	if run.is_empty() or busy or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("menu"):
		get_viewport().set_input_as_handled()
		open_menu()
	elif event.is_action("inventory"):
		get_viewport().set_input_as_handled()
		open_character()
	elif event.is_action("interact"):
		var target: Variant = nearest_interactable()
		if target != null:
			get_viewport().set_input_as_handled()
			interact(target)


func interact(obj: Dictionary) -> void:
	match obj.kind:
		"heal":
			var s := Ctx.stats()
			run.hp = int(s.maxHp)
			run.focus = int(s.maxFocus)
			run.lastHeal = Vector2(obj.x + 0.5, obj.y + 0.5)
			Sound.play("heal")
			hud.refresh()
			Ctx.autosave()
			open_altar(obj)
		"bossDoor":
			if int(run.runes) < int(obj.runes):
				toast("Das Siegeltor braucht %d Runen. Besiege Gegner und öffne Türen, um Runen zu sammeln." % int(obj.runes))
				return
			run.opened[obj.id] = true
			_refresh_object(obj)
			Sound.play("door")
			_shake(0.4, 0.12)
			toast("Die Runen leuchten auf – das Siegeltor öffnet sich! Dahinter wartet der Boss.")
			Ctx.autosave()
		"chest", "door":
			busy = true
			var title: String = MapModel.CHEST_LABELS[obj.chestType] if obj.kind == "chest" else "Verschlossene Tür"
			var required: int = (2 if obj.chestType == "rare" else 1) if obj.kind == "chest" else int(obj.answers)
			var mode := "preferHard" if obj.kind == "chest" and obj.chestType == "special" else "normal"
			var done: bool = await run_challenge(title, required, mode)
			busy = false
			_target_dirty = true
			if not done:
				return
			run.opened[obj.id] = true
			_refresh_object(obj)
			if obj.kind == "chest":
				grant_chest(obj)
			else:
				run.runes = int(run.runes) + 1
				Sound.play("door")
				toast("Die Tür springt auf! +1 Rune ◆")
			hud.refresh()
			Ctx.autosave()


## Beute einer geöffneten Truhe gutschreiben und als Liste mit Symbolen zeigen.
func grant_chest(obj: Dictionary) -> void:
	var source := "chestRare" if obj.chestType == "rare" else ("chestSpecial" if obj.chestType == "special" else "chestNormal")
	var loot := LootService.roll_loot(source, run.rng, Ctx.owns)
	Ctx.apply_loot(loot)
	var xp := int(GameConfig.section("xp").chest)
	var levels := Ctx.gain_xp(xp)
	Sound.play("chest")
	get_tree().create_timer(0.25).timeout.connect(Sound.play.bind("coins", -1.0, 1.0))
	loot_toast(MapModel.CHEST_LABELS[obj.chestType], CHEST_ICONS[obj.chestType], LootView.entries(loot, xp))
	if levels > 0:
		level_up_toast(levels)


## Lernaktion außerhalb des Kampfes (Truhe, Tür): `required` richtig erinnerte Vokabeln öffnen sie.
## Falsche Antworten lösen die Fehlerkorrektur aus und es folgt eine weitere Vokabel – man kann nicht scheitern.
func run_challenge(title: String, required: int, mode: String) -> bool:
	var wallet := Ctx.hint_wallet(int(run.focus))
	var correct := 0
	var learning: LearningSession = run.learning
	while correct < required:
		var item := learning.next_word(mode)
		var prompt := VocabPrompt.create({"item": item, "wallet": wallet, "label": title, "footer": "%d/%d richtig" % [correct, required], "allow_cancel": true})
		prompt.wallet_changed.connect(func(w: Dictionary) -> void:
			run.focus = int(w.focus)
			hud.refresh())
		ui.add_child(prompt)
		var out: Dictionary = await prompt.finished
		wallet = out.wallet
		run.focus = int(wallet.focus)
		hud.refresh()
		if out.cancelled:
			Ctx.autosave()
			return false
		var levels := Ctx.submit_answer(item, out.result)
		if levels > 0:
			level_up_toast(levels)
		hud.refresh()
		# Fast richtig (ein Tippfehler) öffnet ebenfalls – das Wort kommt trotzdem bald wieder.
		if out.result.outcome != "wrongCorrected":
			correct += 1
	return true


static func describe_loot(loot: Dictionary) -> String:
	var parts: Array[String] = ["%d Gold" % int(loot.gold)]
	if int(loot.potions) > 0:
		parts.append("Heiltrank")
	if loot.itemId != null:
		parts.append("✨ %s" % GameData.get_item(loot.itemId).name)
	return ", ".join(parts)


func _refresh_object(obj: Dictionary) -> void:
	_target_dirty = true
	# Geöffnete Türen verschwinden ganz (Issue #13), statt offen stehen zu bleiben.
	if obj.kind in ["door", "bossDoor"] and run.opened.has(obj.id):
		level.fade_out(obj.id)
	else:
		level.refresh_object(obj)


# ---------- Kampf ----------

func start_combat(obj: Dictionary) -> void:
	busy = true
	walk_time = 0.0
	Sound.play("encounter")
	_flash_screen(Color(1, 1, 1, 0.85), 0.25)
	if not fast:
		var tw := create_tween()
		tw.tween_property(fx, "zoom", 1.5, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tw.finished
	fx.zoom = 1.0
	if not ResourceLoader.exists(COMBAT):
		toast("Der Kampf wird gerade gebaut.")
		on_combat_return({"objectId": obj.id, "outcome": "lost", "messages": []})
		return
	var combat: Node = (load(COMBAT) as PackedScene).instantiate()
	combat.set("object_id", obj.id)
	combat.connect("finished", on_combat_return)
	_set_world_active(false)
	get_tree().root.add_child(combat)


## data: { objectId, outcome: "won" | "lost", messages: Array[String] }
func on_combat_return(data: Dictionary) -> void:
	_set_world_active(true)
	_refresh_speed()
	busy = false
	contact_cooldown = 1.2
	_target_dirty = true
	if data.outcome == "won":
		level.fade_out(data.objectId)
		agents.erase(data.objectId)
	else:
		reset_enemies()
		run.player = run.lastHeal
		_place_hero()
		fx.target = Vector3(run.player.x, 0, run.player.y)
		fx.snap()
		_fade_in(0.6)
	for msg: String in data.messages:
		toast(msg)
	hud.refresh()
	if data.get("victory", false):
		finish_run(true)
	elif data.get("gameOver", false):
		finish_run(false)


## Zuletzt an den Urwald-Shader gemeldete Heldenposition.
var shader_player := NO_PLAYER


func _set_shader_player(pos: Vector3) -> void:
	shader_player = pos
	RenderingServer.global_shader_parameter_set("player_world", pos)


func _refresh_speed() -> void:
	_speed_factor = Ctx.move_speed_factor()
	# Ausrüstung kann sich geändert haben (Menü, Händler): Waffe in der Hand anpassen.
	if hero != null:
		HeldWeapon.equip(hero, Ctx.profile.equipment.get("weapon"))


func _exit_tree() -> void:
	if Ctx.profile_changed.is_connected(_refresh_speed):
		Ctx.profile_changed.disconnect(_refresh_speed)
	_set_shader_player(NO_PLAYER)


func _set_world_active(on: bool) -> void:
	ui.visible = on
	level.root.visible = on
	hero_root.visible = on
	fx.set_active(on)


func time_over() -> UI.Modal:
	busy = true
	walk_time = 0.0
	Sound.play("wrong")
	var m := UI.modal(ui, "⏱ Die Zeit ist abgelaufen!", 600, false)
	m.body.add_child(UI.para("Der Tempel hat dich diesmal noch nicht ganz durchgelassen. Für alles Erreichte bekommst du trotzdem %s." % Meta.CURRENCY, "", 18))
	m.body.add_child(UI.label("Alles, was du gelernt hast, bleibt erhalten.", "Good", 18))
	var btn := UI.button("Zur Auswertung", func() -> void:
		m.close()
		finish_run(false))
	m.body.add_child(UI.hbox([UI.spacer(), btn, UI.spacer()]))
	UI.focus_later(btn)
	return m


func finish_run(victory: bool) -> void:
	Ctx.end_run(victory)
	if ResourceLoader.exists(SUMMARY):
		var s: Node = (load(SUMMARY) as PackedScene).instantiate()
		s.set("victory", victory)
		var tree := get_tree()
		tree.root.add_child(s)
		tree.current_scene = s
		queue_free()
	else:
		get_tree().change_scene_to_file(TITLE)


# ---------- UI ----------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	hud = Hud.new()
	ui.add_child(hud)

	var keyhint := PanelContainer.new()
	var kt := RichTextLabel.new()
	kt.bbcode_enabled = true
	kt.fit_content = true
	kt.autowrap_mode = TextServer.AUTOWRAP_OFF
	kt.scroll_active = false
	kt.add_theme_font_size_override("normal_font_size", 15)
	kt.text = "[color=#f1c96b]E[/color] Interagieren · [color=#f1c96b]I[/color] Inventar · [color=#f1c96b]Esc[/color] Menü"
	keyhint.add_child(kt)
	UI.pin(ui, keyhint, Control.PRESET_TOP_RIGHT, Vector2(-12, 12))

	_prompt = PanelContainer.new()
	_prompt_text = RichTextLabel.new()
	_prompt_text.bbcode_enabled = true
	_prompt_text.fit_content = true
	_prompt_text.scroll_active = false
	_prompt_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_prompt_text.custom_minimum_size.x = 520
	_prompt_text.add_theme_font_size_override("normal_font_size", 20)
	_prompt.add_child(_prompt_text)
	UI.pin(ui, _prompt, Control.PRESET_CENTER_BOTTOM, Vector2(0, -28))
	_prompt.visible = false

	_toasts = VBoxContainer.new()
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.pin(ui, _toasts, Control.PRESET_TOP_RIGHT, Vector2(-16, 80))

	minimap = Minimap.new()
	minimap.enemy_pos = enemy_pos
	ui.add_child(minimap)
	UI.pin(ui, minimap, Control.PRESET_BOTTOM_RIGHT, Vector2(-14, -52))
	minimap.reveal_around(run.player)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0, 0, 0, 0)
	ui.add_child(_flash)


func toast(text: String) -> void:
	var p := PanelContainer.new()
	var l := UI.label(text, "", 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 420
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(4.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


const CHEST_ICONS := {"normal": 89, "rare": 90, "special": 92}


## Beute einer Truhe als kleine Liste mit Symbolen; blendet sich wie ein Toast selbst aus.
func loot_toast(title: String, icon: int, entries: Array) -> void:
	var p := PanelContainer.new()
	p.custom_minimum_size.x = 420
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := UI.hbox([UI.sprite(icon, 32), UI.label("%s geöffnet" % title, "H3")], 10)
	p.add_child(UI.vbox([head, LootView.list(entries, true)], 6))
	for c in p.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(5.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func level_up_toast(levels: int) -> void:
	Sound.play("levelup")
	toast("⭐ Level up! Du bist jetzt Level %d%s. HP und Fokus aufgefüllt." % [int(Ctx.profile.level), " (+%d)" % levels if levels > 1 else ""])
	hud.refresh()


func _fade_in(seconds: float) -> void:
	_flash.color = Color(0, 0, 0, 1)
	create_tween().tween_property(_flash, "color:a", 0.0, seconds)


func _flash_screen(c: Color, seconds: float) -> void:
	_flash.color = c
	create_tween().tween_property(_flash, "color:a", 0.0, seconds)


func _shake(seconds: float, strength: float) -> void:
	var cam := fx.camera
	var tw := create_tween()
	var n := int(seconds / 0.04)
	for i in n:
		var k := 1.0 - float(i) / n
		tw.tween_property(cam, "h_offset", randf_range(-strength, strength) * k, 0.04)
		tw.parallel().tween_property(cam, "v_offset", randf_range(-strength, strength) * k, 0.04)
	tw.tween_property(cam, "h_offset", 0.0, 0.04)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.04)


# ---------- Kristallaltar mit Händler ----------

## Rast am Altar: HP/Fokus sind schon aufgefüllt; der Händler bietet Gegenstände und Tränke für Gold an.
func open_altar(obj: Dictionary) -> UI.Modal:
	busy = true
	walk_time = 0.0
	var m := UI.modal(ui, "Kristallaltar", 900)
	m.closed.connect(func() -> void:
		busy = false
		_target_dirty = true
		hud.refresh()
		Ctx.autosave())
	var content := UI.vbox()
	m.body.add_child(content)
	_render_altar(content, obj)
	return m


func _render_altar(content: VBoxContainer, obj: Dictionary) -> void:
	UI.clear(content)
	var rerender := func() -> void:
		hud.refresh()
		_render_altar(content, obj)
	content.add_child(UI.para("Der Kristall leuchtet: HP und Fokus sind wieder voll. Hier erwachst du, falls du besiegt wirst.", "Good", 17))
	content.add_child(UI.hbox([UI.label("Händler", "H3"), UI.spacer(), UI.label("💰 %d Gold" % int(Ctx.profile.gold), "Accent", 18)]))
	var offers := Meta.shop_offers(run, Ctx.profile, obj.id)
	if offers.is_empty():
		content.add_child(UI.label("Der Händler hat nichts mehr für dich.", "Dim", 16))
	for item: Dictionary in offers:
		var price := Meta.shop_price(item)
		var buy := UI.button("Kaufen −%d 💰" % price, func() -> void:
			Ctx.set_profile(Meta.buy_item(Ctx.profile, item))
			Sound.play("coins")
			toast("Gekauft: %s (in der Tasche, anlegen mit I)" % item.name)
			rerender.call(), "SmallButton")
		buy.disabled = not Meta.can_buy_item(Ctx.profile, item)
		content.add_child(EquipmentView._item_card(item, buy))
	content.add_child(EquipmentView._merchant(rerender))


# ---------- Menü ----------

func open_menu() -> UI.Modal:
	busy = true
	walk_time = 0.0
	var m := UI.modal(ui, "Menü", 980)
	_clock_paused = true
	m.closed.connect(func() -> void:
		_clock_paused = false
		busy = false
		_refresh_speed()
		hud.refresh())
	var content := UI.vbox()
	var character := UI.button("Charakter & Inventar (I)", func() -> void:
		m.close()
		open_character(), "SmallButton")
	m.header.add_child(character)
	m.header.move_child(character, 1)
	m.body.add_child(content)
	var finish := UI.button("Abenteuer beenden", func() -> void:
		UI.confirm(ui, "Abenteuer jetzt beenden und zur Auswertung gehen? Dein Lernfortschritt bleibt gespeichert.", func() -> void:
			m.close()
			finish_run(false), "Beenden"), "DangerButton")
	var to_title := UI.button("Speichern & zum Titel", func() -> void:
		Ctx.autosave()
		m.close()
		get_tree().change_scene_to_file(TITLE))
	var resume := UI.button("Weiterspielen", m.close)
	m.body.add_child(UI.gap(8))
	m.body.add_child(UI.hbox([finish, UI.spacer(), to_title, resume]))
	_render_learning(content)
	UI.focus_later(resume)
	return m


## Talentwahl nach einem Level-up: eins von drei zufälligen Talenten (stapelbar, gilt bis Abenteuerende).
func open_talent_choice() -> UI.Modal:
	var owned: Array = Ctx.profile.talents
	_talent_options = Talents.roll(run.rng, owned)
	if _talent_options.is_empty():
		Ctx.profile.pendingTalents = 0
		return null
	busy = true
	walk_time = 0.0
	_clock_paused = true
	Sound.play("levelup")
	var m := UI.modal(ui, "⭐ Level %d – wähle ein Talent" % int(Ctx.profile.level), 900, false)
	_talent_modal = m
	var more := int(Ctx.profile.pendingTalents) - 1
	m.body.add_child(UI.label("Dein Talent wirkt bis zum Ende dieses Abenteuers.%s" % (" Danach darfst du noch %d× wählen." % more if more > 0 else ""), "Dim", 16))
	var row := UI.hbox([], 12)
	for i in _talent_options.size():
		var t: Dictionary = _talent_options[i]
		var r := Talents.rank(owned, t.id)
		var btn := UI.choice_card(i + 1, t.icon, t.name, Talents.text(t), "Stufe %d/%d" % [r + 1, int(t.max)])
		btn.pressed.connect(choose_talent.bind(i))
		row.add_child(btn)
	m.body.add_child(row)
	var hint := UI.label("Taste 1–3 oder klicken", "Dim", 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.body.add_child(hint)
	UI.focus_later(row.get_child(0) as Control)
	return m


func choose_talent(i: int) -> void:
	if _talent_modal == null or i < 0 or i >= _talent_options.size():
		return
	var t: Dictionary = _talent_options[i]
	Meta.add_talent(Ctx.profile, run, t.id)
	Sound.play("select")
	var m := _talent_modal
	_talent_modal = null
	m.close()
	toast("Talent: %s %s – %s" % [t.icon, t.name, Talents.text(t)])
	Ctx.clamp_run_stats()
	Ctx.profile_changed.emit()
	_clock_paused = false
	busy = false
	hud.refresh()
	Ctx.autosave()


## Charakterfenster mit Inventar (Taste I); die Uhr der Zeit-Challenge steht dabei still.
func open_character() -> UI.Modal:
	busy = true
	walk_time = 0.0
	_clock_paused = true
	Sound.play("select", 0.5)
	var m := CharacterWindow.open(ui)
	m.closed.connect(func() -> void:
		_clock_paused = false
		busy = false
		_target_dirty = true
		_refresh_speed()
		hud.refresh())
	return m


func _render_learning(content: VBoxContainer) -> void:
	UI.clear(content)
	var learning: LearningSession = run.learning
	var summary := learning.run.summary()
	var owed := learning.scheduler.owed_repeats()
	var cell := func(n: int, label: String, variation: String) -> VBoxContainer:
		var big := UI.label(str(n), variation, 40)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var l := UI.label(label, "Dim", 16)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var v := UI.vbox([big, l], 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return v
	content.add_child(UI.hbox([
		cell.call(int(summary.totalQuestions), "Abfragen", "Bold"),
		cell.call((summary.words as Array).size(), "verschiedene Wörter", "Bold"),
		cell.call((summary.firstTryCorrect as Array).size(), "sofort gewusst", "Good"),
		cell.call((summary.wrongWords as Array).size(), "noch üben", "Bad"),
	]))
	content.add_child(UI.label("Diese Wörter kommen bald noch einmal:", "H3"))
	if owed.is_empty():
		content.add_child(UI.label("Keine offenen Wiederholungen – super!", "Dim", 16))
	else:
		var flow := HFlowContainer.new()
		for i: Dictionary in owed:
			var chip := PanelContainer.new()
			chip.theme_type_variation = "Card"
			chip.add_child(UI.label(i.entry.de, "", 16))
			flow.add_child(chip)
		content.add_child(flow)


## Nur für Screenshots/Debugging: Beute der ersten (seltenen) Truhe zeigen, ohne Abfrage.
func debug_open_chest() -> void:
	for o: Dictionary in run.map.objects:
		if o.kind == "chest":
			o.chestType = "rare"
			grant_chest(o)
			return


## Nur für Screenshots/Debugging: Altar-Fenster am ersten Altar öffnen.
func debug_open_altar() -> void:
	for o: Dictionary in run.map.objects:
		if o.kind == "heal":
			Ctx.profile.gold = 60
			open_altar(o)
			return
