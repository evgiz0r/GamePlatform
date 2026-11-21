extends SceneTree
## The build stamp's clock (streets.gd israel_time) against the time-zone database: the user
## reads build times in Israel time. Prints each UTC time and what the game makes of it;
## tests/israel_time.py runs this and compares with Python's zoneinfo (Asia/Jerusalem),
## across each summer-time change from 2025 to 2030. Expect "all match".
func _initialize() -> void:
	var S = load("res://game/streets/streets.gd")
	for line: String in OS.get_environment("TIMES").split(";", false):
		var p := line.split(" ")
		print("IL %s %s -> %s" % [p[0], p[1], S.israel_time(p[0], p[1])])
	quit(0)
