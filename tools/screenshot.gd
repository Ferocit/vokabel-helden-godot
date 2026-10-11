extends Node
## Screenshot-Hilfe: lädt eine Szene, ruft optional Methoden auf ihr auf, wartet und speichert ein PNG.
## Aufruf (unter Linux z. B. mit xvfb-run):
##   godot --path . --rendering-driver opengl3 res://tools/screenshot.tscn -- \
##     scene=res://scenes/title.tscn out=screenshots/title.png [call=open_unit_manager] [frames=30]

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	# shards=N setzt Tempelsplitter (Spielstand nur im Arbeitsspeicher), z. B. für den Skillbaum.
	if args.has("shards"):
		Ctx.setup(KeyValueStore.new())
		Ctx.profile.shards = int(args.shards)
		Ctx.settings.seenIntro = true
		if args.has("heat"):
			Ctx.profile.records.heatUnlocked = int(args.heat)
			Ctx.settings.heat = int(args.heat)
	# run=1 startet ein Abenteuer mit dem Beispiel-Set (Spielstand nur im Arbeitsspeicher).
	if args.has("run"):
		Ctx.setup(KeyValueStore.new())
		Ctx.profile.unlockedClasses = ["warrior", "rogue", "mage"] if args.has("class") else ["warrior"]
		Ctx.profile.heroClass = args.get("class", "warrior")
		Ctx.start_run(["sample"], "jungle", int(args.get("seed", "12345")))
		# answers=N simuliert N Abfragen (jede dritte falsch, jede fünfte mit Hilfe).
		for i in int(args.get("answers", "0")):
			var item: Dictionary = (Ctx.run.learning as LearningSession).next_word("normal")
			var outcome := "wrongCorrected" if i % 3 == 2 else "correct"
			Ctx.submit_answer(item, Vocab.result(outcome, 1 if i % 5 == 4 else 0))
		# end=1 beendet das Abenteuer als Sieg (Belohnung für die Auswertung).
		if args.has("end"):
			for o: Dictionary in Ctx.run.map.objects:
				if o.kind in ["chest", "door"]:
					Ctx.run.opened[o.id] = true
			Ctx.end_run(true)
		if args.has("at"):
			var at: PackedStringArray = String(args.at).split(",")
			Ctx.run.player = Vector2(float(at[0]), float(at[1]))
		# near=door|bossDoor|… stellt den Helden neben das erste Objekt dieser Art (sideDoor: Tür im Ost-West-Gang).
		if args.has("near"):
			for o: Dictionary in Ctx.run.map.objects:
				var side := LevelBuilder.door_faces_side(Ctx.run.map, int(o.x), int(o.y))
				if o.kind == args.near or (args.near == "sideDoor" and o.kind in ["door", "bossDoor"] and side):
					for d: Vector2i in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
						if MapModel.is_floor(Ctx.run.map, int(o.x) + d.x, int(o.y) + d.y):
							Ctx.run.player = Vector2(o.x + d.x + 0.5, o.y + d.y + 0.5)
							break
					break
	# weapon=<Gegenstand> rüstet den Helden mit dieser Waffe aus.
	if args.has("weapon") and Ctx.has_run():
		Ctx.profile.equipment.weapon = args.weapon
	# train=<Set-ID> öffnet mit scene=res://scenes/training.tscn das Training für dieses Set.
	if args.has("train"):
		TrainingScreen.unit_id = args.train
	# challenge=1 startet das Abenteuer als Zeit-Challenge.
	if args.has("challenge") and Ctx.has_run():
		Ctx.run.timeChallenge = true
		Ctx.run.timeLimit = RunScaling.time_limit_for(27)
		Ctx.run.timeLeft = float(args.challenge) if float(args.challenge) > 1.0 else float(Ctx.run.timeLimit)
	var scene: PackedScene = load(args.get("scene", "res://scenes/title.tscn"))
	var node := scene.instantiate()
	if args.has("victory"):
		node.set("victory", true)
	# enemy=normal|elite|boss wählt für die Kampfszene einen Gegner dieser Stufe.
	if args.has("enemy"):
		for o: Dictionary in Ctx.run.map.objects:
			if o.kind == "enemy" and o.tier == args.enemy:
				node.set("object_id", o.id)
				break
	get_tree().root.add_child.call_deferred(node)
	await get_tree().process_frame
	await get_tree().process_frame
	# delay=Sekunden: vor den Aufrufen warten (z. B. bis das Kampfmenü bereit ist).
	if args.has("delay"):
		await get_tree().create_timer(float(args.delay)).timeout
	for m: String in String(args.get("call", "")).split(",", false):
		var parts := m.split("|")
		if parts.size() > 1:
			# Argumente mit @ am Anfang sind Dateipfade, deren Inhalt übergeben wird.
			var call_args := Array(parts.slice(1)).map(func(x: String) -> Variant:
				if x.begins_with("@"):
					return FileAccess.get_file_as_string(x.substr(1))
				return int(x) if x.is_valid_int() else x)
			node.callv(parts[0], call_args)
		else:
			node.call(m)
		for i in 5:
			await get_tree().process_frame
	if args.has("report"):
		Reporter.open_report()
	for i in int(args.get("frames", "30")):
		await get_tree().process_frame
	var out: String = args.get("out", "screenshots/shot.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(out.get_base_dir()))
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://").path_join(out))
	print("Screenshot: ", out)
	get_tree().quit()
