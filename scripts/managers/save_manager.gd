extends Node

## 세이브 매니저 (Save Manager)
## 골드 및 영구 업그레이드 데이터 저장/로드

const SAVE_PATH = "user://save_data.cfg"

var gold: int = 0
var meta_upgrades: Dictionary = {}

func _ready() -> void:
	load_game()

func save_game() -> void:
	var config = ConfigFile.new()
	config.set_value("player", "gold", gold)
	config.set_value("player", "meta_upgrades", meta_upgrades)
	
	var err = config.save(SAVE_PATH)
	if err != OK:
		push_error("SaveManager: 저장 실패 (error code: %d)" % err)
	else:
		print("💾 게임 저장 완료 (Gold: %d)" % gold)

func load_game() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	
	if err == OK:
		gold = config.get_value("player", "gold", 0)
		meta_upgrades = config.get_value("player", "meta_upgrades", {})
		print("📂 게임 로드 완료 (Gold: %d)" % gold)
	else:
		print("📂 저장된 파일이 없습니다. 초기 상태로 시작합니다.")
		gold = 0
		meta_upgrades = {}

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
