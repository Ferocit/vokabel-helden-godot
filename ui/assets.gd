class_name Assets
extends RefCounted
## Zugriff auf die Kenney-Tilesheets (16×16 px, je 12×11 Kacheln) und einzelne Frames als AtlasTexture.

const DUNGEON := "res://assets/tiles/dungeon.png"
const TOWN := "res://assets/tiles/town.png"
const COLS := 12
const TILE := 16

static var _cache := {}


static func sheet(path: String) -> Texture2D:
	return load(path)


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
