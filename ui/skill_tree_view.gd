class_name SkillTreeView
extends RefCounted
## Fertigkeiten: Klassenauswahl (mit Freischalten), Skillbaum der gewählten Klasse in drei Zweigen
## und drei Stufen. Käufe sind dauerhaft und werden sofort gespeichert.


static func render(container: Control, class_id: String = "") -> void:
	if class_id == "":
		class_id = Ctx.profile.heroClass
	var rerender := func(cid: String = class_id) -> void: render(container, cid)
	UI.clear(container)
	var p: Dictionary = Ctx.profile

	# Kopfzeile: Splitter und Klassen-Reiter.
	var tabs := UI.hbox([], 8)
	for c: Dictionary in GameData.HERO_CLASSES:
		var unlocked := Meta.is_class_unlocked(p, c.id)
		var b := UI.button(("" if unlocked else "🔒 ") + c.name, rerender.bind(c.id), "SmallButton")
		b.toggle_mode = true
		b.button_pressed = c.id == class_id
		tabs.add_child(b)
	var shards := UI.label("%s %d %s" % [Meta.ICON, int(p.shards), Meta.CURRENCY], "Accent", 20)
	container.add_child(UI.hbox([tabs, UI.spacer(), shards]))
	container.add_child(UI.gap(4))

	var cls := GameData.get_class_def(class_id)
	if not Meta.is_class_unlocked(p, class_id):
		container.add_child(_locked_panel(cls, rerender))
		return

	container.add_child(UI.para("Fertigkeiten wirken in jedem Abenteuer mit %s. Sie verbessern Kampf, Bewegung und Vorräte – beim Vokabellernen hilft dir nur dein Kopf. Investiert: %d %s" % [cls.name, Meta.invested(p, class_id), Meta.ICON], "Dim", 15))
	var tree := SkillTrees.tree(class_id)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.add_child(Control.new())
	for tier in [1, 2, 3]:
		var h := UI.label("Stufe %d" % tier, "Dim", 15)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(h)
	for b in (tree.branches as Array).size():
		var branch := UI.label(tree.branches[b], "H3")
		branch.custom_minimum_size.x = 150
		branch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(branch)
		for tier in [1, 2, 3]:
			var node: Dictionary = {}
			for n: Dictionary in tree.nodes:
				if int(n.branch) == b and int(n.tier) == tier:
					node = n
			grid.add_child(_node_card(class_id, node, rerender) if not node.is_empty() else Control.new())
	container.add_child(grid)


static func _node_card(class_id: String, node: Dictionary, rerender: Callable) -> PanelContainer:
	var p: Dictionary = Ctx.profile
	var r := Meta.rank(p, class_id, node.id)
	var maxed := r >= int(node.maxRank)
	var check := Meta.can_learn(p, class_id, node.id)
	var card := PanelContainer.new()
	card.theme_type_variation = "CardSelected" if r > 0 else "Card"
	card.custom_minimum_size = Vector2(270, 112)
	var title := UI.hbox([UI.label(node.name, "Bold", 18), UI.spacer(), UI.label("%d/%d" % [r, int(node.maxRank)], "Accent" if r > 0 else "Dim", 16)])
	var now := UI.para("Jetzt: " + SkillTrees.effect_text(node, r) if r > 0 else "Pro Rang: " + SkillTrees.effect_text(node, 1), "" if r > 0 else "Dim", 14)
	var box := UI.vbox([title, now], 4)
	if maxed:
		box.add_child(UI.label("✔ Gemeistert", "Good", 15))
	else:
		var btn := UI.button("Lernen  %d %s" % [int(check.cost), Meta.ICON], func() -> void:
			Ctx.set_profile(Meta.learn(Ctx.profile, class_id, node.id))
			Ctx.save_persistent()
			Sound.play("levelup")
			rerender.call(), "SmallButton")
		btn.disabled = not check.ok
		btn.tooltip_text = check.reason
		var row := UI.hbox([btn])
		if not check.ok and check.reason != "":
			row.add_child(UI.label(check.reason, "Dim", 13))
		box.add_child(row)
	card.add_child(box)
	return card


static func _locked_panel(cls: Dictionary, rerender: Callable) -> PanelContainer:
	var p: Dictionary = Ctx.profile
	var cost := Meta.unlock_cost(cls.id)
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var info := UI.vbox([
		UI.label("%s – %s" % [cls.name, cls.tagline], "H2"),
		UI.para(cls.description, "", 16),
		UI.para("%s: %s" % [cls.passiveName, cls.passiveDescription], "Dim", 15),
	])
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn := UI.button("🔓 Freischalten  %d %s" % [cost, Meta.ICON], func() -> void:
		Ctx.set_profile(Meta.unlock_class(Ctx.profile, cls.id))
		Ctx.save_persistent()
		Sound.play("victory")
		rerender.call(cls.id))
	btn.disabled = not Meta.can_unlock_class(p, cls.id)
	if btn.disabled:
		btn.tooltip_text = "Dir fehlen noch %d %s." % [cost - int(p.shards), Meta.CURRENCY]
	info.add_child(UI.hbox([btn]))
	card.add_child(UI.hbox([UI.sprite(int(cls.frame), 96), info], 16))
	return card
