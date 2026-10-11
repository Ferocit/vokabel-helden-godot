extends TestCase
## Gegnerbewegung: Patrouille, Verfolgung, Aufgeben, Leine, Wände, nie schneller als der Held.

const EXPLORATION := preload("res://scenes/exploration.tscn")
const HERO_SPEED := 3.4
const ROOM := {"id": 1, "x": 2, "y": 2, "w": 8, "h": 8}


## Offene Fläche 0..20 × 0..20, Wand bei x == 12 (außer Durchgang y == 6).
static func solid(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= 20 or y >= 20:
		return true
	return x == 12 and y != 6


static func agent(tier: String, x: int = 5, y: int = 5, seed: int = 1) -> EnemyAgent:
	return EnemyAgent.new({"id": "e", "tier": tier, "x": x, "y": y}, ROOM, Rng.create(seed))


static func run_for(a: EnemyAgent, seconds: float, hero: Vector2, check: Callable = Callable()) -> void:
	var t := 0.0
	while t < seconds:
		a.update(0.05, hero, solid, HERO_SPEED)
		if check.is_valid():
			check.call(a)
		t += 0.05


func test_normaler_gegner_patrouilliert_im_raum() -> void:
	var a := agent("normal")
	var moved := [false]
	run_for(a, 30.0, Vector2(18.5, 18.5), func(x: EnemyAgent) -> void:
		if x.pos.distance_to(x.home) > 0.5:
			moved[0] = true
		expect_true(MapModel.room_contains(ROOM, floori(x.pos.x), floori(x.pos.y)), "bleibt im Raum: %s" % x.pos))
	expect_true(moved[0], "bewegt sich")


func test_verfolgt_und_kommt_naeher() -> void:
	var a := agent("normal")
	var hero := Vector2(7.5, 5.5)
	a.update(0.05, hero, solid, HERO_SPEED)
	expect_eq(a.mode, "chase")
	var d0 := a.pos.distance_to(hero)
	run_for(a, 0.5, hero)
	expect_lt(a.pos.distance_to(hero), d0)


func test_nie_schneller_als_der_held() -> void:
	var a := agent("normal")
	var hero := Vector2(8.0, 5.5)
	a.update(0.05, hero, solid, 1.0)  # sehr langsamer Held
	var start := a.pos
	for i in 20:
		a.update(0.05, hero, solid, 1.0)
	expect_gt(a.pos.distance_to(start), 0.5, "Bewegt sich überhaupt")
	expect_le(a.pos.distance_to(start), 0.9 * 1.0 * 1.0 + 0.01, "Höchstens 90 % des Heldentempos")
	for tier in ["normal", "elite", "boss"]:
		expect_lt(float(GameConfig.section("enemyAI")[tier].chaseSpeed), HERO_SPEED, tier)


func test_gibt_auf_und_kehrt_heim() -> void:
	var a := agent("normal")
	a.update(0.05, Vector2(7.5, 5.5), solid, HERO_SPEED)
	run_for(a, 0.6, Vector2(7.5, 5.5))
	expect_gt(a.pos.distance_to(a.home), 0.3, "ist losgelaufen")
	run_for(a, 12.0, Vector2(18.5, 18.5))
	expect_ne(a.mode, "chase", "hat aufgegeben")
	expect_true(a.mode in ["idle", "patrol"], "zurück im Normalbetrieb")


func test_leine_begrenzt_verfolgung() -> void:
	var a := agent("elite")
	var leash := float(GameConfig.section("enemyAI").elite.leash)
	var max_d := [0.0]
	# Held läuft langsam weg: der Elite-Gegner folgt nur bis zur Leine.
	var hero := Vector2(6.5, 5.5)
	for i in 300:
		hero.x = minf(11.0, hero.x + 0.02)
		hero.y = 5.5 + i * 0.02
		a.update(0.05, hero, solid, HERO_SPEED)
		max_d[0] = maxf(max_d[0], a.pos.distance_to(a.home))
	expect_gt(max_d[0], 0.5, "Elite hat überhaupt verfolgt")
	expect_le(max_d[0], leash + 0.3)


func test_elite_patrouilliert_nicht_boss_steht() -> void:
	var e := agent("elite")
	run_for(e, 10.0, Vector2(18.5, 18.5))
	expect_eq(e.pos, e.home, "Elite bleibt auf Posten")
	var b := agent("boss")
	run_for(b, 5.0, Vector2(5.6, 5.5))
	expect_eq(b.pos, b.home, "Boss bewegt sich nie")
	expect_false(b.moves())


func test_keine_wand_wird_betreten() -> void:
	var a := agent("normal", 9, 9)
	a.room = {}
	run_for(a, 8.0, Vector2(11.0, 9.5), func(x: EnemyAgent) -> void:
		for c: Vector2 in [Vector2(-0.3, -0.3), Vector2(0.3, 0.3)]:
			expect_false(solid(floori(x.pos.x + c.x), floori(x.pos.y + c.y)), "in Wand: %s" % x.pos))


func test_zuruecksetzen() -> void:
	var a := agent("normal")
	a.update(0.05, Vector2(7.5, 5.5), solid, HERO_SPEED)
	run_for(a, 0.5, Vector2(7.5, 5.5))
	a.reset()
	expect_eq(a.pos, a.home)
	expect_eq(a.mode, "idle")


func test_erkundung_gegner_kommt_und_kampf_beginnt() -> void:
	VocabPrompt.instant = true
	Ctx.setup(KeyValueStore.new())
	Ctx.start_run(["sample"], "jungle", 4242)
	var e: Node3D = EXPLORATION.instantiate()
	e.fast = true
	(Engine.get_main_loop() as SceneTree).root.add_child(e)
	var obj: Dictionary = (Ctx.run.map.objects as Array).filter(func(o: Dictionary) -> bool: return o.kind == "enemy" and o.tier == "normal")[0]
	var a: EnemyAgent = e.agents[obj.id]
	# Held zwei Kacheln neben den Gegner stellen (auf freien Boden in Richtung Raummitte).
	var hero := a.home
	for d: Vector2 in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
		if e.free_at(a.home.x + d.x, a.home.y + d.y):
			hero = a.home + d
			break
	Ctx.run.player = hero
	var steps := 0
	while not e.busy and steps < 100:
		e.update_enemies(0.05)
		e.check_enemy_contact()
		steps += 1
	expect_true(e.busy, "Gegner hat den Helden erreicht, Kampf beginnt")
	expect_lt(a.pos.distance_to(a.home), 2.0)
	var view: Node3D = e.level.views[obj.id]
	expect_near(view.position.x, a.pos.x, 0.01, "Ansicht folgt")
	e.reset_enemies()
	expect_eq(a.pos, a.home, "Nach Niederlage zurück auf Platz")
	e.free()
