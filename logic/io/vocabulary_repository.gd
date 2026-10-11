class_name VocabularyRepository
extends RefCounted
## Verwaltet Vokabeleinheiten (mitgelieferte Beispiel-Einheit + importierte).

const SAMPLE_UNIT_ID := "sample"
const SAMPLE_PATH := "res://data/units/sample_unit.json"

var _save: SaveService
var _units: Array = []
var _built_in: Dictionary


func _init(save: SaveService) -> void:
	_save = save
	var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE_PATH))
	_built_in = {"id": SAMPLE_UNIT_ID, "title": sample.title, "createdAt": 0, "vocabulary": sample.vocabulary}
	for u: Variant in save.load_units():
		if u is Dictionary and (u as Dictionary).has("vocabulary"):
			_units.append(_normalize(u))


static func _normalize(u: Dictionary) -> Dictionary:
	var vocab: Array = []
	for e: Dictionary in u.vocabulary:
		vocab.append({
			"id": str(e.get("id", "")),
			"de": str(e.get("de", "")),
			"en": str(e.get("en", "")),
			"alternatives": Array(e.get("alternatives", [])),
			"caseSensitive": bool(e.get("caseSensitive", true)),
		})
	return {"id": str(u.id), "title": str(u.get("title", "Set")), "createdAt": int(u.get("createdAt", 0)), "vocabulary": vocab}


func all() -> Array:
	return [_built_in] + _units


func get_unit(id: String) -> Dictionary:
	for u: Dictionary in all():
		if u.id == id:
			return u
	return {}


func is_built_in(id: String) -> bool:
	return id == SAMPLE_UNIT_ID


func new_unit_id() -> String:
	return "unit_%s" % String.num_int64(Vocab.now_ms(), 36)


## Speichert ein Set. Die Beispiel-Einheit kann nicht verändert werden (liefert dann false).
func upsert(unit: Dictionary) -> bool:
	if is_built_in(unit.id):
		return false
	for i in _units.size():
		if _units[i].id == unit.id:
			_units[i] = unit
			_save.save_units(_units)
			return true
	_units.append(unit)
	_save.save_units(_units)
	return true


func remove(id: String) -> void:
	_units = _units.filter(func(u: Dictionary) -> bool: return u.id != id)
	_save.save_units(_units)


func learning_items(unit_ids: Array) -> Array:
	var items: Array = []
	for id: String in unit_ids:
		var unit := get_unit(id)
		if unit.is_empty():
			continue
		for e: Dictionary in unit.vocabulary:
			items.append({"key": Vocab.item_key(unit.id, e.id), "entry": e})
	return items
