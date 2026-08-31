extends Node
## Global signal bus. Anything in game/ can emit or listen without hard references.

signal score_changed(score: int)
signal lives_changed(lives: int)
signal game_over(won: bool, score: int)
signal request_pause()
signal juice_requested(kind: String, strength: float)
signal palette_changed()
