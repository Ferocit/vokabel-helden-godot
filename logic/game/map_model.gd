class_name MapModel
extends RefCounted
## LevelMap { seed, width, height, tiles: PackedInt32Array (zeilenweise), rooms, startRoomId, bossRoomId,
##            start: Vector2i, objects: Array[MapObject] }
## Room      { id, x, y, w, h }
## MapObject { id, kind: enemy|chest|door|bossDoor|heal, x, y, … }
##   enemy: enemyId, tier · chest: chestType (normal|rare|special) · door: answers · bossDoor: runes

const VOID := 0
const FLOOR := 1

const CHEST_LABELS := {"normal": "Truhe", "rare": "Seltene Truhe", "special": "Besondere Truhe"}


static func tile_at(map: Dictionary, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= int(map.width) or y >= int(map.height):
		return VOID
	return map.tiles[y * int(map.width) + x]


static func is_floor(map: Dictionary, x: int, y: int) -> bool:
	return tile_at(map, x, y) == FLOOR


static func room_contains(room: Dictionary, x: int, y: int) -> bool:
	return x >= room.x and y >= room.y and x < room.x + room.w and y < room.y + room.h


static func room_center(room: Dictionary) -> Vector2i:
	return Vector2i(room.x + room.w / 2, room.y + room.h / 2)


## Objekte, durch die man nicht hindurchlaufen kann, solange sie aktiv sind.
static func is_solid_object(obj: Dictionary) -> bool:
	return obj.kind != "enemy"
