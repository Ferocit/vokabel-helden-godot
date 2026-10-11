extends SceneTree
## Aufruf: godot --headless --path . -s res://tests/run_tests.gd [-- filter]
## Führt alle Methoden `test_*` in tests/test_*.gd aus und beendet sich mit Exit-Code 0 (grün) oder 1.


var _done := false
var _errors := ErrorCounter.new()


## Zählt Script-Fehler (z. B. Aufruf auf null), damit ein Test mit Laufzeitfehler nicht grün durchgeht.
class ErrorCounter extends Logger:
	var count := 0
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_SCRIPT:
			_mutex.lock()
			count += 1
			_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


## Erst im ersten Frame starten: dann ist der Baum samt Autoloads bereit und `_ready` läuft beim Einhängen.
func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	OS.add_logger(_errors)
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
		if script == null or not script.can_instantiate():
			# Eine Testdatei mit Parse-Fehler darf nicht stillschweigend fehlen.
			total += 1
			failed += 1
			print("  ✗ %s lässt sich nicht laden (Parse-Fehler, siehe oben)" % f)
			continue
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
			var errors_before := _errors.count
			tc.call(m)
			if _errors.count > errors_before:
				tc.fail("%d Script-Fehler während des Tests (siehe Ausgabe oben)" % (_errors.count - errors_before))
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
