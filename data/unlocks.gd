class_name Unlocks
extends RefCounted
## Dauerhafte Freischaltungen mit Tempelsplittern (Issue #23): Statt nur Werte zu verbessern, kommen neue Inhalte
## in die Pools – seltene Gegenstände, Regel-Segnungen, Regel-Talente –, dazu Aussehen und Startwaffen.
## Gekauftes steht in profile.unlocks (Liste von IDs). Inhalte, die hier nicht vorkommen, sind immer verfügbar.
## Ein leeres Profil (Tests, Werkzeuge) gilt als „alles frei“.

const ALL: Array[Dictionary] = [
	# Gegenstände für Beute und Händler
	{"id": "u_rune_blade", "kind": "item", "ref": "rune_blade", "cost": 20},
	{"id": "u_precision_blade", "kind": "item", "ref": "precision_blade", "cost": 20},
	{"id": "u_knight_helm", "kind": "item", "ref": "knight_helm", "cost": 15},
	{"id": "u_library_ring", "kind": "item", "ref": "library_ring", "cost": 15},
	{"id": "u_healer_circlet", "kind": "item", "ref": "healer_circlet", "cost": 10},
	# Regel-Segnungen
	{"id": "u_b_revenge", "kind": "blessing", "ref": "b_revenge", "cost": 20},
	{"id": "u_b_hunter", "kind": "blessing", "ref": "b_hunter", "cost": 20},
	{"id": "u_b_vampire", "kind": "blessing", "ref": "b_vampire", "cost": 20},
	{"id": "u_b_venom", "kind": "blessing", "ref": "b_venom", "cost": 15},
	{"id": "u_b_spark", "kind": "blessing", "ref": "b_spark", "cost": 15},
	{"id": "u_b_chain", "kind": "blessing", "ref": "b_chain", "cost": 40},
	# Regel-Talente
	{"id": "u_t_ambush", "kind": "talent", "ref": "t_ambush", "cost": 15},
	{"id": "u_t_thirst", "kind": "talent", "ref": "t_thirst", "cost": 15},
	{"id": "u_t_clarity", "kind": "talent", "ref": "t_clarity", "cost": 15},
	# Startwaffen (ersetzen das Holzschwert)
	{"id": "u_start_dagger", "kind": "startWeapon", "ref": "hunter_dagger", "cost": 35},
	{"id": "u_start_staff", "kind": "startWeapon", "ref": "focus_staff", "cost": 35},
	{"id": "u_start_iron", "kind": "startWeapon", "ref": "iron_sword", "cost": 45},
	# Aussehen (nur Optik): Sprite-Nummer im Dungeon-Tileset
	{"id": "u_skin_knight", "kind": "skin", "ref": 97, "class": "warrior", "name": "Visierritter", "cost": 8},
	{"id": "u_skin_viking", "kind": "skin", "ref": 87, "class": "warrior", "name": "Nordmann", "cost": 8},
	{"id": "u_skin_bandit", "kind": "skin", "ref": 88, "class": "rogue", "name": "Straßenkind", "cost": 8},
	{"id": "u_skin_scout", "kind": "skin", "ref": 98, "class": "rogue", "name": "Späher", "cost": 8},
	{"id": "u_skin_sorceress", "kind": "skin", "ref": 99, "class": "mage", "name": "Zauberin", "cost": 8},
	{"id": "u_skin_monk", "kind": "skin", "ref": 86, "class": "mage", "name": "Mönch", "cost": 8},
]

const KIND_LABEL := {"item": "Gegenstand", "blessing": "Segnung", "talent": "Talent", "startWeapon": "Startwaffe", "skin": "Aussehen"}


static func get_unlock(id: String) -> Dictionary:
	for u in ALL:
		if u.id == id:
			return u
	return {}


static func _for(kind: String, ref: Variant) -> Dictionary:
	for u in ALL:
		if u.kind == kind and u.ref == ref:
			return u
	return {}


static func owned(profile: Dictionary, id: String) -> bool:
	return (profile.get("unlocks", []) as Array).has(id)


## Darf dieser Inhalt im Pool auftauchen?
static func available(profile: Dictionary, kind: String, ref: Variant) -> bool:
	if profile.is_empty():
		return true
	var u := _for(kind, ref)
	return u.is_empty() or owned(profile, u.id)


static func can_buy(profile: Dictionary, id: String) -> bool:
	var u := get_unlock(id)
	return not u.is_empty() and not owned(profile, id) and int(profile.get("shards", 0)) >= int(u.cost)


static func buy(profile: Dictionary, id: String) -> Dictionary:
	if not can_buy(profile, id):
		return profile
	var next := profile.duplicate(true)
	next.shards = int(next.shards) - int(get_unlock(id).cost)
	if not next.get("unlocks") is Array:
		next.unlocks = []
	(next.unlocks as Array).append(id)
	return next


## Alle IDs (für Werkzeuge und den Simulator: „alles frei“).
static func all_ids() -> Array:
	return ALL.map(func(u: Dictionary) -> String: return u.id)


## Name eines Eintrags für die Anzeige.
static func title(u: Dictionary) -> String:
	match u.kind:
		"item", "startWeapon":
			return GameData.get_item(u.ref).name
		"blessing":
			return Blessings.get_blessing(u.ref).name
		"talent":
			return Talents.get_talent(u.ref).name
	return String(u.get("name", u.id))


## Gewähltes Aussehen der Klasse (Sprite-Nummer), sonst das Standard-Sprite.
static func hero_frame(profile: Dictionary, cls: Dictionary) -> int:
	var skin: Variant = (profile.get("skins", {}) as Dictionary).get(cls.id)
	if skin != null:
		var u := _for("skin", int(skin))
		if not u.is_empty() and owned(profile, u.id):
			return int(skin)
	return int(cls.frame)


## Gewählte Startwaffe der Klasse (falls freigeschaltet), sonst das Holzschwert.
static func start_weapon(profile: Dictionary) -> String:
	var w: Variant = (profile.get("startWeapons", {}) as Dictionary).get(profile.get("heroClass", "warrior"))
	if w != null:
		var u := _for("startWeapon", String(w))
		if not u.is_empty() and owned(profile, u.id):
			return String(w)
	return "wooden_sword"
