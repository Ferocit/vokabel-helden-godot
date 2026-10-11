class_name WorldFx
extends Node3D
## HD-2D-Stimmung: Kamera mit flachem Blickwinkel, Dschungel-Halbdunkel, warmes Licht,
## Glow, SSAO und Nebel. Bewusst ohne Tiefenunschärfe – die Pixel-Art bleibt scharf (Issue #10).
## Dazu Glühwürmchen und fallende Blätter rund um das Kameraziel und eine Vignette.

const BACKGROUND := Color("#0e1a12")
const AMBIENT := Color("#b4c8b0")
## Blickwinkel und Abstand der Kamera (Grad über dem Boden, Einheiten).
const PITCH := 52.0
const DISTANCE := 21.0
const FOV := 34.0

var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
## Punkt, dem Kamera und Partikel folgen (Weltkoordinaten, y = 0).
var target := Vector3.ZERO
var follow_speed := 7.0
var zoom := 1.0

var _atmosphere: Node3D


func _init(density: float = 1.0) -> void:
	name = "WorldFx"
	environment = _make_environment()
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("#c8dcff")
	sun.light_energy = 0.3
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.7
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 40.0
	sun.rotation = Vector3(deg_to_rad(-62), deg_to_rad(28), 0)
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.5
	camera.far = 120.0
	camera.current = true
	add_child(camera)

	_atmosphere = Node3D.new()
	_atmosphere.add_child(_fireflies(density))
	_atmosphere.add_child(_leaves(density))
	add_child(_atmosphere)

	var layer := CanvasLayer.new()
	layer.layer = -1
	layer.add_child(_vignette())
	add_child(layer)


static func _make_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BACKGROUND
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = AMBIENT
	e.ambient_light_energy = 0.2
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.75
	e.glow_strength = 1.0
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 0.95
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 1.0)
	e.set_glow_level(3, 0.6)
	e.set_glow_level(4, 0.3)
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.6
	e.ssao_power = 1.3
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color("#1c3022")
	e.fog_light_energy = 0.8
	e.fog_density = 0.012
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.08
	e.adjustment_contrast = 1.04
	return e


func _process(delta: float) -> void:
	_update_camera(minf(1.0, delta * follow_speed))
	_atmosphere.position = target


## Kamera sofort auf das Ziel setzen (ohne Nachziehen).
func snap() -> void:
	_update_camera(1.0)


var _cam_pos := Vector3.ZERO


func _update_camera(t: float) -> void:
	_cam_pos = _cam_pos.lerp(target, t)
	var pitch := deg_to_rad(PITCH)
	var dist := DISTANCE / zoom
	camera.position = _cam_pos + Vector3(0, sin(pitch) * dist, cos(pitch) * dist)
	camera.look_at(_cam_pos + Vector3(0, 0.6, 0), Vector3.UP)


static func _vignette() -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.01, 0.02, 0.01, 0.55)])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 1.05)
	t.width = 256
	t.height = 144
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _particle_quad(size: float, color: Color, unshaded: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	return q


static func _fireflies(density: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Fireflies"
	p.amount = int(40 * density)
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-14, -2, -12), Vector3(28, 8, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(11, 1.0, 8)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	p.position.y = 1.2
	p.draw_pass_1 = _particle_quad(0.07, Color(2.2, 2.6, 1.2), true)
	return p


static func _leaves(density: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Leaves"
	p.amount = int(14 * density)
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-14, -2, -12), Vector3(28, 12, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(11, 0.5, 8)
	pm.direction = Vector3(0.3, -1, 0.1)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, -0.15, 0)
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.color = Color("#7fbf4a")
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	p.position.y = 5.0
	p.draw_pass_1 = _particle_quad(0.12, Color.WHITE, false)
	return p
