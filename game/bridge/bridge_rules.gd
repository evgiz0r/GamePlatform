extends RefCounted
## The rules of contract bridge as pure functions: cards, calls, the auction, tricks and
## rubber scoring. No nodes, no state -- the table (bridge.gd) and both brains
## (bridge_bidder.gd, bridge_player.gd) all ask the same questions here.
##
## Seats go round the table clockwise in the order play moves: 0 south (you), 1 west,
## 2 north (partner), 3 east. A seat's partner is seat + 2; seat % 2 is its side
## (0 = north-south, "we"; 1 = east-west, "they").
##
## A card is an int 0..51: suit * 13 + rank, rank 0 is the two and 12 the ace.
## Suits 0 clubs, 1 diamonds, 2 hearts, 3 spades; strain 4 is no trumps.
## A call is an int: 0 pass, 1 double, 2 redouble, 3.. a bid, 3 + (level - 1) * 5 + strain.

const CLUBS := 0
const DIAMONDS := 1
const HEARTS := 2
const SPADES := 3
const NT := 4

const PASS := 0
const DBL := 1
const RDBL := 2

const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const STRAIN_NAMES := ["clubs", "diamonds", "hearts", "spades", "no trumps"]
const SEAT_NAMES := ["south", "west", "north", "east"]
const SEAT_SHORT := ["S", "W", "N", "E"]

## ---- cards ----------------------------------------------------------------------

static func suit_of(c: int) -> int:
	return c / 13

static func rank_of(c: int) -> int:
	return c % 13

static func make_card(suit: int, rank: int) -> int:
	return suit * 13 + rank

static func side_of(seat: int) -> int:
	return seat % 2

static func partner_of(seat: int) -> int:
	return (seat + 2) % 4

## Four sorted hands of thirteen.
static func deal(rng: RandomNumberGenerator) -> Array:
	var deck: Array = []
	for i in 52:
		deck.append(i)
	for i in range(51, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = deck[i]
		deck[i] = deck[j]
		deck[j] = t
	var hands: Array = []
	for s in 4:
		var h: Array = deck.slice(s * 13, s * 13 + 13)
		sort_hand(h)
		hands.append(h)
	return hands

## Display order: spades, hearts, clubs, diamonds (colours alternate), high to low.
static func sort_hand(h: Array) -> void:
	h.sort_custom(func(a: int, b: int) -> bool:
		var ka := _display_key(a)
		var kb := _display_key(b)
		return ka > kb)

static func _display_key(c: int) -> int:
	# clubs, diamonds, hearts, spades -> S H C D, so the colours alternate
	var so: int = [2, 1, 3, 4][suit_of(c)]
	return so * 13 + rank_of(c)

static func hcp(hand: Array) -> int:
	var n := 0
	for c in hand:
		var r := rank_of(c)
		if r >= 9:
			n += r - 8
	return n

static func lengths(hand: Array) -> Array:
	var l := [0, 0, 0, 0]
	for c in hand:
		l[suit_of(c)] += 1
	return l

## 4-3-3-3, 4-4-3-2 or 5-3-3-2.
static func balanced(l: Array) -> bool:
	var doubles := 0
	for n in l:
		if n < 2:
			return false
		if n == 2:
			doubles += 1
	return doubles <= 1

static func cards_in(hand: Array, suit: int) -> Array:
	var out: Array = []
	for c in hand:
		if suit_of(c) == suit:
			out.append(c)
	return out

static func card_text(c: int) -> String:
	return RANKS[rank_of(c)]

## ---- calls ----------------------------------------------------------------------

static func make_bid(level: int, strain: int) -> int:
	return 3 + (level - 1) * 5 + strain

static func bid_level(b: int) -> int:
	return (b - 3) / 5 + 1

static func bid_strain(b: int) -> int:
	return (b - 3) % 5

static func is_bid(b: int) -> bool:
	return b >= 3

static func call_text(b: int) -> String:
	match b:
		PASS: return "pass"
		DBL: return "X"
		RDBL: return "XX"
	var st := bid_strain(b)
	return str(bid_level(b)) + ["C", "D", "H", "S", "NT"][st]

static func seat_at(dealer: int, i: int) -> int:
	return (dealer + i) % 4

## The facts of an auction so far: last bid and who made it, whether it is doubled,
## who calls next.
static func auction_state(auc: Array, dealer: int) -> Dictionary:
	var last := -1
	var last_seat := -1
	var dbl := 0
	for i in auc.size():
		var c: int = auc[i]
		if is_bid(c):
			last = c
			last_seat = seat_at(dealer, i)
			dbl = 0
		elif c == DBL:
			dbl = 1
		elif c == RDBL:
			dbl = 2
	return {"last": last, "last_seat": last_seat, "dbl": dbl,
		"to_act": seat_at(dealer, auc.size())}

static func legal_calls(auc: Array, dealer: int) -> Array:
	var st := auction_state(auc, dealer)
	var out: Array = [PASS]
	var me: int = st["to_act"]
	if st["last"] >= 0:
		var opp := side_of(st["last_seat"]) != side_of(me)
		if opp and st["dbl"] == 0:
			out.append(DBL)
		if not opp and st["dbl"] == 1:
			out.append(RDBL)
	var lo: int = maxi(3, int(st["last"]) + 1)
	for b in range(lo, 38):
		out.append(b)
	return out

static func is_legal(auc: Array, dealer: int, call: int) -> bool:
	return legal_calls(auc, dealer).has(call)

static func auction_over(auc: Array) -> bool:
	if auc.size() < 4:
		return false
	return auc[-1] == PASS and auc[-2] == PASS and auc[-3] == PASS

static func passed_out(auc: Array) -> bool:
	if auc.size() != 4:
		return false
	for c in auc:
		if c != PASS:
			return false
	return true

## {level, strain, dbl, declarer} for a finished auction, or {} if it was passed out.
## The declarer is whoever of the winning side first named the final strain.
static func final_contract(auc: Array, dealer: int) -> Dictionary:
	var st := auction_state(auc, dealer)
	if st["last"] < 0:
		return {}
	var strain := bid_strain(st["last"])
	var side := side_of(st["last_seat"])
	var decl := -1
	for i in auc.size():
		var c: int = auc[i]
		var s := seat_at(dealer, i)
		if is_bid(c) and bid_strain(c) == strain and side_of(s) == side:
			decl = s
			break
	return {"level": bid_level(st["last"]), "strain": strain, "dbl": st["dbl"], "declarer": decl}

## ---- tricks ----------------------------------------------------------------------

## Cards `hand` may play to a trick that has `trick` in it already ([[seat, card], ...]).
static func legal_cards(hand: Array, trick: Array) -> Array:
	if trick.is_empty():
		return hand.duplicate()
	var led := suit_of(trick[0][1])
	var follow := cards_in(hand, led)
	return follow if not follow.is_empty() else hand.duplicate()

## Index into `trick` of the card winning it so far.
static func winning_index(trick: Array, trump: int) -> int:
	var best := 0
	for i in range(1, trick.size()):
		if beats(trick[i][1], trick[best][1], suit_of(trick[0][1]), trump):
			best = i
	return best

## Does card a beat card b, given the led suit and trumps?
static func beats(a: int, b: int, led: int, trump: int) -> bool:
	var sa := suit_of(a)
	var sb := suit_of(b)
	if sa == sb:
		return rank_of(a) > rank_of(b)
	if trump < 4 and sa == trump:
		return true
	return false

## ---- rubber scoring ------------------------------------------------------------------

static func trick_value(strain: int) -> int:
	return 20 if strain <= DIAMONDS else 30

## Points below the line for bid-and-made tricks.
static func contract_points(level: int, strain: int, dbl: int) -> int:
	var p := level * trick_value(strain) + (10 if strain == NT else 0)
	return p * [1, 2, 4][dbl]

## What one deal is worth. `taken` is the declaring side's tricks.
## Returns {made, over, down, below, above_decl, above_def, parts: [text...]}
static func score_deal(con: Dictionary, taken: int, vul: bool) -> Dictionary:
	var level: int = con["level"]
	var strain: int = con["strain"]
	var dbl: int = con["dbl"]
	var need := 6 + level
	var r := {"made": taken >= need, "over": 0, "down": 0, "below": 0,
		"above_decl": 0, "above_def": 0, "parts": []}
	if taken >= need:
		var below := contract_points(level, strain, dbl)
		r["below"] = below
		r["parts"].append("contract %d" % below)
		var over := taken - need
		r["over"] = over
		if over > 0:
			var per := trick_value(strain)
			if dbl == 1:
				per = 200 if vul else 100
			elif dbl == 2:
				per = 400 if vul else 200
			r["above_decl"] += over * per
			r["parts"].append("overtricks %d" % (over * per))
		if dbl > 0:
			r["above_decl"] += 50 * dbl
			r["parts"].append("for the double %d" % (50 * dbl))
		if level == 6:
			var b := 750 if vul else 500
			r["above_decl"] += b
			r["parts"].append("small slam %d" % b)
		elif level == 7:
			var b := 1500 if vul else 1000
			r["above_decl"] += b
			r["parts"].append("grand slam %d" % b)
	else:
		var down := need - taken
		r["down"] = down
		var pen := 0
		for k in range(1, down + 1):
			if dbl == 0:
				pen += 100 if vul else 50
			elif vul:
				pen += 200 if k == 1 else 300
			else:
				pen += 100 if k == 1 else (200 if k <= 3 else 300)
		if dbl == 2:
			pen *= 2
		r["above_def"] = pen
		r["parts"].append("down %d: %d" % [down, pen])
	return r

## Honours held in one hand, scored above the line for that hand's side whatever the
## result: four of the five top trumps 100, all five 150; at no trumps all four aces 150.
## Returns {seat, points} or {}.
static func honours(hands: Array, strain: int) -> Dictionary:
	for s in 4:
		var h: Array = hands[s]
		if strain == NT:
			var aces := 0
			for c in h:
				if rank_of(c) == 12:
					aces += 1
			if aces == 4:
				return {"seat": s, "points": 150}
		else:
			var n := 0
			for c in h:
				if suit_of(c) == strain and rank_of(c) >= 8:
					n += 1
			if n == 5:
				return {"seat": s, "points": 150}
			if n == 4:
				return {"seat": s, "points": 100}
	return {}
