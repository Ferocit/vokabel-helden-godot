class_name EnemyAgent
extends RefCounted
## Bewegung eines Gegners in der Erkundung (reine Logik, ohne Darstellung).
## - normal: patrouilliert langsam in seinem Raum, verfolgt den Helden in Sichtweite, gibt nach einer Weile auf
## - elite:  bewacht seinen Platz, reagiert erst aus der Nähe, entfernt sich nur kurz
## - boss:   bleibt stehen
## Lernspiel-Regel: Kein Gegner ist schneller als der Held – Kämpfen kann man immer ausweichen.
## Werte in config/game.json → enemyAI. Positionen in Kachel-Einheiten (Mittelpunkt einer Kachel = x + 0.5).

const RADIUS := 0.3

var id: String
var tier: String
var home: Vector2
var pos: Vector2
var mode := "idle"  # idle | patrol | chase | return
var target := Vector2.ZERO
## Zuletzt gelaufene Richtung (für die Blickrichtung des Sprites).
var facing := Vector2.ZERO
var room: Dictionary = {}

var _cfg: Dictionary
var _rng: Callable
var _timer := 0.0
var _lost_timer := 0.0
var _stuck_timer := 0.0


func _init(obj: Dictionary, map_room: Dictionary, rng: Callable) -> void:
	id = obj.id
	tier = obj.tier
	home = Vector2(obj.x + 0.5, obj.y + 0.5)
	pos = home
	room = map_room
	_rng = rng
	_cfg = GameConfig.section("enemyAI")[tier]
	_timer = _rand(float(_cfg.pauseMin), float(_cfg.pauseMax))


func _rand(a: float, b: float) -> float:
	return a + (b - a) * float(_rng.call())


func moves() -> bool:
	return float(_cfg.chaseSpeed) > 0.0 or float(_cfg.patrolSpeed) > 0.0


## Zurück an den Ausgangsplatz (nach einer Niederlage des Helden, beim Laden).
func reset() -> void:
	pos = home
	mode = "idle"
	facing = Vector2.ZERO
	_lost_timer = 0.0
	_timer = _rand(float(_cfg.pauseMin), float(_cfg.pauseMax))


## Ein Schritt. `is_solid(x, y)` meldet blockierte Kacheln; `hero_speed` ist das aktuelle Tempo des Helden.
func update(dt: float, player: Vector2, is_solid: Callable, hero_speed: float) -> void:
	if not moves():
		return
	var to_player := player.distance_to(pos)
	var from_home := pos.distance_to(home)
	# Nie schneller als der Held (90 % seines Tempos als Obergrenze).
	var chase_speed := minf(float(_cfg.chaseSpeed), hero_speed * 0.9)

	match mode:
		"idle", "patrol":
			if to_player <= float(_cfg.aggroRange) and float(_cfg.chaseSpeed) > 0.0:
				mode = "chase"
				_lost_timer = 0.0
		"chase":
			var too_far := to_player > float(_cfg.giveUpRange)
			_lost_timer = _lost_timer + dt if too_far else 0.0
			if _lost_timer >= float(_cfg.giveUpTime) or from_home > float(_cfg.leash):
				mode = "return"

	match mode:
		"idle":
			_timer -= dt
			if _timer <= 0.0 and float(_cfg.patrolSpeed) > 0.0:
				var t := _patrol_target(is_solid)
				if t != pos:
					target = t
					mode = "patrol"
				_timer = _rand(float(_cfg.pauseMin), float(_cfg.pauseMax))
		"patrol":
			if _step_towards(target, float(_cfg.patrolSpeed), dt, is_solid) or _stuck_timer > 1.0:
				mode = "idle"
				_stuck_timer = 0.0
		"chase":
			_step_towards(player, chase_speed, dt, is_solid)
		"return":
			var arrived := _step_towards(home, maxf(float(_cfg.patrolSpeed), chase_speed * 0.8), dt, is_solid)
			# Hängt er fest (z. B. an einer Ecke im Gang), kehrt er einfach heim.
			if arrived or _stuck_timer > 2.0:
				reset()


## Bewegt sich in gerader Linie mit Gleiten an Hindernissen. Liefert true, wenn das Ziel erreicht ist.
func _step_towards(goal: Vector2, speed: float, dt: float, is_solid: Callable) -> bool:
	var d := goal - pos
	if d.length() < 0.08:
		return true
	var dir := d.normalized()
	var step := minf(speed * dt, d.length())
	var before := pos
	var nx := pos + Vector2(dir.x * step, 0)
	if _free(nx, is_solid):
		pos = nx
	var ny := pos + Vector2(0, dir.y * step)
	if _free(ny, is_solid):
		pos = ny
	var moved := pos.distance_to(before)
	if moved > 0.0001:
		facing = (pos - before).normalized()
	_stuck_timer = _stuck_timer + dt if moved < step * 0.2 else 0.0
	return pos.distance_to(goal) < 0.08


func _free(p: Vector2, is_solid: Callable) -> bool:
	var r := RADIUS
	for c: Vector2 in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
		if is_solid.call(floori(p.x + c.x), floori(p.y + c.y)):
			return false
	return true


## Zufällige freie Kachel im eigenen Raum; ohne Raum (Gang) bleibt er stehen.
func _patrol_target(is_solid: Callable) -> Vector2:
	if room.is_empty():
		return pos
	for attempt in 8:
		var x: int = room.x + floori(_rng.call() * int(room.w))
		var y: int = room.y + floori(_rng.call() * int(room.h))
		if not is_solid.call(x, y):
			return Vector2(x + 0.5, y + 0.5)
	return pos
