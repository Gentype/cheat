extends Node
## SaveSystem — настройки и состояние смены.
##
## Настройки лежат в user://mydriasis_settings.cfg и применяются сразу.
## Прогресс смены — в user://mydriasis_run.json: можно закрыть игру в середине
## бита и вернуться к той же точке.

signal setting_changed(key: String, value: Variant)
signal run_saved()
signal run_loaded(data: Dictionary)

const SETTINGS_PATH := "user://mydriasis_settings.cfg"
const RUN_PATH := "user://mydriasis_run.json"
const RUN_VERSION := 1

const DEFAULTS := {
	"video/tier": 3,
	"video/auto_guard": true,
	"video/target_fps": 60,
	"video/fov_multiplier": 1.0,
	"audio/master": 0.85,
	"audio/bed": 0.7,
	"audio/body": 0.9,
	"audio/sfx": 0.8,
	"audio/voices": 0.9,
	"audio/mono": false,
	"input/sensitivity": 0.0022,
	"input/invert_y": false,
	"input/hold_to_breath": true,
	"game/difficulty": 1,
	"game/language": "ru",
	"ui/hud_scale": 1.0,
	"ui/subtitles": true,
	"comfort/reduce_grain": false,
	"comfort/reduce_shake": false,
	"comfort/no_flash": false,
	"comfort/no_pupil_distortion": false,
}

var _settings: Dictionary = {}
var _config := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()


func load_settings() -> void:
	_settings = DEFAULTS.duplicate(true)
	if _config.load(SETTINGS_PATH) == OK:
		for key in DEFAULTS.keys():
			if _config.has_section_key(_section_of(key), _key_of(key)):
				_settings[key] = _config.get_value(_section_of(key), _key_of(key))
	# Автолоады инициализируются раньше сцен — применяем сразу.
	_apply_video()
	_apply_audio()
	_apply_comfort()


func save_settings() -> void:
	for key in _settings.keys():
		_config.set_value(_section_of(key), _key_of(key), _settings[key])
	_config.save(SETTINGS_PATH)


func get_setting(key: String, fallback: Variant = null) -> Variant:
	return _settings.get(key, DEFAULTS.get(key, fallback))


func set_setting(key: String, value: Variant, persist := true) -> void:
	var previous: Variant = _settings.get(key)
	if previous == value:
		return
	_settings[key] = value
	match key.split("/")[0]:
		"video":
			_apply_video()
		"audio":
			_apply_audio()
		"comfort":
			_apply_comfort()
	setting_changed.emit(key, value)
	if persist:
		save_settings()


func _section_of(key: String) -> String:
	var parts := key.split("/")
	return parts[0] if parts.size() > 0 else "misc"


func _key_of(key: String) -> String:
	var parts := key.split("/")
	return parts[1] if parts.size() > 1 else key


func _apply_video() -> void:
	Quality.auto_guard = bool(get_setting("video/auto_guard", true))
	Quality.target_fps = int(get_setting("video/target_fps", 60))
	var tier := int(get_setting("video/tier", int(Quality.Tier.ULTRA)))
	if Quality.is_node_ready():
		Quality.set_tier(tier as Quality.Tier, false)


func _apply_audio() -> void:
	AudioDirector.set_bus_volume("Master", float(get_setting("audio/master", 0.85)))
	AudioDirector.set_bus_volume("Bed", float(get_setting("audio/bed", 0.7)))
	AudioDirector.set_bus_volume("Body", float(get_setting("audio/body", 0.9)))
	AudioDirector.set_bus_volume("SFX", float(get_setting("audio/sfx", 0.8)))
	AudioDirector.set_bus_volume("Voices", float(get_setting("audio/voices", 0.9)))
	AudioDirector.set_mono(bool(get_setting("audio/mono", false)))


func _apply_comfort() -> void:
	for key in ["reduce_grain", "reduce_shake", "no_flash", "no_pupil_distortion"]:
		Quality.comfort[key] = bool(get_setting("comfort/" + key, false))


# --- Состояние смены ----------------------------------------------------------

func save_run() -> void:
	var data := {
		"version": RUN_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"level": String(GameState.current_level),
		"run_time": GameState.run_time,
		"difficulty": GameState.difficulty,
		"flags": {},
		"vitals": GameState.vitals(),
	}
	for key in GameState.run_flags.keys():
		data["flags"][String(key)] = GameState.run_flags[key]
	var file := FileAccess.open(RUN_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem: не удалось записать прогресс смены")
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	run_saved.emit()


func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)


func load_run() -> Dictionary:
	if not has_run():
		return {}
	var file := FileAccess.open(RUN_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != RUN_VERSION:
		return {}
	GameState.current_level = StringName(data.get("level", ""))
	GameState.run_time = float(data.get("run_time", 0.0))
	GameState.difficulty = int(data.get("difficulty", 1))
	GameState.run_flags.clear()
	for key in Dictionary(data.get("flags", {})).keys():
		GameState.run_flags[StringName(key)] = Dictionary(data.get("flags", {}))[key]
	var vitals: Dictionary = data.get("vitals", {})
	GameState.heart_rate = float(vitals.get("heart_rate", GameState.BASE_HEART))
	GameState.spo2 = float(vitals.get("spo2", 98.0))
	GameState.systolic = float(vitals.get("systolic", 118.0))
	GameState.diastolic = float(vitals.get("diastolic", 76.0))
	GameState.consciousness = float(vitals.get("consciousness", 1.0))
	GameState.dread = float(vitals.get("dread", 0.0))
	run_loaded.emit(data)
	return data


func clear_run() -> void:
	if has_run():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))


func reset_everything() -> void:
	_settings = DEFAULTS.duplicate(true)
	save_settings()
	load_settings()
	Quality.apply()
	AudioDirector.rebuild()
