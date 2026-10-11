class_name GameContext
extends Node
## Zentraler Spielzustand (Autoload „Ctx“); Szenen lesen und verändern ihn, SaveService persistiert ihn.
## ActiveRun { seed, levelScale, bossRunes, unitIds, worldId, map, hp, focus, runes, player: Vector2,
##             lastHeal: Vector2, defeated: {id: true}, opened: {id: true}, xpGained, goldGained,
##             lootGained, levelsGained, startedAt, learning: LearningSession, rng: Callable, completed }

signal profile_changed

var save: SaveService
var repo: VocabularyRepository
var profile: Dictionary
var progress: Dictionary
var settings: Dictionary
var run: Dictionary = {}


func _init(store: KeyValueStore = null) -> void:
	setup(store if store != null else KeyValueStore.FileStore.new())


func setup(store: KeyValueStore) -> void:
	save = SaveService.new(store)
	repo = VocabularyRepository.new(save)
	var loaded: Variant = save.load_player()
	profile = Player.normalize(loaded if loaded is Dictionary else {}, GameConfig.section("player"))
	progress = save.load_progress()
	settings = save.load_settings()
	run = {}


func has_run() -> bool:
	return not run.is_empty()


func stats() -> Dictionary:
	return Player.compute_stats(profile, GameConfig.section("player"))


func hero_class() -> Dictionary:
	return GameData.get_class_def(profile.heroClass)


## Hilfe-Ressourcen für eine Begegnung: Gratis-Ladungen aus Klasse/Ausrüstung + aktueller Fokus.
func hint_wallet(focus: int) -> Dictionary:
	return {"freeCharges": (stats().freeHints as Dictionary).duplicate(), "focus": focus, "costs": GameConfig.section("combat").hintFocusCost.duplicate()}


func save_persistent() -> void:
	save.save_player(profile)
	save.save_progress(progress)
	save.save_settings(settings)


func autosave() -> void:
	save_persistent()
	if has_run() and not run.completed:
		save.save_run(snapshot_run())


func _generate_map(seed: int, scale: float, boss_runes: int, world_id: String) -> Dictionary:
	var theme := GameData.get_theme(world_id)
	var cfg := RunScaling.scale_level_config(GameConfig.section("level"), scale)
	return LevelGenerator.generate(seed, cfg, {"bossRunesRequired": boss_runes, "enemies": theme.enemies})


## Neues Abenteuer: Lauf-Werte (Level, Gold, Ausrüstung …) werden zurückgesetzt, Skills wirken ab Start.
func start_run(unit_ids: Array, world_id: String = "jungle", seed: int = -1) -> Dictionary:
	if seed < 0:
		seed = Rng.random_seed()
	profile = Meta.reset_run_fields(Meta.ensure(profile), GameConfig.section("player"))
	var level_scale := RunScaling.level_scale_for(repo.learning_items(unit_ids).size())
	var boss_runes := RunScaling.scaled_boss_runes(int(GameConfig.section("run").bossRunesRequired), level_scale)
	var map := _generate_map(seed, level_scale, boss_runes, world_id)
	var s := stats()
	var start_pos := Vector2(map.start.x + 0.5, map.start.y + 0.5)
	run = {
		"seed": seed,
		"levelScale": level_scale,
		"bossRunes": boss_runes,
		"unitIds": unit_ids.duplicate(),
		"worldId": GameData.get_theme(world_id).id,
		"map": map,
		"hp": int(s.maxHp),
		"focus": int(s.maxFocus),
		"runes": 0,
		"player": start_pos,
		"lastHeal": start_pos,
		"defeated": {},
		"opened": {},
		"xpGained": 0,
		"goldGained": 0,
		"lootGained": [],
		"levelsGained": 0,
		"startedAt": Vocab.now_ms(),
		"learning": _create_learning(unit_ids, seed),
		"rng": Rng.create(seed ^ 0x9E3779B9),
		"completed": false,
	}
	autosave()
	return run


func can_resume() -> bool:
	var snap: Variant = save.load_run()
	if not snap is Dictionary:
		return false
	for id: String in snap.get("unitIds", []):
		if not repo.get_unit(id).is_empty():
			return true
	return false


func resume_run() -> Dictionary:
	var snap: Variant = save.load_run()
	if not snap is Dictionary:
		return {}
	var unit_ids: Array = (snap.unitIds as Array).filter(func(id: String) -> bool: return not repo.get_unit(id).is_empty())
	if unit_ids.is_empty():
		return {}
	var seed := int(snap.seed)
	var level_scale := float(snap.get("levelScale", 1.0))
	var boss_runes := RunScaling.scaled_boss_runes(int(GameConfig.section("run").bossRunesRequired), level_scale)
	var map := _generate_map(seed, level_scale, boss_runes, snap.worldId)
	var learning := _create_learning(unit_ids, seed + int(snap.learning.scheduler.picks))
	learning.restore(snap.learning)
	var s := stats()
	var to_set := func(list: Array) -> Dictionary:
		var d := {}
		for k: String in list:
			d[k] = true
		return d
	run = {
		"seed": seed,
		"levelScale": level_scale,
		"bossRunes": boss_runes,
		"unitIds": unit_ids,
		"worldId": GameData.get_theme(snap.worldId).id,
		"map": map,
		"hp": mini(int(snap.hp), int(s.maxHp)),
		"focus": mini(int(snap.focus), int(s.maxFocus)),
		"runes": int(snap.runes),
		"player": Vector2(snap.player.x, snap.player.y),
		"lastHeal": Vector2(snap.lastHeal.x, snap.lastHeal.y),
		"defeated": to_set.call(snap.defeated),
		"opened": to_set.call(snap.opened),
		"xpGained": int(snap.xpGained),
		"goldGained": int(snap.goldGained),
		"lootGained": Array(snap.lootGained),
		"levelsGained": 0,
		"startedAt": int(snap.startedAt),
		"learning": learning,
		"rng": Rng.create(((seed ^ 0x9E3779B9) + int(snap.learning.run.questions)) & Rng.MASK),
		"completed": false,
	}
	return run


## Beendet das Abenteuer und schreibt die Tempelsplitter gut. Liefert die Belohnung
## ({ total, lines }); ein zweiter Aufruf für denselben Lauf zahlt nichts mehr aus.
func end_run(victory: bool = false) -> Dictionary:
	var reward := {"total": 0, "lines": []}
	if has_run() and not run.completed:
		reward = Meta.run_reward(run, victory, profile)
		profile.shards = int(profile.shards) + int(reward.total)
		profile.records.runs = int(profile.records.runs) + 1
		profile.records.shardsTotal = int(profile.records.shardsTotal) + int(reward.total)
		if victory:
			profile.records.victories = int(profile.records.victories) + 1
		run.completed = true
		run.victory = victory
		run.reward = reward
		profile_changed.emit()
	elif has_run():
		reward = run.get("reward", reward)
	save.clear_run()
	save_persistent()
	return reward


## Kampfwerte des Helden für den aktuellen Lauf (inklusive Skillbaum).
func combat_player() -> Dictionary:
	var s := stats()
	return CombatService.combat_player_from(
		{"hp": run.hp, "maxHp": s.maxHp, "focus": run.focus, "maxFocus": s.maxFocus, "attack": s.attack, "potions": profile.potions},
		hero_class(), s.mods)


## Laufgeschwindigkeits-Faktor aus dem Skillbaum (1.0 = normal).
func move_speed_factor() -> float:
	return 1.0 + Meta.mod(stats().mods, "moveSpeed")


## XP gutschreiben; liefert die Anzahl neuer Level.
func gain_xp(amount: int) -> int:
	var res := Player.add_xp(profile, amount, GameConfig.section("player"))
	profile = res.profile
	var gained: int = res.levelsGained
	if has_run():
		run.xpGained = int(run.xpGained) + amount
		run.levelsGained = int(run.levelsGained) + gained
		if gained > 0:
			# Level-up: volle Heilung als kleine Belohnung.
			var s := stats()
			run.hp = int(s.maxHp)
			run.focus = int(s.maxFocus)
	profile_changed.emit()
	return gained


## Beute gutschreiben; Gold wird um den Skill-Bonus „goldFind“ erhöht (der Bonus steht danach in loot.gold).
func apply_loot(loot: Dictionary) -> void:
	var find := Meta.mod(stats().mods, "goldFind")
	if find > 0.0:
		loot.gold = int(round(int(loot.gold) * (1.0 + find)))
	profile.gold = int(profile.gold) + int(loot.gold)
	profile.potions = int(profile.potions) + int(loot.potions)
	if loot.itemId != null and not owns(loot.itemId):
		(profile.bag as Array).append(loot.itemId)
	if has_run():
		run.goldGained = int(run.goldGained) + int(loot.gold)
		if loot.itemId != null:
			(run.lootGained as Array).append(loot.itemId)
	profile_changed.emit()


func owns(item_id: String) -> bool:
	return Player.owns_item(profile, item_id)


func set_profile(p: Dictionary) -> void:
	profile = p
	clamp_run_stats()
	profile_changed.emit()


## Nach Ausrüstungswechsel: aktuelle Werte auf neue Maxima begrenzen.
func clamp_run_stats() -> void:
	if not has_run():
		return
	var s := stats()
	run.hp = mini(int(run.hp), int(s.maxHp))
	run.focus = mini(int(run.focus), int(s.maxFocus))


## Eine Vokabel wurde beantwortet: Statistik, Mastery und Scheduler aktualisieren, XP vergeben.
## Liefert die Anzahl neuer Level.
func submit_answer(item: Dictionary, res: Dictionary) -> int:
	var learning: LearningSession = run.learning
	learning.submit(item, res)
	profile.lastLearnedAt = Vocab.now_ms()
	if res.outcome == "correct":
		return gain_xp(int(GameConfig.section("xp").correctAnswer))
	return 0


func _create_learning(unit_ids: Array, seed: int) -> LearningSession:
	return LearningSession.new(repo.learning_items(unit_ids), progress, GameConfig.section("learning"), Rng.create(seed & Rng.MASK), Vocab.now_ms, {"repeatGapReduction": stats().repeatGapReduction})


func snapshot_run() -> Dictionary:
	var learning: LearningSession = run.learning
	return {
		"seed": run.seed,
		"levelScale": run.levelScale,
		"unitIds": run.unitIds,
		"worldId": run.worldId,
		"hp": run.hp,
		"focus": run.focus,
		"runes": run.runes,
		"player": {"x": run.player.x, "y": run.player.y},
		"lastHeal": {"x": run.lastHeal.x, "y": run.lastHeal.y},
		"defeated": run.defeated.keys(),
		"opened": run.opened.keys(),
		"xpGained": run.xpGained,
		"goldGained": run.goldGained,
		"lootGained": run.lootGained,
		"startedAt": run.startedAt,
		"learning": learning.snapshot(),
	}
