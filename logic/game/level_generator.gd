class_name LevelGenerator
extends RefCounted
## Erzeugt ein vollständiges, garantiert lösbares Level. Gleicher Seed ⇒ gleiches Level.
## cfg = config.level (rooms, roomSize, bossRoomSize, gridSize, extraLoops, normalEnemies, eliteEnemies,
##       chests, doors, doorAnswers, minEnemyDistanceFromStart)
## options = { bossRunesRequired, enemies: {normal: [...], elite: [...], boss: "..."} }

const MAX_ATTEMPTS := 60
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const TURN_COST := 3.0

var rng: Callable
var cfg: Dictionary
var options: Dictionary
var W: int
var H: int
var tiles: PackedInt32Array
var room_at: PackedInt32Array
var rooms: Array = []
var boss: Dictionary
var start_room: Dictionary
var start_pos: Vector2i
var occupied := {}
var base_dist: PackedInt32Array
var objects: Array = []
var counter := 0
var _wall_mask := PackedByteArray()


static func generate(seed: int, level_cfg: Dictionary, opts: Dictionary) -> Dictionary:
	for attempt in MAX_ATTEMPTS:
		var gen := LevelGenerator.new()
		gen.rng = Rng.create((seed + attempt * 7919) & Rng.MASK)
		gen.cfg = level_cfg
		gen.options = opts
		var map := gen._try_generate()
		if not map.is_empty():
			map.seed = seed
			return map
	push_error("Level konnte für Seed %d nicht erzeugt werden." % seed)
	return {}


func _idx(x: int, y: int) -> int:
	return y * W + x


func _in_bounds(x: int, y: int) -> bool:
	return x >= 1 and y >= 1 and x < W - 1 and y < H - 1


func _dist(a: Dictionary, b: Dictionary) -> int:
	var ca := MapModel.room_center(a)
	var cb := MapModel.room_center(b)
	return absi(ca.x - cb.x) + absi(ca.y - cb.y)


func _rand(r: Dictionary) -> int:
	return Rng.rand_int(rng, int(r.min), int(r.max))


## Leeres Dictionary bedeutet: Versuch fehlgeschlagen, nächster Seed.
func _try_generate() -> Dictionary:
	W = int(cfg.gridSize)
	H = int(cfg.gridSize)
	tiles = PackedInt32Array()
	tiles.resize(W * H)
	tiles.fill(MapModel.VOID)

	# 1. Räume: zuerst der Bossraum, dann normale Räume ohne Überlappung.
	var boss_size := int(cfg.bossRoomSize)
	rooms.append({"id": 0, "x": Rng.rand_int(rng, 2, W - boss_size - 2), "y": Rng.rand_int(rng, 2, H - boss_size - 2), "w": boss_size, "h": boss_size})
	var target_rooms := _rand(cfg.rooms)
	var tries := 0
	while tries < 600 and rooms.size() < target_rooms:
		tries += 1
		var w := _rand(cfg.roomSize)
		var h := _rand(cfg.roomSize)
		var room := {"id": rooms.size(), "x": Rng.rand_int(rng, 2, W - w - 2), "y": Rng.rand_int(rng, 2, H - h - 2), "w": w, "h": h}
		var overlaps := false
		for r: Dictionary in rooms:
			var gap := 3 if r.id == 0 else 2
			if room.x < r.x + r.w + gap and room.x + room.w + gap > r.x and room.y < r.y + r.h + gap and room.y + room.h + gap > r.y:
				overlaps = true
				break
		if not overlaps:
			rooms.append(room)
	if rooms.size() < int(cfg.rooms.min):
		return {}

	boss = rooms[0]
	var boss_c := MapModel.room_center(boss)
	var others: Array = rooms.slice(1)
	start_room = others[0]
	for r: Dictionary in others:
		if _dist(r, boss) > _dist(start_room, boss):
			start_room = r

	_wall_mask.resize(W * H)
	_wall_mask.fill(0)
	room_at = PackedInt32Array()
	room_at.resize(W * H)
	room_at.fill(-1)
	for room: Dictionary in rooms:
		for y in range(room.y, room.y + room.h):
			for x in range(room.x, room.x + room.w):
				tiles[_idx(x, y)] = MapModel.FLOOR
				room_at[_idx(x, y)] = room.id

	# 2. Raumgraph: Spannbaum über normale Räume (Prim) + einige Schleifen.
	var edges: Array = []  # [Room, Room]
	var in_tree := {others[0].id: true}
	while in_tree.size() < others.size():
		var best: Array = []
		for a: Dictionary in others:
			if not in_tree.has(a.id):
				continue
			for b: Dictionary in others:
				if in_tree.has(b.id):
					continue
				if best.is_empty() or _dist(a, b) < _dist(best[0], best[1]):
					best = [a, b]
		edges.append(best)
		in_tree[best[1].id] = true
	var has_edge := func(a: Dictionary, b: Dictionary) -> bool:
		for e: Array in edges:
			if (e[0].id == a.id and e[1].id == b.id) or (e[0].id == b.id and e[1].id == a.id):
				return true
		return false
	var loop_candidates: Array = []
	for i in others.size():
		for j in range(i + 1, others.size()):
			if not has_edge.call(others[i], others[j]):
				loop_candidates.append([others[i], others[j]])
	# Stabil sortieren wie Array.prototype.sort (Index als Zweitschlüssel).
	for i in loop_candidates.size():
		loop_candidates[i].append(i)
	loop_candidates.sort_custom(func(a: Array, b: Array) -> bool:
		var da := _dist(a[0], a[1])
		var db := _dist(b[0], b[1])
		return da < db if da != db else a[2] < b[2])
	var loops: Array = Rng.shuffle(rng, loop_candidates.slice(0, 6)).slice(0, int(cfg.extraLoops))
	for l: Array in loops:
		edges.append([l[0], l[1]])

	# 3. Gänge (Bossraum samt Rand ist für alle anderen Gänge gesperrt).
	for e: Array in edges:
		var path := _find_path(MapModel.room_center(e[0]), MapModel.room_center(e[1]))
		if path.is_empty():
			return {}
		_carve(path)

	# Bossanbindung: Tür an der Seite, die zum nächstgelegenen Raum zeigt – bevorzugt oben oder unten,
	# denn Türen werden frontal zur Kamera gezeichnet und passen nur in Nord-Süd-Durchgänge.
	var neighbor_pool: Array = others.filter(func(r: Dictionary) -> bool: return r.id != start_room.id)
	if others.size() == 1:
		neighbor_pool.append(start_room)
	var boss_neighbor: Dictionary = neighbor_pool[0]
	for r: Dictionary in neighbor_pool:
		if _dist(r, boss) < _dist(boss_neighbor, boss):
			boss_neighbor = r
	var nb := MapModel.room_center(boss_neighbor)
	var boss_door := Vector2i(-1, -1)
	for side: Dictionary in _boss_door_sides(boss_c, nb):
		var outer: Vector2i = side.outer
		if not _in_bounds(outer.x, outer.y):
			continue
		var path := _find_path(outer, nb)
		if path.is_empty():
			continue
		_carve(path)
		tiles[_idx(side.door.x, side.door.y)] = MapModel.FLOOR
		tiles[_idx(outer.x, outer.y)] = MapModel.FLOOR
		boss_door = side.door
		break
	if boss_door.x < 0:
		return {}

	start_pos = MapModel.room_center(start_room)
	var boss_door_idx := _idx(boss_door.x, boss_door.y)
	base_dist = _bfs(PackedInt32Array([boss_door_idx]))
	# Der Bossraum darf nur durch die Bosstür erreichbar sein, alle anderen Räume ohne sie.
	if base_dist[_idx(boss_c.x, boss_c.y)] != -1:
		return {}
	for room: Dictionary in others:
		var c := MapModel.room_center(room)
		if base_dist[_idx(c.x, c.y)] == -1:
			return {}
	var reachable_count := _count_reachable(base_dist)

	# 4. Lerntüren an Raumeingängen, die einen Bereich wirklich abtrennen.
	var door_candidates: Array = []
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if not _is_entrance(x, y) or not _north_south_passage(x, y) or (x == boss_door.x and y == boss_door.y):
				continue
			var d := _bfs(PackedInt32Array([boss_door_idx, _idx(x, y)]))
			var cut := reachable_count - _count_reachable(d) - 1
			if cut <= 0:
				continue
			var cut_rooms: Array = []
			for r: Dictionary in others:
				var c := MapModel.room_center(r)
				if d[_idx(c.x, c.y)] == -1:
					cut_rooms.append(r.id)
			if cut_rooms.is_empty():
				continue
			door_candidates.append({"x": x, "y": y, "cutRooms": cut_rooms})
	var door_count := _rand(cfg.doors)
	var doors: Array = []
	for cand: Dictionary in Rng.shuffle(rng, door_candidates):
		if doors.size() >= door_count:
			break
		var skip := false
		for d: Dictionary in doors:
			if absi(d.x - cand.x) + absi(d.y - cand.y) < 4 or d.cutRooms == cand.cutRooms:
				skip = true
				break
		if not skip:
			doors.append(cand)
	if doors.size() < int(cfg.doors.min):
		return {}
	var behind_door := {}
	for d: Dictionary in doors:
		for id: int in d.cutRooms:
			behind_door[id] = true

	# 5. Objekte platzieren.
	occupied = {_idx(start_pos.x, start_pos.y): true, boss_door_idx: true}
	for d: Dictionary in doors:
		occupied[_idx(d.x, d.y)] = true

	objects.append({"id": "bossdoor", "kind": "bossDoor", "x": boss_door.x, "y": boss_door.y, "runes": int(options.bossRunesRequired)})
	for i in doors.size():
		objects.append({"id": "door%d" % i, "kind": "door", "x": doors[i].x, "y": doors[i].y, "answers": _rand(cfg.doorAnswers)})
	objects.append({"id": "boss", "kind": "enemy", "x": boss_c.x, "y": boss_c.y, "enemyId": options.enemies.boss, "tier": "boss"})

	var make_heal := func(x: int, y: int, id: String) -> Dictionary: return {"id": id, "kind": "heal", "x": x, "y": y}
	if not _place([start_room], make_heal):
		return {}
	if boss_neighbor.id != start_room.id:
		_place([boss_neighbor], make_heal)

	# Hauptpfad: Räume auf dem kürzesten Weg vom Start zur Bosstür.
	var full_dist := _bfs(PackedInt32Array())
	var main_path: Array = _trace_path_rooms(boss_door, full_dist).filter(func(id: int) -> bool:
		return id != start_room.id and id != boss.id)
	var non_start: Array = others.filter(func(r: Dictionary) -> bool: return r.id != start_room.id)
	var min_dist := int(cfg.minEnemyDistanceFromStart)

	var elite_count := _rand(cfg.eliteEnemies)
	for i in elite_count:
		var preferred: Array
		if i == 0 and not main_path.is_empty():
			preferred = [rooms[main_path[main_path.size() / 2]]]
		else:
			preferred = Rng.shuffle(rng, non_start.filter(func(r: Dictionary) -> bool: return behind_door.has(r.id)))
		var candidates: Array = preferred + Rng.shuffle(rng, non_start)
		var ok := _place(candidates, func(x: int, y: int, id: String) -> Dictionary:
			return {"id": id, "kind": "enemy", "x": x, "y": y, "enemyId": Rng.pick(rng, options.enemies.elite), "tier": "elite"}, min_dist)
		if not ok:
			return {}

	var normal_count := _rand(cfg.normalEnemies)
	var room_order: Array = Rng.shuffle(rng, non_start)
	for i in normal_count:
		var first: Dictionary = room_order[i % room_order.size()]
		var candidates: Array = [first] + Rng.shuffle(rng, non_start)
		var ok := _place(candidates, func(x: int, y: int, id: String) -> Dictionary:
			return {"id": id, "kind": "enemy", "x": x, "y": y, "enemyId": Rng.pick(rng, options.enemies.normal), "tier": "normal"}, min_dist)
		if not ok:
			return {}

	var chest_count := _rand(cfg.chests)
	var leaf_rooms: Array = non_start.filter(func(r: Dictionary) -> bool:
		var n := 0
		for e: Array in edges:
			if e[0].id == r.id or e[1].id == r.id:
				n += 1
		return n == 1)
	var chest_rooms: Array = Rng.shuffle(rng, non_start.filter(func(r: Dictionary) -> bool: return behind_door.has(r.id)))
	chest_rooms += Rng.shuffle(rng, leaf_rooms)
	chest_rooms += Rng.shuffle(rng, non_start)
	for i in chest_count:
		var chest_type := "rare" if i == 0 else ("special" if i == 1 and chest_count >= 3 else "normal")
		var rotated: Array = chest_rooms.slice(i % chest_rooms.size()) + chest_rooms
		if not _place(rotated, func(x: int, y: int, id: String) -> Dictionary:
			return {"id": id, "kind": "chest", "x": x, "y": y, "chestType": chest_type}):
			return {}

	# Wissensschreine in Räumen, Runenplatten in Gängen (Issue #16: mehr Abfragen unterwegs).
	var shrine_rooms: Array = Rng.shuffle(rng, non_start)
	for i in _rand(cfg.get("shrines", {"min": 0, "max": 0})):
		var rotated: Array = shrine_rooms.slice(i % shrine_rooms.size()) + shrine_rooms
		if not _place(rotated, func(x: int, y: int, id: String) -> Dictionary:
			return {"id": id, "kind": "shrine", "x": x, "y": y}):
			break
	_place_plates(_rand(cfg.get("plates", {"min": 0, "max": 0})))

	# 6. Absicherung: Mit allen festen Objekten als Hindernis muss alles erreichbar bleiben.
	var walls := PackedInt32Array([boss_door_idx])
	for o: Dictionary in objects:
		if o.kind == "chest" or o.kind == "heal" or o.kind == "shrine":
			walls.append(_idx(o.x, o.y))
	var final_dist := _bfs(walls)
	for o: Dictionary in objects:
		if o.kind == "enemy" and o.tier == "boss":
			continue
		var reachable: bool = final_dist[_idx(o.x, o.y)] >= 0
		for dir in DIRS:
			if final_dist[_idx(o.x + dir.x, o.y + dir.y)] >= 0:
				reachable = true
		if not reachable:
			return {}
	var rune_sources := 0
	for o: Dictionary in objects:
		if (o.kind == "enemy" and o.tier != "boss") or o.kind == "door":
			rune_sources += 1
	if rune_sources < int(options.bossRunesRequired):
		return {}

	return {
		"seed": 0,
		"width": W,
		"height": H,
		"tiles": tiles,
		"rooms": rooms,
		"startRoomId": start_room.id,
		"bossRoomId": boss.id,
		"start": start_pos,
		"objects": objects,
	}


func _carve(path: Array) -> void:
	for p: Vector2i in path:
		tiles[_idx(p.x, p.y)] = MapModel.FLOOR


func _blocked(x: int, y: int) -> bool:
	return x >= boss.x - 1 and x <= boss.x + boss.w and y >= boss.y - 1 and y <= boss.y + boss.h


## Schrittkosten (in _find_path vorberechnet): Bestehender Boden ist günstig (Gänge treffen sich), aber
## direkt neben einem Gang oder an einer Raumwand entlang zu graben ist teuer – so entstehen keine
## doppelten, parallelen Gänge.


## walls: Indizes, die als Wand gelten (zusätzlich zu VOID).
func _bfs(walls: PackedInt32Array) -> PackedInt32Array:
	for w in walls:
		_wall_mask[w] = 1
	var d := PackedInt32Array()
	d.resize(W * H)
	d.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(W * H)
	var head := 0
	var tail := 1
	queue[0] = _idx(start_pos.x, start_pos.y)
	d[queue[0]] = 0
	var offsets := [1, W, -1, -W]
	while head < tail:
		var cur := queue[head]
		head += 1
		var nd := d[cur] + 1
		for off: int in offsets:
			var n := cur + off
			if tiles[n] != MapModel.FLOOR or d[n] != -1 or _wall_mask[n] == 1:
				continue
			d[n] = nd
			queue[tail] = n
			tail += 1
	for w in walls:
		_wall_mask[w] = 0
	return d


func _count_reachable(d: PackedInt32Array) -> int:
	var n := 0
	for v in d:
		if v >= 0:
			n += 1
	return n


func _is_entrance(x: int, y: int) -> bool:
	var i := _idx(x, y)
	if tiles[i] != MapModel.FLOOR or room_at[i] != -1:
		return false
	for dir in DIRS:
		var r := room_at[_idx(x + dir.x, y + dir.y)]
		if r != -1 and r != boss.id and r != start_room.id:
			return true
	return false


## Durchgang von oben nach unten (links und rechts kein Boden): Nur hier steht eine Tür richtig herum.
func _north_south_passage(x: int, y: int) -> bool:
	return tiles[_idx(x, y - 1)] == MapModel.FLOOR and tiles[_idx(x, y + 1)] == MapModel.FLOOR 		and tiles[_idx(x - 1, y)] != MapModel.FLOOR and tiles[_idx(x + 1, y)] != MapModel.FLOOR


func _near_corridor(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := _idx(x + dx, y + dy)
			if tiles[n] == MapModel.FLOOR and room_at[n] == -1:
				return true
	return false


func _near_occupied(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if occupied.has(_idx(x + dx, y + dy)):
				return true
	return false


func _free_tiles(room: Dictionary, min_dist: int) -> Array:
	var result: Array = []
	for y in range(room.y, room.y + room.h):
		for x in range(room.x, room.x + room.w):
			if _near_corridor(x, y) or _near_occupied(x, y):
				continue
			if min_dist > 0 and base_dist[_idx(x, y)] < min_dist:
				continue
			result.append(Vector2i(x, y))
	return result


## Runenplatten auf Gangkacheln (außerhalb der Räume), mit Abstand zueinander und zu Türen.
func _place_plates(count: int) -> void:
	var corridor: Array = []
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := _idx(x, y)
			if tiles[i] == MapModel.FLOOR and room_at[i] == -1 and not occupied.has(i):
				corridor.append(Vector2i(x, y))
	var placed: Array = []
	for t: Vector2i in Rng.shuffle(rng, corridor):
		if placed.size() >= count:
			return
		var ok := true
		for o: Dictionary in objects:
			if absi(int(o.x) - t.x) + absi(int(o.y) - t.y) < (5 if o.kind == "plate" else 2):
				ok = false
				break
		if not ok:
			continue
		occupied[_idx(t.x, t.y)] = true
		var plate := {"id": "o%d" % counter, "kind": "plate", "x": t.x, "y": t.y}
		counter += 1
		objects.append(plate)
		placed.append(plate)


func _place(candidates: Array, make: Callable, min_dist: int = 0) -> bool:
	for room: Dictionary in candidates:
		var free := _free_tiles(room, min_dist)
		if free.is_empty():
			continue
		var t: Vector2i = Rng.pick(rng, free)
		occupied[_idx(t.x, t.y)] = true
		objects.append(make.call(t.x, t.y, "o%d" % counter))
		counter += 1
		return true
	return false


func _boss_door_sides(c: Vector2i, target: Vector2i) -> Array:
	var east := {"door": Vector2i(boss.x + boss.w, c.y), "outer": Vector2i(boss.x + boss.w + 1, c.y)}
	var west := {"door": Vector2i(boss.x - 1, c.y), "outer": Vector2i(boss.x - 2, c.y)}
	var south := {"door": Vector2i(c.x, boss.y + boss.h), "outer": Vector2i(c.x, boss.y + boss.h + 1)}
	var north := {"door": Vector2i(c.x, boss.y - 1), "outer": Vector2i(c.x, boss.y - 2)}
	var dx := target.x - c.x
	var dy := target.y - c.y
	var horizontal: Array = [east, west] if dx > 0 else [west, east]
	var vertical: Array = [south, north] if dy > 0 else [north, south]
	return [vertical[0], vertical[1], horizontal[0], horizontal[1]]


## Läuft vom Ziel entlang fallender BFS-Distanz zurück zum Start und sammelt die besuchten Räume.
func _trace_path_rooms(target: Vector2i, dist: PackedInt32Array) -> Array:
	var result: Array = []
	var cur := target.y * W + target.x
	if dist[cur] < 0:
		return result
	while dist[cur] > 0:
		var cx := cur % W
		var cy := cur / W
		var next := cur
		for dir in DIRS:
			var n := (cy + dir.y) * W + (cx + dir.x)
			if dist[n] == dist[cur] - 1:
				next = n
				break
		if next == cur:
			break
		cur = next
		var r := room_at[cur]
		if r != -1 and (result.is_empty() or result[result.size() - 1] != r):
			result.append(r)
	result.reverse()
	return result


## A* (Manhattan-Heuristik × minimale Schrittkosten) mit Abbiege-Strafe ⇒ überwiegend gerade bzw.
## L-förmige Gänge. Zustand = Zelle × Richtung. Leeres Array = kein Weg.
func _find_path(from: Vector2i, to: Vector2i) -> Array:
	var cells := W * H
	var states := cells * 4
	var cost := PackedFloat64Array()
	cost.resize(states)
	cost.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(states)
	prev.fill(-1)

	# Schrittkosten einmal pro Suche vorberechnen (0 = nicht begehbar).
	var corridor := PackedByteArray()
	corridor.resize(cells)
	for i in cells:
		corridor[i] = 1 if tiles[i] == MapModel.FLOOR and room_at[i] == -1 else 0
	var step := PackedFloat64Array()
	step.resize(cells)
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			if not (x == to.x and y == to.y) and (not _in_bounds(x, y) or _blocked(x, y)):
				continue
			if tiles[i] == MapModel.FLOOR:
				step[i] = 0.6
				continue
			var c := 1.0
			if corridor[i - W - 1] + corridor[i - W] + corridor[i - W + 1] + corridor[i - 1] + corridor[i + 1] + corridor[i + W - 1] + corridor[i + W] + corridor[i + W + 1] > 0:
				c += 3.0
			if room_at[i + 1] != -1 or room_at[i - 1] != -1 or room_at[i + W] != -1 or room_at[i - W] != -1:
				c += 1.5
			step[i] = c
	if to.x <= 0 or to.y <= 0 or to.x >= W - 1 or to.y >= H - 1:
		step[to.y * W + to.x] = 1.0

	# Binärer Min-Heap, inline für Geschwindigkeit: Zustände + Priorität (f = g + h).
	var heap_s := PackedInt32Array()
	var heap_p := PackedFloat64Array()
	var offsets := [1, W, -1, -W]
	var start_cell := from.y * W + from.x
	for d in 4:
		var s0 := start_cell * 4 + d
		cost[s0] = 0.0
		heap_s.append(s0)
		heap_p.append(0.0)
	var end_state := -1
	while heap_s.size() > 0:
		# pop
		var s := heap_s[0]
		var last := heap_s.size() - 1
		heap_s[0] = heap_s[last]
		heap_p[0] = heap_p[last]
		heap_s.resize(last)
		heap_p.resize(last)
		var i := 0
		while true:
			var l := 2 * i + 1
			if l >= last:
				break
			var m := l
			if l + 1 < last and heap_p[l + 1] < heap_p[l]:
				m = l + 1
			if heap_p[m] >= heap_p[i]:
				break
			var ts := heap_s[i]
			heap_s[i] = heap_s[m]
			heap_s[m] = ts
			var tp := heap_p[i]
			heap_p[i] = heap_p[m]
			heap_p[m] = tp
			i = m

		var cell := s >> 2
		if cell == to.y * W + to.x:
			end_state = s
			break
		var dir := s & 3
		var g := cost[s]
		for nd in 4:
			var ni: int = cell + offsets[nd]
			if ni < 0 or ni >= cells:
				continue
			var sc := step[ni]
			if sc == 0.0:
				continue
			var nc := g + sc + (0.0 if nd == dir else TURN_COST)
			var ns := ni * 4 + nd
			if nc < cost[ns]:
				cost[ns] = nc
				prev[ns] = s
				var f := nc + 0.6 * (absi(ni % W - to.x) + absi(ni / W - to.y))
				# push
				heap_s.append(ns)
				heap_p.append(f)
				var k := heap_s.size() - 1
				while k > 0:
					var pk := (k - 1) >> 1
					if heap_p[pk] <= heap_p[k]:
						break
					var ts2 := heap_s[k]
					heap_s[k] = heap_s[pk]
					heap_s[pk] = ts2
					var tp2 := heap_p[k]
					heap_p[k] = heap_p[pk]
					heap_p[pk] = tp2
					k = pk
	if end_state < 0:
		return []
	var path: Array = []
	var st := end_state
	while st != -1:
		var c2 := st >> 2
		path.append(Vector2i(c2 % W, c2 / W))
		st = prev[st]
	path.reverse()
	return path

