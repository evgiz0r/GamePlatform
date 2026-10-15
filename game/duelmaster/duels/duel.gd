extends Node2D
## One duel. The frame builds it from a seed, so both players get exactly the same setup
## (same target, same speeds), runs one turn, and reads back one number: the error, where
## lower is better. That "seed in, number out" shape is also what online play will send.
##
## A duel overrides _build(), press(), release() (if it holds), step() and describe().

signal done(err: float)

const MISS := 1.0e9               ## "never acted" or "fell off" -- loses to any real try

var title := ""
var hint := ""
var tie := 1.0                    ## two results this close are a draw
var limit := 8.0                  ## seconds before the turn counts as a miss
var role := "player"              ## the colour of whoever is playing this turn
var rng := RandomNumberGenerator.new()
var t := 0.0                      ## seconds since the turn started
var over := false                 ## the player has acted (animation may still be running)
var _reported := false

func setup(seed: int, who_role: String) -> void:
	rng.seed = seed
	role = who_role
	_build()

## Called by the frame every frame of the turn, including after the player has acted so
## falling marbles and sliding pucks finish their motion.
func advance(delta: float) -> void:
	if not over:
		t += delta
		if t >= limit:
			over = true
			report(MISS)
	step(delta)
	queue_redraw()

func report(err: float) -> void:
	if _reported:
		return
	_reported = true
	over = true
	done.emit(err)

func describe(err: float) -> String:
	return "missed" if err >= MISS else "%.0f px off" % err

## ---- override these ----------------------------------------------------------

func _build() -> void:
	pass

func press() -> void:
	pass

func release() -> void:
	pass

func step(_delta: float) -> void:
	pass

## ---- shared drawing ----------------------------------------------------------

func label(cx: float, y: float, msg: String, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(cx - 200, y), msg,
		HORIZONTAL_ALIGNMENT_CENTER, 400, size, col)

func time_bar() -> void:
	var frac := clampf(1.0 - t / limit, 0.0, 1.0)
	draw_rect(Rect2(120, 336, 400, 5), Palette.col("bg_alt"))
	var r := "friend" if frac > 0.5 else ("warn" if frac > 0.25 else "hazard")
	draw_rect(Rect2(120, 336, 400 * frac, 5), Palette.col(r))
