extends SceneTree
## Balancing-Simulator auf der Kommandozeile (siehe logic/sim/balance_sim.gd).
##
##   godot --headless --path . -s res://tools/sim.gd -- [schlüssel=wert …]
##   start.bat sim [schlüssel=wert …]      ./start.sh sim [schlüssel=wert …]
##
## Schlüssel (Listen mit Komma = alle Kombinationen):
##   runs=30                Abenteuer je Kombination
##   class=warrior,rogue    Klassen
##   learner=average        fixed | beginner | average | strong
##   accuracy=0.8           nur für learner=fixed
##   heat=0,3               Tempelstufen
##   skills=none,full       Skillbaum leer oder voll
##   words=0                0 = Beispielset, sonst ein künstliches Set mit so vielen Wörtern
##   hints=1 shop=1 talents=1 blessings=1   Bot-Verhalten an (1) / aus (0)
##   floors=1               so viele Ebenen spielt der Bot höchstens (steigt nur mit 2+ Leben ab)
##   campaign=0             >0: so viele Läufe hintereinander mit Meta-Fortschritt (je Klasse/Lerner)
##   seed=1


func _init() -> void:
	var args := {"runs": "30", "class": "warrior", "learner": "average", "accuracy": "0.8", "heat": "0", "skills": "none",
		"words": "0", "hints": "1", "shop": "1", "talents": "1", "blessings": "1", "campaign": "0", "seed": "1", "floors": "1"}
	# start.bat reicht die Argumente über SIM_ARGS weiter, weil cmd.exe bei „=“ und „,“ trennt.
	var user_args: Array = Array(OS.get_cmdline_user_args())
	var raw := OS.get_environment("SIM_ARGS")
	if raw != "":
		user_args = Array(raw.split(" ", false))
	for a: String in user_args:
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var vocab: Array = []
	if int(args.words) > 0:
		for i in int(args.words):
			vocab.append(Vocab.entry("w%d" % i, "de%d" % i, "en%d" % i))
	var base := {
		"seed": int(args.seed), "accuracy": float(args.accuracy), "vocabulary": vocab, "floors": int(args.floors),
		"useHints": args.hints == "1", "useShop": args.shop == "1", "useTalents": args.talents == "1", "useBlessings": args.blessings == "1",
	}
	if int(args.campaign) > 0:
		_campaign(args, base)
	else:
		_batch(args, base)
	quit()


func _batch(args: Dictionary, base: Dictionary) -> void:
	var rows: Array = []
	for cls: String in args["class"].split(","):
		for learner: String in args.learner.split(","):
			for heat: String in args.heat.split(","):
				for skills: String in args.skills.split(","):
					var o := base.duplicate()
					o.heroClass = cls
					o.learner = learner
					o.heat = int(heat)
					o.skills = "full" if skills == "full" else {}
					var s := BalanceSim.batch(o, int(args.runs))
					rows.append([cls, learner, int(heat), skills, "%d %%" % roundi(s.winRate * 100.0), s.floorsCleared, s.defeats, s.shards, s.level,
						s.questions, s.words, s.perMinute, s.minutes, s.hints, s.talents, s.blessings, s.maxCombo, "%d %% / %d %%" % [roundi(s.setBonus * 100.0), roundi(s.setBonusGolden * 100.0)], s.knowledgeGain,
						"%.2f / %.2f" % [s.defendKnowledge, s.otherKnowledge]])
	print(BalanceSim.table(["Klasse", "Lerner", "Stufe", "Skills", "Sieg", "Ø Ebenen", "Ø Niederl.", "Ø 🔷", "Ø Level", "Abfragen",
		"Wörter", "Abfr./min", "Minuten", "Hilfen", "Talente", "Segnungen", "Ø max. Kombo", "Set-Meister / golden", "Wissen +", "Wissen Vert./sonst"], rows))


func _campaign(args: Dictionary, base: Dictionary) -> void:
	for cls: String in args["class"].split(","):
		for learner: String in args.learner.split(","):
			var o := base.duplicate()
			o.heroClass = cls
			o.learner = learner
			var rows: Array = []
			for r: Dictionary in BalanceSim.campaign(o, int(args.campaign)):
				rows.append([r.run, "✓" if r.victory else "✗", r.defeats, r.shards, r.invested, r.level, r.questions, r.perMinute, r.minutes, r.knowledgeGain])
			print("\n### Kampagne: %s, %s\n" % [cls, learner])
			print(BalanceSim.table(["Lauf", "Sieg", "Niederl.", "🔷", "investiert", "Level", "Abfragen", "Abfr./min", "Minuten", "Wissen +"], rows))
