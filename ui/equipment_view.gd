class_name EquipmentView
extends RefCounted
## Bausteine rund um Ausrüstung: Gegenstandskarte, Effekttext, Heiltrank-Händler.
## Die Übersicht mit Tasche und Ausrüstung ist das Charakterfenster (CharacterWindow, Taste I).


static func _item_card(item: Dictionary, action: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var name := UI.label(item.name, "Bold", 18)
	name.add_theme_color_override("font_color", UI.RARITY.get(item.rarity, UI.TEXT))
	var meta := UI.label("%s · %s" % [GameData.SLOT_LABELS[item.slot], GameData.RARITY_LABELS[item.rarity]], "Dim", 13)
	var desc := UI.para(item.description + effect_text(item), "Dim", 15)
	var info := UI.vbox([UI.hbox([name, meta]), desc], 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UI.hbox([UI.icon(Assets.item_icon(item), 40), info])
	if action:
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(action)
	card.add_child(row)
	return card


static func effect_text(item: Dictionary) -> String:
	var fx: Dictionary = item.effects
	var parts: Array[String] = []
	if fx.has("attack"):
		parts.append("Angriff +%d" % int(fx.attack))
	if fx.has("maxHp"):
		parts.append("HP +%d" % int(fx.maxHp))
	if fx.has("maxFocus"):
		parts.append("FP +%d" % int(fx.maxFocus))
	for key: String in fx:
		if SkillTrees.EFFECT_TEXT.has(key) and key not in ["attack", "maxHp"]:
			parts.append(SkillTrees.effect_text({"effect": {key: fx[key]}}, 1))
	return " (%s)" % ", ".join(parts) if not parts.is_empty() else ""


static func _merchant(rerender: Callable) -> PanelContainer:
	var p: Dictionary = Ctx.profile
	var buy := UI.button("Kaufen −%d 💰" % GameData.POTION_PRICE, func() -> void:
		Ctx.set_profile(Player.buy_potion(Ctx.profile))
		Sound.play("coins")
		_after_change()
		rerender.call(), "SmallButton")
	buy.disabled = not Player.can_buy_potion(p)
	var info := UI.vbox([
		UI.label("Heiltrank", "Bold", 18),
		UI.para("Heilt im Kampf %d HP. Du hast %d/%d." % [int(GameConfig.section("combat").potionHeal), int(p.potions), GameData.MAX_POTIONS], "Dim", 15),
	], 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.add_child(UI.hbox([UI.sprite(115, 40), info, buy]))
	return card


static func _after_change() -> void:
	Ctx.clamp_run_stats()
	if Ctx.has_run():
		(Ctx.run.learning as LearningSession).scheduler.set_options({"repeatGapReduction": Ctx.stats().repeatGapReduction})
	Ctx.autosave()
