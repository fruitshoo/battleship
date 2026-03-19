extends Node

## 메타 업그레이드 매니저 (Meta Manager)
## 영구 스탯 업그레이드 데이터 정의 및 구매 로직

signal meta_upgraded(id: String, new_level: int)

# 영구 업그레이드 정의
var UPGRADES = {
	"hull_hp": {
		"name": "최대 체력",
		"description": "선체 +40",
		"base_cost": 420,
		"cost_multiplier": 1.55,
		"max_level": 5
	},
	"hull_defense": {
		"name": "방어력",
		"description": "방어력 +2",
		"base_cost": 800,
		"cost_multiplier": 1.85,
		"max_level": 5
	},
	"sail_speed": {
		"name": "이동 속도",
		"description": "속도 +10%",
		"base_cost": 520,
		"cost_multiplier": 1.65,
		"max_level": 5
	},
	"xp_gain": {
		"name": "경험치 증가",
		"description": "경험치 +10%",
		"base_cost": 580,
		"cost_multiplier": 1.7,
		"max_level": 5
	},
	"pickup_range": {
		"name": "수집 반경",
		"description": "반경 +1.5m",
		"base_cost": 480,
		"cost_multiplier": 1.6,
		"max_level": 5
	},
	"reroll_stock": {
		"name": "재굴림",
		"description": "재굴림 +1",
		"base_cost": 900,
		"cost_multiplier": 2.1,
		"max_level": 3
	},
	"crew_capacity": {
		"name": "병사 수",
		"description": "병사 +1",
		"base_cost": 900,
		"cost_multiplier": 1.9,
		"max_level": 4
	},
	"crew_health": {
		"name": "병사 체력",
		"description": "체력 +12%",
		"base_cost": 700,
		"cost_multiplier": 1.75,
		"max_level": 5
	},
	"crew_attack": {
		"name": "병사 공격력",
		"description": "공격력 +2",
		"base_cost": 750,
		"cost_multiplier": 1.8,
		"max_level": 5
	},
	"crew_defense": {
		"name": "병사 방어력",
		"description": "방어력 +1",
		"base_cost": 800,
		"cost_multiplier": 1.85,
		"max_level": 5
	}
}

const UPGRADE_ORDER := [
	"hull_hp",
	"hull_defense",
	"sail_speed",
	"xp_gain",
	"pickup_range",
	"reroll_stock",
	"crew_capacity",
	"crew_health",
	"crew_attack",
	"crew_defense",
]

func get_upgrade_cost(id: String) -> int:
	var level = SaveManager.get_upgrade_level(id)
	var data = UPGRADES[id]
	return int(data["base_cost"] * pow(data["cost_multiplier"], level))

func buy_upgrade(id: String) -> bool:
	var data = UPGRADES.get(id)
	if not data: return false
	
	var level = SaveManager.get_upgrade_level(id)
	if level >= data["max_level"]:
		print("❌ 최대 레벨 도달")
		return false
		
	var cost = get_upgrade_cost(id)
	if SaveManager.spend_gold(cost):
		var new_level = level + 1
		SaveManager.set_upgrade_level(id, new_level)
		meta_upgraded.emit(id, new_level)
		print("✅ 구매 완료: %s (Lv.%d)" % [data["name"], new_level])
		return true
	
	print("❌ 골드 부족")
	return false

# --- 인게임 스탯 보너스 계산용 ---

func get_hull_hp_bonus() -> float:
	return SaveManager.get_upgrade_level("hull_hp") * 40.0

func get_hull_defense_bonus() -> float:
	return SaveManager.get_upgrade_level("hull_defense") * 2.0

func get_sail_speed_multiplier() -> float:
	return 1.0 + (SaveManager.get_upgrade_level("sail_speed") * 0.1)

func get_xp_gain_multiplier() -> float:
	return 1.0 + (SaveManager.get_upgrade_level("xp_gain") * 0.10)

func get_collection_radius_bonus() -> float:
	return SaveManager.get_upgrade_level("pickup_range") * 1.5

func get_reroll_bonus() -> int:
	return SaveManager.get_upgrade_level("reroll_stock")

func get_max_crew_bonus() -> int:
	return SaveManager.get_upgrade_level("crew_capacity")

func get_crew_health_multiplier() -> float:
	return 1.0 + (SaveManager.get_upgrade_level("crew_health") * 0.12)

func get_crew_damage_bonus() -> float:
	return SaveManager.get_upgrade_level("crew_attack") * 2.0

func get_crew_defense_bonus() -> float:
	return SaveManager.get_upgrade_level("crew_defense") * 1.0

func get_upgrade_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in UPGRADE_ORDER:
		if UPGRADES.has(id):
			ids.append(id)
	for id in UPGRADES.keys():
		if id not in ids:
			ids.append(id)
	return ids
