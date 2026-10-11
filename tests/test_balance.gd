extends TestCase
## Balancing-Simulation: kompletter Run eines Spielers, der `accuracy` der Wörter richtig weiß.


static func sample_vocab() -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/sample_unit.json"))
	return data.vocabulary


static func simulate_run(seed: int, accuracy: float, hero_class: String = "warrior", vocabulary: Array = [], skills: Dictionary = {}, heat: int = 0) -> Dictionary:
	if vocabulary.is_empty():
		vocabulary = sample_vocab()
	var c := GameConfig.data()
	var pc: Dictionary = c.player
	var rng := Rng.create(seed)
	var st := {"profile": Player.new_profile(pc), "hp": 0, "focus": 0, "defeats": 0}
	st.profile.heroClass = hero_class
	st.profile.unlockedClasses = ["warrior", "rogue", "mage"]
	st.profile.skills[hero_class] = skills
	st.profile = Meta.reset_run_fields(st.profile, pc)
	var progress := {}
	var items: Array = vocabulary.map(func(e: Dictionary) -> Dictionary: return {"key": "s/" + str(e.id), "entry": e})
	var learning := LearningSession.new(items, progress, c.learning, Rng.create(seed + 1), func() -> int: return 0)
	var scale := RunScaling.level_scale_for(vocabulary.size())
	var map := LevelGenerator.generate(seed, RunScaling.scale_level_config(c.level, scale), {
		"bossRunesRequired": RunScaling.scaled_boss_runes(int(c.run.bossRunesRequired), scale),
		"enemies": GameData.THEMES[0].enemies,
	})

	var gain_xp := func(amount: int) -> void:
		st.profile = Player.add_xp(st.profile, amount, pc).profile
	var ask := func(mode: String) -> bool:
		var item := learning.next_word(mode)
		var correct: bool = rng.call() < accuracy
		learning.submit(item, Vocab.result("correct" if correct else "wrongCorrected"))
		if correct:
			gain_xp.call(int(c.xp.correctAnswer))
		return correct
	var auto_equip := func() -> void:
		for id: String in (st.profile.bag as Array).duplicate():
			st.profile = Player.equip(st.profile, id)
	var add_loot := func(loot: Dictionary) -> void:
		st.profile.potions = int(st.profile.potions) + int(loot.potions)
		if loot.itemId != null:
			(st.profile.bag as Array).append(loot.itemId)
		auto_equip.call()
	var rest := func() -> void:
		var s := Player.compute_stats(st.profile, pc)
		st.hp = s.maxHp
		st.focus = s.maxFocus
	rest.call()

	var fight := func(enemy_id: String) -> bool:
		var stats := Player.compute_stats(st.profile, pc)
		var def := GameData.get_enemy(enemy_id)
		var base := {"hp": st.hp, "maxHp": stats.maxHp, "focus": st.focus, "maxFocus": stats.maxFocus, "attack": stats.attack, "potions": st.profile.potions}
		var state := CombatService.create_combat(CombatService.combat_player_from(base, GameData.get_class_def(hero_class), stats.mods), CombatService.create_enemy(def, int(st.profile.level), rng, heat))
		while state.outcome == "ongoing":
			var action := "attack"
			if state.player.hp < state.player.maxHp * 0.35 and CombatService.can_use_action(state, "item"):
				action = "item"
			elif state.enemy.intent == "heavy" and state.player.hp < state.player.maxHp * 0.7:
				action = "defend"
			elif CombatService.can_use_action(state, "skill") and (def.tier != "normal" or hero_class == "mage"):
				action = "skill"
			var correct: bool = ask.call(def.selection)
			CombatService.resolve_player_action(state, action, correct, c.combat, rng)
			CombatService.resolve_enemy_turn(state, rng)
		st.profile.potions = state.player.potions
		if state.outcome == "lost":
			st.defeats += 1
			st.hp = stats.maxHp
			st.focus = stats.maxFocus
			return false
		st.hp = state.player.hp
		st.focus = mini(int(stats.maxFocus), int(state.player.focus) + 1)
		var xp: int = c.xp.boss if def.tier == "boss" else (c.xp.eliteEnemy if def.tier == "elite" else c.xp.normalEnemy)
		gain_xp.call(xp)
		add_loot.call(LootService.roll_loot(def.tier, rng, func(id: String) -> bool: return Player.owns_item(st.profile, id)))
		return true

	# Truhen und Türen
	for obj: Dictionary in map.objects:
		if obj.kind == "chest":
			var needed := 2 if obj.chestType == "rare" else 1
			var got := 0
			while got < needed:
				if ask.call("preferHard" if obj.chestType == "special" else "normal"):
					got += 1
			gain_xp.call(int(c.xp.chest))
			add_loot.call(LootService.roll_loot("chestNormal", rng, func(id: String) -> bool: return (st.profile.bag as Array).has(id)))
		if obj.kind == "door":
			var got := 0
			while got < int(obj.answers):
				if ask.call("normal"):
					got += 1
	# Gegner: normale zuerst, Heilung vor Elite und Boss.
	for tier in ["normal", "elite"]:
		for obj: Dictionary in map.objects:
			if obj.kind == "enemy" and obj.tier == tier:
				while not fight.call(obj.enemyId):
					pass
		rest.call()
	var boss: Dictionary = map.objects.filter(func(o: Dictionary) -> bool: return o.kind == "enemy" and o.tier == "boss")[0]
	var boss_attempts := 1
	while not fight.call(boss.enemyId):
		boss_attempts += 1
		rest.call()
		if boss_attempts > 10:
			break
	# Rogue-lite: Splitter für den vollständigen Lauf (alle Gegner, Truhen, Türen, Sieg).
	var fake_run := {"map": map, "defeated": {}, "opened": {}, "learning": learning, "heat": heat}
	for obj: Dictionary in map.objects:
		if obj.kind == "enemy":
			fake_run.defeated[obj.id] = true
		elif obj.kind in ["chest", "door"]:
			fake_run.opened[obj.id] = true
	var shards := int(Meta.run_reward(fake_run, true, st.profile).total)
	return {"questions": learning.run.questions, "words": learning.run.records.size(), "level": st.profile.level, "defeats": st.defeats, "bossAttempts": boss_attempts, "shards": shards}


func test_balance_abfragen_pro_run() -> void:
	for seed in range(1, 31):
		var r := simulate_run(seed * 31, 0.8)
		expect_ge(r.questions, GameConfig.section("run").minVocabularyInteractions, "seed %d" % seed)
		expect_le(r.questions, 65, "seed %d" % seed)
		expect_ge(r.words, 15, "seed %d" % seed)


func test_balance_boss_schaffbar() -> void:
	var first := 0
	var two := 0
	for i in 40:
		var r := simulate_run(1000 + i * 17, 0.8)
		if r.bossAttempts == 1:
			first += 1
		if r.bossAttempts <= 2:
			two += 1
	expect_gt(first / 40.0, 0.5)
	expect_gt(two / 40.0, 0.85)


func test_balance_60_prozent() -> void:
	for i in 30:
		expect_le(simulate_run(5000 + i * 13, 0.6).bossAttempts, 10)


func test_balance_klassen() -> void:
	for cls in ["warrior", "rogue", "mage"]:
		var two := 0
		for i in 40:
			if simulate_run(9000 + i * 7, 0.8, cls).bossAttempts <= 2:
				two += 1
		expect_gt(two / 40.0, 0.8, cls)


func test_balance_grosse_sets_issue16() -> void:
	var big: Array = []
	for i in 95:
		big.append(Vocab.entry("b%d" % i, "de%d" % i, "en%d" % i))
	var total := 0
	for i in 15:
		var r := simulate_run(7000 + i * 11, 0.8, "warrior", big)
		expect_ge(r.words, 50)
		expect_le(r.questions, 150)
		total += int(r.words)
	expect_ge(total / 15.0, 60)


# ---------- Rogue-lite (gemessen mit einem Bot, der sich vor Elite und Boss heilt) ----------

const FULL_WARRIOR := {"w_toughness": 3, "w_shieldwall": 2, "w_ironwill": 2, "w_strength": 3, "w_momentum": 2, "w_slayer": 2, "w_stride": 3, "w_supplies": 2, "w_veteran": 2}


static func lost_runs(n: int, accuracy: float, skills: Dictionary, heat: int) -> int:
	var lost := 0
	for i in n:
		if int(simulate_run(9000 + i * 7, accuracy, "warrior", [], skills, heat).defeats) >= int(Meta.cfg().lives):
			lost += 1
	return lost


func test_balance_splitter_pro_sieg() -> void:
	var total := 0
	for i in 30:
		total += int(simulate_run(2000 + i * 13, 0.8).shards)
	var avg := total / 30.0
	expect_ge(avg, 30.0, "Schurke (25) nach dem ersten Sieg freischaltbar")
	expect_le(avg, 60.0, "Skillbaum (198) nicht nach 2–3 Läufen fertig")


func test_balance_leben_reichen_auf_stufe_0() -> void:
	expect_le(lost_runs(30, 0.6, {}, 0), 1, "Auch mit 60 % Treffern endet der Lauf praktisch nie vorzeitig")


func test_balance_tempelstufen_brauchen_skills() -> void:
	var without := lost_runs(20, 0.8, {}, 3)
	var with_tree := lost_runs(20, 0.8, FULL_WARRIOR, 3)
	expect_ge(without, 8, "Stufe 3 ohne Skills ist schwer")
	expect_le(with_tree, 1, "Stufe 3 mit vollem Baum ist machbar")
	expect_le(lost_runs(20, 0.8, FULL_WARRIOR, 5), 5, "Höchste Stufe bleibt mit vollem Baum schaffbar")
