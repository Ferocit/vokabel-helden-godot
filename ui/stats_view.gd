class_name StatsView
extends RefCounted
## Lernstatistik pro Vokabel (über alle Abenteuer und Trainings) und Mastery-Durchschnitt eines Sets.


static func average_mastery(unit_id: String) -> float:
	var ctx: GameContext = Ctx
	var unit := ctx.repo.get_unit(unit_id)
	if unit.is_empty() or (unit.vocabulary as Array).is_empty():
		return 0.0
	var sum := 0.0
	for v: Dictionary in unit.vocabulary:
		var s: Variant = ctx.progress.get(Vocab.item_key(unit.id, v.id))
		sum += float(s.mastery) if s is Dictionary else 0.0
	return sum / (unit.vocabulary as Array).size()


static func render(container: Control, unit_id: String) -> void:
	var ctx: GameContext = Ctx
	UI.clear(container)
	var unit := ctx.repo.get_unit(unit_id)
	if unit.is_empty():
		container.add_child(UI.label("Einheit nicht gefunden.", "Dim"))
		return
	var rows: Array = []
	for e: Dictionary in unit.vocabulary:
		rows.append({"entry": e, "stats": ctx.progress.get(Vocab.item_key(unit.id, e.id))})
	var m := func(r: Dictionary) -> float: return float(r.stats.mastery) if r.stats is Dictionary else -1.0
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return m.call(a) < m.call(b))
	var seen := rows.filter(func(r: Dictionary) -> bool: return r.stats is Dictionary and int(r.stats.seen) > 0)
	var avg := 0.0
	for r: Dictionary in seen:
		avg += float(r.stats.mastery)
	avg = avg / rows.size() if rows.size() > 0 else 0.0

	container.add_child(UI.hbox([
		UI.label("%d Vokabeln" % rows.size(), "", 17),
		UI.label("%d schon geübt" % seen.size(), "", 17),
		UI.label("%d noch nie dran" % (rows.size() - seen.size()), "Accent" if rows.size() > seen.size() else "Dim", 17),
		UI.label("Ø Mastery", "", 17),
		UI.mastery_bar(avg),
	], 20))

	var headers := ["Deutsch", "Englisch", "Dran", "Auf Anhieb", "Richtig", "Falsch", "Quote", "Hilfen", "Mastery", "Zuletzt"]
	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	for h: String in headers:
		grid.add_child(UI.label(h, "Accent", 15))
	for r: Dictionary in rows:
		var s: Dictionary = r.stats if r.stats is Dictionary else Vocab.empty_stats()
		var de := UI.label(r.entry.de, "", 16)
		de.custom_minimum_size.x = 200
		de.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var en := UI.label(r.entry.en, "", 16)
		en.custom_minimum_size.x = 200
		en.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(de)
		grid.add_child(en)
		grid.add_child(UI.label(str(s.seen), "", 16))
		var first := UI.label(str(int(s.get("firstTry", 0))), "Good", 16)
		first.tooltip_text = "Ohne Hilfe und ohne vorherigen Fehler richtig – zuletzt %d× in Folge" % int(s.get("firstTryStreak", 0))
		first.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(first)
		grid.add_child(UI.label(str(s.correct), "", 16))
		grid.add_child(UI.label(str(s.wrong), "Bad", 16))
		grid.add_child(UI.label("%d %%" % roundi(Vocab.success_rate(s) * 100.0) if int(s.seen) > 0 else "–", "", 16))
		grid.add_child(UI.label(str(s.hintsUsed), "", 16))
		grid.add_child(UI.mastery_bar(float(s.mastery), 80))
		grid.add_child(UI.label(UI.format_date_time(s.lastSeen), "Dim", 15))
	container.add_child(UI.scroll(grid, 430))
