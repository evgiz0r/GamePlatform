class_name SimBot extends RefCounted
## A bot that plays the game through the SAME verbs a human uses (PInput). Game code has
## no idea a bot is playing -- there are no "if simulating" branches anywhere.
##
## The bot perceives the world through Probe's tracked symbols, i.e. exactly the same
## view the AI reads in the report. If the bot can't find the player, neither can the AI,
## and that itself is a useful finding.

var policy := "smart"
var _dir := Vector2.ZERO
var _jump := false
var _frame := -1
var _wander := Vector2.RIGHT

func pressed(action: String) -> bool:
	_recompute()
	match action:
		"move_left":  return _dir.x < -0.25
		"move_right": return _dir.x > 0.25
		"move_up":    return _dir.y < -0.25
		"move_down":  return _dir.y > 0.25
		"action_a":   return _jump
		_: return false

func _recompute() -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return
	_frame = f

	var me := Probe.first_with("@")
	if me == null:
		_dir = Vector2.ZERO
		return
	var here: Vector2 = me.global_position

	match policy:
		"idle":
			_dir = Vector2.ZERO
			_jump = false
		"random":
			if f % 20 == 0:
				_wander = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			_dir = _wander
			_jump = (f % 45 == 0)
		"seek":
			_dir = _toward(here, "*")
			_jump = false
		"avoid":
			_dir = -_toward(here, "x")
			_jump = (f % 30 == 0)
		_:
			# "smart": dodge anything close, otherwise go shopping
			var threat := Probe.nearest(here, "x")
			if threat != null and here.distance_to(threat.global_position) < 90.0:
				_dir = (here - threat.global_position).normalized()
			else:
				var want := _toward(here, "*")
				_dir = want if want != Vector2.ZERO else _wander
				if f % 20 == 0 and want == Vector2.ZERO:
					_wander = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			_jump = (f % 25 == 0)

func _toward(here: Vector2, sym: String) -> Vector2:
	var n := Probe.nearest(here, sym)
	if n == null:
		return Vector2.ZERO
	return (n.global_position - here).normalized()
