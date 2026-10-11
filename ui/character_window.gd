class_name CharacterWindow
extends VBoxContainer
## Charakterfenster mit Inventar (Taste I), angelehnt an Diablo: links die Figur mit ihren drei
## Ausrüstungsplätzen und den Werten, rechts die Tasche als Raster. Ein Klick wählt einen Gegenstand
## (Details und Vergleich mit dem Angelegten), Doppelklick legt an bzw. ab.
## Änderungen wirken sofort und werden gespeichert.

const BAG_COLS := 5
const BAG_ROWS := 4
const SLOT_PX := 64
## Platz für jeden Ausrüstungsslot im Figurenraster (3 × 2): Helm oben, Waffe links, Ring rechts.
const DOLL := {"helmet": Vector2i(1, 0), "weapon": Vector2i(0, 1), "ring": Vector2i(2, 1)}

var modal: UI.Modal
## Ausgewählt: {"from": "bag" | "slot", "id": Gegenstand, "slot": Slot}
var selected := {}


static func open(parent: Node) -> UI.Modal:
	var m := UI.modal(parent, "Charakter & Inventar", 1040)
	var w := CharacterWindow.new()
	w.modal = m
	m.body.add_child(w)
	w.render()
	return m


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k.pressed and not k.echo and k.physical_keycode == KEY_I and modal != null and modal.is_top():
		get_viewport().set_input_as_handled()
		modal.close()


func render() -> void:
	UI.clear(self)
	add_theme_constant_override("separation", 10)
	if not selected.is_empty() and not _still_there():
		selected = {}
	var cols := UI.hbox([_character_column(), _bag_column()], 18)
	add_child(cols)


# ---------- Figur, Plätze, Werte ----------

func _character_column() -> Control:
	var p: Dictionary = Ctx.profile
	var cls := Ctx.hero_class()
	var col := UI.vbox([], 8)
	col.custom_minimum_size.x = 420

	var next := Player.xp_for_next_level(int(p.level), GameConfig.section("player"))
	var xp_bar := Hud.xp_bar(240)
	col.add_child(UI.hbox([UI.label(cls.name, "H3"), UI.spacer(), UI.label("Level %d" % int(p.level), "Accent", 18)]))
	col.add_child(UI.hbox([xp_bar, UI.label("XP %d%s" % [int(p.xp), " / %d" % next if next >= 0 else " (max)"], "Dim", 14)], 10))

	# Figur in der Mitte, Plätze drumherum.
	var doll := GridContainer.new()
	doll.columns = 3
	doll.add_theme_constant_override("h_separation", 18)
	doll.add_theme_constant_override("v_separation", 8)
	var cells := {}
	for slot: String in DOLL:
		cells[DOLL[slot]] = _equip_slot(slot)
	var hero := UI.sprite(int(cls.frame), 128)
	cells[Vector2i(1, 1)] = hero
	for y in 2:
		for x in 3:
			var c: Control = cells.get(Vector2i(x, y), null)
			if c == null:
				c = Control.new()
				c.custom_minimum_size = Vector2(SLOT_PX, SLOT_PX)
			doll.add_child(c)
	var stage := PanelContainer.new()
	stage.theme_type_variation = "Card"
	stage.add_child(CenterContainer.new())
	stage.get_child(0).add_child(doll)
	col.add_child(stage)

	col.add_child(_stats())
	return col


func _equip_slot(slot: String) -> Control:
	var id: Variant = Ctx.profile.equipment.get(slot)
	var item := GameData.get_item(id) if id != null else {}
	var b := _cell(item, selected.get("from") == "slot" and selected.get("slot") == slot)
	b.tooltip_text = "%s: %s" % [GameData.SLOT_LABELS[slot], item.name if not item.is_empty() else "leer"]
	b.pressed.connect(func() -> void:
		selected = {} if item.is_empty() else {"from": "slot", "slot": slot, "id": id}
		Sound.play("select", 0.4)
		render())
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.double_click and not item.is_empty():
			unequip(slot))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := UI.label(GameData.SLOT_LABELS[slot], "Dim", 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return UI.vbox([b, label], 2)


func _stats() -> Control:
	var s := Ctx.stats()
	var fighter := Ctx.combat_player() if Ctx.has_run() else {}
	var rows: Array = [
		["❤", "Lebenspunkte", "%d" % int(s.maxHp)],
		["✦", "Fokus", "%d" % int(s.maxFocus)],
		["⚔", "Angriff", "%d" % int(s.attack)],
	]
	if not fighter.is_empty():
		rows.append(["✸", "Kritische Treffer", "%d %% (×%s)" % [roundi(float(fighter.critChance) * 100.0), String.num(float(fighter.critMultiplier), 1)]])
		rows.append(["🛡", "Verteidigen hält ab", "%d %%" % roundi((1.0 - float(fighter.defendFactor)) * 100.0)])
		if int(fighter.armor) > 0:
			rows.append(["⛨", "Rüstung", "−%d pro Treffer" % int(fighter.armor)])
		if int(fighter.lifeOnWin) > 0:
			rows.append(["✚", "HP nach jedem Sieg", "+%d" % int(fighter.lifeOnWin)])
	var speed := Ctx.move_speed_factor()
	if speed > 1.0:
		rows.append(["👟", "Laufgeschwindigkeit", "+%d %%" % roundi((speed - 1.0) * 100.0)])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	for r: Array in rows:
		grid.add_child(UI.label(r[0], "Accent", 16))
		var name := UI.label(r[1], "", 16)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name)
		grid.add_child(UI.label(r[2], "Bold", 16))
	var box := UI.vbox([UI.label("Werte", "H3"), grid], 4)
	var talents: Array = Ctx.profile.get("talents", [])
	if not talents.is_empty():
		var tflow := HFlowContainer.new()
		tflow.add_theme_constant_override("h_separation", 6)
		tflow.add_theme_constant_override("v_separation", 4)
		var shown := {}
		for id: String in talents:
			if shown.has(id):
				continue
			shown[id] = true
			var t := Talents.get_talent(id)
			var n := Talents.rank(talents, id)
			var chip := PanelContainer.new()
			chip.theme_type_variation = "Card"
			chip.tooltip_text = "%s (je Stufe)" % Talents.text(t)
			chip.add_child(UI.label("%s %s%s" % [t.icon, t.name, " ×%d" % n if n > 1 else ""], "", 14))
			tflow.add_child(chip)
		box.add_child(UI.label("Talente", "H3"))
		box.add_child(tflow)
	var blessings: Array = Ctx.profile.get("blessings", [])
	if not blessings.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 4)
		for id: String in blessings:
			var bl := Blessings.get_blessing(id)
			var chip := PanelContainer.new()
			chip.theme_type_variation = "Card"
			chip.tooltip_text = Blessings.text(bl)
			chip.add_child(UI.label("%s %s" % [bl.icon, bl.name], "", 14))
			flow.add_child(chip)
		for duo: Dictionary in Blessings.active_duos(blessings):
			var chip := PanelContainer.new()
			chip.theme_type_variation = "Card"
			chip.tooltip_text = "Duo-Segnung: %s" % Blessings.text(duo)
			chip.add_child(UI.label("%s %s (Duo)" % [duo.icon, duo.name], "Accent", 14))
			flow.add_child(chip)
		box.add_child(UI.label("Segnungen", "H3"))
		box.add_child(flow)
	return box


# ---------- Tasche ----------

func _bag_column() -> Control:
	var p: Dictionary = Ctx.profile
	var col := UI.vbox([], 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.hbox([UI.label("Tasche", "H3"), UI.spacer(), UI.label("%d / %d" % [(p.bag as Array).size(), BAG_COLS * BAG_ROWS], "Dim", 14)]))
	var grid := GridContainer.new()
	grid.columns = BAG_COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var bag: Array = p.bag
	for i in maxi(BAG_COLS * BAG_ROWS, bag.size()):
		if i >= bag.size():
			grid.add_child(_cell({}, false))
			continue
		var id: String = bag[i]
		var item := GameData.get_item(id)
		var b := _cell(item, selected.get("from") == "bag" and selected.get("id") == id)
		b.tooltip_text = "%s\n%s%s" % [item.name, item.description, EquipmentView.effect_text(item)]
		b.pressed.connect(func() -> void:
			selected = {"from": "bag", "id": id, "slot": item.slot}
			Sound.play("select", 0.4)
			render())
		b.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.double_click:
				equip(id))
		grid.add_child(b)
	col.add_child(grid)
	col.add_child(UI.hbox([
		UI.label("💰 %d Gold" % int(p.gold), "Accent", 18),
		UI.label("🧪 %d Heiltränke" % int(p.potions), "", 18),
		UI.spacer(),
		UI.label("Klick: Details · Doppelklick: an-/ablegen", "Dim", 13),
	], 16))
	col.add_child(_details())
	col.add_child(UI.para("Ausrüstung, Gold und Level gelten nur für dieses Abenteuer. Dauerhaft bleiben %s und deine Fertigkeiten." % Meta.CURRENCY, "Dim", 13))
	return col


## Quadratisches Feld mit Item-Symbol; Rahmen in Raritätsfarbe, ausgewählt golden.
func _cell(item: Dictionary, is_selected: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SLOT_PX, SLOT_PX)
	b.focus_mode = Control.FOCUS_NONE
	var border: Color = UI.GOLD if is_selected else (UI.RARITY.get(item.rarity, UI.DIM) if not item.is_empty() else Color(1, 1, 1, 0.12))
	var bg := Color(0.05, 0.045, 0.04, 0.9) if not item.is_empty() else Color(0, 0, 0, 0.35)
	var sb := UiTheme.box(bg, border, 3 if is_selected else 2, 6, Vector4(6, 6, 6, 6))
	var hover := UiTheme.box(bg.lightened(0.12), UI.GOLD if not item.is_empty() else border, 2, 6, Vector4(6, 6, 6, 6))
	for state: String in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	if item.is_empty():
		b.disabled = true
		return b
	var icon := TextureRect.new()
	icon.texture = Assets.item_icon(item)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	return b


## Details zum ausgewählten Gegenstand mit Vergleich und Aktionen.
func _details() -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.custom_minimum_size.y = 150
	if selected.is_empty():
		card.add_child(UI.para("Wähle einen Gegenstand in der Tasche oder an der Figur, um ihn genauer anzusehen.", "Dim", 15))
		return card
	var item := GameData.get_item(selected.id)
	var name := UI.label(item.name, "Bold", 20)
	name.add_theme_color_override("font_color", UI.RARITY.get(item.rarity, UI.TEXT))
	var info := UI.vbox([
		UI.hbox([name, UI.label("%s · %s" % [GameData.SLOT_LABELS[item.slot], GameData.RARITY_LABELS[item.rarity]], "Dim", 14)]),
		UI.para(item.description + EquipmentView.effect_text(item), "", 15),
	], 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var actions := UI.vbox([], 6)
	if selected.from == "bag":
		var worn: Variant = Ctx.profile.equipment.get(item.slot)
		if worn != null:
			info.add_child(UI.para(compare_text(item, GameData.get_item(worn)), "Accent", 14))
		actions.add_child(UI.button("Anlegen", equip.bind(item.id), "SmallButton"))
		var price := int(GameData.SELL_PRICE[item.rarity])
		actions.add_child(UI.button("Verkaufen +%d 💰" % price, sell.bind(item.id), "SmallButton"))
	else:
		info.add_child(UI.label("Angelegt", "Good", 14))
		actions.add_child(UI.button("Ablegen", unequip.bind(item.slot), "SmallButton"))
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.add_child(UI.hbox([UI.icon(Assets.item_icon(item), 56), info, actions], 12))
	return card


## „Gegenüber Eisenschwert: Angriff ▲2, Krit ▼10 %“ – Unterschied der Effekte zum angelegten Gegenstand.
static func compare_text(item: Dictionary, worn: Dictionary) -> String:
	var keys: Array = []
	for k: String in (item.effects as Dictionary).keys() + (worn.effects as Dictionary).keys():
		if k not in keys:
			keys.append(k)
	var parts: Array[String] = []
	for k: String in keys:
		var d := float(item.effects.get(k, 0)) - float(worn.effects.get(k, 0))
		if is_zero_approx(d):
			continue
		var pct: bool = k in SkillTrees.PERCENT
		var amount := "%d %%" % roundi(absf(d) * 100.0) if pct else str(roundi(absf(d)))
		parts.append("%s %s%s" % [STAT_NAMES.get(k, k), "▲" if d > 0 else "▼", amount])
	if parts.is_empty():
		return "Gleich stark wie %s." % worn.name
	return "Gegenüber %s: %s" % [worn.name, ", ".join(parts)]


const STAT_NAMES := {
	"attack": "Angriff", "maxHp": "HP", "maxFocus": "FP", "critChance": "Krit", "critMult": "Krit-Schaden",
	"armor": "Rüstung", "skillPower": "Fähigkeit", "moveSpeed": "Tempo", "goldFind": "Gold", "lifeOnWin": "HP nach Sieg",
	"repeatGapReduction": "Wiederholung", "defend": "Verteidigen", "potionHeal": "Heiltrank", "poisonTurns": "Gift",
}


# ---------- Aktionen ----------

func equip(id: String) -> void:
	Ctx.set_profile(Player.equip(Ctx.profile, id))
	Sound.play("select")
	var item := GameData.get_item(id)
	selected = {"from": "slot", "slot": item.slot, "id": id}
	EquipmentView._after_change()
	render()


func unequip(slot: String) -> void:
	var id: Variant = Ctx.profile.equipment.get(slot)
	Ctx.set_profile(Player.unequip(Ctx.profile, slot))
	Sound.play("select", 0.5)
	selected = {"from": "bag", "id": id, "slot": slot} if id != null else {}
	EquipmentView._after_change()
	render()


func sell(id: String) -> void:
	var item := GameData.get_item(id)
	var do_sell := func() -> void:
		Ctx.set_profile(Player.sell_item(Ctx.profile, id))
		Sound.play("coins")
		selected = {}
		EquipmentView._after_change()
		render()
	if item.rarity == "rare":
		UI.confirm(modal.get_parent(), "„%s“ ist selten. Wirklich für %d Gold verkaufen?" % [item.name, int(GameData.SELL_PRICE[item.rarity])], do_sell, "Verkaufen")
	else:
		do_sell.call()


func _still_there() -> bool:
	if selected.from == "bag":
		return (Ctx.profile.bag as Array).has(selected.id)
	return Ctx.profile.equipment.get(selected.slot) == selected.id
