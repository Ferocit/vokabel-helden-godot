class_name Controls
extends RefCounted
## Tastenbelegung als Input-Actions (zur Laufzeit angelegt, damit project.godot schlank bleibt).
## Bewegung über physische Tasten (WASD liegt auf QWERTZ und QWERTY gleich).

const PHYSICAL := {
	"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
}
## Controller: Steuerkreuz und linker Stick bewegen, A interagiert, Start öffnet das Menü, Y das Inventar.
const JOY_BUTTONS := {
	"move_up": [JOY_BUTTON_DPAD_UP], "move_down": [JOY_BUTTON_DPAD_DOWN],
	"move_left": [JOY_BUTTON_DPAD_LEFT], "move_right": [JOY_BUTTON_DPAD_RIGHT],
	"interact": [JOY_BUTTON_A], "menu": [JOY_BUTTON_START], "inventory": [JOY_BUTTON_Y],
}
const JOY_AXES := {
	"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
}

const LOGICAL := {
	"interact": [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
	"menu": [KEY_ESCAPE],
	"inventory": [KEY_I],
}


static func ensure() -> void:
	for action: String in PHYSICAL:
		_add(action, PHYSICAL[action], true)
	for action: String in LOGICAL:
		_add(action, LOGICAL[action], false)
	for action: String in JOY_BUTTONS:
		if not _has_joy(action):
			for b: JoyButton in JOY_BUTTONS[action]:
				var ev := InputEventJoypadButton.new()
				ev.button_index = b
				InputMap.action_add_event(action, ev)
			if JOY_AXES.has(action):
				var m := InputEventJoypadMotion.new()
				m.axis = JOY_AXES[action][0]
				m.axis_value = JOY_AXES[action][1]
				InputMap.action_add_event(action, m)
				InputMap.action_set_deadzone(action, 0.3)


static func _has_joy(action: String) -> bool:
	return InputMap.action_get_events(action).any(func(e: InputEvent) -> bool: return e is InputEventJoypadButton)


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
