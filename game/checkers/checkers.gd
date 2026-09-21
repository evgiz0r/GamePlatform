extends GameMode
## checkers -- you against the computer on an eight by eight board. See GAME.md.
## Russian-draughts rules: capturing is compulsory and keeps going while it can, men
## capture backwards as well as forwards, kings fly. Tap a piece, tap a square. Arrow
## keys steer a cursor and space picks up or drops, which is also how the bots play.
## Three difficulties on the left, reset on the right, no clock anywhere.

const N := 8
const CELL := 37.0
const ORIGIN := Vector2(172.0, 32.0)
const CURSOR_SPEED := 230.0
const STEP_TIME := 0.11                   ## one square of sliding
const AI_PAUSE := 0.14                    ## a beat before the reply, so it reads as a reply
const DRAW_QUIET := 60                    ## king-only, capture-free moves before a draw
## The shell default (0.8) is loud for a game that knocks on wood every move. Scaled in
## memory only while checkers is on screen -- the saved settings file is never touched.
const SFX_SCALE := 0.28

## Board codes. Positive is you, negative the computer; 2 is a king.
const PM := 1
const PK := 2
const AM := -1
const AK := -2
const YOU := 1
const CPU := -1
const DIRS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]

const MAN_VALUE := 100
const KING_VALUE := 280
const LOSS := 50000
const BIG := 400000
const LEVELS := {
	"easy":   {"depth": 1, "noise": 80, "budget_ms": 40, "mult": 1},
	"normal": {"depth": 3, "noise": 15, "budget_ms": 80, "mult": 2},
	"hard":   {"depth": 9, "noise": 0, "budget_ms": 250, "mult": 3},
}
const LEVEL_ORDER := ["easy", "normal", "hard"]

var _board := PackedInt32Array()
var _nodes: Dictionary = {}               ## square -> Blob
var _side := YOU
var _level := "normal"
var _legal: Array = []                    ## every legal move for the side to move
var _movable: Dictionary = {}             ## square -> true, for pieces that may move
var _sel := -1
var _targets: Dictionary = {}             ## square -> move, for the selected piece
var _must_capture := false
var _busy := false                        ## a piece is sliding
var _anim: Tween
var _ai_wait := 0.0
var _last_from := -1
var _last_to := -1
var _quiet := 0
var _moves_played := 0

var _cursor: Blob
var _cur_pos := Vector2.ZERO              ## the keyboard pointer, continuous; drawn snapped
var _markers: Array = []
var _layer: CanvasLayer
var _buttons: Array = []
var _level_btns: Dictionary = {}
var _sfx_was := 0.8
var _idle_limit := 0.0
var _idle_t := 0.0
var _t := 0.0

## search scratch
var _search_nodes := 0
var _deadline := 0
var _aborted := false

func _ready() -> void:
	title = "checkers"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE

	# There is no clock, so a player who does nothing never loses -- which means the idle
	# bot cannot either. A playtest may set this to make doing nothing count as resigning.
	var forced := OS.get_environment("CHECKERS_IDLE_SECONDS")
	if forced.is_valid_float() and float(forced) > 0.0:
		_idle_limit = float(forced)
	# Bots cannot press the level buttons either, so a playtest may pick the opponent.
	var lv_forced := OS.get_environment("CHECKERS_LEVEL")
	if LEVELS.has(lv_forced):
		_level = lv_forced

	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()

	set_lives(0)

	_cursor = Blob.new()
	_cursor.role = "player"
	_cursor.shape = "diamond"
	_cursor.radius = 6.0
	_cursor.z_index = 2
	_cursor.visible = false
	add_child(_cursor)
	_cur_pos = _centre(Vector2i(2, 5))
	_cursor.position = _cur_pos
	Probe.track(_cursor, "@")

	# Buttons live in a CanvasLayer above the shell's HUD (10), otherwise Flow's
	# full-screen Control takes the click first and the button is decorative.
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	for i in LEVEL_ORDER.size():
		var lv: String = LEVEL_ORDER[i]
		var b := UIKit.button(lv, _set_level.bind(lv))
		b.custom_minimum_size = Vector2(120, 30)
		b.size = Vector2(120, 30)
		b.position = Vector2(22, 98 + i * 40)
		b.add_theme_font_size_override("font_size", 13)
		_layer.add_child(b)
		_buttons.append(b)
		_level_btns[lv] = b
	var reset := UIKit.button("reset", _reset)
	reset.custom_minimum_size = Vector2(120, 34)
	reset.size = Vector2(120, 34)
	reset.position = Vector2(493, 286)
	reset.add_theme_font_size_override("font_size", 14)
	_layer.add_child(reset)
	_buttons.append(reset)
	_show_level()

	_new_game()
	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- squares ------------------------------------------------------------------

func _rc(i: int) -> Vector2i:
	return Vector2i(i & 7, i >> 3)

func _idx(c: Vector2i) -> int:
	return c.y * N + c.x

func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < N and c.y < N

func _dark(c: Vector2i) -> bool:
	return (c.x + c.y) % 2 == 1

func _centre(c: Vector2i) -> Vector2:
	return ORIGIN + Vector2(c.x + 0.5, c.y + 0.5) * CELL

func _cell_of(p: Vector2) -> Vector2i:
	var rel := (p - ORIGIN) / CELL
	return Vector2i(int(floorf(rel.x)), int(floorf(rel.y)))

func _board_rect() -> Rect2:
	return Rect2(ORIGIN, Vector2(N, N) * CELL)

func _count(side: int) -> int:
	var n := 0
	for p in _board:
		if p * side > 0:
			n += 1
	return n

## ---- the rules ------------------------------------------------------------------
## Pure functions of a board, shared by play and by the search. A move is
## {from, to, caps, path, king}: caps are the squares jumped in order, path the squares
## landed on in order, king whether the piece is a king once the move is over.

func _gen_moves(b: PackedInt32Array, side: int) -> Array:
	var out: Array = []
	for i in 64:
		if b[i] * side > 0 and _can_capture(b, side, _rc(i), absi(b[i]) == 2, PackedInt32Array()):
			# the mover leaves its square, so a flying king may pass back over it
			var w := b.duplicate()
			w[i] = 0
			_gen_captures(w, side, i, i, absi(b[i]) == 2, PackedInt32Array(), PackedInt32Array(), out)
	if not out.is_empty():
		return out
	for i in 64:
		if b[i] * side > 0:
			_gen_quiet(b, side, i, out)
	return out

## Along one diagonal from `c`: the enemy that could be jumped and every square it could
## be jumped to, as [victim, land, land...]. Empty if there is no jump that way. A piece
## already jumped this turn is still on the board and blocks, but cannot be jumped again.
func _jump(b: PackedInt32Array, side: int, c: Vector2i, d: Vector2i, king: bool,
		taken: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := c + d
	if king:
		while _inside(n) and b[_idx(n)] == 0:
			n += d
	if not _inside(n):
		return out
	var v := _idx(n)
	if b[v] * side >= 0 or taken.has(v):
		return out
	var l := n + d
	if not _inside(l) or b[_idx(l)] != 0:
		return out
	out.append(v)
	while _inside(l) and b[_idx(l)] == 0:
		out.append(_idx(l))
		if not king:
			break
		l += d
	return out

## The same question as _jump() without building the answer: the search asks it at
## every leaf, so it has to be cheap.
func _can_capture(b: PackedInt32Array, side: int, c: Vector2i, king: bool,
		taken: PackedInt32Array) -> bool:
	for d in DIRS:
		var n := c + d
		if king:
			while _inside(n) and b[_idx(n)] == 0:
				n += d
		if not _inside(n):
			continue
		var v := _idx(n)
		if b[v] * side >= 0 or taken.has(v):
			continue
		var l := n + d
		if _inside(l) and b[_idx(l)] == 0:
			return true
	return false

func _any_capture(b: PackedInt32Array, side: int) -> bool:
	for i in 64:
		if b[i] * side > 0 and _can_capture(b, side, _rc(i), absi(b[i]) == 2, PackedInt32Array()):
			return true
	return false

func _promotes(side: int, land: Vector2i) -> bool:
	return land.y == (0 if side == YOU else N - 1)

## Every complete capture sequence from `pos`, appended to `out`. Returns whether any
## jump was possible at all, so a caller knows whether its own landing ended the move.
func _gen_captures(b: PackedInt32Array, side: int, origin: int, pos: int, king: bool,
		taken: PackedInt32Array, path: PackedInt32Array, out: Array) -> bool:
	var found := false
	var c := _rc(pos)
	for d in DIRS:
		var j := _jump(b, side, c, d, king, taken)
		if j.is_empty():
			continue
		found = true
		var victim := j[0]
		var nt := taken.duplicate()
		nt.append(victim)
		var lands: Array = []
		var can_go_on: Array = []
		for k in range(1, j.size()):
			var land: int = j[k]
			var nk := king or _promotes(side, _rc(land))
			lands.append(land)
			can_go_on.append(_can_capture(b, side, _rc(land), nk, nt))
		# a landing square from which the jump continues wins over one where it stops
		var must_go_on: bool = can_go_on.has(true)
		for k in lands.size():
			if must_go_on and not can_go_on[k]:
				continue
			var land: int = lands[k]
			var nk := king or _promotes(side, _rc(land))
			var np := path.duplicate()
			np.append(land)
			if not _gen_captures(b, side, origin, land, nk, nt, np, out):
				out.append({"from": origin, "to": land, "caps": nt, "path": np, "king": nk})
	return found

func _gen_quiet(b: PackedInt32Array, side: int, i: int, out: Array) -> void:
	var king := absi(b[i]) == 2
	var c := _rc(i)
	for d in DIRS:
		if not king and d.y != -side:
			continue
		var n := c + d
		while _inside(n) and b[_idx(n)] == 0:
			var to := _idx(n)
			out.append({"from": i, "to": to, "caps": PackedInt32Array(),
				"path": PackedInt32Array([to]), "king": king or _promotes(side, n)})
			if not king:
				break
			n += d

func _apply(b: PackedInt32Array, m: Dictionary) -> PackedInt32Array:
	var nb := b.duplicate()
	var side := 1 if nb[m["from"]] > 0 else -1
	nb[m["from"]] = 0
	for t in m["caps"]:
		nb[t] = 0
	nb[m["to"]] = side * (2 if m["king"] else 1)
	return nb

## ---- the computer -------------------------------------------------------------------
## Negamax with alpha-beta inside a time budget, deepening one ply at a time and keeping
## the last depth it finished. Captures at the horizon are followed to the end so a piece
## is never counted as safe halfway through being taken. The lower levels add noise to
## the root scores so they blunder like people do.

func _eval(b: PackedInt32Array) -> int:
	var s := 0
	for i in 64:
		var p := b[i]
		if p == 0:
			continue
		var r := i >> 3
		var col := i & 7
		var centre := 2 if (col >= 2 and col <= 5 and r >= 2 and r <= 5) else 0
		if p == PM:
			s += MAN_VALUE + (N - 1 - r) * 4 + centre + (3 if r == N - 1 else 0)
		elif p == PK:
			s += KING_VALUE + centre
		elif p == AM:
			s -= MAN_VALUE + r * 4 + centre + (3 if r == 0 else 0)
		else:
			s -= KING_VALUE + centre
	return s

func _negamax(b: PackedInt32Array, side: int, depth: int, alpha: int, beta: int, ext: int) -> int:
	_search_nodes += 1
	if (_search_nodes & 127) == 0 and Time.get_ticks_usec() > _deadline:
		_aborted = true
		return 0
	if depth <= 0:
		# a leaf is scored as it stands unless a capture is pending, which is followed to
		# its end (a few plies at most) so half-finished exchanges are never counted
		if ext <= 0 or not _any_capture(b, side):
			return side * _eval(b)
		ext -= 1
	var moves := _gen_moves(b, side)
	if moves.is_empty():
		return -(LOSS + depth)
	var best := -BIG
	for m in moves:
		var v := -_negamax(_apply(b, m), -side, depth - 1, -beta, -alpha, ext)
		if _aborted:
			return 0
		if v > best:
			best = v
		if v > alpha:
			alpha = v
		if alpha >= beta:
			break
	return best

func _think() -> Dictionary:
	var cfg: Dictionary = LEVELS[_level]
	var moves := _gen_moves(_board, CPU)
	if moves.is_empty():
		return {}
	moves.shuffle()
	if moves.size() == 1:
		return moves[0]
	var noise := int(cfg["noise"])
	var started := Time.get_ticks_usec()
	_deadline = started + int(cfg["budget_ms"]) * 1000
	_aborted = false
	_search_nodes = 0
	var best: Dictionary = moves[0]
	var scores: Array = []
	var reached := 0
	for depth in range(1, int(cfg["depth"]) + 1):
		var round_scores: Array = []
		var round_best: Dictionary = {}
		var round_v := -BIG
		var alpha := -BIG
		for m in moves:
			# the noisy levels want every root move scored on the same scale, so they
			# keep the window open; hard narrows it like any other node
			var v := -_negamax(_apply(_board, m), YOU, depth - 1, -BIG, -alpha, 4)
			if _aborted:
				break
			round_scores.append(v)
			if v > round_v:
				round_v = v
				round_best = m
			if noise == 0 and v > alpha:
				alpha = v
		if _aborted:
			break
		best = round_best
		scores = round_scores
		reached = depth
		if noise == 0:
			moves.erase(best)
			moves.push_front(best)
		if round_v > (LOSS >> 1) or round_v < -(LOSS >> 1):
			break
	if noise > 0 and scores.size() == moves.size():
		var pick_v := -BIG
		for i in moves.size():
			var v: int = scores[i] + randi_range(-noise, noise)
			if v > pick_v:
				pick_v = v
				best = moves[i]
	Probe.event("ai_think", {"level": _level, "depth": reached, "nodes": _search_nodes,
		"ms": int((Time.get_ticks_usec() - started) / 1000.0)})
	return best

## ---- a game -------------------------------------------------------------------------

func _new_game() -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()
	for i in _nodes:
		var n = _nodes[i]
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_clear_markers()
	_board.resize(64)
	_board.fill(0)
	for i in 64:
		var c := _rc(i)
		if not _dark(c):
			continue
		if c.y < 3:
			_board[i] = AM
		elif c.y > 4:
			_board[i] = PM
	for i in 64:
		if _board[i] != 0:
			_make_node(i)
	_side = YOU
	_sel = -1
	_targets.clear()
	_last_from = -1
	_last_to = -1
	_quiet = 0
	_moves_played = 0
	_busy = false
	_idle_t = 0.0
	_begin_turn()

func _make_node(i: int) -> void:
	var p := _board[i]
	var b := Blob.new()
	b.role = "player" if p > 0 else "hazard"
	b.radius = 13.0
	b.z_index = 1
	add_child(b)
	b.position = _centre(_rc(i))
	if absi(p) == 2:
		_crown(b)
	Probe.track(b, "p" if p > 0 else "o")
	_nodes[i] = b

func _crown(b: Blob) -> void:
	if b.has_node("Crown"):
		return
	var k := Blob.new()
	k.name = "Crown"
	k.role = "warn"
	k.shape = "diamond"
	k.radius = 5.0
	k.glow = false
	b.add_child(k)

func _begin_turn() -> void:
	_legal = _gen_moves(_board, _side)
	_must_capture = not _legal.is_empty() and not (_legal[0]["caps"] as PackedInt32Array).is_empty()
	_movable.clear()
	for m in _legal:
		_movable[m["from"]] = true
	_sel = -1
	_targets.clear()
	if _legal.is_empty():
		_end(_side == CPU, "no_moves")
		return
	if _quiet >= DRAW_QUIET:
		_end(false, "draw")
		return
	if _side == CPU:
		_ai_wait = AI_PAUSE
	else:
		_idle_t = 0.0
		if _must_capture and _moves_played > 0:
			Audio.play("click", 0.05, -4.0)
	_refresh_markers()
	queue_redraw()

func _select(i: int) -> void:
	_sel = i
	_targets.clear()
	for m in _legal:
		if m["from"] != i:
			continue
		var to: int = m["to"]
		# two jumps can end on the same square; offer the one that takes more
		if not _targets.has(to) or (m["caps"] as PackedInt32Array).size() > (_targets[to]["caps"] as PackedInt32Array).size():
			_targets[to] = m
	Audio.play("click", 0.06, -6.0)
	var n = _nodes.get(i)
	if n != null and is_instance_valid(n):
		Juice.pop(n, 1.18, 0.14)
	_refresh_markers()
	queue_redraw()

func _deselect() -> void:
	if _sel < 0:
		return
	_sel = -1
	_targets.clear()
	_refresh_markers()
	queue_redraw()

func _tap(c: Vector2i) -> void:
	if finished or _side != YOU or _busy:
		return
	if not _inside(c):
		_deselect()
		return
	var i := _idx(c)
	if _sel >= 0 and _targets.has(i):
		_play(_targets[i])
		return
	if _movable.has(i):
		if i == _sel:
			_deselect()
		else:
			_select(i)
		return
	if _sel >= 0:
		_deselect()
	elif _board[i] * YOU > 0:
		# a piece of yours that may not move: say why, once
		Audio.play("thud", 0.05, -8.0)
		Probe.event("blocked_piece", {"must_capture": _must_capture})

func _play(m: Dictionary) -> void:
	var from: int = m["from"]
	var caps: PackedInt32Array = m["caps"]
	var path: PackedInt32Array = m["path"]
	var side := _side
	_busy = true
	_sel = -1
	_targets.clear()
	_clear_markers()
	_last_from = from
	_last_to = m["to"]
	_moves_played += 1
	if caps.is_empty() and absi(_board[from]) == 2:
		_quiet += 1
	else:
		_quiet = 0
	_board = _apply(_board, m)

	var node: Blob = _nodes[from]
	_nodes.erase(from)
	Probe.event("move" if side == YOU else "ai_move", {"from": from, "to": m["to"], "caps": caps.size()})
	if caps.is_empty():
		Audio.play("impact_wood", 0.1, -4.0)
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_anim = create_tween()
	for k in path.size():
		var p := _centre(_rc(path[k]))
		_anim.tween_property(node, "position", p, STEP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if k < caps.size():
			_anim.tween_callback(_take.bind(caps[k], side))
	_anim.tween_callback(_after_move.bind(node, m, side))
	queue_redraw()

func _take(victim: int, by: int) -> void:
	var v = _nodes.get(victim)
	_nodes.erase(victim)
	if v != null and is_instance_valid(v):
		Juice.flash(v)
		var tw: Tween = v.create_tween()
		tw.tween_property(v, "scale", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(v.queue_free)
	Audio.play("impact_punch", 0.1, -2.0)
	Juice.shake(3.5)
	Probe.event("capture", {"by": "you" if by == YOU else "cpu"})
	if by == YOU:
		var was_king: bool = v != null and is_instance_valid(v) and v.has_node("Crown")
		var pts := (30 if was_king else 10) * int(LEVELS[_level]["mult"])
		add_score(pts)
		Juice.text(self, _centre(_rc(victim)) + Vector2(-10, -26), "+%d" % pts, Palette.col("warn"))

func _after_move(node: Blob, m: Dictionary, side: int) -> void:
	if not is_instance_valid(node):
		return
	_nodes[m["to"]] = node
	if m["king"] and not node.has_node("Crown"):
		_crown(node)
		Juice.pop(node, 1.4)
		Audio.play("coin", 0.05, -4.0)
		Probe.event("king", {"side": "you" if side == YOU else "cpu"})
	_busy = false
	_side = -side
	_begin_turn()

func _end(won: bool, why: String) -> void:
	if finished:
		return
	_clear_markers()
	_layer.visible = false
	Probe.event("won" if won else "lost", {"why": why, "level": _level,
		"you": _count(YOU), "cpu": _count(CPU), "moves": _moves_played})
	Probe.capture("end")
	if won:
		add_score(300 * int(LEVELS[_level]["mult"]))
		Audio.play("voice_you_win")
		Juice.shake(6.0)
		win()
	else:
		Audio.play("voice_you_lose" if why != "draw" else "voice_time_over")
		lose()

## ---- buttons ------------------------------------------------------------------------

func _set_level(lv: String) -> void:
	if not LEVELS.has(lv) or lv == _level:
		return
	_level = lv
	_show_level()
	Audio.play("select", 0.05, -6.0)
	Probe.event("difficulty", {"level": lv})
	queue_redraw()

func _show_level() -> void:
	for lv in _level_btns:
		var b: Button = _level_btns[lv]
		var on: bool = lv == _level
		b.modulate.a = 1.0 if on else 0.5
		b.text = ("> " + lv) if on else lv

func _reset() -> void:
	if finished:
		return
	Audio.play("open", 0.05, -4.0)
	score = 0
	Bus.score_changed.emit(score)
	Probe.event("reset", {"moves": _moves_played})
	_new_game()

## ---- input -------------------------------------------------------------------------------

## Mouse and finger are the main way in; the cursor exists so keyboard, gamepad and
## bots can play the same game.
func _input(event: InputEvent) -> void:
	if finished or _side != YOU or _busy:
		return
	if Flow.pointer_over_hud():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# _input runs before the GUI, so without this a tap on a button also lands on the board
	for b in _buttons:
		if (b as Control).get_global_rect().has_point(mb.position):
			return
	_cursor.visible = false
	_idle_t = 0.0
	_tap(_cell_of(get_global_mouse_position()))

func _process(delta: float) -> void:
	if finished:
		return
	_t += delta
	queue_redraw()
	if _busy:
		return

	if _side == CPU:
		_ai_wait -= delta
		if _ai_wait <= 0.0:
			var m := _think()
			if m.is_empty():
				_end(true, "no_moves")
			else:
				_play(m)
		return

	# the keyboard pointer moves smoothly and snaps to whatever square it is over, so
	# holding a key walks the cursor square by square and a bot can steer it to a "*"
	var d := PInput.dir()
	if d != Vector2.ZERO:
		var r := _board_rect().grow(-1.0)
		_cur_pos = (_cur_pos + d * CURSOR_SPEED * delta).clamp(r.position, r.end)
		_cursor.visible = true
		_cursor.position = _centre(_cell_of(_cur_pos))
		_idle_t = 0.0
	if PInput.just_pressed("action_a"):
		_cursor.visible = true
		_idle_t = 0.0
		_tap(_cell_of(_cur_pos))
	if _idle_limit > 0.0:
		_idle_t += delta
		if _idle_t > _idle_limit:
			Probe.event("resigned_idle", {"after": _idle_limit})
			_end(false, "idle")

## ---- the playtest eye --------------------------------------------------------------------
## Every square the player may act on right now is a "*": the pieces that may move, or
## once one is picked up, where it may go. The smart bot steers the cursor to the nearest
## one and pulses space, which is a whole game of checkers played through the same
## verbs a person uses.

func _clear_markers() -> void:
	for m in _markers:
		if is_instance_valid(m):
			m.queue_free()
	_markers.clear()

func _refresh_markers() -> void:
	_clear_markers()
	if not Probe.enabled or _side != YOU:
		return
	var squares: Array = _targets.keys() if _sel >= 0 else _movable.keys()
	for i in squares:
		var n := Node2D.new()
		add_child(n)
		n.position = _centre(_rc(i))
		Probe.track(n, "*")
		_markers.append(n)

## ---- the screen ------------------------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	var accent := Palette.col("accent")
	var ink := Palette.col("ink")
	var warn := Palette.col("warn")
	var prize := Palette.col("prize")
	var hazard := Palette.col("hazard")
	var light := Palette.col("bg").lightened(0.07)
	var dark := Palette.col("bg_alt")

	var frame := _board_rect()
	draw_rect(frame.grow(6.0), Color(accent.r, accent.g, accent.b, 0.18))
	draw_rect(frame.grow(3.0), accent, false, 2.0)
	for i in 64:
		var c := _rc(i)
		var r := Rect2(ORIGIN + Vector2(c) * CELL, Vector2(CELL, CELL))
		draw_rect(r, dark if _dark(c) else light)
		if i == _last_from or i == _last_to:
			draw_rect(r, Color(hazard.r, hazard.g, hazard.b, 0.16 if _side == YOU else 0.28))

	if _side == YOU and not _busy:
		if _sel < 0 and _must_capture:
			var pulse := 0.6 + 0.4 * sin(_t * 6.0)
			for i in _movable:
				draw_arc(_centre(_rc(i)), 16.5, 0.0, TAU, 32, Color(warn.r, warn.g, warn.b, pulse), 2.0)
		if _sel >= 0:
			var p := _centre(_rc(_sel))
			draw_circle(p, 18.0, Color(ink.r, ink.g, ink.b, 0.12))
			draw_arc(p, 17.0, 0.0, TAU, 32, ink, 2.5)
			for to in _targets:
				var m: Dictionary = _targets[to]
				var path: PackedInt32Array = m["path"]
				# a long jump shows its stepping stones, faintly
				for k in path.size() - 1:
					var q := _centre(_rc(path[k]))
					draw_circle(q, 4.0, Color(prize.r, prize.g, prize.b, 0.45))
				var q := _centre(_rc(to))
				var big := not (m["caps"] as PackedInt32Array).is_empty()
				draw_circle(q, 13.0 if big else 10.0, Color(prize.r, prize.g, prize.b, 0.16))
				draw_circle(q, 7.0 if big else 5.0, prize)

	# left: what it is and which brain
	_text(f, 22, 78, 120, "checkers", 20, accent)
	_text(f, 22, 96, 120, "opponent", 11, ink)
	_text(f, 22, 250, 120, "must eat, jumps chain,", 10, Color(ink.r, ink.g, ink.b, 0.6))
	_text(f, 22, 264, 120, "men eat backwards,", 10, Color(ink.r, ink.g, ink.b, 0.6))
	_text(f, 22, 278, 120, "kings fly. no clock.", 10, Color(ink.r, ink.g, ink.b, 0.6))
	_text(f, 22, 330, 120, "tap a piece, tap a square", 10, Color(ink.r, ink.g, ink.b, 0.6))

	# right: whose move, and the count
	var status := ""
	var status_col := ink
	if _side == CPU or _busy:
		status = "thinking..." if _side == CPU else "..."
		status_col = hazard
	elif _must_capture:
		status = "you must eat!"
		status_col = warn
	else:
		status = "your move"
		status_col = Palette.col("player")
	_text(f, 476, 82, 154, status, 15, status_col)
	_text(f, 476, 118, 154, "you  %d" % _count(YOU), 14, Palette.col("player"))
	_text(f, 476, 138, 154, "cpu  %d" % _count(CPU), 14, hazard)
	_text(f, 476, 172, 154, "x%d score" % int(LEVELS[_level]["mult"]), 11, Color(ink.r, ink.g, ink.b, 0.6))
	_text(f, 476, 186, 154, "on " + _level, 11, Color(ink.r, ink.g, ink.b, 0.6))

func _text(f: Font, x: float, y: float, w: float, msg: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(x, y), msg, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)
