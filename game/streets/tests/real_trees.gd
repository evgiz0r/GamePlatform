extends SceneTree
## The towns' own maps of their trees (the city file's tree_info and tree_surveys, from
## tools/osm_city.py's TREE_SURVEYS): how many trees came from them, how many street-row trees
## were still made up (none where a map covers), the grates and earth squares under them,
## the credit line; then views by day of the streets with the most trees of a kind.
##
##   OUT=/tmp/rt game/streets/tests/run.sh real_trees 7     Tel Aviv: its street trees by species
##   OUT=/tmp/rt game/streets/tests/run.sh real_trees 1     Givatayim: its crowns mapped from the air
##   STREETS_CITY_FILE=/some/old/tel_aviv.json ...          the same views on another copy of the
##                                                          file (before the trees were taken)
##   LEVEL=7 $GODOT --headless --path . -s res://game/streets/tests/real_trees.gd   the numbers only
##
## Good (21 Nov 2026): see README.md here.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## the eye at (x, z), `up` over the surface, facing `at`, tilted `tilt` degrees
func _view(name: String, p: Vector2, at: Vector2, up: float, tilt: float) -> void:
	g._dev_cam[2] = up
	g._dev_cam[4] = tilt
	var yaw := (at - p).angle()
	for i in 10:
		g._pos = p
		g._prev_pos = p
		g._yaw = yaw
		g._prev_yaw = yaw
		g._v = 0.0
		await process_frame
	await _snap(name)

func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.6,0,0")
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var d: Dictionary = g._dressing
	print("real_trees: ", {"trees": g._trees_made, "mapped": d.get("trees_mapped", 0),
		"made_up_rows": d.get("trees_made_up_rows", 0), "grates": d.get("tree_grates", 0),
		"pits": d.get("tree_pits", 0), "wild": d.get("wild_trees", 0), "cover_cells": g._tree_cover.size()})
	print("credit: ", g._osm_lbl.text)
	if DisplayServer.get_name() == "headless":
		quit()
		return
	g._car.visible = false
	if g._city_id == "tel_aviv":
		# the promenade's Washingtonia palms; Dizengoff's ficus; a street of feathery crowns
		await _view("palms_herbert_samuel", Vector2(-2268, -362), Vector2(-2308, -270), 1.7, 3.0)
		await _view("palms_herbert_samuel_above", Vector2(-2240, -420), Vector2(-2308, -270), 22.0, -18.0)
		await _view("ficus_dizengoff", Vector2(-1559, -1069), Vector2(-1565, -1000), 1.7, 3.0)
		await _view("feathery_rivka_ziv", Vector2(-380, -551), Vector2(-380, -480), 1.7, 3.0)
		await _view("rothschild_above", Vector2(-1130, 420), Vector2(-1220, 760), 40.0, -25.0)
	elif g._city_id == "givatayim":
		# Eilat street's yards, the most crowns along a street; the west side's Tel Aviv street trees
		await _view("crowns_eilat", Vector2(-286, 160), Vector2(-290, 230), 1.7, 3.0)
		await _view("crowns_eilat_above", Vector2(-250, 100), Vector2(-290, 230), 35.0, -28.0)
		await _view("moshe_dayan", Vector2(-983, 471), Vector2(-990, 560), 1.7, 3.0)
	quit()
