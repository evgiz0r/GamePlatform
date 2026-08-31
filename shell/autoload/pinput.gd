extends Node
## Input indirection. Game code must read input through PInput, never through Input
## directly -- that is what lets a bot play the game during a sim run using the exact
## same verbs a human uses. No special "bot mode" branches anywhere in game code.

var bot: Object = null              ## set by the sim runner; implements pressed(action)->bool

var _prev := {}
var _curr := {}

func _process(_d: float) -> void:
	_prev = _curr.duplicate()
	_curr.clear()
	for a in Controls.ACTIONS:
		_curr[a] = _raw(a)

func _raw(action: String) -> bool:
	if bot != null:
		return bot.pressed(action)
	return Input.is_action_pressed(action)

func pressed(action: String) -> bool:
	return _curr.get(action, false)

func just_pressed(action: String) -> bool:
	return _curr.get(action, false) and not _prev.get(action, false)

func just_released(action: String) -> bool:
	return _prev.get(action, false) and not _curr.get(action, false)

func axis(neg: String, pos: String) -> float:
	return (1.0 if pressed(pos) else 0.0) - (1.0 if pressed(neg) else 0.0)

## Normalized movement direction. The workhorse for most games.
func dir() -> Vector2:
	var v := Vector2(axis("move_left", "move_right"), axis("move_up", "move_down"))
	return v.normalized() if v.length() > 1.0 else v
