extends Node

## 세이브 매니저 (Save Manager)
## 포인트 및 영구 업그레이드 데이터 저장/로드

const InputSettingsHelper = preload("res://scripts/helpers/input_settings_helper.gd")
const SAVE_PATH = "user://save_data.cfg"
const BACKUP_SAVE_PATH = "user://save_data.backup.cfg"
const WINDOW_MODE_NO_CHANGE := -1
const DEFAULT_SETTINGS := {
	"master_volume": 0.5,
	"music_volume": 0.5,
	"sfx_volume": 0.5,
	"ui_volume": 0.5,
	"performance_preset": "quality",
	"fullscreen": false,
	"screen_edge_fx_enabled": true,
	"screen_edge_fx_strength": 0.75,
	"sail_control_mode": "manual",
	"control_scheme": "screen",
	"gamepad_confirm_button": "auto",
	"gamepad_confirm_button_user_set": false,
	"locale": "ko",
}

var gold: int = 0
var meta_upgrades: Dictionary = {}
var items: Array[String] = []
var settings: Dictionary = {}
var performance_vfx_scale: float = 1.0
var performance_cpu_interval_scale: float = 1.0

func _ready() -> void:
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	load_game()
	apply_settings()

func save_game() -> void:
	if _env_flag_enabled("BATTLESHIP_DISABLE_AUTOSAVE"):
		return
	var config = ConfigFile.new()
	config.set_value("player", "gold", gold)
	config.set_value("player", "meta_upgrades", meta_upgrades)
	config.set_value("player", "items", items)
	config.set_value("player", "settings", settings)
	
	var err = config.save(SAVE_PATH)
	if err != OK:
		push_error("SaveManager: 저장 실패 (error code: %d)" % err)
	else:
		var backup_err = config.save(BACKUP_SAVE_PATH)
		if backup_err != OK:
			push_warning("SaveManager: 백업 저장 실패 (error code: %d)" % backup_err)
		print("[Save] 게임 저장 완료 (Points: %d)" % gold)

func load_game() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	
	if err == OK:
		_apply_loaded_config(config)
		print("[Load] 게임 로드 완료 (Points: %d)" % gold)
	elif err == ERR_FILE_NOT_FOUND:
		print("[Load] 저장된 파일이 없습니다. 초기 상태로 시작합니다.")
		_reset_to_defaults()
		save_game()
	else:
		push_warning("SaveManager: 메인 세이브 로드 실패 (error code: %d), 백업을 확인합니다." % err)
		var backup_config = ConfigFile.new()
		var backup_err = backup_config.load(BACKUP_SAVE_PATH)
		if backup_err == OK:
			_apply_loaded_config(backup_config)
			print("[Load] 백업 세이브 로드 완료 (Points: %d)" % gold)
		else:
			push_warning("SaveManager: 백업 세이브도 로드 실패 (error code: %d). 기본값으로 시작하되 파일은 덮어쓰지 않습니다." % backup_err)
			_reset_to_defaults()

func add_gold(amount: int) -> void:
	gold += amount
	save_game()

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		save_game()
		return true
	return false

func get_upgrade_level(id: String) -> int:
	return meta_upgrades.get(id, 0)

func set_upgrade_level(id: String, level: int) -> void:
	meta_upgrades[id] = level
	save_game()

func has_item(item_id: String) -> bool:
	return items.has(item_id)

func add_item(item_id: String) -> void:
	if items.has(item_id):
		return
	items.append(item_id)
	save_game()

func get_items() -> Array[String]:
	return items.duplicate()

func get_setting(id: String, fallback = null):
	if settings.is_empty():
		settings = DEFAULT_SETTINGS.duplicate(true)
	if settings.has(id):
		return settings[id]
	if fallback != null:
		return fallback
	return DEFAULT_SETTINGS.get(id)

func set_setting(id: String, value, save_now: bool = true) -> void:
	if settings.is_empty():
		settings = DEFAULT_SETTINGS.duplicate(true)
	settings[id] = value
	if save_now:
		save_game()

func _reset_to_defaults() -> void:
	gold = 0
	meta_upgrades = {}
	items = []
	settings = DEFAULT_SETTINGS.duplicate(true)

func _apply_loaded_config(config: ConfigFile) -> void:
	gold = int(config.get_value("player", "gold", 0))
	meta_upgrades = config.get_value("player", "meta_upgrades", {})
	var loaded_items = config.get_value("player", "items", [])
	items = []
	if loaded_items is Array:
		for item_id in loaded_items:
			items.append(str(item_id))
	var loaded_settings = config.get_value("player", "settings", {})
	settings = DEFAULT_SETTINGS.duplicate(true)
	if loaded_settings is Dictionary:
		for key in loaded_settings.keys():
			settings[key] = loaded_settings[key]
		_migrate_loaded_settings(loaded_settings)

func _migrate_loaded_settings(loaded_settings: Dictionary) -> void:
	if loaded_settings.has("gamepad_confirm_button_user_set"):
		return
	var legacy_confirm := str(loaded_settings.get("gamepad_confirm_button", ""))
	if legacy_confirm == InputSettingsHelper.CONFIRM_POSITION_BOTTOM:
		settings["gamepad_confirm_button"] = InputSettingsHelper.CONFIRM_POSITION_AUTO
		settings["gamepad_confirm_button_user_set"] = false
	elif legacy_confirm == InputSettingsHelper.CONFIRM_POSITION_RIGHT:
		settings["gamepad_confirm_button_user_set"] = true

func apply_settings() -> void:
	if settings.is_empty():
		settings = DEFAULT_SETTINGS.duplicate(true)
	_set_bus_volume_linear("Master", float(get_setting("master_volume", DEFAULT_SETTINGS["master_volume"])))
	_set_bus_volume_linear("Music", float(get_setting("music_volume", DEFAULT_SETTINGS["music_volume"])))
	_set_bus_volume_linear("SFX", float(get_setting("sfx_volume", DEFAULT_SETTINGS["sfx_volume"])))
	_set_bus_volume_linear("UI", float(get_setting("ui_volume", DEFAULT_SETTINGS["ui_volume"])))
	_apply_fullscreen_setting()
	_apply_performance_preset()
	_apply_gamepad_confirm_button_layout()

func _apply_fullscreen_setting() -> void:
	var fullscreen: bool = get_setting("fullscreen", false) == true
	var current_mode := DisplayServer.window_get_mode()
	var requested_mode := _get_fullscreen_window_mode_update(current_mode, fullscreen)
	if requested_mode != WINDOW_MODE_NO_CHANGE:
		DisplayServer.window_set_mode(requested_mode)

func _get_fullscreen_window_mode_update(current_mode: int, fullscreen: bool) -> int:
	if fullscreen:
		if current_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		return WINDOW_MODE_NO_CHANGE
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return DisplayServer.WINDOW_MODE_WINDOWED
	return WINDOW_MODE_NO_CHANGE

func _set_bus_volume_linear(bus_name: String, linear: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return
	var clamped: float = clampf(linear, 0.0, 1.0)
	var volume_db: float = linear_to_db(clamped)
	if clamped <= 0.001:
		volume_db = -80.0
	AudioServer.set_bus_volume_db(bus_idx, volume_db)

func _apply_gamepad_confirm_button_layout() -> void:
	InputSettingsHelper.apply_gamepad_confirm_button_layout(str(get_setting("gamepad_confirm_button", DEFAULT_SETTINGS["gamepad_confirm_button"])))

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	if str(get_setting("gamepad_confirm_button", DEFAULT_SETTINGS["gamepad_confirm_button"])) == InputSettingsHelper.CONFIRM_POSITION_AUTO:
		_apply_gamepad_confirm_button_layout()

func _apply_performance_preset() -> void:
	var preset := str(get_setting("performance_preset", "quality"))
	var render_scale := 1.0
	performance_vfx_scale = 1.0
	performance_cpu_interval_scale = 1.0
	match preset:
		"balanced":
			render_scale = 0.88
			performance_vfx_scale = 0.84
			performance_cpu_interval_scale = 1.06
		"performance":
			render_scale = 0.74
			performance_vfx_scale = 0.64
			performance_cpu_interval_scale = 1.14
		_:
			render_scale = 1.0
			performance_vfx_scale = 1.0
			performance_cpu_interval_scale = 1.0
	var viewport := get_tree().root if get_tree() != null else null
	if viewport == null:
		return
	_set_viewport_property_if_present(viewport, "scaling_3d_scale", render_scale)
	_set_viewport_property_if_present(viewport, "scaling_3d_mode", 1 if render_scale < 0.999 else 0)


func _set_viewport_property_if_present(viewport: Viewport, property_name: String, value) -> void:
	for property in viewport.get_property_list():
		if str(property.get("name", "")) == property_name:
			viewport.set(property_name, value)
			return


func get_performance_cpu_interval_scale() -> float:
	return clampf(performance_cpu_interval_scale, 1.0, 1.25)

func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
