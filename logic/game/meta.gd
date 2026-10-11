class_name Meta
extends RefCounted
## Rogue-lite-Fortschritt über alle Abenteuer hinweg.
##
## Dauerhaft (im Profil):  shards (Tempelsplitter 🔷), unlockedClasses, skills {klasse: {knoten: rang}},
##                         records {runs, victories, shardsTotal}
## Pro Abenteuer (werden bei jedem Start zurückgesetzt): level, xp, gold, potions, equipment, bag,
##                         blessings (Segnungen), lives (verbleibende Leben)
##
## Splitter gibt es am Ende jedes Abenteuers (Sieg oder vorzeitiges Ende) für besiegte Gegner, geöffnete
## Truhen und Türen, richtig erinnerte Vokabeln und einen Sieg über den Boss.

const ICON := "🔷"
const CURRENCY := "Tempelsplitter"
const START_EQUIPMENT := {"weapon": "wooden_sword", "helmet": null, "ring": null}


static func cfg() -> Dictionary:
	return GameConfig.section("meta")


## Fehlende Felder ergänzen (ältere Spielstände) und eine gesperrte Klasse auf den Krieger zurücksetzen.
static func ensure(profile: Dictionary) -> Dictionary:
	if not profile.has("shards"):
		profile.shards = 0
	profile.shards = int(profile.shards)
	if not profile.get("blessings") is Array:
		profile.blessings = []
	profile.lives = int(profile.get("lives", cfg().lives))
	if not profile.get("unlockedClasses") is Array or (profile.unlockedClasses as Array).is_empty():
		profile.unlockedClasses = ["warrior"]
	if not profile.get("skills") is Dictionary:
		profile.skills = {}
	for c: Dictionary in GameData.HERO_CLASSES:
		if not (profile.skills as Dictionary).get(c.id) is Dictionary:
			profile.skills[c.id] = {}
		for k: String in profile.skills[c.id]:
			profile.skills[c.id][k] = int(profile.skills[c.id][k])
	var rec := {"runs": 0, "victories": 0, "shardsTotal": 0}
	if profile.get("records") is Dictionary:
		rec.merge(profile.records, true)
	for k: String in rec:
		rec[k] = int(rec[k])
	profile.records = rec
	if not is_class_unlocked(profile, profile.get("heroClass", "warrior")):
		profile.heroClass = "warrior"
	return profile


# ---------- Klassen ----------

static func is_class_unlocked(profile: Dictionary, class_id: Variant) -> bool:
	return (profile.get("unlockedClasses", ["warrior"]) as Array).has(class_id)


static func unlock_cost(class_id: String) -> int:
	return int(cfg().classUnlockCost.get(class_id, 0))


static func can_unlock_class(profile: Dictionary, class_id: String) -> bool:
	return not is_class_unlocked(profile, class_id) and int(profile.shards) >= unlock_cost(class_id)


static func unlock_class(profile: Dictionary, class_id: String) -> Dictionary:
	if not can_unlock_class(profile, class_id):
		return profile
	var next := profile.duplicate(true)
	next.shards = int(profile.shards) - unlock_cost(class_id)
	(next.unlockedClasses as Array).append(class_id)
	return next


# ---------- Skillbaum ----------

static func rank(profile: Dictionary, class_id: String, node_id: String) -> int:
	return int((profile.get("skills", {}) as Dictionary).get(class_id, {}).get(node_id, 0))


## Kosten für den nächsten Rang: Stufenpreis × Rang (1. Rang einfach, 2. doppelt …).
static func node_cost(node: Dictionary, next_rank: int) -> int:
	var tier_cost: Array = cfg().tierCost
	return int(tier_cost[int(node.tier) - 1]) * next_rank


## { ok: bool, cost: int, reason: String }
static func can_learn(profile: Dictionary, class_id: String, node_id: String) -> Dictionary:
	var node := SkillTrees.get_node_def(class_id, node_id)
	if node.is_empty():
		return {"ok": false, "cost": 0, "reason": "Unbekannte Fertigkeit."}
	var r := rank(profile, class_id, node_id)
	if r >= int(node.maxRank):
		return {"ok": false, "cost": 0, "reason": "Höchster Rang erreicht."}
	var cost := node_cost(node, r + 1)
	if not is_class_unlocked(profile, class_id):
		return {"ok": false, "cost": cost, "reason": "Klasse noch nicht freigeschaltet."}
	if node.requires != "" and rank(profile, class_id, node.requires) < 1:
		return {"ok": false, "cost": cost, "reason": "Benötigt „%s“." % SkillTrees.get_node_def(class_id, node.requires).name}
	if int(profile.shards) < cost:
		return {"ok": false, "cost": cost, "reason": "Zu wenige %s." % CURRENCY}
	return {"ok": true, "cost": cost, "reason": ""}


static func learn(profile: Dictionary, class_id: String, node_id: String) -> Dictionary:
	var check := can_learn(profile, class_id, node_id)
	if not check.ok:
		return profile
	var next := profile.duplicate(true)
	next.shards = int(profile.shards) - int(check.cost)
	next.skills[class_id][node_id] = rank(profile, class_id, node_id) + 1
	return next


## Summe aller gelernten Effekte einer Klasse, z. B. { maxHp: 12, moveSpeed: 0.16 }.
static func mods(profile: Dictionary, class_id: String) -> Dictionary:
	var sum := {}
	for node: Dictionary in SkillTrees.tree(class_id).nodes:
		var r := rank(profile, class_id, node.id)
		if r <= 0:
			continue
		for key: String in node.effect:
			sum[key] = float(sum.get(key, 0.0)) + float(node.effect[key]) * r
	return sum


static func mod(mods_dict: Dictionary, key: String) -> float:
	return float(mods_dict.get(key, 0.0))


## Insgesamt in eine Klasse investierte Splitter (für die Anzeige).
static func invested(profile: Dictionary, class_id: String) -> int:
	var total := 0
	for node: Dictionary in SkillTrees.tree(class_id).nodes:
		for r in range(1, rank(profile, class_id, node.id) + 1):
			total += node_cost(node, r)
	return total


# ---------- Abenteuer ----------

## Setzt die Lauf-Werte für ein neues Abenteuer zurück (Ausrüstung, Gold, Level gelten nur im Lauf).
static func reset_run_fields(profile: Dictionary, player_cfg: Dictionary) -> Dictionary:
	var next := profile.duplicate(true)
	var m := mods(profile, profile.heroClass)
	next.level = 1
	next.xp = 0
	next.gold = int(mod(m, "startGold"))
	next.potions = int(player_cfg.startPotions) + int(mod(m, "startPotions"))
	next.equipment = START_EQUIPMENT.duplicate()
	next.bag = []
	next.blessings = []
	next.lives = int(cfg().lives)
	return next


## Belohnung für ein beendetes Abenteuer: { total, lines: [[Text, Splitter], …] }
static func run_reward(run: Dictionary, victory: bool, profile: Dictionary) -> Dictionary:
	var c: Dictionary = cfg().shards
	var counts := {"normal": 0, "elite": 0, "boss": 0, "chest": 0, "door": 0}
	for obj: Dictionary in run.map.objects:
		if obj.kind == "enemy" and run.defeated.has(obj.id):
			counts[obj.tier] += 1
		elif obj.kind == "chest" and run.opened.has(obj.id):
			counts.chest += 1
		elif obj.kind == "door" and run.opened.has(obj.id):
			counts.door += 1
	var correct := 0
	var learning: LearningSession = run.learning
	for r: Dictionary in learning.run.records.values():
		correct += int(r.correct)
	var lines: Array = []
	var add := func(label: String, n: int, per: int) -> void:
		if n > 0 and per > 0:
			lines.append(["%s ×%d" % [label, n], n * per])
	add.call("Gegner", counts.normal, int(c.normalEnemy))
	add.call("Elite-Gegner", counts.elite, int(c.eliteEnemy))
	add.call("Boss", counts.boss, int(c.boss))
	add.call("Truhen", counts.chest, int(c.chest))
	add.call("Türen", counts.door, int(c.door))
	var per_words := int(c.correctPer)
	if per_words > 0 and correct >= per_words:
		lines.append(["%d richtig erinnerte Vokabeln" % correct, correct / per_words])
	if victory:
		lines.append(["Tempel bezwungen", int(c.victory)])
	var subtotal := 0
	for l: Array in lines:
		subtotal += int(l[1])
	var bonus_share := mod(mods(profile, profile.heroClass), "shardBonus")
	var bonus := int(floor(subtotal * bonus_share))
	if bonus > 0:
		lines.append(["Fertigkeiten-Bonus +%d %%" % roundi(bonus_share * 100.0), bonus])
	return {"total": subtotal + bonus, "lines": lines}



# ---------- Leben, Segnungen, Händler (nur im laufenden Abenteuer) ----------

## Eine Niederlage kostet ein Leben. Liefert true, wenn noch Leben übrig sind (Erwachen am Altar).
static func lose_life(profile: Dictionary) -> bool:
	profile.lives = maxi(0, int(profile.lives) - 1)
	return int(profile.lives) > 0


## Segnung annehmen; ein HP-Bonus füllt auch die aktuellen HP entsprechend auf.
static func add_blessing(profile: Dictionary, run: Dictionary, id: String) -> void:
	var b := Blessings.get_blessing(id)
	if b.is_empty() or (profile.blessings as Array).has(id):
		return
	(profile.blessings as Array).append(id)
	if not run.is_empty():
		run.hp = int(run.hp) + int(b.effect.get("maxHp", 0))


## Händler am Kristallaltar: je Abenteuer und Altar feste Angebote (Seed), ohne bereits besessene Gegenstände.
static func shop_offers(run: Dictionary, profile: Dictionary, altar_id: String) -> Array:
	var rng := Rng.create((int(run.seed) * 31 + altar_id.hash()) & Rng.MASK)
	# Erst feste Auswahl ziehen, dann Gekauftes/Besessenes ausblenden – Gekauftes wird nicht nachgefüllt.
	var picks := Rng.shuffle(rng, GameData.ITEMS.duplicate()).slice(0, int(cfg().shopOffers))
	return picks.filter(func(i: Dictionary) -> bool: return not Player.owns_item(profile, i.id))


static func shop_price(item: Dictionary) -> int:
	return int(cfg().shopPrice[item.rarity])


static func can_buy_item(profile: Dictionary, item: Dictionary) -> bool:
	return int(profile.gold) >= shop_price(item) and not Player.owns_item(profile, item.id)


## Kauft einen Gegenstand in die Tasche.
static func buy_item(profile: Dictionary, item: Dictionary) -> Dictionary:
	if not can_buy_item(profile, item):
		return profile
	var next := profile.duplicate(true)
	next.gold = int(profile.gold) - shop_price(item)
	(next.bag as Array).append(item.id)
	return next
