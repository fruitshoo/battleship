extends Node

## 세이브 매니저 (Save Manager)
## 골드 및 영구 업그레이드 데이터 저장/로드

const SAVE_PATH = "user://save_data.cfg"
const DEFAULT_SETTINGS := {
	"master_volume": 0.85,
	"music_volume": 0.75,
	"sfx_volume": 0.85,
	"ui_volume": 0.85,
	"fullscreen": false,
}

var gold: int = 0
var meta_upgrades: Dictionary = {}
var settings: Dictionary = {}

func _ready() -> void:
	load_game()
	apply_settings()

func save_game() -> void:
	var config = ConfigFile.new()
	config.set_value("player", "gold", gold)
	config.set_value("player", "meta_upgrades", meta_upgrades)
	config.set_value("player", "settings", settings)
	
	var err = config.save(SAVE_PATH)
	if err != OK:
		push_error("SaveManager: 저장 실패 (error code: %d)" % err)
	else:
		print("[Save] 게임 저장 완료 (Gold: %d)" % gold)

func load_game() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	
	if err == OK:
		gold = config.get_value("player", "gold", 0)
		meta_upgrades = config.get_value("player", "meta_upgrades", {})
		var loaded_settings = config.get_value("player", "settings", {})
		settings = DEFAULT_SETTINGS.duplicate(true)
		if loaded_settings is Dictionary:
			for key in loaded_settings.keys():
				settings[key] = loaded_settings[key]
		print("[Load] 게임 로드 완료 (Gold: %d)" % gold)
	else:
		print("[Load] 저장된 파일이 없습니다. 초기 상태로 시작합니다.")
		gold = 0
		meta_upgrades = {}
		settings = DEFAULT_SETTINGS.duplicate(true)
		save_game()

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

func apply_settings() -> void:
	if settings.is_empty():
		settings = DEFAULT_SETTINGS.duplicate(true)
	_set_bus_volume_linear("Master", float(get_setting("master_volume", 0.85)))
	_set_bus_volume_linear("Music", float(get_setting("music_volume", 0.75)))
	_set_bus_volume_linear("SFX", float(get_setting("sfx_volume", 0.85)))
	_set_bus_volume_linear("UI", float(get_setting("ui_volume", 0.85)))
	var fullscreen := bool(get_setting("fullscreen", false))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _set_bus_volume_linear(bus_name: String, linear: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return
	var clamped := clampf(linear, 0.0, 1.0)
	var volume_db := linear_to_db(clamped)
	if clamped <= 0.001:
		volume_db = -80.0
	AudioServer.set_bus_volume_db(bus_idx, volume_db)
