class_name SimChecks
## Automatic findings. These catch the failure modes an AI actually produces:
## a game where nothing spawns, an unwinnable game, an unloseable game, actors off-screen.

static func run(bot_policy: String, duration: float, ended: bool, won: bool, score: int) -> Array:
	var out: Array = []
	var c := Probe.counts()

	if c.is_empty():
		out.append(["FAIL", "no events recorded -- the game never called Probe.event(). It may not be running at all."])

	if score == 0 and c.get("prize_taken", 0) == 0:
		out.append(["WARN", "score never moved. Nothing rewarding happened in %.0fs." % duration])

	if bot_policy == "idle":
		if ended and not won:
			out.append(["PASS", "the game can be lost (idle bot died) -- there is a real fail state"])
		else:
			out.append(["FAIL", "idle bot survived %.0fs without dying. The game has no teeth." % duration])

	if bot_policy == "smart":
		if ended and not won and duration < 6.0:
			out.append(["FAIL", "a competent bot died in %.1fs. Too hard / unfair." % duration])
		elif not ended:
			out.append(["PASS", "a competent bot survived the full run"])

	var spawned := int(c.get("hazard_spawn", 0))
	if spawned == 0 and c.get("enemy_spawn", 0) == 0:
		out.append(["WARN", "nothing hostile ever spawned -- check the spawner"])

	if not Probe.player_seen:
		out.append(["FAIL", "no node was tracked as the player ('@'). Call Probe.track(player, \"@\")."])

	if out.is_empty():
		out.append(["PASS", "no problems detected"])
	return out
