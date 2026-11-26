extends SceneTree
## Autodrive and someone standing in its lane who is not a walker or a crosser (g.add_person:
## a scenario's fare, a wedding's guest; the same path as the street's chatters, waiters,
## sitters, crowds). The scenarios' wedding run hit someone at (249, 236) on Tel Aviv's
## Givat HaTachmoshet bridge over the Ayalon at 28-32 km/h on every pass (24 Nov 2026):
## autodrive braked only for walkers and crossers. Three go-tos from FROM to TO over AT:
## (0) a person standing on the bridge's lane at AT -- autodrive must stop short; (1) the same
## person on the ground under the bridge -- not in the way: it must not brake (people were
## solid and braked for by x and z alone); (2) nobody. Prints, every 0.5 s within 30 m of AT,
## the car and everyone within 6 m of AT; every person the car's body touches is a HIT.
##   LEVEL=7 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/stop_people.gd
## Good: 0 hits, nobody standing on the asphalt.
var g: Node
const ROAD := "גבעת התחמושת"

func _initialize() -> void:
	_run()

func _vec(env: String, def: Vector2) -> Vector2:
	var s := OS.get_environment(env)
	if s == "":
		return def
	var p := s.split(",")
	return Vector2(float(p[0]), float(p[1]))

func _everyone() -> Array:
	var out: Array = []
	var lists := {"walker": g._walkers, "crosser": g._crossers, "chatter": g._chatters, "sitter": g._sitters,
		"waiter": g._waiters, "keeper": g._keepers, "bather": g._bathers, "boarder": g._boarders}
	for who: String in lists:
		for w: Dictionary in lists[who]:
			var a = w.get("actor")
			if a == null or not is_instance_valid(a) or not (a as Node3D).visible:
				continue
			var p3: Vector3 = (a as Node3D).global_position
			out.append([who + (":" + String(w.get("state", "")) if w.has("state") else ""), Vector2(p3.x, p3.z), p3.y])
	return out

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(0)
	var from := _vec("FROM", Vector2(220.0, 224.0))
	var to := _vec("TO", Vector2(286.0, 247.0))
	var at := _vec("AT", Vector2(249.0, 236.0))
	var head := _vec("HEAD", Vector2(0.94, 0.34))
	var trips := int(OS.get_environment("TRIPS")) if OS.get_environment("TRIPS") != "" else 3
	var hits := 0
	var on_road := 0
	var stood := false     # trip 0: stopped short of them
	var under_kmh := 0.0   # trip 1: its speed over them
	var person = null   # (an Actor3D, made by load(): naming the class here broke the compile)
	for trip in range(trips):
		if person != null:
			person.queue_free()
			person = null
		if trip < 2:
			person = load("res://shell/actor3d.gd").new()
			g.world.add_child(person)
			g._set_character(person, g.PEOPLE[3], 1.72)
			person.play("Idle", true, 1.0)
			g.add_person(person)
		g._set_auto(false)
		# (the stop is on a bridge over the Ayalon: landed by the ground's height the car went to
		# the street under it -- tried from the ground up until the road it lands on is ROAD)
		var landed := false
		for up in range(0, 16):
			g._pos = from
			g._y = float(g._h(from)) + float(up)
			g._land_on_road(from, 12.0, head)
			var hs: Dictionary = g._nearest_seg(g._pos, 3.0, true, true, g._y)
			if not hs.is_empty() and String(g._roads[hs["road"]]["name"]) == ROAD and g._fwd().dot(head) > 0.5:
				landed = true
				break
		if not landed:
			print("could not land on %s near %s" % [ROAD, from])
		await physics_frame
		g._set_dest(to, "stop test")
		g._set_auto(true)
		await physics_frame
		if person != null:
			# on the line the car will take (trip 0), or straight under it on the ground (trip 1)
			var spot := at
			var bd := INF
			for q: Vector2 in g._ap_pts:
				if q.distance_to(at) < bd:
					bd = q.distance_to(at)
					spot = q
			person.position = Vector3(spot.x, float(g._y) if trip == 0 else float(g._h(spot)), spot.y)
			print("trip %d: a person at (%.1f, %.1f) y %.1f, the bridge's road at y %.1f" % [trip, spot.x, spot.y, person.position.y, g._y])
		if trip == 0:
			var pl := ""
			for q: Vector2 in g._ap_pts:
				pl += " (%.0f,%.0f)" % [q.x, q.y]
			print("landed at (%.1f, %.1f) on %s heading %s; plan:%s" % [g._pos.x, g._pos.y, g._on_name, g._fwd(), pl.substr(0, 400)])
		var t := 0.0
		var next := 0.0
		var hit_cool := 0.0
		var closest := INF
		var spot2: Vector2 = Vector2(person.position.x, person.position.z) if person != null else at
		var min_kmh_near := INF
		while t < (15.0 if trip == 0 else 40.0) and g._pos.distance_to(to) > 8.0:
			await physics_frame
			var dt := 1.0 / Engine.physics_ticks_per_second
			t += dt
			hit_cool -= dt
			closest = minf(closest, g._pos.distance_to(at))
			if (g._pos as Vector2).distance_to(spot2) < 12.0:
				min_kmh_near = minf(min_kmh_near, absf(g._v) * 3.6)
			var near: bool = (g._pos as Vector2).distance_to(at) < 30.0
			var fw: Vector2 = g._fwd()
			var all_now: Array = _everyone()
			if person != null:
				all_now.append(["standing (add_person)", Vector2(person.position.x, person.position.z), person.position.y])
			for e: Array in all_now:
				if absf(float(e[2]) - float(g._y)) > 2.5:
					continue
				var p: Vector2 = e[1]
				var rel: Vector2 = p - g._pos
				if absf(rel.dot(fw)) < g.CAR_LEN * 0.5 + 0.2 and absf(rel.dot(Vector2(-fw.y, fw.x))) < g.CAR_WIDTH * 0.5 + 0.25 and absf(g._v) > 1.0 and hit_cool <= 0.0:
					hits += 1
					hit_cool = 2.0
					print("HIT trip %d t %.1f: %s at (%.1f, %.1f) y %.1f, the car %.0f km/h at y %.1f, held by %s" % [trip, t, e[0], p.x, p.y, float(e[2]), absf(g._v) * 3.6, float(g._y), g._ap_why])
			if near and t >= next:
				if t < 0.6 and trip == 0:
					for e: Array in _everyone():
						if (e[1] as Vector2).distance_to(at) < 8.0:
							pass
				next = t + 0.5
				var who: Array = []
				for e: Array in _everyone():
					var p: Vector2 = e[1]
					if p.distance_to(at) < 6.0:
						var hs: Dictionary = g._nearest_seg(p, 15.0, true, true)
						var edge: float = float(hs["edge"]) if not hs.is_empty() else 99.0
						if edge < 0.0:
							on_road += 1
						who.append("%s (%.1f, %.1f) y %.1f (the car's %.1f) %s" % [e[0], p.x, p.y, float(e[2]), float(g._y), ("%.1f m ON the asphalt" % -edge) if edge < 0.0 else ("%.1f m off" % edge)])
				print("  trip %d t %.1f car (%.1f, %.1f) %.0f km/h %s | %s" % [trip, t, g._pos.x, g._pos.y, absf(g._v) * 3.6, g._ap_why, "; ".join(who)])
		var gap: float = (g._pos as Vector2).distance_to(spot2)
		if trip == 0:
			stood = absf(g._v) < 0.5 and gap < 12.0 and (spot2 - g._pos).dot(g._fwd()) > 0.0
		if trip == 1:
			under_kmh = min_kmh_near
		print("trip %d: %.0f s, came within %.1f m of the spot, now %.1f m from the person, %.0f km/h; arrived %s" % [trip, t, closest, gap, absf(g._v) * 3.6, str(g._pos.distance_to(to) <= 8.0)])
	print("REGRESS stop_people: %s -- someone standing in autodrive's lane (Tel Aviv's Givat HaTachmoshet bridge): stopped short %s, %d hits; the same person under the bridge: over them at %.0f km/h at the slowest (good: stopped, 0 hits, over 25; the bug: hit at 28-32 km/h)" % [
		"PASS" if hits == 0 and stood and under_kmh > 25.0 else "FAIL", str(stood), hits, under_kmh])
	quit(0)
