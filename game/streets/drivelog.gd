extends RefCounted
## The drive recorder: the last two minutes of the car and the cars round it, ten times a
## second -- to see afterwards why autodrive (or traffic) drove the way it did. Shown as a
## map in the perf view's second page (P, or a tap on the fps text, twice), and saved as a
## JSON file from there ("save log"): downloaded in a browser, user://drive_logs/ elsewhere.
## tests/drive_log_map.py draws a saved one over the city's streets.
##
## A sample: t, x, z, yaw, v, steer, gear, auto, why (what held autodrive's speed down: limit,
## curve, light, sign, zebra, people, car, blocked, choice, backing, turning), plan (the
## next points of autodrive's lane, every 5 m for 40 m), lead (metres to the car ahead on
## it, or -1), cars: [[id, kind, x, z, yaw, v, blocker], ...] within 50 m (at most 10).
## Events: [t, what, detail] -- hits, rescues, junction choices, quality steps.

const HZ := 10.0
const KEEP_S := 120.0
const NEAR := 50.0

var samples: Array = []              ## oldest first, KEEP_S of them at most
var events: Array = []
var _acc := 0.0
var _t := 0.0
var _last_hit := ""

func tick(g, dt: float) -> void:
	_t += dt
	_acc += dt
	if _acc < 1.0 / HZ:
		return
	_acc = 0.0
	var plan: Array = []
	if g._auto and g._ap_pts.size() > 1:
		var s := 0.0
		var p: Vector2 = g._ap_pts[0]
		plan.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
		for k in range(1, g._ap_pts.size()):
			s += (g._ap_pts[k - 1] as Vector2).distance_to(g._ap_pts[k])
			if s > 40.0:
				break
			if s >= 5.0 * plan.size():
				var q: Vector2 = g._ap_pts[k]
				plan.append([snappedf(q.x, 0.1), snappedf(q.y, 0.1)])
	var cars: Array = []
	if g._traffic != null:
		for i in range(g._traffic.cars.size()):
			var c = g._traffic.cars[i]
			if c.alive and c.pos.distance_to(g._pos) < NEAR and cars.size() < 10:
				cars.append([i, c.kind, snappedf(c.pos.x, 0.1), snappedf(c.pos.y, 0.1), snappedf(c.yaw, 0.01),
					snappedf(c.v, 0.1), c.blocker])
	samples.append({"t": snappedf(_t, 0.01), "x": snappedf(g._pos.x, 0.01), "z": snappedf(g._pos.y, 0.01),
		"yaw": snappedf(g._yaw, 0.001), "v": snappedf(g._v, 0.01), "steer": snappedf(g._steer, 0.001),
		"gear": g._gear, "auto": g._auto, "walk": g._walking, "why": g._ap_why if g._auto else "",
		"plan": plan, "lead": snappedf(g._ap_lead, 0.1), "cars": cars})
	while samples.size() > int(KEEP_S * HZ):
		samples.pop_front()
	while not events.is_empty() and float(events[0][0]) < _t - KEEP_S:
		events.pop_front()
	if g._last_hit != _last_hit:
		_last_hit = g._last_hit
		if _last_hit != "" and g._crash_cool > 0.0:
			event("hit", _last_hit)

func event(what: String, detail = "") -> void:
	events.append([snappedf(_t, 0.01), what, detail])

func to_json(g) -> String:
	return JSON.stringify({"city": g._city_id, "name": g._city_name, "made": Time.get_datetime_string_from_system(),
		"hz": HZ, "quality": g._quality, "samples": samples, "events": events})

## the file: downloaded in a browser, written under user:// otherwise; the name it got
func save(g) -> String:
	var name := "drive-%s-%s.json" % [g._city_id, Time.get_datetime_string_from_system().replace(":", "-")]
	var text := to_json(g)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), name, "application/json")
		return name
	DirAccess.make_dir_recursive_absolute("user://drive_logs")
	var f := FileAccess.open("user://drive_logs/" + name, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text)
	f.close()
	return ProjectSettings.globalize_path("user://drive_logs/" + name)
