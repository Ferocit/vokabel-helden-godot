class_name BalanceSim
extends RefCounted
## Balancing-Simulator: spielt komplette Abenteuer mit der echten Spiellogik (LevelGenerator, LearningSession,
## CombatService, LootService, Meta) und einem Bot. Wird von tests/test_balance.gd und vom
## Kommandozeilen-Werkzeug tools/sim.gd genutzt (`start.bat sim`, `./start.sh sim`).
##
## Optionen (alle optional, siehe default_options):
##   seed, heroClass, skills {knoten: rang} oder "full"
##   pact         – Pakt {id: rang} (data/pact.gd); alternativ heat = alte Tempelstufe (= {p_hp: n, p_atk: n})
##   learner      – "fixed" (jede Antwort mit `accuracy` richtig) | "beginner" | "average" | "strong"
##                  (Wissen pro Wort, wächst mit Abrufen, Werte unter config/game.json → simulation.learners)
##   vocabulary   – Liste von VocabEntry (Standard: data/units/sample_unit.json)
##   useHints, useShop, useTalents, useBlessings – Bot-Verhalten an/aus
##   knowledge    – {key: Wahrscheinlichkeit}, wird fortgeschrieben (für Kampagnen)
##   progress     – VocabStats je Wort, wird fortgeschrieben (für Kampagnen)
##   profile      – Spielerprofil (für Kampagnen), sonst ein neues
##   clockMs      – Startzeit der simulierten Uhr
##
## Ergebnis eines Abenteuers: siehe `_result`.

const TALENT_ORDER := ["t_might", "t_ambush", "t_vigor", "t_eye", "t_hide", "t_thirst", "t_guard", "t_mastery", "t_clarity", "t_will", "t_herbs", "t_focus", "t_stride", "t_luck"]
const BLESSING_ORDER := ["b_chain", "b_revenge", "b_blade", "b_vampire", "b_hunter", "b_venom", "b_spark", "b_oak", "b_stone", "b_fury", "b_falcon", "b_sun", "b_spring", "b_prayer", "b_alchemy", "b_crystal", "b_jaguar", "b_gold"]


static func default_options() -> Dictionary:
	return {
		"seed": 1, "heroClass": "warrior", "heat": 0, "skills": {}, "learner": "fixed", "accuracy": 0.8,
		"vocabulary": [], "useHints": true, "useShop": true, "useTalents": true, "useBlessings": true,
		"knowledge": {}, "progress": {}, "profile": {}, "clockMs": 0,
	}


static func sample_vocab() -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/sample_unit.json"))
	return data.vocabulary


## Alle Knoten eines Klassenbaums auf Höchstrang.
static func full_tree(class_id: String) -> Dictionary:
	var skills := {}
	for node: Dictionary in SkillTrees.tree(class_id).nodes:
		skills[node.id] = int(node.maxRank)
	return skills


## Ein einzelnes Abenteuer.
static func run(opts: Dictionary = {}) -> Dictionary:
	var o := default_options()
	o.merge(opts, true)
	var sim := _Run.new(o)
	return sim.play()


## Mehrere Abenteuer mit verschiedenen Seeds, zusammengefasst (Durchschnitte, Quoten).
static func batch(opts: Dictionary, count: int) -> Dictionary:
	var rows: Array = []
	var base := int(opts.get("seed", 1))
	for i in count:
		var o := opts.duplicate()
		o.seed = base + i * 7919
		o.knowledge = {}
		o.progress = {}
		rows.append(run(o))
	return summarize(rows)


## Mehrere Abenteuer hintereinander mit dauerhaftem Fortschritt: Splitter werden nach jedem Lauf in den
## Skillbaum gesteckt (günstigster Knoten zuerst), Wissen und Statistik bleiben, die Tempelstufe steigt mit.
static func campaign(opts: Dictionary, runs: int) -> Array:
	var o := default_options()
	o.merge(opts, true)
	var profile := Player.normalize({}, GameConfig.section("player"))
	profile.heroClass = o.heroClass
	if not Meta.is_class_unlocked(profile, o.heroClass):
		(profile.unlockedClasses as Array).append(o.heroClass)
	var knowledge := {}
	var progress := {}
	var clock := 0
	var day_ms := int(float(GameConfig.section("simulation").daysBetweenRuns) * 24 * 3600 * 1000)
	var out: Array = []
	for i in runs:
		var ro := o.duplicate()
		ro.seed = int(o.seed) + i * 7919
		ro.profile = profile
		ro.knowledge = knowledge
		ro.progress = progress
		ro.clockMs = clock
		# Standard: immer auf der höchsten freien Tempelstufe spielen.
		# Standard: immer alle freien Pakt-Punkte für stärkere Gegner einsetzen.
		ro.pact = Pact.sanitize({"p_hp": 5, "p_atk": 5}, profile) if o.get("climbHeat", true) else Pact.sanitize(Pact.normalize(o.get("pact", o.heat)), profile)
		var r := run(ro)
		profile = r.profile
		clock = int(r.clockMs) + day_ms
		_forget(knowledge, o.learner)
		profile = spend_shards(profile, o.heroClass)
		r.erase("profile")
		r.run = i + 1
		r.shardsBank = int(profile.shards)
		r.invested = Meta.invested(profile, o.heroClass)
		r.unlocks = (profile.get("unlocks", []) as Array).size()
		out.append(r)
	return out


## Splitter ausgeben: erst der günstigste lernbare Skillbaum-Knoten, dann die günstigste Freischaltung
## (ohne Aussehen, das nur Optik ist).
static func spend_shards(profile: Dictionary, class_id: String) -> Dictionary:
	profile = _spend_skills(profile, class_id)
	while true:
		var best := ""
		var best_cost := 1 << 30
		for u: Dictionary in Unlocks.ALL:
			if u.kind != "skin" and Unlocks.can_buy(profile, u.id) and int(u.cost) < best_cost:
				best = u.id
				best_cost = int(u.cost)
		if best == "":
			return profile
		profile = Unlocks.buy(profile, best)
	return profile


static func _spend_skills(profile: Dictionary, class_id: String) -> Dictionary:
	while true:
		var best := ""
		var best_cost := 1 << 30
		for node: Dictionary in SkillTrees.tree(class_id).nodes:
			var check := Meta.can_learn(profile, class_id, node.id)
			if check.ok and int(check.cost) < best_cost:
				best = node.id
				best_cost = int(check.cost)
		if best == "":
			return profile
		profile = Meta.learn(profile, class_id, best)
	return profile


static func _forget(knowledge: Dictionary, learner: String) -> void:
	var lc: Dictionary = GameConfig.section("simulation").learners.get(learner, {})
	var f := float(lc.get("forget", 0.0))
	for k: String in knowledge:
		knowledge[k] = float(knowledge[k]) * (1.0 - f)


## Durchschnitte und Quoten über mehrere Ergebnisse.
static func summarize(rows: Array) -> Dictionary:
	var n := float(maxi(1, rows.size()))
	var keys := ["shards", "level", "defeats", "questions", "words", "firstTry", "hints", "minutes", "perMinute", "talents", "blessings", "itemsBought", "knowledgeGain", "defendShare", "defendKnowledge", "otherKnowledge", "maxCombo", "setBonus", "setBonusGolden", "floorsCleared", "nemesisArmor", "nemesisBroken", "groups"]
	var sum := {}
	for k: String in keys:
		sum[k] = 0.0
	var wins := 0
	var first_try_boss := 0
	var defend_rows := 0
	for r: Dictionary in rows:
		for k: String in keys:
			sum[k] += float(r.get(k, 0.0))
		if float(r.defendShare) > 0.0:
			defend_rows += 1
		if r.victory:
			wins += 1
		if int(r.bossAttempts) == 1 and r.victory:
			first_try_boss += 1
	var out := {"runs": rows.size(), "winRate": wins / n, "bossFirstTry": first_try_boss / n, "lost": rows.size() - wins}
	for k: String in keys:
		out[k] = sum[k] / n
	# Wissen beim Verteidigen nur über Läufe mitteln, in denen verteidigt wurde.
	out.defendKnowledge = sum.defendKnowledge / maxf(1.0, defend_rows)
	return out


## Markdown-Tabelle für die Kommandozeile.
static func table(headers: Array, rows: Array) -> String:
	var lines: PackedStringArray = ["| " + " | ".join(PackedStringArray(headers)) + " |", "|" + "---|".repeat(headers.size())]
	for r: Array in rows:
		var cells: PackedStringArray = []
		for c: Variant in r:
			cells.append(String.num(c, 2) if c is float else str(c))
		lines.append("| " + " | ".join(cells) + " |")
	return "\n".join(lines)


## Ein simuliertes Abenteuer (interner Zustand).
class _Run:
	var o: Dictionary
	var c: Dictionary
	var pc: Dictionary
	var sc: Dictionary
	var rng: Callable
	var profile: Dictionary
	var learning: LearningSession
	var knowledge: Dictionary
	var learner: Dictionary
	var map: Dictionary
	var run_state: Dictionary  # wie Ctx.run: seed, heat, map, defeated, opened, learning, hp, focus, runes
	var clock := 0
	var seconds := 0.0
	var hints := 0
	var defend_known := []
	var other_known := []
	var items_bought := 0
	var blessings_taken := 0
	var talents_taken := 0
	var knowledge_before := 0.0
	var pos := Vector2i.ZERO
	var level_scale := 1.0
	var pact := {}
	var combo := 0
	var max_combo := 0
	var last_revenge := false
	var groups_fought := 0
	var last_key := ""
	var armor_broken := 0
	var armor_total := 0
	var set_bonus_heal := false
	var set_bonus_level := ""

	func _init(opts: Dictionary) -> void:
		o = opts
		c = GameConfig.data()
		pc = c.player
		sc = c.simulation
		rng = Rng.create(int(o.seed))
		var vocab: Array = o.vocabulary if not (o.vocabulary as Array).is_empty() else BalanceSim.sample_vocab()
		var items: Array = vocab.map(func(e: Dictionary) -> Dictionary: return {"key": "s/" + str(e.id), "entry": e, "unitId": "s"})
		profile = (o.profile as Dictionary).duplicate(true) if not (o.profile as Dictionary).is_empty() else Player.normalize({}, pc)
		profile.heroClass = o.heroClass
		if (o.profile as Dictionary).is_empty():
			profile.unlockedClasses = ["warrior", "rogue", "mage"]
			profile.unlocks = Unlocks.all_ids()
			profile.skills[o.heroClass] = BalanceSim.full_tree(o.heroClass) if o.skills is String and o.skills == "full" else o.skills
		profile = Meta.reset_run_fields(profile, pc)
		pact = Pact.normalize(o.get("pact", o.heat))
		profile.potions = maxi(0, int(profile.potions) - Pact.rank(pact, "p_supplies"))
		profile.lives = maxi(1, int(profile.lives) - Pact.rank(pact, "p_lives"))
		clock = int(o.clockMs)
		knowledge = o.knowledge
		learner = (sc.learners as Dictionary).get(o.learner, {})
		for item: Dictionary in items:
			if not knowledge.has(item.key):
				knowledge[item.key] = _initial_knowledge()
		for item: Dictionary in items:
			knowledge_before += float(knowledge[item.key])
		knowledge_before /= items.size()
		learning = LearningSession.new(items, o.progress, c.learning, Rng.create(int(o.seed) + 1), func() -> int: return clock, {"unseenBoost": Pact.rank(pact, "p_new") > 0})
		level_scale = RunScaling.level_scale_for(vocab.size())
		var s := _stats()
		run_state = {"seed": int(o.seed), "pact": pact, "heat": Pact.points(pact), "learning": learning, "floor": 1, "floorsCleared": 0, "pastCounts": {},
			"hp": int(s.maxHp), "focus": int(s.maxFocus), "runes": 0}
		_load_floor(1)
		SetBonus.init_run(run_state, items)
		pos = map.start

	## Karte einer Ebene erzeugen (wie GameContext.start_run / descend).
	func _load_floor(floor: int) -> void:
		if floor > 1:
			run_state.pastCounts = Meta.progress_counts(run_state)
		var level_cfg := RunScaling.scale_level_config(c.level, level_scale).duplicate(true)
		var extra := Pact.rank(pact, "p_elite")
		level_cfg.eliteEnemies = {"min": int(level_cfg.eliteEnemies.min) + extra, "max": int(level_cfg.eliteEnemies.max) + extra}
		map = LevelGenerator.generate(Meta.floor_seed(int(o.seed), floor), level_cfg, {
			"bossRunesRequired": RunScaling.scaled_boss_runes(int(c.run.bossRunesRequired), level_scale),
			"enemies": GameData.theme_for_floor(floor).enemies, "group": c.combat.group,
		})
		run_state.floor = floor
		run_state.map = map
		run_state.defeated = {}
		run_state.opened = {}
		run_state.runes = 0
		pos = map.start
		if floor > 1:
			var s := _stats()
			run_state.hp = int(s.maxHp)
			run_state.focus = int(s.maxFocus)

	func _initial_knowledge() -> float:
		if o.learner == "fixed":
			return float(o.accuracy)
		var v: float = float(learner.start) + (rng.call() * 2.0 - 1.0) * float(learner.spread)
		return clampf(v, 0.02, 0.98)

	func _stats() -> Dictionary:
		return Player.compute_stats(profile, pc)

	# ---------- Zeit ----------

	func _walk_to(target: Vector2i) -> void:
		var tiles := absi(target.x - pos.x) + absi(target.y - pos.y)
		var speed := float(sc.time.heroSpeed) * (1.0 + Meta.mod(_stats().mods, "moveSpeed"))
		_spend(tiles * float(sc.time.pathFactor) / speed)
		pos = target

	func _spend(sec: float) -> void:
		seconds += sec
		clock += int(sec * 1000.0)

	# ---------- Lernen ----------

	## Eine Vokabel abfragen (mit Hilfen nach Bot-Regel). Liefert das Ergebnis wie die Abfrage:
	## "correct" | "almostCorrect" | "wrongCorrected". Ein Teil der Fehler sind Tippfehler (simulation.almostShare).
	func ask(mode: String, wallet: Dictionary, reserve_focus: int = 0, action: String = "", key: String = "") -> String:
		var item := learning.word(key) if key != "" else learning.next_word(mode)
		last_key = item.key
		var p := float(knowledge[item.key])
		if action == "defend":
			defend_known.append(p)
		elif action != "":
			other_known.append(p)
		var used := 0
		var hc: Dictionary = sc.hints
		if o.useHints and Pact.hints_allowed(pact) and p < float(hc.useBelow):
			for type: String in ["firstLetter", "length"]:
				var pay := HintService.payment(wallet, type)
				if pay.is_empty() or (pay.source == "focus" and int(wallet.focus) - int(pay.cost) < reserve_focus):
					continue
				var next := HintService.pay(wallet, type)
				wallet.freeCharges = next.freeCharges
				wallet.focus = next.focus
				p = minf(0.98, p + float(hc.firstLetterBoost if type == "firstLetter" else hc.lengthBoost))
				used += 1
				break
		hints += used
		var was_missed: bool = learning.scheduler.wrong_in_run.has(item.key)
		var correct: bool = rng.call() < p
		last_revenge = was_missed and correct
		var outcome := "correct" if correct else ("almostCorrect" if rng.call() < float(sc.almostShare) else "wrongCorrected")
		_spend(float(sc.time.answerSec) + used * float(sc.time.hintSec) + (float(sc.time.wrongExtraSec) if outcome == "wrongCorrected" else 0.0))
		learning.submit(item, Vocab.result(outcome, used))
		combo = Combo.next(combo, Vocab.result(outcome, used))
		for bonus: Dictionary in SetBonus.record(run_state, learning.scheduler._items, item, Vocab.result(outcome, used)):
			var st := _stats()
			run_state.hp = int(st.maxHp)
			run_state.focus = int(st.maxFocus)
			set_bonus_heal = true
			set_bonus_level = bonus.level
		max_combo = maxi(max_combo, combo)
		if o.learner != "fixed":
			var k := float(knowledge[item.key])
			knowledge[item.key] = minf(0.98, k + (1.0 - k) * float(learner.gainCorrect if correct else learner.gainWrong))
		if correct:
			gain_xp(int(c.xp.correctAnswer))
		elif outcome == "almostCorrect":
			gain_xp(int(c.xp.almostAnswer))
		return outcome

	func _wallet(focus: int) -> Dictionary:
		return {"freeCharges": (_stats().freeHints as Dictionary).duplicate(), "focus": focus, "costs": (c.combat.hintFocusCost as Dictionary).duplicate()}

	# ---------- Fortschritt ----------

	## Wie Ctx.gain_xp: Level-up heilt voll und bringt eine Talentwahl. Liefert die neuen Level.
	func gain_xp(amount: int) -> int:
		var res := Player.add_xp(profile, amount, pc)
		profile = res.profile
		var gained: int = res.levelsGained
		if gained > 0:
			profile.pendingTalents = int(profile.get("pendingTalents", 0)) + gained
			var s := _stats()
			run_state.hp = int(s.maxHp)
			run_state.focus = int(s.maxFocus)
		return gained

	func pick_talents() -> void:
		while int(profile.get("pendingTalents", 0)) > 0:
			var offer := Talents.roll(rng, profile.talents, 3, profile)
			if offer.is_empty() or not o.useTalents:
				profile.pendingTalents = 0
				return
			_spend(float(sc.time.choiceSec))
			Meta.add_talent(profile, run_state, _best(offer, TALENT_ORDER).id)
			talents_taken += 1

	func pick_blessing() -> void:
		if not o.useBlessings:
			return
		var offer := Blessings.roll(rng, profile.blessings, int(Meta.cfg().blessingChoices), String(profile.heroClass), profile)
		if offer.is_empty():
			return
		_spend(float(sc.time.choiceSec))
		Meta.add_blessing(profile, run_state, _best(offer, BLESSING_ORDER).id)
		blessings_taken += 1

	func _best(offer: Array, order: Array) -> Dictionary:
		var best: Dictionary = offer[0]
		for d: Dictionary in offer:
			if order.find(d.id) < order.find(best.id):
				best = d
		return best

	static func item_score(item: Dictionary) -> float:
		var fx: Dictionary = item.effects
		return 3.0 * float(fx.get("attack", 0)) + 0.5 * float(fx.get("maxHp", 0)) + 4.0 * float(fx.get("armor", 0)) \
			+ 20.0 * float(fx.get("critChance", 0)) + 0.6 * float(fx.get("maxFocus", 0)) + 6.0 * float(fx.get("skillPower", 0)) \
			+ 0.8 * float(fx.get("lifeOnWin", 0)) + 0.5

	func auto_equip() -> void:
		for id: String in (profile.bag as Array).duplicate():
			var item := GameData.get_item(id)
			var current: Variant = profile.equipment[item.slot]
			if current == null or item_score(item) > item_score(GameData.get_item(current)):
				profile = Player.equip(profile, id)
		# Überflüssiges verkaufen (Gold für den Händler).
		for id: String in (profile.bag as Array).duplicate():
			profile = Player.sell_item(profile, id)
		_clamp()

	func _clamp() -> void:
		var s := _stats()
		run_state.hp = mini(int(run_state.hp), int(s.maxHp))
		run_state.focus = mini(int(run_state.focus), int(s.maxFocus))

	func add_loot(source: String) -> void:
		var loot := LootService.roll_loot(source, rng, func(id: String) -> bool: return Player.owns_item(profile, id), profile)
		var find := Meta.mod(_stats().mods, "goldFind")
		profile.gold = int(profile.gold) + int(round(int(loot.gold) * (1.0 + find)))
		profile.potions = int(profile.potions) + int(loot.potions)
		if loot.itemId != null:
			(profile.bag as Array).append(loot.itemId)
		_spend(float(sc.time.lootSec))
		auto_equip()

	## Am Kristallaltar: heilen und einkaufen.
	func rest(altar: Dictionary) -> void:
		_walk_to(Vector2i(altar.x, altar.y))
		var s := _stats()
		run_state.hp = int(s.maxHp)
		run_state.focus = int(s.maxFocus)
		if not o.useShop:
			return
		var bought := false
		for item: Dictionary in Meta.shop_offers(run_state, profile, altar.id):
			var current: Variant = profile.equipment[item.slot]
			var better := current == null or item_score(item) > item_score(GameData.get_item(current))
			if better and Meta.can_buy_item(profile, item, run_state):
				profile = Meta.buy_item(profile, item, run_state)
				items_bought += 1
				bought = true
		while int(profile.potions) < 3 and Player.can_buy_potion(profile):
			profile = Player.buy_potion(profile)
			bought = true
		if bought:
			_spend(float(sc.time.shopSec))
			auto_equip()
			s = _stats()
			run_state.hp = int(s.maxHp)
			run_state.focus = int(s.maxFocus)

	# ---------- Kampf ----------

	## Ein Kampf. Liefert "won" | "lost".
	func fight(obj: Dictionary) -> String:
		var def := GameData.get_enemy(obj.enemyId)
		var s := _stats()
		var cls := GameData.get_class_def(profile.heroClass)
		var base := {"hp": run_state.hp, "maxHp": s.maxHp, "focus": run_state.focus, "maxFocus": s.maxFocus, "attack": s.attack, "potions": profile.potions}
		var group := CombatService.create_group(obj, int(profile.level), rng, pact, int(run_state.floor))
		var state := CombatService.create_combat(CombatService.combat_player_from(base, cls, s.mods), group)
		if group.size() > 1:
			groups_fought += 1
		if def.tier == "boss":
			state.enemy.armor = Nemesis.pick(learning.scheduler._items, o.progress).map(func(w: Dictionary) -> String: return w.key)
			armor_total += (state.enemy.armor as Array).size()
		var wallet := _wallet(int(run_state.focus))
		while state.outcome == "ongoing":
			var p: Dictionary = state.player
			# Gruppen: den schwächsten lebenden Gegner zuerst angreifen.
			var weakest := -1
			for i in (state.enemies as Array).size():
				var e: Dictionary = state.enemies[i]
				if CombatService.alive(e) and (weakest < 0 or int(e.hp) < int(state.enemies[weakest].hp)):
					weakest = i
			CombatService.set_target(state, weakest)
			var heavy_coming := (state.enemies as Array).any(func(e: Dictionary) -> bool: return CombatService.alive(e) and e.intent == "heavy")
			var action := "attack"
			if int(p.hp) < int(p.maxHp) * 0.35 and CombatService.can_use_action(state, "item"):
				action = "item"
			elif heavy_coming and int(p.hp) < int(p.maxHp) * 0.7:
				action = "defend"
			elif CombatService.can_use_action(state, "skill") and (def.tier != "normal" or profile.heroClass == "mage"):
				action = "skill"
			var mode: String = def.selection
			wallet.focus = int(p.focus)
			var reserve := int(p.skill.focusCost) if action == "skill" else 0
			var level_before := int(profile.level)
			var armor: Array = state.enemy.get("armor", [])
			var key: String = armor[0] if not armor.is_empty() and action in ["attack", "skill"] else ""
			var outcome := ask(mode, wallet, reserve, action, key)
			if outcome == "correct" and not CombatService.break_armor(state, last_key).is_empty():
				armor_broken += 1
			elif key != "":
				armor.erase(key)
				armor.append(key)
			p.focus = int(wallet.focus)
			if set_bonus_heal:
				set_bonus_heal = false
				p.hp = int(p.maxHp)
				p.focus = int(p.maxFocus)
			if int(profile.level) > level_before:
				var ns := _stats()
				p.maxHp = int(ns.maxHp)
				p.maxFocus = int(ns.maxFocus)
				p.attack = int(ns.attack)
				p.hp = int(ns.maxHp)
				p.focus = int(ns.maxFocus)
			if action == "skill" and not CombatService.can_use_action(state, "skill"):
				action = "attack"  # Fokus für eine Hilfe ausgegeben
			var power := float(c.combat.almostPower) if outcome == "almostCorrect" else 1.0
			p.comboMult = Combo.multiplier(combo)
			p.combo = combo
			p.revengeWord = last_revenge
			CombatService.resolve_player_action(state, action, outcome != "wrongCorrected", c.combat, rng, power)
			CombatService.resolve_enemy_turn(state, rng)
			_spend(float(sc.time.combatRoundSec))
		profile.potions = int(state.player.potions)
		if state.outcome == "lost":
			return "lost"
		var p: Dictionary = state.player
		run_state.hp = int(p.hp) + mini(int(p.get("lifeOnWin", 0)), int(p.maxHp) - int(p.hp))
		run_state.focus = mini(int(p.maxFocus), int(p.focus) + 1)
		run_state.defeated[obj.id] = true
		for member in group.size():
			gain_xp(int(c.xp.boss) if def.tier == "boss" else (int(c.xp.eliteEnemy) if def.tier == "elite" else int(c.xp.normalEnemy)))
			add_loot(def.tier)
		if def.tier != "boss":
			run_state.runes = int(run_state.runes) + 1
		if def.tier == "elite":
			pick_blessing()
		pick_talents()
		return "won"

	## Truhe oder Tür: so lange abfragen, bis genug richtig ist.
	func challenge(obj: Dictionary) -> void:
		var needed := (2 if obj.chestType == "rare" else 1) if obj.kind == "chest" else int(obj.answers)
		var mode := "preferHard" if obj.kind == "chest" and obj.chestType == "special" else "normal"
		var wallet := _wallet(int(run_state.focus))
		var got := 0
		while got < needed:
			if ask(mode, wallet) != "wrongCorrected":
				got += 1
		run_state.focus = int(wallet.focus)
		run_state.opened[obj.id] = true
		if obj.kind == "chest":
			gain_xp(int(c.xp.chest))
			add_loot("chestRare" if obj.chestType == "rare" else ("chestSpecial" if obj.chestType == "special" else "chestNormal"))
		else:
			run_state.runes = int(run_state.runes) + 1
		pick_talents()

	## Wissensschrein: jede Vokabel einmal, Belohnung nach Treffern (wie Exploration.run_shrine).
	func shrine(obj: Dictionary) -> void:
		var wallet := _wallet(int(run_state.focus))
		var hits := 0
		for i in int(c.shrine.words):
			if ask("normal", wallet) != "wrongCorrected":
				hits += 1
		run_state.focus = int(wallet.focus)
		run_state.opened[obj.id] = true
		var s := _stats()
		var r := Encounters.shrine_reward(hits, int(s.maxHp))
		profile.gold = int(profile.gold) + int(r.gold)
		run_state.hp = mini(int(s.maxHp), int(run_state.hp) + int(r.heal))
		run_state.focus = mini(int(s.maxFocus), int(run_state.focus) + int(r.focus))
		gain_xp(int(c.xp.shrine))
		_spend(float(sc.time.shrineSec))
		pick_talents()

	## Runenplatte: eine Vokabel, Gold oder ein paar HP Schaden.
	func plate(obj: Dictionary) -> void:
		run_state.opened[obj.id] = true
		var outcome := ask("normal", _wallet(int(run_state.focus)))
		var r := Encounters.plate_result(outcome, int(run_state.hp))
		profile.gold = int(profile.gold) + int(r.gold)
		run_state.hp = int(run_state.hp) - int(r.damage)
		pick_talents()

	# ---------- Ablauf ----------

	## Ebenen nacheinander spielen: Der Bot steigt ab, solange `floors` es erlaubt und er noch 2+ Leben hat.
	func play() -> Dictionary:
		var defeats := 0
		var boss_attempts := 0
		var max_floor := mini(int(o.get("floors", 1)), Meta.max_floors())
		while true:
			var r := _play_floor()
			defeats += int(r.defeats)
			boss_attempts += int(r.bossAttempts)
			if not r.victory:
				return _result(false, defeats, boss_attempts)
			run_state.floorsCleared = int(run_state.floorsCleared) + 1
			if int(run_state.floor) >= max_floor or int(profile.lives) < 2:
				return _result(true, defeats, boss_attempts)
			_load_floor(int(run_state.floor) + 1)
		return {}

	func _play_floor() -> Dictionary:
		var altars: Array = map.objects.filter(func(x: Dictionary) -> bool: return x.kind == "heal")
		var todo: Array = map.objects.filter(func(x: Dictionary) -> bool:
			return x.kind in ["chest", "door", "shrine", "plate"] or (x.kind == "enemy" and x.tier != "boss"))
		var boss: Dictionary = map.objects.filter(func(x: Dictionary) -> bool: return x.kind == "enemy" and x.tier == "boss")[0]
		var defeats := 0
		var boss_attempts := 0
		var alive := true
		var victory := false
		# Nächstgelegenes Ziel zuerst; vor Elite und Boss (und bei wenig HP) zum Altar.
		while alive and not todo.is_empty():
			todo.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _dist(a) < _dist(b))
			var obj: Dictionary = todo[0]
			var low := float(run_state.hp) < float(_stats().maxHp) * float(sc.restBelowHp)
			if obj.kind == "enemy" and (obj.tier == "elite" or low):
				rest(_nearest(altars))
			_walk_to(Vector2i(obj.x, obj.y))
			if obj.kind == "shrine":
				shrine(obj)
			elif obj.kind == "plate":
				plate(obj)
			elif obj.kind == "enemy":
				if fight(obj) == "lost":
					defeats += 1
					alive = Meta.lose_life(profile)
					rest(altars[0])
					continue
			else:
				challenge(obj)
			todo.pop_front()
		while alive and not victory:
			rest(_nearest(altars))
			_walk_to(Vector2i(boss.x, boss.y))
			boss_attempts += 1
			if fight(boss) == "won":
				victory = true
			else:
				defeats += 1
				alive = Meta.lose_life(profile)
		return {"victory": victory, "defeats": defeats, "bossAttempts": boss_attempts}

	func _dist(obj: Dictionary) -> int:
		return absi(int(obj.x) - pos.x) + absi(int(obj.y) - pos.y)

	func _nearest(list: Array) -> Dictionary:
		var best: Dictionary = list[0]
		for x: Dictionary in list:
			if _dist(x) < _dist(best):
				best = x
		return best

	func _result(victory: bool, defeats: int, boss_attempts: int) -> Dictionary:
		var reward := Meta.apply_run_end(profile, run_state, victory)
		run_state.reward = reward
		# Letzte Prüfung (Issue #18): der Bot macht sie immer; jedes Fehlerwort einmal, ohne Hilfen.
		var exam_correct := 0
		var exam_words: Array = learning.run.summary().wrongWords
		if o.get("useFinalExam", true):
			for w: Dictionary in exam_words:
				var key: String = w.item.key
				var ok: bool = rng.call() < float(knowledge[key])
				if ok:
					exam_correct += 1
				var st: Variant = o.progress.get(key)
				o.progress[key] = Vocab.record_answer(st, Vocab.result("correct" if ok else "wrongCorrected"), c.learning, clock)
				_spend(float(sc.time.answerSec))
			Meta.apply_final_exam(profile, run_state, exam_correct)
		var summary := learning.run.summary()
		var known_after := 0.0
		for item: Dictionary in learning.scheduler._items:
			known_after += float(knowledge[item.key])
		known_after /= learning.scheduler._items.size()
		var questions := int(summary.totalQuestions)
		var defend_n := defend_known.size()
		return {
			"victory": victory,
			"defeats": defeats,
			"bossAttempts": boss_attempts,
			"shards": int(reward.total),
			"floorsCleared": int(run_state.floorsCleared),
			"examWords": exam_words.size(),
			"examCorrect": exam_correct,
			"level": int(profile.level),
			"questions": questions,
			"words": (summary.words as Array).size(),
			"firstTry": (summary.firstTryCorrect as Array).size(),
			"hints": hints,
			"minutes": seconds / 60.0,
			"perMinute": questions / maxf(0.01, seconds / 60.0),
			"talents": talents_taken,
			"maxCombo": max_combo,
			"groups": groups_fought,
			"nemesisArmor": armor_total,
			"nemesisBroken": armor_broken,
			"setBonus": 1.0 if set_bonus_level != "" else 0.0,
			"setBonusGolden": 1.0 if set_bonus_level == "golden" else 0.0,
			"blessings": blessings_taken,
			"itemsBought": items_bought,
			"knowledgeGain": known_after - knowledge_before,
			"defendShare": float(defend_n) / maxf(1.0, float(defend_n + other_known.size())),
			"defendKnowledge": _avg(defend_known),
			"otherKnowledge": _avg(other_known),
			"clockMs": clock,
			"profile": profile,
		}

	static func _avg(list: Array) -> float:
		if list.is_empty():
			return 0.0
		var s := 0.0
		for v: float in list:
			s += v
		return s / list.size()
