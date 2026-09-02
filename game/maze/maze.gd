extends GameMode
## maze -- watch a maze carve itself, then get out. Solve one and the next one builds
## itself next door, a square bigger, forever. See game/maze/GAME.md.
##
## You cannot move while it is generating; watching the thing build is half the point.
## The mazes sit side by side in one world and the camera pans between them, so the one
## you just escaped is still on screen behind you.

## Every maze is the same size in world units whatever its cell count, so the camera never
## has to change zoom -- only slide. Cells just get smaller as the mazes get harder.
const SPAN := 300.0
const GAP := 45.0
const CAM_ZOOM := 0.62
const PAN_TIME := 0.9
const KEEP_PAST := 3

const FIRST_SIZE := 3
const MAX_SIZE := 12
const STEP_TIME := 0.085     ## seconds to cross one cell
const SFX_VOLUME := 0.28

const N := 1
const E := 2
const S := 4
const W := 8
const SIDE_DIR := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const SIDE_BIT := [N, E, S, W]

var _cols := FIRST_SIZE
var _rows := FIRST_SIZE
var _cell := SPAN / float(FIRST_SIZE)
var _origin := Vector2.ZERO
var _walls: Array = []
var _seen: Array = []
var _stack: Array = []
var _past: Array = []        ## the last few mazes, drawn faded behind you

var _building := true
var _build_acc := 0.0
var _build_rate := 30.0
var _ticks := 0

var _in := Vector2i.ZERO
var _out := Vector2i.ZERO
var _in_side := 3
var _out_side := 1

## The player lives on the grid. _pc is the cell it is IN; everything else is the
## animation between two cells. There is no free movement, so it can never end up
## half-way through a wall or drifting off the middle of a corridor.
var _pc := Vector2i.ZERO
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _step_t := 0.0
var _moving := false
var _leaving := false
var _goal := Vector2i(-999, -999)
var _run_axis := 0

var player: Blob
var _marker: Blob
var _cam: Camera2D
var _hud_top: Label
var _hud_bottom: Label
var _level := 0
var _sfx_was := 0.8

func _ready() -> void:
	title = "maze"
	# Deliberately far bigger than a screen. The camera pans across a whole plane of mazes,
	# and the shell's backdrop is sized from this -- leave it at 640x360 and the background
	# slides away the moment you leave the first maze. Probe.world_rect is narrowed to the
	# current maze in _next_maze(), so the playtest map still frames something useful.
	play_area = Rect2(-2500, -2500, 5000, 5000)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = SFX_VOLUME

	_cam = Camera2D.new()
	_cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
	add_child(_cam)
	_cam.make_current()

	set_lives(0)   # nothing can go wrong here; there is no fail state by design

	player = Blob.new()
	player.role = "player"
	add_child(player)
	Probe.track(player, "@")

	_marker = Blob.new()
	_marker.role = "prize"
	_marker.shape = "diamond"
	add_child(_marker)
	Probe.track(_marker, "*")

	# Text has to live in a CanvasLayer, not _draw(): the camera moves, and anything drawn
	# in world space would slide off screen with it.
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_top = UIKit.label("", 14, "accent")
	_hud_top.position = Vector2(120, 14)
	_hud_top.size = Vector2(400, 20)
	layer.add_child(_hud_top)
	_hud_bottom = UIKit.label("", 12, "ink")
	_hud_bottom.position = Vector2(120, 336)
	_hud_bottom.size = Vector2(400, 20)
	layer.add_child(_hud_bottom)

	_next_maze()

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- building -------------------------------------------------------------

func _next_maze() -> void:
	var prev_origin := _origin
	var prev_cell := _cell
	var prev_out := _out
	var prev_side := _out_side

	if _level > 0:
		_past.append({"walls": _walls, "cols": _cols, "rows": _rows,
			"origin": _origin, "cell": _cell})
		while _past.size() > KEEP_PAST:
			_past.pop_front()

	_level += 1
	var size := clampi(FIRST_SIZE + _level - 1, FIRST_SIZE, MAX_SIZE)
	_cols = size
	_rows = size
	_cell = SPAN / float(size)

	if _level == 1:
		_origin = Vector2.ZERO
		_in_side = randi() % 4
		_in = _random_border_cell(_in_side)
	else:
		# the next maze sits next door, on the side you left by
		_origin = prev_origin + Vector2(SIDE_DIR[prev_side]) * (SPAN + GAP)
		_in_side = (prev_side + 2) % 4
		_in = _aligned_in_cell(prev_origin, prev_cell, prev_out)

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

	_stack = [_in]
	_seen[_in.y][_in.x] = true
	_building = true
	_build_acc = 0.0
	_ticks = 0
	_build_rate = maxf(16.0, float(_cols * _rows) / 2.2)

	_pc = _in
	_moving = false
	_leaving = false
	_goal = Vector2i(-999, -999)
	player.radius = maxf(3.0, _cell * 0.2)
	_marker.radius = maxf(3.5, _cell * 0.22)
	player.position = _cell_centre(_in)
	player.visible = false
	_marker.visible = false

	# so the ASCII map in a playtest report frames the maze we are actually in
	Probe.world_rect = Rect2(_origin, Vector2(SPAN, SPAN)).grow(GAP)

	var tw := create_tween()
	tw.tween_property(_cam, "position", _origin + Vector2(SPAN, SPAN) * 0.5,
		PAN_TIME if _level > 1 else 0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	Probe.event("build_start", {"level": _level, "size": "%dx%d" % [_cols, _rows]})

## Line the new entrance up with the exit you just walked out of, so the two doorways face
## each other across the gap instead of being joined by an invisible jump.
func _aligned_in_cell(p_origin: Vector2, p_cell: float, p_out: Vector2i) -> Vector2i:
	var world := p_origin + (Vector2(p_out) + Vector2(0.5, 0.5)) * p_cell
	match _in_side:
		0: return Vector2i(_nearest_index(world.x - _origin.x), 0)
		1: return Vector2i(_cols - 1, _nearest_index(world.y - _origin.y))
		2: return Vector2i(_nearest_index(world.x - _origin.x), _rows - 1)
		_: return Vector2i(0, _nearest_index(world.y - _origin.y))

func _nearest_index(offset: float) -> int:
	return clampi(int(floorf(offset / _cell)), 0, _cols - 1)

func _random_border_cell(side: int) -> Vector2i:
	match side:
		0: return Vector2i(randi() % _cols, 0)
		1: return Vector2i(_cols - 1, randi() % _rows)
		2: return Vector2i(randi() % _cols, _rows - 1)
		_: return Vector2i(0, randi() % _rows)

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
	_walls[_in.y][_in.x] &= ~SIDE_BIT[_in_side]
	var dist := _dist_from_in()
	_pick_far_exit(dist)
	_walls[_out.y][_out.x] &= ~SIDE_BIT[_out_side]

	_building = false
	player.visible = true
	_marker.visible = true
	_marker.position = _cell_centre(_out) + Vector2(SIDE_DIR[_out_side]) * _cell * 0.8
	Audio.play("impact_light")

	var steps: int = int(dist.get(_out, -1))
	if steps < 0:
		Probe.note("maze %d is unsolvable -- no path from the entrance to the exit" % _level)
	Probe.event("build_done", {"level": _level, "path": steps})

## The exit is the border cell FURTHEST from the entrance by actual corridor distance, not
## a random one. A random exit was often a couple of steps away, which made the maze
## pointless -- you want the long way round to be the only way.
func _pick_far_exit(dist: Dictionary) -> void:
	var best := -1
	var best_cell := _in
	var best_side := (_in_side + 2) % 4
	for side in 4:
		if side == _in_side:
			continue
		for i in _cols:
			var c: Vector2i = _border_cell(side, i)
			if c == _in:
				continue
			var d: int = int(dist.get(c, -1))
			if d > best:
				best = d
				best_cell = c
				best_side = side
	_out = best_cell
	_out_side = best_side

func _border_cell(side: int, i: int) -> Vector2i:
	match side:
		0: return Vector2i(i, 0)
		1: return Vector2i(_cols - 1, i)
		2: return Vector2i(i, _rows - 1)
		_: return Vector2i(0, i)

func _dist_from_in() -> Dictionary:
	var dist := {_in: 0}
	var queue: Array = [_in]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for side in 4:
			if _walls[c.y][c.x] & SIDE_BIT[side]:
				continue
			var n: Vector2i = c + SIDE_DIR[side]
			if _inside(n) and not dist.has(n):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	return dist

## ---- walking on the grid --------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	queue_redraw()
	_hud_top.text = "building %dx%d..." % [_cols, _rows] if _building else "get out"
	_hud_bottom.text = "maze %d" % _level

	if _building:
		_build_acc += delta * _build_rate
		while _build_acc >= 1.0 and _building:
			_build_acc -= 1.0
			_build_step()
		return

	if _moving:
		_step_t += delta / STEP_TIME
		if _step_t < 1.0:
			player.position = _from.lerp(_to, _step_t)
			return
		player.position = _to
		_moving = false
		if _leaving:
			_solved()
			return
		_pc = _step_target

	var d := _wanted_step()
	if d != Vector2i.ZERO:
		_begin_step(d)

var _step_target := Vector2i.ZERO

## One cell at a time, always axis-locked. A tap picks the axis once and the player runs
## down that line until it reaches the tapped row or column, or a wall stops it.
func _wanted_step() -> Vector2i:
	var k := PInput.dir()
	if k != Vector2.ZERO:
		_goal = Vector2i(-999, -999)
		if absf(k.x) > absf(k.y):
			return Vector2i(1 if k.x > 0.0 else -1, 0)
		return Vector2i(0, 1 if k.y > 0.0 else -1)
	if _goal.x == -999:
		return Vector2i.ZERO
	if _run_axis == 0:
		if _pc.x == _goal.x:
			_goal = Vector2i(-999, -999)
			return Vector2i.ZERO
		return Vector2i(1 if _goal.x > _pc.x else -1, 0)
	if _pc.y == _goal.y:
		_goal = Vector2i(-999, -999)
		return Vector2i.ZERO
	return Vector2i(0, 1 if _goal.y > _pc.y else -1)

func _begin_step(d: Vector2i) -> void:
	var side := _side_of(d)
	var nxt := _pc + d
	if not _inside(nxt):
		if _pc == _out and side == _out_side:
			_from = player.position
			_to = _cell_centre(_pc) + Vector2(d) * _cell
			_step_target = nxt
			_step_t = 0.0
			_moving = true
			_leaving = true
		else:
			_goal = Vector2i(-999, -999)
		return
	if _walls[_pc.y][_pc.x] & SIDE_BIT[side]:
		_goal = Vector2i(-999, -999)   # a wall: stop rather than grind against it
		return
	_from = _cell_centre(_pc)
	_to = _cell_centre(nxt)
	_step_target = nxt
	_step_t = 0.0
	_moving = true

func _solved() -> void:
	var points := 10 + _level * 5
	add_score(points)
	Juice.hit(5.0)
	Juice.text(self, player.position + Vector2(-14, -30), "+%d" % points, Palette.col("warn"))
	Audio.play("impact_bell")
	Audio.play("voice_level_up" if _level % 5 == 0 else "voice_correct")
	Probe.event("solved", {"level": _level})
	_next_maze()

func _input(event: InputEvent) -> void:
	if finished or _building or Flow.pointer_over_hud():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var rel := (get_global_mouse_position() - _origin) / _cell
	var tc := Vector2i(int(floorf(rel.x)), int(floorf(rel.y)))
	var away := tc - _pc
	if away == Vector2i.ZERO:
		return
	_run_axis = 0 if absi(away.x) >= absi(away.y) else 1
	_goal = tc

## ---- grid helpers ---------------------------------------------------------

func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _cols and c.y < _rows

func _cell_centre(c: Vector2i) -> Vector2:
	return _origin + (Vector2(c) + Vector2(0.5, 0.5)) * _cell

func _side_of(d: Vector2i) -> int:
	if d.x > 0:
		return 1
	if d.x < 0:
		return 3
	return 2 if d.y > 0 else 0

## ---- drawing --------------------------------------------------------------

func _draw() -> void:
	for m in _past:
		_draw_maze(m["walls"], m["cols"], m["rows"], m["origin"], m["cell"], 0.3)
	_draw_maze(_walls, _cols, _rows, _origin, _cell, 1.0)

	if _building and not _stack.is_empty():
		var head: Vector2i = _stack[-1]
		draw_rect(Rect2(_origin + Vector2(head) * _cell, Vector2(_cell, _cell)),
			Palette.col("accent"))
	if not _building:
		_draw_doorway(_in, _in_side, Palette.col("friend"))
		_draw_doorway(_out, _out_side, Palette.col("prize"))

func _draw_maze(walls: Array, cols: int, rows: int, origin: Vector2, cell: float,
		alpha: float) -> void:
	var c := Palette.col("ink")
	var ink := Color(c.r, c.g, c.b, alpha)
	var g := Palette.col("bg_alt")
	var ground := Color(g.r, g.g, g.b, alpha)
	var thick := maxf(1.5, cell * 0.1)
	for y in rows:
		for x in cols:
			var tl := origin + Vector2(x, y) * cell
			draw_rect(Rect2(tl, Vector2(cell, cell)), ground)
			var bits: int = walls[y][x]
			if bits & N:
				draw_line(tl, tl + Vector2(cell, 0), ink, thick)
			if bits & W:
				draw_line(tl, tl + Vector2(0, cell), ink, thick)
			if bits & S:
				draw_line(tl + Vector2(0, cell), tl + Vector2(cell, cell), ink, thick)
			if bits & E:
				draw_line(tl + Vector2(cell, 0), tl + Vector2(cell, cell), ink, thick)

func _draw_doorway(cell: Vector2i, side: int, col: Color) -> void:
	var c := _cell_centre(cell)
	var d := Vector2(SIDE_DIR[side])
	draw_line(c + d * _cell * 0.5, c + d * _cell * 1.1, col, maxf(2.5, _cell * 0.14))
