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
var _last_x := -9999.0
var _stall := 0.0

## Button presses MUST be pulsed, never held. A bot that holds a button down triggers
## just_pressed() exactly once and then never again, so a platformer looks like it has a
## broken jump when the bug is really in the bot. Everything that maps to a discrete
## action goes through here.
func _pulse(want: bool, f: int, period: int = 14, hold: int = 2) -> bool:
	return want and (f % period) < hold

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
			_jump = _pulse(true, f, 45, 2)
		"runner":
			# platformers: run right, and jump when the ground runs out ahead.
			# Ground is sensed through the "#" markers a game tracks for its platforms,
			# so a game that does not track its geometry gets a bot that walks off cliffs
			# -- which is itself the finding.
			_dir = Vector2.RIGHT
			if absf(here.x - _last_x) < 0.6:
				_stall += 1.0
			else:
				_stall = 0.0
			_last_x = here.x

			var foot := here + Vector2(26, 18)
			var ground := Probe.nearest(foot, "#")
			var gap_ahead: bool = ground == null or foot.distance_to(ground.global_position) > 22.0

			var blocked: bool = _stall > 5.0
			_jump = _pulse(gap_ahead or blocked, f, 10, 2)
		"gunner":
			# shooters: line up horizontally with the nearest threat and hold fire
			var tgt := Probe.nearest(here, "x")
			if tgt != null:
				var dx: float = tgt.global_position.x - here.x
				_dir = Vector2(signf(dx) if absf(dx) > 4.0 else 0.0, 0.0)
			else:
				if f % 30 == 0:
					_wander = Vector2(randf_range(-1, 1), 0)
				_dir = _wander
			_jump = _pulse(true, f, 8, 4)
		"seek":
			_dir = _toward(here, "*")
			_jump = false
		"avoid":
			_dir = -_toward(here, "x")
			_jump = _pulse(true, f, 30, 2)
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
			_jump = _pulse(true, f, 25, 2)

func _toward(here: Vector2, sym: String) -> Vector2:
	var n := Probe.nearest(here, sym)
	if n == null:
		return Vector2.ZERO
	return (n.global_position - here).normalized()
