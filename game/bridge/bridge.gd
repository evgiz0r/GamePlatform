extends GameMode
## bridge -- rubber bridge, you and a computer partner against two computer opponents.
## See GAME.md. You sit south; partner is north across the table. The auction is bid on
## the bidding box, cards are played by tapping them. When your side wins the contract
## you play both your hand and partner's, as declarer does. First side to two games
## wins the rubber.
##
## The rules and scoring live in bridge_rules.gd, the bidding brain in bridge_bidder.gd,
## the card-play brain in bridge_player.gd. This file is the table: dealing, turns, the
## screen and your taps.

const R := preload("res://game/bridge/bridge_rules.gd")
const B := preload("res://game/bridge/bridge_bidder.gd")
const P := preload("res://game/bridge/bridge_player.gd")

const SOUTH := 0
const WEST := 1
const NORTH := 2
const EAST := 3

## The shell default (0.8) is loud for a game that clicks every card. Scaled in memory
## only while bridge is on screen -- the saved settings file is never touched.
const SFX_SCALE := 0.28
const LEVEL_ORDER := ["easy", "normal", "hard"]
## Partner is always at its best: difficulty is about the opponents.
const PARTNER_LEVEL := "hard"

const AI_CALL_TIME := 0.6
const AI_CARD_TIME := 0.5
const TRICK_PAUSE := 1.1
const SWEEP_TIME := 0.25
const FLY_TIME := 0.16

## Layout, in the 640x360 design space.
const S_CARD := Vector2(42, 60)
const N_CARD := Vector2(34, 48)
const T_CARD := Vector2(36, 50)
const S_TOP := 292.0
const N_TOP := 36.0
const MID := Vector2(320, 190)
const SLOT := [Vector2(320, 238), Vector2(266, 190), Vector2(320, 142), Vector2(374, 190)]
const BOX := Vector2(334, 104)          ## bidding box top-left
const CELL := Vector2(33, 19)
const AUC := Vector2(146, 114)          ## auction table top-left
const AUC_COL := 44.0

var _rng := RandomNumberGenerator.new()
var _level := "normal"
var _tempo := 1.0

## one deal
var _phase := "bid"                 ## bid, play, result, over
var _dealer := SOUTH
var _hands: Array = []              ## as dealt, kept for honours and the review
var _auc: Array = []
var _con: Dictionary = {}
var _table: P.Table
var _shown: Array = []              ## trick on screen: [seat, card, age]
var _sweep := -1.0                  ## >= 0 while the finished trick slides to its winner
var _sweep_to := SOUTH
var _pause := 0.0
var _wait := 0.0
var _deal_t := 0.0
var _last_trick: Array = []
var _result: Dictionary = {}

## the rubber: index 0 is we (north-south), 1 they
var _games := [0, 0]
var _part := [0, 0]                 ## below the line toward the current game
var _below := [0, 0]                ## all below the line
var _above := [0, 0]
var _deals := 0

var _hits: Array = []               ## [{rect, kind, value}] from the last draw
var _kb := -1                       ## keyboard selection among the current options
var _t := 0.0
var _sfx_was := 0.8
var _idle_limit := 0.0
var _idle_t := 0.0
var _me: Node2D
var _markers: Array = []

func _ready() -> void:
	title = "bridge"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	_rng.randomize()
	# There is no clock, so a player who does nothing never loses; a playtest may make
	# doing nothing count as conceding the rubber. It may also pick the opponents and
	# speed the table up, since bots cannot press buttons and a rubber is long.
	var forced := OS.get_environment("BRIDGE_IDLE_SECONDS")
	if forced.is_valid_float() and float(forced) > 0.0:
		_idle_limit = float(forced)
	var lv := OS.get_environment("BRIDGE_LEVEL")
	if LEVEL_ORDER.has(lv):
		_level = lv
	var tempo := OS.get_environment("BRIDGE_TEMPO")
	if tempo.is_valid_float() and float(tempo) > 0.0:
		_tempo = float(tempo)

	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()
	set_lives(0)

	_me = Node2D.new()
	_me.position = SLOT[SOUTH] + Vector2(0, 80)
	add_child(_me)
	Probe.track(_me, "@")

	_new_rubber()
	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the rubber and the deal ----------------------------------------------------------

func _new_rubber() -> void:
	_games = [0, 0]
	_part = [0, 0]
	_below = [0, 0]
	_above = [0, 0]
	_deals = 0
	_dealer = _rng.randi_range(0, 3)
	score = 0
	Bus.score_changed.emit(score)
	_new_deal()

func _new_deal() -> void:
	_hands = R.deal(_rng)
	_auc = []
	_con = {}
	_table = null
	_shown = []
	_last_trick = []
	_sweep = -1.0
	_pause = 0.0
	_result = {}
	_phase = "bid"
	_deal_t = 0.0
	_kb = -1
	_wait = AI_CALL_TIME * _tempo + 0.5
	_deals += 1
	Audio.play("open", 0.05, -6.0)
	Probe.event("deal", {"n": _deals, "dealer": R.SEAT_NAMES[_dealer], "your_hcp": R.hcp(_hands[SOUTH])})
	_refresh_markers()

func _level_for(seat: int) -> String:
	return PARTNER_LEVEL if seat % 2 == 0 else _level

func _we_declare() -> bool:
	return not _con.is_empty() and int(_con["declarer"]) % 2 == 0

## Which seats your taps play for right now.
func _yours(seat: int) -> bool:
	if seat == SOUTH:
		return true
	return seat == NORTH and _phase == "play" and _we_declare()

func _to_act() -> int:
	if _phase == "bid":
		return R.seat_at(_dealer, _auc.size())
	if _phase == "play" and _table != null:
		return _table.to_play()
	return -1

func _vul(side: int) -> bool:
	return _games[side] >= 1

## ---- the auction ----------------------------------------------------------------------

func _make_call(call: int) -> void:
	var seat := R.seat_at(_dealer, _auc.size())
	if not R.is_legal(_auc, _dealer, call):
		return
	_auc.append(call)
	_kb = -1
	Audio.play("click", 0.08, -4.0 if call == R.PASS else 0.0)
	Probe.event("call", {"seat": R.SEAT_SHORT[seat], "call": R.call_text(call)})
	if R.is_bid(call) or call != R.PASS:
		Juice.shake(1.0)
	if R.auction_over(_auc):
		_end_auction()
		return
	_wait = AI_CALL_TIME * _tempo
	_refresh_markers()

func _end_auction() -> void:
	if R.passed_out(_auc):
		Probe.event("passed_out")
		_result = {"passed": true, "lines": ["passed out", "nobody opened -- a fresh deal"]}
		_phase = "result"
		_dealer = (_dealer + 1) % 4
		_refresh_markers()
		return
	_con = R.final_contract(_auc, _dealer)
	_table = P.Table.new()
	for s in 4:
		_table.hands[s] = (_hands[s] as Array).duplicate()
	_table.trump = _con["strain"]
	_table.declarer = _con["declarer"]
	_table.dummy = R.partner_of(_con["declarer"])
	_table.leader = (int(_con["declarer"]) + 1) % 4
	var inf := B.infer(_auc, _dealer, _auc.size())
	for s in 4:
		_table.bid_suits[s] = inf[s]["suits"]
		_table.shape.append({"lmin": inf[s]["lmin"], "lmax": inf[s]["lmax"], "played": [0, 0, 0, 0]})
	_phase = "play"
	_wait = AI_CARD_TIME * _tempo + 0.4
	Audio.play("select", 0.05, -4.0)
	Probe.event("contract", {"contract": _con_text(), "by": R.SEAT_NAMES[_con["declarer"]]})
	_refresh_markers()

## ---- the play ---------------------------------------------------------------------------

func _play_card(card: int) -> void:
	var seat := _table.to_play()
	if not R.legal_cards(_table.hands[seat], _table.trick).has(card):
		return
	var led := -1
	if not _table.trick.is_empty():
		led = R.suit_of(_table.trick[0][1])
	var trick_before: Array = _table.trick.duplicate(true)
	_table.shape[seat]["played"][R.suit_of(card)] += 1
	var winner := _table.play(card)
	_shown.append([seat, card, 0.0])
	_kb = -1
	Audio.play("impact_light", 0.12, -2.0)
	if led >= 0 and R.suit_of(card) != led and R.suit_of(card) == _table.trump:
		Juice.shake(3.0)
		Audio.play("impact_punch", 0.1, -8.0)
	if winner >= 0:
		trick_before.append([seat, card])
		_last_trick = trick_before
		_sweep_to = winner
		_pause = TRICK_PAUSE * _tempo
		Probe.event("trick", {"winner": R.SEAT_SHORT[winner], "we": _table.won[0], "they": _table.won[1]})
	else:
		_wait = AI_CARD_TIME * _tempo
	_refresh_markers()

func _collect_trick() -> void:
	var we := _sweep_to % 2 == 0
	Audio.play("pickup" if we else "impact_soft", 0.08, -3.0 if we else -6.0)
	if we:
		Juice.text(self, SLOT[_sweep_to] + Vector2(-12, -40), "trick", Palette.col("prize"))
	_shown = []
	_sweep = -1.0
	_wait = AI_CARD_TIME * _tempo
	if (_table.hands[0] as Array).is_empty():
		_score_deal()
	_refresh_markers()

func _score_deal() -> void:
	var ds: int = int(_con["declarer"]) % 2
	var taken: int = _table.won[ds]
	var vul := _vul(ds)
	var res := R.score_deal(_con, taken, vul)
	var before := [_above[0] + _below[0], _above[1] + _below[1]]
	var lines: Array = []
	var who := "we" if ds == 0 else "they"
	var need := 6 + int(_con["level"])
	if res["made"]:
		lines.append("%s made %s%s" % [_con_text(), "" if res["over"] == 0 else "+%d " % res["over"], "by " + R.SEAT_NAMES[_con["declarer"]]])
		_part[ds] += res["below"]
		_below[ds] += res["below"]
		_above[ds] += res["above_decl"]
	else:
		lines.append("%s down %d" % [_con_text(), res["down"]])
		_above[1 - ds] += res["above_def"]
	lines.append("%s took %d of %d needed" % [who, taken, need])
	var hon := R.honours(_hands, _con["strain"])
	if not hon.is_empty():
		var hs: int = int(hon["seat"]) % 2
		_above[hs] += int(hon["points"])
		lines.append("honours %d to %s (%s)" % [hon["points"], "we" if hs == 0 else "they", R.SEAT_NAMES[hon["seat"]]])
	var over := false
	if _part[ds] >= 100:
		_games[ds] += 1
		_part = [0, 0]
		lines.append("GAME to %s" % ("us" if ds == 0 else "them"))
		if _games[ds] == 2:
			var bonus := 700 if _games[1 - ds] == 0 else 500
			_above[ds] += bonus
			lines.append("RUBBER to %s  +%d" % ["us" if ds == 0 else "them", bonus])
			over = true
	var gain: int = (_above[0] + _below[0]) - before[0]
	var loss: int = (_above[1] + _below[1]) - before[1]
	if gain > 0:
		add_score(gain)
		Juice.text(self, MID + Vector2(-20, -60), "+%d" % gain, Palette.col("prize"))
		Audio.play("coin", 0.05, -2.0)
		Juice.shake(4.0 if res["made"] and ds == 0 else 2.0)
	elif loss > 0:
		Audio.play("thud", 0.05, -4.0)
		Juice.text(self, MID + Vector2(-20, -60), "they +%d" % loss, Palette.col("hazard"))
	_result = {"passed": false, "lines": lines, "we": gain, "they": loss, "made": res["made"], "over": over}
	Probe.event("deal_scored", {"contract": _con_text(), "made": res["made"], "we": gain, "they": loss,
		"games": _games.duplicate()})
	_phase = "result"
	_dealer = (_dealer + 1) % 4
	Probe.capture("deal %d" % _deals)

func _continue() -> void:
	if _phase != "result":
		return
	if _result.get("over", false):
		_end_rubber()
		return
	_new_deal()

func _end_rubber() -> void:
	if finished:
		return
	var we: int = _above[0] + _below[0]
	var they: int = _above[1] + _below[1]
	Probe.event("rubber_over", {"we": we, "they": they, "deals": _deals, "level": _level})
	_phase = "over"
	if we > they:
		Audio.play("voice_you_win")
		Juice.shake(6.0)
		win()
	else:
		Audio.play("voice_you_lose")
		lose()

func _con_text() -> String:
	if _con.is_empty():
		return ""
	var t: String = str(_con["level"]) + ["C", "D", "H", "S", "NT"][_con["strain"]]
	return t + ["", "x", "xx"][_con["dbl"]]

## ---- the computer and "auto" ------------------------------------------------------------

func _ai_call(seat: int) -> int:
	return B.choose(_hands[seat], _auc, _dealer, _level_for(seat), _rng)

func _ai_card(seat: int) -> int:
	return P.choose(_table, _level_for(seat) if not _yours(seat) else PARTNER_LEVEL, _rng, 260)

## Space (or the "auto" button): the computer makes your call or plays your card. It is
## also how the bots get a whole rubber played.
func _auto() -> void:
	if finished:
		return
	var seat := _to_act()
	if _phase == "result":
		_continue()
		return
	if seat < 0 or not _yours(seat) or _pause > 0.0 or _sweep >= 0.0:
		return
	if _phase == "bid":
		_make_call(_ai_call(seat))
	elif _phase == "play":
		_play_card(_ai_card(seat))

func _process(delta: float) -> void:
	_t += delta
	_deal_t += delta
	for e in _shown:
		e[2] += delta
	queue_redraw()
	if finished:
		return
	if _idle_limit > 0.0:
		_idle_t += delta
		if _idle_t > _idle_limit:
			Probe.event("conceded_idle", {"after": _idle_limit})
			_phase = "over"
			lose()
			return

	_keyboard()
	if _phase == "result":
		return
	if _sweep >= 0.0:
		_sweep += delta
		if _sweep >= SWEEP_TIME * minf(1.0, _tempo * 2.0):
			_collect_trick()
		return
	if _pause > 0.0:
		_pause -= delta
		if _pause <= 0.0:
			_sweep = 0.0
		return
	var seat := _to_act()
	if seat < 0 or _yours(seat):
		return
	_wait -= delta
	if _wait > 0.0:
		return
	if _phase == "bid":
		_make_call(_ai_call(seat))
	elif _phase == "play":
		_play_card(_ai_card(seat))

## ---- input ----------------------------------------------------------------------------

## What the keyboard can pick from right now: legal calls or legal cards.
func _options() -> Array:
	var seat := _to_act()
	if seat < 0 or not _yours(seat) or _pause > 0.0 or _sweep >= 0.0:
		return []
	if _phase == "bid":
		return R.legal_calls(_auc, _dealer)
	if _phase == "play":
		var legal := R.legal_cards(_table.hands[seat], _table.trick)
		var ordered: Array = []
		for c in _table.hands[seat]:
			if legal.has(c):
				ordered.append(c)
		return ordered
	return []

func _keyboard() -> void:
	if PInput.just_pressed("action_a"):
		_idle_t = 0.0
		_auto()
		return
	var opts := _options()
	if opts.is_empty():
		return
	var step := 0
	if PInput.just_pressed("move_right") or PInput.just_pressed("move_down"):
		step = 1
	elif PInput.just_pressed("move_left") or PInput.just_pressed("move_up"):
		step = -1
	if step != 0:
		_idle_t = 0.0
		_kb = 0 if _kb < 0 else posmod(_kb + step, opts.size())
		Audio.play("click", 0.05, -12.0)
	if PInput.just_pressed("action_b") and _kb >= 0 and _kb < opts.size():
		_idle_t = 0.0
		if _phase == "bid":
			_make_call(opts[_kb])
		else:
			_play_card(opts[_kb])

func _input(event: InputEvent) -> void:
	if finished:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if Flow.pointer_over_hud():
		return
	_idle_t = 0.0
	var p := get_global_mouse_position()
	for k in range(_hits.size() - 1, -1, -1):
		var h: Dictionary = _hits[k]
		if not (h["rect"] as Rect2).has_point(p):
			continue
		match h["kind"]:
			"level": _set_level(h["value"])
			"auto": _auto()
			"new": _new_rubber_pressed()
			"call":
				if _phase == "bid" and _yours(_to_act()):
					_make_call(h["value"])
			"card":
				if _phase == "play" and _pause <= 0.0 and _sweep < 0.0 and _yours(_to_act()):
					_play_card(h["value"])
		return
	if _phase == "result":
		_continue()

func _set_level(lv: String) -> void:
	if lv == _level:
		return
	_level = lv
	Audio.play("select", 0.05, -6.0)
	Probe.event("difficulty", {"level": lv})

func _new_rubber_pressed() -> void:
	if finished:
		return
	Audio.play("open", 0.05, -4.0)
	Probe.event("new_rubber", {"deals": _deals})
	_new_rubber()

## ---- the playtest eye ---------------------------------------------------------------------
## The player is the "@" under your hand; whenever it is your turn the spot where your
## card or call goes is a "*". The smart bot pulses space, which is "auto", so a bot run
## plays whole rubbers through the same verb a person can use.

func _refresh_markers() -> void:
	for m in _markers:
		if is_instance_valid(m):
			m.queue_free()
	_markers.clear()
	if not Probe.enabled:
		return
	var seat := _to_act()
	if seat >= 0 and _yours(seat):
		var n := Node2D.new()
		add_child(n)
		n.position = SLOT[seat] if _phase == "play" else BOX + Vector2(80, 60)
		Probe.track(n, "*")
		_markers.append(n)

## ---- the screen -----------------------------------------------------------------------------

func _suit_col(s: int) -> Color:
	return Palette.col(["friend", "warn", "hazard", "player"][s])

func _draw() -> void:
	_hits.clear()
	var f: Font = ThemeDB.fallback_font
	var ink := Palette.col("ink")
	var dim := Color(ink.r, ink.g, ink.b, 0.55)
	var accent := Palette.col("accent")

	# the table felt: a soft glowing oval
	var felt := Palette.col("bg_alt")
	for k in 3:
		var r := 150.0 - k * 6.0
		_ellipse(MID + Vector2(0, -6), Vector2(r * 1.25, r * 0.62), Color(felt.r, felt.g, felt.b, 0.35 + k * 0.2))
	_ellipse_line(MID + Vector2(0, -6), Vector2(188, 93), Color(accent.r, accent.g, accent.b, 0.35), 1.5)

	_draw_left(f, ink, dim, accent)
	_draw_right(f, ink, dim, accent)
	_draw_north(f, dim)
	_draw_side(f, WEST, Vector2(8, 150), dim)
	_draw_side(f, EAST, Vector2(532, 150), dim)
	match _phase:
		"bid":
			_draw_auction(f, AUC, 9)
			_draw_box(f)
		"play", "over":
			_draw_trick(f)
		"result":
			_draw_result(f)
	_draw_south(f)

func _draw_left(f: Font, ink: Color, dim: Color, accent: Color) -> void:
	var y := 44.0
	_txt(f, 10, y, "BRIDGE", 16, accent)
	y += 16
	_txt(f, 10, y, "rubber, deal %d" % _deals, 10, dim)
	y += 18
	if not _con.is_empty():
		_txt(f, 10, y, "contract", 10, dim)
		y += 16
		_draw_call(f, Vector2(10, y), R.make_bid(_con["level"], _con["strain"]), 16)
		var extra: String = ["", " x", " xx"][_con["dbl"]] + "  by " + R.SEAT_NAMES[_con["declarer"]]
		_txt(f, 44, y, extra, 11, ink)
		y += 18
		if _table != null:
			var ds: int = int(_con["declarer"]) % 2
			var need := 6 + int(_con["level"])
			_txt(f, 10, y, "we %d   they %d" % [_table.won[0], _table.won[1]], 12, ink)
			y += 14
			var goal := "we need %d" % need if ds == 0 else "we need %d to beat it" % (14 - need)
			_txt(f, 10, y, goal, 10, dim)
	elif _phase == "bid":
		_txt(f, 10, y, "dealer: " + R.SEAT_NAMES[_dealer], 11, ink)
		y += 14
		_txt(f, 10, y, "your points: %d" % R.hcp(_hands[SOUTH]), 11, ink)
	# difficulty
	_txt(f, 10, 262, "opponents", 10, dim)
	for i in LEVEL_ORDER.size():
		var lv: String = LEVEL_ORDER[i]
		var rect := Rect2(8, 268 + i * 26, 88, 22)
		_button(f, rect, lv, lv == _level)
		_hits.append({"rect": rect, "kind": "level", "value": lv})

func _draw_right(f: Font, ink: Color, dim: Color, accent: Color) -> void:
	var x := 536.0
	var y := 56.0
	_txt(f, x + 40, y, "WE", 10, Palette.col("player"))
	_txt(f, x + 70, y, "THEY", 10, Palette.col("hazard"))
	y += 15
	var rows := [["games", _games], ["part", _part], ["above", _above]]
	for r in rows:
		_txt(f, x, y, r[0], 10, dim)
		_txt(f, x + 40, y, str(r[1][0]), 11, ink)
		_txt(f, x + 70, y, str(r[1][1]), 11, ink)
		y += 14
	draw_line(Vector2(x, y - 9), Vector2(x + 96, y - 9), Color(accent.r, accent.g, accent.b, 0.4), 1.0)
	_txt(f, x, y + 2, "total", 10, dim)
	_txt(f, x + 40, y + 2, str(_above[0] + _below[0]), 11, Palette.col("player"))
	_txt(f, x + 70, y + 2, str(_above[1] + _below[1]), 11, Palette.col("hazard"))
	y += 18
	var vul := "none"
	if _vul(0) and _vul(1):
		vul = "both"
	elif _vul(0):
		vul = "we are"
	elif _vul(1):
		vul = "they are"
	_txt(f, x, y, "vulnerable: " + vul, 9, Palette.col("warn") if vul != "none" else dim)
	var auto := Rect2(540, 268, 92, 22)
	var mine := _to_act() >= 0 and _yours(_to_act()) or _phase == "result"
	_button(f, auto, "next" if _phase == "result" else "auto", mine)
	_hits.append({"rect": auto, "kind": "auto", "value": 0})
	var nr := Rect2(540, 320, 92, 22)
	_button(f, nr, "new rubber", false)
	_hits.append({"rect": nr, "kind": "new", "value": 0})

func _button(f: Font, rect: Rect2, label: String, on: bool) -> void:
	var accent := Palette.col("accent")
	var fill := Palette.col("bg")
	if on:
		fill = accent.darkened(0.55)
	draw_rect(rect, fill)
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 1.0 if on else 0.55), false, 1.5)
	draw_string(f, rect.position + Vector2(0, rect.size.y * 0.5 + 4), label, HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x, 11, Palette.col("ink") if on else Color(Palette.col("ink"), 0.7))

## -- hands

func _face_up(seat: int) -> bool:
	if seat == SOUTH or _phase == "result" or _phase == "over":
		return true
	if _phase != "play" or _table == null:
		return false
	if seat == NORTH and _we_declare():
		return true
	return _table.exposed and seat == _table.dummy

func _cards_of(seat: int) -> Array:
	if _table != null and _phase != "result":
		return _table.hands[seat]
	return _hands[seat]

func _draw_south(f: Font) -> void:
	var cards: Array = _cards_of(SOUTH)
	var shown := mini(cards.size(), int(_deal_t * 40.0)) if _phase == "bid" and _auc.is_empty() else cards.size()
	_draw_row(f, SOUTH, cards, shown, S_TOP, S_CARD, 32.0, 440.0)

func _draw_north(f: Font, dim: Color) -> void:
	var cards: Array = _cards_of(NORTH)
	var up := _face_up(NORTH)
	var label := "north - partner"
	if not _con.is_empty() and _phase == "play":
		if int(_con["declarer"]) == NORTH:
			label = "north - declarer (you play it)"
		elif _table.dummy == NORTH:
			label = "north - dummy (you play it)"
	_txt_c(f, 320, 97, label, 10, _seat_col(NORTH, dim))
	if up:
		_draw_row(f, NORTH, cards, cards.size(), N_TOP, N_CARD, 24.0, 330.0)
	else:
		var n := cards.size()
		var step := 14.0
		var w := step * (n - 1) + 26.0
		for i in n:
			_draw_back(Rect2(320 - w * 0.5 + i * step, N_TOP + 6, 26, 36))

func _seat_col(seat: int, dim: Color) -> Color:
	if _to_act() == seat and _phase != "result":
		var c := Palette.col("warn")
		return Color(c.r, c.g, c.b, 0.7 + 0.3 * sin(_t * 5.0))
	if _phase == "bid" and seat == _dealer:
		return Palette.col("ink")
	return dim

func _draw_row(f: Font, seat: int, cards: Array, shown: int, top: float, size: Vector2, max_step: float, max_w: float) -> void:
	var n := cards.size()
	if n == 0:
		return
	var step := max_step
	if n > 1:
		step = minf(max_step, (max_w - size.x) / float(n - 1))
	var w := step * (n - 1) + size.x
	var x0 := 320.0 - w * 0.5
	var mine := _phase == "play" and _yours(seat) and _to_act() == seat and _pause <= 0.0 and _sweep < 0.0
	var legal: Array = []
	if mine:
		legal = R.legal_cards(cards, _table.trick)
	var opts := _options() if mine else []
	var sel := -1
	if mine and _kb >= 0 and _kb < opts.size():
		sel = opts[_kb]
	for i in shown:
		var c: int = cards[i]
		var ok := mine and legal.has(c)
		var lift := 0.0
		if ok:
			lift = -6.0
		if c == sel:
			lift = -14.0
		var rect := Rect2(x0 + i * step, top + lift, size.x, size.y)
		_draw_face(f, rect, c, ok, mine and not ok, c == sel)
		if ok:
			var hit := Rect2(rect.position, Vector2(step if i < n - 1 else size.x, size.y + 10))
			_hits.append({"rect": hit, "kind": "card", "value": c})

func _draw_side(f: Font, seat: int, at: Vector2, dim: Color) -> void:
	var name: String = R.SEAT_NAMES[seat]
	var tag := ""
	if _phase == "bid" and seat == _dealer:
		tag = " (dealer)"
	elif not _con.is_empty() and _phase == "play":
		if int(_con["declarer"]) == seat:
			tag = " - declarer"
		elif _table.dummy == seat and _table.exposed:
			tag = " - dummy"
	_txt(f, at.x + 2, at.y, name + tag, 11, _seat_col(seat, dim))
	var cards: Array = _cards_of(seat)
	if _face_up(seat):
		var y := at.y + 16
		for s in [3, 2, 0, 1]:
			var cs := R.cards_in(cards, s)
			_suit(Vector2(at.x + 8, y - 4), s, 5.0, _suit_col(s))
			var txt := ""
			for c in cs:
				txt += R.card_text(c) + " "
			_txt(f, at.x + 18, y, txt if txt != "" else "-", 11, Palette.col("ink"))
			y += 16
	else:
		var n := cards.size()
		for i in mini(n, 6):
			_draw_back(Rect2(at.x + 18 + i * 7, at.y + 10, 26, 36))
		_txt(f, at.x + 18 + mini(n, 6) * 7 + 24, at.y + 34, "%d" % n, 11, dim)

func _draw_back(rect: Rect2) -> void:
	var accent := Palette.col("accent")
	draw_rect(rect, Palette.col("bg_alt"))
	draw_rect(rect.grow(-3), Color(accent.r, accent.g, accent.b, 0.18))
	var c := rect.get_center()
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 0), c + Vector2(0, 7), c + Vector2(-5, 0)]),
		Color(accent.r, accent.g, accent.b, 0.55))
	draw_rect(rect, accent, false, 1.2)

func _draw_face(f: Font, rect: Rect2, c: int, lit: bool, dull: bool, chosen: bool) -> void:
	var s := R.suit_of(c)
	var col := _suit_col(s)
	var base := Palette.col("bg_alt").lightened(0.12)
	if lit:
		draw_rect(rect.grow(2.5), Color(col.r, col.g, col.b, 0.25))
	if chosen:
		draw_rect(rect.grow(4.0), Color(col.r, col.g, col.b, 0.45))
	draw_rect(rect, base)
	draw_rect(rect, Color(col.r, col.g, col.b, 0.95 if lit else 0.55), false, 1.5)
	var fs := 14 if rect.size.x >= 40 else 12
	draw_string(f, rect.position + Vector2(3, fs + 1), R.card_text(c), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	_suit(rect.position + Vector2(9, fs + 10), s, 4.5, col)
	_suit(rect.position + Vector2(rect.size.x * 0.6, rect.size.y * 0.66), s, rect.size.x * 0.2, Color(col.r, col.g, col.b, 0.85))
	if dull:
		draw_rect(rect, Color(0, 0, 0, 0.45))

## -- the middle of the table

func _draw_trick(f: Font) -> void:
	var dim := Color(Palette.col("ink"), 0.25)
	var seat := _to_act()
	for s in 4:
		var p: Vector2 = SLOT[s]
		var r := Rect2(p - T_CARD * 0.5, T_CARD)
		draw_rect(r, Color(dim.r, dim.g, dim.b, 0.08))
		if s == seat and _pause <= 0.0 and _sweep < 0.0 and _phase == "play":
			var w := Palette.col("warn")
			draw_rect(r.grow(2.0), Color(w.r, w.g, w.b, 0.5 + 0.4 * sin(_t * 6.0)), false, 2.0)
		draw_string(f, p + Vector2(-T_CARD.x * 0.5, 5), R.SEAT_SHORT[s], HORIZONTAL_ALIGNMENT_CENTER, T_CARD.x, 12, dim)
	var sweep_k := 0.0
	if _sweep >= 0.0:
		sweep_k = clampf(_sweep / (SWEEP_TIME * minf(1.0, _tempo * 2.0)), 0.0, 1.0)
	for e in _shown:
		var s: int = e[0]
		var k := clampf(float(e[2]) / FLY_TIME, 0.0, 1.0)
		var from := _hand_anchor(s)
		var p: Vector2 = from.lerp(SLOT[s], 1.0 - pow(1.0 - k, 3.0))
		if sweep_k > 0.0:
			p = p.lerp(_hand_anchor(_sweep_to), sweep_k)
		var r := Rect2(p - T_CARD * 0.5, T_CARD)
		var winning := _pause > 0.0 and s == _sweep_to
		if winning:
			var g := Palette.col("prize")
			draw_rect(r.grow(3.0), Color(g.r, g.g, g.b, 0.5))
		_draw_face(f, r, e[1], winning, false, false)

func _hand_anchor(seat: int) -> Vector2:
	match seat:
		SOUTH: return Vector2(320, 320)
		NORTH: return Vector2(320, 60)
		WEST: return Vector2(60, 180)
	return Vector2(580, 180)

func _draw_result(f: Font) -> void:
	var rect := Rect2(150, 104, 340, 150)
	var accent := Palette.col("accent")
	draw_rect(rect, Color(Palette.col("bg").r, Palette.col("bg").g, Palette.col("bg").b, 0.92))
	draw_rect(rect, accent, false, 2.0)
	var lines: Array = _result.get("lines", [])
	var y := rect.position.y + 24
	for i in lines.size():
		var col := Palette.col("ink")
		if i == 0:
			col = Palette.col("prize") if _result.get("made", false) == (_we_declare()) else Palette.col("hazard")
			if _result.get("passed", false):
				col = Palette.col("warn")
		var t: String = lines[i]
		if t.begins_with("GAME") or t.begins_with("RUBBER"):
			col = Palette.col("warn")
		_txt_c(f, 320, y, t, 15 if i == 0 else 12, col)
		y += 20 if i == 0 else 16
	if not _result.get("passed", false):
		_txt_c(f, 320, y + 4, "we +%d    they +%d" % [_result.get("we", 0), _result.get("they", 0)], 12, Palette.col("ink"))
	var more := "tap for the final score" if _result.get("over", false) else "tap for the next deal"
	_txt_c(f, 320, rect.end.y - 10, more, 10, Color(Palette.col("ink"), 0.6))

func _draw_auction(f: Font, at: Vector2, rows: int) -> void:
	var ink := Palette.col("ink")
	var dim := Color(ink.r, ink.g, ink.b, 0.55)
	var order := [WEST, NORTH, EAST, SOUTH]
	for k in 4:
		var s: int = order[k]
		draw_string(f, at + Vector2(k * AUC_COL, 0), R.SEAT_SHORT[s], HORIZONTAL_ALIGNMENT_CENTER, AUC_COL, 11,
			_seat_col(s, dim))
	draw_line(at + Vector2(0, 5), at + Vector2(4 * AUC_COL, 5), Color(ink.r, ink.g, ink.b, 0.25), 1.0)
	var col0: int = order.find(_dealer)
	var total := col0 + _auc.size()
	var first_row := maxi(0, (total + 3) / 4 - rows)
	for i in _auc.size():
		var slot := col0 + i
		var row := slot / 4
		if row < first_row:
			continue
		var col := slot % 4
		var p := at + Vector2(col * AUC_COL + 8, 20 + (row - first_row) * 15)
		_draw_call(f, p, _auc[i], 12)
	# where the next call goes
	if _phase == "bid":
		var slot := col0 + _auc.size()
		var row := slot / 4 - first_row
		if row < rows:
			var w := Palette.col("warn")
			var p := at + Vector2((slot % 4) * AUC_COL + 8, 20 + row * 15)
			draw_string(f, p, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(w.r, w.g, w.b, 0.6 + 0.4 * sin(_t * 6.0)))

func _draw_box(f: Font) -> void:
	var seat := _to_act()
	var mine := seat == SOUTH
	var legal := R.legal_calls(_auc, _dealer)
	var opts := _options()
	var sel := -1
	if mine and _kb >= 0 and _kb < opts.size():
		sel = opts[_kb]
	var ink := Palette.col("ink")
	if not mine:
		_txt_c(f, BOX.x + CELL.x * 2.5, BOX.y + 70, "%s to call..." % R.SEAT_NAMES[seat], 12, Color(ink.r, ink.g, ink.b, 0.7))
		return
	_txt_c(f, BOX.x + CELL.x * 2.5, BOX.y - 6, "your call", 11, Palette.col("warn"))
	for lv in range(1, 8):
		for st in 5:
			var b := R.make_bid(lv, st)
			var rect := Rect2(BOX + Vector2(st * CELL.x, (lv - 1) * CELL.y), CELL - Vector2(2, 2))
			var ok := legal.has(b)
			_cell(f, rect, b, ok, b == sel)
			if ok:
				_hits.append({"rect": rect, "kind": "call", "value": b})
	var y := BOX.y + 7 * CELL.y + 3
	var specials := [[R.PASS, Rect2(BOX.x, y, CELL.x * 3 - 2, 20)],
		[R.DBL, Rect2(BOX.x + CELL.x * 3, y, CELL.x - 2, 20)],
		[R.RDBL, Rect2(BOX.x + CELL.x * 4, y, CELL.x - 2, 20)]]
	for sp in specials:
		var ok := legal.has(sp[0])
		_cell(f, sp[1], sp[0], ok, sp[0] == sel)
		if ok:
			_hits.append({"rect": sp[1], "kind": "call", "value": sp[0]})

func _cell(f: Font, rect: Rect2, call: int, ok: bool, chosen: bool) -> void:
	var accent := Palette.col("accent")
	var fill := Palette.col("bg_alt") if ok else Palette.col("bg")
	draw_rect(rect, fill)
	if chosen:
		draw_rect(rect.grow(2.0), Palette.col("warn"), false, 2.0)
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.7 if ok else 0.15), false, 1.0)
	var a := 1.0 if ok else 0.22
	var w := _call_width(call, 11)
	_draw_call(f, rect.position + Vector2((rect.size.x - w) * 0.5, rect.size.y * 0.5 + 4), call, 11, a)

func _call_width(call: int, size: int) -> float:
	if not R.is_bid(call):
		return ThemeDB.fallback_font.get_string_size(R.call_text(call), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if R.bid_strain(call) == R.NT:
		return ThemeDB.fallback_font.get_string_size(str(R.bid_level(call)) + "NT", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return size * 0.6 + size * 0.9

## A call as text with a drawn suit symbol: 4 then a spade.
func _draw_call(f: Font, at: Vector2, call: int, size: int, alpha: float = 1.0) -> void:
	var ink := Palette.col("ink")
	if not R.is_bid(call):
		var col := Color(ink.r, ink.g, ink.b, 0.6 * alpha)
		if call == R.DBL:
			col = Color(Palette.col("hazard"), alpha)
		elif call == R.RDBL:
			col = Color(Palette.col("prize"), alpha)
		draw_string(f, at, R.call_text(call), HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		return
	var st := R.bid_strain(call)
	var lv := str(R.bid_level(call))
	draw_string(f, at, lv, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(ink.r, ink.g, ink.b, alpha))
	var x := f.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 1
	if st == R.NT:
		draw_string(f, at + Vector2(x, 0), "NT", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(Palette.col("accent"), alpha))
	else:
		var sc := _suit_col(st)
		_suit(at + Vector2(x + size * 0.45, -size * 0.36), st, size * 0.42, Color(sc.r, sc.g, sc.b, alpha))

## Suits are drawn, not typed: the fallback font has no suit glyphs on every platform.
func _suit(c: Vector2, s: int, r: float, col: Color) -> void:
	match s:
		R.DIAMONDS:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.72, 0),
				c + Vector2(0, r), c + Vector2(-r * 0.72, 0)]), col)
		R.HEARTS:
			draw_circle(c + Vector2(-r * 0.46, -r * 0.28), r * 0.52, col)
			draw_circle(c + Vector2(r * 0.46, -r * 0.28), r * 0.52, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.95, -r * 0.12),
				c + Vector2(r * 0.95, -r * 0.12), c + Vector2(0, r * 0.95)]), col)
		R.SPADES:
			draw_circle(c + Vector2(-r * 0.46, r * 0.18), r * 0.5, col)
			draw_circle(c + Vector2(r * 0.46, r * 0.18), r * 0.5, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.93, r * 0.05),
				c + Vector2(r * 0.93, r * 0.05), c + Vector2(0, -r * 0.98)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.2),
				c + Vector2(-r * 0.38, r), c + Vector2(r * 0.38, r)]), col)
		_:
			draw_circle(c + Vector2(0, -r * 0.45), r * 0.4, col)
			draw_circle(c + Vector2(-r * 0.45, r * 0.12), r * 0.4, col)
			draw_circle(c + Vector2(r * 0.45, r * 0.12), r * 0.4, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0),
				c + Vector2(-r * 0.35, r), c + Vector2(r * 0.35, r)]), col)

func _ellipse(c: Vector2, rad: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		pts.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
	draw_colored_polygon(pts, col)

func _ellipse_line(c: Vector2, rad: Vector2, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		pts.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
	draw_polyline(pts, col, w, true)

func _txt(f: Font, x: float, y: float, msg: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(x, y), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _txt_c(f: Font, x: float, y: float, msg: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(x - 200, y), msg, HORIZONTAL_ALIGNMENT_CENTER, 400, size, col)
