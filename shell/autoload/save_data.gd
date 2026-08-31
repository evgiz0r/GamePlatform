extends Node
## Settings + high scores, persisted to user://save.json. Games never touch the file;
## they call SaveData.submit_score() and read SaveData.best_for().

const PATH := "user://save.json"

var data := {
	"volume_music": 0.7,
	"volume_sfx": 0.8,
	"palette": "neon_candy",
	"fullscreen": false,
	"scores": {},
}

func _ready() -> void:
	load_file()
	Palette.use(data.get("palette", "neon_candy"))

func load_file() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in parsed:
			data[k] = parsed[k]

func save_file() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))

func set_value(key: String, value) -> void:
	data[key] = value
	save_file()

## Returns true if this beat the previous best.
func submit_score(game_id: String, score: int) -> bool:
	var best := int(data["scores"].get(game_id, 0))
	if score > best:
		data["scores"][game_id] = score
		save_file()
		return true
	return false

func best_for(game_id: String) -> int:
	return int(data["scores"].get(game_id, 0))
