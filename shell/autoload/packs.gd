extends Node
# The web build's extra packs (tools/split_pck.py): the main index.pck lists them in
# res://packs.txt and index.html has already put each one in the page's file system before
# the engine started. They are loaded here, in _init, as the FIRST autoload, so every other
# autoload and scene finds its textures, sounds and data as if they were in the main pack.
# A native run or the editor has no packs.txt, and this does nothing.

func _init() -> void:
	if not FileAccess.file_exists("res://packs.txt"):
		return
	for name in FileAccess.get_file_as_string("res://packs.txt").split("\n", false):
		if not ProjectSettings.load_resource_pack(name.strip_edges()):
			push_error("pack not loaded: " + name)
