extends RefCounted
## Hands while talking (moved out of streets.gd; `g` is the game).
## People standing and talking move their hands: now and then one forearm comes up from the
## elbow and the hand moves as they make a point, then goes down again; sometimes both. The
## figures have no clip for it (Idle stands with arms hanging), so this bends the arm bones
## on top of the pose the animation gave, every frame. (tests/people_talk.gd)

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

class Talk extends SkeletonModifier3D:
	var arms := []      ## [upper arm, forearm] bone indices, left then right
	var t := 0.0
	var rate := 1.0     ## how lively: 0.7 slow, 1.3 quick
	## the axis, in each arm bone's own frame, that brings the hand forward and up, left then
	## right (measured: about the bone's x alone the hand also swung out to the side, and about
	## -x behind the back; the same for the upper arm and the forearm)
	var axes := [Vector3(1, 0, -1).normalized(), Vector3(1, 0, 1).normalized()]

	## how far each arm is up, 0..1, at time t: a gesture of a second or two every few
	## seconds, one arm (now this one, now the other), sometimes both
	func _up(side: int) -> float:
		var cyc := t * 0.3 * rate + float(side) * 0.37
		var k := floori(cyc)
		var f := cyc - float(k)
		var h := posmod(k * 7919 + side * 31 + int(rate * 1000.0), 10)
		var on := h < (6 if side == 0 else 4)   # (now and then neither: listening)
		if not on:
			return 0.0
		return smoothstep(0.0, 0.18, f) * (1.0 - smoothstep(0.55, 0.75, f))

	func _process_modification_with_delta(delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		t += delta
		for side in range(arms.size()):
			var e := _up(side)
			if e <= 0.001:
				continue
			var ua: int = arms[side][0]
			var fa: int = arms[side][1]
			# the hand moving as the point is made: a small beat on top
			var beat := sin(t * (5.0 + float(side)) * rate) * 0.18 + sin(t * 2.3 * rate + float(side)) * 0.1
			var r1 := Quaternion(axes[side], e * 0.35)
			var r2 := Quaternion(axes[side], e * (1.15 + beat))
			sk.set_bone_pose_rotation(ua, sk.get_bone_pose_rotation(ua) * r1)
			sk.set_bone_pose_rotation(fa, sk.get_bone_pose_rotation(fa) * r2)

## talking hands for someone standing in a group (Talk)
func _talker(a: Actor3D, seed: int) -> void:
	if a == null or a.model == null:
		return
	var sks := a.model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	if sk.find_bone("UpperArm.L") < 0 and a.anim != null:
		# people.gd's figures have the library's own talking idle: no bending needed
		a.anim.remove_animation_library("")
		a.anim.add_animation_library("", g._people_maker()._lib("talk"))
		return
	var tk := Talk.new()
	for sd: String in ["L", "R"]:
		var u := sk.find_bone("UpperArm." + sd)
		var f := sk.find_bone("LowerArm." + sd)
		if u >= 0 and f >= 0:
			tk.arms.append([u, f])
	if tk.arms.is_empty():
		return
	tk.rate = 0.75 + float(posmod(seed, 50)) / 100.0
	tk.t = float(posmod(seed * 13, 1000)) / 37.0
	sk.add_child(tk)
