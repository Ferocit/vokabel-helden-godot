class_name HeldWeapon
extends Sprite3D
## Die ausgerüstete Waffe in der Hand des Helden. Hängt als Kind am Helden-Sprite, spiegelt sich mit
## dessen Blickrichtung und schwingt beim Angriff. Maße in Pixeln der 16-px-Figur, damit es in der
## Erkundung (1 Einheit hoch) und im Kampf (2 Einheiten hoch) gleich aussieht.

## Hand der Figur: Pixel rechts von der Mitte und über dem Fußpunkt (Figur schaut nach rechts).
const HAND_PX := Vector2(5.0, 4.0)
## Griff in der Waffen-Kachel: Pixel unter der Kachelmitte.
const GRIP_PX := 4.0
## Waffe im Verhältnis zur Figur.
const SIZE := 0.62
## Ruhehaltung: Klinge leicht nach vorn geneigt.
const REST_DEG := -20.0
## Rarität → Schimmer (Licht an der Klinge).
const GLOW := {"rare": Color("#ffd75e")}

var item_id := ""
## Zusätzlicher Winkel beim Zuschlagen (Grad).
var swing_deg := 0.0
var _hero: Sprite3D


## Liefert null, wenn keine (bekannte) Waffe ausgerüstet ist.
static func create(id: Variant) -> HeldWeapon:
	if id == null or not GameData.has_item(id):
		return null
	var item := GameData.get_item(id)
	if item.slot != "weapon":
		return null
	var w := HeldWeapon.new()
	w.name = "Weapon"
	w.item_id = id
	w.texture = slim_texture(int(item.icon))
	w.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	w.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	w.double_sided = true
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	w.offset = Vector2(0, GRIP_PX)
	if GLOW.has(item.rarity):
		var l := OmniLight3D.new()
		l.light_color = GLOW[item.rarity]
		l.light_energy = 0.6
		l.omni_range = 1.2
		l.position = Vector3(0, 0.3, 0.2)
		w.add_child(l)
	return w


static var _slim := {}


## Die Kenney-Symbole haben einen 2 px breiten dunklen Rand – gut als Inventarsymbol, in der Hand wird die
## verkleinerte Klinge damit klobig. Hier wird die äußere Randschicht entfernt (1 px Rand bleibt).
static func slim_texture(frame_no: int) -> Texture2D:
	if _slim.has(frame_no):
		return _slim[frame_no]
	var src := Assets.frame_image(frame_no)
	var img := src.duplicate() as Image
	# Randfarbe = dunkelste deckende Farbe der Kachel.
	var outline := Color.WHITE
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a > 0.0 and c.get_luminance() < outline.get_luminance():
				outline = c
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a == 0.0 or not c.is_equal_approx(outline):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := Vector2i(x, y) + d
				if n.x < 0 or n.y < 0 or n.x >= src.get_width() or n.y >= src.get_height() or src.get_pixel(n.x, n.y).a == 0.0:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
					break
	var t := ImageTexture.create_from_image(img)
	_slim[frame_no] = t
	return t


## Hängt die ausgerüstete Waffe an `hero` (ersetzt eine vorhandene); liefert sie oder null.
static func equip(hero: Sprite3D, id: Variant) -> HeldWeapon:
	var old := hero.get_node_or_null("Weapon")
	if old != null:
		if old is HeldWeapon and (old as HeldWeapon).item_id == str(id):
			return old
		hero.remove_child(old)
		old.queue_free()
	var w := create(id)
	if w != null:
		hero.add_child(w)
	return w


func _ready() -> void:
	_hero = get_parent() as Sprite3D
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if _hero == null:
		return
	var px := _hero.pixel_size
	pixel_size = px * SIZE
	var side := -1.0 if _hero.flip_h else 1.0
	flip_h = _hero.flip_h
	# Leicht vor der Figur, damit die Waffe nicht hinter dem Körper verschwindet.
	position = Vector3(HAND_PX.x * px * side, HAND_PX.y * px, 0.3 * px)
	rotation = Vector3(0, 0, deg_to_rad(REST_DEG + swing_deg) * side)
	modulate = _hero.modulate


## Ausholen und zuschlagen; läuft als Tween am Helden, damit er mit ihm endet.
func swing(seconds: float = 0.24) -> void:
	var tw := create_tween()
	tw.tween_property(self, "swing_deg", 55.0, seconds * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "swing_deg", -95.0, seconds * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "swing_deg", 0.0, seconds * 0.6).set_trans(Tween.TRANS_SINE)
