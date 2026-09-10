extends GameMode
## maze -- watch a maze carve itself, then get out. See game/maze/GAME.md.
##
## Two modes, picked on the game's own first screen:
##
##   classic   solve one, and the next one builds itself next door, a square bigger,
##             forever. The mazes sit side by side in one world and the camera pans
##             between them, so the one you just escaped is still on screen behind you.
##
##   infinite  mazes inside mazes. A bigger maze is planned up front (one square bigger
##             than the ones you play) and every one of its cells is a small maze. You
##             play the small ones in the order the big one was carved, each one's
##             doorways lined up with the big corridors, so filling the grid BUILDS the
##             big maze around you. When the last cell is done the camera zooms out and
##             you play the big one at regular size, with all the small ones still drawn
##             inside it. Solve that and it shrinks to become the first cell of the next
##             big one, a square bigger again, forever.
##
## You cannot move while a maze is generating; watching the thing build is half the point.

## Every maze you play is the same size in world units whatever its cell count, so the
## camera never has to change zoom -- only slide. Cells just get smaller as the mazes get
## harder. The one exception is infinite mode's zoom-out, and even that snaps back to this
## zoom the moment it lands: the world is rescaled instead (see _inf_play_big).
const SPAN := 300.0
const GAP := 45.0
const CAM_ZOOM := 0.62
const PAN_TIME := 0.9
const ZOOM_TIME := 2.2
const KEEP_PAST := 3          ## classic: how many escaped mazes stay drawn behind you

const FIRST_SIZE := 3
const MAX_SIZE := 12
const STEP_TIME := 0.085     ## seconds to cross one cell
## Fraction of whatever the menu's volume knob is set to, not an absolute level --
## a game that hard-set this ignored the menu control entirely. 0.35 matches the old
## fixed 0.28 at the shipped default (0.8), so nothing sounds different if the knob
## has never been touched.
const SFX_SCALE := 0.35

const N := 1
const E := 2
const S := 4
const W := 8
const SIDE_DIR := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const SIDE_BIT := [N, E, S, W]
const NO_GOAL := Vector2i(-999, -999)
const NO_CELL := Vector2i(-1, -1)

## "" while the mode picker is up, then "classic" or "infinite".
var _mode := ""

## ---- the maze being played right now ----------------------------------------
var _cols := FIRST_SIZE
var _rows := FIRST_SIZE
var _cell := SPAN / float(FIRST_SIZE)
var _origin := Vector2.ZERO
var _walls: Array = []
var _seen: Array = []
var _stack: Array = []
## Every maze already escaped, in every mode, oldest first. Drawn faded by the static
## layer; classic keeps the last few, infinite keeps them all (they only get smaller).
var _done: Array = []

var _building := true
var _build_acc := 0.0
var _build_rate := 30.0
var _ticks := 0

var _in := Vector2i.ZERO
var _out := Vector2i.ZERO
var _in_side := 3
var _out_side := 1
## Which sides the exit may be picked on. Classic: any side but the entrance's. Infinite:
## exactly the side the big maze's corridor leaves this cell by.
var _out_sides: Array = [0, 1, 2]

## The player lives on the grid. _pc is the cell it is IN; everything else is the
## animation between two cells. There is no free movement, so it can never end up
## half-way through a wall or drifting off the middle of a corridor.
var _pc := Vector2i.ZERO
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _step_t := 0.0
var _moving := false
var _leaving := false
var _goal := NO_GOAL
var _run_axis := 0
var _step_target := Vector2i.ZERO

## Auto-solve. A real depth-first search walked one cell at a time: it only ever knows the
## walls of cells it has actually stood in, takes the opening that heads most towards the
## exit, and reverses back out of dead ends. On a maze with no loops -- which a recursive
## backtracker always produces -- that is guaranteed to find the way out.
var _auto := false
var _known := {}        ## cells the solver has stood in
var _route: Array = []  ## its stack: entrance -> where it is now

## ---- infinite mode -------------------------------------------------------------
var _stage := 0
var _small := FIRST_SIZE        ## cell count of the mazes being played
var _big := FIRST_SIZE + 1      ## cell count of the maze they are building
var _phase := "small"           ## small | zoom | big
var _big_origin := Vector2.ZERO ## top-left of the big maze; its cells are SPAN wide
var _bwalls: Array = []         ## the preplanned big maze
var _order: Array = []          ## its cells in the order they were carved = play order
var _bidx := 0                  ## which of those is being played
var _bin := Vector2i.ZERO
var _bout := Vector2i.ZERO
var _bin_side := 0
var _bout_side := 0
var _cell_in_side := {}         ## big cell -> side its small maze is entered by
var _cell_kids := {}            ## big cell -> sides the carving left it by, in order
var _cell_rec := {}             ## big cell -> its finished small maze (a _record)
var _prev_cell := NO_CELL       ## the big cell just finished, for doorway continuity
var _exit_open := false         ## has the big one's way out been cut yet
var _door_flash := {}           ## a doorway just cut, lit up for a moment
var _big_done_pts := PackedVector2Array()  ## finished cells' border walls, big units

var player: Blob
var _marker: Blob
var _cam: Camera2D
var _cam_tw: Tween
var _last_cam_pos := Vector2.INF
var _last_cam_zoom := 0.0
var _static: Node2D     ## escaped mazes + the big plan; redrawn only when something changes
var _live: Node2D       ## the maze being played; redrawn every frame
var _hud_top: Label
var _hud_bottom: Label
var _solve_btn: Button
var _picker: Array = []     ## the mode screen's controls, freed once a mode is picked
var _pick_btns: Array = []
var _pick_idx := 0
var _level := 0             ## mazes started so far, in either mode
var _sfx_was := 0.8

func _ready() -> void:
	title = "maze"
	# Deliberately far bigger than a screen. The camera pans across a whole plane of mazes,
	# and the shell's backdrop is sized from this -- leave it at 640x360 and the background
	# slides away the moment you leave the first maze. Probe.world_rect is narrowed to the
	# current maze in _begin_build(), so the playtest map still frames something useful.
	play_area = Rect2(-2500, -2500, 5000, 5000)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE

	_cam = Camera2D.new()
	_cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
	add_child(_cam)
	_cam.make_current()

	set_lives(0)   # nothing can go wrong here; there is no fail state by design

	# Two drawing layers under the actors. The static one holds every maze already
	# escaped -- hundreds of them in infinite mode -- and only redraws when the list or
	# the camera changes, which is what keeps the frame cheap. Their wall geometry is
	# cached in unit cells and drawn through a transform, so a maze costs two calls
	# however many cells it has.
	_static = Node2D.new()
	_static.draw.connect(_draw_static)
	add_child(_static)
	_live = Node2D.new()
	_live.draw.connect(_draw_live)
	add_child(_live)

	player = Blob.new()
	player.role = "player"
	player.visible = false
	add_child(player)
	Probe.track(player, "@")

	_marker = Blob.new()
	_marker.role = "prize"
	_marker.shape = "diamond"
	_marker.visible = false
	add_child(_marker)
	Probe.track(_marker, "*")

	# Text has to live in a CanvasLayer, not _draw(): the camera moves, and anything drawn
	# in world space would slide off screen with it.
	var layer := CanvasLayer.new()
	# Above the shell's own HUD layer (10). Flow's full-screen Control sits there on
	# MOUSE_FILTER_PASS and takes the click first, so a button on a lower layer looks
	# present and is simply not clickable.
	layer.layer = 20
	add_child(layer)
	_hud_top = UIKit.label("", 14, "accent")
	_hud_top.position = Vector2(120, 14)
	_hud_top.size = Vector2(400, 20)
	layer.add_child(_hud_top)
	_hud_bottom = UIKit.label("", 12, "ink")
	_hud_bottom.position = Vector2(120, 336)
	_hud_bottom.size = Vector2(400, 20)
	layer.add_child(_hud_bottom)
	_solve_btn = UIKit.button("solve", _toggle_auto)
	_solve_btn.custom_minimum_size = Vector2(62, 22)
	_solve_btn.size = Vector2(62, 22)
	_solve_btn.position = Vector2(10, 330)
	_solve_btn.add_theme_font_size_override("font_size", 12)
	_solve_btn.visible = false
	layer.add_child(_solve_btn)

	# The playtest bots cannot read a menu, so a playtest skips it: MAZE_MODE=infinite in
	# the environment picks the other mode, anything else means classic. MAZE_MODE=menu
	# keeps the picker up anyway, which is how it gets screenshotted.
	var forced := OS.get_environment("MAZE_MODE")
	if Probe.enabled and forced != "menu":
		_choose("infinite" if forced == "infinite" else "classic")
	else:
		_build_picker(layer)

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- mode picker ------------------------------------------------------------

func _build_picker(layer: CanvasLayer) -> void:
	var t := UIKit.label("maze", 30, "accent")
	t.position = Vector2(120, 60)
	t.size = Vector2(400, 40)
	layer.add_child(t)
	_picker.append(t)
	var modes := [
		["classic", "one after another, each a square bigger"],
		["infinite", "mazes inside mazes: fill the grid, zoom out, play the big one"],
	]
	for i in modes.size():
		var m: Array = modes[i]
		var b := UIKit.button(m[0], _choose.bind(m[0]))
		b.custom_minimum_size = Vector2(200, 36)
		b.size = Vector2(200, 36)
		b.position = Vector2(220, 130 + i * 80)
		layer.add_child(b)
		_picker.append(b)
		_pick_btns.append(b)
		var l := UIKit.label(m[1], 11, "ink")
		l.position = Vector2(90, 170 + i * 80)
		l.size = Vector2(460, 18)
		layer.add_child(l)
		_picker.append(l)
	var hint := UIKit.label("up / down + space, or tap one", 11, "friend")
	hint.position = Vector2(120, 300)
	hint.size = Vector2(400, 18)
	layer.add_child(hint)
	_picker.append(hint)
	_pick_idx = 0
	_pick_btns[0].grab_focus()

func _picker_input() -> void:
	if _pick_btns.is_empty():
		return
	if PInput.just_pressed("move_down") or PInput.just_pressed("move_up"):
		_pick_idx = (_pick_idx + 1) % _pick_btns.size()
		_pick_btns[_pick_idx].grab_focus()
		Audio.play("click", 0.5, -10.0)
	if PInput.just_pressed("action_a"):
		_choose("classic" if _pick_idx == 0 else "infinite")

func _choose(mode: String) -> void:
	if _mode != "":
		return
	_mode = mode
	for n in _picker:
		n.queue_free()
	_picker = []
	_pick_btns = []
	_solve_btn.visible = true
	Audio.play("select")
	Probe.event("mode", {"mode": mode})
	if mode == "classic":
		_next_maze()
	else:
		_inf_begin()

## ---- building -------------------------------------------------------------

## Classic: the next maze sits next door, on the side you left by, one square bigger.
func _next_maze() -> void:
	var prev_origin := _origin
	var prev_cell := _cell
	var prev_out := _out
	var prev_side := _out_side

	if _level > 0:
		_done.append(_record(true))
		while _done.size() > KEEP_PAST:
			_done.pop_front()
		_static.queue_redraw()

	var size := clampi(FIRST_SIZE + _level, FIRST_SIZE, MAX_SIZE)
	_cols = size
	_rows = size
	_cell = SPAN / float(size)

	if _level == 0:
		_origin = Vector2.ZERO
		_in_side = randi() % 4
		_in = _random_border_cell(_in_side)
	else:
		_origin = prev_origin + Vector2(SIDE_DIR[prev_side]) * (SPAN + GAP)
		_in_side = (prev_side + 2) % 4
		_in = _aligned_in_cell(prev_origin, prev_cell, prev_out)
	_out_sides = _sides_except(_in_side)
	_begin_build(PAN_TIME if _level > 0 else 0.0)

## Everything both modes share once the new maze's size, place and entrance are known:
## an all-walls grid, the carving stack, a hidden player, and the camera on its way.
func _begin_build(pan_time: float) -> void:
	_level += 1
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

	_reset_walker()
	player.visible = false
	_marker.visible = false

	# so the ASCII map in a playtest report frames the maze we are actually in
	Probe.world_rect = Rect2(_origin, Vector2(SPAN, SPAN)).grow(GAP)
	_pan_to(_origin + Vector2(SPAN, SPAN) * 0.5, pan_time)
	Probe.event("build_start", {"level": _level, "size": "%dx%d" % [_cols, _rows]})

func _reset_walker() -> void:
	_pc = _in
	_moving = false
	_leaving = false
	_goal = NO_GOAL
	_known = {}
	_route = []
	player.radius = maxf(3.0, _cell * 0.2)
	_marker.radius = maxf(3.5, _cell * 0.22)
	player.position = _cell_centre(_in)

func _pan_to(where: Vector2, time: float) -> void:
	if _cam_tw != null and _cam_tw.is_valid():
		_cam_tw.kill()
	_cam_tw = create_tween()
	_cam_tw.tween_property(_cam, "position", where, time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## A finished maze, as the static layer draws it. `ground` is false for a maze that has
## other mazes drawn inside it (infinite mode's big ones): its floor would paint over them.
func _record(ground: bool) -> Dictionary:
	return {"walls": _walls, "cols": _cols, "rows": _rows, "origin": _origin,
		"cell": _cell, "in": _in, "pts": _wall_pts(_walls, _cols, _rows), "ground": ground}

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
	return _border_cell(side, randi() % _cols, _cols)

func _sides_except(side: int) -> Array:
	var out: Array = []
	for s in 4:
		if s != side:
			out.append(s)
	return out

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
	var dist := _grid_dist(_walls, _cols, _rows, _in)
	if _out_sides.is_empty():
		# no way out at all (a dead end of infinite mode's big maze): the goal is the
		# cell furthest in, and the prize sits on it
		_out = _in
		_out_side = -1
		var best := -1
		for c in dist:
			if int(dist[c]) > best:
				best = int(dist[c])
				_out = c
		_marker.position = _cell_centre(_out)
	else:
		var far := _far_border(_cols, _in, dist, _out_sides)
		_out = far[0]
		_out_side = far[1]
		_walls[_out.y][_out.x] &= ~SIDE_BIT[_out_side]
		_marker.position = _cell_centre(_out) + Vector2(SIDE_DIR[_out_side]) * _cell * 0.8

	_building = false
	player.visible = true
	_marker.visible = true
	Audio.play("impact_light")

	var steps: int = int(dist.get(_out, -1))
	if steps < 0:
		Probe.note("maze %d is unsolvable -- no path from the entrance to the exit" % _level)
	Probe.event("build_done", {"level": _level, "path": steps})

## The exit is the border cell FURTHEST from the entrance by actual corridor distance, not
## a random one. A random exit was often a couple of steps away, which made the maze
## pointless -- you want the long way round to be the only way. Returns [cell, side].
## Works on any square grid, so infinite mode can use it on the big maze too.
func _far_border(size: int, from: Vector2i, dist: Dictionary, sides: Array) -> Array:
	var best := -1
	var best_cell := from
	var best_side: int = sides[0] if not sides.is_empty() else 0
	for side in sides:
		for i in size:
			var c: Vector2i = _border_cell(side, i, size)
			if c == from:
				continue
			var d: int = int(dist.get(c, -1))
			if d > best:
				best = d
				best_cell = c
				best_side = side
	if best < 0:
		Probe.note("no exit reachable on the allowed sides of a %dx%d maze" % [size, size])
	return [best_cell, best_side]

func _border_cell(side: int, i: int, size: int) -> Vector2i:
	match side:
		0: return Vector2i(i, 0)
		1: return Vector2i(size - 1, i)
		2: return Vector2i(i, size - 1)
		_: return Vector2i(0, i)

func _grid_dist(walls: Array, cols: int, rows: int, from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var queue: Array = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for side in 4:
			if walls[c.y][c.x] & SIDE_BIT[side]:
				continue
			var n: Vector2i = c + SIDE_DIR[side]
			if n.x >= 0 and n.y >= 0 and n.x < cols and n.y < rows and not dist.has(n):
				dist[n] = int(dist[c]) + 1
				queue.append(n)
	return dist

## ---- infinite mode ------------------------------------------------------------
##
## Nothing about the big maze is drawn ahead of time, and nothing about it is decided
## separately from the small ones. Every opening in the big maze IS a doorway in a small
## maze: the doorway you leave one by, lined up with the doorway you enter the next by.
## When the carving comes back to a finished cell to branch off in a new direction, a new
## doorway is cut into that cell's maze right where the next maze's entrance will be. A
## dead end of the big maze is a maze with a single doorway and a prize at the far end.
## The way out of the big one is cut last, just before the zoom-out.
##
## A plan does exist -- the big maze is carved invisibly up front, so the play order and
## the far exit are known -- but the big maze you play after the zoom-out is read back
## off the small mazes' doorways, and the plan is only used to check the two agree.

func _inf_begin() -> void:
	_stage = 0
	_small = FIRST_SIZE
	_big = FIRST_SIZE + 1
	_bin_side = randi() % 4
	var root := _border_cell(_bin_side, randi() % _big, _big)
	_inf_plan_big(root, -1)
	# the first small maze goes at the world origin, like classic's first one
	_big_origin = -Vector2(root) * SPAN
	_cell_rec = {}
	_prev_cell = NO_CELL
	_bidx = 0
	_phase = "small"
	_exit_open = false
	_inf_start_small()

## Carve the plan, instantly, and remember the order its cells were reached in -- that
## is the order the player fills them, so the big maze grows the way a maze is carved.
## Each cell remembers which side it was entered from (its small maze's entrance) and
## the sides the carving left it by, in order (its small maze's exits, cut one at a time
## as the carving comes back for each).
## `forced` is the side the very first carve must take: the cell that was the previous
## big maze keeps the exit you just used, so its first neighbour has to be there.
func _inf_plan_big(root: Vector2i, forced: int) -> void:
	_bwalls = []
	for y in _big:
		var row: Array = []
		for x in _big:
			row.append(N | E | S | W)
		_bwalls.append(row)
	var seen := {root: true}
	var stack: Array = [root]
	_order = [root]
	_cell_in_side = {}
	_cell_kids = {}
	while not stack.is_empty():
		var here: Vector2i = stack[-1]
		var options: Array = []
		for side in 4:
			var n: Vector2i = here + SIDE_DIR[side]
			if _in_big(n) and not seen.has(n):
				options.append(side)
		if options.is_empty():
			stack.pop_back()
			continue
		var side: int = options[randi() % options.size()]
		if forced >= 0:
			if options.has(forced):
				side = forced
			else:
				Probe.note("the forced first carve of the big maze was not possible")
			forced = -1
		var nxt: Vector2i = here + SIDE_DIR[side]
		_bwalls[here.y][here.x] &= ~SIDE_BIT[side]
		_bwalls[nxt.y][nxt.x] &= ~SIDE_BIT[(side + 2) % 4]
		seen[nxt] = true
		stack.append(nxt)
		_order.append(nxt)
		_cell_in_side[nxt] = (side + 2) % 4
		if not _cell_kids.has(here):
			_cell_kids[here] = []
		_cell_kids[here].append(side)

	_bin = root
	_cell_in_side[root] = _bin_side
	var dist := _grid_dist(_bwalls, _big, _big, _bin)
	var far := _far_border(_big, _bin, dist, _sides_except(_bin_side))
	_bout = far[0]
	_bout_side = far[1]
	_bwalls[_bin.y][_bin.x] &= ~SIDE_BIT[_bin_side]
	_bwalls[_bout.y][_bout.x] &= ~SIDE_BIT[_bout_side]

	_rebuild_big_done()
	if _order.size() != _big * _big or int(dist.get(_bout, -1)) < 0:
		Probe.note("the big %dx%d maze did not carve every cell or has no way out" % [_big, _big])
	Probe.event("big_planned", {"stage": _stage, "size": "%dx%d" % [_big, _big],
		"cells": _order.size(), "path": int(dist.get(_bout, -1))})

func _in_big(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _big and c.y < _big

func _inf_start_small() -> void:
	var prev_origin := _origin
	var prev_cell := _cell
	var prev_out := _out
	var prev_out_side := _out_side

	var c: Vector2i = _order[_bidx]
	_cols = _small
	_rows = _small
	_cell = SPAN / float(_small)
	_origin = _big_origin + Vector2(c) * SPAN
	_in_side = _cell_in_side[c]
	var kids: Array = _cell_kids.get(c, [])
	if not kids.is_empty():
		_out_sides = [kids[0]]
	elif c == _bout:
		_out_sides = [_bout_side]
		_exit_open = true
	else:
		_out_sides = []      # a dead end of the big maze: one doorway, and a prize inside

	# When the maze you just left is the neighbour across this entrance, the doorways
	# line up like classic's do. Otherwise the carving has come back to an earlier cell
	# to branch: pick this entrance, then cut the matching doorway into that cell's maze.
	var continuous: bool = _prev_cell != NO_CELL and prev_out_side >= 0 \
		and _prev_cell + SIDE_DIR[prev_out_side] == c \
		and _in_side == (prev_out_side + 2) % 4
	if continuous:
		_in = _aligned_in_cell(prev_origin, prev_cell, prev_out)
	else:
		_in = _random_border_cell(_in_side)
		if _bidx > 0:
			var parent: Vector2i = c + SIDE_DIR[_in_side]
			var rec: Dictionary = _cell_rec[parent]
			_cut_doorway(rec, _aligned_border_cell(rec, (_in_side + 2) % 4, _cell_centre(_in)),
				(_in_side + 2) % 4)
	_begin_build(PAN_TIME if _level > 0 else 0.0)
	Probe.event("cell_start", {"stage": _stage, "cell": _bidx + 1, "of": _order.size(),
		"continuous": continuous, "dead_end": _out_sides.is_empty()})

## The border cell of a finished maze on `side` that sits across from `world` -- where a
## doorway has to go for it to face the neighbour's.
func _aligned_border_cell(rec: Dictionary, side: int, world: Vector2) -> Vector2i:
	var size: int = rec["cols"]
	var rel: Vector2 = (world - rec["origin"]) / float(rec["cell"])
	var along: float = rel.x if (side == 0 or side == 2) else rel.y
	return _border_cell(side, clampi(int(floorf(along)), 0, size - 1), size)

## Open a doorway in a finished maze. This is how a cell of the big maze gets its second
## and third openings, and how the big one gets its way out.
func _cut_doorway(rec: Dictionary, bc: Vector2i, side: int) -> void:
	rec["walls"][bc.y][bc.x] &= ~SIDE_BIT[side]
	rec["pts"] = _wall_pts(rec["walls"], rec["cols"], rec["rows"])
	_door_flash = {"origin": rec["origin"], "cell": rec["cell"], "c": bc, "side": side, "t": 1.4}
	Audio.play("open")
	Probe.event("doorway_cut", {"stage": _stage, "side": side})
	_rebuild_big_done()
	_static.queue_redraw()

func _inf_after_solve() -> void:
	if _phase == "small":
		var rec := _record(true)
		_done.append(rec)
		var c: Vector2i = _order[_bidx]
		_cell_rec[c] = rec
		_prev_cell = c
		_bidx += 1
		_rebuild_big_done()
		_static.queue_redraw()
		if _bidx < _order.size():
			_inf_start_small()
		else:
			_inf_zoom_out()
	elif _phase == "big":
		_done.append(_record(false))
		_inf_next_stage()

## Every cell is filled: cut the way out of the big one if it is not there yet, then
## pull back until the whole thing is on screen.
func _inf_zoom_out() -> void:
	_phase = "zoom"
	player.visible = false
	_marker.visible = false
	if not _exit_open:
		var rec: Dictionary = _cell_rec[_bout]
		var dist := _grid_dist(rec["walls"], rec["cols"], rec["rows"], rec["in"])
		var far := _far_border(rec["cols"], rec["in"], dist, [_bout_side])
		_cut_doorway(rec, far[0], _bout_side)
		_exit_open = true
	Probe.world_rect = Rect2(_big_origin, Vector2.ONE * SPAN * _big)
	Probe.event("zoom_out", {"stage": _stage, "size": "%dx%d" % [_big, _big]})
	Audio.play("voice_level_up")
	Juice.shake(4.0)
	if _cam_tw != null and _cam_tw.is_valid():
		_cam_tw.kill()
	_cam_tw = create_tween().set_parallel(true)
	_cam_tw.tween_property(_cam, "zoom", Vector2.ONE * CAM_ZOOM / float(_big), ZOOM_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tw.tween_property(_cam, "position", _big_origin + Vector2.ONE * SPAN * _big * 0.5,
		ZOOM_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_cam_tw.chain().tween_callback(_inf_play_big)

## The big maze, read off the small ones: two neighbouring cells are joined where both
## their mazes have a doorway on the shared wall, and a doorway on the outer edge is the
## way in or out. Nothing else is open.
func _derive_big_walls() -> Array:
	var w: Array = []
	for y in _big:
		var row: Array = []
		for x in _big:
			row.append(N | E | S | W)
		w.append(row)
	for c in _order:
		var rec: Dictionary = _cell_rec[c]
		for side in 4:
			if not _rec_has_door(rec, side):
				continue
			var n: Vector2i = c + SIDE_DIR[side]
			if not _in_big(n) or _rec_has_door(_cell_rec[n], (side + 2) % 4):
				w[c.y][c.x] &= ~SIDE_BIT[side]
	return w

func _rec_has_door(rec: Dictionary, side: int) -> bool:
	var size: int = rec["cols"]
	for i in size:
		var bc := _border_cell(side, i, size)
		if not (rec["walls"][bc.y][bc.x] & SIDE_BIT[side]):
			return true
	return false

## The zoom has landed. Rather than keep playing at a smaller and smaller camera zoom --
## which would run the coordinates into float trouble a few stages in -- shrink the world
## so the big maze is SPAN wide like every maze before it, and snap the zoom back. The
## two cancel out exactly, so nothing on screen moves.
func _inf_play_big() -> void:
	var f := 1.0 / float(_big)
	for r in _done:
		r["origin"] = _big_origin + (r["origin"] - _big_origin) * f
		r["cell"] = r["cell"] * f
	_cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
	_cam.position = _big_origin + Vector2.ONE * SPAN * 0.5

	var derived := _derive_big_walls()
	if derived != _bwalls:
		Probe.note("the big maze read off the small mazes' doorways differs from the plan")
	_phase = "big"
	_cols = _big
	_rows = _big
	_cell = SPAN / float(_big)
	_origin = _big_origin
	_walls = derived
	_in = _bin
	_in_side = _bin_side
	_out = _bout
	_out_side = _bout_side
	_building = false
	_level += 1
	_reset_walker()
	player.visible = true
	_marker.visible = true
	_marker.position = _cell_centre(_out) + Vector2(SIDE_DIR[_out_side]) * _cell * 0.8
	Probe.world_rect = Rect2(_origin, Vector2(SPAN, SPAN)).grow(GAP)
	_static.queue_redraw()
	Audio.play("impact_light")
	var dist := _grid_dist(_walls, _cols, _rows, _in)
	Probe.event("big_start", {"stage": _stage, "size": "%dx%d" % [_big, _big],
		"path": int(dist.get(_out, -1)), "matches_plan": derived == _bwalls})

## The big maze is solved. It becomes the first cell of the next big one, one square
## bigger, keeping the doorways you came in and went out by, and the camera slides on to
## the next cell -- no zoom in, ever: the zoom-out just happened one level up.
func _inf_next_stage() -> void:
	var prev_in_side := _in_side
	var prev_out_side := _out_side
	_stage += 1
	_small = mini(FIRST_SIZE + _stage, MAX_SIZE)
	_big = _small + 1
	var root := _root_for(prev_in_side, prev_out_side)
	_bin_side = prev_in_side
	_inf_plan_big(root, prev_out_side)
	_big_origin = _origin - Vector2(root) * SPAN
	_cell_rec = {root: _done[-1]}
	_prev_cell = root
	_bidx = 1
	_phase = "small"
	_exit_open = false
	_rebuild_big_done()
	Probe.event("stage", {"stage": _stage, "small": _small, "big": _big})
	_inf_start_small()

## A cell on the `in_side` border of the new big maze whose `out_side` neighbour exists,
## so the solved maze can keep both its doorways as the root of the next one.
func _root_for(in_side: int, out_side: int) -> Vector2i:
	for _try in 40:
		var c := _border_cell(in_side, randi() % _big, _big)
		if _in_big(c + SIDE_DIR[out_side]):
			return c
	for i in _big:
		var c := _border_cell(in_side, i, _big)
		if _in_big(c + SIDE_DIR[out_side]):
			return c
	return _border_cell(in_side, 0, _big)

## The thick outline around finished cells is the small mazes' own border walls, gaps
## and all, in big-maze units (one cell of the big maze = 1.0). Nothing is drawn that a
## small maze does not have.
func _rebuild_big_done() -> void:
	_big_done_pts = PackedVector2Array()
	for c in _cell_rec:
		var rec: Dictionary = _cell_rec[c]
		var size: int = rec["cols"]
		var step := 1.0 / float(size)
		for side in 4:
			for i in size:
				var bc := _border_cell(side, i, size)
				if not (rec["walls"][bc.y][bc.x] & SIDE_BIT[side]):
					continue
				var a: Vector2
				var b: Vector2
				match side:
					0:
						a = Vector2(c.x + i * step, c.y)
						b = a + Vector2(step, 0)
					2:
						a = Vector2(c.x + i * step, c.y + 1)
						b = a + Vector2(step, 0)
					3:
						a = Vector2(c.x, c.y + i * step)
						b = a + Vector2(0, step)
					_:
						a = Vector2(c.x + 1, c.y + i * step)
						b = a + Vector2(0, step)
				_big_done_pts.append(a)
				_big_done_pts.append(b)

## ---- walking on the grid --------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	if _mode == "":
		_picker_input()
		return
	_live.queue_redraw()
	if _cam.position != _last_cam_pos or _cam.zoom.x != _last_cam_zoom:
		_last_cam_pos = _cam.position
		_last_cam_zoom = _cam.zoom.x
		_static.queue_redraw()
	_update_hud()
	if not _door_flash.is_empty():
		_door_flash["t"] = float(_door_flash["t"]) - delta
		if float(_door_flash["t"]) <= 0.0:
			_door_flash = {}

	if _mode == "infinite" and _phase == "zoom":
		return
	if _building:
		_build_acc += delta * _build_rate
		while _build_acc >= 1.0 and _building:
			_build_acc -= 1.0
			_build_step()
		return

	if PInput.just_pressed("action_a") and not _auto:
		_toggle_auto()
	elif PInput.just_pressed("action_b") and _auto:
		_toggle_auto()

	if _moving:
		# the solver runs brisker than a person, so watching it is not a chore
		_step_t += delta / (STEP_TIME * (0.6 if _auto else 1.0))
		if _step_t < 1.0:
			player.position = _from.lerp(_to, _step_t)
			return
		player.position = _to
		_moving = false
		if _leaving:
			_solved()
			return
		_pc = _step_target
		if _out_side < 0 and _pc == _out:
			_solved()      # a dead end: reaching the prize is the whole job
			return

	var d := _wanted_step()
	if d != Vector2i.ZERO:
		_begin_step(d)

func _update_hud() -> void:
	if _mode == "classic":
		_hud_top.text = "building %dx%d..." % [_cols, _rows] if _building else "get out"
		_hud_bottom.text = "maze %d" % _level
		return
	match _phase:
		"small":
			_hud_top.text = "building %dx%d..." % [_cols, _rows] if _building else "get out"
			_hud_bottom.text = "cell %d of %d of the %dx%d" % [_bidx + 1, _order.size(), _big, _big]
		"zoom":
			_hud_top.text = "the %dx%d is built" % [_big, _big]
			_hud_bottom.text = "zooming out..."
		_:
			_hud_top.text = "get out of the big one"
			_hud_bottom.text = "the %dx%d  (level %d)" % [_big, _big, _stage + 1]

## One cell at a time, always axis-locked. A tap picks the axis once and the player runs
## down that line until it reaches the tapped row or column, or a wall stops it.
func _wanted_step() -> Vector2i:
	if _auto:
		return _solver_step()
	var k := PInput.dir()
	if k != Vector2.ZERO:
		_goal = NO_GOAL
		if absf(k.x) > absf(k.y):
			return Vector2i(1 if k.x > 0.0 else -1, 0)
		return Vector2i(0, 1 if k.y > 0.0 else -1)
	if _goal == NO_GOAL:
		return Vector2i.ZERO
	if _run_axis == 0:
		if _pc.x == _goal.x:
			_goal = NO_GOAL
			return Vector2i.ZERO
		return Vector2i(1 if _goal.x > _pc.x else -1, 0)
	if _pc.y == _goal.y:
		_goal = NO_GOAL
		return Vector2i.ZERO
	return Vector2i(0, 1 if _goal.y > _pc.y else -1)

func _toggle_auto() -> void:
	_auto = not _auto
	_solve_btn.text = "stop" if _auto else "solve"
	_goal = NO_GOAL
	Probe.event("auto_solve", {"on": _auto, "level": _level})

## One move of the search. Returns the direction to step, or nothing if it is stuck --
## which on a perfect maze it never is.
func _solver_step() -> Vector2i:
	if _route.is_empty():
		_route = [_pc]
		_known = {_pc: true}
	if _pc == _out:
		if _out_side < 0:
			return Vector2i.ZERO
		return SIDE_DIR[_out_side]     # standing on the exit: walk out of the doorway

	var best_side := -1
	var best_d := INF
	for side in 4:
		if _walls[_pc.y][_pc.x] & SIDE_BIT[side]:
			continue
		var n: Vector2i = _pc + SIDE_DIR[side]
		if not _inside(n) or _known.has(n):
			continue
		# of the openings it has not tried, take the one pointing most at the exit. That
		# is not cheating: where the exit IS can be seen from anywhere. What it cannot see
		# is which walls are in the way, which is the whole problem.
		var d: float = Vector2(n).distance_squared_to(Vector2(_out))
		if d < best_d:
			best_d = d
			best_side = side
	if best_side >= 0:
		var n: Vector2i = _pc + SIDE_DIR[best_side]
		_known[n] = true
		_route.append(n)
		return SIDE_DIR[best_side]

	if _route.size() >= 2:
		_route.pop_back()               # dead end: reverse out the way it came
		var back: Vector2i = _route[-1]
		return back - _pc
	return Vector2i.ZERO

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
			_goal = NO_GOAL
		return
	if _walls[_pc.y][_pc.x] & SIDE_BIT[side]:
		_goal = NO_GOAL   # a wall: stop rather than grind against it
		return
	_from = _cell_centre(_pc)
	_to = _cell_centre(nxt)
	_step_target = nxt
	_step_t = 0.0
	_moving = true

func _solved() -> void:
	var big_one: bool = _mode == "infinite" and _phase == "big"
	var points: int = _cols * _cols * 10 if big_one else 10 + _level * 5
	add_score(points)
	Juice.hit(8.0 if big_one else 5.0)
	Juice.text(self, player.position + Vector2(-14, -30), "+%d" % points, Palette.col("warn"))
	Audio.play("impact_bell")
	if big_one:
		Audio.play("voice_congratulations")
	elif _mode == "classic":
		Audio.play("voice_level_up" if _level % 5 == 0 else "voice_correct")
	Probe.event("solved", {"level": _level, "big": big_one})
	if _mode == "classic":
		_next_maze()
	else:
		_inf_after_solve()

func _input(event: InputEvent) -> void:
	if finished or _mode == "" or _building or Flow.pointer_over_hud():
		return
	if _mode == "infinite" and _phase == "zoom":
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# _input runs before the GUI, so without this a tap on the solve button would also
	# order the player to run somewhere
	if _solve_btn.get_global_rect().has_point(mb.position):
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

## Every wall of a grid as line segments in unit cells (cell (x, y) spans x..x+1), so a
## whole maze can be drawn with one draw_multiline through a transform. Walls are
## symmetric, so each cell contributes its north and west sides and the outer east and
## south edges are added once.
func _wall_pts(walls: Array, cols: int, rows: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for y in rows:
		for x in cols:
			var bits: int = walls[y][x]
			var tl := Vector2(x, y)
			if bits & N:
				pts.append(tl); pts.append(tl + Vector2(1, 0))
			if bits & W:
				pts.append(tl); pts.append(tl + Vector2(0, 1))
			if x == cols - 1 and bits & E:
				pts.append(tl + Vector2(1, 0)); pts.append(tl + Vector2(1, 1))
			if y == rows - 1 and bits & S:
				pts.append(tl + Vector2(0, 1)); pts.append(tl + Vector2(1, 1))
	return pts

## ---- drawing --------------------------------------------------------------

func _faded(role: String, alpha: float) -> Color:
	var c := Palette.col(role)
	return Color(c.r, c.g, c.b, alpha)

## Escaped mazes and, in infinite mode, the plan of the big one. Redrawn only when the
## list or the camera changes. Mazes off screen are skipped, and ones too small to see
## keep only their floor -- deep in infinite mode there are hundreds of those.
func _draw_static() -> void:
	if _mode == "":
		return
	var zoom: float = _cam.zoom.x
	var half := Vector2(640, 360) / zoom * 0.6
	var view := Rect2(_cam.position - half, half * 2.0)

	if _mode == "infinite":
		var side := SPAN if _phase == "big" else SPAN * float(_big)
		_static.draw_rect(Rect2(_big_origin, Vector2.ONE * side), _faded("bg_alt", 0.25))

	var ground := _faded("bg_alt", 0.3)
	var ink := _faded("ink", 0.3)
	for r in _done:
		var cell: float = r["cell"]
		var origin: Vector2 = r["origin"]
		var cols: int = r["cols"]
		var rows: int = r["rows"]
		if not view.intersects(Rect2(origin, Vector2(cols, rows) * cell)):
			continue
		_static.draw_set_transform(origin, 0.0, Vector2(cell, cell))
		if r["ground"]:
			_static.draw_rect(Rect2(0, 0, cols, rows), ground)
		if cell * zoom >= 1.5:
			_static.draw_multiline(r["pts"], ink, maxf(1.5, cell * 0.1) / cell)
	_static.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _mode == "infinite" and _phase != "big":
		# the big maze so far: nothing but the finished mazes' own border walls, thick,
		# so every doorway between two of them reads as an opening in the big one
		if not _big_done_pts.is_empty():
			_static.draw_set_transform(_big_origin, 0.0, Vector2(SPAN, SPAN))
			_static.draw_multiline(_big_done_pts, _faded("accent", 0.85), 0.035)
			_static.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_doorway(_static, _big_origin, SPAN, _bin, _bin_side, _faded("friend", 0.5), SPAN * 0.035)
		if _exit_open:
			_draw_doorway(_static, _big_origin, SPAN, _bout, _bout_side, _faded("prize", 0.5), SPAN * 0.035)

## The maze being played, every frame: its walls (vanishing as it carves), the carving
## head, the solver's trail, and the doorways.
func _draw_live() -> void:
	if _mode == "":
		return
	# the big one's floor would hide the small mazes drawn inside it
	var ground: bool = not (_mode == "infinite" and _phase == "big")
	_draw_maze(_live, _walls, _cols, _rows, _origin, _cell, 1.0, ground)

	if _building and not _stack.is_empty():
		var head: Vector2i = _stack[-1]
		_live.draw_rect(Rect2(_origin + Vector2(head) * _cell, Vector2(_cell, _cell)),
			Palette.col("accent"))
	if _auto and not _building:
		var seen_col := _faded("accent", 0.1)
		for c in _known:
			_live.draw_rect(Rect2(_origin + Vector2(c) * _cell, Vector2(_cell, _cell)), seen_col)
		if _route.size() > 1:
			var pts := PackedVector2Array()
			for c in _route:
				pts.append(_cell_centre(c))
			_live.draw_polyline(pts, Palette.col("friend"), maxf(1.5, _cell * 0.08))

	if not _building:
		_draw_doorway(_live, _origin, _cell, _in, _in_side, Palette.col("friend"))
		if _out_side >= 0:
			_draw_doorway(_live, _origin, _cell, _out, _out_side, Palette.col("prize"))
	if not _door_flash.is_empty():
		# a doorway just cut into a finished maze lights up, then fades
		var k: float = clampf(float(_door_flash["t"]) / 1.4, 0.0, 1.0)
		var cell: float = _door_flash["cell"]
		var bc: Vector2i = _door_flash["c"]
		var o: Vector2 = _door_flash["origin"]
		_live.draw_rect(Rect2(o + Vector2(bc) * cell, Vector2(cell, cell)), _faded("warn", 0.35 * k))
		_draw_doorway(_live, o, cell, bc, int(_door_flash["side"]), _faded("warn", k), cell * 0.25)

func _draw_maze(on: CanvasItem, walls: Array, cols: int, rows: int, origin: Vector2,
		cell: float, alpha: float, ground: bool) -> void:
	var ink := _faded("ink", alpha)
	var floor_col := _faded("bg_alt", alpha)
	var thick := maxf(1.5, cell * 0.1)
	for y in rows:
		for x in cols:
			var tl := origin + Vector2(x, y) * cell
			if ground:
				on.draw_rect(Rect2(tl, Vector2(cell, cell)), floor_col)
			var bits: int = walls[y][x]
			if bits & N:
				on.draw_line(tl, tl + Vector2(cell, 0), ink, thick)
			if bits & W:
				on.draw_line(tl, tl + Vector2(0, cell), ink, thick)
			if bits & S:
				on.draw_line(tl + Vector2(0, cell), tl + Vector2(cell, cell), ink, thick)
			if bits & E:
				on.draw_line(tl + Vector2(cell, 0), tl + Vector2(cell, cell), ink, thick)

func _draw_doorway(on: CanvasItem, origin: Vector2, cell: float, c: Vector2i, side: int,
		col: Color, thick: float = -1.0) -> void:
	var centre := origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell
	var d := Vector2(SIDE_DIR[side])
	if thick < 0.0:
		thick = maxf(2.5, cell * 0.14)
	on.draw_line(centre + d * cell * 0.5, centre + d * cell * 1.1, col, thick)
