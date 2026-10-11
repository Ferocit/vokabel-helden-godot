class_name Fx
extends RefCounted
## Zur Laufzeit erzeugte Effekt-Texturen (Pixel-Fackel, Markierungspfeil, Lichtschein, Lichtstrahl)
## und kleine Bausteine für Licht und Partikel.

static var _cache := {}

const FLAMES := [
	["......k.........", ".....kok........", ".....kyok.......", "....kyYyok......", "....koYYok......", "....kryYrk......", ".....krrk......."],
	[".......k........", "......kok.......", ".....koyk.......", "....koyYyk......", "....koYYok......", "....krYyrk......", ".....krrk......."],
	["................", "......kk........", ".....koyk.......", "....kyYYok......", "....koYYyk......", "....kryYrk......", ".....krrk......."],
]
const HANDLE := ["....kmmmmk......", "....kMmmMk......", ".....kwwk.......", ".....kwwk.......", ".....kwWk.......", ".....kwwk.......", ".....kwWk.......", "......kk........", "................"]
const PALETTE := {"k": "#3b2027", "r": "#e43b44", "o": "#f77622", "y": "#feae34", "Y": "#fff2a8", "m": "#8b9bb4", "M": "#5a6988", "w": "#b86f50", "W": "#743f39"}
const MARKER := ["ooooooo", "oyyyyyo", ".oyyyo.", ".oyyyo.", "..oyo..", "..oyo..", "...o..."]


static func _pixels(rows: Array, palette: Dictionary, w: int, h: int, x0: int = 0) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if palette.has(ch):
				img.set_pixel(x + x0, y, Color(palette[ch]))
	return img


## Drei Animationsbilder der Wandfackel (16×16, wie die Kenney-Sprites).
static func torch_frames() -> Array[ImageTexture]:
	if _cache.has("torch"):
		return _cache.torch
	var frames: Array[ImageTexture] = []
	for f in FLAMES:
		frames.append(ImageTexture.create_from_image(_pixels(f + HANDLE, PALETTE, 16, 16, 1)))
	_cache.torch = frames
	return frames


static func marker() -> ImageTexture:
	if not _cache.has("marker"):
		_cache.marker = ImageTexture.create_from_image(_pixels(MARKER, {"o": "#3a2408", "y": "#ffffff"}, 7, 7))
	return _cache.marker


## Weicher, runder Lichtschein (weiß, wird eingefärbt).
static func glow() -> GradientTexture2D:
	if not _cache.has("glow"):
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_cache.glow = t
	return _cache.glow


## Dunkler, weicher Schatten unter Figuren.
static func blob() -> GradientTexture2D:
	if not _cache.has("blob"):
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.04, 0.08, 0.03, 0.55), Color(0.04, 0.08, 0.03, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 32
		t.height = 32
		_cache.blob = t
	return _cache.blob


## Lichtstrahl: in der Mitte hell, zu den Rändern und nach unten weich auslaufend.
static func shaft() -> ImageTexture:
	if not _cache.has("shaft"):
		var img := Image.create(32, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			var fy := float(y) / 127.0
			var va := smoothstep(0.0, 0.2, fy) * (1.0 - fy)
			for x in 32:
				var fx := absf(float(x) / 31.0 - 0.5) * 2.0
				img.set_pixel(x, y, Color(1, 1, 1, (1.0 - fx * fx) * va))
		_cache.shaft = ImageTexture.create_from_image(img)
	return _cache.shaft


## Material für flache, unbeleuchtete Effekte (Leuchten, Strahlen).
static func additive(tex: Texture2D, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


## Flacher Schatten unter einer Figur.
static func shadow_quad(width: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(width, width * 0.55)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = blob()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.01
	return mi


## Pixel-Sprite im Stil der Welt: aufrecht, leicht zur Kamera geneigt, beleuchtet, harte Alphakante.
static func sprite(tex: Texture2D, height_px: float = 16.0, shaded: bool = true) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = 1.0 / height_px if height_px > 0 else 1.0 / 16.0
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = shaded
	s.double_sided = true
	s.centered = true
	s.offset = Vector2(0, tex.get_height() / 2.0) if tex else Vector2.ZERO
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return s


## Licht mit sanftem Flackern (Fackeln, Kristalle).
class Flicker extends OmniLight3D:
	var base_energy := 1.0
	var speed := 9.0
	var amount := 0.18
	var _t := randf() * 100.0

	func _process(delta: float) -> void:
		_t += delta * speed
		light_energy = base_energy * (1.0 + amount * (sin(_t) * 0.6 + sin(_t * 2.3 + 1.7) * 0.4))


## Wechselt Texturen eines Sprite3D im festen Takt (Fackelflamme).
class FrameAnim extends Node:
	var frames: Array = []
	var interval := 0.15
	var _t := 0.0
	var _i := 0

	func _ready() -> void:
		_i = randi() % maxi(1, frames.size())
		interval += randf() * 0.04

	func _process(delta: float) -> void:
		_t += delta
		if _t >= interval and not frames.is_empty():
			_t = 0.0
			_i = (_i + 1) % frames.size()
			(get_parent() as Sprite3D).texture = frames[_i]


## Sanftes Auf und Ab (Gegner, Markierungen).
class Bob extends Node:
	var amplitude := 0.12
	var period := 1.3
	var _base := 0.0
	var _t := 0.0

	func _ready() -> void:
		_base = (get_parent() as Node3D).position.y
		_t = randf() * period

	func _process(delta: float) -> void:
		_t += delta
		(get_parent() as Node3D).position.y = _base + (sin(_t / period * TAU) * 0.5 + 0.5) * amplitude
