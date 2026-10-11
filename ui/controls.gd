class_name Controls
extends RefCounted
## Tastenbelegung als Input-Actions (zur Laufzeit angelegt, damit project.godot schlank bleibt).
## Bewegung über physische Tasten (WASD liegt auf QWERTZ und QWERTY gleich).

const PHYSICAL := {
	"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
}
const LOGICAL := {
	"interact": [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
	"menu": [KEY_ESCAPE],
}


static func ensure() -> void:
	for action: String in PHYSICAL:
		_add(action, PHYSICAL[action], true)
	for action: String in LOGICAL:
		_add(action, LOGICAL[action], false)


static func _add(action: String, keys: Array, physical: bool) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k: Key in keys:
		var ev := InputEventKey.new()
		if physical:
			ev.physical_keycode = k
		else:
			ev.keycode = k
		InputMap.action_add_event(action, ev)
