extends TestCase
## Rogue-lite: Tempelsplitter, Freischalten, Skillbäume, Reset pro Abenteuer, Belohnung.


static func pc() -> Dictionary:
	return GameConfig.section("player")


static func fresh() -> Dictionary:
	return Player.normalize({}, pc())


static func rich(shards: int = 500) -> Dictionary:
	var p := fresh()
	p.shards = shards
	return p


func test_neues_profil_nur_krieger() -> void:
	var p := fresh()
	expect_eq(p.unlockedClasses, ["warrior"])
	expect_eq(int(p.shards), 0)
	expect_true(Meta.is_class_unlocked(p, "warrior"))
	expect_false(Meta.is_class_unlocked(p, "mage"))


func test_alter_spielstand_wird_ergaenzt() -> void:
	var p := Player.normalize({"heroClass": "mage", "level": 4, "gold": 30}, pc())
	expect_eq(p.heroClass, "warrior", "Gesperrte Klasse fällt auf Krieger zurück")
	expect_true(p.skills.has("rogue"))
	expect_eq(int(p.records.runs), 0)


func test_klasse_freischalten() -> void:
	var p := rich(24)
	expect_false(Meta.can_unlock_class(p, "rogue"), "25 nötig")
	expect_true(is_same(Meta.unlock_class(p, "rogue"), p), "Unverändert ohne genug Splitter")
	p.shards = 30
	var u := Meta.unlock_class(p, "rogue")
	expect_true(Meta.is_class_unlocked(u, "rogue"))
	expect_eq(int(u.shards), 5)
	expect_false(Meta.can_unlock_class(u, "rogue"), "Schon freigeschaltet")


func test_skill_lernen_voraussetzung_kosten_maximum() -> void:
	var p := rich(100)
	var check := Meta.can_learn(p, "warrior", "w_shieldwall")
	expect_false(check.ok, "Stufe 2 braucht Stufe 1")
	expect_true(String(check.reason).contains("Zähigkeit"))
	p = Meta.learn(p, "warrior", "w_toughness")
	expect_eq(int(p.shards), 97, "Rang 1 kostet 3")
	p = Meta.learn(p, "warrior", "w_toughness")
	expect_eq(int(p.shards), 91, "Rang 2 kostet 6")
	p = Meta.learn(p, "warrior", "w_toughness")
	expect_eq(Meta.rank(p, "warrior", "w_toughness"), 3)
	expect_false(Meta.can_learn(p, "warrior", "w_toughness").ok, "Maximum erreicht")
	expect_true(Meta.can_learn(p, "warrior", "w_shieldwall").ok, "Jetzt frei")
	expect_eq(Meta.invested(p, "warrior"), 18)
	expect_false(Meta.can_learn(p, "rogue", "r_swift").ok, "Gesperrte Klasse")


func test_skills_wirken_auf_werte() -> void:
	var p := rich()
	var base := Player.compute_stats(p, pc())
	for i in 3:
		p = Meta.learn(p, "warrior", "w_toughness")
		p = Meta.learn(p, "warrior", "w_strength")
		p = Meta.learn(p, "warrior", "w_stride")
	var s := Player.compute_stats(p, pc())
	expect_eq(int(s.maxHp), int(base.maxHp) + 18)
	expect_eq(int(s.attack), int(base.attack) + 3)
	expect_near(Meta.mod(s.mods, "moveSpeed"), 0.24)
	expect_eq(s.freeHints, base.freeHints, "Keine Vokabelhilfen durch Skills")


func test_kampfwerte_mit_skills() -> void:
	var cls := GameData.get_class_def("rogue")
	var base := {"hp": 20, "maxHp": 30, "focus": 6, "maxFocus": 6, "attack": 5, "potions": 1}
	var mods := {"defend": 0.1, "armor": 1, "potionHeal": 5, "poisonTurns": 1, "skillPower": 0.3, "critChance": 0.05}
	var p := CombatService.combat_player_from(base, cls, mods)
	expect_near(float(p.defendFactor), 0.4)
	expect_eq(int(p.skill.poisonTurns), 4)
	expect_near(float(p.skill.multiplier), 1.5)
	expect_near(float(p.critChance), 0.3)
	expect_near(float(cls.skill.multiplier), 1.2, 0.001, "Klassendaten bleiben unverändert")
	var state := CombatService.create_combat(p, CombatService.create_enemy(GameData.get_enemy("bat"), 1))
	var ev := CombatService.resolve_player_action(state, "item", true, GameConfig.section("combat"), Rng.create(1))
	expect_eq(int(ev[0].amount), 10, "Trank heilt bis max. HP (18+5, gekappt)")
	state.enemy.intent = "attack"
	var hp := int(state.player.hp)
	var no_armor := CombatService.create_combat(CombatService.combat_player_from(base, cls), CombatService.create_enemy(GameData.get_enemy("bat"), 1))
	no_armor.enemy.intent = "attack"
	CombatService.resolve_enemy_turn(state, Rng.create(9))
	CombatService.resolve_enemy_turn(no_armor, Rng.create(9))
	expect_eq(hp - int(state.player.hp), 20 - int(no_armor.player.hp) - 1, "Rüstung hält 1 Schaden ab")


func test_abenteuer_setzt_laufwerte_zurueck() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.profile.level = 5
	Ctx.profile.gold = 99
	Ctx.profile.bag = ["knight_helm"]
	Ctx.profile.equipment.ring = "copper_ring"
	Ctx.profile.shards = 100
	Ctx.set_profile(Meta.learn(Meta.learn(Ctx.profile, "warrior", "w_stride"), "warrior", "w_supplies"))
	Ctx.start_run(["sample"], "jungle", 3)
	expect_eq(int(Ctx.profile.level), 1)
	expect_eq(int(Ctx.profile.gold), 0)
	expect_eq(Ctx.profile.bag, [])
	expect_eq(Ctx.profile.equipment, Meta.START_EQUIPMENT)
	expect_eq(int(Ctx.profile.potions), int(pc().startPotions) + 1, "Feldration: +1 Trank")
	expect_eq(int(Ctx.profile.shards), 91, "Splitter bleiben")
	expect_near(Ctx.move_speed_factor(), 1.08)
	expect_eq(int(Ctx.run.hp), int(Ctx.stats().maxHp))


func test_belohnung_und_einmalige_auszahlung() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 3)
	var run: Dictionary = Ctx.run
	var n := 0
	for o: Dictionary in run.map.objects:
		if o.kind == "enemy" and o.tier == "normal" and n < 2:
			run.defeated[o.id] = true
			n += 1
		elif o.kind == "chest":
			run.opened[o.id] = true
	var chests := (run.map.objects as Array).filter(func(o: Dictionary) -> bool: return o.kind == "chest").size()
	var learning: LearningSession = run.learning
	for i in 10:
		Ctx.submit_answer(learning.next_word("normal"), Vocab.result("correct", 0))
	var r := Ctx.end_run(true)
	var c: Dictionary = Meta.cfg().shards
	expect_eq(int(r.total), 2 * int(c.normalEnemy) + chests * int(c.chest) + 10 / int(c.correctPer) + int(c.victory))
	expect_eq(int(Ctx.profile.shards), int(r.total))
	expect_eq(int(Ctx.profile.records.runs), 1)
	expect_eq(int(Ctx.profile.records.victories), 1)
	var again := Ctx.end_run(true)
	expect_eq(int(Ctx.profile.shards), int(r.total), "Kein zweites Mal")
	expect_eq(int(again.total), int(r.total), "Gleiche Belohnung zur Anzeige")


func test_splitterbonus_und_goldfund() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.profile.unlockedClasses = ["warrior", "rogue"]
	Ctx.profile.heroClass = "rogue"
	Ctx.profile.skills.rogue = {"r_swift": 1, "r_pockets": 2, "r_fence": 2}
	Ctx.start_run(["sample"], "jungle", 3)
	var loot := {"gold": 10, "potions": 0, "itemId": null}
	Ctx.apply_loot(loot)
	expect_eq(int(Ctx.profile.gold), 15, "+50 % Gold")
	expect_eq(int(loot.gold), 15, "Beute zeigt den Bonus")
	var r := Meta.run_reward(Ctx.run, true, Ctx.profile)
	expect_eq(int(r.total), int(Meta.cfg().shards.victory) + int(floor(int(Meta.cfg().shards.victory) * 0.3)), "+30 % Splitter")


func test_skillbaeume_vollstaendig_und_ohne_vokabelhilfe() -> void:
	for c: Dictionary in GameData.HERO_CLASSES:
		var t := SkillTrees.tree(c.id)
		expect_eq((t.nodes as Array).size(), 9, "%s: 9 Knoten" % c.id)
		for n: Dictionary in t.nodes:
			for key: String in n.effect:
				expect_true(SkillTrees.EFFECT_TEXT.has(key), "Bekannter Effekt %s" % key)
			if n.requires != "":
				var req := SkillTrees.get_node_def(c.id, n.requires)
				expect_eq(int(req.tier), int(n.tier) - 1, "Voraussetzung eine Stufe davor")
				expect_eq(int(req.branch), int(n.branch), "Gleicher Zweig")


func test_skillbaum_oberflaeche_kaufen() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.profile.shards = 10
	var box := VBoxContainer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(box)
	SkillTreeView.render(box, "warrior")
	var learn: Array = box.find_children("*", "Button", true, false).filter(func(b: Button) -> bool:
		return b.text.begins_with("Lernen") and not b.disabled)
	expect_eq(learn.size(), 3, "Drei Stufe-1-Knoten kaufbar")
	(learn[0] as Button).pressed.emit()
	expect_eq(int(Ctx.profile.shards), 7)
	SkillTreeView.render(box, "rogue")
	var unlock: Array = box.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text.begins_with("🔓"))
	expect_eq(unlock.size(), 1, "Freischalten angeboten")
	expect_true((unlock[0] as Button).disabled, "Zu wenige Splitter")
	box.free()


func test_keine_gegenstaende_mit_gratis_hilfen() -> void:
	for item: Dictionary in GameData.ITEMS:
		expect_false((item.effects as Dictionary).has("freeHints"), "%s gibt Gratis-Hilfen" % item.id)
		for key: String in item.effects:
			expect_true(key in Player.BASE_KEYS or SkillTrees.EFFECT_TEXT.has(key), "%s: unbekannter Effekt %s" % [item.id, key])


func test_gegenstand_effekte_wirken_wie_skills() -> void:
	var p := rich()
	p.equipment.ring = "wanderer_ring"
	p.equipment.weapon = "rune_blade"
	var s := Player.compute_stats(p, pc())
	expect_near(Meta.mod(s.mods, "moveSpeed"), 0.12)
	expect_near(Meta.mod(s.mods, "skillPower"), 0.3)


func test_leben_und_segnungen() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 3)
	expect_eq(int(Ctx.profile.lives), int(Meta.cfg().lives))
	expect_true(Meta.lose_life(Ctx.profile))
	expect_true(Meta.lose_life(Ctx.profile))
	expect_false(Meta.lose_life(Ctx.profile), "Drittes Mal: vorbei")
	var hp := int(Ctx.run.hp)
	var base := int(Ctx.stats().maxHp)
	Meta.add_blessing(Ctx.profile, Ctx.run, "b_oak")
	Meta.add_blessing(Ctx.profile, Ctx.run, "b_oak")
	expect_eq(Ctx.profile.blessings, ["b_oak"], "Keine doppelte Segnung")
	expect_eq(int(Ctx.stats().maxHp), base + 8)
	expect_eq(int(Ctx.run.hp), hp + 8)
	var choices := Blessings.roll(Rng.create(5), Ctx.profile.blessings, 3)
	expect_eq(choices.size(), 3)
	expect_false(choices.any(func(b: Dictionary) -> bool: return b.id == "b_oak"))
	Ctx.start_run(["sample"], "jungle", 4)
	expect_eq(Ctx.profile.blessings, [], "Segnungen verfallen mit dem Abenteuer")
	expect_eq(int(Ctx.profile.lives), int(Meta.cfg().lives))


func test_haendler_angebote_fest_und_kaufbar() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 11)
	var a := Meta.shop_offers(Ctx.run, Ctx.profile, "o0")
	expect_eq(a.size(), int(Meta.cfg().shopOffers))
	expect_eq(Meta.shop_offers(Ctx.run, Ctx.profile, "o0"), a, "Gleiche Angebote beim erneuten Besuch")
	var item: Dictionary = a.filter(func(i: Dictionary) -> bool: return i.id != "wooden_sword")[0]
	expect_false(Meta.can_buy_item(Ctx.profile, item), "Ohne Gold nicht kaufbar")
	Ctx.profile.gold = 200
	Ctx.set_profile(Meta.buy_item(Ctx.profile, item))
	expect_eq(int(Ctx.profile.gold), 200 - Meta.shop_price(item))
	expect_true((Ctx.profile.bag as Array).has(item.id))
	expect_false(Meta.shop_offers(Ctx.run, Ctx.profile, "o0").has(item), "Gekauftes verschwindet")
