extends TestCase
## Vokabel-Abfrage, Level-Aufbau und Erkundung (Kollision, Interaktion, Truhen/Türen mit Vokabeln).

const EXPLORATION := preload("res://scenes/exploration.tscn")


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func item(en: String = "house", alternatives: Array = []) -> Dictionary:
	return {"key": "t/1", "entry": Vocab.entry("1", "Haus", en, alternatives)}


static func wallet(focus: int = 6, free: Dictionary = {}) -> Dictionary:
	return {"freeCharges": free, "focus": focus, "costs": {"length": 1, "firstLetter": 2}}


static func prompt(it: Dictionary, w: Dictionary, cancel := false) -> VocabPrompt:
	VocabPrompt.instant = true
	var p := VocabPrompt.create({"item": it, "wallet": w, "allow_cancel": cancel})
	root().add_child(p)
	return p


static func answer(p: VocabPrompt, text: String) -> void:
	p.input.text = text
	p._submit()


func test_abfrage_richtig() -> void:
	var p := prompt(item(), wallet())
	var out := []
	p.finished.connect(func(o: Dictionary) -> void: out.append(o))
	answer(p, "  house ")
	expect_eq(out.size(), 1, "Ergebnis gemeldet")
	expect_eq(out[0].result, Vocab.result("correct", 0))
	expect_false(out[0].cancelled)


func test_abfrage_falsch_dann_abtippen() -> void:
	var p := prompt(item(), wallet())
	var out := []
	p.finished.connect(func(o: Dictionary) -> void: out.append(o))
	answer(p, "House")
	expect_eq(p.phase, "correction", "Groß-/Kleinschreibung zählt")
	answer(p, "hous")
	expect_eq(p.phase, "correction", "Falsch abgetippt bleibt in der Korrektur")
	expect_true(out.is_empty())
	answer(p, "house")
	expect_eq(out.size(), 1)
	expect_eq(out[0].result.outcome, "wrongCorrected")


func test_abfrage_leere_eingabe_wird_ignoriert() -> void:
	var p := prompt(item(), wallet())
	answer(p, "   ")
	expect_eq(p.phase, "answer")
	p.free()


func test_abfrage_hilfen_kosten_fokus_oder_gratis() -> void:
	var p := prompt(item(), wallet(6, {"length": 1}))
	var changes := []
	p.wallet_changed.connect(func(w: Dictionary) -> void: changes.append(w))
	p.use_hint("length")
	expect_eq(int(p.wallet.freeCharges.length), 0, "Gratis-Ladung verbraucht")
	expect_eq(int(p.wallet.focus), 6, "Fokus unverändert")
	expect_eq(p._length.text, "5 Buchstaben")
	p.use_hint("length")
	expect_eq(changes.size(), 1, "Wortlänge nur einmal")
	p.use_hint("firstLetter")
	expect_eq(int(p.wallet.focus), 4, "Erster Buchstabe kostet 2 FP")
	expect_eq(p._mask.text, "h _ _ _ _")
	var out := []
	p.finished.connect(func(o: Dictionary) -> void: out.append(o))
	answer(p, "house")
	expect_eq(int(out[0].result.hintsUsed), 2)


func test_abfrage_abbrechen() -> void:
	var p := prompt(item(), wallet(), true)
	var out := []
	p.finished.connect(func(o: Dictionary) -> void: out.append(o))
	p.cancel()
	expect_true(out[0].cancelled)


func test_level_aufbau_hat_objekte_und_fackeln() -> void:
	var map := LevelGenerator.generate(777, GameConfig.section("level"), {"bossRunesRequired": 3, "enemies": GameData.get_theme("jungle").enemies})
	var lb := LevelBuilder.build(map)
	expect_eq(lb.views.size(), (map.objects as Array).size(), "Jedes Objekt hat eine Ansicht")
	expect_gt(lb.torches, 0, "Fackeln vorhanden")
	expect_gt(lb.root.find_children("*", "MeshInstance3D", true, false).size(), 4, "Gechunkte Meshes")
	for k: Vector2i in lb.solid_deco:
		expect_true(MapModel.is_floor(map, k.x, k.y), "Deko steht nur auf Boden")
	lb.root.free()


func _explore() -> Node3D:
	VocabPrompt.instant = true
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 4242)
	var e: Node3D = EXPLORATION.instantiate()
	root().add_child(e)
	return e


static func find_obj(e: Node3D, kind: String) -> Dictionary:
	for o: Dictionary in e.run.map.objects:
		if o.kind == kind:
			return o
	return {}


static func current_prompt(e: Node3D) -> VocabPrompt:
	for c in e.ui.get_children():
		if c is VocabPrompt and not c.is_queued_for_deletion():
			return c
	return null


func test_erkundung_kollision_und_bewegung() -> void:
	var e := _explore()
	var start: Vector2 = e.run.player
	expect_true(e.free_at(start.x, start.y), "Start ist frei")
	var heal := find_obj(e, "heal")
	expect_true(e.is_solid_tile(heal.x, heal.y), "Altar blockiert")
	expect_true(e.is_solid_tile(-5, -5), "Außerhalb ist fest")
	# Lange in eine Richtung laufen: man bleibt immer auf freiem Boden.
	for i in 200:
		e.move(Vector2(-1, 0), 0.05)
		expect_true(e.free_at(e.run.player.x, e.run.player.y))
	expect_lt(e.run.player.x, start.x + 0.001, "Nach links bewegt oder an Wand gestoppt")
	e.free()


func test_erkundung_altar_heilt() -> void:
	var e := _explore()
	Ctx.run.hp = 3
	Ctx.run.focus = 0
	var heal := find_obj(e, "heal")
	e.interact(heal)
	expect_eq(int(Ctx.run.hp), int(Ctx.stats().maxHp))
	expect_eq(int(Ctx.run.focus), int(Ctx.stats().maxFocus))
	expect_eq(Ctx.run.lastHeal, Vector2(heal.x + 0.5, heal.y + 0.5))
	expect_true(e.busy, "Altar-Fenster mit Händler offen")
	var buys: Array = e.ui.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text.begins_with("Kaufen −"))
	expect_ge(buys.size(), 2, "Gegenstände und Trank im Angebot")
	e.free()


func test_erkundung_siegeltor_braucht_runen() -> void:
	var e := _explore()
	var gate := find_obj(e, "bossDoor")
	e.interact(gate)
	expect_false(Ctx.run.opened.has(gate.id), "Ohne Runen bleibt es zu")
	Ctx.run.runes = int(gate.runes)
	e.interact(gate)
	expect_true(Ctx.run.opened.has(gate.id), "Mit Runen offen")
	expect_false(e.is_solid_tile(gate.x, gate.y), "Offenes Tor ist begehbar")
	e.free()


func test_erkundung_tuer_mit_vokabeln_oeffnen() -> void:
	var e := _explore()
	var door := find_obj(e, "door")
	e.interact(door)
	expect_true(e.busy, "Abfrage läuft")
	var asked := 0
	while current_prompt(e) != null and asked < 10:
		var p := current_prompt(e)
		answer(p, p.entry.en)
		asked += 1
	expect_eq(asked, int(door.answers), "So viele Vokabeln wie die Tür verlangt")
	expect_false(e.busy)
	expect_true(Ctx.run.opened.has(door.id), "Tür offen")
	expect_eq(int(Ctx.run.runes), 1, "+1 Rune")
	expect_eq((Ctx.run.learning as LearningSession).run.questions, asked, "Abfragen protokolliert")
	expect_false(e.level.views.has(door.id), "Geöffnete Tür verschwindet (Issue #13)")
	var rebuilt := LevelBuilder.build(Ctx.run.map, e.is_gone)
	expect_false(rebuilt.views.has(door.id), "… auch nach dem Laden")
	rebuilt.root.free()
	e.free()


func test_erkundung_truhe_abbrechen_und_oeffnen() -> void:
	var e := _explore()
	var chest := find_obj(e, "chest")
	e.interact(chest)
	current_prompt(e).cancel()
	expect_false(Ctx.run.opened.has(chest.id), "Abgebrochen bleibt zu")
	expect_false(e.busy)
	var gold := int(Ctx.profile.gold)
	e.interact(chest)
	var guard := 0
	while current_prompt(e) != null and guard < 10:
		var p := current_prompt(e)
		# Erst falsch, dann abtippen: zählt nicht als richtig, es folgt eine weitere Vokabel.
		if guard == 0:
			answer(p, "xyz")
		answer(p, p.entry.en)
		guard += 1
	expect_true(Ctx.run.opened.has(chest.id), "Truhe offen")
	expect_gt(int(Ctx.profile.gold), gold, "Beute erhalten")
	expect_ge(guard, 2, "Nach Fehler kam eine weitere Vokabel")
	e.free()


func test_erkundung_gegnerkontakt_startet_kampf() -> void:
	var e := _explore()
	var enemy := find_obj(e, "enemy")
	Ctx.run.player = Vector2(enemy.x + 0.5, enemy.y + 0.5)
	e.check_enemy_contact()
	expect_true(e.busy, "Kampf beginnt")
	e.free()


func test_urwald_nutzt_ausblend_shader() -> void:
	var map := LevelGenerator.generate(778, GameConfig.section("level"), {"bossRunesRequired": 3, "enemies": GameData.get_theme("jungle").enemies})
	var lb := LevelBuilder.build(map)
	var shaders := lb.root.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool:
		return m.material_override is ShaderMaterial)
	expect_gt(shaders.size(), 0, "Urwald-Meshes mit Shader")
	lb.root.free()
	var e := _explore()
	e._place_hero()
	expect_near(e.shader_player.x, e.run.player.x, 0.01, "Shader kennt die Heldenposition")
	e._set_world_active(false)
	e._place_hero()
	expect_lt(e.shader_player.y, -100.0, "Im Kampf aus")
	root().remove_child(e)
	expect_lt(e.shader_player.y, -100.0, "Nach Verlassen aus")
	e.free()


func test_zeit_challenge_endet_in_der_erkundung() -> void:
	VocabPrompt.instant = true
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 4242, 0, true)
	expect_eq(int(Ctx.run.timeLimit), RunScaling.time_limit_for(27), "Zeit nach Vokabelzahl")
	var e: Node3D = EXPLORATION.instantiate()
	root().add_child(e)
	Ctx.run.timeLeft = 2.0
	e.open_menu()
	e._process(5.0)
	expect_eq(float(Ctx.run.timeLeft), 2.0, "Im Menü steht die Uhr")
	for m in e.ui.get_children():
		if m is UI.Modal:
			(m as UI.Modal).close()
	e._process(1.0)
	expect_near(float(Ctx.run.timeLeft), 1.0, 0.01)
	expect_false(e.busy)
	e._process(1.5)
	expect_true(Ctx.time_up(), "Zeit abgelaufen")
	expect_true(e.busy, "Zeit-abgelaufen-Fenster blockiert")
	expect_true(e.ui.get_children().any(func(n: Node) -> bool: return n is UI.Modal and not n.is_queued_for_deletion()), "Fenster offen")
	e.free()


func test_abfrage_nach_fehler_sofort_tippbereit() -> void:
	var p := prompt(item(), wallet())
	p.input.grab_focus()
	p.input.edit()
	p.input.text = "falsch"
	# Echtes Enter, damit das Eingabefeld wie im Spiel reagiert.
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	p.get_viewport().push_input(enter)
	expect_eq(p.phase, "correction")
	expect_true(p.input.has_focus(), "Fokus im Eingabefeld (Issue #6)")
	expect_true(p.input.is_editing(), "Eingabefeld ist tippbereit")
	p.free()


func test_waffe_in_der_hand() -> void:
	var e := _explore()
	var w := e.hero.get_node_or_null("Weapon") as HeldWeapon
	expect_true(w != null, "Startwaffe in der Hand")
	expect_eq(w.item_id, str(Ctx.profile.equipment.weapon))
	var p: Vector3 = w.position
	e.hero.flip_h = true
	w._update()
	expect_true(w.flip_h, "Waffe spiegelt sich mit dem Helden")
	expect_near(w.position.x, -p.x, 0.001, "… und wechselt die Hand")
	Ctx.profile.equipment.weapon = "rune_blade"
	Ctx.profile_changed.emit()
	w = e.hero.get_node_or_null("Weapon") as HeldWeapon
	expect_eq(w.item_id, "rune_blade", "Neue Waffe nach Ausrüstungswechsel")
	expect_eq(w.get_child_count(), 1, "Seltene Waffe schimmert")
	Ctx.profile.equipment.weapon = null
	Ctx.profile_changed.emit()
	expect_true(e.hero.get_node_or_null("Weapon") == null or e.hero.get_node("Weapon").is_queued_for_deletion(), "Ohne Waffe nichts in der Hand")
	e.free()


func test_truhe_zeigt_beuteliste() -> void:
	var e := _explore()
	var gold := int(Ctx.profile.gold)
	e.debug_open_chest()
	expect_gt(int(Ctx.profile.gold), gold, "Gold gutgeschrieben")
	var texts: Array = e._toasts.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	expect_true(texts.has("Seltene Truhe geöffnet"), "Titel mit Truhe")
	expect_true(texts.has("Gold"), "Gold als eigene Zeile")
	e.free()


func test_inventar_mit_taste_i() -> void:
	Controls.ensure()
	var e := _explore()
	var key := InputEventKey.new()
	key.keycode = KEY_I
	key.physical_keycode = KEY_I
	key.pressed = true
	e._unhandled_input(key)
	expect_true(e.busy, "Charakterfenster offen")
	var w: Array = e.ui.find_children("*", "CharacterWindow", true, false)
	expect_eq(w.size(), 1, "Fenster im UI")
	(w[0] as CharacterWindow).modal.close()
	expect_false(e.busy, "Nach dem Schließen geht es weiter")
	e.free()


## Issue #8: Der Altar hat im Tileset einen Sandhintergrund, der entfernt wird.
func test_kacheln_ohne_sandhintergrund() -> void:
	for f: int in Assets.CUTOUT:
		var img := Assets.frame_image(f)
		expect_eq(img.get_pixel(0, 15).a, 0.0, "Kachel %d: Ecke durchsichtig" % f)
		expect_eq(img.get_pixel(15, 15).a, 0.0, "Kachel %d: Ecke durchsichtig" % f)
		expect_gt(img.get_pixel(8, 8).a, 0.0, "Kachel %d: Motiv bleibt" % f)
	expect_gt(Assets.frame_image(48).get_pixel(0, 15).a, 0.0, "Bodenkacheln bleiben unverändert")


## Issue #15: Keine Stachelfalle (Bodenkachel 41) auf den Mauern.
func test_keine_stacheln_an_der_wand() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 777)
	var level := LevelBuilder.build(Ctx.run.map)
	var spikes := LevelBuilder.uv_rect(41)
	var found := false
	for mi: MeshInstance3D in level.root.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi.mesh as ArrayMesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat := mi.material_override as BaseMaterial3D
			if mat == null or mat.albedo_texture != Assets.sheet(Assets.DUNGEON):
				continue
			for uv: Vector2 in mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]:
				if spikes.has_point(uv):
					found = true
	expect_false(found, "Stachel-Kachel an der Wand")
	level.root.free()


func test_hud_zeigt_xp_balken() -> void:
	var e := _explore()
	Ctx.gain_xp(20)
	e.hud.refresh()
	var bars: Array = e.hud.find_children("XpBar", "ProgressBar", true, false)
	expect_eq(bars.size(), 1, "XP-Balken in der Statusleiste (Issue #9)")
	var cfg := GameConfig.section("player")
	expect_eq(int(bars[0].value), int(Ctx.profile.xp) - int((cfg.xpPerLevel as Array)[int(Ctx.profile.level) - 1]))
	e.free()


## Issue #14: Jedes Level-up bringt eine Talentwahl; Talente wirken und stapeln sich.
func test_level_up_talentwahl() -> void:
	var e := _explore()
	var before := Ctx.stats()
	var need := Player.xp_for_next_level(1, GameConfig.section("player"))
	expect_eq(Ctx.gain_xp(need), 1, "Level-up")
	expect_eq(int(Ctx.profile.pendingTalents), 1, "Eine Talentwahl offen")
	e._process(0.01)
	expect_true(e._talent_modal != null, "Wahl öffnet sich in der Erkundung")
	expect_eq(e._talent_options.size(), 3, "Drei Talente zur Wahl")
	var t: Dictionary = e._talent_options[0]
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	e._unhandled_input(key)
	expect_true(e._talent_modal == null, "Mit Taste 1 gewählt")
	expect_false(e.busy)
	expect_eq(int(Ctx.profile.pendingTalents), 0)
	expect_eq(Ctx.profile.talents, [t.id])
	# Zähigkeit zweimal: +16 max. HP zusätzlich zum Level-Bonus.
	Ctx.profile.talents = ["t_vigor", "t_vigor"]
	var cfg := GameConfig.section("player")
	expect_eq(int(Ctx.stats().maxHp), int(before.maxHp) + int(cfg.hpPerLevel) + 16, "Talente stapeln sich")
	expect_eq(Talents.roll(Rng.create(1), ["t_hide", "t_hide"], 20).filter(func(x: Dictionary) -> bool: return x.id == "t_hide").size(), 0, "Ausgebaute Talente kommen nicht mehr")
	e.free()
	# Neues Abenteuer: Talente verfallen.
	Ctx.start_run(["sample"], "jungle", 1)
	expect_eq(Ctx.profile.talents, [])
