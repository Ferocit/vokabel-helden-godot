class_name SaveService
extends RefCounted
## Lokale Speicherung (ohne Account und Cloud). Jeder Schlüssel ist eine JSON-Datei mit Versionsfeld:
## { "version": 1, "data": … } – gleiches Format wie die LocalStorage-Einträge der Browser-Version.

const SAVE_VERSION := 1
const KEYS := {
	"player": "vq.player",
	"progress": "vq.vocabulary_progress",
	"settings": "vq.settings",
	"units": "vq.units",
	"run": "vq.run",
}

var store: KeyValueStore


func _init(kv: KeyValueStore) -> void:
	store = kv


func _read(key: String) -> Variant:
	var raw := store.get_item(key)
	if raw == "":
		return null
	var env: Variant = JSON.parse_string(raw)
	if not env is Dictionary or not (env as Dictionary).has("version") or int(env.version) != SAVE_VERSION:
		return null
	return env.get("data")


func _write(key: String, data: Variant) -> void:
	store.set_item(key, JSON.stringify({"version": SAVE_VERSION, "data": data}))


func load_player() -> Variant:
	return _read(KEYS.player)


func save_player(profile: Dictionary) -> void:
	_write(KEYS.player, profile)


func load_progress() -> Dictionary:
	var d: Variant = _read(KEYS.progress)
	return d if d is Dictionary else {}


func save_progress(progress: Dictionary) -> void:
	_write(KEYS.progress, progress)


func load_settings() -> Dictionary:
	var s := {"sound": true, "volume": 0.8, "fullscreen": false, "seenIntro": false, "selectedUnits": [], "depthOfField": false}
	var d: Variant = _read(KEYS.settings)
	if d is Dictionary:
		s.merge(d, true)
	return s


func save_settings(settings: Dictionary) -> void:
	_write(KEYS.settings, settings)


func load_units() -> Array:
	var d: Variant = _read(KEYS.units)
	return d if d is Array else []


func save_units(units: Array) -> void:
	_write(KEYS.units, units)


func load_run() -> Variant:
	var d: Variant = _read(KEYS.run)
	return d if d is Dictionary else null


func save_run(run: Dictionary) -> void:
	_write(KEYS.run, run)


func clear_run() -> void:
	store.remove_item(KEYS.run)
