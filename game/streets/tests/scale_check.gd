extends SceneTree
## How big things are, as the game builds them, beside how big they are in life: the cars
## (the player's, traffic's by kind, the parked ones), the bus, motorbikes and scooters, the
## people, the street's widths, kerbs and pavements, and the cameras' heights and fields of
## view (a wide field of view makes near things loom and the rest look small and far, which
## reads as "the scale is off" as surely as a wrong size). Prints a table: what, the game's
## size, life's range, and OFF where the game falls outside it. Level 1 (Givatayim).
## Good: nothing OFF that is not explained in DEV.md.
var g: Node

func _initialize() -> void:
	_run()

## the box round everything drawn under n, in world metres
func _box(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var ab := m.global_transform * m.get_aabb()
		if first:
			out = ab
			first = false
		else:
			out = out.merge(ab)
	return out

func _row(what: String, got: float, lo: float, hi: float, unit := "m") -> void:
	var ok := got >= lo and got <= hi
	print("%-44s %7.2f %s   life %5.2f-%5.2f   %s" % [what, got, unit, lo, hi, "" if ok else "OFF"])

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	print("---- vehicles (length, width, height)")
	var car := _box(g._sedan_node)   # (the body: the car node also holds its headlight beams)
	_row("the player's car: length", maxf(car.size.x, car.size.z), 4.0, 4.9)
	_row("the player's car: width", minf(car.size.x, car.size.z), 1.7, 2.0)
	_row("the player's car: height", car.size.y, 1.4, 1.75)
	var life := {"sedan": [4.4, 4.9, 1.75, 1.9, 1.4, 1.5], "hatch": [3.8, 4.3, 1.65, 1.85, 1.4, 1.6],
		"suv": [4.3, 4.9, 1.8, 1.95, 1.6, 1.8], "van": [4.8, 5.5, 1.9, 2.1, 1.9, 2.6]}
	for kind: String in life:
		var ab: AABB = g._parked_mesh(kind).get_aabb()
		var L: Array = life[kind]
		_row("a parked %s: length" % kind, maxf(ab.size.x, ab.size.z), L[0], L[1])
		_row("a parked %s: width" % kind, minf(ab.size.x, ab.size.z), L[2], L[3])
		_row("a parked %s: height" % kind, ab.size.y, L[4], L[5])
	var bus: AABB = g._bus_mesh().get_aabb()
	_row("a bus: length", maxf(bus.size.x, bus.size.z), 11.5, 12.5)
	_row("a bus: width", minf(bus.size.x, bus.size.z), 2.45, 2.6)
	_row("a bus: height", bus.size.y, 3.0, 3.4)
	var sc: AABB = g._furn._scooter_kit().get_aabb()
	_row("a scooter: length", maxf(sc.size.x, sc.size.z), 1.7, 2.1)
	_row("a scooter: height", sc.size.y, 1.05, 1.35)
	if g._details != null:
		var mk: AABB = g._details._moto_kit().get_aabb()
		_row("a motorbike: length", maxf(mk.size.x, mk.size.z), 2.0, 2.25)
		_row("a motorbike: height", mk.size.y, 1.05, 1.25)
	print("---- people (the game's own: a test script cannot make an Actor3D, it uses autoloads)")
	var who: Array = [["you, on foot", g._me]]
	for k in range(mini(6, g._walkers.size())):
		who.append(["a walker %d" % k, g._walkers[k]["actor"]])
	for wv: Array in who:
		if wv[1] == null:
			print("%-44s (not out of the car in this place)" % wv[0])
			continue
		var a: Node3D = wv[1]
		var vis := a.visible
		a.visible = true
		await process_frame
		var ab := _box(a)
		a.visible = vis
		var asked: float = float(a.get("height")) if a.get("height") != null else 0.0
		_row("%s (asked %.2f m): height" % [wv[0], asked], ab.size.y, 1.55, 1.95)
		if asked > 0.0:
			print("%-44s %7.2f   (built over asked)" % ["", ab.size.y / asked])
	print("---- the street")
	var lanes: Dictionary = {}
	for r: Dictionary in g._roads:
		if not r["drive"]:
			continue
		var n := int(r["l"])
		if n <= 0:
			n = 1 if int(r["o"]) != 0 else 2
		var k := String(r["k"])
		if not lanes.has(k):
			lanes[k] = []
		(lanes[k] as Array).append(float(r["w"]) / n)
	for k: String in ["primary", "secondary", "tertiary", "residential", "living_street", "service"]:
		if not lanes.has(k):
			continue
		var v: Array = lanes[k]
		v.sort()
		_row("a %s lane: the middle one of %d ways" % [k, v.size()], v[v.size() / 2], 2.75 if k != "service" else 2.5, 3.6)
	var kc: Dictionary = (g.get_script() as GDScript).get_script_constant_map()
	_row("a pavement's width", float(kc["PAVE_W"]), 1.5, 3.5)
	_row("a kerb's height", float(kc["KERB_H"]), 0.12, 0.16)
	print("---- the eyes")
	_row("on foot, from the eyes: eye height", 1.64, 1.5, 1.7)
	_row("in the car, from the seat: eye height", float((kc["SEAT"] as Vector3).y), 1.1, 1.3)
	var aspect := 16.0 / 9.0
	for v: Array in [["on foot, behind", 66.0], ["on foot, from the eyes", 70.0], ["driving, slow", 64.0], ["driving, fast", 74.0]]:
		var vf: float = v[1]
		var hf := rad_to_deg(2.0 * atan(tan(deg_to_rad(vf) * 0.5) * aspect))
		_row("%s: field of view up and down" % v[0], vf, 40.0, 60.0, "deg")
		print("%-44s %7.1f deg across on a 16:9 screen (the eye's sharp field ~60, a phone's camera ~65-75)" % ["", hf])
	quit()
