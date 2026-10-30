extends GameMode
## elkyur -- two explorers on squared paper, one hidden map with walls on the lines.
## See GAME.md. Nobody is told where they are. A turn is one step, one bullet or one stick
## of dynamite in one direction, and both players hear what happened. Your map is drawn
## from where you started, the rival's from where it started; fitting the two together is
## the game. The computer plays from exactly those two maps: _walls, _starts and _treasure
## belong to the referee and no brain ever reads them.

const N := 10                              ## the world is N x N squares
const AMMO := 3
const DYNAMITE := 3
const EXTRA_OPEN := 0.55                   ## share of a perfect maze's walls knocked out
const MIN_APART := 6                       ## steps between the two starts, at least
const AI_PAUSE := 0.55                     ## a beat before the rival acts, so it reads
const AUTO_PAUSE := 0.12                   ## the same beat when a brain plays your side
const REVEAL_TIME := 2.8                   ## the real map is shown this long at the end
const WALL_PRIOR := 0.22                   ## how often a line nobody has tried is a wall
const BLAST_COST := [0.0, 9.0, 8.0, 6.0]   ## by level: how far a detour is worth a stick
const INF := 1e9
const THREAT_COST := 10.0                  ## hard: extra steps a square in the line of fire costs
## The shell default (0.8) is loud for a game that clicks every turn. Scaled in memory
## only while elkyur is on screen -- the saved settings file is never touched.
const SFX_SCALE := 0.28

## What a notebook knows about one line between two squares.
const WALL := 1                            ## bumped into it
const OPEN := 2                            ## walked across it, or blasted thin air
const BLOWN := 3                           ## a wall was there and dynamite took it
const EDGE := 4                            ## the outer wall: dynamite would not break it
const NOFIX := -999
const NONE := Vector2i(9999, 9999)

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIR_NAMES := ["up", "right", "down", "left"]
const MODES := ["walk", "shoot", "blast"]
const MODE_ROLE := {"walk": "player", "shoot": "hazard", "blast": "warn"}

## The three difficulties. The menu's level screen shows them as 1, 2, 3.
const LEVELS := [
	{"name": "easy", "mult": 1},
	{"name": "normal", "mult": 2},
	{"name": "hard", "mult": 3},
]

const YOU := 0
const RIVAL := 1
const MY_PANEL := Rect2(8, 34, 318, 318)
const RIVAL_PANEL := Rect2(334, 34, 146, 146)
const PAD_CENTER := Vector2(533, 270)
const PAD_BTN := 46.0

## One player's notebook, in that player's own frame: their start is (0, 0). Everything
## in here is public -- both players hear every result -- and it is all a brain may use.
class Book extends RefCounted:
	var cells := {}                        ## squares walked on
	var inside := {}                       ## squares known to be on the map
	var edges := {}                        ## Vector3i line -> WALL / OPEN / BLOWN / EDGE
	var pos := Vector2i.ZERO
	var trail: Array[Vector2i] = [Vector2i.ZERO]
	var ammo := 0
	var dyn := 0
	var shots: Array = []                  ## {from, dir, tpos}: tpos is the target's spot in ITS frame
	var bb_min := Vector2i.ZERO            ## bounding box of `inside`
	var bb_max := Vector2i.ZERO
	var fix := Vector2i(-999, -999)        ## where the map's left/top edge is, once proven

	func _init() -> void:
		cells[Vector2i.ZERO] = true
		inside[Vector2i.ZERO] = true

## Hides the controls while the shell's pause screen is up. It has to keep running while
## everything else is paused, so it is its own little node.
class PauseHider extends Node:
	var target: CanvasLayer
	var game: GameMode

	func _process(_d: float) -> void:
		if is_instance_valid(target) and is_instance_valid(game):
			target.visible = not get_tree().paused and not game.finished

var _level := 1
var _walls := {}                           ## referee only: absolute lines that are walls
var _blown := {}                           ## referee only: absolute lines blasted away
var _starts: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO]
var _treasure := Vector2i.ZERO
var _books: Array = []
var _turn := YOU
var _wait := 0.0
var _turns := 0
var _over := false
var _winner := YOU
var _reveal_left := 0.0
var _mode := "walk"
var _known_self := [false, false]          ## announced "knows where it is" yet
var _ai_target: Array[Vector2i] = [NONE, NONE]  ## each brain's current goal, for steadiness

var _autoplay := 0                         ## a brain plays your side too (playtests)
var _idle_limit := 0.0
var _idle_t := 0.0
var _sfx_was := 0.8

var _ghost := false
var _ghost_off := Vector2i.ZERO
var _ghost_clash: Array = []
var _ghost_fits := true
var _ghost_places := 0                     ## how many offsets fit at all, for the label
var _drag := false
var _drag_from := Vector2.ZERO
var _drag_off0 := Vector2i.ZERO

var _view: Array = [Rect2(), Rect2()]      ## what each panel shows, in squares (animated)
var _view_goal: Array = [Rect2(), Rect2()]
var _nudge: Array = [[0, 0.0], [0, 0.0]]   ## a bump: [dir, time left]
var _fx: Array = []                        ## beams and blasts being drawn

var _me_blob: Blob
var _rv_blob: Blob
var _ghost_blob: Blob
var _gold_blob: Blob
var _layer: CanvasLayer
var _buttons: Array = []
var _mode_btns := {}
var _pad: Array = []
var _ghost_btn: Button
var _status: Label
var _res_lbl: Array = []
var _log_lbls: Array = []
var _ghost_lbl: Label
var _log: Array = []

func _ready() -> void:
	title = "elkyur"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	_level = clampi(int(config.get("level", 1)), 1, LEVELS.size())

	# There is no clock, so a player who does nothing never loses -- which means the idle
	# bot cannot either. A playtest may set this to make doing nothing count as giving up.
	var forced := OS.get_environment("ELKYUR_IDLE_SECONDS")
	if forced.is_valid_float() and float(forced) > 0.0:
		_idle_limit = float(forced)
	# The bots cannot read a map, so a playtest may hand your side to a brain instead.
	var auto := OS.get_environment("ELKYUR_AUTOPLAY")
	for i in LEVELS.size():
		if auto == LEVELS[i]["name"] or auto == str(i + 1):
			_autoplay = i + 1

	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()
	set_lives(0)

	_generate()
	_books = [Book.new(), Book.new()]
	for b in _books:
		b.ammo = AMMO
		b.dyn = DYNAMITE

	_gold_blob = _blob("prize", "diamond")
	_gold_blob.visible = false
	_ghost_blob = _blob("hazard", "triangle")
	_ghost_blob.visible = false
	_rv_blob = _blob("hazard", "circle")
	_me_blob = _blob("player", "circle")
	Probe.track(_me_blob, "@")
	Probe.track(_rv_blob, "o")

	_build_ui()
	_turn = randi() % 2
	_wait = _pause_for(_turn)
	_say("%s map, %d x %d. nobody knows where they are." % [_level_name(), N, N], "accent")
	_say("you go first" if _turn == YOU else "rival goes first", "ink")
	_refresh_views(true)
	_place_blobs(1.0)
	_refresh_ui()
	Probe.event("game_begin", {"level": _level, "first": "you" if _turn == YOU else "rival"})
	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

func _blob(role: String, shape: String) -> Blob:
	var b := Blob.new()
	b.role = role
	b.shape = shape
	b.radius = 6.0
	b.z_index = 2
	add_child(b)
	return b

func _level_name() -> String:
	return LEVELS[_level - 1]["name"]

## ---- the real map (referee only) --------------------------------------------------

## The line on side `d` of square `c`, the same key from either side of it.
## (x, y, 0) is between (x, y) and (x + 1, y); (x, y, 1) is between (x, y) and (x, y + 1).
static func _ek(c: Vector2i, d: int) -> Vector3i:
	match d:
		0: return Vector3i(c.x, c.y - 1, 1)
		1: return Vector3i(c.x, c.y, 0)
		2: return Vector3i(c.x, c.y, 1)
		_: return Vector3i(c.x - 1, c.y, 0)

func _in_world(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < N and c.y < N

func _blocked(c: Vector2i, d: int) -> bool:
	return not _in_world(c + DIRS[d]) or _walls.has(_ek(c, d))

## A perfect maze with a good share of its walls knocked out: everything connected, plenty
## of loops, and roughly one line in five a wall. Then two starts far apart and a treasure
## about as far from one as from the other.
func _generate() -> void:
	for attempt in 300:
		_walls.clear()
		for x in N:
			for y in N:
				if x < N - 1:
					_walls[Vector3i(x, y, 0)] = true
				if y < N - 1:
					_walls[Vector3i(x, y, 1)] = true
		var first := Vector2i(randi() % N, randi() % N)
		var stack: Array[Vector2i] = [first]
		var seen := {first: true}
		while not stack.is_empty():
			var c: Vector2i = stack.back()
			var opts: Array[int] = []
			for d in 4:
				var n := c + DIRS[d]
				if _in_world(n) and not seen.has(n):
					opts.append(d)
			if opts.is_empty():
				stack.pop_back()
				continue
			var d: int = opts.pick_random()
			_walls.erase(_ek(c, d))
			seen[c + DIRS[d]] = true
			stack.append(c + DIRS[d])
		for k in _walls.keys():
			if randf() < EXTRA_OPEN:
				_walls.erase(k)

		var a := Vector2i(randi() % N, randi() % N)
		var da := _steps_from(a)
		var far: Array[Vector2i] = []
		for c in da:
			if da[c] >= MIN_APART:
				far.append(c)
		if far.is_empty():
			continue
		var b: Vector2i = far.pick_random()
		var db := _steps_from(b)
		var spots: Array[Vector2i] = []
		for c in da:
			if da[c] >= 5 and db[c] >= 5 and absi(da[c] - db[c]) <= 1:
				spots.append(c)
		if spots.is_empty():
			continue
		if randf() < 0.5:
			_starts = [a, b]
		else:
			_starts = [b, a]
		_treasure = spots.pick_random()
		return
	push_warning("elkyur: map generation fell back after 300 tries")

func _steps_from(s: Vector2i) -> Dictionary:
	var dist := {s: 0}
	var q: Array[Vector2i] = [s]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in 4:
			if _blocked(c, d):
				continue
			var n := c + DIRS[d]
			if not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return dist

## ---- notebooks --------------------------------------------------------------------

func _add_inside(b: Book, c: Vector2i) -> void:
	b.inside[c] = true
	b.bb_min = Vector2i(mini(b.bb_min.x, c.x), mini(b.bb_min.y, c.y))
	b.bb_max = Vector2i(maxi(b.bb_max.x, c.x), maxi(b.bb_max.y, c.y))

## Dynamite bounced off the outer wall on side `d` of square `c`: that pins one edge of the
## map, so it pins where the map is along that axis.
func _pin_edge(b: Book, c: Vector2i, d: int) -> void:
	match d:
		0: b.fix = Vector2i(b.fix.x, c.y)
		1: b.fix = Vector2i(c.x - N + 1, b.fix.y)
		2: b.fix = Vector2i(b.fix.x, c.y - N + 1)
		_: b.fix = Vector2i(c.x, b.fix.y)

## Where the map's low edge could be along one axis, as [lowest, highest]: the map is N
## long and has to hold every square known to be on it.
func _axis_range(lo_cell: int, hi_cell: int, fixed: int) -> Vector2i:
	var lo := hi_cell - N + 1
	var hi := lo_cell
	if fixed != NOFIX:
		lo = maxi(lo, fixed)
		hi = mini(hi, fixed)
	return Vector2i(lo, maxi(lo, hi))

## Everywhere the map could still reach, in the book's own frame. Exactly N x N once the
## player has worked out where they are.
func _region(b: Book) -> Rect2i:
	var rx := _axis_range(b.bb_min.x, b.bb_max.x, b.fix.x)
	var ry := _axis_range(b.bb_min.y, b.bb_max.y, b.fix.y)
	return Rect2i(rx.x, ry.x, rx.y - rx.x + N, ry.y - ry.x + N)

## The squares that are on the map whichever way it lies.
func _certain(b: Book) -> Rect2i:
	var rx := _axis_range(b.bb_min.x, b.bb_max.x, b.fix.x)
	var ry := _axis_range(b.bb_min.y, b.bb_max.y, b.fix.y)
	return Rect2i(rx.y, ry.y, rx.x + N - rx.y, ry.x + N - ry.y)

static func _clash(s1: int, s2: int) -> bool:
	if s1 == EDGE:
		return s2 == OPEN or s2 == BLOWN
	if s2 == EDGE:
		return s1 == OPEN or s1 == BLOWN
	# walls only ever disappear, and whoever blasts one writes BLOWN, so "walked through"
	# against "bumped into" can never both be true of the same line
	return (s1 == WALL and s2 == OPEN) or (s1 == OPEN and s2 == WALL)

## Both maps along one axis with b shifted into a's frame: how many places the pair
## could sit on the real map. 0 means they cannot both be true.
func _pair_axis(amin: int, amax: int, afix: int, bmin: int, bmax: int, bfix: int) -> int:
	var lo := maxi(amax, bmax) - N + 1
	var hi := mini(amin, bmin)
	if afix != NOFIX:
		lo = maxi(lo, afix)
		hi = mini(hi, afix)
	if bfix != NOFIX:
		lo = maxi(lo, bfix)
		hi = mini(hi, bfix)
	return hi - lo + 1

func _box_fits(a: Book, b: Book, d: Vector2i) -> int:
	var nx := _pair_axis(a.bb_min.x, a.bb_max.x, a.fix.x, b.bb_min.x + d.x, b.bb_max.x + d.x,
		b.fix.x + d.x if b.fix.x != NOFIX else NOFIX)
	if nx <= 0:
		return 0
	var ny := _pair_axis(a.bb_min.y, a.bb_max.y, a.fix.y, b.bb_min.y + d.y, b.bb_max.y + d.y,
		b.fix.y + d.y if b.fix.y != NOFIX else NOFIX)
	return maxi(0, nx * ny)

## If b's start sits at `d` in a's frame: how many ways both maps fit the real one at once.
func _placements(a: Book, b: Book, d: Vector2i) -> int:
	var n := _box_fits(a, b, d)
	if n <= 0:
		return 0
	var dk := Vector3i(d.x, d.y, 0)
	var ae: Dictionary = a.edges
	for k in b.edges:
		var sa: int = ae.get(k + dk, 0)
		if sa != 0 and _clash(sa, b.edges[k]):
			return 0
	return n

## What a and b (b's start at `d` in a's frame) know between them about line `k`.
func _merged(a: Book, b: Book, d: Vector2i, k: Vector3i) -> int:
	var sa: int = a.edges.get(k, 0)
	var sb: int = b.edges.get(k - Vector3i(d.x, d.y, 0), 0)
	if sa == OPEN or sa == BLOWN or sb == OPEN or sb == BLOWN:
		return OPEN
	if sa != 0 or sb != 0:
		return WALL
	return 0

## Chance a bullet fired from `from` heading `dir` reaches `target` (a's frame), given what
## both maps know about the lines in between. 0 when the target is not on that line.
func _pass(a: Book, b: Book, d: Vector2i, from: Vector2i, dir: int, target: Vector2i) -> float:
	var delta := target - from
	var step := DIRS[dir]
	var k := 0
	if step.x != 0:
		if delta.y != 0 or delta.x * step.x < 0:
			return 0.0
		k = absi(delta.x)
	else:
		if delta.x != 0 or delta.y * step.y < 0:
			return 0.0
		k = absi(delta.y)
	var p := 1.0
	var c := from
	for i in k:
		var s := _merged(a, b, d, _ek(c, dir))
		if s == WALL:
			return 0.0
		if s == 0:
			p *= 1.0 - WALL_PRIOR
		c += step
	return p

## Every place the other player's start could be in a's frame, each with a weight: the
## number of ways both maps fit the real one, and (if asked) how well that explains every
## bullet that missed.
func _hyps(a: Book, b: Book, use_shots: bool) -> Array:
	var out: Array = []
	for dx in range(-(N - 1), N):
		for dy in range(-(N - 1), N):
			var d := Vector2i(dx, dy)
			var w := float(_placements(a, b, d))
			if w <= 0.0:
				continue
			if use_shots:
				for s in a.shots:
					w *= 1.0 - _pass(a, b, d, s["from"], s["dir"], d + s["tpos"])
				for s in b.shots:
					w *= 1.0 - _pass(a, b, d, d + s["from"], s["dir"], s["tpos"])
				if w <= 0.0:
					continue
			out.append([d, w])
	return out

## ---- the brains ---------------------------------------------------------------------
## Each returns {kind, dir}. They read the two notebooks and nothing else.

func _think(who: int, lv: int) -> Dictionary:
	var me: Book = _books[who]
	var them: Book = _books[1 - who]
	if lv <= 1:
		return _think_easy(who)
	var hyps := _hyps(me, them, lv >= 3)
	var total := 0.0
	for h in hyps:
		total += h[1]
	if me.ammo > 0 and total > 0.0:
		var best_dir := -1
		var best_p := 0.0
		for dir in 4:
			var p := 0.0
			for h in hyps:
				p += h[1] * _pass(me, them, h[0], me.pos, dir, h[0] + them.pos)
			p /= total
			if p > best_p:
				best_p = p
				best_dir = dir
		# hard spends its first bullets on better than one-in-three, its last on a coin flip
		var need: float = 0.6 if lv == 2 else [0.0, 0.5, 0.42, 0.34][mini(me.ammo, 3)]
		if best_dir >= 0 and best_p >= need:
			return {"kind": "shoot", "dir": best_dir}
	return _plan(who, lv, hyps, total)

## easy: mostly the nearest new square, sometimes just a wander, the odd shot in the dark.
func _think_easy(who: int) -> Dictionary:
	var me: Book = _books[who]
	if me.ammo > 0 and _turns > 10 and randf() < 0.05:
		return {"kind": "shoot", "dir": randi() % 4}
	if randf() < 0.55:
		return _plan(who, 1, [], 0.0)
	var fresh: Array[int] = []
	var ok: Array[int] = []
	var walls: Array[int] = []
	for dir in 4:
		var s: int = me.edges.get(_ek(me.pos, dir), 0)
		if s == WALL or s == EDGE:
			if s == WALL:
				walls.append(dir)
			continue
		ok.append(dir)
		if not me.cells.has(me.pos + DIRS[dir]):
			fresh.append(dir)
	if not fresh.is_empty() and randf() < 0.75:
		return {"kind": "move", "dir": fresh.pick_random()}
	if not ok.is_empty():
		return {"kind": "move", "dir": ok.pick_random()}
	if me.dyn > 0 and not walls.is_empty():
		return {"kind": "blast", "dir": walls.pick_random()}
	return {"kind": "move", "dir": randi() % 4}

## Where to walk: the nearest square nobody has stood on, inside where the map could be.
## hard also skips squares it thinks the rival has already searched, walks round squares
## the rival could shoot into, and once the rival is out of bullets and it is fairly sure
## where the rival is, walks to a square with a clear line to it instead.
func _plan(who: int, lv: int, hyps: Array, total: float) -> Dictionary:
	var me: Book = _books[who]
	var them: Book = _books[1 - who]
	var reg := _region(me)
	var cert := _certain(me)
	var top := Vector2i.ZERO
	var top_w := 0.0
	for h in hyps:
		if h[1] > top_w:
			top_w = h[1]
			top = h[0]
	var sure := top_w / total if total > 0.0 else 0.0
	var helper: Book = them if lv >= 3 and sure >= 0.5 else null
	var allow_blast := me.dyn > 0 and lv >= 2
	var threat := {}
	if lv >= 3 and them.ammo > 0 and total > 0.0:
		threat = _threat_map(who, hyps, total, reg)
	var route := _routes(me, helper, top, reg, allow_blast, BLAST_COST[lv], threat)
	var cost: Dictionary = route["cost"]
	var first: Dictionary = route["first"]

	var goal := NONE
	if lv >= 3 and me.ammo > 0 and them.ammo == 0 and sure >= 0.5:
		var t := top + them.pos
		var best := INF
		for c in cost:
			if c == me.pos or (c.x != t.x and c.y != t.y):
				continue
			var dir := _dir_toward(c, t)
			if dir >= 0 and _pass(me, them, top, c, dir, t) >= 0.75 and cost[c] < best:
				best = cost[c]
				goal = c
		if best > 10.0:
			goal = NONE
	if goal == NONE:
		var searched := {}
		if helper != null:
			for c in them.cells:
				searched[c + top] = true
		var best := INF
		for c in cost:
			if me.cells.has(c) or searched.has(c):
				continue
			var v: float = cost[c] + randf() * 0.3
			if not cert.has_point(c):
				v += 2.0               # might be off the edge of the map
			if c == _ai_target[who]:
				v -= 1.0               # keep heading where it was heading
			if v < best:
				best = v
				goal = c
	_ai_target[who] = goal
	if goal == NONE or not first.has(goal) or int(first[goal]) < 0:
		return _wander(who)
	var dir0: int = first[goal]
	if _path_state(me, helper, top, _ek(me.pos, dir0)) == WALL:
		return {"kind": "blast", "dir": dir0}
	return {"kind": "move", "dir": dir0}

## hard only: for every square of the region, how likely the rival could shoot `who`
## there. Only the likeliest offsets are counted, which is plenty and keeps it quick.
func _threat_map(who: int, hyps: Array, total: float, reg: Rect2i) -> Dictionary:
	var me: Book = _books[who]
	var them: Book = _books[1 - who]
	var top: Array = hyps.duplicate()
	top.sort_custom(func(a, b): return a[1] > b[1])
	top.resize(mini(top.size(), 16))
	var out := {}
	for x in range(reg.position.x, reg.end.x):
		for y in range(reg.position.y, reg.end.y):
			var c := Vector2i(x, y)
			var p := 0.0
			for h in top:
				var t: Vector2i = h[0] + them.pos
				if t.x != c.x and t.y != c.y:
					continue
				var dir := 0 if t == c else _dir_toward(t, c)
				p += h[1] * _pass(me, them, h[0], t, dir, c)
			if p > 0.0:
				out[c] = p / total
	return out

func _wander(who: int) -> Dictionary:
	var me: Book = _books[who]
	var ok: Array[int] = []
	for dir in 4:
		var s: int = me.edges.get(_ek(me.pos, dir), 0)
		if s != WALL and s != EDGE:
			ok.append(dir)
	return {"kind": "move", "dir": ok.pick_random() if not ok.is_empty() else randi() % 4}

static func _dir_toward(c: Vector2i, t: Vector2i) -> int:
	if c.x == t.x and c.y != t.y:
		return 2 if t.y > c.y else 0
	if c.y == t.y and c.x != t.x:
		return 1 if t.x > c.x else 3
	return -1

## A line as a walker sees it: its own notebook first, the rival's (if trusted) to fill gaps.
func _path_state(me: Book, helper: Book, d: Vector2i, k: Vector3i) -> int:
	var s: int = me.edges.get(k, 0)
	if helper != null:
		var sh: int = helper.edges.get(k - Vector3i(d.x, d.y, 0), 0)
		if s == 0 or (s == WALL and sh == BLOWN):
			s = sh
	return s

## Cheapest way to every square of the region: known passages cost 1, untried lines a bit
## more (they may be walls), a known wall the price of a stick of dynamite if there is one.
func _routes(me: Book, helper: Book, d: Vector2i, reg: Rect2i, allow_blast: bool,
		blast_cost: float, threat: Dictionary) -> Dictionary:
	var cost := {me.pos: 0.0}
	var first := {me.pos: -1}
	var done := {}
	var open: Array[Vector2i] = [me.pos]
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			if cost[open[i]] < cost[open[bi]]:
				bi = i
		var c: Vector2i = open[bi]
		open.remove_at(bi)
		if done.has(c):
			continue
		done[c] = true
		for dir in 4:
			var n := c + DIRS[dir]
			if not reg.has_point(n) or done.has(n):
				continue
			var s := _path_state(me, helper, d, _ek(c, dir))
			var step := 1.5
			if s == OPEN or s == BLOWN:
				step = 1.0
			elif s == EDGE:
				continue
			elif s == WALL:
				if not allow_blast:
					continue
				step = blast_cost
			var nc: float = cost[c] + step + float(threat.get(n, 0.0)) * THREAT_COST
			if nc < float(cost.get(n, INF)):
				cost[n] = nc
				first[n] = dir if c == me.pos else first[c]
				open.append(n)
	return {"cost": cost, "first": first}

## ---- a turn -------------------------------------------------------------------------

func _act(who: int, kind: String, dir: int) -> void:
	var b: Book = _books[who]
	var o: Book = _books[1 - who]
	var here := _starts[who] + b.pos
	var who_s := "you" if who == YOU else "rival"
	var role := "player" if who == YOU else "hazard"
	var dn: String = DIR_NAMES[dir]
	var k := _ek(b.pos, dir)
	_turns += 1
	match kind:
		"move":
			if _blocked(here, dir):
				if b.edges.get(k, 0) == 0:
					b.edges[k] = WALL
				_say("%s: %s - wall" % [who_s, dn], role)
				_nudge[who] = [dir, 0.22]
				Audio.play("thud", 0.1)
				Juice.text(self, _blob_of(who).position + Vector2(0, -10), "wall", Palette.col("ink"))
				if who == YOU:
					Juice.shake(2.0)
				Probe.event("bump", {"who": who_s})
			else:
				var s: int = b.edges.get(k, 0)
				# it was a wall when we bumped it, so someone has blasted it since
				b.edges[k] = BLOWN if s == WALL or s == BLOWN else OPEN
				b.pos += DIRS[dir]
				var fresh := not b.cells.has(b.pos)
				b.cells[b.pos] = true
				_add_inside(b, b.pos)
				b.trail.append(b.pos)
				_say("%s: %s" % [who_s, dn], role)
				Audio.play("step_wood", 0.15)
				if who == YOU and fresh:
					add_score(1)
				Probe.event("step", {"who": who_s, "fresh": fresh})
				if _starts[who] + b.pos == _treasure:
					_end(who, "treasure")
					return
		"shoot":
			b.ammo -= 1
			b.shots.append({"from": b.pos, "dir": dir, "tpos": o.pos})
			var target := _starts[1 - who] + o.pos
			var c := here
			var hit := c == target
			while not hit and not _blocked(c, dir):
				c += DIRS[dir]
				hit = c == target
			_fx.append({"kind": "beam", "who": who, "at": b.pos, "dir": dir, "t": 0.0})
			Audio.play("impact_punch", 0.05)
			Juice.shake(3.0)
			Probe.event("shot", {"who": who_s, "hit": hit})
			if hit:
				_end(who, "shot")
				return
			_say("%s: shot %s - miss" % [who_s, dn], role)
		"blast":
			b.dyn -= 1
			var n := here + DIRS[dir]
			var what := ""
			if not _in_world(n):
				b.edges[k] = EDGE
				_pin_edge(b, b.pos, dir)
				what = "outer wall holds"
				Audio.play("impact_metal", 0.05)
			elif _walls.has(_ek(here, dir)):
				_walls.erase(_ek(here, dir))
				_blown[_ek(here, dir)] = true
				b.edges[k] = BLOWN
				_add_inside(b, b.pos + DIRS[dir])
				what = "boom, wall gone"
				Audio.play("explode", 0.05)
			else:
				if b.edges.get(k, 0) != BLOWN:
					b.edges[k] = OPEN
				_add_inside(b, b.pos + DIRS[dir])
				what = "nothing there"
				Audio.play("impact_soft", 0.05)
			_fx.append({"kind": "boom", "who": who, "k": k, "t": 0.0})
			Juice.shake(5.0 if what.begins_with("boom") else 2.5)
			_say("%s: blast %s - %s" % [who_s, dn, what], role)
			Probe.event("blast", {"who": who_s, "result": what})
	_check_known(who)
	_turn = 1 - who
	_wait = _pause_for(_turn)
	_refresh_views(false)
	_refresh_ui()

func _pause_for(who: int) -> float:
	if _autoplay > 0:
		return AUTO_PAUSE
	return AI_PAUSE if who == RIVAL else 0.0

## Once a map has been walked (or blasted) wall to wall both ways, its owner knows where
## they stand. Worth saying out loud: it is half of the puzzle.
func _check_known(who: int) -> void:
	if _known_self[who]:
		return
	var r := _region(_books[who])
	if r.size == Vector2i(N, N):
		_known_self[who] = true
		if who == YOU:
			_say("you know where you are now", "friend")
			Audio.play("voice_correct", 0.0)
			Juice.pop(_me_blob, 1.8)
		else:
			_say("rival knows where it is now", "warn")
		Probe.event("located", {"who": "you" if who == YOU else "rival"})

func _end(winner: int, how: String) -> void:
	_over = true
	_winner = winner
	_reveal_left = REVEAL_TIME
	var mult: int = LEVELS[_level - 1]["mult"]
	if winner == YOU:
		if how == "treasure":
			_say("you found the treasure!", "prize")
			add_score(100 * mult)
		else:
			_say("hit! you got the rival", "player")
			add_score(150 * mult)
		# winning moves you up a difficulty for "play again"
		Flow.current_config["level"] = mini(_level + 1, LEVELS.size())
		Audio.play("voice_you_win", 0.0)
	else:
		if how == "treasure":
			_say("the rival found the treasure", "hazard")
		elif how == "shot":
			_say("the rival shot you", "hazard")
		else:
			_say("you gave up", "hazard")
		Audio.play("voice_you_lose", 0.0)
	if how == "treasure":
		Audio.play("coin", 0.0)
	if how == "shot":
		Juice.hit(8.0)
		Juice.flash(_blob_of(1 - winner))
	Probe.event("treasure_found" if how == "treasure" else ("shot_hit" if how == "shot" else "gave_up"),
		{"winner": "you" if winner == YOU else "rival", "turns": _turns})
	_gold_blob.visible = true
	_ghost_blob.visible = true
	_refresh_views(false)
	_refresh_ui()
	Probe.capture("end")

## ---- input ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _books.is_empty():
		return
	for i in 2:
		var g: Rect2 = _view_goal[i]
		var v: Rect2 = _view[i]
		var a := 1.0 - exp(-7.0 * delta)
		_view[i] = Rect2(v.position.lerp(g.position, a), v.size.lerp(g.size, a))
		_nudge[i][1] = maxf(0.0, _nudge[i][1] - delta)
	var keep: Array = []
	for f in _fx:
		f["t"] += delta
		if f["t"] < 0.8:
			keep.append(f)
	_fx = keep
	_place_blobs(1.0 - exp(-16.0 * delta))
	queue_redraw()

	if _over:
		_reveal_left -= delta
		if _reveal_left <= 0.0 and not finished:
			if _winner == YOU:
				win()
			else:
				lose()
		return

	if _turn == RIVAL or _autoplay > 0:
		_wait -= delta
		if _wait <= 0.0:
			var m := _think(_turn, _level if _turn == RIVAL else _autoplay)
			_act(_turn, m["kind"], m["dir"])
		return

	if PInput.just_pressed("action_b"):
		_cycle_mode()
	if PInput.just_pressed("action_a"):
		_auto_turn()
		return
	for d in 4:
		var act: String = ["move_up", "move_right", "move_down", "move_left"][d]
		if PInput.just_pressed(act):
			_human(d)
			return
	if _idle_limit > 0.0:
		_idle_t += delta
		if _idle_t > _idle_limit:
			Probe.event("resigned_idle", {"after": _idle_limit})
			_end(RIVAL, "idle")

func _input(event: InputEvent) -> void:
	if _over or not _ghost:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if not mb.pressed:
			_drag = false
			return
		if Flow.pointer_over_hud() or not MY_PANEL.has_point(mb.position):
			return
		_drag = true
		_drag_from = mb.position
		_drag_off0 = _ghost_off
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		var cs := _cs(MY_PANEL, _view[YOU])
		var moved := (mm.position - _drag_from) / cs
		var off := _drag_off0 + Vector2i(roundi(moved.x), roundi(moved.y))
		off = off.clamp(Vector2i(-(N - 1), -(N - 1)), Vector2i(N - 1, N - 1))
		if off != _ghost_off:
			_ghost_off = off
			_check_ghost()
			Audio.play("click", 0.2, -8.0)

func _human(d: int) -> void:
	if _over or _turn != YOU:
		return
	var b: Book = _books[YOU]
	if (_mode == "shoot" and b.ammo <= 0) or (_mode == "blast" and b.dyn <= 0):
		_mode = "walk"
		_refresh_ui()
		return
	_idle_t = 0.0
	var kind: String = "move" if _mode == "walk" else _mode
	_mode = "walk"
	_act(YOU, kind, d)

func _auto_turn() -> void:
	if _over or _turn != YOU:
		return
	_idle_t = 0.0
	_mode = "walk"
	var m := _think(YOU, 2)
	_act(YOU, m["kind"], m["dir"])

func _cycle_mode() -> void:
	var b: Book = _books[YOU]
	var i := MODES.find(_mode)
	for step in range(1, 4):
		var m: String = MODES[(i + step) % 3]
		if m == "walk" or (m == "shoot" and b.ammo > 0) or (m == "blast" and b.dyn > 0):
			_set_mode(m)
			return

func _set_mode(m: String) -> void:
	var b: Book = _books[YOU]
	if (m == "shoot" and b.ammo <= 0) or (m == "blast" and b.dyn <= 0):
		return
	_mode = m
	Audio.play("click", 0.1)
	_refresh_ui()

func _toggle_ghost() -> void:
	_ghost = not _ghost
	_drag = false
	_count_places()
	Audio.play("select", 0.1)
	_check_ghost()
	_refresh_ui()

## Lay the rival's map over yours at the chosen offset and look for disagreements: a line
## one of you walked through that the other bumped into, or the two maps together being
## too big for N x N.
func _check_ghost() -> void:
	var me: Book = _books[YOU]
	var rv: Book = _books[RIVAL]
	_ghost_clash.clear()
	var dk := Vector3i(_ghost_off.x, _ghost_off.y, 0)
	for k in rv.edges:
		var sa: int = me.edges.get(k + dk, 0)
		if sa != 0 and _clash(sa, rv.edges[k]):
			_ghost_clash.append(k + dk)
	_ghost_fits = _box_fits(me, rv, _ghost_off) > 0
	_refresh_ui()

## Every offset at which the two maps agree. Only redone when a map changes, not while
## dragging: it is a few hundred overlays.
func _count_places() -> void:
	_ghost_places = 0
	for dx in range(-(N - 1), N):
		for dy in range(-(N - 1), N):
			if _placements(_books[YOU], _books[RIVAL], Vector2i(dx, dy)) > 0:
				_ghost_places += 1

## ---- the screen ---------------------------------------------------------------------

func _build_ui() -> void:
	# Buttons live in a CanvasLayer above the shell's HUD (10), otherwise Flow's
	# full-screen Control takes the click first and the button is decorative.
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	var hider := PauseHider.new()
	hider.process_mode = Node.PROCESS_MODE_ALWAYS
	hider.target = _layer
	hider.game = self
	add_child(hider)

	_status = UIKit.label("", 13, "ink")
	_status.position = Vector2(96, 8)
	_status.size = Vector2(400, 20)
	_layer.add_child(_status)

	for i in 2:
		var l := _small_label(Vector2(488, 36 + i * 15), 11, "player" if i == 0 else "hazard")
		_res_lbl.append(l)
	for i in 7:
		_log_lbls.append(_small_label(Vector2(488, 70 + i * 15), 10, "ink"))
	_ghost_lbl = _small_label(Vector2(14, 334), 11, "friend")

	var labels := {"walk": "walk", "shoot": "shoot", "blast": "blast"}
	var y := 190.0
	for m in MODES:
		var b := _button(labels[m], _set_mode.bind(m), Rect2(334, y, 92, 28))
		_mode_btns[m] = b
		y += 32.0
	_ghost_btn = _button("ghost", _toggle_ghost, Rect2(334, y, 92, 28))
	y += 32.0
	_button("auto", _auto_turn, Rect2(334, y, 92, 28))

	for d in 4:
		var c := PAD_CENTER + Vector2(DIRS[d]) * (PAD_BTN + 3.0)
		var b := _button("", _human.bind(d), Rect2(c - Vector2.ONE * PAD_BTN * 0.5, Vector2.ONE * PAD_BTN))
		b.draw.connect(_draw_arrow.bind(b, d))
		_pad.append(b)

func _small_label(at: Vector2, size: int, role: String) -> Label:
	var l := UIKit.label("", size, role)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.position = at
	l.size = Vector2(150, 14)
	_layer.add_child(l)
	return l

func _button(text: String, cb: Callable, r: Rect2) -> Button:
	var b := UIKit.button(text, cb)
	b.custom_minimum_size = r.size
	b.size = r.size
	b.position = r.position
	b.add_theme_font_size_override("font_size", 13)
	# no keyboard focus: space and the arrows already mean something here, and a focused
	# button would take them too
	b.focus_mode = Control.FOCUS_NONE
	_layer.add_child(b)
	_buttons.append(b)
	return b

func _draw_arrow(b: Button, d: int) -> void:
	var c := b.size * 0.5
	var f := Vector2(DIRS[d])
	var s := Vector2(-f.y, f.x)
	var r := b.size.x * 0.27
	var col := Palette.col(MODE_ROLE[_mode])
	if _turn != YOU or _over or _autoplay > 0:
		col.a = 0.3
	b.draw_colored_polygon(PackedVector2Array([c + f * r, c - f * r * 0.6 + s * r,
		c - f * r * 0.6 - s * r]), col)

func _say(text: String, role: String) -> void:
	_log.append([text, role])
	while _log.size() > _log_lbls.size():
		_log.pop_front()
	if _layer != null:
		_refresh_ui()

func _refresh_ui() -> void:
	if _status == null or _books.is_empty():
		return
	var me: Book = _books[YOU]
	var rv: Book = _books[RIVAL]
	var lv := _level_name()
	if _over:
		_status.text = "%s - the real map" % lv
	elif _turn == YOU and _autoplay == 0:
		_status.text = "%s  -  your turn: %s" % [lv, _mode]
	else:
		_status.text = "%s  -  rival is thinking..." % lv
	_res_lbl[0].text = "you    %d shots  %d blasts" % [me.ammo, me.dyn]
	_res_lbl[1].text = "rival  %d shots  %d blasts" % [rv.ammo, rv.dyn]
	for i in _log_lbls.size():
		var l: Label = _log_lbls[i]
		if i < _log.size():
			l.text = _log[i][0]
			l.add_theme_color_override("font_color", Palette.col(_log[i][1]))
			l.modulate.a = 0.45 + 0.55 * float(i + 1) / float(_log.size())
		else:
			l.text = ""
	_mode_btns["shoot"].text = "shoot %d" % me.ammo
	_mode_btns["blast"].text = "blast %d" % me.dyn
	for m in MODES:
		var b: Button = _mode_btns[m]
		var on: bool = m == _mode
		b.add_theme_color_override("font_color", Palette.col(MODE_ROLE[m] if on else "ink"))
		b.modulate.a = 1.0 if on else 0.6
		b.disabled = (m == "shoot" and me.ammo <= 0) or (m == "blast" and me.dyn <= 0)
	_ghost_btn.text = "ghost: on" if _ghost else "ghost"
	_ghost_btn.add_theme_color_override("font_color", Palette.col("hazard" if _ghost else "ink"))
	if _ghost and not _over:
		if not _ghost_fits:
			_ghost_lbl.text = "ghost: too big for %d x %d" % [N, N]
			_ghost_lbl.add_theme_color_override("font_color", Palette.col("warn"))
		elif not _ghost_clash.is_empty():
			_ghost_lbl.text = "ghost: walls disagree"
			_ghost_lbl.add_theme_color_override("font_color", Palette.col("warn"))
		else:
			if _ghost_places <= 1:
				_ghost_lbl.text = "ghost: fits - the only place it can!"
			else:
				_ghost_lbl.text = "ghost: fits  (%d places do)" % _ghost_places
			_ghost_lbl.add_theme_color_override("font_color", Palette.col("friend"))
	else:
		_ghost_lbl.text = ""
	for b in _buttons:
		if b in _pad or b in _mode_btns.values() or b == _ghost_btn:
			b.visible = not _over
		else:
			b.visible = not _over and _autoplay == 0
		b.queue_redraw()

## ---- views: squares to pixels -------------------------------------------------------

func _refresh_views(snap: bool) -> void:
	for i in 2:
		var r: Rect2i
		if _over:
			r = Rect2i(-_starts[i], Vector2i(N, N))
		else:
			r = _region(_books[i])
		_view_goal[i] = Rect2(Vector2(r.position), Vector2(r.size)).grow(0.35)
		if snap:
			_view[i] = _view_goal[i]
	if _ghost:
		_count_places()
		_check_ghost()

func _cs(panel: Rect2, v: Rect2) -> float:
	return minf(panel.size.x / v.size.x, panel.size.y / v.size.y)

## A point in squares (corner coordinates) to a point on screen.
func _px(panel: Rect2, v: Rect2, p: Vector2) -> Vector2:
	return panel.get_center() + (p - v.get_center()) * _cs(panel, v)

func _ctr(panel: Rect2, v: Rect2, c: Vector2i) -> Vector2:
	return _px(panel, v, Vector2(c) + Vector2(0.5, 0.5))

func _blob_of(who: int) -> Blob:
	return _me_blob if who == YOU else _rv_blob

func _place_blobs(a: float) -> void:
	var me: Book = _books[YOU]
	var rv: Book = _books[RIVAL]
	var cs0 := _cs(MY_PANEL, _view[YOU])
	var cs1 := _cs(RIVAL_PANEL, _view[RIVAL])
	_set_blob(_me_blob, _ctr(MY_PANEL, _view[YOU], me.pos) + _nudge_px(YOU, cs0), cs0, a)
	_set_blob(_rv_blob, _ctr(RIVAL_PANEL, _view[RIVAL], rv.pos) + _nudge_px(RIVAL, cs1), cs1, a)
	var off := _starts[RIVAL] - _starts[YOU] if _over else _ghost_off
	var gp := _ctr(MY_PANEL, _view[YOU], rv.pos + off)
	_set_blob(_ghost_blob, gp, cs0, a)
	_ghost_blob.visible = (_ghost or _over) and MY_PANEL.has_point(gp)
	_set_blob(_gold_blob, _ctr(MY_PANEL, _view[YOU], _treasure - _starts[YOU]), cs0, 1.0)

func _set_blob(b: Blob, p: Vector2, cs: float, a: float) -> void:
	b.position = b.position.lerp(p, a)
	var r := clampf(cs * 0.3, 3.0, 9.0)
	if absf(r - b.radius) > 0.2:
		b.radius = r
		b.queue_redraw()

func _nudge_px(who: int, cs: float) -> Vector2:
	var t: float = _nudge[who][1]
	if t <= 0.0:
		return Vector2.ZERO
	return Vector2(DIRS[_nudge[who][0]]) * cs * 0.3 * sin(t / 0.22 * PI)

## ---- drawing ---------------------------------------------------------------------------

func _draw() -> void:
	if _books.is_empty():
		return
	var me: Book = _books[YOU]
	var rv: Book = _books[RIVAL]

	var v0: Rect2 = _view[YOU]
	_draw_panel(MY_PANEL)
	if _over:
		var w := Rect2i(-_starts[YOU], Vector2i(N, N))
		_draw_paper(MY_PANEL, v0, w, w, "friend")
		_draw_truth(MY_PANEL, v0, _starts[YOU])
	else:
		var known: bool = _known_self[YOU]
		_draw_paper(MY_PANEL, v0, _region(me), _certain(me), "friend" if known else "accent")
	if _ghost or _over:
		var off := _starts[RIVAL] - _starts[YOU] if _over else _ghost_off
		_draw_marks(MY_PANEL, v0, rv, off, "hazard", "hazard", 0.8)
	_draw_marks(MY_PANEL, v0, me, Vector2i.ZERO, "player", "ink", 1.0)
	if _ghost and not _over:
		var cs := _cs(MY_PANEL, v0)
		for k in _ghost_clash:
			var pts := _edge_px(MY_PANEL, v0, k)
			var m: Vector2 = (pts[0] + pts[1]) * 0.5
			if MY_PANEL.has_point(m):
				var r := maxf(3.0, cs * 0.22)
				var wc := Palette.col("warn")
				draw_line(m + Vector2(-r, -r), m + Vector2(r, r), wc, 2.0)
				draw_line(m + Vector2(-r, r), m + Vector2(r, -r), wc, 2.0)
	_caption(MY_PANEL.position + Vector2(6, 13), "your map", 10, "player")

	var v1: Rect2 = _view[RIVAL]
	_draw_panel(RIVAL_PANEL)
	if _over:
		var w1 := Rect2i(-_starts[RIVAL], Vector2i(N, N))
		_draw_paper(RIVAL_PANEL, v1, w1, w1, "friend")
		_draw_truth(RIVAL_PANEL, v1, _starts[RIVAL])
	else:
		_draw_paper(RIVAL_PANEL, v1, _region(rv), _certain(rv), "warn" if _known_self[RIVAL] else "accent")
	_draw_marks(RIVAL_PANEL, v1, rv, Vector2i.ZERO, "hazard", "ink", 1.0)
	_caption(RIVAL_PANEL.position + Vector2(5, 12), "rival's map", 9, "hazard")

	for f in _fx:
		var who: int = f["who"]
		var panel := MY_PANEL if who == YOU else RIVAL_PANEL
		_draw_fx(f, panel, _view[who], Vector2i.ZERO)
		if who == RIVAL and _ghost and not _over:
			_draw_fx(f, MY_PANEL, v0, _ghost_off)

## A panel's name in its corner, on a scrap of backing so the map can run underneath it.
func _caption(at: Vector2, text: String, size: int, role: String) -> void:
	var font := ThemeDB.fallback_font
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	draw_rect(Rect2(at + Vector2(-3, -sz.y + 2), sz + Vector2(6, 2)), Color(Palette.col("bg_alt"), 0.85))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(Palette.col(role), 0.8))

func _draw_panel(panel: Rect2) -> void:
	draw_rect(panel, Color(Palette.col("bg_alt"), 0.85))
	draw_rect(panel, Color(Palette.col("accent"), 0.35), false, 1.5)

## Squared paper over everywhere the map could still be, brighter where it certainly is,
## and a frame round the lot. The frame is the map's size exactly once you know where
## you are.
func _draw_paper(panel: Rect2, v: Rect2, reg: Rect2i, cert: Rect2i, frame_role: String) -> void:
	var ink := Palette.col("ink")
	var c0 := _px(panel, v, Vector2(cert.position))
	var c1 := _px(panel, v, Vector2(cert.end))
	_box(panel, Rect2(c0, c1 - c0), Color(ink, 0.05))
	var line := Color(ink, 0.09)
	for x in range(reg.position.x, reg.end.x + 1):
		_seg(panel, _px(panel, v, Vector2(x, reg.position.y)), _px(panel, v, Vector2(x, reg.end.y)), line, 1.0)
	for y in range(reg.position.y, reg.end.y + 1):
		_seg(panel, _px(panel, v, Vector2(reg.position.x, y)), _px(panel, v, Vector2(reg.end.x, y)), line, 1.0)
	var r0 := _px(panel, v, Vector2(reg.position))
	var r1 := _px(panel, v, Vector2(reg.end))
	var fc := Color(Palette.col(frame_role), 0.55)
	_seg(panel, r0, Vector2(r1.x, r0.y), fc, 1.5)
	_seg(panel, Vector2(r0.x, r1.y), r1, fc, 1.5)
	_seg(panel, r0, Vector2(r0.x, r1.y), fc, 1.5)
	_seg(panel, Vector2(r1.x, r0.y), r1, fc, 1.5)

## The end-of-game reveal: every real wall, the blasted ones, the outer wall.
func _draw_truth(panel: Rect2, v: Rect2, origin: Vector2i) -> void:
	var cs := _cs(panel, v)
	var dk := Vector3i(origin.x, origin.y, 0)
	var wall := Color(Palette.col("ink"), 0.55)
	for k in _walls:
		var pts := _edge_px(panel, v, k - dk)
		_seg(panel, pts[0], pts[1], wall, maxf(1.5, cs * 0.08))
	for k in _blown:
		_draw_blown(panel, v, k - dk, Color(Palette.col("warn"), 0.6), cs)
	var r0 := _px(panel, v, Vector2(-origin))
	var r1 := _px(panel, v, Vector2(-origin + Vector2i(N, N)))
	var ec := Palette.col("warn")
	var w := maxf(2.0, cs * 0.12)
	_seg(panel, r0, Vector2(r1.x, r0.y), ec, w)
	_seg(panel, Vector2(r0.x, r1.y), r1, ec, w)
	_seg(panel, r0, Vector2(r0.x, r1.y), ec, w)
	_seg(panel, Vector2(r1.x, r0.y), r1, ec, w)

## One notebook drawn onto a panel, shifted by `off` squares: squares walked on, the trail,
## the start ring, and every line it knows about.
func _draw_marks(panel: Rect2, v: Rect2, b: Book, off: Vector2i, role: String, wall_role: String,
		alpha: float) -> void:
	var col := Palette.col(role)
	var cs := _cs(panel, v)
	for c in b.cells:
		var cc: Vector2i = c + off
		var p := _px(panel, v, Vector2(cc))
		_box(panel, Rect2(p + Vector2.ONE, Vector2(cs, cs) - Vector2.ONE * 2.0), Color(col, 0.14 * alpha))
	var tw := maxf(1.5, cs * 0.09)
	for i in range(1, b.trail.size()):
		_seg(panel, _ctr(panel, v, b.trail[i - 1] + off), _ctr(panel, v, b.trail[i] + off),
			Color(col, 0.5 * alpha), tw)
	var s := _ctr(panel, v, off)
	if panel.grow(-2.0).has_point(s):
		draw_arc(s, cs * 0.26, 0.0, TAU, 20, Color(col, 0.85 * alpha), 1.5)
	var dk := Vector3i(off.x, off.y, 0)
	var wc := Color(Palette.col(wall_role), alpha)
	var ec := Color(Palette.col("warn"), alpha)
	for k in b.edges:
		var st: int = b.edges[k]
		if st == OPEN:
			continue
		var kk: Vector3i = k + dk
		if st == BLOWN:
			_draw_blown(panel, v, kk, Color(ec, 0.75 * alpha), cs)
			continue
		var pts := _edge_px(panel, v, kk)
		if st == WALL:
			_seg(panel, pts[0], pts[1], wc, maxf(2.0, cs * 0.14))
		else:
			_seg(panel, pts[0], pts[1], ec, maxf(2.5, cs * 0.2))

## A blasted wall: two stubs at its ends with the middle gone.
func _draw_blown(panel: Rect2, v: Rect2, k: Vector3i, col: Color, cs: float) -> void:
	var pts := _edge_px(panel, v, k)
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var w := maxf(1.5, cs * 0.1)
	_seg(panel, a, a.lerp(b, 0.22), col, w)
	_seg(panel, b.lerp(a, 0.22), b, col, w)

func _draw_fx(f: Dictionary, panel: Rect2, v: Rect2, off: Vector2i) -> void:
	var t: float = f["t"]
	var who: int = f["who"]
	var col := Palette.col("player" if who == YOU else "hazard")
	var cs := _cs(panel, v)
	if f["kind"] == "beam":
		# nobody hears how far a bullet went, so the beam runs off the edge of the paper
		var a := _ctr(panel, v, f["at"] + off)
		var d := Vector2(DIRS[f["dir"]])
		var b := a + d * 2000.0
		b = Vector2(clampf(b.x, panel.position.x, panel.end.x), clampf(b.y, panel.position.y, panel.end.y))
		if panel.has_point(a):
			_seg(panel, a, b, Color(col, 1.0 - t / 0.8), maxf(2.0, cs * 0.12))
	else:
		var k: Vector3i = f["k"] + Vector3i(off.x, off.y, 0)
		var pts := _edge_px(panel, v, k)
		var m: Vector2 = (pts[0] + pts[1]) * 0.5
		if panel.has_point(m):
			var wc := Palette.col("warn")
			draw_circle(m, cs * (0.2 + t * 0.9), Color(wc, 0.35 * (1.0 - t / 0.8)))
			draw_arc(m, cs * (0.3 + t * 1.4), 0.0, TAU, 24, Color(wc, 1.0 - t / 0.8), 2.0)

func _edge_px(panel: Rect2, v: Rect2, k: Vector3i) -> Array:
	if k.z == 0:
		return [_px(panel, v, Vector2(k.x + 1, k.y)), _px(panel, v, Vector2(k.x + 1, k.y + 1))]
	return [_px(panel, v, Vector2(k.x, k.y + 1)), _px(panel, v, Vector2(k.x + 1, k.y + 1))]

## A straight line (every line here is level or upright) cut to the panel it belongs to,
## so a map sliding around never draws over its neighbour.
func _seg(panel: Rect2, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	if absf(a.y - b.y) < 0.01:
		if a.y < panel.position.y or a.y > panel.end.y:
			return
		var x0 := clampf(minf(a.x, b.x), panel.position.x, panel.end.x)
		var x1 := clampf(maxf(a.x, b.x), panel.position.x, panel.end.x)
		if x1 - x0 > 0.5:
			draw_line(Vector2(x0, a.y), Vector2(x1, a.y), col, w)
	else:
		if a.x < panel.position.x or a.x > panel.end.x:
			return
		var y0 := clampf(minf(a.y, b.y), panel.position.y, panel.end.y)
		var y1 := clampf(maxf(a.y, b.y), panel.position.y, panel.end.y)
		if y1 - y0 > 0.5:
			draw_line(Vector2(a.x, y0), Vector2(a.x, y1), col, w)

func _box(panel: Rect2, r: Rect2, col: Color) -> void:
	var c := r.abs().intersection(panel)
	if c.has_area():
		draw_rect(c, col)
