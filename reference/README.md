# reference/

Frozen copies of games worth keeping as examples. **Nothing in here is playable** — the
menu only scans `res://game/`, so these are read-only reference material for the next game.

Keep this folder small. One good example beats five mediocre ones.

## count/

A copy of `game/count/` at the point where it first played well. It is the reference
implementation of the `GameMode` contract now that the kit's starter games (`dodge`,
`jump`, `blast`) have been deleted. Worth re-reading before writing a new game:

- **Round/reveal state machine** — `_new_round()` builds a round, `_reveal()` tears it
  down and holds the answer on screen for a beat before the next one.
- **Two input paths for one verb** — the mouse is the real way to play, but the game is
  also playable with `PInput.dir()` steering a paw. That second path is what lets the
  headless bots play it; a mouse-only game cannot be self-playtested.
- **Bot-friendly layout** — answers are spaced more than 90px apart because the `smart`
  bot flees anything tagged `"x"` within 90px. Pack them tighter and the bot gets stuck
  oscillating between two wrong answers instead of walking to the right one.
- **Probe tagging as game design** — the correct answer is tracked as `"*"` (prize) and
  the wrong ones as `"x"` (hazard), so `smart` plays the quiz correctly with no bot
  changes at all.

### Sound: the shell default is loud

`SaveData.data["volume_sfx"]` ships at **0.8**, which is a lot for any game that makes a
noise every few seconds. `count` drops it to **0.28** in `start()` and puts it back in
`_exit_tree()`:

```gdscript
const SFX_VOLUME := 0.28

func start(_config: Dictionary) -> void:
    _sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
    SaveData.data["volume_sfx"] = SFX_VOLUME

func _exit_tree() -> void:
    SaveData.data["volume_sfx"] = _sfx_was
```

In memory only — `SaveData.save_file()` is never called, so the settings file on disk is
untouched and the other games are unaffected. **Copy this into any new game**, or raise
the argument the other way and lower the shell default in `save_data.gd` once for
everything.

`Audio.play()` also takes a per-call `volume_db` offset if one specific sound is the
problem rather than all of them. Note that `lose_life()` plays `"hurt"` from inside the
shell at 0 dB, so a per-call offset cannot reach it — the global knob above can.
