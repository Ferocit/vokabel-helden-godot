class_name CombatService
extends RefCounted
## Reine Rundenlogik ohne Darstellung.
## Aktionen: "attack" | "defend" | "skill" | "item"
## CombatState { player, enemy, defending, outcome: "ongoing"|"won"|"lost", round }
##   player { hp, maxHp, focus, maxFocus, attack, potions, skill, defendFactor, critChance, critMultiplier, focusOnCorrect,
##            armor, potionHealBonus, lifeOnWin }
##   enemy  { def, hp, maxHp, attack, phase, poison ({turns, damage} oder null), intent, patternIndex, guarding }
## Events sind Dictionaries mit "type": damage | enemyMove | enemyHeal | intent | poisonTick | poisoned |
##   heal | focus | defend | fizzle | phase | enemyDefeated | playerDefeated


static func action_label(action: String, player: Dictionary) -> String:
	match action:
		"attack":
			return "Angriff"
		"defend":
			return "Verteidigen"
		"skill":
			return player.skill.name
		_:
			return "Heiltrank"


## Was eine Aktion gerade bewirken würde, mit den aktuellen Werten (Issue #7).
static func action_effect(action: String, state: Dictionary, cfg: Dictionary) -> String:
	var p: Dictionary = state.player
	var atk := int(p.attack)
	var guarded: bool = state.enemy.guarding
	var halved := " (halbiert: Gegner ist gepanzert)" if guarded else ""
	match action:
		"attack":
			var text := "Trifft für %d–%d Schaden%s." % [atk, atk + 2, halved]
			if float(p.critChance) > 0.0:
				text += " %d %% Chance auf einen kritischen Treffer (×%s)." % [roundi(float(p.critChance) * 100.0), String.num(float(p.critMultiplier), 1)]
			return text
		"defend":
			return "Der nächste gegnerische Angriff macht nur %d %% Schaden. Ideal vor einem schweren Schlag." % roundi(float(p.defendFactor) * 100.0)
		"skill":
			var skill: Dictionary = p.skill
			var dmg := js_round(atk * float(skill.multiplier))
			var text := "Trifft für %d–%d Schaden%s, kostet %d FP." % [dmg, dmg + 2, halved, int(skill.focusCost)]
			if skill.has("poisonTurns"):
				text += " Dazu Gift: %d Runden je %d Schaden." % [int(skill.poisonTurns), maxi(1, js_round(atk * float(skill.get("poisonFactor", 0.5))))]
			return text
		_:
			var heal := int(cfg.potionHeal) + int(p.get("potionHealBonus", 0))
			return "Heilt bis zu %d HP. Noch %d Heiltränke." % [heal, int(p.potions)]


static func js_round(x: float) -> int:
	return int(floor(x + 0.5))


## Kampfwerte des Helden aus Grundwerten {hp, maxHp, focus, maxFocus, attack, potions}, Klasse und
## optional den Skillbaum-Effekten (Meta.mods).
static func combat_player_from(base: Dictionary, cls: Dictionary, mods: Dictionary = {}) -> Dictionary:
	var p := base.duplicate()
	var skill: Dictionary = (cls.skill as Dictionary).duplicate()
	skill.multiplier = float(skill.multiplier) + Meta.mod(mods, "skillPower")
	if skill.has("poisonTurns"):
		skill.poisonTurns = int(skill.poisonTurns) + int(Meta.mod(mods, "poisonTurns"))
	p.skill = skill
	p.defendFactor = maxf(0.05, float(cls.defendFactor) - Meta.mod(mods, "defend"))
	p.critChance = minf(0.9, float(cls.critChance) + Meta.mod(mods, "critChance"))
	p.critMultiplier = float(cls.critMultiplier) + Meta.mod(mods, "critMult")
	p.focusOnCorrect = cls.focusOnCorrect
	p.armor = int(Meta.mod(mods, "armor"))
	p.potionHealBonus = int(Meta.mod(mods, "potionHeal"))
	p.lifeOnWin = int(Meta.mod(mods, "lifeOnWin"))
	return p


## Gegnerwerte wachsen leicht mit dem Spielerlevel, damit Kämpfe spannend bleiben.
## `heat` = Tempelstufe (Rogue-lite-Schwierigkeit), siehe Meta.heat_*.
static func create_enemy(def: Dictionary, player_level: int, rng: Variant = null, heat: int = 0) -> Dictionary:
	var scale := (1.0 + 0.12 * (player_level - 1)) * Meta.heat_hp_factor(heat)
	var hp := js_round(float(def.hp) * scale)
	var pattern: Array = def.pattern
	var start := int(floor((rng as Callable).call() * pattern.size())) if rng is Callable else 0
	return {
		"def": def,
		"hp": hp,
		"maxHp": hp,
		"attack": js_round(float(def.attack) * (1.0 + 0.05 * (player_level - 1)) * Meta.heat_attack_factor(heat)),
		"phase": 1,
		"poison": null,
		"intent": pattern[start],
		"patternIndex": start,
		"guarding": false,
	}


static func _current_pattern(enemy: Dictionary) -> Array:
	if int(enemy.phase) == 2 and enemy.def.has("phase2Pattern"):
		return enemy.def.phase2Pattern
	return enemy.def.pattern


static func create_combat(player: Dictionary, enemy: Dictionary) -> Dictionary:
	return {"player": player.duplicate(), "enemy": enemy.duplicate(), "defending": false, "outcome": "ongoing", "round": 1}


static func can_use_action(state: Dictionary, action: String) -> bool:
	if state.outcome != "ongoing":
		return false
	var p: Dictionary = state.player
	if action == "skill":
		return int(p.focus) >= int(p.skill.focusCost)
	if action == "item":
		return int(p.potions) > 0 and int(p.hp) < int(p.maxHp)
	return true


## Führt die gewählte Aktion aus. Nur bei richtig erinnerter Vokabel wirkt sie;
## bei falscher Antwort verpufft sie, ohne Fokus oder Items zu verbrauchen.
## `power` < 1 schwächt die Wirkung ab („fast richtig“, Issue #17): Schaden, Heilung und Verteidigen.
static func resolve_player_action(state: Dictionary, action: String, answered_correctly: bool, cfg: Dictionary, rng: Callable, power: float = 1.0) -> Array:
	var events: Array = []
	state.defending = false
	state.defendPower = 1.0
	if not answered_correctly:
		events.append({"type": "fizzle", "action": action})
		return events
	if power < 1.0:
		events.append({"type": "weak", "action": action, "power": power})

	var player: Dictionary = state.player
	var enemy: Dictionary = state.enemy
	match action:
		"attack":
			var crit: bool = rng.call() < float(player.critChance)
			var base: int = int(player.attack) + Rng.rand_int(rng, 0, 2)
			var dmg: int = js_round(base * float(player.critMultiplier)) if crit else base
			events.append_array(_damage_enemy(state, maxi(1, js_round(dmg * power)), crit))
		"skill":
			var skill: Dictionary = player.skill
			player.focus = int(player.focus) - int(skill.focusCost)
			var hit: int = js_round(int(player.attack) * float(skill.multiplier)) + Rng.rand_int(rng, 0, 2)
			events.append_array(_damage_enemy(state, maxi(1, js_round(hit * power)), false))
			if skill.has("poisonTurns") and state.outcome == "ongoing":
				var dmg := maxi(1, js_round(int(player.attack) * float(skill.get("poisonFactor", 0.5))))
				enemy.poison = {"turns": int(skill.poisonTurns), "damage": dmg}
				events.append({"type": "poisoned", "turns": int(skill.poisonTurns)})
		"defend":
			state.defending = true
			state.defendPower = power
			events.append({"type": "defend"})
		"item":
			player.potions = int(player.potions) - 1
			var healed := mini(js_round((int(cfg.potionHeal) + int(player.get("potionHealBonus", 0))) * power), int(player.maxHp) - int(player.hp))
			player.hp = int(player.hp) + healed
			events.append({"type": "heal", "amount": healed})

	# Der Panzer des Gegners hält genau einen Zug des Helden.
	enemy.guarding = false

	if int(player.focusOnCorrect) > 0 and int(player.focus) < int(player.maxFocus):
		var gain := mini(int(player.focusOnCorrect), int(player.maxFocus) - int(player.focus))
		player.focus = int(player.focus) + gain
		events.append({"type": "focus", "amount": gain})
	events.append_array(_check_phase(state))
	return events


static func resolve_enemy_turn(state: Dictionary, rng: Callable) -> Array:
	if state.outcome != "ongoing":
		return []
	var events: Array = []
	var enemy: Dictionary = state.enemy
	var player: Dictionary = state.player

	if enemy.poison != null:
		var poison: Dictionary = enemy.poison
		var amount := mini(int(poison.damage), int(enemy.hp))
		enemy.hp = int(enemy.hp) - amount
		poison.turns = int(poison.turns) - 1
		if int(poison.turns) <= 0:
			enemy.poison = null
		events.append({"type": "poisonTick", "amount": amount})
		if int(enemy.hp) <= 0:
			state.outcome = "won"
			events.append({"type": "enemyDefeated"})
			return events
		events.append_array(_check_phase(state))

	var move: Dictionary = GameData.ENEMY_MOVES[enemy.intent]
	events.append({"type": "enemyMove", "move": move.id})
	if move.id == "guard":
		enemy.guarding = true
	if move.id == "regenerate":
		var heal := mini(int(enemy.maxHp) - int(enemy.hp), maxi(1, js_round(int(enemy.maxHp) * 0.2)))
		enemy.hp = int(enemy.hp) + heal
		events.append({"type": "enemyHeal", "amount": heal})
	var hit := 0
	while hit < int(move.hits) and int(player.hp) > 0:
		var raw := maxi(1, js_round(int(enemy.attack) * float(move.power)) + Rng.rand_int(rng, -1, 1))
		# Halbes Verteidigen („fast richtig“) hält nur einen Teil dessen ab, was volles Verteidigen abhält.
		var factor := 1.0 - (1.0 - float(player.defendFactor)) * float(state.get("defendPower", 1.0))
		var amount := maxi(1, int(floor(raw * factor))) if state.defending else raw
		amount = maxi(1, amount - int(player.get("armor", 0)))
		player.hp = maxi(0, int(player.hp) - amount)
		events.append({"type": "damage", "target": "player", "amount": amount, "blocked": state.defending})
		hit += 1
	state.defending = false
	state.round = int(state.round) + 1
	if int(player.hp) == 0:
		state.outcome = "lost"
		events.append({"type": "playerDefeated"})
		return events
	var pattern := _current_pattern(enemy)
	enemy.patternIndex = (int(enemy.patternIndex) + 1) % pattern.size()
	enemy.intent = pattern[enemy.patternIndex]
	events.append({"type": "intent", "move": enemy.intent})
	return events


static func _check_phase(state: Dictionary) -> Array:
	var enemy: Dictionary = state.enemy
	var def: Dictionary = enemy.def
	if int(enemy.hp) > 0 and int(enemy.phase) == 1 and def.has("phase2At") and int(enemy.hp) <= int(enemy.maxHp) * float(def.phase2At):
		enemy.phase = 2
		enemy.attack = js_round(int(enemy.attack) * float(def.get("phase2AttackMultiplier", 1.0)))
		var events: Array = [{"type": "phase", "text": def.get("phase2Text", "%s wird stärker!" % def.name)}]
		if def.has("phase2Pattern"):
			enemy.patternIndex = 0
			enemy.intent = def.phase2Pattern[0]
			events.append({"type": "intent", "move": enemy.intent})
		return events
	return []


static func _damage_enemy(state: Dictionary, raw_amount: int, crit: bool) -> Array:
	var enemy: Dictionary = state.enemy
	var guarded: bool = enemy.guarding
	var amount := maxi(1, int(ceil(raw_amount / 2.0))) if guarded else raw_amount
	enemy.hp = maxi(0, int(enemy.hp) - amount)
	var events: Array = [{"type": "damage", "target": "enemy", "amount": amount, "crit": crit, "guarded": guarded}]
	if int(enemy.hp) == 0:
		state.outcome = "won"
		events.append({"type": "enemyDefeated"})
	return events
