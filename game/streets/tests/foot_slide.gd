extends SceneTree
## Do the walkers' feet slide? A walking figure looks real only if a foot on the ground stays
## put while the body goes over it; when the walk clip plays at another pace than the walker
## moves, the planted foot skates along the pavement (forward if the walker goes faster than
## the clip, backward if slower) -- the commonest tell of a puppet.
## The real walkers of a town (_walkers, as built: their height, their proportions on the
## skeleton, the clip's speed set from their pace), followed for SECS (default 8) seconds: each
## foot bone in the world, "planted" while it is within 3 cm of the lowest it gets, and how fast
## it moves over the ground then. Per walker: the character, height, pace, the clip's speed
## scale, the planted foot's slide (cm/s, the sign: + along the way it walks) and per step (cm).
## Good: under ~3 cm a step (hard to see); 10 cm and up reads as skating.
##   LEVEL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/foot_slide.gd
var g: Node
func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(3.0).timeout
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 8.0
	# per walker: {w, sk, feet: [bone, bone], last: [Vector3, Vector3], low: [y, y], rec: [[speeds], [speeds]], planted_t}
	var track: Array = []
	for w: Dictionary in g._walkers:
		var a = w.get("actor")
		if a == null or not a.visible or a.model == null or a.anim == null:
			continue
		var sks: Array = a.model.find_children("*", "Skeleton3D", true, false)
		if sks.is_empty():
			continue
		var sk: Skeleton3D = sks[0]
		# (the kit's figures name them Foot.L; the Universal Base Characters foot_l)
		var hip := maxi(sk.find_bone("UpperLeg.L"), sk.find_bone("thigh_l"))
		var fl := maxi(sk.find_bone("Foot.L"), sk.find_bone("foot_l"))
		var fr := maxi(sk.find_bone("Foot.R"), sk.find_bone("foot_r"))
		if fl < 0 or fr < 0:
			continue
		track.append({"w": w, "a": a, "sk": sk, "feet": [fl, fr], "last": [Vector3.INF, Vector3.INF],
			"ys": [[], []], "pts": [[], []], "loc": [[], []], "hip": hip, "hips": [], "dirs": [], "steps": 0, "was": [false, false]})
	print("walkers followed: %d" % track.size())
	var dt := 1.0 / 60.0
	var frames := int(secs * 60.0)
	for f in range(frames):
		await process_frame
		for t: Dictionary in track:
			var a: Node3D = t["a"]
			var sk: Skeleton3D = t["sk"]
			for k in [0, 1]:
				var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(t["feet"][k]).origin
				(t["ys"][k] as Array).append(p.y - a.global_position.y)
				(t["pts"][k] as Array).append(p)
				(t["loc"][k] as Array).append(p - a.global_position)
			(t["hips"] as Array).append((sk.global_transform * sk.get_bone_global_pose(t["hip"]).origin).y - a.global_position.y)
			var fw := -a.global_transform.basis.z   # (the figure faces -z or +z: the sign is taken from its motion below)
			(t["dirs"] as Array).append(a.global_position)
	# planted: within 3 cm of the lowest that foot got; its speed over the ground then, along
	# the way the walker went (from the actor's own motion) and across it
	var rows: Array = []
	for t: Dictionary in track:
		var pos: Array = t["dirs"]
		var travel: Vector3 = pos[pos.size() - 1] - pos[0]
		var dist := Vector2(travel.x, travel.z).length()
		if dist < 2.0:
			continue   # (stood at a crossing, or idling: nothing to see)
		var along := Vector2(travel.x, travel.z).normalized()
		var w: Dictionary = t["w"]
		var a = t["a"]
		var speed := dist / secs
		if absf(speed - float(w.get("speed", speed))) > 0.15:
			continue   # (stopped a while, or moved on elsewhere: not one steady walk)
		# on the ground = while the foot moves back past the body (a planted foot does, at the
		# clip's own ground speed; a swinging one comes forward, faster). By height ("within
		# 3 cm of its lowest") took in much of the swing for the Universal Base Characters,
		# whose ankle bone hardly lifts, and read their whole pace as slide.
		var ul: Array = []   # the foot's speed back past the body, while on the ground
		var stance := 0
		var steps := 0
		for k in [0, 1]:
			var loc: Array = t["loc"][k]
			var was := false
			for i in range(1, loc.size()):
				var lv: Vector3 = (loc[i] - loc[i - 1]) / dt
				var back := -Vector2(lv.x, lv.z).dot(along)
				var on := back > 0.0
				if on and not was:
					steps += 1
				was = on
				if on:
					ul.append(back)
					stance += 1
		if ul.is_empty() or steps == 0:
			continue
		ul.sort()
		var u: float = ul[ul.size() / 2]
		var med := speed - u   # the planted foot over the ground: + forward (the clip too slow)
		var per_step := absf(med) * (stance * dt) / steps
		var hips: Array = t["hips"]
		var hip_h := 0.0
		for h in hips:
			hip_h += float(h)
		hip_h /= hips.size()
		var nat := u / maxf(float(a.anim.speed_scale), 0.01)   # the clip's ground speed at x1, this figure
		rows.append([absf(per_step), "%-15s %.2f m tall  pace %.2f m/s (moved %.2f)  clip x%.2f  planted foot %+5.1f cm/s, %4.1f cm a step;  hip %.2f m, clip's own pace %.2f m/s = %.2f hips/s" % [
			String(a.character), float(a.scale.y) if a.scale.y != 1.0 else float(w.get("tall", 0.0)),
			float(w.get("speed", 0.0)), speed, float(a.anim.speed_scale), med * 100.0, per_step * 100.0, hip_h, nat, nat / maxf(hip_h, 0.01)]])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	var tot := 0.0
	for r: Array in rows:
		print("  " + r[1])
		tot += float(r[0])
	if rows.size() > 0:
		var n10 := rows.filter(func(r): return float(r[0]) >= 0.10).size()
		print("FOOT SLIDE: %d walkers, mean %.1f cm a step, %d of them 10 cm or more" % [rows.size(), tot / rows.size() * 100.0, n10])
	quit()
