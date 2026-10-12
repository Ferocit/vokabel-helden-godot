class_name GameData
extends RefCounted
## Statische Spieldaten: Klassen, Gegner, Gegneraktionen, Items, Welt-Themen.
## Frames beziehen sich auf das Kenney-Tiny-Dungeon-Sheet (assets/tiles/dungeon.png, 12 Spalten, 16 px).

# ---------- Klassen ----------
## Keine Klasse verändert die Strenge der Vokabelprüfung – nur Kampfwerte und Hilfe-Ressourcen.
const HERO_CLASSES: Array[Dictionary] = [
	{
		"id": "warrior", "name": "Krieger", "tagline": "Robust und schlagkräftig",
		"description": "Viele Lebenspunkte und eine starke Verteidigung. Gut für alle, die gerne mittendrin sind.",
		"frame": 96, "hpBonus": 14, "focusBonus": 0, "attackBonus": 1,
		"skill": {"name": "Wuchtschlag", "description": "Ein gewaltiger Hieb mit doppeltem Schaden.", "focusCost": 3, "multiplier": 2.2},
		"passiveName": "Eiserne Haut", "passiveDescription": "Verteidigen hält 70 % des Schadens ab.",
		"defendFactor": 0.3, "critChance": 0.05, "critMultiplier": 1.5, "focusOnCorrect": 0, "freeHints": {},
		"steps": {"sound": "step_heavy", "volume": 0.32, "rate": 0.85, "interval": 0.38},
	},
	{
		"id": "rogue", "name": "Schurke", "tagline": "Flink und listig",
		"description": "Trifft oft kritisch und vergiftet Gegner. Findet Spuren – der erste Buchstabe ist einmal pro Begegnung gratis.",
		"frame": 112, "hpBonus": 4, "focusBonus": 1, "attackBonus": 1,
		"skill": {"name": "Giftklinge", "description": "Treffer plus Gift, das drei Runden lang Schaden macht.", "focusCost": 2, "multiplier": 1.2, "poisonTurns": 3, "poisonFactor": 0.6},
		"passiveName": "Präzision & Spurenleser", "passiveDescription": "25 % Chance auf kritische Treffer. 1× erster Buchstabe gratis pro Begegnung.",
		"defendFactor": 0.5, "critChance": 0.25, "critMultiplier": 1.8, "focusOnCorrect": 0, "freeHints": {"firstLetter": 1},
		"steps": {"sound": "step_light", "volume": 0.13, "rate": 1.3, "interval": 0.25},
	},
	{
		"id": "mage", "name": "Magier", "tagline": "Weise und mächtig",
		"description": "Wenig Lebenspunkte, aber viel Fokus. Jede richtig erinnerte Vokabel lädt Fokus auf – für mächtige Feuerbälle.",
		"frame": 84, "hpBonus": -4, "focusBonus": 4, "attackBonus": -1,
		"skill": {"name": "Feuerball", "description": "Ein lodernder Zauber mit hohem Schaden.", "focusCost": 3, "multiplier": 2.7},
		"passiveName": "Weisheit", "passiveDescription": "+1 Fokus pro richtiger Vokabel. 1× Wortlänge gratis pro Begegnung.",
		"defendFactor": 0.5, "critChance": 0.05, "critMultiplier": 1.5, "focusOnCorrect": 1, "freeHints": {"length": 1},
		"steps": {"sound": "step_soft", "volume": 0.07, "rate": 1.1, "interval": 0.36, "extra": "step_cloth"},
	},
]


static func get_class_def(id: Variant) -> Dictionary:
	for c in HERO_CLASSES:
		if c.id == id:
			return c
	return HERO_CLASSES[0]


# ---------- Gegner ----------
## Was ein Gegner als Nächstes vorhat, wird im Kampf angezeigt – so wird Verteidigen eine echte Entscheidung.
const ENEMY_MOVES := {
	"attack": {"id": "attack", "name": "Angriff", "icon": "⚔", "hint": "Normaler Angriff.", "power": 1.0, "hits": 1},
	"quick": {"id": "quick", "name": "Doppelangriff", "icon": "⚔⚔", "hint": "Zwei schnelle, schwächere Treffer.", "power": 0.6, "hits": 2},
	"heavy": {"id": "heavy", "name": "Schwerer Schlag", "icon": "✸", "hint": "Doppelter Schaden – jetzt lohnt sich Verteidigen!", "power": 2.0, "hits": 1},
	"charge": {"id": "charge", "name": "Holt aus", "icon": "⏳", "hint": "Kein Schaden, aber danach kommt ein schwerer Schlag.", "power": 0.0, "hits": 0},
	"guard": {"id": "guard", "name": "Panzern", "icon": "⛨", "hint": "Dein nächster Treffer macht nur halben Schaden – gute Gelegenheit zum Heilen.", "power": 0.0, "hits": 0},
	"regenerate": {"id": "regenerate", "name": "Regeneriert", "icon": "✚", "hint": "Heilt sich ein wenig – greif kräftig an!", "power": 0.0, "hits": 0},
}

const ENEMIES: Array[Dictionary] = [
	{"id": "moss_spirit", "name": "Moosgeist", "tier": "normal", "hp": 9, "attack": 3, "frame": 108, "selection": "normal", "pattern": ["attack", "attack", "regenerate"]},
	{"id": "bat", "name": "Fledermaus", "tier": "normal", "hp": 11, "attack": 3, "frame": 120, "selection": "normal", "pattern": ["quick", "attack"]},
	{"id": "spider", "name": "Dschungelspinne", "tier": "normal", "hp": 13, "attack": 4, "frame": 122, "selection": "normal", "pattern": ["attack", "charge", "heavy"]},
	{"id": "jungle_rat", "name": "Dschungelratte", "tier": "normal", "hp": 14, "attack": 4, "frame": 123, "selection": "normal", "pattern": ["attack", "quick", "charge", "heavy"]},
	{"id": "stone_rat", "name": "Steinratte", "tier": "normal", "hp": 15, "attack": 3, "frame": 124, "selection": "normal", "pattern": ["guard", "attack", "attack"]},
	{"id": "temple_ghost", "name": "Tempelgeist", "tier": "normal", "hp": 12, "attack": 4, "frame": 121, "selection": "normal", "pattern": ["quick", "charge", "heavy"]},
	{"id": "temple_guard", "name": "Tempelwächter", "tier": "elite", "hp": 32, "attack": 5, "frame": 111, "selection": "preferHard", "pattern": ["attack", "guard", "charge", "heavy"]},
	{"id": "giant_crab", "name": "Riesenkrabbe", "tier": "elite", "hp": 36, "attack": 5, "frame": 110, "selection": "preferHard", "pattern": ["quick", "guard", "charge", "heavy"]},
	{
		"id": "temple_cyclops", "name": "Zyklop des Tempels", "tier": "boss", "hp": 62, "attack": 4, "frame": 109, "selection": "preferHard",
		"pattern": ["attack", "charge", "heavy", "quick"],
		"phase2Pattern": ["quick", "charge", "heavy", "guard", "heavy"],
		"phase2At": 0.5, "phase2AttackMultiplier": 1.3,
		"phase2Text": "Das Auge des Zyklopen glüht auf! Seine Angriffe werden stärker.",
	},
	# Kristallhöhle (Ebene 2): eingefärbte Dungeon-Sprites (Issue #28).
	{"id": "crystal_bat", "name": "Kristallfledermaus", "tier": "normal", "hp": 11, "attack": 3, "frame": 120, "tint": "#d0a8ff", "selection": "normal", "pattern": ["quick", "attack"]},
	{"id": "cave_spider", "name": "Höhlenspinne", "tier": "normal", "hp": 13, "attack": 4, "frame": 122, "tint": "#b090ff", "selection": "normal", "pattern": ["attack", "charge", "heavy"]},
	{"id": "shadow_ghost", "name": "Schattengeist", "tier": "normal", "hp": 12, "attack": 4, "frame": 121, "tint": "#9a88d8", "selection": "normal", "pattern": ["quick", "charge", "heavy"]},
	{"id": "glow_slime", "name": "Leuchtschleim", "tier": "normal", "hp": 10, "attack": 3, "frame": 108, "tint": "#a8ffe8", "selection": "normal", "pattern": ["attack", "attack", "regenerate"]},
	{"id": "crystal_guard", "name": "Kristallwächter", "tier": "elite", "hp": 34, "attack": 5, "frame": 111, "tint": "#c0a0ff", "selection": "preferHard", "pattern": ["attack", "guard", "charge", "heavy"]},
	{"id": "rock_crab", "name": "Felsenkrabbe", "tier": "elite", "hp": 36, "attack": 5, "frame": 110, "tint": "#a898c0", "selection": "preferHard", "pattern": ["quick", "guard", "charge", "heavy"]},
	{
		"id": "crystal_colossus", "name": "Kristallkoloss", "tier": "boss", "hp": 62, "attack": 4, "frame": 109, "tint": "#c8a8ff", "selection": "preferHard",
		"pattern": ["attack", "guard", "charge", "heavy"],
		"phase2Pattern": ["quick", "charge", "heavy", "guard", "heavy"],
		"phase2At": 0.5, "phase2AttackMultiplier": 1.3,
		"phase2Text": "Die Kristalle des Kolosses beginnen zu glühen! Seine Schläge werden härter.",
	},
	# Eistempel (Ebene 3): Kenney Tiny Ski.
	{"id": "snowman", "name": "Böser Schneemann", "tier": "normal", "hp": 12, "attack": 3, "frame": 69, "sheet": "ski", "selection": "normal", "pattern": ["attack", "guard", "attack"]},
	{"id": "frost_bat", "name": "Frostfledermaus", "tier": "normal", "hp": 11, "attack": 3, "frame": 120, "tint": "#c0ecff", "selection": "normal", "pattern": ["quick", "attack"]},
	{"id": "frost_ghost", "name": "Frostgeist", "tier": "normal", "hp": 12, "attack": 4, "frame": 121, "tint": "#d8f4ff", "selection": "normal", "pattern": ["quick", "charge", "heavy"]},
	{"id": "young_yeti", "name": "Junger Yeti", "tier": "normal", "hp": 14, "attack": 4, "frame": 78, "sheet": "ski", "selection": "normal", "pattern": ["attack", "quick", "charge", "heavy"]},
	{"id": "yeti", "name": "Yeti", "tier": "elite", "hp": 36, "attack": 5, "frame": 79, "sheet": "ski", "selection": "preferHard", "pattern": ["attack", "guard", "charge", "heavy"]},
	{"id": "ice_guard", "name": "Eiswächter", "tier": "elite", "hp": 34, "attack": 5, "frame": 111, "tint": "#b0e0ff", "selection": "preferHard", "pattern": ["quick", "guard", "charge", "heavy"]},
	{
		"id": "yeti_king", "name": "Yeti-König", "tier": "boss", "hp": 62, "attack": 4, "frame": 80, "sheet": "ski", "selection": "preferHard",
		"pattern": ["attack", "charge", "heavy", "quick"],
		"phase2Pattern": ["quick", "charge", "heavy", "guard", "heavy"],
		"phase2At": 0.5, "phase2AttackMultiplier": 1.3,
		"phase2Text": "Der Yeti-König brüllt – Eis splittert von der Decke!",
	},
]


static func get_enemy(id: String) -> Dictionary:
	for e in ENEMIES:
		if e.id == id:
			return e
	push_error("Unbekannter Gegner: %s" % id)
	return ENEMIES[0]


static func enemies_of_tier(tier: String) -> Array:
	return ENEMIES.filter(func(e: Dictionary) -> bool: return e.tier == tier)


# ---------- Items ----------
const SLOT_LABELS := {"weapon": "Waffe", "helmet": "Helm", "ring": "Ring"}
const SLOTS: Array[String] = ["weapon", "helmet", "ring"]
const RARITY_LABELS := {"common": "gewöhnlich", "uncommon": "ungewöhnlich", "rare": "selten"}
## Verkaufspreis beim Händler (Issue #15).
const SELL_PRICE := {"common": 10, "uncommon": 25, "rare": 60}
const POTION_PRICE := 20
const MAX_POTIONS := 9

## Designregel: Ausrüstung verbessert Kampf, Bewegung und Beute, gibt aber keine Vokabelhilfen (keine Gratis-Hilfen).
## Ausnahme ist der Bibliotheksring: Er lässt falsch beantwortete Wörter früher wiederkommen – das hilft beim Lernen,
## nicht beim Antworten. Effekte jenseits von attack/maxHp/maxFocus/repeatGapReduction nutzen dieselben Schlüssel wie
## die Skillbäume (siehe SkillTrees.EFFECT_TEXT) und werden zu den Skill-Effekten addiert.
const ITEMS: Array[Dictionary] = [
	{"id": "wooden_sword", "name": "Holzschwert", "slot": "weapon", "rarity": "common", "icon": 107, "description": "Ein einfaches Übungsschwert.", "effects": {"attack": 1}},
	{"id": "iron_sword", "name": "Eisenschwert", "slot": "weapon", "rarity": "uncommon", "icon": 104, "description": "Solide Klinge.", "effects": {"attack": 3}},
	{"id": "precision_blade", "name": "Präzisionsklinge", "slot": "weapon", "rarity": "rare", "icon": 106, "description": "Hohe Kampfstärke, aber keine Lernhilfe.", "effects": {"attack": 5}},
	{"id": "hunter_dagger", "name": "Jägerdolch", "slot": "weapon", "rarity": "uncommon", "icon": 103, "description": "Leicht und tückisch.", "effects": {"attack": 2, "critChance": 0.1}},
	{"id": "rune_blade", "name": "Runenklinge", "slot": "weapon", "rarity": "rare", "icon": 105, "description": "Verstärkt die Klassenfähigkeit.", "effects": {"attack": 4, "skillPower": 0.3}},
	{"id": "focus_staff", "name": "Fokusstab", "slot": "weapon", "rarity": "uncommon", "icon": 129, "description": "Erhöht die maximalen Fokus-Punkte deutlich.", "effects": {"attack": 1, "maxFocus": 4}},
	{"id": "leather_cap", "name": "Lederkappe", "slot": "helmet", "rarity": "common", "icon": 0, "iconSheet": "items", "description": "Etwas mehr Lebenspunkte.", "effects": {"maxHp": 6}},
	{"id": "apprentice_helm", "name": "Lehrlingshelm", "slot": "helmet", "rarity": "uncommon", "icon": 1, "iconSheet": "items", "description": "Gut gepolstert: Jeder Treffer schmerzt etwas weniger.", "effects": {"maxHp": 4, "armor": 1}},
	{"id": "healer_circlet", "name": "Heilerreif", "slot": "helmet", "rarity": "uncommon", "icon": 2, "iconSheet": "items", "description": "Nach jedem Sieg kehrt etwas Kraft zurück.", "effects": {"maxHp": 3, "lifeOnWin": 3}},
	{"id": "knight_helm", "name": "Ritterhelm", "slot": "helmet", "rarity": "rare", "icon": 3, "iconSheet": "items", "description": "Viele zusätzliche Lebenspunkte.", "effects": {"maxHp": 14}},
	{"id": "copper_ring", "name": "Kupferring", "slot": "ring", "rarity": "common", "icon": 101, "description": "Ein wenig mehr Fokus.", "effects": {"maxFocus": 1}},
	{"id": "ring_of_beginning", "name": "Ring des Anfangs", "slot": "ring", "rarity": "uncommon", "icon": 101, "description": "Schärft den Blick für Schwachstellen.", "effects": {"maxFocus": 1, "critChance": 0.08}},
	{"id": "wanderer_ring", "name": "Wandererring", "slot": "ring", "rarity": "common", "icon": 101, "description": "Leichte Schritte durch den Tempel.", "effects": {"moveSpeed": 0.12}},
	{"id": "greed_ring", "name": "Ring der Gier", "slot": "ring", "rarity": "uncommon", "icon": 101, "description": "Gold findet seinen Weg zu dir.", "effects": {"goldFind": 0.4}},
	{"id": "library_ring", "name": "Bibliotheksring", "slot": "ring", "rarity": "rare", "icon": 101, "description": "Nach einem Fehler wird das Wort schneller erneut abgefragt.", "effects": {"maxFocus": 1, "repeatGapReduction": 1}},
]


static func has_item(id: Variant) -> bool:
	return ITEMS.any(func(i: Dictionary) -> bool: return i.id == id)


static func get_item(id: String) -> Dictionary:
	for i in ITEMS:
		if i.id == id:
			return i
	push_error("Unbekanntes Item: %s" % id)
	return {}


# ---------- Welt-Themen ----------
const THEMES: Array[Dictionary] = [
	{
		"id": "jungle", "name": "Geheimer Dschungeltempel",
		"enemies": {
			"normal": ["moss_spirit", "bat", "spider", "jungle_rat", "stone_rat", "temple_ghost"],
			"elite": ["temple_guard", "giant_crab"],
			"boss": "temple_cyclops",
		},
		"look": {
			"groundSheet": "town", "ground": [0, 0, 0, 0, 1, 1, 2], "groundTint": "#8fa284",
			"pathSheet": "town", "path": [25], "pathTint": "#ffffff",
			"plantSheet": "town", "trees": [4, 16, 28, 5], "bush": [5, 17], "deco": [29], "plantTint": [0.85, 1.0, 0.8],
			"floorSheet": "dungeon", "floorTint": "#ffffff", "mossTint": "#eef2e0", "wallTint": "#ffffff",
			"background": "#0e1a12", "ambient": "#b4c8b0", "fog": "#1c3022", "farGround": "#16251a",
			"torch": "#ffa040", "particles": "#7fbf4a", "fireflies": "#ffe680",
		},
	},
	# Issue #28: Jede Ebene ist ein eigenes Biom.
	{
		"id": "cave", "name": "Kristallhöhle",
		"enemies": {
			"normal": ["crystal_bat", "cave_spider", "shadow_ghost", "glow_slime"],
			"elite": ["crystal_guard", "rock_crab"],
			"boss": "crystal_colossus",
		},
		"look": {
			"groundSheet": "dungeon", "ground": [48, 48, 42], "groundTint": "#3a3150",
			"pathSheet": "dungeon", "path": [40, 40, 57], "pathTint": "#6e6496",
			"plantSheet": "ski", "trees": [81, 81], "bush": [81], "deco": [95], "plantTint": [0.75, 0.6, 1.0],
			"floorSheet": "dungeon", "floor": [40, 40, 57], "floorTint": "#a89cd0", "mossTint": "#c8b4ff", "wallTint": "#bcb2dc",
			"background": "#100c1a", "ambient": "#b0a6d6", "fog": "#221a36", "farGround": "#15101f",
			"torch": "#b58cff", "particles": "#c8a8ff", "fireflies": "#9ff0ff",
		},
	},
	{
		"id": "ice", "name": "Eistempel",
		"enemies": {
			"normal": ["snowman", "frost_bat", "frost_ghost", "young_yeti"],
			"elite": ["yeti", "ice_guard"],
			"boss": "yeti_king",
		},
		"look": {
			"groundSheet": "ski", "ground": [0, 0, 0, 1, 5], "groundTint": "#c9d6e6",
			"pathSheet": "ski", "path": [0], "pathTint": "#eef4ff",
			"plantSheet": "ski", "trees": [18, 18, 30, 6], "bush": [30, 31], "deco": [69, 81], "plantTint": [0.95, 1.0, 1.05],
			"floorSheet": "ski", "floor": [0, 0, 1], "floorTint": "#e4eefc", "mossTint": "#cfe2ff", "wallTint": "#cddcf5",
			"background": "#121a24", "ambient": "#c6d6ee", "fog": "#283a4e", "farGround": "#1c2836",
			"torch": "#8fd4ff", "particles": "#ffffff", "fireflies": "#cfefff",
		},
	},
]

## Biom einer Ebene (Ebene 1 Dschungel, 2 Kristallhöhle, 3 Eistempel …).
static func theme_for_floor(floor: int) -> Dictionary:
	return THEMES[clampi(floor - 1, 0, THEMES.size() - 1)]


static func get_theme(id: String) -> Dictionary:
	for t in THEMES:
		if t.id == id:
			return t
	return THEMES[0]
