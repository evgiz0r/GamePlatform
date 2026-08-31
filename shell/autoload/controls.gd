extends Node
## Input actions are registered in CODE (not the editor input map) so every game in this
## kit gets the same verbs on keyboard + gamepad with zero setup, and so a bot can drive
## them during a sim run.
##
## Verbs: move_left move_right move_up move_down action_a action_b pause restart

const ACTIONS := {
	"move_left":  {"keys": [KEY_A, KEY_LEFT],      "pad": [JOY_BUTTON_DPAD_LEFT]},
	"move_right": {"keys": [KEY_D, KEY_RIGHT],     "pad": [JOY_BUTTON_DPAD_RIGHT]},
	"move_up":    {"keys": [KEY_W, KEY_UP],        "pad": [JOY_BUTTON_DPAD_UP]},
	"move_down":  {"keys": [KEY_S, KEY_DOWN],      "pad": [JOY_BUTTON_DPAD_DOWN]},
	"action_a":   {"keys": [KEY_SPACE, KEY_J],     "pad": [JOY_BUTTON_A]},
	"action_b":   {"keys": [KEY_SHIFT, KEY_K],     "pad": [JOY_BUTTON_X]},
	"pause":      {"keys": [KEY_ESCAPE, KEY_P],    "pad": [JOY_BUTTON_START]},
	"restart":    {"keys": [KEY_R, KEY_ENTER],     "pad": [JOY_BUTTON_Y]},
}

## Left stick also drives the move_* actions.
const STICK := {
	"move_left":  [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X,  1.0],
	"move_up":    [JOY_AXIS_LEFT_Y, -1.0],
	"move_down":  [JOY_AXIS_LEFT_Y,  1.0],
}

func _enter_tree() -> void:
	for action_name in ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name, 0.35)
		for code in ACTIONS[action_name]["keys"]:
			var k := InputEventKey.new()
			k.physical_keycode = code
			InputMap.action_add_event(action_name, k)
		for btn in ACTIONS[action_name]["pad"]:
			var jb := InputEventJoypadButton.new()
			jb.button_index = btn
			InputMap.action_add_event(action_name, jb)
		if STICK.has(action_name):
			var jm := InputEventJoypadMotion.new()
			jm.axis = STICK[action_name][0]
			jm.axis_value = STICK[action_name][1]
			InputMap.action_add_event(action_name, jm)
