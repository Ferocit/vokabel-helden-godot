class_name ArchiveView
extends RefCounted
## Tempelarchiv (Issue #23): Freischaltungen mit Tempelsplittern kaufen, Aussehen und Startwaffe wählen,
## Sammlung ansehen (Bestiarium, gefundene Gegenstände, gemeisterte Wörter).


static func render(body: VBoxContainer, tab: String = "unlock") -> void:
	UI.clear(body)
	var p: Dictionary = Ctx.profile
	var tabs := UI.hbox([], 8)
	for t: Array in [["unlock", "🔓 Freischalten"], ["look", "🎨 Aussehen & Start"], ["collection", "📖 Sammlung"]]:
		var b := UI.button(t[1], render.bind(body, t[0]), "SmallButton")
		b.name = "Tab_" + t[0]
		b.disabled = t[0] == tab
		tabs.add_child(b)
	tabs.add_child(UI.spacer())
	tabs.add_child(UI.label("%s %d" % [Meta.ICON, int(p.shards)], "Accent", 20))
	body.add_child(tabs)
	var content := UI.vbox([], 6)
	match tab:
		"unlock":
			_render_unlocks(content, body)
		"look":
			_render_look(content, body)
		_:
			_render_collection(content)
	body.add_child(UI.scroll(content, 470))


static func _render_unlocks(box: VBoxContainer, body: VBoxContainer) -> void:
	box.add_child(UI.para("Neue Inhalte für alle künftigen Abenteuer: Sie tauchen danach in Beute, beim Händler oder in der Auswahl auf.", "Dim", 15))
	for kind: String in ["item", "blessing", "talent", "startWeapon"]:
		box.add_child(UI.label(Unlocks.KIND_LABEL[kind], "H3"))
		for u: Dictionary in Unlocks.ALL:
			if u.kind != kind:
				continue
			var owned := Unlocks.owned(Ctx.profile, u.id)
			var detail := ""
			match kind:
				"item", "startWeapon":
					detail = GameData.get_item(u.ref).description + EquipmentView.effect_text(GameData.get_item(u.ref))
				"blessing":
					detail = Blessings.text(Blessings.get_blessing(u.ref))
				"talent":
					detail = Talents.text(Talents.get_talent(u.ref))
			var btn: Control
			if owned:
				btn = UI.label("✔ frei", "Good", 16)
			else:
				var b := UI.button("Freischalten −%d %s" % [int(u.cost), Meta.ICON], func() -> void:
					Ctx.set_profile(Unlocks.buy(Ctx.profile, u.id))
					Ctx.save_persistent()
					Sound.play("levelup")
					render(body, "unlock"), "SmallButton")
				b.name = "Buy_" + u.id
				b.disabled = not Unlocks.can_buy(Ctx.profile, u.id)
				btn = b
			var name := UI.label(Unlocks.title(u), "Bold", 16)
			name.custom_minimum_size.x = 210
			var d := UI.para(detail, "Dim", 14)
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_child(UI.hbox([name, d, btn], 10))


static func _render_look(box: VBoxContainer, body: VBoxContainer) -> void:
	var p: Dictionary = Ctx.profile
	box.add_child(UI.para("Aussehen ist reine Optik. Die Startwaffe ersetzt das Holzschwert zu Beginn jedes Abenteuers.", "Dim", 15))
	for cls: Dictionary in GameData.HERO_CLASSES:
		box.add_child(UI.label(cls.name, "H3"))
		var row := UI.hbox([], 10)
		var frames: Array = [[int(cls.frame), "Standard", ""]]
		for u: Dictionary in Unlocks.ALL:
			if u.kind == "skin" and u.get("class") == cls.id:
				frames.append([int(u.ref), u.name, u.id])
		var current := Unlocks.hero_frame(p, cls)
		for f: Array in frames:
			var owned: bool = f[2] == "" or Unlocks.owned(p, f[2])
			var label: String = f[1]
			if not owned:
				label += " (−%d %s)" % [int(Unlocks.get_unlock(f[2]).cost), Meta.ICON]
			var b := UI.button(label, func() -> void:
				if not owned:
					if not Unlocks.can_buy(Ctx.profile, f[2]):
						return
					Ctx.set_profile(Unlocks.buy(Ctx.profile, f[2]))
				Ctx.profile.skins[cls.id] = f[0]
				Ctx.save_persistent()
				Sound.play("select")
				render(body, "look"), "SmallButton")
			b.name = "Skin_%d" % int(f[0])
			b.disabled = int(f[0]) == current or (not owned and not Unlocks.can_buy(p, f[2]))
			row.add_child(UI.vbox([UI.sprite(int(f[0]), 56), b], 2))
		box.add_child(row)
		var weapons := UI.hbox([UI.label("Startwaffe:", "", 16)], 8)
		var chosen: Variant = (p.startWeapons as Dictionary).get(cls.id)
		for w: Array in [["wooden_sword", ""]] + Unlocks.ALL.filter(func(u: Dictionary) -> bool: return u.kind == "startWeapon").map(func(u: Dictionary) -> Array: return [u.ref, u.id]):
			var free: bool = w[1] == "" or Unlocks.owned(p, w[1])
			var b := UI.button(GameData.get_item(w[0]).name, func() -> void:
				Ctx.profile.startWeapons[cls.id] = w[0]
				Ctx.save_persistent()
				render(body, "look"), "SmallButton")
			b.disabled = not free or (chosen == w[0]) or (chosen == null and w[0] == "wooden_sword")
			b.tooltip_text = "" if free else "Erst unter „Freischalten“ kaufen"
			weapons.add_child(b)
		box.add_child(weapons)


static func _render_collection(box: VBoxContainer) -> void:
	var p: Dictionary = Ctx.profile
	var seen: Dictionary = p.get("bestiary", {})
	box.add_child(UI.label("Bestiarium – %d von %d Gegnern besiegt" % [seen.size(), GameData.ENEMIES.size()], "H3"))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	for e: Dictionary in GameData.ENEMIES:
		var known := seen.has(e.id)
		var icon := UI.sprite(int(e.frame), 48)
		if not known:
			icon.modulate = Color(0, 0, 0, 0.75)
		var cell := UI.vbox([icon, UI.label(e.name if known else "???", "" if known else "Dim", 14), UI.label("%d×" % int(seen.get(e.id, 0)) if known else "", "Dim", 13)], 2)
		cell.custom_minimum_size.x = 110
		grid.add_child(cell)
	box.add_child(grid)
	var found: Dictionary = p.get("found", {})
	box.add_child(UI.label("Gegenstände – %d von %d gefunden" % [found.size(), GameData.ITEMS.size()], "H3"))
	var items := HFlowContainer.new()
	items.add_theme_constant_override("h_separation", 8)
	for it: Dictionary in GameData.ITEMS:
		var t := TextureRect.new()
		t.texture = Assets.item_icon(it)
		t.custom_minimum_size = Vector2(40, 40)
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.tooltip_text = it.name if found.has(it.id) else "???"
		if not found.has(it.id):
			t.modulate = Color(0, 0, 0, 0.75)
		items.add_child(t)
	box.add_child(items)
	var mastered := 0
	var total := 0
	for unit: Dictionary in Ctx.repo.all():
		for e: Dictionary in unit.vocabulary:
			total += 1
			var s: Variant = Ctx.progress.get(Vocab.item_key(unit.id, e.id))
			if s is Dictionary and float(s.mastery) >= 0.9:
				mastered += 1
	box.add_child(UI.label("Wörter – %d von %d sehr sicher" % [mastered, total], "H3"))
	var stars := 0
	for u: String in p.get("setStars", {}):
		stars += 1
	box.add_child(UI.label("⭐ Set-Meister: %d Sets" % stars, "", 16))
