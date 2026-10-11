class_name KeyValueStore
extends RefCounted
## Einfacher Schlüssel-Wert-Speicher. Die Basisklasse hält alles im Speicher (für Tests);
## FileStore schreibt je Schlüssel eine Datei nach user://save/.

var _data := {}


func get_item(key: String) -> String:
	return _data.get(key, "")


func set_item(key: String, value: String) -> void:
	_data[key] = value


func remove_item(key: String) -> void:
	_data.erase(key)


class FileStore extends KeyValueStore:
	var _dir: String

	func _init(dir: String = "user://save") -> void:
		_dir = dir
		DirAccess.make_dir_recursive_absolute(_dir)

	func _path(key: String) -> String:
		return "%s/%s.json" % [_dir, key]

	func get_item(key: String) -> String:
		if not FileAccess.file_exists(_path(key)):
			return ""
		return FileAccess.get_file_as_string(_path(key))

	func set_item(key: String, value: String) -> void:
		# Erst in eine Temp-Datei schreiben, dann umbenennen – ein Absturz zerstört so keinen Spielstand.
		var tmp := _path(key) + ".tmp"
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f == null:
			push_error("Speichern fehlgeschlagen: %s" % key)
			return
		f.store_string(value)
		f.close()
		DirAccess.rename_absolute(tmp, _path(key))

	func remove_item(key: String) -> void:
		if FileAccess.file_exists(_path(key)):
			DirAccess.remove_absolute(_path(key))
