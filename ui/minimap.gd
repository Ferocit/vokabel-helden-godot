class_name Minimap
extends Control
## Ausschnitt der Karte um den Spieler; zeigt nur, was schon erkundet wurde.

const SIZE := 184
const CELL := 7.0
const REVEAL := 6

var explored := {}  # Kachelindex → true


func _ready() -> void:
	name = "Minimap"
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reveal_around(p: Vector2) -> void:
	var map: Dictionary = Ctx.run.map
	var px := floori(p.x)
	var py := floori(p.y)
	for y in range(py - REVEAL, py + REVEAL + 1):
		for x in range(px - REVEAL, px + REVEAL + 1):
			if MapModel.is_floor(map, x, y):
				explored[y * int(map.width) + x] = true
	queue_redraw()


func _draw() -> void:
	draw_style_box(UiTheme.box(Color(0.04, 0.055, 0.04, 0.78), UI.GOLD, 1, 6, Vector4.ZERO), Rect2(Vector2.ZERO, size))
	if not Ctx.has_run():
		return
	var run: Dictionary = Ctx.run
	var map: Dictionary = run.map
	var w := int(map.width)
	var p: Vector2 = run.player
	var origin := size / 2.0 - p * CELL
	for idx: int in explored:
		draw_rect(Rect2(origin + Vector2(idx % w, idx / w) * CELL, Vector2(CELL + 0.4, CELL + 0.4)), Color("#c9b48f"))
	for obj: Dictionary in map.objects:
		if not explored.has(int(obj.y) * w + int(obj.x)):
			continue
		if obj.kind == "enemy" and run.defeated.has(obj.id):
			continue
		var c: Color
		match obj.kind:
			"enemy":
				c = Color("#ff3c3c") if obj.tier != "normal" else Color("#ff8a6a")
			"chest":
				c = Color("#ffd75e")
			"door":
				c = Color("#8a5a2c")
			"bossDoor":
				c = Color("#c070ff")
			_:
				c = Color("#3ddc84")
		if obj.kind in ["chest", "door", "bossDoor"] and run.opened.has(obj.id):
			c = Color("#8a7a65")
		draw_rect(Rect2(origin + Vector2(obj.x, obj.y) * CELL + Vector2(1, 1), Vector2(CELL - 2, CELL - 2)), c)
	draw_circle(size / 2.0, 5.5, Color("#1a1030"))
	draw_circle(size / 2.0, 4.5, Color.WHITE)
