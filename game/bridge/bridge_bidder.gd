extends RefCounted
## The bidding brain. One natural system, the kind most people learn first (see GAME.md):
## five-card majors, 15-17 no trumps with Stayman, strong 2C, weak twos, takeout doubles,
## negative doubles, Blackwood. Every computer seat bids it and reads everybody else's
## calls -- including yours -- as if they were bid in it too.
##
## The same role logic runs in two directions. choose() decides a call; meaning() reads
## one back ("partner's 2H shows 6-9 and three hearts") and infer() adds those readings
## up per seat, which is how a later call knows what partner holds.

const R := preload("res://game/bridge/bridge_rules.gd")

const C := 0
const D := 1
const H := 2
const S := 3
const NT := 4
const PASS := 0
const DBL := 1
const RDBL := 2

## ---- the hand ------------------------------------------------------------------------

static func evaluate(hand: Array) -> Dictionary:
	var l := R.lengths(hand)
	var short := 13
	for n in l:
		short = mini(short, n)
	return {"hand": hand, "hcp": R.hcp(hand), "len": l, "bal": R.balanced(l),
		"semi": short >= 2}

static func stopper(hand: Array, s: int) -> bool:
	var cs := R.cards_in(hand, s)
	var n := cs.size()
	for c in cs:
		var r := R.rank_of(c)
		if r == 12 or (r == 11 and n >= 2) or (r == 10 and n >= 3) or (r == 9 and n >= 4):
			return true
	return false

## Honours among the top five in a suit: how good a suit is to bid.
static func quality(hand: Array, s: int) -> int:
	var n := 0
	for c in R.cards_in(hand, s):
		if R.rank_of(c) >= 8:
			n += 1
	return n

static func aces(hand: Array) -> int:
	var n := 0
	for c in hand:
		if R.rank_of(c) == 12:
			n += 1
	return n

## Points for shape once a trump suit is found: shortness as dummy, length as the long hand.
static func shape_pts(e: Dictionary, trump: int) -> int:
	var l: Array = e["len"]
	if trump < 0 or trump > 3 or l[trump] < 3:
		return 0
	var p := 0
	for s in 4:
		if s == trump:
			continue
		match int(l[s]):
			0: p += 5 if l[trump] >= 4 else 3
			1: p += 3 if l[trump] >= 4 else 2
			2: p += 1
	if l[trump] >= 5:
		p = p / 2 + (l[trump] - 5)
	return p

static func _game_level(strain: int) -> int:
	return 3 if strain == NT else (4 if strain >= H else 5)

static func _game_pts(strain: int) -> int:
	return 28 if strain <= D else 25

## ---- the auction around one call ------------------------------------------------------

## Who opened, who has said what, and what this seat's call is responding to.
static func ctx(auc: Array, dealer: int, i: int) -> Dictionary:
	var seat := R.seat_at(dealer, i)
	var pard := R.partner_of(seat)
	var opener := -1
	var open_bid := -1
	var mine: Array = []
	var pards: Array = []
	var opps: Array = []
	var last := -1
	var last_seat := -1
	var dbl := 0
	for k in i:
		var c: int = auc[k]
		var s := R.seat_at(dealer, k)
		if R.is_bid(c):
			if opener < 0:
				opener = s
				open_bid = c
			last = c
			last_seat = s
			dbl = 0
		elif c == DBL:
			dbl = 1
		elif c == RDBL:
			dbl = 2
		if c != PASS:
			if s == seat:
				mine.append(k)
			elif s == pard:
				pards.append(k)
			else:
				opps.append(k)
	var role := "later"
	if opener < 0:
		role = "open"
	elif opener == pard and mine.is_empty():
		role = "respond"
	elif opener == seat and mine.size() == 1:
		role = "rebid"
	elif R.side_of(opener) != R.side_of(seat) and mine.is_empty():
		role = "overcall" if pards.is_empty() else "advance"
	# the partner's first real call and my first one, which the role handlers key on
	var pard_first := PASS
	if not pards.is_empty():
		pard_first = auc[pards[0]]
	# after I opened: partner's first call (pass counts, it is a response too)
	if role == "rebid":
		pard_first = PASS
		for k in range(mine[0] + 1, i):
			if R.seat_at(dealer, k) == pard:
				pard_first = auc[k]
				break
	var rho_call: int = auc[i - 1] if i >= 1 else PASS
	var interfered := false
	if opener >= 0:
		for k in opps:
			if k > _index_of_first_bid(auc):
				interfered = true
	var opp_suits: Array = []
	for k in opps:
		var c: int = auc[k]
		if R.is_bid(c) and R.bid_strain(c) < NT and not opp_suits.has(R.bid_strain(c)):
			opp_suits.append(R.bid_strain(c))
	return {"i": i, "seat": seat, "pard": pard, "opener": opener, "open_bid": open_bid,
		"mine": mine, "pards": pards, "opps": opps, "last": last, "last_seat": last_seat,
		"dbl": dbl, "role": role, "pard_first": pard_first, "rho_call": rho_call,
		"interfered": interfered, "opp_suits": opp_suits,
		"ours": last_seat >= 0 and R.side_of(last_seat) == R.side_of(seat)}

static func _index_of_first_bid(auc: Array) -> int:
	for k in auc.size():
		if R.is_bid(auc[k]):
			return k
	return -1

## The cheapest legal bid in `strain`, or -1 above seven.
static func cheapest(c: Dictionary, strain: int) -> int:
	var last: int = c["last"]
	var level := 1
	if last >= 0:
		level = R.bid_level(last) + (0 if strain > R.bid_strain(last) else 1)
	return R.make_bid(level, strain) if level <= 7 else -1

static func _at(c: Dictionary, level: int, strain: int) -> int:
	if level > 7:
		return -1
	var b := R.make_bid(level, strain)
	return b if b > int(c["last"]) else -1

## `extra` levels above the cheapest: 1 is a jump.
static func _jump(c: Dictionary, strain: int, extra: int) -> int:
	var b := cheapest(c, strain)
	if b < 0:
		return -1
	return _at(c, R.bid_level(b) + extra, strain)

static func _first(options: Array) -> int:
	for b in options:
		if int(b) >= 0:
			return b
	return -1

## ---- choosing a call ---------------------------------------------------------------------

## lvl: "easy" misjudges its hand by a couple of points and never competes or doubles;
## "normal" bids the system; "hard" also opens light, competes by the law of total tricks
## and doubles opponents who overreach.
static func choose(hand: Array, auc: Array, dealer: int, lvl: String, rng: RandomNumberGenerator) -> int:
	var i := auc.size()
	if i >= 40:
		return PASS
	var e := evaluate(hand)
	if lvl == "easy":
		e["hcp"] = maxi(0, int(e["hcp"]) + rng.randi_range(-2, 2))
	var c := ctx(auc, dealer, i)
	var call := -1
	match c["role"]:
		"open": call = _open(e, c, lvl)
		"respond": call = _respond(e, c, lvl)
		"rebid": call = _rebid(e, c, lvl)
		"overcall": call = _overcall(e, c, lvl)
		"advance": call = _advance(e, c, lvl)
	if call < 0:
		call = _later(e, c, lvl, auc, dealer)
	if call < 0 or not R.is_legal(auc, dealer, call):
		call = PASS
	return call

static func _open(e: Dictionary, c: Dictionary, lvl: String) -> int:
	var h: int = e["hcp"]
	var l: Array = e["len"]
	if e["bal"] and h >= 15 and h <= 17:
		return R.make_bid(1, NT)
	if e["bal"] and h >= 20 and h <= 21:
		return R.make_bid(2, NT)
	if h >= 22:
		return R.make_bid(2, C)
	var sl: Array = l.duplicate()
	sl.sort()
	var rule20: bool = h + int(sl[3]) + int(sl[2]) >= 20
	if h >= 12 or (lvl == "hard" and h >= 10 and rule20):
		return R.make_bid(1, _one_suit(l))
	if h >= 5 and h <= 10:
		var hand: Array = e["hand"]
		for s in [S, H, D]:
			if l[s] == 6 and quality(hand, s) >= 2:
				return R.make_bid(2, s)
		for s in [S, H, D, C]:
			if l[s] >= 7 and quality(hand, s) >= 2:
				return R.make_bid(4 if (l[s] >= 8 and s >= H) else 3, s)
	return PASS

static func _one_suit(l: Array) -> int:
	if l[S] >= 5 and l[S] >= l[H]:
		return S
	if l[H] >= 5:
		return H
	if l[D] >= 4 and l[D] >= l[C]:
		return D
	if l[C] > l[D]:
		return C
	if l[C] == 3 and l[D] == 3:
		return C
	return D

## -- responder's first call

static func _respond(e: Dictionary, c: Dictionary, lvl: String) -> int:
	var ob: int = c["open_bid"]
	var x := R.bid_strain(ob)
	var lv := R.bid_level(ob)
	if ob == R.make_bid(1, NT):
		return -1 if c["interfered"] else _resp_1nt(e, c)
	if ob == R.make_bid(2, NT):
		return -1 if c["interfered"] else _resp_2nt(e, c)
	if ob == R.make_bid(2, C):
		return -1 if c["interfered"] else _resp_2c(e, c)
	if lv == 1 and x < NT:
		return _resp_1suit(e, c, x, lvl)
	if lv >= 2 and x < NT:
		return -1 if c["interfered"] else _resp_preempt(e, c, x)
	return -1

static func _resp_1suit(e: Dictionary, c: Dictionary, x: int, lvl: String) -> int:
	var h: int = e["hcp"]
	var l: Array = e["len"]
	var need := 3 if x >= H else (4 if x == D else 5)
	var fit: bool = l[x] >= need
	var sp: int = h + (shape_pts(e, x) if fit else 0)
	if c["interfered"] and c["last"] != c["open_bid"]:
		return _resp_competitive(e, c, x, fit, sp, lvl)
	if c["rho_call"] == DBL and h >= 10 and not fit:
		return RDBL
	if sp < 6:
		return PASS
	if x >= H:
		if fit:
			if sp >= 13:
				if x == H and l[S] >= 4:
					return R.make_bid(1, S)
				var side := _longest_of(l, [C, D, H if x == S else -1], 3)
				if side >= 0:
					return cheapest(c, side)
				return _at(c, 4, x)
			if sp >= 10:
				return _at(c, 3, x)
			return _at(c, 2, x)
		if x == H and l[S] >= 4:
			return R.make_bid(1, S)
		if h <= 10:
			return R.make_bid(1, NT)
		if e["bal"]:
			return _at(c, 2, NT) if h <= 12 else _at(c, 3, NT)
		var best := -1
		for s in [C, D, H]:
			if s == x:
				continue
			var n := 5 if s == H else 4
			if l[s] >= n and (best < 0 or l[s] > l[best]):
				best = s
		if best >= 0:
			return cheapest(c, best)
		return _at(c, 2, NT) if h <= 12 else _at(c, 3, NT)
	# partner opened a minor: show a major first, up the line
	if l[H] >= 4 or l[S] >= 4:
		if l[S] >= 5 and l[S] >= l[H]:
			return R.make_bid(1, S)
		if l[H] >= 4:
			return R.make_bid(1, H)
		return R.make_bid(1, S)
	if x == C and l[D] >= 4:
		return R.make_bid(1, D)
	if fit:
		if h >= 13:
			if e["bal"]:
				return _at(c, 3, NT)
			if x == D and l[C] >= 4:
				return _at(c, 2, C)
			return _at(c, 3, x)
		if sp >= 10:
			return _at(c, 3, x)
		return _at(c, 2, x)
	if x == D and l[C] >= 4 and h >= 10 and not e["bal"]:
		return _at(c, 2, C)
	if h <= 10:
		return R.make_bid(1, NT)
	return _at(c, 2, NT) if h <= 12 else _at(c, 3, NT)

static func _longest_of(l: Array, suits: Array, at_least: int) -> int:
	var best := -1
	for s in suits:
		if s < 0:
			continue
		if l[s] >= at_least and (best < 0 or l[s] > l[best]):
			best = s
	return best

## Partner opened, the next hand came in.
static func _resp_competitive(e: Dictionary, c: Dictionary, x: int, fit: bool, sp: int, lvl: String) -> int:
	var h: int = e["hcp"]
	var l: Array = e["len"]
	var hand: Array = e["hand"]
	var last: int = c["last"]
	var os := R.bid_strain(last)
	var ol := R.bid_level(last)
	if os == NT:
		return DBL if h >= 9 and lvl != "easy" else PASS
	if fit:
		if sp >= 13:
			if x >= H:
				return _at(c, 4, x)
			if stopper(hand, os):
				return _at(c, 3, NT)
			return cheapest(c, x)
		if sp >= 10:
			var j := _jump(c, x, 1)
			if j >= 0 and R.bid_level(j) <= _game_level(x):
				return j
		if sp >= 6:
			var b := cheapest(c, x)
			if b >= 0 and R.bid_level(b) <= 3:
				return b
		return PASS
	for m in [S, H]:
		if m == x or m == os or l[m] < 4:
			continue
		var b := cheapest(c, m)
		if b >= 0 and R.bid_level(b) == 1 and h >= 6:
			return b
		if b >= 0 and l[m] >= 5 and h >= 10 and R.bid_level(b) <= 2:
			return b
		if h >= 6 and ol <= 2 and lvl != "easy":
			return DBL
	if stopper(hand, os) and e["semi"]:
		if h >= 13:
			return _at(c, 3, NT)
		if h >= 11:
			return _at(c, 2, NT)
		if h >= 8:
			var b := cheapest(c, NT)
			if b >= 0 and R.bid_level(b) == 1:
				return b
	for s in [S, H, D, C]:
		if s == x or s == os:
			continue
		if l[s] >= 5 and h >= 10:
			var b := cheapest(c, s)
			if b >= 0 and R.bid_level(b) <= 2:
				return b
	if h >= 11 and ol <= 2 and lvl != "easy":
		return DBL
	return PASS

static func _resp_1nt(e: Dictionary, c: Dictionary) -> int:
	var h: int = e["hcp"]
	var l: Array = e["len"]
	for m in [S, H]:
		if l[m] >= 6:
			if h >= 10 and h <= 15:
				return R.make_bid(4, m)
			if h <= 7:
				return R.make_bid(2, m)
	if h <= 7:
		var s := _longest_of(l, [D, H, S], 5)
		return R.make_bid(2, s) if s >= 0 else PASS
	if (l[H] == 4 or l[S] == 4) and h <= 15:
		return R.make_bid(2, C)
	if (l[H] >= 5 or l[S] >= 5) and h >= 10 and h <= 15:
		return R.make_bid(3, S if l[S] >= l[H] else H)
	if h <= 9:
		return R.make_bid(2, NT)
	if h <= 15:
		return R.make_bid(3, NT)
	if h <= 17:
		return R.make_bid(4, NT)
	if h <= 19:
		return R.make_bid(6, NT)
	return R.make_bid(7, NT)

static func _resp_2nt(e: Dictionary, c: Dictionary) -> int:
	var h: int = e["hcp"]
	var l: Array = e["len"]
	if h <= 3:
		return PASS
	for m in [S, H]:
		if l[m] >= 6 and h <= 12:
			return R.make_bid(4, m)
	for m in [S, H]:
		if l[m] == 5 and h <= 12:
			return R.make_bid(3, m)
	if h <= 10:
		return R.make_bid(3, NT)
	if h <= 12:
		return R.make_bid(4, NT)
	if h <= 16:
		return R.make_bid(6, NT)
	return R.make_bid(7, NT)

static func _resp_2c(e: Dictionary, c: Dictionary) -> int:
	var h: int = e["hcp"]
	var l: Array = e["len"]
	if h >= 8:
		for s in [S, H, D, C]:
			if l[s] >= 5 and quality(e["hand"], s) >= 2:
				return cheapest(c, s)
		if e["bal"]:
			return R.make_bid(2, NT)
	return R.make_bid(2, D)

static func _resp_preempt(e: Dictionary, c: Dictionary, x: int) -> int:
	var h: int = e["hcp"]
	var l: Array = e["len"]
	var lv := R.bid_level(c["open_bid"])
	if x >= H:
		if l[x] >= 2 and h >= 16:
			return _at(c, 4, x)
		if l[x] >= 4 and lv == 2:
			return _at(c, 3, x)
	else:
		if l[x] >= 4 and lv == 2 and h < 16:
			return _at(c, 3, x)
	if h >= 17 and e["semi"]:
		return _at(c, 3, NT)
	return PASS

## -- opener's second call

static func _rebid(e: Dictionary, c: Dictionary, lvl: String) -> int:
	var ob: int = c["open_bid"]
	var pr: int = c["pard_first"]
	var l: Array = e["len"]
	var h: int = e["hcp"]
	if ob == R.make_bid(1, NT):
		if c["interfered"]:
			return -1
		if pr == R.make_bid(2, C):
			if l[H] >= 4:
				return R.make_bid(2, H)
			if l[S] >= 4:
				return R.make_bid(2, S)
			return R.make_bid(2, D)
		if pr == R.make_bid(2, D) or pr == R.make_bid(2, H) or pr == R.make_bid(2, S):
			return PASS
		if pr == R.make_bid(2, NT):
			return R.make_bid(3, NT) if h >= 16 else PASS
		if pr == R.make_bid(3, H) or pr == R.make_bid(3, S):
			var m := R.bid_strain(pr)
			return R.make_bid(4, m) if l[m] >= 3 else R.make_bid(3, NT)
		if pr == R.make_bid(3, C) or pr == R.make_bid(3, D):
			return R.make_bid(3, NT)
		if pr == R.make_bid(4, NT):
			return R.make_bid(6, NT) if h >= 16 else PASS
		return PASS if R.is_bid(pr) else -1
	if ob == R.make_bid(2, NT):
		if pr == R.make_bid(3, H) or pr == R.make_bid(3, S):
			var m := R.bid_strain(pr)
			return R.make_bid(4, m) if l[m] >= 3 else R.make_bid(3, NT)
		if pr == R.make_bid(4, NT):
			return R.make_bid(6, NT) if h >= 21 else PASS
		return PASS if R.is_bid(pr) else -1
	if ob == R.make_bid(2, C):
		if c["interfered"]:
			return -1
		if pr == R.make_bid(2, D):
			if e["bal"] and h <= 24:
				return R.make_bid(2, NT)
			if e["bal"] and h <= 27:
				return R.make_bid(3, NT)
			return cheapest(c, _one_suit(l))
		return -1
	var x := R.bid_strain(ob)
	if R.bid_level(ob) != 1 or x == NT:
		return -1
	return _rebid_1suit(e, c, x, pr, lvl)

static func _rebid_1suit(e: Dictionary, c: Dictionary, x: int, pr: int, lvl: String) -> int:
	var h: int = e["hcp"]
	var l: Array = e["len"]
	var hand: Array = e["hand"]
	if pr == PASS:
		# partner passed and the opponents are bidding
		if not c["ours"] and c["last"] >= 0:
			var os := R.bid_strain(c["last"])
			if l[x] >= 6 and h <= 15:
				var b := cheapest(c, x)
				if b >= 0 and R.bid_level(b) <= 2:
					return b
			if h >= 16 and lvl != "easy" and c["dbl"] == 0 and (os == NT or l[os] <= 2):
				return DBL
		return PASS
	if pr == DBL:
		# a negative double: show the other major, else describe
		var os := R.bid_strain(c["last"])
		for m in [H, S]:
			if m != x and m != os and l[m] >= 4:
				return _jump(c, m, 1 if h >= 17 else 0)
		if os < NT and stopper(hand, os) and e["semi"]:
			return _at(c, 3, NT) if h >= 18 else cheapest(c, NT)
		for s in [x, C, D, H, S]:
			if s != os and (l[s] >= 5 or (s != x and l[s] >= 4)):
				var b := cheapest(c, s)
				if b >= 0 and R.bid_level(b) <= 3:
					return b
		return PASS
	if not R.is_bid(pr):
		return -1
	var y := R.bid_strain(pr)
	var ly := R.bid_level(pr)
	var game := _game_level(x)
	if y == x:
		if ly == 2:
			if h <= 15:
				return PASS
			if h <= 18:
				return _at(c, 2, NT) if (x <= D and e["bal"]) else _at(c, 3, x)
			return _at(c, 4, x) if x >= H else _at(c, 3, NT)
		if ly == 3:
			if h >= 14:
				return _at(c, 4, x) if x >= H else _at(c, 3, NT)
			return PASS
		return PASS if h < 20 else -1
	if y == NT:
		if ly == 1:
			if e["bal"]:
				if h <= 15:
					return PASS
				return _at(c, 2, NT) if h <= 17 else _at(c, 3, NT)
			if l[x] >= 6:
				if h <= 15:
					return _at(c, 2, x)
				if h <= 18:
					return _at(c, 3, x)
				return _at(c, game, x) if x >= H else _at(c, 3, NT)
			for s in [S, H, D, C]:
				if s != x and l[s] >= 4 and (s < x or h >= 16):
					var b := cheapest(c, s)
					if b >= 0 and R.bid_level(b) == 2:
						return b
			return _at(c, 3, NT) if h >= 19 else PASS
		if ly == 2:
			if h <= 13:
				return _at(c, 3, x) if l[x] >= 6 else PASS
			return _at(c, 4, x) if (x >= H and l[x] >= 6) else _at(c, 3, NT)
		if ly == 3:
			if x >= H and l[x] >= 6:
				return _at(c, 4, x)
			return _at(c, 6, NT) if h >= 20 else PASS
		return -1
	# partner named a new suit: forcing
	if pr != cheapest({"last": c["open_bid"]}, y) and not c["interfered"]:
		return -1    # a jump shift: game is on, let the general logic drive
	if ly == 1:
		if y >= H and l[y] >= 4:
			if h <= 15:
				return _at(c, 2, y)
			return _at(c, 3, y) if h <= 18 else _at(c, 4, y)
		if x <= D and y == H and l[S] >= 4:
			return cheapest(c, S)
		if x == C and y == D:
			if l[H] >= 4:
				return cheapest(c, H)
			if l[S] >= 4:
				return cheapest(c, S)
		if e["bal"]:
			if h <= 14:
				return cheapest(c, NT)
			if h >= 18:
				return _jump(c, NT, 1)
		if l[x] >= 6:
			if h <= 15:
				return cheapest(c, x)
			if h <= 18:
				return _jump(c, x, 1)
			return _at(c, 4, x) if x >= H else _at(c, 3, NT)
		if y <= D and l[y] >= 4:
			return cheapest(c, y) if h <= 15 else _jump(c, y, 1)
		for s in [S, H, D, C]:
			if s != x and s != y and l[s] >= 4:
				var b := cheapest(c, s)
				if b >= 0 and R.bid_level(b) <= 2 and (s < x or h >= 16 or R.bid_level(b) == 1):
					return b
		if l[x] >= 5:
			return cheapest(c, x)
		return cheapest(c, NT)
	if ly == 2:
		if l[y] >= (3 if y >= H else 4):
			if y >= H and h >= 15:
				return _at(c, 4, y)
			return cheapest(c, y)
		if l[x] >= 6:
			return cheapest(c, x) if h <= 15 else _jump(c, x, 1)
		if e["bal"]:
			return cheapest(c, NT) if h <= 14 else _at(c, 3, NT)
		for s in [S, H, D, C]:
			if s != x and s != y and l[s] >= 4:
				var b := cheapest(c, s)
				if b >= 0 and ((R.bid_level(b) == 2 and s < x) or h >= 16) and R.bid_level(b) <= 3:
					return b
		if l[x] >= 5:
			return cheapest(c, x)
		return cheapest(c, NT)
	return -1

## -- defending the auction: the first call after an opponent opened

static func _overcall(e: Dictionary, c: Dictionary, lvl: String) -> int:
	var h: int = e["hcp"]
	var l: Array = e["len"]
	var hand: Array = e["hand"]
	var last: int = c["last"]
	if last < 0:
		return PASS
	var os := R.bid_strain(last)
	var ol := R.bid_level(last)
	# the pass-out seat may come in lighter: partner is marked with some values
	var balancing: bool = lvl == "hard" and c["opps"].size() == 1 \
		and int(c["i"]) - int(c["opps"][0]) == 3
	var adj := 3 if balancing else 0
	if os == NT:
		if h >= 15 and ol == 1 and lvl != "easy":
			return DBL
		for s in [S, H, D, C]:
			if l[s] >= 6 and h >= 8:
				return cheapest(c, s)
		return PASS
	if e["bal"] and h >= 15 - adj and h <= 18 and stopper(hand, os) and ol == 1:
		return cheapest(c, NT)
	# a good five-card suit
	var best := -1
	for s in [S, H, D, C]:
		if s == os or l[s] < 5:
			continue
		if quality(hand, s) < 2 and l[s] < 6:
			continue
		if best < 0 or l[s] > l[best]:
			best = s
	if best >= 0:
		var b := cheapest(c, best)
		if b >= 0:
			var bl := R.bid_level(b)
			if bl == 1 and h >= 8 - adj and h <= 16:
				return b
			if bl == 2 and h >= 10 - adj and h <= 16:
				return b
			if bl == 3 and h >= 13 and l[best] >= 6:
				return b
	# takeout double: short in their suit, something in the others
	if h >= 12 - adj and l[os] <= 2 and ol <= 3 and lvl != "easy" or (h >= 13 and l[os] <= 1):
		var ok := true
		for s in 4:
			if s != os and not c["opp_suits"].has(s) and l[s] < 3:
				ok = false
		if ok:
			return DBL
	if h >= 17 and ol <= 3:
		return DBL
	return PASS

## -- partner came in over their opening

static func _advance(e: Dictionary, c: Dictionary, lvl: String) -> int:
	var h: int = e["hcp"]
	var l: Array = e["len"]
	var hand: Array = e["hand"]
	var pc: int = c["pard_first"]
	var os: int = c["opp_suits"][0] if not c["opp_suits"].is_empty() else NT
	if pc == DBL:
		if c["rho_call"] != PASS:
			# no longer forced: bid only with something to say
			for s in [S, H, D, C]:
				if not c["opp_suits"].has(s) and l[s] >= 5 and h >= 6:
					var b := cheapest(c, s)
					if b >= 0 and R.bid_level(b) <= 2:
						return b
			return PASS
		if c["last"] >= 0 and R.bid_level(c["last"]) >= 4:
			return PASS
		var best := -1
		for s in [S, H, D, C]:
			if c["opp_suits"].has(s):
				continue
			var score: int = int(l[s]) * 10 + (5 if s >= H else 0)
			if best < 0 or score > int(l[best]) * 10 + (5 if best >= H else 0):
				best = s
		if os < NT and stopper(hand, os) and e["semi"] and (best < 0 or l[best] <= 4 or best <= D):
			if h >= 13:
				return _at(c, 3, NT)
			if h >= 11:
				return _at(c, 2, NT)
			if h >= 8:
				var nb := cheapest(c, NT)
				if nb >= 0 and R.bid_level(nb) == 1:
					return nb
		if best < 0:
			return PASS
		if h >= 12 and best >= H and l[best] >= 4:
			return _at(c, 4, best)
		if h >= 12:
			return _at(c, 3, NT) if (os < NT and stopper(hand, os)) else _jump(c, best, 1)
		if h >= 9:
			return _jump(c, best, 1)
		return cheapest(c, best)
	if not R.is_bid(pc):
		return -1
	var ps := R.bid_strain(pc)
	if pc == R.make_bid(1, NT):
		return -1 if c["rho_call"] != PASS else _resp_1nt(e, c)
	if ps == NT:
		return -1
	var sp: int = h + shape_pts(e, ps)
	if l[ps] >= 3:
		if sp >= 13 and ps >= H:
			return _at(c, 4, ps)
		if sp >= 11:
			var j := _jump(c, ps, 1)
			if j >= 0 and R.bid_level(j) <= _game_level(ps):
				return j
		if sp >= 8:
			var b := cheapest(c, ps)
			if b >= 0 and R.bid_level(b) <= 3:
				return b
		return PASS
	if os < NT and stopper(hand, os) and e["semi"]:
		if h >= 13:
			return _at(c, 3, NT)
		if h >= 11:
			return _at(c, 2, NT)
		if h >= 8:
			var nb := cheapest(c, NT)
			if nb >= 0 and R.bid_level(nb) == 1:
				return nb
	for s in [S, H, D, C]:
		if s != ps and not c["opp_suits"].has(s) and l[s] >= 5 and h >= 10:
			var b := cheapest(c, s)
			if b >= 0 and R.bid_level(b) <= 2:
				return b
	return PASS

## -- everything after the first round: aim for the best contract with what is known

static func _later(e: Dictionary, c: Dictionary, lvl: String, auc: Array, dealer: int) -> int:
	var inf := infer(auc, dealer, c["i"])
	var seat: int = c["seat"]
	var pard: int = c["pard"]
	var p: Dictionary = inf[pard]
	var me: Dictionary = inf[seat]
	var h: int = e["hcp"]
	var l: Array = e["len"]
	var hand: Array = e["hand"]
	var cur: int = c["last"]
	var pard_last: int = _last_call(auc, dealer, c["i"], pard)
	var my_last: int = _last_call(auc, dealer, c["i"], seat)

	# Blackwood: answer it, or place the contract after the answer
	if p.get("kind", "") == "bw_ask" and pard_last == cur and c["rho_call"] == PASS:
		var a := aces(hand)
		return _at(c, 5, [C, D, H, S, C][a])
	if me.get("kind", "") == "bw_ask" and p.get("kind", "") == "bw_answer":
		var theirs := R.bid_strain(pard_last)   # 0 = none or four
		var mine := aces(hand)
		if theirs == C and mine == 0:
			theirs = 4
		var missing := 4 - mine - theirs
		var st := _pick_strain(e, p, c)
		if st < 0:
			st = NT
		var pts: int = h + shape_pts(e, st) + int(p["min"])
		if missing >= 2:
			var five := _at(c, 5, st)
			return five if five >= 0 else (PASS if R.bid_strain(cur) == st else _at(c, 6, st))
		if missing == 1:
			return _at(c, 6, st)
		return _at(c, 7 if pts >= 36 else 6, st)
	if me.get("bw_done", false) or p.get("bw_done", false):
		return PASS
	if p.get("kind", "") == "quant" and pard_last == cur:
		var mid: float = (float(me["min"]) + float(me["max"])) * 0.5
		return _at(c, 6, NT) if float(h) >= mid else PASS

	# the Stayman follow-ups
	var st_ans := _stayman_step(e, c, auc, dealer)
	if st_ans != -2:
		return st_ans

	var strain := _pick_strain(e, p, c)
	var ours: bool = c["ours"]
	var gf := _game_forced(auc, dealer, seat)
	var forced: bool = ours and bool(p.get("forcing", false)) and pard_last == cur and c["rho_call"] == PASS
	# shape only counts once partner is known to fit, or a six-card suit and 11 points
	# looks like a game in clubs
	var my_pts: int = h
	if strain >= 0 and strain < NT and int(l[strain]) + int(p["lmin"][strain]) >= 8:
		my_pts += shape_pts(e, strain)
	var pmin: int = p["min"]
	var pmax: int = mini(int(p["max"]), pmin + 8)
	var cmin := my_pts + pmin
	var cmax := my_pts + pmax
	var cest := my_pts + (pmin + pmax) / 2

	if cur >= 0 and not ours:
		if pard_last == DBL and p.get("kind", "") == "takeout" and c["rho_call"] == PASS:
			return _advance_double(e, c)
		return _compete(e, c, p, strain, cmin, lvl)

	if strain < 0:
		if forced or gf or cmin >= 25:
			var best := -1
			for s in [S, H, D, C]:
				if l[s] >= 4 and not p["suits"].has(s) and not me["suits"].has(s):
					var b := cheapest(c, s)
					if b >= 0 and b <= R.make_bid(3, NT) and (best < 0 or l[s] > l[best]):
						best = s
			if best >= 0:
				return cheapest(c, best)
			if cmin >= 25:
				var g := _at(c, 3, NT)
				if g >= 0:
					return g
			var ln := _longest_of(l, [S, H, D, C], 5)
			if ln >= 0:
				return cheapest(c, ln)
			return cheapest(c, NT)
		return PASS

	var game := _game_level(strain)
	var gpts := _game_pts(strain)

	if cmin >= 33 and lvl != "easy" and strain < NT and not me.get("bw_done", false):
		var ask := _at(c, 4, NT)
		if ask >= 0:
			return ask
	if cmin >= 33:
		var slam := _at(c, 7 if cmin >= 37 else 6, strain)
		return slam if slam >= 0 else PASS
	if ours and cur >= 0:
		var cs := R.bid_strain(cur)
		if R.bid_level(cur) >= _game_level(cs) or (cs == NT and R.bid_level(cur) >= 3):
			return PASS
	if cmin >= gpts or gf:
		var gb := _at(c, game, strain)
		if strain <= D and cmin < 28:
			var ntb := _at(c, 3, NT)
			if ntb >= 0 and _nt_ok(e, p, c):
				return ntb
		return gb if gb >= 0 else PASS
	if p.get("invite", false) and pard_last == cur:
		var mid: float = (float(me["min"]) + float(me["max"])) * 0.5
		if float(my_pts) >= mid or cest >= gpts:
			var gb := _at(c, game, strain)
			return gb if gb >= 0 else PASS
		if forced:
			return cheapest(c, strain)
		return PASS
	if cmax >= gpts:
		if cest >= gpts + 1:
			var gb := _at(c, game, strain)
			if gb >= 0:
				return gb
		var inv := _at(c, game - 1, strain)
		if inv >= 0 and strain <= D:
			inv = _at(c, 2, NT) if _nt_ok(e, p, c) else inv
		if inv >= 0:
			return inv
		if cest >= gpts:
			var gb2 := _at(c, game, strain)
			return gb2 if gb2 >= 0 else PASS
	# part score
	if cur >= 0 and R.bid_strain(cur) == strain:
		return PASS
	var fitlen: int = (int(l[strain]) + int(p["lmin"][strain])) if strain < NT else 0
	var b := cheapest(c, strain)
	if b < 0:
		return PASS
	if forced:
		return b
	var cap := 2 if fitlen < 9 else 3
	if strain == NT:
		return PASS
	if R.bid_level(b) <= cap and (fitlen >= 8 or int(l[strain]) >= 6):
		return b
	return PASS

## Partner doubled for takeout late in the auction: pick a suit, or sit with their trumps.
static func _advance_double(e: Dictionary, c: Dictionary) -> int:
	var l: Array = e["len"]
	var os := R.bid_strain(c["last"])
	if os < NT and l[os] >= 4 and quality(e["hand"], os) >= 2:
		return PASS
	var best := -1
	for s in [S, H, D, C]:
		if s == os or c["opp_suits"].has(s):
			continue
		if best < 0 or l[s] > l[best]:
			best = s
	if best < 0:
		return PASS
	var b := cheapest(c, best)
	return b if b >= 0 and R.bid_level(b) <= 3 else PASS

## Opponents hold the auction after the first round: compete, double, or let them have it.
static func _compete(e: Dictionary, c: Dictionary, p: Dictionary, strain: int, cmin: int, lvl: String) -> int:
	var l: Array = e["len"]
	var cur: int = c["last"]
	var os := R.bid_strain(cur)
	var ol := R.bid_level(cur)
	if c["dbl"] > 0:
		return PASS
	if lvl != "easy":
		if os < NT and l[os] >= 4 and quality(e["hand"], os) >= 2 and cmin >= 21 and ol >= 2:
			return DBL
		if cmin >= 25 and ol >= 3:
			return DBL
		if lvl == "hard" and os == NT and cmin >= 23 and ol >= 2:
			return DBL
	if strain < 0 or strain == os or lvl == "easy" and ol >= 3:
		return PASS
	if cmin >= _game_pts(strain):
		var g := _at(c, _game_level(strain), strain)
		if g >= 0:
			return g
	if strain == NT:
		return PASS
	var fitlen: int = int(l[strain]) + int(p["lmin"][strain])
	var cap := 2
	if lvl == "normal":
		cap = clampi(fitlen - 6, 2, 3)
	elif lvl == "hard":
		cap = maxi(2, fitlen - 6)
	if fitlen < 8 and int(l[strain]) < 6:
		return PASS
	var b := cheapest(c, strain)
	if b >= 0 and R.bid_level(b) <= cap and cmin >= 17:
		return b
	return PASS

## -2 when the Stayman sequence is not in play.
static func _stayman_step(e: Dictionary, c: Dictionary, auc: Array, dealer: int) -> int:
	var seat: int = c["seat"]
	var l: Array = e["len"]
	var h: int = e["hcp"]
	var mine := _calls_of(auc, dealer, c["i"], seat)
	var theirs := _calls_of(auc, dealer, c["i"], c["pard"])
	if c["interfered"]:
		return -2
	# responder: 1NT - 2C - answer - me
	if c["open_bid"] == R.make_bid(1, NT) and c["opener"] == c["pard"] \
			and mine.size() == 1 and mine[0] == R.make_bid(2, C) and theirs.size() == 2:
		var ans: int = theirs[1]
		var fit: bool = (ans == R.make_bid(2, H) and l[H] >= 4) or (ans == R.make_bid(2, S) and l[S] >= 4)
		if fit:
			var m := R.bid_strain(ans)
			if h <= 9:
				return R.make_bid(3, m)
			if h <= 15:
				return R.make_bid(4, m)
			return -2
		for m in [S, H]:
			if l[m] >= 5 and h >= 10 and h <= 15 and R.make_bid(3, m) > ans:
				return R.make_bid(3, m)
		if h <= 9:
			return R.make_bid(2, NT)
		if h <= 15:
			return R.make_bid(3, NT)
		return -2
	# opener: 1NT - 2C - 2H - NT: responder has the spades
	if c["opener"] == seat and c["open_bid"] == R.make_bid(1, NT) and mine.size() == 2 \
			and theirs.size() == 2 and theirs[0] == R.make_bid(2, C):
		var nt: int = theirs[1]
		if mine[1] == R.make_bid(2, H) and l[S] >= 4:
			if nt == R.make_bid(2, NT):
				return R.make_bid(4, S) if h >= 16 else R.make_bid(3, S)
			if nt == R.make_bid(3, NT):
				return R.make_bid(4, S)
		if nt == R.make_bid(2, NT):
			return R.make_bid(3, NT) if h >= 16 else PASS
		if nt == R.make_bid(3, H) or nt == R.make_bid(3, S):
			return R.make_bid(4, R.bid_strain(nt)) if h >= 16 else PASS
		return PASS
	return -2

static func _game_forced(auc: Array, dealer: int, seat: int) -> bool:
	# after 2C and any rebid but 2NT, nobody stops short of game
	var side := R.side_of(seat)
	var opened_2c := false
	var highest := -1
	for k in auc.size():
		var cl: int = auc[k]
		var s := R.seat_at(dealer, k)
		if not R.is_bid(cl):
			continue
		if highest < 0 and cl == R.make_bid(2, C) and R.side_of(s) == side:
			opened_2c = true
		elif opened_2c and R.side_of(s) == side and cl == R.make_bid(2, NT) and highest == R.make_bid(2, D):
			return false
		highest = cl
	if not opened_2c or highest < 0:
		return false
	var hs := R.bid_strain(highest)
	return R.bid_level(highest) < _game_level(hs)

static func _nt_ok(e: Dictionary, p: Dictionary, c: Dictionary) -> bool:
	if not (e["semi"] or p.get("bal", false)):
		return false
	for s in c["opp_suits"]:
		if not stopper(e["hand"], s) and not p.get("nt", false):
			return false
	return true

## Where to play: a major fit, else no trumps if it is safe, else a minor fit, else a
## long suit of my own. -1 while it is still unclear.
static func _pick_strain(e: Dictionary, p: Dictionary, c: Dictionary) -> int:
	var l: Array = e["len"]
	var pl: Array = p["lmin"]
	var best := -1
	var bestf := 0
	for s in [S, H]:
		var f: int = int(l[s]) + int(pl[s])
		if f >= 8 and f > bestf:
			best = s
			bestf = f
	if best >= 0:
		return best
	var nt_ok := _nt_ok(e, p, c)
	if nt_ok and (e["bal"] or p.get("bal", false) or p.get("nt", false)):
		return NT
	for s in [D, C]:
		var f: int = int(l[s]) + int(pl[s])
		if f >= 8 and f > bestf:
			best = s
			bestf = f
	if best >= 0:
		return NT if nt_ok else best
	for s in [S, H, D, C]:
		if l[s] >= 6:
			return s
	if nt_ok:
		return NT
	return -1

static func _last_call(auc: Array, dealer: int, upto: int, seat: int) -> int:
	for k in range(upto - 1, -1, -1):
		if R.seat_at(dealer, k) == seat:
			return auc[k]
	return -1

static func _calls_of(auc: Array, dealer: int, upto: int, seat: int) -> Array:
	var out: Array = []
	for k in upto:
		if R.seat_at(dealer, k) == seat and auc[k] != PASS:
			out.append(auc[k])
	return out

## ---- reading calls back ---------------------------------------------------------------

static func blank() -> Dictionary:
	return {"min": 0, "max": 37, "lmin": [0, 0, 0, 0], "lmax": [13, 13, 13, 13],
		"bal": false, "nt": false, "forcing": false, "invite": false, "kind": "",
		"suits": [], "bw_done": false}

## What every seat has shown by call `upto` (exclusive).
static func infer(auc: Array, dealer: int, upto: int) -> Array:
	var out: Array = [blank(), blank(), blank(), blank()]
	for i in upto:
		var s := R.seat_at(dealer, i)
		var m := meaning(auc, dealer, i, out)
		_merge(out[s], m)
		# answering or asking Blackwood settles who places the contract
		if m.get("kind", "") == "bw_answer":
			out[R.partner_of(s)]["kind"] = "bw_ask"
		if R.is_bid(auc[i]) and i > 0:
			var prev_kind: String = out[R.partner_of(s)].get("kind", "")
			if prev_kind == "bw_answer" and R.bid_level(auc[i]) >= 5:
				out[s]["bw_done"] = true
	return out

static func _merge(info: Dictionary, m: Dictionary) -> void:
	var lo := maxi(int(info["min"]), int(m["min"]))
	var hi := mini(int(info["max"]), int(m["max"]))
	if lo > hi:
		lo = m["min"]
		hi = m["max"]
	info["min"] = lo
	info["max"] = hi
	for s in 4:
		var a := maxi(int(info["lmin"][s]), int(m["lmin"][s]))
		var b := mini(int(info["lmax"][s]), int(m["lmax"][s]))
		if a > b:
			a = m["lmin"][s]
			b = m["lmax"][s]
		info["lmin"][s] = a
		info["lmax"][s] = b
	info["bal"] = info["bal"] or m["bal"]
	info["nt"] = info["nt"] or m["nt"]
	info["forcing"] = m["forcing"]
	info["invite"] = m["invite"]
	if m["kind"] != "" or R.is_bid(m.get("call", PASS)):
		info["kind"] = m["kind"]
	for s in m["suits"]:
		if not info["suits"].has(s):
			info["suits"].append(s)

static func _mk(lo: int, hi: int) -> Dictionary:
	var m := blank()
	m["min"] = lo
	m["max"] = hi
	return m

static func _len(m: Dictionary, s: int, lo: int, hi: int = 13) -> Dictionary:
	m["lmin"][s] = lo
	m["lmax"][s] = hi
	if lo >= 4 and not m["suits"].has(s):
		m["suits"].append(s)
	return m

static func _balanced_shape(m: Dictionary) -> Dictionary:
	m["bal"] = true
	m["nt"] = true
	for s in 4:
		m["lmin"][s] = 2
		m["lmax"][s] = 5
	return m

static func meaning(auc: Array, dealer: int, i: int, inf: Array) -> Dictionary:
	var call: int = auc[i]
	var c := ctx(auc, dealer, i)
	var m := blank()
	m["call"] = call
	var role: String = c["role"]
	if call == PASS:
		if role == "open":
			m["max"] = 11
		elif role == "respond" and not c["interfered"]:
			var ob: int = c["open_bid"]
			if R.bid_level(ob) == 1 and R.bid_strain(ob) < NT:
				m["max"] = 5
			elif ob == R.make_bid(1, NT):
				m["max"] = 7
		elif role == "overcall":
			m["max"] = 16
		return m
	if call == RDBL:
		m["min"] = 10
		return m
	if call == DBL:
		var last: int = c["last"]
		var os := R.bid_strain(last)
		if role == "overcall" and R.bid_level(last) <= 3:
			if os == NT:
				m["min"] = 15
				m["kind"] = "penalty"
			else:
				m["min"] = 12
				m["lmax"][os] = 3
				m["forcing"] = true
				m["kind"] = "takeout"
			return m
		if role == "rebid" and c["pard_first"] == PASS and R.bid_level(last) <= 2 and os < NT:
			m["min"] = 16
			m["lmax"][os] = 2
			m["kind"] = "takeout"
			return m
		if role == "respond" and R.bid_level(last) <= 2 and os < NT:
			m["min"] = 6
			m["kind"] = "negative"
			var unbid: Array = []
			for mj in [H, S]:
				if mj != os and mj != R.bid_strain(c["open_bid"]):
					unbid.append(mj)
			if unbid.size() == 1:
				_len(m, unbid[0], 4)
			m["forcing"] = true
			return m
		m["min"] = 8
		m["kind"] = "penalty"
		return m

	var lv := R.bid_level(call)
	var st := R.bid_strain(call)
	var cheap := cheapest(c, st)
	var jumps: int = lv - R.bid_level(cheap) if cheap >= 0 else 0
	match role:
		"open":
			return _mean_open(lv, st)
		"respond":
			var r := _mean_respond(c, lv, st, jumps)
			if not r.is_empty():
				return r
		"rebid":
			var r := _mean_rebid(c, lv, st, jumps)
			if not r.is_empty():
				return r
		"overcall":
			return _mean_overcall(c, lv, st, jumps)
		"advance":
			var r := _mean_advance(c, lv, st, jumps)
			if not r.is_empty():
				return r
	return _mean_later(auc, dealer, c, inf, lv, st, jumps)

static func _mean_open(lv: int, st: int) -> Dictionary:
	if lv == 1:
		if st == NT:
			return _balanced_shape(_mk(15, 17))
		var m := _mk(11, 21)
		if st >= H:
			return _len(m, st, 5)
		_len(m, st, 3)
		m["lmax"][H] = 4
		m["lmax"][S] = 4
		return m
	if lv == 2:
		if st == C:
			var m := _mk(22, 37)
			m["forcing"] = true
			return m
		if st == NT:
			return _balanced_shape(_mk(20, 21))
		return _len(_mk(5, 11), st, 6, 7)
	if st == NT:
		return _balanced_shape(_mk(25, 27))
	return _len(_mk(5, 12), st, 7)

static func _mean_respond(c: Dictionary, lv: int, st: int, jumps: int) -> Dictionary:
	var ob: int = c["open_bid"]
	var x := R.bid_strain(ob)
	var ol := R.bid_level(ob)
	if ob == R.make_bid(1, NT) and not c["interfered"]:
		if lv == 2 and st == C:
			var m := _mk(8, 37)
			m["forcing"] = true
			m["kind"] = "stayman"
			return m
		if lv == 2 and st < NT:
			var m := _len(_mk(0, 7), st, 5)
			m["kind"] = "signoff"
			return m
		if st == NT:
			match lv:
				2:
					var m := _mk(8, 9)
					m["invite"] = true
					m["nt"] = true
					return m
				3: return _mk(10, 15)
				4:
					var m := _mk(16, 17)
					m["kind"] = "quant"
					return m
				6: return _mk(18, 19)
				7: return _mk(20, 37)
		if lv == 3:
			var m := _len(_mk(10, 37), st, 5)
			m["forcing"] = true
			return m
		if lv == 4 and st >= H:
			return _len(_mk(10, 15), st, 6)
		return {}
	if ob == R.make_bid(2, NT) and not c["interfered"]:
		if st == NT:
			match lv:
				3: return _mk(4, 10)
				4:
					var m := _mk(11, 12)
					m["kind"] = "quant"
					return m
				6: return _mk(13, 16)
		if lv == 3 and st >= H:
			var m := _len(_mk(4, 37), st, 5)
			m["forcing"] = true
			return m
		if lv == 4 and st >= H:
			return _len(_mk(4, 12), st, 6)
		return {}
	if ob == R.make_bid(2, C) and not c["interfered"]:
		var m := _mk(0, 7) if (lv == 2 and st == D) else _mk(8, 37)
		if st < NT and not (lv == 2 and st == D):
			_len(m, st, 5)
		if st == NT:
			m["nt"] = true
		m["forcing"] = true
		return m
	if ol >= 2 and x < NT:
		if st == x:
			return _len(_mk(0, 37), x, 3 if lv == ol + 1 else 2)
		if st == NT:
			return _mk(16, 37)
		var m := _len(_mk(16, 37), st, 5)
		m["forcing"] = true
		return m
	if ol != 1 or x == NT:
		return {}
	if st == x:
		var need := 3 if x >= H else 4
		if lv == 2:
			return _len(_mk(5, 10), x, need)
		if lv == 3:
			var m := _len(_mk(10, 12), x, need)
			m["invite"] = true
			return m
		return _len(_mk(6, 12), x, 4)
	if st == NT:
		var m := blank()
		m["nt"] = true
		match lv:
			1:
				m = _mk(6, 10)
				m["nt"] = true
				if x >= H:
					m["lmax"][x] = 2
				if x == H:
					m["lmax"][S] = 3
			2:
				m = _balanced_shape(_mk(11, 12))
				m["invite"] = true
			3:
				m = _balanced_shape(_mk(13, 15))
		return m
	if c["interfered"] and c["opp_suits"].has(st):
		var m := _mk(10, 37)
		m["forcing"] = true
		m["kind"] = "cue"
		return m
	if jumps >= 1 and lv <= 3:
		var m := _len(_mk(16, 37), st, 5)
		m["forcing"] = true
		return m
	if lv == 1:
		var m := _len(_mk(6, 37), st, 4)
		m["forcing"] = true
		return m
	var m := _len(_mk(10, 37), st, 5 if (st == H and x == S) else 4)
	m["forcing"] = true
	return m

static func _mean_rebid(c: Dictionary, lv: int, st: int, jumps: int) -> Dictionary:
	var ob: int = c["open_bid"]
	var pr: int = c["pard_first"]
	var x := R.bid_strain(ob)
	if ob == R.make_bid(1, NT):
		if pr == R.make_bid(2, C) and lv == 2:
			var m := _mk(15, 17)
			if st == D:
				m["lmax"][H] = 3
				m["lmax"][S] = 3
			elif st == H:
				_len(m, H, 4)
			elif st == S:
				_len(m, S, 4)
				m["lmax"][H] = 3
			return m
		if pr == R.make_bid(2, NT) and st == NT:
			return _mk(16, 17)
		return _mk(15, 17)
	if ob == R.make_bid(2, C):
		if st == NT:
			var m := _balanced_shape(_mk(22, 24) if lv == 2 else _mk(25, 27))
			return m
		var m := _len(_mk(22, 37), st, 5)
		m["forcing"] = true
		return m
	if R.bid_level(ob) != 1 or x == NT:
		return {}
	var raised: bool = R.is_bid(pr) and R.bid_strain(pr) == x
	if st == x:
		if raised:
			var m := _mk(16, 18) if lv < _game_level(x) else _mk(19, 21)
			m["invite"] = lv < _game_level(x)
			return m
		var m := _len(_mk(12, 15), x, 6)
		if jumps == 1:
			m = _len(_mk(16, 18), x, 6)
			m["invite"] = true
		elif jumps >= 2 or lv >= _game_level(x):
			m = _len(_mk(19, 21), x, 6)
		return m
	if st == NT:
		if raised:
			var m := _mk(16, 18)
			m["invite"] = true
			m["nt"] = true
			return m
		if lv == 1:
			return _balanced_shape(_mk(12, 14))
		if lv == 2:
			if jumps >= 1:
				var m := _balanced_shape(_mk(18, 19))
				m["invite"] = true
				return m
			if pr == R.make_bid(1, NT):
				var m := _balanced_shape(_mk(16, 17))
				m["invite"] = true
				return m
			return _balanced_shape(_mk(12, 14))
		var m := _mk(18, 21)
		m["nt"] = true
		return m
	if R.is_bid(pr) and st == R.bid_strain(pr) and R.bid_strain(pr) < NT:
		var need := 4 if R.bid_level(pr) == 1 else 3
		if jumps == 0:
			return _len(_mk(12, 15), st, need)
		if lv >= _game_level(st):
			return _len(_mk(19, 21), st, need)
		var m := _len(_mk(16, 18), st, need)
		m["invite"] = true
		return m
	var m := _len(_mk(12, 21), st, 4)
	if x >= H or R.bid_level(ob) == 1:
		m["lmin"][x] = maxi(int(m["lmin"][x]), 4 if x <= D else 5)
	if jumps >= 1:
		m["min"] = 19
		m["forcing"] = true
	elif lv == 2 and st > x:
		m["min"] = 16
		m["forcing"] = true
	return m

static func _mean_overcall(c: Dictionary, lv: int, st: int, jumps: int) -> Dictionary:
	if st == NT:
		var m := _balanced_shape(_mk(15, 18))
		if lv >= 2:
			m = _mk(19, 22)
			m["nt"] = true
		return m
	if c["opp_suits"].has(st):
		var m := _mk(13, 37)
		m["forcing"] = true
		m["kind"] = "cue"
		return m
	if jumps >= 1:
		return _len(_mk(5, 10), st, 6)
	if lv == 1:
		return _len(_mk(8, 16), st, 5)
	if lv == 2:
		return _len(_mk(10, 16), st, 5)
	return _len(_mk(11, 16), st, 6)

static func _mean_advance(c: Dictionary, lv: int, st: int, jumps: int) -> Dictionary:
	var pc: int = c["pard_first"]
	if pc == DBL:
		if st == NT:
			var m: Dictionary = _mk(8, 10) if lv == 1 else (_mk(11, 12) if lv == 2 else _mk(13, 37))
			m["nt"] = true
			return m
		if lv >= _game_level(st):
			return _len(_mk(12, 37), st, 4)
		if jumps >= 1:
			var m := _len(_mk(9, 11), st, 4)
			m["invite"] = true
			return m
		return _len(_mk(0, 8), st, 4)
	if not R.is_bid(pc):
		return {}
	if pc == R.make_bid(1, NT):
		var fake := c.duplicate()
		fake["open_bid"] = pc
		fake["interfered"] = false
		return _mean_respond(fake, lv, st, jumps)
	var ps := R.bid_strain(pc)
	if st == ps:
		if lv >= _game_level(st):
			return _len(_mk(13, 37), st, 3)
		if jumps >= 1:
			var m := _len(_mk(11, 12), st, 3)
			m["invite"] = true
			return m
		return _len(_mk(8, 10), st, 3)
	if st == NT:
		var m: Dictionary = _mk(8, 10) if lv == 1 else (_mk(11, 12) if lv == 2 else _mk(13, 37))
		m["nt"] = true
		return m
	return _len(_mk(10, 37), st, 5)

static func _mean_later(auc: Array, dealer: int, c: Dictionary, inf: Array, lv: int, st: int, jumps: int) -> Dictionary:
	var seat: int = c["seat"]
	var me: Dictionary = inf[seat]
	var p: Dictionary = inf[c["pard"]]
	var m := blank()
	var pard_last := _last_call(auc, dealer, c["i"], c["pard"])
	if lv == 4 and st == NT:
		# straight after partner's no trumps it asks for more; otherwise it asks for aces
		if R.is_bid(pard_last) and R.bid_strain(pard_last) == NT:
			m["kind"] = "quant"
		else:
			m["kind"] = "bw_ask"
		m["forcing"] = true
		return m
	if lv == 5 and st <= S and p.get("kind", "") == "bw_ask" and pard_last == R.make_bid(4, NT):
		m["kind"] = "bw_answer"
		return m
	if st == NT:
		m["nt"] = true
		if lv < 3:
			m["invite"] = true
		return m
	if p["suits"].has(st) or int(p["lmin"][st]) >= 5:
		_len(m, st, maxi(3, 8 - int(p["lmin"][st])))
	elif me["suits"].has(st):
		_len(m, st, clampi(int(me["lmin"][st]) + 1, 5, 7))
	else:
		_len(m, st, 4)
		if lv < _game_level(st) and c["ours"]:
			m["forcing"] = true
	var shared: bool = me["suits"].has(st) or p["suits"].has(st)
	if shared and lv == _game_level(st) - 1:
		m["invite"] = true
	return m
