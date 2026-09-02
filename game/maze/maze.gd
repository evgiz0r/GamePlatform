extends GameMode
## maze -- watch a maze carve itself, then walk out of it. Solve one and the next one
## builds itself a little bigger, forever. See game/maze/GAME.md.
##
## You cannot move while it is generating; watching the thing build is half the point.

const MARGIN := 30.0
const FIRST_SIZE := 3
const MAX_SIZE := 15
const SFX_VOLUME := 0.28

## wall bits, one per side of a cell
const N := 1
const E := 2
const S := 4
const W := 8
const SIDE_DIR := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const SIDE_BIT := [N, E, S, W]

var _cols := FIRST_SIZE
var _rows := FIRST_SIZE
var _cell := 40.0
var _origin := Vector2.ZERO

var _walls: Array = []      ## _walls[y][x] -> bitmask of the walls still standing
var _seen: Array = []       ## _seen[y][x] -> carved yet?
var _stack: Array = []      ## the backtracker's path
var _building := true
var _build_acc := 0.0
var _build_rate := 30.0
var _ticks := 0

var _in := Vector2i.ZERO
var _out := Vector2i.ZERO
var _in_side := 3
var _out_side := 1

var player: Blob
var _goal: Blob
var _level := 0
var _flash := 0.0
var _target := Vector2.INF   ## where a tap asked us to run to
var _sfx_was := 0.8

func _ready() -> void:
	title = "maze"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = SFX_VOLUME

	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()

	set_lives(0)   # nothing can go wrong here; there is no fail state by design

	player = Blob.new()
	player.role = "player"
	player.radius = 5.0
	add_child(player)
	Probe.track(player, "@")

	_goal = Blob.new()
	_goal.role = "prize"
	_goal.radius = 6.0
	_goal.shape = "diamond"
	add_child(_goal)
	Probe.track(_goal, "*")

	_next_maze()

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- building the maze ----------------------------------------------------

func _next_maze() -> void:
	_level += 1
	var size := clampi(FIRST_SIZE + _level - 1, FIRST_SIZE, MAX_SIZE)
	_cols = size
	_rows = size
	_fit_to_screen()

	# Every wall up, nothing carved yet.
	_walls = []
	_seen = []
	for y in _rows:
		var wrow: Array = []
		var srow: Array = []
		for x in _cols:
			wrow.append(N | E | S | W)
			srow.append(false)
		_walls.append(wrow)
		_seen.append(srow)

	# "the out becomes the in": leaving by the right edge means arriving at the left of
	# the next one. The very first maze just picks a side.
	_in_side = (_out_side + 2) % 4 if _level > 1 else randi() % 4
	_out_side = _in_side
	while _out_side == _in_side:
		_out_side = randi() % 4
	_in = _random_border_cell(_in_side)
	_out = _random_border_cell(_out_side)

	_stack = [_in]
	_seen[_in.y][_in.x] = true
	_building = true
	_build_acc = 0.0
	_ticks = 0
	# bigger mazes carve faster, so the wait stays a couple of seconds either way
	_build_rate = maxf(14.0, float(_cols * _rows) / 2.2)

	player.position = _cell_centre(_in)
	_target = Vector2.INF
	player.visible = false
	# The marker sits OUT in the doorway rather than on the exit cell. Standing on the exit
	# is not finishing -- you have to walk through -- and a marker on the cell centre stops
	# anything aiming at it one step short, bots included.
	_goal.position = _cell_centre(_out) + Vector2(SIDE_DIR[_out_side]) * _cell * 0.8
	_goal.visible = false

	Probe.event("build_start", {"level": _level, "size": "%dx%d" % [_cols, _rows]})

## Cells are square and the whole maze is centred, so it always fits whatever it grows to.
func _fit_to_screen() -> void:
	var avail := play_area.size - Vector2(MARGIN, MARGIN) * 2.0
	_cell = floorf(minf(avail.x / float(_cols), avail.y / float(_rows)))
	var span := Vector2(_cols, _rows) * _cell
	_origin = play_area.position + (play_area.size - span) * 0.5

func _random_border_cell(side: int) -> Vector2i:
	match side:
		0: return Vector2i(randi() % _cols, 0)
		1: return Vector2i(_cols - 1, randi() % _rows)
		2: return Vector2i(randi() % _cols, _rows - 1)
		_: return Vector2i(0, randi() % _rows)

## One step of a recursive backtracker. Called many times a second so it is watchable.
func _build_step() -> void:
	if _stack.is_empty():
		_finish_build()
		return
	var here: Vector2i = _stack[-1]
	var options: Array = []
	for side in 4:
		var n: Vector2i = here + SIDE_DIR[side]
		if _inside(n) and not _seen[n.y][n.x]:
			options.append(side)
	if options.is_empty():
		_stack.pop_back()
		return
	var side: int = options[randi() % options.size()]
	var nxt: Vector2i = here + SIDE_DIR[side]
	_walls[here.y][here.x] &= ~SIDE_BIT[side]
	_walls[nxt.y][nxt.x] &= ~SIDE_BIT[(side + 2) % 4]
	_seen[nxt.y][nxt.x] = true
	_stack.append(nxt)
	_ticks += 1
	if _ticks % 5 == 0:
		Audio.play("click", 0.3, -14.0)

func _finish_build() -> void:
	# doorways in the outer wall, so you walk in and out rather than teleport
	_walls[_in.y][_in.x] &= ~SIDE_BIT[_in_side]
	_walls[_out.y][_out.x] &= ~SIDE_BIT[_out_side]
	_building = false
	player.visible = true
	_goal.visible = true
	Audio.play("impact_light")

	# A backtracker always produces a connected maze, so this should never fail -- which
	# is exactly why it is worth asserting. A silent unsolvable maze is unplayable and
	# the bots cannot tell us, so the game checks itself.
	var steps := _distance(_in, _out)
	if steps < 0:
		Probe.note("maze %d is unsolvable -- no path from the entrance to the exit" % _level)
	Probe.event("build_done", {"level": _level, "path": steps})

## Breadth-first, purely as a self-check. Returns -1 if the exit cannot be reached.
func _distance(from: Vector2i, to: Vector2i) -> int:
	var dist := {from: 0}
	var queue: Array = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			return dist[c]
		for side in 4:
			if _walls[c.y][c.x] & SIDE_BIT[side]:
				continue
			var n: Vector2i = c + SIDE_DIR[side]
			if _inside(n) and not dist.has(n):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	return -1

## ---- walking --------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	queue_redraw()
	if _flash > 0.0:
		_flash -= delta

	if _building:
		_build_acc += delta * _build_rate
		while _build_acc >= 1.0 and _building:
			_build_acc -= 1.0
			_build_step()
		return

	_walk(delta)

func _walk(delta: float) -> void:
	var dir := _wanted_direction()
	if dir == Vector2.ZERO:
		return

	var here := _cell_of(player.position)
	var before := player.position
	var speed := _cell * 4.2
	var target := player.position + dir * speed * delta
	var nxt := _cell_of(target)

	if nxt != here:
		if not _inside(nxt):
			# stepping off the board is only allowed through the exit doorway
			if here == _out and _side_towards(dir) == _out_side:
				_solved()
				return
			target = _stop_at_edge(here, dir)
		elif _walls[here.y][here.x] & SIDE_BIT[_side_towards(dir)]:
			target = _stop_at_edge(here, dir)

	player.position = target
	# slide back onto the middle of the corridor, so corners cannot be cut
	var mid := _cell_centre(here)
	if dir.x != 0.0:
		player.position.y = lerpf(player.position.y, mid.y, 14.0 * delta)
	else:
		player.position.x = lerpf(player.position.x, mid.x, 14.0 * delta)

	# ran into a wall on the way to a tapped spot: stop rather than grind against it
	if _target != Vector2.INF and player.position.distance_to(before) < 0.4:
		_target = Vector2.INF

## Keyboard and gamepad through PInput; pointer by tapping where you want to end up and
## running there. Either way the direction is locked to one axis, which is what makes it
## feel like running down a corridor rather than drifting about.
func _wanted_direction() -> Vector2:
	var d := PInput.dir()
	if d == Vector2.ZERO and _target != Vector2.INF:
		d = _target - player.position
		if d.length() < 5.0:
			_target = Vector2.INF
			return Vector2.ZERO
	if d == Vector2.ZERO:
		return Vector2.ZERO
	return Vector2(signf(d.x), 0.0) if absf(d.x) > absf(d.y) else Vector2(0.0, signf(d.y))

func _stop_at_edge(cell: Vector2i, dir: Vector2) -> Vector2:
	return _cell_centre(cell) + dir * (_cell * 0.5 - player.radius - 1.0)

func _solved() -> void:
	var points := 10 + _level * 5
	add_score(points)
	_flash = 0.6
	Juice.hit(5.0)
	Juice.text(self, player.position + Vector2(-14, -30), "+%d" % points, Palette.col("warn"))
	Audio.play("impact_bell")
	Audio.play("voice_level_up" if _level % 5 == 0 else "voice_correct")
	Probe.event("solved", {"level": _level})
	_next_maze()

func _input(event: InputEvent) -> void:
	if finished or _building or Flow.pointer_over_hud():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_target = get_global_mouse_position()

## ---- grid helpers ---------------------------------------------------------

func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _cols and c.y < _rows

func _cell_centre(c: Vector2i) -> Vector2:
	return _origin + (Vector2(c) + Vector2(0.5, 0.5)) * _cell

func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - _origin.x) / _cell), floori((p.y - _origin.y) / _cell))

func _side_towards(dir: Vector2) -> int:
	if dir.x > 0.0:
		return 1
	if dir.x < 0.0:
		return 3
	return 2 if dir.y > 0.0 else 0

## ---- drawing --------------------------------------------------------------

func _draw() -> void:
	var ink := Palette.col("ink")
	var dim := Palette.col("bg_alt")

	# carved ground, so the shape of the maze reads while it is still building
	for y in _rows:
		for x in _cols:
			if _seen[y][x]:
				draw_rect(Rect2(_origin + Vector2(x, y) * _cell, Vector2(_cell, _cell)), dim)

	if _building and not _stack.is_empty():
		var head: Vector2i = _stack[-1]
		draw_rect(Rect2(_origin + Vector2(head.x, head.y) * _cell,
			Vector2(_cell, _cell)), Palette.col("accent"))

	var thick := maxf(2.0, _cell * 0.09)
	for y in _rows:
		for x in _cols:
			var bits: int = _walls[y][x]
			var tl := _origin + Vector2(x, y) * _cell
			if bits & N:
				draw_line(tl, tl + Vector2(_cell, 0), ink, thick)
			if bits & W:
				draw_line(tl, tl + Vector2(0, _cell), ink, thick)
			if bits & S:
				draw_line(tl + Vector2(0, _cell), tl + Vector2(_cell, _cell), ink, thick)
			if bits & E:
				draw_line(tl + Vector2(_cell, 0), tl + Vector2(_cell, _cell), ink, thick)

	if not _building:
		_draw_doorway(_in, _in_side, Palette.col("friend"))
		_draw_doorway(_out, _out_side, Palette.col("prize"))

	var f: Font = ThemeDB.fallback_font
	var msg := "building %dx%d..." % [_cols, _rows] if _building else "get out"
	draw_string(f, Vector2(120, 22), msg, HORIZONTAL_ALIGNMENT_CENTER, 400, 14,
		Palette.col("accent"))
	draw_string(f, Vector2(120, 352), "maze %d" % _level, HORIZONTAL_ALIGNMENT_CENTER, 400,
		12, Palette.col("ink"))

## a stub of corridor poking out of the wall, so the way in and the way out are obvious
func _draw_doorway(cell: Vector2i, side: int, col: Color) -> void:
	var c := _cell_centre(cell)
	var d := Vector2(SIDE_DIR[side])
	draw_line(c + d * _cell * 0.5, c + d * _cell * 0.9, col, maxf(3.0, _cell * 0.12))
