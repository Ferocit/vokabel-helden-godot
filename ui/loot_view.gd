class_name LootView
extends RefCounted
## Beute übersichtlich als Liste: eine Zeile pro Fund mit Symbol, Name, Details und Menge.
## Eintrag: { icon: int (Kachel im Dungeon-Sheet), Texture2D oder String (Emoji), title, detail, amount, color, highlight }

const POTION_ICON := 115


## Einträge für eine gewürfelte Beute (LootService.roll_loot) plus Erfahrung.
static func entries(loot: Dictionary, xp: int = 0) -> Array:
	var list: Array = []
	if xp > 0:
		list.append({"icon": "⭐", "title": "Erfahrung", "amount": "+%d XP" % xp})
	if int(loot.get("gold", 0)) > 0:
		list.append({"icon": "💰", "title": "Gold", "detail": "Jetzt %d Gold" % int(Ctx.profile.gold), "amount": "+%d" % int(loot.gold), "color": UI.ACCENT})
	if int(loot.get("potions", 0)) > 0:
		list.append({"icon": POTION_ICON, "title": "Heiltrank", "detail": "Heilt im Kampf %d HP" % int(GameConfig.section("combat").potionHeal), "amount": "+%d" % int(loot.potions)})
	if loot.get("itemId") != null:
		list.append(item_entry(GameData.get_item(loot.itemId)))
	return list


static func item_entry(item: Dictionary) -> Dictionary:
	var fx := EquipmentView.effect_text(item).trim_prefix(" (").trim_suffix(")")
	return {
		"icon": Assets.item_icon(item),
		"title": item.name,
		"detail": "%s · %s%s" % [GameData.SLOT_LABELS[item.slot], GameData.RARITY_LABELS[item.rarity], " – " + fx if fx != "" else ""],
		"amount": "Neu!",
		"color": UI.RARITY.get(item.rarity, UI.TEXT),
		"highlight": item.rarity != "common",
	}


static func list(items: Array, compact: bool = false) -> VBoxContainer:
	var box := UI.vbox([], 4 if compact else 6)
	for e: Dictionary in items:
		box.add_child(row(e, compact))
	return box


static func row(e: Dictionary, compact: bool = false) -> PanelContainer:
	var size := 28 if compact else 36
	var card := PanelContainer.new()
	card.theme_type_variation = "CardSelected" if e.get("highlight", false) else "Card"
	var icon: Control
	if e.icon is int:
		icon = UI.sprite(e.icon, size)
	elif e.icon is Texture2D:
		icon = UI.icon(e.icon, size)
	else:
		var l := UI.label(e.icon, "", size - 8)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(size, size)
		icon = l
	var title := UI.label(e.title, "Bold", 16 if compact else 19)
	title.add_theme_color_override("font_color", e.get("color", UI.TEXT))
	var text := UI.vbox([title], 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if str(e.get("detail", "")) != "":
		var d := UI.label(e.detail, "Dim", 13 if compact else 14)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(d)
	var amount := UI.label(str(e.get("amount", "")), "Accent", 17 if compact else 20)
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.add_child(UI.hbox([icon, text, amount], 12))
	return card
