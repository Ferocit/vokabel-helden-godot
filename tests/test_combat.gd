extends TestCase
## Kampfszene: Befehle, Vokabeln, Ereignisse, Sieg und Niederlage (synchron im fast-Modus).

const COMBAT := preload("res://scenes/combat.tscn")
const EXPLORATION := preload("res://scenes/exploration.tscn")


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func start_run(hero_class: String = "warrior") -> void:
	VocabPrompt.instant = true
	Ctx.setup(KeyValueStore.new())
	Ctx.profile.unlockedClasses = ["warrior", "rogue", "mage"]
	Ctx.profile.heroClass = hero_class
	Ctx.start_run(["sample"], "jungle", 4242)


static func enemy_of(tier: String) -> Dictionary:
	for o: Dictionary in Ctx.run.map.objects:
		if o.kind == "enemy" and o.tier == tier:
			return o
	return {}


static func open_combat(tier: String = "normal") -> Node:
	var c: Node = COMBAT.instantiate()
	c.fast = true
	c.object_id = enemy_of(tier).id
	root().add_child(c)
	return c


static func prompt_of(c: Node) -> VocabPrompt:
	for n in c.ui.get_children():
		if n is VocabPrompt and not n.is_queued_for_deletion():
			return n
	return null


## Befehl wählen und die Vokabel richtig oder falsch (mit Abtippen) beantworten.
static func act(c: Node, index: int, correct: bool) -> void:
	c.choose(index)
	var p := prompt_of(c)
	if p == null:
		return
	if correct:
		p.input.text = p.entry.en
		p._submit()
	else:
		p.input.text = "falsch!"
		p._submit()
		p.input.text = p.entry.en
		p._submit()


func test_kampf_sieg_mit_richtigen_antworten() -> void:
	start_run()
	var c := open_combat()
	var out := []
	c.finished.connect(func(d: Dictionary) -> void: out.append(d))
	var obj := enemy_of("normal")
	var xp := int(Ctx.profile.xp)
	var rounds := 0
	while c.state.outcome == "ongoing" and rounds < 30:
		act(c, 0, true)
		rounds += 1
	expect_eq(c.state.outcome, "won", "Gegner besiegt")
	expect_true(c._result_modal != null, "Ergebnisfenster offen")
	c.close_result()
	expect_eq(out.size(), 1, "finished gemeldet")
	expect_eq(out[0].outcome, "won")
	expect_false(out[0].victory, "Kein Boss → kein Spielende")
	expect_true(Ctx.run.defeated.has(obj.id))
	expect_eq(int(Ctx.run.runes), 1, "+1 Rune")
	expect_gt(int(Ctx.profile.xp), xp, "XP erhalten")


func test_kampf_falsche_antwort_verpufft() -> void:
	start_run()
	var c := open_combat()
	var hp_before := int(c.state.enemy.hp)
	var asked := (Ctx.run.learning as LearningSession).run.questions
	act(c, 0, false)
	expect_eq(int(c.state.enemy.hp), hp_before, "Kein Schaden am Gegner")
	expect_eq((Ctx.run.learning as LearningSession).run.questions, asked + 1, "Abfrage gezählt")
	expect_eq(c.state.outcome, "ongoing")
	c.free()


func test_kampf_gesperrte_aktion_wird_abgelehnt() -> void:
	start_run()
	var c := open_combat()
	c.choose(3)  # Heiltrank bei vollen HP
	expect_true(prompt_of(c) == null, "Keine Abfrage für gesperrte Aktion")
	expect_true(c._menu_active, "Menü bleibt aktiv")
	c.free()


func test_kampf_niederlage_heilt_und_meldet() -> void:
	start_run()
	var c := open_combat("elite")
	var out := []
	c.finished.connect(func(d: Dictionary) -> void: out.append(d))
	c.state.player.hp = 1
	c.state.enemy.intent = "heavy"
	act(c, 0, false)
	expect_eq(c.state.outcome, "lost", "Besiegt")
	c.close_result()
	expect_eq(out[0].outcome, "lost")
	expect_eq(int(Ctx.run.hp), int(Ctx.stats().maxHp), "Volle HP am Altar")


func test_kampf_klassenfaehigkeiten() -> void:
	for cls in ["warrior", "rogue", "mage"]:
		start_run(cls)
		var c := open_combat("elite")
		var hp_before := int(c.state.enemy.hp)
		act(c, 2, true)  # Fähigkeit
		expect_lt(int(c.state.enemy.hp), hp_before, "%s: Fähigkeit trifft" % cls)
		if cls == "rogue":
			expect_true(c.state.enemy.poison != null or c.state.outcome != "ongoing", "Giftklinge vergiftet")
		c.free()


func test_kampf_verteidigen_halbiert_schaden() -> void:
	start_run()
	var c := open_combat("elite")
	c.state.enemy.intent = "heavy"
	c.state.enemy.guarding = false
	var hp := int(c.state.player.hp)
	act(c, 1, true)
	var taken := hp - int(c.state.player.hp)
	expect_gt(taken, 0, "Schaden trotz Verteidigung")
	expect_le(taken, int(ceil(c.state.enemy.attack * 2.0 * 0.3)) + 1, "Krieger hält 70 % ab")
	c.free()


func test_erkundung_kampf_rueckkehr() -> void:
	start_run()
	var e: Node3D = EXPLORATION.instantiate()
	e.fast = true
	root().add_child(e)
	var obj := enemy_of("normal")
	e.start_combat(obj)
	# Zuletzt eingehängtes Kind (ältere Kampfknoten warten evtl. noch auf queue_free).
	var c: Node = root().get_child(root().get_child_count() - 1)
	expect_true(c.has_signal("command_chosen"), "Kampfszene geöffnet")
	expect_false(e.ui.visible, "Erkundungs-UI ausgeblendet")
	c.fast = true
	var rounds := 0
	while c.state.outcome == "ongoing" and rounds < 30:
		act(c, 0, true)
		rounds += 1
	c.close_result()
	expect_true(e.ui.visible, "Zurück in der Erkundung")
	expect_false(e.busy)
	expect_true(e.fx.camera.current, "Erkundungskamera aktiv")
	expect_false(e.level.views.has(obj.id), "Gegner verschwindet")
	e.free()


func test_kampf_letztes_leben_beendet_abenteuer() -> void:
	start_run()
	Ctx.profile.lives = 1
	var c := open_combat("elite")
	var out := []
	c.finished.connect(func(d: Dictionary) -> void: out.append(d))
	c.state.player.hp = 1
	c.state.enemy.intent = "heavy"
	act(c, 0, false)
	c.close_result()
	expect_true(out[0].get("gameOver", false), "Spielende gemeldet")
	expect_eq(int(Ctx.profile.lives), 0)


func test_kampf_elite_sieg_bietet_segnung() -> void:
	start_run()
	var c := open_combat("elite")
	var out := []
	c.finished.connect(func(d: Dictionary) -> void: out.append(d))
	c.state.enemy.hp = 1
	act(c, 0, true)
	expect_eq(c.state.outcome, "won")
	c.close_result()
	expect_true(c._blessing_modal != null, "Segnungswahl offen")
	expect_true(out.is_empty(), "Kampf endet erst nach der Wahl")
	var chosen: Dictionary = c._blessing_options[1]
	c.choose_blessing(1)
	expect_eq(Ctx.profile.blessings, [chosen.id])
	expect_eq(out.size(), 1)


func test_erkundung_spielende_fuehrt_zur_auswertung() -> void:
	start_run()
	var e: Node3D = EXPLORATION.instantiate()
	e.fast = true
	root().add_child(e)
	e.on_combat_return({"objectId": "x", "outcome": "lost", "messages": [], "gameOver": true})
	var s: Node = root().get_child(root().get_child_count() - 1)
	expect_eq(String(s.name), "Summary")
	expect_false(s.victory)
	expect_true(Ctx.run.completed)
	(Engine.get_main_loop() as SceneTree).current_scene = null
	root().remove_child(s)
	s.free()


func test_kampf_zeit_challenge_abgelaufen() -> void:
	start_run()
	Ctx.run.timeChallenge = true
	Ctx.run.timeLeft = 30.0
	var c := open_combat("elite")
	var out := []
	c.finished.connect(func(d: Dictionary) -> void: out.append(d))
	expect_true(c.ui.find_children("*", "Label", true, false).any(func(n: Node) -> bool: return n is Hud.Clock), "Uhr im Kampf")
	Ctx.run.timeLeft = 0.0
	act(c, 0, true)
	expect_true(c._result_modal != null, "Zeit-abgelaufen-Fenster")
	c.close_result()
	expect_eq(out.size(), 1)
	expect_true(out[0].get("gameOver", false), "Abenteuer endet")


func test_kampf_held_links_gegner_rechts() -> void:
	start_run()
	var c := open_combat()
	expect_lt(c.HERO_POS.x, c.ENEMY_POS.x, "Held steht links")
	var bottom: Node = c._party_panel.get_parent().get_parent()
	expect_lt(c._party_panel.get_parent().get_index(), c._enemy_panel.get_parent().get_index(), "Heldenanzeige links")
	expect_eq(bottom, c._enemy_panel.get_parent().get_parent())
	expect_true(c._enemy_panel.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "HP %d/%d" % [int(c.state.enemy.hp), int(c.state.enemy.maxHp)]), "Gegner-HP als Zahl (Issue #1)")
	c.free()


func test_kampf_befehle_erklaeren_ihre_wirkung() -> void:
	start_run("rogue")
	var c := open_combat()
	var cfg := GameConfig.section("combat")
	var atk := int(c.state.player.attack)
	expect_eq(CombatService.action_effect("attack", c.state, cfg), "Trifft für %d–%d Schaden. 25 %% Chance auf einen kritischen Treffer (×1.8)." % [atk, atk + 2])
	expect_true(CombatService.action_effect("skill", c.state, cfg).contains("Gift: 3 Runden"), "Giftklinge nennt das Gift")
	expect_true(CombatService.action_effect("defend", c.state, cfg).begins_with("Der nächste gegnerische Angriff macht nur"))
	c._command_buttons[1].focus_entered.emit()
	expect_eq(c._command_info.text, CombatService.action_effect("defend", c.state, cfg), "Erklärung zum gewählten Befehl (Issue #7)")
	c.state.enemy.guarding = true
	expect_true(CombatService.action_effect("attack", c.state, cfg).contains("gepanzert"), "Panzer wird erwähnt")
	c.free()


func test_kampf_waffe_schwingt() -> void:
	start_run()
	var c := open_combat()
	expect_true(c.weapon != null, "Waffe in der Hand")
	expect_eq(c.weapon.get_parent(), c.hero)
	c.free()
