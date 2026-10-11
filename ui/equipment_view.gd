class_name EquipmentView
extends RefCounted
## Ausrüstung (3 Slots), Tasche mit Verkaufen und Händler für Heiltränke (Issue #15).
## Änderungen wirken sofort und werden gespeichert.


static func render(container: Control) -> void:
	var rerender := func() -> void: render(container)
	UI.clear(container)
	var p: Dictionary = Ctx.profile
	var stats := Ctx.stats()
	var next := Player.xp_for_next_level(int(p.level), GameConfig.section("player"))

	container.add_child(UI.hbox([
		UI.label("Level %d" % int(p.level), "Accent", 18),
		UI.label("XP %d%s" % [int(p.xp), " / %d" % next if next >= 0 else " (max)"], "", 18),
		UI.label("HP %d" % int(stats.maxHp), "", 18),
		UI.label("FP %d" % int(stats.maxFocus), "", 18),
		UI.label("Angriff %d" % int(stats.attack), "", 18),
		UI.label("💰 %d Gold" % int(p.gold), "", 18),
		UI.label("🧪 %d Heiltränke" % int(p.potions), "", 18),
	], 22))
	container.add_child(UI.para("Ausrüstung, Gold und Level gelten nur für dieses Abenteuer. Dauerhaft bleiben %s und deine Fertigkeiten." % Meta.CURRENCY, "Dim", 14))
	container.add_child(UI.gap(4))

	var left := UI.vbox([UI.label("Angelegt", "H3")])
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for slot: String in GameData.SLOTS:
		var id: Variant = p.equipment.get(slot)
		if id == null:
			var empty := PanelContainer.new()
			empty.theme_type_variation = "Card"
			empty.add_child(UI.label("%s: leer" % GameData.SLOT_LABELS[slot], "Dim", 16))
			left.add_child(empty)
			continue
		var off := UI.button("Ablegen", func() -> void:
			Ctx.set_profile(Player.unequip(Ctx.profile, slot))
			_after_change()
			rerender.call(), "SmallButton")
		left.add_child(_item_card(GameData.get_item(id), off))

	var right := UI.vbox([UI.label("Tasche", "H3")])
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bag := UI.vbox()
	if (p.bag as Array).is_empty():
		bag.add_child(UI.para("Noch keine weiteren Gegenstände. Öffne Truhen und besiege Gegner!"))
	for id: String in p.bag:
		var item := GameData.get_item(id)
		var price := int(GameData.SELL_PRICE[item.rarity])
		var equip_btn := UI.button("Anlegen", func() -> void:
			Ctx.set_profile(Player.equip(Ctx.profile, id))
			_after_change()
			rerender.call(), "SmallButton")
		var do_sell := func() -> void:
			Ctx.set_profile(Player.sell_item(Ctx.profile, id))
			Sound.play("coins")
			_after_change()
			rerender.call()
		var sell := UI.button("Verkaufen +%d 💰" % price, func() -> void:
			if item.rarity == "rare":
				UI.confirm(container, "„%s“ ist selten. Wirklich für %d Gold verkaufen?" % [item.name, price], do_sell, "Verkaufen")
			else:
				do_sell.call(), "SmallButton")
		sell.tooltip_text = "Beim Händler verkaufen"
		bag.add_child(_item_card(item, UI.vbox([equip_btn, sell], 4)))
	right.add_child(UI.scroll(bag, 250))
	right.add_child(UI.gap(6))
	right.add_child(UI.label("Händler", "H3"))
	right.add_child(_merchant(rerender))

	var cols := UI.hbox([left, right], 24)
	container.add_child(cols)


static func _item_card(item: Dictionary, action: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var name := UI.label(item.name, "Bold", 18)
	name.add_theme_color_override("font_color", UI.RARITY.get(item.rarity, UI.TEXT))
	var meta := UI.label("%s · %s" % [GameData.SLOT_LABELS[item.slot], GameData.RARITY_LABELS[item.rarity]], "Dim", 13)
	var desc := UI.para(item.description + effect_text(item), "Dim", 15)
	var info := UI.vbox([UI.hbox([name, meta]), desc], 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UI.hbox([UI.sprite(int(item.icon), 40), info])
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
