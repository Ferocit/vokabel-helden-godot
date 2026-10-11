class_name Assets
extends RefCounted
## Zugriff auf die Kenney-Tilesheets (16×16 px, je 12×11 Kacheln) und einzelne Frames als AtlasTexture.

const DUNGEON := "res://assets/tiles/dungeon.png"
const TOWN := "res://assets/tiles/town.png"
## Eigene Gegenstandssymbole (tools/item_icons.py), z. B. Helme, die es bei Kenney nicht einzeln gibt.
const ITEMS := "res://assets/tiles/items.png"
const COLS := 12
const TILE := 16

## Kacheln, die im Tileset einen deckenden Sandboden-Hintergrund haben (gedacht für die Draufsicht), hier
## aber freistehend in der Welt stehen: der Kristallaltar (Kopf eines Wandbrunnens).
## Der Hintergrund wird beim Laden entfernt (Issue #8).
const CUTOUT := [32]

static var _cache := {}


static func sheet(path: String) -> Texture2D:
	if path != DUNGEON:
		return load(path)
	if not _cache.has("dungeon_clean"):
		var img := (load(path) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for f: int in CUTOUT:
			cut_background(img, Rect2i((f % COLS) * TILE, (f / COLS) * TILE, TILE, TILE))
		_cache["dungeon_clean"] = ImageTexture.create_from_image(img)
	return _cache["dungeon_clean"]


## Macht in `rect` alle Pixel durchsichtig, die vom Rand aus zusammenhängend die Farbe der linken unteren
## Ecke haben (Flood-Fill) – entfernt so den einfarbigen Hintergrund, ohne gleichfarbige Stellen im Motiv.
static func cut_background(img: Image, rect: Rect2i) -> void:
	var bg := img.get_pixelv(rect.position + Vector2i(0, rect.size.y - 1))
	if bg.a == 0.0:
		return
	var todo: Array[Vector2i] = []
	for x in rect.size.x:
		todo.append(rect.position + Vector2i(x, 0))
		todo.append(rect.position + Vector2i(x, rect.size.y - 1))
	for y in rect.size.y:
		todo.append(rect.position + Vector2i(0, y))
		todo.append(rect.position + Vector2i(rect.size.x - 1, y))
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		if not rect.has_point(p):
			continue
		var c := img.get_pixelv(p)
		if c.a == 0.0 or not c.is_equal_approx(bg):
			continue
		img.set_pixelv(p, Color(0, 0, 0, 0))
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			todo.append(p + d)


## Einzelner 16×16-Frame (Frame-Nummer zeilenweise wie in der Phaser-Version).
static func frame(frame_no: int, path: String = DUNGEON) -> AtlasTexture:
	var key := "%s#%d" % [path, frame_no]
	if _cache.has(key):
		return _cache[key]
	var t := AtlasTexture.new()
	t.atlas = sheet(path)
	t.region = Rect2((frame_no % COLS) * TILE, (frame_no / COLS) * TILE, TILE, TILE)
	t.filter_clip = true
	_cache[key] = t
	return t


## Symbol eines Gegenstands: Kachel aus dem Dungeon-Sheet oder – mit "iconSheet": "items" – aus items.png.
static func item_icon(item: Dictionary) -> Texture2D:
	return frame(int(item.icon), ITEMS if item.get("iconSheet") == "items" else DUNGEON)


## Frame als eigenes Image (für 3D-Texturen, die Wiederholung brauchen).
static func frame_image(frame_no: int, path: String = DUNGEON) -> Image:
	var key := "%s#img%d" % [path, frame_no]
	if _cache.has(key):
		return _cache[key]
	var img := sheet(path).get_image()
	if img.is_compressed():
		img.decompress()
	var sub := img.get_region(Rect2i((frame_no % COLS) * TILE, (frame_no / COLS) * TILE, TILE, TILE))
	_cache[key] = sub
	return sub


static func frame_texture(frame_no: int, path: String = DUNGEON) -> ImageTexture:
	var key := "%s#tex%d" % [path, frame_no]
	if _cache.has(key):
		return _cache[key]
	var t := ImageTexture.create_from_image(frame_image(frame_no, path))
	_cache[key] = t
	return t
