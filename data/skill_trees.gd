class_name SkillTrees
extends RefCounted
## Skillbäume je Klasse: drei Zweige mit je drei Stufen. Fertigkeiten werden dauerhaft mit Tempelsplittern
## gekauft und wirken in jedem Abenteuer dieser Klasse.
## Designregel: Fertigkeiten helfen nie direkt bei Vokabeln (keine Gratis-Hilfen, keine Lösungen,
## keine geringeren Hilfekosten). Sie verbessern Kampf, Bewegung, Vorräte und Beute.
##
## Knoten: { id, name, branch (Index), tier (1–3), maxRank, effect: {Schlüssel: Wert pro Rang}, requires: id oder "" }
## Effekt-Schlüssel (pro Rang addiert):
##   maxHp, attack            – Grundwerte
##   moveSpeed                – Laufgeschwindigkeit in der Erkundung (+Anteil)
##   critChance, critMult     – kritische Treffer
##   defend                   – Verteidigen hält zusätzlich diesen Anteil ab
##   armor                    – jeder gegnerische Treffer macht so viel weniger Schaden (min. 1)
##   skillPower               – Multiplikator der Klassenfähigkeit (+)
##   poisonTurns              – Giftdauer der Giftklinge (+Runden)
##   potionHeal               – Heiltränke heilen mehr
##   lifeOnWin                – HP nach jedem gewonnenen Kampf
##   startPotions, startGold  – Startvorräte jedes Abenteuers
##   goldFind                 – mehr Gold aus Beute (+Anteil)
##   shardBonus               – mehr Tempelsplitter am Ende eines Abenteuers (+Anteil)
## Regel-Effekte (Segnungen/Talente, Issue #20) – belohnen richtiges Erinnern, helfen nie beim Antworten:
##   chainStrike              – jede 3. Kombo-Stufe (3, 6 …) trifft doppelt
##   revenge                  – ein im Abenteuer schon falsches Wort richtig: +Anteil Schaden
##   firstStrike              – der erste Treffer jedes Kampfes ist kritisch
##   critHeal, critFocus      – kritische Treffer heilen HP / geben Fokus
##   poisonStack              – neues Gift addiert sich zum alten, statt es zu ersetzen

const EFFECT_TEXT := {
	"maxHp": "+%d max. HP",
	"attack": "+%d Angriff",
	"moveSpeed": "+%d %% Laufgeschwindigkeit",
	"critChance": "+%d %% Chance auf kritische Treffer",
	"critMult": "+%d %% Schaden kritischer Treffer",
	"defend": "Verteidigen hält %d %% mehr ab",
	"armor": "−%d Schaden pro gegnerischem Treffer",
	"skillPower": "+%d %% Schaden der Klassenfähigkeit",
	"poisonTurns": "Gift wirkt %d Runde(n) länger",
	"potionHeal": "Heiltränke heilen %d HP mehr",
	"lifeOnWin": "+%d HP nach jedem Sieg",
	"startPotions": "+%d Heiltrank zu Beginn",
	"startGold": "+%d Gold zu Beginn",
	"goldFind": "+%d %% Gold aus Beute",
	"shardBonus": "+%d %% Tempelsplitter",
	"chainStrike": "Jede 3. Antwort in Folge (Kombo 3, 6 …) trifft doppelt",
	"revenge": "Früher falsches Wort jetzt richtig: +%d %% Schaden",
	"firstStrike": "Der erste Treffer jedes Kampfes ist kritisch",
	"critHeal": "Kritische Treffer heilen %d HP",
	"critFocus": "Kritische Treffer geben %d Fokus",
	"poisonStack": "Gift stapelt sich",
}
## Diese Werte sind Anteile und werden in Prozent angezeigt.
const PERCENT := ["moveSpeed", "critChance", "critMult", "defend", "skillPower", "goldFind", "shardBonus", "revenge"]

const TREES := {
	"warrior": {
		"branches": ["Bollwerk", "Klinge", "Wanderer"],
		"nodes": [
			{"id": "w_toughness", "name": "Zähigkeit", "branch": 0, "tier": 1, "maxRank": 3, "effect": {"maxHp": 6}, "requires": ""},
			{"id": "w_shieldwall", "name": "Schildwall", "branch": 0, "tier": 2, "maxRank": 2, "effect": {"defend": 0.05}, "requires": "w_toughness"},
			{"id": "w_ironwill", "name": "Eiserner Wille", "branch": 0, "tier": 3, "maxRank": 2, "effect": {"armor": 1}, "requires": "w_shieldwall"},
			{"id": "w_strength", "name": "Kraft", "branch": 1, "tier": 1, "maxRank": 3, "effect": {"attack": 1}, "requires": ""},
			{"id": "w_momentum", "name": "Wucht", "branch": 1, "tier": 2, "maxRank": 2, "effect": {"skillPower": 0.25}, "requires": "w_strength"},
			{"id": "w_slayer", "name": "Bezwinger", "branch": 1, "tier": 3, "maxRank": 2, "effect": {"critChance": 0.07}, "requires": "w_momentum"},
			{"id": "w_stride", "name": "Weiter Schritt", "branch": 2, "tier": 1, "maxRank": 3, "effect": {"moveSpeed": 0.08}, "requires": ""},
			{"id": "w_supplies", "name": "Feldration", "branch": 2, "tier": 2, "maxRank": 2, "effect": {"startPotions": 1}, "requires": "w_stride"},
			{"id": "w_veteran", "name": "Veteran", "branch": 2, "tier": 3, "maxRank": 2, "effect": {"lifeOnWin": 4}, "requires": "w_supplies"},
		],
	},
	"rogue": {
		"branches": ["Schatten", "Gift", "Streuner"],
		"nodes": [
			{"id": "r_precision", "name": "Scharfes Auge", "branch": 0, "tier": 1, "maxRank": 3, "effect": {"critChance": 0.04}, "requires": ""},
			{"id": "r_ambush", "name": "Hinterhalt", "branch": 0, "tier": 2, "maxRank": 2, "effect": {"critMult": 0.2}, "requires": "r_precision"},
			{"id": "r_blades", "name": "Klingentanz", "branch": 0, "tier": 3, "maxRank": 2, "effect": {"attack": 1}, "requires": "r_ambush"},
			{"id": "r_toxin", "name": "Starkes Gift", "branch": 1, "tier": 1, "maxRank": 3, "effect": {"skillPower": 0.15}, "requires": ""},
			{"id": "r_lingering", "name": "Schleichendes Gift", "branch": 1, "tier": 2, "maxRank": 2, "effect": {"poisonTurns": 1}, "requires": "r_toxin"},
			{"id": "r_antidote", "name": "Gegengift", "branch": 1, "tier": 3, "maxRank": 2, "effect": {"potionHeal": 5}, "requires": "r_lingering"},
			{"id": "r_swift", "name": "Leichtfuß", "branch": 2, "tier": 1, "maxRank": 3, "effect": {"moveSpeed": 0.1}, "requires": ""},
			{"id": "r_pockets", "name": "Tiefe Taschen", "branch": 2, "tier": 2, "maxRank": 2, "effect": {"goldFind": 0.25}, "requires": "r_swift"},
			{"id": "r_fence", "name": "Hehlerware", "branch": 2, "tier": 3, "maxRank": 2, "effect": {"shardBonus": 0.15}, "requires": "r_pockets"},
		],
	},
	"mage": {
		"branches": ["Glut", "Arkanschild", "Gelehrter"],
		"nodes": [
			{"id": "m_ember", "name": "Glut", "branch": 0, "tier": 1, "maxRank": 3, "effect": {"skillPower": 0.15}, "requires": ""},
			{"id": "m_kindle", "name": "Entfachen", "branch": 0, "tier": 2, "maxRank": 2, "effect": {"critChance": 0.05}, "requires": "m_ember"},
			{"id": "m_inferno", "name": "Inferno", "branch": 0, "tier": 3, "maxRank": 2, "effect": {"attack": 1}, "requires": "m_kindle"},
			{"id": "m_ward", "name": "Schutzrune", "branch": 1, "tier": 1, "maxRank": 3, "effect": {"maxHp": 4}, "requires": ""},
			{"id": "m_barrier", "name": "Barriere", "branch": 1, "tier": 2, "maxRank": 2, "effect": {"defend": 0.05}, "requires": "m_ward"},
			{"id": "m_mending", "name": "Heilfluss", "branch": 1, "tier": 3, "maxRank": 2, "effect": {"lifeOnWin": 3}, "requires": "m_barrier"},
			{"id": "m_blink", "name": "Gleiten", "branch": 2, "tier": 1, "maxRank": 3, "effect": {"moveSpeed": 0.08}, "requires": ""},
			{"id": "m_alchemy", "name": "Alchemie", "branch": 2, "tier": 2, "maxRank": 2, "effect": {"potionHeal": 4}, "requires": "m_blink"},
			{"id": "m_scholar", "name": "Tempelkunde", "branch": 2, "tier": 3, "maxRank": 2, "effect": {"shardBonus": 0.15}, "requires": "m_alchemy"},
		],
	},
}


static func tree(class_id: String) -> Dictionary:
	return TREES.get(class_id, TREES.warrior)


static func get_node_def(class_id: String, node_id: String) -> Dictionary:
	for n: Dictionary in tree(class_id).nodes:
		if n.id == node_id:
			return n
	return {}


## Lesbarer Effekt für `rank` Ränge, z. B. "+12 max. HP".
static func effect_text(node: Dictionary, rank: int) -> String:
	var parts: Array[String] = []
	for key: String in node.effect:
		var v: float = float(node.effect[key]) * rank
		var template: String = EFFECT_TEXT[key]
		if not template.contains("%d"):
			parts.append(template)  # Regel ohne Zahl
			continue
		parts.append(template % (roundi(v * 100.0) if key in PERCENT else roundi(v)))
	return ", ".join(parts)
