extends RefCounted
## The card-play brain. Three levels:
##   easy   -- plays the obvious card and sometimes just a card;
##   normal -- the classic rules: second hand low, third hand high, cover an honour with
##             an honour, win as cheaply as possible, draw trumps, cash winners, return
##             partner's suit;
##   hard   -- deals out the unseen cards many times over consistently with everything
##             seen so far (who showed out of what, what the auction said) and plays each
##             candidate card to the end of the hand, keeping the one that scores best.
##             With three tricks or fewer left it solves each layout exactly.
## Nobody peeks: every level only reads its own hand, the dummy once it is down, and the
## cards already played.

const R := preload("res://game/bridge/bridge_rules.gd")

## The whole state of play, cheap to copy for simulations.
class Table:
	var hands: Array = [[], [], [], []]
	var trick: Array = []           ## [[seat, card], ...]
	var leader := 0
	var trump := 4
	var declarer := 0
	var dummy := 2
	var exposed := false            ## dummy is face up
	var played := PackedByteArray()
	var voids: Array = []           ## voids[seat][suit] = 1 once they showed out
	var won := [0, 0]               ## tricks by side
	var bid_suits: Array = [[], [], [], []]
	var shape: Array = []           ## per seat {lmin, lmax} from the auction, may be empty

	func _init() -> void:
		played.resize(52)
		voids = [PackedByteArray([0, 0, 0, 0]), PackedByteArray([0, 0, 0, 0]),
			PackedByteArray([0, 0, 0, 0]), PackedByteArray([0, 0, 0, 0])]

	func copy() -> Table:
		var t := Table.new()
		for s in 4:
			t.hands[s] = (hands[s] as Array).duplicate()
			t.voids[s] = (voids[s] as PackedByteArray).duplicate()
		t.trick = trick.duplicate(true)
		t.leader = leader
		t.trump = trump
		t.declarer = declarer
		t.dummy = dummy
		t.exposed = exposed
		t.played = played.duplicate()
		t.won = won.duplicate()
		t.bid_suits = bid_suits
		t.shape = shape
		return t

	func to_play() -> int:
		return (leader + trick.size()) % 4

	func tricks_left() -> int:
		return (hands[0] as Array).size() + (1 if not trick.is_empty() else 0)

	## Play a card; returns the seat that won the trick if this card completed one, else -1.
	func play(card: int) -> int:
		var seat := to_play()
		var h: Array = hands[seat]
		h.erase(card)
		if not trick.is_empty():
			var led := R.suit_of(trick[0][1])
			if R.suit_of(card) != led:
				voids[seat][led] = 1
		trick.append([seat, card])
		played[card] = 1
		if seat == leader and trick.size() == 1 and not exposed:
			exposed = true
		if trick.size() < 4:
			return -1
		var w: int = trick[R.winning_index(trick, trump)][0]
		won[w % 2] += 1
		leader = w
		trick = []
		return w

## ---- what a seat can see -------------------------------------------------------------

## The seat whose head decides for `seat`: declarer plays the dummy.
static func brain(t: Table, seat: int) -> int:
	return t.declarer if seat == t.dummy else seat

## Cards `seat` can see: its own, the dummy once down (declarer always sees dummy's once
## it is down), and everything already played.
static func visible(t: Table, seat: int) -> PackedByteArray:
	var b := brain(t, seat)
	var v := t.played.duplicate()
	for c in t.hands[b]:
		v[c] = 1
	if t.exposed:
		for c in t.hands[t.dummy]:
			v[c] = 1
	return v

static func hand_visible(t: Table, viewer: int, seat: int) -> bool:
	var b := brain(t, viewer)
	return seat == b or (t.exposed and seat == t.dummy)

## Could `seat` hold a card of `suit` above `rank`, as far as `viewer` knows?
static func may_beat(t: Table, viewer: int, seat: int, suit: int, rank: int, vis: PackedByteArray) -> bool:
	if hand_visible(t, viewer, seat):
		for c in t.hands[seat]:
			if R.suit_of(c) == suit and R.rank_of(c) > rank:
				return true
		return false
	if t.voids[seat][suit] == 1:
		return false
	for r in range(rank + 1, 13):
		if vis[suit * 13 + r] == 0:
			return true
	return false

static func may_have(t: Table, viewer: int, seat: int, suit: int, vis: PackedByteArray) -> bool:
	return may_beat(t, viewer, seat, suit, -1, vis)

## Is `card` sure to win the current trick if played now by the seat to play?
static func secure(t: Table, seat: int, card: int, vis: PackedByteArray) -> bool:
	var led := R.suit_of(t.trick[0][1]) if not t.trick.is_empty() else R.suit_of(card)
	var n := t.trick.size()
	for k in range(n + 1, 4):
		var p := (t.leader + k) % 4
		if p % 2 == seat % 2:
			continue
		if R.suit_of(card) == led:
			if may_beat(t, seat, p, led, R.rank_of(card), vis):
				return false
			if t.trump < 4 and led != t.trump and not may_have(t, seat, p, led, vis) \
					and may_have(t, seat, p, t.trump, vis):
				return false
			# void and holding trumps is only a threat if they might be void
			if t.trump < 4 and led != t.trump and not hand_visible(t, seat, p) \
					and t.voids[p][led] == 0 and _few_left(t, led, vis) and may_have(t, seat, p, t.trump, vis):
				return false
		else:
			# a ruff: over-ruffed only by someone also void who has a higher trump
			if not may_have(t, seat, p, led, vis) and may_beat(t, seat, p, t.trump, R.rank_of(card), vis):
				return false
	return true

## Few enough of a suit left unseen that a defender may well be out of it.
static func _few_left(t: Table, suit: int, vis: PackedByteArray) -> bool:
	var n := 0
	for r in 13:
		if vis[suit * 13 + r] == 0:
			n += 1
	return n <= 2

## No unplayed card above it except ones in `own` (the hands on its own side).
static func is_master(t: Table, card: int, own: Array) -> bool:
	var s := R.suit_of(card)
	for r in range(R.rank_of(card) + 1, 13):
		var c := s * 13 + r
		if t.played[c] == 0 and not own.has(c):
			return false
	return true

## ---- choosing a card ------------------------------------------------------------------

static func choose(t: Table, lvl: String, rng: RandomNumberGenerator, budget_ms: int = 300) -> int:
	var seat := t.to_play()
	var legal := R.legal_cards(t.hands[seat], t.trick)
	if legal.size() == 1:
		return legal[0]
	match lvl:
		"easy":
			if rng.randf() < 0.3:
				return legal[rng.randi_range(0, legal.size() - 1)]
			return simple(t, seat, legal)
		"hard":
			if t.exposed:
				return monte_carlo(t, seat, legal, rng, budget_ms)
			return heuristic(t, seat)
	return heuristic(t, seat)

## Easy: win if it is cheap and obvious, otherwise get rid of the lowest card.
static func simple(t: Table, seat: int, legal: Array) -> int:
	if t.trick.is_empty():
		var l := R.lengths(t.hands[seat])
		var best := 0
		for s in 4:
			if l[s] > l[best]:
				best = s
		var cs := R.cards_in(legal, best)
		return cs[0] if not cs.is_empty() else legal[0]
	var wi := R.winning_index(t.trick, t.trump)
	var wc: int = t.trick[wi][1]
	var led := R.suit_of(t.trick[0][1])
	if t.trick[wi][0] % 2 == seat % 2:
		return _lowest(legal)
	var winners: Array = []
	for c in legal:
		if R.beats(c, wc, led, t.trump):
			winners.append(c)
	if not winners.is_empty():
		return _lowest(winners)
	return _lowest(legal)

static func heuristic(t: Table, seat: int) -> int:
	var legal := R.legal_cards(t.hands[seat], t.trick)
	if legal.size() == 1:
		return legal[0]
	var vis := visible(t, seat)
	if t.trick.is_empty():
		return _lead(t, seat, legal, vis)
	return _follow(t, seat, legal, vis)

static func _lowest(cards: Array) -> int:
	var best: int = cards[0]
	for c in cards:
		if R.rank_of(c) < R.rank_of(best) or (R.rank_of(c) == R.rank_of(best) and c < best):
			best = c
	return best

static func _highest(cards: Array) -> int:
	var best: int = cards[0]
	for c in cards:
		if R.rank_of(c) > R.rank_of(best):
			best = c
	return best

## The lowest of the top touching cards: how you play "high" without wasting.
static func _top_of_equals(cards: Array, vis: PackedByteArray, own: Array) -> int:
	var top := _highest(cards)
	var s := R.suit_of(top)
	var r := R.rank_of(top) - 1
	var pick := top
	while r >= 0:
		var c := s * 13 + r
		if cards.has(c):
			pick = c
		elif vis[c] == 1 and not own.has(c):
			pass    # already played: still touching
		else:
			break
		r -= 1
	return pick

static func _follow(t: Table, seat: int, legal: Array, vis: PackedByteArray) -> int:
	var led := R.suit_of(t.trick[0][1])
	var pos := t.trick.size()
	var wi := R.winning_index(t.trick, t.trump)
	var wseat: int = t.trick[wi][0]
	var wc: int = t.trick[wi][1]
	var pard_win := wseat % 2 == seat % 2
	var own: Array = t.hands[seat]
	var beaters: Array = []
	for c in legal:
		if R.beats(c, wc, led, t.trump):
			beaters.append(c)
	if R.suit_of(legal[0]) == led:
		if pos == 3:
			if pard_win or beaters.is_empty():
				return _lowest(legal)
			return _lowest(beaters)
		if pard_win:
			if secure(t, seat, wc, vis) or beaters.is_empty():
				return _lowest(legal)
			for c in _sorted_up(beaters):
				if secure(t, seat, c, vis):
					return c
			return _lowest(legal) if R.rank_of(wc) >= 9 else _top_of_equals(beaters, vis, own)
		if beaters.is_empty():
			return _lowest(legal)
		if pos == 1:
			# second hand low, but cover an honour with an honour
			var led_card: int = t.trick[0][1]
			if R.rank_of(led_card) >= 9 and R.suit_of(led_card) == led:
				var cover := _lowest(beaters)
				if R.rank_of(cover) >= 9:
					return cover
			# take a sure trick when the last hand cannot beat it and it is late
			var cheap := _lowest(beaters)
			if secure(t, seat, cheap, vis) and (t.tricks_left() <= 5 or R.rank_of(cheap) >= 11):
				return cheap
			return _lowest(legal)
		# third hand: win it, as cheaply as is safe
		for c in _sorted_up(beaters):
			if secure(t, seat, c, vis):
				return c
		return _top_of_equals(beaters, vis, own)
	# void in the led suit
	var trumps: Array = []
	if t.trump < 4:
		trumps = R.cards_in(legal, t.trump)
	if pard_win and (pos == 3 or secure(t, seat, wc, vis)):
		return _discard(t, seat, legal, vis)
	if not trumps.is_empty():
		var ruffs: Array = []
		for c in trumps:
			if R.beats(c, wc, led, t.trump):
				ruffs.append(c)
		if not ruffs.is_empty():
			if pos == 3:
				return _lowest(ruffs)
			for c in _sorted_up(ruffs):
				if secure(t, seat, c, vis):
					return c
			return _lowest(ruffs)
	return _discard(t, seat, legal, vis)

static func _sorted_up(cards: Array) -> Array:
	var a := cards.duplicate()
	a.sort_custom(func(x: int, y: int) -> bool: return R.rank_of(x) < R.rank_of(y))
	return a

## Throw the least useful card: low, from a suit with nothing worth guarding, never a
## trump if anything else will do.
static func _discard(t: Table, seat: int, legal: Array, vis: PackedByteArray) -> int:
	var own: Array = t.hands[seat]
	var best := -1
	var best_cost := 1e9
	for s in 4:
		if s == t.trump:
			continue
		var cs := R.cards_in(legal, s)
		if cs.is_empty():
			continue
		var low := _lowest(cs)
		var cost := float(R.rank_of(low)) - cs.size() * 0.6
		if is_master(t, low, own):
			cost += 12.0
		# keep a guard with an honour: Kx, Qxx
		for c in cs:
			var r := R.rank_of(c)
			if r >= 10 and r < 12 and cs.size() <= 13 - r:
				cost += 5.0
		if cost < best_cost:
			best_cost = cost
			best = low
	if best >= 0:
		return best
	return _lowest(legal)

static func _lead(t: Table, seat: int, legal: Array, vis: PackedByteArray) -> int:
	var b := brain(t, seat)
	if b == t.declarer:
		return _declarer_lead(t, seat, legal, vis)
	if not t.exposed:
		return _opening_lead(t, seat, legal)
	return _defender_lead(t, seat, legal, vis)

static func _opening_lead(t: Table, seat: int, legal: Array) -> int:
	var hand: Array = t.hands[seat]
	var l := R.lengths(hand)
	var pard := R.partner_of(seat)
	# partner's suit first
	for s in t.bid_suits[pard]:
		if s != t.trump and l[s] > 0:
			return _lead_from(R.cards_in(hand, s), t.trump == 4, true)
	var nt := t.trump == 4
	var best := -1
	var best_score := -1e9
	for s in 4:
		if l[s] == 0 or (s == t.trump and l[s] < 4):
			continue
		var cs := R.cards_in(hand, s)
		var score := 0.0
		var seq := _sequence(cs)
		if nt:
			score = l[s] * 3.0 + _suit_honours(cs) + seq * 4.0
		else:
			score = seq * 5.0 + (6.0 if _has_ak(cs) else 0.0)
			if l[s] == 1 and s != t.trump and l[t.trump] >= 1 and l[t.trump] <= 3:
				score += 5.0
			# leading away from an ace or a king gives a trick away
			if not _has_ak(cs) and seq == 0 and _has(cs, 12):
				score -= 8.0
			if not _has_ak(cs) and seq == 0 and _has(cs, 11):
				score -= 4.0
		# the opponents' suits are theirs
		for o in [(seat + 1) % 4, (seat + 3) % 4]:
			if t.bid_suits[o].has(s):
				score -= 6.0
		if s == t.trump:
			score -= 3.0
		if score > best_score:
			best_score = score
			best = s
	if best < 0:
		return legal[0]
	return _lead_from(R.cards_in(hand, best), nt, false)

## The standard card from a suit: top of a sequence, top of a doubleton, fourth best from
## an honour, top of nothing.
static func _lead_from(cs: Array, nt: bool, partner_suit: bool) -> int:
	var sorted := _sorted_up(cs)
	sorted.reverse()      # high to low
	var n := sorted.size()
	if n == 1:
		return sorted[0]
	if _has_ak(cs) and not nt:
		return sorted[0]
	if _sequence(cs) > 0:
		return sorted[0]
	if n == 2:
		return sorted[0]
	var honour := R.rank_of(sorted[0]) >= 9
	if partner_suit:
		return sorted[n - 1] if honour else sorted[0]
	if honour:
		return sorted[3] if n >= 4 else sorted[n - 1]
	return sorted[0] if n <= 3 else sorted[1]

static func _has(cs: Array, rank: int) -> bool:
	for c in cs:
		if R.rank_of(c) == rank:
			return true
	return false

static func _has_ak(cs: Array) -> bool:
	return _has(cs, 12) and _has(cs, 11)

## Top touching honours (AK, KQ, QJ, JT): 1 if the suit is headed by a sequence.
static func _sequence(cs: Array) -> int:
	var top := -1
	for c in cs:
		top = maxi(top, R.rank_of(c))
	if top < 9:
		return 0
	return 1 if _has(cs, top - 1) else 0

static func _suit_honours(cs: Array) -> float:
	var n := 0.0
	for c in cs:
		if R.rank_of(c) >= 9:
			n += R.rank_of(c) - 8
	return n * 0.5

static func _defender_lead(t: Table, seat: int, legal: Array, vis: PackedByteArray) -> int:
	var own: Array = t.hands[seat]
	var dec := t.declarer
	var dum := t.dummy
	var trump_left := t.trump < 4 and (may_have(t, seat, dec, t.trump, vis) or may_have(t, seat, dum, t.trump, vis))
	# cash a master card unless it will just be ruffed
	for c in legal:
		if R.suit_of(c) == t.trump:
			continue
		if is_master(t, c, own):
			var s := R.suit_of(c)
			var ruffable := trump_left and (not may_have(t, seat, dec, s, vis) or not may_have(t, seat, dum, s, vis))
			if not ruffable:
				return c
	# return partner's suit (the first one partner led)
	var pard := R.partner_of(seat)
	for s in t.bid_suits[pard]:
		var cs := R.cards_in(legal, s)
		if not cs.is_empty() and s != t.trump:
			return _lead_from(cs, t.trump == 4, true)
	var best := -1
	var best_score := -1e9
	var dummy_after := (seat + 1) % 4 == dum
	for s in 4:
		var cs := R.cards_in(legal, s)
		if cs.is_empty():
			continue
		var score := 0.0
		if t.trump == 4:
			score += cs.size() * 2.0 + _sequence(cs) * 3.0
		else:
			if s == t.trump:
				score -= 2.0
			# never give a ruff and discard
			if s != t.trump and trump_left and not may_have(t, seat, dec, s, vis) and not may_have(t, seat, dum, s, vis):
				score -= 20.0
			score += _sequence(cs) * 3.0
		# through strength in dummy on the left, up to weakness on the right
		var dh := R.cards_in(t.hands[dum], s)
		var dstrength := _suit_honours(dh)
		score += dstrength if dummy_after else -dstrength
		if score > best_score:
			best_score = score
			best = s
	return _lead_from(R.cards_in(legal, best), t.trump == 4, false)

static func _declarer_lead(t: Table, seat: int, legal: Array, vis: PackedByteArray) -> int:
	var other := t.dummy if seat == t.declarer else t.declarer
	var mine: Array = t.hands[seat]
	var theirs: Array = t.hands[other]
	var both: Array = mine + theirs
	var defenders := [(t.declarer + 1) % 4, (t.declarer + 3) % 4]
	# draw trumps while the defenders still hold some and we have more
	if t.trump < 4:
		var out := 0
		for r in 13:
			if vis[t.trump * 13 + r] == 0:
				out += 1
		var ours := R.cards_in(both, t.trump).size()
		var my_trumps := R.cards_in(legal, t.trump)
		if out > 0 and ours > out and not my_trumps.is_empty():
			var top := _highest(my_trumps)
			if is_master(t, top, both):
				return top
			var other_top := R.cards_in(theirs, t.trump)
			if not other_top.is_empty() and is_master(t, _highest(other_top), both):
				return _lowest(my_trumps)
			return _top_of_equals(my_trumps, vis, mine) if _sequence(my_trumps) > 0 else _lowest(my_trumps)
	# cash side-suit winners that will not be ruffed
	var trumps_out := false
	if t.trump < 4:
		for d in defenders:
			if may_have(t, seat, d, t.trump, vis):
				trumps_out = true
	for c in legal:
		if is_master(t, c, both):
			var s := R.suit_of(c)
			var safe := true
			if trumps_out and s != t.trump:
				for d in defenders:
					if not may_have(t, seat, d, s, vis):
						safe = false
			if safe:
				return c
	# go over to the other hand's winner
	for s in 4:
		var there := R.cards_in(theirs, s)
		var here := R.cards_in(legal, s)
		if there.is_empty() or here.is_empty():
			continue
		if is_master(t, _highest(there), both) and not is_master(t, _highest(here), both):
			return _lowest(here)
	# build a trick: lead the longest combined suit, top of a sequence or low towards honours
	var best := -1
	var best_len := -1
	for s in 4:
		if s == t.trump:
			continue
		var here := R.cards_in(legal, s)
		if here.is_empty():
			continue
		var n := R.cards_in(both, s).size() * 2 + (3 if _sequence(here) > 0 else 0)
		if n > best_len:
			best_len = n
			best = s
	if best < 0:
		return _lowest(legal)
	var here := R.cards_in(legal, best)
	if _sequence(here) > 0:
		return _top_of_equals(here, vis, mine)
	return _lowest(here)

## ---- hard: sample the unseen cards, play it out ---------------------------------------

static func monte_carlo(t: Table, seat: int, legal: Array, rng: RandomNumberGenerator, budget_ms: int) -> int:
	var cands := _distinct(t, seat, legal)
	if cands.size() == 1:
		return cands[0]
	var side := seat % 2
	var totals: Array = []
	totals.resize(cands.size())
	totals.fill(0.0)
	var deadline := Time.get_ticks_msec() + budget_ms
	var samples := 0
	var exact := t.tricks_left() <= 3
	while samples < 60 and (samples < 6 or Time.get_ticks_msec() < deadline):
		var world := _sample(t, seat, rng)
		if world == null:
			break
		samples += 1
		for k in cands.size():
			var w := world.copy()
			w.play(cands[k])
			if exact:
				totals[k] += float(_solve(w, side, -1, 99))
			else:
				totals[k] += float(_rollout(w, side))
	if samples == 0:
		return heuristic(t, seat)
	var pick := heuristic(t, seat)
	var best := -1e9
	var pick_i := cands.find(pick)
	if pick_i >= 0:
		best = totals[pick_i]
	for k in cands.size():
		if totals[k] > best + 0.01:
			best = totals[k]
			pick = cands[k]
	return pick

## One card per group of touching cards: the others would do the same.
static func _distinct(t: Table, seat: int, legal: Array) -> Array:
	var out: Array = []
	var vis := visible(t, seat)
	var own: Array = t.hands[seat]
	var sorted := _sorted_up(legal)
	for c in sorted:
		var dup := false
		for o in out:
			if R.suit_of(o) != R.suit_of(c):
				continue
			var lo := mini(R.rank_of(o), R.rank_of(c))
			var hi := maxi(R.rank_of(o), R.rank_of(c))
			var touching := true
			for r in range(lo + 1, hi):
				var x := R.suit_of(c) * 13 + r
				if not own.has(x) and t.played[x] == 0:
					touching = false
					break
			if touching:
				dup = true
				break
		if not dup:
			out.append(c)
	return out

## A full table where the cards `seat` cannot see are dealt at random to the hands that
## could hold them, respecting shown voids and (loosely) the auction.
static func _sample(t: Table, seat: int, rng: RandomNumberGenerator) -> Table:
	var vis := visible(t, seat)
	var unseen: Array = []
	for c in 52:
		if vis[c] == 0:
			unseen.append(c)
	var hidden: Array = []
	for s in 4:
		if not hand_visible(t, seat, s):
			hidden.append(s)
	for attempt in 30:
		var pool := unseen.duplicate()
		for i in range(pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: int = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		var w := t.copy()
		var need: Array = []
		for s in hidden:
			need.append((t.hands[s] as Array).size())
			w.hands[s] = []
		var ok := true
		# deal the most constrained cards first: each card to a hidden hand that may hold it
		for c in pool:
			var su := R.suit_of(c)
			var choices: Array = []
			for k in hidden.size():
				var s: int = hidden[k]
				if (w.hands[s] as Array).size() < need[k] and t.voids[s][su] == 0:
					choices.append(k)
			if choices.is_empty():
				ok = false
				break
			var pick: int = choices[rng.randi_range(0, choices.size() - 1)]
			(w.hands[hidden[pick]] as Array).append(c)
		if not ok:
			continue
		if attempt < 20 and not _fits_auction(w, hidden):
			continue
		return w
	return null

static func _fits_auction(w: Table, hidden: Array) -> bool:
	if w.shape.is_empty():
		return true
	for s in hidden:
		var sh: Dictionary = w.shape[s]
		if sh.is_empty():
			continue
		# count the suit including cards this seat already played
		var l := [0, 0, 0, 0]
		for c in w.hands[s]:
			l[R.suit_of(c)] += 1
		var gone: Array = sh.get("played", [0, 0, 0, 0])
		for su in 4:
			var total: int = l[su] + int(gone[su])
			if total < int(sh["lmin"][su]) - 1 or total > int(sh["lmax"][su]) + 1:
				return false
	return true

## Everyone plays the normal rules to the end; returns tricks for `side`.
static func _rollout(w: Table, side: int) -> int:
	while not (w.hands[0] as Array).is_empty() or not w.trick.is_empty():
		var s := w.to_play()
		if (w.hands[s] as Array).is_empty():
			break
		w.play(heuristic(w, s))
	return w.won[side]

## Exact play-out for the last few tricks, alpha-beta on tricks for `side`.
static func _solve(w: Table, side: int, alpha: int, beta: int) -> int:
	if (w.hands[w.to_play()] as Array).is_empty():
		return w.won[side]
	var s := w.to_play()
	var legal := R.legal_cards(w.hands[s], w.trick)
	var maxing := s % 2 == side
	var best := -1 if maxing else 99
	for c in legal:
		var n := w.copy()
		n.play(c)
		var v := _solve(n, side, alpha, beta)
		if maxing:
			best = maxi(best, v)
			alpha = maxi(alpha, v)
		else:
			best = mini(best, v)
			beta = mini(beta, v)
		if alpha >= beta:
			break
	return best
