class_name LevelBuilder
extends RefCounted
## Baut aus einer LevelMap die HD-2D-Welt in 3D: Pixel-Art-Kacheln (Kenney Tiny Dungeon + Tiny Town)
## als Boden, Tempelmauern als Blöcke, Urwald und Deko als aufrechte, leicht zur Kamera geneigte Sprites.
## Statische Teile werden pro 8×8-Chunk zu wenigen Meshes zusammengefasst (wenige Draw Calls,
## gute Lichtverteilung). Spielobjekte (Gegner, Truhen, Türen, Altar) sind einzelne Sprite3D-Knoten.
## Koordinaten: Kachel (x, y) ↔ Welt (x … x+1, 0, y … y+1); 1 Einheit = 1 Kachel = 16 px.

const MARGIN := 9
const CHUNK := 8
const WALL_H := 2.0
## Neigung aller aufrechten Sprites zur Kamera hin (gegen die Verkürzung durch den Kamerawinkel).
const TILT := deg_to_rad(-20.0)

const TD := {
	"floor": [48, 48, 48, 48, 48, 48, 48, 48, 42], "wall": [40, 40, 40, 57, 59, 58, 28], "wall_plain": 40,
	"banner": 29, "skull": 41, "door": 45, "door_open": 9, "chest": 89, "chest_rare": 90, "chest_special": 92,
	"altar": 32, "pillar_mid": 18, "pillar_base": 30, "pots": [54, 55, 56, 43, 44],
}
const TT := {"grass": [0, 0, 0, 0, 1, 1, 2], "dirt": 25, "trees": [4, 16, 28, 5], "bush": [5, 17], "mushrooms": 29}
const SHEET_PX := Vector2(192.0, 176.0)

var map: Dictionary
var rng: Callable
var root: Node3D
var objects_root: Node3D
## Objekt-ID → Node3D (für Aktualisierung nach Öffnen/Besiegen).
var views := {}
## Nicht begehbare Deko auf Bodenkacheln (Vector2i → true).
var solid_deco := {}
var bounds: Rect2
var torches := 0

var _is_gone: Callable
var _wall_tiles := {}
var _occupied := {}
var _rooms_at := {}
var _surfaces := {}  # "cx,cy|material" → SurfaceTool
var _materials := {}


static func build(level: Dictionary, is_gone: Callable = func(_o: Dictionary) -> bool: return false) -> LevelBuilder:
	var b := LevelBuilder.new()
	b.map = level
	b._is_gone = is_gone
	b._build()
	return b


# ---------- Hilfen ----------

func _floor(x: int, y: int) -> bool:
	return MapModel.is_floor(map, x, y)


func _room_of(x: int, y: int) -> Variant:
	var key := Vector2i(x, y)
	if _rooms_at.has(key):
		return _rooms_at[key]
	return null


func _room_floor(x: int, y: int) -> bool:
	return _floor(x, y) and _room_of(x, y) != null


## Chebyshev-Abstand zum nächsten Boden (bis 3).
func _dist(x: int, y: int) -> int:
	for d in 3:
		for dy in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if _floor(x + dx, y + dy):
					return d
	return 3


func _pick(arr: Array) -> Variant:
	return Rng.pick(rng, arr)


static func uv_rect(frame_no: int) -> Rect2:
	# Halber Texel Abstand zum Rand verhindert Ausfransen an Nachbarkacheln.
	var px := Vector2((frame_no % 12) * 16 + 0.02, (frame_no / 12) * 16 + 0.02)
	return Rect2(px / SHEET_PX, Vector2(15.96, 15.96) / SHEET_PX)


func _material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = Assets.sheet(Assets.TOWN if key.begins_with("town") else Assets.DUNGEON)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.92
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if key.ends_with("sprite"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = m
	return m


func _st(x: float, z: float, key: String) -> SurfaceTool:
	var c := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
	var k := "%d,%d|%s" % [c.x, c.y, key]
	if not _surfaces.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[k] = st
	return _surfaces[k]


func _vert(st: SurfaceTool, p: Vector3, uv: Vector2, n: Vector3, c: Color) -> void:
	st.set_normal(n)
	st.set_color(c)
	st.set_uv(uv)
	st.add_vertex(p)


## Rechteck aus vier Ecken (oben links, oben rechts, unten rechts, unten links), im Uhrzeigersinn von vorn.
func _quad(st: SurfaceTool, tl: Vector3, tr: Vector3, br: Vector3, bl: Vector3, uv: Rect2, n: Vector3, c: Color) -> void:
	var u0 := uv.position
	var u1 := uv.end
	_vert(st, tl, u0, n, c)
	_vert(st, tr, Vector2(u1.x, u0.y), n, c)
	_vert(st, br, u1, n, c)
	_vert(st, tl, u0, n, c)
	_vert(st, br, u1, n, c)
	_vert(st, bl, Vector2(u0.x, u1.y), n, c)


func _floor_tile(x: int, z: int, frame_no: int, key: String, c: Color = Color.WHITE) -> void:
	_quad(_st(x, z, key), Vector3(x, 0, z), Vector3(x + 1, 0, z), Vector3(x + 1, 0, z + 1), Vector3(x, 0, z + 1), uv_rect(frame_no), Vector3.UP, c)


## Aufrechtes Sprite-Rechteck, Fußpunkt (cx, bz), leicht zur Kamera geneigt.
func _upright(cx: float, bz: float, w: float, h: float, frame_no: int, key: String, c: Color = Color.WHITE, flip := false, base_y := 0.0) -> void:
	var up := Vector3(0, cos(-TILT), sin(TILT)) * h
	var b0 := Vector3(cx - w / 2, base_y, bz)
	var b1 := Vector3(cx + w / 2, base_y, bz)
	var uv := uv_rect(frame_no)
	if flip:
		uv = Rect2(Vector2(uv.end.x, uv.position.y), Vector2(-uv.size.x, uv.size.y))
	var n := Vector3(0, -sin(TILT), cos(TILT))
	_quad(_st(cx, bz, key), b0 + up, b1 + up, b1, b0, uv, n, c)


# ---------- Aufbau ----------

func _build() -> void:
	rng = Rng.create((int(map.seed) ^ 0x5bd1e995) & Rng.MASK)
	root = Node3D.new()
	root.name = "Level"
	objects_root = Node3D.new()
	objects_root.name = "Objects"
	for room: Dictionary in map.rooms:
		for y in range(room.y, room.y + room.h):
			for x in range(room.x, room.x + room.w):
				_rooms_at[Vector2i(x, y)] = room
	for obj: Dictionary in map.objects:
		_occupied[Vector2i(obj.x, obj.y)] = true
	var w := int(map.width)
	var h := int(map.height)
	bounds = Rect2(-MARGIN, -MARGIN, w + MARGIN * 2, h + MARGIN * 2)

	_build_ground_and_walls(w, h)
	_build_forest(w, h)
	for room: Dictionary in map.rooms:
		_decorate_room(room)
	_commit_meshes()
	_add_far_ground()
	root.add_child(objects_root)
	for obj: Dictionary in map.objects:
		_create_view(obj)


func _build_ground_and_walls(w: int, h: int) -> void:
	for j in range(-MARGIN, h + MARGIN):
		for i in range(-MARGIN, w + MARGIN):
			if _room_floor(i, j):
				# Vereinzelt bemooste Platten.
				_floor_tile(i, j, _pick(TD.floor), "dungeon", Color("#eef2e0") if rng.call() < 0.15 else Color.WHITE)
				continue
			if _floor(i, j):
				_floor_tile(i, j, TT.dirt, "town")
				continue
			_floor_tile(i, j, _pick(TT.grass), "town", Color("#8fa284"))
			# Rückwand eines Tempelraums: Mauerblock direkt über dem Raum.
			if _room_floor(i, j + 1):
				_wall_tiles[Vector2i(i, j)] = true
	# Mauerblöcke: Vorderseite zwei Kacheln hoch, Deckplatte, Seitenflächen an den Enden.
	for key: Vector2i in _wall_tiles:
		var i := key.x
		var j := key.y
		var room: Dictionary = _room_of(i, j + 1)
		var torch := _is_torch_column(room, i)
		var lower: int = TD.wall_plain if torch else (_pick([TD.banner, TD.skull]) if rng.call() < 0.12 else _pick(TD.wall))
		var upper: int = TD.wall_plain if torch else _pick(TD.wall)
		var z := float(j + 1)
		var st := _st(i, j, "dungeon")
		_quad(st, Vector3(i, 1, z), Vector3(i + 1, 1, z), Vector3(i + 1, 0, z), Vector3(i, 0, z), uv_rect(lower), Vector3.BACK, Color.WHITE)
		_quad(st, Vector3(i, 2, z), Vector3(i + 1, 2, z), Vector3(i + 1, 1, z), Vector3(i, 1, z), uv_rect(upper), Vector3.BACK, Color("#c4c8bc"))
		_quad(st, Vector3(i, WALL_H, j), Vector3(i + 1, WALL_H, j), Vector3(i + 1, WALL_H, z), Vector3(i, WALL_H, z), uv_rect(TD.wall_plain), Vector3.UP, Color("#6d7368"))
		var side := uv_rect(TD.wall_plain)
		var shade := Color("#9aa094")
		for y0 in [0.0, 1.0]:
			if not _wall_tiles.has(Vector2i(i - 1, j)):
				_quad(st, Vector3(i, y0 + 1, j), Vector3(i, y0 + 1, z), Vector3(i, y0, z), Vector3(i, y0, j), side, Vector3.LEFT, shade)
			if not _wall_tiles.has(Vector2i(i + 1, j)):
				_quad(st, Vector3(i + 1, y0 + 1, z), Vector3(i + 1, y0 + 1, j), Vector3(i + 1, y0, j), Vector3(i + 1, y0, z), side, Vector3.RIGHT, shade)


static func _is_torch_column(room: Dictionary, x: int) -> bool:
	return x > room.x and x < room.x + room.w - 1 and (x - room.x - 1) % 3 == 0


func _tint(shade: float) -> Color:
	return Color(shade * 0.85, shade, shade * 0.8)


func _build_forest(w: int, h: int) -> void:
	for j in range(-MARGIN, h + MARGIN):
		for i in range(-MARGIN, w + MARGIN):
			if _floor(i, j) or _wall_tiles.has(Vector2i(i, j)):
				continue
			var d := _dist(i, j)
			var beside_wall := _wall_tiles.has(Vector2i(i - 1, j)) or _wall_tiles.has(Vector2i(i + 1, j)) or _wall_tiles.has(Vector2i(i, j + 1))
			# Südlich (vor) einem Weg verdecken hohe Bäume die Sicht – dort nur niedrige Büsche.
			var in_front := _floor(i, j - 1) or _floor(i - 1, j - 1) or _floor(i + 1, j - 1)
			if d == 1:
				if in_front:
					_tree(i, j, _pick(TT.bush), 0.1, 0.62 + rng.call() * 0.12, false)
				else:
					var frame: int = _pick(TT.trees) if rng.call() < 0.55 else _pick(TT.bush)
					_tree(i, j, frame, 0.0 if beside_wall else 0.15, 1.0 if beside_wall else 0.95 + rng.call() * 0.15, false)
			else:
				var count := 2 if d >= 3 else 1
				var near_front := in_front or _floor(i, j - 2)
				for k in count:
					var s: float = 1.0 if beside_wall else 1.0 + rng.call() * 0.45
					if near_front:
						s = 0.8
					_tree(i, j, _pick(TT.trees), 0.0 if beside_wall else 0.35, s, d >= 3)
				if rng.call() < 0.06:
					_tree(i, j, TT.mushrooms, 0.3, 0.7, false)


func _tree(i: int, j: int, frame_no: int, jitter: float, scale: float, dark: bool) -> void:
	var x: float = i + 0.5 + (rng.call() - 0.5) * jitter * 2.0
	var z: float = j + 1.0 + (rng.call() - 0.5) * jitter - 0.15
	var shade: float = 0.4 + rng.call() * 0.15 if dark else 0.55 + rng.call() * 0.25
	_upright(x, z, scale, scale, frame_no, "town_sprite", _tint(shade), rng.call() < 0.5)


func _decorate_room(room: Dictionary) -> void:
	var near_corridor := func(x: int, y: int) -> bool:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if _floor(x + dx, y + dy) and _room_of(x + dx, y + dy) == null:
					return true
		return false
	var free := func(x: int, y: int) -> bool:
		return not _occupied.has(Vector2i(x, y)) and not near_corridor.call(x, y) and not (map.start.x == x and map.start.y == y)
	var top: int = room.y

	# Säulen in den hinteren Ecken vor der Mauer.
	for x: int in [room.x, room.x + room.w - 1]:
		if not free.call(x, top) or not _wall_tiles.has(Vector2i(x, top - 1)) or rng.call() < 0.25:
			continue
		_upright(x + 0.5, top + 0.75, 1.0, 1.0, TD.pillar_base, "dungeon_sprite")
		_upright(x + 0.5, top + 0.75 + sin(TILT) * 0.94, 1.0, 1.0, TD.pillar_mid, "dungeon_sprite", Color.WHITE, false, cos(TILT) * 0.94)
		_mark_solid(x, top)

	# Fackeln an der Rückwand.
	for x in range(room.x, room.x + room.w):
		if _is_torch_column(room, x) and _wall_tiles.has(Vector2i(x, top - 1)):
			_add_torch(Vector3(x + 0.5, 0.75, top + 0.04))

	# Krüge und Vasen am Rand.
	for n in 2:
		var x: int = room.x + 1 + floori(rng.call() * maxi(1, room.w - 2))
		var y: int = room.y if rng.call() < 0.5 else room.y + room.h - 1
		if not free.call(x, y) or rng.call() < 0.4:
			continue
		_upright(x + 0.5, y + 0.7, 0.9, 0.9, _pick(TD.pots), "dungeon_sprite")
		var sh := Fx.shadow_quad(0.8)
		sh.position = Vector3(x + 0.5, 0.01, y + 0.62)
		root.add_child(sh)
		_mark_solid(x, y)

	# Licht fällt durch das Blätterdach.
	if rng.call() < 0.7:
		var cx: float = room.x + room.w * (0.3 + rng.call() * 0.4)
		var cz: float = room.y + room.h / 2.0
		_add_light_shaft(Vector3(cx, 0, cz), room.h * 1.1)


func _mark_solid(x: int, y: int) -> void:
	solid_deco[Vector2i(x, y)] = true
	_occupied[Vector2i(x, y)] = true


func _add_torch(pos: Vector3) -> void:
	torches += 1
	var frames := Fx.torch_frames()
	var s := Fx.sprite(frames[0], 16.0, false)
	s.position = pos
	s.modulate = Color(1.6, 1.4, 1.2)  # leicht überhell → Glow
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var anim := Fx.FrameAnim.new()
	anim.frames = frames
	anim.interval = 0.14
	s.add_child(anim)
	root.add_child(s)
	var light := Fx.Flicker.new()
	light.light_color = Color("#ffa040")
	light.base_energy = 2.4
	light.omni_range = 5.0
	light.omni_attenuation = 1.3
	light.position = pos + Vector3(0, 0.75, 0.45)
	root.add_child(light)


func _add_light_shaft(pos: Vector3, height: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.2 + rng.call() * 0.8, height * 1.6)
	mi.mesh = q
	mi.material_override = Fx.additive(Fx.shaft(), Color(1.0, 0.95, 0.7, 0.13))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0.6, height * 0.6, 0)
	mi.rotation = Vector3(deg_to_rad(-35), 0, deg_to_rad(-24))
	root.add_child(mi)


func _commit_meshes() -> void:
	var static_root := Node3D.new()
	static_root.name = "Static"
	for k: String in _surfaces:
		var st: SurfaceTool = _surfaces[k]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var key := k.split("|")[1]
		mi.material_override = _material(key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key.ends_with("sprite") or key == "dungeon" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		static_root.add_child(mi)
	root.add_child(static_root)
	_surfaces.clear()


## Dunkler Boden jenseits des Rands, damit die Welt nie im Leeren endet.
func _add_far_ground() -> void:
	var mi := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(bounds.size.x + 80, bounds.size.y + 80)
	mi.mesh = p
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#16251a")
	m.roughness = 1.0
	mi.material_override = m
	mi.position = Vector3(bounds.get_center().x, -0.02, bounds.get_center().y)
	root.add_child(mi)


# ---------- Spielobjekte ----------

func is_gone(obj: Dictionary) -> bool:
	return _is_gone.call(obj)


func refresh_object(obj: Dictionary) -> void:
	if views.has(obj.id):
		(views[obj.id] as Node).queue_free()
		views.erase(obj.id)
	_create_view(obj)


## Entfernt eine Objektansicht mit kurzem Ausblenden (besiegte Gegner).
func fade_out(obj_id: String) -> void:
	if not views.has(obj_id):
		return
	var node: Node3D = views[obj_id]
	views.erase(obj_id)
	var tw := node.create_tween()
	for s in node.find_children("*", "Sprite3D", true, false):
		tw.parallel().tween_property(s, "modulate:a", 0.0, 0.4)
	tw.tween_callback(node.queue_free)


func _create_view(obj: Dictionary) -> void:
	var gone := is_gone(obj)
	var node := Node3D.new()
	node.name = obj.id
	node.position = Vector3(obj.x + 0.5, 0, obj.y + 0.5)
	match obj.kind:
		"enemy":
			if gone:
				return
			var def := GameData.get_enemy(obj.enemyId)
			var scale := 2.0 if obj.tier == "boss" else (1.4 if obj.tier == "elite" else 1.0)
			node.add_child(Fx.shadow_quad(0.85 * scale))
			var s := Fx.sprite(Assets.frame(int(def.frame)), 16.0 / scale)
			s.rotation.x = TILT
			s.position.y = 0.05
			var bob := Fx.Bob.new()
			bob.amplitude = 0.12
			bob.period = 1.3 + float((int(obj.x) * 37 + int(obj.y) * 11) % 400) / 500.0
			s.add_child(bob)
			node.add_child(s)
			if obj.tier != "normal":
				node.add_child(_light(Color("#ff5040") if obj.tier == "boss" else Color("#ffb030"), 1.2, 2.5 * scale, Vector3(0, 0.8 * scale, 0.5)))
		"chest":
			var frame_no: int = TD.chest_rare if obj.chestType == "rare" else (TD.chest_special if obj.chestType == "special" else TD.chest)
			node.add_child(Fx.shadow_quad(0.8))
			var s := Fx.sprite(Assets.frame(frame_no))
			s.rotation.x = TILT
			node.add_child(s)
			if gone:
				s.modulate = Color(0.45, 0.45, 0.45, 0.9)
			else:
				var c := Color("#ffe6a0") if obj.chestType == "normal" else (Color("#ffd75e") if obj.chestType == "rare" else Color("#d8a0ff"))
				node.add_child(_light(c, 0.8, 2.2, Vector3(0, 0.7, 0.4)))
				node.add_child(_marker(c))
		"door", "bossDoor":
			var s := Fx.sprite(Assets.frame(TD.door_open if gone else TD.door))
			s.scale = Vector3(1.0, 1.25, 1.0)
			node.add_child(s)
			if obj.kind == "bossDoor":
				s.modulate = Color("#8a6a8a") if gone else Color("#e0a0ff")
				if not gone:
					node.add_child(_light(Color("#c070ff"), 1.6, 3.2, Vector3(0, 1.0, 0.6)))
			if not gone:
				node.add_child(_marker(Color("#e0a0ff") if obj.kind == "bossDoor" else Color.WHITE))
		"heal":
			var s := Fx.sprite(Assets.frame(TD.altar))
			s.rotation.x = TILT
			node.add_child(s)
			var l := Fx.Flicker.new()
			l.light_color = Color("#6dffa8")
			l.base_energy = 1.6
			l.speed = 2.0
			l.amount = 0.25
			l.omni_range = 3.6
			l.position = Vector3(0, 1.0, 0.4)
			node.add_child(l)
			node.add_child(_sparkles(Color("#b8ffd4")))
	objects_root.add_child(node)
	views[obj.id] = node


static func _light(c: Color, energy: float, range_: float, pos: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = range_
	l.position = pos
	return l


## Schwebender Pfeil über Truhen und Türen, immer sichtbar (auch hinter Bäumen).
static func _marker(c: Color) -> Sprite3D:
	var m := Fx.sprite(Fx.marker(), 16.0, false)
	m.modulate = c
	# Transparenter Pass + ohne Tiefentest: wird nach allem Opaken gezeichnet und bleibt sichtbar.
	m.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	m.no_depth_test = true
	m.render_priority = 10
	m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position.y = 1.35
	var bob := Fx.Bob.new()
	bob.amplitude = 0.15
	bob.period = 1.2
	m.add_child(bob)
	return m


## Aufsteigende Lichtfunken (Kristallaltar).
static func _sparkles(c: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 1.8
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.35, 0.1, 0.2)
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3.ZERO
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * 2.0
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	p.position = Vector3(0, 0.5, 0.1)
	return p
