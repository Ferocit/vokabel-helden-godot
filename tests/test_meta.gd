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


func test_pakt_freischalten_und_belohnung() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 3, {"p_hp": 2})
	expect_eq(Ctx.run.pact, {}, "Ohne Sieg kein Pakt")
	Ctx.end_run(false)
	expect_eq(Meta.heat_max_unlocked(Ctx.profile), 0, "Abbruch schaltet nichts frei")
	Ctx.start_run(["sample"], "jungle", 3, {})
	Ctx.end_run(true)
	expect_eq(Meta.heat_max_unlocked(Ctx.profile), 1, "Sieg schaltet Pakt-Stufe 1 frei")
	expect_eq(Pact.cap(Ctx.profile), 3)
	Ctx.start_run(["sample"], "jungle", 3, {"p_hp": 1, "p_nohints": 1, "p_atk": 3})
	expect_eq(Pact.points(Ctx.run.pact), 3, "auf freie Punkte begrenzt")
	expect_eq(int(Ctx.run.heat), 3)
	expect_false(Ctx.hints_allowed(), "Ohne Hilfen")
	var saved: Dictionary = Ctx.run.pact.duplicate()
	Ctx.autosave()
	expect_eq(Ctx.resume_run().pact, saved, "Pakt bleibt beim Fortsetzen erhalten")
	var r := Meta.run_reward(Ctx.run, true, Ctx.profile)
	var base := int(Meta.cfg().shards.victory)
	expect_eq(int(r.total), base + int(floor(base * Pact.shard_bonus(saved))))
	Ctx.end_run(true)
	expect_eq(Meta.heat_max_unlocked(Ctx.profile), 2, "Sieg mit vollen Punkten schaltet weiter frei")
	var e0 := CombatService.create_enemy(GameData.get_enemy("bat"), 1, null, {})
	var e2 := CombatService.create_enemy(GameData.get_enemy("bat"), 1, null, 2)
	expect_gt(int(e2.hp), int(e0.hp), "alte Tempelstufe als Zahl geht weiter")
	expect_gt(int(e2.attack), int(e0.attack))


func test_pakt_regeln() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.profile.records.heatUnlocked = 5
	Ctx.start_run(["sample"], "jungle", 11, {"p_supplies": 2, "p_lives": 1, "p_elite": 2, "p_greed": 2, "p_reverse": 2})
	expect_eq(int(Ctx.profile.potions), 0, "Karge Vorräte")
	expect_eq(int(Ctx.profile.lives), int(Meta.cfg().lives) - 1, "Zerbrechlich")
	var elites: Array = Ctx.run.map.objects.filter(func(o: Dictionary) -> bool: return o.kind == "enemy" and o.tier == "elite")
	expect_ge(elites.size(), int(GameConfig.section("level").eliteEnemies.min) + 2, "Elite-Horden")
	var item := GameData.get_item("iron_sword")
	expect_eq(Meta.shop_price(item, Ctx.run), Meta.shop_price(item) * 2, "Gierige Händler")
	var card := (Ctx.run.learning as LearningSession).next_word()
	var shown := Ctx.prompt_item(card)
	expect_eq(shown.entry.de, card.entry.en, "Umgekehrte Richtung zeigt Englisch")
	expect_eq(shown.entry.en, card.entry.de)
	expect_eq(shown.key, card.key)
	expect_true(Pact.sanitize({"p_hp": 5, "p_atk": 5}, {"records": {"heatUnlocked": 1}}).size() >= 1)
	expect_eq(Pact.points(Pact.sanitize({"p_hp": 5, "p_atk": 5}, {"records": {"heatUnlocked": 1}})), 3)


func test_zeit_challenge_zeit_und_bonus() -> void:
	var c := GameConfig.section("timeChallenge")
	expect_eq(RunScaling.time_limit_for(1), int(c.minSeconds), "Untergrenze")
	expect_eq(RunScaling.time_limit_for(10000), int(c.maxSeconds), "Obergrenze")
	expect_gt(RunScaling.time_limit_for(80), RunScaling.time_limit_for(40), "Mehr Vokabeln, mehr Zeit")
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 99, 0, true)
	var normal := Meta.run_reward(Ctx.run, true, Ctx.profile)
	expect_true((normal.lines as Array).any(func(l: Array) -> bool: return String(l[0]).begins_with("Zeit-Challenge")), "Bonus bei Sieg")
	expect_false((Meta.run_reward(Ctx.run, false, Ctx.profile).lines as Array).any(func(l: Array) -> bool: return String(l[0]).begins_with("Zeit-Challenge")), "kein Bonus ohne Sieg")
	Ctx.tick_time(12.5)
	var snap := Ctx.snapshot_run()
	Ctx.save.save_run(snap)
	Ctx.resume_run()
	expect_true(Ctx.run.timeChallenge, "Modus bleibt beim Fortsetzen")
	expect_near(float(Ctx.run.timeLeft), float(Ctx.run.timeLimit) - 12.5, 0.01, "Restzeit bleibt erhalten")


# ---------- Regel-Segnungen und -Talente (Issue #20) ----------

static func rule_combat(effects: Dictionary, attack: int = 10) -> Dictionary:
	var base := {"hp": 30, "maxHp": 60, "focus": 2, "maxFocus": 6, "attack": attack, "potions": 0}
	var p := CombatService.combat_player_from(base, GameData.get_class_def("warrior"), effects)
	p.critChance = 0.0
	return CombatService.create_combat(p, CombatService.create_enemy(GameData.get_enemy("temple_cyclops"), 1))


static func damage_of(state: Dictionary) -> int:
	return int(state.enemy.maxHp) - int(state.enemy.hp)


func test_segnungen_und_talente_texte_bekannt() -> void:
	for list: Array in [Blessings.ALL, Blessings.DUOS, Talents.ALL]:
		for b: Dictionary in list:
			for key: String in b.effect:
				expect_true(key in Player.BASE_KEYS or SkillTrees.EFFECT_TEXT.has(key), "%s: %s" % [b.id, key])
			expect_ne(Talents.text(b) if list == Talents.ALL else Blessings.text(b), "")


func test_kettenblitz_bei_kombo_3() -> void:
	var rng := func() -> float: return 0.5
	var plain := rule_combat({})
	plain.player.combo = 3
	var chain := rule_combat({"chainStrike": 1})
	chain.player.combo = 3
	CombatService.resolve_player_action(plain, "attack", true, GameConfig.section("combat"), rng)
	var ev := CombatService.resolve_player_action(chain, "attack", true, GameConfig.section("combat"), rng)
	expect_eq(ev[0].type, "chain")
	expect_eq(damage_of(chain), damage_of(plain) * 2)
	var off := rule_combat({"chainStrike": 1})
	off.player.combo = 2
	CombatService.resolve_player_action(off, "attack", true, GameConfig.section("combat"), rng)
	expect_eq(damage_of(off), damage_of(plain), "Kombo 2: kein Kettenblitz")


func test_rache_des_gelehrten() -> void:
	var rng := func() -> float: return 0.5
	var plain := rule_combat({})
	var rev := rule_combat({"revenge": 1.0})
	rev.player.revengeWord = true
	CombatService.resolve_player_action(plain, "attack", true, GameConfig.section("combat"), rng)
	CombatService.resolve_player_action(rev, "attack", true, GameConfig.section("combat"), rng)
	expect_eq(damage_of(rev), damage_of(plain) * 2)


func test_erstschlag_krit_heilt_und_gibt_fokus() -> void:
	var rng := func() -> float: return 0.5
	var s := rule_combat({"firstStrike": 1, "critHeal": 4, "critFocus": 1})
	var ev := CombatService.resolve_player_action(s, "attack", true, GameConfig.section("combat"), rng)
	expect_true(ev.any(func(e: Dictionary) -> bool: return e.type == "damage" and e.crit), "erster Treffer kritisch")
	expect_eq(int(s.player.hp), 34)
	expect_eq(int(s.player.focus), 3)
	ev = CombatService.resolve_player_action(s, "attack", true, GameConfig.section("combat"), rng)
	expect_false(ev.any(func(e: Dictionary) -> bool: return e.type == "damage" and e.crit), "zweiter Treffer normal")


func test_gift_stapelt_sich() -> void:
	var base := {"hp": 30, "maxHp": 60, "focus": 6, "maxFocus": 6, "attack": 10, "potions": 0}
	var p := CombatService.combat_player_from(base, GameData.get_class_def("rogue"), {"poisonStack": 1})
	var s := CombatService.create_combat(p, CombatService.create_enemy(GameData.get_enemy("temple_cyclops"), 1))
	var rng := func() -> float: return 0.5
	CombatService.resolve_player_action(s, "skill", true, GameConfig.section("combat"), rng)
	var first: Dictionary = s.enemy.poison.duplicate()
	CombatService.resolve_player_action(s, "skill", true, GameConfig.section("combat"), rng)
	expect_eq(int(s.enemy.poison.turns), int(first.turns) * 2)
	expect_eq(int(s.enemy.poison.damage), int(first.damage) * 2)


func test_duo_segnungen() -> void:
	var p := rich()
	p.blessings = ["b_stone"]
	var before := Player.compute_stats(p, pc())
	expect_eq(Blessings.duos_completed_by(p.blessings, "b_prayer").size(), 1)
	p.blessings = ["b_stone", "b_prayer"]
	var after := Player.compute_stats(p, pc())
	expect_near(Meta.mod(after.mods, "armor"), Meta.mod(before.mods, "armor") + 1.0, 0.001, "Duo-Festung: +1 Rüstung")
	expect_near(Meta.mod(after.mods, "defend"), Meta.mod(before.mods, "defend") + 0.2, 0.001, "Schildgebet + Duo")
	expect_eq(Blessings.active_duos(p.blessings).size(), 1)


func test_segnungen_klasse_und_seltenheit() -> void:
	var seen := {}
	for i in 200:
		for b: Dictionary in Blessings.roll(Rng.create(i), [], 3, "warrior"):
			seen[b.id] = int(seen.get(b.id, 0)) + 1
	expect_false(seen.has("b_venom"), "Schurken-Segnung nicht für Krieger")
	expect_true(seen.has("b_chain"), "legendäre Segnungen kommen vor")
	expect_lt(int(seen.b_chain), int(seen.b_oak), "legendär seltener als gewöhnlich")
