extends TestCase
## Portierung der Kampf-, Spieler-, Loot- und Levelgenerator-Tests.

const BASE := {"hp": 30, "maxHp": 30, "focus": 6, "maxFocus": 6, "attack": 6, "potions": 1}


static func cfg() -> Dictionary:
	return GameConfig.section("combat")


static func hero(id: String, overrides: Dictionary = {}) -> Dictionary:
	var p := CombatService.combat_player_from(BASE, GameData.get_class_def(id))
	p.merge(overrides, true)
	return p


static func enemy(id: String, overrides: Dictionary = {}) -> Dictionary:
	var e := CombatService.create_enemy(GameData.get_enemy(id), 1)
	e.merge(overrides, true)
	return e


static func player_damage(events: Array) -> int:
	var sum := 0
	for e: Dictionary in events:
		if e.type == "damage" and e.target == "player":
			sum += int(e.amount)
	return sum


static func has_event(events: Array, type: String) -> bool:
	return events.any(func(e: Dictionary) -> bool: return e.type == type)


# ---------- Kampf ----------

func test_kampf_richtig_trifft_falsch_verpufft() -> void:
	var state := CombatService.create_combat(hero("warrior"), enemy("jungle_rat"))
	var rng := Rng.create(1)
	var fizzle := CombatService.resolve_player_action(state, "skill", false, cfg(), rng)
	expect_eq(fizzle[0].type, "fizzle")
	expect_eq(state.player.focus, 6)
	expect_eq(state.enemy.hp, state.enemy.maxHp)
	CombatService.resolve_player_action(state, "attack", true, cfg(), rng)
	expect_lt(state.enemy.hp, state.enemy.maxHp)


## Normale Gegner: höchstens 4 Treffer, mit laufender Kombo (×1.3) höchstens 3 (Issue #21).
func test_kampf_normale_gegner_1_bis_3_treffer() -> void:
	for id in ["moss_spirit", "bat", "spider", "jungle_rat", "stone_rat", "temple_ghost"]:
		for mult in [1.0, 1.3]:
			var state := CombatService.create_combat(hero("warrior", {"critChance": 0.0, "comboMult": mult}), enemy(id))
			var hits := 0
			var rng := Rng.create(3)
			while state.outcome == "ongoing":
				CombatService.resolve_player_action(state, "attack", true, cfg(), rng)
				hits += 1
			expect_ge(hits, 1, id)
			expect_le(hits, 4 if mult == 1.0 else 3, "%s ×%s" % [id, mult])


func test_kampf_verteidigen() -> void:
	var blocked := func(p: Dictionary) -> int:
		var s := CombatService.create_combat(p, enemy("giant_crab", {"intent": "heavy"}))
		CombatService.resolve_player_action(s, "defend", true, cfg(), Rng.create(5))
		return player_damage(CombatService.resolve_enemy_turn(s, Rng.create(9)))
	var full := player_damage(CombatService.resolve_enemy_turn(CombatService.create_combat(hero("warrior"), enemy("giant_crab", {"intent": "heavy"})), Rng.create(9)))
	expect_lt(blocked.call(hero("rogue")), full)
	expect_lt(blocked.call(hero("warrior")), blocked.call(hero("rogue")))


func test_kampf_faehigkeit_und_heiltrank() -> void:
	var state := CombatService.create_combat(hero("warrior", {"hp": 10}), enemy("giant_crab"))
	var rng := Rng.create(2)
	CombatService.resolve_player_action(state, "skill", true, cfg(), rng)
	expect_eq(state.player.focus, 6 - int(state.player.skill.focusCost))
	CombatService.resolve_player_action(state, "item", true, cfg(), rng)
	expect_eq(state.player.hp, 10 + int(cfg().potionHeal))
	expect_eq(state.player.potions, 0)
	expect_false(CombatService.can_use_action(state, "item"))


func test_kampf_gift() -> void:
	var state := CombatService.create_combat(hero("rogue"), enemy("temple_guard"))
	var events := CombatService.resolve_player_action(state, "skill", true, cfg(), Rng.create(4))
	expect_true(has_event(events, "poisoned"))
	var hp_before: int = state.enemy.hp
	var turn := CombatService.resolve_enemy_turn(state, Rng.create(4))
	expect_eq(turn[0].type, "poisonTick")
	expect_lt(state.enemy.hp, hp_before)


func test_kampf_schurke_kritisch() -> void:
	var crits := func(p: Dictionary) -> int:
		var n := 0
		var rng := Rng.create(77)
		for i in 400:
			var s := CombatService.create_combat(p, enemy("temple_cyclops"))
			var ev := CombatService.resolve_player_action(s, "attack", true, cfg(), rng)
			if ev[0].type == "damage" and ev[0].crit:
				n += 1
		return n
	expect_gt(crits.call(hero("rogue")), crits.call(hero("warrior")) * 2)


func test_kampf_magier_fokus() -> void:
	var state := CombatService.create_combat(hero("mage", {"focus": 2}), enemy("temple_guard"))
	CombatService.resolve_player_action(state, "attack", true, cfg(), Rng.create(1))
	expect_eq(state.player.focus, 3)
	CombatService.resolve_player_action(state, "attack", false, cfg(), Rng.create(1))
	expect_eq(state.player.focus, 3)


func test_kampf_boss_phase2() -> void:
	var state := CombatService.create_combat(hero("warrior", {"attack": 7, "critChance": 0.0}), enemy("temple_cyclops"))
	var rng := Rng.create(4)
	var actions := 0
	var phase := false
	while state.outcome == "ongoing":
		if has_event(CombatService.resolve_player_action(state, "attack", true, cfg(), rng), "phase"):
			phase = true
		actions += 1
	expect_true(phase)
	expect_ge(actions, 8)
	expect_le(actions, 15)


func test_kampf_absichten_folgen_muster() -> void:
	var state := CombatService.create_combat(hero("warrior"), enemy("spider"))
	var seen: Array = [state.enemy.intent]
	for i in 5:
		state.player.hp = 999
		for e: Dictionary in CombatService.resolve_enemy_turn(state, Rng.create(i)):
			if e.type == "intent":
				seen.append(e.move)
	expect_eq(seen.slice(0, 4), ["attack", "charge", "heavy", "attack"])


func test_kampf_schwerer_schlag() -> void:
	var dmg := func(intent: String) -> int:
		var s := CombatService.create_combat(hero("warrior", {"hp": 999, "maxHp": 999}), enemy("temple_guard", {"intent": intent}))
		return player_damage(CombatService.resolve_enemy_turn(s, Rng.create(3)))
	expect_ge(dmg.call("heavy"), dmg.call("attack") * 1.6)


func test_kampf_panzern_und_regenerieren() -> void:
	var guarded := CombatService.create_combat(hero("warrior", {"critChance": 0.0}), enemy("stone_rat", {"intent": "guard"}))
	CombatService.resolve_enemy_turn(guarded, Rng.create(1))
	expect_true(guarded.enemy.guarding)
	var ev := CombatService.resolve_player_action(guarded, "attack", true, cfg(), Rng.create(2))
	expect_true(ev[0].type == "damage" and ev[0].guarded)
	expect_false(guarded.enemy.guarding)
	var regen := CombatService.create_combat(hero("warrior"), enemy("moss_spirit", {"intent": "regenerate", "hp": 3}))
	CombatService.resolve_enemy_turn(regen, Rng.create(1))
	expect_gt(regen.enemy.hp, 3)


func test_kampf_niederlage() -> void:
	var state := CombatService.create_combat(hero("warrior", {"hp": 1}), enemy("jungle_rat"))
	CombatService.resolve_enemy_turn(state, Rng.create(1))
	expect_eq(state.outcome, "lost")


# ---------- Spieler & Loot ----------

func test_spieler_werte() -> void:
	var pc := GameConfig.section("player")
	var profile := Player.new_profile(pc)
	profile.bag = ["apprentice_helm", "focus_staff"]
	profile = Player.equip(Player.equip(profile, "apprentice_helm"), "focus_staff")
	var stats := Player.compute_stats(profile, pc)
	expect_false(stats.freeHints.has("length"), "Gegenstände geben keine Vokabelhilfen")
	expect_near(Meta.mod(stats.mods, "armor"), 1.0, 0.001, "Lehrlingshelm: Rüstung")
	expect_eq(stats.maxFocus, int(pc.baseFocus) + 4)
	expect_eq(profile.bag, ["wooden_sword"])
	var leveled := Player.add_xp(profile, 100, pc)
	expect_eq(leveled.levelsGained, 2)
	expect_eq(leveled.profile.level, 3)
	var mage_profile := Player.new_profile(pc)
	mage_profile.heroClass = "mage"
	var mage := Player.compute_stats(mage_profile, pc)
	var warrior := Player.compute_stats(Player.new_profile(pc), pc)
	expect_gt(mage.maxFocus, warrior.maxFocus)
	expect_lt(mage.maxHp, warrior.maxHp)
	expect_eq(mage.freeHints.length, 1)


func test_spieler_verkaufen_und_kaufen() -> void:
	var profile := Player.new_profile(GameConfig.section("player"))
	profile.bag = ["knight_helm", "copper_ring"]
	profile = Player.sell_item(profile, "knight_helm")
	expect_eq(profile.bag, ["copper_ring"])
	expect_eq(profile.gold, 60)
	expect_true(is_same(Player.sell_item(profile, "wooden_sword"), profile), "angelegt, also nicht verkaufbar")
	var potions: int = profile.potions
	profile = Player.buy_potion(profile)
	expect_eq(profile.potions, potions + 1)
	expect_eq(profile.gold, 40)
	var poor := profile.duplicate(true)
	poor.gold = 5
	expect_false(Player.can_buy_potion(poor))


func test_loot_keine_duplikate() -> void:
	var rng := Rng.create(11)
	var owned := {}
	for i in 200:
		var loot := LootService.roll_loot("boss", rng, func(id: String) -> bool: return owned.has(id))
		if loot.itemId != null:
			expect_false(owned.has(loot.itemId))
			owned[loot.itemId] = true
	expect_ge(owned.size(), 5)


# ---------- Levelgenerator ----------

static func options(runes: int = -1) -> Dictionary:
	return {"bossRunesRequired": runes if runes >= 0 else int(GameConfig.section("run").bossRunesRequired), "enemies": GameData.THEMES[0].enemies}


static func gen(seed: int) -> Dictionary:
	return LevelGenerator.generate(seed, GameConfig.section("level"), options())


static func reachable(map: Dictionary, walls: Dictionary) -> Dictionary:
	var start: Vector2i = map.start
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	while qi < queue.size():
		var p := queue[qi]
		qi += 1
		for d in LevelGenerator.DIRS:
			var n := p + d
			if seen.has(n) or walls.has(n) or not MapModel.is_floor(map, n.x, n.y):
				continue
			seen[n] = true
			queue.append(n)
	return seen


func test_level_deterministisch() -> void:
	expect_eq(gen(1234), gen(1234))
	expect_ne(gen(1234).tiles, gen(4321).tiles)


func test_level_viele_seeds_loesbar() -> void:
	var lv := GameConfig.section("level")
	for seed in range(1, 201):
		var map := gen(seed * 977)
		if map.is_empty():
			fail("seed %d nicht erzeugt" % seed)
			continue
		_check_level(map, lv, int(GameConfig.section("run").bossRunesRequired), true, "seed %d" % seed)


func _check_level(map: Dictionary, lv: Dictionary, runes: int, strict: bool, label: String) -> void:
	var boss_door: Dictionary = map.objects.filter(func(o: Dictionary) -> bool: return o.kind == "bossDoor")[0]
	var boss_room: Dictionary = map.rooms[map.bossRoomId]
	var bc := MapModel.room_center(boss_room)
	var door_key := Vector2i(boss_door.x, boss_door.y)
	var without_boss := reachable(map, {door_key: true})
	expect_false(without_boss.has(bc), label + " Bossraum ohne Tür erreichbar")
	for room: Dictionary in map.rooms:
		if room.id == map.bossRoomId:
			continue
		expect_true(without_boss.has(MapModel.room_center(room)), label + " Raum unerreichbar")
	expect_true(reachable(map, {}).has(bc), label + " Boss unerreichbar")
	if not strict:
		var normal_count: int = map.objects.filter(func(o: Dictionary) -> bool: return o.kind == "enemy" and o.tier == "normal").size()
		expect_ge(normal_count, lv.normalEnemies.min, label)
		return

	var positions := {}
	for o: Dictionary in map.objects:
		expect_eq(MapModel.tile_at(map, o.x, o.y), MapModel.FLOOR, label + " Objekt in Wand")
		var k := Vector2i(o.x, o.y)
		expect_false(positions.has(k), label + " Objekte übereinander")
		positions[k] = true
	var count := func(pred: Callable) -> int: return map.objects.filter(pred).size()
	var normal: int = count.call(func(o: Dictionary) -> bool: return o.kind == "enemy" and o.tier == "normal")
	var elite: int = count.call(func(o: Dictionary) -> bool: return o.kind == "enemy" and o.tier == "elite")
	var chests: int = count.call(func(o: Dictionary) -> bool: return o.kind == "chest")
	var doors: int = count.call(func(o: Dictionary) -> bool: return o.kind == "door")
	expect_true(normal >= lv.normalEnemies.min and normal <= lv.normalEnemies.max, label + " normale Gegner %d" % normal)
	expect_true(elite >= lv.eliteEnemies.min and elite <= lv.eliteEnemies.max, label + " Elite %d" % elite)
	expect_true(chests >= lv.chests.min and chests <= lv.chests.max, label + " Truhen %d" % chests)
	expect_true(doors >= lv.doors.min and doors <= lv.doors.max, label + " Türen %d" % doors)
	expect_eq(count.call(func(o: Dictionary) -> bool: return o.kind == "enemy" and o.tier == "boss"), 1, label)
	expect_ge(normal + elite + doors, runes, label + " Runenquellen")
	for o: Dictionary in map.objects:
		var in_boss := MapModel.room_contains(boss_room, o.x, o.y)
		expect_eq(in_boss, o.kind == "enemy" and o.tier == "boss", label + " Objekt im Bossraum")
	for door: Dictionary in map.objects.filter(func(o: Dictionary) -> bool: return o.kind == "door"):
		var r := reachable(map, {door_key: true, Vector2i(door.x, door.y): true})
		expect_lt(r.size(), without_boss.size() - 1, label + " Tür trennt nichts ab")


## Issue #3: Türen werden frontal gezeichnet und gehören deshalb in Nord-Süd-Durchgänge.
func test_tueren_stehen_richtig_herum() -> void:
	var sideways := 0
	var total := 0
	for seed in range(1, 201):
		var map := gen(seed * 977)
		for o: Dictionary in map.get("objects", []):
			if o.kind == "door":
				expect_false(LevelBuilder.door_faces_side(map, o.x, o.y), "seed %d Tür %s seitlich" % [seed, o.id])
			if o.kind in ["door", "bossDoor"]:
				total += 1
				if LevelBuilder.door_faces_side(map, o.x, o.y):
					sideways += 1
	# Die Bosstür darf nur im Notfall seitlich sitzen.
	expect_lt(sideways, total / 20, "seitliche Türen %d von %d" % [sideways, total])


func test_level_skalierung_issue16() -> void:
	expect_eq(RunScaling.level_scale_for(20), 1.0)
	expect_eq(RunScaling.level_scale_for(60), 2.0)
	expect_eq(RunScaling.level_scale_for(300), 2.5)
	var scale := RunScaling.level_scale_for(95)
	var c := RunScaling.scale_level_config(GameConfig.section("level"), scale)
	var runes := RunScaling.scaled_boss_runes(int(GameConfig.section("run").bossRunesRequired), scale)
	for seed in range(1, 61):
		var map := LevelGenerator.generate(seed * 131, c, options(runes))
		if map.is_empty():
			fail("seed %d nicht erzeugt" % seed)
			continue
		_check_level(map, c, runes, false, "skaliert seed %d" % seed)


# ---------- Wissensschreine und Runenplatten (Issue #16) ----------

func test_level_hat_schreine_und_runenplatten() -> void:
	var c := GameConfig.section("level")
	for seed in [1, 2, 3, 4, 5]:
		var map := LevelGenerator.generate(seed, c, {"bossRunesRequired": 4, "enemies": GameData.THEMES[0].enemies})
		var shrines: Array = map.objects.filter(func(o: Dictionary) -> bool: return o.kind == "shrine")
		var plates: Array = map.objects.filter(func(o: Dictionary) -> bool: return o.kind == "plate")
		expect_ge(shrines.size(), int(c.shrines.min), "seed %d" % seed)
		expect_ge(plates.size(), 1, "seed %d" % seed)
		for p: Dictionary in plates:
			var in_room := false
			for r: Dictionary in map.rooms:
				if MapModel.room_contains(r, int(p.x), int(p.y)):
					in_room = true
			expect_false(in_room, "Runenplatten liegen in Gängen")
			expect_true(MapModel.is_floor(map, int(p.x), int(p.y)))


func test_schrein_belohnung() -> void:
	var words := int(GameConfig.section("shrine").words)
	var perfect := Encounters.shrine_reward(words, 60)
	expect_true(perfect.perfect)
	expect_gt(int(perfect.heal), 0)
	var some := Encounters.shrine_reward(1, 60)
	expect_false(some.perfect)
	expect_eq(int(some.heal), 0)
	expect_eq(int(some.gold), int(GameConfig.section("shrine").goldPerCorrect))


func test_runenplatte_nie_toedlich() -> void:
	expect_eq(int(Encounters.plate_result("wrongCorrected", 2).damage), 1)
	expect_eq(int(Encounters.plate_result("wrongCorrected", 1).damage), 0)
	expect_eq(int(Encounters.plate_result("almostCorrect", 1).damage), 0)
	expect_gt(int(Encounters.plate_result("correct", 10).gold), 0)


func test_splitter_fuer_schreine() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 12345)
	var before := int(Meta.run_reward(Ctx.run, false, Ctx.profile).total)
	for o: Dictionary in Ctx.run.map.objects:
		if o.kind == "shrine":
			Ctx.run.opened[o.id] = true
	expect_gt(int(Meta.run_reward(Ctx.run, false, Ctx.profile).total), before)


# ---------- Ebenen (Issue #27) ----------

func test_ebenen_tiefer_hinab() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 4242)
	var first_map: Dictionary = Ctx.run.map
	for o: Dictionary in first_map.objects:
		if o.kind == "enemy":
			Ctx.run.defeated[o.id] = true
		elif o.kind in ["chest", "door", "shrine"]:
			Ctx.run.opened[o.id] = true
	Ctx.run.floorsCleared = 1
	var shards_floor1 := int(Meta.run_reward(Ctx.run, false, Ctx.profile).total)
	expect_true(Ctx.can_descend())
	Ctx.profile.level = 4
	Ctx.run.hp = 3
	Ctx.descend()
	expect_eq(int(Ctx.run.floor), 2)
	expect_ne(Ctx.run.map.seed, first_map.seed, "neue Karte")
	expect_true((Ctx.run.defeated as Dictionary).is_empty())
	expect_eq(int(Ctx.run.runes), 0)
	expect_eq(int(Ctx.profile.level), 4, "Held bleibt")
	expect_eq(int(Ctx.run.hp), int(Ctx.stats().maxHp), "aufgefüllt")
	expect_eq(int(Meta.run_reward(Ctx.run, false, Ctx.profile).total), shards_floor1, "Erreichtes zählt weiter")
	Ctx.autosave()
	Ctx.resume_run()
	expect_eq(int(Ctx.run.floor), 2, "Ebene im Spielstand")
	expect_eq(int(Ctx.run.map.seed), int(Meta.floor_seed(int(Ctx.run.seed), 2)))
	Ctx.run.floor = Meta.max_floors()
	expect_false(Ctx.can_descend(), "letzte Ebene")


func test_ebenen_gegner_staerker() -> void:
	var def := GameData.get_enemy("bat")
	var e1 := CombatService.create_enemy(def, 1, null, 0, 1)
	var e2 := CombatService.create_enemy(def, 1, null, 0, 2)
	expect_gt(int(e2.maxHp), int(e1.maxHp))
	expect_gt(int(e2.attack), int(e1.attack))


func test_ebenen_siegbonus_je_ebene() -> void:
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 4242)
	Ctx.run.floorsCleared = 2
	var r := Meta.run_reward(Ctx.run, false, Ctx.profile)
	expect_true((r.lines as Array).any(func(l: Array) -> bool: return String(l[0]).begins_with("Ebenen bezwungen ×2")), "Bonus bleibt auch ohne Endsieg")
	Ctx.end_run(false)
	expect_eq(int(Ctx.profile.records.victories), 1, "zählt als Sieg")
