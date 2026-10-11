extends SceneTree
## Aufruf: godot --headless --path . -s res://tests/run_tests.gd [-- filter]
## Führt alle Methoden `test_*` in tests/test_*.gd aus und beendet sich mit Exit-Code 0 (grün) oder 1.


func _initialize() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		filter = args[0]
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()

	var total := 0
	var failed := 0
	var started := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if (m.name as String).begins_with("test_") and not methods.has(m.name):
				methods.append(m.name)
		for m in methods:
			if filter != "" and not ("%s.%s" % [f, m]).contains(filter):
				continue
			var tc: TestCase = script.new()
			tc.current = "%s › %s" % [f.trim_suffix(".gd"), m]
			var t0 := Time.get_ticks_msec()
			tc.call(m)
			total += 1
			var ms := Time.get_ticks_msec() - t0
			if tc.failures.is_empty():
				print("  ✓ %s (%d ms)" % [tc.current, ms])
			else:
				failed += 1
				print("  ✗ %s" % tc.current)
				for msg in tc.failures.slice(0, 8):
					print("      " + msg)
	print("\n%d Tests, %d fehlgeschlagen (%.1f s)" % [total, failed, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failed > 0 or total == 0 else 0)
