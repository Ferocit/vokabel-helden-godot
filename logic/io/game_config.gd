class_name GameConfig
extends RefCounted
## Balancing-Werte aus config/game.json (einmal geladen, danach zwischengespeichert).

static var _data: Dictionary


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://config/game.json"))
	return _data


static func section(name: String) -> Dictionary:
	return data()[name]
